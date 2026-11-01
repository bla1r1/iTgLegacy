//
// TGClient+Usernames.m - account and supergroup usernames, the group profile
// switches, and the two default administrator-rights presets.
//
// Every request here names its failure. A username can be taken, a group can
// refuse a forum conversion, and default rights are bot-only: the screen needs
// Telegram's sentence rather than a boolean that says only "no".
//
#import "TGClient+Usernames.h"
#import "TGClientInternal.h"

/// The one string a profile tab is called by in a row, and the TDLib object
/// behind it. TDLib sends main_profile_tab as an object; the screens deal in
/// words so a choice list has something to show.
static NSString *TGProfileTabName(NSDictionary *tab) {
	if (![tab isKindOfClass:NSDictionary.class])
		return @"posts";
	NSString *type = tab[@"@type"];
	if (![type hasPrefix:@"profileTab"])
		return @"posts";
	NSString *suffix = [type substringFromIndex:@"profileTab".length];
	if (!suffix.length)
		return @"posts";
	NSString *first = [[suffix substringToIndex:1] lowercaseString];
	return [first stringByAppendingString:[suffix substringFromIndex:1]];
}

static NSDictionary *TGProfileTabObject(NSString *name) {
	static NSArray *known = nil;
	if (!known)
		known = @[@"posts", @"media", @"files", @"links", @"music", @"voice", @"gifs"];
	NSString *use = [name isKindOfClass:NSString.class] ? name : @"posts";
	if (![known containsObject:use])
		use = @"posts";
	NSString *suffix = [[use substringToIndex:1] uppercaseString];
	suffix = [suffix stringByAppendingString:[use substringFromIndex:1]];
	return @{@"@type" : [@"profileTab" stringByAppendingString:suffix]};
}

static NSString *TGRequestError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

/// Every rights boolean TDLib expects. A missing one is not a default; it is
/// a malformed object that Telegram rejects.
static NSDictionary *TGRights(BOOL manage, BOOL info, BOOL post, BOOL edit,
							  BOOL deleteMessages, BOOL invite, BOOL restrictMembers,
							  BOOL pin, BOOL topics, BOOL promote, BOOL video,
							  BOOL postStories, BOOL editStories, BOOL deleteStories,
							  BOOL directMessages, BOOL tags, BOOL welcome,
							  BOOL anonymous) {
	return @{
		@"@type"                       : @"chatAdministratorRights",
		@"can_manage_chat"             : @(manage),
		@"can_change_info"             : @(info),
		@"can_post_messages"           : @(post),
		@"can_edit_messages"           : @(edit),
		@"can_delete_messages"         : @(deleteMessages),
		@"can_invite_users"            : @(invite),
		@"can_restrict_members"        : @(restrictMembers),
		@"can_pin_messages"            : @(pin),
		@"can_manage_topics"           : @(topics),
		@"can_promote_members"         : @(promote),
		@"can_manage_video_chats"      : @(video),
		@"can_post_stories"            : @(postStories),
		@"can_edit_stories"            : @(editStories),
		@"can_delete_stories"          : @(deleteStories),
		@"can_manage_direct_messages"  : @(directMessages),
		@"can_manage_tags"             : @(tags),
		@"can_send_welcome_messages"   : @(welcome),
		@"is_anonymous"                : @(anonymous),
	};
}

@implementation TGClient (Usernames)

#pragma mark - the account

- (void)accountUsernamesWithCompletion:(void (^)(NSDictionary *usernames))completion {
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *me){
		if ([me[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		NSDictionary *usernames = me[@"usernames"];
		if (![usernames isKindOfClass:NSDictionary.class]){
			if (completion) completion(nil);
			return;
		}
		if (completion)
			completion(usernames);
	}];
}

- (void)toggleUsernameIsActive:(NSString *)username
					  isActive:(BOOL)isActive
					completion:(void (^)(BOOL ok, NSString *error))completion {
	if (!username.length){
		if (completion) completion(NO, @"No username was named.");
		return;
	}
	[self request:@{@"@type" : @"toggleUsernameIsActive",
					@"username" : username,
					@"is_active" : @(isActive)}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGRequestError(result) : nil);
	}];
}

