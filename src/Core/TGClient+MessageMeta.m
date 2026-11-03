//
 // TGClient+MessageMeta.m - facts around one message.
//
 // Link info, drafts, auto-delete, viewers, forwards, the reaction
 // lists, the calendar jump, translation - every read that hangs off
 // a message and answers with context rather than content.
//
#import "TGClientInternal.h"

@implementation TGClient (MessageMeta)
#pragma mark - facts a screen asks for

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

#pragma mark - more of the same, kept apart for review

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
					@"chat_id" : @(chatId), @"message_id" : @(messageId),
					@"offset" : @"", @"limit" : @(50)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"publicForwards"]){
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
				[result[@"unavailability_reason"] isKindOfClass:NSDictionary.class]){
			completion(nil);
			return;
		}
		NSArray *top = result[@"top_reactions"];
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *r in top){
			// Live TDLib nests the glyph under reactionTypeEmoji; the flat
			// spelling is what older fixtures answer, and both are read.
			NSString *emoji = r[@"type"][@"emoji"] ?: r[@"emoji"];
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
	NSDictionary *type = emoji.length
			? @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji}
			: nil;
	[self addedReactionsOfMessage:messageId
						   inChat:chatId
					 reactionType:type
						   offset:offset
					   completion:completion];
}

/// The same list for either reaction spelling: a custom emoji has no character
/// to send, so the id travels as reactionTypeCustomEmoji instead.
- (void)addedReactionsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
				   reactionType:(NSDictionary *)reactionType
						 offset:(NSString *)offset
					 completion:(void (^)(NSArray *rows, NSString *next))completion {
	if (!reactionType){
		if (completion) completion(nil, nil);
		return;
	}
	[self request:@{@"@type" : @"getMessageAddedReactions",
					@"chat_id" : @(chatId), @"message_id" : @(messageId),
					@"reaction_type" : reactionType,
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
		NSArray *reactions = result[@"reactions"];
		if ([reactions isKindOfClass:NSArray.class]){
			for (NSDictionary *r in reactions){
				if (![r isKindOfClass:NSDictionary.class])
					continue;
				// addedReaction carries is_outgoing itself; older fixtures
				// omit it and the sender still says who it was.
				NSNumber *date = r[@"date"];
				[rows addObject:@{
					@"sender" : r[@"sender_id"] ?: @{},
					@"date"   : date ?: @(0),
					@"mine"   : r[@"is_outgoing"] ?: @NO,
					@"type"   : r[@"type"] ?: @{},
				}];
			}
		}
		NSString *next = result[@"next_offset"];
		completion(rows, [next isKindOfClass:NSString.class] ? next : @"");
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
	NSMutableDictionary *ask = [@{@"@type" : @"getChatMessageCount",
								  @"chat_id" : @(chatId),
								  @"filter" : @{@"@type" : @"searchMessagesFilterEmpty"},
								  @"return_local" : @NO} mutableCopy];
	// The whole chat is no topic at all: td_api.tl has no "main" topic type.
	if (threadId)
		ask[@"topic_id"] = @{@"@type" : @"messageTopicThread", @"message_thread_id" : @(threadId)};
	[self request:ask
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"count"])
			completion([result[@"count"] integerValue]);
		else
			completion(0);
	}];
}

