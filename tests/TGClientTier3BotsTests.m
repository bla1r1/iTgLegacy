// TGClientTier3BotsTests.m - one test per Tier 3 bot, Web App, harness,
// affiliate, game-score and support call.
//
// Each test names the td_api function and pins the wire shape the screen
// sends. Answers that change a row are round-tripped where the flattening
// has a decision in it; the rest only need the request to be right.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientTier3BotsTests : XCTestCase @end

static TGClient *TG3BClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.td_exec = NULL;
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *TG3BDecode(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *TG3BLast(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = TG3BDecode(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static void TG3BAnswer(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = TG3BDecode(data);
		if (request[@"@extra"])
			sent = request;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *TG3BPlain(NSDictionary *dictionary) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientTier3BotsTests

#pragma mark - bot session, passkeys and commands

- (void)testAddLoginPasskey_SendsClientDataAndAttestation {
	TGClient *c = TG3BClient();
	__block NSDictionary *passkey = nil;
	[c addLoginPasskey:@"{\"challenge\":\"x\"}" attestationObject:@"AQID"
			completion:^(NSDictionary *value, NSString *error){ passkey = value; }];
	NSDictionary *r = TG3BLast(c, @"addLoginPasskey");
	XCTAssertEqualObjects(r[@"client_data"], @"{\"challenge\":\"x\"}");
	XCTAssertEqualObjects(r[@"attestation_object"], @"AQID");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"passkey", @"id" : @"pk1",
		@"name" : @"Phone", @"addition_date" : @(7), @"last_usage_date" : @(9),
		@"software_icon_custom_emoji_id" : @(0)}));
	XCTAssertEqualObjects(passkey[@"id"], @"pk1");
	XCTAssertEqualObjects(passkey[@"name"], @"Phone");
}

- (void)testAnswerCallbackQuery_SendsEveryField {
	TGClient *c = TG3BClient();
	[c answerCallbackQuery:55 text:@"Done" showAlert:YES url:@"https://t.me/x"
				 cacheTime:10 completion:nil];
	NSDictionary *r = TG3BLast(c, @"answerCallbackQuery");
	XCTAssertEqualObjects(r[@"callback_query_id"], @(55));
	XCTAssertEqualObjects(r[@"text"], @"Done");
	XCTAssertEqualObjects(r[@"show_alert"], @YES);
	XCTAssertEqualObjects(r[@"url"], @"https://t.me/x");
	XCTAssertEqualObjects(r[@"cache_time"], @(10));
}

- (void)testAnswerCustomQuery_SendsTheData {
	TGClient *c = TG3BClient();
	[c answerCustomQuery:61 data:@"{\"ok\":true}" completion:nil];
	NSDictionary *r = TG3BLast(c, @"answerCustomQuery");
	XCTAssertEqualObjects(r[@"custom_query_id"], @(61));
	XCTAssertEqualObjects(r[@"data"], @"{\"ok\":true}");
}

- (void)testAnswerGuestQuery_SendsAnInlineArticleAndReadsTheId {
	TGClient *c = TG3BClient();
	__block NSString *identifier = nil;
	[c answerGuestQuery:62 resultTitle:@"Guest" resultId:@"r1" url:@"https://x"
			 completion:^(NSString *value, NSString *error){ identifier = value; }];
	NSDictionary *r = TG3BLast(c, @"answerGuestQuery");
	XCTAssertEqualObjects(r[@"guest_query_id"], @(62));
	XCTAssertEqualObjects(r[@"result"][@"@type"], @"inputInlineQueryResultArticle");
	XCTAssertEqualObjects(r[@"result"][@"id"], @"r1");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"inlineMessageId", @"inline_message_id" : @"im1"}));
	XCTAssertEqualObjects(identifier, @"im1");
}

- (void)testAnswerInlineQuery_SendsTheResultVectorAndCacheTime {
	TGClient *c = TG3BClient();
	[c answerInlineQuery:63 isPersonal:YES resultTitle:@"Pick" resultId:@"r2"
					 url:@"" cacheTime:30 nextOffset:@"next" completion:nil];
	NSDictionary *r = TG3BLast(c, @"answerInlineQuery");
	XCTAssertEqualObjects(r[@"inline_query_id"], @(63));
	XCTAssertEqualObjects(r[@"is_personal"], @YES);
	XCTAssertEqualObjects(r[@"cache_time"], @(30));
	XCTAssertEqualObjects(r[@"next_offset"], @"next");
	XCTAssertEqualObjects([r[@"results"] firstObject][@"@type"],
						  @"inputInlineQueryResultArticle");
	XCTAssertEqualObjects(r[@"button"], [NSNull null]);
}

