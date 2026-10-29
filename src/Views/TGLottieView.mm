//
// TGLottieView.mm - High-performance C++ vector animation & WebM VP9 renderer for Telegram stickers.
//
#import "TGLottieView.h"
#import "TGStyle.h"
#import "TGJson.h"
#import "TGWebMDecoder.h"
#include <zlib.h>
#include <vector>
#include <cmath>

#ifndef typeof
#define typeof __typeof__
#endif

#pragma mark - gunzip

/// .tgs is gzip, and NSData has no unzip on iOS 7, so inflate with zlib.
static NSData *TGGunzip(NSData *input) {
	if (!input.length)
		return nil;

	z_stream stream;
	memset(&stream, 0, sizeof(stream));
	stream.next_in = (Bytef *)input.bytes;
	stream.avail_in = (uInt)input.length;

	if (inflateInit2(&stream, 15 + 32) != Z_OK)
		return nil;

	NSMutableData *out = [NSMutableData dataWithLength:input.length * 8];
	int status;
	do {
		if (stream.total_out >= out.length)
			[out increaseLengthBy:input.length * 4];
		stream.next_out = (Bytef *)out.mutableBytes + stream.total_out;
		stream.avail_out = (uInt)(out.length - stream.total_out);
		status = inflate(&stream, Z_SYNC_FLUSH);
	} while (status == Z_OK);

	inflateEnd(&stream);
	if (status != Z_STREAM_END)
		return nil;

	[out setLength:stream.total_out];
	return out;
}

#pragma mark - fast keyframed evaluation (zero-allocation C++ float math)

static inline int TGValueAtFast(NSDictionary *prop, double frame, float *outVals, int maxVals) {
	if (!prop || !maxVals)
		return 0;
	id k = prop[@"k"];
	if (!k)
		return 0;

	// 1. Static single number
	if ([k isKindOfClass:NSNumber.class]){
		outVals[0] = (float)[(NSNumber *)k doubleValue];
		return 1;
	}

	// 2. Static array of numbers or keyframed array of dicts
	if ([k isKindOfClass:NSArray.class]){
		NSArray *arr = (NSArray *)k;
		if (!arr.count)
			return 0;

		id first = arr[0];
		if (![first isKindOfClass:NSDictionary.class]){
			int n = (int)MIN((NSUInteger)maxVals, arr.count);
			for (int i = 0; i < n; i++)
				outVals[i] = (float)[arr[i] doubleValue];
			return n;
		}

		// Keyframed interpolation
		NSDictionary *before = nil, *after = nil;
		for (NSDictionary *kf in arr){
			double t = [kf[@"t"] doubleValue];
			if (t <= frame)
				before = kf;
			else {
				after = kf;
				break;
			}
		}

		if (!before){
			id s = [first objectForKey:@"s"];
			if ([s isKindOfClass:NSArray.class]){
				int n = (int)MIN((NSUInteger)maxVals, [(NSArray *)s count]);
				for (int i = 0; i < n; i++)
					outVals[i] = (float)[s[i] doubleValue];
				return n;
			} else if ([s isKindOfClass:NSNumber.class]){
				outVals[0] = (float)[s doubleValue];
				return 1;
			}
			return 0;
		}

		id fromObj = before[@"s"];
		id toObj   = before[@"e"] ?: after[@"s"];
		if (!fromObj) fromObj = toObj;
		if (!toObj)   toObj   = fromObj;

		float fromVals[8] = {0};
		float toVals[8]   = {0};
		int fromCount = 0, toCount = 0;

		if ([fromObj isKindOfClass:NSArray.class]){
			fromCount = (int)MIN((NSUInteger)8, [(NSArray *)fromObj count]);
			for (int i = 0; i < fromCount; i++)
				fromVals[i] = (float)[fromObj[i] doubleValue];
		} else if ([fromObj isKindOfClass:NSNumber.class]){
			fromVals[0] = (float)[fromObj doubleValue];
			fromCount = 1;
		}

		if ([toObj isKindOfClass:NSArray.class]){
			toCount = (int)MIN((NSUInteger)8, [(NSArray *)toObj count]);
			for (int i = 0; i < toCount; i++)
				toVals[i] = (float)[toObj[i] doubleValue];
		} else if ([toObj isKindOfClass:NSNumber.class]){
			toVals[0] = (float)[toObj doubleValue];
			toCount = 1;
		}

		int count = MAX(fromCount, toCount);
		if (!count)
			return 0;
		count = MIN(count, maxVals);

		double t0 = [before[@"t"] doubleValue];
		double t1 = [after[@"t"] doubleValue];
		double p = (t1 > t0) ? (frame - t0) / (t1 - t0) : 0.0;
		if (p < 0.0) p = 0.0;
		if (p > 1.0) p = 1.0;
		float pf = (float)p;

		for (int i = 0; i < count; i++){
			float a = (i < fromCount) ? fromVals[i] : (i < toCount ? toVals[i] : 0.0f);
			float b = (i < toCount) ? toVals[i] : a;
			outVals[i] = a + (b - a) * pf;
		}
		return count;
	}
	return 0;
}

