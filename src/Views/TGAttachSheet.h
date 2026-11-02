//
// TGAttachSheet - Telegram's attach sheet: a grid of the newest photos to tick
// and send, a camera tile in front of them, and a row of the other kinds of
// attachment along the bottom.
//
#import "TGSheet.h"

typedef NS_ENUM(NSInteger, TGAttachChoice) {
	TGAttachChoiceGallery = 0,
	TGAttachChoiceLocation,
	TGAttachChoiceContact,
	TGAttachChoiceChecklist,
	TGAttachChoiceQuickReply,
	/// The stake dice panel and the ephemeral composer do not attach a file;
	/// they open a screen of their own at the end of the same row.
	TGAttachChoiceDice,
	TGAttachChoiceEphemeral,
	/// The first tile of the grid. Last in the enum so the values the strip
	/// maps to its tiles keep their numbers.
	TGAttachChoiceCamera
};

@interface TGAttachSheet : TGSheet

/// Called with a full-size picture when exactly one tile was ticked.
@property (nonatomic, copy) void (^onPhoto)(UIImage *image);

/// Several pictures at once, in the order they were ticked. A tap on a tile
/// ticks and unticks it; the Send button takes the place of the bottom row
/// while anything is ticked.
@property (nonatomic, copy) void (^onPhotos)(NSArray *images);
@property (nonatomic, copy) void (^onChoice)(TGAttachChoice choice);

/// Covers `view` with a dimmed backdrop and slides the sheet up from the
/// bottom, both TGSheet's. The photos are read once the slide is over, so
/// the sheet is not held up by the library.
+ (TGAttachSheet *)showInView:(UIView *)view;

@end
