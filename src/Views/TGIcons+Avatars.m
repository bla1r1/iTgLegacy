#import "TGIconsInternal.h"
#import "TGStyle.h"
#import <ImageIO/ImageIO.h>

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

+ (UIColor *)nameColourForId:(int64_t)colourId dark:(BOOL)dark {
	// Their name colours, in the same slots as the placeholder palette below
	// and through the same [0,7,4,1,6,3,5] order, so a name never disagrees
	// with the circle beside it. The eighth slot repeats red there too.
	static const uint32_t light[8] = {0xCC5049, 0xD67722, 0x955CDB, 0x40A920,
									  0x309EBA, 0x368AD1, 0xC7508B, 0xCC5049};
	static const uint32_t night[8] = {0xFC5C51, 0xFA790F, 0x895DD5, 0x0FB297,
									  0x00C1A6, 0x3CA5EC, 0xD54FAF, 0xFC5C51};
	static const NSUInteger order[7] = {0, 7, 4, 1, 6, 3, 5};
	uint32_t c = (dark ? night : light)[order[(NSUInteger)llabs(colourId) % 7]];
	return [UIColor colorWithRed:((c >> 16) & 0xFF) / 255.0f
						   green:((c >> 8) & 0xFF) / 255.0f
							blue:(c & 0xFF) / 255.0f
						   alpha:1.0f];
}

+ (UIImage *)archiveAvatarOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"archiveAvatar_%.0f", side];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIImage *img = TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		CGFloat w = s * 0.46f, x = TGHalf(s - w);
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

+ (NSString *)initialsForTitle:(NSString *)title {
	if (!title.length) return @"?";
	NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length) return @"?";

	// Find the first alphanumeric letter, skipping emojis and leading symbols
	NSString *firstLetter = nil;
	for (NSUInteger i = 0; i < trimmed.length; ) {
		NSRange r = [trimmed rangeOfComposedCharacterSequenceAtIndex:i];
		NSString *glyph = [trimmed substringWithRange:r];
		if (r.length == 1) {
			unichar c = [glyph characterAtIndex:0];
			if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
				firstLetter = glyph.uppercaseString;
				break;
			}
		}
		i += r.length;
	}

	if (!firstLetter) {
		// Fallback to first composed sequence safely without splitting surrogate pairs
		NSRange r = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
		return [trimmed substringWithRange:r];
	}

	// Try to find a second word's initial
	NSArray *words = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (words.count > 1) {
		for (NSUInteger w = 1; w < words.count; w++) {
			NSString *wStr = words[w];
			for (NSUInteger j = 0; j < wStr.length; ) {
				NSRange wr = [wStr rangeOfComposedCharacterSequenceAtIndex:j];
				NSString *wGlyph = [wStr substringWithRange:wr];
				if (wr.length == 1 && [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[wGlyph characterAtIndex:0]]) {
					return [NSString stringWithFormat:@"%@%@", firstLetter, wGlyph.uppercaseString];
				}
				j += wr.length;
			}
		}
	}
	return firstLetter;
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

	NSUInteger slot = order[(NSUInteger)llabs(colourId) % 7];
	if (isFlat){
		// Their current placeholders: the same seven hues as a gradient, lighter
		// at the top. Drawn into the circle the plain colour used to fill.
		static const uint32_t top[8]    = {0xFF845E, 0xFEBB5B, 0xB694F9, 0x9AD164,
										   0x53EDD6, 0x5CAFFA, 0xFF8AAC, 0xFF845E};
		static const uint32_t bottom[8] = {0xD45246, 0xF68136, 0x6C61DF, 0x46BA43,
										   0x28C9B7, 0x408ACF, 0xD95574, 0xD45246};
		CGFloat components[8] = {
			((top[slot] >> 16) & 0xFF) / 255.0f, ((top[slot] >> 8) & 0xFF) / 255.0f,
			(top[slot] & 0xFF) / 255.0f, 1.0f,
			((bottom[slot] >> 16) & 0xFF) / 255.0f, ((bottom[slot] >> 8) & 0xFF) / 255.0f,
			(bottom[slot] & 0xFF) / 255.0f, 1.0f,
		};
		CGFloat locations[2] = {0.0f, 1.0f};
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, locations, 2);
		CGContextSaveGState(ctx);
		CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, size, size));
		CGContextClip(ctx);
		CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, 0), CGPointMake(0, size), 0);
		CGContextRestoreGState(ctx);
		CGGradientRelease(gradient);
		CGColorSpaceRelease(space);
	} else {
		CGContextSetRGBFillColor(ctx, [c[0] floatValue], [c[1] floatValue],
									  [c[2] floatValue], 1.0f);
		CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, size, size));
	}

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
	UIFont *font = TGFontMediumAtSize(text.length > 1 ? size * 0.35f : size * 0.42f);
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

