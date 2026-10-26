//
// TGBubbleCell.m - Table view cell for chat bubbles.
//
#import "TGBubbleCell.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <AVFoundation/AVFoundation.h>
#import "TGStyle.h"

@interface TGBubbleCell ()
@property (nonatomic, strong) AVPlayer *loopPlayer;
@property (nonatomic, strong) AVPlayerLayer *loopLayer;
@property (nonatomic, copy) NSString *loopingPath;
@end

@implementation TGBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;

	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;

	TGTheme *theme = [TGTheme shared];
	self.bubble = [[UIView alloc] init];
	self.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	self.bubble.layer.borderWidth = [theme bubbleBorderWidth];
	self.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
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
	self.body.font = TGFontAtSize(theme.messageFontSize);
	self.body.backgroundColor = [UIColor clearColor];
	[self.bubble addSubview:self.body];

	self.sender = [[UILabel alloc] init];
	self.sender.font = TGFontMetaStrong();
	self.sender.lineBreakMode = NSLineBreakByTruncatingTail;
	self.sender.backgroundColor = [UIColor clearColor];
	self.sender.hidden = YES;
	[self.bubble addSubview:self.sender];

	// Under the disc: the play arrow sits over the album art.
	self.artwork = [[UIImageView alloc] init];
	self.artwork.hidden = YES;
	self.artwork.contentMode = UIViewContentModeScaleAspectFill;
	self.artwork.clipsToBounds = YES;
	self.artwork.layer.cornerRadius = TGMetricCornerSmall;
	[self.bubble addSubview:self.artwork];

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
	self.senderAvatar.layer.cornerRadius = TGHalf(TGMetricGroupAvatarSide);
	self.senderAvatar.clipsToBounds = YES;
	self.senderAvatar.layer.shouldRasterize = YES;
	self.senderAvatar.layer.rasterizationScale = scale;
	self.senderAvatar.hidden = YES;
	[self.contentView addSubview:self.senderAvatar];

	self.ticks = [[UIImageView alloc] init];
	self.ticks.hidden = YES;
	[self.bubble addSubview:self.ticks];

	self.checkbox = [[UIImageView alloc] init];
	self.checkbox.hidden = YES;
	self.checkbox.contentMode = UIViewContentModeCenter;
	[self.contentView addSubview:self.checkbox];

	self.quoteBar = [[UIView alloc] init];
	self.quoteBar.hidden = YES;
	[self.bubble addSubview:self.quoteBar];

	self.quoteAuthor = [[UILabel alloc] init];
	self.quoteAuthor.font = TGFontCaptionStrong();
	self.quoteAuthor.backgroundColor = [UIColor clearColor];
	self.quoteAuthor.hidden = YES;
	[self.bubble addSubview:self.quoteAuthor];

	self.quote = [[UILabel alloc] init];
	self.quote.font = TGFontCaption();
	self.quote.numberOfLines = 2;
	self.quote.backgroundColor = [UIColor clearColor];
	self.quote.hidden = YES;
	[self.bubble addSubview:self.quote];

	self.icon = [[UILabel alloc] init];
	self.icon.textAlignment = NSTextAlignmentCenter;
	self.icon.textColor = [UIColor whiteColor];
	self.icon.font = TGFontHeader();
	self.icon.clipsToBounds = YES;
	self.icon.hidden = YES;
	[self.bubble addSubview:self.icon];

	self.subtitle = [[UILabel alloc] init];
	self.subtitle.font = TGFontCaption();
	self.subtitle.textColor = [[TGTheme shared] fileMetaColour];
	self.subtitle.backgroundColor = [UIColor clearColor];
	self.subtitle.hidden = YES;
	[self.bubble addSubview:self.subtitle];

	self.lottie = [[TGLottieView alloc] initWithFrame:CGRectZero];
	self.lottie.hidden = YES;
	[self.bubble addSubview:self.lottie];

	self.forwardLabel = [[UILabel alloc] init];
	self.forwardLabel.font = TGFontMeta();
	self.forwardLabel.backgroundColor = [UIColor clearColor];
	self.forwardLabel.hidden = YES;
	[self.bubble addSubview:self.forwardLabel];

	self.mediaStamp = [[UILabel alloc] init];
	self.mediaStamp.font = TGFontMicro();
	self.mediaStamp.textColor = [UIColor whiteColor];
	self.mediaStamp.textAlignment = NSTextAlignmentCenter;
	self.mediaStamp.layer.cornerRadius = TGMetricCornerControl;
	self.mediaStamp.clipsToBounds = YES;
	self.mediaStamp.layer.shouldRasterize = YES;
	self.mediaStamp.layer.rasterizationScale = scale;
	self.mediaStamp.hidden = YES;
	[self.bubble addSubview:self.mediaStamp];

	self.time = [[UILabel alloc] init];
	self.time.font = TGFontMicro();
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
	self.contactCallButton.titleLabel.font = TGFontSubhead();
	self.contactCallButton.hidden = YES;
	[self.contactCallButton setTitle:@"Call" forState:UIControlStateNormal];
	[self.contactCallButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[self.bubble addSubview:self.contactCallButton];

	self.contactAddButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.contactAddButton.titleLabel.font = TGFontSubhead();
	self.contactAddButton.hidden = YES;
	[self.contactAddButton setTitle:@"Add" forState:UIControlStateNormal];
	[self.contactAddButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[self.bubble addSubview:self.contactAddButton];

	// Album collage container
	self.collageView = [[UIView alloc] init];
	self.collageView.hidden = YES;
	self.collageView.clipsToBounds = YES;
	self.collageViews = [NSMutableArray arrayWithCapacity:4];
	for (NSInteger i = 0; i < 4; i++) {
		UIImageView *cv = [[UIImageView alloc] init];
		cv.contentMode = UIViewContentModeScaleAspectFill;
		cv.clipsToBounds = YES;
		cv.layer.cornerRadius = TGMetricCornerSmall;
		cv.userInteractionEnabled = YES;
		cv.tag = i;
		cv.layer.shouldRasterize = YES;
		cv.layer.rasterizationScale = scale;
		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(collageItemTapped:)];
		[cv addGestureRecognizer:tap];
		[self.collageViews addObject:cv];
		[self.collageView addSubview:cv];
	}
	self.collageMoreLabel = [[UILabel alloc] init];
	self.collageMoreLabel.textAlignment = NSTextAlignmentCenter;
	self.collageMoreLabel.textColor = [UIColor whiteColor];
	self.collageMoreLabel.font = TGFontHeader();
	self.collageMoreLabel.backgroundColor = [[TGTheme shared] mediaOverlayColour];
	self.collageMoreLabel.layer.cornerRadius = TGMetricCornerSmall;
	self.collageMoreLabel.clipsToBounds = YES;
	self.collageMoreLabel.hidden = YES;
	[self.collageView addSubview:self.collageMoreLabel];
	[self.bubble addSubview:self.collageView];

	// Link tap recognizer on body label
	self.body.userInteractionEnabled = YES;
	UITapGestureRecognizer *bodyTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bodyTapped:)];
	bodyTap.delegate = (id<UIGestureRecognizerDelegate>)self;
	[self.body addGestureRecognizer:bodyTap];

	return self;
}

