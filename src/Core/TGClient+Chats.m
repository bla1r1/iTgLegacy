#import "TGClientInternal.h"

/// Preview text for a chat's last message. TDLib nests the content by type.
NSString *TGMessagePreview(NSDictionary *message) {
	NSDictionary *content = message[@"content"];
	NSString *ctype = content[@"@type"];

	if ([ctype isEqualToString:@"messageText"])
		return content[@"text"][@"text"] ?: @"";
	if ([ctype isEqualToString:@"messagePhoto"])
		return @"Photo";
	if ([ctype isEqualToString:@"messageVideo"])
		return @"Video";
	if ([ctype isEqualToString:@"messageVoiceNote"])
		return @"Voice message";
	if ([ctype isEqualToString:@"messageVideoNote"])
		return @"Video message";
	if ([ctype isEqualToString:@"messageSticker"])
		return @"Sticker";
	if ([ctype isEqualToString:@"messageDocument"])
		return @"Document";
	if ([ctype isEqualToString:@"messageAudio"])
		return @"Audio";
	if ([ctype isEqualToString:@"messageAnimation"])
		return @"GIF";
	if ([ctype isEqualToString:@"messageAnimatedEmoji"])
		return content[@"emoji"] ?: @"Emoji";
	if ([ctype isEqualToString:@"messageContact"])
		return @"Contact";
	if ([ctype isEqualToString:@"messageVenue"])
		return @"Venue";
	if ([ctype isEqualToString:@"messageLocation"])
		return @"Location";
	if ([ctype isEqualToString:@"messageCall"])
		return @"Call";
	if ([ctype isEqualToString:@"messageChatJoinByLink"] ||
		[ctype isEqualToString:@"messageChatJoinByRequest"])
		return @"joined the group";
	if ([ctype isEqualToString:@"messageChatAddMembers"])
		return @"added a member";
	if ([ctype isEqualToString:@"messageChatDeleteMember"])
		return @"left the group";
	if ([ctype isEqualToString:@"messageChatChangeTitle"])
		return @"renamed the group";
	if ([ctype isEqualToString:@"messageChatChangePhoto"])
		return @"changed the group photo";
	if ([ctype isEqualToString:@"messagePinMessage"])
		return @"pinned a message";
	if ([ctype isEqualToString:@"messagePoll"])
		return @"Poll";
	// Everything else reads as its own type name turned back into a sentence,
	// the same way the chat itself renders it.
	return ctype.length ? TGPhraseFromTypeName(ctype) : @"";
}

/// Chats are ordered by the "order" of their position in a list. It is an
/// int64 sent as a string, so it must not be compared as a string.
int64_t TGOrderInList(NSArray *positions, NSString *listType) {
	for (NSDictionary *p in positions){
		NSDictionary *list = p[@"list"];
		if ([list[@"@type"] isEqualToString:listType])
			return (int64_t)[p[@"order"] longLongValue];
	}
	return 0;
}

BOOL TGPinnedInMain(NSArray *positions) {
	for (NSDictionary *p in positions)
		if ([p[@"list"][@"@type"] isEqualToString:@"chatListMain"])
			return [p[@"is_pinned"] boolValue];
	return NO;
}

int64_t TGMainListOrder(NSArray *positions) {
	return TGOrderInList(positions, @"chatListMain");
}

int64_t TGArchiveOrder(NSArray *positions) {
	return TGOrderInList(positions, @"chatListArchive");
}

@implementation TGClient (Chats)

#pragma mark - chats

- (void)loadChats {
	// TDLib only emits updateNewChat/updateChatPosition after the list is
	// asked for; without loadChats nothing about chats ever arrives. It also
	// loads in batches - one call is one batch, and it answers with error 404
	// once everything is loaded - so this has to be repeated until the list
	// stops growing.
	if (self.chatListComplete)
		return;
	self.chatsAtLastLoad = self.chatsById.count;
	NSLog(@"TGClient: loadChats attempt %lu (have %lu)",
			(unsigned long)self.loadChatsAttempts + 1,
			(unsigned long)self.chatsById.count);
	[self send:@{
		@"@type"     : @"loadChats",
		@"chat_list" : @{@"@type" : @"chatListMain"},
		@"limit"     : @(50),
	}];
	[self send:@{
		@"@type"     : @"loadChats",
		@"chat_list" : @{@"@type" : @"chatListArchive"},
		@"limit"     : @(50),
	}];

	// A batch beyond the first needs a server round trip, so silence for a
	// second or two means nothing. Keep asking on a timer and stop only when
	// TDLib says 404 (everything loaded) or after a sane number of tries.
	self.loadChatsAttempts++;
	if (self.loadChatsAttempts > 12)
		return;

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGClient *me = weakSelf;
		if (me && !me.chatListComplete)
			[me loadChats];
	});
}

