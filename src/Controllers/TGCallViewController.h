//
// TGCallViewController - the screen for one call.
//
#import <UIKit/UIKit.h>

@interface TGCallViewController : UIViewController

/// For an outgoing call; place it as the screen appears.
- (instancetype)initWithUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing;

/// Present over whatever is on screen, which is what a call does.
+ (void)presentForUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing;

/// The minimised bar with no call behind it, for checking its look from
/// itglegacy://callbar. Nil takes it away.
+ (void)previewMiniBarNamed:(NSString *)name;

@end
