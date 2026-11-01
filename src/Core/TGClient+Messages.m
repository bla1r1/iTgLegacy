//
 // TGClient+Messages.m - the message wire.
//
 // Everything a chat needs live: history, sending and editing of every
 // content kind, deleting, forwarding, reactions, typing, scheduled
 // messages, search, comment threads, bot callbacks.
//
#import "TGClientInternal.h"

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

	// A Saved Messages topic is not a message thread; TDLib keeps its own
	// history call for it, and the thread call answers nothing there.
	if ([self chatIsSavedMessages:chatId]){
		[self historyForSavedTopic:threadId fromMessageId:0 limit:limit
						completion:completion];
		return;
	}

	// A forum topic has a topic call of its own. A plain supergroup thread
	// has no forum id, so an error falls back to the message-thread call
	// the chat used before.
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"getForumTopicHistory",
		@"chat_id"         : @(chatId),
		@"forum_topic_id"  : @(threadId),
		@"from_message_id" : @(0),
		@"offset"          : @(0),
		@"limit"           : @(limit),
	} completion:^(NSDictionary *result){
		NSArray *msgs = result[@"messages"];
		if ([msgs isKindOfClass:NSArray.class]){
			NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
			for (NSDictionary *m in [[msgs reverseObjectEnumerator] allObjects])
				[out addObject:TGFlattenMessage(m)];
			if (completion) completion(out);
			return;
		}
		[weakSelf request:@{
			@"@type"           : @"getMessageThreadHistory",
			@"chat_id"         : @(chatId),
			@"message_id"      : @(threadId),
			@"from_message_id" : @(0),
			@"offset"          : @(0),
			@"limit"           : @(limit),
		} completion:^(NSDictionary *threadResult){
			NSArray *threadMsgs = threadResult[@"messages"];
			if (![threadMsgs isKindOfClass:NSArray.class]){
				NSLog(@"TGClient: thread history -> %@", threadResult[@"@type"]);
				if (completion) completion(@[]);
				return;
			}
			NSMutableArray *out = [NSMutableArray arrayWithCapacity:threadMsgs.count];
			for (NSDictionary *m in [[threadMsgs reverseObjectEnumerator] allObjects])
				[out addObject:TGFlattenMessage(m)];
			if (completion) completion(out);
		}];
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
		// No keyboard of its own; the one the message had is not ours to
		// rebuild from here, and an empty one is the honest answer.
		@"reply_markup" : @{@"@type" : @"replyMarkupInlineKeyboard",
							@"rows" : @[]},
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
	[self sendVoiceAtPath:path duration:seconds toChat:chatId thread:threadId
				 viewOnce:NO];
}

- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
				 toChat:(int64_t)chatId thread:(int64_t)threadId
			   viewOnce:(BOOL)viewOnce {
	if (!path.length)
		return;

	NSDictionary *attributes = [[NSFileManager defaultManager]
			attributesOfItemAtPath:path error:nil];
	NSLog(@"TGClient: sending voice %@ (%llu bytes, %lds, once %d) to %lld",
			path.lastPathComponent, [attributes fileSize], (long)seconds,
			viewOnce, chatId);

	// The one-time mode is written the way their clients do it: a timer of
	// 0x7fffffff, whose whole meaning is "gone the moment it is opened".
	id destruct = viewOnce
			? @{@"@type" : @"messageSelfDestructTypeImmediately"}
			: [NSNull null];

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
			@"caption"    : [NSNull null],
			@"self_destruct_type" : destruct,
		},
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"TGClient: voice rejected: %@ %@",
					result[@"code"], result[@"message"]);
		else
			NSLog(@"TGClient: voice accepted, message %@", result[@"id"]);
	}];
}

- (void)sendVideoNoteAtPath:(NSString *)path duration:(NSInteger)seconds
					 toChat:(int64_t)chatId thread:(int64_t)threadId
				   viewOnce:(BOOL)viewOnce {
	if (!path.length)
		return;
	id destruct = viewOnce
			? @{@"@type" : @"messageSelfDestructTypeImmediately"}
			: [NSNull null];
	[self request:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type" : @"inputMessageVideoNote",
			@"video_note" : @{
				@"@type" : @"inputVideoNote",
				@"video_note" : @{@"@type" : @"inputFileLocal", @"path" : path},
				@"duration" : @(seconds),
				@"length" : @(480),
			},
			@"self_destruct_type" : destruct,
		},
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"TGClient: video note rejected: %@ %@",
					result[@"code"], result[@"message"]);
		else
			NSLog(@"TGClient: video note accepted, message %@", result[@"id"]);
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

