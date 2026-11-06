#import "TGTextDraw.h"
#import "TGIconsInternal.h"
#import "TGIconPaths.h"
#import "TGSVGPath.h"
#import "TGMessageLayout.h"
#import "TGStyle.h"

static NSMutableDictionary *sCache = nil;

UIImage *TGIconsGetCached(NSString *key) {
	return sCache ? sCache[key] : nil;
}

void TGIconsSetCached(NSString *key, UIImage *img) {
	if (!sCache) sCache = [NSMutableDictionary dictionary];
	if (key && img) sCache[key] = img;
}

CGFloat TGMainScreenScale(void) {
	static CGFloat s = 0.0f;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		if ([NSThread isMainThread]) {
			s = [UIScreen mainScreen].scale;
		} else {
			dispatch_sync(dispatch_get_main_queue(), ^{
				s = [UIScreen mainScreen].scale;
			});
		}
	});
	return s > 0.0f ? s : 1.0f;
}

@implementation TGIcons

+ (UIImage *)emojiGlyph:(NSString *)emoji side:(CGFloat)side {
	if (!emoji.length || side <= 0.0f)
		return nil;
	// Quantised, or a cache keyed by an exact point size never hits: bubble
	// widths differ by a point between rows.
	CGFloat quantised = ceilf(side / 8.0f) * 8.0f;
	NSString *key = [NSString stringWithFormat:@"emoji_%@_%.0f", emoji, quantised];
	UIImage *cached = TGIconsGetCached(key);
	if (cached)
		return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(quantised, quantised), NO, 0);
	TGDrawText(emoji, CGRectMake(0.0f, 0.0f, quantised, quantised),
			TGEmojiFontOfSize(TGHalf(quantised)), nil, NSTextAlignmentCenter, nil);
	UIImage *glyph = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, glyph);
	return glyph;
}

+ (void)initialize {
	if (self == [TGIcons class]) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(flush)
													 name:TGThemeChangedNotification
												   object:nil];
		// Every icon is drawn again on demand; after a memory warning they
		// are the cheapest megabytes to give back.
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(flush)
													 name:UIApplicationDidReceiveMemoryWarningNotification
												   object:nil];
	}
}

+ (void)flush {
	[sCache removeAllObjects];
	TGIconsClearSettingsIconCache();
}

BOOL TGIconAddPath(CGContextRef ctx, const char *name, CGRect box) {
	const TGIconPath *icon = TGIconPathNamed(name);
	if (!icon)
		return NO;
	CGFloat inset = box.size.width * icon->pad / 24.0f;
	CGPathRef path = TGSVGPathCreate(icon->d, icon->viewW, icon->viewH, CGRectInset(box, inset, inset));
	if (!path)
		return NO;
	CGContextAddPath(ctx, path);
	CGPathRelease(path);
	return YES;
}

+ (UIImage *)pathIconNamed:(NSString *)name {
	// MDI keeps 2 of 24 units empty; another tenth matches the size the
	// hand-drawn set sat at in menus and buttons.
	return [self pathIconNamed:name margin:0.1f];
}

+ (UIImage *)pathIconNamed:(NSString *)name margin:(CGFloat)margin {
	if (!TGIconPathNamed(name.UTF8String))
		return nil;
	NSString *key = [NSString stringWithFormat:@"svg-%@-%.2f", name, margin];
	return [self iconNamed:key draw:^(CGContextRef ctx, CGFloat s){
		CGFloat m = s * margin;
		if (TGIconAddPath(ctx, name.UTF8String, CGRectMake(m, m, s - 2 * m, s - 2 * m)))
			CGContextFillPath(ctx);
	}];
}

+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw {
	NSString *key = name;
	UIImage *cached = TGIconsGetCached(key);
	if (cached)
		return cached;

	CGFloat side = 28;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// The glyph sits on the surface: a white echo one pixel up, then the black.
	CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, 0, 1);
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.55f);
	CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.55f);
	draw(ctx, side);
	CGContextRestoreGState(ctx);

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

// The three tab glyphs as paths, so each can be drawn filled (the selected
// tab, and every tab before iOS 7) or as an outline (the others, which is
// how their iOS 7 tab bar tells them apart).
static UIBezierPath *TGChatsTabPath(CGFloat s) {
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
	return p;
}

