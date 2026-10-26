#import "TGIconsInternal.h"

static NSMutableDictionary *sSettingsIconCache = nil;

void TGIconsClearSettingsIconCache(void) {
	[sSettingsIconCache removeAllObjects];
}

@implementation TGIcons (Menu)

/// The line art beside each row of their pop-up menu. Drawn as strokes at a
/// single weight so the set reads as one family, which is what their 27x27
/// outline icons do.
+ (UIImage *)menuGlyphNamed:(NSString *)name {
	static NSSet *known = nil;
	if (!known)
		known = [NSSet setWithObjects:@"reply", @"undo", @"forward", @"copy",
				@"edit", @"delete", @"pin", @"unpin", @"mute", @"unmute",
				@"archive", @"unarchive", @"react", @"select",
				// the settings list
				@"notifications", @"privacy", @"data", @"chat", @"folder",
				@"devices", @"language", @"faq", @"policy",
				// the profile's action tiles
				@"call", @"video", @"search", @"more",
				// the call screen
				@"endcall", @"recent", @"star",
				// the dismiss cross and the record lock's arrow, which were
				// drawn with characters in four places and came out as four
				// different shapes
				@"close", @"chevronUp", nil];
	// An unknown name has to answer nil, not a blank square: a row with no
	// glyph is better than a row with a hole where one should be.
	if (![known containsObject:name])
		return nil;

	NSString *key = [@"menu-" stringByAppendingString:name];
	return [self iconNamed:key draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGFloat m = s * 0.18f;              // margin, so every glyph shares a box

		if ([name isEqualToString:@"close"]){
			// Three screens drew this with a character - U+00D7, the same
			// again as a literal, and U+2715 - so one button was three
			// shapes at three weights depending on where it was.
			CGFloat c = s * 0.3f;
			CGContextMoveToPoint(ctx, c, c);
			CGContextAddLineToPoint(ctx, s - c, s - c);
			CGContextMoveToPoint(ctx, s - c, c);
			CGContextAddLineToPoint(ctx, c, s - c);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"chevronUp"]){
			CGContextMoveToPoint(ctx, s * 0.3f, s * 0.58f);
			CGContextAddLineToPoint(ctx, s / 2, s * 0.38f);
			CGContextAddLineToPoint(ctx, s * 0.7f, s * 0.58f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"reply"]){
			// an arrow turning back on itself (reply left)
			CGContextMoveToPoint(ctx, m + 5, s * 0.30f);
			CGContextAddLineToPoint(ctx, m, s * 0.45f);
			CGContextAddLineToPoint(ctx, m + 5, s * 0.60f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, m, s * 0.45f);
			CGContextAddLineToPoint(ctx, s - m - 5, s * 0.45f);
			CGContextAddArc(ctx, s - m - 5, s * 0.62f, s * 0.17f, -M_PI_2, 0, 0);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"undo"]){
			// counter-clockwise circular rewind arrow
			CGFloat r = s * 0.28f;
			CGFloat cx = s / 2.0f;
			CGFloat cy = s / 2.0f;
			CGContextAddArc(ctx, cx, cy, r, -M_PI * 0.70f, M_PI * 0.75f, 0);
			CGContextStrokePath(ctx);
			CGPoint tip = CGPointMake(cx + r * cosf(-M_PI * 0.70f), cy + r * sinf(-M_PI * 0.70f));
			CGContextMoveToPoint(ctx, tip.x - 2.0f, tip.y + 5.0f);
			CGContextAddLineToPoint(ctx, tip.x, tip.y);
			CGContextAddLineToPoint(ctx, tip.x + 5.0f, tip.y + 1.0f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"forward"]){
			// the same arrow mirrored
			CGContextMoveToPoint(ctx, s - m - 5, s * 0.30f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.45f);
			CGContextAddLineToPoint(ctx, s - m - 5, s * 0.60f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s - m, s * 0.45f);
			CGContextAddLineToPoint(ctx, m + 5, s * 0.45f);
			CGContextAddArc(ctx, m + 5, s * 0.62f, s * 0.17f, -M_PI_2, M_PI, 1);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"copy"]){
			// two sheets, one behind the other
			CGContextStrokeRect(ctx, CGRectMake(m, m, s * 0.46f, s * 0.46f));
			CGContextStrokeRect(ctx, CGRectMake(s * 0.34f, s * 0.34f, s * 0.46f, s * 0.46f));

		} else if ([name isEqualToString:@"edit"]){
			// a pencil on its diagonal
			CGContextMoveToPoint(ctx, m, s - m);
			CGContextAddLineToPoint(ctx, m + s * 0.10f, s - m - s * 0.16f);
			CGContextAddLineToPoint(ctx, s - m - s * 0.06f, m + s * 0.06f);
			CGContextAddLineToPoint(ctx, s - m, m + s * 0.16f);
			CGContextAddLineToPoint(ctx, m + s * 0.20f, s - m - s * 0.06f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"delete"]){
			// a bin: lid, body, two ribs
			CGContextMoveToPoint(ctx, m, s * 0.30f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.30f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s * 0.40f, s * 0.30f);
			CGContextAddLineToPoint(ctx, s * 0.40f, s * 0.22f);
			CGContextAddLineToPoint(ctx, s * 0.60f, s * 0.22f);
			CGContextAddLineToPoint(ctx, s * 0.60f, s * 0.30f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, m + 2, s * 0.30f);
			CGContextAddLineToPoint(ctx, m + 4, s - m);
			CGContextAddLineToPoint(ctx, s - m - 4, s - m);
			CGContextAddLineToPoint(ctx, s - m - 2, s * 0.30f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"pin"]){
			// a drawing pin seen from the side
			CGContextMoveToPoint(ctx, s * 0.34f, m);
			CGContextAddLineToPoint(ctx, s * 0.66f, m);
			CGContextAddLineToPoint(ctx, s * 0.58f, s * 0.46f);
			CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.60f);
			CGContextAddLineToPoint(ctx, s * 0.24f, s * 0.60f);
			CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.46f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s / 2, s * 0.60f);
			CGContextAddLineToPoint(ctx, s / 2, s - m);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"unpin"]){
			// pin with a clean diagonal slash across it
			CGContextMoveToPoint(ctx, s * 0.34f, m);
			CGContextAddLineToPoint(ctx, s * 0.66f, m);
			CGContextAddLineToPoint(ctx, s * 0.58f, s * 0.46f);
			CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.60f);
			CGContextAddLineToPoint(ctx, s * 0.24f, s * 0.60f);
			CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.46f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s / 2, s * 0.60f);
			CGContextAddLineToPoint(ctx, s / 2, s - m);
			CGContextStrokePath(ctx);
			// Diagonal strike-through line
			CGContextMoveToPoint(ctx, m + 1.0f, s - m - 1.0f);
			CGContextAddLineToPoint(ctx, s - m - 1.0f, m + 1.0f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"mute"] || [name isEqualToString:@"unmute"]){
			// a speaker cone
			CGContextMoveToPoint(ctx, m, s * 0.38f);
			CGContextAddLineToPoint(ctx, s * 0.34f, s * 0.38f);
			CGContextAddLineToPoint(ctx, s * 0.54f, s * 0.20f);
			CGContextAddLineToPoint(ctx, s * 0.54f, s * 0.80f);
			CGContextAddLineToPoint(ctx, s * 0.34f, s * 0.62f);
			CGContextAddLineToPoint(ctx, m, s * 0.62f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);
			if ([name isEqualToString:@"mute"]){
				CGContextMoveToPoint(ctx, s * 0.66f, s * 0.38f);
				CGContextAddLineToPoint(ctx, s * 0.86f, s * 0.62f);
				CGContextMoveToPoint(ctx, s * 0.86f, s * 0.38f);
				CGContextAddLineToPoint(ctx, s * 0.66f, s * 0.62f);
				CGContextStrokePath(ctx);
			}

		} else if ([name isEqualToString:@"archive"] || [name isEqualToString:@"unarchive"]){
			// a box with a lid and a handle slot
			CGContextStrokeRect(ctx, CGRectMake(m, m, s - 2 * m, s * 0.18f));
			CGContextMoveToPoint(ctx, m + 2, m + s * 0.18f);
			CGContextAddLineToPoint(ctx, m + 2, s - m);
			CGContextAddLineToPoint(ctx, s - m - 2, s - m);
			CGContextAddLineToPoint(ctx, s - m - 2, m + s * 0.18f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s * 0.40f, s * 0.58f);
			CGContextAddLineToPoint(ctx, s * 0.60f, s * 0.58f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"react"]){
			// Smiling face reaction outline
			CGRect faceRect = CGRectInset(CGRectMake(0, 0, s, s), m, m);
			CGContextStrokeEllipseInRect(ctx, faceRect);
			// Eyes
			CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.36f - 1.0f, s * 0.38f - 1.5f, 2.5f, 3.0f));
			CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.64f - 1.5f, s * 0.38f - 1.5f, 2.5f, 3.0f));
			// Smile
			CGContextAddArc(ctx, s / 2.0f, s * 0.48f, s * 0.22f, 0.4f, M_PI - 0.4f, 0);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"select"]){
			// a circular checkbox with a checkmark
			CGContextStrokeEllipseInRect(ctx, CGRectMake(m, m, s - 2 * m, s - 2 * m));
			CGContextMoveToPoint(ctx, s * 0.30f, s * 0.52f);
			CGContextAddLineToPoint(ctx, s * 0.46f, s * 0.68f);
			CGContextAddLineToPoint(ctx, s * 0.72f, s * 0.36f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"call"] || [name isEqualToString:@"endcall"]){
			// Sleek telephone receiver angled at 45 degrees. Hanging up is the
			// same receiver turned face down.
			CGContextSaveGState(ctx);
			CGContextTranslateCTM(ctx, s / 2.0f, s / 2.0f);
			CGContextRotateCTM(ctx, [name isEqualToString:@"endcall"] ? M_PI_4 * 3 : -M_PI_4);

			UIBezierPath *phone = [UIBezierPath bezierPath];
			[phone moveToPoint:CGPointMake(9.0f, 3.8f)];
			[phone addArcWithCenter:CGPointMake(7.0f, -0.5f) radius:2.2f startAngle:0 endAngle:M_PI clockwise:NO];
			[phone addLineToPoint:CGPointMake(5.0f, 1.2f)];
			[phone addCurveToPoint:CGPointMake(-5.0f, 1.2f)
					controlPoint1:CGPointMake(2.5f, 3.0f)
					controlPoint2:CGPointMake(-2.5f, 3.0f)];
			[phone addLineToPoint:CGPointMake(-6.0f, -0.5f)];
			[phone addArcWithCenter:CGPointMake(-7.0f, -0.5f) radius:2.2f startAngle:0 endAngle:M_PI clockwise:NO];
			[phone addLineToPoint:CGPointMake(-9.0f, 3.8f)];
			[phone addCurveToPoint:CGPointMake(9.0f, 3.8f)
					controlPoint1:CGPointMake(-3.5f, 6.0f)
					controlPoint2:CGPointMake(3.5f, 6.0f)];
			[phone closePath];

			CGContextAddPath(ctx, phone.CGPath);
			CGContextFillPath(ctx);
			CGContextRestoreGState(ctx);

		} else if ([name isEqualToString:@"video"]){
			// a camera: body and the lens sticking out of it
			CGContextAddPath(ctx, [UIBezierPath bezierPathWithRoundedRect:
					CGRectMake(m, s * 0.32f, s * 0.44f, s * 0.36f)
															 cornerRadius:3].CGPath);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, m + s * 0.46f, s * 0.44f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.34f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.66f);
			CGContextAddLineToPoint(ctx, m + s * 0.46f, s * 0.56f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"recent"]){
			// a clock, for the "recently used" strip entry
			CGContextStrokeEllipseInRect(ctx, CGRectMake(m, m, s - 2 * m, s - 2 * m));
			CGContextMoveToPoint(ctx, s * 0.5f, s * 0.30f);
			CGContextAddLineToPoint(ctx, s * 0.5f, s * 0.52f);
			CGContextAddLineToPoint(ctx, s * 0.66f, s * 0.60f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"star"]){
			// a five-pointed star, for Favourites
			CGFloat cx = s / 2.0f, cy = s / 2.0f, outer = s * 0.32f, inner = outer * 0.42f;
			UIBezierPath *star = [UIBezierPath bezierPath];
			for (int i = 0; i < 10; i++){
				CGFloat r = (i % 2) ? inner : outer;
				CGFloat a = -M_PI_2 + i * M_PI / 5.0f;
				CGPoint p = CGPointMake(cx + r * cosf(a), cy + r * sinf(a));
				if (i == 0)
					[star moveToPoint:p];
				else
					[star addLineToPoint:p];
			}
			[star closePath];
			CGContextAddPath(ctx, star.CGPath);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"search"]){
			// a magnifier with clean 45-degree handle
			CGFloat r = s * 0.26f;
			CGFloat cx = s * 0.40f;
			CGFloat cy = s * 0.40f;
			CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - r, cy - r, r * 2.0f, r * 2.0f));
			CGFloat cos45 = 0.7071f;
			CGContextMoveToPoint(ctx, cx + r * cos45, cy + r * cos45);
			CGContextAddLineToPoint(ctx, s - m, s - m);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"more"]){
			// three dots across
			for (int i = 0; i < 3; i++)
				CGContextFillEllipseInRect(ctx, CGRectMake(
						s * 0.24f + i * s * 0.20f - 1.5f, s / 2 - 1.5f, 3, 3));

		} else if ([name isEqualToString:@"notifications"]){
			// a bell
			CGContextAddArc(ctx, s / 2, s * 0.46f, s * 0.26f, M_PI, 0, 0);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s * 0.24f, s * 0.46f);
			CGContextAddLineToPoint(ctx, s * 0.24f, s * 0.66f);
			CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.66f);
			CGContextAddLineToPoint(ctx, s * 0.76f, s * 0.46f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s * 0.42f, s * 0.74f);
			CGContextAddLineToPoint(ctx, s * 0.58f, s * 0.74f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"privacy"]){
			// a padlock: shackle over a body
			CGContextAddArc(ctx, s / 2, s * 0.42f, s * 0.16f, M_PI, 0, 0);
			CGContextStrokePath(ctx);
			CGContextStrokeRect(ctx, CGRectMake(s * 0.26f, s * 0.44f,
												s * 0.48f, s * 0.34f));

		} else if ([name isEqualToString:@"data"]){
			// a pie with one slice drawn in
			CGContextStrokeEllipseInRect(ctx, CGRectInset(
					CGRectMake(0, 0, s, s), m, m));
			CGContextMoveToPoint(ctx, s / 2, s / 2);
			CGContextAddLineToPoint(ctx, s / 2, m);
			CGContextMoveToPoint(ctx, s / 2, s / 2);
			CGContextAddLineToPoint(ctx, s - m, s / 2);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"chat"]){
			// a speech bubble with a tail
			CGRect body = CGRectMake(m, m, s - 2 * m, s * 0.50f);
			CGContextAddPath(ctx, [UIBezierPath bezierPathWithRoundedRect:body
															 cornerRadius:s * 0.14f].CGPath);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s * 0.30f, CGRectGetMaxY(body));
			CGContextAddLineToPoint(ctx, s * 0.30f, s - m);
			CGContextAddLineToPoint(ctx, s * 0.48f, CGRectGetMaxY(body));
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"folder"]){
			// a tab along the top left, then the body
			CGContextMoveToPoint(ctx, m, s * 0.74f);
			CGContextAddLineToPoint(ctx, m, s * 0.28f);
			CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.28f);
			CGContextAddLineToPoint(ctx, s * 0.50f, s * 0.38f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.38f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.74f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"devices"]){
			// a laptop: screen and the bar it stands on
			CGContextStrokeRect(ctx, CGRectMake(s * 0.20f, s * 0.28f,
												s * 0.60f, s * 0.36f));
			CGContextMoveToPoint(ctx, m, s * 0.72f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.72f);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"language"]){
			// a globe: circle, equator, meridian
			CGRect ball = CGRectInset(CGRectMake(0, 0, s, s), m, m);
			CGContextStrokeEllipseInRect(ctx, ball);
			CGContextMoveToPoint(ctx, m, s / 2);
			CGContextAddLineToPoint(ctx, s - m, s / 2);
			CGContextStrokePath(ctx);
			CGContextSaveGState(ctx);
			CGContextTranslateCTM(ctx, s / 2, s / 2);
			CGContextScaleCTM(ctx, 0.5f, 1.0f);
			CGContextTranslateCTM(ctx, -s / 2, -s / 2);
			CGContextStrokeEllipseInRect(ctx, ball);
			CGContextRestoreGState(ctx);

		} else if ([name isEqualToString:@"faq"]){
			// Clean circular frame with centered, smoothly curved question mark
			CGContextStrokeEllipseInRect(ctx, CGRectInset(CGRectMake(0, 0, s, s), m, m));
			CGFloat cx = s / 2.0f;
			CGFloat R = 3.4f;
			CGFloat topY = s * 0.38f;
			CGContextAddArc(ctx, cx, topY, R, M_PI, 0, 0);
			CGContextAddCurveToPoint(ctx, cx + R, s * 0.46f, cx, s * 0.49f, cx, s * 0.57f);
			CGContextStrokePath(ctx);
			CGContextFillEllipseInRect(ctx, CGRectMake(cx - 1.2f, s * 0.69f, 2.4f, 2.4f));

		} else if ([name isEqualToString:@"policy"]){
			// a shield with a tick in it
			CGContextMoveToPoint(ctx, s / 2, m);
			CGContextAddLineToPoint(ctx, s - m, s * 0.30f);
			CGContextAddLineToPoint(ctx, s - m, s * 0.56f);
			CGContextAddCurveToPoint(ctx, s - m, s * 0.76f, s * 0.70f, s - m,
									 s / 2, s - m);
			CGContextAddCurveToPoint(ctx, s * 0.30f, s - m, m, s * 0.76f,
									 m, s * 0.56f);
			CGContextAddLineToPoint(ctx, m, s * 0.30f);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s * 0.36f, s * 0.50f);
			CGContextAddLineToPoint(ctx, s * 0.46f, s * 0.60f);
			CGContextAddLineToPoint(ctx, s * 0.66f, s * 0.38f);
			CGContextStrokePath(ctx);

		} else {
			return;   // an unknown name draws nothing rather than a wrong glyph
		}
	}];
}

