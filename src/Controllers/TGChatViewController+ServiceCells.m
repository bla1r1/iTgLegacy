//
// TGChatViewController+ServiceCells.m
// Bubble cell rendering for service messages, polls, documents, contacts, and locations.
//
#import "TGChatViewControllerInternal.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

@implementation TGChatViewController (ServiceCells)

- (BOOL)configureServiceCell:(TGBubbleCell *)cell message:(NSDictionary *)m layout:(TGMessageLayout *)layout isMine:(BOOL)mine indexPath:(NSIndexPath *)indexPath {
	// Service messages & separators
	if (layout.isService) {
		TGTheme *serviceTheme = [TGTheme shared];
		NSString *who = m[@"separator"] ? nil : [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *text = m[@"text"] ?: @"";
		NSString *line = text;
		if (who.length && ![text hasPrefix:@"Group "] && ![text hasPrefix:@"Chat "] && ![text hasPrefix:@"Screenshot "] && ![text hasPrefix:@"You "]) {
			line = [NSString stringWithFormat:@"%@ %@", who, text];
		}

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
		return YES;
	}

	// Polls
	if (layout.isPoll) {
		TGTheme *pollTheme = [TGTheme shared];
		NSArray *options = m[@"pollOptions"];
		NSString *question = m[@"pollQuestion"] ?: @"Poll";
		BOOL closed = [m[@"pollClosed"] boolValue];

		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [pollTheme bubbleMineColour] : [pollTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
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
				id optText = option[@"text"];
				if ([optText isKindOfClass:NSDictionary.class]) {
					label.text = optText[@"text"] ?: @"";
				} else if ([optText isKindOfClass:NSString.class]) {
					label.text = (NSString *)optText;
				} else {
					label.text = @"";
				}
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
		return YES;
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
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
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
		return YES;
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
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
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
		return YES;
	}

	// Locations
	if (layout.isLocation) {
		TGTheme *locTheme = [TGTheme shared];
		CGFloat fwd = [self layoutForwardIn:cell message:m width:layout.bubbleFrame.size.width];
		cell.bubble.frame = layout.bubbleFrame;
		cell.bubble.backgroundColor = mine ? [locTheme bubbleMineColour] : [locTheme bubbleTheirsColour];
		cell.bubble.layer.borderWidth = TGMetricBorderNone;
		cell.bubble.layer.borderColor = [UIColor clearColor].CGColor;
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
		return YES;
	}

	return NO;
}

@end
