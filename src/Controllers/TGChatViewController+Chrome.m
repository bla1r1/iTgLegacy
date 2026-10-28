//
// TGChatViewController+Chrome.m - what sits around the messages rather than
// in them: day and unread separators, the floating date, the jump-down
// button, swipe to reply, and the animated "typing".
//
#import "TGChatViewControllerInternal.h"
#import <QuartzCore/QuartzCore.h>
#import "TGAlertSheet.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGContactsViewController.h"
#import "TGNewContactViewController.h"

static const CGFloat kJumpSide = TGMetricJumpSide;
/// The ticks are drawn a point shorter than the box they sit in, so the two
/// strokes do not touch its edge.
static const CGFloat kTicksDrawnHeight = 11.0f;
/// The widest the unread count on the jump button goes before it truncates.
static const CGFloat kJumpBadgeMaxW    = 60.0f;
/// The arrow that appears while a bubble is dragged to be replied to.
static const CGFloat kReplyHintGlyph   = 20.0f;
static const CGFloat kReplyHintInset   = 24.0f;

@implementation TGChatViewController (Chrome)

#pragma mark - separators

/// "Today", "Yesterday", "5 March", "5 March 2024" - how the day plates and
/// the floating date read.
static NSString *TGDayTitle(NSTimeInterval stamp) {
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:stamp];
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
	NSDateComponents *day = [calendar components:units fromDate:date];
	NSDateComponents *today = [calendar components:units fromDate:[NSDate date]];
	NSDate *dayStart = [calendar dateFromComponents:day];
	NSDate *todayStart = [calendar dateFromComponents:today];
	NSInteger daysAgo = (NSInteger)lround([todayStart timeIntervalSinceDate:dayStart] / 86400.0);
	if (daysAgo == 0)
		return @"Today";
	if (daysAgo == 1)
		return @"Yesterday";

	static NSDateFormatter *sameYear = nil, *otherYear = nil;
	if (!sameYear){
		NSLocale *locale = [NSLocale currentLocale];
		sameYear = [[NSDateFormatter alloc] init];
		sameYear.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"dMMMM" options:0 locale:locale];
		otherYear = [[NSDateFormatter alloc] init];
		otherYear.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"dMMMMyyyy" options:0 locale:locale];
	}
	return day.year == today.year ? [sameYear stringFromDate:date] : [otherYear stringFromDate:date];
}

static NSInteger TGDayNumber(NSTimeInterval stamp) {
	NSDateComponents *c = [[NSCalendar currentCalendar]
			components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
			  fromDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
	return c.year * 10000 + c.month * 100 + c.day;
}

- (NSArray *)messagesWithSeparators:(NSArray *)grouped {
	if (!grouped.count)
		return grouped;
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:grouped.count + 8];
	NSInteger lastDay = -1;
	for (NSDictionary *m in grouped){
		NSTimeInterval stamp = [m[@"date"] doubleValue];
		if (stamp > 0){
			NSInteger dayNumber = TGDayNumber(stamp);
			if (dayNumber != lastDay){
				lastDay = dayNumber;
				[out addObject:@{@"service" : @YES, @"separator" : @"day",
								 @"text" : TGDayTitle(stamp), @"date" : m[@"date"]}];
			}
		}
		if (self.unreadFromId && [m[@"id"] longLongValue] == self.unreadFromId)
			[out addObject:@{@"service" : @YES, @"separator" : @"unread",
							 @"text" : @"Unread Messages", @"date" : m[@"date"] ?: @0}];
		[out addObject:m];
	}
	return out;
}

/// The first message that arrived after you last read the chat, captured
/// once as it opens so it stays put while you read.
- (void)noteFirstUnreadIn:(NSArray *)raw {
	if (self.unreadChecked)
		return;
	self.unreadChecked = YES;
	if (self.readInboxAtOpen <= 0)
		return;
	for (NSDictionary *m in raw){
		if (![m[@"outgoing"] boolValue] && ![m[@"service"] boolValue] &&
			[m[@"id"] longLongValue] > self.readInboxAtOpen){
			self.unreadFromId = [m[@"id"] longLongValue];
			return;
		}
	}
}

