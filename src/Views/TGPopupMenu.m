#import "TGPopupMenu.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

// Their menu at 360dp: a 200 wide card of 48 rows, a 24 glyph inset 24 from
// the left, the label at 16. Scaled to 320pt.
static const CGFloat kMenuWidth  = 178.0f;
static const CGFloat kMenuRow    = 43.0f;
static const CGFloat kMenuGlyph  = 22.0f;
static const CGFloat kMenuInset  = 14.0f;

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
	menu->_card.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
	menu->_card.alpha = 0;
	[UIView animateWithDuration:0.15 animations:^{
		menu->_card.transform = CGAffineTransformIdentity;
		menu->_card.alpha = 1;
	}];
}

- (void)buildWithItems:(NSArray *)items atPoint:(CGPoint)point {
	_items = items;
	TGTheme *theme = [TGTheme shared];

	// A wash rather than a black scrim: their menu dims the chat only slightly,
	// so you can still see the message you are acting on.
	self.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.12f];

	CGFloat height = kMenuRow * items.count;
	CGFloat x = MIN(MAX(8, point.x - kMenuWidth / 2), self.bounds.size.width - kMenuWidth - 8);
	// Above the point when there is no room below it.
	CGFloat y = point.y + 8;
	if (y + height > self.bounds.size.height - 8)
		y = MAX(8, point.y - height - 8);

	_card = [[UIView alloc] initWithFrame:CGRectMake(x, y, kMenuWidth, height)];
	_card.backgroundColor = [theme cardBackgroundColour];
	_card.layer.cornerRadius = 7;
	_card.layer.shadowColor = [UIColor blackColor].CGColor;
	_card.layer.shadowOpacity = 0.22f;
	_card.layer.shadowRadius = 8;
	_card.layer.shadowOffset = CGSizeMake(0, 3);
	[self addSubview:_card];

	for (NSUInteger i = 0; i < items.count; i++){
		NSDictionary *item = items[i];
		BOOL destructive = [item[@"destructive"] boolValue];
		CGRect frame = CGRectMake(0, kMenuRow * i, kMenuWidth, kMenuRow);

		UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
		row.frame = frame;
		row.tag = (NSInteger)i;
		[row addTarget:self action:@selector(rowTapped:)
		  forControlEvents:UIControlEventTouchUpInside];
		[_card addSubview:row];

		UIImage *glyph = [TGIcons menuGlyphNamed:item[@"icon"]];
		if (glyph){
			UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(
					kMenuInset, (kMenuRow - kMenuGlyph) / 2, kMenuGlyph, kMenuGlyph)];
			icon.image = glyph;
			icon.contentMode = UIViewContentModeScaleAspectFit;
			icon.tintColor = destructive ? [theme destructiveColour]
										 : [theme secondaryTextColour];
			[row addSubview:icon];
		}

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				kMenuInset + kMenuGlyph + 14, 0, kMenuWidth - kMenuInset - kMenuGlyph - 22,
				kMenuRow)];
		label.text = item[@"title"];
		label.font = [UIFont systemFontOfSize:15];
		label.backgroundColor = [UIColor clearColor];
		label.textColor = destructive
				? [theme destructiveColour]
				: [theme primaryTextColour];
		[row addSubview:label];

		if (i + 1 < items.count){
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(
					kMenuInset, kMenuRow * (i + 1) - 0.5f, kMenuWidth - kMenuInset, 0.5f)];
			hair.backgroundColor = [theme separatorColour];
			[_card addSubview:hair];
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
