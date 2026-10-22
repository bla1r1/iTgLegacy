#import "TGChatViewControllerInternal.h"

UIColor *TGSenderColour(int64_t userId) {
	static NSArray *lightPalette = nil;
	static NSArray *darkPalette = nil;
	if (!lightPalette) {
		lightPalette = @[[UIColor colorWithRed:0.85f green:0.27f blue:0.27f alpha:1],
						 [UIColor colorWithRed:0.20f green:0.55f blue:0.85f alpha:1],
						 [UIColor colorWithRed:0.25f green:0.62f blue:0.35f alpha:1],
						 [UIColor colorWithRed:0.75f green:0.45f blue:0.15f alpha:1],
						 [UIColor colorWithRed:0.55f green:0.35f blue:0.75f alpha:1],
						 [UIColor colorWithRed:0.20f green:0.60f blue:0.62f alpha:1]];
		darkPalette = @[[UIColor colorWithRed:0.95f green:0.45f blue:0.45f alpha:1],
						[UIColor colorWithRed:0.42f green:0.70f blue:0.98f alpha:1],
						[UIColor colorWithRed:0.45f green:0.80f blue:0.55f alpha:1],
						[UIColor colorWithRed:0.95f green:0.65f blue:0.35f alpha:1],
						[UIColor colorWithRed:0.75f green:0.55f blue:0.95f alpha:1],
						[UIColor colorWithRed:0.40f green:0.78f blue:0.80f alpha:1]];
	}
	NSArray *p = [TGTheme shared].isDark ? darkPalette : lightPalette;
	return p[(NSUInteger)llabs(userId) % p.count];
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
	CGFloat h = 0;
	if ([m[@"forward"] length])
		h += 18;
	// Their reply block is two lines beside a stripe: the author, then what
	// they said.
	if ([self quoteTextFor:m])
		h += 38;
	if ([m[@"reactions"] length])
		h += 18;
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
	CGFloat w = TGTextSize([self stampFor:m], [UIFont systemFontOfSize:11], 0).width + 2;
	if ([m[@"outgoing"] boolValue])
		w += 18;   // room for the ticks
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
			[UIFont systemFontOfSize:[TGTheme shared].messageFontSize], 0).width;
	if (oneLine > kBubbleMaxW - 2 * kPadH)
		return NO;   // it wraps, so there is no short last line to share

	return (oneLine + 6 + [self timeWidthFor:m]) <= (kBubbleMaxW - 2 * kPadH);
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
	cell.forwardLabel.frame = CGRectMake(kPadH, kPadV, width - 2 * kPadH, 16);

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
					   value:[UIFont boldSystemFontOfSize:12]
					   range:NSMakeRange(15, from.length)];
		cell.forwardLabel.attributedText = styled;
	} else {
		cell.forwardLabel.textColor = [theme accentColour];
		cell.forwardLabel.text = line;
	}
	return 18;
}