- (void)membersOfChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSDictionary *type = chat[@"type"];
		NSString *kind = type[@"@type"];

		void (^collect)(NSArray *) = ^(NSArray *members){
			TGClient *me = weakSelf;
			NSMutableArray *out = [NSMutableArray array];
			for (NSDictionary *member in members){
				int64_t userId = [member[@"member_id"][@"user_id"] longLongValue];
				if (!userId)
					continue;
				[out addObject:@{
					@"id"   : @(userId),
					@"name" : [me nameForUserId:userId] ?: @"",
				}];
			}
			if (completion) completion(out);
		};

		if ([kind isEqualToString:@"chatTypeBasicGroup"]){
			[weakSelf request:@{
				@"@type"          : @"getBasicGroupFullInfo",
				@"basic_group_id" : type[@"basic_group_id"],
			} completion:^(NSDictionary *full){ collect(full[@"members"]); }];
			return;
		}
		if ([kind isEqualToString:@"chatTypeSupergroup"]){
			[weakSelf request:@{
				@"@type"        : @"getSupergroupMembers",
				@"supergroup_id": type[@"supergroup_id"],
				@"filter"       : @{@"@type" : @"supergroupMembersFilterRecent"},
				@"offset"       : @(0),
				@"limit"        : @(50),
			} completion:^(NSDictionary *result){ collect(result[@"members"]); }];
			return;
		}
		if (completion) completion(@[]);
	}];
}

- (void)canSendInChat:(int64_t)chatId completion:(void (^)(BOOL, BOOL))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSDictionary *type = chat[@"type"];
		BOOL isChannel = [type[@"@type"] isEqualToString:@"chatTypeSupergroup"] &&
						 [type[@"is_channel"] boolValue];
		// TDLib answers this directly; permissions alone would miss the case
		// where the user is not a member at all.
		BOOL canSend = [chat[@"permissions"][@"can_send_basic_messages"] boolValue];
		if (isChannel)
			canSend = [chat[@"can_be_edited"] boolValue] ||
					  [chat[@"permissions"][@"can_send_basic_messages"] boolValue];
		if (completion) completion(canSend, isChannel);
	}];
}

- (void)deleteChat:(int64_t)chatId {
	[self.chatsById removeObjectForKey:@(chatId)];
	[self rebuildChats];

	// A group has to be left as well, or it comes straight back on the next
	// message.
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSString *kind = chat[@"type"][@"@type"];
		BOOL isMembership = [kind isEqualToString:@"chatTypeSupergroup"] ||
							[kind isEqualToString:@"chatTypeBasicGroup"];
		[self send:@{
			@"@type"       : @"deleteChatHistory",
			@"chat_id"     : @(chatId),
			@"remove_from_chat_list" : @YES,
			@"revoke"      : @NO,
		}];
		if (isMembership)
			[self send:@{@"@type" : @"leaveChat", @"chat_id" : @(chatId)}];
	}];
}

- (void)setChat:(int64_t)chatId joined:(BOOL)joined {
	[self send:@{@"@type" : joined ? @"joinChat" : @"leaveChat", @"chat_id" : @(chatId)}];
}

- (void)pinnedMessageForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getChatPinnedMessage", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *m){
		if (completion)
			completion([m[@"@type"] isEqualToString:@"message"] ? TGFlattenMessage(m) : nil);
	}];
}

- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned {
	[self send:@{
		@"@type"     : @"toggleChatIsPinned",
		@"chat_list" : @{@"@type" : @"chatListMain"},
		@"chat_id"   : @(chatId),
		@"is_pinned" : @(pinned),
	}];
}

