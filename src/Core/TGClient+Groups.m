//
// TGClient+Groups.m - making a group, who is in it, and the links that let
// people in.
//
// A chat could be left and read and nothing else: there was no request in
// this app that created one, added anyone, or produced a link. This is that
// half. Basic groups and supergroups differ in where their member list lives
// and in almost nothing else a screen cares about, so the calls here take a
// chat id and work out the rest.
//
#import "TGClientInternal.h"

/// A member as a MessageSender, which is the only way setChatMemberStatus and
/// banChatMember will name one.
static NSDictionary *TGMemberSender(int64_t userId) {
	return @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)};
}

/// The rights an administrator gets here. Not every box their client offers:
/// the ones that make sense for a group someone is promoted to run, with
/// promoting others and staying anonymous deliberately off.
static NSDictionary *TGAdminRights(void) {
	return @{
		@"@type"                   : @"chatAdministratorRights",
		@"can_manage_chat"         : @YES,
		@"can_change_info"         : @YES,
		@"can_delete_messages"     : @YES,
		@"can_invite_users"        : @YES,
		@"can_restrict_members"    : @YES,
		@"can_pin_messages"        : @YES,
		@"can_manage_topics"       : @YES,
		@"can_manage_video_chats"  : @YES,
		@"can_post_messages"       : @NO,
		@"can_edit_messages"       : @NO,
		@"can_promote_members"     : @NO,
		@"can_post_stories"        : @NO,
		@"can_edit_stories"        : @NO,
		@"can_delete_stories"      : @NO,
		@"can_manage_direct_messages" : @NO,
		@"can_manage_tags"         : @NO,
		@"can_send_welcome_messages"  : @NO,
		@"is_anonymous"            : @NO,
	};
}

/// A member's status as one short word, for a row that has to say what
/// someone is.
NSString *TGMemberStatusName(NSDictionary *status) {
	NSString *kind = status[@"@type"] ?: @"";
	if ([kind isEqualToString:@"chatMemberStatusCreator"])       return @"owner";
	if ([kind isEqualToString:@"chatMemberStatusAdministrator"]) return @"admin";
	if ([kind isEqualToString:@"chatMemberStatusRestricted"])    return @"restricted";
	if ([kind isEqualToString:@"chatMemberStatusBanned"])        return @"banned";
	if ([kind isEqualToString:@"chatMemberStatusLeft"])          return @"left";
	return @"member";
}

/// Flattens chatInviteLink down to what a row shows and a tap needs.
static NSDictionary *TGFlattenInviteLink(NSDictionary *link) {
	return @{
		@"link"        : link[@"invite_link"] ?: @"",
		@"name"        : link[@"name"] ?: @"",
		@"members"     : link[@"member_count"] ?: @(0),
		@"memberLimit" : link[@"member_limit"] ?: @(0),
		@"primary"     : link[@"is_primary"] ?: @NO,
		@"revoked"     : link[@"is_revoked"] ?: @NO,
		@"requests"    : link[@"pending_join_request_count"] ?: @(0),
	};
}

@implementation TGClient (Groups)

#pragma mark - making one

/// A basic group is what their New Group makes: up to 200 people, no
/// username, and it becomes a supergroup on its own when it needs to. It must
/// be created with at least one other member - TDLib refuses an empty one.
- (void)createGroupNamed:(NSString *)title
			   withUsers:(NSArray *)userIds
			  completion:(void (^)(int64_t chatId, NSArray *failedUserIds))completion {
	if (!title.length || !userIds.count){
		if (completion) completion(0, userIds ?: @[]);
		return;
	}
	[self request:@{
		@"@type"                    : @"createNewBasicGroupChat",
		@"user_ids"                 : userIds,
		@"title"                    : title,
		@"message_auto_delete_time" : @(0),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		// Someone whose privacy settings refuse group invitations is reported
		// rather than silently missing from the new group.
		NSMutableArray *failed = [NSMutableArray array];
		for (NSDictionary *entry in result[@"failed_to_add_members"][@"failed_to_add_members"])
			if (entry[@"user_id"])
				[failed addObject:entry[@"user_id"]];
		completion([result[@"chat_id"] longLongValue], failed);
	}];
}

