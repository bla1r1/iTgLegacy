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
		@"can_edit_tag"           : @(everything),
		@"can_change_info"        : @(everything),
		@"can_invite_users"       : @(basic),
		@"can_pin_messages"       : @(everything),
		@"can_create_topics"      : @(everything),
	};
}

- (void)setChatPermissionsFromPreset:(NSString *)preset
							   inChat:(int64_t)chatId
						  completion:(void (^)(BOOL ok))completion {
	[self request:@{
		@"@type"       : @"setChatPermissions",
		@"chat_id"     : @(chatId),
		@"permissions" : [TGClient chatPermissionsForPreset:preset],
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

@end

// vim:ft=objc
