//
// TGMessageFlatten.m - the reader side of a TDLib message.
//
// One TDLib message JSON becomes the dictionary the screens render:
// text with its entities resolved, buttons flattened, reactions
// summarised, waveform decoded. Shared by the client, its categories
// and the message stream store; declared in TGClientInternal.h.
//
#import "TGClientInternal.h"
#import "TGBase64.h"


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
	BOOL hasStickers = NO;   // media other stickers were attached to

	if ([ctype isEqualToString:@"messagePhoto"]){
		hasStickers = [content[@"photo"][@"has_stickers"] boolValue];
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
		hasStickers = [content[@"video"][@"has_stickers"] boolValue];
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
		hasStickers = [content[@"animation"][@"has_stickers"] boolValue];
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
		waveform  = TGBase64Decode(content[@"voice_note"][@"waveform"]);
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
		@"hasStickers" : @(hasStickers),
		@"mediaWidth": @(mediaWidth),
		@"mediaHeight": @(mediaHeight),
		@"docId"     : docFileId   ?: [NSNull null],
		@"docName"   : docName     ?: @"",
		@"docSize"   : docSize     ?: @(0),
		@"service"   : @(isService),
		// Several photos sent together share an album id; the chat draws them
		// as one block rather than as unrelated messages.
		@"albumId"   : m[@"media_album_id"] ?: @"",
		// The effect the sender attached; its id is what getMessageEffect
		// answers for. 0 is most messages.
		@"effectId"  : m[@"effect_id"] ?: @(0),
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

