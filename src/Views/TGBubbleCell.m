//
// TGBubbleCell.m - Table view cell for chat bubbles.
//
#import "TGBubbleCell.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <AVFoundation/AVFoundation.h>
#import "TGStyle.h"
#import <CoreText/CoreText.h>

/// How visible the part of a voice note nobody has heard yet is.
static const CGFloat kWaveUnplayedAlpha = TGAlphaHighlight;
/// A sending arc is a thin line just inside the disc, the same weight as the
/// recorder's own progress ring.
static const CGFloat kSendRingLineWidth = 2.0f;
/// Telegram keeps a sliver of the ring visible before any progress arrives, so
/// a send that has not started does not look like a disc with no control.
static const CGFloat kSendRingMinimum = 0.2f;

@interface TGBubbleCell () {
	CTFrameRef _textFrame;          // the laid-out body text, for hit-testing
	CGSize     _textFrameSize;      // the box it was laid out in
	CGSize     _waveSize;           // the box the bars were laid out in
	// Parked views, their superviews and indices, in the order they left.
	// Strong: a few (the reactions label, poll rows) are held by nothing else.
	NSMutableArray *_parkedViews;
	NSMutableArray *_parkedParents;
	NSUInteger _parkedIndex[64];
}
@property (nonatomic, strong) NSAttributedString *textFrameString;
@property (nonatomic, strong) CAShapeLayer *waveUnplayedLayer;
@property (nonatomic, strong) CALayer *wavePlayedClip;
@property (nonatomic, strong) CAShapeLayer *wavePlayedLayer;
@property (nonatomic, strong) NSData *waveformPathData;
@property (nonatomic, strong) CAShapeLayer *sendRing;
@property (nonatomic, strong) AVPlayer *loopPlayer;
@property (nonatomic, strong) AVPlayerLayer *loopLayer;
@property (nonatomic, copy) NSString *loopingPath;
@end

