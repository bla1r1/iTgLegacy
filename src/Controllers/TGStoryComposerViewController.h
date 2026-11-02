//
// TGStoryComposerViewController - the last step of posting a story: privacy,
// the active period, who posts, and the button. The picture comes from the
// camera and editor steps in TGStoryCameraViewController.
//
#import <UIKit/UIKit.h>

@interface TGStoryComposerViewController : UITableViewController

- (instancetype)initWithChatId:(int64_t)chatId title:(NSString *)title;

/// Asks Telegram whether this account may post at all, and only then puts the
/// camera on screen over `controller`. A refusal (no Premium, a limit reached)
/// is said up front in a sheet and nothing opens, so nobody takes a picture
/// for a story that cannot be sent. `onPosted` runs after Telegram accepted it.
+ (void)openFromController:(UIViewController *)controller
					chatId:(int64_t)chatId
					 title:(NSString *)title
				  onPosted:(void (^)(void))onPosted;

/// Called after Telegram accepted a story, so the strip can re-read.
@property (nonatomic, copy) void (^onPosted)(void);

/// What the editor step hands over. A photo has already been through
/// `writeStoryPhoto:`; a video is sent as it was picked.
- (void)useMediaAtPath:(NSString *)path
			   isVideo:(BOOL)isVideo
			  duration:(double)duration
			   caption:(NSString *)caption;

/// Scales a photo to Telegram's 1080x1920 and writes it as a JPEG. Safe off
/// the main thread: it touches nothing of the controller's state.
- (NSString *)writeStoryPhoto:(UIImage *)image;

@end
