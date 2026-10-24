#import "TGClientInternal.h"

/// TDLib names the three scopes; the app names them shortly.
static NSString *TGScopeType(NSString *scope) {
	if ([scope isEqualToString:@"groups"])   return @"notificationSettingsScopeGroupChats";
	if ([scope isEqualToString:@"channels"]) return @"notificationSettingsScopeChannelChats";
	return @"notificationSettingsScopePrivateChats";
}

/// Flatten one TDLib story down to what a profile row needs.
static NSDictionary *TGFlattenStory(NSDictionary *story) {
	NSDictionary *content = story[@"content"];
	NSString *kind = content[@"@type"];

	// A story is a photo or a video; a video's poster frame is its thumbnail,
	// which is the only frame this device is going to show in a list anyway.
	NSNumber *fileId = nil;
	if ([kind isEqualToString:@"storyContentPhoto"]){
		NSArray *sizes = content[@"photo"][@"sizes"];
		fileId = [sizes lastObject][@"photo"][@"id"] ?: [sizes firstObject][@"photo"][@"id"];
	} else if ([kind isEqualToString:@"storyContentVideo"]){
		fileId = content[@"video"][@"thumbnail"][@"file"][@"id"];
	}

	// The video itself, not just its poster frame - without this a video
	// story could only ever be shown as a still. The smaller alternative is
	// preferred where the server offers one; this is a 512MB phone.
	NSNumber *videoId = nil;
	NSNumber *videoDuration = nil;
	if ([kind isEqualToString:@"storyContentVideo"]){
		NSDictionary *video = [content[@"alternative_video"] isKindOfClass:NSDictionary.class]
				? content[@"alternative_video"] : content[@"video"];
		videoId = video[@"video"][@"id"];
		videoDuration = video[@"duration"];
	}

	NSMutableDictionary *out = [@{
		@"storyId"  : story[@"id"] ?: @(0),
		@"date"     : story[@"date"] ?: @(0),
		@"caption"  : story[@"caption"][@"text"] ?: @"",
		@"isVideo"  : @([kind isEqualToString:@"storyContentVideo"]),
		@"viewers"  : story[@"interaction_info"][@"view_count"] ?: @(0),
	} mutableCopy];
	if (fileId)
		out[@"photoId"] = fileId;
	if (videoId)
		out[@"videoId"] = videoId;
	if (videoDuration)
		out[@"duration"] = videoDuration;
	return out;
}

static NSArray *TGPacksFrom(NSDictionary *target) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *pack in target[@"language_packs"]){
		if (![pack[@"id"] length])
			continue;
		[out addObject:@{@"id"   : pack[@"id"],
						 @"name" : pack[@"native_name"] ?: pack[@"name"] ?: pack[@"id"]}];
	}
	return out;
}

@implementation TGClient (Account)

#pragma mark - contacts

- (void)contactsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getContacts"} completion:^(NSDictionary *result){
		NSArray *ids = result[@"user_ids"];
		if (![ids isKindOfClass:NSArray.class]){
			if (completion) completion(@[]);
			return;
		}

		// Fetch each user; finish when the last one answers.
		NSMutableArray *users = [NSMutableArray array];
		__block NSUInteger left = ids.count;
		if (!left){
			if (completion) completion(@[]);
			return;
		}
		for (NSNumber *uid in ids){
			[weakSelf request:@{@"@type" : @"getUser", @"user_id" : uid}
				   completion:^(NSDictionary *u){
				if ([u[@"@type"] isEqualToString:@"user"]){
					// The photo id travels with the row, so the list can show a
					// face rather than a letter for everyone who has one.
					[weakSelf cacheProfilePhoto:u];
					[users addObject:@{
						@"id"          : u[@"id"] ?: @(0),
						@"first_name"  : u[@"first_name"] ?: @"",
						@"last_name"   : u[@"last_name"] ?: @"",
						@"phone"       : u[@"phone_number"] ?: @"",
						@"username"    : ([u[@"usernames"][@"active_usernames"] isKindOfClass:[NSArray class]] && [u[@"usernames"][@"active_usernames"] count] > 0) ? u[@"usernames"][@"active_usernames"][0] : (u[@"username"] ?: @""),
						@"photoFileId" : u[@"profile_photo"][@"small"][@"id"] ?: [NSNull null],
					}];
				}
				if (--left == 0 && completion)
					completion(users);
			}];
		}
	}];
}

