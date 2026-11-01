//
// TGAffiliateProgramsViewController.h - the affiliate catalogue and the
// programs this account or bot has connected.
//
#import "TGBusinessViewController.h"

@interface TGAffiliateProgramsViewController : TGBusinessBaseViewController

/// "user", "bot" or "channel". A bot or channel profile opens the page with
/// its own kind already selected.
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) int64_t botUserId;
@property (nonatomic, assign) int64_t chatId;

@end

/// A channel's own program: the parameters it offers and the t.me link that
/// resolves to it.
@interface TGChannelAffiliateViewController : TGBusinessBaseViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *username;

@end

// vim:ft=objc
