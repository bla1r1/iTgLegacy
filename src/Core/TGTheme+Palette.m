#import "TGThemeInternal.h"

#define rgb TGThemeRGB

// Telegram's own palette, read out of their design system file. The names are
// theirs. The file is drawn for Android at 360dp; the colours carry over
// unchanged, the metrics are scaled to a 320pt screen where they appear.
#define TG_BLUE_DARK4     rgb(0x51, 0x7D, 0xA2)   // the classic header blue
#define TG_BLUE_LIGHT4    rgb(0x4C, 0xB3, 0xF5)   // send button, links
#define TG_BLUE_MEDIUM8   rgb(0x3D, 0x95, 0xD4)   // unread badge
#define TG_GREEN_LIGHT1   rgb(0xEF, 0xFE, 0xDD)   // outgoing bubble
#define TG_GREEN_BRIGHT1  rgb(0x5A, 0xCD, 0x30)   // online dot, ticks
#define TG_GRAY_LIGHT3    rgb(0xF7, 0xF7, 0xF7)   // bars, input strip
#define TG_STEEL_LIGHT1   rgb(0xED, 0xEE, 0xF0)   // chat background
#define TG_STEEL_LIGHT3   rgb(0xE1, 0xE4, 0xE9)   // separators
#define TG_TEXT_PRIMARY   rgb(0x22, 0x22, 0x22)
#define TG_TEXT_SECONDARY rgb(0x8D, 0x8E, 0x90)
#define TG_TEXT_TIME      rgb(0x95, 0x99, 0x9A)
#define TG_BLUE_SEMI8     rgb(0x51, 0xAE, 0xE7)   // the value on a settings row
#define TG_GRAY_SECTION   rgb(0x69, 0x6A, 0x6F)   // a section caption
#define TG_BLUE_DARK3     rgb(0x5A, 0x8E, 0xBD)   // behind a profile picture
#define TG_BLUE_MEDIUM2   rgb(0x5E, 0xA7, 0xDE)   // the record button
#define TG_BLUE_BLURPLE3  rgb(0x70, 0xAA, 0xEA)   // "typing..." in the chat list
#define TG_STEEL_LIGHT6   rgb(0xC5, 0xC9, 0xCC)   // a muted chat's badge
#define TG_STEEL_LIGHT13  rgb(0xA1, 0xAA, 0xB3)   // size and type under a file
#define TG_FILE_TILE      rgb(0xEB, 0xF0, 0xF4)   // the square behind a file glyph
#define TG_MEDIA_CIRCLE   rgb(0x72, 0xB5, 0xE9)   // the disc inside it
#define TG_FILE_NAME      rgb(0x4E, 0x9A, 0xD4)

// The dark half of their palette, read from the same file. Their greys are
// numbered from light to dark, so the surfaces a dark theme needs are the tail
// of gray_dark and the middle of steel-gray.
#define TG_GRAY_DARK16    rgb(0x20, 0x20, 0x20)   // bars
#define TG_GRAY_DARK15    rgb(0x21, 0x21, 0x21)   // lists
#define TG_GRAY_DARK14    rgb(0x23, 0x23, 0x23)   // chat background
#define TG_GRAY_DARK13    rgb(0x33, 0x33, 0x33)   // incoming bubble, separators
#define TG_GRAY_DARK6     rgb(0x99, 0x99, 0x99)   // secondary text
#define TG_STEEL_DARK13   rgb(0x7D, 0x84, 0x8A)   // the stamp in a dark bubble
#define TG_BLUE_DARK6     rgb(0x1B, 0x5A, 0x7D)   // outgoing bubble when dark

@implementation TGTheme (Palette)

- (UIColor *)barColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK16;
	return self.isFlat ? TG_GRAY_LIGHT3 : TG_BLUE_DARK4;
}

- (UIColor *)barTitleColour {
	UIColor *imported = [self importedColour:@"barTitle"];
	if (imported) return imported;
	if (self.isDarkStyle) return [UIColor whiteColor];
	return self.isFlat ? TG_TEXT_PRIMARY : [UIColor whiteColor];
}

