#import "TGLottieView.h"
#include <zlib.h>

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

#pragma mark - keyframed values

/// Lottie writes a property either as a plain value ("k" is a number or array)
/// or as a list of keyframes. Both collapse to "value at frame f".

static NSArray *TGNumbers(id v) {
	if ([v isKindOfClass:NSArray.class])
		return v;
	if ([v isKindOfClass:NSNumber.class])
		return @[v];
	return nil;
}

/// Interpolate a keyframed property at `frame`. Returns an array of numbers.
static NSArray *TGValueAt(NSDictionary *prop, double frame) {
	id k = prop[@"k"];
	if (!k)
		return nil;

	// static value
	if (![k isKindOfClass:NSArray.class] ||
		![[k firstObject] isKindOfClass:NSDictionary.class])
		return TGNumbers(k);

	NSArray *keys = k;
	NSDictionary *before = nil, *after = nil;

	for (NSDictionary *kf in keys){
		double t = [kf[@"t"] doubleValue];
		if (t <= frame)
			before = kf;
		else { after = kf; break; }
	}
	if (!before)
		return TGNumbers([[keys firstObject] objectForKey:@"s"]);
	if (!after)
		return TGNumbers(before[@"s"] ?: before[@"e"]);

	NSArray *from = TGNumbers(before[@"s"]);
	NSArray *to   = TGNumbers(before[@"e"] ?: after[@"s"]);
	if (!from || !to)
		return from ?: to;

	double t0 = [before[@"t"] doubleValue];
	double t1 = [after[@"t"] doubleValue];
	double p = (t1 > t0) ? (frame - t0) / (t1 - t0) : 0.0;
	if (p < 0) p = 0;
	if (p > 1) p = 1;

	// Linear only. Telegram's easing is cubic, so fast-in/out looks slightly
	// more even than intended - visible only in side-by-side comparison.
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:from.count];
	for (NSUInteger i = 0; i < from.count; i++){
		double a = [from[i] doubleValue];
		double b = (i < to.count) ? [to[i] doubleValue] : a;
		[out addObject:@(a + (b - a) * p)];
	}
	return out;
}

static double TGScalarAt(NSDictionary *prop, double frame, double fallback) {
	NSArray *v = TGValueAt(prop, frame);
	return v.count ? [v[0] doubleValue] : fallback;
}

#pragma mark - view

@interface TGLottieView ()
@property (nonatomic, strong) NSDictionary *animation;
@property (nonatomic, strong) NSArray *layers;
@property (nonatomic, assign) double inPoint;
@property (nonatomic, assign) double outPoint;
@property (nonatomic, assign) double frameRate;
@property (nonatomic, assign) CGSize canvas;
@property (nonatomic, assign) double currentFrame;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL loaded;
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

- (BOOL)loadTGSFile:(NSString *)path {
	NSData *gz = [NSData dataWithContentsOfFile:path];
	NSData *json = TGGunzip(gz);
	if (!json.length){
		NSLog(@"TGLottie: not gzip or empty: %@", path.lastPathComponent);
		return NO;
	}

	NSError *err = nil;
	NSDictionary *anim = [NSJSONSerialization JSONObjectWithData:json options:0 error:&err];
	if (![anim isKindOfClass:NSDictionary.class]){
		NSLog(@"TGLottie: bad JSON: %@", err);
		return NO;
	}

	self.animation = anim;
	self.layers    = anim[@"layers"];
	self.inPoint   = [anim[@"ip"] doubleValue];
	self.outPoint  = [anim[@"op"] doubleValue];
	self.frameRate = [anim[@"fr"] doubleValue] ?: 60.0;
	self.canvas    = CGSizeMake([anim[@"w"] doubleValue], [anim[@"h"] doubleValue]);
	self.currentFrame = self.inPoint;
	self.loaded = (self.layers.count > 0 && self.canvas.width > 0);

	[self setNeedsDisplay];
	return self.loaded;
}

- (void)play {
	if (!self.loaded || self.timer)
		return;
	// An A5 will not hold 60fps on a vector sticker; 20 is smooth enough and
	// leaves the main thread usable.
	self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 20.0
												  target:self
												selector:@selector(tick)
												userInfo:nil
												 repeats:YES];
}

- (void)stop {
	[self.timer invalidate];
	self.timer = nil;
}

- (void)tick {
	double step = self.frameRate / 20.0;
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
			(self.bounds.size.width - self.canvas.width * scale) / 2,
			(self.bounds.size.height - self.canvas.height * scale) / 2);
	CGContextScaleCTM(ctx, scale, scale);

	// Lottie paints the last layer first.
	for (NSDictionary *layer in [[self.layers reverseObjectEnumerator] allObjects])
		[self drawLottieLayer:layer inContext:ctx];

	CGContextRestoreGState(ctx);
}

// NOT drawLayer:inContext: - that is UIView's CALayerDelegate method, and
// CoreAnimation calls it with a real CALayer when the view renders.
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
	[self applyTransform:layer[@"ks"] atFrame:frame inContext:ctx];
	[self drawShapes:layer[@"shapes"] atFrame:frame inContext:ctx];
	CGContextRestoreGState(ctx);
}

