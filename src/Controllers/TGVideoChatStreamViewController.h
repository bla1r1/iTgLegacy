//
// TGVideoChatStreamViewController - the streams and data channel of a call.
//
// Telegram exposes a group call two ways besides the audio engine: the list
// of stream channels with a timestamp, and the data channel TDLib encrypts
// and decrypts between participants. Both are real requests here. A segment
// is written to disk as the file Telegram generated; this client has no
// group-call media engine, so it reports the bytes instead of pretending to
// play them.
//
#import <UIKit/UIKit.h>
#import "TGListViewController.h"

@interface TGVideoChatStreamViewController : TGListViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t groupCallId;

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId;

@end

// vim:ft=objc
