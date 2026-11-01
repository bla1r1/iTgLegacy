//
// TGInstantViewController - Telegram's Instant View, drawn as the text and
// block list TDLib hands over. The full reader is a page renderer; this is
// the part that works on a phone with no browser: paragraphs, headings,
// quotes, lists, captions and dividers, in one scroll.
//
#import <UIKit/UIKit.h>

@interface TGInstantViewController : UIViewController

@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy) NSString *sourceURL;
/// PageBlock dictionaries straight from getWebPageInstantView.
@property (nonatomic, copy) NSArray *blocks;

@end
