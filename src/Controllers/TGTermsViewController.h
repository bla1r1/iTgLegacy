//
// TGTermsViewController.h - the terms Telegram sends after sign-in.
//
// The update names an id that has to be accepted before the account goes on;
// this is the screen that shows the text and sends it back.
//
#import <UIKit/UIKit.h>

@interface TGTermsViewController : UIViewController

@property (nonatomic, copy) NSString *termsText;
/// Runs once, when Accept is tapped, before the screen goes away.
@property (nonatomic, copy) void (^onAccept)(void);

@end
