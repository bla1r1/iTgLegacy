//
// TGProfileViewController - who you are talking to, and what has been shared.
//
// Reached by tapping the chat header. For a private chat it shows the user's
// photo, name, username and phone; for any chat it lists the shared photos and
// files, which TDLib can answer with a filtered searchChatMessages.
//
#import <UIKit/UIKit.h>

@interface TGProfileViewController : UITableViewController

/// Search lives here rather than in the navigation bar, where the avatar is -
/// the same place Telegram keeps it.
@property (nonatomic, copy) void (^onSearchTapped)(void);

- (instancetype)initWithChatId:(int64_t)chatId
                      userId:(int64_t)userId
                       title:(NSString *)title;

@end
