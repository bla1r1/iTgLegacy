//
// TGClient+ChatTools.m - Tier 2's chat surface: folders' shared half, invite
// links, per-chat settings, discovery, statistics, event logs and positions.
//
// The shapes here are deliberately flat. Every screen in this family is a list
// of rows, so the flatteners below turn TDLib's nested objects into the two or
// three strings a row can show before the screen ever sees them.
//
#import "TGClientInternal.h"
#include <math.h>

#pragma mark - flatteners

/// One chat id as the row shape the rest of the app already reads.
static NSDictionary *TGChatRowForId(TGClient *client, NSNumber *chatId) {
	if (![chatId isKindOfClass:NSNumber.class])
		return nil;
	NSDictionary *known = client.chatsById[chatId];
	if (known)
		return known;
	// A chat id and a user id are different namespaces; a user name looked
	// up here could belong to a different account. The title arrives with
	// the chat TDLib has not sent yet, so the row says so.
	return @{@"id" : chatId, @"title" : @"Chat"};
}

/// A list of chat ids as rows, dropping the ids that are not numbers.
static NSArray *TGChatRowsForIds(TGClient *client, NSArray *ids) {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSNumber *chatId in ids ?: @[]){
		NSDictionary *row = TGChatRowForId(client, chatId);
		if (row)
			[rows addObject:row];
	}
	return rows;
}

/// The words a statistic row can carry. TDLib sends doubles; the growth is
/// shown only when it is worth saying, because "+0.0%" on every line is noise.
static NSString *TGStatValue(NSDictionary *value, NSString *suffix) {
	if (![value isKindOfClass:NSDictionary.class])
		return @"-";
	double now = [value[@"value"] doubleValue];
	double growth = [value[@"growth_rate_percentage"] doubleValue];
	NSString *base = [NSString stringWithFormat:@"%ld%@", (long)llround(now),
					  suffix ?: @""];
	if (fabs(growth) < 0.05)
		return base;
	return [NSString stringWithFormat:@"%@ (%+.1f%%)", base, growth];
}

/// One service action in words. The event id and actor are added by the
/// caller; this is only the sentence, and an unknown kind falls back to its
/// own type name rather than disappearing.
static NSString *TGChatEventText(NSDictionary *action) {
	NSString *kind = action[@"@type"] ?: @"";
	if ([kind isEqualToString:@"chatEventMessageEdited"])     return @"edited a message";
	if ([kind isEqualToString:@"chatEventMessageDeleted"])    return @"deleted a message";
	if ([kind isEqualToString:@"chatEventMessagePinned"])     return @"pinned a message";
	if ([kind isEqualToString:@"chatEventMessageUnpinned"])   return @"unpinned a message";
	if ([kind isEqualToString:@"chatEventMemberJoined"])      return @"joined the chat";
	if ([kind isEqualToString:@"chatEventMemberLeft"])        return @"left the chat";
	if ([kind isEqualToString:@"chatEventMemberInvited"])     return @"invited a member";
	if ([kind isEqualToString:@"chatEventMemberPromoted"])    return @"changed an administrator";
	if ([kind isEqualToString:@"chatEventMemberRestricted"])  return @"restricted a member";
	if ([kind isEqualToString:@"chatEventMemberTagChanged"])  return @"changed a member tag";
	if ([kind isEqualToString:@"chatEventTitleChanged"])      return @"changed the title";
	if ([kind isEqualToString:@"chatEventDescriptionChanged"]) return @"changed the description";
	if ([kind isEqualToString:@"chatEventPhotoChanged"])      return @"changed the photo";
	if ([kind isEqualToString:@"chatEventLocationChanged"])   return @"changed the location";
	if ([kind isEqualToString:@"chatEventSlowModeDelayChanged"]) return @"changed slow mode";
	if ([kind isEqualToString:@"chatEventPermissionsChanged"]) return @"changed permissions";
	if ([kind isEqualToString:@"chatEventSettingChanged"])    return @"changed a setting";
	if ([kind isEqualToString:@"chatEventInviteLinkEdited"])  return @"edited an invite link";
	if ([kind isEqualToString:@"chatEventInviteLinkRevoked"]) return @"revoked an invite link";
	if ([kind isEqualToString:@"chatEventInviteLinkDeleted"]) return @"deleted an invite link";
	if ([kind isEqualToString:@"chatEventIsAllHistoryAvailableToggled"]) return @"changed history visibility";
	if ([kind isEqualToString:@"chatEventForumTopicCreated"]) return @"created a topic";
	if ([kind isEqualToString:@"chatEventForumTopicEdited"])  return @"edited a topic";
	if ([kind isEqualToString:@"chatEventForumTopicDeleted"]) return @"deleted a topic";
	if ([kind isEqualToString:@"chatEventForumTopicPinned"])  return @"pinned a topic";
	if ([kind isEqualToString:@"chatEventVideoChatCreated"])  return @"started a video chat";
	if ([kind isEqualToString:@"chatEventVideoChatEnded"])    return @"ended a video chat";
	return TGPhraseFromTypeName(kind);
}

