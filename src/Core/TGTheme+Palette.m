#import "TGThemeInternal.h"
#import "TGStyle.h"

#define rgb TGThemeRGB

// Light Skeuomorphic Palette (Classic iOS 6)
#define TG_BLUE_DARK4     rgb(0x51, 0x7D, 0xA2)   // classic header blue
#define TG_BLUE_LIGHT4    rgb(0x4C, 0xB3, 0xF5)   // links, dark accent
#define TG_BLUE_MEDIUM8   rgb(0x3D, 0x95, 0xD4)   // unread badge
#define TG_GREEN_LIGHT1   rgb(0xEF, 0xFE, 0xDD)   // outgoing bubble
#define TG_GREEN_BRIGHT1  rgb(0x5A, 0xCD, 0x30)   // online dot
#define TG_GRAY_LIGHT3    rgb(0xF7, 0xF7, 0xF7)   // input strip
#define TG_STEEL_LIGHT1   rgb(0xED, 0xEE, 0xF0)   // light gray surface
#define TG_STEEL_LIGHT3   rgb(0xE1, 0xE4, 0xE9)   // separators
#define TG_TEXT_PRIMARY   rgb(0x22, 0x22, 0x22)   // primary text
#define TG_TEXT_SECONDARY rgb(0x8D, 0x8E, 0x90)   // secondary text
#define TG_TEXT_TIME      rgb(0x95, 0x99, 0x9A)   // timestamp
#define TG_BLUE_SEMI8     rgb(0x51, 0xAE, 0xE7)   // settings value
#define TG_GRAY_SECTION   rgb(0x69, 0x6A, 0x6F)   // section caption
#define TG_BLUE_DARK3     rgb(0x5A, 0x8E, 0xBD)   // profile picture header
#define TG_BLUE_BLURPLE3  rgb(0x70, 0xAA, 0xEA)   // typing indicator
#define TG_STEEL_LIGHT6   rgb(0xC5, 0xC9, 0xCC)   // muted badge
#define TG_STEEL_LIGHT13  rgb(0xA1, 0xAA, 0xB3)   // file size
#define TG_FILE_TILE      rgb(0xEB, 0xF0, 0xF4)   // file glyph background
#define TG_MEDIA_CIRCLE   rgb(0x72, 0xB5, 0xE9)   // media circle
#define TG_FILE_NAME      rgb(0x4E, 0x9A, 0xD4)

// Dark Skeuomorphic Palette (Night iOS 6)
#define TG_GRAY_DARK16    rgb(0x20, 0x20, 0x20)   // bars
#define TG_GRAY_DARK15    rgb(0x21, 0x21, 0x21)   // lists, cards
#define TG_GRAY_DARK14    rgb(0x23, 0x23, 0x23)   // chat background
#define TG_GRAY_DARK13    rgb(0x33, 0x33, 0x33)   // incoming bubble, separators
#define TG_GRAY_DARK6     rgb(0x99, 0x99, 0x99)   // secondary text
#define TG_STEEL_DARK13   rgb(0x7D, 0x84, 0x8A)   // timestamp
#define TG_BLUE_DARK6     rgb(0x1B, 0x5A, 0x7D)   // outgoing bubble

@implementation TGTheme (Palette)

- (UIColor *)barColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK16 : TG_BLUE_DARK4;
}

- (UIColor *)barTitleColour {
	UIColor *imported = [self importedColour:@"barTitle"];
	if (imported) return imported;
	return [UIColor whiteColor];
}

- (UIColor *)barSubtitleColour {
	UIColor *imported = [self importedColour:@"barSubtitle"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK6 : [UIColor colorWithWhite:1.0f alpha:0.75f];
}

- (UIColor *)barButtonColour {
	UIColor *imported = [self importedColour:@"barButton"];
	if (imported) return imported;
	return self.isDarkStyle ? [self accentColour] : [UIColor whiteColor];
}

- (UIColor *)accentColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_BLUE_LIGHT4 : TG_BLUE_DARK4;
}

- (UIColor *)onAccentColour {
	return [UIColor whiteColor];
}

- (UIColor *)destructiveColour {
	UIColor *imported = [self importedColour:@"destructive"];
	if (imported) return imported;
	return rgb(0xE5, 0x39, 0x35);
}

- (UIColor *)hudBackgroundColour {
	return [UIColor colorWithWhite:0.0f alpha:0.75f];
}

- (UIColor *)hudTextColour {
	return [UIColor whiteColor];
}

- (UIColor *)snackbarBackgroundColour {
	if (self.isDarkStyle)
		return [UIColor colorWithRed:0.18f green:0.22f blue:0.26f alpha:0.98f];
	return [UIColor colorWithRed:0.24f green:0.28f blue:0.33f alpha:0.97f];
}

- (UIColor *)snackbarTextColour {
	return [UIColor whiteColor];
}

- (UIColor *)chatBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK14 : rgb(217, 222, 212);
}

