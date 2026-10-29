#import "TGPopupMenu.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGReactionPicker.h"

static const CGFloat kMenuWidth    = TGMetricMenuWidth;
static const CGFloat kMenuRow      = TGMetricMenuRow;
static const CGFloat kMenuGlyph    = TGMetricMenuGlyph;
static const CGFloat kMenuInset    = TGMetricMenuInset;
static const CGFloat kGlyphGap     = TGMetricPadLarge;
static const CGFloat kLabelRoom    = 22.0f;
static const CGFloat kArrowW       = 16.0f;
static const CGFloat kArrowH       = 8.0f;
static const CGFloat kArrowMargin  = 16.0f;

static TGPopupMenu *sOpenMenu = nil;

@interface TGPopupMenu () {
	UIView *_card;
	UIView *_body;
	UIView *_shineView;
	CAShapeLayer *_arrowLayer;
	TGReactionPicker *_reactionPicker;
	NSArray *_items;
	void (^_choice)(NSInteger, NSString *);
	void (^_reactionChoice)(NSString *);
	NSTimeInterval _shownAt;
}
@end

@implementation TGPopupMenu

+ (void)dismiss {
	[sOpenMenu removeFromSuperview];
	sOpenMenu = nil;
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	[self showItems:items atPoint:point inView:host reactions:nil selectedReaction:nil onReaction:nil onChoice:choice];
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
       headerView:(UIView *)headerView
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	if ((!items.count && !headerView) || !host)
		return;
	[self dismiss];

	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:host.bounds];
	[menu buildWithItems:items atPoint:point headerView:headerView reactions:nil selectedReaction:nil];
	menu->_choice = [choice copy];
	menu->_shownAt = [NSDate timeIntervalSinceReferenceDate];
	[host addSubview:menu];
	sOpenMenu = menu;

	menu->_card.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
	menu->_card.alpha = TGAlphaTransparent;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		menu->_card.transform = CGAffineTransformIdentity;
		menu->_card.alpha = TGAlphaOpaque;
	}];
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
        reactions:(NSArray<NSString *> *)reactions
   selectedReaction:(NSString *)selectedReaction
       onReaction:(void (^)(NSString *emoji))reactionChoice
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	if ((!items.count && !reactions.count) || !host)
		return;
	[self dismiss];

	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:host.bounds];
	[menu buildWithItems:items atPoint:point headerView:nil reactions:reactions selectedReaction:selectedReaction];
	menu->_choice = [choice copy];
	menu->_reactionChoice = [reactionChoice copy];
	menu->_shownAt = [NSDate timeIntervalSinceReferenceDate];
	[host addSubview:menu];
	sOpenMenu = menu;

	menu->_card.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
	menu->_card.alpha = TGAlphaTransparent;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		menu->_card.transform = CGAffineTransformIdentity;
		menu->_card.alpha = TGAlphaOpaque;
	}];
}

