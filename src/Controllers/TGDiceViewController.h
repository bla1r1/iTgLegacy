//
// TGDiceViewController - the stake dice panel for a channel direct messages
// chat: the state Telegram hands out and the prize table that goes with it.
//
#import <UIKit/UIKit.h>

@interface TGDiceViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;

@end
