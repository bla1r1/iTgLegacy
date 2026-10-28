//
// TGLottieView.mm - High-performance C++ vector animation renderer for Telegram stickers (.tgs / Lottie).
//
#import "TGLottieView.h"
#import "TGStyle.h"
#import "TGJson.h"
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

	// 15 + 32 lets zlib detect gzip or zlib wrapping on its own
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
@property (nonatomic, strong) NSDictionary *anim;
@property (nonatomic, strong) NSArray *layers;
@property (nonatomic, strong) NSDictionary *layersByInd;
@property (nonatomic, assign) double inPoint;
@property (nonatomic, assign) double outPoint;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) CGSize canvas;
@end

@implementation TGLottieModel
@end

#pragma mark - view

@interface TGLottieView ()
@property (nonatomic, copy) NSString *loadedPath;
@property (nonatomic, strong) NSDictionary *animation;
@property (nonatomic, strong) NSArray *layers;
@property (nonatomic, strong) NSDictionary *layersByInd;
@property (nonatomic, assign) double inPoint;
@property (nonatomic, assign) double outPoint;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) CGSize canvas;
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
	}
	return self;
}

- (void)dealloc {
	[_timer invalidate];
}

- (void)startTimer {
	if (self.timer || !self.loaded) return;
	double fps = ([NSProcessInfo processInfo].processorCount < 2) ? 12.0 : 18.0;
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
	}
}

- (BOOL)loadTGSFile:(NSString *)path {
	if (!path.length) return NO;
	if ([self.loadedPath isEqualToString:path] && self.loaded) {
		if (self.isPlaying && !self.timer) {
			[self startTimer];
		}
		return YES;
	}

	static NSCache *sModelCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sModelCache = [[NSCache alloc] init];
		sModelCache.countLimit = 32;
	});

	TGLottieModel *model = [sModelCache objectForKey:path];
	if (!model) {
		NSData *gz = [NSData dataWithContentsOfFile:path];
		NSData *json = TGGunzip(gz);
		if (!json.length){
			NSLog(@"TGLottie: not gzip or empty: %@", path.lastPathComponent);
			return NO;
		}

		NSError *err = nil;
		// Use zero-copy yyjson parser
		NSDictionary *anim = TGJsonParse((const char *)json.bytes, json.length, &err);
		if (![anim isKindOfClass:NSDictionary.class]){
			NSLog(@"TGLottie: bad JSON: %@", err);
			return NO;
		}

		model = [[TGLottieModel alloc] init];
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
			[sModelCache setObject:model forKey:path];
		}
	}

	self.loadedPath = path;
	self.animation = model.anim;
	self.layers    = model.layers;
	self.layersByInd = model.layersByInd;
	self.inPoint   = model.inPoint;
	self.outPoint  = model.outPoint;
	self.frameRate = model.frameRate;
	self.canvas    = model.canvas;
	self.currentFrame = self.inPoint;
	self.loaded = (self.layers.count > 0 && self.canvas.width > 0);

	if (self.isPlaying && !self.timer) {
		[self startTimer];
	}

	[self setNeedsDisplay];
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
	if (!self.window || self.hidden)
		return;
	double fps = ([NSProcessInfo processInfo].processorCount < 2) ? 12.0 : 18.0;
	double step = self.frameRate / fps;
	self.currentFrame += step;
	if (self.currentFrame >= self.outPoint)
		self.currentFrame = self.inPoint;   // stickers loop
	[self setNeedsDisplay];
}

#pragma mark - drawing

- (void)drawRect:(CGRect)rect {
	if (!self.loaded)
		return;

	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSaveGState(ctx);

	// Lottie's origin is top-left in canvas units; scale to fit the view.
	CGFloat scale = MIN(self.bounds.size.width / self.canvas.width,
						self.bounds.size.height / self.canvas.height);
	CGContextTranslateCTM(ctx,
			TGCenteredOrigin(self.bounds.size.width, self.canvas.width * scale),
			TGCenteredOrigin(self.bounds.size.height, self.canvas.height * scale));
	CGContextScaleCTM(ctx, scale, scale);

	// Lottie paints the last layer first.
	for (NSDictionary *layer in [[self.layers reverseObjectEnumerator] allObjects])
		[self drawLottieLayer:layer inContext:ctx];

	CGContextRestoreGState(ctx);
}

- (void)drawLottieLayer:(NSDictionary *)layer inContext:(CGContextRef)ctx {
	// type 4 is a shape layer; nothing else is drawable here
	if ([layer[@"ty"] intValue] != 4)
		return;

	double frame = self.currentFrame;
	double ip = [layer[@"ip"] doubleValue];
	double op = [layer[@"op"] doubleValue];
	if (frame < ip || frame > op)
		return;

	CGContextSaveGState(ctx);

	// Walk parent hierarchy from root down to this layer
	NSMutableArray *hierarchy = [NSMutableArray array];
	NSDictionary *curr = layer;
	while (curr) {
		[hierarchy insertObject:curr atIndex:0];
		id parentInd = curr[@"parent"];
		curr = parentInd ? self.layersByInd[parentInd] : nil;
	}

	for (NSDictionary *l in hierarchy) {
		[self applyTransform:l[@"ks"] atFrame:frame inContext:ctx];
	}

	[self clipByMasks:layer[@"masksProperties"] atFrame:frame inContext:ctx];
	[self drawShapes:layer[@"shapes"] atFrame:frame inContext:ctx];
	[self eraseByMasks:layer[@"masksProperties"] atFrame:frame inContext:ctx];
	CGContextRestoreGState(ctx);
}