- (UIColor *)bubbleMineColour {
	UIColor *imported = [self importedColour:@"bubbleMine"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_BLUE_DARK6 : TG_GREEN_LIGHT1;
}

- (UIColor *)bubbleTheirsColour {
	UIColor *imported = [self importedColour:@"bubbleTheirs"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK13 : [UIColor whiteColor];
}

- (UIColor *)bubbleBorderColour {
	if (self.isDarkStyle)
		return [UIColor colorWithWhite:1.0f alpha:0.08f];
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)listBackgroundColour {
	UIColor *imported = [self importedColour:@"listBackground"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK15 : [UIColor whiteColor];
}

- (UIColor *)groupedBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return rgb(0x0E, 0x0E, 0x0E);
	return [UIColor colorWithPatternImage:[TGTheme skeuomorphicPinstripePattern]];
}

- (UIColor *)cardBackgroundColour {
	UIColor *imported = [self importedColour:@"cardBackground"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK15 : [UIColor whiteColor];
}

- (UIColor *)placeholderColour {
	if (self.isDark)
		return [UIColor colorWithWhite:1.0f alpha:0.40f];
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

- (UIColor *)primaryTextColour {
	UIColor *imported = [self importedColour:@"primaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? [UIColor whiteColor] : TG_TEXT_PRIMARY;
}

- (UIColor *)secondaryTextColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_TEXT_SECONDARY;
}

// Time text color
- (UIColor *)timeColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_STEEL_DARK13 : TG_TEXT_TIME;
}

- (UIColor *)timeMineColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return [self timeColour];
}

- (UIColor *)listDateColour {
	return [self timeColour];
}

- (UIColor *)cellDetailColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_BLUE_LIGHT4 : TG_BLUE_SEMI8;
}

- (UIColor *)sectionHeaderColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_GRAY_SECTION;
}

- (UIColor *)profileHeaderColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK16 : TG_BLUE_DARK3;
}

- (UIColor *)actionTileBackgroundColour {
	UIColor *imported = [self importedColour:@"actionTile"];
	if (imported) return imported;
	return self.isDark ? [UIColor colorWithWhite:1.0f alpha:0.08f]
					   : [UIColor colorWithWhite:0.0f alpha:0.05f];
}

- (UIColor *)inputBarColour {
	if ([self hasCustomPalette])
		return [self barColour];
	return self.isDarkStyle ? TG_GRAY_DARK16 : TG_GRAY_LIGHT3;
}

- (UIColor *)searchBarBackgroundColour {
	UIColor *imported = [self importedColour:@"searchBarBackground"];
	if (imported) return imported;
	return self.isDarkStyle ? rgb(0x2E, 0x2E, 0x2E) : rgb(0xCD, 0xD3, 0xDC);
}

#pragma mark - media and file blocks

// File tile background color
- (UIColor *)fileTileColour {
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_FILE_TILE;
}

- (UIColor *)mediaCircleColour {
	return TG_MEDIA_CIRCLE;
}

- (UIColor *)fileNameColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_FILE_NAME;
}

- (UIColor *)fileMetaColour {
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_STEEL_LIGHT13;
}

// Timestamp badge plate over media
- (UIColor *)mediaStampColour {
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

- (UIColor *)mediaOverlayColour {
	return [UIColor colorWithWhite:0.0f alpha:0.50f];
}

- (UIColor *)mediaViewerBackdropColour {
	return [UIColor blackColor];
}

- (UIColor *)scrimColour {
	return [UIColor colorWithWhite:0.0f alpha:0.40f];
}

- (UIColor *)menuWashColour {
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)calloutBackgroundColour {
	if (self.isDarkStyle) {
		return rgb(0x22, 0x24, 0x28);
	}
	// Light / White theme: luminous white/pearl skeuomorphic card
	return [UIColor colorWithRed:0.96f green:0.97f blue:0.98f alpha:0.98f];
}

- (UIColor *)calloutTrayColour {
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:0.0f alpha:0.35f];
	}
	return [UIColor colorWithWhite:0.0f alpha:0.06f];
}

- (UIColor *)calloutBorderColour {
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.25f];
	}
	return [UIColor colorWithRed:0.72f green:0.75f blue:0.78f alpha:0.90f];
}

- (UIColor *)calloutDividerDarkColour {
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:0.0f alpha:0.45f];
	}
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)calloutDividerLightColour {
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.08f];
	}
	return [UIColor colorWithWhite:1.0f alpha:0.85f];
}

- (UIColor *)calloutGlossTopColour {
	UIColor *imported = [self importedColour:@"calloutGlossTop"];
	if (imported) return imported;
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.18f];
	}
	return [UIColor colorWithWhite:1.0f alpha:0.65f];
}

- (UIColor *)calloutGlossBottomColour {
	UIColor *imported = [self importedColour:@"calloutGlossBottom"];
	if (imported) return imported;
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.04f];
	}
	return [UIColor colorWithWhite:1.0f alpha:0.10f];
}

#pragma mark - chat list

- (UIColor *)badgeColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_BLUE_LIGHT4 : TG_BLUE_MEDIUM8;
}

- (UIColor *)badgeTextColour {
	return [UIColor whiteColor];
}

- (UIColor *)mutedBadgeColour {
	return self.isDarkStyle ? rgb(0x55, 0x55, 0x55) : TG_STEEL_LIGHT6;
}

- (UIColor *)typingColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_BLUE_LIGHT4 : TG_BLUE_BLURPLE3;
}

- (UIColor *)onlineColour {
	return TG_GREEN_BRIGHT1;
}

- (UIColor *)ticksColour {
	UIColor *imported = [self importedColour:@"ticks"];
	if (imported) return imported;
	return self.isDarkStyle ? rgb(0x4C, 0xB3, 0xF5) : rgb(0x51, 0x7D, 0xA2);
}

- (UIColor *)separatorColour {
	if ([self hasCustomPalette])
		return [self bubbleBorderColour];
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_STEEL_LIGHT3;
}

#pragma mark - service messages

// Date plate wash over wallpaper
- (UIColor *)serviceBubbleColour {
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.12f]
							: [UIColor colorWithWhite:0.0f alpha:0.30f];
}

- (UIColor *)unreadSeparatorColour {
	return [[self inputBarColour] colorWithAlphaComponent:0.92f];
}

