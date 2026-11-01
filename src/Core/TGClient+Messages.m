#import "TGClientInternal.h"

/// Reactions as one short line: emoji and count, most used first. Custom
/// emoji have no character to draw, so they are counted but not named.
NSString *TGReactionSummary(NSDictionary *m) {
	NSArray *reactions = m[@"interaction_info"][@"reactions"][@"reactions"];
	if (![reactions isKindOfClass:NSArray.class] || !reactions.count)
		return nil;

	NSMutableArray *parts = [NSMutableArray array];
	for (NSDictionary *r in reactions){
		NSString *emoji = r[@"type"][@"emoji"];
		NSInteger count = [r[@"total_count"] integerValue];
		[parts addObject:[NSString stringWithFormat:@"%@ %ld",
				emoji.length ? emoji : @"\U00002B50", (long)count]];
	}
	return [parts componentsJoinedByString:@"  "];
}

/// The emoji of your own reaction on a message, or nil if you have not
/// reacted. TDLib marks it with is_chosen; a custom emoji has no character to
/// compare, so it does not count as one that can be toggled.
NSString *TGMyReactionEmoji(NSDictionary *m) {
	NSArray *reactions = m[@"interaction_info"][@"reactions"][@"reactions"];
	if (![reactions isKindOfClass:NSArray.class])
		return nil;
	for (NSDictionary *r in reactions){
		if (![r[@"is_chosen"] boolValue])
			continue;
		NSString *emoji = r[@"type"][@"emoji"];
		if (emoji.length)
			return emoji;
	}
	return nil;
}

/// One button as the chat needs it: "text", a "kind" (callback, url, login,
/// switch, copy, user, or unsupported for what this client cannot do -
/// web apps, payments, games, password callbacks) and what that kind needs.
static NSDictionary *TGFlattenInlineButton(NSDictionary *button) {
	NSDictionary *type = button[@"type"];
	NSString *t = type[@"@type"] ?: @"";
	NSMutableDictionary *out = [@{@"text" : button[@"text"] ?: @"", @"kind" : @"unsupported"} mutableCopy];
	if ([t isEqualToString:@"inlineKeyboardButtonTypeCallback"]) {
		out[@"kind"] = @"callback";
		out[@"data"] = type[@"data"] ?: @"";      // base64, as TDLib's JSON spells bytes
	} else if ([t isEqualToString:@"inlineKeyboardButtonTypeUrl"]) {
		out[@"kind"] = @"url";
		out[@"url"] = type[@"url"] ?: @"";
	} else if ([t isEqualToString:@"inlineKeyboardButtonTypeLoginUrl"]) {
		out[@"kind"] = @"login";
		out[@"url"] = type[@"url"] ?: @"";
		out[@"buttonId"] = type[@"id"] ?: @0;
	} else if ([t isEqualToString:@"inlineKeyboardButtonTypeSwitchInline"]) {
		out[@"kind"] = @"switch";
		out[@"query"] = type[@"query"] ?: @"";
	} else if ([t isEqualToString:@"inlineKeyboardButtonTypeCopyText"]) {
		out[@"kind"] = @"copy";
		out[@"copy"] = type[@"text"] ?: @"";
	} else if ([t isEqualToString:@"inlineKeyboardButtonTypeUser"]) {
		out[@"kind"] = @"user";
		out[@"userId"] = type[@"user_id"] ?: @0;
	}
	return out;
}

/// A message's reply_markup as the chat draws it: "inlineRows" (rows of
/// flattened buttons under the bubble), "replyKeyboard" ("rows" of plain
/// button texts, "oneTime", "placeholder") or "removeKeyboard". Nil for none.
NSDictionary *TGFlattenReplyMarkup(NSDictionary *markup) {
	NSString *t = markup[@"@type"];
	if ([t isEqualToString:@"replyMarkupInlineKeyboard"]) {
		NSMutableArray *rows = [NSMutableArray array];
		for (NSArray *row in markup[@"rows"]) {
			if (![row isKindOfClass:NSArray.class] || !row.count)
				continue;
			NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:row.count];
			for (NSDictionary *b in row)
				[buttons addObject:TGFlattenInlineButton(b)];
			[rows addObject:buttons];
		}
		return rows.count ? @{@"inlineRows" : rows} : nil;
	}
	if ([t isEqualToString:@"replyMarkupShowKeyboard"]) {
		NSMutableArray *rows = [NSMutableArray array];
		for (NSArray *row in markup[@"rows"]) {
			NSMutableArray *texts = [NSMutableArray array];
			for (NSDictionary *b in row)
				// Phone, location, poll and peer requests need flows this
				// client has not got; their label still sends as text, which
				// is what the bot sees from a client that cannot do them.
				if ([b[@"text"] length])
					[texts addObject:b[@"text"]];
			if (texts.count)
				[rows addObject:texts];
		}
		if (!rows.count)
			return nil;
		return @{@"replyKeyboard" : @{@"rows" : rows,
									  @"oneTime" : markup[@"one_time"] ?: @NO,
									  @"placeholder" : markup[@"input_field_placeholder"] ?: @""}};
	}
	if ([t isEqualToString:@"replyMarkupRemoveKeyboard"])
		return @{@"removeKeyboard" : @YES};
	return nil;
}

/// Converts camelCase message type name to readable phrase, the first letter
/// capitalized ("messageVideoChatStarted" -> "Video chat started",
/// "somethingElse" -> "Something else").
NSString *TGPhraseFromTypeName(NSString *ctype) {
	NSString *rest = [ctype hasPrefix:@"message"] ? [ctype substringFromIndex:7] : ctype;
	if (!rest.length)
		return @"Message";

	NSMutableString *out = [NSMutableString stringWithCapacity:rest.length + 8];
	for (NSUInteger i = 0; i < rest.length; i++){
		unichar c = [rest characterAtIndex:i];
		if (i == 0 && c >= 'a' && c <= 'z')
			[out appendFormat:@"%C", (unichar)(c - 'a' + 'A')];
		else if (i > 0 && c >= 'A' && c <= 'Z'){
			[out appendString:@" "];
			[out appendFormat:@"%C", (unichar)(c - 'A' + 'a')];
		} else {
			[out appendFormat:@"%C", c];
		}
	}
	return out;
}

