//
// TGMemberAvatarStore - the face on a member row.
//
// A member list gives an id and a name, not a picture. Both the group profile
// and Group Settings draw that list, so the lookup, the download and the
// decode live here once: a screen asks for a user at the size its row uses
// and gets the picture back, or nil while it is on its way.
//
#import <UIKit/UIKit.h>

@interface TGMemberAvatarStore : NSObject

+ (instancetype)shared;

/// The picture if it has already been decoded at this size.
- (UIImage *)cachedAvatarForUser:(int64_t)userId side:(CGFloat)side;

/// Asks for the user's profile photo, scaled to a square `side`. The
/// completion runs on the main queue and is called once per request; a
/// second row for the same user waits on the first download instead of
/// starting another. `completion` gets nil when the user has no photo or
/// the download failed - the caller keeps its initials.
- (void)loadAvatarForUser:(int64_t)userId
					 side:(CGFloat)side
			   completion:(void (^)(UIImage *image))completion;

@end