- (NSInteger)unreadSeparatorRow {
	for (NSUInteger i = 0; i < self.messages.count; i++)
		if ([self.messages[i][@"separator"] isEqualToString:@"unread"])
			return (NSInteger)i;
	return NSNotFound;
}

#pragma mark - the bar over a chat nobody has spoken to

static const CGFloat kActionBarCloseSide = 44.0f;

/// The chat dict row of the open chat, read fresh: the bar follows the chat,
/// so its kind and words are re-derived on every pass rather than stored.
- (NSDictionary *)actionBarRow {
	for (NSDictionary *chat in [TGClient shared].chats)
		if ([chat[@"id"] longLongValue] == self.chatId)
			return chat;
	return nil;
}

/// The bar Telegram puts over a chat the account has never spoken to: report
/// spam over a stranger, add to contacts, share a phone number. It rides the
/// composer the way the reply banner does, and the X is not a hiding - it is
/// the removeChatActionBar request.
- (void)refreshActionBar {
	NSString *kind = [self actionBarRow][@"actionBarKind"] ?: @"";
	if (!kind.length){
		if (self.actionBarView && !self.actionBarView.hidden){
			self.actionBarView.hidden = YES;
			[self layoutChrome];
		}
		return;
	}

	if (!self.actionBarView){
		UIView *bar = [[UIView alloc] init];
		bar.backgroundColor = [[TGTheme shared] inputBarColour];
		bar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
							   UIViewAutoresizingFlexibleTopMargin;

		UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
				self.view.bounds.size.width, TGMetricBorderWidth)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[bar addSubview:hair];

		UILabel *say = [[UILabel alloc] init];
		say.font = TGFontCaption();
		say.textColor = [[TGTheme shared] secondaryTextColour];
		say.backgroundColor = [UIColor clearColor];
		self.actionBarLabel = say;
		[bar addSubview:say];

		TGTheme *theme = [TGTheme shared];

		UIButton *primary = [UIButton buttonWithType:UIButtonTypeCustom];
		primary.titleLabel.font = TGFontCaptionStrong();
		primary.tag = 1;
		[primary setTitleColor:[theme accentColour] forState:UIControlStateNormal];
		[primary addTarget:self action:@selector(actionBarPrimaryTapped)
			  forControlEvents:UIControlEventTouchUpInside];
		[bar addSubview:primary];

		UIButton *secondary = [UIButton buttonWithType:UIButtonTypeCustom];
		secondary.titleLabel.font = TGFontCaptionStrong();
		secondary.tag = 2;
		secondary.hidden = YES;
		[secondary setTitleColor:[theme accentColour] forState:UIControlStateNormal];
		[secondary addTarget:self action:@selector(actionBarSecondaryTapped)
			forControlEvents:UIControlEventTouchUpInside];
		[bar addSubview:secondary];

		UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
		close.tag = 9;
		[close setImage:[TGIcons glyphNamed:@"close"
									 colour:[theme secondaryTextColour]
									   side:kBannerCloseGlyph]
				forState:UIControlStateNormal];
		[close addTarget:self action:@selector(actionBarClosed)
			forControlEvents:UIControlEventTouchUpInside];
		[bar addSubview:close];

		self.actionBarView = bar;
		[self.view addSubview:bar];
	}

	NSString *say = nil;
	NSString *primary = nil;
	NSString *secondary = nil;
	NSString *who = self.chatTitle ?: @"";
	if ([kind isEqualToString:@"chatActionBarReportAddBlock"]){
		NSString *name = [self actionBarRow][@"actionBarAccount"][@"name"];
		say = [name length] ? [NSString stringWithFormat:@"%@ is nobody you know.", name]
							: @"Report spam and block?";
		primary = @"Report";
		secondary = @"Block";
	}
	else if ([kind isEqualToString:@"chatActionBarReportSpam"]){
		say = [NSString stringWithFormat:@"Report spam from %@?", who ?: @"this chat"];
		primary = @"Report";
	}
	else if ([kind isEqualToString:@"chatActionBarAddContact"]){
		say = [NSString stringWithFormat:@"%@ is not in your contacts.", who ?: @"This account"];
		primary = @"Add Contact";
	}
	else if ([kind isEqualToString:@"chatActionBarSharePhoneNumber"]){
		say = @"Share your phone number with them?";
		primary = @"Share";
	}
	else if ([kind isEqualToString:@"chatActionBarInviteMembers"]){
		say = [NSString stringWithFormat:@"%@ takes people.", who ?: @"This chat"];
		primary = @"Add";
	}
	else if ([kind isEqualToString:@"chatActionBarJoinRequest"]){
		NSString *title = [self actionBarRow][@"actionBarText"];
		say = [title length] ? title : @"They have asked to join.";
	}
	else {
		// A kind this app has no action for still deserves the words it was
		// handed: the bar lives so long as Telegram sends it.
		say = kind;
	}

	self.actionBarLabel.text = say;
	self.actionBarView.hidden = NO;
	[self positionActionBarButtons:primary secondary:secondary];
	[self layoutChrome];
}

