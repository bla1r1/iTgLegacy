// tests/shim/UIKit/UIKit.h — macOS test shim.
//
// The host test suite compiles real src code. Some src files import
// <UIKit/UIKit.h> even though what the tests exercise from them is pure
// text/geometry logic: font/colour bookkeeping, measure and wrap. On macOS
// those UIKit names map onto their AppKit counterparts, and the handful of
// view classes the tests actually touch get tiny stand-ins here.
//
// Must stay first on the include path (-I$(TESTS)/shim) so this header
// resolves instead of to the iOS SDK, which does not exist on the host.
//
// It is deliberately narrow: only what the suites under it need. Grow it
// only when a new suite can compile real src without faking behaviour.
#pragma once

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

// ─── fonts and colours ───────────────────────────────────────────────────────
// AppKit's NSFont/NSColor carry the same surface the tested code uses
// (fontWithName:size:, systemFontOfSize:, boldSystemFontOfSize:,
// pointSize, fontName; blackColor, colorWithRed:green:blue:alpha:).
typedef NSFont UIFont;
typedef NSColor UIColor;
typedef NSImage UIImage;

// Host gaps AppKit does not cover. NSFont lacks the italic convenience and
// the geometry NSValue accessors only exist on iOS in this spelling.
@interface NSFont (UIKitHostShim)
+ (UIFont *)italicSystemFontOfSize:(CGFloat)size;
@end

@interface NSValue (UIKitHostShim)
+ (NSValue *)valueWithCGSize:(CGSize)size;
- (CGSize)CGSizeValue;
@end

// ─── UIDevice ────────────────────────────────────────────────────────────────
// TGClient +Account streams device_model/system_version into setTdlibParameters.
@interface UIDevice : NSObject
+ (UIDevice *)currentDevice;
@property (nonatomic, readonly) NSString *model;
@property (nonatomic, readonly) NSString *systemVersion;
@end

// ─── UILabel ─────────────────────────────────────────────────────────────────
// A data-holding stand-in: TGSetBodyText only ever reads and writes these.
@interface UILabel : NSObject
@property (nonatomic, copy)   NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) NSAttributedString *attributedText;
@end

// ─── NSString UIKit additions ────────────────────────────────────────────────
@interface NSString (UIKitHostShim)
- (CGSize)sizeWithFont:(UIFont *)font;
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size
        lineBreakMode:(NSInteger)lineBreakMode;
@end

// ─── NSAttributedString UIKit additions ──────────────────────────────────────
// None needed: AppKit's NSStringDrawing.h provides the full
// boundingRectWithSize:options:context: surface the src code calls, and a
// shimmed duplicate of a selector AppKit owns would recurse through itself.