static inline float TGScalarAtFast(NSDictionary *prop, double frame, float fallback) {
	float val = 0;
	if (TGValueAtFast(prop, frame, &val, 1) > 0)
		return val;
	return fallback;
}

#pragma mark - model & cache

@interface TGLottieModel : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSDictionary *anim;
@property (nonatomic, strong) NSArray *layers;
@property (nonatomic, strong) NSDictionary *layersByInd;
@property (nonatomic, assign) double inPoint;
@property (nonatomic, assign) double outPoint;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) CGSize canvas;

// Cached decoded/rasterized frames (NSArray of CGImageRef wrapped in id)
@property (nonatomic, strong) NSArray *cachedFrames;
@property (nonatomic, assign) BOOL isRasterizing;
@property (nonatomic, assign) BOOL isWebM;
@end

@implementation TGLottieModel
@end

#pragma mark - C++ Vector Render Helpers (usable in background threads)

static void TGApplyTransform(NSDictionary *ks, double frame, CGContextRef ctx) {
	if (!ks)
		return;

	float pos[2]    = {0};
	float anchor[2] = {0};
	float scale[2]  = {100.0f, 100.0f};

	int posCount = 0;
	if (ks[@"p"][@"x"] && ks[@"p"][@"y"]) {
		pos[0] = TGScalarAtFast(ks[@"p"][@"x"], frame, 0.0f);
		pos[1] = TGScalarAtFast(ks[@"p"][@"y"], frame, 0.0f);
		posCount = 2;
	} else {
		posCount = TGValueAtFast(ks[@"p"], frame, pos, 2);
	}
	int anchorCount = TGValueAtFast(ks[@"a"], frame, anchor, 2);
	int scaleCount  = TGValueAtFast(ks[@"s"], frame, scale, 2);
	float rotation  = TGScalarAtFast(ks[@"r"], frame, 0.0f);
	float opacity   = TGScalarAtFast(ks[@"o"], frame, 100.0f);

	if (posCount >= 2)
		CGContextTranslateCTM(ctx, pos[0], pos[1]);
	if (rotation != 0.0f)
		CGContextRotateCTM(ctx, rotation * (float)M_PI / 180.0f);
	if (scaleCount >= 2)
		CGContextScaleCTM(ctx, scale[0] / 100.0f, scale[1] / 100.0f);
	if (anchorCount >= 2)
		CGContextTranslateCTM(ctx, -anchor[0], -anchor[1]);

	if (opacity < 100.0f)
		CGContextSetAlpha(ctx, opacity / 100.0f);
}

