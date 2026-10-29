//
// TGEmptyView.m - Tactile Empty State Presentation
// Centered vector iconography, embossed typography, and action buttons.
//
#import "TGEmptyView.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kEmptyIconSide = TGMetricEmptyIconSide;
static const CGFloat kEmptyBtnH     = TGMetricButtonHeightSmall;
static const CGFloat kEmptyBtnW     = 160.0f;

@implementation TGEmptyView

+ (instancetype)emptyViewWithFrame:(CGRect)frame
                             image:(UIImage *)image
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle
                       buttonTitle:(NSString *)buttonTitle
                            target:(id)target
                            action:(SEL)action {
	TGEmptyView *view = [[self alloc] initWithFrame:frame];
	[view configureWithImage:image
	                   title:title
	                subtitle:subtitle
	             buttonTitle:buttonTitle
	                  target:target
	                  action:action];
	return view;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.backgroundColor = [UIColor clearColor];
	self.userInteractionEnabled = YES;

	return self;
}

- (void)configureWithImage:(UIImage *)image
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               buttonTitle:(NSString *)buttonTitle
                    target:(id)target
                    action:(SEL)action {
	// Remove previous subviews if any
	for (UIView *v in self.subviews) {
		[v removeFromSuperview];
	}

	TGTheme *theme = [TGTheme shared];
	CGFloat width = self.bounds.size.width;
	CGFloat height = self.bounds.size.height;

	CGFloat contentHeight = kEmptyIconSide + TGMetricPadLarge + TGMetricLineTitle + TGMetricPad + TGMetricLineBody * 2;
	if (buttonTitle.length) {
		contentHeight += TGMetricPadLarge + kEmptyBtnH;
	}

	CGFloat startY = TGCenteredOrigin(height, contentHeight);
	if (startY < TGMetricPadWide) startY = TGMetricPadWide;

	// Icon
	CGFloat iconX = TGCenteredOrigin(width, kEmptyIconSide);
	_iconView = [[UIImageView alloc] initWithFrame:CGRectMake(iconX, startY, kEmptyIconSide, kEmptyIconSide)];
	_iconView.image = image;
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.tintColor = [theme secondaryTextColour];
	_iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[self addSubview:_iconView];

	CGFloat y = startY + kEmptyIconSide + TGMetricPadLarge;

	// Title
	_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadWide, y, width - TGDoubled(TGMetricPadWide), TGMetricLineTitle)];
	_titleLabel.font = TGFontTitle();
	_titleLabel.textColor = [theme primaryTextColour];
	_titleLabel.textAlignment = NSTextAlignmentCenter;
	_titleLabel.text = title;
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:_titleLabel];

	y += TGMetricLineTitle + TGMetricPad;

	// Subtitle
	CGFloat subH = TGMetricLineBody * 2;
	_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadWide, y, width - TGDoubled(TGMetricPadWide), subH)];
	_subtitleLabel.font = TGFontBody();
	_subtitleLabel.textColor = [theme secondaryTextColour];
	_subtitleLabel.textAlignment = NSTextAlignmentCenter;
	_subtitleLabel.numberOfLines = 0;
	_subtitleLabel.text = subtitle;
	_subtitleLabel.backgroundColor = [UIColor clearColor];
	_subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:_subtitleLabel];

	y += subH + TGMetricPadLarge;

	// Optional Action Button
	if (buttonTitle.length) {
		CGFloat btnX = TGCenteredOrigin(width, kEmptyBtnW);
		_actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
		_actionButton.frame = CGRectMake(btnX, y, kEmptyBtnW, kEmptyBtnH);
		_actionButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		[_actionButton setTitle:buttonTitle forState:UIControlStateNormal];
		[TGTheme applySkeuomorphicStyleToButton:_actionButton style:TGButtonStyleAction];
		if (target && action) {
			[_actionButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
		}
		[self addSubview:_actionButton];
	}
}

@end
