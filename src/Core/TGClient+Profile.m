#import "TGClientInternal.h"

/// TDLib answers a failed request with @type "error" and a human sentence in
/// "message". Every screen in this category shows that sentence rather than
/// inventing a reason of its own.
static NSString *TGProfileError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

static NSString *TGMainProfileTabName(NSDictionary *tab) {
	NSString *type = tab[@"@type"];
	if ([type isEqualToString:@"profileTabGifts"])  return @"gifts";
	if ([type isEqualToString:@"profileTabMedia"])  return @"media";
	if ([type isEqualToString:@"profileTabFiles"])  return @"files";
	if ([type isEqualToString:@"profileTabLinks"])  return @"links";
	if ([type isEqualToString:@"profileTabMusic"])  return @"music";
	if ([type isEqualToString:@"profileTabVoice"])  return @"voice";
	if ([type isEqualToString:@"profileTabGifs"])   return @"gifs";
	return @"posts";
}

static NSString *TGMainProfileTabType(NSString *name) {
	static NSDictionary *types = nil;
	if (!types)
		types = @{
			@"posts" : @"profileTabPosts",
			@"gifts" : @"profileTabGifts",
			@"media" : @"profileTabMedia",
			@"files" : @"profileTabFiles",
			@"links" : @"profileTabLinks",
			@"music" : @"profileTabMusic",
			@"voice" : @"profileTabVoice",
			@"gifs"  : @"profileTabGifs",
		};
	return types[name] ?: @"profileTabPosts";
}

static NSArray *TGAccentIdsOrDefault(NSArray *ids) {
	if (ids.count)
		return ids;
	// The schema guarantees 0-6 are always valid, so a client that has not
	// met updateAccentColors yet still has something honest to draw.
	return @[ @0, @1, @2, @3, @4, @5, @6 ];
}

@implementation TGClient (Profile)

#pragma mark - the private note

- (void)setUserNote:(NSString *)note
			forUser:(int64_t)userId
		 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"   : @"setUserNote",
		@"user_id" : @(userId),
		@"note"    : TGFormattedText(note),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

#pragma mark - close friends

- (void)closeFriendsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getCloseFriends"} completion:^(NSDictionary *result){
		NSMutableArray *ids = [NSMutableArray array];
		for (id entry in result[@"user_ids"])
			if ([entry isKindOfClass:NSNumber.class])
				[ids addObject:entry];
		if (completion)
			completion(ids);
	}];
}

- (void)setCloseFriends:(NSArray *)userIds
			 completion:(void (^)(BOOL, NSString *))completion {
	NSMutableArray *ids = [NSMutableArray array];
	for (id entry in userIds)
		if ([entry isKindOfClass:NSNumber.class])
			[ids addObject:entry];
	[self request:@{
		@"@type"    : @"setCloseFriends",
		@"user_ids" : ids,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

#pragma mark - read-date privacy

- (void)readDatePrivacySettingsWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"getReadDatePrivacySettings"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"show_read_date"] boolValue]);
	}];
}

- (void)setReadDateShown:(BOOL)shown
			  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"    : @"setReadDatePrivacySettings",
		@"settings" : @{
			@"@type"          : @"readDatePrivacySettings",
			@"show_read_date" : @(shown),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

#pragma mark - suggestions

- (void)suggestBirthdateDay:(NSInteger)day
					  month:(NSInteger)month
					   year:(NSInteger)year
					 forUser:(int64_t)userId
				  completion:(void (^)(BOOL, NSString *))completion {
	NSMutableDictionary *birthdate = [@{
		@"@type" : @"birthdate",
		@"day"   : @(day),
		@"month" : @(month),
	} mutableCopy];
	if (year > 0)
		birthdate[@"year"] = @(year);
	[self request:@{
		@"@type"     : @"suggestUserBirthdate",
		@"user_id"   : @(userId),
		@"birthdate" : birthdate,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

- (void)suggestProfilePhotoAtPath:(NSString *)path
						  forUser:(int64_t)userId
					   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"   : @"suggestUserProfilePhoto",
		@"user_id" : @(userId),
		@"photo"   : @{
			@"@type" : @"inputChatPhotoStatic",
			@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path ?: @""},
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

- (void)setPersonalProfilePhotoAtPath:(NSString *)path
							  forUser:(int64_t)userId
						   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"   : @"setUserPersonalProfilePhoto",
		@"user_id" : @(userId),
		// A nil picture is how the schema says "remove it".
		@"photo"   : path.length
				? @{@"@type" : @"inputChatPhotoStatic",
					@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path}}
				: [NSNull null],
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

#pragma mark - the main profile tab

- (void)myMainProfileTabWithCompletion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"   : @"getUserFullInfo",
		@"user_id" : self.me[@"id"] ?: @0,
	} completion:^(NSDictionary *full){
		if (completion)
			completion(TGMainProfileTabName(full[@"main_profile_tab"]));
	}];
}

