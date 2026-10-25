//
// TGSheet.m - backdrop, cards, one slide.
//
#import "TGSheet.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMargin     = 8.0f;    ///< gap around a floating card
static const CGFloat kCorner     = 12.0f;   ///< a floating card, all four
static const CGFloat kEdgeCorner = 14.0f;   ///< a pinned card, top two
static const CGFloat kScrim      = 0.4f;
static const NSTimeInterval kIn  = 0.25;
static const NSTimeInterval kOut = 0.2;

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
	if (!host)
		return nil;
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
	_backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:kScrim];
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
							   : self.bounds.size.width - 2 * kMargin;
	UIView *card = [[UIView alloc] initWithFrame:CGRectMake(
			edgeToEdge ? 0 : kMargin, self.bounds.size.height, width, height)];
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
	}
	[_cards addObject:card];
	[_edgeFlags addObject:@(edgeToEdge)];
	[self addSubview:card];
	return card;
}

/// Shown: the stack rests on the bottom edge, each floating card with a gap
/// under it. Hidden: every card sits just below the screen, where the slide
/// starts and ends.
- (void)layoutCardsShown:(BOOL)shown {
	CGFloat y = self.bounds.size.height;
	for (NSInteger i = (NSInteger)_cards.count - 1; i >= 0; i--){
		UIView *card = _cards[i];
		CGRect frame = card.frame;
		if (shown){
			if ([_edgeFlags[i] boolValue] == NO)
				y -= kMargin;
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