static NSDictionary *TGEventFilterAll(void) {
	return @{
		@"@type" : @"chatEventLogFilters",
		@"message_edits" : @YES, @"message_deletions" : @YES,
		@"message_pins" : @YES, @"member_joins" : @YES,
		@"member_leaves" : @YES, @"member_invites" : @YES,
		@"member_promotions" : @YES, @"member_restrictions" : @YES,
		@"member_tag_changes" : @YES, @"info_changes" : @YES,
		@"setting_changes" : @YES, @"invite_link_changes" : @YES,
		@"video_chat_changes" : @YES, @"forum_changes" : @YES,
		@"subscription_extensions" : @YES,
	};
}

static NSDictionary *TGFilterFromName(NSString *name) {
	NSString *type = @"searchMessagesFilterEmpty";
	if ([name isEqualToString:@"photo"])       type = @"searchMessagesFilterPhoto";
	else if ([name isEqualToString:@"video"])  type = @"searchMessagesFilterVideo";
	else if ([name isEqualToString:@"file"])   type = @"searchMessagesFilterDocument";
	else if ([name isEqualToString:@"link"])   type = @"searchMessagesFilterUrl";
	else if ([name isEqualToString:@"audio"])  type = @"searchMessagesFilterAudio";
	else if ([name isEqualToString:@"voice"])  type = @"searchMessagesFilterVoiceNote";
	return @{@"@type" : type};
}

@implementation TGClient (ChatTools)

#pragma mark - folders

- (void)chatCountForFolder:(NSDictionary *)folder
				completion:(void (^)(NSInteger count))completion {
	if (![folder isKindOfClass:NSDictionary.class]){
		if (completion) completion(0);
		return;
	}
	NSMutableDictionary *copy = [folder mutableCopy];
	copy[@"@type"] = @"chatFolder";
	[self request:@{@"@type" : @"getChatFolderChatCount", @"folder" : copy}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"count"] integerValue]);
	}];
}

- (void)chatsToLeaveForFolder:(NSInteger)folderId
				   completion:(void (^)(NSArray *chatIds))completion {
	[self request:@{@"@type" : @"getChatFolderChatsToLeave",
					@"chat_folder_id" : @(folderId)}
	   completion:^(NSDictionary *result){
		NSArray *ids = [result[@"chat_ids"] isKindOfClass:NSArray.class]
				? result[@"chat_ids"] : @[];
		if (completion)
			completion(ids);
	}];
}

/// getChatFolderDefaultIconName is one of the few requests TDLib answers
/// without a round trip. The execute path needs a client; when the host test
/// has none the request path still gives the same answer.
- (void)defaultIconNameForFolder:(NSDictionary *)folder
					  completion:(void (^)(NSString *name))completion {
	if (![folder isKindOfClass:NSDictionary.class]){
		if (completion) completion(@"Setup");
		return;
	}
	NSMutableDictionary *copy = [folder mutableCopy];
	copy[@"@type"] = @"chatFolder";
	NSDictionary *sync = [self executeSynchronously:
			@{@"@type" : @"getChatFolderDefaultIconName", @"folder" : copy}];
	if ([sync[@"@type"] isEqualToString:@"chatFolderIcon"]){
		if (completion)
			completion(sync[@"name"] ?: @"Setup");
		return;
	}
	[self request:@{@"@type" : @"getChatFolderDefaultIconName", @"folder" : copy}
	   completion:^(NSDictionary *result){
		NSString *name = [result[@"@type"] isEqualToString:@"chatFolderIcon"]
				? result[@"name"] : nil;
		if (completion)
			completion(name.length ? name : @"Setup");
	}];
}

- (void)inviteLinksForFolder:(NSInteger)folderId
				  completion:(void (^)(NSArray *links))completion {
	[self request:@{@"@type" : @"getChatFolderInviteLinks",
					@"chat_folder_id" : @(folderId)}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *link in result[@"invite_links"]){
			if (![link isKindOfClass:NSDictionary.class])
				continue;
			[out addObject:@{
				@"link"    : link[@"invite_link"] ?: @"",
				@"name"    : link[@"name"] ?: @"",
				@"chatIds" : link[@"chat_ids"] ?: @[],
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)chatsForFolderInviteLink:(NSInteger)folderId
					  completion:(void (^)(NSArray *chatIds))completion {
	[self request:@{@"@type" : @"getChatsForChatFolderInviteLink",
					@"chat_folder_id" : @(folderId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"chat_ids"] isKindOfClass:NSArray.class]
					? result[@"chat_ids"] : @[]);
	}];
}

- (void)createInviteLinkForFolder:(NSInteger)folderId
							 name:(NSString *)name
						  chatIds:(NSArray *)chatIds
					   completion:(void (^)(NSString *link))completion {
	[self request:@{
		@"@type" : @"createChatFolderInviteLink",
		@"chat_folder_id" : @(folderId),
		@"name" : name ?: @"",
		@"chat_ids" : chatIds ?: @[],
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"chatFolderInviteLink"]
					? (result[@"invite_link"] ?: @"") : @"");
	}];
}

