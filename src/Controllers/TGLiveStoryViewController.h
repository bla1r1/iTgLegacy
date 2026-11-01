//
// TGLiveStoryViewController - starts or joins a live story and shows the
// server's side of it: the streamer, the RTMP address, message senders, top
// donors and the pending paid reactions.
//
#import <UIKit/UIKit.h>
#import "TGListViewController.h"

@interface TGLiveStoryViewController : TGListViewController

/// `groupCallId` 0 means this screen starts a new live story; a nonzero id
/// means it was opened from an existing live story.
- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId;

@end
