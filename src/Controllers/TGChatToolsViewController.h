//
// TGChatToolsViewController.h - the per-chat half of Tier 2.
//
// Reached from a profile's More menu. Everything here changes the chat itself
// or reads what Telegram keeps about it: the event log, statistics, similar
// chats, slow mode, reactions, protected content, themes, the discussion
// group, the location, the local note, member positions and the photo tools.
//
#import <UIKit/UIKit.h>

@interface TGChatToolsViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;
/// Whether the chat is a group or channel; a private chat has no event log
/// or statistics, and the rows say so rather than failing later.
@property (nonatomic, assign) BOOL isGroup;

@end