/// Question, the "N voted" line, one row per option, and the stamp.
- (CGFloat)pollHeightFor:(NSDictionary *)m {
	NSString *question = m[@"pollQuestion"] ?: @"Poll";
	CGSize qs = TGTextSize(question, [UIFont boldSystemFontOfSize:15],
			kBubbleMaxW - 2 * kPadH);
	NSArray *options = m[@"pollOptions"];
	return kPadV + qs.height + 22 + kPollRow * options.count + 18;
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
	return TGTextSizeWithEntities(text, m[@"entities"], [UIFont systemFontOfSize:[TGTheme shared].messageFontSize],
			kBubbleMaxW - 2 * kPadH);
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
		h = kImageMax * 0.75f;
	}
	if (w <= 0 || h <= 0)
		return CGSizeZero;

	CGFloat scale = MIN(kImageMax / w, kImageMax / h);
	scale = MIN(scale, 1.0f);
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
	if (tableW <= 0) tableW = 320.0f;

	BOOL mine = [m[@"outgoing"] boolValue];
	NSString *kind = m[@"kind"];
	BOOL isSticker = [kind isEqualToString:@"messageSticker"] || [kind isEqualToString:@"messageAnimatedEmoji"];
	BOOL isVoice = [kind isEqualToString:@"messageVoiceNote"];
	BOOL isRound = [kind isEqualToString:@"messageVideoNote"];
	BOOL isService = [m[@"service"] boolValue];
	BOOL isPoll = [kind isEqualToString:@"messagePoll"];
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
	layout.isCall = isCall;
	layout.isDoc = isDoc;
	layout.isContact = isContact;
	layout.isLocation = isLocation;
	layout.isAlbum = isAlbum;

	CGFloat forwarded = [m[@"forward"] length] ? 18.0f : 0.0f;
	layout.fwdHeight = forwarded;
	layout.stamp = [self stampFor:m];
	layout.timeWidth = TGTextSize(layout.stamp, [UIFont systemFontOfSize:11], 0).width;

	if (isService) {
		NSString *who = [[TGClient shared] nameForUserId:[m[@"senderId"] longLongValue]];
		NSString *line = who.length ? [NSString stringWithFormat:@"%@ %@", who, m[@"text"]] : (m[@"text"] ?: @"");
		UIFont *font = [UIFont systemFontOfSize:12];
		CGFloat textW = MIN(TGTextSize(line, font, 0).width, tableW - 60);
		CGFloat plateW = textW + 20;
		layout.bubbleFrame = CGRectMake((tableW - plateW) / 2, 4, plateW, 21);
		layout.bodyFrame = CGRectMake(0, 2, plateW, 17);
		layout.rowHeight = 30;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isPoll) {
		CGFloat width = kBubbleMaxW;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		CGFloat height = [self pollHeightFor:m];
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = height + 6;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isCall) {
		NSString *line = m[@"text"] ?: @"Call";
		CGFloat textW = TGTextSize(line, [UIFont boldSystemFontOfSize:14], 0).width;
		CGFloat width = MIN(kBubbleMaxW, textW + 80);
		width = MAX(190.0f, width);
		CGFloat height = 48 + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = 54 + forwarded;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isDoc) {
		CGFloat width = 225;
		CGFloat height = kFileTile + 2 * kPadV + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = kFileTile + 2 * kPadV + 6 + forwarded;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isContact) {
		CGFloat width = 230;
		CGFloat height = 56 + 36 + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = height + 6;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if (isLocation) {
		NSNumber *lat = m[@"lat"], *lon = m[@"lon"];
		if ([lat isKindOfClass:NSNumber.class] && [lon isKindOfClass:NSNumber.class] && !self.maps[m[@"id"]]) {
			self.maps[m[@"id"]] = [self mapCardForLatitude:lat.doubleValue longitude:lon.doubleValue];
		}
		CGFloat width = 224;
		CGFloat height = 130 + 44 + forwarded;
		CGFloat x = mine ? (tableW - width - 8) : 8;
		layout.bubbleFrame = CGRectMake(x, 3, width, height);
		layout.rowHeight = height + 6;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];
	layout.bodySize = body;
	layout.picSize = pic;

	if (isRound) {
		CGFloat side = 180;
		layout.picSize = CGSizeMake(side, side);
		layout.bubbleFrame = CGRectMake(mine ? (tableW - side - 8) : 8, 3, side, side);
		layout.rowHeight = side + 10;
		layout.stamp = [self stampFor:m];
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	if ([m[@"docName"] isEqualToString:@"tgs"] && self.lottiePaths[m[@"docId"]]) {
		CGFloat side = 128;
		layout.bubbleFrame = CGRectMake(mine ? (tableW - side - 8) : 8, 3, side, side + 14);
		layout.rowHeight = 148;
		if (msgId) self.layoutCache[msgId] = layout;
		return layout;
	}

	CGFloat collageW = 220.0f;
	CGFloat collageH = 0.0f;
	NSMutableArray *itemFrames = [NSMutableArray array];

	if (isAlbum) {
		NSArray *items = m[@"albumMessages"];
		NSUInteger count = items.count;
		CGFloat gap = 2.0f;
		CGFloat halfW = (collageW - gap) / 2.0f;

		if (count <= 2) {
			collageH = 135.0f;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, halfW, collageH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, 0, halfW, collageH)]];
		} else if (count == 3) {
			CGFloat topH = 120.0f;
			CGFloat botH = 88.0f;
			collageH = topH + gap + botH;
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, 0, collageW, topH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(0, topH + gap, halfW, botH)]];
			[itemFrames addObject:[NSValue valueWithCGRect:CGRectMake(halfW + gap, topH + gap, halfW, botH)]];
		} else {
			CGFloat halfH = 104.0f;
			collageH = halfH * 2.0f + gap;
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
		contentW = MAX(contentW, 170);
	if (inlineStamp)
		contentW = MAX(contentW, body.width + 6 + timeW);
	if (isVoice)
		contentW = 190;
	if (senderName.length) {
		CGFloat senderW = TGTextSize(senderName, [UIFont boldSystemFontOfSize:12], 0).width;
		contentW = MAX(contentW, senderW);
	}

	CGFloat bubbleW = MAX(contentW + 2 * kPadH, timeW + 2 * kPadH + 8);
	bubbleW = MIN(bubbleW, kBubbleMaxW + 2 * kPadH);
	BOOL stampOnPicture = [self stampSitsOnPictureFor:m];
	CGFloat bubbleH = kPadV * 2 + (inlineStamp || stampOnPicture ? 0 : 14) +
			[self decorationHeightFor:m] +
			(isAlbum ? (collageH + (body.height ? 4 : 0)) : (pic.height ? pic.height + 4 : 0)) + body.height;
	if (isVoice)
		bubbleH = 56 + ([m[@"forward"] length] ? 18 : 0);

	CGFloat x = mine ? (tableW - bubbleW - 8) : 8;
	CGFloat top = [self continuesAlbumAtRow:row] ? 0 : 3;

	if (senderName.length) {
		x += kAvatarSide + 4;
		top = 18;
		layout.senderName = senderName;
		layout.senderFrame = CGRectMake(x + kPadH, 2, bubbleW - 2 * kPadH, 14);
		CGFloat avatarY = MAX(2.0f, top + bubbleH - kAvatarSide);
		layout.senderAvatarFrame = CGRectMake(8, avatarY, kAvatarSide, kAvatarSide);
	}

	layout.bubbleFrame = CGRectMake(x, top, bubbleW, bubbleH);
	layout.inlineStamp = inlineStamp;
	layout.stampOnPicture = stampOnPicture;
	layout.timeWidth = timeW;
	layout.stamp = [self stampFor:m];
	layout.quoteText = quoted;
	layout.quoteAuthor = [self quoteAuthorFor:m];

	layout.tailFrame = CGRectZero;

	CGFloat y = kPadV + forwarded;
	if (quoted) {
		layout.quoteBarFrame = CGRectMake(kPadH, y, 2, 34);
		layout.quoteAuthorFrame = CGRectMake(kPadH + 8, y, bubbleW - 2 * kPadH - 10, 16);
		layout.quoteFrame = CGRectMake(kPadH + 8, y + 17, bubbleW - 2 * kPadH - 10, 17);
		y += 38;
	}
	CGFloat innerW = bubbleW - 2 * kPadH;
	if (isAlbum) {
		CGFloat cW = (body.height > 0) ? innerW : collageW;
		layout.collageFrame = CGRectMake(kPadH, y, cW, collageH);
		if (!body.height) {
			CGFloat plateW = timeW + (mine ? 28 : 14);
			layout.mediaStampFrame = CGRectMake(kPadH + collageW - plateW - 6, y + collageH - 22, plateW, 16);
		}
		y += collageH + 4;
	} else if (pic.height > 0) {
		CGFloat picW = (body.height > 0) ? innerW : pic.width;
		layout.pictureFrame = CGRectMake(kPadH, y, picW, pic.height);
		if (!body.height) {
			CGFloat plateW = timeW + (mine ? 28 : 14);
			layout.mediaStampFrame = CGRectMake(kPadH + pic.width - plateW - 6, y + pic.height - 22, plateW, 16);
		}
		y += pic.height + 4;
	}
	layout.bodyFrame = CGRectMake(kPadH, y, bubbleW - 2 * kPadH, body.height);
	CGFloat stampY = inlineStamp ? (y + body.height - 14) : (bubbleH - kPadV - 13);
	CGFloat tickW = mine ? 18 : 0;
	layout.timeFrame = CGRectMake(bubbleW - timeW - kPadH, stampY, timeW - tickW, 12);

	CGFloat rowH = kPadV * 2 + [self decorationHeightFor:m] +
			(inlineStamp || stampOnPicture ? 0 : 14);
	if (self.isGroup && !mine && senderName.length)
		rowH += 15;
	if (isAlbum) rowH += collageH + (body.height > 0 ? 4 : 0);
	else if (pic.height > 0) rowH += pic.height + 4;
	if (body.height > 0) rowH += body.height;
	if (isVoice) rowH = 62 + forwarded;

	layout.rowHeight = MAX(rowH + 6, 40);

	if (msgId) self.layoutCache[msgId] = layout;
	return layout;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *m = self.messages[indexPath.row];
	return [self layoutForMessage:m atRow:indexPath.row].rowHeight;
}

@end
