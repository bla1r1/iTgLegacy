#import "TGButton.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kIconGap = 6.0f;
static const CGFloat kPressOffset = 1.0f;
static const CGFloat kDefaultPadH = 14.0f;

@interface TGButton () {
	UIActivityIndicatorView *_spinner;
	UIImageView *_leftIconView;
	UIImageView *_rightIconView;
}
@end

@implementation TGButton

+ (instancetype)buttonWithTitle:(NSString *)title
                        variant:(TGButtonVariant)variant
                           size:(TGButtonSize)size {
	TGButton *btn = [self buttonWithType:UIButtonTypeCustom];
	[btn setTitle:title forState:UIControlStateNormal];
	[btn setVariant:variant size:size];
	return btn;
}

+ (instancetype)buttonWithTitle:(NSString *)title variant:(TGButtonVariant)variant {
	return [self buttonWithTitle:title variant:variant size:TGButtonSizeMedium];
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_variant = TGButtonVariantPrimary;
		_buttonSize = TGButtonSizeMedium;
		self.adjustsImageWhenHighlighted = NO;
		self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
		self.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

		_leftIconView = [[UIImageView alloc] init];
		_leftIconView.contentMode = UIViewContentModeCenter;
		[self addSubview:_leftIconView];

		_rightIconView = [[UIImageView alloc] init];
		_rightIconView.contentMode = UIViewContentModeCenter;
		[self addSubview:_rightIconView];

		_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
		_spinner.hidesWhenStopped = YES;
		[self addSubview:_spinner];

		[self applyStyling];
	}
	return self;
}

- (void)setVariant:(TGButtonVariant)variant size:(TGButtonSize)size {
	_variant = variant;
	_buttonSize = size;
	[self applyStyling];
	[self setNeedsLayout];
}

- (void)setVariant:(TGButtonVariant)variant {
	[self setVariant:variant size:_buttonSize];
}

- (void)setButtonSize:(TGButtonSize)buttonSize {
	[self setVariant:_variant size:buttonSize];
}

- (CGFloat)resolvedHeight {
	switch (_buttonSize) {
		case TGButtonSizeSmall:
			return TGMetricButtonSmallH;
		case TGButtonSizeMedium:
			return TGMetricButtonMediumH;
		case TGButtonSizeLarge:
			return TGMetricButtonLargeH;
	}
	return TGMetricButtonMediumH;
}

- (UIFont *)resolvedFont {
	switch (_buttonSize) {
		case TGButtonSizeSmall:
			return TGFontCaptionStrong();
		case TGButtonSizeMedium:
			return TGFontRowStrong();
		case TGButtonSizeLarge:
			return TGFontBodyStrong();
	}
	return TGFontRowStrong();
}

- (TGButtonStyle)themeStyleForVariant:(TGButtonVariant)v {
	switch (v) {
		case TGButtonVariantPrimary:
			return TGButtonStyleAction;
		case TGButtonVariantSecondary:
			return TGButtonStyleSilver;
		case TGButtonVariantDestructive:
			return TGButtonStyleDestructive;
		case TGButtonVariantSuccess:
			return TGButtonStyleSuccess;
		case TGButtonVariantGhost:
			return TGButtonStyleGhost;
	}
	return TGButtonStyleAction;
}

- (void)applyStyling {
	CGFloat h = [self resolvedHeight];
	TGButtonStyle style = [self themeStyleForVariant:_variant];

	UIImage *norm = [TGTheme buttonImageForStyle:style highlighted:NO height:h];
	UIImage *high = [TGTheme buttonImageForStyle:style highlighted:YES height:h];
	[self setBackgroundImage:norm forState:UIControlStateNormal];
	[self setBackgroundImage:high forState:UIControlStateHighlighted];

	self.titleLabel.font = [self resolvedFont];

	TGTheme *theme = [TGTheme shared];
	if (_variant == TGButtonVariantSecondary || _variant == TGButtonVariantGhost) {
		[self setTitleColor:[theme primaryTextColour] forState:UIControlStateNormal];
		[self setTitleShadowColor:[theme etchedTextShadowColour] forState:UIControlStateNormal];
		self.titleLabel.shadowOffset = CGSizeMake(0, 1.0f);
		_spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
	} else {
		[self setTitleColor:[theme onAccentColour] forState:UIControlStateNormal];
		[self setTitleShadowColor:[theme navBarTextShadowColour] forState:UIControlStateNormal];
		self.titleLabel.shadowOffset = CGSizeMake(0, -1.0f);
		_spinner.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhite;
	}
}

