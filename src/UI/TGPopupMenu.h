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

/// The same bar with a second verb: holding a reaction asks for it to lead
/// the bar from now on. The picker promotes it in place, so the menu the
/// finger is still on already shows the new order.
+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
        reactions:(nullable NSArray<NSString *> *)reactions
   selectedReaction:(nullable NSString *)selectedReaction
       onReaction:(nullable void (^)(NSString *emoji))reactionChoice
onDefaultReaction:(nullable void (^)(NSString *emoji))defaultChoice
         onChoice:(void (^)(NSInteger index, NSString *title))choice;

/// The hold presentation: `anchor` is the lifted bubble in host coordinates.
/// The reaction bar floats above its top edge and the action card hangs from
/// its bottom edge, so the menu reads as belonging to the picture rather than
/// to the finger that opened it. A card too tall for the room underneath is
/// scrolled inside its own frame instead of running off the screen.
///
/// `onDismiss` runs exactly once when the menu goes away - a row, a reaction,
/// a tap outside, or the screen closing - which is where the caller puts the
/// message back into the list.
+ (void)showItems:(NSArray *)items
       anchoredAt:(CGRect)anchor
           inView:(UIView *)host
        reactions:(nullable NSArray<NSString *> *)reactions
   selectedReaction:(nullable NSString *)selectedReaction
       onReaction:(nullable void (^)(NSString *emoji))reactionChoice
onDefaultReaction:(nullable void (^)(NSString *emoji))defaultChoice
         onChoice:(void (^)(NSInteger index, NSString *title))choice
       onDismiss:(nullable void (^)(void))dismissal;

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