/// A supergroup or a channel: a username, no member ceiling worth the name,
/// and a history that outlives its members.
- (void)createSupergroupNamed:(NSString *)title
				  description:(NSString *)description
					isChannel:(BOOL)isChannel
				   completion:(void (^)(int64_t chatId))completion {
	if (!title.length){
		if (completion) completion(0);
		return;
	}
	[self request:@{
		@"@type"                    : @"createNewSupergroupChat",
		@"title"                    : title,
		@"is_forum"                 : @NO,
		@"is_channel"               : @(isChannel),
		@"description"              : description ?: @"",
		// A chat that is not tied to a place sends the origin with an empty
		// address; TDLib wants the field whether or not there is a pin.
		@"location"                 : @{
			@"@type"   : @"chatLocation",
			@"location": @{@"@type" : @"location",
						   @"latitude" : @0, @"longitude" : @0,
						   @"horizontal_accuracy" : @0},
			@"address" : @"",
		},
		@"message_auto_delete_time" : @(0),
		@"for_import"               : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

/// Past 200 members, or when a group needs a username or admins with rights,
/// a basic group has to become a supergroup. The chat id changes.
- (void)upgradeGroupToSupergroup:(int64_t)chatId
					  completion:(void (^)(int64_t newChatId))completion {
	[self request:@{@"@type" : @"upgradeBasicGroupChatToSupergroupChat",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"id"] longLongValue]);
	}];
}

#pragma mark - who is in it

