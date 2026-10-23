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

// Day: their iOS client from iOS 7 on. White bars, one blue for everything
// you can tap, and the pale green outgoing bubble with green ticks.
#define TG_IOS_BLUE       rgb(0x00, 0x7E, 0xE5)   // accent, badge, typing
#define TG_IOS_TEXT       rgb(0x00, 0x00, 0x00)
#define TG_IOS_GRAY       rgb(0x8E, 0x8E, 0x93)   // preview, date, values
#define TG_IOS_SECTION    rgb(0x6D, 0x6D, 0x72)
#define TG_IOS_SEPARATOR  rgb(0xC8, 0xC7, 0xCC)
#define TG_IOS_MUTED      rgb(0xB6, 0xB6, 0xBB)   // a muted chat's badge
#define TG_IOS_BUBBLE_OUT rgb(0xE1, 0xFF, 0xC7)
#define TG_IOS_CHAT_BG    rgb(0xDC, 0xE8, 0xF3)
#define TG_IOS_STAMP_IN   rgb(0xA3, 0xA3, 0xA8)
#define TG_IOS_STAMP_OUT  rgb(0x59, 0xB5, 0x4E)
#define TG_IOS_TICKS      rgb(0x19, 0xC7, 0x00)

// Night Blue: their night theme with the blue undertone. Three depths - the
// chat behind everything, bars and lists over it, fields over those - and
// separators drawn in the deepest one instead of a grey line.
#define TG_NB_CHAT        rgb(0x0E, 0x16, 0x21)
#define TG_NB_SURFACE     rgb(0x17, 0x21, 0x2B)   // bars, lists, cards
#define TG_NB_FIELD       rgb(0x24, 0x2F, 0x3D)   // search, input, tiles
#define TG_NB_BUBBLE_IN   rgb(0x18, 0x25, 0x33)
#define TG_NB_BUBBLE_OUT  rgb(0x2B, 0x52, 0x78)
#define TG_NB_ACCENT      rgb(0x6A, 0xB2, 0xF2)
#define TG_NB_BADGE       rgb(0x40, 0x82, 0xBC)
#define TG_NB_MUTED       rgb(0x3E, 0x54, 0x6A)
#define TG_NB_TEXT        rgb(0xF5, 0xF5, 0xF5)
#define TG_NB_SECONDARY   rgb(0x7F, 0x91, 0xA4)
#define TG_NB_STAMP_IN    rgb(0x6D, 0x7F, 0x8F)
#define TG_NB_STAMP_OUT   rgb(0x7D, 0xA8, 0xD3)
#define TG_NB_TICKS       rgb(0x7D, 0xC2, 0xF5)
#define TG_NB_ONLINE      rgb(0x4F, 0xAE, 0x4E)

/// The built-in Night Blue, as opposed to the plain dark style it shares
/// -isDarkStyle with.
static BOOL TGIsNightBlue(TGTheme *theme) {
	return theme.isDarkStyle && theme.style == TGThemeStyleNightBlue;
}

/// The built-in Day style; imported themes are flat too but bring their own.
static BOOL TGIsDay(TGTheme *theme) {
	return theme.style == TGThemeStyleFlat && theme.importedName == nil;
}

@implementation TGTheme (Palette)

- (UIColor *)barColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_SURFACE;
	if (self.isDarkStyle) return TG_GRAY_DARK16;
	return self.isFlat ? TG_GRAY_LIGHT3 : TG_BLUE_DARK4;
}