/// A folder is a chat list of its own in TDLib, so this is getChats against
/// that list; the rows themselves are the ones the client already holds.
- (void)chatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"     : @"getChats",
		@"chat_list" : @{@"@type" : @"chatListFolder",
						 @"chat_folder_id" : @(folderId)},
		@"limit"     : @(100),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		if (!me){
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSNumber *chatId in result[@"chat_ids"]){
			NSDictionary *info = me.chatsById[chatId];
			// An unknown id is still a chat the folder holds: this folder
			// walk is often the first time tdlib hears about it, and its
			// info update runs behind the answer. A pending placeholder
			// keeps the merge honest (it counts the drop and retries)
			// instead of shrinking folder lists silently.
			if (info)
				[out addObject:info];
			else
				[out addObject:@{@"id" : chatId, @"pending" : @YES}];
		}
		NSLog(@"TGClient: folder %ld holds %lu chats",
				(long)folderId, (unsigned long)out.count);
		if (completion) completion(out);
	}];
}

/// A forum keeps several threads in one chat; each topic reads like a chat row.
- (void)forumTopicsForChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"                    : @"getForumTopics",
		@"chat_id"                  : @(chatId),
		@"query"                    : @"",
		@"offset_date"              : @(0),
		@"offset_message_id"        : @(0),
		@"offset_message_thread_id" : @(0),
		@"limit"                    : @(100),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *topic in result[@"topics"]){
			NSDictionary *info = topic[@"info"];
			NSDictionary *last = topic[@"last_message"];
			[out addObject:@{
				@"threadId" : info[@"message_thread_id"] ?: @(0),
				@"name"     : info[@"name"] ?: @"",
				@"text"     : [last isKindOfClass:NSDictionary.class]
								? (TGMessagePreview(last) ?: @"") : @"",
				@"unread"   : topic[@"unread_count"] ?: @(0),
				@"date"     : last[@"date"] ?: @(0),
			}];
		}
		NSLog(@"TGClient: %lu forum topics", (unsigned long)out.count);
		if (completion) completion(out);
	}];
}

- (void)chatProfile:(int64_t)chatId completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSString *kind = chat[@"type"][@"@type"];
		void (^answer)(NSDictionary *) = ^(NSDictionary *full){
			if (completion) completion(@{
				@"description" : full[@"description"] ?: @"",
				@"members"     : full[@"member_count"] ?: @0,
				@"admins"      : full[@"administrator_count"] ?: @0,
				@"inviteLink"  : full[@"invite_link"][@"invite_link"] ?: @"",
			});
		};

		if ([kind isEqualToString:@"chatTypeSupergroup"]){
			[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
								@"supergroup_id" : chat[@"type"][@"supergroup_id"]}
				   completion:answer];
		} else if ([kind isEqualToString:@"chatTypeBasicGroup"]){
			[weakSelf request:@{@"@type" : @"getBasicGroupFullInfo",
								@"basic_group_id" : chat[@"type"][@"basic_group_id"]}
				   completion:answer];
		} else {
			answer(@{});
		}
	}];
}

- (BOOL)isChatMuted:(int64_t)chatId {
	return [self.chatsById[@(chatId)][@"isMuted"] boolValue];
}

- (void)clearHistoryInChat:(int64_t)chatId {
	// Without remove_from_chat_list this empties the chat and leaves it there,
	// which is what "clear history" means as opposed to "delete chat".
	[self send:@{
		@"@type"                 : @"deleteChatHistory",
		@"chat_id"               : @(chatId),
		@"remove_from_chat_list" : @NO,
		@"revoke"                : @NO,
	}];
}

- (void)setChat:(int64_t)chatId autoDeleteSeconds:(NSInteger)seconds {
	[self send:@{
		@"@type"   : @"setChatMessageAutoDeleteTime",
		@"chat_id" : @(chatId),
		@"message_auto_delete_time" : @(seconds),
	}];
}

- (void)chatWithUsername:(NSString *)username
              completion:(void (^)(int64_t, NSString *))completion {
	// searchPublicChat resolves the name and puts the chat in the local
	// database in one step, which is what a link or a QR code needs.
	[self request:@{
		@"@type"    : @"searchPublicChat",
		@"username" : username ?: @"",
	} completion:^(NSDictionary *chat){
		if (completion)
			completion([chat[@"id"] longLongValue], chat[@"title"]);
	}];
}

