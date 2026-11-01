//
// TGBotConsoleViewController.h - the bot records a user account owns, and the
// inline and OAuth calls that belong to the user side of a bot.
//
#import "TGBusinessViewController.h"

@interface TGBotConsoleViewController : TGBusinessBaseViewController

/// A bot opened from its profile. 0 asks for one.
@property (nonatomic, assign) int64_t botUserId;

@end

// vim:ft=objc
