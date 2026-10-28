//
// TGMessageLayout.h - Geometry, sizing and layout cache for chat bubbles.
//
#import <UIKit/UIKit.h>
#import "TGStyle.h"

static const CGFloat kBubbleMaxW      = TGMetricBubbleMaxW;   // text width; the bubble is ~83% of the screen
static const CGFloat kPadH            = TGMetricBubblePadH;
static const CGFloat kAvatarSide      = TGMetricGroupAvatarSide;   // sender avatar in groups
static const CGFloat kPadV            = TGMetricBubblePadV;
static const CGFloat kImageMax        = TGMetricImageMax;
static const CGFloat kSendSide        = TGMetricSendSide;   // the round send button
static const CGFloat kFileTile        = TGMetricFileTile;
static const CGFloat kFileDisc        = TGMetricFileDisc;
static const CGFloat kTrackArt        = TGMetricTrackArt;   // album cover on a track bubble
static const CGFloat kTrackDisc       = TGMetricTrackDisc;   // the play arrow over it
static const CGFloat kTrackRow        = TGMetricTrackRow;   // the whole bubble, which is fixed
static const CGFloat kPlayerBarHeight = TGMetricPlayerBarHeight;  // the strip under the header
static const CGFloat kPlayerArt       = TGMetricPlayerArt;   // its album cover
static const CGFloat kMediaRadius     = TGMetricCornerMedium;
static const CGFloat kPollRow         = TGMetricPollRow;
static const CGFloat kTailWidth       = TGMetricBubbleTailWidth;    // the hook on the last bubble of a run
static const CGFloat kTailHeight      = TGMetricBubbleTailHeight;

#ifdef __cplusplus
extern "C" {
#endif

UIFont *TGEmojiFontOfSize(CGFloat size);
BOOL TGIsEmojiScalar(UTF32Char c);
NSAttributedString *TGEmojiAttributedText(NSString *text, UIFont *base);
NSAttributedString *TGAttributedMessageText(NSString *text, NSArray *entities, UIFont *baseFont, UIColor *textColor);
void TGSetBodyText(UILabel *label, NSString *text, UIColor *colour);
CGSize TGTextSize(NSString *text, UIFont *font, CGFloat width);
CGSize TGTextSizeWithEntities(NSString *text, NSArray *entities, UIFont *font, CGFloat width);

#ifdef __cplusplus
}
#endif

@interface TGMessageLayout : NSObject
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) CGRect bubbleFrame;
@property (nonatomic, assign) CGRect bodyFrame;
@property (nonatomic, assign) CGRect senderAvatarFrame;
@property (nonatomic, assign) CGRect senderFrame;
@property (nonatomic, assign) CGRect tailFrame;
@property (nonatomic, assign) CGRect quoteBarFrame;
@property (nonatomic, assign) CGRect quoteAuthorFrame;
@property (nonatomic, assign) CGRect quoteFrame;
@property (nonatomic, assign) CGRect pictureFrame;
@property (nonatomic, assign) CGRect collageFrame;
@property (nonatomic, strong) NSArray *albumFrames;
@property (nonatomic, assign) CGRect mediaStampFrame;
@property (nonatomic, assign) CGRect timeFrame;
@property (nonatomic, assign) CGSize bodySize;
@property (nonatomic, assign) CGSize picSize;
@property (nonatomic, assign) BOOL inlineStamp;
@property (nonatomic, assign) BOOL stampOnPicture;
@property (nonatomic, copy)   NSString *stamp;
@property (nonatomic, assign) CGFloat timeWidth;
@property (nonatomic, copy)   NSString *senderName;
@property (nonatomic, copy)   NSString *quoteText;
@property (nonatomic, copy)   NSString *quoteAuthor;
@property (nonatomic, assign) BOOL isService;
@property (nonatomic, assign) BOOL isSticker;
@property (nonatomic, assign) BOOL isVoice;
@property (nonatomic, assign) BOOL isPoll;
@property (nonatomic, assign) BOOL isCall;
@property (nonatomic, assign) BOOL isDoc;
/// A track: a file with a title and a performer of its own, drawn as one
/// rather than as the document it also is.
@property (nonatomic, assign) BOOL isTrack;
@property (nonatomic, assign) BOOL isContact;
@property (nonatomic, assign) BOOL isRound;
@property (nonatomic, assign) BOOL isLocation;
@property (nonatomic, assign) BOOL isAlbum;
@property (nonatomic, assign) CGFloat fwdHeight;
@property (nonatomic, strong) NSArray *entities;
@property (nonatomic, strong) NSAttributedString *attributedBody;
@end

#ifdef __cplusplus
extern "C" {
#endif

NSString *TGDescribeMessageContent(NSDictionary *m);

void TGVideoNoteLayoutBottomBar(CGRect bubbleFrame,
								CGFloat durWidth,
								CGFloat clockWidth,
								bool mine,
								bool unplayed,
								CGRect *outDurFrame,
								CGRect *outTimeFrame,
								CGRect *outTicksFrame,
								CGRect *outDotFrame);

#ifdef __cplusplus
}
#endif
