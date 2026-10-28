#import "TGChatViewControllerInternal.h"
#import <QuartzCore/QuartzCore.h>
#import "TGCapabilities.h"
#import "TGStyle.h"
#import "TGMusicPlayer.h"

/// The stamp in the corner of a bubble, in one place: where it sits and how
/// much room it leaves for the ticks beside it.
static void TGPlaceStamp(TGBubbleCell *cell, CGRect bubbleFrame,
						 CGFloat timeWidth, BOOL mine) {
	cell.time.frame = CGRectMake(
			bubbleFrame.size.width - timeWidth - kPadH,
			bubbleFrame.size.height - TGMetricStampBottomInset,
			timeWidth - (mine ? TGMetricStampTicksRoom : 0),
			TGMetricStampHeight);
}

/// The ticks in the corner of your own bubble, in one place. Three branches
/// put them at height-15, one at height-18 and one at a counted offset, so
/// the same two checkmarks sat at three heights depending on whether the
/// bubble held text, a file or a quote.
static void TGPlaceTicks(TGBubbleCell *cell, CGRect bubbleFrame) {
	// Centred on the clock's own line rather than measured up from the bottom
	// of the bubble on its own: the two insets were 17 and 18 against heights
	// of 12 and 9, which left the ticks two and a half points above the time
	// they belong to, and in a bubble whose height came out differently they
	// drifted apart further.
	CGFloat stampTop = bubbleFrame.size.height - TGMetricStampBottomInset;
	cell.ticks.frame = CGRectMake(
			bubbleFrame.size.width - kPadH - TGMetricTicksWidth,
			stampTop + TGCenteredOrigin(TGMetricStampHeight, TGMetricTicksHeight),
			TGMetricTicksWidth, TGMetricTicksHeight);
}

/// The title and the line under it, for every bubble that names something -
/// a call, a track, a contact, a place. Four branches wrote this pair out
/// with heights of 18/14, 19/16 and 18/16 and tops 20 or 21 apart, so a
/// document and a track beside each other did not line up.
static void TGPlaceTitleDetail(TGBubbleCell *cell, CGFloat x, CGFloat top,
							   CGFloat width) {
	cell.body.frame = CGRectMake(x, top + TGMetricBubbleTitleTop, width,
								 TGMetricBubbleTitleHeight);
	cell.subtitle.frame = CGRectMake(x, top + TGMetricBubbleDetailTop, width,
									 TGMetricBubbleDetailHeight);
}

