#import "TGTextField.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kFieldInsetH = 10.0f;
static const CGFloat kFieldIconPad = 6.0f;
static const CGFloat kIconSide = 18.0f;

@interface TGTextField () {
	UIImageView *_iconImageView;
	UIView *_leftContainerView;
}
@end

@implementation TGTextField

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
	self.font = TGFontInput();
	TGTheme *theme = [TGTheme shared];
	self.textColor = [theme primaryTextColour];
	self.clearButtonMode = UITextFieldViewModeWhileEditing;

	[self updateBackgroundAppearance];
}

- (void)updateBackgroundAppearance {
	CGFloat h = self.bounds.size.height > 0 ? self.bounds.size.height : TGMetricTextFieldH;
	self.background = [TGTheme skeuomorphicWellImageWithHeight:h cornerRadius:TGMetricCornerControl];
}

- (void)setLeadingIcon:(UIImage *)leadingIcon {
	_leadingIcon = leadingIcon;
	if (leadingIcon) {
		if (!_leftContainerView) {
			CGFloat containerW = kIconSide + TGDoubled(kFieldIconPad);
			_leftContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, containerW, TGMetricTextFieldH)];
			_iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(kFieldIconPad, TGCenteredOrigin(TGMetricTextFieldH, kIconSide), kIconSide, kIconSide)];
			_iconImageView.contentMode = UIViewContentModeScaleAspectFit;
			[_leftContainerView addSubview:_iconImageView];
		}
		_iconImageView.image = leadingIcon;
		self.leftView = _leftContainerView;
		self.leftViewMode = UITextFieldViewModeAlways;
	} else {
		self.leftView = nil;
		self.leftViewMode = UITextFieldViewModeNever;
	}
	[self setNeedsLayout];
}

- (void)setHasError:(BOOL)hasError {
	_hasError = hasError;
	if (hasError) {
		self.layer.borderColor = [TGTheme shared].destructiveActionColour.CGColor;
		self.layer.borderWidth = 1.0f;
		self.layer.cornerRadius = TGMetricCornerControl;
	} else {
		self.layer.borderWidth = 0.0f;
	}
}

- (CGRect)textRectForBounds:(CGRect)bounds {
	CGFloat leftPad = self.leftView ? self.leftView.frame.size.width + kFieldIconPad : kFieldInsetH;
	CGFloat rightPad = self.rightView ? self.rightView.frame.size.width + kFieldIconPad : kFieldInsetH;
	return CGRectMake(leftPad, 0, bounds.size.width - leftPad - rightPad, bounds.size.height);
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
	return [self textRectForBounds:bounds];
}

- (CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(size.width, TGMetricTextFieldH);
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(UIViewNoIntrinsicMetric, TGMetricTextFieldH);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self updateBackgroundAppearance];
}

@end
