//
// TGSimilarChannelsViewController.h - List of recommended similar channels.
//
#import <UIKit/UIKit.h>

@interface TGSimilarChannelsViewController : UITableViewController

@property (nonatomic, assign) int64_t originalChatId;
@property (nonatomic, strong) NSArray *channelChatIds;

@end