static UIBezierPath *TGContactsTabPath(CGFloat s) {
	// head and shoulders
	UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(TGHalf(s) - 5, 4, 10, 10)];
	[p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(TGHalf(s) - 9, 16, 18, 12) cornerRadius:9]];
	return p;
}

static UIBezierPath *TGSettingsTabPath(CGFloat s) {
	// iOS 7 Telegram 6-toothed circular gear
	CGFloat cx = TGHalf(s);
	CGFloat cy = TGHalf(s);
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
	return gear;
}

static void TGDrawTabPath(CGContextRef ctx, UIBezierPath *path, BOOL filled) {
	CGContextAddPath(ctx, path.CGPath);
	if (filled){
		if (path.usesEvenOddFillRule)
			CGContextEOFillPath(ctx);
		else
			CGContextFillPath(ctx);
		return;
	}
	CGContextSetLineWidth(ctx, TGIconStroke);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextStrokePath(ctx);
}

#pragma mark - tab bar

+ (UIImage *)chats {
	UIImage *svg = [self pathIconNamed:@"chats" margin:0];
	if (svg)
		return svg;
	return [self iconNamed:@"chats" draw:^(CGContextRef ctx, CGFloat s){
		TGDrawTabPath(ctx, TGChatsTabPath(s), YES);
	}];
}

+ (UIImage *)contacts {
	UIImage *svg = [self pathIconNamed:@"contacts" margin:0];
	if (svg)
		return svg;
	return [self iconNamed:@"contacts" draw:^(CGContextRef ctx, CGFloat s){
		TGDrawTabPath(ctx, TGContactsTabPath(s), YES);
	}];
}

+ (UIImage *)calls {
	return [self pathIconNamed:@"phoneCall" margin:0];
}

+ (UIImage *)settings {
	UIImage *svg = [self pathIconNamed:@"settings" margin:0];
	if (svg)
		return svg;
	return [self iconNamed:@"settings" draw:^(CGContextRef ctx, CGFloat s){
		TGDrawTabPath(ctx, TGSettingsTabPath(s), YES);
	}];
}

+ (UIImage *)chatsOutline {
	UIImage *svg = [self pathIconNamed:@"chats" margin:0];
	if (svg)
		return svg;
	return [self iconNamed:@"chats-outline" draw:^(CGContextRef ctx, CGFloat s){
		TGDrawTabPath(ctx, TGChatsTabPath(s), NO);
	}];
}

+ (UIImage *)contactsOutline {
	UIImage *svg = [self pathIconNamed:@"contactsOutline" margin:0];
	if (svg)
		return svg;
	return [self iconNamed:@"contacts-outline" draw:^(CGContextRef ctx, CGFloat s){
		TGDrawTabPath(ctx, TGContactsTabPath(s), NO);
	}];
}

+ (UIImage *)settingsOutline {
	UIImage *svg = [self pathIconNamed:@"settingsOutline" margin:0];
	if (svg)
		return svg;
	return [self iconNamed:@"settings-outline" draw:^(CGContextRef ctx, CGFloat s){
		TGDrawTabPath(ctx, TGSettingsTabPath(s), NO);
	}];
}

#pragma mark - actions