static void TGAppendBezier(NSDictionary *ks, double frame, CGMutablePathRef path) {
	NSArray *value = nil;
	id k = ks[@"k"];

	if ([k isKindOfClass:NSDictionary.class]){
		value = @[k];
	} else if ([k isKindOfClass:NSArray.class] &&
			   [[k firstObject] isKindOfClass:NSDictionary.class] &&
			   [[k firstObject] objectForKey:@"t"]){
		NSDictionary *chosen = [k firstObject];
		for (NSDictionary *kf in k)
			if ([kf[@"t"] doubleValue] <= frame)
				chosen = kf;
		id s = chosen[@"s"];
		value = [s isKindOfClass:NSArray.class] ? s : (s ? @[s] : nil);
	} else if ([k isKindOfClass:NSArray.class]){
		value = k;
	}

	for (NSDictionary *shape in value){
		if (![shape isKindOfClass:NSDictionary.class])
			continue;

		NSArray *v   = shape[@"v"];
		NSArray *in  = shape[@"i"];
		NSArray *out = shape[@"o"];
		size_t count = v.count;
		if (count < 2)
			continue;

		std::vector<CGPoint> vPts(count), inPts(count), outPts(count);
		for (size_t i = 0; i < count; i++){
			NSArray *vp = v[i];
			if ([vp isKindOfClass:NSArray.class] && vp.count >= 2){
				vPts[i] = CGPointMake([vp[0] doubleValue], [vp[1] doubleValue]);
			}
			if (i < in.count){
				NSArray *inp = in[i];
				if ([inp isKindOfClass:NSArray.class] && inp.count >= 2)
					inPts[i] = CGPointMake([inp[0] doubleValue], [inp[1] doubleValue]);
			}
			if (i < out.count){
				NSArray *outp = out[i];
				if ([outp isKindOfClass:NSArray.class] && outp.count >= 2)
					outPts[i] = CGPointMake([outp[0] doubleValue], [outp[1] doubleValue]);
			}
		}

		CGPathMoveToPoint(path, NULL, vPts[0].x, vPts[0].y);
		for (size_t i = 1; i < count; i++){
			size_t p = i - 1;
			CGPathAddCurveToPoint(path, NULL,
				vPts[p].x + outPts[p].x, vPts[p].y + outPts[p].y,
				vPts[i].x + inPts[i].x,  vPts[i].y + inPts[i].y,
				vPts[i].x, vPts[i].y);
		}

		if ([shape[@"c"] boolValue]){
			size_t last = count - 1;
			CGPathAddCurveToPoint(path, NULL,
				vPts[last].x + outPts[last].x, vPts[last].y + outPts[last].y,
				vPts[0].x + inPts[0].x,        vPts[0].y + inPts[0].y,
				vPts[0].x, vPts[0].y);
			CGPathCloseSubpath(path);
		}
	}
}

static void TGFillPath(CGPathRef path, NSDictionary *shape, double frame, CGContextRef ctx) {
	float c[4] = {0};
	int cC = TGValueAtFast(shape[@"c"], frame, c, 4);
	if (cC < 3 || CGPathIsEmpty(path))
		return;

	float alpha = TGScalarAtFast(shape[@"o"], frame, 100.0f) / 100.0f;
	CGContextSetRGBFillColor(ctx, c[0], c[1], c[2], alpha);
	CGContextAddPath(ctx, path);
	CGContextEOFillPath(ctx);
}

static void TGStrokePath(CGPathRef path, NSDictionary *shape, double frame, CGContextRef ctx) {
	float c[4] = {0};
	int cC = TGValueAtFast(shape[@"c"], frame, c, 4);
	if (cC < 3 || CGPathIsEmpty(path))
		return;

	float alpha = TGScalarAtFast(shape[@"o"], frame, 100.0f) / 100.0f;
	float width = TGScalarAtFast(shape[@"w"], frame, 1.0f);
	CGContextSetRGBStrokeColor(ctx, c[0], c[1], c[2], alpha);
	CGContextSetLineWidth(ctx, width);
	CGContextAddPath(ctx, path);
	CGContextStrokePath(ctx);
}

static CGGradientRef TGGradientFromStops(NSArray *k, NSUInteger perStop, double alpha) {
	NSUInteger stops = k.count / perStop;
	if (stops > 64)
		return nil;

	CGFloat cLocations[64];
	CGFloat cComponents[256];

	for (NSUInteger i = 0; i < stops; i++){
		NSUInteger base = i * perStop;
		double offset = [k[base] doubleValue];
		double colourAlpha = (perStop == 5) ? [k[base + 4] doubleValue] : 1.0;

		cLocations[i] = (CGFloat)MAX(MIN(offset, 1.0), 0.0);
		cComponents[i * 4 + 0] = (CGFloat)[k[base + 1] doubleValue];
		cComponents[i * 4 + 1] = (CGFloat)[k[base + 2] doubleValue];
		cComponents[i * 4 + 2] = (CGFloat)[k[base + 3] doubleValue];
		cComponents[i * 4 + 3] = (CGFloat)(colourAlpha * alpha);
	}

	static CGColorSpaceRef space = NULL;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		space = CGColorSpaceCreateDeviceRGB();
	});
	return CGGradientCreateWithColorComponents(space, cComponents, cLocations, (size_t)stops);
}

