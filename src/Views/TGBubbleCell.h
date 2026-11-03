//
// TGBubbleCell.h - Table view cell for chat bubbles.
//
#import <UIKit/UIKit.h>
#import "TGMessageLayout.h"
#import "TGLottieView.h"

@interface TGBubbleCell : UITableViewCell

@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UILabel *time;
@property (nonatomic, strong) TGLottieView *lottie;
@property (nonatomic, strong) UILabel *icon;
@property (nonatomic, strong) UILabel *subtitle;
@property (nonatomic, strong) UILabel *sender;
@property (nonatomic, strong) UIView  *quoteBar;
@property (nonatomic, strong) UILabel *quote;
@property (nonatomic, strong) UILabel *quoteAuthor;
@property (nonatomic, strong) UIImageView *ticks;
/// Skeuomorphic top specular highlight reflection line for tactile iOS 6 bubbles.
@property (nonatomic, strong) UIView *shineBar;
@property (nonatomic, strong) CAGradientLayer *shineGradientLayer;
/// Gradient, edge and tail of the bubble as one stretchable picture. It
/// replaced a CAShapeLayer mask, a gradient layer and a stroked shape layer
/// per bubble: on an A4 backboardd re-rendered the mask offscreen and
/// stroked the path on the CPU every frame, which was 3.4 s of every 8 s
/// of scrolling.
@property (nonatomic, strong) UIImageView *bubbleBack;

/// The dot that says a voice note has not been listened to or a round note
/// has not been watched. It lives beside the clock, not inside the bubble,
/// because on a round note the bubble clips to a circle.
@property (nonatomic, strong) UIView *unreadDot;
@property (nonatomic, strong) UIImageView *checkbox;
@property (nonatomic, strong) UIImageView *senderAvatar;
@property (nonatomic, strong) UIImageView *tail;
@property (nonatomic, strong) UIImageView *disc;
/// Album art on a track bubble. Its own view rather than the picture one:
/// a track is not a photo message, and the two are laid out differently.
@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, strong) UIImageView *wave;

/// Lays the voice-note bars out as two filled paths - the whole waveform dim,
/// the listened part solid and clipped - inside -wave. Cheap to call again
/// with the same waveform and box: the path is only rebuilt when one changes.
- (void)setWaveform:(NSData *)waveform size:(CGSize)size colour:(UIColor *)colour;

/// Moves the boundary between the two, 0 to 1. One frame assignment: nothing
/// is drawn, allocated or rasterized, which is what lets playback tick.
- (void)setWavePlayed:(CGFloat)played;

/// The turning arc round a sending note's disc. The arc is a shape layer on
/// the disc itself, so the table never reloads to move it. 0..1.
- (void)showSendRingWithProgress:(CGFloat)progress;
- (void)hideSendRing;

@property (nonatomic, strong) UILabel *mediaStamp;
@property (nonatomic, assign) int64_t voiceMessageId;
@property (nonatomic, assign) int64_t pollMessageId;
/// What the option rows were built from: the tally, the chosen answer and
/// whether it is closed. Keeping it lets a reused cell keep its rows while
/// still rebuilding them the moment a vote lands.
@property (nonatomic, assign) NSUInteger pollRevision;
@property (nonatomic, strong) UILabel *forwardLabel;

// Contact card components
@property (nonatomic, strong) UIButton *contactCallButton;
@property (nonatomic, strong) UIButton *contactAddButton;
@property (nonatomic, strong) UIView   *contactSeparatorH;
@property (nonatomic, strong) UIView   *contactSeparatorV;

// Album collage components
@property (nonatomic, strong) UIView *collageView;
@property (nonatomic, strong) NSMutableArray *collageViews;
@property (nonatomic, strong) UILabel *collageMoreLabel;
@property (nonatomic, copy) void (^onCollageItemTapped)(NSInteger index);
@property (nonatomic, copy) void (^onLinkTapped)(NSString *url);
/// Following a reply: the quote header is a button, and this is where it fires.
@property (nonatomic, copy) void (^onQuoteTapped)(void);

/// A GIF looping silently over the picture. Telegram's GIFs are short
/// MP4s, so this is a muted video layer, not an image sequence.
- (void)playLoopingVideoAtPath:(NSString *)path;
- (void)stopLoopingVideo;
@property (nonatomic, readonly) BOOL isPlayingLoop;
@property (nonatomic, readonly) NSString *loopingPath;

- (void)resetForReuse;
/// Takes every hidden subview of the bubble and the content view out of the
/// tree; resetForReuse puts them back where they were. Call once the row is
/// configured. A chat row holds 46 layers and shows about 10, and backboardd
/// walked and composited all 46 on every frame of a scroll: parking the
/// hidden ones took the iPod touch 4 from 10-26% dropped frames to 1%.
- (void)parkHiddenViews;
- (void)applyTheme;

@end
