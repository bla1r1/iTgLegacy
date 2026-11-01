//
// TGCloseFriendsViewController - the contacts Telegram will accept as close
// friends, with a check beside the ones already in the list.
//
#import <UIKit/UIKit.h>

@interface TGCloseFriendsViewController : UITableViewController

/// How many ids the server holds after a successful write; the privacy row
/// behind this screen shows the same number.
@property (nonatomic, copy) void (^onCountChanged)(NSInteger count);

@end