- (UIColor *)serviceTextColour {
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.85f]
							: [UIColor whiteColor];
}

#pragma mark - map preview

- (UIColor *)mapPaperColour {
	return [UIColor colorWithRed:0.90f green:0.91f blue:0.87f alpha:1.0f];
}

- (UIColor *)mapRoadColour {
	return [UIColor whiteColor];
}

- (UIColor *)mapGreeneryColour {
	return [UIColor colorWithRed:0.78f green:0.86f blue:0.74f alpha:1.0f];
}

- (UIColor *)mapPinColour {
	return [UIColor colorWithRed:0.85f green:0.15f blue:0.15f alpha:1.0f];
}

- (UIColor *)mapPinShadowColour {
	return [UIColor colorWithWhite:0.0f alpha:0.25f];
}

#pragma mark - swipe actions

- (UIColor *)archiveActionColour {
	return rgb(0xA8, 0xB0, 0xBA);
}

- (UIColor *)muteActionColour {
	return rgb(0xFF, 0x94, 0x00);
}

- (UIColor *)recordLockColour {
	return [UIColor colorWithRed:0x1F / 255.0f green:0x24 / 255.0f
							blue:0x2E / 255.0f alpha:0.92f];
}

#pragma mark - the call screen

// The call screen is its own skin - it is not a list on a theme surface - but
// its colours belong here with the rest of them rather than inside the
// controller, where nothing else could see or override them.
- (NSArray *)callGradientColours {
	return @[rgb(0x6E, 0x61, 0xDE), rgb(0x59, 0x99, 0xF2)];
}

- (NSArray *)callGradientColoursConnected {
	return @[rgb(0x45, 0xB0, 0x8C), rgb(0x73, 0xC4, 0x6E)];
}

- (NSArray *)callGradientColoursFailed {
	return @[rgb(0x73, 0x29, 0x29), rgb(0x4D, 0x1A, 0x1F)];
}

- (UIColor *)callEndColour {
	return rgb(0xE5, 0x33, 0x33);
}

- (UIColor *)callAcceptColour {
	return rgb(0x33, 0xCC, 0x4D);
}

- (UIColor *)callControlColour {
	return [UIColor colorWithWhite:1.0f alpha:0.20f];
}

- (UIColor *)callControlActiveColour {
	return [UIColor colorWithWhite:1.0f alpha:0.40f];
}

#pragma mark - charts

- (NSArray *)chartPalette {
	return @[rgb(0xF5, 0xA6, 0x24),   // orange
			 rgb(0x33, 0x70, 0xED),   // blue
			 rgb(0x59, 0xC7, 0xFA),   // light blue
			 rgb(0x6B, 0x59, 0xD9),   // violet
			 rgb(0x4A, 0xCC, 0x70),   // green
			 rgb(0xD9, 0x59, 0x59)];  // red
}

- (UIColor *)giftStarColour {
	return rgb(0xFF, 0xB3, 0x00);
}

- (UIColor *)skeuoShineColour {
	return [UIColor colorWithWhite:1.0f alpha:0.18f];
}

- (NSArray *)skeuoShineGradientColours {
	return @[
		(id)[UIColor colorWithWhite:1.0f alpha:0.45f].CGColor,
		(id)[UIColor colorWithWhite:1.0f alpha:0.04f].CGColor
	];
}

- (UIColor *)etchedTextShadowColour {
	return [UIColor colorWithWhite:1.0f alpha:0.7f];
}

- (UIColor *)navBarTextShadowColour {
	return [UIColor colorWithWhite:0.0f alpha:0.4f];
}

- (UIColor *)buttonHighlightColour {
	return [[self accentColour] colorWithAlphaComponent:0.4f];
}

- (UIColor *)callSubtitleColour {
	return [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
}

- (CGFloat)bubbleCornerRadius {
	return TGMetricCornerBubbleSkeuo;
}

- (CGFloat)bubbleJoinedCornerRadius {
	return TGMetricCornerBubbleJoined;
}

- (CGFloat)bubbleBorderWidth {
	return TGMetricBorderWidth;
}

@end

#pragma mark - TGTheme (Skeuomorphism)

static const CGFloat kSkeuoCapInset    = TGMetricPadTiny;
static const CGFloat kSkeuoRimInset    = 0.75f;
static const CGFloat kSkeuoThumbPad    = TGMetricPadTiny;
static const CGFloat kSkeuoThumbLift   = 1.5f;

@implementation TGTheme (Skeuomorphism)

+ (UIImage *)skeuomorphicBarImageWithColor:(UIColor *)tint height:(CGFloat)height {
	CGFloat width = 8.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat r = 0, g = 0, b = 0, a = 1.0f;
	if (![tint getRed:&r green:&g blue:&b alpha:&a]) {
		r = 0.32f; g = 0.49f; b = 0.64f; a = 1.0f;
	}

	CGFloat topY = 0.0f;
	if (height >= 60.0f) {
		topY = TGMetricPadWide; // 20pt status bar area on attached bar
	}

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

	// 1. Status bar area (if attached)
	if (topY > 0.0f) {
		CGFloat statusComps[] = {
			r * 0.85f, g * 0.85f, b * 0.85f, a,
			MIN(1.0f, r * 1.35f), MIN(1.0f, g * 1.35f), MIN(1.0f, b * 1.35f), a
		};
		CGFloat statusLocs[] = { 0.0f, 1.0f };
		CGGradientRef statusGrad = CGGradientCreateWithColorComponents(cs, statusComps, statusLocs, 2);
		CGContextDrawLinearGradient(ctx, statusGrad, CGPointMake(0, 0), CGPointMake(0, topY), 0);
		CGGradientRelease(statusGrad);
	}

	// 2. Continuous smooth metallic gradient (authentic iOS 6 slate sheen - Picture 3)
	CGFloat barComps[] = {
		MIN(1.0f, r * 1.42f), MIN(1.0f, g * 1.42f), MIN(1.0f, b * 1.42f), a,
		MIN(1.0f, r * 1.08f), MIN(1.0f, g * 1.08f), MIN(1.0f, b * 1.08f), a,
		r * 0.75f, g * 0.75f, b * 0.75f, a
	};
	CGFloat barLocs[] = { 0.0f, 0.45f, 1.0f };
	CGGradientRef barGrad = CGGradientCreateWithColorComponents(cs, barComps, barLocs, 3);
	CGContextDrawLinearGradient(ctx, barGrad, CGPointMake(0, topY), CGPointMake(0, height), 0);
	CGGradientRelease(barGrad);

	CGColorSpaceRelease(cs);

	// Top specular highlight line
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.45f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextMoveToPoint(ctx, 0, topY + 0.5f);
	CGContextAddLineToPoint(ctx, width, topY + 0.5f);
	CGContextStrokePath(ctx);

	// Bottom dark hairline
	CGContextSetRGBStrokeColor(ctx, 0.11f, 0.11f, 0.11f, 0.95f);
	CGContextMoveToPoint(ctx, 0, height - 0.5f);
	CGContextAddLineToPoint(ctx, width, height - 0.5f);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(0, kSkeuoCapInset, 0, kSkeuoCapInset)];
}

