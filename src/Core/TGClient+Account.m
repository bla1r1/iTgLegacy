#import "TGClientInternal.h"
#import "TGStatusText.h"

/// Defined with the autosave reads below; the update branch above it only
/// needs the same flattening so both paths produce one row shape.
static NSDictionary *TGFlattenAutosaveScope(NSDictionary *settings);

/// TDLib names the three scopes; the app names them shortly.
static NSString *TGScopeType(NSString *scope) {
	if ([scope isEqualToString:@"groups"])   return @"notificationSettingsScopeGroupChats";
	if ([scope isEqualToString:@"channels"]) return @"notificationSettingsScopeChannelChats";
	return @"notificationSettingsScopePrivateChats";
}

/// Flatten one TDLib story down to what a profile row needs.
/// One gift as the list wants it. A gift wears a sticker: its thumbnail is
/// the still picture the row draws (a WebP sticker doubles as its own
/// thumbnail, per the sticker panel's rule), and the emoji beside it is the
/// glyph every layout falls back to. "title" does not exist in the schema -
/// the old flatten invented it, and every gift rendered identically.
static NSDictionary *TGFlattenGift(NSDictionary *entry) {
	NSDictionary *gift = entry[@"gift"][@"gift"] ?: entry[@"gift"];
	NSDictionary *sticker = gift[@"sticker"];
	NSString *format = sticker[@"format"][@"@type"] ?: @"";
	BOOL webp = [format isEqualToString:@"stickerFormatWebp"];

	NSDictionary *thumbnail = sticker[@"thumbnail"];
	NSString *thumbFormat = thumbnail[@"format"][@"@type"] ?: @"";
	NSNumber *thumbId = thumbnail[@"file"][@"id"];
	BOOL thumbIsPicture = [thumbFormat isEqualToString:@"thumbnailFormatWebp"] ||
						  [thumbFormat isEqualToString:@"thumbnailFormatJpeg"] ||
						  [thumbFormat isEqualToString:@"thumbnailFormatPng"];
	if (!thumbId || !thumbIsPicture)
		thumbId = webp ? sticker[@"sticker"][@"id"] : nil;

	NSString *message = entry[@"message"][@"text"];
	NSMutableDictionary *out = [@{
		@"date"      : entry[@"date"] ?: @(0),
		@"emoji"     : sticker[@"emoji"] ?: @"",
		@"starCount" : gift[@"star_count"] ?: @(0),
		// Who gave it: the tile badge and the viewer's "From" row read here.
		@"senderUserId" : entry[@"sender_id"][@"user_id"] ?: @(0),
	} mutableCopy];
	if (message.length)
		out[@"message"] = message;
	if (thumbId)
		out[@"thumbFileId"] = thumbId;
	return out;
}

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

	// A grid tile draws about 105 pt on edge, so beyond roughly 220 px of
	// width every extra byte only pads a 512 MB phone's download queue (B2:
	// the grid used to ask for the largest render of every story). The
	// smallest size that still covers the tile is the list download; the
	// full-size id stays beside it for the viewer.
	NSNumber *thumbId = nil;
	if ([kind isEqualToString:@"storyContentPhoto"]){
		NSDictionary *best = nil, *smallest = nil;
		for (NSDictionary *size in content[@"photo"][@"sizes"]){
			CGFloat w = [size[@"width"] doubleValue];
			if (w <= 0)
				continue;
			if (!smallest || w < [smallest[@"width"] doubleValue])
				smallest = size;
			if (w >= 220.0f && (!best || w < [best[@"width"] doubleValue]))
				best = size;
		}
		thumbId = (best ?: smallest ?: [content[@"photo"][@"sizes"] firstObject])[@"photo"][@"id"];
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
	if (thumbId)
		out[@"thumbPhotoId"] = thumbId;
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
		// The answer is a full chat object, id included; feeding it into
		// the cache puts a photo and a title beside the id, so the screen a
		// contact opens is dressed like any other chat instead of a bare
		// id and name pair (B6).
		[self mergeChat:chat];
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
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			[out addObject:TGFlattenGift(entry)];
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
	[self sessionsWithInactiveTtlCompletion:^(NSArray *sessions, NSInteger ttlDays){
		if (completion) completion(sessions);
	}];
}

