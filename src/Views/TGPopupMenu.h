//
// TGPopupMenu - contextual popup menu anchored to touch point.
//
#import <UIKit/UIKit.h>

@interface TGPopupMenu : UIView

/// `items` are dictionaries: "title" (NSString), "icon" (NSString, a name
/// TGIcons answers to, or absent for no glyph) and optionally "destructive"
/// (NSNumber BOOL) to draw the row in red.
///
/// The card is placed beside `point`, in `host`'s coordinates, and nudged back
/// on screen if it would hang off an edge. Tapping outside dismisses it and
/// `choice` is not called.
+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
         onChoice:(void (^)(NSInteger index, NSString *title))choice;

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
       headerView:(UIView *)headerView
         onChoice:(void (^)(NSInteger index, NSString *title))choice;

/// Close whatever menu is open, if any. Called when a screen goes away.
+ (void)dismiss;

@end
