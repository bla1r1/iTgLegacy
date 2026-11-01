//
// TGSuggestedPostViewController.h - one suggested post: its price and date,
// and the two answers Telegram accepts.
//
#import "TGTier2ListViewController.h"

@interface TGSuggestedPostViewController : TGTier2ListViewController

- (instancetype)initWithChatId:(int64_t)chatId messageId:(int64_t)messageId;

@end
