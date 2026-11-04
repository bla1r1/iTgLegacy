//
// TGProfileViewController - user/chat profile, media overview, and actions.
//
#import <UIKit/UIKit.h>

@interface TGProfileViewController : UITableViewController

/// Search lives here rather than in the navigation bar, where the avatar is -
/// the same place Telegram keeps it.
@property (nonatomic, copy) void (^onSearchTapped)(void);
/// The tab to open on, or nil for the first one.
@property (nonatomic, copy) NSString *storedMediaKind;
/// "Jump to Date" in the More menu; the chat behind opens its date picker.
@property (nonatomic, copy) void (^onJumpToDateTapped)(void);

- (instancetype)initWithChatId:(int64_t)chatId
                      userId:(int64_t)userId
                       title:(NSString *)title;

@end