- (void)sessionsWithInactiveTtlCompletion:(void (^)(NSArray *, NSInteger))completion {
	[self request:@{@"@type" : @"getActiveSessions"} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(@[], 0);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *session in result[@"sessions"]){
			[out addObject:@{
				@"id"         : session[@"id"] ?: @0,
				@"name"       : session[@"application_name"] ?: @"",
				@"platform"   : [NSString stringWithFormat:@"%@ %@",
						session[@"platform"] ?: @"", session[@"system_version"] ?: @""],
				@"ip"         : session[@"ip_address"] ?: session[@"ip"] ?: @"",
				@"isCurrent"  : session[@"is_current"] ?: @NO,
				@"isUnconfirmed" : session[@"is_unconfirmed"] ?: @NO,
				@"canAcceptSecretChats" : session[@"can_accept_secret_chats"] ?: @YES,
				@"canAcceptCalls" : session[@"can_accept_calls"] ?: @YES,
				@"lastActive" : session[@"last_active_date"] ?: @0,
			}];
		}
		if (completion)
			completion(out, [result[@"inactive_session_ttl_days"] integerValue]);
	}];
}

- (void)terminateSession:(long long)sessionId {
	[self send:@{@"@type" : @"terminateSession", @"session_id" : @(sessionId)}];
}

- (void)confirmSession:(long long)sessionId {
	[self send:@{@"@type" : @"confirmSession", @"session_id" : @(sessionId)}];
}

- (void)toggleSession:(long long)sessionId
	   canAcceptCalls:(BOOL)canAccept
		   completion:(void (^)(BOOL, NSString *))completion {
	if (!sessionId){
		if (completion) completion(NO, @"No session was named.");
		return;
	}
	[self request:@{@"@type" : @"toggleSessionCanAcceptCalls",
					@"session_id" : @(sessionId),
					@"can_accept_calls" : @(canAccept)}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		NSString *message = [result[@"message"] isKindOfClass:NSString.class]
				? result[@"message"] : @"Telegram refused that.";
		if (completion) completion(!failed, failed ? message : nil);
	}];
}

- (void)setInactiveSessionTtlDays:(NSInteger)days
					   completion:(void (^)(BOOL, NSString *))completion {
	// TDLib's own range; naming it here means the picker cannot send a value
	// the server will only reject.
	if (days < 1 || days > 366){
		if (completion) completion(NO, @"The idle timeout is 1 to 366 days.");
		return;
	}
	[self request:@{@"@type" : @"setInactiveSessionTtl",
					@"inactive_session_ttl_days" : @((int32_t)days)}
	   completion:^(NSDictionary *result){
		BOOL failed = [result[@"@type"] isEqualToString:@"error"];
		NSString *message = [result[@"message"] isKindOfClass:NSString.class]
				? result[@"message"] : @"Telegram refused that.";
		if (completion) completion(!failed, failed ? message : nil);
	}];
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
	if (self.rawUsersById[@(userId)][@"status"]){
		NSString *text = TGStatusTextFromTDStatus(self.rawUsersById[@(userId)][@"status"]);
		if (completion) completion(text);
		return;
	}
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		if ([user[@"@type"] isEqualToString:@"user"]){
			if (!self.rawUsersById) self.rawUsersById = [[TGObjectLruCache alloc] initWithCapacity:TGRawUserCacheCap];
			self.rawUsersById[@(userId)] = user;
		}
		// The phrase table now lives in TGStatusText alongside the network
		// names, so a host test can pin every line it can say (B4).
		NSString *text = TGStatusTextFromTDStatus(user[@"status"]);
		if (completion) completion(text);
	}];
}

- (NSNumber *)photoFileIdForUserId:(int64_t)userId {
	return self.userPhotosById[@(userId)];
}

