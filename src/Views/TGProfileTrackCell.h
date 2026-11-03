//
// TGProfileTrackCell - one saved or shared track in a profile list.
//
// The chat's track bubble and this row show the same four things: a 44 pt
// cover, a play/pause disc over it, the title over the performer and length,
// and the length on the right. Keeping the geometry here stops the profile
// from growing a second track row.
//
#import <UIKit/UIKit.h>

@interface TGProfileTrackCell : UITableViewCell

- (void)configureTitle:(NSString *)title
				artist:(NSString *)artist
			  duration:(NSString *)duration
			   current:(BOOL)current
			   playing:(BOOL)playing;
/// The controller downloads the cover; the row only draws what it is given.
- (void)setArtworkImage:(UIImage *)image;

@end

// vim:ft=objc