- (void)testAnswerPreCheckoutQuery_SendsTheErrorMessage {
	TGClient *c = TG3BClient();
	[c answerPreCheckoutQuery:64 errorMessage:@"No card" completion:nil];
	NSDictionary *r = TG3BLast(c, @"answerPreCheckoutQuery");
	XCTAssertEqualObjects(r[@"pre_checkout_query_id"], @(64));
	XCTAssertEqualObjects(r[@"error_message"], @"No card");
}

- (void)testAnswerShippingQuery_SendsAnEmptyOptionList {
	TGClient *c = TG3BClient();
	[c answerShippingQuery:65 errorMessage:@"Cannot ship" completion:nil];
	NSDictionary *r = TG3BLast(c, @"answerShippingQuery");
	XCTAssertEqualObjects(r[@"shipping_query_id"], @(65));
	XCTAssertEqualObjects(r[@"error_message"], @"Cannot ship");
	XCTAssertEqualObjects(r[@"shipping_options"], @[]);
}

- (void)testAnswerWebAppQuery_SendsTheQueryString {
	TGClient *c = TG3BClient();
	[c answerWebAppQuery:@"waq1" resultTitle:@"Web" resultId:@"r3" url:@""
			  completion:nil];
	NSDictionary *r = TG3BLast(c, @"answerWebAppQuery");
	XCTAssertEqualObjects(r[@"web_app_query_id"], @"waq1");
	XCTAssertEqualObjects(r[@"result"][@"id"], @"r3");
}

- (void)testCheckAuthenticationBotToken_SendsTheToken {
	TGClient *c = TG3BClient();
	__block NSString *error = nil;
	[c checkAuthenticationBotToken:@"123:abc" completion:^(BOOL ok, NSString *text){
		error = text;
	}];
	NSDictionary *r = TG3BLast(c, @"checkAuthenticationBotToken");
	XCTAssertEqualObjects(r[@"token"], @"123:abc");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"error", @"code" : @(400),
		@"message" : @"Can be called only in authorizationStateWaitPhoneNumber"}));
	XCTAssertEqualObjects(error,
			@"Can be called only in authorizationStateWaitPhoneNumber");
}

- (void)testCheckAuthenticationPasskey_SendsAllFiveFields {
	TGClient *c = TG3BClient();
	[c checkAuthenticationPasskey:@"cred" clientData:@"{}" authenticatorData:@"AA"
						signature:@"BB" userHandle:@"CC" completion:nil];
	NSDictionary *r = TG3BLast(c, @"checkAuthenticationPasskey");
	XCTAssertEqualObjects(r[@"credential_id"], @"cred");
	XCTAssertEqualObjects(r[@"client_data"], @"{}");
	XCTAssertEqualObjects(r[@"authenticator_data"], @"AA");
	XCTAssertEqualObjects(r[@"signature"], @"BB");
	XCTAssertEqualObjects(r[@"user_handle"], @"CC");
}

- (void)testCheckWebAppFileDownload_SendsNameAndURL {
	TGClient *c = TG3BClient();
	[c checkWebAppFileDownload:66 fileName:@"doc.pdf" url:@"https://x/doc"
					completion:nil];
	NSDictionary *r = TG3BLast(c, @"checkWebAppFileDownload");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(66));
	XCTAssertEqualObjects(r[@"file_name"], @"doc.pdf");
	XCTAssertEqualObjects(r[@"url"], @"https://x/doc");
}

- (void)testCloseWebApp_SendsTheLaunchId {
	TGClient *c = TG3BClient();
	[c closeWebApp:77 completion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"closeWebApp")[@"web_app_launch_id"], @(77));
}

- (void)testDeleteCommands_SendsTheScopeAndLanguage {
	TGClient *c = TG3BClient();
	[c deleteCommandsForScope:@"chat" chatId:88 language:@"en" completion:nil];
	NSDictionary *r = TG3BLast(c, @"deleteCommands");
	XCTAssertEqualObjects(r[@"scope"][@"@type"], @"botCommandScopeChat");
	XCTAssertEqualObjects(r[@"scope"][@"chat_id"], @(88));
	XCTAssertEqualObjects(r[@"language_code"], @"en");
}

