#import "TGChatViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGStyle.h"

UIColor *TGSenderColour(int64_t userId) {
	// Same slot as the sender's placeholder avatar, so the two always match.
	return [TGIcons nameColourForId:userId dark:[TGTheme shared].isDark];
}

@implementation TGChatViewController (Layout)

#pragma mark - geometry

/// Size of the text inside a bubble, and of the bubble itself.
/// The quote block a reply carries, and the "forwarded from" line above it.
- (NSString *)quoteTextFor:(NSDictionary *)m {
	NSNumber *replyId = m[@"replyId"];
	if (![replyId isKindOfClass:NSNumber.class])
		return nil;
	NSString *inline_ = m[@"replyText"];
	if (inline_.length)
		return inline_;
	NSDictionary *fetched = self.quotes[replyId];
	return fetched[@"text"] ?: @"...";
}

/// Who wrote the message being answered. Only known once the original has been
/// fetched; TDLib's inline quote carries the text but not the author.
- (NSString *)quoteAuthorFor:(NSDictionary *)m {
	NSNumber *replyId = [m[@"replyId"] isKindOfClass:NSNumber.class] ? m[@"replyId"] : nil;
	if (!replyId)
		return nil;
	NSDictionary *original = self.quotes[replyId];
	if (!original)
		return nil;
	if ([original[@"outgoing"] boolValue])
		return @"You";
	return [[TGClient shared] nameForUserId:[original[@"senderId"] longLongValue]];
}

- (CGFloat)decorationHeightFor:(NSDictionary *)m {
	CGFloat h = TGMetricZero;
	if ([m[@"forward"] length])
		h += TGMetricQuoteForwardLine;
	// Their reply block is two lines beside a stripe: the author, then what
	// they said.
	if ([self quoteTextFor:m])
		h += kQuoteBlock;
	if ([m[@"reactions"] length])
		h += TGMetricLineBody;
	return h;
}

/// "12:29" for incoming, "12:29 ✓✓" for outgoing, "edited" in front when it
/// applies - the same line Telegram tucks into the corner of the bubble.
- (NSString *)stampFor:(NSDictionary *)m {
	static NSDateFormatter *hm = nil;
	if (!hm){ hm = [[NSDateFormatter alloc] init]; [hm setDateFormat:@"HH:mm"]; }

	NSString *stamp = [hm stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	if ([m[@"edited"] boolValue])
		stamp = [NSString stringWithFormat:@"edited %@", stamp];
	return stamp;   // the ticks are drawn beside it, not spelled out
}

- (CGFloat)timeWidthFor:(NSDictionary *)m {
	CGFloat w = TGTextSize([self stampFor:m], TGFontMicro(), 0).width + TGMetricPadTiny;
	if ([m[@"outgoing"] boolValue])
		w += TGMetricStampTicksRoom;
	return w;
}

/// Telegram puts the stamp at the end of the last line when it fits there,
/// and only drops it to its own line when it does not. Anything else leaves a
/// gap under short messages, which is what looked wrong.
- (BOOL)stampFitsInlineFor:(NSDictionary *)m {
	NSString *text = m[@"text"] ?: @"";
	if (!text.length || [text rangeOfString:@"\n"].location != NSNotFound)
		return NO;

	CGFloat oneLine = TGTextSize(text,
			TGFontAtSize([TGTheme shared].messageFontSize), 0).width;
	if (oneLine > kBubbleMaxW - TGDoubled(kPadH))
		return NO;   // it wraps, so there is no short last line to share

	return (oneLine + kStampGap + [self timeWidthFor:m]) <= (kBubbleMaxW - TGDoubled(kPadH));
}

/// Configures forwarded message attribution header and returns its height.
- (CGFloat)layoutForwardIn:(TGBubbleCell *)cell
				   message:(NSDictionary *)m
					 width:(CGFloat)width
{
	NSString *from = m[@"forward"];
	if (![from length]){
		cell.forwardLabel.hidden = YES;
		return 0;
	}

	TGTheme *theme = [TGTheme shared];
	cell.forwardLabel.hidden = NO;
	cell.forwardLabel.frame = CGRectMake(kPadH, kPadV, width - TGDoubled(kPadH), TGMetricSenderLineHeight);

	NSString *line = [NSString stringWithFormat:@"Forwarded from %@", from];
	if ([cell.forwardLabel respondsToSelector:@selector(setAttributedText:)]){
		NSMutableAttributedString *styled =
				[[NSMutableAttributedString alloc] initWithString:line];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:[theme secondaryTextColour]
					   range:NSMakeRange(0, line.length)];
		[styled addAttribute:NSForegroundColorAttributeName
					   value:[theme accentColour]
					   range:NSMakeRange(15, from.length)];
		[styled addAttribute:NSFontAttributeName
					   value:TGFontMetaStrong()
					   range:NSMakeRange(15, from.length)];
		cell.forwardLabel.attributedText = styled;
	} else {
		cell.forwardLabel.textColor = [theme accentColour];
		cell.forwardLabel.text = line;
	}
	return TGMetricQuoteForwardLine;
}

