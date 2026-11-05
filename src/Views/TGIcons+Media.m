//
// TGIcons+Media.m
// Audio and media player vector icons.
//
#import "TGIconsInternal.h"
#import <objc/runtime.h>

/// The X on a cancel disc is cut out of the same circle the play glyph is:
/// arms start a third of the way in and the stroke is its own weight, not the
/// circle's.
static const CGFloat kCancelGlyphInset  = 0.32f;
static const CGFloat kCancelGlyphStroke = 0.075f;

/// Rounded copies already made of one image, most recent first. A picture
/// is usually shown at one size, but the same file can sit in a collage tile
/// and a single bubble at once; with one slot those two evicted each other
/// on every cell and the copy was redrawn - JPEG decode included - each time.
enum { kRoundedVariants = 4 };

typedef struct {
	CGSize size;
	CGFloat radius;
	UIRectCorner corners;
} TGRoundedKey;

@interface TGRoundedVariants : NSObject {
@public
	TGRoundedKey keys[kRoundedVariants];
	UIImage *images[kRoundedVariants];
}
@end
@implementation TGRoundedVariants
@end

static char kRoundedVariantKey;

@implementation TGIcons (Media)

static BOOL TGRoundable(UIImage *image, CGSize size) {
	return image && !image.images.count && size.width >= 1 && size.height >= 1
			&& image.size.width >= 1 && image.size.height >= 1;
}

static UIImage *TGRoundedLookup(UIImage *image, CGSize size, CGFloat radius, UIRectCorner corners) {
	TGRoundedVariants *v = objc_getAssociatedObject(image, &kRoundedVariantKey);
	for (int i = 0; v && i < kRoundedVariants; i++) {
		TGRoundedKey k = v->keys[i];
		if (v->images[i] && CGSizeEqualToSize(k.size, size) && k.radius == radius && k.corners == corners)
			return v->images[i];
	}
	return nil;
}

/// Any thread: UIGraphics image contexts are per-thread since iOS 4.
static UIImage *TGRoundedRender(UIImage *image, CGSize size, CGFloat radius, UIRectCorner corners) {
	CGRect box = CGRectMake(0, 0, size.width, size.height);
	CGFloat scale = (image.scale > 0.0f) ? image.scale : TGMainScreenScale();
	UIGraphicsBeginImageContextWithOptions(size, NO, scale);
	if (radius > 0)
		[[UIBezierPath bezierPathWithRoundedRect:box byRoundingCorners:corners
									 cornerRadii:CGSizeMake(radius, radius)] addClip];
	CGFloat k = MAX(size.width / image.size.width, size.height / image.size.height);
	CGSize fill = CGSizeMake(image.size.width * k, image.size.height * k);
	[image drawInRect:CGRectMake(TGHalf(size.width - fill.width), TGHalf(size.height - fill.height),
								 fill.width, fill.height)];
	UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return out;
}

/// Main thread only, like the lookup: the slots are not locked.
static void TGRoundedStore(UIImage *image, CGSize size, CGFloat radius, UIRectCorner corners, UIImage *out) {
	TGRoundedVariants *v = objc_getAssociatedObject(image, &kRoundedVariantKey);
	if (!v) {
		v = [[TGRoundedVariants alloc] init];
		objc_setAssociatedObject(image, &kRoundedVariantKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	for (int i = kRoundedVariants - 1; i > 0; i--) {
		v->keys[i] = v->keys[i - 1];
		v->images[i] = v->images[i - 1];
	}
	v->keys[0] = (TGRoundedKey){ size, radius, corners };
	v->images[0] = out;
}

+ (UIImage *)roundedImage:(UIImage *)image size:(CGSize)size radius:(CGFloat)radius
				  corners:(UIRectCorner)corners {
	if (!TGRoundable(image, size))
		return image;
	UIImage *hit = TGRoundedLookup(image, size, radius, corners);
	if (hit)
		return hit;
	UIImage *out = TGRoundedRender(image, size, radius, corners);
	if (!out)
		return image;
	if ([NSThread isMainThread])
		TGRoundedStore(image, size, radius, corners, out);
	return out;
}

static char kAwaitedKey;

+ (void)setRoundedImage:(UIImage *)image inView:(UIImageView *)view size:(CGSize)size
				 radius:(CGFloat)radius {
	UIRectCorner corners = UIRectCornerAllCorners;
	if (!TGRoundable(image, size)) {
		objc_setAssociatedObject(view, &kAwaitedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		view.image = image;
		return;
	}
	UIImage *hit = TGRoundedLookup(image, size, radius, corners);
	objc_setAssociatedObject(view, &kAwaitedKey, hit ? nil : image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	view.image = hit;
	if (hit)
		return;

	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("org.legacy.itg.round", DISPATCH_QUEUE_SERIAL);
	});
	__weak UIImageView *weakView = view;
	dispatch_async(queue, ^{
		UIImage *out = TGRoundedRender(image, size, radius, corners);
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!out)
				return;
			TGRoundedStore(image, size, radius, corners, out);
			UIImageView *v = weakView;
			// The row may have been reused for another message meanwhile.
			if (v && objc_getAssociatedObject(v, &kAwaitedKey) == image) {
				objc_setAssociatedObject(v, &kAwaitedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				v.image = out;
			}
		});
	});
}

