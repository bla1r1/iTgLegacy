//
// TGAntiSpamViewController.h - deleted messages an administrator may report
// as aggressive anti-spam false positives.
//
#import "TGBusinessViewController.h"

@interface TGAntiSpamViewController : TGBusinessBaseViewController

@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;

@end

// vim:ft=objc
