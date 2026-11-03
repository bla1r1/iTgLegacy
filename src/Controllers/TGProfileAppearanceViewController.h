//
// TGProfileAppearanceViewController - name colour and profile colour, as the
// official "Your Color" screen shows them: two tabs over a grid of real
// swatches, a live preview of your own name and avatar, and a reset.
//
#import <UIKit/UIKit.h>

@interface TGProfileAppearanceViewController : UITableViewController

/// NO opens on the name colour, YES on the profile colour.
- (instancetype)initWithProfileTab:(BOOL)profileTab;

@end