+ (UIImage *)glyphNamed:(NSString *)name colour:(UIColor *)colour side:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"glyph-%@-%.0f-%@", name, side, colour];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIImage *glyph = [self menuGlyphNamed:name];
	if (!glyph) return nil;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextTranslateCTM(ctx, 0, side);
	CGContextScaleCTM(ctx, 1.0, -1.0);
	CGContextClipToMask(ctx, CGRectMake(0, 0, side, side), glyph.CGImage);
	[colour setFill];
	CGContextFillRect(ctx, CGRectMake(0, 0, side, side));
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	if (image) TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)settingsIconNamed:(NSString *)name color:(UIColor *)color {
	// Every settings row asks for its icon in cellForRow, and the list reloads
	// on every appearance - redrawing sixteen of these each time is what made
	// the screen crawl on a 4S.
	if (!sSettingsIconCache) sSettingsIconCache = [NSMutableDictionary dictionary];
	NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", name, color];
	UIImage *hit = sSettingsIconCache[cacheKey];
	if (hit) return hit;

	CGFloat side = 29.0;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	(void)ctx;

	// Draw rounded square background
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:6.0];
	[color setFill];
	[path fill];

	// Get line glyph and draw it centered in white
	UIImage *glyph = [self menuGlyphNamed:name];
	if (!glyph) {
		// Fallback for missing glyphs: use a generic dot or similar if needed,
		// but we'll map them carefully.
		if ([name isEqualToString:@"star"]) glyph = [self menuGlyphNamed:@"folder"]; // Placeholder
		if ([name isEqualToString:@"battery"]) glyph = [self menuGlyphNamed:@"call"]; // Placeholder
		if ([name isEqualToString:@"devices"]) glyph = [self menuGlyphNamed:@"chat"]; // Placeholder
		if ([name isEqualToString:@"gift"]) glyph = [self menuGlyphNamed:@"policy"]; // Placeholder
		if ([name isEqualToString:@"briefcase"]) glyph = [self menuGlyphNamed:@"archive"]; // Placeholder
		// The sticker glyph is drawn as a top-level icon rather than a menu one,
		// so it never matched here and the row got a plain coloured square.
		if ([name isEqualToString:@"sticker"]) glyph = [self sticker];
	}

	if (glyph) {
		// Draw white glyph centered on the colored background plate.
		CGFloat w = glyph.size.width;
		CGFloat h = glyph.size.height;
		CGRect rect = CGRectMake((side - w) / 2.0, (side - h) / 2.0, w, h);
		
		// To tint the template image white
		UIGraphicsBeginImageContextWithOptions(glyph.size, NO, 0);
		CGContextRef tintCtx = UIGraphicsGetCurrentContext();
		CGContextTranslateCTM(tintCtx, 0, h);
		CGContextScaleCTM(tintCtx, 1.0, -1.0);
		CGContextClipToMask(tintCtx, CGRectMake(0, 0, w, h), glyph.CGImage);
		[[UIColor whiteColor] setFill];
		CGContextFillRect(tintCtx, CGRectMake(0, 0, w, h));
		UIImage *tintedGlyph = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		
		[tintedGlyph drawInRect:rect];
	}

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (image) sSettingsIconCache[cacheKey] = image;
	return image;
}

@end