- (void)testGetAuthenticationPasskeyParameters_ReadsTheText {
	TGClient *c = TG3BClient();
	__block NSString *text = nil;
	[c authenticationPasskeyParametersWithCompletion:
			^(NSString *value, NSString *error){ text = value; }];
	XCTAssertEqualObjects(TG3BLast(c, @"getAuthenticationPasskeyParameters")[@"@type"],
						  @"getAuthenticationPasskeyParameters");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"text", @"text" : @"{\"rp\":{}}"}));
	XCTAssertEqualObjects(text, @"{\"rp\":{}}");
}

- (void)testGetCommands_SendsDefaultScopeAndFlattensCommands {
	TGClient *c = TG3BClient();
	__block NSDictionary *answer = nil;
	[c commandsForScope:@"default" chatId:0 language:@"en"
			  completion:^(NSDictionary *value, NSString *error){ answer = value; }];
	NSDictionary *r = TG3BLast(c, @"getCommands");
	XCTAssertEqualObjects(r[@"scope"][@"@type"], @"botCommandScopeDefault");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"botCommands", @"bot_user_id" : @(99),
		@"commands" : @[@{@"@type" : @"botCommand", @"command" : @"start",
			@"description" : @"Start", @"is_ephemeral" : @NO}]}));
	XCTAssertEqualObjects(answer[@"botUserId"], @(99));
	XCTAssertEqualObjects(answer[@"commands"][0][@"command"], @"start");
}

- (void)testGetGuardBotWebAppUrl_SendsTheParameters {
	TGClient *c = TG3BClient();
	__block NSString *link = nil;
	[c guardBotWebAppURLForQuery:101 mode:@"fullSize"
					  completion:^(NSString *value, NSString *error){ link = value; }];
	NSDictionary *r = TG3BLast(c, @"getGuardBotWebAppUrl");
	XCTAssertEqualObjects(r[@"query_id"], @(101));
	XCTAssertEqualObjects(r[@"parameters"][@"@type"], @"webAppOpenParameters");
	XCTAssertEqualObjects(r[@"parameters"][@"mode"][@"@type"],
						  @"webAppOpenModeFullSize");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"webAppUrl", @"url" : @"https://web"}));
	XCTAssertEqualObjects(link, @"https://web");
}

- (void)testGetLoginPasskeys_FlattensTheList {
	TGClient *c = TG3BClient();
	__block NSArray *rows = nil;
	[c loginPasskeysWithCompletion:^(NSArray *value, NSString *error){ rows = value; }];
	XCTAssertEqualObjects(TG3BLast(c, @"getLoginPasskeys")[@"@type"],
						  @"getLoginPasskeys");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"passkeys", @"passkeys" : @[
		@{@"@type" : @"passkey", @"id" : @"pk1", @"name" : @"Phone",
		  @"addition_date" : @(1), @"last_usage_date" : @(2),
		  @"software_icon_custom_emoji_id" : @(3)}]}));
	XCTAssertEqual(rows.count, (NSUInteger)1);
	XCTAssertEqualObjects(rows[0][@"name"], @"Phone");
}

- (void)testGetManagedBotAccessSettings_FlattensTheFlags {
	TGClient *c = TG3BClient();
	__block NSDictionary *settings = nil;
	[c managedBotAccessSettingsForBot:102
						   completion:^(NSDictionary *value, NSString *error){
		settings = value;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"getManagedBotAccessSettings")[@"bot_user_id"],
						  @(102));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"botAccessSettings",
		@"is_restricted" : @YES, @"added_user_ids" : @[@(5), @(6)]}));
	XCTAssertEqualObjects(settings[@"restricted"], @YES);
	XCTAssertEqualObjects(settings[@"addedUserIds"], (@[@(5), @(6)]));
}

- (void)testGetManagedBotToken_SendsTheRevokeFlag {
	TGClient *c = TG3BClient();
	__block NSString *token = nil;
	[c managedBotTokenForBot:103 revoke:YES
				  completion:^(NSString *value, NSString *error){ token = value; }];
	NSDictionary *r = TG3BLast(c, @"getManagedBotToken");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(103));
	XCTAssertEqualObjects(r[@"revoke"], @YES);
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"text", @"text" : @"123:new"}));
	XCTAssertEqualObjects(token, @"123:new");
}

- (void)testGetMenuButton_ReadsTheTextVariant {
	TGClient *c = TG3BClient();
	__block NSDictionary *button = nil;
	[c menuButtonForBot:104 completion:^(NSDictionary *value, NSString *error){
		button = value;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"getMenuButton")[@"user_id"], @(104));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"botMenuButton", @"text" : @"Open",
		@"url" : @"https://x"}));
	XCTAssertEqualObjects(button[@"kind"], @"text");
	XCTAssertEqualObjects(button[@"text"], @"Open");
}