/// The basic group's record, which is what a basic-group id resolves to before
/// any chat exists in the local database. `getBasicGroupFullInfo` is the other
/// half the profile reads; this one carries the member count and the status
/// word the debug resolver shows beside the name.
- (void)basicGroupInfo:(int64_t)basicGroupId
			completion:(void (^)(NSDictionary *info))completion {
	if (!basicGroupId){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getBasicGroup", @"basic_group_id" : @(basicGroupId)}
	   completion:^(NSDictionary *group){
		if ([group[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		// getBasicGroup carries no name; the chat record does. Resolving it
		// here means the resolver row can show the group as a name with a
		// member count rather than as an id with a result.
		[self request:@{@"@type" : @"createBasicGroupChat",
						@"basic_group_id" : @(basicGroupId),
						@"force" : @NO}
		   completion:^(NSDictionary *chat){
			[self mergeChat:chat];
			if (completion)
				completion(@{
					@"id"         : group[@"id"] ?: @(basicGroupId),
					@"title"      : chat[@"title"] ?: @"Basic Group",
					@"members"    : group[@"member_count"] ?: @(0),
					@"status"     : TGMemberStatusName(group[@"status"]),
					@"active"     : group[@"is_active"] ?: @NO,
					@"upgradedTo" : group[@"upgraded_to_supergroup_id"] ?: @(0),
				});
		}];
	}];
}

/// `forwardLimit` is how much of the history the new member sees in a basic
/// group; a supergroup ignores it and shows everything.
- (void)addUser:(int64_t)userId
		 toChat:(int64_t)chatId
	 completion:(void (^)(BOOL ok, NSArray *failedUserIds))completion {
	[self request:@{
		@"@type"         : @"addChatMember",
		@"chat_id"       : @(chatId),
		@"user_id"       : @(userId),
		@"forward_limit" : @(100),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSMutableArray *failed = [NSMutableArray array];
		for (NSDictionary *entry in result[@"failed_to_add_members"])
			if (entry[@"user_id"])
				[failed addObject:entry[@"user_id"]];
		BOOL errored = [result[@"@type"] isEqualToString:@"error"];
		completion(!errored && failed.count == 0, failed);
	}];
}

/// The picker's batch, in one request instead of one request per tick.
/// Same failed-half answer as the single-member call, so one sheet covers
/// everyone the server said no to.
- (void)addUsers:(NSArray *)userIds
		  toChat:(int64_t)chatId
	  completion:(void (^)(BOOL ok, NSArray *refused))completion {
	if (!userIds.count){
		if (completion) completion(NO, @[]);
		return;
	}
	[self request:@{
		@"@type"         : @"addChatMembers",
		@"chat_id"       : @(chatId),
		@"user_ids"      : userIds,
		@"forward_limit" : @(100),
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSMutableArray *failed = [NSMutableArray array];
		for (NSDictionary *entry in result[@"failed_to_add_members"])
			if (entry[@"user_id"])
				[failed addObject:entry[@"user_id"]];
		BOOL errored = [result[@"@type"] isEqualToString:@"error"];
		completion(!errored && failed.count == 0, failed);
	}];
}

/// One member's own record - status, rights, the renewal date of a
/// restriction. The member list is the aggregate; this is the detail.
- (void)chatMember:(int64_t)userId
			 inChat:(int64_t)chatId
		completion:(void (^)(NSDictionary *member))completion {
	if (!userId){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"     : @"getChatMember",
		@"chat_id"   : @(chatId),
		@"member_id" : TGMemberSender(userId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"error"] ? nil : result);
	}];
}

/// What members of a chat may do, as one of three presets - the full set of
/// fifteen booleans is not a sheet of switches anyone reads on a phone.
/// "All" and "read only" are the two ends, and "text" is the middle TDLib
/// itself keeps: messages and previews, no media.
+ (NSDictionary *)chatPermissionsForPreset:(NSString *)preset {
	BOOL everything, basic;
	if ([preset isEqualToString:@"all"]){
		everything = YES; basic = YES;
	} else if ([preset isEqualToString:@"text"]){
		everything = NO; basic = YES;
	} else {
		everything = NO; basic = NO;
	}
	return @{
		@"@type"                  : @"chatPermissions",
		@"can_send_basic_messages": @(basic),
		@"can_send_audios"        : @(everything),
		@"can_send_documents"     : @(everything),
		@"can_send_photos"        : @(everything),
		@"can_send_videos"        : @(everything),
		@"can_send_video_notes"   : @(everything),
		@"can_send_voice_notes"   : @(everything),
		@"can_send_polls"         : @(everything),
		@"can_send_other_messages": @(everything),
		@"can_add_link_previews"  : @(basic),
		@"can_react_to_messages"  : @(everything),
		// These four are default member rights that reach past posting:
		// renaming the group, pinning, creating topics and editing tags.
		// A message preset never turns them on; setChatPermissionsFromPreset
		// carries whatever the chat already allows instead.
		@"can_edit_tag"           : @NO,
		@"can_change_info"        : @NO,
		@"can_invite_users"       : @(basic),
		@"can_pin_messages"       : @NO,
		@"can_create_topics"      : @NO,
	};
}

- (void)setChatPermissionsFromPreset:(NSString *)preset
							   inChat:(int64_t)chatId
						  completion:(void (^)(BOOL ok))completion {
	NSMutableDictionary *permissions =
			[[TGClient chatPermissionsForPreset:preset] mutableCopy];
	// The four admin-like flags are not part of what a posting preset means.
	// Keep what the chat already has rather than silently changing them.
	NSDictionary *current = self.chatsById[@(chatId)][@"permissions"];
	if ([current isKindOfClass:NSDictionary.class]){
		for (NSString *key in @[@"can_change_info", @"can_pin_messages",
								@"can_create_topics", @"can_edit_tag"]){
			if ([current[key] isKindOfClass:NSNumber.class])
				permissions[key] = current[key];
		}
	}
	[self request:@{
		@"@type"       : @"setChatPermissions",
		@"chat_id"     : @(chatId),
		@"permissions" : permissions,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// Handing the whole chat over. TDLib demands the password once two-factor
/// authentication is on, which is the request's third field; the confirm
/// sheet says why this one cannot be undone.
- (void)transferOwnershipOfChat:(int64_t)chatId
						 toUser:(int64_t)userId
					   password:(NSString *)password
					 completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"      : @"transferChatOwnership",
		@"chat_id"    : @(chatId),
		@"user_id"    : @(userId),
		@"password"   : password ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}
/// Search inside a chat's members. An empty query is the whole list, which is
/// how a member screen fills itself. Entries carry "id", "name" and "status".
- (void)searchMembersInChat:(int64_t)chatId
					  query:(NSString *)query
				 completion:(void (^)(NSArray *members))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"   : @"searchChatMembers",
		@"chat_id" : @(chatId),
		@"query"   : query ?: @"",
		@"limit"   : @(100),
		@"filter"  : @{@"@type" : @"chatMembersFilterMembers"},
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *member in result[@"members"]){
			int64_t userId = [member[@"member_id"][@"user_id"] longLongValue];
			if (!userId)
				continue;
			[out addObject:@{
				@"id"     : @(userId),
				@"name"   : [me nameForUserId:userId] ?: @"",
				@"status" : TGMemberStatusName(member[@"status"]),
			}];
		}
		if (completion)
			completion(out);
	}];
}

