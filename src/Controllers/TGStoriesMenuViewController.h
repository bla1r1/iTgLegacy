//
// TGStoriesMenuViewController - the actions behind the stories strip's More
// bubble: add, albums, archive, notifications, discovery, stealth and live.
//
#import <UIKit/UIKit.h>
#import "TGListViewController.h"

@interface TGStoriesMenuViewController : TGListViewController

- (instancetype)initWithChatId:(int64_t)chatId title:(NSString *)title;

@property (nonatomic, copy) void (^onStoriesChanged)(void);

@end