- (void)privateChatWithUser:(int64_t)userId completion:(void (^)(int64_t))completion {
	[self request:@{
		@"@type"   : @"createPrivateChat",
		@"user_id" : @(userId),
		@"force"   : @NO,
	} completion:^(NSDictionary *chat){
		if (completion)
			completion([chat[@"id"] longLongValue]);
	}];
}

- (void)userForPhone:(NSString *)phone completion:(void (^)(NSDictionary *))completion {
	if (!phone.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"        : @"searchUserByPhoneNumber",
		@"phone_number" : phone,
	} completion:^(NSDictionary *u){
		if (![u[@"@type"] isEqualToString:@"user"]){
			if (completion) completion(nil);
			return;
		}
		if (completion) completion(@{
			@"id"         : u[@"id"] ?: @(0),
			@"first_name" : u[@"first_name"] ?: @"",
			@"last_name"  : u[@"last_name"] ?: @"",
			@"phone"      : u[@"phone_number"] ?: @"",
			@"username"   : u[@"usernames"][@"active_usernames"][0] ?: @"",
		});
	}];
}

#pragma mark - people

- (void)setUser:(int64_t)userId blocked:(BOOL)blocked {
	[self send:@{
		@"@type"      : @"setMessageSenderBlockList",
		@"sender_id"  : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
		// A null block list is how TDLib spells "not blocked".
		@"block_list" : blocked ? @{@"@type" : @"blockListMain"} : [NSNull null],
	}];
}

- (void)isUserBlocked:(int64_t)userId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *full){
		if (completion)
			completion([full[@"block_list"] isKindOfClass:NSDictionary.class]);
	}];
}

- (void)giftsForUser:(int64_t)userId completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"    : @"getReceivedGifts",
		@"owner_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
		@"offset"   : @"",
		@"limit"    : @(20),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *entry in result[@"gifts"]){
			NSDictionary *gift = entry[@"gift"][@"gift"] ?: entry[@"gift"];
			[out addObject:@{
				@"title"     : gift[@"title"] ?: @"Gift",
				@"starCount" : gift[@"star_count"] ?: @0,
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)premiumStateWithCompletion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getPremiumState"} completion:^(NSDictionary *state){
		NSDictionary *me = self.me;
		if (![me[@"is_premium"] boolValue]){
			if (completion) completion(nil);
			return;
		}
		// The state carries what is active; a date is the useful part of it.
		NSNumber *until = state[@"state"][@"expiration_date"] ?: state[@"expiration_date"];
		if (!until.doubleValue){
			if (completion) completion(@"Active");
			return;
		}
		static NSDateFormatter *fmt = nil;
		if (!fmt){
			fmt = [[NSDateFormatter alloc] init];
			[fmt setDateFormat:@"d MMM yyyy"];
		}
		if (completion)
			completion([NSString stringWithFormat:@"Until %@", [fmt stringFromDate:
					[NSDate dateWithTimeIntervalSince1970:until.doubleValue]]]);
	}];
}

#pragma mark - account