/// Pre-decodes image onto offscreen bitmap context and scales to target size using ImageIO DCT downsampling.
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

	CGFloat effectiveScale = (scale > 0.0f) ? scale : 1.0f;

	// Try ImageIO DCT downsampling via provider if available
	CGImageRef cgImage = image.CGImage;
	if (cgImage) {
		CGDataProviderRef provider = CGImageGetDataProvider(cgImage);
		if (provider) {
			CGImageSourceRef source = CGImageSourceCreateWithDataProvider(provider, NULL);
			if (source) {
				if (CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == kCGImageStatusComplete) {
					CGFloat maxPixelSize = 0.0f;
					if (target.width > 0 && target.height > 0) {
						if (fill) {
							CGFloat grow = MAX(target.width / size.width, target.height / size.height);
							if (grow >= 1.0f)
								maxPixelSize = MAX(size.width, size.height) * effectiveScale;
							else
								maxPixelSize = ceilf(MAX(size.width * grow, size.height * grow) * effectiveScale);
						} else {
							CGFloat shrink = MIN(target.width / size.width, target.height / size.height);
							if (shrink < 1.0f)
								maxPixelSize = ceilf(MAX(target.width, target.height) * effectiveScale);
							else
								maxPixelSize = MAX(size.width, size.height) * effectiveScale;
						}
					} else {
						maxPixelSize = MAX(size.width, size.height) * effectiveScale;
					}

					if (maxPixelSize < 1.0f) maxPixelSize = 1.0f;

					NSDictionary *options = @{
						(id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
						(id)kCGImageSourceThumbnailMaxPixelSize          : @((int)maxPixelSize),
						(id)kCGImageSourceCreateThumbnailWithTransform   : @YES,
						(id)kCGImageSourceShouldCacheImmediately        : @YES
					};

					CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
					CFRelease(source);

					if (thumb) {
						if (fill && target.width > 0 && target.height > 0) {
							size_t tw = CGImageGetWidth(thumb);
							size_t th = CGImageGetHeight(thumb);
							CGFloat reqW = target.width * effectiveScale;
							CGFloat reqH = target.height * effectiveScale;
							if (tw > reqW + 1 || th > reqH + 1) {
								CGFloat cropW = MIN((CGFloat)tw, reqW);
								CGFloat cropH = MIN((CGFloat)th, reqH);
								CGFloat cropX = TGHalf((CGFloat)tw - cropW);
								CGFloat cropY = TGHalf((CGFloat)th - cropH);
								CGImageRef cropped = CGImageCreateWithImageInRect(thumb, CGRectMake(cropX, cropY, cropW, cropH));
								CGImageRelease(thumb);
								thumb = cropped;
							}
						}

						UIImage *decodedThumb = [UIImage imageWithCGImage:thumb scale:effectiveScale orientation:UIImageOrientationUp];
						CGImageRelease(thumb);
						return decodedThumb;
					}
				} else {
					CFRelease(source);
				}
			}
		}
	}

	// Fallback to offscreen context drawing
	if (fill && target.width > 0 && target.height > 0){
		CGFloat grow = MAX(target.width / size.width, target.height / size.height);
		CGSize drawn = CGSizeMake(size.width * grow, size.height * grow);
		UIGraphicsBeginImageContextWithOptions(target, NO, effectiveScale);
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

	UIGraphicsBeginImageContextWithOptions(size, NO, effectiveScale);
	[image drawInRect:CGRectMake(0, 0, size.width, size.height)];
	UIImage *decoded = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return decoded ?: image;
}

+ (UIImage *)decodedImageAtPath:(NSString *)path
					fittingSize:(CGSize)target
						   fill:(BOOL)fill
						  scale:(CGFloat)scale
{
	if (!path.length)
		return nil;

	NSURL *url = [NSURL fileURLWithPath:path];
	CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
	if (!source || CGImageSourceGetCount(source) == 0) {
		if (source) CFRelease(source);
		return [self decodedImage:[UIImage imageWithContentsOfFile:path] fittingSize:target fill:fill scale:scale];
	}

	CGFloat effectiveScale = (scale > 0.0f) ? scale : 1.0f;
	CGFloat maxPixelSize = 0.0f;

	CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
	CGFloat origW = 0, origH = 0;
	if (props) {
		CFNumberRef wNum = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
		CFNumberRef hNum = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
		if (wNum) CFNumberGetValue(wNum, kCFNumberCGFloatType, &origW);
		if (hNum) CFNumberGetValue(hNum, kCFNumberCGFloatType, &origH);
		CFRelease(props);
	}

	if (origW < 1 || origH < 1) {
		CFRelease(source);
		return [self decodedImage:[UIImage imageWithContentsOfFile:path] fittingSize:target fill:fill scale:scale];
	}

	if (target.width > 0 && target.height > 0) {
		if (fill) {
			CGFloat grow = MAX(target.width / origW, target.height / origH);
			if (grow >= 1.0f)
				maxPixelSize = MAX(origW, origH) * effectiveScale;
			else
				maxPixelSize = ceilf(MAX(origW * grow, origH * grow) * effectiveScale);
		} else {
			CGFloat shrink = MIN(target.width / origW, target.height / origH);
			if (shrink < 1.0f)
				maxPixelSize = ceilf(MAX(target.width, target.height) * effectiveScale);
			else
				maxPixelSize = MAX(origW, origH) * effectiveScale;
		}
	} else {
		maxPixelSize = MAX(origW, origH) * effectiveScale;
	}

	if (maxPixelSize < 1.0f) maxPixelSize = 1.0f;

	NSDictionary *options = @{
		(id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
		(id)kCGImageSourceThumbnailMaxPixelSize          : @((int)maxPixelSize),
		(id)kCGImageSourceCreateThumbnailWithTransform   : @YES,
		(id)kCGImageSourceShouldCacheImmediately        : @YES
	};

	CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
	CFRelease(source);

	if (!thumb)
		return [self decodedImage:[UIImage imageWithContentsOfFile:path] fittingSize:target fill:fill scale:scale];

	if (fill && target.width > 0 && target.height > 0) {
		size_t tw = CGImageGetWidth(thumb);
		size_t th = CGImageGetHeight(thumb);
		CGFloat reqW = target.width * effectiveScale;
		CGFloat reqH = target.height * effectiveScale;
		if (tw > reqW + 1 || th > reqH + 1) {
			CGFloat cropW = MIN((CGFloat)tw, reqW);
			CGFloat cropH = MIN((CGFloat)th, reqH);
			CGFloat cropX = TGHalf((CGFloat)tw - cropW);
			CGFloat cropY = TGHalf((CGFloat)th - cropH);
			CGImageRef cropped = CGImageCreateWithImageInRect(thumb, CGRectMake(cropX, cropY, cropW, cropH));
			CGImageRelease(thumb);
			thumb = cropped;
		}
	}

	UIImage *res = [UIImage imageWithCGImage:thumb scale:effectiveScale orientation:UIImageOrientationUp];
	CGImageRelease(thumb);
	return res;
}

+ (void)loadImageAtPath:(NSString *)path into:(UIImageView *)view {
	if (!path.length || !view)
		return;
	__weak UIImageView *weakView = view;
	CGSize target = view.bounds.size;
	CGFloat screenScale = [UIScreen mainScreen].scale;   // UIScreen is main-thread only
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		UIImage *decoded = [TGIcons decodedImageAtPath:path fittingSize:target fill:YES scale:screenScale];
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

	CGFloat cx = TGHalf(w);
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

+ (UIImage *)thumbsUpSticker {
	NSString *key = @"sticker_thumbs_up";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat side = 130.0f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat bX = 15.0f, bY = 15.0f, bW = 100.0f, bH = 100.0f;
	UIBezierPath *badge = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(bX, bY, bW, bH)
													 cornerRadius:26.0f];

	CGContextSaveGState(ctx);
	CGContextSetShadowWithColor(ctx, CGSizeMake(0.0f, 4.0f), 8.0f, [UIColor blackColor].CGColor);
	CGContextSetRGBFillColor(ctx, 0.05f, 0.45f, 0.85f, 1.0f);
	[badge fill];
	CGContextRestoreGState(ctx);

	CGContextSaveGState(ctx);
	[badge addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	const CGFloat compBadge[] = {
		0.18f, 0.72f, 0.98f, 1.0f,
		0.02f, 0.42f, 0.86f, 1.0f
	};
	CGGradientRef gradBadge = CGGradientCreateWithColorComponents(cs, compBadge, NULL, 2);
	CGContextDrawLinearGradient(ctx, gradBadge, CGPointMake(bX, bY), CGPointMake(bX, bY + bH), 0);
	CGGradientRelease(gradBadge);

	UIBezierPath *gloss = [UIBezierPath bezierPath];
	[gloss moveToPoint:CGPointMake(bX, bY)];
	[gloss addLineToPoint:CGPointMake(bX + bW, bY)];
	[gloss addLineToPoint:CGPointMake(bX + bW, bY + TGHalf(bH))];
	[gloss addCurveToPoint:CGPointMake(bX, bY + TGHalf(bH) + 10.0f)
			 controlPoint1:CGPointMake(bX + bW * 0.75f, bY + TGHalf(bH) - 10.0f)
			 controlPoint2:CGPointMake(bX + bW * 0.25f, bY + TGHalf(bH) + 12.0f)];
	[gloss closePath];
	const CGFloat compGloss[] = {
		1.0f, 1.0f, 1.0f, 0.48f,
		1.0f, 1.0f, 1.0f, 0.06f
	};
	CGGradientRef gradGloss = CGGradientCreateWithColorComponents(cs, compGloss, NULL, 2);
	CGContextSaveGState(ctx);
	[gloss addClip];
	CGContextDrawLinearGradient(ctx, gradGloss, CGPointMake(bX, bY), CGPointMake(bX, bY + TGHalf(bH) + 10.0f), 0);
	CGGradientRelease(gradGloss);
	CGContextRestoreGState(ctx);

	CGContextRestoreGState(ctx);

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.92f);
	badge.lineWidth = 3.5f;
	[badge stroke];

	CGContextSaveGState(ctx);
	CGContextSetShadowWithColor(ctx, CGSizeMake(0.0f, 2.0f), 3.0f, [UIColor blackColor].CGColor);
	CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);

	UIBezierPath *palm = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(46.0f, 52.0f, 40.0f, 36.0f)
													cornerRadius:7.0f];
	[palm fill];

	UIBezierPath *thumb = [UIBezierPath bezierPath];
	[thumb moveToPoint:CGPointMake(46.0f, 62.0f)];
	[thumb addLineToPoint:CGPointMake(46.0f, 38.0f)];
	[thumb addArcWithCenter:CGPointMake(53.0f, 38.0f) radius:7.0f startAngle:(CGFloat)M_PI endAngle:0 clockwise:YES];
	[thumb addLineToPoint:CGPointMake(60.0f, 55.0f)];
	[thumb closePath];
	[thumb fill];

	CGContextSetRGBStrokeColor(ctx, 0.05f, 0.40f, 0.80f, 0.55f);
	CGContextSetLineWidth(ctx, 1.5f);
	for (int f = 1; f <= 3; f++) {
		CGFloat fY = 52.0f + f * 9.0f;
		CGContextMoveToPoint(ctx, 70.0f, fY);
		CGContextAddLineToPoint(ctx, 84.0f, fY);
		CGContextStrokePath(ctx);
	}

	UIBezierPath *cuff = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(40.0f, 76.0f, 12.0f, 20.0f)
													cornerRadius:3.0f];
	CGContextSetRGBFillColor(ctx, 0.90f, 0.95f, 1.0f, 0.95f);
	[cuff fill];

	CGContextRestoreGState(ctx);
	CGColorSpaceRelease(cs);

	UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, res);
	return res;
}

