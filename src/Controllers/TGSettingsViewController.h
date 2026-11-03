//
// TGSettingsViewController - account, settings pages, and maintenance UI.
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
	TGSettingsPageFolders,
	TGSettingsPageProxy,
	TGSettingsPageDownloads,
	TGSettingsPageWallpaper,
	TGSettingsPageAutosave,
	/// Orders and payment data: the saved checkout, a card lookup, a
	/// suggested post's offer and validateOrderInfo. Reached from Privacy and
	/// Security's payment section.
	TGSettingsPagePaymentData,
	/// Reached from Notifications and Sounds: saved sounds and the local list
	/// TDLib keeps while the app is running.
	TGSettingsPageNotificationSounds,
	TGSettingsPageActiveNotifications,
	/// Dev mode's settings tab and the consoles under it. Dev builds only.
	TGSettingsPageDebug,
	TGSettingsPageLanguageDev,
	TGSettingsPagePaymentDev
};

@interface TGSettingsViewController : UITableViewController

/// Root unless set before the view loads.
@property (nonatomic, assign) TGSettingsPage page;

@end
