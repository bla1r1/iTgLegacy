//
// TGClient+BotSession.m - the wire behind TGClient+BotSession.h.
//
// Every method names its td_api function literally so the coverage script
// sees it and scripts/tdlib_wired.py can prove a screen calls the method.
// Blocks are handed the server's answer; where Telegram refuses a user
// session, that refusal is the completion's error and the screen shows it.
//
#import "TGClient+BotSession.h"
#import "TGClientInternal.h"

#pragma mark - shared helpers

static NSDictionary *TGBSDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *TGBSArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGBSString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSNumber *TGBSNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

static NSString *TGBSErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] && message.length
			? message : @"Telegram refused that.";
}

static BOOL TGBSFailed(NSDictionary *result) {
	return [result[@"@type"] isEqualToString:@"error"];
}

/// botCommandScope as the TDLib object. This client only offers the default
/// scope and one chat's scope; the other two need a user id that a console
/// field would only guess at.
static NSDictionary *TGBSCommandScope(NSString *scope, int64_t chatId) {
	if ([scope isEqualToString:@"chat"])
		return @{@"@type" : @"botCommandScopeChat", @"chat_id" : @(chatId)};
	return @{@"@type" : @"botCommandScopeDefault"};
}

static NSDictionary *TGBSBotCommand(id value) {
	if ([value isKindOfClass:NSString.class]){
		NSString *command = TGBSString(value);
		return @{@"@type" : @"botCommand",
				 @"command" : command,
				 @"description" : command,
				 @"is_ephemeral" : @NO};
	}
	NSDictionary *row = TGBSDict(value);
	return @{@"@type" : @"botCommand",
			 @"command" : TGBSString(row[@"command"]),
			 @"description" : TGBSString(row[@"description"]),
			 @"is_ephemeral" : @([row[@"ephemeral"] boolValue])};
}

static NSDictionary *TGBSPasskey(NSDictionary *passkey) {
	return @{
		@"id"        : TGBSString(passkey[@"id"]),
		@"name"      : TGBSString(passkey[@"name"]),
		@"additionDate"    : TGBSNumber(passkey[@"addition_date"]),
		@"lastUsageDate"   : TGBSNumber(passkey[@"last_usage_date"]),
		@"softwareIconCustomEmojiId" :
				TGBSNumber(passkey[@"software_icon_custom_emoji_id"]),
	};
}

/// Every answer* call that carries an inline result wants one
/// InputInlineQueryResult. This is the article shape: an id, a title, an
/// optional URL and a one-line text message. The thumbnail is left empty
/// because this client has no file to upload for a diagnostic answer.
static NSDictionary *TGBSInlineResult(NSString *resultId, NSString *title,
									  NSString *url) {
	return @{
		@"@type" : @"inputInlineQueryResultArticle",
		@"id" : resultId.length ? resultId : @"1",
		@"url" : url ?: @"",
		@"title" : title.length ? title : @"LegacyTG",
		@"description" : @"Sent from the LegacyTG Bot Console",
		@"thumbnail_url" : @"",
		@"thumbnail_width" : @0,
		@"thumbnail_height" : @0,
		@"reply_markup" : @{
			@"@type" : @"replyMarkupInlineKeyboard",
			@"rows" : @[],
			@"force_reply" : @NO,
		},
		@"input_message_content" : @{
			@"@type" : @"inputMessageText",
			@"text" : TGFormattedText(title.length ? title : @"LegacyTG"),
			@"link_preview_options" : @{
				@"@type" : @"linkPreviewOptions",
				@"is_disabled" : @YES,
				@"url" : @"",
				@"force_small_media" : @NO,
				@"force_large_media" : @NO,
				@"show_above_text" : @NO,
			},
			@"clear_draft" : @NO,
		},
	};
}

