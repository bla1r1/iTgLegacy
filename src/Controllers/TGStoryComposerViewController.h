//
// TGStoryComposerViewController - picks a photo or video, captions it, sets
// the privacy and the active period, and posts it.
//
#import <UIKit/UIKit.h>

@interface TGStoryComposerViewController : UITableViewController

- (instancetype)initWithChatId:(int64_t)chatId title:(NSString *)title;

/// Called after Telegram accepted a story, so the strip can re-read.
@property (nonatomic, copy) void (^onPosted)(void);

@end
