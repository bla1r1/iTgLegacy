//
// TGGroupMemberActions - what a group member row does.
//
// A tap opens the person's profile; a hold (and the sheet's own Member Info)
// uses this class. The group profile and Group Settings draw the same member
// list, and the list used to own this menu. Keeping one copy means a promote,
// a removal or a handover cannot behave one way on the profile and another in
// settings.
//
#import <UIKit/UIKit.h>

@interface TGGroupMemberActions : NSObject

/// Opens the member's action sheet from `host`. `onChanged` runs after a
/// change Telegram accepted, so the screen that owns the list can re-read it.
+ (void)showForMember:(NSDictionary *)member
			   inChat:(int64_t)chatId
				 from:(UIViewController *)host
			onChanged:(void (^)(void))onChanged;

/// Opens the person's profile - never a private chat. This is what tapping a
/// member row and "Member Info" both mean. The profile is addressed the way
/// every other user profile is: the user id stands in for the chat id.
+ (void)openProfileForMember:(NSDictionary *)member from:(UIViewController *)host;

/// The navigation fallback the group surfaces share: push when `host` is on
/// a stack, otherwise present `controller` inside its own navigation
/// controller with a Done button. Never a no-op.
FOUNDATION_EXPORT void TGPresentControllerFrom(UIViewController *controller,
											   UIViewController *host);

@end
