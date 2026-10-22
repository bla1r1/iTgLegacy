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

+ (void)initialize {
	if (self == [TGIcons class]) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(flush)
													 name:TGThemeChangedNotification
												   object:nil];
	}
}

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
		// Smooth Telegram chat bubble
		CGFloat r = 7.0f;
		CGRect rect = CGRectMake(3.0f, 4.0f, s - 6.0f, 15.0f);
		UIBezierPath *p = [UIBezierPath bezierPath];
		[p moveToPoint:CGPointMake(rect.origin.x + r, rect.origin.y)];
		[p addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - r, rect.origin.y)];
		[p addArcWithCenter:CGPointMake(CGRectGetMaxX(rect) - r, rect.origin.y + r) radius:r startAngle:-M_PI_2 endAngle:0 clockwise:YES];
		[p addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect) - r)];
		[p addArcWithCenter:CGPointMake(CGRectGetMaxX(rect) - r, CGRectGetMaxY(rect) - r) radius:r startAngle:0 endAngle:M_PI_2 clockwise:YES];
		[p addLineToPoint:CGPointMake(rect.origin.x + 13.0f, CGRectGetMaxY(rect))];
		// Tail curving down-left
		[p addCurveToPoint:CGPointMake(rect.origin.x + 3.0f, CGRectGetMaxY(rect) + 5.0f)
			 controlPoint1:CGPointMake(rect.origin.x + 8.0f, CGRectGetMaxY(rect) + 1.0f)
			 controlPoint2:CGPointMake(rect.origin.x + 4.5f, CGRectGetMaxY(rect) + 3.5f)];
		// Tail curve returning to bubble body
		[p addCurveToPoint:CGPointMake(rect.origin.x + 6.0f, CGRectGetMaxY(rect))
			 controlPoint1:CGPointMake(rect.origin.x + 4.5f, CGRectGetMaxY(rect) + 3.5f)
			 controlPoint2:CGPointMake(rect.origin.x + 5.5f, CGRectGetMaxY(rect) + 1.5f)];
		[p addLineToPoint:CGPointMake(rect.origin.x + r, CGRectGetMaxY(rect))];
		[p addArcWithCenter:CGPointMake(rect.origin.x + r, CGRectGetMaxY(rect) - r) radius:r startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
		[p addLineToPoint:CGPointMake(rect.origin.x, rect.origin.y + r)];
		[p addArcWithCenter:CGPointMake(rect.origin.x + r, rect.origin.y + r) radius:r startAngle:M_PI endAngle:-M_PI_2 clockwise:YES];
		[p closePath];

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
		// iOS 7 Telegram 6-toothed circular gear
		CGFloat cx = s / 2.0f;
		CGFloat cy = s / 2.0f;
		CGFloat rOut = 11.5f;
		CGFloat rIn = 9.2f;
		CGFloat rHole = 3.8f;
		NSInteger teeth = 6;

		UIBezierPath *gear = [UIBezierPath bezierPath];
		CGFloat step = (CGFloat)(M_PI * 2.0 / teeth);
		CGFloat halfTooth = step * 0.24f;

		for (NSInteger i = 0; i < teeth; i++) {
			CGFloat angle = i * step;
			CGFloat a1 = angle - halfTooth;
			CGFloat a2 = angle + halfTooth;
			CGFloat aNext = angle + step - halfTooth;

			CGPoint p1 = CGPointMake(cx + rIn * cosf(a1 - 0.12f), cy + rIn * sinf(a1 - 0.12f));
			CGPoint p2 = CGPointMake(cx + rOut * cosf(a1), cy + rOut * sinf(a1));
			CGPoint p3 = CGPointMake(cx + rOut * cosf(a2), cy + rOut * sinf(a2));
			CGPoint p4 = CGPointMake(cx + rIn * cosf(a2 + 0.12f), cy + rIn * sinf(a2 + 0.12f));

			if (i == 0) [gear moveToPoint:p1];
			else [gear addLineToPoint:p1];
			[gear addLineToPoint:p2];
			[gear addLineToPoint:p3];
			[gear addLineToPoint:p4];
			[gear addArcWithCenter:CGPointMake(cx, cy) radius:rIn startAngle:a2 + 0.12f endAngle:aNext - 0.12f clockwise:YES];
		}
		[gear closePath];

		UIBezierPath *hole = [UIBezierPath bezierPathWithOvalInRect:
				CGRectMake(cx - rHole, cy - rHole, rHole * 2.0f, rHole * 2.0f)];
		[gear appendPath:hole];
		gear.usesEvenOddFillRule = YES;

		CGContextAddPath(ctx, gear.CGPath);
		CGContextEOFillPath(ctx);
	}];
}

