//
// TGClient+Tier3.m - the requests behind TGClient+Tier3.h.
//
// Every method names its td_api function literally, so the coverage script
// sees it and scripts/tdlib_wired.py can prove a screen calls the method.
// The answers are flattened only to what a row can draw; the raw object is
// never kept, because these are records a screen shows once.
//
#import "TGClient+Tier3.h"
#import "TGClientInternal.h"

#pragma mark - shared helpers

static NSString *TGT3Error(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static BOOL TGT3Failed(NSDictionary *result) {
	return [result[@"@type"] isEqualToString:@"error"];
}

/// The synchronous half of td_api has to go through execute. A build without
/// the symbol falls back to the outbox so a request is still recorded and the
/// host tests can read its shape.
static void TGT3Execute(TGClient *client, NSDictionary *request,
						void (^completion)(NSDictionary *)) {
	if (client.td_exec){
		NSDictionary *answer = [client executeSynchronously:request];
		if (completion) completion(answer);
		return;
	}
	[client request:request completion:completion];
}

/// "premiumFeatureDisabledAds" -> "disabledAds", the word a row shows.
static NSString *TGT3ShortType(id value) {
	if (![value isKindOfClass:NSString.class])
		return @"unknown";
	NSString *name = value;
	static NSArray *prefixes = nil;
	if (!prefixes)
		prefixes = @[@"premiumFeature", @"premiumLimitType", @"premiumSource",
					 @"checkChatUsernameResult", @"canSendGiftResult",
					 @"reportSponsoredResult", @"starTransactionType",
					 @"transactionDirection", @"giftForResaleOrder",
					 @"logStream", @"chatTheme", @"emojiStatusType",
					 @"businessRecipient", @"messageSender"];
	for (NSString *prefix in prefixes){
		if ([name hasPrefix:prefix]){
			name = [name substringFromIndex:prefix.length];
			break;
		}
	}
	if ([name hasSuffix:@"Result"] && name.length > @"Result".length)
		name = [name substringToIndex:name.length - @"Result".length];
	if (!name.length)
		return @"unknown";
	return [[[name substringToIndex:1] lowercaseString]
			stringByAppendingString:[name substringFromIndex:1]];
}

/// "disabledAds" -> "premiumFeatureDisabledAds", and an already-prefixed
/// name is left alone so a caller can pass either spelling.
static NSString *TGT3PrefixedType(NSString *prefix, NSString *value) {
	if ([value hasPrefix:prefix])
		return value;
	if (!value.length)
		return prefix;
	NSString *first = [[value substringToIndex:1] uppercaseString];
	return [prefix stringByAppendingString:
			[first stringByAppendingString:[value substringFromIndex:1]]];
}

static NSString *TGT3String(NSDictionary *dictionary, NSString *key) {
	id value = dictionary[key];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGT3Number(NSDictionary *dictionary, NSString *key) {
	id value = dictionary[key];
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

/// A user record reduced to the three facts a row draws.
static NSDictionary *TGT3User(NSDictionary *user) {
	if (![user isKindOfClass:NSDictionary.class])
		return @{@"id" : @0, @"name" : @"", @"username" : @""};
	NSString *first = TGT3String(user, @"first_name");
	NSString *last = TGT3String(user, @"last_name");
	NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (!name.length)
		name = TGT3String(user, @"username");
	return @{
		@"id"       : TGT3Number(user, @"id"),
		@"name"     : name,
		@"username" : TGT3String(user, @"username"),
	};
}

/// messageSenderUser/messageSenderChat as the object the requests want.
static NSDictionary *TGT3Sender(NSString *kind, int64_t identifier) {
	if ([kind isEqualToString:@"chat"])
		return @{@"@type" : @"messageSenderChat", @"chat_id" : @(identifier)};
	return @{@"@type" : @"messageSenderUser", @"user_id" : @(identifier)};
}

static NSDictionary *TGT3Sticker(NSDictionary *sticker) {
	if (![sticker isKindOfClass:NSDictionary.class])
		return @{};
	return @{
		@"id"     : TGT3Number(sticker, @"id"),
		@"setId"  : TGT3Number(sticker, @"set_id"),
		@"emoji"  : TGT3String(sticker, @"emoji"),
		@"fileId" : TGT3Number(sticker[@"sticker"], @"id"),
	};
}

/// JsonValue for a plain string. A full tree is accepted when the caller
/// already built one, which is what the JSON screen does.
static NSDictionary *TGT3JsonValue(id value) {
	if ([value isKindOfClass:NSDictionary.class] &&
			[value[@"@type"] hasPrefix:@"jsonValue"])
		return value;
	NSString *text = [value isKindOfClass:NSString.class] ? value : @"";
	return @{@"@type" : @"jsonValueString", @"value" : text};
}

/// The report result shape: the word Telegram wants the client to draw plus
/// the option list when it is asking for one.
static NSDictionary *TGT3ReportResult(NSDictionary *result) {
	NSString *type = TGT3ShortType(result[@"@type"]);
	NSMutableDictionary *out = [@{@"type" : type} mutableCopy];
	if ([result[@"title"] isKindOfClass:NSString.class])
		out[@"title"] = result[@"title"];
	NSMutableArray *options = [NSMutableArray array];
	for (NSDictionary *option in result[@"options"]){
		if (![option isKindOfClass:NSDictionary.class])
			continue;
		[options addObject:@{
			@"id"   : TGT3String(option, @"id"),
			@"text" : TGT3String(option, @"text"),
		}];
	}
	if (options.count)
		out[@"options"] = options;
	return out;
}

@implementation TGClient (Tier3)

/// The nested themeParameters a Web App call requires. This client has no
/// in-app browser, so the colours are only the record Telegram stores with
/// the request; black is TDLib's zero.
static NSDictionary *TGT3WebAppTheme(void) {
	return @{@"@type" : @"themeParameters",
			 @"background_color" : @((int32_t)0xff000000),
			 @"secondary_background_color" : @((int32_t)0xff1c1c1c),
			 @"header_background_color" : @((int32_t)0xff000000),
			 @"bottom_bar_background_color" : @((int32_t)0xff000000),
			 @"section_background_color" : @((int32_t)0xffffffff),
			 @"section_separator_color" : @((int32_t)0xffe1e4e9),
			 @"text_color" : @((int32_t)0xff222222),
			 @"accent_text_color" : @((int32_t)0xff3d95d4),
			 @"section_header_text_color" : @((int32_t)0xff696a6f),
			 @"subtitle_text_color" : @((int32_t)0xff8d8e90),
			 @"destructive_text_color" : @((int32_t)0xffe53935),
			 @"hint_color" : @((int32_t)0xff95999a),
			 @"link_color" : @((int32_t)0xff4cb3f5),
			 @"button_color" : @((int32_t)0xff3d95d4),
			 @"button_text_color" : @((int32_t)0xffffffff)};
}

static NSDictionary *TGT3WebAppParameters(NSString *mode) {
	NSString *openMode = @"webAppOpenModeCompact";
	if ([mode isEqualToString:@"fullSize"])
		openMode = @"webAppOpenModeFullSize";
	else if ([mode isEqualToString:@"fullScreen"])
		openMode = @"webAppOpenModeFullScreen";
	return @{@"@type" : @"webAppOpenParameters",
			 @"theme" : TGT3WebAppTheme(),
			 @"application_name" : @"LegacyTG",
			 @"mode" : @{@"@type" : openMode}};
}

static NSDictionary *TGT3ButtonSource(int64_t chatId, int64_t messageId) {
	return @{@"@type" : @"keyboardButtonSourceMessage",
			 @"chat_id" : @(chatId),
			 @"message_id" : @(messageId)};
}

#pragma mark - sponsored messages

- (void)sponsoredMessagesForChat:(int64_t)chatId
					  completion:(void (^)(NSArray *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatSponsoredMessages", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *message in result[@"messages"]){
			if (![message isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *sponsor = message[@"sponsor"];
			[rows addObject:@{
				@"kind"           : @"chat",
				@"messageId"      : TGT3Number(message, @"message_id"),
				@"isRecommended"  : @([message[@"is_recommended"] boolValue]),
				@"canBeReported"  : @([message[@"can_be_reported"] boolValue]),
				@"title"          : TGT3String(message, @"title"),
				@"buttonText"     : TGT3String(message, @"button_text"),
				@"additionalInfo" : TGT3String(message, @"additional_info"),
				@"sponsor"        : TGT3String(sponsor, @"info"),
				@"contentType"    : TGT3ShortType(message[@"content"][@"@type"]),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)clickSponsoredMessage:(int64_t)messageId
					   inChat:(int64_t)chatId
					mediaClick:(BOOL)mediaClick
			  fromFullscreen:(BOOL)fromFullscreen
				   completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(NO, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"clickChatSponsoredMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"is_media_click" : @(mediaClick),
					@"from_fullscreen" : @(fromFullscreen)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)reportSponsoredMessage:(int64_t)messageId
						inChat:(int64_t)chatId
						option:(NSString *)optionId
					completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(nil, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"reportChatSponsoredMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"option_id" : (optionId ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3ReportResult(result), nil);
	}];
}

- (void)setSponsoredMessagesEnabled:(BOOL)enabled
						 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"toggleHasSponsoredMessagesEnabled",
					@"has_sponsored_messages_enabled" : @(enabled)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)setChannelSponsoredMessagesEnabled:(BOOL)enabled
							  supergroupId:(int64_t)supergroupId
							   completion:(void (^)(BOOL, NSString *))completion {
	if (!supergroupId){
		if (completion) completion(NO, @"A supergroup id is needed here, not a chat id.");
		return;
	}
	[self request:@{@"@type" : @"toggleSupergroupCanHaveSponsoredMessages",
					@"supergroup_id" : @(supergroupId),
					@"can_have_sponsored_messages" : @(enabled)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)searchSponsoredChats:(NSString *)query
				  completion:(void (^)(NSArray *, NSString *))completion {
	query = [query stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!query.length){
		if (completion) completion(nil, @"Type what to search for.");
		return;
	}
	[self request:@{@"@type" : @"getSearchSponsoredChats", @"query" : query}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *chat in result[@"chats"]){
			if (![chat isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"kind"           : @"search",
				@"uniqueId"       : TGT3Number(chat, @"unique_id"),
				@"chatId"         : TGT3Number(chat, @"chat_id"),
				@"sponsorInfo"    : TGT3String(chat, @"sponsor_info"),
				@"additionalInfo" : TGT3String(chat, @"additional_info"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)openSponsoredChat:(int64_t)uniqueId
			   completion:(void (^)(BOOL, NSString *))completion {
	if (!uniqueId){
		if (completion) completion(NO, @"A sponsored chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"openSponsoredChat",
					@"sponsored_chat_unique_id" : @(uniqueId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)viewSponsoredChat:(int64_t)uniqueId
			   completion:(void (^)(BOOL, NSString *))completion {
	if (!uniqueId){
		if (completion) completion(NO, @"A sponsored chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"viewSponsoredChat",
					@"sponsored_chat_unique_id" : @(uniqueId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)reportSponsoredChat:(int64_t)uniqueId
					 option:(NSString *)optionId
				 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!uniqueId){
		if (completion) completion(nil, @"A sponsored chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"reportSponsoredChat",
					@"sponsored_chat_unique_id" : @(uniqueId),
					@"option_id" : (optionId ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3ReportResult(result), nil);
	}];
}

- (void)videoAdvertisementsForChat:(int64_t)chatId
						 message:(int64_t)messageId
					  completion:(void (^)(NSArray *, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(nil, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"getVideoMessageAdvertisements",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *ad in result[@"advertisements"]){
			if (![ad isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"kind"               : @"video",
				@"uniqueId"           : TGT3Number(ad, @"unique_id"),
				@"text"               : TGT3String(ad, @"text"),
				@"title"              : TGT3String(ad, @"title"),
				@"additionalInfo"     : TGT3String(ad, @"additional_info"),
				@"minDisplayDuration" : TGT3Number(ad, @"min_display_duration"),
				@"maxDisplayDuration" : TGT3Number(ad, @"max_display_duration"),
				@"canBeReported"      : @([ad[@"can_be_reported"] boolValue]),
				@"sponsor"            : TGT3String(ad[@"sponsor"], @"info"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)clickVideoAdvertisement:(int64_t)uniqueId
					 completion:(void (^)(BOOL, NSString *))completion {
	if (!uniqueId){
		if (completion) completion(NO, @"An advertisement id is needed.");
		return;
	}
	[self request:@{@"@type" : @"clickVideoMessageAdvertisement",
					@"advertisement_unique_id" : @(uniqueId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)viewVideoAdvertisement:(int64_t)uniqueId
					completion:(void (^)(BOOL, NSString *))completion {
	if (!uniqueId){
		if (completion) completion(NO, @"An advertisement id is needed.");
		return;
	}
	[self request:@{@"@type" : @"viewVideoMessageAdvertisement",
					@"advertisement_unique_id" : @(uniqueId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)reportVideoAdvertisement:(int64_t)uniqueId
						  option:(NSString *)optionId
					  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!uniqueId){
		if (completion) completion(nil, @"An advertisement id is needed.");
		return;
	}
	[self request:@{@"@type" : @"reportVideoMessageAdvertisement",
					@"advertisement_unique_id" : @(uniqueId),
					@"option_id" : (optionId ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3ReportResult(result), nil);
	}];
}

#pragma mark - speech

- (void)recognizeSpeechInChat:(int64_t)chatId
					  message:(int64_t)messageId
				   completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(NO, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"recognizeSpeech",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)rateSpeechInChat:(int64_t)chatId
				 message:(int64_t)messageId
				  isGood:(BOOL)isGood
			  completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(NO, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"rateSpeechRecognition",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId),
					@"is_good" : @(isGood)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)markAudioListened:(int32_t)fileId
				 duration:(int32_t)duration
			   completion:(void (^)(BOOL, NSString *))completion {
	if (fileId <= 0){
		if (completion) completion(NO, @"An audio file id is needed.");
		return;
	}
	[self request:@{@"@type" : @"listenToAudio",
					@"audio_file_id" : @(fileId),
					@"duration" : @(MAX((int32_t)0, duration))}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - environment

- (void)jsonValueForText:(NSString *)text
			  completion:(void (^)(NSDictionary *, NSString *))completion {
	text = text ?: @"";
	TGT3Execute(self, @{@"@type" : @"getJsonValue", @"json" : text},
				^(NSDictionary *result){
		if (!result){
			if (completion) completion(nil, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(result, nil);
	});
}

- (void)jsonTextForValue:(NSDictionary *)value
			  completion:(void (^)(NSString *, NSString *))completion {
	TGT3Execute(self, @{@"@type" : @"getJsonString",
						@"json_value" : (value ?: @{@"@type" : @"jsonValueNull"})},
				^(NSDictionary *result){
		if (!result){
			if (completion) completion(nil, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"text"), nil);
	});
}

- (void)themeParametersJSONString:(NSDictionary *)colours
					   completion:(void (^)(NSString *, NSString *))completion {
	static NSArray *roles = nil;
	if (!roles)
		roles = @[@"backgroundColor", @"secondaryBackgroundColor",
				  @"headerBackgroundColor", @"bottomBarBackgroundColor",
				  @"sectionBackgroundColor", @"sectionSeparatorColor",
				  @"textColor", @"accentTextColor", @"sectionHeaderTextColor",
				  @"subtitleTextColor", @"destructiveTextColor", @"hintColor",
				  @"linkColor", @"buttonColor", @"buttonTextColor"];
	NSMutableDictionary *theme = [NSMutableDictionary dictionary];
	theme[@"@type"] = @"themeParameters";
	for (NSString *role in roles){
		NSString *key = [role stringByReplacingOccurrencesOfString:@"Color" withString:@"_color"];
		// The snake_case key has to keep the first word intact: the role is
		// written in camelCase and only its suffix changes.
		key = [key stringByReplacingOccurrencesOfString:@"([a-z])([A-Z])"
											 withString:@"$1_$2"
												options:NSRegularExpressionSearch
												  range:NSMakeRange(0, key.length)];
		key = [key lowercaseString];
		theme[key] = TGT3Number(colours ?: @{}, role);
	}
	TGT3Execute(self, @{@"@type" : @"getThemeParametersJsonString",
						@"theme" : theme}, ^(NSDictionary *result){
		if (!result){
			if (completion) completion(nil, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"text"), nil);
	});
}

- (void)logStreamWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	TGT3Execute(self, @{@"@type" : @"getLogStream"}, ^(NSDictionary *result){
		if (!result){
			if (completion) completion(nil, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(result, nil);
	});
}

- (void)logVerbosityLevelWithCompletion:(void (^)(int32_t, NSString *))completion {
	TGT3Execute(self, @{@"@type" : @"getLogVerbosityLevel"}, ^(NSDictionary *result){
		if (!result){
			if (completion) completion(0, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(0, TGT3Error(result));
			return;
		}
		if (completion) completion([TGT3Number(result, @"verbosity_level") intValue], nil);
	});
}

- (void)logTagsWithCompletion:(void (^)(NSArray *, NSString *))completion {
	TGT3Execute(self, @{@"@type" : @"getLogTags"}, ^(NSDictionary *result){
		if (!result){
			if (completion) completion(nil, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSArray *tags = result[@"tags"];
		if (completion) completion([tags isKindOfClass:NSArray.class] ? tags : @[], nil);
	});
}

- (void)logVerbosityForTag:(NSString *)tag
				completion:(void (^)(int32_t, NSString *))completion {
	tag = [tag stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!tag.length){
		if (completion) completion(0, @"A log tag is needed.");
		return;
	}
	TGT3Execute(self, @{@"@type" : @"getLogTagVerbosityLevel", @"tag" : tag},
				^(NSDictionary *result){
		if (!result){
			if (completion) completion(0, @"TDLib's execute symbol is not loaded.");
			return;
		}
		if (TGT3Failed(result)){
			if (completion) completion(0, TGT3Error(result));
			return;
		}
		if (completion) completion([TGT3Number(result, @"verbosity_level") intValue], nil);
	});
}

- (void)setLogVerbosityForTag:(NSString *)tag
						level:(int32_t)level
				   completion:(void (^)(BOOL, NSString *))completion {
	tag = [tag stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!tag.length){
		if (completion) completion(NO, @"A log tag is needed.");
		return;
	}
	if (level < 1 || level > 1024){
		if (completion) completion(NO, @"TDLib takes a verbosity level from 1 to 1024.");
		return;
	}
	TGT3Execute(self, @{@"@type" : @"setLogTagVerbosityLevel",
						@"tag" : tag, @"new_verbosity_level" : @(level)},
				^(NSDictionary *result){
		BOOL failed = !result || TGT3Failed(result);
		NSString *error = !result
				? @"TDLib's execute symbol is not loaded."
				: (failed ? TGT3Error(result) : nil);
		if (completion) completion(!failed, error);
	});
}

- (void)setLogStreamKind:(NSString *)kind
					path:(NSString *)path
			  completion:(void (^)(BOOL, NSString *))completion {
	NSDictionary *stream = nil;
	if ([kind isEqualToString:@"file"]){
		path = [path stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!path.length){
			if (completion) completion(NO, @"A file path is needed for a file stream.");
			return;
		}
		stream = @{@"@type" : @"logStreamFile",
				   @"path" : path,
				   @"max_file_size" : @(1048576),
				   @"redirect_stderr" : @NO};
	} else if ([kind isEqualToString:@"empty"]){
		stream = @{@"@type" : @"logStreamEmpty"};
	} else {
		stream = @{@"@type" : @"logStreamDefault"};
	}
	TGT3Execute(self, @{@"@type" : @"setLogStream", @"log_stream" : stream},
				^(NSDictionary *result){
		BOOL failed = !result || TGT3Failed(result);
		NSString *error = !result
				? @"TDLib's execute symbol is not loaded."
				: (failed ? TGT3Error(result) : nil);
		if (completion) completion(!failed, error);
	});
}

- (void)addLogMessage:(NSString *)text
				level:(int32_t)level
		   completion:(void (^)(BOOL, NSString *))completion {
	TGT3Execute(self, @{@"@type" : @"addLogMessage",
						@"verbosity_level" : @(MAX((int32_t)0, MIN(level, (int32_t)1023))),
						@"text" : (text ?: @"")},
				^(NSDictionary *result){
		BOOL failed = !result || TGT3Failed(result);
		NSString *error = !result
				? @"TDLib's execute symbol is not loaded."
				: (failed ? TGT3Error(result) : nil);
		if (completion) completion(!failed, error);
	});
}

- (void)saveApplicationLogEvent:(NSString *)type
						chatId:(int64_t)chatId
						  data:(NSString *)data
					completion:(void (^)(BOOL, NSString *))completion {
	type = [type stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!type.length){
		if (completion) completion(NO, @"An event type is needed.");
		return;
	}
	[self request:@{@"@type" : @"saveApplicationLogEvent",
					@"type" : type,
					@"chat_id" : @(chatId),
					@"data" : TGT3JsonValue(data)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)timeZonesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getTimeZones"} completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *zone in result[@"time_zones"]){
			if (![zone isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"id"     : TGT3String(zone, @"id"),
				@"name"   : TGT3String(zone, @"name"),
				@"offset" : TGT3Number(zone, @"utc_time_offset"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)currencyExchangeRatesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getCurrencyExchangeRates"}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *rate in result[@"rates"]){
			if (![rate isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"currency" : TGT3String(rate, @"currency"),
				@"rate"     : TGT3Number(rate, @"rate"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)currentWeatherAtLatitude:(double)latitude
					   longitude:(double)longitude
					  completion:(void (^)(NSDictionary *, NSString *))completion {
	NSDictionary *location = @{@"@type" : @"location",
							   @"latitude" : @(latitude),
							   @"longitude" : @(longitude),
							   @"horizontal_accuracy" : @0};
	[self request:@{@"@type" : @"getCurrentWeather", @"location" : location}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"temperature" : TGT3Number(result, @"temperature"),
						 @"emoji" : TGT3String(result, @"emoji")}, nil);
	}];
}

- (void)alarmAfterSeconds:(double)seconds
			   completion:(void (^)(BOOL, NSString *))completion {
	if (seconds <= 0 || seconds > 86400){
		if (completion) completion(NO, @"The wait must be between 1 second and a day.");
		return;
	}
	[self request:@{@"@type" : @"setAlarm", @"seconds" : @(seconds)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - owned bots

- (BOOL)userIsBot:(int64_t)userId {
	NSDictionary *raw = self.rawUsersById[@(userId)];
	NSDictionary *type = raw[@"type"];
	return [type[@"@type"] isEqualToString:@"userTypeBot"];
}

- (void)ownedBotsWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getOwnedBots"} completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		// Users carries ids, not records: TDLib keeps the user objects in its
		// own cache and the client already has their names from updateUser.
		NSMutableArray *rows = [NSMutableArray array];
		for (NSNumber *identifier in result[@"user_ids"]){
			if (![identifier isKindOfClass:NSNumber.class])
				continue;
			int64_t userId = identifier.longLongValue;
			[rows addObject:@{
				@"id" : @(userId),
				@"name" : [self nameForUserId:userId] ?: @"Bot",
				@"username" : @"",
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)checkBotUsername:(NSString *)username
			  isSecondary:(BOOL)isSecondary
			   completion:(void (^)(NSString *, NSString *))completion {
	username = [username stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!username.length){
		if (completion) completion(nil, @"A username is needed.");
		return;
	}
	[self request:@{@"@type" : @"checkBotUsername",
					@"username" : username,
					@"is_secondary" : @(isSecondary)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSString *word = TGT3ShortType(result[@"@type"]);
		if (completion) completion(word, nil);
	}];
}

- (void)botNameForBot:(int64_t)botUserId
			 language:(NSString *)language
		   completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotName", @"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"text"), nil);
	}];
}

- (void)setBotName:(NSString *)name
			forBot:(int64_t)botUserId
		  language:(NSString *)language
		completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"setBotName", @"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""), @"name" : (name ?: @"")}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)botDescriptionForBot:(int64_t)botUserId
					language:(NSString *)language
				  completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotInfoDescription", @"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"text"), nil);
	}];
}

- (void)setBotDescription:(NSString *)text
				   forBot:(int64_t)botUserId
				 language:(NSString *)language
			   completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"setBotInfoDescription",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""),
					@"description" : (text ?: @"")}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)botShortDescriptionForBot:(int64_t)botUserId
						 language:(NSString *)language
					   completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotInfoShortDescription",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"text"), nil);
	}];
}

- (void)setBotShortDescription:(NSString *)text
						forBot:(int64_t)botUserId
					  language:(NSString *)language
					completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"setBotInfoShortDescription",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""),
					@"short_description" : (text ?: @"")}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)removeBotProfilePhoto:(int64_t)botUserId
				   completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"setBotProfilePhoto",
					@"bot_user_id" : @(botUserId),
					@"photo" : [NSNull null]}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)addBotSecondaryUsername:(NSString *)username
						 forBot:(int64_t)botUserId
					 completion:(void (^)(BOOL, NSString *))completion {
	username = [username stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!botUserId || !username.length){
		if (completion) completion(NO, @"A bot id and a username are needed.");
		return;
	}
	[self request:@{@"@type" : @"addBotSecondaryUsername",
					@"bot_user_id" : @(botUserId), @"username" : username}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)deleteBotSecondaryUsernameForBot:(int64_t)botUserId
							  completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"deleteBotSecondaryUsername",
					@"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)setBotUsername:(NSString *)username
				active:(BOOL)active
				forBot:(int64_t)botUserId
			completion:(void (^)(BOOL, NSString *))completion {
	username = [username stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!botUserId || !username.length){
		if (completion) completion(NO, @"A bot id and a username are needed.");
		return;
	}
	[self request:@{@"@type" : @"toggleBotUsernameIsActive",
					@"bot_user_id" : @(botUserId),
					@"username" : username,
					@"is_active" : @(active)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)reorderBotActiveUsernames:(NSArray *)usernames
						   forBot:(int64_t)botUserId
					   completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !usernames.count){
		if (completion) completion(NO, @"A bot id and its usernames are needed.");
		return;
	}
	[self request:@{@"@type" : @"reorderBotActiveUsernames",
					@"bot_user_id" : @(botUserId),
					@"usernames" : usernames}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)botMediaPreviewsForBot:(int64_t)botUserId
					completion:(void (^)(NSArray *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotMediaPreviews", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *preview in result[@"previews"]){
			if (![preview isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *content = preview[@"content"];
			[rows addObject:@{
				@"date"        : TGT3Number(preview, @"date"),
				@"contentType" : TGT3ShortType(content[@"@type"]),
				@"fileId"      : TGT3Number(content[@"photo"] ?: content[@"video"], @"id"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)botMediaPreviewInfoForBot:(int64_t)botUserId
						 language:(NSString *)language
					   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotMediaPreviewInfo",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *previews = [NSMutableArray array];
		for (NSDictionary *preview in result[@"previews"]){
			if (![preview isKindOfClass:NSDictionary.class])
				continue;
			[previews addObject:@{@"date" : TGT3Number(preview, @"date"),
								  @"contentType" : TGT3ShortType(preview[@"content"][@"@type"])}];
		}
		NSArray *languages = result[@"language_codes"];
		if (completion)
			completion(@{@"previews" : previews,
						 @"languages" : ([languages isKindOfClass:NSArray.class]
								 ? languages : @[])}, nil);
	}];
}

- (NSDictionary *)botPreviewContentForFile:(int32_t)fileId video:(BOOL)video {
	NSDictionary *input = @{@"@type" : @"inputFileId", @"id" : @(fileId)};
	if (video){
		return @{@"@type" : @"inputStoryContentVideo",
				 @"video" : input,
				 @"added_sticker_file_ids" : @[],
				 @"duration" : @0.0,
				 @"cover_frame_timestamp" : @0.0,
				 @"is_animation" : @NO};
	}
	return @{@"@type" : @"inputStoryContentPhoto",
			 @"photo" : input,
			 @"added_sticker_file_ids" : @[]};
}

- (void)addBotMediaPreviewForBot:(int64_t)botUserId
						language:(NSString *)language
						  fileId:(int32_t)fileId
						   video:(BOOL)video
					  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId || fileId <= 0){
		if (completion) completion(nil, @"A bot id and a file id are needed.");
		return;
	}
	[self request:@{@"@type" : @"addBotMediaPreview",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""),
					@"content" : [self botPreviewContentForFile:fileId video:video]}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"date" : TGT3Number(result, @"date"),
						 @"contentType" : TGT3ShortType(result[@"content"][@"@type"])}, nil);
	}];
}

- (void)editBotMediaPreviewForBot:(int64_t)botUserId
						 language:(NSString *)language
						   fileId:(int32_t)fileId
					   newFileId:(int32_t)newFileId
							video:(BOOL)video
					   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId || fileId <= 0 || newFileId <= 0){
		if (completion) completion(nil, @"A bot id and both file ids are needed.");
		return;
	}
	[self request:@{@"@type" : @"editBotMediaPreview",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""),
					@"file_id" : @(fileId),
					@"content" : [self botPreviewContentForFile:newFileId video:video]}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"date" : TGT3Number(result, @"date"),
						 @"contentType" : TGT3ShortType(result[@"content"][@"@type"])}, nil);
	}];
}

- (void)deleteBotMediaPreviewsForBot:(int64_t)botUserId
							language:(NSString *)language
							 fileIds:(NSArray *)fileIds
						  completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !fileIds.count){
		if (completion) completion(NO, @"A bot id and file ids are needed.");
		return;
	}
	[self request:@{@"@type" : @"deleteBotMediaPreviews",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""),
					@"file_ids" : fileIds}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)reorderBotMediaPreviewsForBot:(int64_t)botUserId
							 language:(NSString *)language
							  fileIds:(NSArray *)fileIds
						   completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !fileIds.count){
		if (completion) completion(NO, @"A bot id and file ids are needed.");
		return;
	}
	[self request:@{@"@type" : @"reorderBotMediaPreviews",
					@"bot_user_id" : @(botUserId),
					@"language_code" : (language ?: @""),
					@"file_ids" : fileIds}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)similarBotCountForBot:(int64_t)botUserId
						local:(BOOL)localOnly
				   completion:(void (^)(int32_t, NSString *))completion {
	if (!botUserId){
		if (completion) completion(0, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotSimilarBotCount",
					@"bot_user_id" : @(botUserId),
					@"return_local" : @(localOnly)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(0, TGT3Error(result));
			return;
		}
		if (completion) completion([TGT3Number(result, @"count") intValue], nil);
	}];
}

- (void)similarBotsForBot:(int64_t)botUserId
			   completion:(void (^)(NSArray *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getBotSimilarBots", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *user in result[@"users"]){
			if ([user isKindOfClass:NSDictionary.class])
				[rows addObject:TGT3User(user)];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)openSimilarBot:(int64_t)openedBotId
			   fromBot:(int64_t)botUserId
			completion:(void (^)(BOOL, NSString *))completion {
	if (!openedBotId || !botUserId){
		if (completion) completion(NO, @"Both bot ids are needed.");
		return;
	}
	[self request:@{@"@type" : @"openBotSimilarBot",
					@"bot_user_id" : @(botUserId),
					@"opened_bot_user_id" : @(openedBotId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)setBotCanManageEmojiStatus:(BOOL)allowed
							forBot:(int64_t)botUserId
						completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"toggleBotCanManageEmojiStatus",
					@"bot_user_id" : @(botUserId),
					@"can_manage_emoji_status" : @(allowed)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)setBotVerification:(int64_t)botUserId
			 verifiedKind:(NSString *)kind
				 verifiedId:(int64_t)verifiedId
				description:(NSString *)description
				 completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !verifiedId){
		if (completion) completion(NO, @"A bot id and a verified account id are needed.");
		return;
	}
	NSDictionary *formatted = @{@"@type" : @"formattedText",
								@"text" : (description ?: @""),
								@"entities" : @[]};
	[self request:@{@"@type" : @"setMessageSenderBotVerification",
					@"bot_user_id" : @(botUserId),
					@"verified_id" : TGT3Sender(kind, verifiedId),
					@"custom_description" : formatted}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)removeBotVerification:(int64_t)botUserId
				 verifiedKind:(NSString *)kind
					 verifiedId:(int64_t)verifiedId
				   completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !verifiedId){
		if (completion) completion(NO, @"A bot id and a verified account id are needed.");
		return;
	}
	[self request:@{@"@type" : @"removeMessageSenderBotVerification",
					@"bot_user_id" : @(botUserId),
					@"verified_id" : TGT3Sender(kind, verifiedId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)createBotNamed:(NSString *)name
			  username:(NSString *)username
			  manager:(int64_t)managerBotId
			completion:(void (^)(NSDictionary *, NSString *))completion {
	name = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	username = [username stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!managerBotId || !name.length || !username.length){
		if (completion) completion(nil, @"A manager bot, a name and a username are needed.");
		return;
	}
	[self request:@{@"@type" : @"createBot",
					@"manager_bot_user_id" : @(managerBotId),
					@"name" : name,
					@"username" : username,
					@"via_link" : @NO}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3User(result), nil);
	}];
}

- (void)recentInlineBotsWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getRecentInlineBots"} completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *user in result[@"users"]){
			if ([user isKindOfClass:NSDictionary.class])
				[rows addObject:TGT3User(user)];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)startBot:(int64_t)botUserId
		  inChat:(int64_t)chatId
	   parameter:(NSString *)parameter
	  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId || !chatId){
		if (completion) completion(nil, @"A bot id and a chat id are needed.");
		return;
	}
	[self request:@{@"@type" : @"sendBotStartMessage",
					@"bot_user_id" : @(botUserId),
					@"chat_id" : @(chatId),
					@"parameter" : (parameter ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"id" : TGT3Number(result, @"id"),
						 @"date" : TGT3Number(result, @"date"),
						 @"contentType" : TGT3ShortType(result[@"content"][@"@type"])}, nil);
	}];
}

- (void)attachmentMenuBot:(int64_t)botUserId
			   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getAttachmentMenuBot", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"name" : TGT3String(result, @"name"),
						 @"isAdded" : @([result[@"is_added"] boolValue]),
						 @"requestWriteAccess" : @([result[@"request_write_access"] boolValue]),
						 @"supportsSelfChat" : @([result[@"supports_self_chat"] boolValue]),
						 @"supportsUserChats" : @([result[@"supports_user_chats"] boolValue]),
						 @"supportsBotChats" : @([result[@"supports_bot_chats"] boolValue]),
						 @"supportsGroupChats" : @([result[@"supports_group_chats"] boolValue]),
						 @"supportsChannelChats" : @([result[@"supports_channel_chats"] boolValue])}, nil);
	}];
}