- (void)testGetPasskeyParameters_ReadsTheText {
	TGClient *c = TG3BClient();
	__block NSString *text = nil;
	[c passkeyParametersWithCompletion:^(NSString *value, NSString *error){
		text = value;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"getPasskeyParameters")[@"@type"],
						  @"getPasskeyParameters");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"text", @"text" : @"{\"pubKey\":{}}"}));
	XCTAssertEqualObjects(text, @"{\"pubKey\":{}}");
}

- (void)testOpenWebApp_SendsChatBotURLAndMode {
	TGClient *c = TG3BClient();
	__block NSDictionary *info = nil;
	[c openWebAppInChat:105 bot:106 url:@"https://app" mode:@"fullScreen"
			 completion:^(NSDictionary *value, NSString *error){ info = value; }];
	NSDictionary *r = TG3BLast(c, @"openWebApp");
	XCTAssertEqualObjects(r[@"chat_id"], @(105));
	XCTAssertEqualObjects(r[@"bot_user_id"], @(106));
	XCTAssertEqualObjects(r[@"url"], @"https://app");
	XCTAssertEqualObjects(r[@"parameters"][@"mode"][@"@type"],
						  @"webAppOpenModeFullScreen");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"webAppInfo", @"launch_id" : @(7),
		@"url" : @"https://app"}));
	XCTAssertEqualObjects(info[@"launchId"], @(7));
}

- (void)testRemoveLoginPasskey_SendsTheId {
	TGClient *c = TG3BClient();
	[c removeLoginPasskey:@"pk9" completion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"removeLoginPasskey")[@"passkey_id"], @"pk9");
}

- (void)testReplyToCallbackQueryWithEphemeralMessage_SendsContentAndFlags {
	TGClient *c = TG3BClient();
	[c replyToCallbackQueryWithEphemeralMessage:107 text:@"Only you"
					   replaceCallbackMessage:YES protectContent:NO completion:nil];
	NSDictionary *r = TG3BLast(c, @"replyToCallbackQueryWithEphemeralMessage");
	XCTAssertEqualObjects(r[@"callback_query_id"], @(107));
	XCTAssertEqualObjects(r[@"replace_callback_query_message"], @YES);
	XCTAssertEqualObjects(r[@"protect_content"], @NO);
	XCTAssertEqualObjects(r[@"input_message_content"][@"@type"],
						  @"inputMessageText");
	XCTAssertEqualObjects(r[@"input_message_content"][@"text"][@"text"], @"Only you");
}

- (void)testSendWebAppCustomRequest_SendsMethodAndParameters {
	TGClient *c = TG3BClient();
	__block NSString *result = nil;
	[c sendWebAppCustomRequest:108 method:@"get_data" parameters:@"{\"a\":1}"
					completion:^(NSString *value, NSString *error){ result = value; }];
	NSDictionary *r = TG3BLast(c, @"sendWebAppCustomRequest");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(108));
	XCTAssertEqualObjects(r[@"method"], @"get_data");
	XCTAssertEqualObjects(r[@"parameters"], @"{\"a\":1}");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"customRequestResult",
		@"result" : @"{\"ok\":true}"}));
	XCTAssertEqualObjects(result, @"{\"ok\":true}");
}

- (void)testSendWebAppData_SendsButtonTextAndData {
	TGClient *c = TG3BClient();
	[c sendWebAppData:109 buttonText:@"Send" data:@"payload" completion:nil];
	NSDictionary *r = TG3BLast(c, @"sendWebAppData");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(109));
	XCTAssertEqualObjects(r[@"button_text"], @"Send");
	XCTAssertEqualObjects(r[@"data"], @"payload");
}

- (void)testSetBotUpdatesStatus_SendsCountAndError {
	TGClient *c = TG3BClient();
	[c setBotUpdatesStatus:3 errorMessage:@"timeout" completion:nil];
	NSDictionary *r = TG3BLast(c, @"setBotUpdatesStatus");
	XCTAssertEqualObjects(r[@"pending_update_count"], @(3));
	XCTAssertEqualObjects(r[@"error_message"], @"timeout");
}

