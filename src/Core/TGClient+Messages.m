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

/// Converts camelCase message type name to readable phrase (e.g. "messageVideoChatStarted" -> "Video chat started").
NSString *TGPhraseFromTypeName(NSString *ctype) {
	NSString *rest = [ctype hasPrefix:@"message"] ? [ctype substringFromIndex:7] : ctype;
	if (!rest.length)
		return @"Message";

	NSMutableString *out = [NSMutableString stringWithCapacity:rest.length + 8];
	for (NSUInteger i = 0; i < rest.length; i++){
		unichar c = [rest characterAtIndex:i];
		if (i > 0 && c >= 'A' && c <= 'Z'){
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
		} else if ([format isEqualToString:@"stickerFormatWebp"]){
			photoFileId = sticker[@"sticker"][@"id"];
		} else {
			// .webm is VP9, which this device cannot decode - thumbnail only.
			photoFileId = sticker[@"thumbnail"][@"file"][@"id"];
		}

		extra = content[@"emoji"] ?: sticker[@"emoji"];

	} else if ([ctype isEqualToString:@"messageDocument"]){
		photoFileId = content[@"document"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"document"][@"document"][@"id"];
		docName     = content[@"document"][@"file_name"];
		NSNumber *size = content[@"document"][@"document"][@"size"];
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
		for (NSDictionary *option in poll[@"options"]){
			[lines appendFormat:@"%@  %@%ld%%\n",
					[option[@"is_chosen"] boolValue] ? @"\u25c9" : @"\u25cb",
					option[@"text"][@"text"] ?: option[@"text"] ?: @"",
					(long)[option[@"vote_percentage"] integerValue]];
		}
		[lines appendFormat:@"%ld voted", (long)total];
		extra = lines;
		isService = NO;

	} else if ([ctype isEqualToString:@"messageLocation"]){
		NSDictionary *loc = content[@"location"];
		extra = @"Location";
		latitude  = loc[@"latitude"];
		longitude = loc[@"longitude"];

	} else if ([ctype isEqualToString:@"messageLiveLocation"]){
		// The same card as a fixed point, said differently: a live location is
		// a place that keeps changing, and the map is still worth drawing.
		NSDictionary *loc = content[@"location"];
		extra = @"Live location";
		latitude  = loc[@"latitude"];
		longitude = loc[@"longitude"];

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
	else                     text = TGMessagePreview(m);

	// TDLib has over a hundred content types and gains more with every
	// release, most of them one-line notices nobody has written a branch for.
	// Anything that would otherwise be an empty bubble says what it is instead:
	// messageVideoChatStarted reads as "Video chat started". Only content with
	// nothing at all to show reaches this - text and media have already spoken.
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
		@"service"   : @(isService),
		// Several photos sent together share an album id; the chat draws them
		// as one block rather than as unrelated messages.
		@"albumId"   : m[@"media_album_id"] ?: @"",
		// "\U0001F44D 3" per reaction, joined - enough to show under a bubble.
		@"reactions" : TGReactionSummary(m) ?: @"",
		// Options of a poll, so tapping one can vote, and the parts the chat
		// draws around them.
		@"pollOptions"  : m[@"content"][@"poll"][@"options"] ?: @[],
		@"pollQuestion" : m[@"content"][@"poll"][@"question"][@"text"] ?: @"",
		@"pollTotal"    : m[@"content"][@"poll"][@"total_voter_count"] ?: @0,
		@"pollClosed"   : m[@"content"][@"poll"][@"is_closed"] ?: @NO,
		@"pollAnonymous": m[@"content"][@"poll"][@"is_anonymous"] ?: @YES,
		@"duration"  : duration ?: @0,
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
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : query ?: @"",
		@"from_message_id" : @(0),
		@"offset"          : @(0),
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
	// getChatHistory returns only what TDLib already holds, and picks the
	// batch size itself - a first call on a cold chat often answers with one
	// message. Walk backwards from the newest until we have enough or the
	// chat runs out.
	NSMutableArray *collected = [NSMutableArray array];
	[self fetchHistoryChunkForChat:chatId
					 fromMessageId:fromMessageId
							 limit:limit
						 collected:collected
						completion:completion];
}

- (void)fetchHistoryChunkForChat:(int64_t)chatId
                   fromMessageId:(int64_t)fromMessageId
                           limit:(NSInteger)limit
                       collected:(NSMutableArray *)collected
                      completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"getChatHistory",
		@"chat_id"         : @(chatId),
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(0),
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

		int64_t oldest = [[msgs lastObject][@"id"] longLongValue];
		if ((NSInteger)collected.count >= limit || oldest == 0){
			if (completion)
				completion([[collected reverseObjectEnumerator] allObjects]);
			return;
		}

		[me fetchHistoryChunkForChat:chatId
					   fromMessageId:oldest
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
			@"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""},
		},
	} mutableCopy];

	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};

	[self send:request];
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
			@"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""},
		},
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
			NSNumber *fileId = sticker[@"sticker"][@"id"];
			if (!fileId)
				continue;
			NSString *format = sticker[@"format"][@"@type"] ?: @"";
			NSNumber *thumbId = sticker[@"thumbnail"][@"file"][@"id"];
			if (!thumbId || [thumbId integerValue] == 0) {
				if ([format isEqualToString:@"stickerFormatWebp"]) {
					thumbId = fileId;
				}
			}
			[out addObject:@{
				@"fileId"     : fileId,
				@"emoji"      : sticker[@"emoji"] ?: @"",
				@"isAnimated" : @(![format isEqualToString:@"stickerFormatWebp"]),
				@"thumbId"    : thumbId ?: @0,
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)sendStickerWithFileId:(NSInteger)fileId toChat:(int64_t)chatId thread:(int64_t)threadId {
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type"   : @"inputMessageSticker",
			@"sticker" : @{@"@type" : @"inputFileId", @"id" : @(fileId)},
			@"width"   : @512,
			@"height"  : @512,
		},
	}];
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

@end