- (void)joinChatByInviteLink:(NSString *)inviteLink
                  completion:(void (^)(int64_t, NSString *))completion {
	[self request:@{
		@"@type"       : @"joinChatByInviteLink",
		@"invite_link" : inviteLink ?: @"",
	} completion:^(NSDictionary *chat){
		if (completion)
			completion([chat[@"id"] longLongValue], chat[@"title"]);
	}];
}

- (void)openChat:(int64_t)chatId {
	[self send:@{
		@"@type"   : @"openChat",
		@"chat_id" : @(chatId),
	}];
}

- (void)closeChat:(int64_t)chatId {
	[self send:@{
		@"@type"   : @"closeChat",
		@"chat_id" : @(chatId),
	}];
}

/// Archiving is a move between the two chat lists, not a flag on the chat.
/// TDLib answers with updateChatPosition, so the list rebuilds itself.
- (void)setChat:(int64_t)chatId archived:(BOOL)archived {
	[self send:@{
		@"@type"     : @"addChatToList",
		@"chat_id"   : @(chatId),
		@"chat_list" : @{@"@type" : (archived ? @"chatListArchive" : @"chatListMain")},
	}];
}

- (void)setChat:(int64_t)chatId muted:(BOOL)muted {
	// A very large mute_for is how TDLib expresses "muted", there is no flag.
	[self send:@{
		@"@type" : @"setChatNotificationSettings",
		@"chat_id" : @(chatId),
		@"notification_settings" : @{
			@"@type"                : @"chatNotificationSettings",
			@"use_default_mute_for" : @NO,
			@"mute_for"             : @(muted ? 365 * 24 * 3600 : 0),
		},
	}];
}

- (NSNumber *)photoFileIdForChat:(int64_t)chatId {
	// The cache is the source of truth: the wrapper lists (.chats holding
	// only the un-foldered portion, archive the pulled-up one) came and went
	// with the active folder, and a chat opened through a folder used to
	// lose its photo to a nil lookup and render as initials.
	NSDictionary *info = self.chatsById[@(chatId)];
	return info[@"photoFileId"];
}

/// Member count for a group, so the chat header can carry a subtitle.
- (void)memberCountForChat:(int64_t)chatId completion:(void (^)(NSInteger count))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSDictionary *type = chat[@"type"];
		NSString *t = type[@"@type"];
		if ([t isEqualToString:@"chatTypeBasicGroup"]){
			[self request:@{@"@type" : @"getBasicGroupFullInfo",
							@"basic_group_id" : type[@"basic_group_id"]}
			   completion:^(NSDictionary *full){
				if (completion) completion([full[@"members"] count]);
			}];
		} else if ([t isEqualToString:@"chatTypeSupergroup"]){
			[self request:@{@"@type" : @"getSupergroupFullInfo",
							@"supergroup_id" : type[@"supergroup_id"]}
			   completion:^(NSDictionary *full){
				if (completion) completion([full[@"member_count"] integerValue]);
			}];
		} else if (completion){
			completion(0);
		}
	}];
}