@implementation TGChatViewController (Cells)

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGBubbleCell";
	TGBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	NSDictionary *m = self.messages[indexPath.row];
	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];
	TGMessageLayout *layout = [self layoutForMessage:m atRow:indexPath.row];

	[cell resetForReuse];

	// Service messages
	if (layout.isService) {
		TGTheme *serviceTheme = [TGTheme shared];
		NSString *who = m[@"separator"] ? nil : [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length ? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]] : (m[@"text"] ?: @"");

		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = [serviceTheme serviceBubbleColour];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.layer.cornerRadius = [serviceTheme bubbleCornerRadius];
		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontMeta();
		cell.body.textAlignment = NSTextAlignmentCenter;
		cell.body.textColor = [serviceTheme serviceTextColour];
		cell.body.text = line;
		cell.body.frame = layout.bodyFrame;
		if ([m[@"separator"] isEqualToString:@"unread"]) {
			cell.bubble.backgroundColor = [serviceTheme unreadSeparatorColour];
			cell.bubble.layer.cornerRadius = TGMetricCornerNone;
			cell.body.font = TGFontCaptionStrong();
			cell.body.textColor = [serviceTheme secondaryTextColour];
		} else if (m[@"separator"]) {
			cell.body.font = TGFontMetaStrong();
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	cell.body.textAlignment = NSTextAlignmentLeft;
	cell.bubble.layer.cornerRadius = [[TGTheme shared] bubbleCornerRadius];

	// Polls
	if (layout.isPoll) {
		TGTheme *pollTheme = [TGTheme shared];
		NSArray *options = m[@"pollOptions"];
		NSString *question = m[@"pollQuestion"] ?: @"Poll";
		BOOL closed = [m[@"pollClosed"] boolValue];

		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [pollTheme bubbleMineColour] : [pollTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [pollTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [pollTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [pollTheme bubbleCornerRadius];

		cell.body.hidden = NO;
		cell.body.numberOfLines = 0;
		cell.body.font = TGFontBodyStrong();
		cell.body.textColor = [pollTheme primaryTextColour];
		cell.body.text = question;
		CGSize qs = TGTextSize(question, cell.body.font, layout.bubbleFrame.size.width - TGDoubled(kPadH));
		cell.body.frame = CGRectMake(kPadH, kPadV, layout.bubbleFrame.size.width - TGDoubled(kPadH), qs.height);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontMeta();
		cell.subtitle.textColor = [pollTheme secondaryTextColour];
		cell.subtitle.text = closed ? @"Final results"
			: [NSString stringWithFormat:@"%@ voted",
					[m[@"pollTotal"] integerValue] == 0 ? @"Nobody" : m[@"pollTotal"]];
		cell.subtitle.frame = CGRectMake(kPadH, kPadV + qs.height + TGMetricPadTiny,
				layout.bubbleFrame.size.width - TGDoubled(kPadH), TGMetricLineCaption);

		int64_t msgId = [m[@"id"] longLongValue];
		if (cell.pollMessageId != msgId) {
			for (UIView *old in [cell.bubble.subviews copy]) {
				if (old.tag >= 0x9100 && old.tag < 0x9200) [old removeFromSuperview];
			}
			cell.pollMessageId = msgId;

			CGFloat y = kPadV + qs.height + kPollVotedLine;
			for (NSUInteger i = 0; i < options.count; i++) {
				NSDictionary *option = options[i];
				BOOL chosen = [option[@"is_chosen"] boolValue];
				NSInteger share = [option[@"vote_percentage"] integerValue];

				UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
				row.frame = CGRectMake(kPadH, y, layout.bubbleFrame.size.width - TGDoubled(kPadH), kPollRow);
				row.tag = 0x9100 + (NSInteger)i;
				row.enabled = !closed;
				[row addTarget:self action:@selector(pollOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
				[cell.bubble addSubview:row];

				UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(TGMetricZero, TGCenteredOrigin(kPollRow, TGMetricPollDotSide),
						TGMetricPollDotSide, TGMetricPollDotSide)];
				dot.layer.cornerRadius = TGHalf(TGMetricPollDotSide);
				dot.layer.borderWidth = TGMetricBorderMedium;
				dot.layer.borderColor = [pollTheme accentColour].CGColor;
				dot.backgroundColor = chosen ? [pollTheme accentColour] : [UIColor clearColor];
				[row addSubview:dot];

				UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kPollTextColumn, TGMetricPadTiny,
						row.bounds.size.width - kPollTextColumn - kPollShareWidth - TGMetricPadTiny,
						TGMetricLineRow)];
				label.text = option[@"text"][@"text"] ?: option[@"text"] ?: @"";
				label.font = TGFontSubhead();
				label.textColor = [pollTheme primaryTextColour];
				label.backgroundColor = [UIColor clearColor];
				[row addSubview:label];

				UILabel *percent = [[UILabel alloc] initWithFrame:CGRectMake(row.bounds.size.width - kPollShareWidth, TGMetricPadTiny,
						kPollShareWidth, TGMetricLineRow)];
				percent.text = [NSString stringWithFormat:@"%ld%%", (long)share];
				percent.font = TGFontCaption();
				percent.textAlignment = NSTextAlignmentRight;
				percent.textColor = [pollTheme secondaryTextColour];
				percent.backgroundColor = [UIColor clearColor];
				[row addSubview:percent];

				UIView *track = [[UIView alloc] initWithFrame:CGRectMake(kPollTextColumn, kPollRow - kPollTrackDrop - kPollTrackHeight,
						row.bounds.size.width - kPollTextColumn, kPollTrackHeight)];
				track.backgroundColor = [pollTheme separatorColour];
				[row addSubview:track];

				UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(kPollTextColumn, kPollRow - kPollTrackDrop - kPollTrackHeight,
						(row.bounds.size.width - kPollTextColumn) * share / TGPercentFull,
						kPollTrackHeight)];
				fill.backgroundColor = [pollTheme accentColour];
				[row addSubview:fill];

				y += kPollRow;
			}
		}

		cell.picture.hidden = YES;
		cell.disc.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [pollTheme timeMineColour] : [pollTheme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame, layout.timeWidth, mine);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			TGPlaceTicks(cell, layout.bubbleFrame);
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Calls
	if (layout.isCall) {
		TGTheme *callTheme = [TGTheme shared];
		BOOL missed = [m[@"callState"] isEqualToString:@"missed"];
		NSString *line = m[@"text"] ?: @"Call";

		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [callTheme bubbleMineColour] : [callTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [callTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [callTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [callTheme bubbleCornerRadius];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons callArrowOutgoing:mine missed:missed];
		cell.disc.frame = CGRectMake(kPadH,
				fwd + TGCenteredOrigin(layout.bubbleFrame.size.height - fwd, kCallArrow),
				kCallArrow, kCallArrow);

		CGFloat rightBtnW = TGMetricCallControlSide;
		CGFloat textW = layout.bubbleFrame.size.width - kPadH - TGMetricBubbleDiscColumn
				- rightBtnW - TGMetricPadSmall;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontSubheadStrong();
		cell.body.textColor = missed ? [callTheme destructiveColour] : [callTheme primaryTextColour];
		cell.body.text = line;
		TGPlaceTitleDetail(cell, kPadH + TGMetricBubbleDiscColumn, fwd, textW);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontMeta();
		cell.subtitle.textColor = [callTheme secondaryTextColour];
		cell.subtitle.text = layout.stamp;


		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame =
				CGRectMake(layout.bubbleFrame.size.width - rightBtnW - TGMetricPadSmall,
						fwd + TGCenteredOrigin(layout.bubbleFrame.size.height - fwd, kCallButton),
						kCallButton, kCallButton);
		[cell.contactCallButton setImage:[TGIcons callArrowOutgoing:YES missed:NO] forState:UIControlStateNormal];
		[cell.contactCallButton setTitle:nil forState:UIControlStateNormal];
		cell.contactCallButton.tag = indexPath.row;
		[cell.contactCallButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactCallButton addTarget:self action:@selector(callCellButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.ticks.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// A track: album art, the title, who it is by, and how long - with the
	// arrow over the art saying whether this is the one playing. It used to
	// fall through to the document branch below, where a song looked like an
	// attachment and its cover, which TDLib sends, was never drawn at all.
	if (layout.isTrack) {
		TGTheme *cardTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour]
										   : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [cardTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [cardTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];

		CGFloat artY = fwd + TGCenteredOrigin(kTrackRow, kTrackArt) - TGMetricPadTiny;
		cell.artwork.hidden = NO;
		cell.artwork.frame = CGRectMake(kPadH, artY, kTrackArt, kTrackArt);
		UIImage *cover = [self artworkForTrack:m];
		cell.artwork.image = cover;
		// No cover is not an empty square: the tile colour stands in, the way
		// a file glyph's does.
		cell.artwork.backgroundColor = cover ? [UIColor clearColor]
											 : [cardTheme fileTileColour];

		BOOL isCurrent = [TGMusicPlayer shared].currentMessageId ==
						 [m[@"id"] longLongValue];
		cell.disc.hidden = NO;
		cell.disc.image = (isCurrent && [TGMusicPlayer shared].playing)
				? [TGIcons pause] : [TGIcons play];
		cell.disc.frame = CGRectMake(kPadH + TGCenteredOrigin(kTrackArt, kTrackDisc),
									 artY + TGCenteredOrigin(kTrackArt, kTrackDisc),
									 kTrackDisc, kTrackDisc);
		[cell.bubble bringSubviewToFront:cell.disc];

		CGFloat textX = kPadH + kTrackArt + TGMetricPadSmall + TGMetricPadTiny;
		// Never negative: a label given a negative width draws its whole text
		// anyway, straight out past the bubble it belongs to.
		CGFloat textW = MAX(layout.bubbleFrame.size.width - textX - kPadH, TGMetricZero);

		NSString *title = [m[@"audioTitle"] length] ? m[@"audioTitle"]
				: ([m[@"docName"] length] ? m[@"docName"] : @"Audio");
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontBodyStrong();
		cell.body.textColor = [cardTheme primaryTextColour];
		cell.body.text = title;
		TGPlaceTitleDetail(cell, textX, artY, textW);

		// The performer, or how long it is when there is none - a line that
		// says nothing is worse than a line that says the duration twice.
		NSInteger seconds = [m[@"duration"] integerValue];
		NSString *length = seconds > 0
				? [NSString stringWithFormat:@"%ld:%02ld",
						(long)(seconds / 60), (long)(seconds % 60)]
				: @"";
		NSString *performer = m[@"audioPerformer"];
		NSString *second = performer.length
				? (length.length ? [NSString stringWithFormat:@"%@ - %@",
						performer, length] : performer)
				: length;
		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontCaption();
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = second;


		cell.time.frame = layout.timeFrame;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Documents
	if (layout.isDoc) {
		NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
		NSString *first = lines.count ? lines[0] : @"";
		NSString *second = lines.count > 1 ? lines[1] : @"";

		TGTheme *cardTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour] : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [cardTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [cardTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];

		cell.icon.hidden = NO;
		CGFloat side = kFileTile;
		cell.icon.frame = CGRectMake(kPadH, fwd + kPadV + TGCenteredOrigin(kFileTile, side), side, side);
		cell.icon.text = @"";
		cell.icon.layer.cornerRadius = TGMetricCornerSmall;
		cell.icon.backgroundColor = [cardTheme fileTileColour];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons fileDiscOfSide:kFileDisc];
		cell.disc.frame = CGRectMake(kPadH + TGCenteredOrigin(kFileTile, kFileDisc),
									 fwd + kPadV + TGCenteredOrigin(kFileTile, kFileDisc),
									 kFileDisc, kFileDisc);
		[cell.bubble bringSubviewToFront:cell.disc];

		CGFloat textX = kPadH + side + kTileTextGap;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 2;
		cell.body.font = TGFontBody();
		cell.body.textColor = [cardTheme fileNameColour];
		cell.body.text = first;
		cell.body.frame = CGRectMake(textX, fwd + kPadV + TGMetricPad,
				layout.bubbleFrame.size.width - textX - kPadH, kFileNameBlock);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontCaption();
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = second;
		cell.subtitle.frame = CGRectMake(textX, fwd + kPadV + kFileMetaTop,
				layout.bubbleFrame.size.width - textX - kPadH, TGMetricLineSubhead);

		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [cardTheme timeMineColour] : [cardTheme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame, layout.timeWidth, mine);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			TGPlaceTicks(cell, layout.bubbleFrame);
		}
		cell.picture.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Contacts
	if (layout.isContact) {
		NSDictionary *contact = [m[@"contact"] isKindOfClass:NSDictionary.class] ? m[@"contact"] : nil;
		NSString *name = contact[@"name"];
		NSString *phone = contact[@"phoneNumber"];
		if (!name.length || !phone.length) {
			NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (!name.length && lines.count) name = lines[0];
			if (!phone.length && lines.count > 1) phone = lines[1];
		}
		if (!name.length) name = @"Contact";
		if (!phone.length) phone = @"";

		TGTheme *cardTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [cardTheme bubbleMineColour] : [cardTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [cardTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [cardTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [cardTheme bubbleCornerRadius];

		cell.icon.hidden = NO;
		CGFloat side = kContactDisc;
		cell.icon.frame = CGRectMake(kPadH, fwd + kContactDiscTop, side, side);
		NSString *initials = name.length ? [name substringToIndex:1] : @"?";
		NSArray *words = [name componentsSeparatedByString:@" "];
		if (words.count > 1 && [words[1] length])
			initials = [initials stringByAppendingString:[words[1] substringToIndex:1]];
		cell.icon.text = initials.uppercaseString;
		cell.icon.font = TGFontHeader();
		cell.icon.layer.cornerRadius = TGHalf(side);
		cell.icon.backgroundColor = [cardTheme mediaCircleColour];

		CGFloat textX = kPadH + side + kTileTextGap;
		CGFloat textW = layout.bubbleFrame.size.width - textX - kPadH;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontBodyStrong();
		cell.body.textColor = [cardTheme primaryTextColour];
		cell.body.text = name;
		TGPlaceTitleDetail(cell, textX, fwd + TGMetricPadSmall, textW);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = TGFontCaption();
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = phone;


		CGFloat sepY = fwd + kContactButtons;
		cell.contactSeparatorH.hidden = NO;
		cell.contactSeparatorH.backgroundColor = [cardTheme separatorColour];
		cell.contactSeparatorH.frame = CGRectMake(TGMetricZero, sepY,
				layout.bubbleFrame.size.width, TGMetricHairline);

		CGFloat btnW = TGHalf(layout.bubbleFrame.size.width);
		cell.contactSeparatorV.hidden = NO;
		cell.contactSeparatorV.backgroundColor = [cardTheme separatorColour];
		cell.contactSeparatorV.frame = CGRectMake(btnW, sepY, TGMetricHairline, TGMetricButtonHeightSmall);

		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame = CGRectMake(TGMetricZero, sepY, btnW, TGMetricButtonHeightSmall);
		[cell.contactCallButton setTitleColor:[cardTheme accentColour] forState:UIControlStateNormal];
		[cell.contactCallButton setTitleColor:[cardTheme buttonHighlightColour] forState:UIControlStateHighlighted];
		cell.contactCallButton.tag = indexPath.row;
		[cell.contactCallButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactCallButton addTarget:self action:@selector(contactCallButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.contactAddButton.hidden = NO;
		cell.contactAddButton.frame = CGRectMake(btnW, sepY, btnW, TGMetricButtonHeightSmall);
		[cell.contactAddButton setTitleColor:[cardTheme accentColour] forState:UIControlStateNormal];
		[cell.contactAddButton setTitleColor:[cardTheme buttonHighlightColour] forState:UIControlStateHighlighted];
		cell.contactAddButton.tag = indexPath.row;
		[cell.contactAddButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactAddButton addTarget:self action:@selector(contactAddButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [cardTheme timeMineColour] : [cardTheme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame, layout.timeWidth, mine);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			TGPlaceTicks(cell, layout.bubbleFrame);
		}
		cell.picture.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Locations
	if (layout.isLocation) {
		TGTheme *locTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [locTheme bubbleMineColour] : [locTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = [locTheme bubbleBorderWidth];
		cell.bubble.layer.borderColor = [locTheme bubbleBorderColour].CGColor;
		cell.bubble.layer.cornerRadius = [locTheme bubbleCornerRadius];

		CGFloat mapW = layout.bubbleFrame.size.width;
		CGFloat mapH = TGMetricMapCardHeight;

		double lat = [m[@"lat"] doubleValue];
		double lon = [m[@"lon"] doubleValue];

		cell.picture.hidden = NO;
		cell.picture.frame = CGRectMake(TGMetricZero, fwd, mapW, mapH);
		cell.picture.clipsToBounds = YES;
		cell.picture.image = [self imageFor:m];

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = NO;
		cell.disc.image = [TGIcons mapPinBadge];
		cell.disc.frame = CGRectMake(TGCenteredOrigin(mapW, kMapPinWidth),
				fwd + TGCenteredOrigin(mapH, kMapPinHeight) - kMapPinLift,
				kMapPinWidth, kMapPinHeight);
		[cell.bubble bringSubviewToFront:cell.disc];

		cell.icon.hidden = NO;
		cell.icon.layer.cornerRadius = TGMetricCornerSmall;
		cell.icon.backgroundColor = [[TGTheme shared] mediaOverlayColour];
		cell.icon.textColor = [UIColor whiteColor];
		cell.icon.font = TGFontPlate();
		cell.icon.text = @" Apple Maps ";
		cell.icon.frame = CGRectMake(kMediaStampInset, fwd + mapH - TGMetricFloatingDateHeight,
				kMapCreditWidth, TGMetricLineCaption);
		[cell.bubble bringSubviewToFront:cell.icon];

		cell.mediaStamp.hidden = YES;

		NSDictionary *venue = [m[@"venue"] isKindOfClass:NSDictionary.class] ? m[@"venue"] : nil;
		NSString *vTitle = venue[@"title"];
		NSString *vAddr = venue[@"address"];
		if (!vTitle.length) {
			NSArray *lines = [m[@"text"] componentsSeparatedByString:@"\n"];
			if (lines.count > 1) {
				vTitle = lines[0];
				vAddr = lines[1];
			} else if (lines.count == 1 && ![lines[0] isEqualToString:@"Location"]) {
				vTitle = lines[0];
			}
		}

		// Prevent coordinates from appearing both in the title and in the subtitle
		BOOL titleIsCoords = NO;
		if (vTitle.length) {
			NSCharacterSet *coordChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789., -+°NSEWnsew"];
			if ([[vTitle stringByTrimmingCharactersInSet:coordChars] length] == 0 &&
				[vTitle rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound) {
				titleIsCoords = YES;
			}
		}
		if (titleIsCoords) {
			if (!vAddr.length) {
				vAddr = vTitle;
			}
			vTitle = @"Location";
		}

		if (!vTitle.length) vTitle = @"Location";
		if (!vAddr.length && !titleIsCoords) {
			vAddr = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];
		}
		if ([vTitle isEqualToString:vAddr]) {
			vAddr = @"";
		}

		CGFloat locTimeW = layout.timeWidth;
		CGFloat locTicks = mine ? TGMetricStampTicksRoom : TGMetricZero;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontSubheadStrong();
		cell.body.textColor = [locTheme primaryTextColour];
		cell.body.text = vTitle;

		if (vAddr.length > 0) {
			cell.subtitle.hidden = NO;
			cell.subtitle.numberOfLines = 1;
			cell.subtitle.font = TGFontMeta();
			cell.subtitle.textColor = [locTheme fileMetaColour];
			cell.subtitle.text = vAddr;
			TGPlaceTitleDetail(cell, kPadH, fwd + mapH + TGMetricPadTiny,
							   mapW - TGDoubled(kPadH));
			// Its second line stops short of the stamp in the corner.
			CGRect detail = cell.subtitle.frame;
			detail.size.width -= locTimeW + locTicks + TGMetricPadSmall;
			cell.subtitle.frame = detail;
		} else {
			cell.subtitle.hidden = YES;
			cell.subtitle.text = @"";
			cell.body.frame = CGRectMake(kPadH, fwd + mapH + TGMetricPadMedium,
					mapW - TGDoubled(kPadH) - locTimeW - locTicks - TGMetricPadSmall,
					TGMetricLineBody);
		}

		cell.time.hidden = NO;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [locTheme timeMineColour] : [locTheme timeColour];
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - locTimeW - locTicks - kPadH,
									 layout.bubbleFrame.size.height - TGMetricStampBottomInset,
									 locTimeW, TGMetricStampHeight);

		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - locTicks - kPadH + TGMetricPadTiny,
										  layout.bubbleFrame.size.height - TGMetricStampBottomInset
												  + TGMetricPadTiny,
										  TGMetricTicksWidth, TGMetricTicksHeight);
			[cell.bubble bringSubviewToFront:cell.ticks];
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// General bubble messages
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
	cell.bubble.layer.borderWidth = (layout.isSticker || layout.isRound) ? TGMetricBorderNone : [theme bubbleBorderWidth];
	cell.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	cell.body.textColor = [theme primaryTextColour];

	// Video note
	if (layout.isRound) {
		CGFloat side = layout.bubbleFrame.size.width;
		cell.bubble.backgroundColor = [theme fileTileColour];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.frame = layout.bubbleFrame;
		// Half of the side this view actually has, not half of the widest a
		// picture may be: a video note is 178 across, and asking for 100 drew
		// a rounded quadrilateral because CALayer here does not clamp.
		cell.bubble.layer.cornerRadius = TGHalf(side);
		cell.bubble.clipsToBounds = YES;
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.backgroundColor = [theme fileTileColour];
		cell.picture.frame = CGRectMake(TGMetricZero, TGMetricZero, side, side);
		cell.picture.layer.cornerRadius = TGHalf(side);
		cell.picture.clipsToBounds = YES;
		cell.body.hidden = YES;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		CGFloat disc = kVideoDisc;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.videoNotePlayer != nil);
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake(TGCenteredOrigin(side, disc), TGCenteredOrigin(side, disc), disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(videoNoteDiscTapped:)]];
		}
		NSInteger dur = [m[@"duration"] integerValue];
		NSString *durStr = (dur > 0) ? [NSString stringWithFormat:@"%ld:%02ld", (long)(dur / 60), (long)(dur % 60)] : @"";
		NSString *stamp = (layout.stamp.length && ![layout.stamp isEqualToString:@"(null)"]) ? layout.stamp : @"";

		// How long it runs belongs to the picture, so it rides inside the
		// circle; what time it was sent and whether it was read belong to the
		// message, so they sit outside it. They used to share one pill in the
		// middle of the circle, which read as the clock being part of the
		// video, and the ticks were clipped away by the circle's own curve.
		CGFloat stampW = TGTextSize(durStr, TGFontMicro(), 0).width + TGMetricPadLarge;
		cell.mediaStamp.hidden = !durStr.length;
		cell.mediaStamp.backgroundColor = [theme mediaStampColour];
		cell.mediaStamp.text = durStr;
		cell.mediaStamp.textAlignment = NSTextAlignmentCenter;
		cell.mediaStamp.frame = CGRectMake(TGCenteredOrigin(side, stampW),
										   side - TGMetricStampBottomInset - TGMetricPadSmall,
										   stampW, TGHalf(TGMetricRow) - TGMetricPadSmall);
		[cell.bubble bringSubviewToFront:cell.mediaStamp];

		// Under the circle, centred on it. The bubble clips to a circle, so
		// anything parented to it that leaves the disc is cut: the stamp line
		// is re-parented to the cell instead. One line - clock then ticks,
		// then the unheard dot for theirs - the way every other bubble reads,
		// rather than hanging out to the side or stacking the ticks wherever
		// the corner let them fit.
		CGRect frame = layout.bubbleFrame;
		CGFloat roundSide = CGRectGetWidth(frame);
		BOOL unplayedDot = !mine && [m[@"unplayed"] boolValue];
		CGFloat clockW = TGTextSize(stamp, TGFontMicro(), 0).width;
		CGFloat groupW = clockW + (mine ? TGMetricPadSmall + TGMetricTicksWidth : 0);
		if (unplayedDot)
			groupW += TGMetricPadSmall + TGMetricUnreadDotSide;
		CGFloat groupX = CGRectGetMinX(frame) + TGCenteredOrigin(roundSide, groupW);
		CGFloat clockY = CGRectGetMaxY(frame) + TGMetricPadSmall;

		[cell.contentView addSubview:cell.time];
		cell.time.hidden = !stamp.length;
		cell.time.text = stamp;
		cell.time.textColor = [theme timeColour];
		cell.time.textAlignment = NSTextAlignmentLeft;
		cell.time.frame = CGRectMake(groupX, clockY, clockW, TGMetricStampHeight);

		cell.ticks.hidden = !mine;
		if (mine) {
			[cell.contentView addSubview:cell.ticks];
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(
					groupX + clockW + TGMetricPadSmall,
					clockY + TGCenteredOrigin(TGMetricStampHeight, TGMetricTicksHeight),
					TGMetricTicksWidth, TGMetricTicksHeight);
		}

		// A round note nobody has opened gets the same dot a voice note does.
		cell.unreadDot.hidden = !unplayedDot;
		if (unplayedDot){
			cell.unreadDot.frame = CGRectMake(
					groupX + groupW + TGMetricPadSmall,
					clockY + TGCenteredOrigin(TGMetricStampHeight, TGMetricUnreadDotSide),
					TGMetricUnreadDotSide, TGMetricUnreadDotSide);
			cell.unreadDot.layer.cornerRadius = TGHalf(TGMetricUnreadDotSide);
			cell.unreadDot.backgroundColor = [theme accentColour];
		}

		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Animated sticker
	NSString *tgsPath = ([TGCapabilities canPlayAnimatedStickers] && [m[@"docName"] isEqualToString:@"tgs"]) ? self.lottiePaths[m[@"docId"]] : nil;
	if (tgsPath) {
		CGFloat side = kLottieSide;
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.frame = layout.bubbleFrame;
		cell.picture.hidden = YES;
		cell.body.hidden = YES;
		cell.lottie.hidden = NO;
		cell.lottie.frame = CGRectMake(TGMetricZero, TGMetricZero, side, side);
		[cell.lottie loadTGSFile:tgsPath];
		[cell.lottie play];

		static NSDateFormatter *hmt = nil;
		if (!hmt) { hmt = [[NSDateFormatter alloc] init]; [hmt setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [theme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame,
				TGTextSize(cell.time.text, TGFontMicro(), 0).width, NO);
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

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
	}

	cell.mediaStamp.hidden = YES;
	if (layout.isAlbum) {
		cell.collageView.hidden = NO;
		cell.collageView.frame = layout.collageFrame;
		cell.picture.hidden = YES;
		cell.picture.image = nil;

		NSArray *albumMsgs = m[@"albumMessages"];
		NSUInteger count = albumMsgs.count;
		NSArray *frames = layout.albumFrames;

		for (NSInteger i = 0; i < 4; i++) {
			UIImageView *iv = cell.collageViews[i];
			if (i < (NSInteger)frames.count && i < (NSInteger)count) {
				iv.hidden = NO;
				iv.frame = [frames[i] CGRectValue];
				NSDictionary *itemMsg = albumMsgs[i];
				iv.image = [self imageFor:itemMsg];
			} else {
				iv.hidden = YES;
				iv.image = nil;
			}
		}

		if (count > 4 && frames.count >= 4) {
			cell.collageMoreLabel.hidden = NO;
			cell.collageMoreLabel.frame = [frames[3] CGRectValue];
			cell.collageMoreLabel.text = [NSString stringWithFormat:@"+%ld", (long)(count - 3)];
			[cell.collageView bringSubviewToFront:cell.collageMoreLabel];
		} else {
			cell.collageMoreLabel.hidden = YES;
		}

		__weak typeof(self) weakSelf = self;
		cell.onCollageItemTapped = ^(NSInteger idx) {
			TGChatViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (idx >= 0 && idx < (NSInteger)albumMsgs.count) {
				NSDictionary *target = albumMsgs[idx];
				NSArray *pool = strongSelf.rawMessages.count ? strongSelf.rawMessages : albumMsgs;
				NSInteger targetIdx = [pool indexOfObject:target];
				if (targetIdx == NSNotFound) {
					pool = albumMsgs;
					targetIdx = idx;
				}
				[TGMediaViewer presentItems:pool
									startAt:targetIdx
									 inChat:strongSelf.chatId];
			}
		};

		if (!layout.bodySize.height) {
			cell.mediaStamp.hidden = NO;
			cell.mediaStamp.backgroundColor = [theme mediaStampColour];
			cell.mediaStamp.text = mine ? [NSString stringWithFormat:@"  %@", layout.stamp] : layout.stamp;
			cell.mediaStamp.textAlignment = mine ? NSTextAlignmentLeft : NSTextAlignmentCenter;
			cell.mediaStamp.frame = layout.mediaStampFrame;
			[cell.bubble bringSubviewToFront:cell.mediaStamp];
		}
	} else if (layout.picSize.height > 0) {
		cell.collageView.hidden = YES;
		cell.picture.hidden = NO;
		UIImage *img = [self imageFor:m];
		cell.picture.image = img;
		cell.picture.backgroundColor = (img || layout.isSticker) ? [UIColor clearColor] : [theme fileTileColour];
		cell.picture.frame = layout.pictureFrame;
		cell.picture.layer.cornerRadius = layout.isSticker ? TGMetricCornerNone : TGMetricCornerMedium;
		cell.picture.clipsToBounds = YES;

		cell.disc.hidden = ![kind isEqualToString:@"messageVideo"] && ![kind isEqualToString:@"messageAnimation"];
		if (!cell.disc.hidden) {
			CGFloat disc = kGifDisc;
			cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:NO];
			cell.disc.frame = CGRectMake(kPadH + TGCenteredOrigin(layout.picSize.width, disc),
										 layout.pictureFrame.origin.y + TGCenteredOrigin(layout.picSize.height, disc), disc, disc);
		}

		// A GIF that cannot loop here is still watchable - tapping it opens
		// the same MP4 in the viewer - so the corner says what it is and why
		// it is sitting still rather than leaving it looking like a broken
		// picture.
		if ([kind isEqualToString:@"messageAnimation"] && ![TGCapabilities canAutoplayGIFs]) {
			cell.icon.hidden = NO;
			cell.icon.layer.cornerRadius = TGMetricCornerSmall;
			cell.icon.clipsToBounds = YES;
			cell.icon.backgroundColor = [[TGTheme shared] mediaOverlayColour];
			cell.icon.textColor = [UIColor whiteColor];
			cell.icon.font = TGFontPlate();
			cell.icon.text = [TGCapabilities gifAutoplayWanted] ? @" GIF · tap to play "
																: @" GIF · autoplay off ";
			CGSize fits = [cell.icon sizeThatFits:CGSizeMake(layout.picSize.width, TGMetricLineCaption)];
			cell.icon.frame = CGRectMake(kPadH + kCaptionInset,
										 layout.pictureFrame.origin.y + kCaptionInset,
										 MIN(fits.width + TGMetricPad,
												 layout.picSize.width - TGDoubled(kCaptionInset)),
										 TGMetricLineCaption);
			[cell.bubble bringSubviewToFront:cell.icon];
		}

		if (!layout.bodySize.height) {
			cell.mediaStamp.hidden = NO;
			cell.mediaStamp.backgroundColor = [theme mediaStampColour];
			cell.mediaStamp.text = mine ? [NSString stringWithFormat:@"  %@", layout.stamp] : layout.stamp;
			cell.mediaStamp.textAlignment = mine ? NSTextAlignmentLeft : NSTextAlignmentCenter;
			cell.mediaStamp.frame = layout.mediaStampFrame;
			[cell.bubble bringSubviewToFront:cell.mediaStamp];
		}
	} else {
		cell.collageView.hidden = YES;
		cell.picture.hidden = YES;
		cell.picture.image = nil;
	}

	// Voice notes
	if (layout.isVoice) {
		TGTheme *voiceTheme = [TGTheme shared];
		CGFloat disc = kVoiceDisc;
		CGFloat left = kPadH + disc + TGMetricPad;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.voicePlayer && self.voicePlayer.playing);

		cell.voiceMessageId = [m[@"id"] longLongValue];
		cell.waveformData = m[@"waveform"];

		CGFloat fwd = layout.fwdHeight;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake(kPadH, fwd + TGCenteredOrigin(layout.bubbleFrame.size.height - fwd, disc), disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(voiceDiscTapped:)]];
		}

		// A voice note nobody has heard is drawn whole, as if it had already
		// played through; listening to it is what empties the bars. That is
		// Telegram's way of saying it is waiting for you.
		BOOL unplayed = !mine && [m[@"unplayed"] boolValue];

		cell.wave.hidden = NO;
		CGSize waveSize = CGSizeMake(layout.bubbleFrame.size.width - left - kPadH, kVoiceWaveHeight);
		cell.wave.image = [TGIcons waveform:m[@"waveform"]
									   size:waveSize
									 played:(isPlaying ? [self playedFraction]
													  : (unplayed ? 1.0f : 0))
									 colour:[voiceTheme accentColour]];
		cell.wave.frame = CGRectMake(left, fwd + kVoiceWaveTop, waveSize.width, waveSize.height);
		cell.wave.userInteractionEnabled = YES;
		if (!cell.wave.gestureRecognizers.count) {
			[cell.wave addGestureRecognizer:[[UIPanGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
			[cell.wave addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
		}

		NSInteger seconds = [m[@"duration"] integerValue];
		NSString *durText = [NSString stringWithFormat:@"%ld:%02ld",
				(long)(seconds / 60), (long)(seconds % 60)];
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = TGFontMeta();
		cell.body.textColor = [voiceTheme secondaryTextColour];
		cell.body.text = durText;
		// The label is as long as what it says, like every other stamp in
		// the app: a fixed 44pt wide one put "1:07" far right of its digits
		// and left the dot placement doing arithmetic - to cover for it.
		cell.body.frame = CGRectMake(left, layout.bubbleFrame.size.height - TGMetricLineRow,
				MAX(TGTextSize(durText, TGFontMeta(), 0).width, kVoiceClockMinimum), TGMetricLineMicro);

		// The dot sits just after the length, where Telegram puts it.
		cell.unreadDot.hidden = !unplayed;
		if (unplayed){
			CGRect inCell = [cell.contentView convertRect:cell.body.frame fromView:cell.bubble];
			cell.unreadDot.frame = CGRectMake(
					CGRectGetMinX(inCell) + TGTextSize(cell.body.text, cell.body.font, 0).width + TGMetricPadSmall,
					CGRectGetMinY(inCell) + TGCenteredOrigin(CGRectGetHeight(inCell), TGMetricUnreadDotSide),
					TGMetricUnreadDotSide, TGMetricUnreadDotSide);
			cell.unreadDot.layer.cornerRadius = TGHalf(TGMetricUnreadDotSide);
			cell.unreadDot.backgroundColor = [voiceTheme accentColour];
		}

		cell.picture.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [voiceTheme timeMineColour] : [voiceTheme timeColour];
		TGPlaceStamp(cell, layout.bubbleFrame, layout.timeWidth, mine);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			TGPlaceTicks(cell, layout.bubbleFrame);
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

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

	// Reactions
	UILabel *reactions = (UILabel *)[cell.bubble viewWithTag:0x9002];
	NSString *reactionText = m[@"reactions"];
	if ([reactionText length]) {
		if (!reactions) {
			reactions = [[UILabel alloc] init];
			reactions.tag = 0x9002;
			reactions.backgroundColor = [UIColor clearColor];
			reactions.font = TGFontCaption();
			[cell.bubble addSubview:reactions];
		}
		reactions.hidden = NO;
		reactions.text = reactionText;
		reactions.textColor = [theme secondaryTextColour];
		reactions.frame = CGRectMake(kPadH,
				layout.bodyFrame.origin.y + layout.bodySize.height + TGMetricPadTiny,
				layout.bubbleFrame.size.width - TGDoubled(kPadH), TGMetricLineCaption);
	} else {
		reactions.hidden = YES;
	}

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
				layout.timeFrame.origin.y + TGMetricPadTiny,
				TGMetricTicksWidth, TGMetricTicksHeight);
		[cell.bubble bringSubviewToFront:cell.ticks];
	}
	[cell.bubble bringSubviewToFront:cell.time];

	return [self finalizeCell:cell message:m layout:layout isMine:mine];
}

#pragma mark - ticks

/// Two ticks once the other side has read it, one until then.
- (UIImage *)ticksForMessage:(NSDictionary *)m white:(BOOL)white {
	// Saved Messages has no one on the other side to read it.
	BOOL read = self.chatId == [[TGClient shared] savedMessagesChatId] ||
				[m[@"id"] longLongValue] <= [[TGClient shared] lastReadOutboxForChat:self.chatId];
	UIColor *colour = white ? [UIColor whiteColor] : [[TGTheme shared] ticksColour];
	return [TGIcons ticksColour:colour read:read];
}

#pragma mark - GIFs

static const long long kGifAutoDownloadLimit = 3 * 1024 * 1024;

/// Loops a GIF in its bubble when the device can afford it: downloaded on
/// sight if small, and only so many playing at once.
- (void)startGifIfWantedIn:(TGBubbleCell *)cell message:(NSDictionary *)m {
	if (![m[@"kind"] isEqualToString:@"messageAnimation"] || cell.picture.hidden ||
		![TGCapabilities canAutoplayGIFs] || self.isEditingMessages){
		[cell stopLoopingVideo];
		return;
	}
	NSNumber *docId = [m[@"docId"] isKindOfClass:NSNumber.class] ? m[@"docId"] : nil;
	if (!docId)
		return;

	NSString *path = self.gifPaths[docId];
	if (path){
		NSUInteger playing = 0;
		for (UITableViewCell *visible in self.table.visibleCells)
			if (visible != cell && [visible isKindOfClass:TGBubbleCell.class] &&
				((TGBubbleCell *)visible).isPlayingLoop)
				playing++;
		if (playing >= [TGCapabilities maxConcurrentGIFs])
			return;
		[cell playLoopingVideoAtPath:path];
		cell.disc.hidden = YES;
		return;
	}

	long long size = [m[@"docSize"] longLongValue];
	if ([self.gifsRequested containsObject:docId] || size <= 0 || size > kGifAutoDownloadLimit)
		return;
	[self.gifsRequested addObject:docId];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:docId.integerValue completion:^(NSString *downloaded){
		TGChatViewController *me = weakSelf;
		if (!me || !downloaded.length)
			return;
		me.gifPaths[docId] = downloaded;
		[me reloadTableDebounced];
	}];
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)tableCell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([tableCell isKindOfClass:TGBubbleCell.class])
		[(TGBubbleCell *)tableCell stopLoopingVideo];
}

#pragma mark - runs

/// Two neighbours belong to one run - one block with a single tail - when the
/// same person sent them within a few minutes of each other.
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

/// How far a bubble moves from where its cached layout put it (3pt down) so
/// that bubbles of one run sit 2pt apart and runs 8pt apart. Zero for rows
/// that are not bubbles laid out at the top of their row.
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

/// A rounded box whose four corners can differ.
static UIBezierPath *TGBubblePath(CGSize size, CGFloat tl, CGFloat tr, CGFloat br, CGFloat bl) {
	CGFloat cap = TGHalf(MIN(size.width, size.height));
	tl = MIN(tl, cap); tr = MIN(tr, cap); br = MIN(br, cap); bl = MIN(bl, cap);
	CGFloat w = size.width, h = size.height;

	UIBezierPath *path = [UIBezierPath bezierPath];
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

/// Shapes the bubble by its place in the run: the outer corners stay round,
/// the ones facing a neighbour of the same run nearly square off, and only
/// the last bubble hangs a tail. Done here rather than in the layout because
/// a run changes as messages arrive while a cached layout does not; every
/// change to the list reloads the table, so this runs again each time.
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

	// The rhythm: positions are set from the layout each time, so this is
	// safe however often the cell is shown.
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

	// A group shows the sender's picture once, beside the tail.
	if (!last && !cell.senderAvatar.hidden)
		cell.senderAvatar.hidden = YES;

	TGTheme *theme = [TGTheme shared];
	UIColor *fill = cell.bubble.backgroundColor;
	BOOL plain = !fill || CGColorGetAlpha(fill.CGColor) < TGAlphaEpsilon;
	// A drawn border would be clipped by the mask, so the skeuomorphic style
	// keeps its plain rounded box; so do the things that are not bubbles.
	if (!theme.isFlat || [theme bubbleBorderWidth] > 0 || plain ||
		layout.isService || layout.isSticker || layout.isRound)
		return;

	BOOL mine = [m[@"outgoing"] boolValue];
	CGFloat big = [theme bubbleCornerRadius];
	CGFloat small = [theme bubbleJoinedCornerRadius];
	CGFloat top = first ? big : small;
	CGFloat bottom = last ? 0 : small;   // the tail takes the last one's corner
	CGSize size = cell.bubble.bounds.size;
	UIBezierPath *path = mine ? TGBubblePath(size, big, top, bottom, big)
							  : TGBubblePath(size, top, big, big, bottom);

	CAShapeLayer *mask = [CAShapeLayer layer];
	mask.frame = cell.bubble.bounds;
	mask.path = path.CGPath;
	cell.bubble.layer.cornerRadius = 0;
	cell.bubble.layer.mask = mask;

	if (last) {
		CGRect b = cell.bubble.frame;
		cell.tail.image = [TGIcons bubbleTailForColour:fill outgoing:mine];
		cell.tail.frame = CGRectMake(mine ? CGRectGetMaxX(b) : CGRectGetMinX(b) - kTailWidth,
									 CGRectGetMaxY(b) - kTailHeight, kTailWidth, kTailHeight);
		cell.tail.hidden = NO;
	}
}

@end
