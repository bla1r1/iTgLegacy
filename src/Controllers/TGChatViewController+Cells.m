#import "TGChatViewControllerInternal.h"
#import <QuartzCore/QuartzCore.h>
#import "TGCapabilities.h"
#import "TGStyle.h"
#import "TGMusicPlayer.h"

@implementation TGChatViewController (Cells)

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGBubbleCell";
	TGBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	NSDictionary *m = self.messages[indexPath.row];
	BOOL mine = [m[@"outgoing"] boolValue];
	TGMessageLayout *layout = [self layoutForMessage:m atRow:indexPath.row];

	[cell resetForReuse];

	// 1. Service cells (service messages, separators, polls, docs, contacts, locations)
	if ([self configureServiceCell:cell message:m layout:layout isMine:mine indexPath:indexPath]) {
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// 2. Audio cells (calls, audio tracks, voice notes)
	if ([self configureAudioCell:cell message:m layout:layout isMine:mine indexPath:indexPath]) {
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// 3. Sender info for general bubbles
	int64_t senderId = [m[@"senderId"] longLongValue];
	if (layout.senderName.length) {
		cell.senderAvatar.hidden = NO;
		cell.senderAvatar.image = [self avatarForUser:senderId name:layout.senderName];
		cell.senderAvatar.frame = layout.senderAvatarFrame;

		cell.sender.hidden = NO;
		cell.sender.text = layout.senderName;
		cell.sender.textColor = TGSenderColour(senderId);
		cell.sender.frame = layout.senderFrame;
	}

	cell.bubble.frame = layout.bubbleFrame;

	TGTheme *theme = [TGTheme shared];
	UIColor *fill = mine ? [theme bubbleMineColour] : [theme bubbleTheirsColour];
	cell.bubble.backgroundColor = layout.isSticker ? [UIColor clearColor] : fill;

	cell.tail.hidden = YES;
	cell.bubble.layer.borderWidth = TGMetricBorderNone;
	cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	cell.body.textColor = [theme primaryTextColour];

	// 4. Round video notes or animated stickers
	if ([self configureRoundOrStickerCell:cell message:m layout:layout isMine:mine]) {
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// 5. Quote headers & replies
	cell.quoteBar.hidden = YES;
	cell.quote.hidden = YES;
	cell.quoteAuthor.hidden = YES;

	[self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];

	if (layout.quoteText) {
		cell.quoteBar.hidden = NO;
		cell.quoteBar.backgroundColor = [theme accentColour];
		cell.quoteBar.frame = layout.quoteBarFrame;

		cell.quoteAuthor.hidden = NO;
		cell.quoteAuthor.font = TGFontCaptionStrong();
		cell.quoteAuthor.textColor = [theme accentColour];
		cell.quoteAuthor.text = layout.quoteAuthor ?: @"Reply";
		cell.quoteAuthor.frame = layout.quoteAuthorFrame;

		cell.quote.hidden = NO;
		cell.quote.numberOfLines = 1;
		cell.quote.font = TGFontCaption();
		cell.quote.textColor = [theme primaryTextColour];
		cell.quote.text = layout.quoteText;
		cell.quote.frame = layout.quoteFrame;

		NSNumber *replyId = [m[@"replyId"] isKindOfClass:NSNumber.class]
				? m[@"replyId"] : nil;
		__weak typeof(self) weakCells = self;
		cell.onQuoteTapped = replyId ? ^{
			[weakCells jumpToReplyById:replyId.longLongValue];
		} : nil;
	}

	cell.mediaStamp.hidden = YES;

	// 6. Media thumbnails & photo albums
	[self configureMediaForCell:cell message:m layout:layout isMine:mine];

	// 7. Message body text
	cell.body.hidden = (layout.bodySize.height == 0 || layout.isSticker);
	cell.body.numberOfLines = 0;
	cell.body.lineBreakMode = NSLineBreakByWordWrapping;
	cell.body.font = TGFontAtSize([TGTheme shared].messageFontSize);
	NSArray *entities = m[@"entities"];
	if (entities.count) {
		cell.body.attributedText = TGAttributedMessageText(m[@"text"], entities, TGFontAtSize([TGTheme shared].messageFontSize), [theme primaryTextColour]);
	} else {
		TGSetBodyText(cell.body, m[@"text"], [theme primaryTextColour]);
	}
	cell.body.frame = layout.bodyFrame;

	__weak typeof(self) weakSelf = self;
	cell.onLinkTapped = ^(NSString *url) {
		[weakSelf handleOpenLink:url];
	};

	// 8. Reactions
	UILabel *reactions = (UILabel *)[cell.bubble viewWithTag:0x9002];
	NSString *reactionText = m[@"reactions"];
	if ([reactionText length]) {
		if (!reactions) {
			reactions = [[UILabel alloc] init];
			reactions.tag = 0x9002;
			reactions.font = TGFontCaption();
			[cell.bubble addSubview:reactions];
		}
		reactions.hidden = NO;
		reactions.text = reactionText;
		reactions.textColor = [theme secondaryTextColour];
		if (!theme.isFlat) {
			reactions.backgroundColor = [theme cardBackgroundColour];
			reactions.layer.cornerRadius = TGMetricCornerSmall;
			reactions.layer.borderWidth = 1.0f;
			reactions.layer.borderColor = [theme separatorColour].CGColor;
			reactions.clipsToBounds = YES;
		} else {
			reactions.backgroundColor = [UIColor clearColor];
			reactions.layer.borderWidth = 0.0f;
		}
		reactions.frame = CGRectMake(kPadH,
				layout.bodyFrame.origin.y + layout.bodySize.height + TGMetricPadTiny,
				layout.bubbleFrame.size.width - TGDoubled(kPadH), TGMetricLineCaption);
	} else {
		reactions.hidden = YES;
	}

	// 9. Time & delivery ticks
	BOOL onPicture = !cell.mediaStamp.hidden;
	cell.time.text = (onPicture || [self albumContinuesAfterRow:indexPath.row]) ? @"" : layout.stamp;
	cell.time.textColor = mine ? [theme timeMineColour] : [theme timeColour];
	cell.time.frame = layout.timeFrame;

	cell.ticks.hidden = !mine;
	if (mine && onPicture) {
		cell.ticks.image = [self ticksForMessage:m white:YES];
		cell.ticks.frame = CGRectMake(CGRectGetMaxX(cell.mediaStamp.frame) - TGMetricMediaStampCheckPhotoInset,
									  CGRectGetMidY(cell.mediaStamp.frame) - TGHalf(TGMetricTicksHeight),
									  TGMetricTicksWidth, TGMetricTicksHeight);
		[cell.bubble bringSubviewToFront:cell.ticks];
	} else if (mine) {
		cell.ticks.image = [self ticksForMessage:m white:NO];
		cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - TGMetricTicksWidth,
				layout.timeFrame.origin.y + TGCenteredOrigin(TGMetricStampHeight, TGMetricTicksHeight),
				TGMetricTicksWidth, TGMetricTicksHeight);
		[cell.bubble bringSubviewToFront:cell.ticks];
	}
	[cell.bubble bringSubviewToFront:cell.time];

	// 10. iOS 6 Skeuomorphic drop shadows & styling (no harsh shine split)
	if (!theme.isFlat && !layout.isService && !layout.isSticker && !layout.isRound) {
		cell.shineBar.hidden = YES;
		cell.shineGradientLayer.hidden = YES;

		if (mine) {
			cell.body.textColor = theme.isDarkStyle ? [UIColor whiteColor] : [theme primaryTextColour];
			cell.body.shadowColor = theme.isDarkStyle ? [theme navBarTextShadowColour] : [theme etchedTextShadowColour];
			cell.body.shadowOffset = theme.isDarkStyle ? CGSizeMake(0, -1.0f) : CGSizeMake(0, 1.0f);
			cell.time.textColor = [theme timeMineColour];
			cell.time.shadowColor = theme.isDarkStyle ? [theme navBarTextShadowColour] : [theme etchedTextShadowColour];
			cell.time.shadowOffset = theme.isDarkStyle ? CGSizeMake(0, -1.0f) : CGSizeMake(0, 1.0f);
		} else {
			cell.body.textColor = [theme primaryTextColour];
			cell.body.shadowColor = [theme etchedTextShadowColour];
			cell.body.shadowOffset = CGSizeMake(0, 1.0f);
			cell.time.textColor = [theme timeColour];
			cell.time.shadowColor = [theme etchedTextShadowColour];
			cell.time.shadowOffset = CGSizeMake(0, 1.0f);
		}
	} else {
		cell.shineBar.hidden = YES;
		cell.shineGradientLayer.hidden = YES;
		cell.body.shadowColor = nil;
		cell.body.shadowOffset = CGSizeZero;
		cell.time.shadowColor = nil;
		cell.time.shadowOffset = CGSizeZero;
	}

	return [self finalizeCell:cell message:m layout:layout isMine:mine];
}

#pragma mark - ticks

- (UIImage *)ticksForMessage:(NSDictionary *)m white:(BOOL)white {
	NSString *state = m[@"state"];
	if ([state isEqualToString:@"read"]) {
		return white ? [TGIcons ticksWhite:YES] : [TGIcons ticksColour:[[TGTheme shared] ticksColour] read:YES];
	}
	return white ? [TGIcons ticksWhite:NO] : [TGIcons ticksColour:[[TGTheme shared] ticksColour] read:NO];
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)tableCell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![tableCell isKindOfClass:TGBubbleCell.class]) return;
	TGBubbleCell *cell = (TGBubbleCell *)tableCell;
	[cell stopLoopingVideo];
}