- (void)setLeftIcon:(UIImage *)leftIcon {
	_leftIcon = leftIcon;
	_leftIconView.image = leftIcon;
	[self setNeedsLayout];
}

- (void)setRightIcon:(UIImage *)rightIcon {
	_rightIcon = rightIcon;
	_rightIconView.image = rightIcon;
	[self setNeedsLayout];
}

- (void)setBusy:(BOOL)busy {
	if (_busy == busy) return;
	_busy = busy;
	self.userInteractionEnabled = !busy;

	if (busy) {
		[_spinner startAnimating];
		self.titleLabel.alpha = 0.0f;
		_leftIconView.alpha = 0.0f;
		_rightIconView.alpha = 0.0f;
	} else {
		[_spinner stopAnimating];
		self.titleLabel.alpha = 1.0f;
		_leftIconView.alpha = 1.0f;
		_rightIconView.alpha = 1.0f;
	}
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	[self setNeedsLayout];
}

- (CGSize)sizeThatFits:(CGSize)size {
	CGFloat h = [self resolvedHeight];
	CGSize textSize = [self.titleLabel sizeThatFits:CGSizeMake(size.width, h)];
	CGFloat totalW = textSize.width + kDefaultPadH * 2.0f;

	if (_leftIcon) {
		totalW += _leftIcon.size.width + kIconGap;
	}
	if (_rightIcon) {
		totalW += _rightIcon.size.width + kIconGap;
	}
	return CGSizeMake(totalW, h);
}

- (CGSize)intrinsicContentSize {
	return [self sizeThatFits:CGSizeMake(CGFLOAT_MAX, [self resolvedHeight])];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGRect b = self.bounds;
	CGFloat h = b.size.height;
	CGFloat w = b.size.width;
	CGFloat yOffset = self.isHighlighted ? kPressOffset : 0.0f;

	if (_busy) {
		CGSize spinSize = _spinner.bounds.size;
		CGFloat spinX = TGCenteredOrigin(w, spinSize.width);
		CGFloat spinY = TGCenteredOrigin(h, spinSize.height) + yOffset;
		_spinner.frame = CGRectMake(spinX, spinY, spinSize.width, spinSize.height);
		return;
	}

	CGSize iconLSize = _leftIcon ? _leftIcon.size : CGSizeZero;
	CGSize iconRSize = _rightIcon ? _rightIcon.size : CGSizeZero;
	CGSize textSize = [self.titleLabel sizeThatFits:CGSizeMake(w, h)];

	CGFloat contentW = textSize.width;
	if (_leftIcon) {
		contentW += iconLSize.width + kIconGap;
	}
	if (_rightIcon) {
		contentW += iconRSize.width + kIconGap;
	}

	CGFloat startX = TGCenteredOrigin(w, contentW);
	CGFloat curX = startX;

	if (_leftIcon) {
		CGFloat iconY = TGCenteredOrigin(h, iconLSize.height) + yOffset;
		_leftIconView.frame = CGRectMake(curX, iconY, iconLSize.width, iconLSize.height);
		curX += iconLSize.width + kIconGap;
	} else {
		_leftIconView.frame = CGRectZero;
	}

	CGFloat labelY = TGCenteredOrigin(h, textSize.height) + yOffset;
	self.titleLabel.frame = CGRectMake(curX, labelY, textSize.width, textSize.height);
	curX += textSize.width;

	if (_rightIcon) {
		curX += kIconGap;
		CGFloat iconY = TGCenteredOrigin(h, iconRSize.height) + yOffset;
		_rightIconView.frame = CGRectMake(curX, iconY, iconRSize.width, iconRSize.height);
	} else {
		_rightIconView.frame = CGRectZero;
	}
}

@end
