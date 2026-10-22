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
@property (nonatomic, strong) UIImageView *senderAvatar;
@property (nonatomic, strong) UIImageView *tail;
@property (nonatomic, strong) UIImageView *disc;
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

- (void)resetForReuse;

@end
