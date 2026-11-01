//
// TGGroupCallParticipantCell - one person in a group call.
//
// The row carries more state than a member row: speaking, a raised hand, a
// mute that can be for everyone or only for this device, the volume, and
// whether video or screen sharing is live. Keeping it in one cell means the
// call screen and the full participant list cannot describe the same person
// two different ways.
//
#import <UIKit/UIKit.h>

@interface TGGroupCallParticipantCell : UITableViewCell

/// `participant` is the flat row TGClient+GroupCalls hands out. `table` is
/// only used to re-draw this one row after a profile photo arrives.
- (void)setParticipant:(NSDictionary *)participant inTable:(UITableView *)table;

@end

// vim:ft=objc
