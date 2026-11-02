//
// TGVideoNoteViewController - the full-screen round-video recorder.
//
// The chat stays visible behind a dimmed snapshot; the camera preview is the
// circle Telegram draws, and the controls are the timer/cancel/send bar plus
// the one-time switch. The recorder itself is already running when this
// screen is presented.
//
#import <UIKit/UIKit.h>

@interface TGVideoNoteViewController : UIViewController

- (instancetype)initWithChatId:(int64_t)chatId
					  threadId:(int64_t)threadId
				 background:(UIImage *)background;

/// Where the screen will sit, known before it builds itself: the circle and the
/// cover over it are drawn once, for this size.
@property (nonatomic, assign) CGRect overlayFrame;
@property (nonatomic, copy) void (^onDismiss)(void);

@end