#pragma mark - the message as a record

- (void)addLocalTextMessage:(NSString *)text
					 toChat:(int64_t)chatId
				 completion:(void (^)(int64_t messageId))completion {
	if (!text.length){
		if (completion) completion(0);
		return;
	}
	int64_t userId = [self.me[@"id"] longLongValue];
	if (!userId){
		if (completion) completion(0);
		return;
	}
	[self request:@{
		@"@type"                  : @"addLocalMessage",
		@"chat_id"                : @(chatId),
		@"sender_id"              : @{@"@type" : @"messageSenderUser",
									  @"user_id" : @(userId)},
		@"reply_to"               : [NSNull null],
		@"disable_notification"   : @YES,
		@"input_message_content"  : @{@"@type" : @"inputMessageText",
									  @"text" : TGFormattedText(text)},
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

- (void)clickAnimatedEmojiMessage:(int64_t)messageId
						   inChat:(int64_t)chatId
					   completion:(void (^)(NSString *emoji))completion {
	[self request:@{
		@"@type"      : @"clickAnimatedEmojiMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		// The answer is a Sticker. TDLib's JSON has it both as the object
		// itself in some builds and under "sticker" in the wrapped form, so
		// accept either instead of losing a successful roll.
		NSDictionary *sticker = [result[@"sticker"] isKindOfClass:NSDictionary.class]
				? result[@"sticker"] : result;
		NSString *emoji = sticker[@"emoji"];
		completion([emoji isKindOfClass:NSString.class] ? emoji : nil);
	}];
}

- (void)clearReplyMarkupOfMessage:(int64_t)messageId
						   inChat:(int64_t)chatId
					   completion:(void (^)(BOOL ok))completion {
	// An inline keyboard with no rows is how TDLib spells "no buttons".
	[self request:@{
		@"@type"        : @"editMessageReplyMarkup",
		@"chat_id"      : @(chatId),
		@"message_id"   : @(messageId),
		@"reply_markup" : @{@"@type" : @"replyMarkupInlineKeyboard",
							@"rows" : @[]},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)callbackQueryMessage:(int64_t)messageId
					  inChat:(int64_t)chatId
			 callbackQueryId:(int64_t)callbackQueryId
				  completion:(void (^)(NSDictionary *message))completion {
	[self request:@{
		@"@type"             : @"getCallbackQueryMessage",
		@"chat_id"           : @(chatId),
		@"message_id"        : @(messageId),
		@"callback_query_id" : @(callbackQueryId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"message"])
			completion(TGFlattenMessage(result));
		else
			completion(nil);
	}];
}

- (void)localMessageWithId:(int64_t)messageId
					inChat:(int64_t)chatId
				completion:(void (^)(NSDictionary *message))completion {
	[self request:@{
		@"@type"      : @"getMessageLocally",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"message"])
			completion(TGFlattenMessage(result));
		else
			completion(nil);
	}];
}

/// The MessageTopic a chat view's threadId names: a Saved Messages topic, a
/// forum topic, or an ordinary message thread. Null when the whole chat is
/// meant, which is what a non-forum chat without a thread passes.
static id TGMessageTopicForThread(TGClient *client, int64_t chatId, int64_t threadId) {
	if (threadId == 0)
		return [NSNull null];
	if ([client chatIsSavedMessages:chatId])
		return @{@"@type" : @"messageTopicSavedMessages",
				 @"saved_messages_topic_id" : @(threadId)};
	if ([client.chatsById[@(chatId)][@"isForum"] boolValue])
		return @{@"@type" : @"messageTopicForum",
				 @"forum_topic_id" : @(threadId)};
	return @{@"@type" : @"messageTopicThread",
			 @"message_thread_id" : @(threadId)};
}

- (void)positionOfMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
				   thread:(int64_t)threadId
			   completion:(void (^)(NSInteger position))completion {
	[self request:@{
		@"@type"      : @"getChatMessagePosition",
		@"chat_id"    : @(chatId),
		@"topic_id"   : TGMessageTopicForThread(self, chatId, threadId),
		@"filter"     : @{@"@type" : @"searchMessagesFilterEmpty"},
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"count"] integerValue]);
	}];
}