+ (UIImage *)goldStarSticker {
	NSString *key = @"sticker_gold_star";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat side = 130.0f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGPoint center = CGPointMake(TGHalf(side), TGHalf(side));
	CGFloat rOuter = 52.0f;
	CGFloat rInner = 22.0f;

	CGPoint tips[5];
	CGPoint inners[5];
	for (int i = 0; i < 5; i++) {
		CGFloat aOuter = (CGFloat)(-M_PI_2 + i * 2.0 * M_PI / 5.0);
		CGFloat aInner = (CGFloat)(aOuter + M_PI / 5.0);
		tips[i] = CGPointMake(center.x + rOuter * cosf(aOuter), center.y + rOuter * sinf(aOuter));
		inners[i] = CGPointMake(center.x + rInner * cosf(aInner), center.y + rInner * sinf(aInner));
	}

	UIBezierPath *starOutline = [UIBezierPath bezierPath];
	[starOutline moveToPoint:tips[0]];
	for (int i = 0; i < 5; i++) {
		[starOutline addLineToPoint:inners[i]];
		[starOutline addLineToPoint:tips[(i + 1) % 5]];
	}
	[starOutline closePath];

	CGContextSaveGState(ctx);
	CGContextSetShadowWithColor(ctx, CGSizeMake(0.0f, 4.0f), 7.0f, [UIColor blackColor].CGColor);
	CGContextSetRGBFillColor(ctx, 0.60f, 0.35f, 0.0f, 1.0f);
	[starOutline fill];
	CGContextRestoreGState(ctx);

	for (int i = 0; i < 5; i++) {
		int prevInner = (i + 4) % 5;
		UIBezierPath *leftFacet = [UIBezierPath bezierPath];
		[leftFacet moveToPoint:center];
		[leftFacet addLineToPoint:inners[prevInner]];
		[leftFacet addLineToPoint:tips[i]];
		[leftFacet closePath];

		UIBezierPath *rightFacet = [UIBezierPath bezierPath];
		[rightFacet moveToPoint:center];
		[rightFacet addLineToPoint:tips[i]];
		[rightFacet addLineToPoint:inners[i]];
		[rightFacet closePath];

		CGFloat lBri = 0.85f + (i == 0 || i == 4 ? 0.12f : 0.0f);
		CGContextSetRGBFillColor(ctx, 1.0f * lBri, 0.82f * lBri, 0.15f * lBri, 1.0f);
		[leftFacet fill];

		CGFloat rBri = 0.65f - (i == 1 || i == 2 ? 0.12f : 0.0f);
		CGContextSetRGBFillColor(ctx, 0.95f * rBri, 0.68f * rBri, 0.05f * rBri, 1.0f);
		[rightFacet fill];
	}

	CGContextSetRGBStrokeColor(ctx, 1.0f, 0.98f, 0.70f, 0.85f);
	starOutline.lineWidth = 1.5f;
	[starOutline stroke];

	for (int i = 0; i < 5; i++) {
		if (i == 0 || i == 1 || i == 4) {
			CGPoint p = tips[i];
			CGContextSaveGState(ctx);
			CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 0.95f);
			UIBezierPath *glint = [UIBezierPath bezierPath];
			[glint moveToPoint:CGPointMake(p.x, p.y - 5.0f)];
			[glint addLineToPoint:CGPointMake(p.x + 1.8f, p.y)];
			[glint addLineToPoint:CGPointMake(p.x, p.y + 5.0f)];
			[glint addLineToPoint:CGPointMake(p.x - 1.8f, p.y)];
			[glint closePath];
			[glint fill];

			UIBezierPath *glintH = [UIBezierPath bezierPath];
			[glintH moveToPoint:CGPointMake(p.x - 5.0f, p.y)];
			[glintH addLineToPoint:CGPointMake(p.x, p.y + 1.8f)];
			[glintH addLineToPoint:CGPointMake(p.x + 5.0f, p.y)];
			[glintH addLineToPoint:CGPointMake(p.x - 1.8f, p.y)];
			[glintH closePath];
			[glintH fill];
			CGContextRestoreGState(ctx);
		}
	}

	UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, res);
	return res;
}

