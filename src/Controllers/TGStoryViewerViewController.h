//
// TGStoryViewerViewController - full-screen stories: progress bars, tap left
// and right, hold to pause, the reaction rail and the own-story menu.
//
#import <UIKit/UIKit.h>

@interface TGStoryViewerViewController : UIViewController

/// Each entry is either a flattened story dictionary or an NSNumber story id;
/// an id is fetched on the way in, which is what the chat list has.
- (instancetype)initWithChatId:(int64_t)chatId
						title:(NSString *)title
					   stories:(NSArray *)stories
					startIndex:(NSInteger)startIndex
					  canManage:(BOOL)canManage;

/// Called after the viewer changed something the list draws - a story
/// deleted, posted to the chat page or reacted to.
@property (nonatomic, copy) void (^onStoriesChanged)(void);

@end
