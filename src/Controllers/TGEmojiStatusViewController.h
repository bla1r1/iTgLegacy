//
// TGEmojiStatusViewController - Telegram's emoji status grid.
//
// The same picker serves three targets: the signed-in account, another user
// (a bot-side call this app still offers and lets Telegram refuse), and a
// chat. The chat lists are narrower, so the screen asks for the chat ones
// when a chat is the target.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGEmojiStatusTarget) {
	TGEmojiStatusTargetSelf = 0,
	TGEmojiStatusTargetUser,
	TGEmojiStatusTargetChat,
};

@interface TGEmojiStatusViewController : UITableViewController

@property (nonatomic, assign) TGEmojiStatusTarget target;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *subjectTitle;

@end