- (void)setBotOnAttachmentMenu:(int64_t)botUserId
					   added:(BOOL)added
			 allowWriteAccess:(BOOL)allowWriteAccess
					completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"toggleBotIsAddedToAttachmentMenu",
					@"bot_user_id" : @(botUserId),
					@"is_added" : @(added),
					@"allow_write_access" : @(allowWriteAccess)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)canBotSendMessages:(int64_t)botUserId
				completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"canBotSendMessages", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)allowBotToSendMessages:(int64_t)botUserId
					completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"allowBotToSendMessages", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)addInlineResultToQuickReply:(NSString *)shortcutName
						 replyToId:(int64_t)replyToMessageId
						   queryId:(int64_t)queryId
						  resultId:(NSString *)resultId
						 hideViaBot:(BOOL)hideViaBot
						completion:(void (^)(NSDictionary *, NSString *))completion {
	shortcutName = [shortcutName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	resultId = [resultId stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!shortcutName.length || !queryId || !resultId.length){
		if (completion) completion(nil, @"A shortcut, a query id and a result id are needed.");
		return;
	}
	[self request:@{@"@type" : @"addQuickReplyShortcutInlineQueryResultMessage",
					@"shortcut_name" : shortcutName,
					@"reply_to_message_id" : @(replyToMessageId),
					@"query_id" : @(queryId),
					@"result_id" : resultId,
					@"hide_via_bot" : @(hideViaBot)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"id" : TGT3Number(result, @"id"),
						 @"contentType" : TGT3ShortType(result[@"content"][@"@type"])}, nil);
	}];
}

