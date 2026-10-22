//
// TGTopicsViewController - the topics of a forum supergroup.
//
// A forum holds several independent threads in one chat, so opening it should
// offer a choice of topic rather than one merged stream.
//
#import <UIKit/UIKit.h>

@interface TGTopicsViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;

@end