- (void)editInviteLinkForFolder:(NSInteger)folderId
						   link:(NSString *)link
						   name:(NSString *)name
						chatIds:(NSArray *)chatIds
					 completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type" : @"editChatFolderInviteLink",
		@"chat_folder_id" : @(folderId),
		@"invite_link" : link,
		@"name" : name ?: @"",
		@"chat_ids" : chatIds ?: @[],
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"chatFolderInviteLink"]);
	}];
}

- (void)deleteInviteLinkForFolder:(NSInteger)folderId
							 link:(NSString *)link
					   completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"deleteChatFolderInviteLink",
					@"chat_folder_id" : @(folderId),
					@"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)checkFolderInviteLink:(NSString *)link
				   completion:(void (^)(NSDictionary *folder))completion {
	if (!link.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"checkChatFolderInviteLink",
					@"invite_link" : link}
	   completion:^(NSDictionary *result){
		NSDictionary *info = result[@"chat_folder_info"];
		if (![result[@"@type"] isEqualToString:@"chatFolderInviteLinkInfo"] ||
			![info isKindOfClass:NSDictionary.class]){
			if (completion) completion(nil);
			return;
		}
		NSDictionary *out = @{
			@"id"      : info[@"id"] ?: @(0),
			@"name"    : TGPlainTitle(info[@"name"]) ?: @"Shared folder",
			@"added"   : result[@"added_chat_ids"] ?: @[],
			@"missing" : result[@"missing_chat_ids"] ?: @[],
		};
		if (completion)
			completion(out);
	}];
}

- (void)addFolderByInviteLink:(NSString *)link
					  chatIds:(NSArray *)chatIds
				   completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"addChatFolderByInviteLink",
					@"invite_link" : link,
					@"chat_ids" : chatIds ?: @[]}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)newChatsForFolder:(NSInteger)folderId
			   completion:(void (^)(NSArray *chatIds))completion {
	[self request:@{@"@type" : @"getChatFolderNewChats",
					@"chat_folder_id" : @(folderId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"chat_ids"] isKindOfClass:NSArray.class]
					? result[@"chat_ids"] : @[]);
	}];
}

- (void)processNewChats:(NSArray *)chatIds forFolder:(NSInteger)folderId
			 completion:(void (^)(BOOL ok))completion {
	if (!chatIds.count){
		if (completion) completion(YES);
		return;
	}
	[self request:@{@"@type" : @"processChatFolderNewChats",
					@"chat_folder_id" : @(folderId),
					@"added_chat_ids" : chatIds}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)chatListsForChat:(int64_t)chatId
			  completion:(void (^)(NSArray *lists))completion {
	[self request:@{@"@type" : @"getChatListsToAddChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		NSArray *lists = [result[@"chat_lists"] isKindOfClass:NSArray.class]
				? result[@"chat_lists"] : @[];
		if (completion)
			completion(lists);
	}];
}

- (void)toggleFolderTags:(BOOL)on {
	[self send:@{@"@type" : @"toggleChatFolderTags", @"are_tags_enabled" : @(on)}];
}

#pragma mark - invite links

- (void)inviteLink:(NSString *)link
			inChat:(int64_t)chatId
		completion:(void (^)(NSDictionary *info))completion {
	if (!link.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getChatInviteLink", @"chat_id" : @(chatId),
					@"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"chatInviteLink"]){
			if (completion) completion(nil);
			return;
		}
		if (completion)
			completion(@{
				@"link"        : result[@"invite_link"] ?: @"",
				@"name"        : result[@"name"] ?: @"",
				@"members"     : result[@"member_count"] ?: @(0),
				@"memberLimit" : result[@"member_limit"] ?: @(0),
				@"expiration"  : result[@"expiration_date"] ?: @(0),
				@"requests"    : result[@"pending_join_request_count"] ?: @(0),
				@"joinRequest" : result[@"creates_join_request"] ?: @NO,
				@"primary"     : result[@"is_primary"] ?: @NO,
				@"revoked"     : result[@"is_revoked"] ?: @NO,
				@"subscription": result[@"subscription_pricing"] ?: [NSNull null],
			});
	}];
}