- (void)profilePhotoFileIdForUser:(int64_t)userId
                       completion:(void (^)(NSNumber *))completion {
	if (!userId){
		if (completion) completion(nil);
		return;
	}
	NSNumber *cached = self.userPhotosById[@(userId)];
	if (cached){
		if (completion) completion(cached);
		return;
	}
	// A member list names people TDLib has already told us about; their raw
	// record carries the picture without another round trip.
	NSDictionary *raw = self.rawUsersById[@(userId)];
	if (raw){
		NSNumber *fileId = [raw[@"profile_photo"][@"small"][@"id"]
				isKindOfClass:NSNumber.class]
				? raw[@"profile_photo"][@"small"][@"id"] : nil;
		if (fileId)
			self.userPhotosById[@(userId)] = fileId;
		if (completion) completion(fileId);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		TGClient *me = weakSelf;
		NSNumber *fileId = nil;
		if ([user[@"@type"] isEqualToString:@"user"]){
			// The raw record is what the next call reads, so a user with no
			// picture is answered locally instead of asked for again.
			if (!me.rawUsersById)
				me.rawUsersById = [[TGObjectLruCache alloc] initWithCapacity:TGRawUserCacheCap];
			if (me)
				me.rawUsersById[@(userId)] = user;
			NSNumber *small = user[@"profile_photo"][@"small"][@"id"];
			if ([small isKindOfClass:NSNumber.class]){
				fileId = small;
				if (!me.userPhotosById)
					me.userPhotosById = [NSMutableDictionary dictionary];
				me.userPhotosById[@(userId)] = small;
			}
		}
		if (completion) completion(fileId);
	}];
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
		NSString *tab = full[@"main_profile_tab"][@"@type"];
		tab = [tab stringByReplacingOccurrencesOfString:@"profileTab" withString:@""];
		if (completion) completion(@{
			@"bio"          : full[@"bio"][@"text"] ?: @"",
			@"commonGroups" : full[@"group_in_common_count"] ?: @0,
			@"birthday"     : birthday,
			// The note is this account's own copy; empty means none is kept.
			@"note"         : full[@"note"][@"text"] ?: @"",
			// A contact's private picture: an id is present only when one is
			// set, which is what the profile's remove row keys off.
			@"personalPhoto": full[@"personal_photo"][@"small"][@"id"] ?: @0,
			@"mainProfileTab": tab.length ? tab.lowercaseString : @"posts",
			@"shareTheme"   : full[@"share_theme"][@"@type"] ?: @"",
			// A user who has calls turned off should not be offered one.
			@"canCall"      : full[@"can_be_called"] ?: @NO,
			@"canVideoCall" : full[@"supports_video_calls"] ?: @NO,
		});
	}];
}

#pragma mark - local notifications

/// The group types TDLib names. A raw "@type" is not what a row header
/// should read, and the four labels are all the schema has.
- (void)applyHavePendingNotificationsUpdate:(NSDictionary *)update {
	self.haveDelayedNotifications =
			[update[@"have_delayed_notifications"] boolValue];
	self.haveUnreceivedNotifications =
			[update[@"have_unreceived_notifications"] boolValue];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGActiveNotificationsChangedNotification
						  object:self
						userInfo:@{@"pending" : @(self.havePendingNotifications)}];
}

- (void)applyAutosaveSettingsUpdate:(NSDictionary *)update {
	NSString *scopeType = update[@"scope"][@"@type"] ?: @"";
	NSString *scope = nil;
	if ([scopeType isEqualToString:@"autosaveSettingsScopeGroupChats"])
		scope = @"groups";
	else if ([scopeType isEqualToString:@"autosaveSettingsScopeChannelChats"])
		scope = @"channels";
	else if ([scopeType isEqualToString:@"autosaveSettingsScopePrivateChats"])
		scope = @"private";

	if (scope.length && [update[@"settings"] isKindOfClass:NSDictionary.class]){
		NSMutableDictionary *scopes = [self.autosaveSettingsByScope mutableCopy]
				?: [NSMutableDictionary dictionary];
		scopes[scope] = TGFlattenAutosaveScope(update[@"settings"]);
		self.autosaveSettingsByScope = scopes;
	}
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGAutosaveSettingsChangedNotification object:self];
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

#pragma mark - reactions

- (NSDictionary *)reactionNotificationSettings {
	return self.reactionNotificationSettingsValue;
}