#pragma mark - browser settings and Web App links

- (void)setWebBrowserSettingsOpenExternal:(BOOL)openExternal
						displayCloseButton:(BOOL)displayCloseButton
							   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"changeWebBrowserSettings",
					@"open_external_browser" : @(openExternal),
					@"display_close_button" : @(displayCloseButton)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)addWebBrowserException:(NSString *)url
				  openExternal:(BOOL)openExternal
					completion:(void (^)(BOOL, NSString *))completion {
	url = [url stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!url.length){
		if (completion) completion(NO, @"A URL is needed.");
		return;
	}
	[self request:@{@"@type" : @"addWebBrowserSettingsException",
					@"open_external_browser" : @(openExternal),
					@"url" : url}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)removeWebBrowserException:(NSString *)url
					   completion:(void (^)(BOOL, NSString *))completion {
	url = [url stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!url.length){
		if (completion) completion(NO, @"A URL is needed.");
		return;
	}
	[self request:@{@"@type" : @"removeWebBrowserSettingsException", @"url" : url}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)removeAllWebBrowserExceptionsWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"removeAllWebBrowserSettingsExceptions"}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)grossingWebAppBotsOffset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getGrossingWebAppBots",
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSNumber *identifier in result[@"user_ids"]){
			if (![identifier isKindOfClass:NSNumber.class])
				continue;
			int64_t userId = identifier.longLongValue;
			[rows addObject:@{@"id" : @(userId),
							  @"name" : [self nameForUserId:userId] ?: @"Bot"}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)searchWebAppForBot:(int64_t)botUserId
				 shortName:(NSString *)shortName
				completion:(void (^)(NSDictionary *, NSString *))completion {
	shortName = [shortName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!botUserId || !shortName.length){
		if (completion) completion(nil, @"A bot id and a short name are needed.");
		return;
	}
	[self request:@{@"@type" : @"searchWebApp",
					@"bot_user_id" : @(botUserId),
					@"web_app_short_name" : shortName}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *app = result[@"web_app"];
		if (completion)
			completion(@{@"shortName" : TGT3String(app, @"short_name"),
						 @"title" : TGT3String(app, @"title"),
						 @"description" : TGT3String(app, @"description"),
						 @"requestWriteAccess" : @([result[@"request_write_access"] boolValue]),
						 @"skipConfirmation" : @([result[@"skip_confirmation"] boolValue])}, nil);
	}];
}