#pragma mark - actions

+ (UIImage *)compose {
	return [self iconNamed:@"compose" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, 2.0f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		// Notepad square with gap at top-right
		CGContextMoveToPoint(ctx, s - 11.0f, 6.0f);
		CGContextAddLineToPoint(ctx, 7.0f, 6.0f);
		CGContextAddCurveToPoint(ctx, 5.0f, 6.0f, 5.0f, 8.0f, 5.0f, 8.0f);
		CGContextAddLineToPoint(ctx, 5.0f, s - 7.0f);
		CGContextAddCurveToPoint(ctx, 5.0f, s - 5.0f, 7.0f, s - 5.0f, 7.0f, s - 5.0f);
		CGContextAddLineToPoint(ctx, s - 7.0f, s - 5.0f);
		CGContextAddCurveToPoint(ctx, s - 5.0f, s - 5.0f, s - 5.0f, s - 7.0f, s - 5.0f, s - 7.0f);
		CGContextAddLineToPoint(ctx, s - 5.0f, 12.0f);
		CGContextStrokePath(ctx);

		// Slanted pencil pointing down-left
		UIBezierPath *pencil = [UIBezierPath bezierPath];
		[pencil moveToPoint:CGPointMake(11.5f, s - 11.5f)];
		[pencil addLineToPoint:CGPointMake(11.0f, s - 15.0f)];
		[pencil addLineToPoint:CGPointMake(s - 8.5f, 4.5f)];
		[pencil addLineToPoint:CGPointMake(s - 5.0f, 8.0f)];
		[pencil addLineToPoint:CGPointMake(15.0f, s - 11.0f)];
		[pencil closePath];
		CGContextAddPath(ctx, pencil.CGPath);
		CGContextFillPath(ctx);
	}];
}