- (void)sessionsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getActiveSessions"} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *session in result[@"sessions"]){
			[out addObject:@{
				@"id"         : session[@"id"] ?: @0,
				@"name"       : session[@"application_name"] ?: @"",
				@"platform"   : [NSString stringWithFormat:@"%@ %@",
						session[@"platform"] ?: @"", session[@"system_version"] ?: @""],
				@"ip"         : session[@"ip_address"] ?: session[@"ip"] ?: @"",
				@"isCurrent"  : session[@"is_current"] ?: @NO,
				@"lastActive" : session[@"last_active_date"] ?: @0,
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)terminateSession:(long long)sessionId {
	[self send:@{@"@type" : @"terminateSession", @"session_id" : @(sessionId)}];
}

- (void)setName:(NSString *)firstName last:(NSString *)lastName {
	[self send:@{
		@"@type"      : @"setName",
		@"first_name" : firstName ?: @"",
		@"last_name"  : lastName ?: @"",
	}];
}

- (void)setBio:(NSString *)bio {
	[self send:@{@"@type" : @"setBio", @"bio" : bio ?: @""}];
}

- (void)setUsername:(NSString *)username completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"setUsername", @"username" : username ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// Small profile photo of a user, so a group message can show who wrote it.
- (void)cacheProfilePhoto:(NSDictionary *)user {
	NSNumber *fileId = user[@"profile_photo"][@"small"][@"id"];
	if (user[@"id"] && fileId)
		self.userPhotosById[user[@"id"]] = fileId;
}

- (int64_t)savedMessagesChatId {
	return [self.me[@"id"] longLongValue];
}

- (void)statusForUser:(int64_t)userId completion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		NSDictionary *status = user[@"status"];
		NSString *kind = status[@"@type"];
		NSString *text = nil;

		if ([kind isEqualToString:@"userStatusOnline"]){
			text = @"online";
		} else if ([kind isEqualToString:@"userStatusRecently"]){
			text = @"last seen recently";
		} else if ([kind isEqualToString:@"userStatusLastWeek"]){
			text = @"last seen within a week";
		} else if ([kind isEqualToString:@"userStatusLastMonth"]){
			text = @"last seen within a month";
		} else if ([kind isEqualToString:@"userStatusOffline"]){
			NSTimeInterval was = [status[@"was_online"] doubleValue];
			static NSDateFormatter *fmt = nil;
			if (!fmt){
				fmt = [[NSDateFormatter alloc] init];
				[fmt setDateFormat:@"HH:mm"];
			}
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:was];
			BOOL today = [[NSCalendar currentCalendar]
					components:NSDayCalendarUnit fromDate:date].day ==
						 [[NSCalendar currentCalendar]
					components:NSDayCalendarUnit fromDate:[NSDate date]].day;
			text = today
				? [NSString stringWithFormat:@"last seen at %@", [fmt stringFromDate:date]]
				: @"last seen a long time ago";
		} else {
			// userStatusEmpty is what TDLib sends for someone who has turned
			// their last-seen off, and for a user it will not talk about. Every
			// client shows the same phrase rather than an empty subtitle.
			text = @"last seen recently";
		}
		if (completion) completion(text);
	}];
}

- (NSNumber *)photoFileIdForUserId:(int64_t)userId {
	return self.userPhotosById[@(userId)];
}

- (void)userProfile:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *full){
		NSDictionary *birth = full[@"birthdate"];
		NSString *birthday = @"";
		if ([birth[@"day"] integerValue] > 0){
			static NSArray *months = nil;
			if (!months) months = @[@"", @"January", @"February", @"March", @"April",
					@"May", @"June", @"July", @"August", @"September", @"October",
					@"November", @"December"];
			NSInteger month = [birth[@"month"] integerValue];
			birthday = [NSString stringWithFormat:@"%@ %@",
					(month > 0 && month < 13) ? months[month] : @"", birth[@"day"]];
		}
		if (completion) completion(@{
			@"bio"          : full[@"bio"][@"text"] ?: @"",
			@"commonGroups" : full[@"group_in_common_count"] ?: @0,
			@"birthday"     : birthday,
			// A user who has calls turned off should not be offered one.
			@"canCall"      : full[@"can_be_called"] ?: @NO,
			@"canVideoCall" : full[@"supports_video_calls"] ?: @NO,
		});
	}];
}

#pragma mark - account settings

- (void)notificationsMutedForScope:(NSString *)scope
                        completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"getScopeNotificationSettings",
		@"scope" : @{@"@type" : TGScopeType(scope)},
	} completion:^(NSDictionary *settings){
		// There is no flag: a very large mute_for is how muting is expressed.
		if (completion) completion([settings[@"mute_for"] integerValue] > 0);
	}];
}

