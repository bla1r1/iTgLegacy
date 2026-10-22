//
// TGTopicsViewController - topic list controller for forum supergroups.
//
#import <UIKit/UIKit.h>

@interface TGTopicsViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;

@end
