#import "TGPopupMenu.h"
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

	self.backgroundColor = [theme menuWashColour];

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
	}

	// Layout positions
	CGFloat cardX = MIN(MAX(TGMetricPad, point.x - TGHalf(kMenuCardW)), hostW - kMenuCardW - TGMetricPad);
	CGFloat cardY = 0.0f;
	CGFloat reactionX = 0.0f;
	CGFloat reactionY = 0.0f;

	if (reactions.count) {
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

		CAGradientLayer *rGloss = [CAGradientLayer layer];
		rGloss.frame = CGRectMake(0, 0, reactionW, TGHalf(reactionH));
		rGloss.colors = @[
			(id)[theme calloutGlossTopColour].CGColor,
			(id)[theme calloutGlossBottomColour].CGColor,
			(id)[UIColor clearColor].CGColor
		];
		rGloss.locations = @[ @0.0f, @0.85f, @1.0f ];
		[_reactionCard.layer addSublayer:rGloss];

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

	CAGradientLayer *gloss = [CAGradientLayer layer];
	gloss.frame = CGRectMake(0, 0, kMenuCardW, TGHalf(actionCardH));
	gloss.colors = @[
		(id)[theme calloutGlossTopColour].CGColor,
		(id)[theme calloutGlossBottomColour].CGColor,
		(id)[UIColor clearColor].CGColor
	];
	gloss.locations = @[ @0.0f, @0.85f, @1.0f ];
	[_actionCard.layer addSublayer:gloss];

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
	} else {
		currentY = kMenuHeaderH;
	}

	// Action Rows
	for (NSUInteger i = 0; i < items.count; i++) {
		NSDictionary *item = items[i];
		BOOL destructive = [item[@"destructive"] boolValue];
		NSString *title = item[@"title"];

		// Section divider before "Select"
		if ([title isEqualToString:@"Select"]) {
			UIView *sDark = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, currentY - 0.5f, kMenuCardW - TGDoubled(TGMetricPadSmall), 0.5f)];
			sDark.backgroundColor = [theme calloutDividerDarkColour];
			[_actionCard addSubview:sDark];

			UIView *sLight = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadSmall, currentY, kMenuCardW - TGDoubled(TGMetricPadSmall), 0.5f)];
			sLight.backgroundColor = [theme calloutDividerLightColour];
			[_actionCard addSubview:sLight];

			currentY += TGMetricPadTiny;
		}

		UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
		row.frame = CGRectMake(0, currentY, kMenuCardW, kMenuRowH);
		row.tag = (NSInteger)i;
		[row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
		[row setBackgroundImage:[TGTheme skeuomorphicButtonImageWithColor:[theme accentColour] height:kMenuRowH highlighted:YES cornerRadius:0.0f] forState:UIControlStateHighlighted];
		[_actionCard addSubview:row];

		UIImage *glyph = [TGIcons menuGlyphNamed:item[@"icon"]];
		if (glyph) {
			UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(
					kMenuGlyphX, TGCenteredOrigin(kMenuRowH, kMenuGlyphSide), kMenuGlyphSide, kMenuGlyphSide)];
			icon.image = glyph;
			icon.contentMode = UIViewContentModeScaleAspectFit;
			BOOL dark = theme.isDarkStyle;
			icon.tintColor = destructive ? [theme destructiveColour] : (dark ? [UIColor whiteColor] : [theme primaryTextColour]);
			[row addSubview:icon];
		}

		BOOL dark = theme.isDarkStyle;
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				kMenuLabelX, 0, kMenuCardW - kMenuLabelX - TGMetricPad, kMenuRowH)];
		label.text = title;
		label.font = TGFontRowStrong();
		label.backgroundColor = [UIColor clearColor];
		if (destructive) {
			label.textColor = [theme destructiveColour];
			label.shadowColor = dark ? nil : [theme etchedTextShadowColour];
			label.shadowOffset = CGSizeMake(0, dark ? -1.0f : 1.0f);
		} else {
			label.textColor = dark ? [UIColor whiteColor] : [theme primaryTextColour];
			label.shadowColor = dark ? [theme navBarTextShadowColour] : [theme etchedTextShadowColour];
			label.shadowOffset = CGSizeMake(0, dark ? -1.0f : 1.0f);
		}
		[row addSubview:label];

		currentY += kMenuRowH;
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
