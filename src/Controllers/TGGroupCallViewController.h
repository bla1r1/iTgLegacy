//
// TGGroupCallViewController - one group call or video chat.
//
// The screen shows Telegram's real record: title, participant count, who is
// speaking, whether this account is joined, the recording state and the
// duration of the session. Every control sends the matching group-call
// request and redraws from the answer or from updateGroupCall.
//
// There is no group-call media engine in this client. Joining returns the
// tgcalls payload and the screen says so; it does not pretend to carry audio
// or video. Participants, messages, stream metadata and the data channel are
// still real, because those are server-side.
//
#import <UIKit/UIKit.h>

@interface TGGroupCallViewController : UIViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t groupCallId;

/// A zero id asks the chat record for its video chat. A chat with none gets
/// the setup screen instead of an invented call.
- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId;

@end

// vim:ft=objc