- (void)testSetCommands_SendsCommandObjects {
	TGClient *c = TG3BClient();
	[c setCommands:@[@{@"command" : @"start", @"description" : @"Begin"},
					 @"help"]
			  scope:@"default" chatId:0 language:@"en" completion:nil];
	NSDictionary *r = TG3BLast(c, @"setCommands");
	XCTAssertEqualObjects(r[@"scope"][@"@type"], @"botCommandScopeDefault");
	XCTAssertEqualObjects(r[@"commands"][0][@"command"], @"start");
	XCTAssertEqualObjects(r[@"commands"][0][@"description"], @"Begin");
	XCTAssertEqualObjects(r[@"commands"][1][@"command"], @"help");
	XCTAssertEqualObjects(r[@"commands"][1][@"description"], @"help");
}

- (void)testSetManagedBotAccessSettings_SendsTheSettingsObject {
	TGClient *c = TG3BClient();
	[c setManagedBotAccessSettingsForBot:110 restricted:YES
							 addedUserIds:@[@(7), @(8)] completion:nil];
	NSDictionary *r = TG3BLast(c, @"setManagedBotAccessSettings");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(110));
	XCTAssertEqualObjects(r[@"settings"][@"@type"], @"botAccessSettings");
	XCTAssertEqualObjects(r[@"settings"][@"is_restricted"], @YES);
	XCTAssertEqualObjects(r[@"settings"][@"added_user_ids"], (@[@(7), @(8)]));
}

- (void)testSetMenuButton_SendsTheTextVariant {
	TGClient *c = TG3BClient();
	[c setMenuButtonForBot:111 text:@"Open" url:@"https://x" completion:nil];
	NSDictionary *r = TG3BLast(c, @"setMenuButton");
	XCTAssertEqualObjects(r[@"user_id"], @(111));
	XCTAssertEqualObjects(r[@"menu_button"][@"@type"], @"botMenuButton");
	XCTAssertEqualObjects(r[@"menu_button"][@"text"], @"Open");
	XCTAssertEqualObjects(r[@"menu_button"][@"url"], @"https://x");
}

#pragma mark - TDLib test harness

- (void)testCallBytes_SendsBase64 {
	TGClient *c = TG3BClient();
	__block NSString *value = nil;
	[c testCallBytes:@"AQID" completion:^(NSString *text, NSString *error){
		value = text;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"testCallBytes")[@"x"], @"AQID");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"testBytes", @"value" : @"AQID"}));
	XCTAssertEqualObjects(value, @"AQID");
}

- (void)testCallEmpty_SendsTheMethod {
	TGClient *c = TG3BClient();
	[c testCallEmptyWithCompletion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"testCallEmpty")[@"@type"], @"testCallEmpty");
}

- (void)testCallString_SendsTheString {
	TGClient *c = TG3BClient();
	__block NSString *value = nil;
	[c testCallString:@"hi" completion:^(NSString *text, NSString *error){
		value = text;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"testCallString")[@"x"], @"hi");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"testString", @"value" : @"hi"}));
	XCTAssertEqualObjects(value, @"hi");
}

- (void)testCallVectorInt_SendsNumbers {
	TGClient *c = TG3BClient();
	[c testCallVectorInt:@[@(1), @(2)] completion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"testCallVectorInt")[@"x"], (@[@(1), @(2)]));
}

- (void)testCallVectorIntObject_SendsTestIntObjects {
	TGClient *c = TG3BClient();
	[c testCallVectorIntObject:@[@(3)] completion:nil];
	NSDictionary *r = TG3BLast(c, @"testCallVectorIntObject");
	XCTAssertEqualObjects(r[@"x"][0][@"@type"], @"testInt");
	XCTAssertEqualObjects(r[@"x"][0][@"value"], @(3));
}

- (void)testCallVectorString_SendsStrings {
	TGClient *c = TG3BClient();
	[c testCallVectorString:@[@"a", @"b"] completion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"testCallVectorString")[@"x"], (@[@"a", @"b"]));
}

- (void)testCallVectorStringObject_SendsTestStringObjects {
	TGClient *c = TG3BClient();
	[c testCallVectorStringObject:@[@"z"] completion:nil];
	NSDictionary *r = TG3BLast(c, @"testCallVectorStringObject");
	XCTAssertEqualObjects(r[@"x"][0][@"@type"], @"testString");
	XCTAssertEqualObjects(r[@"x"][0][@"value"], @"z");
}

- (void)testGetDifference_SendsTheMethod {
	TGClient *c = TG3BClient();
	[c testGetDifferenceWithCompletion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"testGetDifference")[@"@type"],
						  @"testGetDifference");
}