+ (UIImage *)skeuomorphicButtonImageWithColor:(UIColor *)tint
                                       height:(CGFloat)height
                                  highlighted:(BOOL)highlighted
                                 cornerRadius:(CGFloat)radius {
	CGFloat width = radius * 2.0f + 12.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat r = 0, g = 0, b = 0, a = 1.0f;
	if (![tint getRed:&r green:&g blue:&b alpha:&a]) {
		r = 0.5f; g = 0.5f; b = 0.5f; a = 1.0f;
	}

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.5f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
	[path addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	if (!highlighted) {
		// Normal glossy 2-stage gradient
		CGFloat comps[] = {
			MIN(r * 1.25f, 1.0f), MIN(g * 1.25f, 1.0f), MIN(b * 1.25f, 1.0f), a,
			r, g, b, a,
			r * 0.94f, g * 0.94f, b * 0.94f, a,
			r * 0.82f, g * 0.82f, b * 0.82f, a
		};
		CGFloat locs[] = { 0.0f, 0.50f, 0.51f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 4);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		// Top inner specular rim
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.38f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, kSkeuoRimInset, kSkeuoRimInset);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:MAX(radius - kSkeuoRimInset, 0.0f)];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);
	} else {
		// Highlighted / pressed recessed gradient
		CGFloat comps[] = {
			r * 0.70f, g * 0.70f, b * 0.70f, a,
			r * 0.85f, g * 0.85f, b * 0.85f, a,
			r * 0.92f, g * 0.92f, b * 0.92f, a
		};
		CGFloat locs[] = { 0.0f, 0.60f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		// Inset shadow at top
		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.35f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, kSkeuoRimInset, kSkeuoRimInset);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:MAX(radius - kSkeuoRimInset, 0.0f)];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);
	}
	CGColorSpaceRelease(cs);

	// Outer border stroke
	CGContextSetRGBStrokeColor(ctx, r * 0.65f, g * 0.65f, b * 0.65f, 0.95f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (UIImage *)buttonImageForStyle:(TGButtonStyle)style
                     highlighted:(BOOL)highlighted
                          height:(CGFloat)height {
	UIColor *tint = nil;
	switch (style) {
		case TGButtonStyleAction:
			tint = rgb(0x42, 0x82, 0xB8);
			break;
		case TGButtonStyleSilver:
			tint = rgb(0xD0, 0xD4, 0xDA);
			break;
		case TGButtonStyleDestructive:
			tint = rgb(0xC8, 0x2E, 0x2E);
			break;
		case TGButtonStyleSuccess:
			tint = rgb(0x3B, 0xA2, 0x48);
			break;
		case TGButtonStyleGhost:
			tint = [TGTheme shared].isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.12f] : [UIColor colorWithWhite:0.0f alpha:0.08f];
			break;
	}
	return [self skeuomorphicButtonImageWithColor:tint
                                          height:height
                                     highlighted:highlighted
                                    cornerRadius:TGMetricCornerControl];
}

