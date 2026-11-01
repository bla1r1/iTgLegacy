//
// TGCallMessagesViewController - the message bar inside a group call.
//
// Telegram lets participants send short messages into a call when the call
// allows them. The rows here are the messages TDLib delivered, oldest first;
// sending and deleting go back through the same record, so a refusal from
// the server is what the screen shows.
//
#import <UIKit/UIKit.h>
#import "TGListViewController.h"

@interface TGCallMessagesViewController : TGListViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t groupCallId;

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId;

@end

// vim:ft=objc