- (void)testNetwork_SendsTheMethod {
	TGClient *c = TG3BClient();
	[c testNetworkWithCompletion:nil];
	XCTAssertEqualObjects(TG3BLast(c, @"testNetwork")[@"@type"], @"testNetwork");
}

- (void)testReturnError_SendsAnErrorObjectAndReadsItBack {
	TGClient *c = TG3BClient();
	__block int32_t code = 0;
	__block NSString *message = nil;
	[c testReturnErrorCode:400 message:@"Test error"
				 completion:^(int32_t value, NSString *text, NSString *error){
		code = value;
		message = text;
	}];
	NSDictionary *r = TG3BLast(c, @"testReturnError");
	XCTAssertEqualObjects(r[@"error"][@"@type"], @"error");
	XCTAssertEqualObjects(r[@"error"][@"code"], @(400));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"error", @"code" : @(400),
		@"message" : @"Test error"}));
	XCTAssertEqual(code, 400);
	XCTAssertEqualObjects(message, @"Test error");
}

- (void)testSquareInt_SendsTheNumber {
	TGClient *c = TG3BClient();
	__block int32_t result = 0;
	[c testSquareInt:12 completion:^(int32_t value, NSString *error){ result = value; }];
	XCTAssertEqualObjects(TG3BLast(c, @"testSquareInt")[@"x"], @(12));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"testInt", @"value" : @(144)}));
	XCTAssertEqual(result, 144);
}

- (void)testUseUpdate_SendsTheMethodAndReturnsTheUpdate {
	TGClient *c = TG3BClient();
	__block NSDictionary *update = nil;
	[c testUseUpdateWithCompletion:^(NSDictionary *value, NSString *error){
		update = value;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"testUseUpdate")[@"@type"], @"testUseUpdate");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"updateOption", @"name" : @"x",
		@"value" : @{@"@type" : @"optionValueBoolean", @"value" : @YES}}));
	XCTAssertEqualObjects(update[@"@type"], @"updateOption");
}

#pragma mark - affiliate programs

- (void)testConnectAffiliateProgram_SendsAffiliateAndBot {
	TGClient *c = TG3BClient();
	__block NSDictionary *program = nil;
	[c connectAffiliateProgramForKind:@"user" botUserId:0 chatId:0
					 programBotUserId:201 completion:^(NSDictionary *value,
													   NSString *error){
		program = value;
	}];
	NSDictionary *r = TG3BLast(c, @"connectAffiliateProgram");
	XCTAssertEqualObjects(r[@"affiliate"][@"@type"], @"affiliateTypeCurrentUser");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(201));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"connectedAffiliateProgram",
		@"url" : @"https://t.me/bot?start=aff", @"bot_user_id" : @(201),
		@"parameters" : @{@"@type" : @"affiliateProgramParameters",
			@"commission_per_mille" : @(50), @"month_count" : @(12)},
		@"connection_date" : @(1), @"is_disconnected" : @NO,
		@"user_count" : @(10), @"revenue_star_count" : @(100)}));
	XCTAssertEqualObjects(program[@"botUserId"], @(201));
	XCTAssertEqualObjects(program[@"commissionPerMille"], @(50));
}

- (void)testDisconnectAffiliateProgram_SendsTheURL {
	TGClient *c = TG3BClient();
	[c disconnectAffiliateProgramForKind:@"bot" botUserId:202 chatId:0
									 url:@"https://t.me/x" completion:nil];
	NSDictionary *r = TG3BLast(c, @"disconnectAffiliateProgram");
	XCTAssertEqualObjects(r[@"affiliate"][@"@type"], @"affiliateTypeBot");
	XCTAssertEqualObjects(r[@"affiliate"][@"user_id"], @(202));
	XCTAssertEqualObjects(r[@"url"], @"https://t.me/x");
}

- (void)testGetConnectedAffiliateProgram_SendsTheProgramBot {
	TGClient *c = TG3BClient();
	[c connectedAffiliateProgramForKind:@"channel" botUserId:0 chatId:203
						programBotUserId:204 completion:nil];
	NSDictionary *r = TG3BLast(c, @"getConnectedAffiliateProgram");
	XCTAssertEqualObjects(r[@"affiliate"][@"@type"], @"affiliateTypeChannel");
	XCTAssertEqualObjects(r[@"affiliate"][@"chat_id"], @(203));
	XCTAssertEqualObjects(r[@"bot_user_id"], @(204));
}

