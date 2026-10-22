#import "TGIconsInternal.h"

static NSMutableDictionary *sCache = nil;

UIImage *TGIconsGetCached(NSString *key) {
	return sCache ? sCache[key] : nil;
}

void TGIconsSetCached(NSString *key, UIImage *img) {
	if (!sCache) sCache = [NSMutableDictionary dictionary];
	if (key && img) sCache[key] = img;
}

@implementation TGIcons

+ (void)flush {
	[sCache removeAllObjects];
	TGIconsClearSettingsIconCache();
}

+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw {
	BOOL flat = [TGTheme shared].isFlat;
	NSString *key = [NSString stringWithFormat:@"%@-%d", name, (int)flat];
	UIImage *cached = TGIconsGetCached(key);
	if (cached)
		return cached;

	CGFloat side = 28;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (!flat){
		// Skeuomorphic glyphs sit on the surface: a soft shadow under, a white
		// highlight one pixel up. Flat ones are the shape and nothing else.
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, 1);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.55f);
		CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.55f);
		draw(ctx, side);
		CGContextRestoreGState(ctx);
	}

	CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
	CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 1);
	draw(ctx, side);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	// Template rendering lets the tab bar and buttons tint it themselves.
	if ([image respondsToSelector:@selector(imageWithRenderingMode:)])
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	sCache[key] = image;
	return image;
}

#pragma mark - tab bar

