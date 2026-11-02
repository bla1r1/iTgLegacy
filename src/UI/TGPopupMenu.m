#import "TGPopupMenu.h"
#import "TGAlertSheet.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGReactionPicker.h"

static const CGFloat kMenuCardW        = 220.0f;
static const CGFloat kMenuRowH         = 36.0f;
static const CGFloat kMenuHeaderH      = TGMetricPadSmall;
static const CGFloat kMenuGlyphSide    = 18.0f;
static const CGFloat kMenuGlyphX       = 16.0f;
static const CGFloat kMenuLabelX       = 46.0f;
static const CGFloat kReactionPadH     = 12.0f;
static const CGFloat kReactionPadV     = 6.0f;
/// A lifted menu keeps at least this much of itself on screen. Anything the
/// card cannot show at once scrolls inside the card, so the same actions are
/// still there on a 3.5" screen as on a 4" one.
static const CGFloat kMenuLiftedMinH   = 4.0f * kMenuRowH;

static TGPopupMenu *sOpenMenu = nil;

@interface TGPopupMenu () {
	UIView *_reactionWrapper;
	UIView *_reactionCard;
	UIView *_actionWrapper;
	UIView *_actionCard;
	TGReactionPicker *_reactionPicker;
	NSArray *_items;
	void (^_choice)(NSInteger, NSString *);
	void (^_reactionChoice)(NSString *);
	void (^_defaultReactionChoice)(NSString *);
	/// Named once when the menu goes away, however it goes away: the hold
	/// presentation uses it to put the message back into the list.
	void (^_onDismiss)(void);
	NSTimeInterval _shownAt;

	/// The lifted-bubble presentation. The card hangs from the anchor's
	/// bottom edge and the reaction bar sits over its top; a card that cannot
	/// fit is scrolled rather than run off screen.
	BOOL _lifted;
	CGRect _anchorRect;
	UIScrollView *_actionScroll;
	/// The card's height before it was capped to the room below the anchor,
	/// so the row loop knows whether it is scrolling.
	CGFloat _naturalCardH;
}
@end

@implementation TGPopupMenu

+ (void)dismiss {
	TGPopupMenu *menu = sOpenMenu;
	sOpenMenu = nil;
	// The block is copied and the menu released before it runs: it restores
	// the held message, which must not happen while a new menu still holds
	// this one as the open menu. A nil menu has no fields to read.
	void (^done)(void) = menu ? [menu->_onDismiss copy] : nil;
	[menu removeFromSuperview];
	if (done)
		done();
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	// A plain list of actions is what UIActionSheet is for; the drawn popup
	// stays only where it carries something the system sheet cannot
	// (reactions, the emoji header).
	NSMutableArray *titles = [NSMutableArray arrayWithCapacity:items.count];
	__block NSInteger destructive = -1;
	[items enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger i, BOOL *stop){
		[titles addObject:item[@"title"] ?: @""];
		if (destructive < 0 && [item[@"destructive"] boolValue])
			destructive = (NSInteger)i;
	}];
	[TGAlertSheet showChoices:titles title:nil destructiveIndex:destructive inView:host
					 onChoice:^(NSInteger index){ if (choice) choice(index, titles[index]); }];
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

	// The header is the reason this variant exists - an animated sticker or
	// an emoji glyph above the rows - so it is drawn as the card, not handed
	// to the system sheet where a header has nowhere to go.
	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:host.bounds];
	[menu buildWithItems:items atPoint:point headerView:headerView reactions:nil selectedReaction:nil];
	menu->_choice = [choice copy];
	menu->_shownAt = [NSDate timeIntervalSinceReferenceDate];
	[host addSubview:menu];
	sOpenMenu = menu;

	menu->_actionWrapper.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
	menu->_actionWrapper.alpha = TGAlphaTransparent;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		menu->_actionWrapper.transform = CGAffineTransformIdentity;
		menu->_actionWrapper.alpha = TGAlphaOpaque;
	}];
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
        reactions:(NSArray<NSString *> *)reactions
   selectedReaction:(NSString *)selectedReaction
       onReaction:(void (^)(NSString *))reactionChoice
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	[self showItems:items atPoint:point inView:host reactions:reactions
		   selectedReaction:selectedReaction onReaction:reactionChoice
		onDefaultReaction:nil onChoice:choice];
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
        reactions:(NSArray<NSString *> *)reactions
   selectedReaction:(NSString *)selectedReaction
       onReaction:(void (^)(NSString *))reactionChoice