- (UIColor *)barSubtitleColour {
	UIColor *imported = [self importedColour:@"barSubtitle"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK6;
	return self.isFlat ? TG_TEXT_SECONDARY : [UIColor colorWithWhite:1.0f alpha:0.75f];
}

- (UIColor *)barButtonColour {
	UIColor *imported = [self importedColour:@"barButton"];
	if (imported) return imported;
	if (self.isDarkStyle) return [self accentColour];
	return self.isFlat ? [self accentColour] : [UIColor whiteColor];
}

- (UIColor *)accentColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_BLUE_LIGHT4;
	return self.isFlat ? TG_BLUE_LIGHT4 : TG_BLUE_DARK4;
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
	if (self.isDarkStyle) return TG_GRAY_DARK14;
	return self.isFlat ? TG_STEEL_LIGHT1 : rgb(217, 222, 212);
}

- (UIColor *)bubbleMineColour {
	UIColor *imported = [self importedColour:@"bubbleMine"];
	if (imported) return imported;
	// Their pale green would glow on a dark surface; blue_dark6 is the darkest
	// blue they draw, and it is what the outgoing bubble becomes.
	if (self.isDarkStyle) return TG_BLUE_DARK6;
	return TG_GREEN_LIGHT1;
}

- (UIColor *)bubbleTheirsColour {
	UIColor *imported = [self importedColour:@"bubbleTheirs"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK13;
	return [UIColor whiteColor];
}

- (UIColor *)bubbleBorderColour {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface;
	// flat bubbles have none at all.
	// black_alpha12 in their palette, and it applies to both styles: their
	// bubbles carry a hairline whatever the era. On a dark surface a black
	// hairline is invisible, so it turns into a faint white one.
	if (self.isDarkStyle)
		return [UIColor colorWithWhite:1.0f alpha:0.08f];
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

- (UIColor *)listBackgroundColour {
	UIColor *imported = [self importedColour:@"listBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK15;
	return [UIColor whiteColor];
}

- (UIColor *)groupedBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return rgb(0x0E, 0x0E, 0x0E);
	// Their settings page is the grey iOS has used behind grouped lists since
	// iOS 7, and the cards on it are white.
	return rgb(0xEF, 0xEF, 0xF4);
}

- (UIColor *)cardBackgroundColour {
	UIColor *imported = [self importedColour:@"cardBackground"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK15;
	if (self.isDark) return [self listBackgroundColour];
	return [UIColor whiteColor];
}

- (UIColor *)placeholderColour {
	if (self.isDark)
		return [UIColor colorWithWhite:1.0f alpha:0.40f];
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

- (UIColor *)primaryTextColour {
	UIColor *imported = [self importedColour:@"primaryText"];
	if (imported) return imported;
	if (self.isDarkStyle) return [UIColor whiteColor];
	return TG_TEXT_PRIMARY;
}

- (UIColor *)secondaryTextColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (self.isDarkStyle) return TG_GRAY_DARK6;
	return TG_TEXT_SECONDARY;
}

// Time text color
- (UIColor *)timeColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_STEEL_DARK13 : TG_TEXT_TIME;
}

- (UIColor *)cellDetailColour {
	// Telegram puts the value of a setting in blue rather than grey, which is
	// the one thing that makes their settings read as theirs.
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BLUE_SEMI8;
}

- (UIColor *)sectionHeaderColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_GRAY_SECTION;
}

- (UIColor *)profileHeaderColour {
	UIColor *imported = [self importedColour:@"bar"];
	return imported ?: TG_BLUE_DARK3;
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

#pragma mark - chat list

- (UIColor *)badgeColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BLUE_MEDIUM8;
}

- (UIColor *)mutedBadgeColour {
	return self.isDarkStyle ? rgb(0x55, 0x55, 0x55) : TG_STEEL_LIGHT6;
}

- (UIColor *)typingColour {
	UIColor *imported = [self importedColour:@"accent"];
	return imported ?: TG_BLUE_BLURPLE3;
}

- (UIColor *)onlineColour {
	return TG_GREEN_BRIGHT1;
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

- (UIColor *)serviceTextColour {
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.85f]
							: [UIColor whiteColor];
}

- (CGFloat)bubbleCornerRadius {
	// Their bubble is a 6pt tail on a softly rounded box, not a capsule.
	return self.isFlat ? 12.0f : 10.0f;
}

- (CGFloat)bubbleBorderWidth {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface. A
	// flat one is the shape and nothing else, which is what the header has
	// always said this returns.
	return self.isFlat ? 0.0f : 1.0f;
}

@end
