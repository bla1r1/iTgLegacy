#import "TGSearchBar.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"

static const CGFloat kCancelButtonWidth = 64.0f;
static const CGFloat kSearchMarginH     = 8.0f;
static const CGFloat kSearchMarginV     = 6.0f;
static const NSTimeInterval kCancelAnimDuration = 0.20;

@interface TGSearchBar () {
	UIImageView *_barBackground;
	UIView *_dividerView;
}
@end

@implementation TGSearchBar

- (instancetype)initWithFrame:(CGRect)frame {
	CGRect initial = frame;
	if (initial.size.height <= 0) {
		initial = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width > 0 ? frame.size.width : TGMetricRow, TGMetricRow);
	}
	self = [super initWithFrame:initial];
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
	TGTheme *theme = [TGTheme shared];

	_barBackground = [[UIImageView alloc] init];
	_barBackground.contentMode = UIViewContentModeScaleToFill;
	[self addSubview:_barBackground];

	_dividerView = [[UIView alloc] init];
	_dividerView.backgroundColor = [theme separatorColour];
	[self addSubview:_dividerView];

	_textField = [[TGTextField alloc] initWithFrame:CGRectZero];
	_textField.placeholder = @"Search";
	_textField.leadingIcon = [TGIcons glyphNamed:@"search" colour:[theme secondaryTextColour] side:TGMetricSearchIconSize];
	_textField.returnKeyType = UIReturnKeySearch;
	_textField.delegate = self;
	[_textField addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
	[self addSubview:_textField];

	_cancelButton = [TGButton buttonWithTitle:@"Cancel" variant:TGButtonVariantSecondary size:TGButtonSizeSmall];
	[_cancelButton addTarget:self action:@selector(cancelTapped:) forControlEvents:UIControlEventTouchUpInside];
	_cancelButton.alpha = 0.0f;
	[self addSubview:_cancelButton];

	[self updateBackgroundTheme];
}

- (void)updateBackgroundTheme {
	TGTheme *theme = [TGTheme shared];
	CGFloat h = self.bounds.size.height > 0 ? self.bounds.size.height : TGMetricRow;
	_barBackground.image = [TGTheme skeuomorphicBarImageWithColor:[theme barColour] height:h];
	_dividerView.backgroundColor = [theme separatorColour];
}

- (NSString *)text {
	return _textField.text ?: @"";
}

- (void)setText:(NSString *)text {
	_textField.text = text;
}

- (NSString *)placeholder {
	return _textField.placeholder;
}

- (void)setPlaceholder:(NSString *)placeholder {
	_textField.placeholder = placeholder;
}

- (void)setEditing:(BOOL)editing {
	[self setEditing:editing animated:NO];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	_editing = editing;

	if (animated) {
		[UIView animateWithDuration:kCancelAnimDuration
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
			self->_cancelButton.alpha = editing ? 1.0f : 0.0f;
			[self setNeedsLayout];
			[self layoutIfNeeded];
		} completion:nil];
	} else {
		_cancelButton.alpha = editing ? 1.0f : 0.0f;
		[self setNeedsLayout];
	}
}

- (void)textChanged:(UITextField *)sender {
	if ([self.delegate respondsToSelector:@selector(searchBar:textDidChange:)]) {
		[self.delegate searchBar:self textDidChange:sender.text];
	}
}

- (void)cancelTapped:(UIButton *)sender {
	_textField.text = @"";
	[_textField resignFirstResponder];
	[self setEditing:NO animated:YES];

	if ([self.delegate respondsToSelector:@selector(searchBarCancelButtonClicked:)]) {
		[self.delegate searchBarCancelButtonClicked:self];
	}
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
	if ([self.delegate respondsToSelector:@selector(searchBarShouldBeginEditing:)]) {
		return [self.delegate searchBarShouldBeginEditing:self];
	}
	return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
	[self setEditing:YES animated:YES];
	if ([self.delegate respondsToSelector:@selector(searchBarTextDidBeginEditing:)]) {
		[self.delegate searchBarTextDidBeginEditing:self];
	}
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	if (textField.text.length == 0) {
		[self setEditing:NO animated:YES];
	}
	if ([self.delegate respondsToSelector:@selector(searchBarTextDidEndEditing:)]) {
		[self.delegate searchBarTextDidEndEditing:self];
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	if ([self.delegate respondsToSelector:@selector(searchBarSearchButtonClicked:)]) {
		[self.delegate searchBarSearchButtonClicked:self];
	}
	return YES;
}

- (CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(size.width > 0 ? size.width : TGMetricRow, TGMetricRow);
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(UIViewNoIntrinsicMetric, TGMetricRow);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.bounds;
	CGFloat w = b.size.width;
	CGFloat h = b.size.height;

	_barBackground.frame = CGRectMake(0, 0, w, h);
	_dividerView.frame = CGRectMake(0, h - 1.0f, w, 1.0f);

	CGFloat fieldH = TGMetricTextFieldH;
	CGFloat fieldY = TGCenteredOrigin(h, fieldH);

	if (_editing) {
		CGFloat fieldW = w - kSearchMarginH - kCancelButtonWidth - TGMetricPadSmall - kSearchMarginH;
		_textField.frame = CGRectMake(kSearchMarginH, fieldY, fieldW, fieldH);

		CGFloat cancelX = w - kCancelButtonWidth - kSearchMarginH;
		CGFloat cancelY = TGCenteredOrigin(h, TGMetricButtonSmallH);
		_cancelButton.frame = CGRectMake(cancelX, cancelY, kCancelButtonWidth, TGMetricButtonSmallH);
	} else {
		CGFloat fieldW = w - TGDoubled(kSearchMarginH);
		_textField.frame = CGRectMake(kSearchMarginH, fieldY, fieldW, fieldH);
		_cancelButton.frame = CGRectMake(w, TGCenteredOrigin(h, TGMetricButtonSmallH), kCancelButtonWidth, TGMetricButtonSmallH);
	}
}

@end