- (void)applyTransform:(NSDictionary *)ks atFrame:(double)frame inContext:(CGContextRef)ctx {
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

/// A shape group is a list where paths accumulate and a fill/stroke paints
/// whatever came before it - so build the path first, then look for paint.
- (void)drawShapes:(NSArray *)shapes atFrame:(double)frame inContext:(CGContextRef)ctx {
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
					[self applyTransform:item atFrame:frame inContext:ctx];
			[self drawShapes:items atFrame:frame inContext:ctx];
			CGContextRestoreGState(ctx);

		} else if ([ty isEqualToString:@"sh"]){
			[self appendBezier:shape[@"ks"] atFrame:frame toPath:path];

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
					UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:r
																	  cornerRadius:radius];
					CGPathAddPath(path, NULL, rounded.CGPath);
				} else {
					CGPathAddRect(path, NULL, r);
				}
			}

		} else if ([ty isEqualToString:@"fl"]){
			[self fillPath:path withShape:shape atFrame:frame inContext:ctx];

		} else if ([ty isEqualToString:@"gf"]){
			[self gradientFillPath:path withShape:shape atFrame:frame inContext:ctx];

		} else if ([ty isEqualToString:@"st"]){
			[self strokePath:path withShape:shape atFrame:frame inContext:ctx];
		}
	}

	CGPathRelease(path);
}

/// Lottie bezier: "v" vertices, "i"/"o" tangents relative to their vertex.
- (void)appendBezier:(NSDictionary *)ks atFrame:(double)frame toPath:(CGMutablePathRef)path {
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

- (void)fillPath:(CGPathRef)path withShape:(NSDictionary *)shape
		 atFrame:(double)frame inContext:(CGContextRef)ctx {
	float c[4] = {0};
	int cC = TGValueAtFast(shape[@"c"], frame, c, 4);
	if (cC < 3 || CGPathIsEmpty(path))
		return;

	float alpha = TGScalarAtFast(shape[@"o"], frame, 100.0f) / 100.0f;
	CGContextSetRGBFillColor(ctx, c[0], c[1], c[2], alpha);
	CGContextAddPath(ctx, path);
	CGContextEOFillPath(ctx);
}

#pragma mark - masks

- (void)collectMaskPaths:(NSArray *)masks atFrame:(double)frame
				   inside:(CGMutablePathRef)inside
				  outside:(CGMutablePathRef)outside
				  counted:(NSUInteger *)counted {
	for (NSDictionary *mask in masks){
		if (![mask isKindOfClass:NSDictionary.class])
			continue;
		NSString *mode = mask[@"mode"] ?: @"";
		if ([mode isEqualToString:@"n"] || !mode.length)
			continue;
		BOOL erase = [mode isEqualToString:@"s"] ||
					 [mode isEqualToString:@"d"];
		if ([mask[@"inv"] boolValue] && !erase)
			erase = YES;

		CGMutablePathRef sink = erase ? outside : inside;
		CGMutablePathRef maskPath = CGPathCreateMutable();
		[self appendBezier:mask[@"pt"] atFrame:frame toPath:maskPath];
		CGPathAddPath(sink, NULL, maskPath);
		CGPathRelease(maskPath);
		(*counted)++;
	}
}

- (void)clipByMasks:(NSArray *)masks atFrame:(double)frame inContext:(CGContextRef)ctx {
	if (![masks isKindOfClass:NSArray.class] || !masks.count)
		return;

	NSUInteger counted = 0;
	CGMutablePathRef inside  = CGPathCreateMutable();
	CGMutablePathRef outside = CGPathCreateMutable();
	[self collectMaskPaths:masks atFrame:frame inside:inside outside:outside counted:&counted];

	if (counted && !CGPathIsEmpty(inside)){
		CGContextAddPath(ctx, inside);
		CGContextClip(ctx);
	}
	CGPathRelease(inside);
	CGPathRelease(outside);
}

- (void)eraseByMasks:(NSArray *)masks atFrame:(double)frame inContext:(CGContextRef)ctx {
	if (![masks isKindOfClass:NSArray.class] || !masks.count)
		return;

	NSUInteger counted = 0;
	CGMutablePathRef inside  = CGPathCreateMutable();
	CGMutablePathRef outside = CGPathCreateMutable();
	[self collectMaskPaths:masks atFrame:frame inside:inside outside:outside counted:&counted];
	[self erasePath:outside inContext:ctx];

	CGPathRelease(inside);
	CGPathRelease(outside);
}

- (void)erasePath:(CGMutablePathRef)path inContext:(CGContextRef)ctx {
	if (CGPathIsEmpty(path))
		return;
	CGContextSetBlendMode(ctx, kCGBlendModeClear);
	CGContextSetRGBFillColor(ctx, 0, 0, 0, TGAlphaOpaque);
	CGContextAddPath(ctx, path);
	CGContextFillPath(ctx);
	CGContextSetBlendMode(ctx, kCGBlendModeNormal);
}

#pragma mark - gradients

- (void)gradientFillPath:(CGPathRef)path withShape:(NSDictionary *)shape
				 atFrame:(double)frame inContext:(CGContextRef)ctx {
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
	CGGradientRef gradient = [self gradientFromStops:k
											 perStop:perStop
											 atFrame:frame
										   withAlpha:alpha];
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

- (CGGradientRef)gradientFromStops:(NSArray *)k
						   perStop:(NSUInteger)perStop
						   atFrame:(double)frame
						 withAlpha:(double)alpha {
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
	if (!space)
		space = CGColorSpaceCreateDeviceRGB();
	return CGGradientCreateWithColorComponents(space, cComponents, cLocations, (size_t)stops);
}

- (void)strokePath:(CGPathRef)path withShape:(NSDictionary *)shape
		   atFrame:(double)frame inContext:(CGContextRef)ctx {
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

@end