/// setScopeNotificationSettings replaces the whole record, so writing one field
/// means reading the rest back first - otherwise muting a scope silently reset
/// its preview setting, and turning previews off unmuted it.
- (void)updateScope:(NSString *)scope
			 change:(NSDictionary *(^)(NSDictionary *current))change
{
	[self request:@{
		@"@type" : @"getScopeNotificationSettings",
		@"scope" : @{@"@type" : TGScopeType(scope)},
	} completion:^(NSDictionary *current){
		NSMutableDictionary *next = [@{
			@"@type"        : @"scopeNotificationSettings",
			@"mute_for"     : current[@"mute_for"] ?: @(0),
			@"sound_id"     : current[@"sound_id"] ?: @(0),
			@"show_preview" : current[@"show_preview"] ?: @YES,
		} mutableCopy];
		[next addEntriesFromDictionary:change(current)];
		[self send:@{
			@"@type" : @"setScopeNotificationSettings",
			@"scope" : @{@"@type" : TGScopeType(scope)},
			@"notification_settings" : next,
		}];
	}];
}

- (void)setScope:(NSString *)scope muted:(BOOL)muted {
	[self updateScope:scope change:^NSDictionary *(NSDictionary *current){
		return @{@"mute_for" : @(muted ? 365 * 24 * 3600 : 0)};
	}];
}

- (void)notificationPreviewForScope:(NSString *)scope
						 completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"getScopeNotificationSettings",
		@"scope" : @{@"@type" : TGScopeType(scope)},
	} completion:^(NSDictionary *settings){
		if (completion) completion([settings[@"show_preview"] boolValue]);
	}];
}

- (void)setScope:(NSString *)scope showPreview:(BOOL)show {
	[self updateScope:scope change:^NSDictionary *(NSDictionary *current){
		return @{@"show_preview" : @(show)};
	}];
}

- (void)resetAllNotificationSettings {
	[self send:@{@"@type" : @"resetAllNotificationSettings"}];
}

#pragma mark - options

- (void)optionValue:(NSString *)name completion:(void (^)(id))completion {
	[self request:@{@"@type" : @"getOption", @"name" : name}
	   completion:^(NSDictionary *option){
		if (completion) completion(option[@"value"]);
	}];
}

- (void)setOption:(NSString *)name boolValue:(BOOL)value {
	[self send:@{
		@"@type" : @"setOption",
		@"name"  : name,
		@"value" : @{@"@type" : @"optionValueBoolean", @"value" : @(value)},
	}];
}

/// Fetches profile stories (pinned profile stories falling back to active 24h stories).
- (void)storiesForChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;

	void (^flattenAll)(NSArray *) = ^(NSArray *stories){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *story in stories)
			if ([story isKindOfClass:NSDictionary.class])
				[out addObject:TGFlattenStory(story)];
		if (completion) completion(out);
	};

	[self request:@{
		@"@type"         : @"getChatPostedToChatPageStories",
		@"chat_id"       : @(chatId),
		@"from_story_id" : @(0),
		@"limit"         : @(20),
	} completion:^(NSDictionary *posted){
		NSArray *stories = posted[@"stories"];
		if ([stories count]){
			flattenAll(stories);
			return;
		}

		// Nothing kept on the page: the active list needs each story fetched
		// by id, because it only carries the ids.
		[weakSelf request:@{@"@type" : @"getChatActiveStories", @"chat_id" : @(chatId)}
			   completion:^(NSDictionary *active){
			NSArray *infos = active[@"stories"];
			if (![infos count]){
				if (completion) completion(@[]);
				return;
			}

			NSMutableArray *collected = [NSMutableArray array];
			__block NSUInteger outstanding = infos.count;
			for (NSDictionary *info in infos){
				[weakSelf request:@{
					@"@type"                : @"getStory",
					@"story_sender_chat_id" : @(chatId),
					@"story_id"             : info[@"story_id"] ?: @(0),
					@"only_local"           : @NO,
				} completion:^(NSDictionary *story){
					if ([story[@"@type"] isEqualToString:@"story"])
						[collected addObject:TGFlattenStory(story)];
					if (--outstanding == 0 && completion)
						completion(collected);
				}];
			}
		}];
	}];
}