- (void)webAppPlaceholderForBot:(int64_t)botUserId
					 completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getWebAppPlaceholder", @"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"@type"), nil);
	}];
}

- (void)webAppURLForBot:(int64_t)botUserId
					url:(NSString *)url
				   mode:(NSString *)mode
			 completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getWebAppUrl",
					@"bot_user_id" : @(botUserId),
					@"url" : (url ?: @""),
					@"parameters" : TGT3WebAppParameters(mode)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"url"), nil);
	}];
}

- (void)mainWebAppForBot:(int64_t)botUserId
				  chatId:(int64_t)chatId
		  startParameter:(NSString *)startParameter
					mode:(NSString *)mode
			  completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getMainWebApp",
					@"chat_id" : @(chatId),
					@"bot_user_id" : @(botUserId),
					@"start_parameter" : (startParameter ?: @""),
					@"parameters" : TGT3WebAppParameters(mode)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result[@"url"], @"url"), nil);
	}];
}

- (void)webAppLinkURLForBot:(int64_t)botUserId
					 chatId:(int64_t)chatId
				  shortName:(NSString *)shortName
			 startParameter:(NSString *)startParameter
				 allowWrite:(BOOL)allowWrite
					   mode:(NSString *)mode
				 completion:(void (^)(NSString *, NSString *))completion {
	shortName = [shortName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!botUserId || !shortName.length){
		if (completion) completion(nil, @"A bot id and a short name are needed.");
		return;
	}
	[self request:@{@"@type" : @"getWebAppLinkUrl",
					@"chat_id" : @(chatId),
					@"bot_user_id" : @(botUserId),
					@"web_app_short_name" : shortName,
					@"start_parameter" : (startParameter ?: @""),
					@"allow_write_access" : @(allowWrite),
					@"parameters" : TGT3WebAppParameters(mode)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"url"), nil);
	}];
}

