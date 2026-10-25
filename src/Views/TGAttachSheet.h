//
// TGAttachSheet - Telegram's attach menu: a strip of the latest photos to
// send in one tap, and the other kinds of attachment as buttons under it.
//
#import "TGSheet.h"

typedef NS_ENUM(NSInteger, TGAttachChoice) {
	TGAttachChoiceGallery = 0,
	TGAttachChoiceLocation,
	TGAttachChoiceContact
};

@interface TGAttachSheet : TGSheet

/// Called with a full-size picture from the strip.
@property (nonatomic, copy) void (^onPhoto)(UIImage *image);
@property (nonatomic, copy) void (^onChoice)(TGAttachChoice choice);

/// Covers `view` with a dimmed backdrop and slides the sheet up from the
/// bottom, both TGSheet's. The strip only appears where TGCapabilities
/// allows it.
+ (TGAttachSheet *)showInView:(UIView *)view;

@end