/// No record yet means Telegram has not answered the post-login burst; its
/// default is to show them, so the switch starts on rather than off.
- (BOOL)reactionNotificationsEnabled {
	NSString *source = self.reactionNotificationSettingsValue[@"message_reaction_source"][@"@type"];
	if (!source.length)
		return YES;
	return ![source isEqualToString:@"reactionNotificationSourceNone"];
}

- (void)setReactionNotificationsEnabled:(BOOL)enabled
                             completion:(void (^)(BOOL))completion {
	// setReactionNotificationSettings replaces the whole record. Reading the
	// one Telegram last sent is the only way toggling reactions does not also
	// reset the story and poll sources or the chosen sound.
	NSDictionary *current = self.reactionNotificationSettingsValue ?: @{};
	NSDictionary *all = @{@"@type" : @"reactionNotificationSourceAll"};
	NSMutableDictionary *next = [@{
		@"@type"                    : @"reactionNotificationSettings",
		@"message_reaction_source"  : enabled
				? all : @{@"@type" : @"reactionNotificationSourceNone"},
		@"story_reaction_source"    : current[@"story_reaction_source"] ?: all,
		@"poll_vote_source"         : current[@"poll_vote_source"] ?: all,
		@"sound_id"                 : current[@"sound_id"] ?: @(0),
		@"show_preview"             : current[@"show_preview"] ?: @YES,
	} mutableCopy];

	[self request:@{@"@type" : @"setReactionNotificationSettings",
					@"notification_settings" : next}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok){
			NSLog(@"setReactionNotificationSettings: %@", result[@"message"]);
			if (completion) completion(NO);
			return;
		}
		self.reactionNotificationSettingsValue = next;
		// The settings page rebuilds from what it reads, and this write is
		// the one place the local copy moves without a server update.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGNotificationSettingsChangedNotification object:self];
		if (completion) completion(YES);
	}];
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

- (void)importedContactCountWithCompletion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"getImportedContactCount"}
	   completion:^(NSDictionary *result){
		NSInteger count = 0;
		if ([result isKindOfClass:NSDictionary.class] &&
			![result[@"@type"] isEqualToString:@"error"])
			count = [result[@"count"] integerValue];
		if (completion) completion(count);
	}];
}

- (void)changeImportedContacts:(NSArray *)contacts
					completion:(void (^)(NSInteger, NSArray *))completion {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *contact in contacts){
		if (![contact isKindOfClass:NSDictionary.class])
			continue;
		NSString *phone = contact[@"phone_number"] ?: @"";
		if (!phone.length)
			continue;
		[rows addObject:@{
			@"@type"        : @"importedContact",
			@"phone_number" : phone,
			@"first_name"   : contact[@"first_name"] ?: @"",
			@"last_name"    : contact[@"last_name"] ?: @"",
			@"note"         : [NSNull null],
		}];
	}
	[self request:@{@"@type" : @"changeImportedContacts", @"contacts" : rows}
	   completion:^(NSDictionary *result){
		NSArray *userIds = result[@"user_ids"];
		if (![userIds isKindOfClass:NSArray.class])
			userIds = @[];
		if (completion) completion((NSInteger)userIds.count, userIds);
	}];
}

- (void)applicationDownloadLinkWithCompletion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getApplicationDownloadLink"}
	   completion:^(NSDictionary *result){
		NSString *url = @"";
		if ([result isKindOfClass:NSDictionary.class] &&
			![result[@"@type"] isEqualToString:@"error"])
			url = [result[@"url"] isKindOfClass:NSString.class] ? result[@"url"] : @"";
		if (completion) completion(url);
	}];
}

#pragma mark - autosave

static NSString *TGAutosaveScopeType(NSString *scope) {
	if ([scope isEqualToString:@"groups"])
		return @"autosaveSettingsScopeGroupChats";
	if ([scope isEqualToString:@"channels"])
		return @"autosaveSettingsScopeChannelChats";
	return @"autosaveSettingsScopePrivateChats";
}