onDefaultReaction:(void (^)(NSString *))defaultChoice
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	if ((!items.count && !reactions.count) || !host)
		return;
	[self dismiss];

	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:host.bounds];
	[menu buildWithItems:items atPoint:point headerView:nil reactions:reactions selectedReaction:selectedReaction];
	menu->_choice = [choice copy];
	menu->_reactionChoice = [reactionChoice copy];
	menu->_defaultReactionChoice = [defaultChoice copy];
	menu->_shownAt = [NSDate timeIntervalSinceReferenceDate];
	[host addSubview:menu];
	sOpenMenu = menu;

	if (menu->_reactionWrapper) {
		menu->_reactionWrapper.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
		menu->_reactionWrapper.alpha = TGAlphaTransparent;
	}
	menu->_actionWrapper.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
	menu->_actionWrapper.alpha = TGAlphaTransparent;

	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		if (menu->_reactionWrapper) {
			menu->_reactionWrapper.transform = CGAffineTransformIdentity;
			menu->_reactionWrapper.alpha = TGAlphaOpaque;
		}
		menu->_actionWrapper.transform = CGAffineTransformIdentity;
		menu->_actionWrapper.alpha = TGAlphaOpaque;
	}];
}

+ (void)showItems:(NSArray *)items
       anchoredAt:(CGRect)anchor
           inView:(UIView *)host
        reactions:(NSArray<NSString *> *)reactions
   selectedReaction:(NSString *)selectedReaction
       onReaction:(void (^)(NSString *))reactionChoice