- (void)sparsePositionsInChat:(int64_t)chatId
				fromMessageId:(int64_t)fromMessageId
					   thread:(int64_t)threadId
						limit:(NSInteger)limit
				   completion:(void (^)(NSArray *messageIds))completion {
	// This call has no MessageTopic field, only a saved-topic id; a forum's
	// positions stay chat-wide because the schema gives no topic filter.
	int64_t savedTopicId = [self chatIsSavedMessages:chatId] ? threadId : 0;
	[self request:@{
		@"@type"                  : @"getChatSparseMessagePositions",
		@"chat_id"                : @(chatId),
		@"filter"                 : @{@"@type" : @"searchMessagesFilterEmpty"},
		@"from_message_id"        : @(fromMessageId),
		@"limit"                  : @(MAX((NSInteger)50, MIN(limit, (NSInteger)2000))),
		@"saved_messages_topic_id": @(savedTopicId),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *positions = [result[@"positions"] isKindOfClass:NSArray.class]
				? result[@"positions"] : @[];
		completion(positions);
	}];
}

- (void)statisticsOfMessage:(int64_t)messageId
					 inChat:(int64_t)chatId
				 completion:(void (^)(NSDictionary *statistics))completion {
	[self request:@{
		@"@type"      : @"getMessageStatistics",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		// The flag only picks the graph's colour scheme; the numbers are the
		// same either way, so a light chart is safe on every theme.
		@"is_dark"    : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion([result[@"@type"] isEqualToString:@"messageStatistics"]
				? result : nil);
	}];
}