- (void)shareChatWithBot:(int64_t)botUserId
			 sourceChat:(int64_t)sourceChatId
		  sourceMessage:(int64_t)sourceMessageId
			   buttonId:(int32_t)buttonId
			  sharedChat:(int64_t)sharedChatId
				checkOnly:(BOOL)checkOnly
			   completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !sharedChatId){
		if (completion) completion(NO, @"A bot id and a shared chat id are needed.");
		return;
	}
	[self request:@{@"@type" : @"shareChatWithBot",
					@"source" : TGT3ButtonSource(sourceChatId, sourceMessageId),
					@"button_id" : @(buttonId),
					@"shared_chat_id" : @(sharedChatId),
					@"only_check" : @(checkOnly)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)shareUsersWithBot:(int64_t)botUserId
			  sourceChat:(int64_t)sourceChatId
		   sourceMessage:(int64_t)sourceMessageId
				buttonId:(int32_t)buttonId
				 userIds:(NSArray *)userIds
			   checkOnly:(BOOL)checkOnly
			  completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId || !userIds.count){
		if (completion) completion(NO, @"A bot id and user ids are needed.");
		return;
	}
	[self request:@{@"@type" : @"shareUsersWithBot",
					@"source" : TGT3ButtonSource(sourceChatId, sourceMessageId),
					@"button_id" : @(buttonId),
					@"shared_user_ids" : userIds,
					@"only_check" : @(checkOnly)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - OAuth

- (void)oauthLinkInfo:(NSString *)url
			   origin:(NSString *)origin
		   completion:(void (^)(NSDictionary *, NSString *))completion {
	url = [url stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!url.length){
		if (completion) completion(nil, @"A link is needed.");
		return;
	}
	[self request:@{@"@type" : @"getOauthLinkInfo",
					@"url" : url, @"in_app_origin" : (origin ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *matches = [NSMutableArray array];
		for (NSDictionary *match in result[@"match_codes"]){
			[matches addObject:TGT3String(match, @"code")];
		}
		NSArray *codes = result[@"match_codes"];
		if (!matches.count && [codes isKindOfClass:NSArray.class]){
			for (id code in codes){
				if ([code isKindOfClass:NSString.class])
					[matches addObject:code];
			}
		}
		if (completion)
			completion(@{@"botUserId" : TGT3Number(result, @"bot_user_id"),
						 @"botName" : TGT3String(result, @"bot_name"),
						 @"botUsername" : TGT3String(result, @"bot_username"),
						 @"url" : TGT3String(result, @"url"),
						 @"matches" : matches}, nil);
	}];
}

- (void)checkOauthMatchCode:(NSString *)code
					 forURL:(NSString *)url
				  completion:(void (^)(BOOL, NSString *))completion {
	if (!code.length || !url.length){
		if (completion) completion(NO, @"A link and a match code are needed.");
		return;
	}
	[self request:@{@"@type" : @"checkOauthRequestMatchCode",
					@"url" : url, @"match_code" : code}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)acceptOauthRequest:(NSString *)url
				 matchCode:(NSString *)code
			allowWriteAccess:(BOOL)allowWriteAccess
		 allowPhoneNumberAccess:(BOOL)allowPhoneNumberAccess
				completion:(void (^)(NSString *, NSString *))completion {
	if (!url.length || !code.length){
		if (completion) completion(nil, @"A link and a match code are needed.");
		return;
	}
	[self request:@{@"@type" : @"acceptOauthRequest",
					@"url" : url,
					@"match_code" : code,
					@"allow_write_access" : @(allowWriteAccess),
					@"allow_phone_number_access" : @(allowPhoneNumberAccess),
					@"ton_connect_connect_data" : [NSNull null]}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"url"), nil);
	}];
}

- (void)declineOauthRequest:(NSString *)url
				 completion:(void (^)(BOOL, NSString *))completion {
	if (!url.length){
		if (completion) completion(NO, @"A link is needed.");
		return;
	}
	[self request:@{@"@type" : @"declineOauthRequest", @"url" : url}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - business bot

- (void)businessConnectedBotWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getBusinessConnectedBot"}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *bot = result[@"bot"];
		if (completion)
			completion(@{@"botUserId" : TGT3Number(bot, @"bot_user_id"),
						 @"connectionDate" : TGT3Number(result, @"connection_date"),
						 @"deviceModel" : TGT3String(result, @"device_model"),
						 @"location" : TGT3String(result, @"location")}, nil);
	}];
}

- (void)setBusinessConnectedBot:(int64_t)botUserId
					 recipients:(NSDictionary *)recipients
					 completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	NSDictionary *rights = @{
		@"@type" : @"businessBotRights",
		@"can_reply" : @YES, @"can_read_messages" : @YES,
		@"can_delete_sent_messages" : @NO, @"can_delete_all_messages" : @NO,
		@"can_edit_name" : @NO, @"can_edit_bio" : @NO,
		@"can_edit_profile_photo" : @NO, @"can_edit_username" : @NO,
		@"can_view_gifts_and_stars" : @NO, @"can_sell_gifts" : @NO,
		@"can_change_gift_settings" : @NO, @"can_transfer_and_upgrade_gifts" : @NO,
		@"can_transfer_stars" : @NO, @"can_manage_stories" : @NO,
	};
	NSDictionary *selection = @{
		@"@type" : @"businessRecipients",
		@"chat_ids" : @[],
		@"excluded_chat_ids" : @[],
		@"select_existing_chats" : @([recipients[@"existing"] boolValue]),
		@"select_new_chats" : @([recipients[@"new"] boolValue]),
		@"select_contacts" : @([recipients[@"contacts"] boolValue]),
		@"select_non_contacts" : @([recipients[@"nonContacts"] boolValue]),
		@"exclude_selected" : @([recipients[@"excludeSelected"] boolValue]),
	};
	[self request:@{@"@type" : @"setBusinessConnectedBot",
					@"bot" : @{@"@type" : @"businessConnectedBot",
							   @"bot_user_id" : @(botUserId),
							   @"recipients" : selection,
							   @"rights" : rights}}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)deleteBusinessConnectedBot:(int64_t)botUserId
						completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"deleteBusinessConnectedBot",
					@"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)confirmBusinessConnectedBot:(int64_t)botUserId
						 completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot id is needed.");
		return;
	}
	[self request:@{@"@type" : @"confirmBusinessConnectedBot",
					@"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)removeBusinessConnectedBotFromChat:(int64_t)chatId
								completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId){
		if (completion) completion(NO, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"removeBusinessConnectedBotFromChat",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)pauseBusinessConnectedBotInChat:(int64_t)chatId
								 paused:(BOOL)paused
							 completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId){
		if (completion) completion(NO, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"toggleBusinessConnectedBotChatIsPaused",
					@"chat_id" : @(chatId), @"is_paused" : @(paused)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - Premium

- (void)premiumFeaturesFromSource:(NSString *)source
					   completion:(void (^)(NSDictionary *, NSString *))completion {
	NSDictionary *sourceObject = nil;
	if ([source hasPrefix:@"premiumSource"]){
		sourceObject = @{@"@type" : source};
	} else if ([source length]){
		sourceObject = @{@"@type" : @"premiumSourceLink", @"referrer" : source};
	}
	NSMutableDictionary *request = [@{@"@type" : @"getPremiumFeatures"} mutableCopy];
	request[@"source"] = sourceObject ?: [NSNull null];
	[self request:request completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *features = [NSMutableArray array];
		for (NSDictionary *feature in result[@"features"]){
			if ([feature isKindOfClass:NSDictionary.class])
				[features addObject:TGT3ShortType(feature[@"@type"])];
		}
		NSMutableArray *limits = [NSMutableArray array];
		for (NSDictionary *limit in result[@"limits"]){
			if (![limit isKindOfClass:NSDictionary.class])
				continue;
			[limits addObject:@{
				@"type" : TGT3ShortType(limit[@"type"][@"@type"]),
				@"defaultValue" : TGT3Number(limit, @"default_value"),
				@"premiumValue" : TGT3Number(limit, @"premium_value"),
			}];
		}
		if (completion)
			completion(@{@"features" : features,
						 @"limits" : limits,
						 @"paymentLink" : TGT3ShortType(result[@"payment_link"][@"@type"])}, nil);
	}];
}

- (void)viewPremiumFeature:(NSString *)featureType
				completion:(void (^)(BOOL, NSString *))completion {
	featureType = [featureType stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!featureType.length){
		if (completion) completion(NO, @"A Premium feature is needed.");
		return;
	}
	if (![featureType hasPrefix:@"premiumFeature"])
		featureType = TGT3PrefixedType(@"premiumFeature", featureType);
	[self request:@{@"@type" : @"viewPremiumFeature",
					@"feature" : @{@"@type" : featureType}}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)premiumLimitOfType:(NSString *)limitType
				completion:(void (^)(NSDictionary *, NSString *))completion {
	limitType = [limitType stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!limitType.length){
		if (completion) completion(nil, @"A Premium limit type is needed.");
		return;
	}
	if (![limitType hasPrefix:@"premiumLimitType"])
		limitType = TGT3PrefixedType(@"premiumLimitType", limitType);
	[self request:@{@"@type" : @"getPremiumLimit",
					@"limit_type" : @{@"@type" : limitType}}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"type" : TGT3ShortType(result[@"type"][@"@type"]),
						 @"defaultValue" : TGT3Number(result, @"default_value"),
						 @"premiumValue" : TGT3Number(result, @"premium_value")}, nil);
	}];
}

- (void)premiumStickersWithLimit:(int32_t)limit
					  completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getPremiumStickers",
					@"limit" : @(MAX((int32_t)0, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *sticker in result[@"stickers"]){
			if ([sticker isKindOfClass:NSDictionary.class])
				[rows addObject:TGT3Sticker(sticker)];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)premiumStickerExamplesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getPremiumStickerExamples"}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *sticker in result[@"stickers"]){
			if ([sticker isKindOfClass:NSDictionary.class])
				[rows addObject:TGT3Sticker(sticker)];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)premiumInfoStickerForMonths:(int32_t)months
						 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (months <= 0){
		if (completion) completion(nil, @"A month count is needed.");
		return;
	}
	[self request:@{@"@type" : @"getPremiumInfoSticker", @"month_count" : @(months)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3Sticker(result), nil);
	}];
}

- (void)checkPremiumGiftCode:(NSString *)code
				  completion:(void (^)(NSDictionary *, NSString *))completion {
	code = [code stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!code.length){
		if (completion) completion(nil, @"A code is needed.");
		return;
	}
	[self request:@{@"@type" : @"checkPremiumGiftCode", @"code" : code}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"monthCount" : TGT3Number(result, @"month_count"),
						 @"dayCount" : TGT3Number(result, @"day_count"),
						 @"isFromGiveaway" : @([result[@"is_from_giveaway"] boolValue]),
						 @"userId" : TGT3Number(result, @"user_id"),
						 @"useDate" : TGT3Number(result, @"use_date")}, nil);
	}];
}

- (void)applyPremiumGiftCode:(NSString *)code
				  completion:(void (^)(BOOL, NSString *))completion {
	code = [code stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!code.length){
		if (completion) completion(NO, @"A code is needed.");
		return;
	}
	[self request:@{@"@type" : @"applyPremiumGiftCode", @"code" : code}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)clickPremiumSubscriptionButtonWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"clickPremiumSubscriptionButton"}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - boosts

- (void)availableChatBoostSlotsWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getAvailableChatBoostSlots"}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *slot in result[@"slots"]){
			if (![slot isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"slotId" : TGT3Number(slot, @"slot_id"),
				@"currentlyBoostedChatId" : TGT3Number(slot, @"currently_boosted_chat_id"),
				@"startDate" : TGT3Number(slot, @"start_date"),
				@"expirationDate" : TGT3Number(slot, @"expiration_date"),
				@"cooldownUntilDate" : TGT3Number(slot, @"cooldown_until_date"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)chatBoostStatusForChat:(int64_t)chatId
					completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatBoostStatus", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSArray *slots = result[@"applied_slot_ids"];
		if (completion)
			completion(@{@"level" : TGT3Number(result, @"level"),
						 @"boostCount" : TGT3Number(result, @"boost_count"),
						 @"currentLevelBoostCount" : TGT3Number(result, @"current_level_boost_count"),
						 @"nextLevelBoostCount" : TGT3Number(result, @"next_level_boost_count"),
						 @"premiumMemberCount" : TGT3Number(result, @"premium_member_count"),
						 @"boostUrl" : TGT3String(result, @"boost_url"),
						 @"appliedSlotIds" : ([slots isKindOfClass:NSArray.class] ? slots : @[])}, nil);
	}];
}