/// The buttons hang from the right, the X outermost; the label keeps what is
/// left of them. buttonTitle nil hides it.
- (void)positionActionBarButtons:(NSString *)primaryTitle secondary:(NSString *)secondaryTitle {
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = kComposeBannerHeight;

	UIButton *close = nil;
	UIButton *primary = nil;
	UIButton *secondary = nil;
	for (UIView *sub in self.actionBarView.subviews)
		if ([sub isKindOfClass:[UIButton class]]){
			UIButton *button = (UIButton *)sub;
			if (button.tag == 9)      close = button;
			else if (button.tag == 1) primary = button;
			else if (button.tag == 2) secondary = button;
		}

	CGFloat x = width;
	close.frame = CGRectMake(x - kActionBarCloseSide, 0,
			kActionBarCloseSide, height);
	x -= kActionBarCloseSide;
	if (!x) return;

	for (UIButton *button in (@[primary, secondary])){
		NSString *title = (button == primary ? primaryTitle : secondaryTitle) ?: @"";
		if (!title.length){
			button.hidden = YES;
			continue;
		}
		button.hidden = NO;
		[button setTitle:title forState:UIControlStateNormal];
		CGFloat textWidth = button.titleLabel.text.length
			? [button.titleLabel.text sizeWithAttributes:
				@{NSFontAttributeName: button.titleLabel.font ?: TGFontCaptionStrong()}].width
			: TGMetricRow;
		CGFloat side = MAX(TGMetricRow, textWidth) + TGMetricPadWide;   // TGMetricPad on either side
		button.frame = CGRectMake(x - side, 0, side, height);
		x -= side;
	}

	self.actionBarLabel.frame = CGRectMake(TGHalf(TGMetricGutter),
			TGCenteredOrigin(height, TGMetricLineSubhead),
			x - TGMetricGutter, TGMetricLineSubhead);
}

- (void)actionBarClosed {
	// Not a hiding: Telegram keeps offering the bar until it is told no.
	NSString *kind = [self actionBarRow][@"actionBarKind"] ?: @"";
	if (kind.length)
		[[TGClient shared] removeActionBarInChat:self.chatId];
	[self refreshActionBar];
	// The dictionary still holds the kind until the update lands; say so
	// locally too, because the bar must not sit over an already-dismissed one.
	for (NSDictionary *chat in [TGClient shared].chats)
		if ([chat[@"id"] longLongValue] == self.chatId){
			[self refreshActionBar];
			break;
		}
}

