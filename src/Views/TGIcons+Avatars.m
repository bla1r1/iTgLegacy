#import "TGIconsInternal.h"

#pragma mark - avatars

static UIImage *TGGlyphAvatar(CGFloat side, void (^draw)(CGContextRef ctx, CGFloat s)) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(ctx, 0.427f, 0.588f, 0.706f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));

	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
	draw(ctx, side);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@implementation TGIcons (Avatars)

+ (UIImage *)archiveAvatarOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"archiveAvatar_%.0f", side];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIImage *img = TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		CGFloat w = s * 0.46f, x = (s - w) / 2;
		CGContextFillRect(ctx, CGRectMake(x, s * 0.32f, w, s * 0.10f));
		CGContextFillRect(ctx, CGRectMake(x + s * 0.03f, s * 0.44f,
										  w - s * 0.06f, s * 0.24f));
		CGContextSetRGBFillColor(ctx, 0.427f, 0.588f, 0.706f, 1.0f);
		CGContextFillRect(ctx, CGRectMake(s * 0.44f, s * 0.50f, s * 0.12f, s * 0.05f));
	});
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)savedMessagesAvatarOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"savedAvatar_%.0f", side];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIImage *img = TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		CGContextMoveToPoint(ctx, s * 0.36f, s * 0.30f);
		CGContextAddLineToPoint(ctx, s * 0.64f, s * 0.30f);
		CGContextAddLineToPoint(ctx, s * 0.64f, s * 0.70f);
		CGContextAddLineToPoint(ctx, s * 0.50f, s * 0.58f);
		CGContextAddLineToPoint(ctx, s * 0.36f, s * 0.70f);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	});
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                       colourId:(int64_t)colourId
{
	static NSCache *avatarCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		avatarCache = [[NSCache alloc] init];
		avatarCache.countLimit = 200; // Keep up to 200 avatars in memory
	});

	BOOL isFlat = [TGTheme shared].isFlat;
	NSString *cacheKey = [NSString stringWithFormat:@"%@_%.1f_%lld_%d", initials ?: @"?", size, colourId, isFlat];
	UIImage *cached = [avatarCache objectForKey:cacheKey];
	if (cached) return cached;

	// Telegram's own placeholder colours, and its own mapping: the palette is
	// indexed through [0,7,4,1,6,3,5] so that the same person gets the same
	// colour here as in every other client.
	static NSArray *palette = nil;
	if (!palette)
		palette = @[@[@0.882f, @0.443f, @0.463f],   // red
					@[@0.929f, @0.659f, @0.424f],   // orange
					@[@0.651f, @0.584f, @0.906f],   // violet
					@[@0.482f, @0.784f, @0.384f],   // green
					@[@0.431f, @0.788f, @0.796f],   // cyan
					@[@0.396f, @0.667f, @0.867f],   // blue
					@[@0.933f, @0.478f, @0.682f],   // pink
					@[@0.882f, @0.443f, @0.463f]];  // the 8th slot repeats red
	static const NSUInteger order[7] = {0, 7, 4, 1, 6, 3, 5};
	NSArray *c = palette[order[(NSUInteger)llabs(colourId) % 7]];

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(ctx, [c[0] floatValue], [c[1] floatValue],
								  [c[2] floatValue], 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, size, size));

	if (!isFlat){
		// a glassy highlight across the top half
		CGContextSaveGState(ctx);
		CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, size, size));
		CGContextClip(ctx);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.20f);
		CGContextFillEllipseInRect(ctx,
				CGRectMake(-size * 0.2f, -size * 0.55f, size * 1.4f, size * 0.95f));
		CGContextRestoreGState(ctx);
	}

	NSString *text = initials.length ? initials : @"?";
	UIFont *font = [UIFont boldSystemFontOfSize:size * 0.4f];
	CGSize textSize = [text sizeWithFont:font];
	[[UIColor whiteColor] set];
	[text drawAtPoint:CGPointMake((size - textSize.width) / 2,
								  (size - textSize.height) / 2)
			 withFont:font];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	
	if (image) [avatarCache setObject:image forKey:cacheKey];
	return image;
}

