//
// TGTheme - colours and textures for what the app draws itself. Bars,
// lists and alerts are the system's; a theme file only recolours the chat.
//
#import <UIKit/UIKit.h>

@interface TGTheme : NSObject

+ (instancetype)shared;

/// Posted when the style changes so open screens can restyle themselves.
extern NSString *const TGThemeChangedNotification;

#pragma mark - imported themes

/// Name of the imported theme in use, or nil for the built-in styles.
@property (nonatomic, readonly) NSString *importedName;
/// Adopt a theme file made for an official client (.tgios-theme, .attheme).
/// Returns NO if the file cannot be read or is dark. Persists across launches.
- (BOOL)importThemeAtPath:(NSString *)path;

/// Drop the imported theme and go back to the built-in style.
- (void)clearImportedTheme;

/// Theme files the app can see: everything in Documents, plus anything
/// received in a chat and saved there. Paths.
+ (NSArray *)availableThemeFiles;

#pragma mark - one list of themes

/// All available themes (built-in styles and imported files).
/// Entries contain: "id", "name", "dark" (BOOL), and optional "path".
+ (NSArray *)availableThemes;

/// The id of the theme in use.
- (NSString *)currentThemeId;

/// Adopt one by id. NO when a theme file cannot be read; the previous theme
/// stays in that case. Posts TGThemeChangedNotification once.
- (BOOL)selectThemeId:(NSString *)themeId;

/// Message text size in points. Persisted; 15 is the default.
@property (nonatomic, assign) CGFloat messageFontSize;

#pragma mark - wallpaper

typedef NS_ENUM(NSInteger, TGWallpaperType) {
	TGWallpaperTypeNone = 0,
	TGWallpaperTypePaperGrain = 1,
	TGWallpaperTypePinstripes = 2,
	TGWallpaperTypeLinen = 3,
	TGWallpaperTypeParchment = 4,
	TGWallpaperTypeFelt = 5,
	TGWallpaperTypeCustom = 6
};

/// The chat wallpaper, or nil for a plain background. Either a picture the
/// user chose, a physical texture preset, or one carried by an imported theme.
- (UIImage *)wallpaper;

/// Current wallpaper type (preset physical texture, custom photo, or none). Persisted.
- (TGWallpaperType)wallpaperType;
- (void)setWallpaperType:(TGWallpaperType)type;
- (NSString *)wallpaperTitleForType:(TGWallpaperType)type;

/// Adopt a picture as the wallpaper; nil clears it. Persisted.
- (void)setWallpaperImage:(UIImage *)image;

/// A cell with the system's fonts and colours.
- (void)styleCell:(UITableViewCell *)cell;

/// iOS 6's own navigation-bar blue.
- (UIColor *)systemBarBlueColour;
/// A search bar the way the running OS draws one.
- (void)styleSearchBar:(UISearchBar *)bar;
/// A stock cell of this style, for reading the system's fonts and colours.
+ (UITableViewCell *)systemCellOfStyle:(UITableViewCellStyle)style;
/// A grouped table the way the running OS draws one.
- (void)styleGroupedTable:(UITableView *)table;

/// Apply the bar styling to a navigation bar.
- (void)styleNavigationBar:(UINavigationBar *)bar;
/// Same for the tab bar, which an imported theme should not leave behind.
- (void)styleTabBar:(UITabBar *)bar;

@end

typedef NS_ENUM(NSInteger, TGButtonStyle) {
    TGButtonStyleAction = 0,    ///< Glossy blue action button
    TGButtonStyleSilver,        ///< Classic metallic silver button
    TGButtonStyleSecondary = TGButtonStyleSilver, ///< Alias for secondary button
    TGButtonStyleDestructive,   ///< Glossy crimson destructive button
    TGButtonStyleSuccess,       ///< Glossy green accept/call button
    TGButtonStyleGhost          ///< Subtle translucent / etched ghost button
};

@interface TGTheme (Skeuomorphism)

/// The procedural engine lives in TGTheme+Drawing.m: it turns the tokens
/// (Colours, Gradients, Effects) into cached raster images.

/// Procedural skeuomorphic background image for navigation bars.
+ (UIImage *)skeuomorphicBarImageWithColor:(UIColor *)tint height:(CGFloat)height;

/// Procedural tactile button background image with specular gloss, bevel and drop shadow.
+ (UIImage *)skeuomorphicButtonImageWithColor:(UIColor *)tint
                                       height:(CGFloat)height
                                  highlighted:(BOOL)highlighted
                                 cornerRadius:(CGFloat)radius;

/// Returns standard stretchable button image for given button style and state.
+ (UIImage *)buttonImageForStyle:(TGButtonStyle)style
                     highlighted:(BOOL)highlighted
                          height:(CGFloat)height;

/// Subtle procedural vertical pinstripe / linen pattern for grouped backgrounds.
+ (UIImage *)skeuomorphicPinstripePattern;