+ (UIImage *)cinemaSticker {
	NSString *key = @"sticker_cinema";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat side = 130.0f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect bodyRect = CGRectMake(20.0f, 48.0f, 90.0f, 62.0f);
	UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:bodyRect cornerRadius:10.0f];

	CGContextSaveGState(ctx);
	CGContextSetShadowWithColor(ctx, CGSizeMake(0.0f, 4.0f), 7.0f, [UIColor blackColor].CGColor);
	CGContextSetRGBFillColor(ctx, 0.12f, 0.14f, 0.18f, 1.0f);
	[body fill];
	CGContextRestoreGState(ctx);

	CGContextSaveGState(ctx);
	[body addClip];
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	const CGFloat compSlate[] = {
		0.24f, 0.28f, 0.34f, 1.0f,
		0.10f, 0.12f, 0.15f, 1.0f
	};
	CGGradientRef gradSlate = CGGradientCreateWithColorComponents(cs, compSlate, NULL, 2);
	CGContextDrawLinearGradient(ctx, gradSlate, CGPointMake(20.0f, 48.0f), CGPointMake(20.0f, 110.0f), 0);
	CGGradientRelease(gradSlate);

	UIBezierPath *play = [UIBezierPath bezierPath];
	[play moveToPoint:CGPointMake(58.0f, 66.0f)];
	[play addLineToPoint:CGPointMake(78.0f, 79.0f)];
	[play addLineToPoint:CGPointMake(58.0f, 92.0f)];
	[play closePath];
	CGContextSetRGBFillColor(ctx, 0.10f, 0.85f, 0.95f, 0.95f);
	[play fill];

	CGContextRestoreGState(ctx);

	CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, 22.0f, 46.0f);
	CGContextRotateCTM(ctx, (CGFloat)(-12.0 * M_PI / 180.0));
	CGRect armRect = CGRectMake(0.0f, -20.0f, 90.0f, 20.0f);
	UIBezierPath *arm = [UIBezierPath bezierPathWithRoundedRect:armRect cornerRadius:4.0f];

	CGContextSetShadowWithColor(ctx, CGSizeMake(0.0f, 2.0f), 4.0f, [UIColor blackColor].CGColor);
	CGContextSetRGBFillColor(ctx, 0.15f, 0.16f, 0.18f, 1.0f);
	[arm fill];

	CGContextSaveGState(ctx);
	[arm addClip];
	CGContextSetRGBFillColor(ctx, 0.95f, 0.96f, 0.98f, 0.95f);
	for (CGFloat sX = -10.0f; sX < 110.0f; sX += 24.0f) {
		UIBezierPath *stripe = [UIBezierPath bezierPath];
		[stripe moveToPoint:CGPointMake(sX, 0.0f)];
		[stripe addLineToPoint:CGPointMake(sX + 12.0f, 0.0f)];
		[stripe addLineToPoint:CGPointMake(sX + 2.0f, -20.0f)];
		[stripe addLineToPoint:CGPointMake(sX - 10.0f, -20.0f)];
		[stripe closePath];
		[stripe fill];
	}
	CGContextRestoreGState(ctx);

	CGContextSetRGBFillColor(ctx, 0.85f, 0.88f, 0.92f, 1.0f);
	UIBezierPath *hinge = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4.0f, -14.0f, 8.0f, 8.0f)];
	[hinge fill];

	CGContextRestoreGState(ctx);
	CGColorSpaceRelease(cs);

	UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, res);
	return res;
}

