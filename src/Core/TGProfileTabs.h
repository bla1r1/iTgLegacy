//
// TGProfileTabs.h - which tabs a profile shows, in the official client's order.
//
#import <Foundation/Foundation.h>

/// The tab kinds, first to last. `ownPublicProfile` is My Profile: what you publish
/// and your archive, without the Saved Messages chat that shares your user id.
/// `mainKind` is the name from main_profile_tab, which moves its tab to the front.
FOUNDATION_EXPORT NSArray *TGProfileTabKinds(BOOL hasStories, BOOL hasGifts, BOOL hasCommonGroups,
		BOOL ownPublicProfile, NSString *mainKind);