/// Straight answers only: the reasons reportChat hands back are looked at,
/// and the spam one is what a bar is for - asked about first, sent after.
- (void)actionBarPrimaryTapped {
	NSString *kind = [self actionBarRow][@"actionBarKind"] ?: @"";
	if ([kind isEqualToString:@"chatActionBarAddContact"]){
		[self pushNewContactFromActionBar];
		return;
	}
	if ([kind isEqualToString:@"chatActionBarInviteMembers"]){
		TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
		contacts.addingToChatId = self.chatId;
		self.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:contacts animated:YES];
		return;
	}
	if ([kind isEqualToString:@"chatActionBarSharePhoneNumber"]){
		NSString *who = self.chatTitle ?: @"them";
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:[NSString stringWithFormat:@"%@ will see your phone number.", who]
							title:@"Share" action:@"Share" destructive:NO
						   inView:self.view
						onConfirm:^{
			int64_t userId = weakSelf.isGroup ? 0 : weakSelf.chatId;
			[[TGClient shared] sharePhoneNumberWithUser:userId];
		}];
		return;
	}
	// A report of either kind. The reasons are one round trip; the bar's
	// report is the spam reason, which Telegram names among the options.
	NSString *who = self.chatTitle ?: @"this chat";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:@"Report spam from %@?", who]
						title:@"Report" action:@"Report" destructive:NO
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] reportChat:weakSelf.chatId
							   optionId:nil
								  text:@""
							completion:^(NSString *title, NSArray *options, BOOL done){
			TGChatViewController *me = weakSelf;
			if (!me)
				return;
			NSString *spamOption = nil;
			for (NSDictionary *option in options)
				if ([[option[@"text"] lowercaseString]
						rangeOfString:@"spam"].location != NSNotFound){
					spamOption = option[@"id"];
					break;
				}
			if (!spamOption){
				[TGAlertSheet showMessage:@"This report needs a reason this app "
										  @"cannot ask for yet."
									title:@"Report" inView:me.view];
				return;
			}
			[[TGClient shared] reportChat:me.chatId optionId:spamOption text:@""
							   completion:^(NSString *t, NSArray *o, BOOL d){
				if (d && weakSelf)
					[weakSelf actionBarClosed];
			}];
		}];
	}];
}

- (void)actionBarSecondaryTapped {
	int64_t userId = self.isGroup ? 0 : self.chatId;
	if (!userId)
		return;
	NSString *who = self.chatTitle ?: @"this user";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:@"Block %@?", who]
						title:@"Block" action:@"Block" destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] blockUserWithUserId:userId];
		[weakSelf actionBarClosed];
	}];
}

/// A new contact out of the bar: the name Telegram handed over as the account
/// info is where the form starts, and the chat id is who it names.
- (void)pushNewContactFromActionBar {
	NSDictionary *account = [self actionBarRow][@"actionBarAccount"];
	TGNewContactViewController *form = [[TGNewContactViewController alloc] init];
	form.first = account[@"name"] ?: @"first";
	if (!account)
		form.first = self.chatTitle ?: @"";
	else {
		NSString *name = account[@"name"];
		NSString *first = [name componentsSeparatedByString:@" "].firstObject;
		NSString *last = name.length ? [name substringFromIndex:MIN((NSUInteger)first.length + 1, name.length)] : @"";
		form.first = first ?: @"";
		form.last  = last ?: @"";
		form.phone = account[@"phone"];
	}
	form.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:form animated:YES];
}

#pragma mark - floating date and jump button

