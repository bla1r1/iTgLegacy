//
// TGSponsoredMessagesViewController.h - the advertisements Telegram shows in
// a channel, the ones it shows in search, and the video ads under a message.
//
#import "TGBusinessViewController.h"

@interface TGSponsoredMessagesViewController : TGBusinessBaseViewController

/// The channel or bot chat the page opens on. 0 asks for one.
@property (nonatomic, assign) int64_t chatId;

/// A video message to load advertisements for, when opened from one.
@property (nonatomic, assign) int64_t messageId;

@end

// vim:ft=objc
