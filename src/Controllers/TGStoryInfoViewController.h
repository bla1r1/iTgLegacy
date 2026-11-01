//
// TGStoryInfoViewController - who saw, reacted to or forwarded a story, its
// statistics, and the two-step report flow.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGStoryInfoMode) {
	TGStoryInfoModeInfo = 0,
	TGStoryInfoModeReport
};

@interface TGStoryInfoViewController : UITableViewController

- (instancetype)initWithChatId:(int64_t)chatId
					   storyId:(int32_t)storyId
						 story:(NSDictionary *)story
						  mode:(TGStoryInfoMode)mode;

@end
