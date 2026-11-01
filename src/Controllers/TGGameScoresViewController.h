//
// TGGameScoresViewController.h - the score table of a game message and the
// inline game it points at.
//
#import "TGBusinessViewController.h"

@interface TGGameScoresViewController : TGBusinessBaseViewController

/// Filled when opened from a game message's More menu. 0 asks for both.
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;

@end

// vim:ft=objc
