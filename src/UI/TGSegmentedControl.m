#import "TGSegmentedControl.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const NSTimeInterval kSegmentAnimDuration = 0.20;

@interface TGSegmentedControl () {
	UIImageView *_trackImageView;
	UIImageView *_indicatorImageView;
	NSMutableArray<UILabel *> *_labels;
	NSMutableArray<UIView *> *_dividers;
}
@end

@implementation TGSegmentedControl

- (instancetype)initWithItems:(NSArray *)items {
	self = [super initWithFrame:CGRectMake(0, 0, TGMetricRow, TGMetricSegmentedHeight)];
	if (self) {
		_labels = [NSMutableArray array];
		_dividers = [NSMutableArray array];
		_selectedSegmentIndex = 0;
		self.backgroundColor = [UIColor clearColor];

		_trackImageView = [[UIImageView alloc] init];
		_trackImageView.userInteractionEnabled = NO;
		[self addSubview:_trackImageView];

		_indicatorImageView = [[UIImageView alloc] init];
		_indicatorImageView.userInteractionEnabled = NO;
		[self addSubview:_indicatorImageView];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
		[self addGestureRecognizer:tap];

		[self setItems:items];
		[self updateThemeAppearance];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	return [self initWithItems:@[@"First", @"Second"]];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		_labels = [NSMutableArray array];
		_dividers = [NSMutableArray array];
		_selectedSegmentIndex = 0;
		[self updateThemeAppearance];
	}
	return self;
}

- (void)updateThemeAppearance {
	_trackImageView.image = [TGTheme buttonImageForStyle:TGButtonStyleSilver highlighted:NO height:TGMetricSegmentedHeight];
	_indicatorImageView.image = [TGTheme buttonImageForStyle:TGButtonStyleAction highlighted:NO height:TGMetricSegmentedHeight];
	[self updateLabelColors];
}

- (void)setItems:(NSArray *)items {
	_items = [items copy];

	for (UILabel *lbl in _labels) {
		[lbl removeFromSuperview];
	}
	[_labels removeAllObjects];

	for (UIView *div in _dividers) {
		[div removeFromSuperview];
	}
	[_dividers removeAllObjects];

	NSUInteger count = _items.count;
	for (NSUInteger i = 0; i < count; i++) {
		UILabel *lbl = [[UILabel alloc] init];
		lbl.font = TGFontCaptionStrong();
		lbl.textAlignment = NSTextAlignmentCenter;
		lbl.text = [_items[i] description];
		[self addSubview:lbl];
		[_labels addObject:lbl];

		if (i > 0) {
			UIView *div = [[UIView alloc] init];
			div.backgroundColor = [TGTheme shared].separatorColour;
			[self addSubview:div];
			[_dividers addObject:div];
		}
	}

	if (_selectedSegmentIndex >= (NSInteger)count) {
		_selectedSegmentIndex = count > 0 ? (NSInteger)count - 1 : 0;
	}

	[self updateLabelColors];
	[self setNeedsLayout];
}

- (void)setSelectedSegmentIndex:(NSInteger)selectedSegmentIndex {
	[self setSelectedSegmentIndex:selectedSegmentIndex animated:NO];
}

- (void)setSelectedSegmentIndex:(NSInteger)selectedSegmentIndex animated:(BOOL)animated {
	if (selectedSegmentIndex < 0 || selectedSegmentIndex >= (NSInteger)_items.count) {
		return;
	}
	_selectedSegmentIndex = selectedSegmentIndex;
	[self updateLabelColors];

	if (animated) {
		[UIView animateWithDuration:kSegmentAnimDuration
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
			[self layoutIndicatorAndDividers];
		} completion:nil];
	} else {
		[self layoutIndicatorAndDividers];
	}
}

- (void)setTitle:(NSString *)title forSegmentAtIndex:(NSUInteger)segment {
	if (segment < _labels.count) {
		_labels[segment].text = title;
	}
}

- (NSString *)titleForSegmentAtIndex:(NSUInteger)segment {
	if (segment < _labels.count) {
		return _labels[segment].text;
	}
	return nil;
}

- (void)updateLabelColors {
	TGTheme *theme = [TGTheme shared];
	NSUInteger count = _labels.count;
	for (NSUInteger i = 0; i < count; i++) {
		UILabel *lbl = _labels[i];
		if ((NSInteger)i == _selectedSegmentIndex) {
			lbl.textColor = [theme onAccentColour];
			lbl.shadowColor = [theme navBarTextShadowColour];
			lbl.shadowOffset = CGSizeMake(0, -1.0f);
		} else {
			lbl.textColor = [theme primaryTextColour];
			lbl.shadowColor = [theme etchedTextShadowColour];
			lbl.shadowOffset = CGSizeMake(0, 1.0f);
		}
	}
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
	CGPoint pt = [gesture locationInView:self];
	NSUInteger count = _items.count;
	if (count == 0) return;

	CGFloat segW = self.bounds.size.width / (CGFloat)count;
	NSInteger tappedIdx = (NSInteger)(pt.x / segW);
	if (tappedIdx >= 0 && tappedIdx < (NSInteger)count && tappedIdx != _selectedSegmentIndex) {
		[self setSelectedSegmentIndex:tappedIdx animated:YES];
		[self sendActionsForControlEvents:UIControlEventValueChanged];
	}
}

- (CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(size.width > 0 ? size.width : TGMetricRow, TGMetricSegmentedHeight);
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(UIViewNoIntrinsicMetric, TGMetricSegmentedHeight);
}

- (void)layoutIndicatorAndDividers {
	NSUInteger count = _items.count;
	if (count == 0) return;

	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;
	CGFloat segW = w / (CGFloat)count;

	CGFloat indX = (CGFloat)_selectedSegmentIndex * segW;
	_indicatorImageView.frame = CGRectMake(indX, 0, segW, h);

	for (NSUInteger i = 0; i < _dividers.count; i++) {
		UIView *div = _dividers[i];
		CGFloat divX = (CGFloat)(i + 1) * segW;
		div.frame = CGRectMake(divX, 0, 1.0f, h);
		// Hide divider adjacent to active segment
		BOOL nearActive = ((NSInteger)i == _selectedSegmentIndex - 1 || (NSInteger)i == _selectedSegmentIndex);
		div.alpha = nearActive ? 0.0f : 1.0f;
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;
	_trackImageView.frame = CGRectMake(0, 0, w, h);

	NSUInteger count = _items.count;
	if (count == 0) return;

	CGFloat segW = w / (CGFloat)count;
	for (NSUInteger i = 0; i < count; i++) {
		_labels[i].frame = CGRectMake((CGFloat)i * segW, 0, segW, h);
	}

	[self layoutIndicatorAndDividers];
}

@end