@implementation TGBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;

	TGTheme *theme = [TGTheme shared];
	self.bubble = [[UIView alloc] init];
	self.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	self.bubble.layer.borderWidth = 0;
	self.bubble.layer.borderColor = [UIColor clearColor].CGColor;
	// Not clipped and not rasterized. Rounded corners with a clip cost an
	// offscreen pass per frame, and a rasterized bubble is re-rendered into
	// a fresh texture on every reuse, which is every 40 pt of scrolling.
	// cornerRadius alone still rounds the background colour, for free.
	[self.contentView addSubview:self.bubble];

	self.bubbleBack = [[UIImageView alloc] init];
	self.bubbleBack.hidden = YES;
	[self.bubble addSubview:self.bubbleBack];

	self.picture = [[UIImageView alloc] init];
	self.picture.contentMode = UIViewContentModeScaleAspectFill;
	// Pictures arrive pre-cropped and pre-rounded (TGIcons roundedImage:);
	// cornerRadius here only shapes the placeholder fill, which costs nothing.
	self.picture.layer.borderColor = [theme separatorColour].CGColor;
	self.picture.layer.borderWidth = 1.0f;
	self.picture.layer.cornerRadius = TGMetricCornerSmall;
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
	self.senderAvatar.hidden = YES;
	[self.contentView addSubview:self.senderAvatar];

	self.ticks = [[UIImageView alloc] init];
	self.ticks.hidden = YES;
	[self.bubble addSubview:self.ticks];

	self.shineBar = [[UIView alloc] init];
	self.shineBar.userInteractionEnabled = NO;
	self.shineBar.hidden = YES;
	self.shineGradientLayer = [CAGradientLayer layer];
	self.shineGradientLayer.colors = [theme skeuoShineGradientColours];
	[self.shineBar.layer addSublayer:self.shineGradientLayer];
	[self.bubble addSubview:self.shineBar];

	self.unreadDot = [[UIView alloc] init];
	self.unreadDot.hidden = YES;
	self.unreadDot.backgroundColor = [[TGTheme shared] accentColour];
	[self.contentView addSubview:self.unreadDot];

	self.checkbox = [[UIImageView alloc] init];
	self.checkbox.hidden = YES;
	self.checkbox.contentMode = UIViewContentModeCenter;
	[self.contentView addSubview:self.checkbox];

	self.quoteBar = [[UIView alloc] init];
	self.quoteBar.hidden = YES;
	self.quoteBar.userInteractionEnabled = YES;
	[self.bubble addSubview:self.quoteBar];

	self.quoteAuthor = [[UILabel alloc] init];
	self.quoteAuthor.font = TGFontCaptionStrong();
	self.quoteAuthor.backgroundColor = [UIColor clearColor];
	self.quoteAuthor.hidden = YES;
	// The label with interaction off swallows nothing, so both halves of the
	// quote are a hit target: the head the same as the text under it.
	self.quoteAuthor.userInteractionEnabled = YES;
	[self.bubble addSubview:self.quoteAuthor];

	self.quote = [[UILabel alloc] init];
	self.quote.font = TGFontCaption();
	self.quote.numberOfLines = 2;
	self.quote.backgroundColor = [UIColor clearColor];
	self.quote.hidden = YES;
	self.quote.userInteractionEnabled = YES;
	[self.bubble addSubview:self.quote];

	// Following a reply: the quote header is the button, the way their client
	// treats it. One recognizer per half, both aimed at the same callback.
	for (UILabel *label in @[self.quoteAuthor, self.quote]){
		UITapGestureRecognizer *quoteTap = [[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(quoteTapped:)];
		[label addGestureRecognizer:quoteTap];
	}

	self.icon = [[UILabel alloc] init];
	self.icon.textAlignment = NSTextAlignmentCenter;
	self.icon.textColor = [[TGTheme shared] onAccentColour];
	self.icon.font = TGFontHeader();
	// Unclipped: the rounded corners are its background colour's, and the
	// glyph never leaves the tile, so a clip would buy an offscreen pass for
	// nothing.
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
	self.mediaStamp.textColor = [[TGTheme shared] onMediaColour];
	self.mediaStamp.textAlignment = NSTextAlignmentCenter;
	self.mediaStamp.layer.cornerRadius = TGMetricCornerControl;
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
		cv.layer.cornerRadius = TGMetricCornerSmall;
		cv.userInteractionEnabled = YES;
		cv.tag = i;
		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(collageItemTapped:)];
		[cv addGestureRecognizer:tap];
		[self.collageViews addObject:cv];
		[self.collageView addSubview:cv];
	}
	self.collageMoreLabel = [[UILabel alloc] init];
	self.collageMoreLabel.textAlignment = NSTextAlignmentCenter;
	self.collageMoreLabel.textColor = [[TGTheme shared] onMediaColour];
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

/// The frame CoreText laid the label's text out in, kept until the text or
/// the box changes. A tap used to stand up an NSTextStorage, an
/// NSLayoutManager and an NSTextContainer - the whole TextKit stack - only to
/// ask which character was under a finger, and then throw all three away
/// again; on a 4S that is milliseconds of work per touch, and two touches
/// inside the same bubble did it twice.
- (CTFrameRef)layoutFrameForLabel:(UILabel *)label {
	NSAttributedString *attr = label.attributedText;
	CGSize box = label.bounds.size;
	if (_textFrame && _textFrameString == attr &&
			CGSizeEqualToSize(_textFrameSize, box))
		return _textFrame;

	if (_textFrame){
		CFRelease(_textFrame);
		_textFrame = NULL;
	}
	_textFrameString = nil;
	_textFrameSize = CGSizeZero;
	if (!attr.length || box.width <= 0 || box.height <= 0)
		return NULL;

	CTFramesetterRef setter = CTFramesetterCreateWithAttributedString(
			(CFAttributedStringRef)attr);
	if (!setter)
		return NULL;
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathAddRect(path, NULL, CGRectMake(0, 0, box.width, box.height));
	_textFrame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
	CGPathRelease(path);
	CFRelease(setter);

	if (_textFrame){
		_textFrameString = attr;
		_textFrameSize = box;
	}
	return _textFrame;
}

