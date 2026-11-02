#import "TGRecordBar.h"
#import "TGIcons.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kRecordClockX = 32.0f;
static const CGFloat kRecordClockW = 62.0f;
static const CGFloat kRecordCancelW = 100.0f;
static const CGFloat kRecordCancelH = 32.0f;

@interface TGRecordBar ()
@property (nonatomic, strong) UIView *dot;
@property (nonatomic, strong) UILabel *clock;
@property (nonatomic, strong, readwrite) UIButton *cancelButton;
@property (nonatomic, strong, readwrite) UIButton *sendButton;
@property (nonatomic, strong, readwrite) UIButton *pauseButton;
@end

@implementation TGRecordBar

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])){
		TGTheme *theme = [TGTheme shared];
		CGFloat width = frame.size.width;
		CGFloat height = TGMetricInputBarHeight;
		self.backgroundColor = [theme inputBarColour];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
				UIViewAutoresizingFlexibleTopMargin;

		// The composer's own strip, since this takes the composer's place.
		UIImageView *background = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, 0, width, height)];
		background.image = [TGTheme skeuomorphicInputBarImageWithHeight:height];
		background.autoresizingMask = UIViewAutoresizingFlexibleWidth |
				UIViewAutoresizingFlexibleHeight;
		[self addSubview:background];

		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width,
				TGMetricBorderWidth)];
		hair.backgroundColor = [theme separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self addSubview:hair];

		self.dot = [[UIView alloc] initWithFrame:
				CGRectMake(TGMetricPadLarge, TGCenteredOrigin(height, TGMetricRecordDotSide),
						TGMetricRecordDotSide, TGMetricRecordDotSide)];
		self.dot.backgroundColor = [theme destructiveColour];
		self.dot.layer.cornerRadius = TGHalf(TGMetricRecordDotSide);
		[self addSubview:self.dot];

		self.clock = [[UILabel alloc] initWithFrame:
				CGRectMake(kRecordClockX, TGCenteredOrigin(height, TGMetricLineRow),
						kRecordClockW, TGMetricLineRow)];
		self.clock.font = TGFontRow();
		self.clock.textColor = [theme primaryTextColour];
		self.clock.backgroundColor = [UIColor clearColor];
		[self addSubview:self.clock];

		self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.cancelButton.frame = CGRectMake(TGCenteredOrigin(width, kRecordCancelW),
				TGCenteredOrigin(height, kRecordCancelH), kRecordCancelW, kRecordCancelH);
		[self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
		[self.cancelButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
		self.cancelButton.titleLabel.font = TGFontRow();
		[self addSubview:self.cancelButton];

		self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.sendButton.frame = CGRectMake(width - TGMetricRow,
				TGCenteredOrigin(height, TGMetricCallControlSide),
				TGMetricCallControlSide, TGMetricCallControlSide);
		self.sendButton.backgroundColor = [theme accentColour];
		self.sendButton.layer.cornerRadius = TGHalf(TGMetricCallControlSide);
		self.sendButton.layer.masksToBounds = YES;
		[self.sendButton setImage:[TGIcons sendOnAccent] forState:UIControlStateNormal];
		self.sendButton.tintColor = [theme onAccentColour];
		self.sendButton.imageEdgeInsets = UIEdgeInsetsZero;
		self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self addSubview:self.sendButton];

		self.pauseButton = [TGRecordBar discOfSide:TGMetricCallControlSide];
		self.pauseButton.frame = CGRectMake(
				width - TGMetricRow - TGMetricCallControlSide - TGMetricPad,
				TGCenteredOrigin(height, TGMetricCallControlSide),
				TGMetricCallControlSide, TGMetricCallControlSide);
		[self.pauseButton setImage:[TGIcons pause] forState:UIControlStateNormal];
		self.pauseButton.tintColor = [theme primaryTextColour];
		self.pauseButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self addSubview:self.pauseButton];

		[self showSeconds:0 paused:NO];
	}
	return self;
}

- (void)showSeconds:(NSTimeInterval)seconds paused:(BOOL)paused {
	self.clock.text = [NSString stringWithFormat:@"%ld:%02ld,%ld",
			(long)(seconds / 60), (long)((NSInteger)seconds % 60),
			(long)((NSInteger)(seconds * 10) % 10)];
	self.dot.alpha = paused ? TGAlphaRingTrack
			: (((NSInteger)(seconds * 2) % 2 == 0) ? TGAlphaOpaque : TGAlphaRingTrack);
}

+ (UIButton *)discOfSide:(CGFloat)side {
	TGTheme *theme = [TGTheme shared];
	UIButton *disc = [UIButton buttonWithType:UIButtonTypeCustom];
	disc.frame = CGRectMake(0, 0, side, side);
	disc.backgroundColor = [theme inputBarColour];
	disc.layer.borderWidth = TGMetricHairline;
	disc.layer.borderColor = [theme separatorColour].CGColor;
	disc.layer.cornerRadius = TGHalf(side);
	return disc;
}

+ (UIButton *)onceButton {
	UIButton *once = [self discOfSide:TGMetricRow];
	once.titleLabel.font = TGFontCaptionStrong();
	[once setTitle:@"1" forState:UIControlStateNormal];
	once.accessibilityLabel = @"View once";
	[self setOnce:NO onButton:once];
	return once;
}

+ (void)setOnce:(BOOL)on onButton:(UIButton *)button {
	TGTheme *theme = [TGTheme shared];
	[button setTitleColor:on ? [theme onAccentColour] : [theme accentColour]
				 forState:UIControlStateNormal];
	button.backgroundColor = on ? [theme accentColour] : [theme inputBarColour];
}

@end
