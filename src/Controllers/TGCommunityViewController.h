//
// TGCommunityViewController.h - one community: its full record, its chats and
// the four writes Telegram allows the owner.
//
#import "TGTier2ListViewController.h"

@interface TGCommunityViewController : TGTier2ListViewController

/// `community` is the updateCommunity row the list tapped, or a row built
/// from the create answer. The id is what every request uses.
- (instancetype)initWithCommunity:(NSDictionary *)community;

@end