- (UIColor *)barTitleColour {
	UIColor *imported = [self importedColour:@"barTitle"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_TEXT;
	if (self.isDarkStyle) return [UIColor whiteColor];
	if (TGIsDay(self)) return TG_IOS_TEXT;
	return self.isFlat ? TG_TEXT_PRIMARY : [UIColor whiteColor];
}

- (UIColor *)barSubtitleColour {
	UIColor *imported = [self importedColour:@"barSubtitle"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_SECONDARY;
	if (self.isDarkStyle) return TG_GRAY_DARK6;
	if (TGIsDay(self)) return TG_IOS_GRAY;
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
	if (TGIsNightBlue(self)) return TG_NB_ACCENT;
	if (self.isDarkStyle) return TG_BLUE_LIGHT4;
	if (TGIsDay(self)) return TG_IOS_BLUE;
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
	if (TGIsNightBlue(self)) return TG_NB_CHAT;
	if (self.isDarkStyle) return TG_GRAY_DARK14;
	if (TGIsDay(self)) return TG_IOS_CHAT_BG;
	return self.isFlat ? TG_STEEL_LIGHT1 : rgb(217, 222, 212);
}

- (UIColor *)bubbleMineColour {
	UIColor *imported = [self importedColour:@"bubbleMine"];
	if (imported) return imported;
	// Their pale green would glow on a dark surface; blue_dark6 is the darkest
	// blue they draw, and it is what the outgoing bubble becomes.
	if (TGIsNightBlue(self)) return TG_NB_BUBBLE_OUT;
	if (self.isDarkStyle) return TG_BLUE_DARK6;
	if (TGIsDay(self)) return TG_IOS_BUBBLE_OUT;
	return TG_GREEN_LIGHT1;
}

- (UIColor *)bubbleTheirsColour {
	UIColor *imported = [self importedColour:@"bubbleTheirs"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_BUBBLE_IN;
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
	if (TGIsNightBlue(self)) return TG_NB_SURFACE;
	if (self.isDarkStyle) return TG_GRAY_DARK15;
	return [UIColor whiteColor];
}

- (UIColor *)groupedBackgroundColour {
	UIColor *imported = [self importedColour:@"chatBackground"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_CHAT;
	if (self.isDarkStyle) return rgb(0x0E, 0x0E, 0x0E);
	// Their settings page is the grey iOS has used behind grouped lists since
	// iOS 7, and the cards on it are white.
	return rgb(0xEF, 0xEF, 0xF4);
}

- (UIColor *)cardBackgroundColour {
	UIColor *imported = [self importedColour:@"cardBackground"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_SURFACE;
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
	if (TGIsNightBlue(self)) return TG_NB_TEXT;
	if (self.isDarkStyle) return [UIColor whiteColor];
	if (TGIsDay(self)) return TG_IOS_TEXT;
	return TG_TEXT_PRIMARY;
}

- (UIColor *)secondaryTextColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_SECONDARY;
	if (self.isDarkStyle) return TG_GRAY_DARK6;
	if (TGIsDay(self)) return TG_IOS_GRAY;
	return TG_TEXT_SECONDARY;
}

// Time text color
- (UIColor *)timeColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_STAMP_IN;
	if (TGIsDay(self)) return TG_IOS_STAMP_IN;
	return self.isDarkStyle ? TG_STEEL_DARK13 : TG_TEXT_TIME;
}

- (UIColor *)timeMineColour {
	// The stamp in your own bubble takes the bubble's hue, the way the ticks
	// beside it do; grey on pale green is what made it look pasted on.
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_STAMP_OUT;
	if (TGIsDay(self)) return TG_IOS_STAMP_OUT;
	return [self timeColour];
}

- (UIColor *)listDateColour {
	// The date in a chat row is the list's grey, not a bubble stamp's.
	if (TGIsNightBlue(self)) return TG_NB_STAMP_IN;
	if (TGIsDay(self)) return TG_IOS_GRAY;
	return [self timeColour];
}

- (UIColor *)cellDetailColour {
	// Telegram puts the value of a setting in blue rather than grey, which is
	// the one thing that makes their settings read as theirs.
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_ACCENT;
	// Their iOS client puts the value in grey beside the disclosure arrow.
	if (TGIsDay(self)) return TG_IOS_GRAY;
	return TG_BLUE_SEMI8;
}

- (UIColor *)sectionHeaderColour {
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_SECONDARY;
	if (TGIsDay(self)) return TG_IOS_SECTION;
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_GRAY_SECTION;
}

- (UIColor *)profileHeaderColour {
	UIColor *imported = [self importedColour:@"bar"];
	if (imported) return imported;
	return TGIsNightBlue(self) ? TG_NB_FIELD : TG_BLUE_DARK3;
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
	if (TGIsNightBlue(self)) return TG_NB_SURFACE;
	return self.isDarkStyle ? TG_GRAY_DARK16 : TG_GRAY_LIGHT3;
}

- (UIColor *)searchBarBackgroundColour {
	UIColor *imported = [self importedColour:@"searchBarBackground"];
	if (imported) return imported;
	switch (self.style) {
		case TGThemeStyleSkeuomorphic:
			return rgb(0xCD, 0xD3, 0xDC);
		case TGThemeStyleFlat:
			return rgb(0xE9, 0xE9, 0xEB);
		case TGThemeStyleDark:
			return rgb(0x2E, 0x2E, 0x2E);
		case TGThemeStyleNightBlue:
			return TG_NB_FIELD;
	}
	return rgb(0xE9, 0xE9, 0xEB);
}

#pragma mark - media and file blocks

// File tile background color
- (UIColor *)fileTileColour {
	if (TGIsNightBlue(self)) return TG_NB_FIELD;
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
	if (TGIsNightBlue(self)) return TG_NB_SECONDARY;
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_STEEL_LIGHT13;
}

// Timestamp badge plate over media
- (UIColor *)mediaStampColour {
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

#pragma mark - chat list

- (UIColor *)badgeColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_BADGE;
	if (TGIsDay(self)) return TG_IOS_BLUE;
	return TG_BLUE_MEDIUM8;
}

- (UIColor *)mutedBadgeColour {
	if (TGIsNightBlue(self)) return TG_NB_MUTED;
	if (TGIsDay(self)) return TG_IOS_MUTED;
	return self.isDarkStyle ? rgb(0x55, 0x55, 0x55) : TG_STEEL_LIGHT6;
}

- (UIColor *)typingColour {
	UIColor *imported = [self importedColour:@"accent"];
	if (imported) return imported;
	if (TGIsNightBlue(self)) return TG_NB_ACCENT;
	if (TGIsDay(self)) return TG_IOS_BLUE;
	return TG_BLUE_BLURPLE3;
}

- (UIColor *)onlineColour {
	if (TGIsNightBlue(self)) return TG_NB_ONLINE;
	return TG_GREEN_BRIGHT1;
}

- (UIColor *)ticksColour {
	UIColor *imported = [self importedColour:@"ticks"];
	if (imported) return imported;
	switch (self.style) {
		case TGThemeStyleSkeuomorphic:
			return rgb(0x51, 0x7D, 0xA2);
		case TGThemeStyleFlat:
			return TG_IOS_TICKS;
		case TGThemeStyleDark:
			return rgb(0x4C, 0xB3, 0xF5);
		case TGThemeStyleNightBlue:
			return TG_NB_TICKS;
	}
	return rgb(0x4C, 0xB3, 0xF5);
}

- (UIColor *)separatorColour {
	if ([self hasCustomPalette])
		return [self bubbleBorderColour];
	if (TGIsNightBlue(self)) return TG_NB_CHAT;
	if (TGIsDay(self)) return TG_IOS_SEPARATOR;
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_STEEL_LIGHT3;
}

#pragma mark - service messages

// Date plate wash over wallpaper
- (UIColor *)serviceBubbleColour {
	if (TGIsNightBlue(self))
		return [UIColor colorWithRed:0x1E / 255.0f green:0x2C / 255.0f blue:0x3A / 255.0f alpha:0.90f];
	if (TGIsDay(self))
		return [UIColor colorWithRed:0x50 / 255.0f green:0x6E / 255.0f blue:0x8C / 255.0f alpha:0.38f];
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.12f]
							: [UIColor colorWithWhite:0.0f alpha:0.30f];
}

- (UIColor *)serviceTextColour {
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.85f]
							: [UIColor whiteColor];
}

- (CGFloat)bubbleCornerRadius {
	// Their bubble is a tail on a softly rounded box, not a capsule.
	return self.isFlat ? 16.0f : 10.0f;
}

- (CGFloat)bubbleJoinedCornerRadius {
	// Where two bubbles of one run meet, the corners nearly square off so the
	// run reads as one block.
	return 5.0f;
}

- (CGFloat)bubbleBorderWidth {
	// A drawn edge is what makes a skeuomorphic bubble sit on the surface. A
	// flat one is the shape and nothing else, which is what the header has
	// always said this returns.
	return self.isFlat ? 0.0f : 1.0f;
}

@end