/// Only the administrators, which is a different request from the members and
/// the only one that says who the owner is. Entries carry "id", "name",
/// "owner" and "editable" - the last says whether this account may change
/// that administrator at all.
- (void)administratorsOfChat:(int64_t)chatId
				  completion:(void (^)(NSArray *admins))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatAdministrators", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *admin in result[@"administrators"]){
			int64_t userId = [admin[@"user_id"] longLongValue];
			if (!userId)
				continue;
			[out addObject:@{
				@"id"       : @(userId),
				@"name"     : [me nameForUserId:userId] ?: @"",
				@"owner"    : admin[@"is_owner"] ?: @NO,
				@"editable" : admin[@"can_be_edited"] ?: @NO,
			}];
		}
		if (completion)
			completion(out);
	}];
}

/// Promote to administrator, demote back to a plain member, or restrict.
/// `status` is "administrator", "member" or "left"; anything else is refused
/// rather than guessed at, because the wrong one here removes people.
- (void)setMember:(int64_t)userId
		   inChat:(int64_t)chatId
		   status:(NSString *)status
	   completion:(void (^)(BOOL ok))completion {
	NSDictionary *statusObject = nil;
	if ([status isEqualToString:@"administrator"])
		statusObject = @{@"@type"  : @"chatMemberStatusAdministrator",
						 @"rights" : TGAdminRights(),
						 @"can_be_edited" : @YES};
	else if ([status isEqualToString:@"member"])
		statusObject = @{@"@type" : @"chatMemberStatusMember",
						 @"member_until_date" : @(0)};
	else if ([status isEqualToString:@"left"])
		statusObject = @{@"@type" : @"chatMemberStatusLeft"};

	if (!statusObject){
		if (completion) completion(NO);
		return;
	}

	[self request:@{
		@"@type"     : @"setChatMemberStatus",
		@"chat_id"   : @(chatId),
		@"member_id" : TGMemberSender(userId),
		@"status"    : statusObject,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// Banning is not the same as removing: a banned member cannot come back on
/// an invite link. `revokeMessages` also deletes what they wrote.
- (void)banMember:(int64_t)userId
		   inChat:(int64_t)chatId
   revokeMessages:(BOOL)revokeMessages
	   completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"            : @"banChatMember",
		@"chat_id"          : @(chatId),
		@"member_id"        : TGMemberSender(userId),
		// Zero is forever, which is what banning from a phone means.
		@"banned_until_date": @(0),
		@"revoke_messages"  : @(revokeMessages),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

#pragma mark - what it is called

/// The supergroup id behind a chat id, asked for rather than guessed:
/// toggles below name a supergroup, all the app has is the chat. A basic
/// group has no supergroup; the completion answers 0 and nobody is toggled.
- (void)supergroupIdForChat:(int64_t)chatId
				 completion:(void (^)(int64_t supergroupId))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSString *kind = chat[@"type"][@"@type"];
		NSString *id_ = chat[@"type"][@"supergroup_id"];
		if ([kind isEqualToString:@"chatTypeSupergroup"] && id_){
			if (completion) completion([id_ longLongValue]);
			return;
		}
		// A basic group turns into a supergroup the moment this matters;
		// the row the list cached can name the newer shape for us.
		id row = weakSelf.chatsById[@(chatId)][@"supergroupId"];
		if ([row isKindOfClass:NSNumber.class] && [row longLongValue]){
			if (completion) completion([row longLongValue]);
			return;
		}
		if (completion) completion(0);
	}];
}

/// Signs what members post with their names, the way a channel wall works.
- (void)setChatSignMessages:(int64_t)chatId
						 on:(BOOL)on
				 completion:(void (^)(BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		// toggleSupergroupSignMessages requires both switches. The sender
		// line is a separate setting; read it from the supergroup record so
		// turning signatures on does not turn author profiles off.
		[weakSelf request:@{@"@type" : @"getSupergroup",
							@"supergroup_id" : @(supergroupId)}
			 completion:^(NSDictionary *group){
			if (completion && [group[@"@type"] isEqualToString:@"error"]){
				completion(NO);
				return;
			}
			[weakSelf request:@{
				@"@type"             : @"toggleSupergroupSignMessages",
				@"supergroup_id"     : @(supergroupId),
				@"sign_messages"     : @(on),
				@"show_message_sender" : group[@"show_message_sender"] ?: @NO,
			} completion:^(NSDictionary *result){
				if (completion)
					completion(![result[@"@type"] isEqualToString:@"error"]);
			}];
		}];
	}];
}

