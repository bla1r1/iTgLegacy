//
// TGTextDraw.h - drawing and measuring text without an iOS 7 floor.
//
// NSString's attribute-taking drawing and sizing arrived in iOS 7. On 6.1.6 -
// the iPod touch 4 is the device that found this - sending one of them to a
// string segfaults inside objc_msgSend rather than raising, so there is no
// exception to catch and the crash report names the call site and nothing
// else. The first one cost a crash on every audio cell with artwork.
//
// Every screen goes through these two instead of choosing for itself. They
// live apart from TGStyle because they are pure UIKit drawing: the host test
// binary compiles TGStyle.m and would need half of UIGraphics shimmed for a
// function whose only honest test is a device.
//
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Size of one line of `text` in `font`. Zero for an empty string.
CGSize TGLineTextSize(NSString *text, UIFont *font);

/// Height of `text` wrapped to `width`, rounded up. Zero for an empty string.
CGFloat TGTextHeight(NSString *text, UIFont *font, CGFloat width);

/// Draws `text` in `rect`. `colour` and `shadow` may be nil; `shadow` is an
/// NSShadow, applied through the context on the pre-7 path.
void TGDrawText(NSString *text, CGRect rect, UIFont *font, UIColor *colour,
				NSTextAlignment alignment, NSShadow *shadow);

/// Loads the message fonts off the main thread once the app is up. Call on
/// the main thread with the body size.
void TGWarmFonts(CGFloat bodySize);

#ifdef __cplusplus
}
#endif