static void TGGradientFillPath(CGPathRef path, NSDictionary *shape, double frame, CGContextRef ctx) {
	if (CGPathIsEmpty(path))
		return;
	NSDictionary *g = shape[@"g"];
	id kObj = g[@"k"];
	NSArray *k = [kObj isKindOfClass:NSArray.class] ? (NSArray *)kObj : nil;
	NSInteger stops = [g[@"p"] integerValue];
	if (stops < 2 || !k.count)
		return;

	NSUInteger perStop = k.count / (NSUInteger)stops;
	if ((perStop != 4 && perStop != 5) || k.count < perStop * (NSUInteger)stops)
		return;

	float alpha = TGScalarAtFast(shape[@"o"], frame, 100.0f) / 100.0f;
	CGGradientRef gradient = TGGradientFromStops(k, perStop, alpha);
	if (!gradient)
		return;

	float from[2] = {0}, to[2] = {0};
	int fromC = TGValueAtFast(shape[@"s"], frame, from, 2);
	int toC   = TGValueAtFast(shape[@"e"], frame, to, 2);
	if (fromC < 2 || toC < 2){
		CGGradientRelease(gradient);
		return;
	}
	CGPoint start  = CGPointMake(from[0], from[1]);
	CGPoint finish = CGPointMake(to[0],   to[1]);

	CGContextSaveGState(ctx);
	CGContextAddPath(ctx, path);
	CGContextClip(ctx);
	if ([shape[@"t"] integerValue] == 2){
		double radius = sqrt(pow(finish.x - start.x, 2) +
							 pow(finish.y - start.y, 2));
		CGContextDrawRadialGradient(ctx, gradient, start, 0,
				finish, MAX(radius, 0.01), kCGGradientDrawsBeforeStartLocation |
										   kCGGradientDrawsAfterEndLocation);
	} else {
		CGContextDrawLinearGradient(ctx, gradient, start, finish,
				kCGGradientDrawsBeforeStartLocation |
				kCGGradientDrawsAfterEndLocation);
	}
	CGContextRestoreGState(ctx);
	CGGradientRelease(gradient);
}

static void TGCollectMaskPaths(NSArray *masks, double frame,
							   CGMutablePathRef inside,
							   CGMutablePathRef outside,
							   NSUInteger *counted) {
	for (NSDictionary *mask in masks){
		if (![mask isKindOfClass:NSDictionary.class])
			continue;
		NSString *mode = mask[@"mode"] ?: @"";
		if ([mode isEqualToString:@"n"] || !mode.length)
			continue;
		BOOL erase = [mode isEqualToString:@"s"] || [mode isEqualToString:@"d"];
		if ([mask[@"inv"] boolValue] && !erase)
			erase = YES;

		CGMutablePathRef sink = erase ? outside : inside;
		CGMutablePathRef maskPath = CGPathCreateMutable();
		TGAppendBezier(mask[@"pt"], frame, maskPath);
		CGPathAddPath(sink, NULL, maskPath);
		CGPathRelease(maskPath);
		(*counted)++;
	}
}

static void TGClipByMasks(NSArray *masks, double frame, CGContextRef ctx) {
	if (![masks isKindOfClass:NSArray.class] || !masks.count)
		return;

	NSUInteger counted = 0;
	CGMutablePathRef inside  = CGPathCreateMutable();
	CGMutablePathRef outside = CGPathCreateMutable();
	TGCollectMaskPaths(masks, frame, inside, outside, &counted);

	if (counted && !CGPathIsEmpty(inside)){
		CGContextAddPath(ctx, inside);
		CGContextClip(ctx);
	}
	CGPathRelease(inside);
	CGPathRelease(outside);
}

static void TGEraseByMasks(NSArray *masks, double frame, CGContextRef ctx) {
	if (![masks isKindOfClass:NSArray.class] || !masks.count)
		return;

	NSUInteger counted = 0;
	CGMutablePathRef inside  = CGPathCreateMutable();
	CGMutablePathRef outside = CGPathCreateMutable();
	TGCollectMaskPaths(masks, frame, inside, outside, &counted);

	if (!CGPathIsEmpty(outside)) {
		CGContextSetBlendMode(ctx, kCGBlendModeClear);
		CGContextSetRGBFillColor(ctx, 0, 0, 0, TGAlphaOpaque);
		CGContextAddPath(ctx, outside);
		CGContextFillPath(ctx);
		CGContextSetBlendMode(ctx, kCGBlendModeNormal);
	}

	CGPathRelease(inside);
	CGPathRelease(outside);
}

