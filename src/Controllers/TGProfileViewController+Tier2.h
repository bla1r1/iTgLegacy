//
// TGProfileViewController+Tier2 - the profile's entries into the emoji
// status picker, the profile audio list, direct message topics and the
// stake dice panel.
//
#import "TGProfileViewController.h"

@interface TGProfileViewController (Tier2)

/// Rows for the More menu. Kept in this one category so the profile root and
/// its existing actions do not learn four new titles.
- (NSArray *)tier2MoreItems;

/// Runs one of -tier2MoreItems' titles. YES when the title was ours.
- (BOOL)runTier2Action:(NSString *)title;

@end
