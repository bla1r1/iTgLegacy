//
// TGThemeFile - parser for Telegram theme files (.tgios-theme JSON, .attheme ARGB).
//
#import <UIKit/UIKit.h>

@interface TGThemeFile : NSObject

/// Palette keyed by TGTheme's colour names ("bar", "accent", "bubbleMine"...),
/// or nil if the file is neither format. `name` gets the theme's own name.
+ (NSDictionary *)paletteFromFile:(NSString *)path name:(NSString **)name;

/// The part of a theme the app applies: the chat roles only, since bars
/// and lists stay the system's. nil for a dark theme - iOS 6-12 had none.
+ (NSDictionary *)chatPaletteFromFile:(NSString *)path name:(NSString **)name;

/// YES for a path this class can read.
+ (BOOL)handlesFile:(NSString *)path;

@end
