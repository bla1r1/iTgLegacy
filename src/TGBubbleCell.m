//
// TGBubbleCell.m - Table view cell for chat bubbles.
//
#import "TGBubbleCell.h"
#import "TGTheme.h"
#import "TGIcons.h"

@implementation TGBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;

	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;

	self.bubble = [[UIView alloc] init];
	self.bubble.layer.cornerRadius = 14;
	self.bubble.layer.borderWidth = 1.0f;
	self.bubble.clipsToBounds = YES;
	self.bubble.layer.shouldRasterize = YES;
	self.bubble.layer.rasterizationScale = scale;
	[self.contentView addSubview:self.bubble];

	self.picture = [[UIImageView alloc] init];
	self.picture.contentMode = UIViewContentModeScaleAspectFill;
	self.picture.clipsToBounds = YES;
	self.picture.layer.shouldRasterize = YES;
	self.picture.layer.rasterizationScale = scale;
	[self.bubble addSubview:self.picture];

	self.body = [[UILabel alloc] init];
	self.body.numberOfLines = 0;
	self.body.lineBreakMode = NSLineBreakByWordWrapping;
	self.body.font = [UIFont systemFontOfSize:[TGTheme shared].messageFontSize];
	self.body.backgroundColor = [UIColor clearColor];
	[self.bubble addSubview:self.body];

	self.sender = [[UILabel alloc] init];
	self.sender.font = [UIFont boldSystemFontOfSize:12];
	self.sender.lineBreakMode = NSLineBreakByTruncatingTail;
	self.sender.backgroundColor = [UIColor clearColor];
	self.sender.hidden = YES;
	[self.contentView addSubview:self.sender];

	self.disc = [[UIImageView alloc] init];
	self.disc.hidden = YES;
	[self.bubble addSubview:self.disc];

	self.wave = [[UIImageView alloc] init];
	self.wave.hidden = YES;
	[self.bubble addSubview:self.wave];

	self.tail = [[UIImageView alloc] init];
	self.tail.hidden = YES;
	[self.contentView addSubview:self.tail];

	self.senderAvatar = [[UIImageView alloc] init];
	self.senderAvatar.layer.cornerRadius = kAvatarSide / 2;
	self.senderAvatar.clipsToBounds = YES;
	self.senderAvatar.layer.shouldRasterize = YES;
	self.senderAvatar.layer.rasterizationScale = scale;
	self.senderAvatar.hidden = YES;
	[self.contentView addSubview:self.senderAvatar];

	self.ticks = [[UIImageView alloc] init];
	self.ticks.hidden = YES;
	[self.bubble addSubview:self.ticks];

	self.quoteBar = [[UIView alloc] init];
	self.quoteBar.hidden = YES;
	[self.bubble addSubview:self.quoteBar];

	self.quoteAuthor = [[UILabel alloc] init];
	self.quoteAuthor.font = [UIFont boldSystemFontOfSize:13];
	self.quoteAuthor.backgroundColor = [UIColor clearColor];
	self.quoteAuthor.hidden = YES;
	[self.bubble addSubview:self.quoteAuthor];

	self.quote = [[UILabel alloc] init];
	self.quote.font = [UIFont systemFontOfSize:13];
	self.quote.numberOfLines = 2;
	self.quote.backgroundColor = [UIColor clearColor];
	self.quote.hidden = YES;
	[self.bubble addSubview:self.quote];

	self.icon = [[UILabel alloc] init];
	self.icon.textAlignment = NSTextAlignmentCenter;
	self.icon.textColor = [UIColor whiteColor];
	self.icon.font = [UIFont boldSystemFontOfSize:17];
	self.icon.clipsToBounds = YES;
	self.icon.hidden = YES;
	[self.bubble addSubview:self.icon];

	self.subtitle = [[UILabel alloc] init];
	self.subtitle.font = [UIFont systemFontOfSize:13];
	self.subtitle.textColor = [[TGTheme shared] fileMetaColour];
	self.subtitle.backgroundColor = [UIColor clearColor];
	self.subtitle.hidden = YES;
	[self.bubble addSubview:self.subtitle];

	self.lottie = [[TGLottieView alloc] initWithFrame:CGRectZero];
	self.lottie.hidden = YES;
	[self.bubble addSubview:self.lottie];

	self.forwardLabel = [[UILabel alloc] init];
	self.forwardLabel.font = [UIFont systemFontOfSize:12];
	self.forwardLabel.backgroundColor = [UIColor clearColor];
	self.forwardLabel.hidden = YES;
	[self.bubble addSubview:self.forwardLabel];

	self.mediaStamp = [[UILabel alloc] init];
	self.mediaStamp.font = [UIFont systemFontOfSize:11];
	self.mediaStamp.textColor = [UIColor whiteColor];
	self.mediaStamp.textAlignment = NSTextAlignmentCenter;
	self.mediaStamp.layer.cornerRadius = 8;
	self.mediaStamp.clipsToBounds = YES;
	self.mediaStamp.layer.shouldRasterize = YES;
	self.mediaStamp.layer.rasterizationScale = scale;
	self.mediaStamp.hidden = YES;
	[self.bubble addSubview:self.mediaStamp];

	self.time = [[UILabel alloc] init];
	self.time.font = [UIFont systemFontOfSize:11];
	self.time.backgroundColor = [UIColor clearColor];
	self.time.textAlignment = NSTextAlignmentRight;
	[self.bubble addSubview:self.time];

	self.contactSeparatorH = [[UIView alloc] init];
	self.contactSeparatorH.hidden = YES;
	[self.bubble addSubview:self.contactSeparatorH];

	self.contactSeparatorV = [[UIView alloc] init];
	self.contactSeparatorV.hidden = YES;
	[self.bubble addSubview:self.contactSeparatorV];

	self.contactCallButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.contactCallButton.titleLabel.font = [UIFont systemFontOfSize:14];
	self.contactCallButton.hidden = YES;
	[self.contactCallButton setTitle:@"Call" forState:UIControlStateNormal];
	[self.bubble addSubview:self.contactCallButton];

	self.contactAddButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.contactAddButton.titleLabel.font = [UIFont systemFontOfSize:14];
	self.contactAddButton.hidden = YES;
	[self.contactAddButton setTitle:@"Add" forState:UIControlStateNormal];
	[self.bubble addSubview:self.contactAddButton];

	return self;
}

- (void)resetForReuse {
	self.icon.hidden = YES;
	self.subtitle.hidden = YES;
	self.sender.hidden = YES;
	self.senderAvatar.hidden = YES;
	self.tail.hidden = YES;
	self.disc.hidden = YES;
	self.wave.hidden = YES;
	self.contactCallButton.hidden = YES;
	self.contactAddButton.hidden = YES;
	self.contactSeparatorH.hidden = YES;
	self.contactSeparatorV.hidden = YES;
	self.mediaStamp.hidden = YES;
	self.quoteBar.hidden = YES;
	self.quote.hidden = YES;
	self.quoteAuthor.hidden = YES;
	self.forwardLabel.hidden = YES;
	self.lottie.hidden = YES;
	[self.lottie stop];
}

@end