+ (UIImage *)skeuomorphicPinstripePattern {
	CGFloat width = 2.0f, height = 2.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	TGTheme *theme = [TGTheme shared];
	if (theme.isDarkStyle) {
		CGContextSetRGBFillColor(ctx, 0.10f, 0.11f, 0.13f, 1.0f);
		CGContextFillRect(ctx, CGRectMake(0, 0, 1.0f, height));
		CGContextSetRGBFillColor(ctx, 0.08f, 0.09f, 0.10f, 1.0f);
		CGContextFillRect(ctx, CGRectMake(1.0f, 0, 1.0f, height));
	} else {
		// Classic iOS 6 fine woven pinstripes
		CGContextSetRGBFillColor(ctx, 0.85f, 0.86f, 0.89f, 1.0f);
		CGContextFillRect(ctx, CGRectMake(0, 0, 1.0f, height));
		CGContextSetRGBFillColor(ctx, 0.77f, 0.80f, 0.83f, 1.0f);
		CGContextFillRect(ctx, CGRectMake(1.0f, 0, 1.0f, height));
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicPaperGrainPattern {
	CGFloat width = 16.0f, height = 16.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	TGTheme *theme = [TGTheme shared];
	if (theme.isDarkStyle) {
		CGContextSetRGBFillColor(ctx, 0.11f, 0.12f, 0.14f, 1.0f);
	} else {
		CGContextSetRGBFillColor(ctx, 0.92f, 0.93f, 0.94f, 1.0f);
	}
	CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

	// Fine deterministic micro-grain
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			int h = ((x * 47 + y * 31 + (x ^ y)) % 17);
			if (h == 0) {
				if (theme.isDarkStyle) {
					CGContextSetRGBFillColor(ctx, 0.15f, 0.16f, 0.18f, 0.40f);
				} else {
					CGContextSetRGBFillColor(ctx, 0.85f, 0.87f, 0.89f, 0.45f);
				}
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			} else if (h == 1) {
				if (theme.isDarkStyle) {
					CGContextSetRGBFillColor(ctx, 0.08f, 0.09f, 0.10f, 0.35f);
				} else {
					CGContextSetRGBFillColor(ctx, 0.98f, 0.98f, 1.00f, 0.35f);
				}
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			}
		}
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicLinenPattern {
	CGFloat width = 16.0f, height = 16.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	TGTheme *theme = [TGTheme shared];
	// Base tone: authentic Apple charcoal linen or slate
	if (theme.isDarkStyle) {
		CGContextSetRGBFillColor(ctx, 0.14f, 0.15f, 0.17f, 1.0f);
	} else {
		CGContextSetRGBFillColor(ctx, 0.22f, 0.23f, 0.26f, 1.0f);
	}
	CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

	// Cross-hatch threads with highlights and depth shadows
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			BOOL vertRib = (x % 4 == 0);
			BOOL vertShadow = (x % 4 == 1);
			BOOL horizRib = (y % 4 == 0);
			BOOL horizShadow = (y % 4 == 1);
			int noise = ((x * 37 + y * 19 + ((x * 7) ^ (y * 11))) % 11);

			if (vertRib && horizRib) {
				// Interlaced thread crest: subtle highlight
				CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 0.12f);
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			} else if (vertShadow || horizShadow) {
				// Thread recess: depth shadow
				CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.22f);
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			} else if (noise == 0) {
				CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 0.06f);
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			} else if (noise == 1) {
				CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.10f);
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			}
		}
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicParchmentPattern {
	CGFloat width = 32.0f, height = 32.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	TGTheme *theme = [TGTheme shared];
	if (theme.isDarkStyle) {
		// Vintage aged dark parchment
		CGContextSetRGBFillColor(ctx, 0.18f, 0.16f, 0.13f, 1.0f);
	} else {
		// Classic Notes app warm cream parchment
		CGContextSetRGBFillColor(ctx, 0.96f, 0.94f, 0.88f, 1.0f);
	}
	CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

	// Laid paper horizontal watermark line (spaced every 16pt)
	for (int y = 0; y < (int)height; y += 16) {
		if (theme.isDarkStyle) {
			CGContextSetRGBFillColor(ctx, 0.13f, 0.11f, 0.09f, 0.40f);
		} else {
			CGContextSetRGBFillColor(ctx, 0.88f, 0.84f, 0.74f, 0.35f);
		}
		CGContextFillRect(ctx, CGRectMake(0, y, width, 1.0f));
	}

	// Natural organic paper fibers and warm flecks
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			int h = ((x * 53 + y * 29 + (x ^ (y * 3))) % 19);
			if (h == 0) {
				// Fiber fleck
				if (theme.isDarkStyle) {
					CGContextSetRGBFillColor(ctx, 0.24f, 0.20f, 0.16f, 0.45f);
				} else {
					CGContextSetRGBFillColor(ctx, 0.85f, 0.79f, 0.65f, 0.40f);
				}
				CGContextFillRect(ctx, CGRectMake(x, y, 1.5f, 1.0f));
			} else if (h == 1) {
				// Fine light tooth
				if (theme.isDarkStyle) {
					CGContextSetRGBFillColor(ctx, 0.22f, 0.19f, 0.15f, 0.30f);
				} else {
					CGContextSetRGBFillColor(ctx, 0.99f, 0.98f, 0.94f, 0.30f);
				}
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			}
		}
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicFeltPattern {
	CGFloat width = 24.0f, height = 24.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	TGTheme *theme = [TGTheme shared];
	if (theme.isDarkStyle) {
		// Deep pine casino felt
		CGContextSetRGBFillColor(ctx, 0.08f, 0.18f, 0.11f, 1.0f);
	} else {
		// Authentic Apple Game Center billiard felt
		CGContextSetRGBFillColor(ctx, 0.11f, 0.31f, 0.16f, 1.0f);
	}
	CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

	// Soft stippled wool fibers
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			int h = ((x * 41 + y * 23 + (x ^ (y * 5))) % 13);
			if (h == 0) {
				// Light fiber highlight
				if (theme.isDarkStyle) {
					CGContextSetRGBFillColor(ctx, 0.13f, 0.28f, 0.17f, 0.50f);
				} else {
					CGContextSetRGBFillColor(ctx, 0.17f, 0.44f, 0.23f, 0.45f);
				}
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			} else if (h == 1) {
				// Shadow fiber depth
				if (theme.isDarkStyle) {
					CGContextSetRGBFillColor(ctx, 0.04f, 0.10f, 0.06f, 0.55f);
				} else {
					CGContextSetRGBFillColor(ctx, 0.06f, 0.18f, 0.09f, 0.50f);
				}
				CGContextFillRect(ctx, CGRectMake(x, y, 1.0f, 1.0f));
			}
		}
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)textureImageForType:(TGWallpaperType)type {
	UIImage *tile = nil;
	switch (type) {
		case TGWallpaperTypePaperGrain:
			tile = [self skeuomorphicPaperGrainPattern];
			break;
		case TGWallpaperTypePinstripes:
			tile = [self skeuomorphicPinstripePattern];
			break;
		case TGWallpaperTypeLinen:
			tile = [self skeuomorphicLinenPattern];
			break;
		case TGWallpaperTypeParchment:
			tile = [self skeuomorphicParchmentPattern];
			break;
		case TGWallpaperTypeFelt:
			tile = [self skeuomorphicFeltPattern];
			break;
		default:
			return nil;
	}
	if (!tile) return nil;

	CGSize canvasSize = [UIScreen mainScreen].bounds.size;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(canvasSize, YES, scale);
	[[UIColor colorWithPatternImage:tile] setFill];
	UIRectFill(CGRectMake(0.0f, 0.0f, canvasSize.width, canvasSize.height));
	UIImage *canvas = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return canvas;
}

