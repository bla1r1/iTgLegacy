//
// TGGroupCallParticipantsViewController - everybody in a call.
//
// The call screen shows the first few people; this is the list that answers
// "who is here" and carries the per-person actions: mute for everyone or for
// this device, volume, a raised hand, and a ban when the call is the
// account's own. Rows come from TDLib updates, not from a request per row.
//
#import <UIKit/UIKit.h>

@interface TGGroupCallParticipantsViewController : UITableViewController

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId;

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t groupCallId;

@end

// vim:ft=objc