+ (UIImage *)play {
	return [self iconNamed:@"play" draw:^(CGContextRef ctx, CGFloat s){
		CGContextMoveToPoint(ctx, 8, 5);
		CGContextAddLineToPoint(ctx, s - 6, TGHalf(s));
		CGContextAddLineToPoint(ctx, 8, s - 5);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)pause {
	return [self iconNamed:@"pause" draw:^(CGContextRef ctx, CGFloat s){
		CGFloat w = s * 0.18f;
		CGContextFillRect(ctx, CGRectMake(8, 6, w, s - 12));
		CGContextFillRect(ctx, CGRectMake(s - 8 - w, 6, w, s - 12));
	}];
}

+ (UIImage *)previousTrack {
	return [self iconNamed:@"previousTrack" draw:^(CGContextRef ctx, CGFloat s){
		CGContextMoveToPoint(ctx, s - 7, 6);
		CGContextAddLineToPoint(ctx, s * 0.42f, TGHalf(s));
		CGContextAddLineToPoint(ctx, s - 7, s - 6);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
		CGContextFillRect(ctx, CGRectMake(s * 0.3f, 6, s * 0.1f, s - 12));
	}];
}

+ (UIImage *)nextTrack {
	return [self iconNamed:@"nextTrack" draw:^(CGContextRef ctx, CGFloat s){
		CGContextMoveToPoint(ctx, 7, 6);
		CGContextAddLineToPoint(ctx, s * 0.58f, TGHalf(s));
		CGContextAddLineToPoint(ctx, 7, s - 6);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
		CGContextFillRect(ctx, CGRectMake(s * 0.6f, 6, s * 0.1f, s - 12));
	}];
}

+ (UIImage *)repeatModeIcon:(NSInteger)mode {
	NSString *name = [NSString stringWithFormat:@"repeat-%ld", (long)mode];
	return [self iconNamed:name draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		CGFloat left = 6.0f, right = s - 6.0f, top = 8.0f, bottom = s - 8.0f;
		CGFloat rad = 4.0f;

		// Top path going right with arrowhead
		CGContextMoveToPoint(ctx, left + rad, top);
		CGContextAddLineToPoint(ctx, right - rad, top);
		CGContextAddArcToPoint(ctx, right, top, right, top + rad, rad);
		CGContextAddLineToPoint(ctx, right, top + 4.0f);
		CGContextStrokePath(ctx);

		// Top arrow head
		CGContextMoveToPoint(ctx, right - 3.5f, top - 3.0f);
		CGContextAddLineToPoint(ctx, right + 1.0f, top);
		CGContextAddLineToPoint(ctx, right - 3.5f, top + 3.0f);
		CGContextStrokePath(ctx);

		// Bottom path going left with arrowhead
		CGContextMoveToPoint(ctx, right - rad, bottom);
		CGContextAddLineToPoint(ctx, left + rad, bottom);
		CGContextAddArcToPoint(ctx, left, bottom, left, bottom - rad, rad);
		CGContextAddLineToPoint(ctx, left, bottom - 4.0f);
		CGContextStrokePath(ctx);

		// Bottom arrow head
		CGContextMoveToPoint(ctx, left + 3.5f, bottom - 3.0f);
		CGContextAddLineToPoint(ctx, left - 1.0f, bottom);
		CGContextAddLineToPoint(ctx, left + 3.5f, bottom + 3.0f);
		CGContextStrokePath(ctx);

		if (mode == 2) {
			// Numeral '1' in the center
			CGContextSetLineWidth(ctx, TGIconStrokeFine);
			CGContextMoveToPoint(ctx, TGHalf(s) - 2.0f, TGHalf(s) - 2.0f);
			CGContextAddLineToPoint(ctx, TGHalf(s), TGHalf(s) - 4.0f);
			CGContextAddLineToPoint(ctx, TGHalf(s), TGHalf(s) + 4.0f);
			CGContextStrokePath(ctx);
		}
	}];
}

+ (UIImage *)shuffleIconActive:(BOOL)active {
	NSString *name = [NSString stringWithFormat:@"shuffle-%d", active ? 1 : 0];
	return [self iconNamed:name draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		CGFloat left = 6.0f, right = s - 6.0f;
		CGFloat mid = TGHalf(s);
		CGFloat top = 8.0f, bottom = s - 8.0f;

		// Diagonal 1: bottom-left to top-right
		CGContextMoveToPoint(ctx, left, bottom);
		CGContextAddCurveToPoint(ctx, mid - 2.0f, bottom, mid + 2.0f, top, right, top);
		CGContextStrokePath(ctx);

		// Arrow 1 head
		CGContextMoveToPoint(ctx, right - 3.5f, top - 3.0f);
		CGContextAddLineToPoint(ctx, right + 1.0f, top);
		CGContextAddLineToPoint(ctx, right - 3.5f, top + 3.0f);
		CGContextStrokePath(ctx);

		// Diagonal 2: top-left to bottom-right
		CGContextMoveToPoint(ctx, left, top);
		CGContextAddCurveToPoint(ctx, mid - 4.0f, top, mid - 3.0f, mid - 2.0f, mid - 2.0f, mid);
		CGContextStrokePath(ctx);

		CGContextMoveToPoint(ctx, mid + 2.0f, mid + 2.0f);
		CGContextAddCurveToPoint(ctx, mid + 3.0f, bottom - 1.0f, mid + 4.0f, bottom, right, bottom);
		CGContextStrokePath(ctx);

		// Arrow 2 head
		CGContextMoveToPoint(ctx, right - 3.5f, bottom - 3.0f);
		CGContextAddLineToPoint(ctx, right + 1.0f, bottom);
		CGContextAddLineToPoint(ctx, right - 3.5f, bottom + 3.0f);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)volumeMin {
	return [self iconNamed:@"volumeMin" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStrokeFine);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		CGFloat mid = TGHalf(s);
		CGContextMoveToPoint(ctx, 6.0f, mid - 3.5f);
		CGContextAddLineToPoint(ctx, 9.5f, mid - 3.5f);
		CGContextAddLineToPoint(ctx, 14.5f, mid - 7.5f);
		CGContextAddLineToPoint(ctx, 14.5f, mid + 7.5f);
		CGContextAddLineToPoint(ctx, 9.5f, mid + 3.5f);
		CGContextAddLineToPoint(ctx, 6.0f, mid + 3.5f);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);

		CGContextAddArc(ctx, 15.0f, mid, 5.0f, -0.6f, 0.6f, 0);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)volumeMax {
	return [self iconNamed:@"volumeMax" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStrokeFine);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		CGFloat mid = TGHalf(s);
		CGContextMoveToPoint(ctx, 5.0f, mid - 3.5f);
		CGContextAddLineToPoint(ctx, 8.5f, mid - 3.5f);
		CGContextAddLineToPoint(ctx, 13.5f, mid - 7.5f);
		CGContextAddLineToPoint(ctx, 13.5f, mid + 7.5f);
		CGContextAddLineToPoint(ctx, 8.5f, mid + 3.5f);
		CGContextAddLineToPoint(ctx, 5.0f, mid + 3.5f);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);

		CGContextAddArc(ctx, 14.0f, mid, 5.0f, -0.65f, 0.65f, 0);
		CGContextStrokePath(ctx);
		CGContextAddArc(ctx, 14.0f, mid, 9.0f, -0.65f, 0.65f, 0);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)queueList {
	return [self iconNamed:@"queueList" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineCap(ctx, kCGLineCapRound);

		CGFloat x1 = 10.0f, x2 = s - 6.0f;
		CGFloat y1 = 8.0f, y2 = TGHalf(s), y3 = s - 8.0f;

		CGContextMoveToPoint(ctx, x1, y1);
		CGContextAddLineToPoint(ctx, x2, y1);
		CGContextMoveToPoint(ctx, x1, y2);
		CGContextAddLineToPoint(ctx, x2, y2);
		CGContextMoveToPoint(ctx, x1, y3);
		CGContextAddLineToPoint(ctx, x2, y3);
		CGContextStrokePath(ctx);

		CGFloat dotR = 1.6f;
		CGContextFillEllipseInRect(ctx, CGRectMake(5.5f - dotR, y1 - dotR, dotR * 2, dotR * 2));
		CGContextFillEllipseInRect(ctx, CGRectMake(5.5f - dotR, y2 - dotR, dotR * 2, dotR * 2));
		CGContextFillEllipseInRect(ctx, CGRectMake(5.5f - dotR, y3 - dotR, dotR * 2, dotR * 2));
	}];
}