- (void)inviteLinkCountsForChat:(int64_t)chatId
					 completion:(void (^)(NSArray *counts))completion {
	[self request:@{@"@type" : @"getChatInviteLinkCounts", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		__weak typeof(self) weakSelf = self;
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *count in result[@"invite_link_counts"]){
			if (![count isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *userId = count[@"user_id"] ?: @(0);
			[out addObject:@{
				@"id"      : userId,
				@"name"    : [me nameForUserId:userId.longLongValue] ?: @"Administrator",
				@"active"  : count[@"invite_link_count"] ?: @(0),
				@"revoked" : count[@"revoked_invite_link_count"] ?: @(0),
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)membersOfInviteLink:(NSString *)link
					 inChat:(int64_t)chatId
				 completion:(void (^)(NSArray *members))completion {
	[self request:@{
		@"@type" : @"getChatInviteLinkMembers",
		@"chat_id" : @(chatId),
		@"invite_link" : link ?: @"",
		@"only_with_expired_subscription" : @NO,
		@"offset_member" : [NSNull null],
		@"limit" : @(100),
	} completion:^(NSDictionary *result){
		__weak typeof(self) weakSelf = self;
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *member in result[@"members"]){
			if (![member isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *userId = member[@"user_id"] ?: @(0);
			[out addObject:@{
				@"id"       : userId,
				@"name"     : [me nameForUserId:userId.longLongValue] ?: @"Member",
				@"date"     : member[@"joined_chat_date"] ?: @(0),
				@"approver" : member[@"approver_user_id"] ?: @(0),
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)createSubscriptionInviteLink:(int64_t)chatId
								name:(NSString *)name
							   stars:(NSInteger)stars
							  period:(NSInteger)period
						  completion:(void (^)(NSString *link))completion {
	[self request:@{
		@"@type" : @"createChatSubscriptionInviteLink",
		@"chat_id" : @(chatId),
		@"name" : name ?: @"",
		@"subscription_pricing" : @{
			@"@type" : @"starSubscriptionPricing",
			@"period" : @(period > 0 ? period : 2592000),
			@"star_count" : @(MAX(stars, 1)),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"chatInviteLink"]
					? (result[@"invite_link"] ?: @"") : @"");
	}];
}

- (void)editSubscriptionInviteLink:(NSString *)link
							inChat:(int64_t)chatId
							  name:(NSString *)name
						completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"editChatSubscriptionInviteLink",
					@"chat_id" : @(chatId), @"invite_link" : link,
					@"name" : name ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"chatInviteLink"]);
	}];
}

- (void)editInviteLink:(NSString *)link
				inChat:(int64_t)chatId
				  name:(NSString *)name
			expiration:(NSInteger)expiration
		   memberLimit:(NSInteger)memberLimit
		   joinRequest:(BOOL)joinRequest
			completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type" : @"editChatInviteLink",
		@"chat_id" : @(chatId),
		@"invite_link" : link,
		@"name" : name ?: @"",
		@"expiration_date" : @(expiration),
		// TDLib refuses a member limit on a link that also asks for approval.
		@"member_limit" : @(joinRequest ? 0 : memberLimit),
		@"creates_join_request" : @(joinRequest),
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"chatInviteLink"]);
	}];
}

- (void)deleteRevokedInviteLink:(NSString *)link
						 inChat:(int64_t)chatId
					 completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"deleteRevokedChatInviteLink",
					@"chat_id" : @(chatId), @"invite_link" : link ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)deleteAllRevokedInviteLinks:(int64_t)chatId
							creator:(int64_t)creatorId
						 completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"deleteAllRevokedChatInviteLinks",
					@"chat_id" : @(chatId),
					@"creator_user_id" : @(creatorId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

#pragma mark - join requests and bot seams

- (void)answerJoinRequestQuery:(int64_t)queryId
						approve:(BOOL)approve
					 completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type" : @"answerChatJoinRequestQuery",
		@"query_id" : @(queryId),
		@"result" : @{@"@type" : (approve ? @"chatJoinRequestResultApproved"
										   : @"chatJoinRequestResultDeclined")},
		@"url" : @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)processAllJoinRequests:(int64_t)chatId
						  link:(NSString *)link
					   approve:(BOOL)approve
					completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"processChatJoinRequests",
					@"chat_id" : @(chatId),
					@"invite_link" : link ?: @"",
					@"approve" : @(approve)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)deleteReplyMarkupInChat:(int64_t)chatId messageId:(int64_t)messageId {
	if (!messageId)
		return;
	[self send:@{@"@type" : @"deleteChatReplyMarkup",
				 @"chat_id" : @(chatId), @"message_id" : @(messageId)}];
}

- (void)dismissReplyMarkupInChat:(int64_t)chatId {
	int64_t messageId = [self.chatsById[@(chatId)][@"replyMarkupMessageId"]
			longLongValue];
	[self deleteReplyMarkupInChat:chatId messageId:messageId];
}

#pragma mark - recently found

- (void)searchRecentlyFoundChats:(NSString *)query
					  completion:(void (^)(NSArray *chats))completion {
	[self request:@{
		@"@type" : @"searchRecentlyFoundChats",
		@"query" : query ?: @"",
		@"type_filter" : [NSNull null],
		@"limit" : @(50),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

- (void)forgetRecentlyFoundChat:(int64_t)chatId {
	[self send:@{@"@type" : @"removeRecentlyFoundChat", @"chat_id" : @(chatId)}];
}

- (void)clearRecentlyFoundChats {
	[self send:@{@"@type" : @"clearRecentlyFoundChats"}];
}

#pragma mark - discovery

- (void)similarChatsForChat:(int64_t)chatId
				 completion:(void (^)(NSArray *chats, NSInteger total))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatSimilarChatCount", @"chat_id" : @(chatId),
					@"return_local" : @NO}
	   completion:^(NSDictionary *countAnswer){
		TGClient *me = weakSelf;
		NSInteger total = [countAnswer[@"count"] integerValue];
		[me request:@{@"@type" : @"getChatSimilarChats", @"chat_id" : @(chatId)}
		 completion:^(NSDictionary *result){
			NSArray *rows = TGChatRowsForIds(me, result[@"chat_ids"]);
			if (completion)
				completion(rows, total > 0 ? total : (NSInteger)rows.count);
		}];
	}];
}

