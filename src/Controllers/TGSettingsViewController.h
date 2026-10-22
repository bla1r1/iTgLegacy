//
// TGSettingsViewController - account and maintenance, on TDLib only.
//
// Replaces ConfigViewController, whose entries called into libtg's database
// helpers directly.
//
// One flat table held everything, which is not how Telegram arranges it: the
// root is a short list of doors, and the settings themselves live behind them.
// The same class draws each page, because they differ only in their rows.
//
// A page is now a list of sections and a section a list of rows, each row
// carrying what it says and what it does. Every page used to be spelled out
// again in six switch statements keyed on section and row number, which is
// where each new setting had to be threaded through by hand.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGSettingsPage) {
	TGSettingsPageRoot = 0,
	TGSettingsPageAppearance,
	TGSettingsPageData,
	TGSettingsPageNotifications,
	TGSettingsPagePrivacy,
	TGSettingsPageLanguage,
	TGSettingsPageBlocked,
	TGSettingsPagePowerSaving,
	TGSettingsPageRecentCalls,
	/// Reached by tapping the version under the root list ten times, the way
	/// their Debug Menu is. Not linked from anywhere.
	TGSettingsPageDebug
};

@interface TGSettingsViewController : UITableViewController

/// Root unless set before the view loads.
@property (nonatomic, assign) TGSettingsPage page;

@end