- (void)reorderActiveUsernames:(NSArray *)usernames
					completion:(void (^)(BOOL ok, NSString *error))completion {
	if (!usernames.count){
		if (completion) completion(NO, @"There is no active username to order.");
		return;
	}
	[self request:@{@"@type" : @"reorderActiveUsernames", @"usernames" : usernames}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGRequestError(result) : nil);
	}];
}

#pragma mark - a supergroup or channel

- (void)supergroupSettingsForChat:(int64_t)chatId
						completion:(void (^)(NSDictionary *settings))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(nil);
			return;
		}
		TGClient *me = weakSelf;
		[me request:@{@"@type" : @"getSupergroup", @"supergroup_id" : @(supergroupId)}
		 completion:^(NSDictionary *group){
			if ([group[@"@type"] isEqualToString:@"error"]){
				if (completion) completion(nil);
				return;
			}
			// The mode switches are on the record; hidden members and the
			// main profile tab are only in full info. One screen draws both,
			// so one method reads both rather than making the screen pair them.
			[me request:@{@"@type" : @"getSupergroupFullInfo",
						  @"supergroup_id" : @(supergroupId)}
			 completion:^(NSDictionary *full){
				BOOL fullOK = ![full[@"@type"] isEqualToString:@"error"];
				NSDictionary *usernames = [group[@"usernames"] isKindOfClass:NSDictionary.class]
						? group[@"usernames"] : @{};
				NSArray *active = [usernames[@"active_usernames"] isKindOfClass:NSArray.class]
						? usernames[@"active_usernames"] : @[];
				NSArray *disabled = [usernames[@"disabled_usernames"] isKindOfClass:NSArray.class]
						? usernames[@"disabled_usernames"] : @[];
				if (completion)
					completion(@{
						@"supergroupId"   : @(supergroupId),
						@"active"         : active,
						@"disabled"       : disabled,
						@"editable"       : usernames[@"editable_username"] ?: @"",
						@"canSetUsername" : fullOK ? (full[@"can_set_username"] ?: @NO) : @NO,
						@"canHideMembers" : fullOK ? (full[@"can_hide_members"] ?: @NO) : @NO,
						@"guardBotUserId" : fullOK ? (full[@"guard_bot_user_id"] ?: @0) : @0,
						@"isChannel"      : group[@"is_channel"] ?: @NO,
						@"isForum"        : group[@"is_forum"] ?: @NO,
						@"hasForumTabs"   : group[@"has_forum_tabs"] ?: @NO,
						@"joinByRequest"  : group[@"join_by_request"] ?: @NO,
						@"isBroadcast"    : group[@"is_broadcast_group"] ?: @NO,
						@"hiddenMembers"  : fullOK ? (full[@"has_hidden_members"] ?: @NO) : @NO,
						@"automaticTranslation" : group[@"has_automatic_translation"] ?: @NO,
						@"mainTab"        : TGProfileTabName(fullOK ? full[@"main_profile_tab"] : nil),
					});
			}];
		}];
	}];
}

