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
@property (nonatomic, strong) UIImageView *checkbox;
@property (nonatomic, strong) UIImageView *senderAvatar;
@property (nonatomic, strong) UIImageView *tail;
@property (nonatomic, strong) UIImageView *disc;
/// Album art on a track bubble. Its own view rather than the picture one:
/// a track is not a photo message, and the two are laid out differently.
@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, strong) UIImageView *wave;
@property (nonatomic, strong) UILabel *mediaStamp;
@property (nonatomic, assign) int64_t voiceMessageId;
@property (nonatomic, strong) NSData *waveformData;
@property (nonatomic, assign) int64_t pollMessageId;
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

/// A GIF looping silently over the picture. Telegram's GIFs are short
/// MP4s, so this is a muted video layer, not an image sequence.
- (void)playLoopingVideoAtPath:(NSString *)path;
- (void)stopLoopingVideo;
@property (nonatomic, readonly) BOOL isPlayingLoop;
@property (nonatomic, readonly) NSString *loopingPath;

- (void)resetForReuse;
- (void)applyTheme;

@end
