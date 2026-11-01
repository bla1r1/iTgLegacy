//
// TGListViewController.h - a grouped list built from data, not from a screen.
//
// Tier 2's answer surfaces - an event log, statistics, similar chats, folder
// links, members of a link, message positions - are all the same table: a
// title, an optional second line, and sometimes a tap. One controller keeps
// them from growing seven copies of the same data-source boilerplate.
//
#import <UIKit/UIKit.h>

@interface TGListViewController : UITableViewController

/// Shown in the navigation bar.
@property (nonatomic, copy) NSString *listTitle;

/// Entries are dictionaries: "title" (required), "detail", "destructive"
/// (NSNumber BOOL) and "tap" (a void block). Set before or after push; the
/// table reloads itself.
@property (nonatomic, strong) NSArray *rows;

/// A sentence under the list when there are no rows.
@property (nonatomic, copy) NSString *emptyText;

/// A sentence above the list, always shown when set.
@property (nonatomic, copy) NSString *listFooter;

/// A right bar button that copies the whole list as text, for a log or a
/// statistics page that is easier to keep than to retype.
@property (nonatomic, assign) BOOL offersCopy;

@end