/// Their Edit Profile has a birthday row; TDLib keeps it as three numbers and
/// a zero day means it is not set. Year is optional, which is why it is only
/// written when it is there.
- (void)setBirthdayDay:(NSInteger)day month:(NSInteger)month year:(NSInteger)year {
	if (day <= 0){
		[self send:@{@"@type" : @"setBirthdate", @"birthdate" : [NSNull null]}];
		return;
	}
	NSMutableDictionary *birthdate = [@{
		@"@type" : @"birthdate",
		@"day"   : @(day),
		@"month" : @(month),
	} mutableCopy];
	if (year > 0)
		birthdate[@"year"] = @(year);
	[self send:@{@"@type" : @"setBirthdate", @"birthdate" : birthdate}];
}

/// The signed-in account's own birthday as TDLib stores it: "day", "month",
/// "year" (0 when unset).
- (void)myBirthdayWithCompletion:(void (^)(NSInteger, NSInteger, NSInteger))completion {
	[self request:@{@"@type"   : @"getUserFullInfo",
					@"user_id" : self.me[@"id"] ?: @0}
	   completion:^(NSDictionary *full){
		NSDictionary *birth = full[@"birthdate"];
		if (completion)
			completion([birth[@"day"] integerValue], [birth[@"month"] integerValue],
					   [birth[@"year"] integerValue]);
	}];
}

/// Their profile page leads with this, and there was no way to set a picture
/// from the app at all - only to look at one already set from another client.
- (void)setProfilePhotoAtPath:(NSString *)path completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"setProfilePhoto",
		@"photo" : @{@"@type" : @"inputChatPhotoStatic",
					 @"photo" : @{@"@type" : @"inputFileLocal", @"path" : path ?: @""}},
	} completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setProfilePhoto: %@", result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)clearImportedContacts {
	[self send:@{@"@type" : @"clearImportedContacts"}];
}

/// Their Recent Calls page is a search across every chat for call messages -
/// there is no separate call log in TDLib.
- (void)recentCallsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"         : @"searchCallMessages",
		@"offset"        : @"",
		@"limit"         : @(50),
		@"only_missed"   : @NO,
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSDictionary *content = m[@"content"];
			if (![content[@"@type"] isEqualToString:@"messageCall"])
				continue;
			int64_t chatId = [m[@"chat_id"] longLongValue];
			NSString *reason = content[@"discard_reason"][@"@type"];
			[out addObject:@{
				@"userId"   : @(chatId),
				@"name"     : [weakSelf nameForUserId:chatId] ?: @"Unknown",
				@"outgoing" : @([m[@"is_outgoing"] boolValue]),
				@"missed"   : @([reason isEqualToString:@"callDiscardReasonMissed"] ||
								[reason isEqualToString:@"callDiscardReasonDeclined"]),
				@"date"     : m[@"date"] ?: @(0),
				@"duration" : content[@"duration"] ?: @(0),
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)privacyRule:(NSString *)setting completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"   : @"getUserPrivacySettingRules",
		@"setting" : @{@"@type" : [@"userPrivacySetting" stringByAppendingString:setting]},
	} completion:^(NSDictionary *rules){
		// The rules are a list, most specific first. The three answers a client
		// offers are the shapes of the first rule; anything more elaborate,
		// set from another client, reads as the closest of the three.
		NSString *first = [rules[@"rules"] firstObject][@"@type"];
		NSString *value = @"nobody";
		if ([first isEqualToString:@"userPrivacySettingRuleAllowAll"])
			value = @"everybody";
		else if ([first isEqualToString:@"userPrivacySettingRuleAllowContacts"])
			value = @"contacts";
		if (completion) completion(value);
	}];
}

- (void)setPrivacyRule:(NSString *)setting to:(NSString *)value {
	NSString *rule = @"userPrivacySettingRuleRestrictAll";
	if ([value isEqualToString:@"everybody"])
		rule = @"userPrivacySettingRuleAllowAll";
	else if ([value isEqualToString:@"contacts"])
		rule = @"userPrivacySettingRuleAllowContacts";

	[self send:@{
		@"@type"   : @"setUserPrivacySettingRules",
		@"setting" : @{@"@type" : [@"userPrivacySetting" stringByAppendingString:setting]},
		@"rules"   : @{@"@type" : @"userPrivacySettingRules",
					   @"rules" : @[@{@"@type" : rule}]},
	}];
}

