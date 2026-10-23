#import "TGChatViewControllerInternal.h"
#import <QuartzCore/QuartzCore.h>
#import "TGCapabilities.h"

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
		NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length ? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]] : (m[@"text"] ?: @"");

		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = [serviceTheme serviceBubbleColour];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.layer.cornerRadius = 10.5f;
		cell.picture.hidden = YES;
		cell.time.text = @"";
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:12];
		cell.body.textAlignment = NSTextAlignmentCenter;
		cell.body.textColor = [serviceTheme serviceTextColour];
		cell.body.text = line;
		cell.body.frame = layout.bodyFrame;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	cell.body.textAlignment = NSTextAlignmentLeft;
	cell.bubble.layer.cornerRadius = 14;

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
		cell.body.font = [UIFont boldSystemFontOfSize:15];
		cell.body.textColor = [pollTheme primaryTextColour];
		cell.body.text = question;
		CGSize qs = TGTextSize(question, cell.body.font, layout.bubbleFrame.size.width - 2 * kPadH);
		cell.body.frame = CGRectMake(kPadH, kPadV, layout.bubbleFrame.size.width - 2 * kPadH, qs.height);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [pollTheme secondaryTextColour];
		cell.subtitle.text = closed ? @"Final results"
			: [NSString stringWithFormat:@"%@ voted",
					[m[@"pollTotal"] integerValue] == 0 ? @"Nobody" : m[@"pollTotal"]];
		cell.subtitle.frame = CGRectMake(kPadH, kPadV + qs.height + 2, layout.bubbleFrame.size.width - 2 * kPadH, 16);

		int64_t msgId = [m[@"id"] longLongValue];
		if (cell.pollMessageId != msgId) {
			for (UIView *old in [cell.bubble.subviews copy]) {
				if (old.tag >= 0x9100 && old.tag < 0x9200) [old removeFromSuperview];
			}
			cell.pollMessageId = msgId;

			CGFloat y = kPadV + qs.height + 22;
			for (NSUInteger i = 0; i < options.count; i++) {
				NSDictionary *option = options[i];
				BOOL chosen = [option[@"is_chosen"] boolValue];
				NSInteger share = [option[@"vote_percentage"] integerValue];

				UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
				row.frame = CGRectMake(kPadH, y, layout.bubbleFrame.size.width - 2 * kPadH, kPollRow);
				row.tag = 0x9100 + (NSInteger)i;
				row.enabled = !closed;
				[row addTarget:self action:@selector(pollOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
				[cell.bubble addSubview:row];

				UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 16, 16)];
				dot.layer.cornerRadius = 8;
				dot.layer.borderWidth = 1.5f;
				dot.layer.borderColor = [pollTheme accentColour].CGColor;
				dot.backgroundColor = chosen ? [pollTheme accentColour] : [UIColor clearColor];
				[row addSubview:dot];

				UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, 2, row.bounds.size.width - 66, 20)];
				label.text = option[@"text"][@"text"] ?: option[@"text"] ?: @"";
				label.font = [UIFont systemFontOfSize:14];
				label.textColor = [pollTheme primaryTextColour];
				label.backgroundColor = [UIColor clearColor];
				[row addSubview:label];

				UILabel *percent = [[UILabel alloc] initWithFrame:CGRectMake(row.bounds.size.width - 40, 2, 40, 20)];
				percent.text = [NSString stringWithFormat:@"%ld%%", (long)share];
				percent.font = [UIFont systemFontOfSize:13];
				percent.textAlignment = NSTextAlignmentRight;
				percent.textColor = [pollTheme secondaryTextColour];
				percent.backgroundColor = [UIColor clearColor];
				[row addSubview:percent];

				UIView *track = [[UIView alloc] initWithFrame:CGRectMake(24, kPollRow - 6, row.bounds.size.width - 24, 2)];
				track.backgroundColor = [pollTheme separatorColour];
				[row addSubview:track];

				UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(24, kPollRow - 6, (row.bounds.size.width - 24) * share / 100.0f, 2)];
				fill.backgroundColor = [pollTheme accentColour];
				[row addSubview:fill];

				y += kPollRow;
			}
		}

		cell.picture.hidden = YES;
		cell.disc.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [pollTheme timeMineColour] : [pollTheme timeColour];
		CGFloat pollTimeW = layout.timeWidth;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - pollTimeW - kPadH, layout.bubbleFrame.size.height - 17,
									 pollTimeW - (mine ? 18 : 0), 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.bubbleFrame.size.height - 15, 15, 9);
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
		cell.disc.frame = CGRectMake(kPadH, fwd + (layout.bubbleFrame.size.height - fwd - 16) / 2, 16, 16);

		CGFloat rightBtnW = 34.0f;
		CGFloat textW = layout.bubbleFrame.size.width - kPadH - 26 - rightBtnW - 4;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:14];
		cell.body.textColor = missed ? [callTheme destructiveColour] : [callTheme primaryTextColour];
		cell.body.text = line;
		cell.body.frame = CGRectMake(kPadH + 24, fwd + 6, textW, 18);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:12];
		cell.subtitle.textColor = [callTheme secondaryTextColour];
		cell.subtitle.text = layout.stamp;
		cell.subtitle.frame = CGRectMake(kPadH + 24, fwd + 26, textW, 14);

		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame = CGRectMake(layout.bubbleFrame.size.width - rightBtnW - 4, fwd + (layout.bubbleFrame.size.height - fwd - 32) / 2, 32, 32);
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
		cell.icon.frame = CGRectMake(kPadH, fwd + kPadV + (kFileTile - side) / 2, side, side);
		cell.icon.text = @"";
		cell.icon.layer.cornerRadius = 3;
		cell.icon.backgroundColor = [cardTheme fileTileColour];

		cell.disc.hidden = NO;
		cell.disc.image = [TGIcons fileDiscOfSide:kFileDisc];
		cell.disc.frame = CGRectMake(kPadH + (kFileTile - kFileDisc) / 2,
									 fwd + kPadV + (kFileTile - kFileDisc) / 2,
									 kFileDisc, kFileDisc);
		[cell.bubble bringSubviewToFront:cell.disc];

		CGFloat textX = kPadH + side + 10;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 2;
		cell.body.font = [UIFont systemFontOfSize:15];
		cell.body.textColor = [cardTheme fileNameColour];
		cell.body.text = first;
		cell.body.frame = CGRectMake(textX, fwd + kPadV + 8, layout.bubbleFrame.size.width - textX - kPadH, 38);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:13];
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = second;
		cell.subtitle.frame = CGRectMake(textX, fwd + kPadV + 46, layout.bubbleFrame.size.width - textX - kPadH, 17);

		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [cardTheme timeMineColour] : [cardTheme timeColour];
		CGFloat fileTimeW = layout.timeWidth;
		CGFloat fileTicks = mine ? 18 : 0;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - fileTimeW - kPadH, layout.bubbleFrame.size.height - 17,
									 fileTimeW - fileTicks, 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.bubbleFrame.size.height - 15, 15, 9);
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
		CGFloat side = 42;
		cell.icon.frame = CGRectMake(kPadH, fwd + 7, side, side);
		NSString *initials = name.length ? [name substringToIndex:1] : @"?";
		NSArray *words = [name componentsSeparatedByString:@" "];
		if (words.count > 1 && [words[1] length])
			initials = [initials stringByAppendingString:[words[1] substringToIndex:1]];
		cell.icon.text = initials.uppercaseString;
		cell.icon.font = [UIFont boldSystemFontOfSize:17];
		cell.icon.layer.cornerRadius = side / 2;
		cell.icon.backgroundColor = [cardTheme mediaCircleColour];

		CGFloat textX = kPadH + side + 10;
		CGFloat textW = layout.bubbleFrame.size.width - textX - kPadH;
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:15];
		cell.body.textColor = [cardTheme primaryTextColour];
		cell.body.text = name;
		cell.body.frame = CGRectMake(textX, fwd + 8, textW, 18);

		cell.subtitle.hidden = NO;
		cell.subtitle.font = [UIFont systemFontOfSize:13];
		cell.subtitle.textColor = [cardTheme fileMetaColour];
		cell.subtitle.text = phone;
		cell.subtitle.frame = CGRectMake(textX, fwd + 28, textW, 16);

		CGFloat sepY = fwd + 55;
		cell.contactSeparatorH.hidden = NO;
		cell.contactSeparatorH.backgroundColor = [cardTheme separatorColour];
		cell.contactSeparatorH.frame = CGRectMake(0, sepY, layout.bubbleFrame.size.width, 0.5f);

		CGFloat btnW = layout.bubbleFrame.size.width / 2.0f;
		cell.contactSeparatorV.hidden = NO;
		cell.contactSeparatorV.backgroundColor = [cardTheme separatorColour];
		cell.contactSeparatorV.frame = CGRectMake(btnW, sepY, 0.5f, 36);

		cell.contactCallButton.hidden = NO;
		cell.contactCallButton.frame = CGRectMake(0, sepY, btnW, 36);
		[cell.contactCallButton setTitleColor:[cardTheme accentColour] forState:UIControlStateNormal];
		[cell.contactCallButton setTitleColor:[[cardTheme accentColour] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
		cell.contactCallButton.tag = indexPath.row;
		[cell.contactCallButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactCallButton addTarget:self action:@selector(contactCallButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.contactAddButton.hidden = NO;
		cell.contactAddButton.frame = CGRectMake(btnW, sepY, btnW, 36);
		[cell.contactAddButton setTitleColor:[cardTheme accentColour] forState:UIControlStateNormal];
		[cell.contactAddButton setTitleColor:[[cardTheme accentColour] colorWithAlphaComponent:0.4f] forState:UIControlStateHighlighted];
		cell.contactAddButton.tag = indexPath.row;
		[cell.contactAddButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.contactAddButton addTarget:self action:@selector(contactAddButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [cardTheme timeMineColour] : [cardTheme timeColour];
		CGFloat fileTimeW = layout.timeWidth;
		CGFloat fileTicks = mine ? 18 : 0;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - fileTimeW - kPadH, fwd + 30,
									 fileTimeW - fileTicks, 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, fwd + 32, 15, 9);
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
		CGFloat mapH = 130.0f;

		double lat = [m[@"lat"] doubleValue];
		double lon = [m[@"lon"] doubleValue];

		cell.picture.hidden = NO;
		cell.picture.frame = CGRectMake(0, fwd, mapW, mapH);
		cell.picture.clipsToBounds = YES;
		cell.picture.image = [self imageFor:m];

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = NO;
		cell.disc.image = [TGIcons mapPinBadge];
		cell.disc.frame = CGRectMake((mapW - 28) / 2, fwd + (mapH - 36) / 2 - 4, 28, 36);
		[cell.bubble bringSubviewToFront:cell.disc];

		cell.icon.hidden = NO;
		cell.icon.layer.cornerRadius = 3;
		cell.icon.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.45f];
		cell.icon.textColor = [UIColor whiteColor];
		cell.icon.font = [UIFont boldSystemFontOfSize:10];
		cell.icon.text = @" Apple Maps ";
		cell.icon.frame = CGRectMake(6, fwd + mapH - 22, 68, 16);
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
		CGFloat locTicks = mine ? 18 : 0;

		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont boldSystemFontOfSize:14];
		cell.body.textColor = [locTheme primaryTextColour];
		cell.body.text = vTitle;

		if (vAddr.length > 0) {
			cell.subtitle.hidden = NO;
			cell.subtitle.numberOfLines = 1;
			cell.subtitle.font = [UIFont systemFontOfSize:12];
			cell.subtitle.textColor = [locTheme fileMetaColour];
			cell.subtitle.text = vAddr;
			cell.body.frame = CGRectMake(kPadH, fwd + mapH + 4, mapW - 2 * kPadH, 18);
			cell.subtitle.frame = CGRectMake(kPadH, fwd + mapH + 24, mapW - 2 * kPadH - locTimeW - locTicks - 4, 16);
		} else {
			cell.subtitle.hidden = YES;
			cell.subtitle.text = @"";
			cell.body.frame = CGRectMake(kPadH, fwd + mapH + 12, mapW - 2 * kPadH - locTimeW - locTicks - 4, 18);
		}

		cell.time.hidden = NO;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [locTheme timeMineColour] : [locTheme timeColour];
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - locTimeW - locTicks - kPadH,
									 layout.bubbleFrame.size.height - 17,
									 locTimeW, 12);

		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - locTicks - kPadH + 2,
										  layout.bubbleFrame.size.height - 15, 15, 9);
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
	cell.bubble.layer.borderWidth = (layout.isSticker || layout.isRound) ? 0.0f : [theme bubbleBorderWidth];
	cell.bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	cell.bubble.layer.cornerRadius = [theme bubbleCornerRadius];
	cell.body.textColor = [theme primaryTextColour];

	// Video note
	if (layout.isRound) {
		CGFloat side = layout.bubbleFrame.size.width;
		cell.bubble.backgroundColor = [theme fileTileColour];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.layer.cornerRadius = side / 2;
		cell.bubble.clipsToBounds = YES;
		cell.picture.hidden = NO;
		cell.picture.image = [self imageFor:m];
		cell.picture.backgroundColor = [theme fileTileColour];
		cell.picture.frame = CGRectMake(0, 0, side, side);
		cell.picture.layer.cornerRadius = side / 2;
		cell.picture.clipsToBounds = YES;
		cell.body.hidden = YES;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		CGFloat disc = 48;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.videoNotePlayer != nil);
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake((side - disc) / 2, (side - disc) / 2, disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(videoNoteDiscTapped:)]];
		}
		NSInteger dur = [m[@"duration"] integerValue];
		NSString *durStr = (dur > 0) ? [NSString stringWithFormat:@"%ld:%02ld", (long)(dur / 60), (long)(dur % 60)] : @"";
		NSString *stamp = (layout.stamp.length && ![layout.stamp isEqualToString:@"(null)"]) ? layout.stamp : @"";
		NSString *stampText = durStr.length ? (stamp.length ? [NSString stringWithFormat:@"%@  %@", durStr, stamp] : durStr) : stamp;

		CGFloat stampW = TGTextSize(stampText, [UIFont systemFontOfSize:11], 0).width + (mine ? 26 : 14);
		cell.mediaStamp.hidden = NO;
		cell.mediaStamp.backgroundColor = [theme mediaStampColour];
		cell.mediaStamp.text = mine ? [NSString stringWithFormat:@"  %@", stampText] : stampText;
		cell.mediaStamp.textAlignment = mine ? NSTextAlignmentLeft : NSTextAlignmentCenter;
		cell.mediaStamp.frame = CGRectMake((side - stampW) / 2, side - 24, stampW, 16);
		[cell.bubble bringSubviewToFront:cell.mediaStamp];

		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:YES];
			cell.ticks.frame = CGRectMake(CGRectGetMaxX(cell.mediaStamp.frame) - 16,
										  CGRectGetMidY(cell.mediaStamp.frame) - 4.5f, 15, 9);
			[cell.bubble bringSubviewToFront:cell.ticks];
		}

		cell.time.hidden = YES;
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	// Animated sticker
	NSString *tgsPath = [m[@"docName"] isEqualToString:@"tgs"] ? self.lottiePaths[m[@"docId"]] : nil;
	if (tgsPath) {
		CGFloat side = 128;
		cell.bubble.backgroundColor = [UIColor clearColor];
		cell.bubble.layer.borderWidth = 0;
		cell.bubble.frame = layout.bubbleFrame;
		cell.picture.hidden = YES;
		cell.body.hidden = YES;
		cell.lottie.hidden = NO;
		cell.lottie.frame = CGRectMake(0, 0, side, side);
		[cell.lottie loadTGSFile:tgsPath];
		[cell.lottie play];

		static NSDateFormatter *hmt = nil;
		if (!hmt) { hmt = [[NSDateFormatter alloc] init]; [hmt setDateFormat:@"HH:mm"]; }
		cell.time.text = [hmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
		cell.time.textColor = [theme timeColour];
		cell.time.frame = CGRectMake(side - 44, side, 44, 12);
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
		cell.quoteAuthor.font = [UIFont boldSystemFontOfSize:13];
		cell.quoteAuthor.textColor = [theme accentColour];
		cell.quoteAuthor.text = layout.quoteAuthor ?: @"Reply";
		cell.quoteAuthor.frame = layout.quoteAuthorFrame;

		cell.quote.hidden = NO;
		cell.quote.numberOfLines = 1;
		cell.quote.font = [UIFont systemFontOfSize:13];
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
		cell.picture.layer.cornerRadius = layout.isSticker ? 0.0f : kMediaRadius;
		cell.picture.clipsToBounds = YES;

		cell.disc.hidden = ![kind isEqualToString:@"messageVideo"] && ![kind isEqualToString:@"messageAnimation"];
		if (!cell.disc.hidden) {
			CGFloat disc = 42;
			cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:NO];
			cell.disc.frame = CGRectMake(kPadH + (layout.picSize.width - disc) / 2,
										 layout.pictureFrame.origin.y + (layout.picSize.height - disc) / 2, disc, disc);
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
		CGFloat disc = 36;
		CGFloat left = kPadH + disc + 8;
		BOOL isPlaying = (self.playingMessageId == [m[@"id"] longLongValue] && self.voicePlayer && self.voicePlayer.playing);

		cell.voiceMessageId = [m[@"id"] longLongValue];
		cell.waveformData = m[@"waveform"];

		CGFloat fwd = layout.fwdHeight;

		cell.disc.hidden = NO;
		cell.disc.userInteractionEnabled = YES;
		cell.disc.image = [TGIcons mediaDiscOfSide:disc playing:isPlaying];
		cell.disc.frame = CGRectMake(kPadH, fwd + (layout.bubbleFrame.size.height - fwd - disc) / 2, disc, disc);
		if (!cell.disc.gestureRecognizers.count) {
			[cell.disc addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(voiceDiscTapped:)]];
		}

		cell.wave.hidden = NO;
		CGSize waveSize = CGSizeMake(layout.bubbleFrame.size.width - left - kPadH, 18);
		cell.wave.image = [TGIcons waveform:m[@"waveform"]
									   size:waveSize
									 played:(isPlaying ? [self playedFraction] : 0)
									 colour:[voiceTheme accentColour]];
		cell.wave.frame = CGRectMake(left, fwd + 10, waveSize.width, waveSize.height);
		cell.wave.userInteractionEnabled = YES;
		if (!cell.wave.gestureRecognizers.count) {
			[cell.wave addGestureRecognizer:[[UIPanGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
			[cell.wave addGestureRecognizer:[[UITapGestureRecognizer alloc]
					initWithTarget:self action:@selector(waveformScrubbed:)]];
		}

		NSInteger seconds = [m[@"duration"] integerValue];
		cell.body.hidden = NO;
		cell.body.numberOfLines = 1;
		cell.body.font = [UIFont systemFontOfSize:12];
		cell.body.textColor = [voiceTheme secondaryTextColour];
		cell.body.text = [NSString stringWithFormat:@"%ld:%02ld",
				(long)(seconds / 60), (long)(seconds % 60)];
		cell.body.frame = CGRectMake(left, layout.bubbleFrame.size.height - 20, 44, 14);

		cell.picture.hidden = YES;
		cell.time.text = layout.stamp;
		cell.time.textColor = mine ? [voiceTheme timeMineColour] : [voiceTheme timeColour];
		CGFloat tickRoom = mine ? 18 : 0;
		cell.time.frame = CGRectMake(layout.bubbleFrame.size.width - layout.timeWidth - kPadH, layout.bubbleFrame.size.height - 20,
									 layout.timeWidth - tickRoom, 12);
		cell.ticks.hidden = !mine;
		if (mine) {
			cell.ticks.image = [self ticksForMessage:m white:NO];
			cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.bubbleFrame.size.height - 18, 15, 9);
		}
		return [self finalizeCell:cell message:m layout:layout isMine:mine];
	}

	cell.body.hidden = (layout.bodySize.height == 0 || layout.isSticker);
	cell.body.numberOfLines = 0;
	cell.body.lineBreakMode = NSLineBreakByWordWrapping;
	cell.body.font = [UIFont systemFontOfSize:[TGTheme shared].messageFontSize];
	NSArray *entities = m[@"entities"];
	if (entities.count) {
		cell.body.attributedText = TGAttributedMessageText(m[@"text"], entities, [UIFont systemFontOfSize:[TGTheme shared].messageFontSize], [theme primaryTextColour]);
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
			reactions.font = [UIFont systemFontOfSize:13];
			[cell.bubble addSubview:reactions];
		}
		reactions.hidden = NO;
		reactions.text = reactionText;
		reactions.textColor = [theme secondaryTextColour];
		reactions.frame = CGRectMake(kPadH, layout.bodyFrame.origin.y + layout.bodySize.height + 2, layout.bubbleFrame.size.width - 2 * kPadH, 16);
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
		cell.ticks.frame = CGRectMake(CGRectGetMaxX(cell.mediaStamp.frame) - 17,
									  CGRectGetMidY(cell.mediaStamp.frame) - 4.5f, 15, 9);
		[cell.bubble bringSubviewToFront:cell.ticks];
	} else if (mine) {
		cell.ticks.image = [self ticksForMessage:m white:NO];
		cell.ticks.frame = CGRectMake(layout.bubbleFrame.size.width - kPadH - 15, layout.timeFrame.origin.y + 2, 15, 9);
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
	if (layout.isService || fabs(layout.bubbleFrame.origin.y - 3.0f) > 0.1f)
		return 0;
	return ([self runStartsAtRow:row] ? 4.0f : 1.0f) - 3.0f;
}

- (CGFloat)runHeightChangeAtRow:(NSInteger)row layout:(TGMessageLayout *)layout {
	if (layout.isService || fabs(layout.bubbleFrame.origin.y - 3.0f) > 0.1f)
		return 0;
	CGFloat above = [self runStartsAtRow:row] ? 4.0f : 1.0f;
	CGFloat below = [self runEndsAtRow:row] ? 4.0f : 1.0f;
	return (above - 3.0f) + (below - 3.0f);
}

/// A rounded box whose four corners can differ.
static UIBezierPath *TGBubblePath(CGSize size, CGFloat tl, CGFloat tr, CGFloat br, CGFloat bl) {
	CGFloat cap = MIN(size.width, size.height) / 2;
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
			c.origin.y = CGRectGetMidY(b) - c.size.height / 2;
			cell.checkbox.frame = c;
		}
	}

	// A group shows the sender's picture once, beside the tail.
	if (!last && !cell.senderAvatar.hidden)
		cell.senderAvatar.hidden = YES;

	TGTheme *theme = [TGTheme shared];
	UIColor *fill = cell.bubble.backgroundColor;
	BOOL plain = !fill || CGColorGetAlpha(fill.CGColor) < 0.01f;
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