- (void)openSimilarChat:(int64_t)openedChatId fromChat:(int64_t)chatId {
	[self send:@{@"@type" : @"openChatSimilarChat",
				 @"chat_id" : @(chatId),
				 @"opened_chat_id" : @(openedChatId)}];
}

- (void)recommendedChatsWithCompletion:(void (^)(NSArray *chats))completion {
	[self request:@{@"@type" : @"getRecommendedChats"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

- (void)suitableDiscussionChatsWithCompletion:(void (^)(NSArray *chats))completion {
	[self request:@{@"@type" : @"getSuitableDiscussionChats"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

- (void)suitablePersonalChatsWithCompletion:(void (^)(NSArray *chats))completion {
	[self request:@{@"@type" : @"getSuitablePersonalChats"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

- (void)setPersonalChat:(int64_t)chatId completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"setPersonalChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)inactiveSupergroupChatsWithCompletion:(void (^)(NSArray *chats))completion {
	[self request:@{@"@type" : @"getInactiveSupergroupChats"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

#pragma mark - public chats and usernames

- (void)createdPublicChatsOfType:(NSString *)type
					  completion:(void (^)(NSArray *chats))completion {
	NSString *kind = [type isEqualToString:@"location"]
			? @"publicChatTypeIsLocationBased" : @"publicChatTypeHasUsername";
	[self request:@{@"@type" : @"getCreatedPublicChats",
					@"type" : @{@"@type" : kind}}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

- (void)checkCreatedPublicChatsLimitForType:(NSString *)type
								 completion:(void (^)(BOOL ok, NSString *reason))completion {
	NSString *kind = [type isEqualToString:@"location"]
			? @"publicChatTypeIsLocationBased" : @"publicChatTypeHasUsername";
	[self request:@{@"@type" : @"checkCreatedPublicChatsLimit",
					@"type" : @{@"@type" : kind}}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion)
				completion(NO, result[@"message"] ?: @"The public-chat limit is reached.");
			return;
		}
		if (completion)
			completion(YES, nil);
	}];
}

- (void)checkUsername:(NSString *)username
			   forChat:(int64_t)chatId
			completion:(void (^)(NSString *result))completion {
	[self request:@{@"@type" : @"checkChatUsername", @"chat_id" : @(chatId),
					@"username" : username ?: @""}
	   completion:^(NSDictionary *result){
		NSString *kind = result[@"@type"] ?: @"";
		NSString *word = @"unknown";
		if ([kind isEqualToString:@"checkChatUsernameResultOk"])
			word = @"ok";
		else if ([kind isEqualToString:@"checkChatUsernameResultUsernameInvalid"])
			word = @"invalid";
		else if ([kind isEqualToString:@"checkChatUsernameResultUsernameOccupied"])
			word = @"occupied";
		else if ([kind isEqualToString:@"checkChatUsernameResultUsernamePurchasable"])
			word = @"purchasable";
		else if ([kind isEqualToString:@"checkChatUsernameResultPublicChatsTooMany"])
			word = @"tooMany";
		else if ([kind isEqualToString:@"checkChatUsernameResultPublicGroupsUnavailable"])
			word = @"unavailable";
		if (completion)
			completion(word);
	}];
}

#pragma mark - account-level chat preferences

- (void)newChatPrivacySettingsWithCompletion:
		(void (^)(NSDictionary *settings))completion {
	[self request:@{@"@type" : @"getNewChatPrivacySettings"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result isKindOfClass:NSDictionary.class] ? result : @{});
	}];
}

- (void)setNewChatPrivacyAllowUnknown:(BOOL)allowUnknown
						   completion:(void (^)(BOOL ok))completion {
	// The paid-message count is part of the same object and setting it to
	// zero would silently turn paid messages off, so read it first.
	__weak typeof(self) weakSelf = self;
	[self newChatPrivacySettingsWithCompletion:^(NSDictionary *current){
		TGClient *me = weakSelf;
		if (!me){
			if (completion) completion(NO);
			return;
		}
		[me request:@{
			@"@type" : @"setNewChatPrivacySettings",
			@"settings" : @{
				@"@type" : @"newChatPrivacySettings",
				@"allow_new_chats_from_unknown_users" : @(allowUnknown),
				@"incoming_paid_message_star_count" :
						current[@"incoming_paid_message_star_count"] ?: @(0),
			},
		} completion:^(NSDictionary *result){
			if (completion)
				completion(![result[@"@type"] isEqualToString:@"error"]);
		}];
	}];
}

- (void)notificationExceptionsWithCompletion:
		(void (^)(NSArray *chats))completion {
	[self request:@{@"@type" : @"getChatNotificationSettingsExceptions",
					@"scope" : [NSNull null],
					@"compare_sound" : @YES}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGChatRowsForIds(self, result[@"chat_ids"]));
	}];
}

#pragma mark - the chat itself

- (void)chatRecordForChat:(int64_t)chatId
			   completion:(void (^)(NSDictionary *chat))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (completion)
			completion([chat[@"@type"] isEqualToString:@"chat"] ? chat : nil);
	}];
}

- (void)groupFullInfoForChat:(int64_t)chatId
				  completion:(void (^)(NSDictionary *info))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSNumber *supergroupId = chat[@"type"][@"supergroup_id"];
		if (!supergroupId){
			if (completion) completion(nil);
			return;
		}
		[self request:@{@"@type" : @"getSupergroupFullInfo",
						@"supergroup_id" : supergroupId}
		   completion:^(NSDictionary *info){
			if (completion)
				completion([info[@"@type"] isEqualToString:@"supergroupFullInfo"]
						? info : nil);
		}];
	}];
}