/// Flatten a TDLib message into what the UI needs.
NSDictionary *TGFlattenMessage(NSDictionary *m) {
	NSDictionary *content = m[@"content"];
	NSString *ctype = content[@"@type"];
	NSNumber *photoFileId = nil;   // an image to show in the bubble
	NSNumber *docFileId   = nil;   // a file to play or offer for download
	NSNumber *docSize     = nil;   // its size in bytes, where it matters
	NSString *docName     = nil;
	NSString *extra       = nil;   // text the content itself carries
	NSNumber *latitude = nil, *longitude = nil;
	NSDictionary *contactDict = nil;
	NSDictionary *venueDict   = nil;
	NSNumber *duration = nil;
	NSData *waveform = nil;
	NSString *audioTitle = nil, *audioPerformer = nil;
	NSNumber *albumCoverId = nil;
	BOOL isService = NO;
	NSString *callState = nil;     // "missed" or "answered" on a call message
	BOOL liveEditable = NO;        // a live location with time left to edit
	NSDictionary *pollInfo = @{};  // what the poll of this message still allows

	NSNumber *bigPhotoFileId = nil;
	int mediaWidth = 0, mediaHeight = 0;

	if ([ctype isEqualToString:@"messagePhoto"]){
		NSArray *sizes = content[@"photo"][@"sizes"];
		if (sizes.count){
			bigPhotoFileId = [sizes lastObject][@"photo"][@"id"];
			NSDictionary *chosen = sizes[0];
			for (NSDictionary *s in sizes){
				int w = [s[@"width"] intValue];
				int h = [s[@"height"] intValue];
				int maxDim = MAX(w, h);
				if (maxDim >= 200 && maxDim <= 640){
					chosen = s;
					break;
				} else if (maxDim > 0 && maxDim < 640){
					chosen = s;
				}
			}
			photoFileId = chosen[@"photo"][@"id"];
			mediaWidth = [chosen[@"width"] intValue];
			mediaHeight = [chosen[@"height"] intValue];
			if (mediaWidth == 0 && sizes.count > 0){
				mediaWidth = [[sizes lastObject][@"width"] intValue];
				mediaHeight = [[sizes lastObject][@"height"] intValue];
			}
		}

	} else if ([ctype isEqualToString:@"messageVideo"]){
		photoFileId = content[@"video"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"video"][@"video"][@"id"];
		docName     = content[@"video"][@"file_name"];
		mediaWidth  = [content[@"video"][@"width"] intValue];
		mediaHeight = [content[@"video"][@"height"] intValue];
		if (!duration) duration = content[@"video"][@"duration"];

	} else if ([ctype isEqualToString:@"messageVideoNote"]){
		photoFileId = content[@"video_note"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"video_note"][@"video"][@"id"];
		int len     = [content[@"video_note"][@"length"] intValue];
		mediaWidth  = len ?: 240;
		mediaHeight = len ?: 240;
		if (!duration) duration = content[@"video_note"][@"duration"];

	} else if ([ctype isEqualToString:@"messageAnimation"]){
		// Telegram GIFs are MP4, so they play like any video.
		photoFileId = content[@"animation"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"animation"][@"animation"][@"id"];
		docSize     = content[@"animation"][@"animation"][@"size"] ?:
					  content[@"animation"][@"animation"][@"expected_size"];
		docName     = content[@"animation"][@"file_name"];
		mediaWidth  = [content[@"animation"][@"width"] intValue];
		mediaHeight = [content[@"animation"][@"height"] intValue];

	} else if ([ctype isEqualToString:@"messageSticker"] ||
			   [ctype isEqualToString:@"messageAnimatedEmoji"]){
		NSDictionary *sticker = [ctype isEqualToString:@"messageSticker"]
			? content[@"sticker"]
			: content[@"animated_emoji"][@"sticker"];
		NSString *format = sticker[@"format"][@"@type"];

		if ([format isEqualToString:@"stickerFormatTgs"]){
			// Lottie vector animation - TGLottieView plays it. The thumbnail
			// is kept as what to show until the file arrives.
			docFileId   = sticker[@"sticker"][@"id"];
			photoFileId = sticker[@"thumbnail"][@"file"][@"id"];
			docName     = @"tgs";
		} else if ([format isEqualToString:@"stickerFormatWebm"]){
			// WebM VP9 video animation - TGLottieView plays it via TGWebMDecoder.
			docFileId   = sticker[@"sticker"][@"id"];
			photoFileId = sticker[@"thumbnail"][@"file"][@"id"];
			docName     = @"webm";
		} else if ([format isEqualToString:@"stickerFormatWebp"]){
			photoFileId = sticker[@"sticker"][@"id"];
		} else {
			// fallback
			photoFileId = sticker[@"thumbnail"][@"file"][@"id"];
		}

		extra = content[@"emoji"] ?: sticker[@"emoji"];

	} else if ([ctype isEqualToString:@"messageDocument"]){
		photoFileId = content[@"document"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"document"][@"document"][@"id"];
		docName     = content[@"document"][@"file_name"];
		NSNumber *size = content[@"document"][@"document"][@"size"];
		docSize     = size ?: content[@"document"][@"document"][@"expected_size"];
		extra = size.longLongValue > 0
			? [NSString stringWithFormat:@"%@\n%.1f KB", docName ?: @"Document",
					size.doubleValue / 1024.0]
			: (docName ?: @"Document");

	} else if ([ctype isEqualToString:@"messageVoiceNote"]){
		docFileId = content[@"voice_note"][@"voice"][@"id"];
		duration  = content[@"voice_note"][@"duration"];
		// Telegram sends the shape of the sound with the message: five bits
		// per sample, which is what the bars in the bubble are drawn from.
		waveform  = [[NSData alloc] initWithBase64EncodedString:
				content[@"voice_note"][@"waveform"] ?: @"" options:0];
		extra = @"";

	} else if ([ctype isEqualToString:@"messageAudio"]){
		docFileId = content[@"audio"][@"audio"][@"id"];
		docName   = content[@"audio"][@"file_name"];
		// A track has a name and a performer of its own, and a player that has
		// to fall back to the file name has nothing to put on a lock screen.
		audioTitle     = content[@"audio"][@"title"];
		audioPerformer = content[@"audio"][@"performer"];
		duration       = content[@"audio"][@"duration"];
		albumCoverId   = content[@"audio"][@"album_cover_thumbnail"][@"file"][@"id"];
		extra = [audioTitle length] ? audioTitle : (docName ?: @"Audio");

	} else if ([ctype isEqualToString:@"messageContact"]){
		NSDictionary *c = content[@"contact"];
		NSString *name = [[NSString stringWithFormat:@"%@ %@",
				c[@"first_name"] ?: @"", c[@"last_name"] ?: @""]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!name.length)
			name = c[@"phone_number"] ?: @"Contact";
		extra = [NSString stringWithFormat:@"%@\n%@", name, c[@"phone_number"] ?: @""];
		contactDict = @{
			@"name"        : name,
			@"firstName"   : c[@"first_name"] ?: @"",
			@"lastName"    : c[@"last_name"] ?: @"",
			@"phoneNumber" : c[@"phone_number"] ?: @"",
			@"userId"      : c[@"user_id"] ?: @(0),
			@"vcard"       : c[@"vcard"] ?: @"",
		};

	} else if ([ctype isEqualToString:@"messageVenue"]){
		NSDictionary *v = content[@"venue"];
		extra = [NSString stringWithFormat:@"%@\n%@",
				v[@"title"] ?: @"", v[@"address"] ?: @""];
		latitude  = v[@"location"][@"latitude"];
		longitude = v[@"location"][@"longitude"];
		venueDict = @{
			@"title"   : v[@"title"] ?: @"",
			@"address" : v[@"address"] ?: @"",
		};

	} else if ([ctype isEqualToString:@"messageChatAddMembers"]){
		NSMutableArray *names = [NSMutableArray array];
		for (NSNumber *uid in content[@"member_user_ids"])
			[names addObject:[[TGClient shared] nameForUserId:uid.longLongValue] ?: @"someone"];
		extra = [NSString stringWithFormat:@"%@ joined the group",
				[names componentsJoinedByString:@", "]];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatDeleteMember"]){
		NSString *who = [[TGClient shared] nameForUserId:
				[content[@"user_id"] longLongValue]] ?: @"someone";
		extra = [NSString stringWithFormat:@"%@ left the group", who];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatJoinByLink"] ||
			   [ctype isEqualToString:@"messageChatJoinByRequest"]){
		extra = @"joined the group via invite link";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatChangeTitle"]){
		extra = [NSString stringWithFormat:@"Group renamed to \"%@\"",
				content[@"title"] ?: @""];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatChangePhoto"]){
		extra = @"Group photo changed";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatDeletePhoto"]){
		extra = @"Group photo removed";
		isService = YES;

	} else if ([ctype isEqualToString:@"messagePinMessage"]){
		extra = @"pinned a message";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageBasicGroupChatCreate"] ||
			   [ctype isEqualToString:@"messageSupergroupChatCreate"]){
		extra = [NSString stringWithFormat:@"Group \"%@\" created",
				content[@"title"] ?: @""];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatUpgradeTo"] ||
			   [ctype isEqualToString:@"messageChatUpgradeFrom"]){
		extra = @"Group upgraded to a supergroup";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatSetTheme"]){
		extra = @"Chat theme changed";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageScreenshotTaken"]){
		extra = @"Screenshot taken";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageCall"]){
		// A call is a row of its own, not a service line: it says which way it
		// went and whether it was answered, and it can be returned with a tap.
		NSNumber *dur = content[@"duration"];
		NSString *reason = content[@"discard_reason"][@"@type"];
		BOOL missed = [reason isEqualToString:@"callDiscardReasonMissed"] ||
					  [reason isEqualToString:@"callDiscardReasonDeclined"];
		BOOL outgoing = [m[@"is_outgoing"] boolValue];

		extra = missed
			? (outgoing ? @"Cancelled call" : @"Missed call")
			: (outgoing ? @"Outgoing call" : @"Incoming call");
		if (!missed && dur.integerValue > 0)
			extra = [NSString stringWithFormat:@"%@, %ld:%02ld", extra,
					(long)(dur.integerValue / 60), (long)(dur.integerValue % 60)];
		callState = missed ? @"missed" : @"answered";
		isService = NO;

	} else if ([ctype isEqualToString:@"messageDice"]){
		extra = [NSString stringWithFormat:@"%@  %@",
				content[@"emoji"] ?: @"Dice", content[@"value"] ?: @""];

	} else if ([ctype isEqualToString:@"messageGame"]){
		extra = [NSString stringWithFormat:@"Game: %@",
				content[@"game"][@"title"] ?: @""];

	} else if ([ctype isEqualToString:@"messageUnsupported"]){
		extra = @"Message not supported on this client";
		isService = YES;

	} else if ([ctype isEqualToString:@"messagePoll"]){
		// Rendered by the chat as a question with its options and their share
		// of the vote; the flattened form carries them as one block of text.
		NSDictionary *poll = content[@"poll"];
		NSMutableString *lines = [NSMutableString stringWithFormat:@"%@\n",
				poll[@"question"][@"text"] ?: poll[@"question"] ?: @"Poll"];
		NSInteger total = [poll[@"total_voter_count"] integerValue];
		BOOL deletable = NO;
		for (NSDictionary *option in poll[@"options"]){
			[lines appendFormat:@"%@  %@%ld%%\n",
					[option[@"is_chosen"] boolValue] ? @"\u25c9" : @"\u25cb",
					option[@"text"][@"text"] ?: option[@"text"] ?: @"",
					(long)[option[@"vote_percentage"] integerValue]];
			if ([option[@"properties"][@"can_be_deleted"] boolValue])
				deletable = YES;
		}
		[lines appendFormat:@"%ld voted", (long)total];
		extra = lines;
		isService = NO;
		// The menu asks what the poll still allows: voters, an open vote,
		// options deleted after the fact.
		pollInfo = @{
			@"voters"    : poll[@"can_get_voters"] ?: @NO,
			@"open"      : @(![poll[@"is_closed"] boolValue]),
			@"deletable" : @(deletable),
			@"stats"     : poll[@"can_get_poll_vote_statistics"] ?: @NO,
		};

	} else if ([ctype isEqualToString:@"messageLocation"]){
		NSDictionary *loc = content[@"location"];
		extra = @"Location";
		latitude  = loc[@"latitude"];
		longitude = loc[@"longitude"];

	} else if ([ctype isEqualToString:@"messageLiveLocation"]){
		// The same card as a fixed point, said differently: a live location is
		// a place that keeps changing, and the map is still worth drawing.
		NSDictionary *loc = content[@"location"];
		extra = [NSString stringWithFormat:@"Live location · %ld s left",
				(long)[content[@"expires_in"] integerValue]];
		latitude  = loc[@"location"][@"latitude"];
		longitude = loc[@"location"][@"longitude"];
		liveEditable = [content[@"expires_in"] integerValue] > 0;

	} else if ([ctype isEqualToString:@"messageInvoice"]){
		NSInteger amount = [content[@"total_amount"] integerValue];
		NSString *currency = content[@"currency"] ?: @"";
		extra = amount > 0
			? [NSString stringWithFormat:@"%@\n%.2f %@", content[@"product_info"][@"title"]
					?: content[@"title"] ?: @"Invoice", amount / 100.0, currency]
			: (content[@"product_info"][@"title"] ?: @"Invoice");

	} else if ([ctype isEqualToString:@"messageStory"]){
		extra = @"Story";

	} else if ([ctype isEqualToString:@"messagePaidMedia"]){
		extra = [NSString stringWithFormat:@"Paid media, %@ stars",
				content[@"star_count"] ?: @0];

	} else if ([ctype isEqualToString:@"messageChecklist"]){
		NSDictionary *list = content[@"checklist"];
		NSMutableString *lines = [NSMutableString stringWithFormat:@"%@\n",
				list[@"title"][@"text"] ?: @"Checklist"];
		for (NSDictionary *task in list[@"tasks"])
			[lines appendFormat:@"%@ %@\n",
					task[@"completed_by_user_id"] ? @"☑" : @"☐",
					task[@"text"][@"text"] ?: @""];
		extra = [lines stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	} else if ([ctype hasPrefix:@"messageExpired"]){
		// A self-destructing photo that has gone. Saying so is the whole
		// content; an empty bubble would look like a bug.
		extra = @"Expired media";
		isService = YES;

	}

	// A caption wins; then whatever the content itself says; and for a plain
	// picture, nothing at all - the image speaks for itself.
	NSString *caption = content[@"caption"][@"text"];
	NSString *text;
	if (caption.length)      text = caption;
	else if (extra.length)   text = extra;
	else if (photoFileId)    text = @"";
	else {
		// The preview knows the common types by name. When it does not,
		// nobody has a branch for this content anywhere - the phrase
		// fallback below speaks instead, and it is a system notice, not a
		// regular message.
		NSString *known = TGKnownMessagePreview(m);
		text        = known ?: TGPhraseFromTypeName(ctype);
		isService  |= known == nil;
	}

	// A content type with its own branch can still say nothing - an empty
	// text message, say. An empty bubble reads as a bug, so it says what it
	// is as a service line. The unknown types never reach this: the preview
	// above already gave them their phrase, as a service line.
	if (!text.length && !photoFileId && !docFileId && !latitude){
		text = TGPhraseFromTypeName(ctype);
		isService = YES;
	}

	// Reply, forward and edit state - three things a chat is unreadable
	// without, because a bare answer loses what it answers.
	NSDictionary *replyTo = m[@"reply_to"];
	NSNumber *replyId = nil;
	NSString *replyText = nil;
	if ([replyTo[@"@type"] isEqualToString:@"messageReplyToMessage"]){
		replyId = replyTo[@"message_id"];
		// Newer TDLib carries the quoted text inline; otherwise the chat view
		// fetches the original by id.
		replyText = replyTo[@"quote"][@"text"][@"text"] ?: replyTo[@"quote"][@"text"];
	}

	NSString *forwardFrom = nil;
	NSDictionary *origin = m[@"forward_info"][@"origin"];
	NSString *originType = origin[@"@type"];
	if ([originType isEqualToString:@"messageOriginUser"])
		forwardFrom = [[TGClient shared] nameForUserId:
				[origin[@"sender_user_id"] longLongValue]] ?: @"a user";
	else if ([originType isEqualToString:@"messageOriginHiddenUser"])
		forwardFrom = origin[@"sender_name"];
	else if ([originType isEqualToString:@"messageOriginChannel"]){
		NSString *signature = origin[@"author_signature"];
		forwardFrom = signature.length ? signature : @"a channel";
	}
	else if ([originType isEqualToString:@"messageOriginChat"])
		forwardFrom = origin[@"author_signature"] ?: @"a chat";

	// The one reactor the message menu can name for a report: the latest
	// sender of the first reaction group that hands its senders over, user
	// senders only - a channel campaign is a chat-admin problem, not a
	// per-reaction report.
	NSDictionary *reactionReport = nil;
	NSArray *reactionGroups = m[@"interaction_info"][@"reactions"][@"reactions"];
	for (NSDictionary *group in reactionGroups){
		if (![group isKindOfClass:NSDictionary.class])
			continue;
		NSArray *senders = group[@"recent_sender_ids"];
		NSDictionary *send = [senders isKindOfClass:NSArray.class]
				? senders.firstObject : nil;
		NSInteger reactionUserId = [send isKindOfClass:NSDictionary.class]
				? [send[@"user_id"] longLongValue] : 0;
		if (!reactionUserId)
			continue;
		NSString *who = [[TGClient shared] nameForUserId:reactionUserId]
				?: @"someone";
		NSString *emoji = group[@"type"][@"emoji"];
		reactionReport = @{
			@"emoji"  : emoji.length ? emoji : @"\U00002B50",
			@"userId" : @(reactionUserId),
			@"sender" : send,
			@"name"   : who,
		};
		break;
	}

	return @{
		@"id"        : m[@"id"] ?: @(0),
		@"text"      : text,
		@"replyId"   : replyId    ?: [NSNull null],
		@"replyText" : replyText  ?: @"",
		@"forward"   : forwardFrom ?: @"",
		@"edited"    : @([m[@"edit_date"] doubleValue] > 0),
		@"kind"      : ctype ?: @"",
		@"date"      : m[@"date"] ?: @(0),
		@"outgoing"  : m[@"is_outgoing"] ?: @NO,
		@"photoId"   : photoFileId ?: [NSNull null],
		@"bigPhotoId": bigPhotoFileId ?: (photoFileId ?: [NSNull null]),
		@"mediaWidth": @(mediaWidth),
		@"mediaHeight": @(mediaHeight),
		@"docId"     : docFileId   ?: [NSNull null],
		@"docName"   : docName     ?: @"",
		@"docSize"   : docSize     ?: @(0),
		@"service"   : @(isService),
		// Several photos sent together share an album id; the chat draws them
		// as one block rather than as unrelated messages.
		@"albumId"   : m[@"media_album_id"] ?: @"",
		// "\U0001F44D 3" per reaction, joined - enough to show under a bubble.
		@"reactions" : TGReactionSummary(m) ?: @"",
		// Your own reaction, so the menu can offer to take it off.
		@"myReaction" : TGMyReactionEmoji(m) ?: @"",
		// Buttons a bot put under its message, and the keyboard it asked for.
		@"inlineRows" : TGFlattenReplyMarkup(m[@"reply_markup"])[@"inlineRows"] ?: @[],
		// A channel post with a discussion group under it: reply_info is set
		// there (count 0 included) and the post can open its comments.
		// Messages inside the discussion group carry reply_info too, and are
		// not posts, so is_channel_post decides.
		@"canComment" : @([m[@"is_channel_post"] boolValue]
				&& [m[@"interaction_info"][@"reply_info"] isKindOfClass:NSDictionary.class]),
		@"replyCount" : m[@"interaction_info"][@"reply_info"][@"reply_count"] ?: @0,
		@"reactionReport" : reactionReport ?: [NSNull null],
		// A message TDLib could not get out. It stays in the history with a
		// sending state that says so, and it is the only kind worth resending.
		@"failed"    : @([m[@"sending_state"][@"@type"]
				isEqualToString:@"messageSendingStateFailed"]),
		// Options of a poll, so tapping one can vote, and the parts the chat
		// draws around them.
		@"pollOptions"  : m[@"content"][@"poll"][@"options"] ?: @[],
		@"pollQuestion" : m[@"content"][@"poll"][@"question"][@"text"] ?: @"",
		@"pollTotal"    : m[@"content"][@"poll"][@"total_voter_count"] ?: @0,
		@"pollClosed"   : m[@"content"][@"poll"][@"is_closed"] ?: @NO,
		@"pollVoters"   : (pollInfo[@"voters"] ?: @NO),
		@"pollStats"    : (pollInfo[@"stats"] ?: @NO),
		@"pollOpen"     : (pollInfo[@"open"] ?: @NO),
		@"pollDeletable": (pollInfo[@"deletable"] ?: @NO),
		@"pollAnonymous": m[@"content"][@"poll"][@"is_anonymous"] ?: @YES,
		@"liveEditable": @(liveEditable),
		@"duration"  : duration ?: @0,
		// A voice note nobody has listened to, or a round note nobody has
		// watched. Telegram draws both as not-yet-heard until they are, so
		// the chat has to know which ones they are.
		@"unplayed"  : @(([ctype isEqualToString:@"messageVoiceNote"] &&
							![content[@"is_listened"] boolValue]) ||
						 ([ctype isEqualToString:@"messageVideoNote"] &&
							![content[@"is_viewed"] boolValue])),
		@"waveform"  : waveform ?: [NSData data],
		@"audioTitle"     : audioTitle     ?: @"",
		@"audioPerformer" : audioPerformer ?: @"",
		@"albumCoverId"   : albumCoverId   ?: [NSNull null],
		@"senderId"  : m[@"sender_id"][@"user_id"] ?: @(0),
		@"lat"       : latitude    ?: [NSNull null],
		@"lon"       : longitude   ?: [NSNull null],
		@"callState" : callState   ?: @"",
		@"contact"   : contactDict ?: [NSNull null],
		@"venue"     : venueDict   ?: [NSNull null],
		@"entities"  : ([content[@"caption"] isKindOfClass:[NSDictionary class]] && content[@"caption"][@"entities"])
							? content[@"caption"][@"entities"]
							: (([content[@"text"] isKindOfClass:[NSDictionary class]] && content[@"text"][@"entities"])
								? content[@"text"][@"entities"] : @[]),
	};
}

@implementation TGClient (Messages)

#pragma mark - messages

- (void)historyForChat:(int64_t)chatId
                thread:(int64_t)threadId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *))completion {
	if (threadId == 0){
		[self historyForChat:chatId limit:limit completion:completion];
		return;
	}

	// A topic is a message thread, and threads have their own history call.
	[self request:@{
		@"@type"           : @"getMessageThreadHistory",
		@"chat_id"         : @(chatId),
		@"message_id"      : @(threadId),
		@"from_message_id" : @(0),
		@"offset"          : @(0),
		@"limit"           : @(limit),
	} completion:^(NSDictionary *result){
		NSArray *msgs = result[@"messages"];
		if (![msgs isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: thread history -> %@", result[@"@type"]);
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
		for (NSDictionary *m in [[msgs reverseObjectEnumerator] allObjects])
			[out addObject:TGFlattenMessage(m)];
		if (completion) completion(out);
	}];
}

/// Presses a callback button. The bot answers with a line to show
/// ("text", as an alert when "alert"), a link to open ("url"), or nothing.
- (void)pressCallbackButton:(NSDictionary *)button
					 inChat:(int64_t)chatId
				  messageId:(int64_t)messageId
				 completion:(void (^)(NSString *text, BOOL alert, NSString *url,
									  NSString *error))completion {
	[self request:@{@"@type" : @"getCallbackQueryAnswer",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"payload" : @{@"@type" : @"callbackQueryPayloadData",
								   @"data" : button[@"data"] ?: @""}}
	   completion:^(NSDictionary *answer){
		if (!completion)
			return;
		if (![answer[@"@type"] isEqualToString:@"callbackQueryAnswer"]) {
			NSString *message = answer[@"message"];
			completion(nil, NO, nil, message.length ? message : @"The bot did not answer.");
			return;
		}
		completion(answer[@"text"], [answer[@"show_alert"] boolValue], answer[@"url"], nil);
	}];
}

/// A login button signs the user into the bot's site. Telegram either hands
/// the link back at once ("url") or wants the user to agree first
/// ("confirmDomain"), after which confirmLoginButton: fetches the link.
- (void)loginURLForButton:(NSDictionary *)button
				   inChat:(int64_t)chatId
				messageId:(int64_t)messageId
			   completion:(void (^)(NSString *url, NSString *confirmDomain,
									NSString *error))completion {
	[self request:@{@"@type" : @"getLoginUrlInfo",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"button_id" : button[@"buttonId"] ?: @0}
	   completion:^(NSDictionary *info){
		if (!completion)
			return;
		NSString *t = info[@"@type"];
		if ([t isEqualToString:@"loginUrlInfoOpen"])
			completion(info[@"url"], nil, nil);
		else if ([t isEqualToString:@"loginUrlInfoRequestConfirmation"])
			completion(nil, info[@"domain"] ?: info[@"url"], nil);
		else
			// No login on offer: the button's plain address still opens.
			completion(button[@"url"], nil, nil);
	}];
}

- (void)confirmLoginButton:(NSDictionary *)button
					inChat:(int64_t)chatId
				 messageId:(int64_t)messageId
				completion:(void (^)(NSString *url, NSString *error))completion {
	[self request:@{@"@type" : @"getLoginUrl",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"button_id" : button[@"buttonId"] ?: @0,
					@"allow_write_access" : @NO}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *url = result[@"url"];
		completion(url.length ? url : nil, url.length ? nil : (result[@"message"] ?: @"Telegram refused that."));
	}];
}

/// The keyboard a bot left on this chat, or nil. The chat names the message
/// that carries it; it is fetched once and kept on the chat record.
- (void)replyKeyboardForChat:(int64_t)chatId completion:(void (^)(NSDictionary *keyboard))completion {
	NSMutableDictionary *chat = self.chatsById[@(chatId)];
	id kept = chat[@"replyKeyboard"];
	if (kept) {
		if (completion) completion([kept isKindOfClass:NSDictionary.class] ? kept : nil);
		return;
	}
	int64_t messageId = [chat[@"replyMarkupMessageId"] longLongValue];
	if (!messageId) {
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getMessage", @"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *m){
		NSDictionary *keyboard = TGFlattenReplyMarkup(m[@"reply_markup"])[@"replyKeyboard"];
		self.chatsById[@(chatId)][@"replyKeyboard"] = keyboard ?: [NSNull null];
		if (completion) completion(keyboard);
	}];
}