+ (UIImage *)skeuomorphicWellImageWithHeight:(CGFloat)height cornerRadius:(CGFloat)radius {
	CGFloat width = radius * 2.0f + 16.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.0f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

	// Background fill
	if ([TGTheme shared].isDarkStyle) {
		CGContextSetRGBFillColor(ctx, 0.14f, 0.16f, 0.18f, 1.0f);
	} else {
		CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	}
	CGContextAddPath(ctx, path.CGPath);
	CGContextFillPath(ctx);

	// Inner shadow at top
	CGContextSaveGState(ctx);
	[path addClip];
	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.20f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);
	CGContextRestoreGState(ctx);

	// Outer border stroke
	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.25f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (UIImage *)skeuomorphicSliderTrackImageFilled:(BOOL)filled {
	CGFloat width = 18.0f;
	CGFloat height = TGMetricSliderTrackH;
	CGFloat radius = TGHalf(height);
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.0f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
	[path addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	if (filled) {
		CGFloat comps[] = {
			0.14f, 0.45f, 0.88f, 1.0f,
			0.09f, 0.32f, 0.68f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.45f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, radius, 1.0f);
		CGContextAddLineToPoint(ctx, width - radius, 1.0f);
		CGContextStrokePath(ctx);
	} else {
		CGFloat comps[] = {
			0.70f, 0.72f, 0.75f, 1.0f,
			0.88f, 0.90f, 0.92f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.35f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, radius, 1.0f);
		CGContextAddLineToPoint(ctx, width - radius, 1.0f);
		CGContextStrokePath(ctx);
	}
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.30f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (UIImage *)skeuomorphicSliderThumbWithRadius:(CGFloat)radius {
	CGFloat side = radius * 2.0f + 4.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect circle = CGRectMake(kSkeuoThumbPad, kSkeuoThumbLift, TGDoubled(radius), TGDoubled(radius));
	UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:circle];
	[p addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGFloat comps[] = {
		0.98f, 0.98f, 0.99f, 1.0f,
		0.86f, 0.88f, 0.90f, 1.0f,
		0.74f, 0.76f, 0.78f, 1.0f
	};
	CGFloat locs[] = { 0.0f, 0.55f, 1.0f };
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, kSkeuoThumbLift), CGPointMake(0, kSkeuoThumbLift + radius * 2.0f), 0);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	// Inner rim
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.70f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circle, kSkeuoRimInset, kSkeuoRimInset)].CGPath);
	CGContextStrokePath(ctx);

	// Outer border
	CGContextSetRGBStrokeColor(ctx, 0.50f, 0.52f, 0.55f, 0.95f);
	CGContextAddPath(ctx, p.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicSwitchTrackImageOn:(BOOL)isOn {
	CGFloat width = TGMetricSwitchW;
	CGFloat height = TGMetricSwitchH;
	CGFloat radius = TGHalf(height);
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.0f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
	[path addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	if (isOn) {
		CGFloat comps[] = {
			0.14f, 0.45f, 0.88f, 1.0f,
			0.10f, 0.36f, 0.74f, 1.0f,
			0.08f, 0.28f, 0.62f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 0.55f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.40f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, 1.0f, 1.0f);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:radius - 1.0f];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);

		NSDictionary *attrs = @{
			NSFontAttributeName: TGFontMicroStrong(),
			NSForegroundColorAttributeName: [UIColor whiteColor]
		};
		[@"ON" drawAtPoint:CGPointMake(9.0f, 8.5f) withAttributes:attrs];
	} else {
		CGFloat comps[] = {
			0.82f, 0.84f, 0.87f, 1.0f,
			0.90f, 0.92f, 0.94f, 1.0f,
			0.95f, 0.96f, 0.97f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 0.40f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.30f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, 1.0f, 1.0f);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:radius - 1.0f];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);

		NSDictionary *attrs = @{
			NSFontAttributeName: TGFontMicroStrong(),
			NSForegroundColorAttributeName: [UIColor colorWithWhite:0.48f alpha:1.0f]
		};
		[@"OFF" drawAtPoint:CGPointMake(24.0f, 8.5f) withAttributes:attrs];
	}
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.35f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *trackImg = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return trackImg;
}