- (void)buildWithItems:(NSArray *)items
               atPoint:(CGPoint)point
            headerView:(UIView *)headerView
             reactions:(NSArray<NSString *> *)reactions
      selectedReaction:(NSString *)selectedReaction
{
	_items = items;
	TGTheme *theme = [TGTheme shared];

	self.backgroundColor = [theme menuWashColour];

	CGFloat reactionH = 0.0f;
	CGFloat cardW = kMenuWidth;

	if (reactions.count) {
		_reactionPicker = [[TGReactionPicker alloc] initWithEmojis:reactions selectedEmoji:selectedReaction];
		CGSize pSize = [_reactionPicker sizeThatFits:CGSizeZero];
		if (pSize.width > cardW) {
			cardW = pSize.width;
		}
		reactionH = pSize.height;

		__weak typeof(self) weakSelf = self;
		_reactionPicker.onEmojiSelected = ^(NSString *emoji){
			void (^rChoice)(NSString *) = weakSelf->_reactionChoice;
			[TGPopupMenu dismiss];
			if (rChoice) {
				rChoice(emoji);
			}
		};
	}

	CGFloat headerH = headerView ? headerView.bounds.size.height : 0.0f;
	CGFloat totalContentH = reactionH + headerH + kMenuRow * (CGFloat)items.count;
	CGFloat totalHWithArrow = totalContentH + kArrowH;

	CGFloat hostW = self.bounds.size.width;
	CGFloat hostH = self.bounds.size.height;

	CGFloat x = MIN(MAX(TGMetricPad, point.x - TGHalf(cardW)), hostW - cardW - TGMetricPad);

	BOOL arrowPointsDown = NO;
	CGFloat y = point.y + TGMetricPad;
	if (y + totalHWithArrow > hostH - TGMetricPad) {
		// Place card above the point
		y = MAX(TGMetricPad, point.y - totalHWithArrow - TGMetricPad);
		arrowPointsDown = YES;
	}

	_card = [[UIView alloc] initWithFrame:CGRectMake(x, y, cardW, totalHWithArrow)];
	_card.backgroundColor = [UIColor clearColor];
	_card.layer.shadowColor = [UIColor blackColor].CGColor;
	_card.layer.shadowOpacity = TGMetricShadowMenuOpacity;
	_card.layer.shadowRadius = TGMetricShadowMenuRadius;
	_card.layer.shadowOffset = TGMetricShadowOffsetMenu;
	[self addSubview:_card];

	CGFloat bodyY = arrowPointsDown ? 0.0f : kArrowH;
	_body = [[UIView alloc] initWithFrame:CGRectMake(0, bodyY, cardW, totalContentH)];
	_body.backgroundColor = [theme cardBackgroundColour];
	_body.layer.cornerRadius = TGMetricCornerCard;
	_body.layer.masksToBounds = YES;
	_body.layer.borderColor = [theme separatorColour].CGColor;
	_body.layer.borderWidth = 1.0f;
	[_card addSubview:_body];

	_shineView = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, 0.5f, cardW - TGDoubled(TGMetricPadSmall), 1.0f)];
	_shineView.backgroundColor = [theme skeuoShineColour];
	_shineView.userInteractionEnabled = NO;
	[_body addSubview:_shineView];

	// Pointer arrow (Callout tail)
	CGFloat arrowCenterX = MIN(MAX(kArrowMargin + TGHalf(kArrowW), point.x - x), cardW - kArrowMargin - TGHalf(kArrowW));
	CGFloat arrowLeft = arrowCenterX - TGHalf(kArrowW);

	UIBezierPath *arrowPath = [UIBezierPath bezierPath];
	if (arrowPointsDown) {
		CGFloat arrowTop = totalContentH;
		[arrowPath moveToPoint:CGPointMake(arrowLeft, arrowTop)];
		[arrowPath addLineToPoint:CGPointMake(arrowCenterX, arrowTop + kArrowH)];
		[arrowPath addLineToPoint:CGPointMake(arrowLeft + kArrowW, arrowTop)];
		[arrowPath closePath];
	} else {
		[arrowPath moveToPoint:CGPointMake(arrowLeft, kArrowH)];
		[arrowPath addLineToPoint:CGPointMake(arrowCenterX, 0)];
		[arrowPath addLineToPoint:CGPointMake(arrowLeft + kArrowW, kArrowH)];
		[arrowPath closePath];
	}

	_arrowLayer = [CAShapeLayer layer];
	_arrowLayer.path = arrowPath.CGPath;
	_arrowLayer.fillColor = [theme cardBackgroundColour].CGColor;
	_arrowLayer.strokeColor = [theme separatorColour].CGColor;
	_arrowLayer.lineWidth = 1.0f;
	[_card.layer addSublayer:_arrowLayer];

	CGFloat currentY = 0.0f;

	// Reactions bar at top of card
	if (_reactionPicker) {
		_reactionPicker.frame = CGRectMake(0, 0, cardW, reactionH);
		_reactionPicker.layer.cornerRadius = 0.0f;
		_reactionPicker.layer.borderWidth = 0.0f;
		[_body addSubview:_reactionPicker];
		currentY += reactionH;

		if (items.count > 0 || headerView) {
			UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, currentY, cardW, 1.0f)];
			div.backgroundColor = [theme separatorColour];
			[_body addSubview:div];
		}
	}

	if (headerView) {
		headerView.frame = CGRectMake(0, currentY, cardW, headerH);
		[_body addSubview:headerView];
		currentY += headerH;

		if (items.count > 0) {
			UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, currentY, cardW, 1.0f)];
			div.backgroundColor = [theme separatorColour];
			[_body addSubview:div];
		}
	}

	for (NSUInteger i = 0; i < items.count; i++) {
		NSDictionary *item = items[i];
		BOOL destructive = [item[@"destructive"] boolValue];
		CGRect frame = CGRectMake(0, currentY + kMenuRow * (CGFloat)i, cardW, kMenuRow);

		UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
		row.frame = frame;
		row.tag = (NSInteger)i;
		[row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
		[_body addSubview:row];

		UIImage *glyph = [TGIcons menuGlyphNamed:item[@"icon"]];
		if (glyph) {
			UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(
					kMenuInset, TGCenteredOrigin(kMenuRow, kMenuGlyph), kMenuGlyph, kMenuGlyph)];
			icon.image = glyph;
			icon.contentMode = UIViewContentModeScaleAspectFit;
			icon.tintColor = destructive ? [theme destructiveActionColour] : [theme secondaryTextColour];
			[row addSubview:icon];
		}

		CGFloat labelX = kMenuInset + kMenuGlyph + kGlyphGap;
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				labelX, 0, cardW - labelX - kLabelRoom, kMenuRow)];
		label.text = item[@"title"];
		label.font = TGFontRow();
		label.backgroundColor = [UIColor clearColor];
		if (destructive) {
			label.textColor = [theme destructiveActionColour];
		} else {
			label.textColor = [theme primaryTextColour];
			label.shadowColor = [theme etchedTextShadowColour];
			label.shadowOffset = CGSizeMake(0, 1.0f);
		}
		[row addSubview:label];

		if (i + 1 < items.count) {
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(
					kMenuInset, currentY + kMenuRow * (CGFloat)(i + 1) - 1.0f, cardW - kMenuInset, 1.0f)];
			hair.backgroundColor = [theme separatorColour];
			[_body addSubview:hair];
		}
	}
}

- (void)rowTapped:(UIButton *)row {
	NSInteger index = row.tag;
	NSString *title = _items[(NSUInteger)index][@"title"];
	void (^choice)(NSInteger, NSString *) = _choice;
	[TGPopupMenu dismiss];
	if (choice)
		choice(index, title);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	if ([NSDate timeIntervalSinceReferenceDate] - _shownAt < 0.4)
		return;
	CGPoint where = [[touches anyObject] locationInView:self];
	if (!CGRectContainsPoint(_card.frame, where))
		[TGPopupMenu dismiss];
}

@end
