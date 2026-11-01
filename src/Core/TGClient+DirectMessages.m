//
// TGClient+DirectMessages.m - the topic list and the seven calls on one topic.
//
// The list request answers only "ok": the rows themselves arrive one update
// at a time, exactly as Saved Messages topics do. The cache here is therefore
// the list, and a screen opened before load answers with what has arrived.
//
#import "TGClient+DirectMessages.h"
#import "TGClientInternal.h"

static NSString *TGDirectMessagesError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

/// A messageSender is a user or a chat; the row only needs which and its id.
static void TGDirectMessagesSender(NSDictionary *sender, NSString **kind,
                                   int64_t *senderId, NSString **name) {
	*kind = @"user";
	*senderId = 0;
	*name = @"";
	if (![sender isKindOfClass:NSDictionary.class])
		return;
	if ([sender[@"@type"] isEqualToString:@"messageSenderChat"]){
		*kind = @"chat";
		*senderId = [sender[@"chat_id"] longLongValue];
		*name = [[TGClient shared] titleForChat:*senderId] ?: @"";
		return;
	}
	*senderId = [sender[@"user_id"] longLongValue];
	*name = [[TGClient shared] nameForUserId:*senderId] ?: @"";
}

static NSDictionary *TGDirectMessagesTopicRow(NSDictionary *topic) {
	if (![topic isKindOfClass:NSDictionary.class])
		return nil;
	NSNumber *topicId = topic[@"id"];
	if (![topicId isKindOfClass:NSNumber.class])
		return nil;
	NSString *kind = @"user";
	int64_t senderId = 0;
	NSString *name = @"";
	TGDirectMessagesSender(topic[@"sender_id"], &kind, &senderId, &name);
	NSDictionary *last = nil;
	if ([topic[@"last_message"] isKindOfClass:NSDictionary.class])
		last = TGFlattenMessage(topic[@"last_message"]);
	return @{
		@"topicId"        : topicId,
		@"chatId"         : topic[@"chat_id"] ?: @(0),
		@"senderKind"     : kind,
		@"senderId"       : @(senderId),
		@"senderName"     : name,
		@"order"          : topic[@"order"] ?: @(0),
		@"canSendUnpaid"  : @([topic[@"can_send_unpaid_messages"] boolValue]),
		@"isMarkedUnread" : @([topic[@"is_marked_as_unread"] boolValue]),
		@"unread"         : topic[@"unread_count"] ?: @(0),
		@"unreadReactions": topic[@"unread_reaction_count"] ?: @(0),
		@"lastReadInbox"  : topic[@"last_read_inbox_message_id"] ?: @(0),
		@"lastReadOutbox" : topic[@"last_read_outbox_message_id"] ?: @(0),
		@"lastMessage"    : last ?: (id)[NSNull null],
		@"draftText"      : topic[@"draft_message"][@"input_message_text"][@"text"]
				?: @"",
	};
}

@implementation TGClient (DirectMessages)

- (NSArray *)directMessagesChatTopicsForChat:(int64_t)chatId {
	NSDictionary *byChat = self.directMessagesTopicsByChat[@(chatId)];
	if (![byChat isKindOfClass:NSDictionary.class])
		return @[];
	NSArray *rows = [byChat.allValues
			sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,
														   NSDictionary *b){
		long long left = [a[@"order"] longLongValue];
		long long right = [b[@"order"] longLongValue];
		if (left == right)
			return NSOrderedSame;
		return left > right ? NSOrderedAscending : NSOrderedDescending;
	}];
	return rows;
}

- (void)applyDirectMessagesChatTopic:(NSDictionary *)topic {
	NSDictionary *row = TGDirectMessagesTopicRow(topic);
	if (!row)
		return;
	int64_t chatId = [row[@"chatId"] longLongValue];
	int64_t topicId = [row[@"topicId"] longLongValue];
	if (!chatId || !topicId)
		return;
	NSMutableDictionary *byChat = [self.directMessagesTopicsByChat mutableCopy];
	if (!byChat)
		byChat = [NSMutableDictionary dictionary];
	NSMutableDictionary *topics = [byChat[@(chatId)] mutableCopy];
	if (!topics)
		topics = [NSMutableDictionary dictionary];
	topics[@(topicId)] = row;
	byChat[@(chatId)] = topics;
	self.directMessagesTopicsByChat = byChat;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGDirectMessagesTopicsChangedNotification
						  object:self
						userInfo:@{@"chatId" : @(chatId)}];
}

