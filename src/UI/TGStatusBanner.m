//
// TGStatusBanner.m - Tactical Status & Connection Banners
// Pinned status strip for connection states, sync progress, and offline alerts.
//
#import "TGStatusBanner.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGStyle.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kBannerH   = TGMetricConnectionBannerH;
static const CGFloat kDotRadius = 3.5f;

@implementation TGStatusBanner {
	UIView *_dotView;
	UILabel *_textLabel;
	UIActivityIndicatorView *_spinner;
}

+ (instancetype)showInView:(UIView *)host
                      kind:(TGStatusBannerKind)kind
                      text:(NSString *)text
                  animated:(BOOL)animated {
	if (!host) return nil;

	TGStatusBanner *existing = nil;
	for (UIView *v in host.subviews) {
		if ([v isKindOfClass:[TGStatusBanner class]]) {
			existing = (TGStatusBanner *)v;
			break;
		}
	}

	if (!existing) {
		CGFloat width = host.bounds.size.width;
		existing = [[self alloc] initWithFrame:CGRectMake(0, 0, width, kBannerH)];
		existing.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
		[host addSubview:existing];

		if (animated) {
			existing.transform = CGAffineTransformMakeTranslation(0, -kBannerH);
			[UIView animateWithDuration:TGAnimationDurationFast animations:^{
				existing.transform = CGAffineTransformIdentity;
			}];
		}
	}

	[existing updateWithKind:kind text:text];
	return existing;
}

+ (void)hideFromView:(UIView *)host animated:(BOOL)animated {
	if (!host) return;
	for (UIView *v in host.subviews) {
		if ([v isKindOfClass:[TGStatusBanner class]]) {
			if (animated) {
				[UIView animateWithDuration:TGAnimationDurationFast animations:^{
					v.transform = CGAffineTransformMakeTranslation(0, -kBannerH);
				} completion:^(BOOL finished) {
					[v removeFromSuperview];
				}];
			} else {
				[v removeFromSuperview];
			}
		}
	}
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.clipsToBounds = YES;
	TGTheme *theme = [TGTheme shared];

	CGFloat width = frame.size.width;
	CGFloat midY = TGCenteredOrigin(kBannerH, TGMetricPad);

	_dotView = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadMedium, midY, TGMetricPad, TGMetricPad)];
	_dotView.layer.cornerRadius = TGHalf(TGMetricPad);
	_dotView.backgroundColor = [theme accentColour];
	[self addSubview:_dotView];

	CGFloat textX = TGMetricPadMedium + TGMetricPad + TGMetricPadSmall;
	_textLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(textX, 0, width - textX - TGMetricPadMedium, kBannerH)];
	_textLabel.font = TGFontMicroStrong();
	_textLabel.textColor = [theme barTitleColour];
	_textLabel.backgroundColor = [UIColor clearColor];
	_textLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:_textLabel];

	// Top specular highlight hairline
	UIView *topHairline = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, TGMetricHairline)];
	topHairline.backgroundColor = [theme skeuoShineColour];
	topHairline.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:topHairline];

	// Bottom dark hairline
	UIView *botHairline = [[UIView alloc] initWithFrame:CGRectMake(0, kBannerH - TGMetricHairline, width, TGMetricHairline)];
	botHairline.backgroundColor = [theme separatorColour];
	botHairline.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	[self addSubview:botHairline];

	return self;
}

- (void)updateWithKind:(TGStatusBannerKind)kind text:(NSString *)text {
	TGTheme *theme = [TGTheme shared];
	_textLabel.text = text ?: @"Connecting...";

	switch (kind) {
		case TGStatusBannerKindConnecting:
		case TGStatusBannerKindUpdating:
			self.backgroundColor = [theme barColour];
			_dotView.backgroundColor = [theme accentColour];
			[self startPulsing];
			break;
		case TGStatusBannerKindOffline:
			self.backgroundColor = [theme inputBarColour];
			_dotView.backgroundColor = [theme secondaryTextColour];
			[self stopPulsing];
			break;
		case TGStatusBannerKindError:
			self.backgroundColor = [theme destructiveColour];
			_dotView.backgroundColor = [UIColor whiteColor];
			[self stopPulsing];
			break;
	}
}

- (void)startPulsing {
	[_dotView.layer removeAllAnimations];
	CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
	pulse.fromValue = @(1.0f);
	pulse.toValue = @(0.25f);
	pulse.duration = 0.6;
	pulse.autoreverses = YES;
	pulse.repeatCount = HUGE_VALF;
	[_dotView.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)stopPulsing {
	[_dotView.layer removeAllAnimations];
	_dotView.alpha = 1.0f;
}

@end