+ (UIImage *)compose {
	UIImage *svg = [self pathIconNamed:@"compose"];
	if (svg)
		return svg;
	return [self iconNamed:@"compose" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
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

+ (UIImage *)sendOnAccent {
	UIImage *send = [self send];
	// From iOS 7 the button's tint colours the template. iOS 6 has no tint for
	// an image, so the colour goes into the bitmap.
	if ([send respondsToSelector:@selector(imageWithRenderingMode:)])
		return send;
	UIImage *cached = TGIconsGetCached(@"send-on-accent");
	if (cached)
		return cached;
	UIImage *image = [self image:send filledWith:[[TGTheme shared] onAccentColour]];
	sCache[@"send-on-accent"] = image;
	return image;
}

+ (UIImage *)send {
	UIImage *svg = [self pathIconNamed:@"send"];
	if (svg)
		return svg;
	return [self iconNamed:@"send" draw:^(CGContextRef ctx, CGFloat s){
		// Official Telegram iOS / iMessage upward send arrow
		CGFloat cx = s / 2.0f;
		CGFloat topY = s * 0.27f;
		CGFloat botY = s * 0.73f;
		CGFloat wingDX = s * 0.20f;
		CGFloat wingDY = s * 0.20f;

		CGContextSetLineWidth(ctx, TGIconStroke);
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
	UIImage *svg = [self pathIconNamed:@"attach"];
	if (svg)
		return svg;
	return [self iconNamed:@"attach" draw:^(CGContextRef ctx, CGFloat s){
		// Elegant 45-degree angled paperclip
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, s / 2.0f, s / 2.0f);
		CGContextRotateCTM(ctx, -M_PI / 4.0f);

		CGContextSetLineWidth(ctx, TGIconStroke);
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



+ (UIImage *)chevronDown {
	return [self iconNamed:@"chevronDown" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);

		CGFloat mid = TGHalf(s);
		CGContextMoveToPoint(ctx, 7.0f, mid - 3.5f);
		CGContextAddLineToPoint(ctx, mid, mid + 3.5f);
		CGContextAddLineToPoint(ctx, s - 7.0f, mid - 3.5f);
		CGContextStrokePath(ctx);
	}];
}



+ (UIImage *)document {
	UIImage *svg = [self pathIconNamed:@"document"];
	if (svg)
		return svg;
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
	UIImage *svg = [self pathIconNamed:@"pin"];
	if (svg)
		return svg;
	return [self iconNamed:@"pin" draw:^(CGContextRef ctx, CGFloat s){
		// Stationery pushpin angled at 45 degrees
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, s / 2.0f, s / 2.0f);
		CGContextRotateCTM(ctx, -M_PI / 4.0f);

		// Needle
		CGContextSetLineWidth(ctx, TGIconStroke);
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
	UIImage *svg = [self pathIconNamed:@"microphone"];
	if (svg)
		return svg;
	return [self iconNamed:@"microphone" draw:^(CGContextRef ctx, CGFloat s){
		// capsule head, stand, base
		UIBezierPath *head = [UIBezierPath bezierPathWithRoundedRect:
				CGRectMake(TGHalf(s) - 4, 3, 8, 13) cornerRadius:4];
		CGContextAddPath(ctx, head.CGPath);
		CGContextFillPath(ctx);

		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextAddArc(ctx, TGHalf(s), 14, 7, 0, M_PI, 0);
		CGContextStrokePath(ctx);

		CGContextMoveToPoint(ctx, TGHalf(s), 21);
		CGContextAddLineToPoint(ctx, TGHalf(s), s - 4);
		CGContextStrokePath(ctx);
	}];
}

+ (void)tintImageView:(UIImageView *)view colour:(UIColor *)colour {
	if (!view || !colour)
		return;
	if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_6_1) {
		view.tintColor = colour;
		return;
	}
	UIImage *tinted = [self image:view.image filledWith:colour];
	if (tinted)
		view.image = tinted;
}

+ (UIImage *)image:(UIImage *)image filledWith:(UIColor *)colour {
	if (!image.CGImage || !colour)
		return nil;
	CGRect box = CGRectMake(0, 0, image.size.width, image.size.height);
	UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextTranslateCTM(ctx, 0, image.size.height);
	CGContextScaleCTM(ctx, 1.0, -1.0);
	CGContextClipToMask(ctx, box, image.CGImage);
	[colour setFill];
	CGContextFillRect(ctx, box);
	UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return out;
}

/// U+2328 would say "keyboard", but iOS 6 has no glyph for it.
+ (UIImage *)botKeyboard {
	return [self iconNamed:@"botKeyboard" draw:^(CGContextRef ctx, CGFloat s){
		CGFloat key = (s - 10) / 3.0f;
		for (int row = 0; row < 2; row++)
			for (int col = 0; col < 3; col++)
				CGContextFillRect(ctx, CGRectMake(3 + col * (key + 2), s * 0.3f + row * (key + 2),
												  key, key * 0.8f));
	}];
}

/// A smiling face. U+1F642 would be the obvious glyph, but it arrived in
/// Unicode 7.0 and iOS 7 draws it as an empty box.
+ (UIImage *)sticker {
	UIImage *svg = [self pathIconNamed:@"sticker"];
	if (svg)
		return svg;
	return [self iconNamed:@"sticker" draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, TGIconStroke);
		CGContextStrokeEllipseInRect(ctx, CGRectMake(3, 3, s - 6, s - 6));
		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.33f, s * 0.34f, 2.5f, 3.5f));
		CGContextFillEllipseInRect(ctx, CGRectMake(s * 0.60f, s * 0.34f, 2.5f, 3.5f));
		CGContextAddArc(ctx, TGHalf(s), s * 0.52f, s * 0.22f, 0.5f, M_PI - 0.5f, 0);
		CGContextStrokePath(ctx);
	}];
}







