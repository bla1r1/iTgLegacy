#import "TGBadge.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kBadgePadH = 6.0f;

@interface TGBadge () {
	UIImageView *_backgroundView;
	UILabel *_label;
}
@end

@implementation TGBadge

+ (instancetype)badgeWithCount:(NSInteger)count {
	TGBadge *b = [[self alloc] initWithFrame:CGRectZero];
	b.count = count;
	return b;
}

+ (instancetype)badgeWithText:(NSString *)text variant:(TGBadgeVariant)variant {
	TGBadge *b = [[self alloc] initWithFrame:CGRectZero];
	b.variant = variant;
	b.text = text;
	return b;
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
	_variant = TGBadgeVariantNotification;
	self.backgroundColor = [UIColor clearColor];

	_backgroundView = [[UIImageView alloc] init];
	_backgroundView.userInteractionEnabled = NO;
	[self addSubview:_backgroundView];

	_label = [[UILabel alloc] init];
	_label.font = TGFontMicroStrong();
	_label.textAlignment = NSTextAlignmentCenter;
	[self addSubview:_label];

	[self updateAppearance];
}

- (void)setVariant:(TGBadgeVariant)variant {
	_variant = variant;
	[self updateAppearance];
	[self setNeedsLayout];
}

- (void)setText:(NSString *)text {
	_text = [text copy];
	_label.text = text;
	self.hidden = (text.length == 0);
	[self setNeedsLayout];
}

- (void)setCount:(NSInteger)count {
	_count = count;
	if (count <= 0) {
		self.text = nil;
		self.hidden = YES;
	} else if (count > 999) {
		self.text = @"999+";
		self.hidden = NO;
	} else {
		self.text = [NSString stringWithFormat:@"%ld", (long)count];
		self.hidden = NO;
	}
}

- (void)updateAppearance {
	TGTheme *theme = [TGTheme shared];
	TGButtonStyle style = TGButtonStyleDestructive;
	switch (_variant) {
		case TGBadgeVariantNotification:
			style = TGButtonStyleDestructive;
			break;
		case TGBadgeVariantAccent:
			style = TGButtonStyleAction;
			break;
		case TGBadgeVariantMuted:
			style = TGButtonStyleSilver;
			break;
		case TGBadgeVariantSuccess:
			style = TGButtonStyleSuccess;
			break;
	}

	_backgroundView.image = [TGTheme buttonImageForStyle:style highlighted:NO height:TGMetricBadgeH];

	if (_variant == TGBadgeVariantMuted) {
		_label.textColor = theme.primaryTextColour;
		_label.shadowColor = theme.etchedTextShadowColour;
		_label.shadowOffset = CGSizeMake(0, 1.0f);
	} else {
		_label.textColor = theme.onAccentColour;
		_label.shadowColor = theme.navBarTextShadowColour;
		_label.shadowOffset = CGSizeMake(0, -1.0f);
	}
}

- (CGSize)sizeThatFits:(CGSize)size {
	CGSize textSize = [_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, TGMetricBadgeH)];
	CGFloat w = MAX(textSize.width + kBadgePadH * 2.0f, TGMetricBadgeH);
	return CGSizeMake(w, TGMetricBadgeH);
}

- (CGSize)intrinsicContentSize {
	return [self sizeThatFits:CGSizeZero];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.bounds;
	_backgroundView.frame = b;
	_label.frame = b;
}

@end