static NSDictionary *TGFlattenAutosaveScope(NSDictionary *settings) {
	if (![settings isKindOfClass:NSDictionary.class])
		return @{};
	return @{
		@"photos"       : settings[@"autosave_photos"] ?: @NO,
		@"videos"       : settings[@"autosave_videos"] ?: @NO,
		@"maxVideoSize" : settings[@"max_video_file_size"] ?: @(0),
	};
}

- (void)autosaveSettingsWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getAutosaveSettings"}
	   completion:^(NSDictionary *result){
		if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		NSMutableArray *exceptions = [NSMutableArray array];
		for (NSDictionary *exception in result[@"exceptions"]){
			if (![exception isKindOfClass:NSDictionary.class])
				continue;
			NSMutableDictionary *row = [@{
				@"chatId" : exception[@"chat_id"] ?: @(0),
			} mutableCopy];
			[row addEntriesFromDictionary:TGFlattenAutosaveScope(exception[@"settings"])];
			[exceptions addObject:row];
		}
		NSDictionary *settings = @{
			@"private"    : TGFlattenAutosaveScope(result[@"private_chat_settings"]),
			@"groups"     : TGFlattenAutosaveScope(result[@"group_settings"]),
			@"channels"   : TGFlattenAutosaveScope(result[@"channel_settings"]),
			@"exceptions" : exceptions,
		};
		if (completion) completion(settings);
	}];
}

- (void)setAutosaveSettingsForScope:(NSString *)scope
							 photos:(BOOL)photos
							 videos:(BOOL)videos
					   maxVideoSize:(long long)maxVideoSize
						 completion:(void (^)(BOOL))completion {
	NSDictionary *settings = @{
		@"@type"              : @"scopeAutosaveSettings",
		@"autosave_photos"    : @(photos),
		@"autosave_videos"    : @(videos),
		@"max_video_file_size": @(maxVideoSize),
	};
	[self request:@{
		@"@type"    : @"setAutosaveSettings",
		@"scope"    : @{@"@type" : TGAutosaveScopeType(scope)},
		@"settings" : settings,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)clearAutosaveSettingsExceptionsWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"clearAutosaveSettingsExceptions"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

#pragma mark - profile photos, link, groups in common

/// A profile photo taken off the account by the id the chatPhoto carried.
- (void)deleteProfilePhoto:(int64_t)photoId
				completion:(void (^)(BOOL))completion {
	if (!photoId){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"            : @"deleteProfilePhoto",
		@"profile_photo_id" : @(photoId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// The account's whole photo history: what the avatar tap shows, and the
/// only place a photoId worth deleting answers from.
- (void)userProfilePhotos:(int64_t)userId
			   completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"   : @"getUserProfilePhotos",
		@"user_id" : @(userId),
		@"offset"  : @(0),
		@"limit"   : @(50),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *photo in result[@"photos"]){
			int64_t photoId = [photo[@"id"] longLongValue];
			NSNumber *fileId = photo[@"small"][@"id"];
			if (!photoId || !fileId)
				continue;
			[out addObject:@{@"photoId" : @(photoId),
							  @"fileId" : fileId}];
		}
		if (completion) completion(out);
	}];
}

/// The signed-in account's own t.me link - Telegram gives it only for the
/// current user, so there is no asking for someone else's.
- (void)myUserLink:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"                 : @"getUserLink",
		@"remove_messages_fee"   : @NO,
		@"return_permanent_link" : @YES,
		@"revoke_previous_links" : @NO,
	} completion:^(NSDictionary *result){
		if (completion) completion(result[@"url"] ?: @"");
	}];
}

/// The chats two accounts are in together, named off the answer itself, so
/// a tap opens it like any chat the list holds.
- (void)groupsInCommonWithUser:(int64_t)userId
					completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"          : @"getGroupsInCommon",
		@"user_id"        : @(userId),
		@"offset_chat_id" : @(0),
		@"limit"          : @(50),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *chat in result[@"chats"]){
			NSString *title = chat[@"title"] ?: @"";
			if (!title.length)
				continue;
			[out addObject:@{@"chatId" : chat[@"id"] ?: @0,
							  @"title" : title}];
		}
		if (completion) completion(out);
	}];
}

#pragma mark - two-step verification

