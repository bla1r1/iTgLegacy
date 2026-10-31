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

#pragma mark - the role resolver

/// The standard shape of a colour getter: an imported theme wins for the
/// chat roles it may set (see -importedColour:), the built-in value otherwise.
#define TGRole(key, light) ([self importedColour:key] ?: (light))

#pragma mark - the imported role registry

// Theme file parsers (TGThemeFile.m) emit a dictionary keyed by role name.
// The app reads only the chat roles from it - the system draws everything
// else on iOS 6-12, which never had dark or tinted chrome:
//
//   chatBackground    chat canvas
//   bubbleMine        outgoing bubble
//   bubbleTheirs      incoming bubble
//   service           service message plate ("X joined the group")
//   serviceText       text on that plate
//   ticks             delivery checkmarks
//
// Adding a new external theme format starts here and in TGThemeFile.m:
// write a parser that emits a dictionary keyed by these names (see
// docs/theme_system.md).

@interface TGTheme ()
- (UIColor *)importedColour:(NSString *)key;
@end