+ (UIImage *)mediaDiscOfSide:(CGFloat)side playing:(BOOL)playing {
	NSString *key = [NSString stringWithFormat:@"mediaDisc_%.0f_%d", side, playing];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// The disc is the icon itself (a circle with the glyph cut out), filled
	// with the disc's gradient; the circle is 20 of its 24 units.
	CGRect box = CGRectInset(CGRectMake(0, 0, side, side), -side / 10, -side / 10);
	TGIconAddPath(ctx, playing ? "mediaDiscPause" : "mediaDiscPlay", box);
	CGContextClip(ctx);
	CGFloat colors[8] = {
		0.52f, 0.78f, 0.96f, 1.0f,
		0.28f, 0.54f, 0.78f, 1.0f
	};
	CGFloat locs[2] = {0.0f, 1.0f};
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, colors, locs, 2);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, side), 0);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

/// The same disc and the same gradient. The circle is the media disc's own
/// 20-of-24 path expanded to the image, so the X is the only thing that
/// differs: it is drawn clear, which leaves the bubble showing through it the
/// way the play triangle does.
+ (UIImage *)cancelDiscOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"cancelDisc_%.0f", side];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, side, side));
	CGContextClip(ctx);
	CGFloat colors[8] = {
		0.52f, 0.78f, 0.96f, 1.0f,
		0.28f, 0.54f, 0.78f, 1.0f
	};
	CGFloat locs[2] = {0.0f, 1.0f};
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, colors, locs, 2);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, side), 0);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	CGFloat inset = side * kCancelGlyphInset;
	CGFloat stroke = side * kCancelGlyphStroke;
	CGContextSetBlendMode(ctx, kCGBlendModeClear);
	CGContextSetLineWidth(ctx, stroke);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextMoveToPoint(ctx, inset, inset);
	CGContextAddLineToPoint(ctx, side - inset, side - inset);
	CGContextMoveToPoint(ctx, side - inset, inset);
	CGContextAddLineToPoint(ctx, inset, side - inset);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)fileDiscOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"fileDisc_%.0f", side];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat colors[8] = {
		0.56f, 0.62f, 0.70f, 1.0f,
		0.36f, 0.42f, 0.50f, 1.0f
	};
	CGFloat locs[2] = {0.0f, 1.0f};
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, colors, locs, 2);
	CGContextSaveGState(ctx);
	CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, side, side));
	CGContextClip(ctx);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, side), 0);
	CGContextRestoreGState(ctx);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.40f);
	CGContextSetLineWidth(ctx, TGIconStrokeFine);
	CGContextStrokeEllipseInRect(ctx, CGRectInset(CGRectMake(0, 0, side, side), 0.5f, 0.5f));

	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	if (TGIconAddPath(ctx, "fileDisc", CGRectInset(CGRectMake(0, 0, side, side), side * 0.2f, side * 0.2f)))
		CGContextFillPath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

@end