- (NSUInteger)characterIndexAtPoint:(CGPoint)point inLabel:(UILabel *)label {
	NSAttributedString *attr = label.attributedText;
	if (!attr.length) return NSNotFound;

	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:attr];
	NSLayoutManager *layout = [[NSLayoutManager alloc] init];
	[storage addLayoutManager:layout];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:label.bounds.size];
	container.lineFragmentPadding = TGMetricZero;
	container.lineBreakMode = label.lineBreakMode;
	container.maximumNumberOfLines = label.numberOfLines;
	[layout addTextContainer:container];

	NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:container];
	CGRect glyphRect = [layout boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:container];
	if (!CGRectContainsPoint(glyphRect, point))
		return NSNotFound;

	return [layout characterIndexForGlyphAtIndex:glyph];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
	if (gestureRecognizer.view == self.body) {
		CGPoint pt = [touch locationInView:self.body];
		NSUInteger idx = [self characterIndexAtPoint:pt inLabel:self.body];
		if (idx != NSNotFound && idx < self.body.attributedText.length) {
			NSDictionary *attrs = [self.body.attributedText attributesAtIndex:idx effectiveRange:NULL];
			return (attrs[@"TGLinkURL"] != nil);
		}
		return NO;
	}
	return YES;
}

- (void)bodyTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateEnded) return;
	CGPoint pt = [tap locationInView:self.body];
	NSUInteger idx = [self characterIndexAtPoint:pt inLabel:self.body];
	if (idx != NSNotFound && idx < self.body.attributedText.length) {
		NSDictionary *attrs = [self.body.attributedText attributesAtIndex:idx effectiveRange:NULL];
		NSString *url = attrs[@"TGLinkURL"];
		if (url.length && self.onLinkTapped) {
			self.onLinkTapped(url);
		}
	}
}