/// webAppOpenParameters, shared by the three calls that take one. The theme
/// is the fixed set Telegram documents; none of this is drawn because the
/// build has no WebView host.
static NSDictionary *TGBSWebAppParameters(NSString *mode) {
	NSString *openMode = @"webAppOpenModeCompact";
	if ([mode isEqualToString:@"fullSize"])
		openMode = @"webAppOpenModeFullSize";
	else if ([mode isEqualToString:@"fullScreen"])
		openMode = @"webAppOpenModeFullScreen";
	return @{@"@type" : @"webAppOpenParameters",
			 @"theme" : @{
				 @"@type" : @"themeParameters",
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
				 @"button_text_color" : @((int32_t)0xffffffff),
			 },
			 @"application_name" : @"LegacyTG",
			 @"mode" : @{@"@type" : openMode}};
}

@implementation TGClient (BotSession)

#pragma mark - session and passkeys

- (void)checkAuthenticationBotToken:(NSString *)token
						 completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [token stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion) completion(NO, @"A bot token is needed.");
		return;
	}
	[self request:@{@"@type" : @"checkAuthenticationBotToken", @"token" : clean}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)passkeyParametersWithCompletion:(void (^)(NSString *, NSString *))completion {
	[self request:@{@"@type" : @"getPasskeyParameters"}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"text"]), nil);
	}];
}

- (void)authenticationPasskeyParametersWithCompletion:
		(void (^)(NSString *, NSString *))completion {
	[self request:@{@"@type" : @"getAuthenticationPasskeyParameters"}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"text"]), nil);
	}];
}

- (void)loginPasskeysWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getLoginPasskeys"}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *passkey in TGBSArray(result[@"passkeys"]))
			[rows addObject:TGBSPasskey(TGBSDict(passkey))];
		if (completion) completion(rows, nil);
	}];
}

- (void)addLoginPasskey:(NSString *)clientData
	  attestationObject:(NSString *)attestationObject
			 completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *data = TGBSString(clientData);
	NSString *attestation = TGBSString(attestationObject);
	if (!data.length || !attestation.length){
		if (completion) completion(nil, @"Client data and an attestation object are needed.");
		return;
	}
	[self request:@{@"@type" : @"addLoginPasskey",
					@"client_data" : data,
					@"attestation_object" : attestation}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSPasskey(result), nil);
	}];
}

- (void)removeLoginPasskey:(NSString *)passkeyId
				completion:(void (^)(BOOL, NSString *))completion {
	NSString *identifier = TGBSString(passkeyId);
	if (!identifier.length){
		if (completion) completion(NO, @"A passkey id is needed.");
		return;
	}
	[self request:@{@"@type" : @"removeLoginPasskey", @"passkey_id" : identifier}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)checkAuthenticationPasskey:(NSString *)credentialId
						clientData:(NSString *)clientData
				   authenticatorData:(NSString *)authenticatorData
						   signature:(NSString *)signature
						userHandle:(NSString *)userHandle
						completion:(void (^)(BOOL, NSString *))completion {
	NSString *credential = TGBSString(credentialId);
	if (!credential.length){
		if (completion) completion(NO, @"A credential id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"checkAuthenticationPasskey",
		@"credential_id" : credential,
		@"client_data" : TGBSString(clientData),
		@"authenticator_data" : TGBSString(authenticatorData),
		@"signature" : TGBSString(signature),
		@"user_handle" : TGBSString(userHandle),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

#pragma mark - commands and menu button

- (void)commandsForScope:(NSString *)scope
				  chatId:(int64_t)chatId
				language:(NSString *)language
			  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"getCommands",
		@"scope" : TGBSCommandScope(scope, chatId),
		@"language_code" : TGBSString(language),
	} completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		NSMutableArray *commands = [NSMutableArray array];
		for (NSDictionary *command in TGBSArray(result[@"commands"])){
			if (![command isKindOfClass:NSDictionary.class])
				continue;
			[commands addObject:@{
				@"command" : TGBSString(command[@"command"]),
				@"description" : TGBSString(command[@"description"]),
				@"ephemeral" : @([command[@"is_ephemeral"] boolValue]),
			}];
		}
		NSDictionary *answer = @{
			@"botUserId" : TGBSNumber(result[@"bot_user_id"]),
			@"commands" : commands,
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)setCommands:(NSArray *)commands
			  scope:(NSString *)scope
			 chatId:(int64_t)chatId
		   language:(NSString *)language
		 completion:(void (^)(BOOL, NSString *))completion {
	NSMutableArray *objects = [NSMutableArray array];
	for (id command in commands){
		NSDictionary *object = TGBSBotCommand(command);
		if (![object[@"command"] length])
			continue;
		[objects addObject:object];
	}
	if (!objects.count){
		if (completion) completion(NO, @"A command name is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"setCommands",
		@"scope" : TGBSCommandScope(scope, chatId),
		@"language_code" : TGBSString(language),
		@"commands" : objects,
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)deleteCommandsForScope:(NSString *)scope
						chatId:(int64_t)chatId
					  language:(NSString *)language
					completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"deleteCommands",
		@"scope" : TGBSCommandScope(scope, chatId),
		@"language_code" : TGBSString(language),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)menuButtonForBot:(int64_t)botUserId
			  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot user id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getMenuButton", @"user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		NSString *kind = TGBSString(result[@"text"]).length ? @"text" : @"empty";
		NSDictionary *answer = @{
			@"kind" : kind,
			@"text" : TGBSString(result[@"text"]),
			@"url" : TGBSString(result[@"url"]),
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)setMenuButtonForBot:(int64_t)botUserId
					   text:(NSString *)text
						url:(NSString *)url
				 completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot user id is needed.");
		return;
	}
	NSString *buttonText = TGBSString(text);
	NSString *buttonURL = TGBSString(url);
	if (!buttonText.length || !buttonURL.length){
		if (completion)
			completion(NO, @"A menu button needs both text and a URL.");
		return;
	}
	NSDictionary *button = @{@"@type" : @"botMenuButton",
							 @"text" : buttonText,
							 @"url" : buttonURL};
	[self request:@{@"@type" : @"setMenuButton",
					@"user_id" : @(botUserId),
					@"menu_button" : button}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

#pragma mark - managed bot

- (void)managedBotTokenForBot:(int64_t)botUserId
					   revoke:(BOOL)revoke
				   completion:(void (^)(NSString *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot user id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getManagedBotToken",
					@"bot_user_id" : @(botUserId),
					@"revoke" : @(revoke)}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"text"]), nil);
	}];
}