onDefaultReaction:(void (^)(NSString *))defaultChoice
         onChoice:(void (^)(NSInteger, NSString *))choice
       onDismiss:(void (^)(void))dismissal
{
	if ((!items.count && !reactions.count) || !host)
		return;
	[self dismiss];

	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:host.bounds];
	menu->_lifted = YES;
	menu->_anchorRect = anchor;
	[menu buildWithItems:items
				 atPoint:CGPointMake(CGRectGetMidX(anchor), CGRectGetMaxY(anchor))
			  headerView:nil
			   reactions:reactions
		selectedReaction:selectedReaction];
	menu->_choice = [choice copy];
	menu->_reactionChoice = [reactionChoice copy];
	menu->_defaultReactionChoice = [defaultChoice copy];
	menu->_onDismiss = [dismissal copy];
	menu->_shownAt = [NSDate timeIntervalSinceReferenceDate];
	[host addSubview:menu];
	sOpenMenu = menu;

	if (menu->_reactionWrapper) {
		menu->_reactionWrapper.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
		menu->_reactionWrapper.alpha = TGAlphaTransparent;
	}
	menu->_actionWrapper.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
	menu->_actionWrapper.alpha = TGAlphaTransparent;

	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		if (menu->_reactionWrapper) {
			menu->_reactionWrapper.transform = CGAffineTransformIdentity;
			menu->_reactionWrapper.alpha = TGAlphaOpaque;
		}
		menu->_actionWrapper.transform = CGAffineTransformIdentity;
		menu->_actionWrapper.alpha = TGAlphaOpaque;
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

	// The lifted presentation sits over the blurred chat and must not add a
	// second wash to it; it is a touch catcher, not a tinted sheet.
	self.backgroundColor = _lifted ? [UIColor clearColor] : [theme menuWashColour];

	CGFloat hostW = self.bounds.size.width;
	CGFloat hostH = self.bounds.size.height;

	// Calculate Action Card Height
	CGFloat headerH = headerView ? headerView.bounds.size.height : kMenuHeaderH;
	CGFloat actionCardH = headerH + (CGFloat)items.count * kMenuRowH + TGMetricPadSmall;
	for (NSDictionary *it in items) {
		if ([it[@"title"] isEqualToString:@"Select"]) {
			actionCardH += TGMetricPadTiny;
			break;
		}
	}
	// Kept before the lifted layout caps the card: a card shorter than this
	// is a card whose rows have to scroll inside it.
	_naturalCardH = actionCardH;

	CGFloat reactionW = 0.0f;
	CGFloat reactionH = 0.0f;
	CGSize pSize = CGSizeZero;

	if (reactions.count) {
		_reactionPicker = [[TGReactionPicker alloc] initWithEmojis:reactions selectedEmoji:selectedReaction];
		pSize = [_reactionPicker sizeThatFits:CGSizeZero];
		reactionW = pSize.width + kReactionPadH;
		reactionH = pSize.height + kReactionPadV;

		__weak typeof(self) weakSelf = self;
		_reactionPicker.onEmojiSelected = ^(NSString *emoji){
			TGPopupMenu *strongSelf = weakSelf;
			if (!strongSelf) return;
			void (^rChoice)(NSString *) = strongSelf->_reactionChoice;
			[TGPopupMenu dismiss];
			if (rChoice) {
				rChoice(emoji);
			}
		};
		_reactionPicker.onDefaultRequested = ^(NSString *emoji){
			TGPopupMenu *strongSelf = weakSelf;
			if (!strongSelf) return;
			void (^dChoice)(NSString *) = strongSelf->_defaultReactionChoice;
			// Promote first: the bar is still on screen under the finger,
			// so the answer to the hold is visible before the request lands.
			[strongSelf->_reactionPicker promoteEmoji:emoji];
			if (dChoice) {
				dChoice(emoji);
			}
		};
	}

	// Layout positions
	CGFloat cardX = MIN(MAX(TGMetricPad, point.x - TGHalf(kMenuCardW)), hostW - kMenuCardW - TGMetricPad);
	CGFloat cardY = 0.0f;
	CGFloat reactionX = 0.0f;
	CGFloat reactionY = 0.0f;

	if (_lifted) {
		// The anchor is the lifted bubble itself. The bar belongs over its
		// head, the card under its feet; neither answers to the finger.
		CGFloat midX = CGRectGetMidX(_anchorRect);
		reactionX = MIN(MAX(TGMetricPad, midX - TGHalf(reactionW)),
						hostW - reactionW - TGMetricPad);
		reactionY = MAX(TGMetricPad,
				CGRectGetMinY(_anchorRect) - reactionH - TGMetricPadSmall);
		cardX = MIN(MAX(TGMetricPad, midX - TGHalf(kMenuCardW)),
					hostW - kMenuCardW - TGMetricPad);
		cardY = CGRectGetMaxY(_anchorRect) + TGMetricPadSmall;

		// Never let the card run off the bottom. When it would, it keeps a
		// readable four-row window and the rest is reached by scrolling.
		CGFloat room = hostH - cardY - TGMetricPad;
		if (room < actionCardH)
			actionCardH = MAX(room, kMenuLiftedMinH);
	} else if (reactions.count) {
		reactionX = MIN(MAX(TGMetricPad, point.x - TGHalf(reactionW)), hostW - reactionW - TGMetricPad);
		if (point.y + actionCardH + TGMetricPad < hostH) {
			// Message is high: Reactions capsule floating ABOVE message, Action card BELOW
			reactionY = MAX(TGMetricPad, point.y - reactionH - TGMetricPadSmall);
			cardY = point.y + TGMetricPadSmall;
		} else {
			// Message is low: Action card floats above message, Reaction capsule above action card
			cardY = MAX(TGMetricPad + reactionH + TGMetricPadSmall, point.y - actionCardH - TGMetricPadSmall);
			reactionY = cardY - reactionH - TGMetricPadSmall;
		}
	} else {
		if (point.y + actionCardH + TGMetricPad < hostH) {
			cardY = point.y + TGMetricPadSmall;
		} else {
			cardY = MAX(TGMetricPad, point.y - actionCardH - TGMetricPadSmall);
		}
	}

	// 1. Build Floating Reaction Capsule
	if (reactions.count) {
		_reactionWrapper = [[UIView alloc] initWithFrame:CGRectMake(reactionX, reactionY, reactionW, reactionH)];
		_reactionWrapper.backgroundColor = [UIColor clearColor];
		_reactionWrapper.layer.shadowColor = [UIColor blackColor].CGColor;
		_reactionWrapper.layer.shadowOpacity = TGMetricShadowMenuOpacity;
		_reactionWrapper.layer.shadowRadius = TGMetricShadowMenuRadius;
		_reactionWrapper.layer.shadowOffset = TGMetricShadowOffsetMenu;
		[self addSubview:_reactionWrapper];

		_reactionCard = [[UIView alloc] initWithFrame:_reactionWrapper.bounds];
		_reactionCard.backgroundColor = [theme calloutBackgroundColour];
		_reactionCard.layer.cornerRadius = TGHalf(reactionH);
		_reactionCard.layer.masksToBounds = YES;
		_reactionCard.layer.borderColor = [theme calloutBorderColour].CGColor;
		_reactionCard.layer.borderWidth = 1.0f;
		[_reactionWrapper addSubview:_reactionCard];

		UIImage *rGlossImage = [TGTheme calloutGlossImageWithSize:CGSizeMake(reactionW, TGHalf(reactionH))];
		if (rGlossImage) {
			UIImageView *rGloss = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, reactionW, TGHalf(reactionH))];
			rGloss.image = rGlossImage;
			[_reactionCard addSubview:rGloss];
		}

		_reactionPicker.frame = CGRectMake(TGHalf(kReactionPadH), TGHalf(kReactionPadV), pSize.width, pSize.height);
		[_reactionCard addSubview:_reactionPicker];
	}

	// 2. Build Floating Action Menu Card
	_actionWrapper = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, kMenuCardW, actionCardH)];
	_actionWrapper.backgroundColor = [UIColor clearColor];
	_actionWrapper.layer.shadowColor = [UIColor blackColor].CGColor;
	_actionWrapper.layer.shadowOpacity = TGMetricShadowMenuOpacity;
	_actionWrapper.layer.shadowRadius = TGMetricShadowMenuRadius;
	_actionWrapper.layer.shadowOffset = TGMetricShadowOffsetMenu;
	[self addSubview:_actionWrapper];

	_actionCard = [[UIView alloc] initWithFrame:_actionWrapper.bounds];
	_actionCard.backgroundColor = [theme calloutBackgroundColour];
	_actionCard.layer.cornerRadius = TGMetricCornerCard;
	_actionCard.layer.masksToBounds = YES;
	_actionCard.layer.borderColor = [theme calloutBorderColour].CGColor;
	_actionCard.layer.borderWidth = 1.0f;
	[_actionWrapper addSubview:_actionCard];

	UIImage *glossImage = [TGTheme calloutGlossImageWithSize:CGSizeMake(kMenuCardW, TGHalf(actionCardH))];
	if (glossImage) {
		UIImageView *gloss = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kMenuCardW, TGHalf(actionCardH))];
		gloss.image = glossImage;
		[_actionCard addSubview:gloss];
	}

	// The lifted card is the one that can be taller than the room below the
	// bubble. Its rows live in a scroll view so every action stays reachable;
	// the ordinary callout is short enough by construction and keeps adding
	// rows straight to the card.
	if (_lifted && actionCardH < _naturalCardH) {
		_actionScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, headerH,
				kMenuCardW, actionCardH - headerH)];
		_actionScroll.backgroundColor = [UIColor clearColor];
		_actionScroll.showsVerticalScrollIndicator = YES;
		_actionScroll.alwaysBounceVertical = NO;
		_actionScroll.scrollsToTop = NO;
		[_actionCard addSubview:_actionScroll];
	}

	CGFloat currentY = 0.0f;

	if (headerView) {
		headerView.frame = CGRectMake(0, 0, kMenuCardW, headerH);
		[_actionCard addSubview:headerView];
		currentY += headerH;

		UIView *divDark = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, currentY - 0.5f, kMenuCardW - TGDoubled(TGMetricPadSmall), 0.5f)];
		divDark.backgroundColor = [theme calloutDividerDarkColour];
		[_actionCard addSubview:divDark];

		UIView *divLight = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, currentY, kMenuCardW - TGDoubled(TGMetricPadSmall), 0.5f)];
		divLight.backgroundColor = [theme calloutDividerLightColour];
		[_actionCard addSubview:divLight];
	} else if (!_actionScroll) {
		currentY = kMenuHeaderH;
	}

	UIView *rowParent = _actionScroll ?: _actionCard;

	// Action Rows
	for (NSUInteger i = 0; i < items.count; i++) {
		NSDictionary *item = items[i];
		BOOL destructive = [item[@"destructive"] boolValue];
		NSString *title = item[@"title"];

		// Section divider before "Select"
		if ([title isEqualToString:@"Select"]) {
			UIView *sDark = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, currentY - 0.5f, kMenuCardW - TGDoubled(TGMetricPadSmall), 0.5f)];
			sDark.backgroundColor = [theme calloutDividerDarkColour];
			[rowParent addSubview:sDark];

			UIView *sLight = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, currentY, kMenuCardW - TGDoubled(TGMetricPadSmall), 0.5f)];
			sLight.backgroundColor = [theme calloutDividerLightColour];
			[rowParent addSubview:sLight];

			currentY += TGMetricPadTiny;
		}

		UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
		row.frame = CGRectMake(0, currentY, kMenuCardW, kMenuRowH);
		row.tag = (NSInteger)i;
		[row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
		[row setBackgroundImage:[TGTheme skeuomorphicButtonImageWithColor:[theme accentColour] height:kMenuRowH highlighted:YES cornerRadius:0.0f] forState:UIControlStateHighlighted];
		[rowParent addSubview:row];

		UIImage *glyph = [TGIcons menuGlyphNamed:item[@"icon"]];
		if (glyph) {
			UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(
					kMenuGlyphX, TGCenteredOrigin(kMenuRowH, kMenuGlyphSide), kMenuGlyphSide, kMenuGlyphSide)];
			icon.image = glyph;
			icon.contentMode = UIViewContentModeScaleAspectFit;
			[TGIcons tintImageView:icon colour:(destructive ? [theme destructiveColour]
					: [theme primaryTextColour])];
			[row addSubview:icon];
		}

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				kMenuLabelX, 0, kMenuCardW - kMenuLabelX - TGMetricPad, kMenuRowH)];
		label.text = title;
		label.font = TGFontRowStrong();
		label.backgroundColor = [UIColor clearColor];
		label.textColor = destructive ? [theme destructiveColour] : [theme primaryTextColour];
		label.shadowColor = [theme etchedTextShadowColour];
		label.shadowOffset = CGSizeMake(0, 1.0f);
		[row addSubview:label];

		currentY += kMenuRowH;
	}

	if (_actionScroll) {
		_actionScroll.contentSize = CGSizeMake(kMenuCardW, currentY + TGMetricPadSmall);
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
	if ([NSDate timeIntervalSinceReferenceDate] - _shownAt < 0.3)
		return;
	CGPoint where = [[touches anyObject] locationInView:self];
	if (!CGRectContainsPoint(_actionWrapper.frame, where) &&
		(!_reactionWrapper || !CGRectContainsPoint(_reactionWrapper.frame, where))) {
		[TGPopupMenu dismiss];
	}
}

@end