- (void)chatBoostFeaturesForChannel:(BOOL)isChannel
						 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getChatBoostFeatures", @"is_channel" : @(isChannel)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSArray *features = result[@"features"];
		if (completion)
			completion(@{@"levels" : @([features isKindOfClass:NSArray.class] ? features.count : 0),
						 @"minEmojiStatusBoostLevel" : TGT3Number(result, @"min_emoji_status_boost_level"),
						 @"minCustomBackgroundBoostLevel" : TGT3Number(result, @"min_custom_background_boost_level"),
						 @"minSpeechRecognitionBoostLevel" : TGT3Number(result, @"min_speech_recognition_boost_level"),
						 @"minSponsoredMessageDisableBoostLevel" : TGT3Number(result, @"min_sponsored_message_disable_boost_level")}, nil);
	}];
}

- (void)chatBoostLevelFeaturesForChannel:(BOOL)isChannel
								   level:(int32_t)level
							  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (level < 0){
		if (completion) completion(nil, @"A boost level is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatBoostLevelFeatures",
					@"is_channel" : @(isChannel), @"level" : @(level)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"level" : TGT3Number(result, @"level"),
						 @"storyPerDay" : TGT3Number(result, @"story_per_day_count"),
						 @"customEmojiReactionCount" : TGT3Number(result, @"custom_emoji_reaction_count"),
						 @"canSetEmojiStatus" : @([result[@"can_set_emoji_status"] boolValue]),
						 @"canRecognizeSpeech" : @([result[@"can_recognize_speech"] boolValue]),
						 @"canDisableSponsoredMessages" : @([result[@"can_disable_sponsored_messages"] boolValue])}, nil);
	}];
}

- (void)chatBoostLinkForChat:(int64_t)chatId
				  completion:(void (^)(NSString *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatBoostLink", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"link"), nil);
	}];
}

- (void)chatBoostLinkInfo:(NSString *)url
			   completion:(void (^)(NSDictionary *, NSString *))completion {
	url = [url stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!url.length){
		if (completion) completion(nil, @"A boost link is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatBoostLinkInfo", @"url" : url}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"isPublic" : @([result[@"is_public"] boolValue]),
						 @"chatId" : TGT3Number(result, @"chat_id")}, nil);
	}];
}

- (void)chatBoostsForChat:(int64_t)chatId
				   offset:(NSString *)offset
					limit:(int32_t)limit
			   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatBoosts",
					@"chat_id" : @(chatId),
					@"only_gift_codes" : @NO,
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *boost in result[@"boosts"]){
			if (![boost isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"id" : TGT3String(boost, @"id"),
				@"count" : TGT3Number(boost, @"count"),
				@"startDate" : TGT3Number(boost, @"start_date"),
				@"expirationDate" : TGT3Number(boost, @"expiration_date"),
				@"source" : TGT3ShortType(boost[@"source"][@"@type"]),
			}];
		}
		if (completion)
			completion(@{@"boosts" : rows,
						 @"nextOffset" : TGT3String(result, @"next_offset"),
						 @"totalCount" : TGT3Number(result, @"total_count")}, nil);
	}];
}

- (void)boostChat:(int64_t)chatId
		  slotIds:(NSArray *)slotIds
	   completion:(void (^)(NSArray *, NSString *))completion {
	if (!chatId || !slotIds.count){
		if (completion) completion(nil, @"A chat id and at least one slot id are needed.");
		return;
	}
	[self request:@{@"@type" : @"boostChat",
					@"chat_id" : @(chatId),
					@"slot_ids" : slotIds}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *slot in result[@"slots"]){
			if (![slot isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{@"slotId" : TGT3Number(slot, @"slot_id"),
							  @"currentlyBoostedChatId" : TGT3Number(slot, @"currently_boosted_chat_id")}];
		}
		if (completion) completion(rows, nil);
	}];
}

#pragma mark - revenue

- (void)chatRevenueStatisticsForChat:(int64_t)chatId
							  dark:(BOOL)dark
						  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatRevenueStatistics",
					@"chat_id" : @(chatId), @"is_dark" : @(dark)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"usdRate" : TGT3Number(result, @"usd_rate"),
						 @"totalAmount" : TGT3Number(result[@"revenue_amount"], @"total_amount"),
						 @"balanceAmount" : TGT3Number(result[@"revenue_amount"], @"balance_amount"),
						 @"availableAmount" : TGT3Number(result[@"revenue_amount"], @"available_amount"),
						 @"withdrawalEnabled" : @([result[@"revenue_amount"][@"withdrawal_enabled"] boolValue]),
						 @"graph" : TGT3String(result[@"revenue_graph"], @"@type")}, nil);
	}];
}

- (void)chatRevenueTransactionsForChat:(int64_t)chatId
								offset:(NSString *)offset
								 limit:(int32_t)limit
							completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatRevenueTransactions",
					@"chat_id" : @(chatId),
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *transaction in result[@"transactions"]){
			if (![transaction isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"currency" : TGT3String(transaction, @"cryptocurrency"),
				@"amount" : TGT3Number(transaction, @"cryptocurrency_amount"),
				@"type" : TGT3ShortType(transaction[@"type"][@"@type"]),
			}];
		}
		if (completion)
			completion(@{@"transactions" : rows,
						 @"nextOffset" : TGT3String(result, @"next_offset"),
						 @"gramAmount" : TGT3Number(result, @"gram_amount")}, nil);
	}];
}

- (void)starRevenueStatisticsForOwner:(NSString *)ownerKind
							  ownerId:(int64_t)ownerId
								 dark:(BOOL)dark
						   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!ownerId){
		if (completion) completion(nil, @"An owner id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getStarRevenueStatistics",
					@"owner_id" : TGT3Sender(ownerKind, ownerId),
					@"is_dark" : @(dark)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *status = result[@"status"];
		if (completion)
			completion(@{@"total" : TGT3Number(status[@"total_amount"], @"star_count"),
						 @"current" : TGT3Number(status[@"current_amount"], @"star_count"),
						 @"available" : TGT3Number(status[@"available_amount"], @"star_count"),
						 @"withdrawalEnabled" : @([status[@"withdrawal_enabled"] boolValue]),
						 @"nextWithdrawalIn" : TGT3Number(status, @"next_withdrawal_in"),
						 @"graph" : TGT3String(result[@"revenue_by_day_graph"], @"@type")}, nil);
	}];
}

- (void)gramRevenueStatisticsWithDark:(BOOL)dark
						   completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getGramRevenueStatistics", @"is_dark" : @(dark)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *status = result[@"status"];
		if (completion)
			completion(@{@"total" : TGT3Number(status, @"total_amount"),
						 @"balance" : TGT3Number(status, @"balance_amount"),
						 @"available" : TGT3Number(status, @"available_amount"),
						 @"withdrawalEnabled" : @([status[@"withdrawal_enabled"] boolValue]),
						 @"graph" : TGT3String(result[@"revenue_by_day_graph"], @"@type")}, nil);
	}];
}

- (void)paidMessageRevenueForUser:(int64_t)userId
					   completion:(void (^)(int64_t, NSString *))completion {
	if (!userId){
		if (completion) completion(0, @"A user id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getPaidMessageRevenue", @"user_id" : @(userId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(0, TGT3Error(result));
			return;
		}
		if (completion) completion([TGT3Number(result, @"star_count") longLongValue], nil);
	}];
}

- (void)directMessagesChatTopicRevenueForChat:(int64_t)chatId
										topic:(int64_t)topicId
								   completion:(void (^)(int64_t, NSString *))completion {
	if (!chatId || !topicId){
		if (completion) completion(0, @"A chat id and a topic id are needed.");
		return;
	}
	[self request:@{@"@type" : @"getDirectMessagesChatTopicRevenue",
					@"chat_id" : @(chatId), @"topic_id" : @(topicId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(0, TGT3Error(result));
			return;
		}
		if (completion) completion([TGT3Number(result, @"star_count") longLongValue], nil);
	}];
}

/// The balance itself has no screen asking for it today, so it is only kept
/// here for the getter. The two revenue updates do have a screen: the Stars
/// page re-reads the statistics it already asked for when it hears them.
- (void)applyOwnedStarCountUpdate:(NSDictionary *)update {
	self.ownedStarCountValue = [update[@"star_count"] longLongValue];
}

- (int64_t)ownedStarCount {
	return self.ownedStarCountValue;
}

- (void)applyChatRevenueAmountUpdate:(NSDictionary *)update {
	NSNumber *chatId = update[@"chat_id"];
	if (!chatId)
		return;
	NSDictionary *amount = [update[@"revenue_amount"] isKindOfClass:NSDictionary.class]
			? update[@"revenue_amount"] : @{};
	if (!self.chatRevenueAmountByChat)
		self.chatRevenueAmountByChat = [NSMutableDictionary dictionary];
	self.chatRevenueAmountByChat[chatId] = amount;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGChatRevenueChangedNotification object:self
						userInfo:@{@"chatId" : chatId}];
}

- (NSDictionary *)chatRevenueAmountForChat:(int64_t)chatId {
	return self.chatRevenueAmountByChat[@(chatId)];
}

- (void)applyStarRevenueStatusUpdate:(NSDictionary *)update {
	NSDictionary *owner = [update[@"owner_id"] isKindOfClass:NSDictionary.class]
			? update[@"owner_id"] : nil;
	if (!owner)
		return;
	BOOL isChat = [owner[@"@type"] isEqualToString:@"messageSenderChat"];
	NSString *kind = isChat ? @"chat" : @"user";
	int64_t ownerId = isChat ? [owner[@"chat_id"] longLongValue]
			: [owner[@"user_id"] longLongValue];
	if (!ownerId)
		return;
	NSDictionary *status = [update[@"status"] isKindOfClass:NSDictionary.class]
			? update[@"status"] : @{};
	if (!self.starRevenueStatusByOwner)
		self.starRevenueStatusByOwner = [NSMutableDictionary dictionary];
	self.starRevenueStatusByOwner[[NSString stringWithFormat:@"%@:%lld", kind, ownerId]]
			= status;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGStarRevenueChangedNotification object:self
						userInfo:@{@"ownerKind" : kind, @"ownerId" : @(ownerId)}];
}