- (void)buildChrome {
	TGTheme *theme = [TGTheme shared];

	self.floatingDate = [[UILabel alloc] init];
	self.floatingDate.font = TGFontCaptionStrong();
	self.floatingDate.textAlignment = NSTextAlignmentCenter;
	self.floatingDate.layer.cornerRadius = TGHalf(TGMetricFloatingDateHeight);
	self.floatingDate.clipsToBounds = YES;
	self.floatingDate.alpha = 0;
	self.floatingDate.userInteractionEnabled = NO;
	[self.view addSubview:self.floatingDate];

	self.jumpButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.jumpButton.frame = CGRectMake(0, 0, kJumpSide, kJumpSide);
	self.jumpButton.layer.cornerRadius = TGHalf(kJumpSide);
	self.jumpButton.layer.shadowColor = [UIColor blackColor].CGColor;
	self.jumpButton.layer.shadowOpacity = TGMetricShadowButtonOpacity;
	self.jumpButton.layer.shadowRadius = TGMetricShadowButtonRadius;
	self.jumpButton.layer.shadowOffset = TGMetricShadowOffsetEtched;
	self.jumpButton.hidden = YES;
	[self.jumpButton addTarget:self action:@selector(jumpTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.jumpButton];

	self.jumpBadge = [[UILabel alloc] init];
	self.jumpBadge.font = TGFontMetaStrong();
	self.jumpBadge.textColor = [UIColor whiteColor];
	self.jumpBadge.textAlignment = NSTextAlignmentCenter;
	self.jumpBadge.layer.cornerRadius = TGHalf(TGMetricJumpBadgeHeight);
	self.jumpBadge.clipsToBounds = YES;
	self.jumpBadge.hidden = YES;
	[self.jumpButton addSubview:self.jumpBadge];

	[self applyChromeTheme:theme];
	[self layoutChrome];
}

/// A chevron pointing down, for the jump button.
static UIImage *TGJumpChevron(UIColor *colour) {
	CGSize size = CGSizeMake(TGMetricStampTicksRoom, kTicksDrawnHeight);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
	CGContextSetLineWidth(ctx, TGMetricBorderThick);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextMoveToPoint(ctx, 2, 2);
	CGContextAddLineToPoint(ctx, 9, 9);
	CGContextAddLineToPoint(ctx, 16, 2);
	CGContextStrokePath(ctx);
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (void)applyChromeTheme:(TGTheme *)theme {
	self.floatingDate.backgroundColor = [theme serviceBubbleColour];
	self.floatingDate.textColor = [theme serviceTextColour];
	self.jumpButton.backgroundColor = [theme inputBarColour];
	[self.jumpButton setImage:TGJumpChevron([theme secondaryTextColour]) forState:UIControlStateNormal];
	self.jumpBadge.backgroundColor = [theme badgeColour];

	if (self.actionBarView){
		self.actionBarView.backgroundColor = [theme inputBarColour];
		self.actionBarLabel.textColor = [theme secondaryTextColour];
		for (UIView *sub in self.actionBarView.subviews){
			if ([sub isKindOfClass:[UIButton class]]){
				UIButton *button = (UIButton *)sub;
				[button setTitleColor:[theme accentColour] forState:UIControlStateNormal];
				if (button.tag == 9)
					[button setImage:[TGIcons glyphNamed:@"close"
												  colour:[theme secondaryTextColour]
													side:kBannerCloseGlyph]
							forState:UIControlStateNormal];
			}
		}
	}
}

/// Both hang off the table's frame, which moves with the keyboard and the
/// panel; called from wherever that frame changes.
- (void)layoutChrome {
	CGRect table = self.table.frame;
	// Clear of the reply / edit strip when one is showing over the table. The
	// strip rides directly on the composer, so it has to be placed here rather
	// than where it was built: the keyboard moves the bar out from under it.
	CGFloat bottom = CGRectGetMaxY(table);
	if (self.composeBanner && !self.composeBanner.hidden){
		self.composeBanner.frame = CGRectMake(0,
				CGRectGetMinY(self.inputBar.frame) - kComposeBannerHeight,
				self.view.bounds.size.width, kComposeBannerHeight);
		[self.view bringSubviewToFront:self.composeBanner];
		bottom = MIN(bottom, CGRectGetMinY(self.composeBanner.frame));
	}
	self.jumpButton.frame = CGRectMake(CGRectGetMaxX(table) - kJumpSide - TGMetricJumpMarginRight,
									   bottom - kJumpSide - TGMetricJumpMarginBottom, kJumpSide, kJumpSide);
	CGSize badge = [self.jumpBadge sizeThatFits:CGSizeMake(kJumpBadgeMaxW,
			TGMetricJumpBadgeHeight)];
	CGFloat bw = MAX(18, ceilf(badge.width) + TGMetricPadMedium);
	self.jumpBadge.frame = CGRectMake(TGCenteredOrigin(kJumpSide, bw),
			TGMetricBadgeOffsetTop, bw, TGMetricJumpBadgeHeight);
	// The badge pokes out above the button.
	self.jumpButton.clipsToBounds = NO;

	CGSize date = [self.floatingDate sizeThatFits:CGSizeMake(table.size.width,
			TGMetricFloatingDateHeight)];
	CGFloat dw = ceilf(date.width) + TGMetricPadWide;
	CGFloat top = self.pinnedBannerView.hidden || !self.pinnedBannerView ? TGMetricZero : CGRectGetMaxY(self.pinnedBannerView.frame);
	self.floatingDate.frame = CGRectMake(TGCenteredOrigin(table.size.width, dw), top + TGMetricFloatingDateTopOffset, dw,
			TGMetricFloatingDateHeight);
}

- (BOOL)isNearBottom {
	UIScrollView *s = self.table;
	CGFloat fromBottom = s.contentSize.height - (s.contentOffset.y + s.bounds.size.height);
	return fromBottom < TGHalf(s.bounds.size.height);
}

- (void)updateJumpButton {
	BOOL show = ![self isNearBottom] && self.messages.count > 0;
	if (show == !self.jumpButton.hidden)
		return;
	if (show){
		self.jumpButton.hidden = NO;
		self.jumpButton.alpha = 0;
	}
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.jumpButton.alpha = show ? 1 : 0;
	} completion:^(BOOL finished){
		if (!show){
			self.jumpButton.hidden = YES;
			self.newWhileAway = 0;
			self.jumpBadge.hidden = YES;
		}
	}];
}