- (void)mergeChat:(NSDictionary *)chat {
	if (![chat isKindOfClass:NSDictionary.class])
		return;

	NSNumber *chatId = chat[@"id"];
	if (!chatId)
		return;

	NSMutableDictionary *info = self.chatsById[chatId];
	if (!info){
		info = [NSMutableDictionary dictionary];
		self.chatsById[chatId] = info;
	}

	info[@"id"] = chatId;
	if (chat[@"title"])
		info[@"title"] = chat[@"title"];

	// The chat with yourself is Saved Messages everywhere in Telegram, not a
	// conversation under your own name and photo.
	if ([chatId longLongValue] == [self savedMessagesChatId] &&
		[self savedMessagesChatId] != 0){
		info[@"title"] = @"Saved Messages";
		info[@"isSaved"] = @YES;
		[info removeObjectForKey:@"photoFileId"];
	}
	if (chat[@"unread_count"])
		info[@"unread"] = chat[@"unread_count"];
	if (chat[@"last_read_outbox_message_id"])
		info[@"readOutbox"] = chat[@"last_read_outbox_message_id"];
	if (chat[@"last_read_inbox_message_id"])
		info[@"readInbox"] = chat[@"last_read_inbox_message_id"];

	NSString *chatType = chat[@"type"][@"@type"];
	if (chatType)
		info[@"isGroup"] = @(![chatType isEqualToString:@"chatTypePrivate"] &&
							 ![chatType isEqualToString:@"chatTypeSecret"]);

	// A forum keeps several threads in one chat, so it opens on a topic list
	// rather than a merged stream. The flag is on the supergroup, not here:
	// the chat only names which supergroup it is, and reading is_forum off the
	// chat - which has no such field - meant no forum was ever recognised.
	NSNumber *supergroupId = chat[@"type"][@"supergroup_id"];
	if (supergroupId){
		info[@"supergroupId"] = supergroupId;
		NSNumber *known = self.forumSupergroups[supergroupId];
		if (known){
			info[@"isForum"] = known;
		} else {
			// Not seen yet: ask, and the answer updates the row in place.
			__weak typeof(self) weakSelf = self;
			[self request:@{@"@type" : @"getSupergroup",
							@"supergroup_id" : supergroupId}
			   completion:^(NSDictionary *group){
				TGClient *me = weakSelf;
				if (!me || !group[@"id"])
					return;
				me.forumSupergroups[group[@"id"]] = @([group[@"is_forum"] boolValue]);
				NSMutableDictionary *row = me.chatsById[chatId];
				row[@"isForum"] = @([group[@"is_forum"] boolValue]);
				[me rebuildChats];
			}];
		}
	}
	if (chat[@"positions"]){
		info[@"order"] = @(TGMainListOrder(chat[@"positions"]));
		info[@"archiveOrder"] = @(TGArchiveOrder(chat[@"positions"]));
		info[@"isPinned"] = @(TGPinnedInMain(chat[@"positions"]));
	}
	if (chat[@"notification_settings"])
		info[@"isMuted"] = @([chat[@"notification_settings"][@"mute_for"] integerValue] > 0);

	// Small avatar, if the chat has one. Downloaded lazily; the id is enough
	// for the UI to ask for it later.
	NSNumber *photoFile = chat[@"photo"][@"small"][@"id"];
	if (photoFile)
		info[@"photoFileId"] = photoFile;

	NSString *draft = chat[@"draft_message"][@"input_message_text"][@"text"][@"text"];
	info[@"draft"] = draft ?: @"";

	NSDictionary *last = chat[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = [self previewForLastMessage:last inChat:info];
		info[@"date"] = last[@"date"] ?: @(0);
	}

	[self rebuildChats];
}

/// In a group the list shows who spoke last - "Назар: text" - which is the
/// only way to tell a busy group apart at a glance. The speaker and the bare
/// text are also kept apart ("lastAuthor", "previewText") so the list can set
/// the name in its own colour; your own messages are "You" anywhere but in
/// Saved Messages, where everything is yours.
- (NSString *)previewForLastMessage:(NSDictionary *)last inChat:(NSMutableDictionary *)info {
	NSString *text = TGMessagePreview(last);
	info[@"previewText"] = text ?: @"";
	info[@"lastId"] = last[@"id"] ?: @(0);
	info[@"lastOutgoing"] = @([last[@"is_outgoing"] boolValue]);
	[info removeObjectForKey:@"lastAuthor"];
	if ([last[@"is_outgoing"] boolValue]){
		if (![info[@"isSaved"] boolValue])
			info[@"lastAuthor"] = @"You";
		return text;
	}
	if (![info[@"isGroup"] boolValue])
		return text;

	int64_t sender = [last[@"sender_id"][@"user_id"] longLongValue];
	NSString *who = [self nameForUserId:sender];
	if (!who.length){
		// not known yet - fetch, then rebuild so the row fills in
		__weak typeof(self) weakSelf = self;
		[self ensureUserName:sender completion:^{ [weakSelf rebuildChats]; }];
		return text;
	}
	info[@"lastAuthor"] = who;
	return [NSString stringWithFormat:@"%@: %@", who, text];
}

- (int64_t)lastReadOutboxForChat:(int64_t)chatId {
	return [self.chatsById[@(chatId)][@"readOutbox"] longLongValue];
}

- (int64_t)lastReadInboxForChat:(int64_t)chatId {
	return [self.chatsById[@(chatId)][@"readInbox"] longLongValue];
}