static void TGDrawShapes(NSArray *shapes, double frame, CGContextRef ctx) {
	if (![shapes isKindOfClass:NSArray.class])
		return;

	CGMutablePathRef path = CGPathCreateMutable();

	for (NSDictionary *shape in shapes){
		NSString *ty = shape[@"ty"];

		if ([ty isEqualToString:@"gr"]){
			CGContextSaveGState(ctx);
			NSArray *items = shape[@"it"];
			for (NSDictionary *item in items)
				if ([item[@"ty"] isEqualToString:@"tr"])
					TGApplyTransform(item, frame, ctx);
			TGDrawShapes(items, frame, ctx);
			CGContextRestoreGState(ctx);

		} else if ([ty isEqualToString:@"sh"]){
			TGAppendBezier(shape[@"ks"], frame, path);

		} else if ([ty isEqualToString:@"el"]){
			float p[2] = {0}, s[2] = {0};
			int pC = TGValueAtFast(shape[@"p"], frame, p, 2);
			int sC = TGValueAtFast(shape[@"s"], frame, s, 2);
			if (pC >= 2 && sC >= 2){
				CGRect r = CGRectMake(p[0] - s[0] / 2.0f,
									  p[1] - s[1] / 2.0f,
									  s[0], s[1]);
				CGPathAddEllipseInRect(path, NULL, r);
			}

		} else if ([ty isEqualToString:@"rc"]){
			float p[2] = {0}, s[2] = {0};
			int pC = TGValueAtFast(shape[@"p"], frame, p, 2);
			int sC = TGValueAtFast(shape[@"s"], frame, s, 2);
			float radius = TGScalarAtFast(shape[@"r"], frame, 0.0f);
			if (pC >= 2 && sC >= 2){
				CGRect r = CGRectMake(p[0] - s[0] / 2.0f,
									  p[1] - s[1] / 2.0f,
									  s[0], s[1]);
				if (radius > 0.0f){
					UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius];
					CGPathAddPath(path, NULL, rounded.CGPath);
				} else {
					CGPathAddRect(path, NULL, r);
				}
			}

		} else if ([ty isEqualToString:@"fl"]){
			TGFillPath(path, shape, frame, ctx);

		} else if ([ty isEqualToString:@"gf"]){
			TGGradientFillPath(path, shape, frame, ctx);

		} else if ([ty isEqualToString:@"st"]){
			TGStrokePath(path, shape, frame, ctx);
		}
	}

	CGPathRelease(path);
}

static void TGDrawLottieLayer(NSDictionary *layer, NSDictionary *layersByInd, double frame, CGContextRef ctx) {
	if ([layer[@"ty"] intValue] != 4)
		return;

	double ip = [layer[@"ip"] doubleValue];
	double op = [layer[@"op"] doubleValue];
	if (frame < ip || frame > op)
		return;

	CGContextSaveGState(ctx);

	NSMutableArray *hierarchy = [NSMutableArray array];
	NSDictionary *curr = layer;
	while (curr) {
		[hierarchy insertObject:curr atIndex:0];
		id parentInd = curr[@"parent"];
		curr = parentInd ? layersByInd[parentInd] : nil;
	}

	for (NSDictionary *l in hierarchy) {
		TGApplyTransform(l[@"ks"], frame, ctx);
	}

	TGClipByMasks(layer[@"masksProperties"], frame, ctx);
	TGDrawShapes(layer[@"shapes"], frame, ctx);
	TGEraseByMasks(layer[@"masksProperties"], frame, ctx);
	CGContextRestoreGState(ctx);
}

#pragma mark - Offscreen Bitmap Rasterization

static CGImageRef TGRasterizeLottieFrame(TGLottieModel *model, double frame, CGSize targetSize) {
	int w = (int)targetSize.width;
	int h = (int)targetSize.height;
	if (w <= 0 || h <= 0 || model.canvas.width <= 0 || model.canvas.height <= 0)
		return NULL;

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs,
		kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(cs);
	if (!ctx)
		return NULL;

	CGFloat scale = MIN((CGFloat)w / model.canvas.width, (CGFloat)h / model.canvas.height);
	CGFloat ox = TGCenteredOrigin((CGFloat)w, model.canvas.width * scale);
	CGFloat oy = TGCenteredOrigin((CGFloat)h, model.canvas.height * scale);

	CGContextTranslateCTM(ctx, ox, oy);
	CGContextScaleCTM(ctx, scale, scale);

	for (NSDictionary *layer in [[model.layers reverseObjectEnumerator] allObjects]) {
		TGDrawLottieLayer(layer, model.layersByInd, frame, ctx);
	}

	CGImageRef img = CGBitmapContextCreateImage(ctx);
	CGContextRelease(ctx);
	return img;
}

