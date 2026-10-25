//
// TGSheet - the container every bottom sheet in the app rises from: one
// dimmed backdrop, cards stacked on the bottom edge, one slide. Subclass it
// and fill the cards; the backdrop, the corners and the animation come with
// it, so two sheets cannot drift apart again.
//
#import <UIKit/UIKit.h>

@interface TGSheet : UIView

/// Close whatever sheet is open, at once and without animation. One sheet at
/// a time: presenting another closes the one before it.
+ (void)dismissOpen;

/// A sheet the size of `host` with its backdrop in place, nothing shown yet.
/// Called on the subclass, which then adds its cards. `host` is remembered
/// for -present.
+ (instancetype)sheetForView:(UIView *)host;

/// A card to fill. Cards are laid out in the order added, top to bottom,
/// the last one against the bottom edge. `edgeToEdge` pins a card to the
/// screen's sides and rounds only its top corners, the way a modal sheet
/// rises; otherwise it floats with a side margin and rounds all four, the
/// way an action sheet sits.
- (UIView *)addCardOfHeight:(CGFloat)height edgeToEdge:(BOOL)edgeToEdge;

/// Adds the sheet to the view it was made for and slides the cards up.
- (void)present;

/// Slides them back down and removes the sheet. A tap on the backdrop does
/// the same, so a subclass only calls this for its own close button.
- (void)dismiss;

@end