/// Which character sits under `point`, or NSNotFound when the point is past
/// the end of its line. CoreText answers this directly from the line it
/// already measured: no objects, no allocation, sub-microsecond.
- (NSUInteger)characterIndexAtPoint:(CGPoint)point inLabel:(UILabel *)label {
	CTFrameRef frame = [self layoutFrameForLabel:label];
	if (!frame)
		return NSNotFound;

	CFArrayRef lines = CTFrameGetLines(frame);
	CFIndex count = lines ? CFArrayGetCount(lines) : 0;
	if (count <= 0)
		return NSNotFound;

	// CoreText measures from the bottom left of the box it was given; UIKit
	// hands the touch down from the top left.
	CGFloat height = label.bounds.size.height;
	CGPoint flipped = CGPointMake(point.x, height - point.y);

	CGPoint origins[count];
	CTFrameGetLineOrigins(frame, CFRangeMake(0, count), origins);

	for (CFIndex i = 0; i < count; i++){
		CTLineRef line = (CTLineRef)CFArrayGetValueAtIndex(lines, i);
		CGFloat ascent = 0, descent = 0, leading = 0;
		double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
		CGFloat top = origins[i].y + ascent;
		CGFloat bottom = origins[i].y - descent;
		if (flipped.y > top || flipped.y < bottom)
			continue;
		// Past the last glyph of the line is not on any character: tapping
		// the empty run-off after a link must not open it.
		if (flipped.x < origins[i].x || flipped.x > origins[i].x + width)
			return NSNotFound;

		CFIndex index = CTLineGetStringIndexForPosition(line,
				CGPointMake(flipped.x - origins[i].x, 0));
		if (index == kCFNotFound || index < 0)
			return NSNotFound;
		return (NSUInteger)index;
	}
	return NSNotFound;
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

- (void)quoteTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateEnded) return;
	if (self.onQuoteTapped) self.onQuoteTapped();
}

#pragma mark - voice waveform

- (void)setWaveform:(NSData *)waveform size:(CGSize)size colour:(UIColor *)colour {
	if (!self.waveUnplayedLayer){
		// Two fills of one path. The dim one is the whole waveform; the solid
		// one is the same path inside a layer that clips, and moving that
		// layer's edge is the whole of following playback. Before this the
		// cell asked TGIcons for a fresh bitmap - and built an NSString key
		// for it - five times a second, which is twenty offscreen contexts
		// over a ten-second voice note.
		self.waveUnplayedLayer = [CAShapeLayer layer];
		self.wavePlayedLayer = [CAShapeLayer layer];
		self.wavePlayedClip = [CALayer layer];
		self.wavePlayedClip.masksToBounds = YES;
		// Without this the clip's edge animates itself over a quarter of a
		// second every tick, which reads as the bars smearing.
		self.wavePlayedClip.actions = @{@"bounds"   : [NSNull null],
										@"position" : [NSNull null]};
		[self.wavePlayedClip addSublayer:self.wavePlayedLayer];
		[self.wave.layer addSublayer:self.waveUnplayedLayer];
		[self.wave.layer addSublayer:self.wavePlayedClip];
	}

	BOOL sameBars = (self.waveformPathData == waveform ||
					 [self.waveformPathData isEqualToData:waveform]) &&
					CGSizeEqualToSize(_waveSize, size);
	if (!sameBars){
		UIBezierPath *path = [TGIcons waveformPath:waveform size:size];
		self.waveUnplayedLayer.path = path.CGPath;
		self.wavePlayedLayer.path = path.CGPath;
		self.waveformPathData = waveform;
		_waveSize = size;
		self.waveUnplayedLayer.frame = CGRectMake(0, 0, size.width, size.height);
		self.wavePlayedLayer.frame = self.waveUnplayedLayer.frame;
	}

	self.waveUnplayedLayer.fillColor =
			[colour colorWithAlphaComponent:kWaveUnplayedAlpha].CGColor;
	self.wavePlayedLayer.fillColor = colour.CGColor;
}