#pragma mark - View Implementation

@interface TGLottieView ()
@property (nonatomic, copy) NSString *loadedPath;
@property (nonatomic, strong) TGLottieModel *model;
@property (nonatomic, assign) NSUInteger currentFrameIndex;
@property (nonatomic, assign) double currentFrame;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL isPlaying;
@end

@implementation TGLottieView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.backgroundColor = [UIColor clearColor];
		self.opaque = NO;
		self.layer.contentsGravity = kCAGravityResizeAspect;
	}
	return self;
}

- (void)dealloc {
	[_timer invalidate];
}

- (void)startTimer {
	if (self.timer || !self.loaded) return;
	double fps = self.model.isWebM ? self.model.frameRate : 20.0;
	if (fps < 10.0) fps = 15.0;
	if (fps > 30.0) fps = 30.0;

	self.timer = [NSTimer timerWithTimeInterval:1.0 / fps
										 target:self
									   selector:@selector(tick)
									   userInfo:nil
										repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) {
		if (self.isPlaying && self.loaded && !self.timer) {
			[self startTimer];
		}
	} else {
		[self.timer invalidate];
		self.timer = nil;
	}
}

- (BOOL)loadTGSFile:(NSString *)path {
	return [self loadStickerFile:path];
}

- (BOOL)loadStickerFile:(NSString *)path {
	if (!path.length) return NO;
	if ([self.loadedPath isEqualToString:path] && self.loaded) {
		if (self.isPlaying && !self.timer) {
			[self startTimer];
		}
		return YES;
	}

	static NSCache *sStickerCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sStickerCache = [[NSCache alloc] init];
		sStickerCache.countLimit = 32;
	});

	TGLottieModel *model = [sStickerCache objectForKey:path];
	BOOL isWebM = [path.pathExtension.lowercaseString isEqualToString:@"webm"];

	if (!model) {
		model = [[TGLottieModel alloc] init];
		model.path = path;
		model.isWebM = isWebM;

		if (isWebM) {
			double fps = 30.0;
			NSTimeInterval dur = 0;
			NSArray *frames = [TGWebMDecoder decodeFramesFromFile:path fps:&fps duration:&dur];
			if (!frames.count) {
				NSLog(@"TGLottieView: WebM decode returned 0 frames for %@", path.lastPathComponent);
				return NO;
			}
			model.cachedFrames = frames;
			model.frameRate = fps;
			model.canvas = CGSizeMake(256, 256);
			[sStickerCache setObject:model forKey:path];
		} else {
			// Lottie TGS JSON
			NSData *gz = [NSData dataWithContentsOfFile:path];
			NSData *json = TGGunzip(gz);
			if (!json.length){
				NSLog(@"TGLottie: not gzip or empty: %@", path.lastPathComponent);
				return NO;
			}

			NSError *err = nil;
			NSDictionary *anim = TGJsonParse((const char *)json.bytes, json.length, &err);
			if (![anim isKindOfClass:NSDictionary.class]){
				NSLog(@"TGLottie: bad JSON: %@", err);
				return NO;
			}

			model.anim = anim;
			model.layers = anim[@"layers"];
			NSMutableDictionary *byInd = [NSMutableDictionary dictionary];
			for (NSDictionary *l in anim[@"layers"]) {
				id ind = l[@"ind"];
				if (ind) byInd[ind] = l;
			}
			model.layersByInd = byInd;
			model.inPoint = [anim[@"ip"] doubleValue];
			model.outPoint = [anim[@"op"] doubleValue];
			model.frameRate = [anim[@"fr"] doubleValue] ?: 60.0;
			model.canvas = CGSizeMake([anim[@"w"] doubleValue], [anim[@"h"] doubleValue]);

			if (model.layers.count > 0 && model.canvas.width > 0) {
				[sStickerCache setObject:model forKey:path];
			} else {
				return NO;
			}
		}
	}

	self.loadedPath = path;
	self.model = model;
	self.currentFrame = model.inPoint;
	self.currentFrameIndex = 0;
	self.loaded = YES;

	// Target pixel rasterization size (clamped to max 256x256 for optimal A5 performance)
	CGSize viewSize = self.bounds.size;
	if (viewSize.width <= 0) viewSize = CGSizeMake(130, 130);
	CGFloat screenScale = [UIScreen mainScreen].scale;
	CGFloat pxW = MIN(256.0f, viewSize.width * screenScale);
	CGFloat pxH = MIN(256.0f, viewSize.height * screenScale);
	CGSize targetPxSize = CGSizeMake(pxW, pxH);

	if (model.cachedFrames.count > 0) {
		// Instantly show frame 0 with hardware layer
		CGImageRef first = (__bridge CGImageRef)model.cachedFrames[0];
		self.layer.contents = (__bridge id)first;
	} else if (!model.isWebM) {
		// Rasterize frame 0 synchronously so the user sees the sticker immediately
		CGImageRef f0 = TGRasterizeLottieFrame(model, model.inPoint, targetPxSize);
		if (f0) {
			self.layer.contents = (__bridge id)f0;
			CGImageRelease(f0);
		}

		// Asynchronously pre-rasterize the animation loop on a background thread
		if (!model.isRasterizing) {
			model.isRasterizing = YES;
			__weak typeof(self) weakSelf = self;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				double targetFps = 18.0;
				double duration = (model.outPoint - model.inPoint) / (model.frameRate ?: 60.0);
				if (duration <= 0.05) duration = 2.0;
				int totalFrames = (int)ceil(duration * targetFps);
				if (totalFrames < 1) totalFrames = 1;
				if (totalFrames > 60) totalFrames = 60; // clamp to reasonable buffer

				double frameStep = (model.outPoint - model.inPoint) / (double)totalFrames;
				NSMutableArray *rendered = [NSMutableArray arrayWithCapacity:totalFrames];

				for (int i = 0; i < totalFrames; i++) {
					double f = model.inPoint + i * frameStep;
					CGImageRef img = TGRasterizeLottieFrame(model, f, targetPxSize);
					if (img) {
						[rendered addObject:CFBridgingRelease(img)];
					}
				}

				dispatch_async(dispatch_get_main_queue(), ^{
					model.cachedFrames = rendered;
					model.isRasterizing = NO;
					if ([weakSelf.loadedPath isEqualToString:path]) {
						if (rendered.count > 0 && !weakSelf.layer.contents) {
							weakSelf.layer.contents = (__bridge id)(__bridge CGImageRef)rendered[0];
						}
					}
				});
			});
		}
	}

	if (self.isPlaying && !self.timer) {
		[self startTimer];
	}

	return self.loaded;
}