/// The comments under a channel post live in its discussion group, as a
/// thread there. TDLib answers with that group's chat id and the thread id,
/// which is what a chat screen opens with; `error` is set instead when the
/// post has no comments to open.
- (void)commentThreadForChat:(int64_t)chatId
				   messageId:(int64_t)messageId
				  completion:(void (^)(int64_t discussionChatId, int64_t threadId,
									   NSString *error))completion {
	[self request:@{@"@type" : @"getMessageThread",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		int64_t discussion = [result[@"chat_id"] longLongValue];
		int64_t thread = [result[@"message_thread_id"] longLongValue];
		if (![result[@"@type"] isEqualToString:@"messageThreadInfo"] || !discussion || !thread) {
			NSString *message = result[@"message"];
			completion(0, 0, message.length ? message : @"These comments cannot be opened.");
			return;
		}
		completion(discussion, thread, nil);
	}];
}

- (void)searchMessages:(NSString *)query completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"  : @"searchMessages",
		@"query"  : query ?: @"",
		@"limit"  : @(50),
		@"offset" : @"",
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSMutableDictionary *flat = [TGFlattenMessage(m) mutableCopy];
			if (!flat) continue;
			int64_t chatId = [m[@"chat_id"] longLongValue];
			flat[@"chatId"] = @(chatId);
			flat[@"chatTitle"] = [me titleForChat:chatId] ?: @"";
			[out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

- (void)searchInChat:(int64_t)chatId query:(NSString *)query
          completion:(void (^)(NSArray *))completion {
	// A secret chat answers its own spelling: searchChatMessages refuses
	// a non-empty query there, searchSecretMessages is the one TDLib takes.
	NSDictionary *info = self.chatsById[@(chatId)];
	BOOL secret = [info[@"isSecret"] boolValue];
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : secret ? @"searchSecretMessages"
									: @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : query ?: @"",
		@"offset"          : secret ? @"" : @(0),
		@"limit"           : @(50),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSDictionary *flat = TGFlattenMessage(m);
			if (flat) [out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

/// Title of a chat we already know about, for search results that name it.
- (NSString *)titleForChat:(int64_t)chatId {
	for (NSDictionary *c in self.chats)
		if ([c[@"id"] longLongValue] == chatId)
			return c[@"title"];
	for (NSDictionary *c in self.archivedChats)
		if ([c[@"id"] longLongValue] == chatId)
			return c[@"title"];
	return nil;
}

- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *))completion {
    [self historyForChat:chatId fromMessageId:0 limit:limit completion:completion];
}

- (void)historyForChat:(int64_t)chatId
         fromMessageId:(int64_t)fromMessageId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *))completion {
	[self historyForChat:chatId fromMessageId:fromMessageId offset:0 limit:limit completion:completion];
}

