//
 // TGClient+SavedMessages.m - the account's own message housekeeping.
//
 // Welcome messages of a chat, the Saved Messages topics, the profile's
 // purge by date and by sender, and the permission to message a user.
 // This tail grew by accretion; every method here is one thing a user
 // taps in a profile or a topic list.
//
#import "TGClientInternal.h"

@implementation TGClient (SavedMessages)
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


#pragma mark - purge, senders and the saved topics

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