- (void)play {
	self.isPlaying = YES;
	if (self.loaded && !self.timer) {
		[self startTimer];
	}
}

- (void)stop {
	self.isPlaying = NO;
	[self.timer invalidate];
	self.timer = nil;
}

- (void)tick {
	if (!self.window || self.hidden || !self.loaded)
		return;

	NSArray *frames = self.model.cachedFrames;
	if (frames.count > 0) {
		self.currentFrameIndex = (self.currentFrameIndex + 1) % frames.count;
		CGImageRef img = (__bridge CGImageRef)frames[self.currentFrameIndex];
		if (img) {
			self.layer.contents = (__bridge id)img;
		}
		return;
	}

	// Fallback while background rasterizer is completing
	double fps = 18.0;
	double step = self.model.frameRate / fps;
	self.currentFrame += step;
	if (self.currentFrame >= self.model.outPoint)
		self.currentFrame = self.model.inPoint;
	[self setNeedsDisplay];
}

#pragma mark - drawing (fallback only when not yet rasterized)

- (void)drawRect:(CGRect)rect {
	if (!self.loaded || self.model.cachedFrames.count > 0)
		return;

	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSaveGState(ctx);

	CGFloat scale = MIN(self.bounds.size.width / self.model.canvas.width,
						self.bounds.size.height / self.model.canvas.height);
	CGContextTranslateCTM(ctx,
			TGCenteredOrigin(self.bounds.size.width, self.model.canvas.width * scale),
			TGCenteredOrigin(self.bounds.size.height, self.model.canvas.height * scale));
	CGContextScaleCTM(ctx, scale, scale);

	for (NSDictionary *layer in [[self.model.layers reverseObjectEnumerator] allObjects])
		TGDrawLottieLayer(layer, self.model.layersByInd, self.currentFrame, ctx);

	CGContextRestoreGState(ctx);
}

@end
