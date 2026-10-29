//
// TGTheme - app appearance theme manager (Skeuomorphic, Flat, Dark, Night Blue).
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGThemeStyle) {
    TGThemeStyleSkeuomorphic = 0,   ///< "Classic"
    TGThemeStyleFlat         = 1,   ///< "Day"
    TGThemeStyleDark         = 2,   ///< "Night"
    TGThemeStyleNightBlue    = 3    ///< "Night Blue"
};

/// Auto-Night, as their Appearance page offers it. There is no system dark
/// mode to follow on this OS, so scheduled is the only automatic there is.
typedef NS_ENUM(NSInteger, TGAutoNightMode) {
    TGAutoNightOff = 0,
    TGAutoNightScheduled
};

@interface TGTheme : NSObject

+ (instancetype)shared;

/// Persisted; defaults to skeuomorphic below iOS 7 and flat from iOS 7 on.
@property (nonatomic, assign) TGThemeStyle style;
/// YES for the flat style and for dark, which is flat drawn on dark surfaces.
@property (nonatomic, readonly) BOOL isFlat;

/// Posted when the style changes so open screens can restyle themselves.
extern NSString *const TGThemeChangedNotification;

#pragma mark - imported themes

/// Name of the imported theme in use, or nil for the built-in styles.
@property (nonatomic, readonly) NSString *importedName;
/// YES for the built-in dark style, and when an imported theme calls itself dark.
@property (nonatomic, readonly) BOOL isDark;
/// YES only for the built-in dark style: an imported theme brings its own
/// colours and must not be second-guessed by the dark defaults.
@property (nonatomic, readonly) BOOL isDarkStyle;

/// Adopt a theme file made for an official client (.tgios-theme, .attheme).
/// Returns NO if the file cannot be read. Persists across launches.
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

#pragma mark - auto-night

/// Off unless the user asked for it. When scheduled, the theme becomes Night
/// between -autoNightFromHour and -autoNightToHour and goes back after.
@property (nonatomic, assign) TGAutoNightMode autoNight;
@property (nonatomic, assign) NSInteger autoNightFromHour;   ///< default 22
@property (nonatomic, assign) NSInteger autoNightToHour;     ///< default 7

/// Switch to or away from Night if the schedule says so. Cheap and idempotent;
/// called when the app comes forward and once an hour while it is open.
- (void)applyAutoNightIfDue;

/// Message text size in points. Persisted; 15 is the default.
@property (nonatomic, assign) CGFloat messageFontSize;

#pragma mark - wallpaper

/// The chat wallpaper, or nil for a plain background. Either a picture the
/// user chose or one carried by an imported theme.
- (UIImage *)wallpaper;

/// Adopt a picture as the wallpaper; nil clears it. Persisted.
- (void)setWallpaperImage:(UIImage *)image;

/// Style a table cell so an imported theme reaches the settings screens too;
/// grouped tables draw white cells otherwise.
- (void)styleCell:(UITableViewCell *)cell;

/// A table's section caption. Seven screens did this by hand and five left
/// the system's, which on a dark theme is grey on grey - so the same caption
/// was two colours depending on which list it was over.
- (void)styleSectionHeader:(UIView *)headerView;

/// Apply the bar styling to a navigation bar.
- (void)styleNavigationBar:(UINavigationBar *)bar;
/// Same for the tab bar, which an imported theme should not leave behind.
- (void)styleTabBar:(UITabBar *)bar;

@end

typedef NS_ENUM(NSInteger, TGButtonStyle) {
    TGButtonStyleAction = 0,    ///< Glossy blue action button
    TGButtonStyleSilver,        ///< Classic metallic silver button
    TGButtonStyleDestructive,   ///< Glossy crimson destructive button
    TGButtonStyleSuccess,       ///< Glossy green accept/call button
    TGButtonStyleGhost          ///< Subtle translucent / etched ghost button
};

@interface TGTheme (Skeuomorphism)

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

/// Recessed well image for search fields and input bars.
+ (UIImage *)skeuomorphicWellImageWithHeight:(CGFloat)height cornerRadius:(CGFloat)radius;

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

@end

@interface TGTheme (Palette)

#pragma mark - palette

- (UIColor *)barColour;             ///< navigation bar background
- (UIColor *)barTitleColour;
- (UIColor *)barSubtitleColour;     ///< subtitle in chat navigation header
- (UIColor *)barButtonColour;       ///< buttons/items in navigation bar
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

/// Two colours, top to bottom, behind a call in each of its three moods.
- (NSArray *)callGradientColours;
- (NSArray *)callGradientColoursConnected;
- (NSArray *)callGradientColoursFailed;
- (UIColor *)callEndColour;
- (UIColor *)callAcceptColour;
- (UIColor *)callControlColour;     ///< translucent button background on call screen
- (UIColor *)callControlActiveColour;

#pragma mark - charts

/// Six colours for the storage ring, in the order its slices are drawn.
- (NSArray *)chartPalette;
/// The gold on a gift's star.
- (UIColor *)giftStarColour;

#pragma mark - skeuomorphic and depth effects

/// Top glossy highlight shine on iOS 6 buttons.
- (UIColor *)skeuoShineColour;
/// Etched light drop shadow under text in iOS 6 style.
- (UIColor *)etchedTextShadowColour;
/// Dark text shadow under embossed navigation titles.
- (UIColor *)navBarTextShadowColour;
/// Highlighted tint for action buttons.
- (UIColor *)buttonHighlightColour;
/// Subtitle text colour on call screen.
- (UIColor *)callSubtitleColour;

- (CGFloat)bubbleCornerRadius;
- (CGFloat)bubbleJoinedCornerRadius; ///< corners where bubbles of one run meet
- (CGFloat)bubbleBorderWidth;       ///< 0 when flat

@end