- (void)applyTransform:(NSDictionary *)ks atFrame:(double)frame inContext:(CGContextRef)ctx {
	if (!ks)
		return;

	NSArray *pos    = TGValueAt(ks[@"p"], frame);
	NSArray *anchor = TGValueAt(ks[@"a"], frame);
	NSArray *scale  = TGValueAt(ks[@"s"], frame);
	double rotation = TGScalarAt(ks[@"r"], frame, 0);
	double opacity  = TGScalarAt(ks[@"o"], frame, 100);

	if (pos.count >= 2)
		CGContextTranslateCTM(ctx, [pos[0] doubleValue], [pos[1] doubleValue]);
	if (rotation != 0)
		CGContextRotateCTM(ctx, rotation * M_PI / 180.0);
	if (scale.count >= 2)
		CGContextScaleCTM(ctx, [scale[0] doubleValue] / 100.0,
							   [scale[1] doubleValue] / 100.0);
	if (anchor.count >= 2)
		CGContextTranslateCTM(ctx, -[anchor[0] doubleValue], -[anchor[1] doubleValue]);

	CGContextSetAlpha(ctx, opacity / 100.0);
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
			// a group carries its own transform, as the last item
			for (NSDictionary *item in items)
				if ([item[@"ty"] isEqualToString:@"tr"])
					[self applyTransform:item atFrame:frame inContext:ctx];
			[self drawShapes:items atFrame:frame inContext:ctx];
			CGContextRestoreGState(ctx);

		} else if ([ty isEqualToString:@"sh"]){
			[self appendBezier:shape[@"ks"] atFrame:frame toPath:path];

		} else if ([ty isEqualToString:@"el"]){
			NSArray *p = TGValueAt(shape[@"p"], frame);
			NSArray *s = TGValueAt(shape[@"s"], frame);
			if (p.count >= 2 && s.count >= 2){
				CGRect r = CGRectMake([p[0] doubleValue] - [s[0] doubleValue] / 2,
									  [p[1] doubleValue] - [s[1] doubleValue] / 2,
									  [s[0] doubleValue], [s[1] doubleValue]);
				CGPathAddEllipseInRect(path, NULL, r);
			}

		} else if ([ty isEqualToString:@"rc"]){
			NSArray *p = TGValueAt(shape[@"p"], frame);
			NSArray *s = TGValueAt(shape[@"s"], frame);
			double radius = TGScalarAt(shape[@"r"], frame, 0);
			if (p.count >= 2 && s.count >= 2){
				CGRect r = CGRectMake([p[0] doubleValue] - [s[0] doubleValue] / 2,
									  [p[1] doubleValue] - [s[1] doubleValue] / 2,
									  [s[0] doubleValue], [s[1] doubleValue]);
				if (radius > 0){
					UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:r
																	  cornerRadius:radius];
					CGPathAddPath(path, NULL, rounded.CGPath);
				} else {
					CGPathAddRect(path, NULL, r);
				}
			}

		} else if ([ty isEqualToString:@"fl"]){
			[self fillPath:path withShape:shape atFrame:frame inContext:ctx];

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
		// keyframed shape: take the last keyframe whose time has passed
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

		NSArray *v = shape[@"v"], *in = shape[@"i"], *out = shape[@"o"];
		if (v.count < 2)
			continue;

		CGPathMoveToPoint(path, NULL, [v[0][0] doubleValue], [v[0][1] doubleValue]);
		for (NSUInteger i = 1; i < v.count; i++){
			NSUInteger p = i - 1;
			CGPathAddCurveToPoint(path, NULL,
				[v[p][0] doubleValue] + [out[p][0] doubleValue],
				[v[p][1] doubleValue] + [out[p][1] doubleValue],
				[v[i][0] doubleValue] + [in[i][0] doubleValue],
				[v[i][1] doubleValue] + [in[i][1] doubleValue],
				[v[i][0] doubleValue], [v[i][1] doubleValue]);
		}

		if ([shape[@"c"] boolValue]){
			NSUInteger last = v.count - 1;
			CGPathAddCurveToPoint(path, NULL,
				[v[last][0] doubleValue] + [out[last][0] doubleValue],
				[v[last][1] doubleValue] + [out[last][1] doubleValue],
				[v[0][0] doubleValue] + [in[0][0] doubleValue],
				[v[0][1] doubleValue] + [in[0][1] doubleValue],
				[v[0][0] doubleValue], [v[0][1] doubleValue]);
			CGPathCloseSubpath(path);
		}
	}
}

- (void)fillPath:(CGPathRef)path withShape:(NSDictionary *)shape
		 atFrame:(double)frame inContext:(CGContextRef)ctx {
	NSArray *c = TGValueAt(shape[@"c"], frame);
	if (c.count < 3 || CGPathIsEmpty(path))
		return;

	double alpha = TGScalarAt(shape[@"o"], frame, 100) / 100.0;
	CGContextSetRGBFillColor(ctx, [c[0] doubleValue], [c[1] doubleValue],
								  [c[2] doubleValue], alpha);
	CGContextAddPath(ctx, path);
	// Lottie fills use even-odd, which is what makes holes work.
	CGContextEOFillPath(ctx);
}

- (void)strokePath:(CGPathRef)path withShape:(NSDictionary *)shape
		   atFrame:(double)frame inContext:(CGContextRef)ctx {
	NSArray *c = TGValueAt(shape[@"c"], frame);
	if (c.count < 3 || CGPathIsEmpty(path))
		return;

	double alpha = TGScalarAt(shape[@"o"], frame, 100) / 100.0;
	double width = TGScalarAt(shape[@"w"], frame, 1);
	CGContextSetRGBStrokeColor(ctx, [c[0] doubleValue], [c[1] doubleValue],
									[c[2] doubleValue], alpha);
	CGContextSetLineWidth(ctx, width);
	CGContextAddPath(ctx, path);
	CGContextStrokePath(ctx);
}

@end

// vim:ft=objc
