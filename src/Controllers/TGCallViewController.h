//
// TGCallViewController - the screen for one call.
//
#import <UIKit/UIKit.h>

@interface TGCallViewController : UIViewController

/// For an outgoing call; place it as the screen appears.
- (instancetype)initWithUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing;

/// Present over whatever is on screen, which is what a call does.
+ (void)presentForUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing;

@end