/// The password written whole. A wrong old password is the error here, and
/// the screen above is what says that to a human. An empty new password is
/// how the password comes off, not a refusal to write one.
- (void)setPassword:(NSString *)oldPassword
				new:(NSString *)newPassword
			  hint:(NSString *)hint
	setEmailAddress:(BOOL)setEmailAddress
			  email:(NSString *)recoveryEmail
		 completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                      : @"setPassword",
		@"old_password"               : oldPassword ?: @"",
		@"new_password"               : newPassword ?: @"",
		@"new_hint"                   : hint ?: @"",
		@"set_recovery_email_address" : @(setEmailAddress),
		@"new_recovery_email_address" : recoveryEmail ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// What a recovery address says - and whether the password that asked for it
/// was right, because a wrong one is answered with an empty class where the
/// email would have been.
- (void)recoveryEmailAddress:(NSString *)password
				  completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"    : @"getRecoveryEmailAddress",
		@"password" : password ?: @"",
	} completion:^(NSDictionary *result){
		NSString *email = [result[@"@type"] isEqualToString:
				@"recoveryEmailAddress"]
				? (result[@"recovery_email_address"] ?: @"")
				: @"";
		if (completion) completion(email);
	}];
}

/// Point the recovery address somewhere else. TDLib confirms the new one by
/// letter afterwards, so the answer says the request landed, not that the
/// address is live.
- (void)setRecoveryEmailAddress:(NSString *)password
							 to:(NSString *)email
					 completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                      : @"setRecoveryEmailAddress",
		@"password"                   : password ?: @"",
		@"new_recovery_email_address" : email ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

#pragma mark - the last of the account

/// Every other device signs off in one request. This one is never its own
/// victim - terminateAllOtherSessions answers for the rest only.
/// A new recovery address is not in force until the code Telegram emails to
/// it is entered. Until then the old address - or none - still stands, which
/// is why the flow has to offer this rather than stopping at "we wrote".
- (void)checkRecoveryEmailCode:(NSString *)code
					completion:(void (^)(BOOL ok))completion {
	if (!code.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"checkRecoveryEmailAddressCode", @"code" : code}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		// Still carrying a pattern means the code did not take.
		BOOL stillWaiting = [result[@"recovery_email_address_code_info"]
				[@"email_address_pattern"] length] > 0;
		completion([result[@"@type"] isEqualToString:@"passwordState"] && !stillWaiting);
	}];
}

- (void)resendRecoveryEmailCode {
	[self send:@{@"@type" : @"resendRecoveryEmailAddressCode"}];
}

- (void)terminateAllOtherSessions:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"terminateAllOtherSessions"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

/// The end of the road, asked with the reason Telegram's own form collects
/// and the password two-step verification demands.
- (void)deleteAccountWithReason:(NSString *)reason
					   password:(NSString *)password
					 completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"    : @"deleteAccount",
		@"reason"   : reason ?: @"",
		@"password" : password ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
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
				@"chatId"   : @(chatId),
				@"messageId": m[@"id"] ?: @0,
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
	if (self.rawUsersById[@(userId)]){
		if (completion) completion(self.rawUsersById[@(userId)]);
		return;
	}
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *u){
		if ([u[@"@type"] isEqualToString:@"user"]){
			if (!self.rawUsersById) self.rawUsersById = [[TGObjectLruCache alloc] initWithCapacity:TGRawUserCacheCap];
			self.rawUsersById[@(userId)] = u;
		}
		if (completion) completion([u[@"@type"] isEqualToString:@"user"] ? u : nil);
	}];
}

- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
         completion:(void (^)(NSArray *))completion {
	[self mediaInChat:chatId filter:filter fromMessageId:0 limit:60 completion:completion];
}

- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
      fromMessageId:(int64_t)fromMessageId limit:(NSInteger)limit
         completion:(void (^)(NSArray *))completion {
	NSInteger batchLimit = limit > 0 ? MIN(limit, 100) : 60;
	[self request:@{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : @"",
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(0),
		@"limit"           : @(batchLimit),
		@"filter"          : @{@"@type" : filter ?: @"searchMessagesFilterPhotoAndVideo"},
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
