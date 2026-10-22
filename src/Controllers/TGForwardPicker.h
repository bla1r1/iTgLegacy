//
// TGForwardPicker - choose a chat to forward into.
//
#import <UIKit/UIKit.h>

@interface TGForwardPicker : UITableViewController
@property (nonatomic, copy) void (^onPicked)(int64_t chatId);
@end