- (void)newerHistoryForChat:(int64_t)chatId
              fromMessageId:(int64_t)fromMessageId
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *))completion {
	[self historyForChat:chatId fromMessageId:fromMessageId offset:-limit limit:limit completion:completion];
}

- (void)historyForChat:(int64_t)chatId
         fromMessageId:(int64_t)fromMessageId
                offset:(NSInteger)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *))completion {
	// getChatHistory returns only what TDLib already holds, and picks the
	// batch size itself - a first call on a cold chat often answers with one
	// message. Walk backwards (or forwards if offset < 0) until we have enough.
	NSMutableArray *collected = [NSMutableArray array];
	[self fetchHistoryChunkForChat:chatId
					 fromMessageId:fromMessageId
							offset:offset
							 limit:limit
						 collected:collected
						completion:completion];
}

- (void)fetchHistoryChunkForChat:(int64_t)chatId
                   fromMessageId:(int64_t)fromMessageId
                          offset:(NSInteger)offset
                           limit:(NSInteger)limit
                       collected:(NSMutableArray *)collected
                      completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"getChatHistory",
		@"chat_id"         : @(chatId),
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(offset),
		@"limit"           : @(limit),
		@"only_local"      : @NO,
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSArray *msgs = result[@"messages"];

		if (!me || ![msgs isKindOfClass:NSArray.class] || msgs.count == 0){
			// End of the chat, or an error - hand back what we have, oldest
			// first, which is the order a chat view wants.
			if (completion)
				completion([[collected reverseObjectEnumerator] allObjects]);
			return;
		}

		for (NSDictionary *m in msgs)
			[collected addObject:TGFlattenMessage(m)];

		if (offset < 0){
			// Fetching newer messages: TDLib returns messages newest first.
			// Reverse them so they are in chronological order (oldest first).
			if (completion)
				completion([[collected reverseObjectEnumerator] allObjects]);
			return;
		}

		int64_t oldest = [[msgs lastObject][@"id"] longLongValue];
		if ((NSInteger)collected.count >= limit || oldest == 0){
			if (completion)
				completion([[collected reverseObjectEnumerator] allObjects]);
			return;
		}

		[me fetchHistoryChunkForChat:chatId
					   fromMessageId:oldest
							  offset:0
							   limit:limit - collected.count
						   collected:collected
						  completion:completion];
	}];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId {
	[self sendText:text toChat:chatId thread:0];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId thread:(int64_t)threadId {
	[self sendText:text toChat:chatId thread:threadId replyTo:0];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId {
	NSMutableDictionary *request = [@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			// The markup the user typed is read here rather than sent as
			// literal asterisks.
			@"text"  : TGFormattedText(text),
		},
	} mutableCopy];

	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};

	[self send:request];
}

/// The same send held back: at a date, or the moment the other side is next
/// online. TDLib carries it as a scheduling state on the request itself, and
/// echoes back a message that is pending rather than sent.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId
           thread:(int64_t)threadId replyTo:(int64_t)replyToId
        scheduled:(NSDictionary *)schedulingState {
	NSMutableDictionary *request = [@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""},
		},
	} mutableCopy];

	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};
	if (schedulingState[@"@type"])
		request[@"scheduling_state"] = schedulingState;

	[self send:request];
}

/// At a wall-clock date. The date is int32 seconds, which is what the
/// request carries.
+ (NSDictionary *)scheduledAtDate:(NSTimeInterval)date {
	return @{@"@type"     : @"messageSchedulingStateSendAtDate",
			 @"send_date" : @(date),
			 @"repeat_period" : @(0)};
}

/// The moment the other side is next seen. Private chats only; TDLib
/// refuses it anywhere else, and the error is the answer.
+ (NSDictionary *)scheduledWhenOnline {
	return @{@"@type" : @"messageSchedulingStateSendWhenOnline"};
}

/// What a chat has waiting. The answer is a message list flattened exactly
/// as the history is, so the same rows draw from both.
- (void)scheduledMessagesInChat:(int64_t)chatId
					 completion:(void (^)(NSArray *messages))completion {
	[self request:@{@"@type" : @"getChatScheduledMessages", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSDictionary *flat = TGFlattenMessage(m);
			if (flat)
				[out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

/// A scheduling state can change while there is nothing to send yet: null
/// sends it now - TDLib's own meaning of the field - and a state moves it.
- (void)setSchedulingState:(NSDictionary *)state
			 forMessage:(int64_t)messageId
					inChat:(int64_t)chatId
				completion:(void (^)(BOOL ok))completion {
	// An optional object reads back as the JSON null TDLib documents for
	// "send immediately", which is not a dictionary.
	id value = state[@"@type"] ? state : [NSNull null];
	[self request:@{
		@"@type"            : @"editMessageSchedulingState",
		@"chat_id"          : @(chatId),
		@"message_id"       : @(messageId),
		@"scheduling_state" : value,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)forwardMessages:(NSArray *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId {
	[self send:@{
		@"@type"        : @"forwardMessages",
		@"chat_id"      : @(toChatId),
		@"from_chat_id" : @(fromChatId),
		@"message_ids"  : messageIds ?: @[],
	}];
}

- (void)editMessage:(int64_t)messageId inChat:(int64_t)chatId text:(NSString *)text {
	[self send:@{
		@"@type"                : @"editMessageText",
		@"chat_id"              : @(chatId),
		@"message_id"           : @(messageId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : TGFormattedText(text),
		},
	}];
}

/// The caption under a picture, a video or a file. A separate request from
/// editing text, which is why only text could be edited before.
- (void)editCaption:(NSString *)caption
		  ofMessage:(int64_t)messageId
			 inChat:(int64_t)chatId
		 completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"      : @"editMessageCaption",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"caption"    : TGFormattedText(caption),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// Replaces the picture itself, keeping the message where it is in the
/// history. The caption travels with it: editMessageMedia takes the whole
/// content, so leaving the caption out would clear it.
- (void)editPhotoAtPath:(NSString *)path
				caption:(NSString *)caption
			  ofMessage:(int64_t)messageId
				 inChat:(int64_t)chatId
			 completion:(void (^)(BOOL ok))completion {
	if (!path.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"      : @"editMessageMedia",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"input_message_content": @{
			@"@type"   : @"inputMessagePhoto",
			@"photo"   : @{@"@type" : @"inputFileLocal", @"path" : path},
			@"caption" : TGFormattedText(caption),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// Several pictures as one message. Their own client sends up to ten; the
/// album is one request, so the pictures arrive together rather than as a
/// run of separate messages that happen to be next to each other.
///
/// Only the first picture carries the caption - TDLib refuses an album where
/// more than one does.
- (void)sendPhotoAlbumAtPaths:(NSArray *)paths
					  caption:(NSString *)caption
					   toChat:(int64_t)chatId
					   thread:(int64_t)threadId {
	if (!paths.count)
		return;
	NSMutableArray *contents = [NSMutableArray array];
	for (NSUInteger i = 0; i < MIN(paths.count, (NSUInteger)10); i++){
		NSString *path = paths[i];
		if (![path isKindOfClass:NSString.class] || !path.length)
			continue;
		[contents addObject:@{
			@"@type"   : @"inputMessagePhoto",
			@"photo"   : @{@"@type" : @"inputFileLocal", @"path" : path},
			@"caption" : TGFormattedText(i == 0 ? caption : nil),
		}];
	}
	if (!contents.count)
		return;
	[self send:@{
		@"@type"                  : @"sendMessageAlbum",
		@"chat_id"                : @(chatId),
		@"message_thread_id"      : @(threadId),
		@"input_message_contents" : contents,
	}];
}

- (void)messageWithId:(int64_t)messageId
               inChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *m){
		if (completion)
			completion([m[@"@type"] isEqualToString:@"message"]
					? TGFlattenMessage(m) : nil);
	}];
}

- (void)recentStickersWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getRecentStickers", @"is_attached" : @NO}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sticker in result[@"stickers"]){
			NSDictionary *info = TGStickerInfo(sticker);
			if (info)
				[out addObject:info];
		}
		if (completion) completion(out);
	}];
}

- (void)sendStickerWithFileId:(NSInteger)fileId toChat:(int64_t)chatId thread:(int64_t)threadId {
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		// This TDLib nests the file one level down: inputMessageSticker takes
		// an inputSticker, which is what carries the InputFile. Handing it the
		// InputFile directly answers "InputFile is not specified".
		@"input_message_content": @{
			@"@type"   : @"inputMessageSticker",
			@"sticker" : @{
				@"@type"   : @"inputSticker",
				@"sticker" : @{@"@type" : @"inputFileId", @"id" : @(fileId)},
				@"width"   : @512,
				@"height"  : @512,
			},
			@"emoji"   : @"",
		},
	}];

	// Sending does not put it in Recently Used on its own, so the strip never
	// filled up as stickers were sent.
	[self send:@{@"@type"       : @"addRecentSticker",
				 @"is_attached" : @NO,
				 @"sticker"     : @{@"@type" : @"inputFileId", @"id" : @(fileId)}}];
}

- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
                 toChat:(int64_t)chatId thread:(int64_t)threadId {
	if (!path.length)
		return;

	NSDictionary *attributes = [[NSFileManager defaultManager]
			attributesOfItemAtPath:path error:nil];
	NSLog(@"TGClient: sending voice %@ (%llu bytes, %lds) to %lld",
			path.lastPathComponent, [attributes fileSize], (long)seconds, chatId);

	// Answered rather than fire-and-forget: a rejected voice note is silent
	// otherwise, and the file it points at lives in a temporary directory.
	[self request:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type"      : @"inputMessageVoiceNote",
			@"voice_note" : @{
				@"@type"      : @"inputVoiceNote",
				@"voice_note" : @{@"@type" : @"inputFileLocal", @"path" : path},
				@"duration"   : @(seconds),
				@"waveform"   : @"",
			},
		},
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"TGClient: voice rejected: %@ %@",
					result[@"code"], result[@"message"]);
		else
			NSLog(@"TGClient: voice accepted, message %@", result[@"id"]);
	}];
}

- (void)sendVideoAtPath:(NSString *)path toChat:(int64_t)chatId {
	if (!path.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type" : @"inputMessageVideo",
			@"video" : @{
				@"@type" : @"inputVideo",
				@"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
			},
		},
	}];
}

- (void)sendLocation:(double)latitude longitude:(double)longitude toChat:(int64_t)chatId {
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type"    : @"inputMessageLocation",
			@"location" : @{
				@"@type"     : @"location",
				@"latitude"  : @(latitude),
				@"longitude" : @(longitude),
			},
		},
	}];
}

/// A place that keeps changing, for `seconds` more. The send is answered
/// with the message itself, whose id is what every later edit answers
/// through - the one misstep here is a fire-and-forget send, which leaves
/// the live location orphaned, editable by nobody.
- (void)sendLiveLocation:(NSInteger)seconds
			latitude:(double)latitude
			longitude:(double)longitude
				  toChat:(int64_t)chatId
			 completion:(void (^)(int64_t messageId))completion {
	[self request:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type"    : @"inputMessageLiveLocation",
			@"location" : @{
				@"@type"       : @"liveLocation",
				@"location"    : @{@"@type"     : @"location",
								   @"latitude"  : @(latitude),
								   @"longitude" : @(longitude)},
				@"live_period" : @(seconds),
				@"heading"     : @(0),
				@"proximity_alert_radius" : @(0),
			},
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

/// The moving pin, moved again, for `seconds` more of its period - and 0 is
/// the stop that takes it off the map. Without the id the edit is refused,
/// because a pin nobody can move is a lie on the map.
- (void)editLiveLocationOfMessage:(int64_t)messageId
						   inChat:(int64_t)chatId
						 latitude:(double)latitude
						longitude:(double)longitude
					   livePeriod:(NSInteger)seconds
					   completion:(void (^)(BOOL ok))completion {
	if (!messageId){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"      : @"editMessageLiveLocation",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"location"   : @{
			@"@type"       : @"liveLocation",
			@"location"    : @{@"@type"     : @"location",
							   @"latitude"  : @(latitude),
							   @"longitude" : @(longitude)},
			@"live_period" : @(seconds),
			@"heading"     : @(0),
			@"proximity_alert_radius" : @(0),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)sendContactNamed:(NSString *)name phone:(NSString *)phone toChat:(int64_t)chatId {
	if (!phone.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type"   : @"inputMessageContact",
			@"contact" : @{
				@"@type"        : @"contact",
				@"phone_number" : phone,
				@"first_name"   : name ?: @"",
				@"user_id"      : @(0),
			},
		},
	}];
}

- (void)sendPhotoAtPath:(NSString *)path toChat:(int64_t)chatId {
	if (!path.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type" : @"inputMessagePhoto",
			@"photo" : @{
				@"@type" : @"inputPhoto",
				@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
			},
		},
	}];
}

- (void)votePoll:(int64_t)messageId inChat:(int64_t)chatId options:(NSArray *)optionIds {
	[self send:@{
		@"@type"      : @"setPollAnswer",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"option_ids" : optionIds ?: @[],
	}];
}

- (void)reactTo:(int64_t)messageId inChat:(int64_t)chatId emoji:(NSString *)emoji {
	[self send:@{
		@"@type"      : @"addMessageReaction",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"reaction_type" : @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji},
		@"is_big"     : @NO,
		@"update_recent_reactions" : @YES,
	}];
}

- (void)deleteMessage:(int64_t)messageId inChat:(int64_t)chatId {
	[self deleteMessages:@[@(messageId)] inChat:chatId revoke:YES];
}

- (void)deleteMessages:(NSArray *)messageIds inChat:(int64_t)chatId {
	[self deleteMessages:messageIds inChat:chatId revoke:YES];
}

- (void)deleteMessages:(NSArray *)messageIds inChat:(int64_t)chatId revoke:(BOOL)revoke {
	if (!messageIds.count)
		return;
	[self send:@{
		@"@type"        : @"deleteMessages",
		@"chat_id"      : @(chatId),
		@"message_ids"  : messageIds,
		@"revoke"       : @(revoke),
	}];
}

/// "typing...", as the other side shows it. TDLib expects this repeated while
/// typing goes on; it expires on its own a few seconds after the last one.
- (void)sendTypingToChat:(int64_t)chatId thread:(int64_t)threadId {
	[self send:@{
		@"@type"             : @"sendChatAction",
		@"chat_id"           : @(chatId),
		@"message_thread_id" : @(threadId),
		@"action"            : @{@"@type" : @"chatActionTyping"},
	}];
}

/// Stops it at once rather than waiting for it to expire - sent when the
/// message goes or the field is emptied.
- (void)cancelTypingInChat:(int64_t)chatId thread:(int64_t)threadId {
	[self send:@{
		@"@type"             : @"sendChatAction",
		@"chat_id"           : @(chatId),
		@"message_thread_id" : @(threadId),
		@"action"            : @{@"@type" : @"chatActionCancel"},
	}];
}

- (void)removeReaction:(NSString *)emoji
			 fromMessage:(int64_t)messageId
				  inChat:(int64_t)chatId {
	if (!emoji.length)
		return;
	[self send:@{
		@"@type"         : @"removeMessageReaction",
		@"chat_id"       : @(chatId),
		@"message_id"    : @(messageId),
		@"reaction_type" : @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji},
	}];
}

/// Marks a voice note, a video note or a one-time picture as opened. Without
/// it the sender never sees it played and a self-destructing message never
/// starts its clock.
- (void)openContentOfMessage:(int64_t)messageId inChat:(int64_t)chatId {
	if (!messageId)
		return;
	[self send:@{
		@"@type"      : @"openMessageContent",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	}];
}

- (void)pinMessage:(int64_t)messageId inChat:(int64_t)chatId notify:(BOOL)notify {
	[self send:@{
		@"@type"                : @"pinChatMessage",
		@"chat_id"              : @(chatId),
		@"message_id"           : @(messageId),
		@"disable_notification" : @(!notify),
		@"only_for_self"        : @NO,
	}];
}

- (void)unpinMessage:(int64_t)messageId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"      : @"unpinChatMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	}];
}

/// Every pinned message down at once - in a forum topic, only that topic's.
- (void)unpinAllMessagesInChat:(int64_t)chatId thread:(int64_t)threadId {
	if (threadId)
		[self send:@{@"@type" : @"unpinAllForumTopicMessages",
					 @"chat_id" : @(chatId), @"forum_topic_id" : @(threadId)}];
	else
		[self send:@{@"@type" : @"unpinAllChatMessages", @"chat_id" : @(chatId)}];
}

/// The last message sent on or before `date` (unix seconds), for jumping to
/// a day; nil when the chat has nothing that old.
- (void)messageAtDate:(NSTimeInterval)date inChat:(int64_t)chatId
		   completion:(void (^)(NSDictionary *message))completion {
	[self request:@{@"@type" : @"getChatMessageByDate",
					@"chat_id" : @(chatId),
					@"date" : @((int32_t)date)}
	   completion:^(NSDictionary *m){
		if (completion)
			completion([m[@"@type"] isEqualToString:@"message"] ? TGFlattenMessage(m) : nil);
	}];
}

/// The message a reply points at. The history may not hold it - a reply to
/// something far above, or to a message in another chat - so this asks the
/// server rather than searching what is loaded.
- (void)repliedMessageTo:(int64_t)messageId
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSDictionary *message))completion {
	[self request:@{@"@type"      : @"getRepliedMessage",
					@"chat_id"    : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *parsed = [result[@"id"] longLongValue]
				? TGFlattenMessage(result) : nil;
		if (parsed){
			// The chat the answer lives in, which a reply across chats is
			// what reads it: the flattened message carries the id of a
			// message only, and the chat view would ask itself for it.
			NSMutableDictionary *withChat = [parsed mutableCopy];
			withChat[@"chatId"] = result[@"chat_id"];
			parsed = withChat;
		}
		completion(parsed);
	}];
}

/// Returns messages by their ids in a chat. Missing messages are returned as NSNull.
- (void)messagesInChat:(int64_t)chatId
			messageIds:(NSArray *)messageIds
			completion:(void (^)(NSArray *messages))completion {
	if (!messageIds.count){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{
		@"@type"       : @"getMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
	} completion:^(NSDictionary *result){
		if (!completion) return;
		NSArray *raw = result[@"messages"];
		if (![raw isKindOfClass:NSArray.class]){
			completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
		for (id item in raw){
			if ([item isKindOfClass:NSDictionary.class] && [item[@"id"] longLongValue] != 0)
				[out addObject:TGFlattenMessage(item)];
			else
				[out addObject:[NSNull null]];
		}
		completion(out);
	}];
}

/// Returns properties of a message (e.g. can_be_replied, can_get_message_thread).
- (void)messagePropertiesForChat:(int64_t)chatId
					   messageId:(int64_t)messageId
					  completion:(void (^)(NSDictionary *properties))completion {
	[self request:@{
		@"@type"      : @"getMessageProperties",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result isKindOfClass:NSDictionary.class] ? result : nil);
	}];
}

