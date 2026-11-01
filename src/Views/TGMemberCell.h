//
// TGMemberCell - a person's row in a group: their picture, their name.
//
// The stock cell sizes its image view to the picture and puts it at x 0 on
// iOS 6, so a large photo filled the row height flush against the screen
// edge. The same inset the contacts list uses is kept here, and both member
// lists use this cell so a group profile and Group Settings cannot drift.
//
#import <UIKit/UIKit.h>

@interface TGMemberCell : UITableViewCell

/// Draws the row's picture from the avatar store, or the initials while it
/// arrives. `tableView` is only used to re-ask for this one row once the
/// picture is decoded - reloading the whole table for one face is what made
/// the member list flicker while scrolling.
- (void)setName:(NSString *)name userId:(int64_t)userId inTable:(UITableView *)tableView;

/// The same row with the member's role. "owner" and "admin" draw a compact
/// pill after the name; every other status draws only the name. The role is
/// a badge here, never a count - the list must not say "3 admins".
- (void)setName:(NSString *)name
		 userId:(int64_t)userId
		 status:(NSString *)status
		inTable:(UITableView *)tableView;

/// The same row with the member's own tag. TDLib returns an administrator's
/// custom title in chatMember.tag; when it is empty the role word is the
/// badge instead, so an administrator always reads as something.
- (void)setName:(NSString *)name
		 userId:(int64_t)userId
		 status:(NSString *)status
			tag:(NSString *)tag
		inTable:(UITableView *)tableView;

@end
