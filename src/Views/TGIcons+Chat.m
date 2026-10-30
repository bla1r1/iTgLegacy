//
// TGIcons+Chat.m
// Chat bubbles, speech tails, delivery ticks, waveforms and call markers.
//
#import "TGIconsInternal.h"

static const CGFloat kTailWidth  = 6.0f;
static const CGFloat kTailHeight = 13.0f;

@implementation TGIcons (Chat)

+ (UIImage *)callArrowOutgoing:(BOOL)outgoing missed:(BOOL)missed {
	NSString *key = [NSString stringWithFormat:@"callArrow_%d_%d", outgoing, missed];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat s = 14;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (missed)
		CGContextSetRGBStrokeColor(ctx, 0.871f, 0.227f, 0.227f, 1.0f);
	else
		CGContextSetRGBStrokeColor(ctx, 0.353f, 0.804f, 0.188f, 1.0f);
	CGContextSetLineWidth(ctx, TGIconStroke);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	CGFloat lo = 2.5f, hi = s - 2.5f;
	if (outgoing){
		CGContextMoveToPoint(ctx, lo, hi);
		CGContextAddLineToPoint(ctx, hi, lo);
		CGContextStrokePath(ctx);
		CGContextMoveToPoint(ctx, hi - 5, lo);
		CGContextAddLineToPoint(ctx, hi, lo);
		CGContextAddLineToPoint(ctx, hi, lo + 5);
	} else {
		CGContextMoveToPoint(ctx, hi, lo);
		CGContextAddLineToPoint(ctx, lo, hi);
		CGContextStrokePath(ctx);
		CGContextMoveToPoint(ctx, lo + 5, hi);
		CGContextAddLineToPoint(ctx, lo, hi);
		CGContextAddLineToPoint(ctx, lo, hi - 5);
	}
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)microphoneOfSide:(CGFloat)side colour:(UIColor *)colour {
	NSString *key = [NSString stringWithFormat:@"mic_%.0f_%lu", side, (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	UIBezierPath *head = [UIBezierPath bezierPathWithRoundedRect:
			CGRectMake(side * 0.40f, side * 0.18f, side * 0.20f, side * 0.38f)
												   cornerRadius:side * 0.10f];
	[head fill];

	CGContextSetLineWidth(ctx, MAX(1.5f, side * 0.055f));
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextAddArc(ctx, TGHalf(side), side * 0.50f, side * 0.20f, 0, M_PI, 0);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, TGHalf(side), side * 0.70f);
	CGContextAddLineToPoint(ctx, TGHalf(side), side * 0.80f);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, side * 0.38f, side * 0.80f);
	CGContextAddLineToPoint(ctx, side * 0.62f, side * 0.80f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)microphoneOffOfSide:(CGFloat)side colour:(UIColor *)colour {
	NSString *key = [NSString stringWithFormat:@"micoff_%.0f_%lu", side, (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	[[self microphoneOfSide:side colour:colour] drawInRect:CGRectMake(0, 0, side, side)];

	CGContextSetLineWidth(ctx, MAX(1.5f, side * 0.055f));
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextMoveToPoint(ctx, side * 0.22f, side * 0.20f);
	CGContextAddLineToPoint(ctx, side * 0.78f, side * 0.80f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)lockOfSide:(CGFloat)side colour:(UIColor *)colour {
	NSString *key = [NSString stringWithFormat:@"lock_%.0f_%lu", side, (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	CGContextSetLineWidth(ctx, MAX(1.0f, side * 0.09f));
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextAddArc(ctx, side / 2, side * 0.42f, side * 0.18f, M_PI, 0, 0);
	CGContextStrokePath(ctx);

	UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:
			CGRectMake(side * 0.24f, side * 0.42f, side * 0.52f, side * 0.38f)
												   cornerRadius:side * 0.08f];
	[body fill];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)waveform:(NSData *)waveform size:(CGSize)size
               played:(CGFloat)played colour:(UIColor *)colour {
	if (!waveform.length || size.width <= 0 || size.height <= 0)
		return nil;

	int playedBucket = (int)(played * 20.0f);
	NSString *key = [NSString stringWithFormat:@"wave_%lu_%.0f_%d_%lu",
			(unsigned long)waveform.hash, size.width, playedBucket, (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	const uint8_t *bytes = (const uint8_t *)waveform.bytes;
	NSUInteger bits = waveform.length * 8 / 5;
	CGFloat barW = 2, gap = 1;
	NSUInteger bars = (NSUInteger)(size.width / (barW + gap));
	if (bars == 0){
		UIGraphicsEndImageContext();
		return nil;
	}

	for (NSUInteger i = 0; i < bars; i++){
		CGFloat value = 0.35f;
		if (bits > 0){
			NSUInteger index = i * bits / bars;
			NSUInteger bit = index * 5;
			NSUInteger byte = bit / 8;
			if (byte + 1 < waveform.length){
				uint16_t window = (uint16_t)((bytes[byte] | (bytes[byte + 1] << 8)) >> (bit % 8));
				value = (window & 0x1F) / 31.0f;
			}
		}

		CGFloat height = MAX(2.0f, value * size.height);
		CGFloat x = i * (barW + gap);
		CGRect bar = CGRectMake(x, TGCenteredOrigin(size.height, height), barW, height);

		CGFloat alpha = (i < bars * played) ? TGAlphaOpaque : 0.32f;
		[[colour colorWithAlphaComponent:alpha] set];
		UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:1];
		[rounded fill];
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing {
	return [self bubbleTailForColour:colour outgoing:outgoing borderColour:nil];
}

+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing borderColour:(UIColor *)borderColour {
	NSString *key = [NSString stringWithFormat:@"tail_%d_%lu_%lu", outgoing, (unsigned long)[colour hash], (unsigned long)[borderColour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat w = kTailWidth, h = kTailHeight;
	CGSize size = CGSizeMake(w, h);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	if (outgoing){
		CGContextMoveToPoint(ctx, 0, 0);
		CGContextAddCurveToPoint(ctx, w * 0.30f, h * 0.40f, w * 0.75f, h * 0.75f, w, h);
		CGContextAddLineToPoint(ctx, 0, h);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);

		if (borderColour) {
			[borderColour setStroke];
			CGContextSetLineWidth(ctx, TGIconStrokeFine);
			CGContextMoveToPoint(ctx, 0, 0.5f);
			CGContextAddCurveToPoint(ctx, w * 0.30f, h * 0.40f, w * 0.75f, h * 0.75f, w - 0.5f, h - 0.5f);
			CGContextAddLineToPoint(ctx, 0, h - 0.5f);
			CGContextStrokePath(ctx);
		}
	} else {
		CGContextMoveToPoint(ctx, w, 0);
		CGContextAddCurveToPoint(ctx, w * 0.70f, h * 0.40f, w * 0.25f, h * 0.75f, 0, h);
		CGContextAddLineToPoint(ctx, w, h);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);

		if (borderColour) {
			[borderColour setStroke];
			CGContextSetLineWidth(ctx, TGIconStrokeFine);
			CGContextMoveToPoint(ctx, w, 0.5f);
			CGContextAddCurveToPoint(ctx, w * 0.70f, h * 0.40f, w * 0.25f, h * 0.75f, 0.5f, h - 0.5f);
			CGContextAddLineToPoint(ctx, w, h - 0.5f);
			CGContextStrokePath(ctx);
		}
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)ticksWhite:(BOOL)white {
	UIColor *c = white ? [UIColor whiteColor] : [[TGTheme shared] ticksColour];
	return [self ticksColour:c read:YES];
}

+ (UIImage *)ticksColour:(UIColor *)c read:(BOOL)read {
	NSString *key = [NSString stringWithFormat:@"ticks_%lu_%d", (unsigned long)[c hash], read];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(15, 9);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetStrokeColorWithColor(ctx, c.CGColor);
	CGContextSetLineWidth(ctx, TGIconStrokeFine);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	if (read){
		CGContextMoveToPoint(ctx, 0.5f, 5.0f);
		CGContextAddLineToPoint(ctx, 3.0f, 7.6f);
		CGContextAddLineToPoint(ctx, 8.4f, 1.4f);
		CGContextStrokePath(ctx);
	}

	CGContextMoveToPoint(ctx, 6.0f, 5.0f);
	CGContextAddLineToPoint(ctx, 8.5f, 7.6f);
	CGContextAddLineToPoint(ctx, 14.0f, 1.4f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

@end
