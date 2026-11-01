//
// TGVideoChatSetupViewController - creating and managing a video chat.
//
// Telegram splits a video chat across two things: the chat (where the
// invite link and RTMP address hang) and the group call (title, recording,
// switches, who joins as whom). This screen is the one place both halves are
// reachable, and every row reports the answer it got instead of assuming one.
//
#import <UIKit/UIKit.h>
#import "TGListViewController.h"

@interface TGVideoChatSetupViewController : TGListViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t groupCallId;

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId;

@end

// vim:ft=objc