+ (UIImage *)skeuomorphicDisclosureChevron {
	NSString *key = @"skeuo_disclosure_chevron";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(9.0f, 14.0f);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// White etched drop shadow line below
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.80f);
	CGContextSetLineWidth(ctx, TGIconStroke);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextMoveToPoint(ctx, 2.0f, 2.5f);
	CGContextAddLineToPoint(ctx, 7.0f, 7.5f);
	CGContextAddLineToPoint(ctx, 2.0f, 12.5f);
	CGContextStrokePath(ctx);

	// Metallic slate chevron stroke
	CGContextSetRGBStrokeColor(ctx, 0.48f, 0.50f, 0.54f, 1.0f);
	CGContextSetLineWidth(ctx, TGIconStroke);
	CGContextMoveToPoint(ctx, 2.0f, 1.5f);
	CGContextAddLineToPoint(ctx, 7.0f, 6.5f);
	CGContextAddLineToPoint(ctx, 2.0f, 11.5f);
	CGContextStrokePath(ctx);

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, image);
	return image;
}

+ (UIImage *)skeuomorphicDisclosureChevronHighlighted {
	NSString *key = @"skeuo_disclosure_chevron_high";
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	CGSize size = CGSizeMake(9.0f, 14.0f);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextSetLineWidth(ctx, TGIconStroke);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextMoveToPoint(ctx, 2.0f, 1.5f);
	CGContextAddLineToPoint(ctx, 7.0f, 6.5f);
	CGContextAddLineToPoint(ctx, 2.0f, 11.5f);
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
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	UIColor *colour = selected ? [[TGTheme shared] accentColour] : [[TGTheme shared] separatorColour];
	CGContextSetFillColorWithColor(ctx, colour.CGColor);
	// The circle is 20 of the icon's 24 units; the box grows so it spans 22.
	CGRect box = CGRectInset(CGRectMake(0, 0, side, side), -side / 10, -side / 10);
	if (TGIconAddPath(ctx, selected ? "checkboxSelected" : "checkboxUnselected", box))
		CGContextFillPath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

+ (UIImage *)searchLensOfSize:(CGFloat)size colour:(UIColor *)colour {
	if (size <= 0) size = 16.0f;
	if (!colour) colour = [[TGTheme shared] secondaryTextColour];
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
	CGContextSetLineWidth(ctx, TGIconStroke);
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
	UIImage *svg = [self pathIconNamed:@"phoneCall"];
	if (svg)
		return svg;
	return [self iconNamed:@"phoneCall" draw:^(CGContextRef ctx, CGFloat s) {
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, TGHalf(s), TGHalf(s));
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
	NSString *key = [NSString stringWithFormat:@"tgAirplane-%.1f", size];
	UIImage *cached = TGIconsGetCached(key);
	if (cached) return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, [[TGTheme shared] accentColour].CGColor);
	CGRect box = CGRectInset(CGRectMake(0, 0, size, size), -size / 10, -size / 10);
	if (TGIconAddPath(ctx, "telegramAirplane", box))
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
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, [[TGTheme shared] accentColour].CGColor);
	if (TGIconAddPath(ctx, "verifiedBadge", CGRectInset(CGRectMake(0, 0, side, side), -1, -1)))
		CGContextFillPath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	TGIconsSetCached(key, img);
	return img;
}

@end

// vim:ft=objc
