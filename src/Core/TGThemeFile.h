//
// TGThemeFile - read a theme file made for an official Telegram client.
//
// Two formats, because both are widely shared:
//
//   .tgios-theme  JSON, the format Telegram for iOS exports. Key paths are
//                 taken from PresentationThemeCodable.swift in their repo:
//                 root.navBar.background, chatList.bg, chat.message.outgoing.
//                 bubble.withWp.bg, and so on.
//   .attheme      plain "key=value" lines, the Android format. Values are
//                 signed decimal ARGB.
//
// Both are reduced to the handful of colours this app actually paints with;
// anything else in the file is ignored rather than approximated.
//
#import <UIKit/UIKit.h>

@interface TGThemeFile : NSObject

/// Palette keyed by TGTheme's colour names ("bar", "accent", "bubbleMine"...),
/// or nil if the file is neither format. `name` gets the theme's own name.
+ (NSDictionary *)paletteFromFile:(NSString *)path name:(NSString **)name;

/// YES for a path this class can read.
+ (BOOL)handlesFile:(NSString *)path;

@end