- (void)noteArrivedWhileAway {
	self.newWhileAway++;
	self.jumpBadge.text = [NSString stringWithFormat:@"%ld", (long)self.newWhileAway];
	self.jumpBadge.hidden = NO;
	[self layoutChrome];
}

- (void)jumpTapped {
	self.newWhileAway = 0;
	self.jumpBadge.hidden = YES;
	[self scrollToBottomAnimated:YES];
}

- (void)updateFloatingDate {
	NSArray *visible = [self.table indexPathsForVisibleRows];
	if (!visible.count)
		return;
	NSIndexPath *first = visible.firstObject;
	for (NSIndexPath *path in visible)
		if (path.row < first.row)
			first = path;
	if (first.row >= (NSInteger)self.messages.count)
		return;
	NSTimeInterval stamp = [self.messages[first.row][@"date"] doubleValue];
	if (stamp <= 0)
		return;
	NSString *title = TGDayTitle(stamp);
	if (![self.floatingDate.text isEqualToString:title]){
		self.floatingDate.text = title;
		[self layoutChrome];
	}
}

- (void)chromeDidScroll {
	[self updateJumpButton];
	if (self.table.isDragging || self.table.isDecelerating){
		[self updateFloatingDate];
		if (self.floatingDate.alpha < 1){
			[UIView animateWithDuration:TGAnimationDurationFast animations:^{ self.floatingDate.alpha = 1; }];
		}
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeFloatingDate) object:nil];
	}
}

- (void)chromeDidStopScrolling {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeFloatingDate) object:nil];
	[self performSelector:@selector(fadeFloatingDate) withObject:nil afterDelay:1.0];
}

- (void)fadeFloatingDate {
	[UIView animateWithDuration:TGAnimationDurationSlow animations:^{ self.floatingDate.alpha = 0; }];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (scrollView == self.table && !decelerate)
		[self chromeDidStopScrolling];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	if (scrollView == self.table)
		[self chromeDidStopScrolling];
}

#pragma mark - swipe to reply

static const CGFloat kReplyPull = TGMetricReplyPull;   // how far a bubble travels before it counts

