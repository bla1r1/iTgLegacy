#import "TGPopupMenu.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

// Their menu at 360dp: a 200 wide card of 48 rows, a 24 glyph inset 24 from
// the left, the label at 16. Scaled to 320pt with design tokens.
static const CGFloat kMenuWidth  = TGMetricMenuWidth;
static const CGFloat kMenuRow    = TGMetricMenuRow;
static const CGFloat kMenuGlyph  = TGMetricMenuGlyph;
static const CGFloat kMenuInset  = TGMetricMenuInset;
/// The gap between a row's glyph and its word, and the room kept past the
/// word on the right.
static const CGFloat kGlyphGap   = TGMetricPadLarge;
static const CGFloat kLabelRoom  = 22.0f;

static TGPopupMenu *sOpenMenu = nil;

@implementation TGPopupMenu {
	UIView *_card;
	NSArray *_items;
	void (^_choice)(NSInteger, NSString *);
	NSTimeInterval _shownAt;
}

+ (void)dismiss {
	[sOpenMenu removeFromSuperview];
	sOpenMenu = nil;
}

+ (void)showItems:(NSArray *)items
          atPoint:(CGPoint)point
           inView:(UIView *)host
         onChoice:(void (^)(NSInteger, NSString *))choice
{
	if (!items.count || !host)
		return;
	[self dismiss];

	TGPopupMenu *menu = [[TGPopupMenu alloc] initWithFrame:host.bounds];
	[menu buildWithItems:items atPoint:point];
	menu->_choice = [choice copy];
	menu->_shownAt = [NSDate timeIntervalSinceReferenceDate];
	[host addSubview:menu];
	sOpenMenu = menu;

	// Grown from the corner nearest the message, which is what makes it read
	// as coming out of the thing you held rather than appearing over it.
	menu->_card.transform = CGAffineTransformMakeScale(TGTransformScaleMenuInitial, TGTransformScaleMenuInitial);
	menu->_card.alpha = TGAlphaTransparent;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		menu->_card.transform = CGAffineTransformIdentity;
		menu->_card.alpha = TGAlphaOpaque;
	}];
}

- (void)buildWithItems:(NSArray *)items atPoint:(CGPoint)point {
	_items = items;
	TGTheme *theme = [TGTheme shared];

	// A wash rather than a black scrim: their menu dims the chat only slightly,
	// so you can still see the message you are acting on.
	self.backgroundColor = [theme menuWashColour];

	CGFloat height = kMenuRow * items.count;
	CGFloat x = MIN(MAX(TGMetricPad, point.x - TGHalf(kMenuWidth)), self.bounds.size.width - kMenuWidth - TGMetricPad);
	// Above the point when there is no room below it.
	CGFloat y = point.y + TGMetricPad;
	if (y + height > self.bounds.size.height - TGMetricPad)
		y = MAX(TGMetricPad, point.y - height - TGMetricPad);

	_card = [[UIView alloc] initWithFrame:CGRectMake(x, y, kMenuWidth, height)];
	_card.backgroundColor = [UIColor clearColor];
	_card.layer.cornerRadius = TGMetricCornerCard;
	_card.layer.shadowColor = [UIColor blackColor].CGColor;
	_card.layer.shadowOpacity = TGMetricShadowMenuOpacity;
	_card.layer.shadowRadius = TGMetricShadowMenuRadius;
	_card.layer.shadowOffset = TGMetricShadowOffsetMenu;
	[self addSubview:_card];

	// iOS 6 precision container with modern Telegram clipping: keeps button
	// tap highlights strictly within the card's rounded corners, and renders
	// the crisp hairline border.
	UIView *body = [[UIView alloc] initWithFrame:_card.bounds];
	body.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	body.backgroundColor = [theme cardBackgroundColour];
	body.layer.cornerRadius = TGMetricCornerCard;
	body.layer.masksToBounds = YES;
	body.layer.borderColor = [theme separatorColour].CGColor;
	body.layer.borderWidth = TGMetricHairline;
	[_card addSubview:body];

	for (NSUInteger i = 0; i < items.count; i++){
		NSDictionary *item = items[i];
		BOOL destructive = [item[@"destructive"] boolValue];
		CGRect frame = CGRectMake(0, kMenuRow * i, kMenuWidth, kMenuRow);

		UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
		row.frame = frame;
		row.tag = (NSInteger)i;
		[row addTarget:self action:@selector(rowTapped:)
		  forControlEvents:UIControlEventTouchUpInside];
		[body addSubview:row];

		UIImage *glyph = [TGIcons menuGlyphNamed:item[@"icon"]];
		if (glyph){
			UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(
					kMenuInset, TGCenteredOrigin(kMenuRow, kMenuGlyph), kMenuGlyph, kMenuGlyph)];
			icon.image = glyph;
			icon.contentMode = UIViewContentModeScaleAspectFit;
			icon.tintColor = destructive ? [theme destructiveColour]
										 : [theme secondaryTextColour];
			[row addSubview:icon];
		}

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				kMenuInset + kMenuGlyph + kGlyphGap, 0,
				kMenuWidth - kMenuInset - kMenuGlyph - kLabelRoom,
				kMenuRow)];
		label.text = item[@"title"];
		label.font = TGFontRow();
		label.backgroundColor = [UIColor clearColor];
		label.textColor = destructive
				? [theme destructiveColour]
				: [theme primaryTextColour];
		[row addSubview:label];

		if (i + 1 < items.count){
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(
					kMenuInset, kMenuRow * (i + 1) - TGMetricHairline, kMenuWidth - kMenuInset, TGMetricHairline)];
			hair.backgroundColor = [theme separatorColour];
			[body addSubview:hair];
		}
	}
}

- (void)rowTapped:(UIButton *)row {
	NSInteger index = row.tag;
	NSString *title = _items[index][@"title"];
	void (^choice)(NSInteger, NSString *) = _choice;
	[TGPopupMenu dismiss];
	if (choice)
		choice(index, title);
}

/// Anything outside the card closes the menu and chooses nothing - but not
/// the touch that opened it. A menu raised by a long press appears under a
/// finger that is still down, and lifting it landed here as an outside tap,
/// so the card vanished before it could be read, let alone used.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	if ([NSDate timeIntervalSinceReferenceDate] - _shownAt < 0.4)
		return;
	CGPoint where = [[touches anyObject] locationInView:self];
	if (!CGRectContainsPoint(_card.frame, where))
		[TGPopupMenu dismiss];
}

@end

// vim:ft=objc