+ (UIImage *)skeuomorphicSwitchThumbImage {
	CGFloat side = TGMetricSwitchThumbD;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect circle = CGRectMake(0.5f, 0.5f, side - 1.0f, side - 1.0f);
	UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:circle];
	[p addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGFloat comps[] = {
		0.99f, 0.99f, 1.00f, 1.0f,
		0.92f, 0.93f, 0.95f, 1.0f,
		0.80f, 0.82f, 0.85f, 1.0f
	};
	CGFloat locs[] = { 0.0f, 0.60f, 1.0f };
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, side), 0);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.80f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circle, 1.0f, 1.0f)].CGPath);
	CGContextStrokePath(ctx);

	CGContextSetLineWidth(ctx, 1.0f);
	CGFloat midX = TGHalf(side);
	CGFloat ridgeH = 10.0f;
	CGFloat ridgeY = TGCenteredOrigin(side, ridgeH);
	CGFloat offsets[] = { -3.0f, 0.0f, 3.0f };
	for (int i = 0; i < 3; i++) {
		CGFloat rx = midX + offsets[i];
		CGContextSetRGBStrokeColor(ctx, 0.55f, 0.58f, 0.62f, 0.80f);
		CGContextMoveToPoint(ctx, rx, ridgeY);
		CGContextAddLineToPoint(ctx, rx, ridgeY + ridgeH);
		CGContextStrokePath(ctx);
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.90f);
		CGContextMoveToPoint(ctx, rx + 0.5f, ridgeY);
		CGContextAddLineToPoint(ctx, rx + 0.5f, ridgeY + ridgeH);
		CGContextStrokePath(ctx);
	}

	CGContextSetRGBStrokeColor(ctx, 0.45f, 0.48f, 0.52f, 0.95f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, p.CGPath);
	CGContextStrokePath(ctx);

	UIImage *thumbImg = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return thumbImg;
}

+ (void)applySkeuomorphicStyleToButton:(UIButton *)button style:(TGButtonStyle)style {
	if (!button)
		return;
	CGFloat h = button.bounds.size.height > 0 ? button.bounds.size.height : TGMetricButtonHeight;
	UIImage *norm = [self buttonImageForStyle:style highlighted:NO height:h];
	UIImage *high = [self buttonImageForStyle:style highlighted:YES height:h];
	[button setBackgroundImage:norm forState:UIControlStateNormal];
	[button setBackgroundImage:high forState:UIControlStateHighlighted];
	button.titleLabel.font = TGFontRowStrong();

	if (style == TGButtonStyleSilver || style == TGButtonStyleGhost) {
		[button setTitleColor:TG_TEXT_PRIMARY forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.80f] forState:UIControlStateNormal];
		button.titleLabel.shadowOffset = CGSizeMake(0, 1.0f);
	} else {
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.45f] forState:UIControlStateNormal];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1.0f);
	}
}

+ (void)applySkeuomorphicInputStyle:(UITextField *)field {
	if (!field)
		return;
	CGFloat h = field.bounds.size.height > 0 ? field.bounds.size.height : TGMetricRow;
	field.background = [self skeuomorphicWellImageWithHeight:h cornerRadius:TGMetricCornerControl];
	field.font = TGFontInput();
	field.textColor = [[TGTheme shared] primaryTextColour];
}

+ (UIImage *)skeuomorphicInputBarImageWithHeight:(CGFloat)height {
	CGFloat width = TGMetricPadSmall;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	TGTheme *theme = [TGTheme shared];
	if (theme.isDarkStyle) {
		CGFloat comps[] = {
			0.18f, 0.19f, 0.21f, 1.0f,
			0.14f, 0.15f, 0.16f, 1.0f,
			0.10f, 0.11f, 0.12f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 0.5f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		// Top highlight
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.15f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, 0, 0.5f);
		CGContextAddLineToPoint(ctx, width, 0.5f);
		CGContextStrokePath(ctx);
	} else {
		// Classic iOS 6 brushed aluminum satin gradient
		CGFloat comps[] = {
			0.92f, 0.93f, 0.95f, 1.0f,
			0.82f, 0.84f, 0.86f, 1.0f,
			0.72f, 0.74f, 0.77f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 0.5f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		// Top 1px crisp specular highlight line
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.90f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, 0, 0.5f);
		CGContextAddLineToPoint(ctx, width, 0.5f);
		CGContextStrokePath(ctx);
	}
	CGColorSpaceRelease(cs);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	CGFloat cap = TGMetricPadTiny;
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap)];
}

+ (UIImage *)skeuomorphicTabSelectionIndicator {
	return nil;
}

