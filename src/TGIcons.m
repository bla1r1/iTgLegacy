#import "TGIcons.h"
#import "TGTheme.h"

static NSMutableDictionary *sCache = nil;
static NSMutableDictionary *sSettingsIconCache = nil;

static inline id sGetCached(NSString *key) {
	return sCache ? sCache[key] : nil;
}

static inline void sSetCached(NSString *key, UIImage *img) {
	if (!sCache) sCache = [NSMutableDictionary dictionary];
	if (key && img) sCache[key] = img;
}

@implementation TGIcons

+ (void)flush {
	[sCache removeAllObjects];
	[sSettingsIconCache removeAllObjects];
}

+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw {
	BOOL flat = [TGTheme shared].isFlat;
	NSString *key = [NSString stringWithFormat:@"%@-%d", name, (int)flat];
	UIImage *cached = sGetCached(key);
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
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
	return image;
}

#pragma mark - menu glyphs

/// The line art beside each row of their pop-up menu. Drawn as strokes at a
/// single weight so the set reads as one family, which is what their 27x27
/// outline icons do.
+ (UIImage *)menuGlyphNamed:(NSString *)name {
	static NSSet *known = nil;
	if (!known)
		known = [NSSet setWithObjects:@"reply", @"undo", @"forward", @"copy",
				@"edit", @"delete", @"pin", @"unpin", @"mute", @"unmute",
				@"archive", @"unarchive", @"react",
				// the settings list
				@"notifications", @"privacy", @"data", @"chat", @"folder",
				@"devices", @"language", @"faq", @"policy",
				// the profile's action tiles
				@"call", @"video", @"search", @"more", nil];
	// An unknown name has to answer nil, not a blank square: a row with no
	// glyph is better than a row with a hole where one should be.
	if (![known containsObject:name])
		return nil;

	NSString *key = [@"menu-" stringByAppendingString:name];
	return [self iconNamed:key draw:^(CGContextRef ctx, CGFloat s){
		CGContextSetLineWidth(ctx, 1.8f);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGFloat m = s * 0.18f;              // margin, so every glyph shares a box

		if ([name isEqualToString:@"reply"] || [name isEqualToString:@"undo"]){
			// an arrow turning back on itself
			CGContextMoveToPoint(ctx, m + 5, s * 0.30f);
			CGContextAddLineToPoint(ctx, m, s * 0.45f);
			CGContextAddLineToPoint(ctx, m + 5, s * 0.60f);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, m, s * 0.45f);
			CGContextAddLineToPoint(ctx, s - m - 5, s * 0.45f);
			CGContextAddArc(ctx, s - m - 5, s * 0.62f, s * 0.17f, -M_PI_2, 0, 0);
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

		} else if ([name isEqualToString:@"pin"] || [name isEqualToString:@"unpin"]){
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
			// a heart
			CGContextMoveToPoint(ctx, s / 2, s - m - 2);
			CGContextAddCurveToPoint(ctx, m, s * 0.60f, m, s * 0.22f, s / 2, s * 0.38f);
			CGContextAddCurveToPoint(ctx, s - m, s * 0.22f, s - m, s * 0.60f, s / 2, s - m - 2);
			CGContextStrokePath(ctx);

		} else if ([name isEqualToString:@"call"]){
			// a handset on its diagonal
			CGContextSetLineWidth(ctx, 2.0f);
			CGContextMoveToPoint(ctx, m + 1, m + 4);
			CGContextAddCurveToPoint(ctx, m + 1, s * 0.70f, s * 0.70f, s - m - 1,
									 s - m - 4, s - m - 1);
			CGContextAddLineToPoint(ctx, s - m, s * 0.68f);
			CGContextAddLineToPoint(ctx, s * 0.62f, s * 0.58f);
			CGContextAddLineToPoint(ctx, s * 0.50f, s * 0.68f);
			CGContextAddCurveToPoint(ctx, s * 0.40f, s * 0.60f, s * 0.40f, s * 0.60f,
									 s * 0.32f, s * 0.50f);
			CGContextAddLineToPoint(ctx, s * 0.42f, s * 0.38f);
			CGContextAddLineToPoint(ctx, s * 0.32f, m);
			CGContextClosePath(ctx);
			CGContextStrokePath(ctx);

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

		} else if ([name isEqualToString:@"search"]){
			// a magnifier
			CGContextStrokeEllipseInRect(ctx, CGRectMake(m, m, s * 0.50f, s * 0.50f));
			CGContextMoveToPoint(ctx, m + s * 0.46f, m + s * 0.46f);
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
			// a question mark in a circle
			CGContextStrokeEllipseInRect(ctx, CGRectInset(
					CGRectMake(0, 0, s, s), m, m));
			CGContextAddArc(ctx, s / 2, s * 0.40f, s * 0.11f, M_PI, M_PI_2, 1);
			CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx, s / 2, s * 0.51f);
			CGContextAddLineToPoint(ctx, s / 2, s * 0.60f);
			CGContextStrokePath(ctx);
			CGContextFillEllipseInRect(ctx, CGRectMake(s / 2 - 1, s * 0.68f, 2, 2));

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

+ (UIImage *)mediaDiscOfSide:(CGFloat)side playing:(BOOL)playing {
	NSString *key = [NSString stringWithFormat:@"mediaDisc_%.0f_%d", side, playing];
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
	return image;
}

+ (UIImage *)fileDiscOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"fileDisc_%.0f", side];
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
	return image;
}