- (void)testGetConnectedAffiliatePrograms_SendsOffsetAndLimit {
	TGClient *c = TG3BClient();
	__block NSDictionary *page = nil;
	[c connectedAffiliateProgramsForKind:@"user" botUserId:0 chatId:0
								  offset:@"o1" limit:5
							  completion:^(NSDictionary *value, NSString *error){
		page = value;
	}];
	NSDictionary *r = TG3BLast(c, @"getConnectedAffiliatePrograms");
	XCTAssertEqualObjects(r[@"offset"], @"o1");
	XCTAssertEqualObjects(r[@"limit"], @(5));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"connectedAffiliatePrograms",
		@"total_count" : @(1), @"next_offset" : @"o2",
		@"programs" : @[@{@"@type" : @"connectedAffiliateProgram",
			@"url" : @"https://t.me/x", @"bot_user_id" : @(9),
			@"parameters" : @{@"@type" : @"affiliateProgramParameters",
				@"commission_per_mille" : @(30), @"month_count" : @(6)},
			@"connection_date" : @(2), @"is_disconnected" : @YES,
			@"user_count" : @(4), @"revenue_star_count" : @(5)}]}));
	XCTAssertEqualObjects(page[@"nextOffset"], @"o2");
	XCTAssertEqualObjects(page[@"programs"][0][@"disconnected"], @YES);
}

- (void)testSearchAffiliatePrograms_SendsSortAndFlattensFoundRows {
	TGClient *c = TG3BClient();
	__block NSDictionary *page = nil;
	[c searchAffiliateProgramsForKind:@"user" botUserId:0 chatId:0
							sortOrder:@"revenue" offset:@"" limit:10
						   completion:^(NSDictionary *value, NSString *error){
		page = value;
	}];
	NSDictionary *r = TG3BLast(c, @"searchAffiliatePrograms");
	XCTAssertEqualObjects(r[@"sort_order"][@"@type"],
						  @"affiliateProgramSortOrderRevenue");
	XCTAssertEqualObjects(r[@"limit"], @(10));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"foundAffiliatePrograms",
		@"total_count" : @(1), @"next_offset" : @"",
		@"programs" : @[@{@"@type" : @"foundAffiliateProgram",
			@"bot_user_id" : @(8), @"info" : @{@"@type" : @"affiliateProgramInfo",
				@"parameters" : @{@"@type" : @"affiliateProgramParameters",
					@"commission_per_mille" : @(70), @"month_count" : @(3)},
				@"end_date" : @(4),
				@"daily_revenue_per_user_amount" : @{@"@type" : @"starAmount",
					@"star_count" : @(2), @"nanostar_count" : @(0)}}}]}));
	XCTAssertEqualObjects(page[@"found"], @YES);
	XCTAssertEqualObjects(page[@"programs"][0][@"info"][@"commissionPerMille"], @(70));
}

- (void)testSearchChatAffiliateProgram_SendsUsernameAndReferrer {
	TGClient *c = TG3BClient();
	__block NSDictionary *chat = nil;
	[c searchChatAffiliateProgram:@"news" referrer:@"ref"
					   completion:^(NSDictionary *value, NSString *error){
		chat = value;
	}];
	NSDictionary *r = TG3BLast(c, @"searchChatAffiliateProgram");
	XCTAssertEqualObjects(r[@"username"], @"news");
	XCTAssertEqualObjects(r[@"referrer"], @"ref");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"chat", @"id" : @(301),
		@"title" : @"News"}));
	XCTAssertEqualObjects(chat[@"title"], @"News");
}

- (void)testSetChatAffiliateProgram_SendsParameters {
	TGClient *c = TG3BClient();
	[c setChatAffiliateProgram:302 commissionPerMille:40 monthCount:12
					completion:nil];
	NSDictionary *r = TG3BLast(c, @"setChatAffiliateProgram");
	XCTAssertEqualObjects(r[@"chat_id"], @(302));
	XCTAssertEqualObjects(r[@"parameters"][@"commission_per_mille"], @(40));
	XCTAssertEqualObjects(r[@"parameters"][@"month_count"], @(12));
}

#pragma mark - game scores

