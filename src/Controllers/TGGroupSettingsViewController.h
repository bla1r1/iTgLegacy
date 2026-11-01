//
// TGGroupSettingsViewController.h - the group profile's own settings: its
// username, forum mode, join requests, hidden members, translation, the
// channel's main tab and the irreversible broadcast conversion.
//
#import <UIKit/UIKit.h>

@interface TGGroupSettingsViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;

@end