- (void)managedBotAccessSettingsForBot:(int64_t)botUserId
							completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!botUserId){
		if (completion) completion(nil, @"A bot user id is needed.");
		return;
	}
	[self request:@{@"@type" : @"getManagedBotAccessSettings",
					@"bot_user_id" : @(botUserId)}
	   completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		NSMutableArray *ids = [NSMutableArray array];
		for (id identifier in TGBSArray(result[@"added_user_ids"]))
			[ids addObject:@([identifier longLongValue])];
		NSDictionary *answer = @{
			@"restricted" : @([result[@"is_restricted"] boolValue]),
			@"addedUserIds" : ids,
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)setManagedBotAccessSettingsForBot:(int64_t)botUserId
							  restricted:(BOOL)restricted
							   addedUserIds:(NSArray *)userIds
								completion:(void (^)(BOOL, NSString *))completion {
	if (!botUserId){
		if (completion) completion(NO, @"A bot user id is needed.");
		return;
	}
	NSMutableArray *ids = [NSMutableArray array];
	for (id identifier in userIds)
		[ids addObject:@([identifier longLongValue])];
	[self request:@{
		@"@type" : @"setManagedBotAccessSettings",
		@"bot_user_id" : @(botUserId),
		@"settings" : @{
			@"@type" : @"botAccessSettings",
			@"is_restricted" : @(restricted),
			@"added_user_ids" : ids,
		},
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)setBotUpdatesStatus:(int32_t)pendingUpdateCount
			   errorMessage:(NSString *)errorMessage
				 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setBotUpdatesStatus",
		@"pending_update_count" : @(pendingUpdateCount),
		@"error_message" : TGBSString(errorMessage),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

#pragma mark - query answers

- (void)answerInlineQuery:(int64_t)inlineQueryId
			   isPersonal:(BOOL)isPersonal
			  resultTitle:(NSString *)title
				 resultId:(NSString *)resultId
					  url:(NSString *)url
				 cacheTime:(int32_t)cacheTime
				nextOffset:(NSString *)nextOffset
				completion:(void (^)(BOOL, NSString *))completion {
	if (!inlineQueryId){
		if (completion) completion(NO, @"An inline query id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"answerInlineQuery",
		@"inline_query_id" : @(inlineQueryId),
		@"is_personal" : @(isPersonal),
		@"button" : [NSNull null],
		@"results" : @[TGBSInlineResult(resultId, title, url)],
		@"cache_time" : @(cacheTime),
		@"next_offset" : TGBSString(nextOffset),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)answerCallbackQuery:(int64_t)callbackQueryId
					   text:(NSString *)text
				  showAlert:(BOOL)showAlert
						url:(NSString *)url
				  cacheTime:(int32_t)cacheTime
				 completion:(void (^)(BOOL, NSString *))completion {
	if (!callbackQueryId){
		if (completion) completion(NO, @"A callback query id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"answerCallbackQuery",
		@"callback_query_id" : @(callbackQueryId),
		@"text" : TGBSString(text),
		@"show_alert" : @(showAlert),
		@"url" : TGBSString(url),
		@"cache_time" : @(cacheTime),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)answerCustomQuery:(int64_t)customQueryId
					 data:(NSString *)data
			   completion:(void (^)(BOOL, NSString *))completion {
	if (!customQueryId){
		if (completion) completion(NO, @"A custom query id is needed.");
		return;
	}
	[self request:@{@"@type" : @"answerCustomQuery",
					@"custom_query_id" : @(customQueryId),
					@"data" : TGBSString(data)}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)answerGuestQuery:(int64_t)guestQueryId
			 resultTitle:(NSString *)title
				resultId:(NSString *)resultId
					 url:(NSString *)url
			  completion:(void (^)(NSString *, NSString *))completion {
	if (!guestQueryId){
		if (completion) completion(nil, @"A guest query id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"answerGuestQuery",
		@"guest_query_id" : @(guestQueryId),
		@"result" : TGBSInlineResult(resultId, title, url),
	} completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"inline_message_id"]), nil);
	}];
}

- (void)answerWebAppQuery:(NSString *)webAppQueryId
			  resultTitle:(NSString *)title
				 resultId:(NSString *)resultId
					  url:(NSString *)url
			   completion:(void (^)(NSString *, NSString *))completion {
	NSString *query = TGBSString(webAppQueryId);
	if (!query.length){
		if (completion) completion(nil, @"A Web App query id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"answerWebAppQuery",
		@"web_app_query_id" : query,
		@"result" : TGBSInlineResult(resultId, title, url),
	} completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"inline_message_id"]), nil);
	}];
}