- (void)setWavePlayed:(CGFloat)played {
	if (!self.wavePlayedClip)
		return;
	if (played < 0) played = 0;
	if (played > 1) played = 1;
	self.wavePlayedClip.frame = CGRectMake(0, 0, _waveSize.width * played,
										   _waveSize.height);
}

#pragma mark - sending ring

- (void)showSendRingWithProgress:(CGFloat)progress {
	CGRect bounds = self.disc.bounds;
	if (bounds.size.width <= 0 || bounds.size.height <= 0)
		return;

	if (!self.sendRing){
		self.sendRing = [CAShapeLayer layer];
		self.sendRing.fillColor = [UIColor clearColor].CGColor;
		// The media disc's glyph is the theme's over-media white, so the arc
		// reads as the same control rather than a second blue ring.
		self.sendRing.strokeColor = [[TGTheme shared] onMediaColour].CGColor;
		self.sendRing.lineWidth = kSendRingLineWidth;
		self.sendRing.lineCap = kCALineCapRound;
		// Progress lands several times a second. Without this every value
		// would fade in over the default quarter second.
		self.sendRing.actions = @{@"path"      : [NSNull null],
								  @"bounds"    : [NSNull null],
								  @"position"  : [NSNull null],
								  @"strokeEnd" : [NSNull null],
								  @"transform" : [NSNull null]};
		[self.disc.layer addSublayer:self.sendRing];
	}

	if (!CGSizeEqualToSize(self.sendRing.bounds.size, bounds.size)){
		self.sendRing.frame = bounds;
		CGFloat radius = TGHalf(MIN(bounds.size.width, bounds.size.height)) -
				TGHalf(kSendRingLineWidth);
		UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:
				CGPointMake(TGHalf(bounds.size.width), TGHalf(bounds.size.height))
				radius:radius startAngle:(CGFloat)-M_PI_2
				endAngle:(CGFloat)(M_PI + M_PI_2) clockwise:YES];
		self.sendRing.path = circle.CGPath;
	}

	if (progress < kSendRingMinimum)
		progress = kSendRingMinimum;
	if (progress > 1)
		progress = 1;
	self.sendRing.strokeEnd = progress;

	// The render server drops an animation when its layer leaves the tree, so
	// a cell scrolled back in has to ask for the turn again. The disc is
	// already drawn; only the arc moves.
	if (![self.sendRing animationForKey:@"sendSpin"]){
		CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
		spin.fromValue = @(0);
		spin.toValue = @((CGFloat)(M_PI * 2));
		spin.duration = TGAnimationDurationSlow * 4;
		spin.repeatCount = HUGE_VALF;
		spin.timingFunction = [CAMediaTimingFunction functionWithName:
				kCAMediaTimingFunctionLinear];
		[self.sendRing addAnimation:spin forKey:@"sendSpin"];
	}
}

- (void)hideSendRing {
	if (!self.sendRing)
		return;
	[self.sendRing removeFromSuperlayer];
	self.sendRing = nil;
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
	if (_textFrame)
		CFRelease(_textFrame);
}

- (void)parkIn:(UIView *)container {
	NSArray *subs = container.subviews;
	// Last to first, so removing one never shifts an index still to come.
	for (NSInteger i = (NSInteger)subs.count - 1; i >= 0; i--) {
		UIView *v = subs[i];
		if (!v.hidden || _parkedViews.count >= 64)
			continue;
		_parkedIndex[_parkedViews.count] = (NSUInteger)i;
		[_parkedViews addObject:v];
		[_parkedParents addObject:container];
		[v removeFromSuperview];
	}
}

- (void)parkHiddenViews {
	if (!_parkedViews) {
		_parkedViews = [[NSMutableArray alloc] initWithCapacity:48];
		_parkedParents = [[NSMutableArray alloc] initWithCapacity:48];
	}
	[self parkIn:self.bubble];
	[self parkIn:self.contentView];
}

