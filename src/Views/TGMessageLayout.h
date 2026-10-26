//
// TGMessageLayout.h - Geometry, sizing and layout cache for chat bubbles.
//
#import <UIKit/UIKit.h>

static const CGFloat kBubbleMaxW  = 246.0f;   // text width; the bubble is ~83% of the screen
static const CGFloat kPadH        = 10.0f;
static const CGFloat kAvatarSide  = 28.0f;   // sender avatar in groups
static const CGFloat kPadV        = 7.0f;
static const CGFloat kImageMax    = 200.0f;
static const CGFloat kSendSide    = 36.0f;   // the round send button
static const CGFloat kFileTile    = 71.0f;
static const CGFloat kFileDisc    = 37.0f;
static const CGFloat kTrackArt    = 44.0f;   // album cover on a track bubble
static const CGFloat kTrackDisc   = 28.0f;   // the play arrow over it
static const CGFloat kTrackRow    = 60.0f;   // the whole bubble, which is fixed
static const CGFloat kPlayerBarHeight = 48.0f;  // the strip under the header
static const CGFloat kPlayerArt   = 36.0f;   // its album cover
static const CGFloat kMediaRadius = 6.0f;
static const CGFloat kPollRow     = 30.0f;
static const CGFloat kTailWidth   = 6.0f;    // the hook on the last bubble of a run
static const CGFloat kTailHeight  = 13.0f;

UIFont *TGEmojiFontOfSize(CGFloat size);
BOOL TGIsEmojiScalar(UTF32Char c);
NSAttributedString *TGEmojiAttributedText(NSString *text, UIFont *base);
NSAttributedString *TGAttributedMessageText(NSString *text, NSArray *entities, UIFont *baseFont, UIColor *textColor);
void TGSetBodyText(UILabel *label, NSString *text, UIColor *colour);
CGSize TGTextSize(NSString *text, UIFont *font, CGFloat width);
CGSize TGTextSizeWithEntities(NSString *text, NSArray *entities, UIFont *font, CGFloat width);

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