- (void)blockedUsersWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"getBlockedMessageSenders",
		@"block_list"  : @{@"@type" : @"blockListMain"},
		@"offset"      : @(0),
		@"limit"       : @(100),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sender in result[@"senders"]){
			NSNumber *userId = sender[@"user_id"];
			if (!userId)
				continue;
			[out addObject:@{
				@"id"   : userId,
				@"name" : [weakSelf nameForUserId:userId.longLongValue] ?: @"",
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)accountTtlWithCompletion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"getAccountTtl"} completion:^(NSDictionary *ttl){
		if (completion) completion([ttl[@"days"] integerValue]);
	}];
}

- (void)setAccountTtlDays:(NSInteger)days {
	[self send:@{
		@"@type" : @"setAccountTtl",
		@"ttl"   : @{@"@type" : @"accountTtl", @"days" : @(days)},
	}];
}

- (void)languagesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	__weak typeof(self) weakSelf = self;

	void (^answer)(NSArray *) = ^(NSArray *packs){
		[weakSelf request:@{@"@type" : @"getOption",
							@"name"  : @"language_pack_id"}
			   completion:^(NSDictionary *option){
			NSString *current = option[@"value"] ?: @"en";
			NSArray *list = packs;
			// With no list at all, say what is in use rather than nothing:
			// an empty screen looks broken and tells you less than one row.
			if (!list.count)
				list = @[@{@"id" : current, @"name" : current}];
			if (completion) completion(list, current);
		}];
	};

	// The full list comes from Telegram's servers, and they answer 404 to an
	// api_id with no language packs of its own - which is this app's case. The
	// local query still knows about the packs already on the device.
	[self request:@{@"@type" : @"getLocalizationTargetInfo",
					@"only_local" : @NO}
	   completion:^(NSDictionary *target){
		NSArray *packs = TGPacksFrom(target);
		if (packs.count){
			answer(packs);
			return;
		}
		[weakSelf request:@{@"@type" : @"getLocalizationTargetInfo",
							@"only_local" : @YES}
			   completion:^(NSDictionary *local){
			answer(TGPacksFrom(local));
		}];
	}];
}

- (void)setLanguage:(NSString *)packId {
	// The strings themselves are the official client's; this app is written in
	// English throughout. Setting it still matters: TDLib uses it for the text
	// it generates, and other clients on the account follow it.
	[self send:@{
		@"@type" : @"setOption",
		@"name"  : @"language_pack_id",
		@"value" : @{@"@type" : @"optionValueString", @"value" : packId ?: @"en"},
	}];
}

- (void)userInfo:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *u){
		if (completion) completion([u[@"@type"] isEqualToString:@"user"] ? u : nil);
	}];
}

- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
         completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : @"",
		@"from_message_id" : @(0),
		@"offset"          : @(0),
		@"limit"           : @(60),
		@"filter"          : @{@"@type" : filter},
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSDictionary *flat = TGFlattenMessage(m);
			if (flat) [out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

- (NSString *)nameForUserId:(int64_t)userId {
	return self.usersById[@(userId)];
}

- (void)ensureUserName:(int64_t)userId completion:(void (^)(void))completion {
	if (userId == 0 || self.usersById[@(userId)]){
		if (completion) completion();
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *u){
		TGClient *me = weakSelf;
		if (me && [u[@"@type"] isEqualToString:@"user"]){
			NSString *name = [[NSString stringWithFormat:@"%@ %@",
					u[@"first_name"] ?: @"", u[@"last_name"] ?: @""]
					stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (!name.length)
				name = u[@"usernames"][@"active_usernames"][0] ?: @"";
			if (name.length)
				me.usersById[@(userId)] = name;
			[me cacheProfilePhoto:u];
		}
		if (completion) completion();
	}];
}

@end
