//
// TGTheme+Colours - flat colour roles.
//
// One getter per role the screens ask for. No texture, no depth, no motion -
// a getter here either reads an imported theme dictionary through the
// resolver or falls back to the built-in dark/light palettes defined in
// TGThemeInternal.h. Gradients live in TGTheme+Gradients.m, depth materials
// (glass, shadows, gloss) in TGTheme+Effects.m, the procedural drawing engine
// in TGTheme+Drawing.m. See docs/theme_system.md for the full map.
//
#import "TGThemeInternal.h"
#import "TGStyle.h"

#define rgb TGThemeRGB

@implementation TGTheme (Colours)

#pragma mark - bars and global accents

- (UIColor *)barColour {
	return TGRole(@"bar", TG_GRAY_DARK16, TG_BLUE_DARK4);   ///< navigation bar background
}

- (UIColor *)barTitleColour {
	return TGRole(@"barTitle", [UIColor whiteColor], [UIColor whiteColor]);
}

- (UIColor *)barSubtitleColour {
	///< subtitle in chat navigation header
	return TGRole(@"barSubtitle", TG_GRAY_DARK6,
			[UIColor colorWithWhite:1.0f alpha:0.75f]);
}

- (UIColor *)barButtonColour {
	///< buttons/items in navigation bar; the light branch is the accent
	UIColor *imported = [self importedColour:@"barButton"];
	if (imported) return imported;
	return self.isDarkStyle ? [self accentColour] : [UIColor whiteColor];
}

- (UIColor *)accentColour {
	///< buttons, links, unread badges
	return TGRole(@"accent", TG_BLUE_LIGHT4, TG_BLUE_DARK4);
}

- (UIColor *)onAccentColour {
	return [UIColor whiteColor];        ///< text/icons over accentColour
}

- (UIColor *)destructiveColour {
	return TGRole(@"destructive", rgb(0xE5, 0x39, 0x35), rgb(0xE5, 0x39, 0x35));
}

#pragma mark - floating chrome

- (UIColor *)hudBackgroundColour {
	return [UIColor colorWithWhite:0.0f alpha:0.75f];   ///< HUD/toasts backdrop
}

- (UIColor *)hudTextColour {
	return [UIColor whiteColor];                        ///< text in HUD/toasts
}

- (UIColor *)snackbarBackgroundColour {
	// The same matte slate family as the tab bar (§3.3), raised: text and
	// the Undo action stay light over it in both styles.
	if (self.isDarkStyle)
		return [UIColor colorWithRed:0.26f green:0.30f blue:0.36f alpha:0.98f];
	return [UIColor colorWithRed:0x1B / 255.0f green:0x1F / 255.0f
							blue:0x24 / 255.0f alpha:0.97f];
}

- (UIColor *)snackbarTextColour {
	return [self onAccentColour];
}

#pragma mark - the chat canvas and its bubbles

- (UIColor *)chatBackgroundColour {
	///< crisp paper grain canvas in light, flat charcoal in dark
	return TGRole(@"chatBackground", TG_GRAY_DARK14, rgb(226, 230, 236));
}

- (UIColor *)bubbleMineColour {
	return TGRole(@"bubbleMine", TG_BLUE_DARK6, TG_BLUE_BUBBLE_LIGHT);
}

- (UIColor *)bubbleTheirsColour {
	return TGRole(@"bubbleTheirs", TG_GRAY_DARK13, [UIColor whiteColor]);
}

- (UIColor *)bubbleBorderColour {
	///< clear when flat. Depth is drawn half in Effects, half right here.
	if (self.isDarkStyle)
		return [UIColor colorWithWhite:1.0f alpha:0.08f];
	return [UIColor colorWithWhite:0.0f alpha:0.12f];
}

#pragma mark - grouped lists

- (UIColor *)listBackgroundColour {
	return TGRole(@"listBackground", TG_GRAY_DARK15, [UIColor whiteColor]);
}

- (UIColor *)groupedBackgroundColour {
	///< the page behind a settings list
	UIColor *grouped = [self importedColour:@"groupedBackground"];
	if (grouped) return grouped;
	return TGRole(@"chatBackground", rgb(0x0E, 0x0E, 0x0E),
			[UIColor colorWithPatternImage:[TGTheme skeuomorphicPinstripePattern]]);
}

- (UIColor *)cardBackgroundColour {
	return TGRole(@"cardBackground", TG_GRAY_DARK15, [UIColor whiteColor]);
}

- (UIColor *)placeholderColour {
	if (self.isDark)
		return [UIColor colorWithWhite:1.0f alpha:0.40f];
	return [UIColor colorWithWhite:0.0f alpha:0.35f];
}

#pragma mark - text roles

- (UIColor *)primaryTextColour {
	return TGRole(@"primaryText", [UIColor whiteColor], TG_TEXT_PRIMARY);
}

- (UIColor *)secondaryTextColour {
	return TGRole(@"secondaryText", TG_GRAY_DARK6, TG_TEXT_SECONDARY);
}

- (UIColor *)timeColour {
	///< the stamp in the corner of a bubble
	return TGRole(@"secondaryText", TG_STEEL_DARK13, TG_TEXT_TIME);
}

- (UIColor *)timeMineColour {
	///< the same stamp in your own bubble
	UIColor *imported = [self importedColour:@"secondaryText"];
	if (imported) return imported;
	return [self timeColour];
}

- (UIColor *)listDateColour {
	return [self timeColour];           ///< the date on a chat list row
}

- (UIColor *)cellDetailColour {
	///< the value on the right of a settings row
	return TGRole(@"accent", TG_BLUE_LIGHT4, TG_BLUE_SEMI8);
}

