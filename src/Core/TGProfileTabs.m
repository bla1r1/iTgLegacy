//
// TGProfileTabs.m
//
#import "TGProfileTabs.h"

NSArray *TGProfileTabKinds(BOOL hasStories, BOOL hasGifts, BOOL hasCommonGroups,
		BOOL ownPublicProfile, NSString *mainKind) {
	NSMutableArray *out = [NSMutableArray array];
	if (hasStories || ownPublicProfile)
		[out addObject:@"stories"];
	if (hasGifts)
		[out addObject:@"gifts"];
	if (!ownPublicProfile)
		[out addObjectsFromArray:@[@"media", @"files", @"music", @"voice", @"links"]];
	if (hasCommonGroups)
		[out addObject:@"groups"];
	if (ownPublicProfile)
		[out addObject:@"archive"];

	// td_api's profileTabPosts is the stories posted to the page.
	NSString *chosen = [mainKind isEqualToString:@"posts"] ? @"stories" : mainKind;
	if (chosen.length && [out containsObject:chosen]){
		[out removeObject:chosen];
		[out insertObject:chosen atIndex:0];
	}
	return out;
}