/// A t.me link to one message, for Copy Link. Only public chats have one;
/// the completion gets nil for the rest.
- (void)linkToMessage:(int64_t)messageId
			   inChat:(int64_t)chatId
		   completion:(void (^)(NSString *link))completion {
	[self request:@{@"@type"      : @"getMessageLink",
					@"chat_id"    : @(chatId),
					@"message_id" : @(messageId),
					@"for_album"  : @NO}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"link"] isKindOfClass:NSString.class] ? result[@"link"] : nil);
	}];
}

/// Sends failed messages again. TDLib keeps them in the history with their
/// own ids until they go or are deleted.
- (void)resendMessages:(NSArray *)messageIds inChat:(int64_t)chatId {
	if (!messageIds.count)
		return;
	[self send:@{
		@"@type"       : @"resendMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
	}];
}

/// Closes a poll you sent. Nobody can vote afterwards and the result stands.
- (void)stopPoll:(int64_t)messageId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"      : @"stopPoll",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	}];
}

/// Who voted for one answer. `optionIndex` is the 0-based index the answer
/// sits at; the voters come back as senders, flattened into ids and names
/// the menu shows.
- (void)pollVotersOfOption:(NSInteger)optionIndex
				ofMessage:(int64_t)messageId
					 inChat:(int64_t)chatId
				completion:(void (^)(NSArray *voters, BOOL end))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"      : @"getPollVoters",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"option_id"  : @(optionIndex),
		@"offset"     : @(0),
		@"limit"      : @(50),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *voter in result[@"voters"]){
			NSDictionary *sender = voter[@"voter_id"];
			int64_t userId = [sender[@"user_id"] longLongValue];
			if (!userId)
				continue;
			[out addObject:@{
				@"id"   : @(userId),
				@"name" : [me nameForUserId:userId] ?: @"",
				@"date" : voter[@"date"] ?: @(0),
			}];
		}
		if (completion)
			completion(out, [out count] >= [result[@"total_count"] integerValue]);
	}];
}

- (void)pollVoteStatisticsOfMessage:(int64_t)messageId
							 inChat:(int64_t)chatId
						 completion:(void (^)(NSDictionary *graph))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"      : @"getPollVoteStatistics",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		// The sheet has no theme of its own: the chat lists its colours and
		// the graph data is the same numbers either way.
		@"is_dark"    : @NO,
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSDictionary *graph = nil;
		NSString *json = result[@"vote_graph"][@"json_data"];
		if ([json isKindOfClass:NSString.class] && json.length) {
			graph = @{@"json" : json,
					  @"zoom" : result[@"vote_graph"][@"zoom_token"] ?: @""};
		}
		if (completion) completion(graph);
	}];
}

/// An option added after the poll went out, for polls that allow it. The
/// option is a line of text in the same shaped envelope an input poll
/// carries.
- (void)addPollOption:(NSString *)text
			toMessage:(int64_t)messageId
				 inChat:(int64_t)chatId
			completion:(void (^)(BOOL ok))completion {
	if (!text.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"      : @"addPollOption",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"option"     : @{@"@type" : @"inputPollOption",
						  @"text"  : @{@"@type" : @"formattedText",
									   @"text"  : text}},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// An option taken out again; `optionId` is the string id pollOption
/// carries, not an index.
- (void)deletePollOption:(NSString *)optionId
			   ofMessage:(int64_t)messageId
				  inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok))completion {
	if (!optionId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"      : @"deletePollOption",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"option_id"  : optionId,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// Every poll in the chat read up on: the votes are no longer new once the
/// chat has been seen, which is what a badge on the answer options is.
- (void)readAllChatPollVotes:(int64_t)chatId {
	[self send:@{
		@"@type"   : @"readAllChatPollVotes",
		@"chat_id" : @(chatId),
	}];
}

/// Reports a reaction as harassment: TDLib names the sender, not the
/// message alone - the fire brigade wants to know who lit the fire.
/// `sender` is the MessageSender the flattening carried up untouched.
- (void)reportReactionBySender:(NSDictionary *)sender
					 ofMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
					 completion:(void (^)(BOOL ok))completion {
	if (![sender isKindOfClass:NSDictionary.class]){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"      : @"reportMessageReactions",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"sender_id"  : sender,
	} completion:^void (NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"ok"]);
	}];
}

/// Reports messages in a supergroup as spam. It takes the supergroup's own
/// id, not the chat id - a chat id for a supergroup is the negative of it
/// with a prefix, so this reads the chat first rather than doing arithmetic
/// on it.
- (void)reportSpamMessages:(NSArray *)messageIds
				    inChat:(int64_t)chatId
				completion:(void (^)(BOOL ok))completion {
	if (!messageIds.count){
		if (completion) completion(NO);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		TGClient *me = weakSelf;
		NSNumber *supergroupId = chat[@"type"][@"supergroup_id"];
		if (!me || !supergroupId){
			// A basic group or a private chat has no supergroup to report to;
			// reportChat is the route for those.
			if (completion) completion(NO);
			return;
		}
		[me request:@{@"@type"        : @"reportSupergroupSpam",
					  @"supergroup_id": supergroupId,
					  @"message_ids"  : messageIds}
		 completion:^(NSDictionary *result){
			if (completion)
				completion([result[@"@type"] isEqualToString:@"ok"]);
		}];
	}];
}

/// Blocks whoever sent a message from replying again, and optionally takes
/// what they wrote with them. Only for messages in the chats a reply reaches
/// this account through.
- (void)blockSenderOfMessage:(int64_t)messageId
			  deleteMessages:(BOOL)deleteMessages
				  reportSpam:(BOOL)reportSpam {
	[self send:@{
		@"@type"              : @"blockMessageSenderFromReplies",
		@"message_id"         : @(messageId),
		@"delete_message"     : @(deleteMessages),
		@"delete_all_messages": @(deleteMessages),
		@"report_spam"        : @(reportSpam),
	}];
}

/// Telegram's own static map of a place, as a PNG. The completion gets a
/// local path, or nil when there is no answer - which on this device is
/// ordinary: the thumbnail is a download like any other, and a chat opened
/// on a slow connection or with none will not have it.
///
/// `scale` is left at 1 deliberately. A retina plate is four times the bytes
/// for a card 220 points wide on a screen that has 320 of them.
- (void)mapThumbnailForLatitude:(double)latitude
					  longitude:(double)longitude
						  width:(NSInteger)width
						 height:(NSInteger)height
						 inChat:(int64_t)chatId
					 completion:(void (^)(NSString *path))completion {
	// Their own bounds; a request outside them is refused rather than clamped.
	NSInteger wanted = MAX(16, MIN(1024, width));
	NSInteger tall   = MAX(16, MIN(1024, height));

	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"    : @"getMapThumbnailFile",
		@"location" : @{@"@type"     : @"location",
						@"latitude"  : @(latitude),
						@"longitude" : @(longitude)},
		@"zoom"     : @(16),
		@"width"    : @(wanted),
		@"height"   : @(tall),
		@"scale"    : @(1),
		@"chat_id"  : @(chatId),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSNumber *fileId = result[@"id"];
		if (!me || ![fileId isKindOfClass:NSNumber.class]){
			if (completion) completion(nil);
			return;
		}
		// The answer is a file record, not the picture: it still has to come
		// down, and a thumbnail already in the cache answers at once.
		NSString *local = result[@"local"][@"path"];
		if ([result[@"local"][@"is_downloading_completed"] boolValue] && local.length){
			if (completion) completion(local);
			return;
		}
		[me downloadFile:fileId.integerValue completion:completion];
	}];
}

/// What Telegram makes of a link: the site, a title, a description and the
/// picture, which is the card their clients draw under a message. Answers nil
/// when the link has no preview, which is most links.
///
/// Entries: "url", "site", "title", "description", "photoId", "instantView".
- (void)linkPreviewForText:(NSString *)text
				completion:(void (^)(NSDictionary *preview))completion {
	if (!text.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type" : @"getLinkPreview",
		@"text"  : TGFormattedText(text),
		@"link_preview_options" : @{@"@type" : @"linkPreviewOptions",
									@"is_disabled" : @NO},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"linkPreview"]){
			completion(nil);
			return;
		}
		// The biggest size the preview carries, which is the one a card draws.
		NSArray *sizes = result[@"type"][@"photo"][@"sizes"];
		NSDictionary *largest = [sizes isKindOfClass:NSArray.class]
				? [sizes lastObject] : nil;
		NSNumber *photoId = largest[@"photo"][@"id"];
		completion(@{
			@"url"         : result[@"url"] ?: @"",
			@"site"        : result[@"site_name"] ?: @"",
			@"title"       : result[@"title"] ?: @"",
			@"description" : result[@"description"][@"text"] ?: @"",
			@"photoId"     : photoId ?: [NSNull null],
			@"instantView" : @([result[@"instant_view_version"] integerValue] > 0),
		});
	}];
}

/// What a t.me or tg:// link points at, decided by Telegram rather than by
/// pattern-matching the path here - which is how a link to a sticker set
/// ended up opening a chat named after it.
///
/// Answers the kind as one word ("publicChat", "message", "stickerSet",
/// "inviteLink", "unknown") and the piece of it worth acting on.
- (void)internalLinkKind:(NSString *)link
			  completion:(void (^)(NSString *kind, NSString *value))completion {
	if (!link.length){
		if (completion) completion(@"unknown", nil);
		return;
	}
	[self request:@{@"@type" : @"getInternalLinkType", @"link" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = result[@"@type"] ?: @"";
		if ([type isEqualToString:@"internalLinkTypePublicChat"])
			completion(@"publicChat", result[@"chat_username"]);
		else if ([type isEqualToString:@"internalLinkTypeMessage"])
			completion(@"message", result[@"url"]);
		else if ([type isEqualToString:@"internalLinkTypeStickerSet"])
			completion(@"stickerSet", result[@"sticker_set_name"]);
		else if ([type isEqualToString:@"internalLinkTypeChatInvite"])
			completion(@"inviteLink", result[@"invite_link"]);
		else if ([type isEqualToString:@"internalLinkTypeUserPhoneNumber"])
			completion(@"phoneNumber", result[@"phone_number"]);
		else {
			// Telegram keeps a server-side table of links it has no schema
			// for: what a private invite or a reserved page means, told in
			// prose. That prose is the link's meaning - without it the tap
			// fell through to a path-matcher that mostly guessed wrong.
			[self request:@{@"@type" : @"getDeepLinkInfo", @"link" : link}
			   completion:^(NSDictionary *info){
				if (!completion)
					return;
				// A refusal answers as an error, whose "message" is a bare
				// string - subscripting that is the crash a naive chain
				// here would take.
				NSDictionary *said = [info[@"message"] isKindOfClass:NSDictionary.class]
						? info[@"message"] : nil;
				NSString *note = said[@"text"] ?: @"";
				// "update_app" means TDLib answered because its copy is
				// stale, not because this is what the link means: the tap
				// falls back rather than reciting a version check.
				BOOL staleCopy = [info[@"update_app"] boolValue];
				if ([info[@"@type"] isEqualToString:@"deepLinkInfo"] && note.length &&
						!staleCopy)
					completion(@"deepLink", note);
				else
					completion(@"unknown", nil);
			}];
		}
	}];
}