/// Question, the "N voted" line, one row per option, and the stamp.
- (CGFloat)pollHeightFor:(NSDictionary *)m {
	NSString *question = m[@"pollQuestion"] ?: @"Poll";
	CGSize qs = TGTextSize(question, TGFontBodyStrong(),
			kBubbleMaxW - TGDoubled(kPadH));
	NSArray *options = m[@"pollOptions"];
	return kPadV + qs.height + TGMetricPadTiny + TGMetricLineRow
			+ kPollRow * options.count + TGMetricLineBody;
}

/// A picture with no caption carries its own stamp on a plate, so the bubble
/// does not need a strip of empty space under it for one.
- (BOOL)stampSitsOnPictureFor:(NSDictionary *)m {
	if ([m[@"isAlbum"] boolValue] && [self bodySizeFor:m].height == 0)
		return YES;
	return [self imageSizeFor:m].height > 0 && [self bodySizeFor:m].height == 0 &&
		   ![m[@"kind"] isEqualToString:@"messageVideoNote"];
}

- (CGSize)bodySizeFor:(NSDictionary *)m {
	if ([m[@"kind"] isEqualToString:@"messageSticker"] || [m[@"kind"] isEqualToString:@"messageAnimatedEmoji"])
		return CGSizeZero;
	NSString *text = m[@"text"] ?: @"";
	if (!text.length)
		return CGSizeZero;
	return TGTextSizeWithEntities(text, m[@"entities"], TGFontAtSize([TGTheme shared].messageFontSize),
			kBubbleMaxW - TGDoubled(kPadH));
}