- (NSDictionary *)starRevenueStatusForOwner:(NSString *)ownerKind
									ownerId:(int64_t)ownerId {
	NSString *kind = [ownerKind isEqualToString:@"chat"] ? @"chat" : @"user";
	return self.starRevenueStatusByOwner[
			[NSString stringWithFormat:@"%@:%lld", kind, ownerId]];
}

#pragma mark - discovery

- (void)allowUnpaidMessagesFromUser:(int64_t)userId
							 refund:(BOOL)refund
						 completion:(void (^)(BOOL, NSString *))completion {
	if (!userId){
		if (completion) completion(NO, @"A user id is needed.");
		return;
	}
	[self request:@{@"@type" : @"allowUnpaidMessagesFromUser",
					@"user_id" : @(userId), @"refund_payments" : @(refund)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)applyUnpaidMessagesToken:(NSString *)token
						  forUser:(int64_t)userId
					   completion:(void (^)(BOOL, NSString *))completion {
	token = [token stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!userId || !token.length){
		if (completion) completion(NO, @"A user id and a token are needed.");
		return;
	}
	[self request:@{@"@type" : @"applyUnpaidMessagesToken",
					@"user_id" : @(userId), @"token" : token}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)paidReactionSendersForChat:(int64_t)chatId
						completion:(void (^)(NSArray *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"A chat id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getChatAvailablePaidMessageReactionSenders",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *sender in result[@"senders"]){
			if (![sender isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *identifier = sender[@"user_id"] ?: sender[@"chat_id"];
			[rows addObject:@{@"kind" : TGT3ShortType(sender[@"@type"]),
							  @"id" : identifier ?: @0}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)setChatPaidMessageStarCount:(int64_t)chatId
							  count:(int32_t)starCount
						 completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || starCount < 0){
		if (completion) completion(NO, @"A chat id and a non-negative price are needed.");
		return;
	}
	[self request:@{@"@type" : @"setChatPaidMessageStarCount",
					@"chat_id" : @(chatId),
					@"paid_message_star_count" : @(starCount)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)setGroupCallPaidMessageStarCount:(int32_t)groupCallId
								   count:(int32_t)starCount
							  completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId || starCount < 0){
		if (completion) completion(NO, @"A call id and a non-negative price are needed.");
		return;
	}
	[self request:@{@"@type" : @"setGroupCallPaidMessageStarCount",
					@"group_call_id" : @(groupCallId),
					@"paid_message_star_count" : @(starCount)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)setDirectMessagesTopicUnpaid:(int64_t)chatId
							   topic:(int64_t)topicId
							 allowed:(BOOL)allowed
							  refund:(BOOL)refund
						  completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !topicId){
		if (completion) completion(NO, @"A chat id and a topic id are needed.");
		return;
	}
	[self request:@{@"@type" : @"toggleDirectMessagesChatTopicCanSendUnpaidMessages",
					@"chat_id" : @(chatId),
					@"topic_id" : @(topicId),
					@"can_send_unpaid_messages" : @(allowed),
					@"refund_payments" : @(refund)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)paymentReceiptForChat:(int64_t)chatId
					  message:(int64_t)messageId
				   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(nil, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"getPaymentReceipt",
					@"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *product = result[@"product_info"];
		NSDictionary *type = result[@"type"];
		if (completion)
			completion(@{@"kind" : TGT3ShortType(type[@"@type"]),
						 @"title" : TGT3String(product, @"title"),
						 @"description" : TGT3String(product, @"description"),
						 @"date" : TGT3Number(result, @"date"),
						 @"starCount" : TGT3Number(type, @"star_count"),
						 @"transactionId" : TGT3String(type, @"transaction_id"),
						 @"credentialsTitle" : TGT3String(type, @"credentials_title")}, nil);
	}];
}

- (void)starAdAccountURLForOwner:(NSString *)ownerKind
						 ownerId:(int64_t)ownerId
					  completion:(void (^)(NSString *, NSString *))completion {
	if (!ownerId){
		if (completion) completion(nil, @"An owner id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getStarAdAccountUrl",
					@"owner_id" : TGT3Sender(ownerKind, ownerId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(TGT3String(result, @"url"), nil);
	}];
}

- (void)setSupergroupUnrestrictBoostCount:(int32_t)count
							  supergroupId:(int64_t)supergroupId
							   completion:(void (^)(BOOL, NSString *))completion {
	if (!supergroupId || count < 0 || count > 8){
		if (completion) completion(NO, @"A supergroup id and a count from 0 to 8 are needed.");
		return;
	}
	[self request:@{@"@type" : @"setSupergroupUnrestrictBoostCount",
					@"supergroup_id" : @(supergroupId),
					@"unrestrict_boost_count" : @(count)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)giveawayInfoForChat:(int64_t)chatId
					message:(int64_t)messageId
				 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(nil, @"A chat id and a message id are needed.");
		return;
	}
	[self request:@{@"@type" : @"getGiveawayInfo",
					@"chat_id" : @(chatId), @"message_id" : @(messageId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"kind" : TGT3ShortType(result[@"@type"]),
						 @"creationDate" : TGT3Number(result, @"creation_date"),
						 @"isEnded" : @([result[@"is_ended"] boolValue]),
						 @"isWinner" : @([result[@"is_winner"] boolValue]),
						 @"winnerCount" : TGT3Number(result, @"winner_count"),
						 @"wonStarCount" : TGT3Number(result, @"won_star_count"),
						 @"giftCode" : TGT3String(result, @"gift_code")}, nil);
	}];
}

- (void)collectibleItemInfoForKind:(NSString *)kind
							 value:(NSString *)value
						completion:(void (^)(NSDictionary *, NSString *))completion {
	value = [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!value.length){
		if (completion) completion(nil, @"The username or phone number is needed.");
		return;
	}
	NSDictionary *type = nil;
	if ([kind isEqualToString:@"phoneNumber"]){
		type = @{@"@type" : @"collectibleItemTypePhoneNumber",
				 @"phone_number" : value};
	} else {
		type = @{@"@type" : @"collectibleItemTypeUsername", @"username" : value};
	}
	[self request:@{@"@type" : @"getCollectibleItemInfo", @"type" : type}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"purchaseDate" : TGT3Number(result, @"purchase_date"),
						 @"currency" : TGT3String(result, @"currency"),
						 @"amount" : TGT3Number(result, @"amount"),
						 @"cryptocurrency" : TGT3String(result, @"cryptocurrency"),
						 @"cryptocurrencyAmount" : TGT3Number(result, @"cryptocurrency_amount"),
						 @"url" : TGT3String(result, @"url")}, nil);
	}];
}

#pragma mark - Stars

- (void)starTransactionsForOwner:(NSString *)ownerKind
						 ownerId:(int64_t)ownerId
					 direction:(NSString *)direction
						offset:(NSString *)offset
						 limit:(int32_t)limit
					completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!ownerId){
		if (completion) completion(nil, @"An owner id is needed.");
		return;
	}
	NSDictionary *directionObject = nil;
	if ([direction isEqualToString:@"incoming"])
		directionObject = @{@"@type" : @"transactionDirectionIncoming"};
	else if ([direction isEqualToString:@"outgoing"])
		directionObject = @{@"@type" : @"transactionDirectionOutgoing"};
	[self request:@{@"@type" : @"getStarTransactions",
					@"owner_id" : TGT3Sender(ownerKind, ownerId),
					@"subscription_id" : @"",
					@"direction" : directionObject ?: [NSNull null],
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *transaction in result[@"transactions"]){
			if (![transaction isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"id" : TGT3String(transaction, @"id"),
				@"date" : TGT3Number(transaction, @"date"),
				@"starCount" : TGT3Number(transaction[@"star_amount"], @"star_count"),
				@"isRefund" : @([transaction[@"is_refund"] boolValue]),
				@"type" : TGT3ShortType(transaction[@"type"][@"@type"]),
			}];
		}
		if (completion)
			completion(@{@"transactions" : rows,
						 @"nextOffset" : TGT3String(result, @"next_offset"),
						 @"starCount" : TGT3Number(result[@"star_amount"], @"star_count")}, nil);
	}];
}

- (void)starSubscriptionsOnlyExpiring:(BOOL)onlyExpiring
							   offset:(NSString *)offset
						   completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getStarSubscriptions",
					@"only_expiring" : @(onlyExpiring),
					@"offset" : (offset ?: @"")}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *subscription in result[@"subscriptions"]){
			if (![subscription isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"id" : TGT3String(subscription, @"id"),
				@"chatId" : TGT3Number(subscription, @"chat_id"),
				@"expirationDate" : TGT3Number(subscription, @"expiration_date"),
				@"isCanceled" : @([subscription[@"is_canceled"] boolValue]),
				@"isExpiring" : @([subscription[@"is_expiring"] boolValue]),
				@"period" : TGT3Number(subscription[@"pricing"], @"period"),
				@"starCount" : TGT3Number(subscription[@"pricing"], @"star_count"),
				@"type" : TGT3ShortType(subscription[@"type"][@"@type"]),
			}];
		}
		if (completion)
			completion(@{@"subscriptions" : rows,
						 @"nextOffset" : TGT3String(result, @"next_offset"),
						 @"starCount" : TGT3Number(result[@"star_amount"], @"star_count"),
						 @"requiredStarCount" : TGT3Number(result, @"required_star_count")}, nil);
	}];
}