#pragma mark - runs

static BOOL TGSameRun(NSDictionary *a, NSDictionary *b) {
	if (!a || !b)
		return NO;
	if ([a[@"service"] boolValue] || [b[@"service"] boolValue])
		return NO;
	if ([a[@"outgoing"] boolValue] != [b[@"outgoing"] boolValue])
		return NO;
	if ([a[@"senderId"] longLongValue] != [b[@"senderId"] longLongValue])
		return NO;
	return fabs([a[@"date"] doubleValue] - [b[@"date"] doubleValue]) < 300;
}

- (BOOL)runStartsAtRow:(NSInteger)row {
	if (row <= 0 || row >= (NSInteger)self.messages.count)
		return YES;
	return !TGSameRun(self.messages[row - 1], self.messages[row]);
}

- (BOOL)runEndsAtRow:(NSInteger)row {
	if (row < 0 || row + 1 >= (NSInteger)self.messages.count)
		return YES;
	return !TGSameRun(self.messages[row], self.messages[row + 1]);
}

- (CGFloat)runShiftAtRow:(NSInteger)row layout:(TGMessageLayout *)layout {
	if (layout.isService || fabs(layout.bubbleFrame.origin.y - TGMetricBubbleRowInset) > TGMetricEpsilon)
		return TGMetricZero;
	return ([self runStartsAtRow:row] ? TGMetricBubbleRunGapStart : TGMetricBubbleRunGapInner) - TGMetricBubbleRowInset;
}