/// Puts the parked views back last-in first-out, so each goes to the index it
/// left from: everything below it is back in place by then.
- (void)unparkViews {
	for (NSInteger i = (NSInteger)_parkedViews.count - 1; i >= 0; i--) {
		UIView *parent = _parkedParents[i];
		NSUInteger at = MIN(_parkedIndex[i], parent.subviews.count);
		[parent insertSubview:_parkedViews[i] atIndex:at];
	}
	[_parkedViews removeAllObjects];
	[_parkedParents removeAllObjects];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self hideSendRing];
}

- (void)resetForReuse {
	[self unparkViews];
	[self stopLoopingVideo];
	[self hideSendRing];
	self.icon.hidden = YES;
	self.subtitle.hidden = YES;
	self.subtitle.text = nil;
	self.sender.hidden = YES;
	self.sender.text = nil;
	self.senderAvatar.hidden = YES;
	self.tail.hidden = YES;
	self.bubble.layer.borderWidth = 0;
	self.bubble.layer.borderColor = [UIColor clearColor].CGColor;
	self.bubble.backgroundColor = [UIColor clearColor];
	self.bubbleBack.hidden = YES;
	self.bubble.clipsToBounds = NO;
	self.shineBar.hidden = YES;
	self.checkbox.hidden = YES;
	self.disc.hidden = YES;
	self.artwork.hidden = YES;
	self.artwork.image = nil;
	self.wave.hidden = YES;
	self.picture.hidden = YES;
	// Also forgets a rounded copy still being drawn for the last message.
	[TGIcons setRoundedImage:nil inView:self.picture size:CGSizeZero radius:0];
	for (UIImageView *cv in self.collageViews)
		[TGIcons setRoundedImage:nil inView:cv size:CGSizeZero radius:0];
	self.body.hidden = YES;
	self.body.text = nil;
	self.body.attributedText = nil;
	self.body.numberOfLines = 0;
	self.body.textAlignment = NSTextAlignmentLeft;
	self.time.text = nil;
	self.ticks.hidden = YES;
	self.ticks.image = nil;
	self.contactCallButton.hidden = YES;
	self.contactAddButton.hidden = YES;
	self.contactSeparatorH.hidden = YES;
	self.contactSeparatorV.hidden = YES;
	self.mediaStamp.hidden = YES;
	self.mediaStamp.text = nil;
	self.unreadDot.hidden = YES;

	// The poll's option rows are five views apiece and were torn down and
	// built again on every single reuse, because clearing pollMessageId here
	// meant the cell's own "same poll, keep them" check could never hold.
	// Hidden instead: the poll branch rebuilds them when the message under
	// the cell actually changes.
	for (UIView *old in self.bubble.subviews) {
		if (old.tag >= 0x9100 && old.tag < 0x9200) old.hidden = YES;
	}

	// A round note moves the clock and the ticks out of the bubble, because a
	// circle clips them away. Every other kind places them in the bubble's
	// own coordinates, so a reused cell has to get them back first.
	if (self.time.superview != self.bubble)
		[self.bubble addSubview:self.time];
	if (self.ticks.superview != self.bubble)
		[self.bubble addSubview:self.ticks];
	if (self.mediaStamp.superview != self.bubble) {
		[self.bubble addSubview:self.mediaStamp];
		self.mediaStamp.layer.cornerRadius = TGMetricCornerControl;
		self.mediaStamp.textColor = [[TGTheme shared] onMediaColour];
	}
	self.quoteBar.hidden = YES;
	self.quote.hidden = YES;
	self.quote.text = nil;
	self.quoteAuthor.hidden = YES;
	self.quoteAuthor.text = nil;
	self.forwardLabel.hidden = YES;
	self.forwardLabel.text = nil;
	self.forwardLabel.attributedText = nil;
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
	self.bubble.layer.borderWidth = 0;
	self.bubble.layer.borderColor = [UIColor clearColor].CGColor;
	self.body.font = TGFontAtSize(theme.messageFontSize);
	self.body.textColor = [theme primaryTextColour];
	[self.contactCallButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[self.contactAddButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
}

@end