- (void)addChat:(int64_t)chatId toList:(NSDictionary *)list
	 completion:(void (^)(BOOL ok))completion {
	if (![list isKindOfClass:NSDictionary.class]){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"addChatToList", @"chat_id" : @(chatId),
					@"chat_list" : list}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)ownerAfterLeavingChat:(int64_t)chatId
				   completion:(void (^)(NSDictionary *user))completion {
	[self request:@{@"@type" : @"getChatOwnerAfterLeaving", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"user"]){
			if (completion) completion(nil);
			return;
		}
		NSNumber *userId = result[@"id"] ?: @(0);
		NSString *first = result[@"first_name"] ?: @"";
		NSString *last = result[@"last_name"] ?: @"";
		NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!name.length)
			name = [self nameForUserId:userId.longLongValue] ?: @"Unknown";
		if (completion)
			completion(@{@"id" : userId, @"name" : name});
	}];
}

- (void)chatStatisticsForChat:(int64_t)chatId
				   completion:(void (^)(NSArray *rows, NSString *kind))completion {
	[self request:@{@"@type" : @"getChatStatistics", @"chat_id" : @(chatId),
					@"is_dark" : @NO}
	   completion:^(NSDictionary *result){
		NSMutableArray *rows = [NSMutableArray array];
		NSString *kind = result[@"@type"] ?: @"";
		if ([kind isEqualToString:@"error"]){
			if (completion)
				completion(@[], @"");
			return;
		}
		[rows addObject:@{@"title" : @"Members",
						  @"detail" : TGStatValue(result[@"member_count"], @"")}];
		if ([kind isEqualToString:@"chatStatisticsSupergroup"]){
			[rows addObject:@{@"title" : @"Messages",
							  @"detail" : TGStatValue(result[@"message_count"], @"")}];
			[rows addObject:@{@"title" : @"Viewers",
							  @"detail" : TGStatValue(result[@"viewer_count"], @"")}];
			[rows addObject:@{@"title" : @"Senders",
							  @"detail" : TGStatValue(result[@"sender_count"], @"")}];
			for (NSDictionary *sender in result[@"top_senders"]){
				NSNumber *userId = sender[@"user_id"] ?: @(0);
				[rows addObject:@{
					@"title" : [NSString stringWithFormat:@"Top sender: %@",
							[self nameForUserId:userId.longLongValue] ?: @"?"],
					@"detail" : [NSString stringWithFormat:@"%@ messages",
							sender[@"sent_message_count"] ?: @(0)],
				}];
			}
		} else if ([kind isEqualToString:@"chatStatisticsChannel"]){
			[rows addObject:@{@"title" : @"Mean views",
							  @"detail" : TGStatValue(result[@"mean_message_view_count"], @"")}];
			[rows addObject:@{@"title" : @"Mean shares",
							  @"detail" : TGStatValue(result[@"mean_message_share_count"], @"")}];
			[rows addObject:@{@"title" : @"Mean reactions",
							  @"detail" : TGStatValue(result[@"mean_message_reaction_count"], @"")}];
			[rows addObject:@{@"title" : @"Notifications on",
							  @"detail" : [NSString stringWithFormat:@"%.0f%%",
									[result[@"enabled_notifications_percentage"] doubleValue]]}];
		}
		if (completion)
			completion(rows, kind);
	}];
}

