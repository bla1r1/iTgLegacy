//
// TGPopupMenu - contextual popup menu anchored to touch point.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGPopupMenu : UIView

/// Primary API: displays popup menu with integrated emoji reactions bar,
/// callout arrow pointing to anchor point, and tactile action items.
+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
        reactions:(nullable NSArray<NSString *> *)reactions
   selectedReaction:(nullable NSString *)selectedReaction
       onReaction:(nullable void (^)(NSString *emoji))reactionChoice
         onChoice:(void (^)(NSInteger index, NSString *title))choice;

/// Convenience API: displays popup menu without reactions bar.
+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
         onChoice:(void (^)(NSInteger index, NSString *title))choice;

/// Convenience API: displays popup menu with custom header view.
+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
       headerView:(nullable UIView *)headerView
         onChoice:(void (^)(NSInteger index, NSString *title))choice;

/// Close whatever menu is open, if any. Called when a screen goes away.
+ (void)dismiss;

@end

NS_ASSUME_NONNULL_END