- (CGFloat)runHeightChangeAtRow:(NSInteger)row layout:(TGMessageLayout *)layout {
	if (layout.isService || fabs(layout.bubbleFrame.origin.y - TGMetricBubbleRowInset) > TGMetricEpsilon)
		return TGMetricZero;
	CGFloat above = [self runStartsAtRow:row] ? TGMetricBubbleRunGapStart : TGMetricBubbleRunGapInner;
	CGFloat below = [self runEndsAtRow:row] ? TGMetricBubbleRunGapStart : TGMetricBubbleRunGapInner;
	return (above - TGMetricBubbleRowInset) + (below - TGMetricBubbleRowInset);
}

static const CGFloat kTailCurveSpan   = 12.0f;
static const CGFloat kTailCurveAnchor = 5.0f;
static const CGFloat kTailCurveLift   = 2.0f;
static const CGFloat kTailCurveWaist  = 6.0f;
static const CGFloat kTailCurveInBow  = 2.4f;
static const CGFloat kTailCurveOutBow = 3.6f;

static UIBezierPath *TGBubbleUnifiedPath(CGSize size, CGFloat tl, CGFloat tr, CGFloat br, CGFloat bl, BOOL hasTail, BOOL mine) {
	CGFloat cap = TGHalf(MIN(size.width, size.height));
	tl = MIN(tl, cap); tr = MIN(tr, cap); br = MIN(br, cap); bl = MIN(bl, cap);
	CGFloat w = size.width, h = size.height;
	CGFloat tw = kTailWidth;

	UIBezierPath *path = [UIBezierPath bezierPath];
	if (!hasTail) {
		[path moveToPoint:CGPointMake(tl, 0)];
		[path addLineToPoint:CGPointMake(w - tr, 0)];
		[path addArcWithCenter:CGPointMake(w - tr, tr) radius:tr startAngle:-M_PI_2 endAngle:0 clockwise:YES];
		[path addLineToPoint:CGPointMake(w, h - br)];
		[path addArcWithCenter:CGPointMake(w - br, h - br) radius:br startAngle:0 endAngle:M_PI_2 clockwise:YES];
		[path addLineToPoint:CGPointMake(bl, h)];
		[path addArcWithCenter:CGPointMake(bl, h - bl) radius:bl startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
		[path addLineToPoint:CGPointMake(0, tl)];
		[path addArcWithCenter:CGPointMake(tl, tl) radius:tl startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
		[path closePath];
		return path;
	}

	if (!mine) {
		CGFloat W = w + tw;
		[path moveToPoint:CGPointMake(tw + tl, 0)];
		[path addLineToPoint:CGPointMake(W - tr, 0)];
		[path addArcWithCenter:CGPointMake(W - tr, tr) radius:tr startAngle:-M_PI_2 endAngle:0 clockwise:YES];
		[path addLineToPoint:CGPointMake(W, h - br)];
		[path addArcWithCenter:CGPointMake(W - br, h - br) radius:br startAngle:0 endAngle:M_PI_2 clockwise:YES];
		[path addLineToPoint:CGPointMake(tw + kTailCurveSpan, h)];

		[path addCurveToPoint:CGPointMake(TGMetricZero, h)
				controlPoint1:CGPointMake(tw + kTailCurveAnchor, h)
				controlPoint2:CGPointMake(tw - kTailCurveOutBow, h - kTailCurveLift)];
		[path addCurveToPoint:CGPointMake(tw, h - kTailHeight)
				controlPoint1:CGPointMake(tw - kTailCurveInBow, h - kTailCurveWaist)
				controlPoint2:CGPointMake(tw, h - kTailHeight)];

		[path addLineToPoint:CGPointMake(tw, tl)];
		[path addArcWithCenter:CGPointMake(tw + tl, tl) radius:tl startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
		[path closePath];
	} else {
		[path moveToPoint:CGPointMake(tl, 0)];
		[path addLineToPoint:CGPointMake(w - tr, 0)];
		[path addArcWithCenter:CGPointMake(w - tr, tr) radius:tr startAngle:-M_PI_2 endAngle:0 clockwise:YES];
		[path addLineToPoint:CGPointMake(w, h - kTailHeight)];

		[path addCurveToPoint:CGPointMake(w + tw, h)
				controlPoint1:CGPointMake(w, h - kTailCurveWaist)
				controlPoint2:CGPointMake(w + kTailCurveOutBow, h - kTailCurveLift)];
		[path addCurveToPoint:CGPointMake(w - kTailCurveSpan, h)
				controlPoint1:CGPointMake(w, h)
				controlPoint2:CGPointMake(w - kTailCurveAnchor, h)];

		[path addLineToPoint:CGPointMake(bl, h)];
		[path addArcWithCenter:CGPointMake(bl, h - bl) radius:bl startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
		[path addLineToPoint:CGPointMake(0, tl)];
		[path addArcWithCenter:CGPointMake(tl, tl) radius:tl startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
		[path closePath];
	}
	return path;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)tableCell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![tableCell isKindOfClass:TGBubbleCell.class] || indexPath.row >= (NSInteger)self.messages.count)
		return;
	TGBubbleCell *cell = (TGBubbleCell *)tableCell;
	cell.bubble.layer.mask = nil;
	cell.tail.hidden = YES;

	NSDictionary *m = self.messages[indexPath.row];
	TGMessageLayout *layout = [self layoutForMessage:m atRow:indexPath.row];
	[self startGifIfWantedIn:cell message:m];
	NSInteger row = indexPath.row;
	BOOL first = [self runStartsAtRow:row];
	BOOL last = [self runEndsAtRow:row];

	CGFloat shift = [self runShiftAtRow:row layout:layout];
	if (shift != 0) {
		CGRect b = cell.bubble.frame;
		b.origin.y = layout.bubbleFrame.origin.y + shift;
		cell.bubble.frame = b;
		if (!cell.senderAvatar.hidden) {
			CGRect a = cell.senderAvatar.frame;
			a.origin.y = layout.senderAvatarFrame.origin.y + shift;
			cell.senderAvatar.frame = a;
		}
		if (!cell.checkbox.hidden) {
			CGRect c = cell.checkbox.frame;
			c.origin.y = CGRectGetMidY(b) - TGHalf(c.size.height);
			cell.checkbox.frame = c;
		}
	}

	if (!last && !cell.senderAvatar.hidden)
		cell.senderAvatar.hidden = YES;

	TGTheme *theme = [TGTheme shared];
	UIColor *fill = cell.bubble.backgroundColor;
	BOOL plain = !fill || CGColorGetAlpha(fill.CGColor) < TGAlphaEpsilon;
	if (plain || layout.isService || layout.isSticker || layout.isRound)
		return;

	BOOL mine = [m[@"outgoing"] boolValue];
	CGFloat big = [theme bubbleCornerRadius];
	CGFloat small = [theme bubbleJoinedCornerRadius];
	CGFloat top = first ? big : small;
	CGFloat bottom = small;
	CGSize size = cell.bubble.bounds.size;

	BOOL hasTail = last;
	CGFloat tl = mine ? big : top;
	CGFloat tr = mine ? top : big;
	CGFloat br = mine ? (hasTail ? 0 : bottom) : big;
	CGFloat bl = mine ? big : (hasTail ? 0 : bottom);

	CGRect layerFrame = cell.bubble.bounds;
	if (hasTail) {
		layerFrame = mine ? CGRectMake(0, 0, size.width + kTailWidth, size.height)
						  : CGRectMake(-kTailWidth, 0, size.width + kTailWidth, size.height);
	}

	UIBezierPath *path = TGBubbleUnifiedPath(size, tl, tr, br, bl, hasTail, mine);

	cell.bubble.clipsToBounds = NO;
	cell.bubble.layer.cornerRadius = 0;
	cell.bubble.layer.borderWidth = 0;
	cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;

	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.frame = layerFrame;
	mask.path = path.CGPath;
	cell.bubble.layer.mask = mask;

	cell.bubble.backgroundColor = [UIColor clearColor];
	cell.gradientLayer.hidden = NO;
	cell.gradientLayer.frame = layerFrame;
	cell.gradientLayer.colors = mine ? [theme skeuoBubbleMineGradientColours] : [theme skeuoBubbleTheirsGradientColours];

	cell.borderLayer.hidden = NO;
	cell.borderLayer.frame = layerFrame;
	cell.borderLayer.path = path.CGPath;
	cell.borderLayer.strokeColor = (mine ? [theme skeuoBubbleMineBorderColour] : [theme skeuoBubbleTheirsBorderColour]).CGColor;
	cell.borderLayer.lineWidth = 1.0f;
	cell.borderLayer.fillColor = [UIColor clearColor].CGColor;

	cell.shineBar.hidden = YES;
	cell.shineGradientLayer.hidden = YES;

	cell.tail.hidden = YES;
}

@end