- (void)installSwipeToReply {
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(replyPan:)];
	pan.delegate = self;
	[self.table addGestureRecognizer:pan];
	// Vertical drags must still scroll at once; this one decides within a
	// few points whether it is horizontal and gives up otherwise.
	if ([self.table respondsToSelector:@selector(panGestureRecognizer)])
		[self.table.panGestureRecognizer requireGestureRecognizerToFail:pan];
	self.replyPanRecognizer = pan;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
	if (gesture != self.replyPanRecognizer)
		return YES;
	if (self.isEditingMessages)
		return NO;
	UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gesture;
	CGPoint v = [pan velocityInView:self.table];
	if (v.x >= 0 || fabs(v.x) < fabs(v.y) * TGDampingReplySwipeSlope)
		return NO;
	NSIndexPath *path = [self.table indexPathForRowAtPoint:[pan locationInView:self.table]];
	if (!path || path.row >= (NSInteger)self.messages.count)
		return NO;
	NSDictionary *m = self.messages[path.row];
	return ![m[@"service"] boolValue] && [m[@"id"] longLongValue] != 0;
}

- (void)replyPan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan){
		NSIndexPath *path = [self.table indexPathForRowAtPoint:[pan locationInView:self.table]];
		UITableViewCell *cell = path ? [self.table cellForRowAtIndexPath:path] : nil;
		if (!cell)
			return;
		self.replySwipeCell = cell;
		self.replySwipeRow = path.row;

		if (!self.replyHint){
			CGFloat side = 30;
			self.replyHint = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
			self.replyHint.layer.cornerRadius = TGHalf(side);
			self.replyHint.contentMode = UIViewContentModeCenter;
		}
		TGTheme *theme = [TGTheme shared];
		self.replyHint.backgroundColor = [theme serviceBubbleColour];
		self.replyHint.image = [TGIcons glyphNamed:@"reply" colour:[theme serviceTextColour]
										  side:kReplyHintGlyph];
		self.replyHint.alpha = TGAlphaTransparent;
		self.replyHint.center = CGPointMake(cell.bounds.size.width - kReplyHintInset,
			TGHalf(cell.bounds.size.height));
		[cell addSubview:self.replyHint];
		return;
	}

	UITableViewCell *cell = self.replySwipeCell;
	if (!cell)
		return;
	CGFloat dx = MIN(0, [pan translationInView:self.table].x);
	// Past the threshold it resists, the way theirs does.
	CGFloat shown = dx > -kReplyPull ? dx : -kReplyPull + (dx + kReplyPull) * TGDampingRubberband;

	if (pan.state == UIGestureRecognizerStateChanged){
		cell.contentView.transform = CGAffineTransformMakeTranslation(shown, 0);
		self.replyHint.alpha = MIN(1, -dx / kReplyPull);
		CGFloat scale = TGTransformScaleReplyMin + TGTransformScaleReplyRange * self.replyHint.alpha;
		self.replyHint.transform = CGAffineTransformMakeScale(scale, scale);
		return;
	}

	BOOL commit = pan.state == UIGestureRecognizerStateEnded && dx <= -kReplyPull;
	NSInteger row = self.replySwipeRow;
	self.replySwipeCell = nil;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		cell.contentView.transform = CGAffineTransformIdentity;
		self.replyHint.alpha = 0;
	} completion:^(BOOL finished){
		[self.replyHint removeFromSuperview];
	}];
	if (commit && row < (NSInteger)self.messages.count){
		self.actionMessage = self.messages[row];
		[self runMessageAction:@"Reply"];
	}
}

#pragma mark - subtitle ownership