- (void)reportViewOfMessage:(int64_t)messageId
					 inChat:(int64_t)chatId
				timeInViewMs:(NSInteger)timeInViewMs
		  activeTimeInViewMs:(NSInteger)activeTimeInViewMs
				 heightRatio:(NSInteger)heightPerMille
			   seenRangeRatio:(NSInteger)seenPerMille
				 completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"                           : @"sendMessageViewMetrics",
		@"chat_id"                         : @(chatId),
		@"message_id"                      : @(messageId),
		@"time_in_view_ms"                 : @(MAX((NSInteger)0, timeInViewMs)),
		@"active_time_in_view_ms"          : @(MAX((NSInteger)0, activeTimeInViewMs)),
		@"height_to_viewport_ratio_per_mille" : @(MAX((NSInteger)0, MIN(heightPerMille, (NSInteger)1000))),
		@"seen_range_ratio_per_mille"      : @(MAX((NSInteger)0, MIN(seenPerMille, (NSInteger)1000))),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setReactions:(NSArray *)emojis
		   onMessage:(int64_t)messageId
			  inChat:(int64_t)chatId
		  completion:(void (^)(BOOL ok))completion {
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *emoji in emojis)
		if ([emoji isKindOfClass:NSString.class] && emoji.length)
			[types addObject:@{@"@type" : @"reactionTypeEmoji",
							   @"emoji" : emoji}];
	[self request:@{
		@"@type"          : @"setMessageReactions",
		@"chat_id"        : @(chatId),
		@"message_id"     : @(messageId),
		@"reaction_types" : types,
		@"is_big"         : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)personalChatHistoryForUser:(int64_t)userId
							 limit:(NSInteger)limit
						completion:(void (^)(NSArray *messages))completion {
	[self request:@{
		@"@type"   : @"getPersonalChatHistory",
		@"user_id" : @(userId),
		@"limit"   : @(MAX((NSInteger)1, MIN(limit, (NSInteger)20))),
	} completion:^(NSDictionary *result){
		NSArray *msgs = result[@"messages"];
		if (![msgs isKindOfClass:NSArray.class]){
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
		for (NSDictionary *m in msgs)
			[out addObject:TGFlattenMessage(m)];
		if (completion) completion(out);
	}];
}

#pragma mark - inline messages a bot owns

- (void)editInlineMessageText:(NSString *)inlineMessageId
						 text:(NSString *)text
				   completion:(void (^)(BOOL ok))completion {
	if (!inlineMessageId.length || !text.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"                  : @"editInlineMessageText",
		@"inline_message_id"      : inlineMessageId,
		@"reply_markup"           : [NSNull null],
		@"input_message_content"  : @{@"@type" : @"inputMessageText",
									  @"text" : TGFormattedText(text)},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)editInlineMessageCaption:(NSString *)inlineMessageId
						 caption:(NSString *)caption
					  completion:(void (^)(BOOL ok))completion {
	if (!inlineMessageId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"        : @"editInlineMessageCaption",
		@"inline_message_id" : inlineMessageId,
		@"reply_markup" : [NSNull null],
		@"caption"      : TGFormattedText(caption ?: @""),
		@"show_caption_above_media" : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)clearInlineMessageReplyMarkup:(NSString *)inlineMessageId
						   completion:(void (^)(BOOL ok))completion {
	if (!inlineMessageId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"             : @"editInlineMessageReplyMarkup",
		@"inline_message_id" : inlineMessageId,
		@"reply_markup"      : @{@"@type" : @"replyMarkupInlineKeyboard",
								 @"rows" : @[]},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)editInlineMessagePhoto:(NSString *)inlineMessageId
					   photoId:(int64_t)photoId
					   caption:(NSString *)caption
					completion:(void (^)(BOOL ok))completion {
	if (!inlineMessageId.length || photoId <= 0){
		if (completion) completion(NO);
		return;
	}
	// The media edits take an inputPhoto, not a local file: TDLib wants the
	// photo the bot already has. An empty reference is what a caller that
	// only knows the id can send; the server says whether it is enough.
	[self request:@{
		@"@type"             : @"editInlineMessageMedia",
		@"inline_message_id" : inlineMessageId,
		@"reply_markup"      : [NSNull null],
		@"input_message_content" : @{
			@"@type"   : @"inputMessagePhoto",
			@"photo"   : @{@"@type" : @"inputPhoto",
						   @"id" : @(photoId),
						   @"access_hash" : @(0),
						   @"file_reference" : @""},
			@"caption" : TGFormattedText(caption ?: @""),
			@"show_caption_above_media" : @NO,
			@"self_destruct_type" : [NSNull null],
			@"has_spoiler" : @NO,
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)editInlineMessageLiveLocation:(NSString *)inlineMessageId
							 latitude:(double)latitude
							longitude:(double)longitude
						   completion:(void (^)(BOOL ok))completion {
	if (!inlineMessageId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"             : @"editInlineMessageLiveLocation",
		@"inline_message_id" : inlineMessageId,
		@"reply_markup"      : [NSNull null],
		@"location"          : @{
			@"@type"   : @"liveLocation",
			@"location" : @{@"@type" : @"location",
							@"latitude" : @(latitude),
							@"longitude" : @(longitude),
							@"horizontal_accuracy" : @(0)},
			// 0x7FFFFFFF keeps the period the message already has.
			@"live_period" : @(0x7FFFFFFF),
			@"heading" : @(0),
			@"proximity_alert_radius" : @(0),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
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

/// What one answer still allows. TDLib answers with a record of four flags;
/// the card names each one instead of showing the raw object, because a
/// client that only prints JSON has not told the user anything.
- (void)pollOptionProperties:(NSString *)optionId
				   ofMessage:(int64_t)messageId
					  inChat:(int64_t)chatId
				  completion:(void (^)(NSDictionary *, NSString *))completion {
	optionId = [optionId isKindOfClass:NSString.class] ? optionId : @"";
	if (!optionId.length){
		if (completion) completion(nil, @"This answer has no id to look up.");
		return;
	}
	[self request:@{
		@"@type"        : @"getPollOptionProperties",
		@"chat_id"      : @(chatId),
		@"message_id"   : @(messageId),
		@"poll_option_id" : optionId,
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			NSString *message = [result[@"message"] isKindOfClass:NSString.class]
					? result[@"message"] : @"Telegram refused that lookup.";
			if (completion) completion(nil, message);
			return;
		}
		if (completion)
			completion(@{
				@"canBeDeleted"             : result[@"can_be_deleted"] ?: @NO,
				@"canBeReplied"             : result[@"can_be_replied"] ?: @NO,
				@"canBeRepliedInAnotherChat": result[@"can_be_replied_in_another_chat"] ?: @NO,
				@"canGetLink"               : result[@"can_get_link"] ?: @NO,
			}, nil);
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
		else if ([type isEqualToString:@"internalLinkTypeUserToken"])
			completion(@"userToken", result[@"token"]);
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

@end
