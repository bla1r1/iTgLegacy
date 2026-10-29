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
	/// Reached by tapping the version under the root list ten times, the way
	/// their Debug Menu is. Not linked from anywhere.
	TGSettingsPageDebug
};

@interface TGSettingsViewController : UITableViewController

/// Root unless set before the view loads.
@property (nonatomic, assign) TGSettingsPage page;

@end
