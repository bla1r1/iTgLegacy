//
// TGPlayerView.h - iOS 6 Reimagined Player System
// Persistent Docked Mini-Player and Fullscreen iPod/Music Deck Modal.
//
#import <UIKit/UIKit.h>

@interface TGPlayerMiniBar : UIView

@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onDismiss)(void);

+ (instancetype)miniBarWithFrame:(CGRect)frame;
- (void)updateState;

@end

@interface TGPlayerModalViewController : UIViewController

+ (void)presentFromViewController:(UIViewController *)parent animated:(BOOL)animated;

@end