- (void)applyChatUpdate:(NSDictionary *)update {
	NSNumber *chatId = update[@"chat_id"];
	if (!chatId)
		return;

	NSMutableDictionary *info = self.chatsById[chatId];
	if (!info){
		info = [NSMutableDictionary dictionary];
		info[@"id"] = chatId;
		self.chatsById[chatId] = info;
	}

	if (update[@"title"])
		info[@"title"] = update[@"title"];
	if (update[@"unread_count"])
		info[@"unread"] = update[@"unread_count"];
	if (update[@"last_read_inbox_message_id"])
		info[@"readInbox"] = update[@"last_read_inbox_message_id"];
	if (update[@"last_read_outbox_message_id"]){
		info[@"readOutbox"] = update[@"last_read_outbox_message_id"];
		[[NSNotificationCenter defaultCenter] postNotificationName:TGChatReadOutboxChangedNotification
				object:self userInfo:@{@"chatId": chatId}];
	}

	NSDictionary *last = update[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = [self previewForLastMessage:last inChat:info];
		info[@"date"] = last[@"date"] ?: @(0);
	}

	if (update[@"notification_settings"])
		info[@"isMuted"] = @([update[@"notification_settings"][@"mute_for"] integerValue] > 0);
	if (update[@"positions"]){
		info[@"order"] = @(TGMainListOrder(update[@"positions"]));
		info[@"archiveOrder"] = @(TGArchiveOrder(update[@"positions"]));
		info[@"isPinned"] = @(TGPinnedInMain(update[@"positions"]));
	}
	NSDictionary *position = update[@"position"];
	if ([position isKindOfClass:NSDictionary.class]){
		NSString *listType = position[@"list"][@"@type"];
		if ([listType isEqualToString:@"chatListArchive"]){
			info[@"archiveOrder"] = @(TGArchiveOrder(@[position]));
		} else if ([listType isEqualToString:@"chatListMain"]){
			info[@"order"] = @(TGMainListOrder(@[position]));
			info[@"isPinned"] = @(TGPinnedInMain(@[position]));
			// Main and archive are mutually exclusive: a chat that just got a
			// main position died out of the archive, and the stale
			// archiveOrder would otherwise keep it on the archive strip.
			info[@"archiveOrder"] = @0;
		}
		// A chatListFolder position says nothing about the main list: zero
		// order with a pinned reset here used to unpin the chat wholesale
		// every time its folder reshuffled.
	}

	[self rebuildChats];
}

- (void)rebuildChats {
	NSArray *all = self.chatsById.allValues;

	NSComparator byOrder = ^NSComparisonResult(id a, id b){
		int64_t oa = [a[@"order"] longLongValue];
		int64_t ob = [b[@"order"] longLongValue];
		if (oa == ob) return NSOrderedSame;
		return oa > ob ? NSOrderedAscending : NSOrderedDescending;   // newest first
	};

	// A chat sits in exactly one of the two lists, told apart by which
	// position carries a non-zero order.
	NSMutableArray *main = [NSMutableArray array], *archived = [NSMutableArray array];
	int64_t savedId = [self savedMessagesChatId];
	for (NSDictionary *c in all){
		BOOL isSaved = [c[@"isSaved"] boolValue] || ([c[@"id"] longLongValue] == savedId && savedId != 0);
		BOOL isPinned = [c[@"isPinned"] boolValue];
		BOOL hasDraft = [c[@"draft"] length] > 0;
		BOOL hasMessage = [c[@"text"] length] > 0 || [c[@"date"] longLongValue] > 0;
		// Do not show phantom empty chats (e.g. deleted/transferred groups without history)
		if (!isSaved && !isPinned && !hasDraft && !hasMessage)
			continue;

		if ([c[@"archiveOrder"] longLongValue] > 0)
			[archived addObject:c];
		else if ([c[@"order"] longLongValue] > 0)
			[main addObject:c];
	}

	self.chats = [main sortedArrayUsingComparator:byOrder];
	self.archivedChats = [archived sortedArrayUsingComparator:
			^NSComparisonResult(id a, id b){
		int64_t oa = [a[@"archiveOrder"] longLongValue];
		int64_t ob = [b[@"archiveOrder"] longLongValue];
		if (oa == ob) return NSOrderedSame;
		return oa > ob ? NSOrderedAscending : NSOrderedDescending;
	}];

	if (self.onChatsChanged)
		self.onChatsChanged();
	if (self.onArchiveChanged)
		self.onArchiveChanged();
}

@end
