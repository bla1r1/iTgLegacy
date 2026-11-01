//
// TGBusinessViewController.h - the Telegram Business settings page and the
// list screen every Business sub-page inherits from.
//
#import <UIKit/UIKit.h>
#import "TGBusinessRows.h"

/// The row list, theme and switch plumbing the Business pages share. A
/// subclass fills `sections` and answers `didChooseAction:` / `toggleKey:`.
@interface TGBusinessBaseViewController : UITableViewController

@property (nonatomic, strong) NSArray *sections;

- (void)rebuild;
- (void)applyTheme;
- (void)showResult:(BOOL)ok error:(NSString *)error title:(NSString *)title;
- (void)showMessage:(NSString *)message title:(NSString *)title;
- (void)askText:(NSString *)title
		message:(NSString *)message
	placeholder:(NSString *)placeholder
		   text:(NSString *)text
		 action:(NSString *)action
	 completion:(void (^)(NSString *text))completion;

/// Overridden by subclasses; the base does nothing.
- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row;
- (void)toggleKey:(NSString *)key on:(BOOL)on sender:(UISwitch *)sender;

@end

/// Settings → Telegram Business.
@interface TGBusinessViewController : TGBusinessBaseViewController
@end

/// The business-bot connection id, shared by the connection page and the
/// message page. A user account has none; this is where a bot session's id
/// is pasted so the screens can still send the bot-only requests.
FOUNDATION_EXPORT NSString *TGBusinessStoredConnectionId(void);
FOUNDATION_EXPORT void TGBusinessStoreConnectionId(NSString *connectionId);

// vim:ft=objc