+ (UIImage *)skeuomorphicGroupedCellBackgroundForRow:(NSInteger)row
                                           totalRows:(NSInteger)total
                                         highlighted:(BOOL)highlighted
                                               width:(CGFloat)width
                                              height:(CGFloat)height {
	CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
	if (screenW <= 0) screenW = 320.0f;
	CGFloat baseH = TGMetricRow;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(screenW, baseH), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat margin = TGMetricPad - 2.0f;
	CGFloat cardW = screenW - margin * 2.0f;
	CGRect cardRect = CGRectMake(margin, 0, cardW, baseH);

	BOOL isFirst = (row == 0);
	BOOL isLast = (row >= total - 1);
	CGFloat radius = TGMetricCornerCard - 2.0f;

	UIRectCorner corners = 0;
	if (isFirst && isLast) {
		corners = UIRectCornerAllCorners;
	} else if (isFirst) {
		corners = UIRectCornerTopLeft | UIRectCornerTopRight;
	} else if (isLast) {
		corners = UIRectCornerBottomLeft | UIRectCornerBottomRight;
	}

	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:cardRect
											   byRoundingCorners:corners
													 cornerRadii:CGSizeMake(radius, radius)];

	TGTheme *theme = [TGTheme shared];
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

	if (highlighted) {
		// Classic Apple blue gradient for selected row
		[path addClip];
		CGFloat comps[] = {
			0.02f, 0.44f, 0.92f, 1.0f,
			0.01f, 0.28f, 0.77f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, baseH), 0);
		CGGradientRelease(grad);

		// Top inner hairline
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.30f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, margin + (isFirst ? radius : 0), 0.5f);
		CGContextAddLineToPoint(ctx, margin + cardW - (isFirst ? radius : 0), 0.5f);
		CGContextStrokePath(ctx);
	} else {
		// Background fill
		if (theme.isDarkStyle) {
			[rgb(0x22, 0x24, 0x28) setFill];
		} else {
			[[UIColor whiteColor] setFill];
		}
		[path fill];

		// Outer border
		UIColor *borderCol = theme.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.12f] : rgb(0xBE, 0xBE, 0xC2);
		[borderCol setStroke];
		path.lineWidth = 1.0f;
		[path stroke];

		// Etched bottom highlight on bottom edge of card
		if (isLast) {
			UIColor *bottomShine = theme.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.04f] : [UIColor colorWithWhite:1.0f alpha:0.75f];
			[bottomShine setStroke];
			CGContextSetLineWidth(ctx, 1.0f);
			CGContextMoveToPoint(ctx, margin + radius, baseH - 0.5f);
			CGContextAddLineToPoint(ctx, margin + cardW - radius, baseH - 0.5f);
			CGContextStrokePath(ctx);
		}

		// Etched separator between rows (does not touch outer border!)
		if (!isLast) {
			CGFloat divInset = TGMetricPad + TGMetricPadTiny;
			// Dark hairline
			UIColor *darkLine = theme.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.08f] : rgb(0xE2, 0xE2, 0xE6);
			[darkLine setStroke];
			CGContextSetLineWidth(ctx, 0.5f);
			CGContextMoveToPoint(ctx, margin + divInset, baseH - 1.0f);
			CGContextAddLineToPoint(ctx, margin + cardW - 1.0f, baseH - 1.0f);
			CGContextStrokePath(ctx);

			// White highlight line underneath
			UIColor *whiteLine = theme.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.04f] : [UIColor whiteColor];
			[whiteLine setStroke];
			CGContextSetLineWidth(ctx, 0.5f);
			CGContextMoveToPoint(ctx, margin + divInset, baseH - 0.5f);
			CGContextAddLineToPoint(ctx, margin + cardW - 1.0f, baseH - 0.5f);
			CGContextStrokePath(ctx);
		}
	}
	CGColorSpaceRelease(cs);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	// 9-slice resizable insets
	UIEdgeInsets capInsets;
	CGFloat capX = margin + radius + TGMetricPadTiny;
	if (isFirst && isLast) {
		capInsets = UIEdgeInsetsMake(radius + TGMetricPadTiny, capX, radius + TGMetricPadTiny, capX);
	} else if (isFirst) {
		capInsets = UIEdgeInsetsMake(radius + TGMetricPadTiny, capX, TGMetricPadTiny, capX);
	} else if (isLast) {
		capInsets = UIEdgeInsetsMake(TGMetricPadTiny, capX, radius + TGMetricPadTiny, capX);
	} else {
		capInsets = UIEdgeInsetsMake(TGMetricPadTiny, capX, TGMetricPadTiny, capX);
	}

	return [img resizableImageWithCapInsets:capInsets resizingMode:UIImageResizingModeStretch];
}

- (void)styleGroupedCell:(UITableViewCell *)cell forRow:(NSInteger)row totalRows:(NSInteger)total {
	if (!cell) return;
	[self styleCell:cell];
	cell.backgroundColor = [UIColor clearColor];
	cell.contentView.backgroundColor = [UIColor clearColor];
	UIImage *norm = [TGTheme skeuomorphicGroupedCellBackgroundForRow:row totalRows:total highlighted:NO width:0 height:0];
	UIImage *high = [TGTheme skeuomorphicGroupedCellBackgroundForRow:row totalRows:total highlighted:YES width:0 height:0];
	cell.backgroundView = [[UIImageView alloc] initWithImage:norm];
	cell.selectedBackgroundView = [[UIImageView alloc] initWithImage:high];
}

- (NSArray *)skeuoBubbleMineGradientColours {
	return @[
		(id)rgb(0x8C, 0xEB, 0x58).CGColor,
		(id)rgb(0x5E, 0xD3, 0x3D).CGColor,
		(id)rgb(0x36, 0xB2, 0x24).CGColor,
		(id)rgb(0x2B, 0xA0, 0x1B).CGColor
	];
}

- (NSArray *)skeuoBubbleTheirsGradientColours {
	if (self.isDarkStyle) {
		return @[
			(id)rgb(0x2C, 0x2E, 0x33).CGColor,
			(id)rgb(0x24, 0x26, 0x2A).CGColor,
			(id)rgb(0x1B, 0x1C, 0x1F).CGColor
		];
	}
	return @[
		(id)rgb(0xFF, 0xFF, 0xFF).CGColor,
		(id)rgb(0xF2, 0xF2, 0xF5).CGColor,
		(id)rgb(0xDC, 0xDC, 0xE0).CGColor,
		(id)rgb(0xD0, 0xD0, 0xD6).CGColor
	];
}

- (UIColor *)skeuoBubbleMineBorderColour {
	return rgb(0x25, 0x7B, 0x15);
}

- (UIColor *)skeuoBubbleTheirsBorderColour {
	if (self.isDarkStyle) {
		return [UIColor colorWithWhite:1.0f alpha:0.12f];
	}
	return rgb(0xB0, 0xB0, 0xB6);
}

@end