/// Members who cannot post otherwise - non-admins of a broadcast-style group
/// - are shown the composer only when this is on; on it is private and their
/// posts land in the admins' chat.
- (void)setChatJoinToSendMessages:(int64_t)chatId
							   on:(BOOL)on
					   completion:(void (^)(BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		[weakSelf request:@{@"@type"           : @"toggleSupergroupJoinToSendMessages",
							@"supergroup_id"   : @(supergroupId),
							@"join_to_send_messages" : @(on)}
			 completion:^(NSDictionary *result){
			if (completion)
				completion(![result[@"@type"] isEqualToString:@"error"]);
		}];
	}];
}

/// What the three toggles above sit on right now, read off the supergroup's
/// full record, so a menu row can say what the flip is about to do.
- (void)supergroupFlagsForChat:(int64_t)chatId
					completion:(void (^)(BOOL signMessages, BOOL joinToSend,
										 BOOL allHistory, BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, NO, NO, NO);
			return;
		}
		// sign_messages and join_to_send_messages live on the supergroup
		// record, not on supergroupFullInfo. The old keys read as NO for
		// every group, so the menu drew both switches off.
		[weakSelf request:@{@"@type" : @"getSupergroup",
							@"supergroup_id" : @(supergroupId)}
			 completion:^(NSDictionary *group){
			if ([group[@"@type"] isEqualToString:@"error"]){
				if (completion) completion(NO, NO, NO, NO);
				return;
			}
			[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
								@"supergroup_id" : @(supergroupId)}
				 completion:^(NSDictionary *full){
				BOOL history = ![full[@"@type"] isEqualToString:@"error"] &&
						[full[@"is_all_history_available"] boolValue];
				if (completion)
					completion([group[@"sign_messages"] boolValue],
							   [group[@"join_to_send_messages"] boolValue],
							   history, YES);
			}];
		}];
	}];
}

/// Whether the history before a member joined is visible to them. Their
/// client exposes this as a switch on a group that already has some.
- (void)setSupergroupAllHistoryAvailable:(int64_t)chatId
									  on:(BOOL)on
							  completion:(void (^)(BOOL ok))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		[weakSelf request:@{
			@"@type"                    : @"toggleSupergroupIsAllHistoryAvailable",
			@"supergroup_id"            : @(supergroupId),
			@"is_all_history_available" : @(on),
		} completion:^(NSDictionary *result){
			if (completion)
				completion(![result[@"@type"] isEqualToString:@"error"]);
		}];
	}];
}

- (void)setChat:(int64_t)chatId
		  title:(NSString *)title
	 completion:(void (^)(BOOL ok))completion {
	if (!title.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setChatTitle", @"chat_id" : @(chatId),
					@"title" : title}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// A description belongs to a supergroup or a channel; a basic group has
/// nowhere to put one and TDLib says so.
- (void)setChat:(int64_t)chatId
	description:(NSString *)description
	 completion:(void (^)(BOOL ok))completion {
	[self request:@{@"@type" : @"setChatDescription", @"chat_id" : @(chatId),
					@"description" : description ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)setChat:(int64_t)chatId
	photoAtPath:(NSString *)path
	 completion:(void (^)(BOOL ok))completion {
	if (!path.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"   : @"setChatPhoto",
		@"chat_id" : @(chatId),
		@"photo"   : @{@"@type" : @"inputChatPhotoStatic",
					   @"photo" : @{@"@type" : @"inputFileLocal",
									@"path"  : path}},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

#pragma mark - letting people in

/// Every link the chat has, the primary one among them. Entries are flattened
/// to "link", "name", "members", "memberLimit", "primary", "revoked" and
/// "requests".
- (void)inviteLinksForChat:(int64_t)chatId
				completion:(void (^)(NSArray *links))completion {
	[self request:@{
		@"@type"              : @"getChatInviteLinks",
		@"chat_id"            : @(chatId),
		@"creator_user_id"    : @([self.me[@"id"] longLongValue]),
		@"is_revoked"         : @NO,
		@"offset_date"        : @(0),
		@"offset_invite_link" : @"",
		@"limit"              : @(50),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *link in result[@"invite_links"])
			if ([link[@"invite_link"] length])
				[out addObject:TGFlattenInviteLink(link)];
		if (completion)
			completion(out);
	}];
}

/// A link of its own, so it can be revoked without taking the chat's primary
/// link down with it. A limit of zero is no limit.
- (void)createInviteLinkForChat:(int64_t)chatId
						   name:(NSString *)name
					memberLimit:(NSInteger)memberLimit
					 completion:(void (^)(NSString *link))completion {
	[self request:@{
		@"@type"                : @"createChatInviteLink",
		@"chat_id"              : @(chatId),
		@"name"                 : name ?: @"",
		@"expiration_date"      : @(0),
		@"member_limit"         : @(MAX((NSInteger)0, memberLimit)),
		@"creates_join_request" : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"invite_link"] length] ? result[@"invite_link"] : nil);
	}];
}

/// The chat's primary link, replaced: the old one stops working at once. This
/// is what their "Revoke Link" on the main link does.
- (void)replacePrimaryInviteLinkForChat:(int64_t)chatId
							 completion:(void (^)(NSString *link))completion {
	[self request:@{@"@type" : @"replacePrimaryChatInviteLink",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"invite_link"] length] ? result[@"invite_link"] : nil);
	}];
}