- (void)testGetGameHighScores_SendsTheThreeIds {
	TGClient *c = TG3BClient();
	__block NSArray *scores = nil;
	[c gameHighScoresForChat:401 message:402 user:403
				  completion:^(NSArray *value, NSString *error){ scores = value; }];
	NSDictionary *r = TG3BLast(c, @"getGameHighScores");
	XCTAssertEqualObjects(r[@"chat_id"], @(401));
	XCTAssertEqualObjects(r[@"message_id"], @(402));
	XCTAssertEqualObjects(r[@"user_id"], @(403));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"gameHighScores", @"scores" : @[
		@{@"@type" : @"gameHighScore", @"position" : @(1),
		  @"user_id" : @(403), @"score" : @(900)}]}));
	XCTAssertEqualObjects(scores[0][@"score"], @(900));
}

- (void)testGetInlineGameHighScores_SendsInlineMessageId {
	TGClient *c = TG3BClient();
	[c inlineGameHighScores:@"im9" user:404 completion:nil];
	NSDictionary *r = TG3BLast(c, @"getInlineGameHighScores");
	XCTAssertEqualObjects(r[@"inline_message_id"], @"im9");
	XCTAssertEqualObjects(r[@"user_id"], @(404));
}

- (void)testSetGameScore_SendsScoreAndFlags {
	TGClient *c = TG3BClient();
	__block NSDictionary *message = nil;
	[c setGameScoreForChat:401 message:402 user:403 score:77 force:YES
			   editMessage:NO completion:^(NSDictionary *value, NSString *error){
		message = value;
	}];
	NSDictionary *r = TG3BLast(c, @"setGameScore");
	XCTAssertEqualObjects(r[@"chat_id"], @(401));
	XCTAssertEqualObjects(r[@"score"], @(77));
	XCTAssertEqualObjects(r[@"force"], @YES);
	XCTAssertEqualObjects(r[@"edit_message"], @NO);
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"message", @"id" : @(402),
		@"chat_id" : @(401), @"date" : @(1),
		@"content" : @{@"@type" : @"messageText",
			@"text" : @{@"text" : @"Score: 77", @"entities" : @[]}}}));
	XCTAssertEqualObjects(message[@"text"], @"Score: 77");
}

- (void)testSetInlineGameScore_SendsScoreAndFlags {
	TGClient *c = TG3BClient();
	[c setInlineGameScore:@"im9" user:405 score:78 force:NO editMessage:YES
			   completion:nil];
	NSDictionary *r = TG3BLast(c, @"setInlineGameScore");
	XCTAssertEqualObjects(r[@"inline_message_id"], @"im9");
	XCTAssertEqualObjects(r[@"user_id"], @(405));
	XCTAssertEqualObjects(r[@"score"], @(78));
	XCTAssertEqualObjects(r[@"force"], @NO);
	XCTAssertEqualObjects(r[@"edit_message"], @YES);
}

#pragma mark - support

- (void)testGetSupportName_ReadsTheText {
	TGClient *c = TG3BClient();
	__block NSString *name = nil;
	[c supportNameWithCompletion:^(NSString *value, NSString *error){ name = value; }];
	XCTAssertEqualObjects(TG3BLast(c, @"getSupportName")[@"@type"], @"getSupportName");
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"text", @"text" : @"Telegram Support"}));
	XCTAssertEqualObjects(name, @"Telegram Support");
}

- (void)testGetUserSupportInfo_SendsTheUserAndFlattens {
	TGClient *c = TG3BClient();
	__block NSDictionary *info = nil;
	[c supportInfoForUser:501 completion:^(NSDictionary *value, NSString *error){
		info = value;
	}];
	XCTAssertEqualObjects(TG3BLast(c, @"getUserSupportInfo")[@"user_id"], @(501));
	TG3BAnswer(c, TG3BPlain(@{@"@type" : @"userSupportInfo",
		@"message" : @{@"@type" : @"formattedText", @"text" : @"Hello",
			@"entities" : @[]}, @"author" : @"Support", @"date" : @(11)}));
	XCTAssertEqualObjects(info[@"message"], @"Hello");
	XCTAssertEqualObjects(info[@"author"], @"Support");
	XCTAssertEqualObjects(info[@"date"], @(11));
}

- (void)testSetUserSupportInfo_SendsFormattedText {
	TGClient *c = TG3BClient();
	[c setSupportInfo:@"Need help" forUser:502 completion:nil];
	NSDictionary *r = TG3BLast(c, @"setUserSupportInfo");
	XCTAssertEqualObjects(r[@"user_id"], @(502));
	XCTAssertEqualObjects(r[@"message"][@"@type"], @"formattedText");
	XCTAssertEqualObjects(r[@"message"][@"text"], @"Need help");
}

@end

// vim:ft=objc