- (void)setStarSubscription:(NSString *)subscriptionId
				   canceled:(BOOL)canceled
				 completion:(void (^)(BOOL, NSString *))completion {
	if (!subscriptionId.length){
		if (completion) completion(NO, @"A subscription id is needed.");
		return;
	}
	[self request:@{@"@type" : @"editStarSubscription",
					@"subscription_id" : subscriptionId,
					@"is_canceled" : @(canceled)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)reuseStarSubscription:(NSString *)subscriptionId
				   completion:(void (^)(BOOL, NSString *))completion {
	if (!subscriptionId.length){
		if (completion) completion(NO, @"A subscription id is needed.");
		return;
	}
	[self request:@{@"@type" : @"reuseStarSubscription",
					@"subscription_id" : subscriptionId}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

#pragma mark - gifts

- (void)availableGiftsWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getAvailableGifts"} completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *available in result[@"gifts"]){
			if (![available isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *gift = available[@"gift"];
			[rows addObject:@{
				@"id" : TGT3Number(gift, @"id"),
				@"title" : TGT3String(available, @"title"),
				@"starCount" : TGT3Number(gift, @"star_count"),
				@"resaleCount" : TGT3Number(available, @"resale_count"),
				@"minResaleStarCount" : TGT3Number(available, @"min_resale_star_count"),
				@"emoji" : TGT3String(gift[@"sticker"], @"emoji"),
				@"isPremium" : @([gift[@"is_premium"] boolValue]),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)canSendGift:(int64_t)giftId
		 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!giftId){
		if (completion) completion(nil, @"A gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"canSendGift", @"gift_id" : @(giftId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSString *word = TGT3ShortType(result[@"@type"]);
		NSString *reason = TGT3String(result[@"reason"], @"text");
		if (completion)
			completion(@{@"type" : word, @"reason" : reason}, nil);
	}];
}

- (void)receivedGift:(NSString *)receivedGiftId
		  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!receivedGiftId.length){
		if (completion) completion(nil, @"A received gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getReceivedGift",
					@"received_gift_id" : receivedGiftId}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *gift = result[@"gift"];
		if (completion)
			completion(@{@"receivedGiftId" : TGT3String(result, @"received_gift_id"),
						 @"date" : TGT3Number(result, @"date"),
						 @"isSaved" : @([result[@"is_saved"] boolValue]),
						 @"isPinned" : @([result[@"is_pinned"] boolValue]),
						 @"canBeUpgraded" : @([result[@"can_be_upgraded"] boolValue]),
						 @"canBeTransferred" : @([result[@"can_be_transferred"] boolValue]),
						 @"canBeDeleted" : @([result[@"can_be_deleted"] boolValue]),
						 @"starCount" : TGT3Number(gift, @"star_count"),
						 @"emoji" : TGT3String(gift[@"sticker"], @"emoji"),
						 @"text" : TGT3String(result[@"text"], @"text")}, nil);
	}];
}

- (void)upgradedGiftNamed:(NSString *)name
			   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!name.length){
		if (completion) completion(nil, @"A gift name is needed.");
		return;
	}
	[self request:@{@"@type" : @"getUpgradedGift", @"name" : name}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"name" : TGT3String(result, @"name"),
						 @"title" : TGT3String(result, @"title"),
						 @"number" : TGT3Number(result, @"number"),
						 @"isPremium" : @([result[@"is_premium"] boolValue]),
						 @"model" : TGT3String(result[@"model"], @"name"),
						 @"symbol" : TGT3String(result[@"symbol"], @"name"),
						 @"valueCurrency" : TGT3String(result, @"value_currency"),
						 @"valueAmount" : TGT3Number(result, @"value_amount"),
						 @"valueUsdAmount" : TGT3Number(result, @"value_usd_amount")}, nil);
	}];
}

- (void)upgradedGiftValueInfoNamed:(NSString *)name
						completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!name.length){
		if (completion) completion(nil, @"A gift name is needed.");
		return;
	}
	[self request:@{@"@type" : @"getUpgradedGiftValueInfo", @"name" : name}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion)
			completion(@{@"currency" : TGT3String(result, @"currency"),
						 @"value" : TGT3Number(result, @"value"),
						 @"isValueAverage" : @([result[@"is_value_average"] boolValue]),
						 @"minimumPrice" : TGT3Number(result, @"minimum_price"),
						 @"averageSalePrice" : TGT3Number(result, @"average_sale_price"),
						 @"fragmentUrl" : TGT3String(result, @"fragment_url")}, nil);
	}];
}

- (void)upgradedGiftVariantsForGift:(int64_t)regularGiftId
					   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!regularGiftId){
		if (completion) completion(nil, @"A regular gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getUpgradedGiftVariants",
					@"regular_gift_id" : @(regularGiftId),
					@"return_upgrade_models" : @YES,
					@"return_craft_models" : @YES}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSArray *models = result[@"models"];
		NSArray *symbols = result[@"symbols"];
		NSArray *backdrops = result[@"backdrops"];
		if (completion)
			completion(@{@"models" : ([models isKindOfClass:NSArray.class] ? models : @[]),
						 @"symbols" : ([symbols isKindOfClass:NSArray.class] ? symbols : @[]),
						 @"backdrops" : ([backdrops isKindOfClass:NSArray.class] ? backdrops : @[])}, nil);
	}];
}

- (void)giftUpgradePreviewForGift:(int64_t)regularGiftId
					   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!regularGiftId){
		if (completion) completion(nil, @"A regular gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getGiftUpgradePreview",
					@"regular_gift_id" : @(regularGiftId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSArray *models = result[@"models"];
		NSArray *symbols = result[@"symbols"];
		NSArray *backdrops = result[@"backdrops"];
		NSArray *prices = result[@"prices"];
		if (completion)
			completion(@{@"models" : ([models isKindOfClass:NSArray.class] ? models : @[]),
						 @"symbols" : ([symbols isKindOfClass:NSArray.class] ? symbols : @[]),
						 @"backdrops" : ([backdrops isKindOfClass:NSArray.class] ? backdrops : @[]),
						 @"prices" : ([prices isKindOfClass:NSArray.class] ? prices : @[])}, nil);
	}];
}

- (void)giftCollectionsForOwner:(NSString *)ownerKind
						ownerId:(int64_t)ownerId
					 completion:(void (^)(NSArray *, NSString *))completion {
	if (!ownerId){
		if (completion) completion(nil, @"An owner id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getGiftCollections",
					@"owner_id" : TGT3Sender(ownerKind, ownerId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *collection in result[@"collections"]){
			if (![collection isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"id" : TGT3Number(collection, @"id"),
				@"name" : TGT3String(collection, @"name"),
				@"giftCount" : TGT3Number(collection, @"gift_count"),
				@"emoji" : TGT3String(collection[@"icon"], @"emoji"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)giftsForCraftingFromGift:(int64_t)regularGiftId
						  offset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *, NSString *))completion {
	if (!regularGiftId){
		if (completion) completion(nil, @"A regular gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getGiftsForCrafting",
					@"regular_gift_id" : @(regularGiftId),
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *gift in result[@"gifts"]){
			if ([gift isKindOfClass:NSDictionary.class])
				[rows addObject:@{@"receivedGiftId" : TGT3String(gift, @"received_gift_id"),
								  @"date" : TGT3Number(gift, @"date")}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)searchGiftsForResaleFromGift:(int64_t)regularGiftId
							   order:(NSString *)order
						  offset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *, NSString *))completion {
	if (!regularGiftId){
		if (completion) completion(nil, @"A regular gift id is needed.");
		return;
	}
	NSString *orderType = [order hasPrefix:@"giftForResaleOrder"]
			? order : @"giftForResaleOrderPrice";
	[self request:@{@"@type" : @"searchGiftsForResale",
					@"gift_id" : @(regularGiftId),
					@"order" : @{@"@type" : orderType},
					@"for_crafting" : @NO,
					@"for_stars" : @YES,
					@"attributes" : @[],
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *row in result[@"gifts"]){
			if (![row isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *gift = row[@"gift"];
			[rows addObject:@{
				@"receivedGiftId" : TGT3String(row, @"received_gift_id"),
				@"name" : TGT3String(gift, @"name"),
				@"title" : TGT3String(gift, @"title"),
				@"number" : TGT3Number(gift, @"number"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)upgradedGiftEmojiStatusesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getUpgradedGiftEmojiStatuses"}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *status in result[@"emoji_statuses"]){
			if (![status isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *type = status[@"type"];
			[rows addObject:@{
				@"type" : TGT3ShortType(type[@"@type"]),
				@"expirationDate" : TGT3Number(status, @"expiration_date"),
				@"giftTitle" : TGT3String(type, @"gift_title"),
				@"giftName" : TGT3String(type, @"gift_name"),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)giftChatThemesWithOffset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getGiftChatThemes",
					@"offset" : (offset ?: @""),
					@"limit" : @(MAX((int32_t)1, MIN(limit, (int32_t)100)))}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *theme in result[@"themes"]){
			if (![theme isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{@"giftName" : TGT3String(theme[@"gift"], @"name"),
							  @"giftTitle" : TGT3String(theme[@"gift"], @"title")}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)giftAuctionStateForAuction:(NSString *)auctionId
						completion:(void (^)(NSDictionary *, NSString *))completion {
	auctionId = [auctionId stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!auctionId.length){
		if (completion) completion(nil, @"An auction id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getGiftAuctionState", @"auction_id" : auctionId}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSDictionary *state = result[@"state"];
		if (completion)
			completion(@{@"state" : TGT3ShortType(state[@"@type"]),
						 @"startDate" : TGT3Number(state, @"start_date"),
						 @"endDate" : TGT3Number(state, @"end_date"),
						 @"minBid" : TGT3Number(state, @"min_bid"),
						 @"currentRoundEndDate" : TGT3Number(state, @"current_round_end_date"),
						 @"currentRoundNumber" : TGT3Number(state, @"current_round_number"),
						 @"totalRoundCount" : TGT3Number(state, @"total_round_count"),
						 @"leftItemCount" : TGT3Number(state, @"left_item_count"),
						 @"giftTitle" : TGT3String(result[@"gift"], @"title")}, nil);
	}];
}

- (void)giftAuctionAcquiredGiftsForGift:(int64_t)giftId
							 completion:(void (^)(NSArray *, NSString *))completion {
	if (!giftId){
		if (completion) completion(nil, @"A gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getGiftAuctionAcquiredGifts", @"gift_id" : @(giftId)}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *gift in result[@"gifts"]){
			if (![gift isKindOfClass:NSDictionary.class])
				continue;
			[rows addObject:@{
				@"date" : TGT3Number(gift, @"date"),
				@"starCount" : TGT3Number(gift, @"star_count"),
				@"roundNumber" : TGT3Number(gift, @"auction_round_number"),
				@"uniqueGiftNumber" : TGT3Number(gift, @"unique_gift_number"),
				@"receiverKind" : TGT3ShortType(gift[@"receiver_id"][@"@type"]),
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)openGiftAuctionForGift:(int64_t)giftId
					completion:(void (^)(BOOL, NSString *))completion {
	if (!giftId){
		if (completion) completion(NO, @"A gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"openGiftAuction", @"gift_id" : @(giftId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}

- (void)closeGiftAuctionForGift:(int64_t)giftId
					 completion:(void (^)(BOOL, NSString *))completion {
	if (!giftId){
		if (completion) completion(NO, @"A gift id is needed.");
		return;
	}
	[self request:@{@"@type" : @"closeGiftAuction", @"gift_id" : @(giftId)}
	   completion:^(NSDictionary *result){
		BOOL failed = TGT3Failed(result);
		if (completion) completion(!failed, failed ? TGT3Error(result) : nil);
	}];
}
- (void)upgradedGiftsPromotionalAnimationWithCompletion:
		(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getUpgradedGiftsPromotionalAnimation"}
	   completion:^(NSDictionary *result){
		if (TGT3Failed(result)){
			if (completion) completion(nil, TGT3Error(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

@end

// vim:ft=objc
