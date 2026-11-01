//
// TGDMTopicsViewController - the topic list of a channel direct messages
// chat, opened from the channel profile.
//
#import <UIKit/UIKit.h>

@interface TGDMTopicsViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;

@end