- (UIImage *)imageFor:(NSDictionary *)m {
	UIImage *map = self.maps[m[@"id"]];
	if (map)
		return map;
	NSNumber *fileId = m[@"photoId"];
	return [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
}

- (CGSize)imageSizeFor:(NSDictionary *)m {
	UIImage *img = [self imageFor:m];
	CGFloat w = 0, h = 0;
	if (img) {
		w = img.size.width;
		h = img.size.height;
	} else if ([m[@"mediaWidth"] floatValue] > 0 && [m[@"mediaHeight"] floatValue] > 0) {
		w = [m[@"mediaWidth"] floatValue];
		h = [m[@"mediaHeight"] floatValue];
	} else if ([m[@"photoId"] isKindOfClass:NSNumber.class]) {
		w = kImageMax;
		h = kImageMax * TGMetricMediaRatioLandscape;
	}
	if (w <= 0 || h <= 0)
		return CGSizeZero;

	CGFloat scale = MIN(kImageMax / w, kImageMax / h);
	scale = MIN(scale, TGMetricScaleFull);
	return CGSizeMake(floorf(w * scale), floorf(h * scale));
}

- (TGMessageLayout *)layoutForMessage:(NSDictionary *)m atRow:(NSInteger)row {
	NSNumber *msgId = m[@"id"];
	if (msgId) {
		TGMessageLayout *hit = self.layoutCache[msgId];
		if (hit) return hit;
	}

	TGMessageLayout *layout = [[TGMessageLayout alloc] init];
	CGFloat tableW = self.table.bounds.size.width;
	if (tableW <= 0) tableW = TGMetricScreenWidth;

	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];
	BOOL isSticker = [kind isEqualToString:@"messageSticker"] || [kind isEqualToString:@"messageAnimatedEmoji"];
	BOOL isVoice = [kind isEqualToString:@"messageVoiceNote"];
	BOOL isRound = [kind isEqualToString:@"messageVideoNote"];
	BOOL isService = [m[@"service"] boolValue];
	BOOL isPoll = [kind isEqualToString:@"messagePoll"];
	// A track is a document with a title and a performer of its own. It was
	// drawn as the document it also is, which is why music looked like a file.
	BOOL isTrack = [kind isEqualToString:@"messageAudio"];
	BOOL isCall = [kind isEqualToString:@"messageCall"];
	BOOL isDoc = [kind isEqualToString:@"messageDocument"];
	BOOL isContact = [kind isEqualToString:@"messageContact"];
	BOOL isLocation = [kind isEqualToString:@"messageLocation"] ||
					  [kind isEqualToString:@"messageVenue"] ||
					  [kind isEqualToString:@"messageLiveLocation"] ||
					  (![m[@"lat"] isKindOfClass:NSNull.class] && [m[@"lat"] doubleValue] != 0);
	BOOL isAlbum = [m[@"isAlbum"] boolValue];

	layout.isService = isService;
	layout.isSticker = isSticker;
	layout.isVoice = isVoice;
	layout.isRound = isRound;
	layout.isPoll = isPoll;
	layout.isTrack = isTrack;
	layout.isCall = isCall;
	layout.isDoc = isDoc;
	layout.isContact = isContact;
	layout.isLocation = isLocation;
	layout.isAlbum = isAlbum;

	CGFloat forwarded = [m[@"forward"] length] ? TGMetricQuoteForwardLine : TGMetricZero;
	layout.fwdHeight = forwarded;
	layout.stamp = [self stampFor:m];
	layout.timeWidth = TGTextSize(layout.stamp, TGFontMicro(), 0).width;

	NSString *separator = m[@"separator"];
	if ([separator isEqualToString:@"unread"]) {
		// A full-width bar, not a plate: it marks a place, not an event.
		layout.isService = YES;
		layout.bubbleFrame = CGRectMake(TGMetricZero, TGCenteredOrigin(kServiceRow, kUnreadBar),
				tableW, kUnreadBar);
		layout.bodyFrame = CGRectMake(TGMetricZero, TGCenteredOrigin(kUnreadBar, TGMetricLineBody),
				tableW, TGMetricLineBody);
		layout.rowHeight = kServiceRow;
		return layout;
	}

	if (isService) {
		NSString *who = separator ? nil : [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length ? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]] : (m[@"text"] ?: @"");
		UIFont *font = TGFontMeta();
		CGFloat textW = MIN(TGTextSize(line, font, 0).width,
				tableW - TGDoubled(kServicePlateMargin));
		CGFloat plateW = textW + TGDoubled(kServicePlatePad);
		// A day plate gets a little more air than an event in the chat.
		CGFloat top = separator ? kServiceGap : kServiceEventGap;
		layout.bubbleFrame = CGRectMake(TGCenteredOrigin(tableW, plateW), top, plateW, kServicePlate);
		layout.bodyFrame = CGRectMake(TGMetricZero, TGCenteredOrigin(kServicePlate, TGMetricLineSubhead),
				plateW, TGMetricLineSubhead);
		layout.rowHeight = separator ? kServiceRow : kServiceEventRow;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isPoll) {
		CGFloat width = kBubbleMaxW;
		CGFloat x = mine ? (tableW - width - TGMetricPad) : TGMetricPad;
		CGFloat height = [self pollHeightFor:m];
		layout.bubbleFrame = CGRectMake(x, TGMetricBubbleRowInset, width, height);
		layout.rowHeight = height + TGDoubled(TGMetricBubbleRowInset);
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isCall) {
		NSString *line = m[@"text"] ?: @"Call";
		CGFloat textW = TGTextSize(line, TGFontSubheadStrong(), 0).width;
		CGFloat width = MIN(kBubbleMaxW, textW + kCallBubbleRoom);
		width = MAX(kCallBubbleMin, width);
		CGFloat height = kCallBubble + forwarded;
		CGFloat x = mine ? (tableW - width - TGMetricPad) : TGMetricPad;
		layout.bubbleFrame = CGRectMake(x, TGMetricBubbleRowInset, width, height);
		layout.rowHeight = height + TGDoubled(TGMetricBubbleRowInset);
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isDoc) {
		CGFloat width = kDocBubble;
		CGFloat height = kFileTile + TGDoubled(kPadV) + forwarded;
		CGFloat x = mine ? (tableW - width - TGMetricPad) : TGMetricPad;
		layout.bubbleFrame = CGRectMake(x, TGMetricBubbleRowInset, width, height);
		layout.rowHeight = height + TGDoubled(TGMetricBubbleRowInset);
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isContact) {
		CGFloat width = kContactBubble;
		CGFloat height = kContactBubbleH + forwarded;
		CGFloat x = mine ? (tableW - width - TGMetricPad) : TGMetricPad;
		layout.bubbleFrame = CGRectMake(x, TGMetricBubbleRowInset, width, height);
		layout.rowHeight = height + TGDoubled(TGMetricBubbleRowInset);
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isLocation) {
		NSNumber *lat = m[@"lat"], *lon = m[@"lon"];
		if ([lat isKindOfClass:NSNumber.class] && [lon isKindOfClass:NSNumber.class] && !self.maps[m[@"id"]]) {
			self.maps[m[@"id"]] = [self mapCardForLatitude:lat.doubleValue longitude:lon.doubleValue];
		}
		CGFloat width = kLocationBubble;
		CGFloat height = kLocationBubbleH + forwarded;
		CGFloat x = mine ? (tableW - width - TGMetricPad) : TGMetricPad;
		layout.bubbleFrame = CGRectMake(x, TGMetricBubbleRowInset, width, height);
		layout.rowHeight = height + TGDoubled(TGMetricBubbleRowInset);
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];
	layout.bodySize = body;
	layout.picSize = pic;

	if (isRound) {
		CGFloat side = kRoundSide;
		layout.picSize = CGSizeMake(side, side);
		layout.bubbleFrame = CGRectMake(mine ? (tableW - side - TGMetricPad) : TGMetricPad,
				TGMetricBubbleRowInset, side, side);
		// The stamp line lives under the circle now: every other bubble
		// carries its clock under the message, and a round note hanging its
		// clock out to the side read as drifting off the row.
		layout.rowHeight = side + TGMetricStampHeight + TGMetricPadSmall
				+ TGDoubled(TGMetricBubbleRowInset);
		layout.stamp = [self stampFor:m];
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if ([TGCapabilities canPlayAnimatedStickers] && [m[@"docName"] isEqualToString:@"tgs"] && self.lottiePaths[m[@"docId"]]) {
		CGFloat side = kLottieSide;
		layout.bubbleFrame = CGRectMake(mine ? (tableW - side - TGMetricPad) : TGMetricPad,
				TGMetricBubbleRowInset, side, side + TGMetricLineMicro);
		layout.rowHeight = side + TGMetricLineMicro + TGDoubled(TGMetricBubbleRowInset);
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	CGFloat collageW = TGMetricCollageWidth;
	CGFloat collageH = TGMetricZero;
	NSMutableArray *itemFrames = [NSMutableArray array];

	if (isAlbum) {
		NSArray *items = m[@"albumMessages"];
		NSUInteger count = items.count;
		CGFloat gap = TGMetricCollageGap;
		CGFloat halfW = TGHalf(collageW - gap);

		if (count <= 2) {
			collageH = TGMetricCollageHeightDual;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, halfW, collageH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, 0, halfW, collageH)]];
		} else if (count == 3) {
			CGFloat topH = TGMetricCollageTopHeight;
			CGFloat botH = TGMetricCollageBottomHeight;
			collageH = topH + gap + botH;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, collageW, topH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, topH + gap, halfW, botH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, topH + gap, halfW, botH)]];
		} else {
			CGFloat halfH = TGMetricCollageQuadHeight;
			collageH = TGDoubled(halfH) + gap;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, halfW, halfH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, 0, halfW, halfH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, halfH + gap, halfW, halfH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, halfH + gap, halfW, halfH)]];
		}
		layout.albumFrames = itemFrames;
	}

	int64_t senderId = [m[@"senderId"] longLongValue];
	NSString *senderName = (self.isGroup && !mine) ? [[TGClient shared] nameForUserId:senderId] : nil;

	BOOL inlineStamp = [self stampFitsInlineFor:m];
	CGFloat timeW = [self timeWidthFor:m];
	CGFloat contentW = MAX(body.width, pic.width);
	if (isAlbum)
		contentW = MAX(contentW, collageW);
	NSString *quoted = [self quoteTextFor:m];
	if (quoted || [m[@"forward"] length])
		contentW = MAX(contentW, kBubbleMinW);
	if (inlineStamp)
		contentW = MAX(contentW, body.width + kStampGap + timeW);
	if (isVoice)
		contentW = kPicBubbleW;
	// A track measured itself from its caption, which is usually empty, so
	// the bubble came out narrower than the row drawn inside it and the title
	// ran out past its own edge.
	if (isTrack)
		contentW = MAX(contentW, TGMetricTrackContent);
	CGFloat senderH = senderName.length ? TGMetricSenderLineHeight : TGMetricZero;
	if (senderName.length) {
		CGFloat senderW = TGTextSize(senderName, TGFontMetaStrong(), 0).width;
		contentW = MAX(contentW, senderW);
	}

	CGFloat bubbleW = MAX(contentW + TGDoubled(kPadH),
			timeW + TGDoubled(kPadH) + TGMetricPad);
	bubbleW = MIN(bubbleW, kBubbleMaxW + TGDoubled(kPadH));
	BOOL stampOnPicture = [self stampSitsOnPictureFor:m];
	CGFloat bubbleH = TGDoubled(kPadV) + senderH
			+ (inlineStamp || stampOnPicture ? TGMetricZero : TGMetricLineMicro)
			+ [self decorationHeightFor:m]
			+ (isAlbum ? (collageH + (body.height ? TGMetricPadSmall : TGMetricZero))
					   : (pic.height ? pic.height + TGMetricPadSmall : TGMetricZero))
			+ body.height;
	if (isVoice)
		bubbleH = TGMetricPersonRow + senderH
				+ ([m[@"forward"] length] ? TGMetricQuoteForwardLine : TGMetricZero);
	// A track's row is fixed below, but its bubble was still measured by the
	// generic formula, so the two disagreed: the bubble ran past the row it
	// was given and sat on top of the message above it.
	if (isTrack)
		bubbleH = kTrackRow + senderH + forwarded;

	CGFloat x = mine ? (tableW - bubbleW - TGMetricPad) : TGMetricPad;
	CGFloat top = [self continuesAlbumAtRow:row] ? TGMetricZero : TGMetricBubbleRowInset;

	if (senderName.length) {
		x += kAvatarSide + TGMetricPadSmall + kTailWidth;   // the tail hangs between picture and bubble
		layout.senderName = senderName;
		layout.senderFrame = CGRectMake(kPadH, kPadV, bubbleW - TGDoubled(kPadH), TGMetricLineMicro);
		CGFloat avatarY = MAX(TGMetricPadTiny, top + bubbleH - kAvatarSide);
		layout.senderAvatarFrame = CGRectMake(TGMetricPad, avatarY, kAvatarSide, kAvatarSide);
	}

	layout.bubbleFrame = CGRectMake(x, top, bubbleW, bubbleH);
	layout.inlineStamp = inlineStamp;
	layout.stampOnPicture = stampOnPicture;
	layout.timeWidth = timeW;
	layout.stamp = [self stampFor:m];
	layout.quoteText = quoted;
	layout.quoteAuthor = [self quoteAuthorFor:m];

	layout.tailFrame = CGRectZero;

	CGFloat y = kPadV + senderH + forwarded;
	if (quoted) {
		CGFloat quoteW = bubbleW - TGDoubled(kPadH) - TGMetricPadMedium;
		layout.quoteBarFrame = CGRectMake(kPadH, y, kQuoteBarWidth, TGDoubled(kQuoteLine));
		layout.quoteAuthorFrame = CGRectMake(kPadH + kQuoteTextInset, y, quoteW, TGMetricLineCaption);
		layout.quoteFrame = CGRectMake(kPadH + kQuoteTextInset, y + kQuoteLine, quoteW, kQuoteLine);
		y += kQuoteBlock;
	}
	CGFloat innerW = bubbleW - TGDoubled(kPadH);
	if (isAlbum) {
		CGFloat cW = (body.height > 0) ? innerW : collageW;
		layout.collageFrame = CGRectMake(kPadH, y, cW, collageH);
		if (!body.height) {
			CGFloat plateW = timeW + (mine ? TGMetricGroupAvatarSide : TGMetricLineMicro);
			layout.mediaStampFrame = CGRectMake(kPadH + collageW - plateW - kMediaStampInset,
					y + collageH - TGMetricFloatingDateHeight, plateW, TGMetricLineCaption);
		}
		y += collageH + TGMetricPadSmall;
	} else if (pic.height > 0) {
		CGFloat picW = (body.height > 0) ? innerW : pic.width;
		layout.pictureFrame = CGRectMake(kPadH, y, picW, pic.height);
		if (!body.height) {
			CGFloat plateW = timeW + (mine ? TGMetricGroupAvatarSide : TGMetricLineMicro);
			layout.mediaStampFrame = CGRectMake(kPadH + pic.width - plateW - kMediaStampInset,
					y + pic.height - TGMetricFloatingDateHeight, plateW, TGMetricLineCaption);
		}
		y += pic.height + TGMetricPadSmall;
	}
	layout.bodyFrame = CGRectMake(kPadH, y, bubbleW - TGDoubled(kPadH), body.height);
	CGFloat stampY = inlineStamp ? (y + body.height - TGMetricLineMicro)
			: (bubbleH - kPadV - TGMetricStampHeight);
	CGFloat tickW = mine ? TGMetricStampTicksRoom : TGMetricZero;
	layout.timeFrame = CGRectMake(bubbleW - timeW - kPadH, stampY, timeW - tickW, TGMetricStampHeight);

	CGFloat rowH = TGDoubled(kPadV) + [self decorationHeightFor:m] +
			(inlineStamp || stampOnPicture ? TGMetricZero : TGMetricLineMicro);
	if (self.isGroup && !mine && senderName.length)
		rowH += TGMetricSenderLineHeight;
	if (isAlbum) rowH += collageH + (body.height > 0 ? TGMetricPadSmall : TGMetricZero);
	else if (pic.height > 0) rowH += pic.height + TGMetricPadSmall;
	if (body.height > 0) rowH += body.height;
	if (isVoice) rowH = TGMetricVoicePillHeight + forwarded;
	// Fixed, like a voice note: the artwork and the two lines beside it do
	// not grow with the title, which is truncated instead.
	// One expression for the row and the bubble, so they cannot drift apart.
	if (isTrack) rowH = kTrackRow + forwarded + senderH;

	layout.rowHeight = MAX(rowH + TGDoubled(TGMetricBubbleRowInset), kBubbleRowMin);

	if (msgId) self.layoutCache[msgId] = layout;
	return layout;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *m = self.messages[indexPath.row];
	TGMessageLayout *layout = [self layoutForMessage:m atRow:indexPath.row];
	return layout.rowHeight + [self runHeightChangeAtRow:indexPath.row layout:layout];
}

@end
