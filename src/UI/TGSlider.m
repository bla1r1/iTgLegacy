#import "TGSlider.h"
#import "TGTheme.h"
#import "TGStyle.h"

@implementation TGSlider

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
	UIImage *minTrack = [TGTheme skeuomorphicSliderTrackImageFilled:YES];
	UIImage *maxTrack = [TGTheme skeuomorphicSliderTrackImageFilled:NO];
	UIImage *thumb = [TGTheme skeuomorphicSliderThumbWithRadius:TGHalf(TGMetricSliderThumbD)];

	[self setMinimumTrackImage:minTrack forState:UIControlStateNormal];
	[self setMaximumTrackImage:maxTrack forState:UIControlStateNormal];
	[self setThumbImage:thumb forState:UIControlStateNormal];
	[self setThumbImage:thumb forState:UIControlStateHighlighted];
}

- (void)setLeadingIcon:(UIImage *)leadingIcon {
	_leadingIcon = leadingIcon;
	self.minimumValueImage = leadingIcon;
}

- (void)setTrailingIcon:(UIImage *)trailingIcon {
	_trailingIcon = trailingIcon;
	self.maximumValueImage = trailingIcon;
}

- (CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(size.width > 0 ? size.width : TGMetricRow, TGMetricSliderH);
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(UIViewNoIntrinsicMetric, TGMetricSliderH);
}

@end