/// Tactile Apple physical canvas patterns.
+ (UIImage *)skeuomorphicLinenPattern;
+ (UIImage *)skeuomorphicParchmentPattern;
+ (UIImage *)skeuomorphicFeltPattern;
+ (UIImage *)skeuomorphicPaperGrainPattern;

/// Recessed well image for search fields and input bars.
+ (UIImage *)skeuomorphicWellImageWithHeight:(CGFloat)height cornerRadius:(CGFloat)radius;

/// Wallpaper texture for a preset, keyed by TGWallpaperType.
+ (UIImage *)textureImageForType:(TGWallpaperType)type;

/// Metallic circular thumb for scrubbers and volume sliders.
+ (UIImage *)skeuomorphicSliderThumbWithRadius:(CGFloat)radius;

/// Recessed track image for skeuomorphic slider (6pt height).
+ (UIImage *)skeuomorphicSliderTrackImageFilled:(BOOL)filled;

/// Track background image for iOS 6 skeuomorphic switch (51x31 pt).
+ (UIImage *)skeuomorphicSwitchTrackImageOn:(BOOL)isOn;

/// Tactile metallic knob for iOS 6 skeuomorphic switch (27x27 pt).
+ (UIImage *)skeuomorphicSwitchThumbImage;

/// Applies tactile skeuomorphic styling to a generic button.
+ (void)applySkeuomorphicStyleToButton:(UIButton *)button style:(TGButtonStyle)style;

/// Applies classic recessed well styling to a text field.
+ (void)applySkeuomorphicInputStyle:(UITextField *)field;

/// Brushed aluminum satin metal image for chat composer bar.
+ (UIImage *)skeuomorphicInputBarImageWithHeight:(CGFloat)height;



- (void)styleGroupedCell:(UITableViewCell *)cell forRow:(NSInteger)row totalRows:(NSInteger)total;

@end

// The visual language is spread across five homes, one concern per category:
//
//   TGTheme (Colours)       flat colour roles - the answer to "what colour"
//   TGTheme (Gradients)     multi-stop colour sets - "which colours, order"
//   TGTheme (Effects)       depth: frosted glass (the no-blur substitute),
//                           shadows, gloss, bevels - "which material"
//   TGTheme (Skeuomorphism) the procedural drawing engine: turns tokens in
//                           raster images (TGTheme+Drawing.m)
//
// Profile/metrics live in TGStyle.h. Token map: docs/theme_system.md.
//
// Nothing in feature code may invent a colour or a font; scripts/lint_tokens.sh
// enforces it.

@interface TGTheme (Colours)

- (UIColor *)barColour;             ///< navigation bar background
- (UIColor *)barTitleColour;
- (UIColor *)barSubtitleColour;     ///< subtitle in chat navigation header
- (UIColor *)barButtonColour;       ///< buttons/items in navigation bar
- (UIColor *)barControlFillColour;  ///< translucent fill for nav-bar controls
- (UIColor *)accentColour;          ///< buttons, links, unread badges
- (UIColor *)onAccentColour;        ///< text and icons rendered over accentColour / badges
- (UIColor *)destructiveColour;     ///< delete actions, red alerts
- (UIColor *)hudBackgroundColour;   ///< background for HUD/toasts
- (UIColor *)hudTextColour;         ///< text inside HUD/toasts
- (UIColor *)snackbarBackgroundColour;
- (UIColor *)snackbarTextColour;
- (UIColor *)chatBackgroundColour;
- (UIColor *)bubbleMineColour;
- (UIColor *)bubbleTheirsColour;
- (UIColor *)bubbleBorderColour;    ///< clear when flat
/// A reaction pill under a bubble. The chosen one takes the accent border,
/// which is how Telegram marks a reaction you put there yourself.
- (UIColor *)reactionChipColour;
- (UIColor *)reactionChipMineColour;
- (UIColor *)reactionChipBorderColour;
- (UIColor *)reactionChipMineBorderColour;
- (UIColor *)listBackgroundColour;
/// The page behind a settings list. Their sections are rounded cards floating
/// on it, so it has to differ from the card - a grouped table on this OS draws
/// both the same and the cards disappear.
- (UIColor *)groupedBackgroundColour;
- (UIColor *)cardBackgroundColour;
- (UIColor *)placeholderColour;
- (UIColor *)primaryTextColour;
- (UIColor *)secondaryTextColour;
- (UIColor *)inputBarColour;
- (UIColor *)searchBarBackgroundColour;
- (UIColor *)timeColour;            ///< the stamp in the corner of a bubble
- (UIColor *)timeMineColour;        ///< the same stamp in your own bubble
- (UIColor *)listDateColour;        ///< the date on a chat list row
- (UIColor *)cellDetailColour;      ///< the value on the right of a settings row
- (UIColor *)sectionHeaderColour;   ///< the caption above a group of rows
- (UIColor *)profileHeaderColour;   ///< the block behind a profile picture
- (UIColor *)actionTileBackgroundColour; ///< action tiles in profile header

#pragma mark - media and file blocks

