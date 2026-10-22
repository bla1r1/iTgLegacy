//
// TGProfileViewController - user/chat profile, media overview, and actions.
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