- (void)eventLogForChat:(int64_t)chatId
			 completion:(void (^)(NSArray *events))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type" : @"getChatEventLog",
		@"chat_id" : @(chatId),
		@"query" : @"",
		@"from_event_id" : @(0),
		@"limit" : @(100),
		@"filters" : TGEventFilterAll(),
		@"user_ids" : @[],
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *event in result[@"events"]){
			if (![event isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *sender = event[@"member_id"];
			int64_t userId = [sender[@"user_id"] longLongValue];
			NSString *actor = userId ? ([me nameForUserId:userId] ?: @"Someone")
									 : @"Someone";
			[out addObject:@{
				@"date"   : event[@"date"] ?: @(0),
				@"actor"  : actor,
				@"text"   : TGChatEventText(event[@"action"]),
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)reportChatPhotoInChat:(int64_t)chatId
					   reason:(NSString *)reason
					   detail:(NSString *)detail
				   completion:(void (^)(BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		TGClient *me = weakSelf;
		NSArray *sizes = chat[@"photo"][@"sizes"];
		NSNumber *fileId = [sizes.lastObject[@"photo"][@"id"] isKindOfClass:NSNumber.class]
				? sizes.lastObject[@"photo"][@"id"] : nil;
		if (!fileId || !me){
			if (completion) completion(NO);
			return;
		}
		NSString *kind = [reason isEqualToString:@"violence"] ? @"reportReasonViolence"
				: ([reason isEqualToString:@"pornography"] ? @"reportReasonPornography"
				: ([reason isEqualToString:@"childAbuse"] ? @"reportReasonChildAbuse"
				: ([reason isEqualToString:@"copyright"] ? @"reportReasonCopyright"
				: ([reason isEqualToString:@"fake"] ? @"reportReasonFake"
				: ([reason isEqualToString:@"location"] ? @"reportReasonUnrelatedLocation"
				: ([reason isEqualToString:@"custom"] ? @"reportReasonCustom"
				: @"reportReasonSpam"))))));
		[me request:@{@"@type" : @"reportChatPhoto",
					  @"chat_id" : @(chatId),
					  @"file_id" : fileId,
					  @"reason" : @{@"@type" : kind},
					  @"text" : detail ?: @""}
		 completion:^(NSDictionary *result){
			if (completion)
				completion(![result[@"@type"] isEqualToString:@"error"]);
		}];
	}];
}

- (void)defaultChatPhotoEmojiStickersWithCompletion:
		(void (^)(NSArray *stickers))completion {
	[self request:@{@"@type" : @"getDefaultChatPhotoCustomEmojiStickers"}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sticker in result[@"stickers"]){
			if (![sticker isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *emojiId = sticker[@"full_type"][@"custom_emoji_id"];
			if (!emojiId)
				continue;
			[out addObject:@{
				@"emoji"         : sticker[@"emoji"] ?: @"🙂",
				@"customEmojiId" : emojiId,
				@"fileId"        : sticker[@"sticker"][@"id"] ?: @(0),
				@"setId"         : sticker[@"set_id"] ?: @(0),
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)setEmojiPhotoForChat:(int64_t)chatId
				customEmojiId:(int64_t)customEmojiId
					   colour:(NSInteger)colour
				   completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type" : @"setChatPhoto",
		@"chat_id" : @(chatId),
		@"photo" : @{
			@"@type" : @"inputChatPhotoSticker",
			@"sticker" : @{
				@"@type" : @"chatPhotoSticker",
				@"type" : @{
					@"@type" : @"chatPhotoStickerTypeCustomEmoji",
					@"custom_emoji_id" : @(customEmojiId),
				},
				@"background_fill" : @{
					@"@type" : @"backgroundFillSolid",
					@"color" : @(colour),
				},
			},
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setChatAccentColour:(int64_t)chatId colourId:(NSInteger)colourId {
	[self send:@{@"@type" : @"setChatAccentColor", @"chat_id" : @(chatId),
				 @"accent_color_id" : @(colourId),
				 @"background_custom_emoji_id" : @(0)}];
}

- (void)setChatProfileAccentColour:(int64_t)chatId colourId:(NSInteger)colourId {
	[self send:@{@"@type" : @"setChatProfileAccentColor", @"chat_id" : @(chatId),
				 @"profile_accent_color_id" : @(colourId),
				 @"profile_background_custom_emoji_id" : @(0)}];
}

- (void)setChatTheme:(int64_t)chatId name:(NSString *)name
		  completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type" : @"setChatTheme",
		@"chat_id" : @(chatId),
		@"theme" : name.length
				? @{@"@type" : @"inputChatThemeEmoji", @"name" : name}
				: [NSNull null],
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setChatBackground:(int64_t)chatId
				imagePath:(NSString *)imagePath
				   colour:(NSInteger)colour
			  onlyForSelf:(BOOL)onlyForSelf
			   completion:(void (^)(BOOL ok))completion {
	if (!imagePath.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type" : @"setChatBackground",
		@"chat_id" : @(chatId),
		@"background" : @{
			@"@type" : @"inputBackgroundLocal",
			@"background" : @{@"@type" : @"inputFileLocal", @"path" : imagePath},
		},
		@"type" : @{
			@"@type" : @"backgroundTypeWallpaper",
			@"is_blurred" : @NO,
			@"is_moving" : @NO,
		},
		@"dark_theme_dimming" : @(0),
		// A boosted group applies its background to everyone, so only a
		// private chat may keep one to itself.
		@"only_for_self" : @(onlyForSelf),
	} completion:^(NSDictionary *result){
		(void)colour;
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)deleteChatBackground:(int64_t)chatId restorePrevious:(BOOL)restore {
	[self send:@{@"@type" : @"deleteChatBackground", @"chat_id" : @(chatId),
				 @"restore_previous" : @(restore)}];
}

- (void)setAvailableReactionsForChat:(int64_t)chatId
								mode:(NSString *)mode
						  completion:(void (^)(BOOL ok))completion {
	NSDictionary *reactions = nil;
	if ([mode isEqualToString:@"all"]){
		reactions = @{@"@type" : @"chatAvailableReactionsAll",
					  @"max_reaction_count" : @(11)};
	} else {
		NSArray *emojis = @[@"👍", @"❤️", @"🔥"];
		NSMutableArray *list = [NSMutableArray array];
		for (NSString *emoji in emojis)
			[list addObject:@{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji}];
		reactions = @{@"@type" : @"chatAvailableReactionsSome",
					  @"reactions" : list,
					  @"max_reaction_count" : @(3)};
	}
	[self request:@{@"@type" : @"setChatAvailableReactions",
					@"chat_id" : @(chatId),
					@"available_reactions" : reactions}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setSlowModeDelayForChat:(int64_t)chatId
						seconds:(NSInteger)seconds
					 completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"setChatSlowModeDelay", @"chat_id" : @(chatId),
					@"slow_mode_delay" : @(seconds)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)toggleTranslatableForChat:(int64_t)chatId on:(BOOL)on {
	[self send:@{@"@type" : @"toggleChatIsTranslatable", @"chat_id" : @(chatId),
				 @"is_translatable" : @(on)}];
}

- (void)toggleProtectedContentForChat:(int64_t)chatId
								   on:(BOOL)on
						   completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"toggleChatHasProtectedContent",
					@"chat_id" : @(chatId),
					@"has_protected_content" : @(on)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)toggleDefaultSilentForChat:(int64_t)chatId on:(BOOL)on {
	[self send:@{@"@type" : @"toggleChatDefaultDisableNotification",
				 @"chat_id" : @(chatId),
				 @"default_disable_notification" : @(on)}];
}

- (void)setClientNote:(NSString *)note forChat:(int64_t)chatId
		   completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"setChatClientData", @"chat_id" : @(chatId),
					@"client_data" : note ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setDiscussionGroup:(int64_t)discussionChatId
				   forChat:(int64_t)chatId
				completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"setChatDiscussionGroup",
					@"chat_id" : @(chatId),
					@"discussion_chat_id" : @(discussionChatId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setLocationAddress:(NSString *)address
				   forChat:(int64_t)chatId
				completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type" : @"setChatLocation",
		@"chat_id" : @(chatId),
		@"location" : @{
			@"@type" : @"chatLocation",
			@"location" : @{@"@type" : @"location",
							@"latitude" : @0, @"longitude" : @0,
							@"horizontal_accuracy" : @0},
			@"address" : address ?: @"",
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setMemberTag:(NSString *)tag
			  forUser:(int64_t)userId
			   inChat:(int64_t)chatId
		   completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"setChatMemberTag", @"chat_id" : @(chatId),
					@"user_id" : @(userId), @"tag" : tag ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)processProtectedContentDisableRequestInChat:(int64_t)chatId
										  messageId:(int64_t)messageId
											approve:(BOOL)approve
										 completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"processChatHasProtectedContentDisableRequest",
					@"chat_id" : @(chatId),
					@"request_message_id" : @(messageId),
					@"approve" : @(approve)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

#pragma mark - positions

- (void)sparsePositionsInChat:(int64_t)chatId
					   filter:(NSString *)filter
				   fromMessage:(int64_t)messageId
					completion:(void (^)(NSInteger total, NSArray *positions))completion {
	[self request:@{
		@"@type" : @"getChatSparseMessagePositions",
		@"chat_id" : @(chatId),
		@"filter" : TGFilterFromName(filter),
		@"from_message_id" : @(messageId),
		@"limit" : @(100),
		@"saved_messages_topic_id" : @(0),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *entry in result[@"positions"]){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			[out addObject:@{
				@"position"  : entry[@"position"] ?: @(0),
				@"messageId" : entry[@"message_id"] ?: @(0),
				@"date"      : entry[@"date"] ?: @(0),
			}];
		}
		if (completion)
			completion([result[@"total_count"] integerValue], out);
	}];
}

- (void)messagePosition:(int64_t)messageId
				 inChat:(int64_t)chatId
				 filter:(NSString *)filter
			 completion:(void (^)(NSInteger position, NSInteger total))completion {
	[self request:@{
		@"@type" : @"getChatMessagePosition",
		@"chat_id" : @(chatId),
		@"topic_id" : [NSNull null],
		@"filter" : TGFilterFromName(filter),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"count"] integerValue], 0);
	}];
}

#pragma mark - sessions

- (void)toggleSession:(int64_t)sessionId canAcceptSecretChats:(BOOL)can {
	[self send:@{@"@type" : @"toggleSessionCanAcceptSecretChats",
				 @"session_id" : @(sessionId),
				 @"can_accept_secret_chats" : @(can)}];
}

#pragma mark - compatibility resolvers

- (void)chatForBasicGroup:(int64_t)basicGroupId
			   completion:(void (^)(int64_t chatId))completion {
	[self request:@{@"@type" : @"createBasicGroupChat",
					@"basic_group_id" : @(basicGroupId),
					@"force" : @NO}
	   completion:^(NSDictionary *result){
		// The resolver's row also shows the group's name. Keeping the chat
		// record is what puts that title in chatsById for the row to read.
		[self mergeChat:result];
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

- (void)chatForSupergroup:(int64_t)supergroupId
			   completion:(void (^)(int64_t chatId))completion {
	[self request:@{@"@type" : @"createSupergroupChat",
					@"supergroup_id" : @(supergroupId),
					@"force" : @NO}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

- (void)chatForSecretChat:(int32_t)secretChatId
			   completion:(void (^)(int64_t chatId))completion {
	[self request:@{@"@type" : @"createSecretChat",
					@"secret_chat_id" : @(secretChatId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

@end