+ (UIImage *)chats {
	return [self iconNamed:@"chats" draw:^(CGContextRef ctx, CGFloat s){
		// a speech bubble with a tail
		CGRect body = CGRectMake(3, 5, s - 6, s - 13);
		UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:5];
		[p moveToPoint:CGPointMake(8, CGRectGetMaxY(body) - 1)];
		[p addLineToPoint:CGPointMake(8, CGRectGetMaxY(body) + 5)];
		[p addLineToPoint:CGPointMake(14, CGRectGetMaxY(body) - 1)];
		CGContextAddPath(ctx, p.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)contacts {
	return [self iconNamed:@"contacts" draw:^(CGContextRef ctx, CGFloat s){
		// head and shoulders
		CGContextFillEllipseInRect(ctx, CGRectMake(s/2 - 5, 4, 10, 10));
		CGRect shoulders = CGRectMake(s/2 - 9, 16, 18, 12);
		UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:shoulders cornerRadius:9];
		CGContextAddPath(ctx, p.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)settings {
	return [self iconNamed:@"settings" draw:^(CGContextRef ctx, CGFloat s){
		// three sliders
		CGContextSetLineWidth(ctx, 2);
		for (int i = 0; i < 3; i++){
			CGFloat y = 8 + i * 6;
			CGContextMoveToPoint(ctx, 4, y);
			CGContextAddLineToPoint(ctx, s - 4, y);
			CGContextStrokePath(ctx);
			CGContextFillEllipseInRect(ctx,
					CGRectMake(6 + (i == 1 ? 12 : (i == 0 ? 4 : 8)), y - 3, 6, 6));
		}
	}];
}

#pragma mark - actions

/// A pencil laid across the open corner of a sheet - their compose glyph. The
/// previous one drew the sheet as two bare strokes meeting at a right angle,
/// which read as a stray corner rather than paper.
+ (UIImage *)compose {
	return [self iconNamed:@"compose" draw:^(CGContextRef ctx, CGFloat s){
		// The sheet: three sides, left open where the pencil crosses it.
		CGContextSetLineWidth(ctx, 1.8f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGContextMoveToPoint(ctx, s - 9, 5);
		CGContextAddLineToPoint(ctx, 5, 5);
		CGContextAddLineToPoint(ctx, 5, s - 5);
		CGContextAddLineToPoint(ctx, s - 5, s - 5);
		CGContextAddLineToPoint(ctx, s - 5, 10);
		CGContextStrokePath(ctx);

		// The pencil: a shaft with a nib, pointing down and left.
		CGFloat tipX = 11, tipY = s - 10;
		CGContextMoveToPoint(ctx, tipX, tipY);
		CGContextAddLineToPoint(ctx, tipX + 2, tipY + 3.5f);
		CGContextAddLineToPoint(ctx, tipX + 5.5f, tipY + 1.5f);
		CGContextAddLineToPoint(ctx, s - 5, 6.5f);
		CGContextAddLineToPoint(ctx, s - 8.5f, 3);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)send {
	return [self iconNamed:@"send" draw:^(CGContextRef ctx, CGFloat s){
		// paper plane
		CGContextMoveToPoint(ctx, 3, s/2);
		CGContextAddLineToPoint(ctx, s - 3, 4);
		CGContextAddLineToPoint(ctx, s - 8, s - 4);
		CGContextAddLineToPoint(ctx, s/2 - 1, s/2 + 3);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)attach {
	return [self iconNamed:@"attach" draw:^(CGContextRef ctx, CGFloat s){
		// plus
		CGContextSetLineWidth(ctx, 3);
		CGContextMoveToPoint(ctx, s/2, 6);
		CGContextAddLineToPoint(ctx, s/2, s - 6);
		CGContextMoveToPoint(ctx, 6, s/2);
		CGContextAddLineToPoint(ctx, s - 6, s/2);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)play {
	return [self iconNamed:@"play" draw:^(CGContextRef ctx, CGFloat s){
		CGContextMoveToPoint(ctx, 8, 5);
		CGContextAddLineToPoint(ctx, s - 6, s/2);
		CGContextAddLineToPoint(ctx, 8, s - 5);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)pause {
	return [self iconNamed:@"pause" draw:^(CGContextRef ctx, CGFloat s){
		CGContextFillRect(ctx, CGRectMake(s * 0.32f, 5, s * 0.13f, s - 10));
		CGContextFillRect(ctx, CGRectMake(s * 0.55f, 5, s * 0.13f, s - 10));
	}];
}

+ (UIImage *)document {
	return [self iconNamed:@"document" draw:^(CGContextRef ctx, CGFloat s){
		// sheet with a folded corner
		CGContextMoveToPoint(ctx, 6, 3);
		CGContextAddLineToPoint(ctx, s - 10, 3);
		CGContextAddLineToPoint(ctx, s - 5, 8);
		CGContextAddLineToPoint(ctx, s - 5, s - 3);
		CGContextAddLineToPoint(ctx, 6, s - 3);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)pin {
	return [self iconNamed:@"pin" draw:^(CGContextRef ctx, CGFloat s){
		CGContextFillEllipseInRect(ctx, CGRectMake(s/2 - 6, 4, 12, 12));
		CGContextMoveToPoint(ctx, s/2 - 4, 14);
		CGContextAddLineToPoint(ctx, s/2 + 4, 14);
		CGContextAddLineToPoint(ctx, s/2, s - 4);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)microphone {
	return [self iconNamed:@"microphone" draw:^(CGContextRef ctx, CGFloat s){
		// capsule head, stand, base
		UIBezierPath *head = [UIBezierPath bezierPathWithRoundedRect:
				CGRectMake(s/2 - 4, 3, 8, 13) cornerRadius:4];
		CGContextAddPath(ctx, head.CGPath);
		CGContextFillPath(ctx);

		CGContextSetLineWidth(ctx, 2);
		CGContextAddArc(ctx, s/2, 14, 7, 0, M_PI, 0);
		CGContextStrokePath(ctx);

		CGContextMoveToPoint(ctx, s/2, 21);
		CGContextAddLineToPoint(ctx, s/2, s - 4);
		CGContextStrokePath(ctx);
	}];
}

/// A smiling face. U+1F642 would be the obvious glyph, but it arrived in
/// Unicode 7.0 and iOS 7 draws it as an empty box.
+ (UIImage *)sticker {
	return [self iconNamed:@"sticker" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, 2);
		CGContextStrokeEllipseInRect(ctx, CGRectMake(3, 3, s - 6, s - 6));
		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.33f, s * 0.34f, 2.5f, 3.5f));
		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.60f, s * 0.34f, 2.5f, 3.5f));
		CGContextAddArc(ctx, s / 2, s * 0.52f, s * 0.22f, 0.5f, M_PI - 0.5f, 0);
		CGContextStrokePath(ctx);
	}];
}

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
	CGContextSetLineWidth(ctx, 1.6f);
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

+ (UIImage *)mediaDiscOfSide:(CGFloat)side playing:(BOOL)playing {
	NSString *key = [NSString stringWithFormat:@"mediaDisc_%.0f_%d", side, playing];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(ctx, 0.447f, 0.710f, 0.914f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));

	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	if (playing){
		CGFloat w = side * 0.10f, h = side * 0.30f, gap = side * 0.10f;
		CGContextFillRect(ctx, CGRectMake(side/2 - gap/2 - w, (side - h)/2, w, h));
		CGContextFillRect(ctx, CGRectMake(side/2 + gap/2,     (side - h)/2, w, h));
	} else {
		CGContextMoveToPoint(ctx, side * 0.40f, side * 0.32f);
		CGContextAddLineToPoint(ctx, side * 0.68f, side * 0.50f);
		CGContextAddLineToPoint(ctx, side * 0.40f, side * 0.68f);
		CGContextClosePath(ctx);
		CGContextFillPath(ctx);
	}

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

	CGContextSetRGBFillColor(ctx, 0.447f, 0.710f, 0.914f, 1.0f);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));

	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGFloat l = side * 0.34f, r = side * 0.66f, t = side * 0.28f, b = side * 0.72f;
	CGFloat fold = side * 0.12f;
	CGContextMoveToPoint(ctx, l, t);
	CGContextAddLineToPoint(ctx, r - fold, t);
	CGContextAddLineToPoint(ctx, r, t + fold);
	CGContextAddLineToPoint(ctx, r, b);
	CGContextAddLineToPoint(ctx, l, b);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	CGContextSetRGBFillColor(ctx, 0.447f, 0.710f, 0.914f, 1.0f);
	CGContextMoveToPoint(ctx, r - fold, t);
	CGContextAddLineToPoint(ctx, r, t + fold);
	CGContextAddLineToPoint(ctx, r - fold, t + fold);
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

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
	CGContextAddArc(ctx, side / 2, side * 0.50f, side * 0.20f, 0, M_PI, 0);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, side / 2, side * 0.70f);
	CGContextAddLineToPoint(ctx, side / 2, side * 0.80f);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, side * 0.38f, side * 0.80f);
	CGContextAddLineToPoint(ctx, side * 0.62f, side * 0.80f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)waveform:(NSData *)waveform size:(CGSize)size
               played:(CGFloat)played colour:(UIColor *)colour {
	if (!waveform.length || size.width <= 0 || size.height <= 0)
		return nil;

	// Round played percentage to 20 steps to allow caching
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
		CGRect bar = CGRectMake(x, (size.height - height) / 2, barW, height);

		CGFloat alpha = (i < bars * played) ? 1.0f : 0.32f;
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
	NSString *key = [NSString stringWithFormat:@"tail_%d_%lu", outgoing, (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(6, 10);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[colour set];

	if (outgoing){
		CGContextMoveToPoint(ctx, 0, 0);
		CGContextAddLineToPoint(ctx, 0, 10);
		CGContextAddCurveToPoint(ctx, 3, 9, 5, 7, 6, 4);
		CGContextAddLineToPoint(ctx, 0, 4);
	} else {
		CGContextMoveToPoint(ctx, 6, 0);
		CGContextAddLineToPoint(ctx, 6, 10);
		CGContextAddCurveToPoint(ctx, 3, 9, 1, 7, 0, 4);
		CGContextAddLineToPoint(ctx, 6, 4);
	}
	CGContextClosePath(ctx);
	CGContextFillPath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)ticksWhite:(BOOL)white {
	NSString *key = white ? @"ticks_white" : @"ticks_green";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(15, 9);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	if (white)
		CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
	else
		CGContextSetRGBStrokeColor(ctx, 0.35f, 0.72f, 0.42f, 1);

	CGContextSetLineWidth(ctx, 1.2f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	CGContextMoveToPoint(ctx, 0.5f, 5.0f);
	CGContextAddLineToPoint(ctx, 3.0f, 7.6f);
	CGContextAddLineToPoint(ctx, 8.4f, 1.4f);
	CGContextStrokePath(ctx);

	CGContextMoveToPoint(ctx, 6.0f, 5.0f);
	CGContextAddLineToPoint(ctx, 8.5f, 7.6f);
	CGContextAddLineToPoint(ctx, 14.0f, 1.4f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)selectionCheckboxSelected:(BOOL)selected {
	NSString *key = selected ? @"checkbox_selected" : @"checkbox_unselected";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat side = 22.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect circleRect = CGRectMake(1.0f, 1.0f, 20.0f, 20.0f);
	if (selected) {
		UIColor *fill = [[TGTheme shared] accentColour];
		CGContextSetFillColorWithColor(ctx, fill.CGColor);
		CGContextFillEllipseInRect(ctx, circleRect);

		CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
		CGContextSetLineWidth(ctx, 2.0f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		CGContextMoveToPoint(ctx, 6.0f, 11.0f);
		CGContextAddLineToPoint(ctx, 9.5f, 14.5f);
		CGContextAddLineToPoint(ctx, 15.5f, 7.5f);
		CGContextStrokePath(ctx);
	} else {
		UIColor *border = [UIColor colorWithWhite:0.75f alpha:1.0f];
		CGContextSetStrokeColorWithColor(ctx, border.CGColor);
		CGContextSetLineWidth(ctx, 1.5f);
		CGContextStrokeEllipseInRect(ctx, circleRect);
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

@end

// vim:ft=objc