- (void)revokeInviteLink:(NSString *)link
				  inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok))completion {
	if (!link.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"revokeChatInviteLink", @"chat_id" : @(chatId),
					@"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"@type"] isEqualToString:@"chatInviteLinks"]);
	}];
}

/// What is behind a link before joining it: the name, how many are in, and
/// whether this account is already one of them.
- (void)checkInviteLink:(NSString *)link
			 completion:(void (^)(NSString *title, NSInteger members,
								  BOOL alreadyMember))completion {
	if (!link.length){
		if (completion) completion(nil, 0, NO);
		return;
	}
	[self request:@{@"@type" : @"checkChatInviteLink", @"invite_link" : link}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"chatInviteLinkInfo"]){
			completion(nil, 0, NO);
			return;
		}
		completion(result[@"title"],
				   [result[@"member_count"] integerValue],
				   [result[@"chat_id"] longLongValue] != 0);
	}];
}

/// People waiting at a link that creates join requests. Entries carry "id",
/// "name" and "date".
- (void)joinRequestsForChat:(int64_t)chatId
				 completion:(void (^)(NSArray *requests))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"getChatJoinRequests",
		@"chat_id"     : @(chatId),
		@"invite_link" : @"",
		@"query"       : @"",
		@"limit"       : @(50),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *request in result[@"requests"]){
			int64_t userId = [request[@"user_id"] longLongValue];
			if (!userId)
				continue;
			[out addObject:@{
				@"id"   : @(userId),
				@"name" : [me nameForUserId:userId] ?: @"",
				@"date" : request[@"date"] ?: @(0),
			}];
		}
		if (completion)
			completion(out);
	}];
}

- (void)processJoinRequest:(int64_t)userId
					inChat:(int64_t)chatId
				   approve:(BOOL)approve {
	[self send:@{
		@"@type"   : @"processChatJoinRequest",
		@"chat_id" : @(chatId),
		@"user_id" : @(userId),
		@"approve" : @(approve),
	}];
}

/// A group's sticker shelf is set on the supergroup, not the chat, and this
/// client only ever holds the chat id. A basic group has no supergroup and no
/// shelf, so it answers NO without a request.
- (void)setSupergroupStickerSet:(int64_t)setId
						inChat:(int64_t)chatId
					completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		[weakSelf request:@{@"@type" : @"setSupergroupStickerSet",
							@"supergroup_id" : @(supergroupId),
							@"sticker_set_id" : @(setId)}
			   completion:^(NSDictionary *result){
			BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
			if (!ok)
				NSLog(@"setSupergroupStickerSet: %@", result[@"message"]);
			if (completion) completion(ok);
		}];
	}];
}

- (void)setSupergroupCustomEmojiStickerSet:(int64_t)setId
									inChat:(int64_t)chatId
								completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO);
			return;
		}
		[weakSelf request:@{@"@type" : @"setSupergroupCustomEmojiStickerSet",
							@"supergroup_id" : @(supergroupId),
							@"custom_emoji_sticker_set_id" : @(setId)}
			   completion:^(NSDictionary *result){
			BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
			if (!ok)
				NSLog(@"setSupergroupCustomEmojiStickerSet: %@", result[@"message"]);
			if (completion) completion(ok);
		}];
	}];
}

#pragma mark - aggressive anti-spam