- (void)setMainProfileTab:(NSString *)tab
			   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"            : @"setMainProfileTab",
		@"main_profile_tab" : @{@"@type" : TGMainProfileTabType(tab)},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

#pragma mark - birthdays and support

- (void)hideContactCloseBirthdaysWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"hideContactCloseBirthdays"}
	   completion:^(NSDictionary *result){
		BOOL ok = TGProfileError(result) == nil;
		if (ok)
			self.contactCloseBirthdays = @[];
		if (completion)
			completion(ok, TGProfileError(result));
	}];
}

- (NSArray *)contactCloseBirthdayUsers {
	return self.contactCloseBirthdays ?: @[];
}

- (void)supportUserWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getSupportUser"} completion:^(NSDictionary *result){
		NSString *error = TGProfileError(result);
		if (error || ![result[@"@type"] isEqualToString:@"user"]){
			if (completion)
				completion(nil, error ?: @"Telegram did not name a support account.");
			return;
		}
		NSString *name = [[NSString stringWithFormat:@"%@ %@",
				result[@"first_name"] ?: @"", result[@"last_name"] ?: @""]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!name.length)
			name = result[@"usernames"][@"active_usernames"][0] ?: @"Telegram Support";
		if (completion)
			completion(@{
				@"id"       : result[@"id"] ?: @0,
				@"name"     : name,
				@"username" : result[@"usernames"][@"active_usernames"][0] ?: @"",
			}, nil);
	}];
}

#pragma mark - accent colours

- (NSArray *)availableAccentColorIds {
	return TGAccentIdsOrDefault(self.accentColorIds);
}

- (NSArray *)availableProfileAccentColorIds {
	return TGAccentIdsOrDefault(self.profileAccentColorIds);
}

- (void)myAccentColorsWithCompletion:(void (^)(NSInteger, NSInteger))completion {
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *me){
		if (completion)
			completion([me[@"accent_color_id"] integerValue],
					   [me[@"profile_accent_color_id"] integerValue]);
	}];
}

- (void)myAccentColoursWithCompletion:(void (^)(NSInteger, NSInteger, int64_t, int64_t))completion {
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *me){
		if (completion)
			completion([me[@"accent_color_id"] integerValue],
					   [me[@"profile_accent_color_id"] integerValue],
					   [me[@"background_custom_emoji_id"] longLongValue],
					   [me[@"profile_background_custom_emoji_id"] longLongValue]);
	}];
}

/// TDLib's colours are one int each, 0xRRGGBB, and the first is the colour a
/// swatch shows. Ids 0 to 6 are not in the list at all: the schema leaves them to
/// the app, so these are the same seven the initials avatars use. The palette
/// belongs to the account rather than the theme, so it is mapped here.
static UIColor *TGColourFromRGB(int32_t rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f
						   green:((rgb >> 8) & 0xFF) / 255.0f
							blue:(rgb & 0xFF) / 255.0f
						   alpha:1.0f];
}

