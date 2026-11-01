//
// TGAiComposeViewController.h - the AI and rich-message composer. Every
// button sends the real request; a refusal is shown as Telegram worded it.
//
#import "TGTier2ListViewController.h"

@interface TGAiComposeViewController : TGTier2ListViewController

/// Where Send puts the result. Zero means no chat is chosen yet and the
/// screen asks for one first.
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;

@end