- (void)aggressiveAntiSpamForChat:(int64_t)chatId
					   completion:(void (^)(BOOL, BOOL, NSString *))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion)
				completion(NO, NO, @"Telegram reports anti-spam for supergroups only.");
			return;
		}
		[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
							@"supergroup_id" : @(supergroupId)}
			   completion:^(NSDictionary *full){
			if ([full[@"@type"] isEqualToString:@"error"]){
				NSString *message = full[@"message"];
				if (completion)
					completion(NO, NO, [message isKindOfClass:NSString.class]
							? message : @"Telegram did not return the group record.");
				return;
			}
			if (completion)
				completion([full[@"has_aggressive_anti_spam_enabled"] boolValue],
						   [full[@"can_toggle_aggressive_anti_spam"] boolValue], nil);
		}];
	}];
}

- (void)setChat:(int64_t)chatId
	aggressiveAntiSpam:(BOOL)on
			 completion:(void (^)(BOOL, NSString *))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion)
				completion(NO, @"Telegram reports anti-spam for supergroups only.");
			return;
		}
		[weakSelf request:@{
			@"@type" : @"toggleSupergroupHasAggressiveAntiSpamEnabled",
			@"supergroup_id" : @(supergroupId),
			@"has_aggressive_anti_spam_enabled" : @(on),
		} completion:^(NSDictionary *result){
			BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
			NSString *message = result[@"message"];
			if (completion)
				completion(ok, ok ? nil : ([message isKindOfClass:NSString.class]
						? message : @"Telegram refused that switch."));
		}];
	}];
}

- (void)antiSpamFalsePositiveCandidatesForChat:(int64_t)chatId
									completion:(void (^)(NSArray *, NSString *))completion {
	NSDictionary *filters = @{
		@"@type" : @"chatEventLogFilters",
		@"message_edits" : @NO,
		@"message_deletions" : @YES,
		@"message_pins" : @NO,
		@"member_joins" : @NO,
		@"member_leaves" : @NO,
		@"member_invites" : @NO,
		@"member_promotions" : @NO,
		@"member_restrictions" : @NO,
		@"member_tag_changes" : @NO,
		@"info_changes" : @NO,
		@"setting_changes" : @NO,
		@"invite_link_changes" : @NO,
		@"video_chat_changes" : @NO,
		@"forum_changes" : @NO,
		@"subscription_extensions" : @NO,
	};
	[self request:@{
		@"@type" : @"getChatEventLog",
		@"chat_id" : @(chatId),
		@"query" : @"",
		@"from_event_id" : @(0),
		@"limit" : @(100),
		@"filters" : filters,
		@"user_ids" : @[],
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			NSString *message = result[@"message"];
			if (completion)
				completion(nil, [message isKindOfClass:NSString.class]
						? message : @"Telegram did not return the event log.");
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *event in result[@"events"]){
			if (![event isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *action = event[@"action"];
			if (![action[@"@type"] isEqualToString:@"chatEventMessageDeleted"])
				continue;
			if (![action[@"can_report_anti_spam_false_positive"] boolValue])
				continue;
			NSDictionary *message = action[@"message"];
			NSDictionary *flat = TGFlattenMessage(message);
			NSString *text = flat[@"text"];
			if (![text isKindOfClass:NSString.class] || !text.length)
				text = flat[@"docName"];
			if (![text isKindOfClass:NSString.class] || !text.length)
				text = @"Deleted message";
			[rows addObject:@{
				@"messageId" : message[@"id"] ?: @(0),
				@"date" : event[@"date"] ?: @(0),
				@"text" : text,
				@"sender" : flat[@"senderId"] ?: @(0),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)reportAntiSpamFalsePositiveInChat:(int64_t)chatId
								messageId:(int64_t)messageId
							   completion:(void (^)(BOOL, NSString *))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion)
				completion(NO, @"Telegram reports anti-spam for supergroups only.");
			return;
		}
		[weakSelf request:@{
			@"@type" : @"reportSupergroupAntiSpamFalsePositive",
			@"supergroup_id" : @(supergroupId),
			@"message_id" : @(messageId),
		} completion:^(NSDictionary *result){
			BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
			NSString *message = result[@"message"];
			if (completion)
				completion(ok, ok ? nil : ([message isKindOfClass:NSString.class]
						? message : @"Telegram refused that report."));
		}];
	}];
}

@end

// vim:ft=objc
