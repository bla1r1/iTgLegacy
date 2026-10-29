#import "TGSwitch.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kThumbInsetX = 2.0f;
static const NSTimeInterval kSwitchAnimDuration = 0.20;

@interface TGSwitch () {
	UIImageView *_trackView;
	UIImageView *_thumbView;
	UIPanGestureRecognizer *_panGesture;
	UITapGestureRecognizer *_tapGesture;
	CGFloat _dragStartThumbX;
	BOOL _isDragging;
}
@end

@implementation TGSwitch

- (instancetype)initWithFrame:(CGRect)frame {
	CGRect initialFrame = frame;
	if (initialFrame.size.width <= 0 || initialFrame.size.height <= 0) {
		initialFrame = CGRectMake(frame.origin.x, frame.origin.y, TGMetricSwitchW, TGMetricSwitchH);
	}
	self = [super initWithFrame:initialFrame];
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
	_on = NO;
	self.backgroundColor = [UIColor clearColor];
	self.accessibilityTraits = UIAccessibilityTraitButton;

	_trackView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, TGMetricSwitchW, TGMetricSwitchH)];
	_trackView.userInteractionEnabled = NO;
	[self addSubview:_trackView];

	CGFloat thumbY = TGCenteredOrigin(TGMetricSwitchH, TGMetricSwitchThumbD);
	_thumbView = [[UIImageView alloc] initWithFrame:CGRectMake(kThumbInsetX, thumbY, TGMetricSwitchThumbD, TGMetricSwitchThumbD)];
	_thumbView.image = [TGTheme skeuomorphicSwitchThumbImage];
	_thumbView.userInteractionEnabled = NO;
	[self addSubview:_thumbView];

	[self updateTrackImageAnimated:NO];

	_tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
	[self addGestureRecognizer:_tapGesture];

	_panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
	[self addGestureRecognizer:_panGesture];
}

- (CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(TGMetricSwitchW, TGMetricSwitchH);
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(TGMetricSwitchW, TGMetricSwitchH);
}

- (CGFloat)maxThumbX {
	return TGMetricSwitchW - TGMetricSwitchThumbD - kThumbInsetX;
}

- (void)updateTrackImageAnimated:(BOOL)animated {
	UIImage *track = [TGTheme skeuomorphicSwitchTrackImageOn:_on];
	if (animated) {
		[UIView transitionWithView:_trackView
                          duration:kSwitchAnimDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
			self->_trackView.image = track;
		} completion:nil];
	} else {
		_trackView.image = track;
	}
}

- (void)setOn:(BOOL)on {
	[self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
	_on = on;
	[self updateTrackImageAnimated:animated];

	CGFloat targetX = _on ? [self maxThumbX] : kThumbInsetX;
	CGFloat thumbY = TGCenteredOrigin(TGMetricSwitchH, TGMetricSwitchThumbD);

	if (animated) {
		[UIView animateWithDuration:kSwitchAnimDuration
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
			self->_thumbView.frame = CGRectMake(targetX, thumbY, TGMetricSwitchThumbD, TGMetricSwitchThumbD);
		} completion:nil];
	} else {
		_thumbView.frame = CGRectMake(targetX, thumbY, TGMetricSwitchThumbD, TGMetricSwitchThumbD);
	}
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
	if (gesture.state == UIGestureRecognizerStateEnded) {
		[self setOn:!_on animated:YES];
		[self sendActionsForControlEvents:UIControlEventValueChanged];
	}
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
	CGFloat thumbY = TGCenteredOrigin(TGMetricSwitchH, TGMetricSwitchThumbD);
	CGFloat maxX = [self maxThumbX];

	if (gesture.state == UIGestureRecognizerStateBegan) {
		_isDragging = YES;
		_dragStartThumbX = _thumbView.frame.origin.x;
	} else if (gesture.state == UIGestureRecognizerStateChanged) {
		CGPoint translation = [gesture translationInView:self];
		CGFloat newX = _dragStartThumbX + translation.x;
		if (newX < kThumbInsetX) newX = kThumbInsetX;
		if (newX > maxX) newX = maxX;
		_thumbView.frame = CGRectMake(newX, thumbY, TGMetricSwitchThumbD, TGMetricSwitchThumbD);

		BOOL shouldBeOn = (newX >= TGHalf(maxX + kThumbInsetX));
		if (shouldBeOn != _on) {
			_on = shouldBeOn;
			[self updateTrackImageAnimated:YES];
		}
	} else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
		_isDragging = NO;
		CGFloat curX = _thumbView.frame.origin.x;
		BOOL finalOn = (curX >= TGHalf(maxX + kThumbInsetX));
		BOOL changed = (finalOn != _on);
		[self setOn:finalOn animated:YES];
		if (changed) {
			[self sendActionsForControlEvents:UIControlEventValueChanged];
		}
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_trackView.frame = CGRectMake(0, 0, TGMetricSwitchW, TGMetricSwitchH);
	if (!_isDragging) {
		CGFloat thumbX = _on ? [self maxThumbX] : kThumbInsetX;
		CGFloat thumbY = TGCenteredOrigin(TGMetricSwitchH, TGMetricSwitchThumbD);
		_thumbView.frame = CGRectMake(thumbX, thumbY, TGMetricSwitchThumbD, TGMetricSwitchThumbD);
	}
}

@end
