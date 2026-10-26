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

static const CGFloat kJumpSide = TGMetricJumpSide;

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
	CGSize size = CGSizeMake(18, 11);
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
	CGSize badge = [self.jumpBadge sizeThatFits:CGSizeMake(60, 18)];
	CGFloat bw = MAX(18, ceilf(badge.width) + TGMetricPadMedium);
	self.jumpBadge.frame = CGRectMake(TGCenteredOrigin(kJumpSide, bw),
			TGMetricBadgeOffsetTop, bw, TGMetricJumpBadgeHeight);
	// The badge pokes out above the button.
	self.jumpButton.clipsToBounds = NO;

	CGSize date = [self.floatingDate sizeThatFits:CGSizeMake(table.size.width, 22)];
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
		self.replyHint.image = [TGIcons glyphNamed:@"reply" colour:[theme serviceTextColour] side:20];
		self.replyHint.alpha = TGAlphaTransparent;
		self.replyHint.center = CGPointMake(cell.bounds.size.width - 24, TGHalf(cell.bounds.size.height));
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
