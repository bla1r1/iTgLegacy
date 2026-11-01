//
// TGEphemeralViewController - the ephemeral message composer and viewer.
//
// sendEphemeralMessage is a bot-side call: a user account gets Telegram's
// refusal, which this screen prints instead of hiding. The composer, the
// receiver, the reply id and the five follow-up calls are all real requests.
//
#import <UIKit/UIKit.h>

@interface TGEphemeralViewController : UITableViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy)   NSString *chatTitle;

@end