+ (UIImage *)synthwaveTrackArtwork {
	NSString *key = @"artwork_midnight_city";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat side = 180.0f;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

	const CGFloat compSky[] = {
		0.05f, 0.01f, 0.13f, 1.0f,
		0.16f, 0.03f, 0.28f, 1.0f,
		0.52f, 0.04f, 0.62f, 1.0f,
		0.95f, 0.12f, 0.48f, 1.0f
	};
	const CGFloat locsSky[] = { 0.0f, 0.35f, 0.68f, 1.0f };
	CGGradientRef gradSky = CGGradientCreateWithColorComponents(cs, compSky, locsSky, 4);
	CGFloat horizonY = 106.0f;
	CGContextDrawLinearGradient(ctx, gradSky, CGPointMake(TGHalf(side), 0.0f), CGPointMake(TGHalf(side), horizonY), 0);
	CGGradientRelease(gradSky);

	CGPoint sunCenter = CGPointMake(TGHalf(side), horizonY - 4.0f);
	CGFloat sunRadius = 38.0f;
	CGContextSaveGState(ctx);
	UIBezierPath *sunClip = [UIBezierPath bezierPathWithArcCenter:sunCenter
														   radius:sunRadius
													   startAngle:0
														 endAngle:(CGFloat)(2.0 * M_PI)
														clockwise:YES];
	[sunClip addClip];

	const CGFloat compSun[] = {
		1.0f, 0.92f, 0.25f, 1.0f,
		1.0f, 0.40f, 0.10f, 1.0f,
		0.95f, 0.05f, 0.50f, 1.0f
	};
	const CGFloat locsSun[] = { 0.0f, 0.5f, 1.0f };
	CGGradientRef gradSun = CGGradientCreateWithColorComponents(cs, compSun, locsSun, 3);
	CGContextDrawLinearGradient(ctx, gradSun, CGPointMake(sunCenter.x, sunCenter.y - sunRadius),
								CGPointMake(sunCenter.x, sunCenter.y + sunRadius), 0);
	CGGradientRelease(gradSun);

	CGContextSetRGBFillColor(ctx, 0.05f, 0.01f, 0.13f, 1.0f);
	CGFloat stripeY = sunCenter.y + 2.0f;
	CGFloat stripeH = 1.8f;
	while (stripeY < sunCenter.y + sunRadius) {
		CGContextFillRect(ctx, CGRectMake(sunCenter.x - sunRadius, stripeY, sunRadius * 2.0f, stripeH));
		stripeY += stripeH + 3.2f;
		stripeH += 0.8f;
	}
	CGContextRestoreGState(ctx);

	UIBezierPath *mountains = [UIBezierPath bezierPath];
	[mountains moveToPoint:CGPointMake(0.0f, horizonY)];
	[mountains addLineToPoint:CGPointMake(30.0f, horizonY - 14.0f)];
	[mountains addLineToPoint:CGPointMake(58.0f, horizonY - 6.0f)];
	[mountains addLineToPoint:CGPointMake(90.0f, horizonY - 22.0f)];
	[mountains addLineToPoint:CGPointMake(124.0f, horizonY - 8.0f)];
	[mountains addLineToPoint:CGPointMake(150.0f, horizonY - 18.0f)];
	[mountains addLineToPoint:CGPointMake(side, horizonY)];
	[mountains closePath];
	CGContextSetRGBFillColor(ctx, 0.08f, 0.02f, 0.16f, 0.92f);
	[mountains fill];

	CGRect floorRect = CGRectMake(0.0f, horizonY, side, side - horizonY);
	CGContextSaveGState(ctx);
	UIRectClip(floorRect);

	const CGFloat compFloor[] = {
		0.09f, 0.01f, 0.18f, 1.0f,
		0.02f, 0.00f, 0.06f, 1.0f
	};
	CGGradientRef gradFloor = CGGradientCreateWithColorComponents(cs, compFloor, NULL, 2);
	CGContextDrawLinearGradient(ctx, gradFloor, CGPointMake(TGHalf(side), horizonY), CGPointMake(TGHalf(side), side), 0);
	CGGradientRelease(gradFloor);

	CGContextSetRGBStrokeColor(ctx, 0.20f, 0.95f, 1.0f, 1.0f);
	CGContextSetLineWidth(ctx, 2.0f);
	CGContextMoveToPoint(ctx, 0.0f, horizonY);
	CGContextAddLineToPoint(ctx, side, horizonY);
	CGContextStrokePath(ctx);

	CGPoint vp = CGPointMake(TGHalf(side), horizonY);
	CGContextSetRGBStrokeColor(ctx, 0.20f, 0.85f, 0.98f, 0.70f);
	CGContextSetLineWidth(ctx, 1.0f);
	for (CGFloat x = -40.0f; x <= side + 40.0f; x += 18.0f) {
		CGContextMoveToPoint(ctx, vp.x, vp.y);
		CGContextAddLineToPoint(ctx, x, side);
		CGContextStrokePath(ctx);
	}

	CGFloat hY = horizonY + 3.0f;
	CGFloat step = 2.5f;
	while (hY < side) {
		CGFloat alpha = 0.35f + (hY - horizonY) / (side - horizonY) * 0.50f;
		CGContextSetRGBStrokeColor(ctx, 0.90f, 0.15f, 0.65f, alpha);
		CGContextMoveToPoint(ctx, 0.0f, hY);
		CGContextAddLineToPoint(ctx, side, hY);
		CGContextStrokePath(ctx);
		hY += step;
		step += 2.2f;
	}
	CGContextRestoreGState(ctx);

	UIFont *artistFont = TGFontSubheadStrong();
	UIFont *titleFont = TGFontMicro();

	NSString *artist = @"M 8 3";
	NSString *trackTitle = @"MIDNIGHT CITY";

	NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
	style.alignment = NSTextAlignmentCenter;

	NSDictionary *artistAttrs = @{
		NSFontAttributeName: artistFont,
		NSForegroundColorAttributeName: [UIColor whiteColor],
		NSParagraphStyleAttributeName: style
	};
	NSDictionary *titleAttrs = @{
		NSFontAttributeName: titleFont,
		NSForegroundColorAttributeName: [UIColor whiteColor],
		NSParagraphStyleAttributeName: style
	};

	[artist drawInRect:CGRectMake(0.0f, 14.0f, side, 22.0f) withAttributes:artistAttrs];
	[trackTitle drawInRect:CGRectMake(0.0f, 36.0f, side, 16.0f) withAttributes:titleAttrs];

	UIBezierPath *gloss = [UIBezierPath bezierPath];
	[gloss moveToPoint:CGPointMake(0.0f, 0.0f)];
	[gloss addLineToPoint:CGPointMake(side, 0.0f)];
	[gloss addLineToPoint:CGPointMake(side, 45.0f)];
	[gloss addCurveToPoint:CGPointMake(0.0f, 65.0f)
			 controlPoint1:CGPointMake(side * 0.7f, 35.0f)
			 controlPoint2:CGPointMake(side * 0.3f, 75.0f)];
	[gloss closePath];

	const CGFloat compGloss[] = {
		1.0f, 1.0f, 1.0f, 0.38f,
		1.0f, 1.0f, 1.0f, 0.03f
	};
	CGGradientRef gradGloss = CGGradientCreateWithColorComponents(cs, compGloss, NULL, 2);
	CGContextSaveGState(ctx);
	[gloss addClip];
	CGContextDrawLinearGradient(ctx, gradGloss, CGPointMake(0.0f, 0.0f), CGPointMake(0.0f, 65.0f), 0);
	CGGradientRelease(gradGloss);
	CGContextRestoreGState(ctx);

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.25f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextStrokeRect(ctx, CGRectMake(0.5f, 0.5f, side - 1.0f, side - 1.0f));

	CGColorSpaceRelease(cs);

	UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, res);
	return res;
}

@end
