//
// TGStoryArchiveViewController - every story a chat has ever posted.
//
#import <UIKit/UIKit.h>

@interface TGStoryArchiveViewController : UITableViewController

- (instancetype)initWithChatId:(int64_t)chatId title:(NSString *)title;

@end
