//
// TGContactsViewController - contacts list controller backed by TDLib.
//
#import <UIKit/UIKit.h>

@interface TGContactsViewController : UITableViewController

/// Picking people for a new group instead of opening a chat: a tap ticks a
/// row, and Create in the navigation bar asks for the group's name. Set
/// before the view loads.
@property (nonatomic, assign) BOOL picksGroupMembers;

/// Picking people to add to a chat that already exists. Same ticking, but
/// Add puts them straight into `addingToChatId`.
@property (nonatomic, assign) int64_t addingToChatId;

@end
