//
// TGGiftViewer.h - the bottom sheet a gift tile opens.
//
#import "TGSheet.h"

@interface TGGiftViewer : TGSheet

/// `gift` is the flattened gift dictionary (emoji, date, starCount,
/// message, thumbFileId, senderUserId - all optional). The card rises from
/// the bottom of `host`, like the official sheet: big artwork, the heading,
/// a From / Date / Value table, the note the gift carries and a full-width
/// OK button. It is as tall as its contents.
///
/// Tapping the backdrop or the close button dismisses the sheet; nothing
/// else does. The backdrop, the corners and the slide are TGSheet's.
+ (void)showGift:(NSDictionary *)gift inView:(UIView *)host;

/// Close whatever sheet is open, if any. Called when a screen goes away.
+ (void)dismiss;

@end