+ (UIImage *)microphoneOfSide:(CGFloat)side colour:(UIColor *)colour {
	NSString *key = [NSString stringWithFormat:@"mic_%.0f_%lu", side, (unsigned long)[colour hash]];
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
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
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
	return image;
}

+ (UIImage *)bubbleTailForColour:(UIColor *)colour outgoing:(BOOL)outgoing {
	NSString *key = [NSString stringWithFormat:@"tail_%d_%lu", outgoing, (unsigned long)[colour hash]];
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
	return image;
}

+ (UIImage *)ticksWhite:(BOOL)white {
	NSString *key = white ? @"ticks_white" : @"ticks_green";
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, image);
	return image;
}

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

+ (UIImage *)archiveAvatarOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"archiveAvatar_%.0f", side];
	UIImage *cached = sGetCached(key);
	if (cached) return cached;

	UIImage *img = TGGlyphAvatar(side, ^(CGContextRef ctx, CGFloat s){
		CGFloat w = s * 0.46f, x = (s - w) / 2;
		CGContextFillRect(ctx, CGRectMake(x, s * 0.32f, w, s * 0.10f));
		CGContextFillRect(ctx, CGRectMake(x + s * 0.03f, s * 0.44f,
										  w - s * 0.06f, s * 0.24f));
		CGContextSetRGBFillColor(ctx, 0.427f, 0.588f, 0.706f, 1.0f);
		CGContextFillRect(ctx, CGRectMake(s * 0.44f, s * 0.50f, s * 0.12f, s * 0.05f));
	});
	sSetCached(key, img);
	return img;
}

+ (UIImage *)savedMessagesAvatarOfSide:(CGFloat)side {
	NSString *key = [NSString stringWithFormat:@"savedAvatar_%.0f", side];
	UIImage *cached = sGetCached(key);
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
	sSetCached(key, img);
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
		// The glyph goes on top of the plate. It used to be composited with
		// kCGBlendModeDestinationIn, which cut the coloured square down to the
		// glyph instead of drawing a white glyph on it.
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

/// imageWithContentsOfFile: does not decode; the first draw does, on whatever
/// thread draws - the main one. Redrawing it here decodes it off the main
/// thread and scales it down to the size it will be shown at, so a 1280px
/// photo stops being resampled every frame it is on screen.
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

@end

// vim:ft=objc
