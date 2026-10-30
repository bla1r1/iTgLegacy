//
// TGThemeInternal - shared plumbing for the theme files.
//
// Only theme implementation files (TGTheme.m, TGTheme+Colours.m,
// TGTheme+Gradients.m, TGTheme+Effects.m, TGTheme+Drawing.m) import this.
// Feature code talks to TGTheme.h and never sees anything from here.
//
#import "TGTheme.h"

/// Shorthand for the full-thousand hex literals the palettes are written in.
static inline UIColor *TGThemeRGB(int r, int g, int b) {
	return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

#pragma mark - the definition list (every raw hex lives here and only here)

// Each value is written once and spelled by role-ish naming; the semantic
// getters in TGTheme+Colours.m decide what it means. See DESIGN_SPEC.md
// section 3.3 for the rendered palette. Keep the comments honest, they are
// the only documentation most values have.

// Light Skeuomorphic Palette (Classic iOS 6)
#define TG_BLUE_DARK4     TGThemeRGB(0x51, 0x7D, 0xA2)   // classic header blue
#define TG_BLUE_LIGHT4    TGThemeRGB(0x4C, 0xB3, 0xF5)   // links, dark accent
#define TG_BLUE_MEDIUM8   TGThemeRGB(0x3D, 0x95, 0xD4)   // unread badge
#define TG_BLUE_BUBBLE_LIGHT TGThemeRGB(0xDF, 0xEE, 0xFA)   // outgoing bubble (Telegram celestial blue)
#define TG_GREEN_BRIGHT1  TGThemeRGB(0x5A, 0xCD, 0x30)   // online dot
#define TG_GRAY_LIGHT3    TGThemeRGB(0xF7, 0xF7, 0xF7)   // input strip
#define TG_STEEL_LIGHT1   TGThemeRGB(0xED, 0xEE, 0xF0)   // light gray surface
#define TG_STEEL_LIGHT3   TGThemeRGB(0xE1, 0xE4, 0xE9)   // separators
#define TG_TEXT_PRIMARY   TGThemeRGB(0x22, 0x22, 0x22)   // primary text
#define TG_TEXT_SECONDARY TGThemeRGB(0x8D, 0x8E, 0x90)   // secondary text
#define TG_TEXT_TIME      TGThemeRGB(0x95, 0x99, 0x9A)   // timestamp
#define TG_BLUE_SEMI8     TGThemeRGB(0x51, 0xAE, 0xE7)   // settings value
#define TG_GRAY_SECTION   TGThemeRGB(0x69, 0x6A, 0x6F)   // section caption
#define TG_BLUE_DARK3     TGThemeRGB(0x5A, 0x8E, 0xBD)   // profile picture header
#define TG_BLUE_BLURPLE3  TGThemeRGB(0x70, 0xAA, 0xEA)   // typing indicator
#define TG_STEEL_LIGHT6   TGThemeRGB(0xC5, 0xC9, 0xCC)   // muted badge
#define TG_STEEL_LIGHT13  TGThemeRGB(0xA1, 0xAA, 0xB3)   // file size
#define TG_FILE_TILE      TGThemeRGB(0xEB, 0xF0, 0xF4)   // file glyph background
#define TG_MEDIA_CIRCLE   TGThemeRGB(0x72, 0xB5, 0xE9)   // media circle
#define TG_FILE_NAME      TGThemeRGB(0x4E, 0x9A, 0xD4)

// Dark Skeuomorphic Palette (Night iOS 6)
#define TG_GRAY_DARK16    TGThemeRGB(0x20, 0x20, 0x20)   // bars
#define TG_GRAY_DARK15    TGThemeRGB(0x21, 0x21, 0x21)   // lists, cards
#define TG_GRAY_DARK14    TGThemeRGB(0x23, 0x23, 0x23)   // chat background
#define TG_GRAY_DARK13    TGThemeRGB(0x33, 0x33, 0x33)   // incoming bubble, separators
#define TG_GRAY_DARK6     TGThemeRGB(0x99, 0x99, 0x99)   // secondary text
#define TG_STEEL_DARK13   TGThemeRGB(0x7D, 0x84, 0x8A)   // timestamp
#define TG_BLUE_DARK6     TGThemeRGB(0x1B, 0x5A, 0x7D)   // outgoing bubble

#pragma mark - the role resolver

/// The standard shape of a colour getter: an imported theme wins outright,
/// otherwise the built-in value depends on the built-in dark style. Used as
///
///     - (UIColor *)barColour {
///         return TGRole(@"bar", TG_GRAY_DARK16, TG_BLUE_DARK4);
///     }
///
/// Getters whose light branch is dynamic (pattern colours, derived tints) or
/// whose imported key does not divide into a clean pair fall back to writing
/// the three lines out; both shapes must stay interchangeable.
#define TGRole(key, dark, light) \
	([self importedColour:key] ?: (self.isDarkStyle ? (dark) : (light)))

#pragma mark - the imported role registry

// Importable roles and what they cover (one name in the dictionaries every
// theme file parser produces - TGThemeFile.m; anything a parser leaves out
// simply falls through to the built-in palettes above):
//
//   bar               navigation bar, tab bar, profile header backdrop
//   barTitle          navigation bar title
//   barSubtitle       secondary line in a navigation header
//   barButton         navigation bar buttons and icons
//   accent            links, unread badges, settings values, typing colour
//   destructive       delete actions, red alerts
//   chatBackground    chat canvas and grouped page backdrop
//   bubbleMine        outgoing bubble
//   bubbleTheirs      incoming bubble
//   listBackground    plain list background
//   cardBackground    grouped card surface
//   primaryText       main text
//   secondaryText     secondary text, timestamps, section captions
//   searchBarBackground   the recessed search well
//   actionTile        translucent tiles in the profile header
//   ticks             delivery checkmarks
//   badge             unread badge plate
//   badgeText          text inside the unread badge
//   mutedBadge         the same badge when the chat is muted
//   service            service message plate ("X joined the group")
//   serviceText        text on that plate
//   groupedBackground  the page behind a grouped settings list
//   separator          hairlines between rows
//   calloutGlossTop   gloss card top reflection
//   calloutGlossBottom    gloss card bottom reflection
//
//
// Adding a new external theme format starts here and in TGThemeFile.m:
// write a parser that emits a dictionary keyed by these names (see
// docs/theme_system.md).

@interface TGTheme ()
- (UIColor *)importedColour:(NSString *)key;
- (BOOL)hasCustomPalette;
@end