- (void)messageCountInChat:(int64_t)chatId
					filter:(NSString *)filterType
				completion:(void (^)(NSInteger count))completion {
	[self request:@{@"@type" : @"getChatMessageCount",
					@"chat_id" : @(chatId),
					@"filter" : @{@"@type" : filterType ?: @"searchMessagesFilterEmpty"},
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

#pragma mark - effects, import, prepared messages

- (void)messageEffectWithId:(int64_t)effectId
				 completion:(void (^)(NSDictionary *effect))completion {
	[self request:@{@"@type" : @"getMessageEffect", @"effect_id" : @(effectId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"messageEffect"]){
			completion(nil);
			return;
		}
		completion(@{
			@"emoji"   : result[@"emoji"] ?: @"",
			@"premium" : result[@"is_premium"] ?: @NO,
			@"kind"    : result[@"type"][@"@type"] ?: @"",
		});
	}];
}

- (void)messageFileTypeForHead:(NSString *)head
					completion:(void (^)(NSDictionary *fileType))completion {
	if (!head.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getMessageFileType", @"message_file_head" : head}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = result[@"@type"];
		if ([type isEqualToString:@"messageFileTypePrivate"])
			completion(@{@"kind" : @"private",
						 @"title" : result[@"name"] ?: @""});
		else if ([type isEqualToString:@"messageFileTypeGroup"])
			completion(@{@"kind" : @"group",
						 @"title" : result[@"title"] ?: @""});
		else
			completion(@{@"kind" : @"unknown", @"title" : @""});
	}];
}

- (void)importConfirmationTextForChat:(int64_t)chatId
						   completion:(void (^)(NSString *text))completion {
	[self request:@{@"@type" : @"getMessageImportConfirmationText",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		completion([result[@"@type"] isEqualToString:@"text"]
				? (result[@"text"] ?: @"") : @"");
	}];
}

- (void)importMessagesFromFile:(NSString *)path
				 attachedFiles:(NSArray *)attachedPaths
					  intoChat:(int64_t)chatId
					completion:(void (^)(BOOL ok))completion {
	if (!path.length){
		if (completion) completion(NO);
		return;
	}
	NSMutableArray *attached = [NSMutableArray array];
	for (NSString *file in attachedPaths)
		if ([file isKindOfClass:NSString.class] && file.length)
			[attached addObject:@{@"@type" : @"inputFileLocal",
								  @"path" : file}];
	[self request:@{
		@"@type"          : @"importMessages",
		@"chat_id"        : @(chatId),
		@"message_file"   : @{@"@type" : @"inputFileLocal", @"path" : path},
		@"attached_files" : attached,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)preparedInlineMessageFromBot:(int64_t)botUserId
				   preparedMessageId:(NSString *)preparedMessageId
						  completion:(void (^)(NSDictionary *prepared))completion {
	if (!preparedMessageId.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"               : @"getPreparedInlineMessage",
		@"bot_user_id"         : @(botUserId),
		@"prepared_message_id" : preparedMessageId,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"preparedInlineMessage"]){
			completion(nil);
			return;
		}
		completion(@{
			@"id"         : result[@"id"] ?: @"",
			@"result"     : result[@"result"] ?: @{},
			@"allowUsers" : result[@"chat_types"][@"allow_user_chats"] ?: @NO,
			@"allowGroups": result[@"chat_types"][@"allow_group_chats"] ?: @NO,
			@"allowBots"  : result[@"chat_types"][@"allow_bot_chats"] ?: @NO,
			@"allowChannels" : result[@"chat_types"][@"allow_channel_chats"] ?: @NO,
		});
	}];
}

- (void)savePreparedInlineMessageForUser:(int64_t)userId
									text:(NSString *)text
								   title:(NSString *)title
							  completion:(void (^)(NSString *preparedMessageId))completion {
	if (!text.length){
		if (completion) completion(nil);
		return;
	}
	NSDictionary *result = @{
		@"@type"               : @"inputInlineQueryResultArticle",
		@"id"                  : @"legacy-prepared",
		@"url"                 : @"",
		@"title"               : title.length ? title : text,
		@"description"         : text,
		@"thumbnail_url"       : @"",
		@"thumbnail_width"     : @0,
		@"thumbnail_height"    : @0,
		@"reply_markup"        : [NSNull null],
		@"input_message_content" : @{@"@type" : @"inputMessageText",
									 @"text" : TGFormattedText(text)},
	};
	[self request:@{
		@"@type"       : @"savePreparedInlineMessage",
		@"user_id"     : @(userId),
		@"result"      : result,
		@"chat_types"  : @{@"@type" : @"targetChatTypes",
						   @"allow_user_chats" : @YES,
						   @"allow_bot_chats" : @NO,
						   @"allow_group_chats" : @YES,
						   @"allow_channel_chats" : @YES},
	} completion:^(NSDictionary *answer){
		if (!completion)
			return;
		BOOL ok = [answer[@"@type"] isEqualToString:@"preparedInlineMessageId"];
		completion(ok ? answer[@"id"] : nil);
	}];
}

- (void)sendTextDraft:(NSString *)text
			   toChat:(int64_t)chatId
				topic:(int64_t)topicId
			  draftId:(int64_t)draftId
			   canStop:(BOOL)canStop
				  keep:(BOOL)keepOnStop
		   completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"          : @"sendTextMessageDraft",
		@"chat_id"        : @(chatId),
		@"forum_topic_id" : @(topicId),
		@"draft_id"       : @(draftId),
		@"can_stop"       : @(canStop),
		@"keep_on_stop"   : @(keepOnStop),
		@"text"           : text.length ? TGFormattedText(text) : [NSNull null],
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)stopTextDraft:(int64_t)draftId
			   inChat:(int64_t)chatId
				topic:(int64_t)topicId
		   completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"     : @"stopPendingMessage",
		@"chat_id"   : @(chatId),
		@"topic_id"  : topicId ? @{@"@type" : @"messageTopicForum",
									@"forum_topic_id" : @(topicId)}
							  : (id)[NSNull null],
		@"draft_id"  : @(draftId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

@end