- (void)answerPreCheckoutQuery:(int64_t)preCheckoutQueryId
				  errorMessage:(NSString *)errorMessage
					completion:(void (^)(BOOL, NSString *))completion {
	if (!preCheckoutQueryId){
		if (completion) completion(NO, @"A pre-checkout query id is needed.");
		return;
	}
	[self request:@{@"@type" : @"answerPreCheckoutQuery",
					@"pre_checkout_query_id" : @(preCheckoutQueryId),
					@"error_message" : TGBSString(errorMessage)}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)answerShippingQuery:(int64_t)shippingQueryId
			   errorMessage:(NSString *)errorMessage
				 completion:(void (^)(BOOL, NSString *))completion {
	if (!shippingQueryId){
		if (completion) completion(NO, @"A shipping query id is needed.");
		return;
	}
	[self request:@{@"@type" : @"answerShippingQuery",
					@"shipping_query_id" : @(shippingQueryId),
					@"shipping_options" : @[],
					@"error_message" : TGBSString(errorMessage)}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)replyToCallbackQueryWithEphemeralMessage:(int64_t)callbackQueryId
										   text:(NSString *)text
					 replaceCallbackMessage:(BOOL)replaceCallbackMessage
							  protectContent:(BOOL)protectContent
								 completion:(void (^)(BOOL, NSString *))completion {
	if (!callbackQueryId){
		if (completion) completion(NO, @"A callback query id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"replyToCallbackQueryWithEphemeralMessage",
		@"callback_query_id" : @(callbackQueryId),
		@"replace_callback_query_message" : @(replaceCallbackMessage),
		@"protect_content" : @(protectContent),
		@"reply_markup" : @{
			@"@type" : @"replyMarkupInlineKeyboard",
			@"rows" : @[],
			@"force_reply" : @NO,
		},
		@"input_message_content" : @{
			@"@type" : @"inputMessageText",
			@"text" : TGFormattedText(TGBSString(text)),
			@"link_preview_options" : @{
				@"@type" : @"linkPreviewOptions",
				@"is_disabled" : @YES,
				@"url" : @"",
				@"force_small_media" : @NO,
				@"force_large_media" : @NO,
				@"show_above_text" : @NO,
			},
			@"clear_draft" : @NO,
		},
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

#pragma mark - Web App host

- (void)openWebAppInChat:(int64_t)chatId
				   bot:(int64_t)botUserId
					 url:(NSString *)url
				  mode:(NSString *)mode
			  completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *address = TGBSString(url);
	if (!chatId || !botUserId || !address.length){
		if (completion)
			completion(nil, @"A chat id, a bot user id and a URL are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"openWebApp",
		@"chat_id" : @(chatId),
		@"bot_user_id" : @(botUserId),
		@"url" : address,
		@"topic_id" : [NSNull null],
		@"reply_to" : [NSNull null],
		@"parameters" : TGBSWebAppParameters(mode),
	} completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		NSDictionary *info = @{
			@"launchId" : TGBSNumber(result[@"launch_id"]),
			@"url" : TGBSString(result[@"url"]),
		};
		if (completion) completion(info, nil);
	}];
}

- (void)closeWebApp:(int64_t)launchId
		 completion:(void (^)(BOOL, NSString *))completion {
	if (!launchId){
		if (completion) completion(NO, @"A Web App launch id is needed.");
		return;
	}
	[self request:@{@"@type" : @"closeWebApp", @"web_app_launch_id" : @(launchId)}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)checkWebAppFileDownload:(int64_t)botUserId
					   fileName:(NSString *)fileName
							url:(NSString *)url
					 completion:(void (^)(BOOL, NSString *))completion {
	NSString *name = TGBSString(fileName);
	NSString *address = TGBSString(url);
	if (!botUserId || !name.length || !address.length){
		if (completion)
			completion(NO, @"A bot user id, a file name and a URL are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"checkWebAppFileDownload",
		@"bot_user_id" : @(botUserId),
		@"file_name" : name,
		@"url" : address,
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)guardBotWebAppURLForQuery:(int64_t)queryId
							 mode:(NSString *)mode
					   completion:(void (^)(NSString *, NSString *))completion {
	if (!queryId){
		if (completion) completion(nil, @"A query id is needed.");
		return;
	}
	[self request:@{
		@"@type" : @"getGuardBotWebAppUrl",
		@"query_id" : @(queryId),
		@"parameters" : TGBSWebAppParameters(mode),
	} completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"url"]), nil);
	}];
}

- (void)sendWebAppData:(int64_t)botUserId
			buttonText:(NSString *)buttonText
				  data:(NSString *)data
			completion:(void (^)(BOOL, NSString *))completion {
	NSString *button = TGBSString(buttonText);
	if (!botUserId || !button.length){
		if (completion) completion(NO, @"A bot user id and button text are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"sendWebAppData",
		@"bot_user_id" : @(botUserId),
		@"button_text" : button,
		@"data" : TGBSString(data),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGBSFailed(result);
		if (completion) completion(ok, ok ? nil : TGBSErrorText(result));
	}];
}

- (void)sendWebAppCustomRequest:(int64_t)botUserId
						 method:(NSString *)method
					 parameters:(NSString *)parameters
					 completion:(void (^)(NSString *, NSString *))completion {
	NSString *name = TGBSString(method);
	if (!botUserId || !name.length){
		if (completion) completion(nil, @"A bot user id and a method are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"sendWebAppCustomRequest",
		@"bot_user_id" : @(botUserId),
		@"method" : name,
		@"parameters" : TGBSString(parameters),
	} completion:^(NSDictionary *result){
		if (TGBSFailed(result)){
			if (completion) completion(nil, TGBSErrorText(result));
			return;
		}
		if (completion) completion(TGBSString(result[@"result"]), nil);
	}];
}

@end

// vim:ft=objc
