//
// TGSheet.m - backdrop, cards, one slide.
//
#import "TGSheet.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

static const CGFloat kCorner     = TGMetricCornerCard;   ///< a floating card, all four
static const CGFloat kEdgeCorner = TGMetricCornerCard; ///< a pinned card, top two
static const NSTimeInterval kIn  = TGAnimationDurationMedium;
static const NSTimeInterval kOut = TGAnimationDurationNormal;

// One sheet at a time, the way TGPopupMenu keeps its menu.
static TGSheet *sOpenSheet = nil;

@implementation TGSheet {
	UIView *_backdrop;
	NSMutableArray *_cards;        ///< top to bottom, as they were added
	NSMutableArray *_edgeFlags;
	__weak UIView *_host;
}

+ (void)dismissOpen {
	[sOpenSheet removeFromSuperview];
	sOpenSheet = nil;
}

+ (instancetype)sheetForView:(UIView *)host {
	// A caller that is not a view at all is a programming mistake, and it
	// used to be a crash: the media viewer is an NSObject and passed itself,
	// so a picture finishing saving asked a plain object for its bounds.
	if (![host isKindOfClass:UIView.class]){
		if (host)
			NSLog(@"TGSheet: asked to rise from a %@, which is not a view",
					NSStringFromClass([host class]));
		return nil;
	}
	TGSheet *sheet = [[self alloc] initWithFrame:host.bounds];
	sheet->_host = host;
	return sheet;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							UIViewAutoresizingFlexibleHeight;
	_cards = [NSMutableArray array];
	_edgeFlags = [NSMutableArray array];

	_backdrop = [[UIView alloc] initWithFrame:self.bounds];
	_backdrop.autoresizingMask = self.autoresizingMask;
	_backdrop.backgroundColor = [[TGTheme shared] scrimColour];
	_backdrop.alpha = 0;
	// The cards sit above the backdrop, so a tap that lands on one never
	// reaches this recognizer and only the dimmed area closes the sheet.
	[_backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(dismiss)]];
	[self addSubview:_backdrop];
	return self;
}

- (UIView *)addCardOfHeight:(CGFloat)height edgeToEdge:(BOOL)edgeToEdge {
	CGFloat width = edgeToEdge ? self.bounds.size.width
							   : self.bounds.size.width - TGDoubled(TGMetricCardMargin);
	UIView *card = [[UIView alloc] initWithFrame:CGRectMake(
			edgeToEdge ? 0 : TGMetricCardMargin, self.bounds.size.height, width, height)];
	card.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	if (edgeToEdge){
		// Only the top corners: the card stands on the screen edge, and a
		// rounded bottom would show the backdrop through it. maskedCorners
		// arrives in iOS 11, so the shape is a mask layer.
		CAShapeLayer *mask = [CAShapeLayer layer];
		mask.path = [UIBezierPath bezierPathWithRoundedRect:card.bounds
										 byRoundingCorners:UIRectCornerTopLeft |
														   UIRectCornerTopRight
											   cornerRadii:CGSizeMake(kEdgeCorner,
																	  kEdgeCorner)].CGPath;
		card.layer.mask = mask;
	} else {
		card.layer.cornerRadius = kCorner;
		card.clipsToBounds = YES;
		card.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
		card.layer.borderWidth = TGMetricHairline;
	}

	UIView *shine = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, 0.5f, width - TGDoubled(TGMetricPadSmall), 1.0f)];
	shine.backgroundColor = [[TGTheme shared] skeuoShineColour];
	shine.userInteractionEnabled = NO;
	[card addSubview:shine];

	[_cards addObject:card];
	[_edgeFlags addObject:@(edgeToEdge)];
	[self addSubview:card];
	return card;
}

/// Shown: the stack rests on the bottom edge, each floating card with a gap
/// under it. Hidden: every card sits just below the screen, where the slide
/// starts and ends.
- (void)setBottomInset:(CGFloat)bottomInset {
	_bottomInset = bottomInset;
	if (self.superview)
		[self layoutCardsShown:YES];
}

- (void)layoutCardsShown:(BOOL)shown {
	CGFloat y = self.bounds.size.height - (shown ? self.bottomInset : 0);
	for (NSInteger i = (NSInteger)_cards.count - 1; i >= 0; i--){
		UIView *card = _cards[i];
		CGRect frame = card.frame;
		if (shown){
			if ([_edgeFlags[i] boolValue] == NO)
				y -= TGMetricCardMargin;
			y -= frame.size.height;
			frame.origin.y = y;
		} else {
			frame.origin.y = self.bounds.size.height;
		}
		card.frame = frame;
	}
}

- (void)present {
	UIView *host = _host;
	if (!host)
		return;
	[TGSheet dismissOpen];
	[host addSubview:self];
	sOpenSheet = self;

	[self layoutCardsShown:NO];
	[UIView animateWithDuration:kIn animations:^{
		self->_backdrop.alpha = 1;
		[self layoutCardsShown:YES];
	}];
}

- (void)dismiss {
	[UIView animateWithDuration:kOut animations:^{
		self->_backdrop.alpha = 0;
		[self layoutCardsShown:NO];
	} completion:^(BOOL done){
		if (sOpenSheet == self)
			sOpenSheet = nil;
		[self removeFromSuperview];
	}];
}

// The screen under the sheet can go away while it is open; the static that
// keeps one sheet at a time must not keep the view alive past that.
- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (!self.window && sOpenSheet == self)
		sOpenSheet = nil;
}

@end