- (UIColor *)sectionHeaderColour {
	///< the caption above a group of rows
	return TGRole(@"secondaryText", TG_GRAY_DARK6, TG_GRAY_SECTION);
}

- (UIColor *)profileHeaderColour {
	///< the block behind a profile picture
	return TGRole(@"bar", TG_GRAY_DARK16, TG_BLUE_DARK3);
}

- (UIColor *)actionTileBackgroundColour {
	///< action tiles in profile header
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
	return TGRole(@"searchBarBackground", rgb(0x2E, 0x2E, 0x2E),
			rgb(0xCD, 0xD3, 0xDC));
}

#pragma mark - media and file blocks

- (UIColor *)fileTileColour {
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_FILE_TILE;
}

- (UIColor *)mediaCircleColour {
	return TG_MEDIA_CIRCLE;             ///< the disc under a file glyph or play arrow
}

- (UIColor *)fileNameColour {
	///< the file name in a document block
	return TGRole(@"accent", TG_FILE_NAME, TG_FILE_NAME);
}

- (UIColor *)fileMetaColour {
	return self.isDarkStyle ? TG_GRAY_DARK6 : TG_STEEL_LIGHT13;
}

- (UIColor *)mediaStampColour {
	return [UIColor colorWithWhite:0.0f alpha:0.35f];   ///< plate carrying the time over a picture
}

- (UIColor *)mediaOverlayColour {
	return [UIColor colorWithWhite:0.0f alpha:0.50f];   ///< translucent badge/plate over media
}

- (UIColor *)mediaViewerBackdropColour {
	return [UIColor blackColor];
}

- (UIColor *)scrimColour {
	return [UIColor colorWithWhite:0.0f alpha:0.40f];   ///< dimming behind modal sheets and alerts
}

- (UIColor *)menuWashColour {
	return [UIColor colorWithWhite:0.0f alpha:0.12f];   ///< subtle wash behind contextual popup menu
}

#pragma mark - chat list

- (UIColor *)badgeColour {
	return TGRole(@"badge", TG_BLUE_LIGHT4, TG_BLUE_MEDIUM8);
}

- (UIColor *)badgeTextColour {
	return TGRole(@"badgeText", [UIColor whiteColor], [UIColor whiteColor]);
}

- (UIColor *)mutedBadgeColour {
	return TGRole(@"mutedBadge", rgb(0x55, 0x55, 0x55), TG_STEEL_LIGHT6);
}

- (UIColor *)typingColour {
	return TGRole(@"accent", TG_BLUE_LIGHT4, TG_BLUE_BLURPLE3);
}

- (UIColor *)onlineColour {
	return TG_GREEN_BRIGHT1;            ///< the dot on an avatar
}

- (UIColor *)ticksColour {
	return TGRole(@"ticks", rgb(0x4C, 0xB3, 0xF5), rgb(0x51, 0x7D, 0xA2));
}

- (UIColor *)separatorColour {
	///< hairlines between rows and around bars
	UIColor *imported = [self importedColour:@"separator"];
	if (imported) return imported;
	if ([self hasCustomPalette])
		return [self bubbleBorderColour];
	return self.isDarkStyle ? TG_GRAY_DARK13 : TG_STEEL_LIGHT3;
}

#pragma mark - service messages

- (UIColor *)serviceBubbleColour {
	///< the plate behind "X joined the group"; date plate wash over wallpaper
	UIColor *imported = [self importedColour:@"service"];
	if (imported) return imported;
	return self.isDarkStyle ? [UIColor colorWithWhite:1.0f alpha:0.12f]
							: [UIColor colorWithWhite:0.0f alpha:0.30f];
}

- (UIColor *)unreadSeparatorColour {
	return [[self inputBarColour] colorWithAlphaComponent:0.92f];
}

- (UIColor *)serviceTextColour {
	UIColor *imported = [self importedColour:@"serviceText"];
	if (imported) return imported;
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
	return rgb(0xA8, 0xB0, 0xBA);       ///< the grey behind Archive on a swiped row
}

- (UIColor *)muteActionColour {
	return rgb(0xFF, 0x94, 0x00);       ///< the amber behind Mute
}

- (UIColor *)recordLockColour {
	return [UIColor colorWithRed:0x1F / 255.0f green:0x24 / 255.0f
							blue:0x2E / 255.0f alpha:0.92f];
}

#pragma mark - the call screen

// The call screen is its own skin - it is not a list on a theme surface - but
// its colours belong here with the rest of them rather than inside the
// controller, where nothing else could see or override them.

- (UIColor *)callEndColour {
	return rgb(0xD3, 0x2F, 0x2F);       ///< the destructive red of §3.3
}

- (UIColor *)callAcceptColour {
	///< the success green of §3.3; also the online dot's colour
	return rgb(0x4C, 0xAF, 0x50);
}

- (UIColor *)callControlBaseColour {
	///< the opaque metal the round controls are embossed from (§2 embossed
	/// action buttons); light steel by day, charcoal in Night
	return TGRole(@"callControlBase", rgb(0x2E, 0x2E, 0x2E),
				  rgb(0xCD, 0xD3, 0xDC));
}

- (UIColor *)callControlColour {
	return [UIColor colorWithWhite:1.0f alpha:0.20f];   ///< translucent button background
}

- (UIColor *)callControlActiveColour {
	return [UIColor colorWithWhite:1.0f alpha:0.40f];
}

- (UIColor *)callSubtitleColour {
	return [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
}

#pragma mark - misc accents

- (UIColor *)giftStarColour {
	return rgb(0xFF, 0xB3, 0x00);       ///< the gold on a gift star
}

@end

// vim:ft=objc