- (void)loadDirectMessagesChatTopicsInChat:(int64_t)chatId
                                     limit:(NSInteger)limit
                                completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"loadDirectMessagesChatTopics",
		@"chat_id" : @(chatId),
		@"limit" : @(limit),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		// A 404 is how TDLib says the list has no more rows; it is not a
		// refused request and must not be shown as a failure.
		if (error && [result[@"code"] integerValue] == 404)
			error = nil;
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)directMessagesChatTopic:(int64_t)topicId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"getDirectMessagesChatTopic",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		NSDictionary *row = error ? nil : TGDirectMessagesTopicRow(result);
		if (!error && row)
			[self applyDirectMessagesChatTopic:result];
		if (completion)
			completion(row, error);
	}];
}

- (void)directMessagesChatTopicHistory:(int64_t)topicId
                                inChat:(int64_t)chatId
                         fromMessageId:(int64_t)fromMessageId
                                offset:(NSInteger)offset
                                 limit:(NSInteger)limit
                            completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{
		@"@type" : @"getDirectMessagesChatTopicHistory",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
		@"from_message_id" : @(fromMessageId),
		@"offset" : @(offset),
		@"limit" : @(limit),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		if (error){
			if (completion)
				completion(@[], error);
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		NSArray *messages = result[@"messages"];
		if ([messages isKindOfClass:NSArray.class])
			for (NSDictionary *message in messages){
				if (![message isKindOfClass:NSDictionary.class])
					continue;
				[rows addObject:TGFlattenMessage(message)];
			}
		// TDLib answers newest first; the chat list draws oldest first.
		NSArray *ordered = [[rows reverseObjectEnumerator] allObjects];
		if (completion)
			completion(ordered, nil);
	}];
}

- (void)directMessagesChatTopicMessageByDate:(int64_t)topicId
                                      inChat:(int64_t)chatId
                                        date:(NSInteger)date
                                  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"getDirectMessagesChatTopicMessageByDate",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
		@"date" : @(date),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		NSDictionary *message = nil;
		if (!error && [result[@"@type"] isEqualToString:@"message"])
			message = TGFlattenMessage(result);
		if (completion)
			completion(message, error);
	}];
}

- (void)deleteDirectMessagesChatTopicHistory:(int64_t)topicId
                                      inChat:(int64_t)chatId
                                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"deleteDirectMessagesChatTopicHistory",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)deleteDirectMessagesChatTopicMessages:(int64_t)topicId
                                       inChat:(int64_t)chatId
                                     minDate:(NSInteger)minDate
                                     maxDate:(NSInteger)maxDate
                                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"deleteDirectMessagesChatTopicMessagesByDate",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
		@"min_date" : @(minDate),
		@"max_date" : @(maxDate),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)setDirectMessagesChatTopic:(int64_t)topicId
                            inChat:(int64_t)chatId
                  markedAsUnread:(BOOL)markedAsUnread
                        completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setDirectMessagesChatTopicIsMarkedAsUnread",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
		@"is_marked_as_unread" : @(markedAsUnread),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		if (!error){
			// The update carries the whole row, but waiting for it would
			// leave the menu tick on the old value. Patch the cached row.
			NSDictionary *row = self.directMessagesTopicsByChat[@(chatId)][@(topicId)];
			if (row){
				NSMutableDictionary *patched = [row mutableCopy];
				patched[@"isMarkedUnread"] = @(markedAsUnread);
				NSMutableDictionary *byChat =
						[self.directMessagesTopicsByChat mutableCopy];
				NSMutableDictionary *topics = [byChat[@(chatId)] mutableCopy];
				topics[@(topicId)] = patched;
				byChat[@(chatId)] = topics;
				self.directMessagesTopicsByChat = byChat;
				[[NSNotificationCenter defaultCenter]
						postNotificationName:TGDirectMessagesTopicsChangedNotification
									  object:self
									userInfo:@{@"chatId" : @(chatId)}];
			}
		}
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)readAllDirectMessagesChatTopicReactions:(int64_t)topicId
                                         inChat:(int64_t)chatId
                                     completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"readAllDirectMessagesChatTopicReactions",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

- (void)unpinAllDirectMessagesChatTopicMessages:(int64_t)topicId
                                         inChat:(int64_t)chatId
                                     completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"unpinAllDirectMessagesChatTopicMessages",
		@"chat_id" : @(chatId),
		@"topic_id" : @(topicId),
	} completion:^(NSDictionary *result){
		NSString *error = TGDirectMessagesError(result);
		if (completion)
			completion(error == nil, error);
	}];
}

@end