/// What the sender typed, handed back as markdown: *bold*, `_italic_`,
/// `code` come back out of the entities their client stored - so Edit edits
/// the origin rather than the render. A message with no entities is not
/// worth the round trip: the plain text goes back as it is.
- (void)markdownOfMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
				completion:(void (^)(NSString *markdown))completion {
	[self request:@{@"@type" : @"getMessage",
					@"chat_id"    : @(chatId),
					@"message_id" : @(messageId)}
		completion:^(NSDictionary *result){
			if (!completion)
				return;
			NSString *plain = result[@"content"][@"text"][@"text"] ?: @"";
			NSDictionary *formatted = result[@"content"][@"text"];
			if (![formatted[@"@type"] isEqualToString:@"formattedText"] ||
					![formatted[@"entities"] isKindOfClass:NSArray.class] ||
					!((NSArray *)formatted[@"entities"]).count){
				completion(plain);
				return;
			}
			[self request:@{@"@type" : @"getMarkdownText", @"text" : formatted}
				completion:^(NSDictionary *answer){
				NSString *text = answer[@"text"];
				if ([answer[@"@type"] isEqualToString:@"formattedText"] &&
						text.length)
					completion(text);
				else
					completion(plain);
			}];
		}];
}

- (void)markRead:(NSArray *)messageIds inChat:(int64_t)chatId {
	if (!messageIds.count)
		return;
	[self send:@{
		@"@type"       : @"viewMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
		@"force_read"  : @YES,
	}];
}

#pragma mark - message functions the screens ask for

/// What a "message"-kind internal link points at: a t.me/name/12345 resolves
/// to the chat and the exact message inside it. The link type itself is
/// decided by Telegram, at internalLinkKind:; a link to a nonexistent or a
/// private-place message answers as an error, said as a zero chat id.
- (void)messageLinkInfo:(NSString *)link
			 completion:(void (^)(int64_t chatId, int64_t messageId))completion {
	if (!link.length){
		if (completion) completion(0, 0);
		return;
	}
	[self request:@{@"@type" : @"getMessageLinkInfo", @"url" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"messageLinkInfo"]){
			completion(0, 0);
			return;
		}
		completion([result[@"chat_id"] longLongValue],
				   [result[@"message"][@"id"] longLongValue]);
	}];
}

/// Every chat's draft, dropped at once - the ones typed here and the ones
/// typed on another device: TDLib owns all of them.
- (void)clearAllDraftMessages {
	[self request:@{@"@type" : @"clearAllDraftMessages"} completion:nil];
}

/// The lifetime new chats start with when nobody has picked one. Zero means
/// Telegram's "off" - messages live until deleted by hand.
- (void)defaultMessageAutoDeleteTimeWithCompletion:
		(void (^)(NSInteger seconds))completion {
	[self request:@{@"@type" : @"getDefaultMessageAutoDeleteTime"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"messageAutoDeleteTime"]){
			completion(-1);
			return;
		}
		completion([result[@"time"] integerValue]);
	}];
}

- (void)setDefaultMessageAutoDeleteTime:(NSInteger)seconds {
	[self request:@{@"@type"          : @"setDefaultMessageAutoDeleteTime",
					@"auto_delete_seconds" : @(seconds)}
		 completion:nil];
}

#pragma mark - message functions, the third wave

/// Members who opened the voice note, watched the round video or otherwise
/// read this own message in a group. messageViewer carries the user id and
/// when they did it; names resolve out of the client's user records.
- (void)viewersOfMessage:(int64_t)messageId
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *viewers))completion {
	[self request:@{@"@type" : @"getMessageViewers",
					@"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"messageViewers"]){
			completion(nil);
			return;
		}
		completion(result[@"viewers"]);
	}];
}

/// When exactly the other side read this message - or why the answer is not
/// a timestamp: "unread", "tooOld", or their and our own privacy settings.
/// A nil date with a reason word is the honest sheet line.
- (void)readDateOfMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
			   completion:(void (^)(NSTimeInterval date, NSString *reason))completion {
	[self request:@{@"@type" : @"getMessageReadDate",
					@"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *kind = result[@"@type"] ?: @"";
		if ([kind isEqualToString:@"messageReadDateRead"]){
			completion([result[@"read_date"] doubleValue], nil);
		} else if ([kind isEqualToString:@"messageReadDateUnread"]){
			completion(0, @"Not read yet");
		} else if ([kind isEqualToString:@"messageReadDateTooOld"]){
			completion(0, @"Read too long ago for Telegram to say when");
		} else if ([kind isEqualToString:@"messageReadDateUserPrivacyRestricted"]){
			completion(0, @"They hide their read receipts");
		} else if ([kind isEqualToString:@"messageReadDateMyPrivacyRestricted"]){
			completion(0, @"This account hides its own read receipts");
		} else {
			completion(0, @"Not available");
		}
	}];
}

/// Who a channel actually posted as, when the bubble says "Channel Admin".
/// The server answers a full user record.
- (void)authorOfMessage:(int64_t)messageId
				 inChat:(int64_t)chatId
			 completion:(void (^)(NSDictionary *user))completion {
	[self request:@{@"@type" : @"getMessageAuthor",
					@"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"user"] ? result : nil);
	}];
}

/// The HTML this message is pasted with into a blog post. Only messages
/// carrying a web page preview answer it, which is what the server says to
/// anything else - passed on as an empty string.
- (void)embeddingCodeOfMessage:(int64_t)messageId
						inChat:(int64_t)chatId
					 album:(BOOL)album
					completion:(void (^)(NSString *code))completion {
	[self request:@{@"@type" : @"getMessageEmbeddingCode",
					@"chat_id" : @(chatId), @"message_id" : @(messageId),
					@"for_album" : @(album)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"text"]){
			completion(@"");
			return;
		}
		completion(result[@"text"]);
	}];
}

/// Public channels and walls this post was forwarded to, as message dicts -
/// only public places answer, so a short list is the worst case.
- (void)publicForwardsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
					 completion:(void (^)(NSArray *messages))completion {
	[self request:@{@"@type" : @"getMessagePublicForwards",
					@"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"foundMessages"]){
			completion(nil);
			return;
		}
		completion(result[@"messages"]);
	}];
}

/// The reactions that may be added to this message right now: the chat's
/// configured set filtered by per-message rules, from which the picker bar
/// is drawn instead of the app's hard defaults. "all" in the emoji list
/// means the chat allows everything and the defaults are the honest set.
- (void)availableReactionsForMessage:(int64_t)messageId
							  inChat:(int64_t)chatId
					   completion:(void (^)(NSArray *emojis))completion {
	[self request:@{@"@type" : @"getMessageAvailableReactions",
					@"chat_id" : @(chatId), @"message_id" : @(messageId),
					@"row_size" : @(8)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"availableReactions"] ||
				[result[@"unavailability_reason"][@"@type"] boolValue]){
			completion(nil);
			return;
		}
		NSArray *top = result[@"top_reactions"];
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *r in top){
			NSString *emoji = r[@"emoji"];
			if (emoji.length)
				[out addObject:emoji];
		}
		// No explicit top list: the chat allows everything, the app's own
		// default bar answers it.
		completion(out.count ? out : nil);
	}];
}

/// Every reaction this message carries and who put it, for the reactor
/// sheet. `offset` iterates; an empty answer on the first call is a message
/// without reactors or a chat that does not hand these out.
- (void)addedReactionsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
						  emoji:(NSString *)emoji
						 offset:(NSString *)offset
					 completion:(void (^)(NSArray *rows, NSString *next))completion {
	NSDictionary *type = @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji ?: @""};
	[self request:@{@"@type" : @"getMessageAddedReactions",
					@"chat_id" : @(chatId), @"message_id" : @(messageId),
					@"reaction_type" : type,
					@"offset" : offset ?: @"",
					@"limit" : @(50)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"addedReactions"]){
			completion(nil, nil);
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *r in result[@"reactions"]){
			[rows addObject:@{@"sender" : r[@"sender_id"],
							  @"date" : r[@"date"],
							  @"mine" : r[@"is_outgoing"]}];}
		completion(rows, result[@"next_offset"]);
	}];
}

/// An administrator taking somebody's reaction off this message.
- (void)deleteReactionsOfSender:(NSDictionary *)sender
					 ofMessage:(int64_t)messageId
						 inChat:(int64_t)chatId {
	if (!sender)
		return;
	[self send:@{
		@"@type"     : @"deleteMessageReactionsFromSender",
		@"chat_id"   : @(chatId),
		@"message_id": @(messageId),
		@"sender_id" : sender,
	}];
}

/// The same, chat-wide: everything this sender ever reacted with in this
/// chat, gone. That is the strongest undo an admin sheet has.
- (void)deleteAllReactionsOfSender:(NSDictionary *)sender inChat:(int64_t)chatId {
	if (!sender)
		return;
	[self send:@{
		@"@type"   : @"deleteAllRecentMessageReactionsFromSender",
		@"chat_id" : @(chatId),
		@"sender_id" : sender,
	}];
}

/// How many messages a chat (or one of its topics) carries. `thread` selects
/// a forum topic; zero is the whole chat.
- (void)messageCountInChat:(int64_t)chatId
					thread:(int64_t)threadId
				completion:(void (^)(NSInteger count))completion {
	NSDictionary *topic = threadId
		? @{@"@type" : @"messageTopicMessageThread",
			@"messageThread_id" : @(threadId)}
		: @{@"@type" : @"messageTopicMain"};
	[self request:@{@"@type" : @"getChatMessageCount",
					@"chat_id" : @(chatId),
					@"topic_id" : topic,
					@"filter" : @{@"@type" : @"searchMessagesFilterEmpty"},
					@"return_local" : @NO}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"count"])
			completion([result[@"count"] integerValue]);
		else
			completion(0);
	}];
}

/// Every call history entry on this account, gone from everywhere.
- (void)clearAllCallMessages {
	[self request:@{@"@type" : @"deleteAllCallMessages"} completion:nil];
}

/// The calendar answer for one day: the message id to jump to and how many
/// messages the chat carries, from the same search the jump sheet used to
/// make two round trips for.
- (void)calendarJumpForChat:(int64_t)chatId
					 endDate:(NSInteger)end
				  completion:(void (^)(int64_t messageId, NSInteger total))completion {
	[self request:@{@"@type"   : @"getChatMessageCalendar",
					@"chat_id" : @(chatId),
					@"topic_id" : @{@"@type" : @"messageTopicMain"},
					@"filter"  : @{@"@type" : @"searchMessagesFilterEmpty"},
					@"from_message_id" : @(0)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"messageCalendar"]){
			completion(0, 0);
			return;
		}
		completion([result[@"last_message_id"] longLongValue],
				   [result[@"total_count"] integerValue]);
	}];
}

