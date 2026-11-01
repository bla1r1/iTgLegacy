//
// TGSettingsViewController+Tier2.h - the Business row and the Proxy page's
// web-carrier row, kept out of the root page's own categories.
//
#import "TGSettingsViewController.h"

@interface TGSettingsViewController (Tier2)

/// The root list's Telegram Business row. The caller puts it where the
/// placeholder used to sit.
- (NSDictionary *)tier2BusinessRow;

/// The Proxy page's row into the web proxy carrier screen.
- (NSDictionary *)tier2ProxyCarrierRow;

/// The root list's row into communities, saved replies and AI tools.
- (NSDictionary *)tier2ToolsRow;

/// The Profile Extras section: emoji status, profile audio, text styles and
/// the stake dice screen.
- (NSArray *)tier2Sections;

@end

// vim:ft=objc