/// Whose phrase the header subtitle carries: the network state first, then
/// the typing dots, then the resting last-seen. B4: a chat opened offline
/// used to sit at its captured status and never say "Waiting for network".
- (void)titleSubtitleOwnerChanged:(NSNotification *)note {
	NSString *network = TGNetworkSubtitleForState(
			(NSInteger)[TGClient shared].connectionState, nil);
	if (network.length){
		self.networkSubtitle = network;
		self.titleSubtitleLabel.text = network;
		self.titleSubtitleLabel.textColor = [[TGTheme shared] barSubtitleColour];
		return;
	}

	NSString *was = self.networkSubtitle;
	self.networkSubtitle = nil;
	if (!was.length && note)
		return;   // nothing of ours to hand back
	if (!self.typingTimer){
		NSString *resting = self.restingSubtitle ?: @"";
		if (resting.length){
			self.titleSubtitleLabel.text = resting;
			self.titleSubtitleLabel.textColor = [[TGTheme shared] barSubtitleColour];
		}
	}
	// A live typing timer re-writes the line on its own tick.
}

#pragma mark - secret chats

/// A secret chat lives or dies by its state: "pending" until the other
/// device has answered the exchange, spent when closed. The state is the
/// resting subtitle, and an update mid-chat re-runs this line.
- (void)refreshSecretState {
	__weak typeof(self) weakSelf = self;
	NSInteger secretId = self.secretChatId;
	if (!secretId)
		return;
	[[TGClient shared] secretChatState:secretId completion:^(NSString *state, BOOL outgoing){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		NSString *resting = nil;
		if ([state isEqualToString:@"pending"]){
			// An incoming one waits for its owner to accept; the outgoing
			// one waits for the phone it was made with to come online.
			resting = outgoing ? @"Secret chat · waiting for them to come online"
							   : @"Secret chat · waiting for you to accept";
			me.inputBar.hidden = YES;
		} else if ([state isEqualToString:@"ready"]){
			resting = @"Secret chat · keys exchanged";
			me.inputBar.hidden = NO;
		} else if ([state isEqualToString:@"closed"]){
			resting = @"Secret chat · closed and gone when you leave";
			me.inputBar.hidden = YES;
		}
		me.restingSubtitle = resting ?: @"";
		[me titleSubtitleOwnerChanged:nil];
	}];
}

/// Holding the header of a secret chat offers ending it. On a plain chat
/// the hold does nothing, because the profile already has the row.
- (void)headerHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || !self.secretChatId)
		return;
	NSInteger secretId = self.secretChatId;
	int64_t chatId = self.chatId;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The keys are destroyed and the chat cannot be "
							  @"reopened. The messages on your phone stay."
						 title:@"Close Secret Chat"
						action:@"Close"
				   destructive:YES
						inView:self.navigationController.view ?: self.view
				   onConfirm:^{
		[[TGClient shared] closeSecretChat:secretId];
		// The chat turns empty rather than walking off the list, so the
		// screen does not pretend it is still what it was.
		[weakSelf.navigationController popViewControllerAnimated:YES];
		[[TGClient shared] closeChat:chatId];
	}];
}

#pragma mark - typing

- (void)showChatAction:(NSString *)action resting:(NSString *)resting {
	[self.typingTimer invalidate];
	self.typingTimer = nil;
	if (!action.length){
		self.titleSubtitleLabel.text = resting;
		self.titleSubtitleLabel.textColor = [[TGTheme shared] barSubtitleColour];
		return;
	}
	NSString *base = action;
	while ([base hasSuffix:@"."] || [base hasSuffix:@"…"])
		base = [base substringToIndex:base.length - 1];
	self.typingBase = base;
	self.typingStep = 0;
	self.titleSubtitleLabel.textColor = [[TGTheme shared] accentColour];
	[self typingTick];
	self.typingTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self
			selector:@selector(typingTick) userInfo:nil repeats:YES];
}

- (void)typingTick {
	NSString *dots = [@"..." substringToIndex:(NSUInteger)(self.typingStep % 4)];
	// Padded on the right so the word does not shift as the dots grow.
	NSString *pad = [@"   " substringToIndex:3 - dots.length];
	self.titleSubtitleLabel.text = [NSString stringWithFormat:@"%@%@%@", self.typingBase, dots, pad];
	self.typingStep++;
}

- (void)stopChrome {
	[self.typingTimer invalidate];
	self.typingTimer = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeFloatingDate) object:nil];
}

@end