/// Everything this account has sent as a file, named like search results:
/// message dicts the list page lays out as document rows.
- (void)sentDocuments:(NSString *)query
			 completion:(void (^)(NSArray *messages))completion {
	[self request:@{@"@type" : @"searchOutgoingDocumentMessages",
					@"query" : query ?: @"",
					@"limit" : @(100)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"foundMessages"]){
			completion(nil);
			return;
		}
		completion(result[@"messages"]);
	}];
}

/// The pubic posts everywhere a hashtag appears - server search, answered
/// newest first, paged by the string offset Telegram names.
- (void)publicMessagesByTag:(NSString *)tag
					 offset:(NSString *)offset
				completion:(void (^)(NSArray *messages, NSString *next))completion {
	NSString *clean = [tag stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion) completion(nil, nil);
		return;
	}
	[self request:@{@"@type"     : @"searchPublicMessagesByTag",
					@"tag"     : clean,
					@"offset"  : offset ?: @"",
					@"limit"   : @(50)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"foundMessages"]){
			completion(nil, nil);
			return;
		}
		completion(result[@"messages"], result[@"next_offset"]);
	}];
}

/// Where this chat's live pins have been, newest first, for the "recent
/// locations" sheet: message dicts, each a location bubble the map opens.
- (void)recentLocationsInChat:(int64_t)chatId
				   completion:(void (^)(NSArray *messages))completion {
	[self request:@{@"@type" : @"searchChatRecentLocationMessages",
					@"chat_id" : @(chatId),
					@"limit" : @(20)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"messages"]){
			completion(nil);
			return;
		}
		completion(result[@"messages"]);
	}];
}

/// This message's text, translated by Telegram into `languageCode`. The
/// answer is the same formattedText the composer already knows how to show.
- (void)translateMessage:(int64_t)messageId
				  inChat:(int64_t)chatId
				   toCode:(NSString *)languageCode
			  completion:(void (^)(NSString *text))completion {
	if (!languageCode.length)
		languageCode = [[NSLocale currentLocale] objectForKey:
				NSLocaleLanguageCode] ?: @"en";
	[self request:@{@"@type"   : @"translateMessageText",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"to_language_code" : languageCode,
					@"tone" : @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"formattedText"]){
			completion(@"");
			return;
		}
		completion(result[@"text"]);
	}];
}

#pragma mark - welcome messages

/// The welcome messages a supergroup or a channel shows a joiner. The load
/// answers an ok and the rows ride updateChatWelcomeMessages, which the chat
/// row already takes through applyChatUpdate's announcement - so the sheet
/// hears that, not the round trip.
- (void)welcomeMessagesOfChat:(int64_t)chatId
				   completion:(void (^)(NSArray *welcomes))completion {
	__block id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGFullInfoChangedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *note){
		if (![note.userInfo[@"kind"] isEqualToString:@"chat"] ||
				[note.userInfo[@"id"] longLongValue] != chatId)
			return;
		[[NSNotificationCenter defaultCenter] removeObserver:token];
		token = nil;
		NSMutableArray *out = [NSMutableArray array];
		NSArray *rows = self.chatsById[@(chatId)][@"welcomeMessages"];
		for (NSDictionary *w in rows){
			// A welcome text rides the nested shape the composer reads.
			id content = w[@"content"] ?: @{};
			NSString *text = content[@"messageText"][@"text"][@"text"];
			NSString *word = [text isKindOfClass:NSString.class] ? text : @"";
			[out addObject:@{@"id" : w[@"id"], @"text" : word}];
		}
		if (completion) completion(out);
	}];
	// The load answers an ok; the rows themselves ride updateChatWelcome-
	// Messages, which is what the announcement above heard.
	[self request:@{@"@type" : @"loadChatWelcomeMessages", @"chat_id" : @(chatId)}
		 completion:nil];
}


#pragma mark - wave four: the ones the second tail carried

/// Whether a compose with this user can go through at all: "ok",
/// "paidMessages", "userDeleted" or "userRestrictsNewChats".
- (void)canSendMessageToUser:(int64_t)userId
				  completion:(void (^)(NSString *result))completion {
	if (!userId){
		if (completion) completion(@"userDeleted");
		return;
	}
	[self request:@{@"@type" : @"canSendMessageToUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *result){
		NSString *kind = result[@"@type"] ?: @"";
		NSString *word = @"userDeleted";
		if ([kind isEqualToString:@"canSendMessageToUserResultOk"]) word = @"ok";
		else if ([kind isEqualToString:@"canSendMessageToUserResultUserHasPaidMessages"])
			word = @"paidMessages";
		else if ([kind isEqualToString:@"canSendMessageToUserResultUserIsDeleted"])
			word = @"userDeleted";
		else if ([kind isEqualToString:@"canSendMessageToUserResultUserRestrictsNewChats"])
			word = @"userRestrictsNewChats";
		if (completion) completion(word);
	}];
}

/// The admin's whole-range wipe: "clear what was said before date X".
- (void)deleteChatMessagesByDate:(int64_t)chatId
						 minDate:(NSInteger)minDate
						 maxDate:(NSInteger)maxDate
						  revoke:(BOOL)revoke {
	[self send:@{
		@"@type"     : @"deleteChatMessagesByDate",
		@"chat_id"   : @(chatId),
		@"min_date"  : @(minDate),
		@"max_date"  : @(maxDate),
		@"revoke"    : @(revoke),
	}];
}

/// Everything that member wrote in this chat, on every device.
- (void)deleteChatMessagesBySender:(NSDictionary *)sender
							inChat:(int64_t)chatId
							revoke:(BOOL)revoke {
	if (!sender)
		return;
	[self send:@{
		@"@type"     : @"deleteChatMessagesBySender",
		@"chat_id"   : @(chatId),
		@"sender_id" : sender,
		@"revoke"    : @(revoke),
	}];
}

/// Saved Messages topics are asked for and then ride the update of their
/// own name, which the dispatch keeps.
- (void)loadSavedMessagesTopics {
	[self request:@{@"@type" : @"loadSavedMessagesTopics", @"limit" : @(100)}
		 completion:nil];
}

- (void)addWelcomeMessageToChat:(int64_t)chatId
						   text:(NSString *)text
					 completion:(void (^)(BOOL ok))completion {
	if (!text.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
			@"@type"   : @"addChatWelcomeMessage",
			@"chat_id" : @(chatId),
			@"input_message_content" : @{@"@type"  : @"inputMessageText",
										 @"text"   : TGFormattedText(text)},
		} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setWelcomeMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
					 text:(NSString *)text
			   completion:(void (^)(BOOL ok))completion {
	if (!text.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
			@"@type"              : @"editChatWelcomeMessage",
			@"chat_id"            : @(chatId),
			@"welcome_message_id" : @(messageId),
			@"input_message_content" : @{@"@type"  : @"inputMessageText",
										 @"text"   : TGFormattedText(text)},
		} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)deleteWelcomeMessage:(int64_t)messageId inChat:(int64_t)chatId {
	[self request:@{@"@type"              : @"deleteChatWelcomeMessage",
					@"chat_id"            : @(chatId),
					@"welcome_message_id" : @(messageId)}
		 completion:nil];
}

- (void)clearAllWelcomeMessagesInChat:(int64_t)chatId {
	[self request:@{@"@type"   : @"deleteAllChatWelcomeMessages",
					@"chat_id" : @(chatId)}
		 completion:nil];
}

- (void)availableMessageSendersInChat:(int64_t)chatId
						   completion:(void (^)(NSArray *senders))completion {
	[self request:@{@"@type" : @"getChatAvailableMessageSenders", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"chatMessageSenders"]){
			completion(nil);
			return;
		}
		completion(result[@"message_senders"]);
	}];
}

- (void)setMessageSender:(NSDictionary *)sender
				  inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok))completion {
	if (!sender){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type"   : @"setChatMessageSender",
					@"chat_id" : @(chatId),
					@"message_sender_id" : sender}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)labelSavedTag:(NSDictionary *)tag label:(NSString *)label {
	if (!tag)
		return;
	[self request:@{@"@type" : @"setSavedMessagesTagLabel",
					@"tag"   : tag,
					@"label" : label ?: @""}
		 completion:nil];
}

- (void)toggleSavedTopicPinned:(int64_t)topicId pinned:(BOOL)pinned {
	[self request:@{@"@type"    : @"toggleSavedMessagesTopicIsPinned",
					@"saved_messages_topic_id" : @(topicId),
					@"is_pinned"               : @(pinned)}
		 completion:nil];
}

- (void)setPinnedSavedTopics:(NSArray *)topicIds {
	[self request:@{@"@type" : @"setPinnedSavedMessagesTopics",
					@"saved_messages_topic_ids" : topicIds ?: @[]}
		 completion:nil];
}

- (void)savedTopicsTags:(int64_t)topicId
			 completion:(void (^)(NSArray *tags))completion {
	[self request:@{@"@type" : @"getSavedMessagesTags",
					@"saved_messages_topic_id" : @(topicId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"savedMessagesTags"]){
			completion(nil);
			return;
		}
		completion(result[@"tags"]);
	}];
}

- (void)searchSavedMessagesInTopic:(int64_t)topicId
							 query:(NSString *)query
							 tag:(NSDictionary *)tag
							  from:(int64_t)fromMessageId
					completion:(void (^)(NSArray *found, int64_t next))completion {
	[self request:@{
			@"@type"   : @"searchSavedMessages",
			@"saved_messages_topic_id" : @(topicId),
			@"tag"     : tag ?: [NSNull null],
			@"query"   : query ?: @"",
			@"from_message_id" : @(fromMessageId),
			@"offset"  : @(0),
			@"limit"   : @(50),
		} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"foundChatMessages"]){
			completion(nil, 0);
			return;
		}
		id nextId = result[@"next_from_message_id"];
		NSString *next = [nextId isKindOfClass:NSString.class] ? nextId : nil;
		completion(result[@"messages"],
				   [next isKindOfClass:NSString.class] ? [next longLongValue] : 0);
	}];
}

- (void)clearSavedTopicMessagesBefore:(int64_t)topicId
							 minDate:(NSInteger)minDate
							 maxDate:(NSInteger)maxDate {
	[self request:@{@"@type" : @"deleteSavedMessagesTopicMessagesByDate",
					@"saved_messages_topic_id" : @(topicId),
					@"min_date" : @(minDate),
					@"max_date" : @(maxDate)}
		 completion:nil];
}

- (void)savedTopicMessageAtDate:(int64_t)topicId
						   date:(NSInteger)date
					 completion:(void (^)(NSDictionary *message))completion {
	[self request:@{@"@type" : @"getSavedMessagesTopicMessageByDate",
					@"saved_messages_topic_id" : @(topicId),
					@"date" : @(date)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"message"] ? result : nil);
	}];
}

@end