+ (UIImage *)send {
	return [self iconNamed:@"send" draw:^(CGContextRef ctx, CGFloat s){
		// Official Telegram iOS / iMessage upward send arrow
		CGFloat cx = s / 2.0f;
		CGFloat topY = s * 0.27f;
		CGFloat botY = s * 0.73f;
		CGFloat wingDX = s * 0.20f;
		CGFloat wingDY = s * 0.20f;

		CGContextSetLineWidth(ctx, 2.4f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		// Vertical shaft
		CGContextMoveToPoint(ctx, cx, botY);
		CGContextAddLineToPoint(ctx, cx, topY);
		CGContextStrokePath(ctx);

		// Arrowhead pointing up
		CGContextMoveToPoint(ctx, cx - wingDX, topY + wingDY);
		CGContextAddLineToPoint(ctx, cx, topY);
		CGContextAddLineToPoint(ctx, cx + wingDX, topY + wingDY);
		CGContextStrokePath(ctx);
	}];
}

+ (UIImage *)attach {
	return [self iconNamed:@"attach" draw:^(CGContextRef ctx, CGFloat s){
		// Elegant 45-degree angled paperclip
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, s / 2.0f, s / 2.0f);
		CGContextRotateCTM(ctx, -M_PI / 4.0f);

		CGContextSetLineWidth(ctx, 2.0f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		UIBezierPath *clip = [UIBezierPath bezierPath];
		[clip moveToPoint:CGPointMake(-2.5f, -2.0f)];
		[clip addLineToPoint:CGPointMake(-2.5f, 4.0f)];
		[clip addArcWithCenter:CGPointMake(0.0f, 4.0f) radius:2.5f startAngle:M_PI endAngle:0 clockwise:NO];
		[clip addLineToPoint:CGPointMake(2.5f, -5.5f)];
		[clip addArcWithCenter:CGPointMake(-0.5f, -5.5f) radius:3.0f startAngle:0 endAngle:M_PI clockwise:NO];
		[clip addLineToPoint:CGPointMake(-3.5f, 6.0f)];
		[clip addArcWithCenter:CGPointMake(0.5f, 6.0f) radius:4.0f startAngle:M_PI endAngle:0 clockwise:NO];
		[clip addLineToPoint:CGPointMake(4.5f, -3.0f)];

		CGContextAddPath(ctx, clip.CGPath);
		CGContextStrokePath(ctx);
		CGContextRestoreGState(ctx);
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
		// Stationery pushpin angled at 45 degrees
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, s / 2.0f, s / 2.0f);
		CGContextRotateCTM(ctx, -M_PI / 4.0f);

		// Needle
		CGContextSetLineWidth(ctx, 1.8f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextMoveToPoint(ctx, 0.0f, 4.0f);
		CGContextAddLineToPoint(ctx, 0.0f, 10.5f);
		CGContextStrokePath(ctx);

		// Pin body
		UIBezierPath *body = [UIBezierPath bezierPath];
		[body moveToPoint:CGPointMake(-5.0f, 3.5f)];
		[body addLineToPoint:CGPointMake(5.0f, 3.5f)];
		[body addLineToPoint:CGPointMake(2.0f, -1.0f)];
		[body addLineToPoint:CGPointMake(4.0f, -8.0f)];
		[body addLineToPoint:CGPointMake(-4.0f, -8.0f)];
		[body addLineToPoint:CGPointMake(-2.0f, -1.0f)];
		[body closePath];

		CGContextAddPath(ctx, body.CGPath);
		CGContextFillPath(ctx);
		CGContextRestoreGState(ctx);
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
	UIColor *c = white ? [UIColor whiteColor] : [[TGTheme shared] ticksColour];
	NSString *key = [NSString stringWithFormat:@"ticks_%lu", (unsigned long)[c hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(15, 9);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetStrokeColorWithColor(ctx, c.CGColor);
	CGContextSetLineWidth(ctx, 1.3f);
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

+ (UIImage *)searchLensOfSize:(CGFloat)size colour:(UIColor *)colour {
	if (size <= 0) size = 16.0f;
	if (!colour) colour = [UIColor grayColor];
	CGFloat scale = [UIScreen mainScreen].scale;
	NSString *key = [NSString stringWithFormat:@"searchLens-%.1f-%lu", size, (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat r = size * 0.28f;
	CGFloat cx = size * 0.38f;
	CGFloat cy = size * 0.38f;
	CGFloat lw = MAX(1.5f, size * 0.10f);

	CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
	CGContextSetLineWidth(ctx, lw);
	CGContextSetLineCap(ctx, kCGLineCapRound);

	// Rim
	CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - r, cy - r, r * 2.0f, r * 2.0f));

	// Handle at 45 degrees meeting rim edge cleanly
	CGFloat cos45 = 0.7071f;
	CGFloat handleStart = r;
	CGFloat handleEnd = size * 0.38f;
	CGContextMoveToPoint(ctx, cx + handleStart * cos45, cy + handleStart * cos45);
	CGContextAddLineToPoint(ctx, cx + (handleStart + handleEnd) * cos45, cy + (handleStart + handleEnd) * cos45);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)backChevronWithColour:(UIColor *)colour {
	if (!colour) colour = [[TGTheme shared] accentColour];
	CGFloat scale = [UIScreen mainScreen].scale;
	NSString *key = [NSString stringWithFormat:@"backChevron-%lu", (unsigned long)[colour hash]];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(13.0f, 21.0f);
	UIGraphicsBeginImageContextWithOptions(size, NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
	CGContextSetLineWidth(ctx, 2.5f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	CGContextMoveToPoint(ctx, 10.0f, 2.5f);
	CGContextAddLineToPoint(ctx, 2.5f, 10.5f);
	CGContextAddLineToPoint(ctx, 10.0f, 18.5f);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)phoneCall {
	return [self iconNamed:@"phoneCall" draw:^(CGContextRef ctx, CGFloat s) {
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, s / 2.0f, s / 2.0f);
		CGContextRotateCTM(ctx, -M_PI_4);

		UIBezierPath *path = [UIBezierPath bezierPath];
		// Ear piece cap
		[path moveToPoint:CGPointMake(9.5f, 4.0f)];
		[path addArcWithCenter:CGPointMake(7.5f, -0.5f) radius:2.2f startAngle:0 endAngle:M_PI clockwise:NO];
		// Inner dip into handle
		[path addLineToPoint:CGPointMake(5.5f, 1.2f)];
		[path addCurveToPoint:CGPointMake(-5.5f, 1.2f)
				controlPoint1:CGPointMake(2.5f, 3.0f)
				controlPoint2:CGPointMake(-2.5f, 3.0f)];
		// Mouth piece
		[path addLineToPoint:CGPointMake(-6.5f, -0.5f)];
		[path addArcWithCenter:CGPointMake(-7.5f, -0.5f) radius:2.2f startAngle:0 endAngle:M_PI clockwise:NO];
		[path addLineToPoint:CGPointMake(-9.5f, 4.0f)];
		// Outer arch back to ear piece
		[path addCurveToPoint:CGPointMake(9.5f, 4.0f)
				controlPoint1:CGPointMake(-3.5f, 6.2f)
				controlPoint2:CGPointMake(3.5f, 6.2f)];
		[path closePath];

		CGContextAddPath(ctx, path.CGPath);
		CGContextFillPath(ctx);
		CGContextRestoreGState(ctx);
	}];
}

+ (UIImage *)telegramAirplaneOfSide:(CGFloat)size {
	if (size <= 0) size = 28.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	NSString *key = [NSString stringWithFormat:@"tgAirplane-flat-%.1f", size];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGFloat s = size;

	// Modern Telegram paper airplane pointing right
	UIColor *c = [[TGTheme shared] accentColour];
	CGContextSetFillColorWithColor(ctx, c.CGColor);

	UIBezierPath *plane = [UIBezierPath bezierPath];
	// Nose pointing forward/right
	[plane moveToPoint:CGPointMake(s - 2.0f, s * 0.44f)];
	// Top wingtip
	[plane addLineToPoint:CGPointMake(2.0f, s * 0.18f)];
	// Keel fold
	[plane addLineToPoint:CGPointMake(s * 0.42f, s * 0.52f)];
	// Bottom wingtip
	[plane addLineToPoint:CGPointMake(2.0f, s * 0.82f)];
	[plane closePath];

	CGContextAddPath(ctx, plane.CGPath);
	CGContextFillPath(ctx);

	// Inner fold for depth
	CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0f alpha:0.35f].CGColor);
	UIBezierPath *fold = [UIBezierPath bezierPath];
	[fold moveToPoint:CGPointMake(s - 2.0f, s * 0.44f)];
	[fold addLineToPoint:CGPointMake(2.0f, s * 0.18f)];
	[fold addLineToPoint:CGPointMake(s * 0.42f, s * 0.52f)];
	[fold closePath];
	CGContextAddPath(ctx, fold.CGPath);
	CGContextFillPath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)verifiedBadge {
	NSString *key = @"verifiedBadge";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGFloat side = 16.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat cx = side / 2.0f;
	CGFloat cy = side / 2.0f;
	NSInteger points = 8;
	CGFloat rOuter = side * 0.46f;
	CGFloat rInner = side * 0.38f;

	UIBezierPath *star = [UIBezierPath bezierPath];
	for (NSInteger i = 0; i < points * 2; i++) {
		CGFloat r = (i % 2 == 0) ? rOuter : rInner;
		CGFloat angle = (CGFloat)i * (M_PI / (CGFloat)points) - M_PI_2;
		CGPoint pt = CGPointMake(cx + r * cosf(angle), cy + r * sinf(angle));
		if (i == 0) [star moveToPoint:pt];
		else [star addLineToPoint:pt];
	}
	[star closePath];

	CGContextSetFillColorWithColor(ctx, [[TGTheme shared] accentColour].CGColor);
	CGContextAddPath(ctx, star.CGPath);
	CGContextFillPath(ctx);

	CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
	CGContextSetLineWidth(ctx, 1.6f);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);

	CGContextMoveToPoint(ctx, 4.5f, 8.0f);
	CGContextAddLineToPoint(ctx, 7.0f, 10.5f);
	CGContextAddLineToPoint(ctx, 11.5f, 5.5f);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

@end

// vim:ft=objc