- (UIColor *)fileTileColour;        ///< the square behind a file glyph
- (UIColor *)mediaCircleColour;     ///< the disc under a file glyph or play arrow
- (UIColor *)fileNameColour;        ///< the file name in a document block
- (UIColor *)fileMetaColour;        ///< "6.5 KB PNG" under it
- (UIColor *)mediaStampColour;      ///< the plate carrying the time over a picture
- (UIColor *)mediaOverlayColour;    ///< translucent badge/plate over media
- (UIColor *)mediaViewerBackdropColour; ///< full-screen media viewer black background
- (UIColor *)scrimColour;           ///< backdrop dimming behind modal sheets and alerts
- (UIColor *)menuWashColour;        ///< subtle wash behind contextual popup menu
/// The dim over the chat while a message is held and lifted out of the list.
/// Darker than the sheet scrim: the lifted bubble has to read as the only
/// thing in focus, and on iOS 6 there is no live blur to do that job alone.
- (UIColor *)holdDimColour;

#pragma mark - chat list

- (UIColor *)badgeColour;           ///< unread count
- (UIColor *)badgeTextColour;       ///< text inside unread badge
- (UIColor *)mutedBadgeColour;      ///< the same count in a muted chat
- (UIColor *)typingColour;          ///< "typing..." in place of the preview
- (UIColor *)onlineColour;          ///< the dot on an avatar
- (UIColor *)ticksColour;           ///< delivery checkmarks in outgoing bubble
- (UIColor *)separatorColour;       ///< hairlines between rows and around bars

#pragma mark - service messages

- (UIColor *)serviceBubbleColour;   ///< the plate behind "X joined the group"
- (UIColor *)unreadSeparatorColour; ///< unread messages banner plate
- (UIColor *)serviceTextColour;

#pragma mark - map preview

- (UIColor *)mapPaperColour;
- (UIColor *)mapRoadColour;
- (UIColor *)mapGreeneryColour;
- (UIColor *)mapPinColour;
- (UIColor *)mapPinShadowColour;

#pragma mark - swipe actions

- (UIColor *)archiveActionColour;   ///< the grey behind Archive on a swiped row
- (UIColor *)muteActionColour;      ///< the amber behind Mute
- (UIColor *)recordLockColour;      ///< the dark pill holding the record lock

#pragma mark - the call screen

- (UIColor *)callEndColour;
- (UIColor *)callAcceptColour;
- (UIColor *)callControlBaseColour; ///< opaque metal plate the embossed controls are carved from
- (UIColor *)callControlColour;     ///< translucent button background on call screen
- (UIColor *)callControlActiveColour;
- (UIColor *)callSubtitleColour;    ///< subtitle text colour on call screen

- (UIColor *)giftStarColour;        ///< the gold on a gift's star

- (UIColor *)iconCatalogGlyphColour; ///< the dark glyph stamped on a light icon-catalogue tile

@end

@interface TGTheme (Gradients)

/// Two colours, top to bottom, behind a call in each of its three moods.
- (NSArray *)callGradientColours;
- (NSArray *)callGradientColoursConnected;
- (NSArray *)callGradientColoursFailed;

/// Vertical greens for your own skeuomorphic bubble.
- (NSArray *)skeuoBubbleMineGradientColours;
/// Vertical whites in light, vertical charcoals in dark.
- (NSArray *)skeuoBubbleTheirsGradientColours;

/// Top glossy highlight on iOS 6 buttons.
- (NSArray *)skeuoShineGradientColours;

/// Six colours for the storage ring, in the order its slices are drawn.
- (NSArray *)chartPalette;

@end

@interface TGTheme (Effects)

#pragma mark - frosted glass (the "blur" substitute: there is no GPU blur)

- (UIColor *)calloutBackgroundColour; ///< dark satin glass for iOS 6 callout popup menu
- (UIColor *)calloutTrayColour;       ///< recessed dark well for reactions
- (UIColor *)calloutBorderColour;     ///< hairline border for callout
- (UIColor *)calloutDividerDarkColour; ///< etched dark groove
- (UIColor *)calloutDividerLightColour; ///< etched specular highlight
- (UIColor *)calloutGlossTopColour;   ///< specular top reflection for callout popup menu
- (UIColor *)calloutGlossBottomColour;///< specular fade reflection for callout popup menu

#pragma mark - shadows, gloss and bevels

/// Top glossy highlight shine on iOS 6 buttons.
- (UIColor *)skeuoShineColour;
/// Etched light drop shadow under text in iOS 6 style.
- (UIColor *)etchedTextShadowColour;
/// Dark text shadow under embossed navigation titles.
- (UIColor *)navBarTextShadowColour;
/// Highlighted tint for action buttons.
- (UIColor *)buttonHighlightColour;

/// Soft green stroke on your own skeuomorphic bubble.
- (UIColor *)skeuoBubbleMineBorderColour;
/// Tactile outer border on theirs.
- (UIColor *)skeuoBubbleTheirsBorderColour;

- (CGFloat)bubbleCornerRadius;
- (CGFloat)bubbleJoinedCornerRadius; ///< corners where bubbles of one run meet
- (CGFloat)bubbleBorderWidth;       ///< 0 when flat

@end
