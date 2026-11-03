//
// TGProfileAudioViewController - the music on a profile.
//
// A profile audio row plays through TGMusicPlayer, the same queue the chat's
// audio tracks use, so the lock screen and the transport do not fork.
//
#import <UIKit/UIKit.h>

@interface TGProfileAudioViewController : UITableViewController

@property (nonatomic, assign) int64_t userId;
@property (nonatomic, copy)   NSString *subjectTitle;
/// The strip under a profile header opens this screen to start the list; the
/// first page plays as soon as it answers.
@property (nonatomic, assign) BOOL autoplay;

@end