- (void)collageItemTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateEnded) return;
	NSInteger idx = tap.view.tag;
	if (self.onCollageItemTapped) {
		self.onCollageItemTapped(idx);
	}
}

#pragma mark - looping GIF

- (BOOL)isPlayingLoop {
	return self.loopPlayer != nil;
}

- (void)playLoopingVideoAtPath:(NSString *)path {
	if (!path.length)
		return;
	if (self.loopPlayer && [self.loopingPath isEqualToString:path]){
		self.loopLayer.frame = self.picture.bounds;
		return;
	}
	[self stopLoopingVideo];

	AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
	if (!player)
		return;
	if ([player respondsToSelector:@selector(setMuted:)])
		player.muted = YES;
	player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

	AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
	layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	layer.frame = self.picture.bounds;
	[self.picture.layer addSublayer:layer];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(loopEnded:)
				name:AVPlayerItemDidPlayToEndTimeNotification
			  object:player.currentItem];

	self.loopPlayer = player;
	self.loopLayer = layer;
	self.loopingPath = path;
	[player play];
}

- (void)loopEnded:(NSNotification *)note {
	if (note.object != self.loopPlayer.currentItem)
		return;
	[self.loopPlayer seekToTime:kCMTimeZero];
	[self.loopPlayer play];
}

- (void)stopLoopingVideo {
	if (!self.loopPlayer)
		return;
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:AVPlayerItemDidPlayToEndTimeNotification object:self.loopPlayer.currentItem];
	[self.loopPlayer pause];
	[self.loopLayer removeFromSuperlayer];
	self.loopLayer = nil;
	self.loopPlayer = nil;
	self.loopingPath = nil;
}

- (void)dealloc {
	[self stopLoopingVideo];
}

- (void)resetForReuse {
	[self stopLoopingVideo];
	self.icon.hidden = YES;
	self.subtitle.hidden = YES;
	self.sender.hidden = YES;
	self.senderAvatar.hidden = YES;
	self.tail.hidden = YES;
	self.checkbox.hidden = YES;
	self.disc.hidden = YES;
	self.artwork.hidden = YES;
	self.artwork.image = nil;
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

	self.collageView.hidden = YES;
	self.collageMoreLabel.hidden = YES;
	for (UIImageView *v in self.collageViews) {
		v.hidden = YES;
		v.image = nil;
	}
	self.onCollageItemTapped = nil;
	self.onLinkTapped = nil;
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	self.bubble.layer.borderWidth = [theme bubbleBorderWidth];
	self.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	self.body.font = TGFontAtSize(theme.messageFontSize);
	self.body.textColor = [theme primaryTextColour];
	[self.contactCallButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[self.contactAddButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
}

@end