/// Pre-decodes image onto offscreen bitmap context and scales to target size.
+ (UIImage *)decodedImage:(UIImage *)image
			  fittingSize:(CGSize)target
					 fill:(BOOL)fill
					scale:(CGFloat)scale
{
	if (!image)
		return nil;
	CGSize size = image.size;
	if (size.width < 1 || size.height < 1)
		return image;

	// Fill covers the box and comes back at exactly that size, cropped - a
	// nine-by-sixteen story thumbnail scaled to "cover" a 40pt square is still
	// 40x71, which then pushed the row it sat in out of shape. Fit sits inside
	// the box instead and keeps its own proportions (a photo in a bubble).
	if (fill && target.width > 0 && target.height > 0){
		CGFloat grow = MAX(target.width / size.width, target.height / size.height);
		CGSize drawn = CGSizeMake(size.width * grow, size.height * grow);
		UIGraphicsBeginImageContextWithOptions(target, NO, scale > 0 ? scale : 1.0f);
		[image drawInRect:CGRectMake((target.width - drawn.width) / 2,
									 (target.height - drawn.height) / 2,
									 drawn.width, drawn.height)];
		UIImage *cropped = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		return cropped ?: image;
	}

	if (target.width > 0 && target.height > 0){
		// Only ever shrink - upscaling here would cost memory and buy nothing.
		CGFloat shrink = MIN(target.width / size.width, target.height / size.height);
		if (shrink < 1.0f)
			size = CGSizeMake(MAX(1.0f, floorf(size.width * shrink)),
							  MAX(1.0f, floorf(size.height * shrink)));
	}

	UIGraphicsBeginImageContextWithOptions(size, NO, scale > 0 ? scale : 1.0f);
	[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
	UIImage *decoded = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return decoded ?: image;
}

+ (void)loadImageAtPath:(NSString *)path into:(UIImageView *)view {
	if (!path.length || !view)
		return;
	__weak UIImageView *weakView = view;
	CGSize target = view.bounds.size;
	CGFloat screenScale = [UIScreen mainScreen].scale;   // UIScreen is main-thread only
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		UIImage *decoded = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
									 fittingSize:target fill:YES scale:screenScale];
		if (!decoded)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			weakView.image = decoded;
		});
	});
}

+ (UIImage *)mapPinBadge {
	NSString *key = @"mapPinBadge";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;
	CGFloat w = 28.0f, h = 36.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat cx = w / 2.0f;
	CGFloat cy = 12.0f;
	CGFloat r = 10.0f;
	CGFloat tipX = cx;
	CGFloat tipY = 32.0f;
	CGFloat d = tipY - cy;

	CGFloat sinA = r / d;
	CGFloat cosA = sqrtf(1.0f - sinA * sinA);
	CGFloat ptR_x = cx + r * cosA;
	CGFloat ptR_y = cy + r * sinA;

	CGFloat angleR = asinf(sinA);
	CGFloat angleL = (CGFloat)M_PI - angleR;

	// Red teardrop pin body
	CGContextSetRGBFillColor(ctx, 0.95f, 0.26f, 0.21f, 1.0f);
	CGContextBeginPath(ctx);
	// Start at right tangent, arc over the top to left tangent
	CGContextAddArc(ctx, cx, cy, r, angleR, angleL, 1);
	// Line to bottom tip
	CGContextAddLineToPoint(ctx, tipX, tipY);
	// Line back to right tangent
	CGContextAddLineToPoint(ctx, ptR_x, ptR_y);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	// Inner white dot
	CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(cx - 3.8f, cy - 3.8f, 7.6f, 7.6f));

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)mapPlaceholderSize:(CGSize)size {
	NSString *key = [NSString stringWithFormat:@"mapPlaceholder-%.0f-%.0f", size.width, size.height];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;
	UIGraphicsBeginImageContextWithOptions(size, YES, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	// Background: soft map land color
	CGContextSetRGBFillColor(ctx, 0.93f, 0.92f, 0.88f, 1.0f);
	CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));
	// Green park area
	CGContextSetRGBFillColor(ctx, 0.82f, 0.88f, 0.82f, 1.0f);
	CGContextFillRect(ctx, CGRectMake(0, size.height * 0.45f, size.width * 0.42f, size.height * 0.55f));
	// White secondary streets
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextSetLineWidth(ctx, 5.0f);
	CGContextMoveToPoint(ctx, 0, size.height * 0.5f);
	CGContextAddLineToPoint(ctx, size.width, size.height * 0.4f);
	CGContextStrokePath(ctx);
	CGContextSetLineWidth(ctx, 3.5f);
	CGContextMoveToPoint(ctx, size.width * 0.35f, 0);
	CGContextAddLineToPoint(ctx, size.width * 0.45f, size.height);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, size.width * 0.75f, 0);
	CGContextAddLineToPoint(ctx, size.width * 0.65f, size.height);
	CGContextStrokePath(ctx);
	// Orange primary road
	CGContextSetRGBStrokeColor(ctx, 0.98f, 0.80f, 0.55f, 1.0f);
	CGContextSetLineWidth(ctx, 2.5f);
	CGContextMoveToPoint(ctx, 0, size.height * 0.5f);
	CGContextAddLineToPoint(ctx, size.width, size.height * 0.4f);
	CGContextStrokePath(ctx);
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

@end
