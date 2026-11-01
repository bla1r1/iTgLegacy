//
// TGGroupMemberActions - what tapping a member in a group does.
//
// The group profile and Group Settings draw the same member list, and the
// list used to own this menu. Keeping one copy means a promote, a removal or
// a handover cannot behave one way on the profile and another in settings.
//
#import <UIKit/UIKit.h>

@interface TGGroupMemberActions : NSObject

/// Opens the member's action sheet from `host`. `onChanged` runs after a
/// change Telegram accepted, so the screen that owns the list can re-read it.
+ (void)showForMember:(NSDictionary *)member
			   inChat:(int64_t)chatId
				 from:(UIViewController *)host
			onChanged:(void (^)(void))onChanged;

@end
