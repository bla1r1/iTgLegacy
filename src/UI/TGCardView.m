#import "TGCardView.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kHeaderHeight = 38.0f;
static const CGFloat kCardIconSide = 22.0f;
static const CGFloat kHighlightBorderW = 1.0f;

@interface TGCardView () {
	UIView *_headerBar;
	UIImageView *_iconView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIView *_dividerView;
	UITapGestureRecognizer *_tapGesture;
}
@end

@implementation TGCardView

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
	self = [super initWithFrame:CGRectZero];
	if (self) {
		_title = [title copy];
		_subtitle = [subtitle copy];
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		[self commonInit];
	}
	return self;
}

- (void)commonInit {
	self.layer.cornerRadius = TGMetricCornerCard;
	self.layer.masksToBounds = YES;
	self.layer.borderWidth = kHighlightBorderW;

	_headerBar = [[UIView alloc] init];
	[self addSubview:_headerBar];

	_iconView = [[UIImageView alloc] init];
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	[_headerBar addSubview:_iconView];

	_titleLabel = [[UILabel alloc] init];
	_titleLabel.font = TGFontRowStrong();
	[_headerBar addSubview:_titleLabel];

	_subtitleLabel = [[UILabel alloc] init];
	_subtitleLabel.font = TGFontCaption();
	[_headerBar addSubview:_subtitleLabel];

	_dividerView = [[UIView alloc] init];
	[self addSubview:_dividerView];

	_contentContainer = [[UIView alloc] init];
	[self addSubview:_contentContainer];

	_titleLabel.text = _title;
	_subtitleLabel.text = _subtitle;

	[self updateThemeAppearance];
}

- (void)updateThemeAppearance {
	TGTheme *theme = [TGTheme shared];
	self.backgroundColor = theme.cardBackgroundColour;
	self.layer.borderColor = theme.separatorColour.CGColor;
	_dividerView.backgroundColor = theme.separatorColour;

	_titleLabel.textColor = theme.primaryTextColour;
	_subtitleLabel.textColor = theme.secondaryTextColour;
}

- (void)setTitle:(NSString *)title {
	_title = [title copy];
	_titleLabel.text = title;
	[self setNeedsLayout];
}

- (void)setSubtitle:(NSString *)subtitle {
	_subtitle = [subtitle copy];
	_subtitleLabel.text = subtitle;
	[self setNeedsLayout];
}

- (void)setIcon:(UIImage *)icon {
	_icon = icon;
	_iconView.image = icon;
	[self setNeedsLayout];
}

- (void)setInteractive:(BOOL)interactive {
	_interactive = interactive;
	if (interactive) {
		if (!_tapGesture) {
			_tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCardTap:)];
			[self addGestureRecognizer:_tapGesture];
		}
		_tapGesture.enabled = YES;
	} else {
		_tapGesture.enabled = NO;
	}
}

- (void)handleCardTap:(UITapGestureRecognizer *)gesture {
	if (gesture.state == UIGestureRecognizerStateEnded && self.tapHandler) {
		self.tapHandler();
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.bounds;
	CGFloat w = b.size.width;
	CGFloat h = b.size.height;

	BOOL hasHeader = (_title.length > 0 || _subtitle.length > 0 || _icon != nil);
	if (hasHeader) {
		_headerBar.hidden = NO;
		_dividerView.hidden = NO;
		_headerBar.frame = CGRectMake(0, 0, w, kHeaderHeight);
		_dividerView.frame = CGRectMake(0, kHeaderHeight, w, 1.0f);

		CGFloat curX = TGMetricPadMedium;
		if (_icon) {
			CGFloat iconY = TGCenteredOrigin(kHeaderHeight, kCardIconSide);
			_iconView.frame = CGRectMake(curX, iconY, kCardIconSide, kCardIconSide);
			curX += kCardIconSide + TGMetricPadSmall;
		} else {
			_iconView.frame = CGRectZero;
		}

		CGFloat textW = w - curX - TGMetricPadMedium;
		if (_subtitle.length > 0) {
			CGFloat halfH = TGHalf(kHeaderHeight);
			_titleLabel.frame = CGRectMake(curX, TGMetricPadTiny, textW, halfH);
			_subtitleLabel.frame = CGRectMake(curX, halfH, textW, halfH - TGMetricPadTiny);
			_subtitleLabel.hidden = NO;
		} else {
			_titleLabel.frame = CGRectMake(curX, 0, textW, kHeaderHeight);
			_subtitleLabel.frame = CGRectZero;
			_subtitleLabel.hidden = YES;
		}

		_contentContainer.frame = CGRectMake(TGMetricPadMedium, kHeaderHeight + TGMetricPadSmall, w - TGDoubled(TGMetricPadMedium), h - kHeaderHeight - TGMetricPadMedium);
	} else {
		_headerBar.hidden = YES;
		_dividerView.hidden = YES;
		_contentContainer.frame = CGRectMake(TGMetricPadMedium, TGMetricPadMedium, w - TGDoubled(TGMetricPadMedium), h - TGDoubled(TGMetricPadMedium));
	}
}

@end