- (void)setSupergroupUsername:(NSString *)username
					   inChat:(int64_t)chatId
				   completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"setSupergroupUsername",
							@"supergroup_id" : @(supergroupId),
							@"username" : username ?: @""}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)toggleSupergroupUsernameIsActive:(NSString *)username
								  inChat:(int64_t)chatId
								isActive:(BOOL)isActive
							  completion:(void (^)(BOOL ok, NSString *error))completion {
	if (!username.length){
		if (completion) completion(NO, @"No username was named.");
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"toggleSupergroupUsernameIsActive",
							@"supergroup_id" : @(supergroupId),
							@"username" : username,
							@"is_active" : @(isActive)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)reorderSupergroupActiveUsernames:(NSArray *)usernames
								  inChat:(int64_t)chatId
							  completion:(void (^)(BOOL ok, NSString *error))completion {
	if (!usernames.count){
		if (completion) completion(NO, @"There is no active username to order.");
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"reorderSupergroupActiveUsernames",
							@"supergroup_id" : @(supergroupId),
							@"usernames" : usernames}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)disableAllSupergroupUsernamesInChat:(int64_t)chatId
								 completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"disableAllSupergroupUsernames",
							@"supergroup_id" : @(supergroupId)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)setSupergroupForumInChat:(int64_t)chatId
							  on:(BOOL)on
					  completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"toggleSupergroupIsForum",
							@"supergroup_id" : @(supergroupId),
							@"is_forum" : @(on),
							@"has_forum_tabs" : @(on)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)setSupergroupJoinByRequestInChat:(int64_t)chatId
									 on:(BOOL)on
						   guardBotUserId:(int64_t)guardBotUserId
							 completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		// A guard bot belongs to a bot account. Passing the id the group
		// already has, or 0 when there is none, keeps a guard in place;
		// the switch still applies to links this group already has.
		[weakSelf request:@{@"@type" : @"toggleSupergroupJoinByRequest",
							@"supergroup_id" : @(supergroupId),
							@"join_by_request" : @(on),
							@"guard_bot_user_id" : @(guardBotUserId),
							@"apply_to_invite_links" : @YES}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)setSupergroupHiddenMembersInChat:(int64_t)chatId
									 on:(BOOL)on
							 completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"toggleSupergroupHasHiddenMembers",
							@"supergroup_id" : @(supergroupId),
							@"has_hidden_members" : @(on)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)convertSupergroupToBroadcastInChat:(int64_t)chatId
								completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"toggleSupergroupIsBroadcastGroup",
							@"supergroup_id" : @(supergroupId)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)setSupergroupAutomaticTranslationInChat:(int64_t)chatId
											 on:(BOOL)on
									 completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"toggleSupergroupHasAutomaticTranslation",
							@"supergroup_id" : @(supergroupId),
							@"has_automatic_translation" : @(on)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

- (void)setSupergroupMainProfileTab:(NSString *)tab
							 inChat:(int64_t)chatId
						 completion:(void (^)(BOOL ok, NSString *error))completion {
	__weak typeof(self) weakSelf = self;
	[self supergroupIdForChat:chatId completion:^(int64_t supergroupId){
		if (!supergroupId){
			if (completion) completion(NO, @"This chat is not a supergroup or a channel.");
			return;
		}
		[weakSelf request:@{@"@type" : @"setSupergroupMainProfileTab",
							@"supergroup_id" : @(supergroupId),
							@"main_profile_tab" : TGProfileTabObject(tab)}
			   completion:^(NSDictionary *result){
			BOOL failed = [result[@"@type"] isEqualToString:@"error"];
			if (completion)
				completion(!failed, failed ? TGRequestError(result) : nil);
		}];
	}];
}

#pragma mark - default administrator rights

+ (NSDictionary *)administratorRightsForPreset:(NSString *)preset {
	BOOL full = [preset isEqualToString:@"full"];
	BOOL posting = full || [preset isEqualToString:@"posting"];
	BOOL standard = posting || [preset isEqualToString:@"standard"];
	BOOL readOnly = [preset isEqualToString:@"readonly"];
	if (!standard && !readOnly)
		standard = YES;
	return TGRights(standard, standard, posting, posting, standard, standard,
					standard, standard, standard, full, standard,
					full, full, full, full, full, full, full);
}

- (void)setDefaultGroupAdministratorRightsPreset:(NSString *)preset
									  completion:(void (^)(BOOL ok, NSString *error))completion {
	[self request:@{@"@type" : @"setDefaultGroupAdministratorRights",
					@"default_group_administrator_rights" :
							[TGClient administratorRightsForPreset:preset]}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGRequestError(result) : nil);
	}];
}

- (void)setDefaultChannelAdministratorRightsPreset:(NSString *)preset
										completion:(void (^)(BOOL ok, NSString *error))completion {
	[self request:@{@"@type" : @"setDefaultChannelAdministratorRights",
					@"default_channel_administrator_rights" :
							[TGClient administratorRightsForPreset:preset]}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		if (completion)
			completion(!failed, failed ? TGRequestError(result) : nil);
	}];
}

@end