- (UIColor *)accentColourForId:(NSInteger)colourId profile:(BOOL)profile {
	for (NSDictionary *record in (profile ? self.profileAccentColors : self.accentColors) ?: @[]){
		if (![record isKindOfClass:NSDictionary.class] || [record[@"id"] integerValue] != colourId)
			continue;
		id colours = record[@"light_theme_colors"];
		if (profile)
			colours = [colours isKindOfClass:NSDictionary.class] ? colours[@"palette_colors"] : nil;
		if (![colours isKindOfClass:NSArray.class] || ![colours count])
			return nil;
		return TGColourFromRGB([colours[0] intValue]);
	}
	static const int32_t builtIn[] = {0xE17076, 0xEDA86C, 0xA695E7, 0x7BC862, 0x6EC9CB, 0x65AADD, 0xEE7AAE};
	if (!profile && colourId >= 0 && colourId <= 6)
		return TGColourFromRGB(builtIn[colourId]);
	return nil;
}

- (void)setAccountAccentColor:(NSInteger)accentId
		   backgroundEmojiId:(int64_t)emojiId
				  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"                    : @"setAccentColor",
		@"accent_color_id"          : @(accentId),
		@"background_custom_emoji_id" : @(emojiId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

- (void)setAccountProfileAccentColor:(NSInteger)accentId
				 backgroundEmojiId:(int64_t)emojiId
						completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"                            : @"setProfileAccentColor",
		@"profile_accent_color_id"          : @(accentId),
		@"profile_background_custom_emoji_id" : @(emojiId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

- (void)setAccountAccentColorPreservingBackgroundEmoji:(NSInteger)accentId
											completion:(void (^)(BOOL, NSString *))completion {
	[self myAccentColoursWithCompletion:^(NSInteger ignoredAccent, NSInteger ignoredProfile,
										  int64_t backgroundEmojiId, int64_t ignoredProfileEmoji){
		[self setAccountAccentColor:accentId backgroundEmojiId:backgroundEmojiId
						 completion:completion];
	}];
}

- (void)setAccountProfileAccentColorPreservingBackgroundEmoji:(NSInteger)accentId
												   completion:(void (^)(BOOL, NSString *))completion {
	[self myAccentColoursWithCompletion:^(NSInteger ignoredAccent, NSInteger ignoredProfile,
										  int64_t ignoredEmoji, int64_t profileBackgroundEmojiId){
		[self setAccountProfileAccentColor:accentId
						 backgroundEmojiId:profileBackgroundEmojiId
								completion:completion];
	}];
}

#pragma mark - the sharing theme

- (void)profileShareThemeBackdropsWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getProfileShareThemeBackdrops"}
	   completion:^(NSDictionary *result){
		NSString *error = TGProfileError(result);
		if (error){
			if (completion)
				completion(@[], error);
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *backdrop in result[@"backdrops"]){
			NSNumber *backdropId = backdrop[@"id"];
			if (![backdropId isKindOfClass:NSNumber.class])
				continue;
			[rows addObject:@{
				@"id"     : backdropId,
				@"name"   : backdrop[@"name"] ?: [NSString stringWithFormat:@"Backdrop %@",
						backdropId],
				@"colors" : backdrop[@"colors"] ?: @{},
			}];
		}
		if (completion)
			completion(rows, nil);
	}];
}

- (void)setProfileShareThemeForChat:(int64_t)chatId
						 backdropId:(NSInteger)backdropId
						 useDefault:(BOOL)useDefault
						 completion:(void (^)(BOOL, NSString *))completion {
	NSMutableDictionary *theme = [@{
		@"@type"                 : @"inputProfileShareThemeEmoji",
		@"use_default_background" : @(useDefault),
		@"background_backdrop_id" : @(useDefault ? 0 : backdropId),
	} mutableCopy];
	// The schema caps this at six; one emoji is enough to tell a themed
	// sharing card apart from the default, and empty is only legal together
	// with a default background.
	if (!useDefault)
		theme[@"emojis"] = @[@{@"@type" : @"emojiTypeRegular", @"emoji" : @"✨"}];
	[self request:@{
		@"@type"   : @"setProfileShareTheme",
		@"chat_id" : @(chatId),
		@"theme"   : theme,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

- (void)clearProfileShareThemeForChat:(int64_t)chatId
						   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"   : @"setProfileShareTheme",
		@"chat_id" : @(chatId),
		@"theme"   : [NSNull null],
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGProfileError(result) == nil, TGProfileError(result));
	}];
}

@end
