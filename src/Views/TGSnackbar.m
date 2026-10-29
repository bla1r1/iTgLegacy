#import "TGSnackbar.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

// Their snackbar at 360dp: a 48 tall plate inset 8, a 24 countdown ring at 16
// from the left, the wording at 15, UNDO on the right in blue.
static const CGFloat kBarHeight = TGMetricRow;
static const CGFloat kBarInset  = TGMetricSnackbarInset;
static const CGFloat kRingSide  = TGMetricSnackbarRing;
/// The Undo button at the right end of the bar.
static const CGFloat kUndoWidth = 70.0f;
/// The text column, which starts clear of the ring and stops clear of Undo.
static const CGFloat kTextLeft  = 46.0f;
/// The arrow drawn on the Undo button.
static const CGFloat kUndoGlyph = 18.0f;

static TGSnackbar *sOpenBar = nil;

@implementation TGSnackbar {
	NSTimer *_tick;
	NSInteger _left;
	NSInteger _total;
	void (^_commit)(void);
	UILabel *_count;
	CAShapeLayer *_ring;
}

+ (void)commitNow {
	TGSnackbar *bar = sOpenBar;
	if (!bar)
		return;
	sOpenBar = nil;
	[bar->_tick invalidate];
	bar->_tick = nil;
	void (^commit)(void) = bar->_commit;
	bar->_commit = nil;
	[bar removeFromSuperview];
	if (commit)
		commit();
}

+ (void)showInView:(UIView *)host
              text:(NSString *)text
           seconds:(NSInteger)seconds
          onCommit:(void (^)(void))commit
{
	if (!host)
		return;
	// Whatever was waiting has now really happened; only one can be pending.
	[self commitNow];

	CGRect b = host.bounds;
	TGSnackbar *bar = [[TGSnackbar alloc] initWithFrame:CGRectMake(
			kBarInset, b.size.height - kBarHeight - kBarInset,
			b.size.width - TGDoubled(kBarInset), kBarHeight)];
	bar->_total = MAX((NSInteger)1, seconds);
	bar->_left = bar->_total;
	bar->_commit = [commit copy];
	bar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
						   UIViewAutoresizingFlexibleTopMargin;
	[bar buildWithText:text];
	[host addSubview:bar];
	sOpenBar = bar;

	// Up from below the edge, the way it arrives in their design.
	CGRect resting = bar.frame;
	bar.frame = CGRectOffset(resting, 0, kBarHeight + kBarInset);
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{ bar.frame = resting; }];

	bar->_tick = [NSTimer scheduledTimerWithTimeInterval:1.0
												  target:bar
												selector:@selector(second)
												userInfo:nil
												 repeats:YES];
}

- (void)buildWithText:(NSString *)text {
	// steel-gray_dark, which is what their plate is - it has to read over both
	// a light and a dark chat.
	self.backgroundColor = [[TGTheme shared] snackbarBackgroundColour];
	self.layer.cornerRadius = TGMetricCornerMedium;
	if (![TGTheme shared].isFlat) {
		self.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
		self.layer.borderWidth = 1.0f;
	}

	CGRect ring = CGRectMake(TGMetricPadLarge, TGCenteredOrigin(kBarHeight, kRingSide),
			kRingSide, kRingSide);
	_ring = [CAShapeLayer layer];
	_ring.frame = ring;
	_ring.path = [UIBezierPath bezierPathWithOvalInRect:
			CGRectInset(CGRectMake(0, 0, kRingSide, kRingSide), 1, 1)].CGPath;
	_ring.fillColor = [UIColor clearColor].CGColor;
	_ring.strokeColor = [[TGTheme shared] snackbarTextColour].CGColor;
	_ring.lineWidth = TGMetricBorderMedium;
	// Wound from the top and unwinding as the seconds go, so the plate says how
	// long is left without anyone having to read the number.
	_ring.strokeEnd = TGMetricScaleFull;
	_ring.transform = CATransform3DMakeRotation(-M_PI_2, 0, 0, 1);
	[self.layer addSublayer:_ring];

	_count = [[UILabel alloc] initWithFrame:ring];
	_count.textAlignment = NSTextAlignmentCenter;
	_count.font = TGFontMeta();
	_count.textColor = [[TGTheme shared] snackbarTextColour];
	_count.backgroundColor = [UIColor clearColor];
	_count.text = [NSString stringWithFormat:@"%ld", (long)_left];
	[self addSubview:_count];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			kTextLeft, 0, self.bounds.size.width - kTextLeft - kUndoWidth - kBarInset,
			kBarHeight)];
	label.text = text;
	label.font = TGFontBody();
	label.textColor = [[TGTheme shared] snackbarTextColour];
	label.backgroundColor = [UIColor clearColor];
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:label];

	UIButton *undo = [UIButton buttonWithType:UIButtonTypeCustom];
	undo.frame = CGRectMake(self.bounds.size.width - kUndoWidth - kBarInset, 0,
			kUndoWidth, kBarHeight);
	undo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[undo setTitle:@"UNDO" forState:UIControlStateNormal];
	[undo setTitleColor:[[TGTheme shared] accentColour]
			   forState:UIControlStateNormal];
	undo.titleLabel.font = TGFontSubheadStrong();
	undo.titleEdgeInsets = UIEdgeInsetsMake(0, TGMetricPadLarge, 0, 0);
	[undo addTarget:self action:@selector(undoTapped)
   forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:undo];

	UIImageView *arrow = [[UIImageView alloc] initWithFrame:CGRectMake(
			self.bounds.size.width - kUndoGlyph - kUndoWidth - TGMetricPadTiny,
			TGCenteredOrigin(kBarHeight, kUndoGlyph), kUndoGlyph, kUndoGlyph)];
	arrow.image = [TGIcons menuGlyphNamed:@"undo"];
	arrow.contentMode = UIViewContentModeScaleAspectFit;
	arrow.tintColor = [[TGTheme shared] accentColour];
	arrow.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self insertSubview:arrow belowSubview:undo];
}

- (void)second {
	_left--;
	if (_left <= 0){
		[TGSnackbar commitNow];
		return;
	}
	_count.text = [NSString stringWithFormat:@"%ld", (long)_left];
	_ring.strokeEnd = (CGFloat)_left / (CGFloat)_total;
}

- (void)undoTapped {
	sOpenBar = nil;
	[_tick invalidate];
	_tick = nil;
	_commit = nil;             // the action never happens
	UIView *me = self;
	[UIView animateWithDuration:TGAnimationDurationNormal
					 animations:^{ me.alpha = 0; }
					 completion:^(BOOL done){ [me removeFromSuperview]; }];
}

@end

// vim:ft=objc
