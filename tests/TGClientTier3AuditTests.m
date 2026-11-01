// TGClientTier3AuditTests.m - the requests behind the Tier 3 audit.
//
// Each test names one td_api function and pins the wire shape the screen
// sends. The answers that change a row are round-tripped as well, so a
// flattening bug fails here rather than on a device.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientTier3AuditTests : XCTestCase @end

static TGClient *T3(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.td_exec = NULL;
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeT3(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastT3(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = decodeT3(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static void answerT3(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = decodeT3(data);
		if (request[@"@extra"])
			sent = request;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainT3(NSDictionary *dictionary) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientTier3AuditTests

#pragma mark - sponsored messages

- (void)testSponsoredMessages_AsksForTheChatAndFlattensTheRows {
	TGClient *c = T3();
	__block NSArray *rows = nil;
	[c sponsoredMessagesForChat:77 completion:^(NSArray *messages, NSString *error){
		rows = messages;
	}];
	NSDictionary *r = lastT3(c, @"getChatSponsoredMessages");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));

	answerT3(c, plainT3(@{@"@type" : @"sponsoredMessages",
		@"messages" : @[@{@"@type" : @"sponsoredMessage",
			@"message_id" : @(9), @"is_recommended" : @NO,
			@"can_be_reported" : @YES, @"title" : @"A sponsor",
			@"button_text" : @"Open",
			@"content" : @{@"@type" : @"messageText",
				@"text" : @{@"text" : @"Buy", @"entities" : @[]}}}]}));
	XCTAssertEqual(rows.count, (NSUInteger)1);
	XCTAssertEqualObjects(rows[0][@"kind"], @"chat");
	XCTAssertEqualObjects(rows[0][@"messageId"], @(9));
	XCTAssertEqualObjects(rows[0][@"title"], @"A sponsor");
}

- (void)testClickSponsoredMessage_SendsBothFlags {
	TGClient *c = T3();
	[c clickSponsoredMessage:9 inChat:77 mediaClick:YES fromFullscreen:NO
				  completion:nil];
	NSDictionary *r = lastT3(c, @"clickChatSponsoredMessage");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(9));
	XCTAssertEqualObjects(r[@"is_media_click"], @YES);
	XCTAssertEqualObjects(r[@"from_fullscreen"], @NO);
}

- (void)testReportSponsoredMessage_KeepsTheOptionAndFlattensTheResult {
	TGClient *c = T3();
	__block NSDictionary *result = nil;
	[c reportSponsoredMessage:9 inChat:77 option:@"b3B0aW9u"
				   completion:^(NSDictionary *value, NSString *error){
		result = value;
	}];
	NSDictionary *r = lastT3(c, @"reportChatSponsoredMessage");
	XCTAssertEqualObjects(r[@"option_id"], @"b3B0aW9u");
	answerT3(c, plainT3(@{@"@type" : @"reportSponsoredResultOptionRequired",
		@"title" : @"Why?", @"options" : @[@{@"@type" : @"reportOption",
			@"id" : @"b3B0aW9u", @"text" : @"Spam"}]}));
	XCTAssertEqualObjects(result[@"type"], @"optionRequired");
	XCTAssertEqualObjects(result[@"title"], @"Why?");
	XCTAssertEqualObjects(result[@"options"][0][@"text"], @"Spam");
}

- (void)testSponsoredMessagesSwitch_SendsTheFlag {
	TGClient *c = T3();
	[c setSponsoredMessagesEnabled:NO completion:nil];
	NSDictionary *r = lastT3(c, @"toggleHasSponsoredMessagesEnabled");
	XCTAssertEqualObjects(r[@"has_sponsored_messages_enabled"], @NO);
}

- (void)testChannelSponsoredMessagesSwitch_UsesTheSupergroupId {
	TGClient *c = T3();
	[c setChannelSponsoredMessagesEnabled:YES supergroupId:55 completion:nil];
	NSDictionary *r = lastT3(c, @"toggleSupergroupCanHaveSponsoredMessages");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(55));
	XCTAssertEqualObjects(r[@"can_have_sponsored_messages"], @YES);
}

- (void)testSearchSponsoredChats_SendsTheQueryAndFlattensRows {
	TGClient *c = T3();
	__block NSArray *rows = nil;
	[c searchSponsoredChats:@"news" completion:^(NSArray *chats, NSString *error){
		rows = chats;
	}];
	NSDictionary *r = lastT3(c, @"getSearchSponsoredChats");
	XCTAssertEqualObjects(r[@"query"], @"news");
	answerT3(c, plainT3(@{@"@type" : @"sponsoredChats",
		@"chats" : @[@{@"@type" : @"sponsoredChat", @"unique_id" : @(3),
			@"chat_id" : @(88), @"sponsor_info" : @"Pays"}]}));
	XCTAssertEqualObjects(rows[0][@"kind"], @"search");
	XCTAssertEqualObjects(rows[0][@"uniqueId"], @(3));
	XCTAssertEqualObjects(rows[0][@"chatId"], @(88));
}

- (void)testOpenAndViewSponsoredChat_SendTheUniqueId {
	TGClient *c = T3();
	[c openSponsoredChat:3 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"openSponsoredChat")[@"sponsored_chat_unique_id"], @(3));
	[c viewSponsoredChat:4 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"viewSponsoredChat")[@"sponsored_chat_unique_id"], @(4));
}

- (void)testReportSponsoredChat_SendsTheOption {
	TGClient *c = T3();
	[c reportSponsoredChat:3 option:@"b3B0aW9u" completion:nil];
	NSDictionary *r = lastT3(c, @"reportSponsoredChat");
	XCTAssertEqualObjects(r[@"sponsored_chat_unique_id"], @(3));
	XCTAssertEqualObjects(r[@"option_id"], @"b3B0aW9u");
}

- (void)testVideoAdvertisements_AsksForTheMessageAndFlattensRows {
	TGClient *c = T3();
	__block NSArray *rows = nil;
	[c videoAdvertisementsForChat:77 message:9
						completion:^(NSArray *ads, NSString *error){ rows = ads; }];
	NSDictionary *r = lastT3(c, @"getVideoMessageAdvertisements");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(9));
	answerT3(c, plainT3(@{@"@type" : @"videoMessageAdvertisements",
		@"advertisements" : @[@{@"@type" : @"videoMessageAdvertisement",
			@"unique_id" : @(12), @"text" : @"An ad",
			@"min_display_duration" : @(3), @"max_display_duration" : @(10),
			@"can_be_reported" : @YES, @"title" : @"Sponsor"}]}));
	XCTAssertEqualObjects(rows[0][@"kind"], @"video");
	XCTAssertEqualObjects(rows[0][@"uniqueId"], @(12));
	XCTAssertEqualObjects(rows[0][@"minDisplayDuration"], @(3));
}

- (void)testVideoAdvertisementClickAndView_SendTheId {
	TGClient *c = T3();
	[c clickVideoAdvertisement:12 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"clickVideoMessageAdvertisement")[@"advertisement_unique_id"], @(12));
	[c viewVideoAdvertisement:12 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"viewVideoMessageAdvertisement")[@"advertisement_unique_id"], @(12));
}

- (void)testReportVideoAdvertisement_SendsTheIdAndOption {
	TGClient *c = T3();
	[c reportVideoAdvertisement:12 option:@"" completion:nil];
	NSDictionary *r = lastT3(c, @"reportVideoMessageAdvertisement");
	XCTAssertEqualObjects(r[@"advertisement_unique_id"], @(12));
	XCTAssertEqualObjects(r[@"option_id"], @"");
}

#pragma mark - speech and listening

- (void)testRecognizeSpeech_SendsTheChatAndMessage {
	TGClient *c = T3();
	[c recognizeSpeechInChat:77 message:9 completion:nil];
	NSDictionary *r = lastT3(c, @"recognizeSpeech");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(9));
}

- (void)testRateSpeech_SendsTheVote {
	TGClient *c = T3();
	[c rateSpeechInChat:77 message:9 isGood:NO completion:nil];
	NSDictionary *r = lastT3(c, @"rateSpeechRecognition");
	XCTAssertEqualObjects(r[@"is_good"], @NO);
}

- (void)testListenToAudio_SendsTheFileAndDuration {
	TGClient *c = T3();
	[c markAudioListened:41 duration:120 completion:nil];
	NSDictionary *r = lastT3(c, @"listenToAudio");
	XCTAssertEqualObjects(r[@"audio_file_id"], @(41));
	XCTAssertEqualObjects(r[@"duration"], @(120));
}

#pragma mark - environment

- (void)testJsonValue_AsksTDLibToParseTheText {
	TGClient *c = T3();
	__block NSDictionary *value = nil;
	[c jsonValueForText:@"{\"a\":1}" completion:^(NSDictionary *v, NSString *e){ value = v; }];
	NSDictionary *r = lastT3(c, @"getJsonValue");
	XCTAssertEqualObjects(r[@"json"], @"{\"a\":1}");
	answerT3(c, plainT3(@{@"@type" : @"jsonValueObject", @"members" : @[]}));
	XCTAssertEqualObjects(value[@"@type"], @"jsonValueObject");
}

- (void)testJsonText_WritesTheValueBack {
	TGClient *c = T3();
	__block NSString *text = nil;
	[c jsonTextForValue:@{@"@type" : @"jsonValueString", @"value" : @"x"}
			 completion:^(NSString *t, NSString *e){ text = t; }];
	NSDictionary *r = lastT3(c, @"getJsonString");
	XCTAssertEqualObjects(r[@"json_value"][@"@type"], @"jsonValueString");
	answerT3(c, plainT3(@{@"@type" : @"text", @"text" : @"{\"x\":1}"}));
	XCTAssertEqualObjects(text, @"{\"x\":1}");
}

- (void)testThemeParametersJSONString_SendsEveryRole {
	TGClient *c = T3();
	[c themeParametersJSONString:@{@"backgroundColor" : @((int32_t)0xff000000)}
					  completion:nil];
	NSDictionary *r = lastT3(c, @"getThemeParametersJsonString");
	XCTAssertEqualObjects(r[@"theme"][@"@type"], @"themeParameters");
	XCTAssertEqualObjects(r[@"theme"][@"background_color"], @((int32_t)0xff000000));
	XCTAssertNotNil(r[@"theme"][@"button_text_color"]);
}

- (void)testLogStreamAndVerbosity_AreReadSynchronously {
	TGClient *c = T3();
	__block NSDictionary *stream = nil;
	__block int32_t level = -1;
	[c logStreamWithCompletion:^(NSDictionary *s, NSString *e){ stream = s; }];
	XCTAssertEqualObjects(lastT3(c, @"getLogStream")[@"@type"], @"getLogStream");
	answerT3(c, plainT3(@{@"@type" : @"logStreamDefault"}));
	XCTAssertEqualObjects(stream[@"@type"], @"logStreamDefault");

	[c logVerbosityLevelWithCompletion:^(int32_t l, NSString *e){ level = l; }];
	XCTAssertNotNil(lastT3(c, @"getLogVerbosityLevel"));
	answerT3(c, plainT3(@{@"@type" : @"logVerbosityLevel", @"verbosity_level" : @(4)}));
	XCTAssertEqual(level, 4);
}

- (void)testLogTags_ReadsTheList {
	TGClient *c = T3();
	__block NSArray *tags = nil;
	[c logTagsWithCompletion:^(NSArray *t, NSString *e){ tags = t; }];
	XCTAssertNotNil(lastT3(c, @"getLogTags"));
	answerT3(c, plainT3(@{@"@type" : @"logTags", @"tags" : @[@"tdlib", @"net"]}));
	XCTAssertEqualObjects(tags, (@[@"tdlib", @"net"]));
}

- (void)testLogTagVerbosity_ReadAndWrite {
	TGClient *c = T3();
	[c logVerbosityForTag:@"net" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getLogTagVerbosityLevel")[@"tag"], @"net");
	[c setLogVerbosityForTag:@"net" level:5 completion:nil];
	NSDictionary *r = lastT3(c, @"setLogTagVerbosityLevel");
	XCTAssertEqualObjects(r[@"tag"], @"net");
	XCTAssertEqualObjects(r[@"new_verbosity_level"], @(5));
}

- (void)testSetLogStream_BuildsAFileStream {
	TGClient *c = T3();
	[c setLogStreamKind:@"file" path:@"/tmp/td.log" completion:nil];
	NSDictionary *r = lastT3(c, @"setLogStream");
	XCTAssertEqualObjects(r[@"log_stream"][@"@type"], @"logStreamFile");
	XCTAssertEqualObjects(r[@"log_stream"][@"path"], @"/tmp/td.log");
	XCTAssertEqualObjects(r[@"log_stream"][@"redirect_stderr"], @NO);
}

- (void)testAddLogMessage_ClampsTheLevel {
	TGClient *c = T3();
	[c addLogMessage:@"hello" level:5000 completion:nil];
	NSDictionary *r = lastT3(c, @"addLogMessage");
	XCTAssertEqualObjects(r[@"verbosity_level"], @(1023));
	XCTAssertEqualObjects(r[@"text"], @"hello");
}

- (void)testSaveApplicationLogEvent_WrapsTheDataAsJsonValue {
	TGClient *c = T3();
	[c saveApplicationLogEvent:@"open" chatId:77 data:@"why"
					completion:nil];
	NSDictionary *r = lastT3(c, @"saveApplicationLogEvent");
	XCTAssertEqualObjects(r[@"type"], @"open");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"data"][@"@type"], @"jsonValueString");
	XCTAssertEqualObjects(r[@"data"][@"value"], @"why");
}

- (void)testTimeZones_FlattenTheList {
	TGClient *c = T3();
	__block NSArray *zones = nil;
	[c timeZonesWithCompletion:^(NSArray *z, NSString *e){ zones = z; }];
	XCTAssertNotNil(lastT3(c, @"getTimeZones"));
	answerT3(c, plainT3(@{@"@type" : @"timeZones", @"time_zones" : @[
		@{@"@type" : @"timeZone", @"id" : @"UTC", @"name" : @"UTC",
		  @"utc_time_offset" : @0}]}));
	XCTAssertEqualObjects(zones[0][@"id"], @"UTC");
}

- (void)testCurrencyExchangeRates_FlattenTheList {
	TGClient *c = T3();
	__block NSArray *rates = nil;
	[c currencyExchangeRatesWithCompletion:^(NSArray *r, NSString *e){ rates = r; }];
	XCTAssertNotNil(lastT3(c, @"getCurrencyExchangeRates"));
	answerT3(c, plainT3(@{@"@type" : @"currencyExchangeRates",
		@"rates" : @[@{@"@type" : @"currencyExchangeRate",
			@"currency" : @"EUR", @"rate" : @0.9}]}));
	XCTAssertEqualObjects(rates[0][@"currency"], @"EUR");
	XCTAssertEqualObjects(rates[0][@"rate"], @0.9);
}

- (void)testCurrentWeather_SendsThePoint {
	TGClient *c = T3();
	__block NSDictionary *weather = nil;
	[c currentWeatherAtLatitude:50.5 longitude:30.5
					 completion:^(NSDictionary *w, NSString *e){ weather = w; }];
	NSDictionary *r = lastT3(c, @"getCurrentWeather");
	XCTAssertEqualObjects(r[@"location"][@"latitude"], @50.5);
	XCTAssertEqualObjects(r[@"location"][@"longitude"], @30.5);
	answerT3(c, plainT3(@{@"@type" : @"currentWeather",
		@"temperature" : @21.5, @"emoji" : @"☀️"}));
	XCTAssertEqualObjects(weather[@"emoji"], @"☀️");
}

- (void)testAlarm_SendsTheSeconds {
	TGClient *c = T3();
	[c alarmAfterSeconds:3.0 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"setAlarm")[@"seconds"], @3.0);
}

#pragma mark - owned bots

- (void)testOwnedBots_AsksForTheList {
	TGClient *c = T3();
	__block NSArray *bots = nil;
	[c ownedBotsWithCompletion:^(NSArray *b, NSString *e){ bots = b; }];
	XCTAssertNotNil(lastT3(c, @"getOwnedBots"));
	[c.usersById setObject:@"Helper" forKey:@(123)];
	answerT3(c, plainT3(@{@"@type" : @"users", @"total_count" : @1,
		@"user_ids" : @[@(123)]}));
	XCTAssertEqualObjects(bots[0][@"name"], @"Helper");
}

- (void)testCheckBotUsername_SendsTheSecondaryFlag {
	TGClient *c = T3();
	[c checkBotUsername:@"mybot" isSecondary:YES completion:nil];
	NSDictionary *r = lastT3(c, @"checkBotUsername");
	XCTAssertEqualObjects(r[@"username"], @"mybot");
	XCTAssertEqualObjects(r[@"is_secondary"], @YES);
}

- (void)testBotName_ReadAndWrite {
	TGClient *c = T3();
	[c botNameForBot:123 language:@"en" completion:nil];
	NSDictionary *r = lastT3(c, @"getBotName");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(123));
	XCTAssertEqualObjects(r[@"language_code"], @"en");
	[c setBotName:@"New" forBot:123 language:@"en" completion:nil];
	NSDictionary *w = lastT3(c, @"setBotName");
	XCTAssertEqualObjects(w[@"name"], @"New");
}

- (void)testBotDescription_ReadAndWrite {
	TGClient *c = T3();
	[c botDescriptionForBot:123 language:@"en" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getBotInfoDescription")[@"bot_user_id"], @(123));
	[c setBotDescription:@"Text" forBot:123 language:@"en" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"setBotInfoDescription")[@"description"], @"Text");
}

- (void)testBotShortDescription_ReadAndWrite {
	TGClient *c = T3();
	[c botShortDescriptionForBot:123 language:@"en" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getBotInfoShortDescription")[@"bot_user_id"], @(123));
	[c setBotShortDescription:@"Short" forBot:123 language:@"en" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"setBotInfoShortDescription")[@"short_description"], @"Short");
}

- (void)testRemoveBotPhoto_SendsANullPhoto {
	TGClient *c = T3();
	[c removeBotProfilePhoto:123 completion:nil];
	NSDictionary *r = lastT3(c, @"setBotProfilePhoto");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(123));
	XCTAssertEqualObjects(r[@"photo"], [NSNull null]);
}

- (void)testBotSecondaryUsername_AddAndDelete {
	TGClient *c = T3();
	[c addBotSecondaryUsername:@"mybot2" forBot:123 completion:nil];
	NSDictionary *a = lastT3(c, @"addBotSecondaryUsername");
	XCTAssertEqualObjects(a[@"username"], @"mybot2");
	[c deleteBotSecondaryUsernameForBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"deleteBotSecondaryUsername")[@"bot_user_id"], @(123));
}

- (void)testBotUsernameActive_SendsTheFlag {
	TGClient *c = T3();
	[c setBotUsername:@"mybot" active:NO forBot:123 completion:nil];
	NSDictionary *r = lastT3(c, @"toggleBotUsernameIsActive");
	XCTAssertEqualObjects(r[@"username"], @"mybot");
	XCTAssertEqualObjects(r[@"is_active"], @NO);
}

- (void)testReorderBotUsernames_SendsTheWholeOrder {
	TGClient *c = T3();
	[c reorderBotActiveUsernames:@[@"b", @"a"] forBot:123 completion:nil];
	NSDictionary *r = lastT3(c, @"reorderBotActiveUsernames");
	XCTAssertEqualObjects(r[@"usernames"], (@[@"b", @"a"]));
}

- (void)testBotMediaPreviews_ListAndInfo {
	TGClient *c = T3();
	[c botMediaPreviewsForBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getBotMediaPreviews")[@"bot_user_id"], @(123));
	[c botMediaPreviewInfoForBot:123 language:@"en" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getBotMediaPreviewInfo")[@"language_code"], @"en");
}

- (void)testBotMediaPreview_AddAndEdit {
	TGClient *c = T3();
	[c addBotMediaPreviewForBot:123 language:@"en" fileId:41 video:YES
					 completion:nil];
	NSDictionary *a = lastT3(c, @"addBotMediaPreview");
	XCTAssertEqualObjects(a[@"content"][@"@type"], @"inputStoryContentVideo");
	XCTAssertEqualObjects(a[@"content"][@"video"][@"id"], @(41));
	[c editBotMediaPreviewForBot:123 language:@"en" fileId:41 newFileId:42
						   video:NO completion:nil];
	NSDictionary *e = lastT3(c, @"editBotMediaPreview");
	XCTAssertEqualObjects(e[@"file_id"], @(41));
	XCTAssertEqualObjects(e[@"content"][@"photo"][@"id"], @(42));
}

- (void)testBotMediaPreview_DeleteAndReorder {
	TGClient *c = T3();
	[c deleteBotMediaPreviewsForBot:123 language:@"en" fileIds:@[@41, @42]
						 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"deleteBotMediaPreviews")[@"file_ids"], (@[@41, @42]));
	[c reorderBotMediaPreviewsForBot:123 language:@"en" fileIds:@[@42, @41]
						  completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"reorderBotMediaPreviews")[@"file_ids"], (@[@42, @41]));
}

- (void)testSimilarBots_CountListAndOpen {
	TGClient *c = T3();
	[c similarBotCountForBot:123 local:YES completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getBotSimilarBotCount")[@"return_local"], @YES);
	[c similarBotsForBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getBotSimilarBots")[@"bot_user_id"], @(123));
	[c openSimilarBot:456 fromBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"openBotSimilarBot")[@"opened_bot_user_id"], @(456));
}

- (void)testBotEmojiStatusPermission_SendsTheFlag {
	TGClient *c = T3();
	[c setBotCanManageEmojiStatus:YES forBot:123 completion:nil];
	NSDictionary *r = lastT3(c, @"toggleBotCanManageEmojiStatus");
	XCTAssertEqualObjects(r[@"can_manage_emoji_status"], @YES);
}

- (void)testBotVerification_SetAndRemove {
	TGClient *c = T3();
	[c setBotVerification:123 verifiedKind:@"user" verifiedId:456
			  description:@"Checked" completion:nil];
	NSDictionary *s = lastT3(c, @"setMessageSenderBotVerification");
	XCTAssertEqualObjects(s[@"verified_id"][@"@type"], @"messageSenderUser");
	XCTAssertEqualObjects(s[@"custom_description"][@"text"], @"Checked");
	[c removeBotVerification:123 verifiedKind:@"chat" verifiedId:789 completion:nil];
	NSDictionary *r = lastT3(c, @"removeMessageSenderBotVerification");
	XCTAssertEqualObjects(r[@"verified_id"][@"@type"], @"messageSenderChat");
	XCTAssertEqualObjects(r[@"verified_id"][@"chat_id"], @(789));
}

- (void)testCreateBot_SendsTheManagerNameAndUsername {
	TGClient *c = T3();
	[c createBotNamed:@"New Bot" username:@"newbot" manager:123 completion:nil];
	NSDictionary *r = lastT3(c, @"createBot");
	XCTAssertEqualObjects(r[@"manager_bot_user_id"], @(123));
	XCTAssertEqualObjects(r[@"name"], @"New Bot");
	XCTAssertEqualObjects(r[@"username"], @"newbot");
	XCTAssertEqualObjects(r[@"via_link"], @NO);
}

- (void)testRecentInlineBots_AsksForTheList {
	TGClient *c = T3();
	[c recentInlineBotsWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"getRecentInlineBots"));
}

- (void)testStartBot_SendsTheChatAndParameter {
	TGClient *c = T3();
	[c startBot:123 inChat:77 parameter:@"deep" completion:nil];
	NSDictionary *r = lastT3(c, @"sendBotStartMessage");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(123));
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"parameter"], @"deep");
}

- (void)testAttachmentMenuBot_ReadAndToggle {
	TGClient *c = T3();
	__block NSDictionary *bot = nil;
	[c attachmentMenuBot:123 completion:^(NSDictionary *b, NSString *e){ bot = b; }];
	XCTAssertEqualObjects(lastT3(c, @"getAttachmentMenuBot")[@"bot_user_id"], @(123));
	answerT3(c, plainT3(@{@"@type" : @"attachmentMenuBot",
		@"bot_user_id" : @(123), @"is_added" : @YES, @"name" : @"Helper"}));
	XCTAssertEqualObjects(bot[@"isAdded"], @YES);
	[c setBotOnAttachmentMenu:123 added:YES allowWriteAccess:NO completion:nil];
	NSDictionary *r = lastT3(c, @"toggleBotIsAddedToAttachmentMenu");
	XCTAssertEqualObjects(r[@"is_added"], @YES);
	XCTAssertEqualObjects(r[@"allow_write_access"], @NO);
}

- (void)testBotMessaging_CanAndAllow {
	TGClient *c = T3();
	[c canBotSendMessages:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"canBotSendMessages")[@"bot_user_id"], @(123));
	[c allowBotToSendMessages:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"allowBotToSendMessages")[@"bot_user_id"], @(123));
}

- (void)testAddInlineResultToSavedReply_SendsEveryPart {
	TGClient *c = T3();
	[c addInlineResultToQuickReply:@"greeting" replyToId:5 queryId:9
						 resultId:@"r1" hideViaBot:YES completion:nil];
	NSDictionary *r = lastT3(c, @"addQuickReplyShortcutInlineQueryResultMessage");
	XCTAssertEqualObjects(r[@"shortcut_name"], @"greeting");
	XCTAssertEqualObjects(r[@"reply_to_message_id"], @(5));
	XCTAssertEqualObjects(r[@"query_id"], @(9));
	XCTAssertEqualObjects(r[@"result_id"], @"r1");
	XCTAssertEqualObjects(r[@"hide_via_bot"], @YES);
}

#pragma mark - OAuth

- (void)testOauthLinkInfo_SendsTheUrl {
	TGClient *c = T3();
	[c oauthLinkInfo:@"https://t.me/x" origin:@"" completion:nil];
	NSDictionary *r = lastT3(c, @"getOauthLinkInfo");
	XCTAssertEqualObjects(r[@"url"], @"https://t.me/x");
	XCTAssertEqualObjects(r[@"in_app_origin"], @"");
}

- (void)testOauthMatchCode_SendsTheCode {
	TGClient *c = T3();
	[c checkOauthMatchCode:@"AB12" forURL:@"https://t.me/x" completion:nil];
	NSDictionary *r = lastT3(c, @"checkOauthRequestMatchCode");
	XCTAssertEqualObjects(r[@"match_code"], @"AB12");
}

- (void)testAcceptAndDeclineOauth_SendTheRequest {
	TGClient *c = T3();
	[c acceptOauthRequest:@"https://t.me/x" matchCode:@"AB12"
		 allowWriteAccess:YES allowPhoneNumberAccess:NO completion:nil];
	NSDictionary *a = lastT3(c, @"acceptOauthRequest");
	XCTAssertEqualObjects(a[@"allow_write_access"], @YES);
	XCTAssertEqualObjects(a[@"allow_phone_number_access"], @NO);
	XCTAssertEqualObjects(a[@"ton_connect_connect_data"], [NSNull null]);
	[c declineOauthRequest:@"https://t.me/x" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"declineOauthRequest")[@"url"], @"https://t.me/x");
}

#pragma mark - business bot

- (void)testBusinessBot_ReadSetDeleteConfirm {
	TGClient *c = T3();
	[c businessConnectedBotWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"getBusinessConnectedBot"));
	[c setBusinessConnectedBot:123 recipients:@{@"existing" : @YES}
					completion:nil];
	NSDictionary *s = lastT3(c, @"setBusinessConnectedBot");
	XCTAssertEqualObjects(s[@"bot"][@"bot_user_id"], @(123));
	XCTAssertEqualObjects(s[@"bot"][@"recipients"][@"select_existing_chats"], @YES);
	[c deleteBusinessConnectedBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"deleteBusinessConnectedBot")[@"bot_user_id"], @(123));
	[c confirmBusinessConnectedBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"confirmBusinessConnectedBot")[@"bot_user_id"], @(123));
}

- (void)testBusinessBotChatControls_SendTheChat {
	TGClient *c = T3();
	[c removeBusinessConnectedBotFromChat:77 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"removeBusinessConnectedBotFromChat")[@"chat_id"], @(77));
	[c pauseBusinessConnectedBotInChat:77 paused:YES completion:nil];
	NSDictionary *r = lastT3(c, @"toggleBusinessConnectedBotChatIsPaused");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"is_paused"], @YES);
}

#pragma mark - Premium

- (void)testPremiumFeatures_AskWithANullSource {
	TGClient *c = T3();
	[c premiumFeaturesFromSource:@"" completion:nil];
	NSDictionary *r = lastT3(c, @"getPremiumFeatures");
	XCTAssertEqualObjects(r[@"source"], [NSNull null]);
}

- (void)testViewPremiumFeature_SendsTheFeatureObject {
	TGClient *c = T3();
	[c viewPremiumFeature:@"disabledAds" completion:nil];
	NSDictionary *r = lastT3(c, @"viewPremiumFeature");
	XCTAssertEqualObjects(r[@"feature"][@"@type"], @"premiumFeatureDisabledAds");
}

- (void)testPremiumLimit_SendsTheTypeObject {
	TGClient *c = T3();
	[c premiumLimitOfType:@"pinnedChatCount" completion:nil];
	NSDictionary *r = lastT3(c, @"getPremiumLimit");
	XCTAssertEqualObjects(r[@"limit_type"][@"@type"], @"premiumLimitTypePinnedChatCount");
}

- (void)testPremiumStickers_SendTheLimit {
	TGClient *c = T3();
	[c premiumStickersWithLimit:1000 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getPremiumStickers")[@"limit"], @(100));
	[c premiumStickerExamplesWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"getPremiumStickerExamples"));
	[c premiumInfoStickerForMonths:12 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getPremiumInfoSticker")[@"month_count"], @(12));
}

- (void)testPremiumGiftCode_CheckAndApply {
	TGClient *c = T3();
	[c checkPremiumGiftCode:@"CODE" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"checkPremiumGiftCode")[@"code"], @"CODE");
	[c applyPremiumGiftCode:@"CODE" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"applyPremiumGiftCode")[@"code"], @"CODE");
}

#pragma mark - Stars

- (void)testStarTransactions_SendTheOwnerAndDirection {
	TGClient *c = T3();
	[c starTransactionsForOwner:@"chat" ownerId:77 direction:@"incoming"
						 offset:@"" limit:20 completion:nil];
	NSDictionary *r = lastT3(c, @"getStarTransactions");
	XCTAssertEqualObjects(r[@"owner_id"][@"@type"], @"messageSenderChat");
	XCTAssertEqualObjects(r[@"owner_id"][@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"direction"][@"@type"], @"transactionDirectionIncoming");
	XCTAssertEqualObjects(r[@"limit"], @(20));
}

- (void)testStarSubscriptions_SendTheFilters {
	TGClient *c = T3();
	[c starSubscriptionsOnlyExpiring:YES offset:@"" completion:nil];
	NSDictionary *r = lastT3(c, @"getStarSubscriptions");
	XCTAssertEqualObjects(r[@"only_expiring"], @YES);
	XCTAssertEqualObjects(r[@"offset"], @"");
}

- (void)testStarSubscription_EditAndReuse {
	TGClient *c = T3();
	[c setStarSubscription:@"sub-1" canceled:YES completion:nil];
	NSDictionary *e = lastT3(c, @"editStarSubscription");
	XCTAssertEqualObjects(e[@"subscription_id"], @"sub-1");
	XCTAssertEqualObjects(e[@"is_canceled"], @YES);
	[c reuseStarSubscription:@"sub-1" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"reuseStarSubscription")[@"subscription_id"], @"sub-1");
}

#pragma mark - gifts

- (void)testAvailableGifts_FlattenTheCatalog {
	TGClient *c = T3();
	__block NSArray *gifts = nil;
	[c availableGiftsWithCompletion:^(NSArray *g, NSString *e){ gifts = g; }];
	XCTAssertNotNil(lastT3(c, @"getAvailableGifts"));
	answerT3(c, plainT3(@{@"@type" : @"availableGifts", @"gifts" : @[
		@{@"@type" : @"availableGift", @"resale_count" : @0,
		  @"min_resale_star_count" : @0, @"title" : @"Bear",
		  @"gift" : @{@"@type" : @"gift", @"id" : @(5), @"star_count" : @(50),
			@"sticker" : @{@"@type" : @"sticker", @"emoji" : @"🧸"}}}]}));
	XCTAssertEqualObjects(gifts[0][@"id"], @(5));
	XCTAssertEqualObjects(gifts[0][@"title"], @"Bear");
}

- (void)testCanSendGift_AsksWithTheGiftId {
	TGClient *c = T3();
	[c canSendGift:5 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"canSendGift")[@"gift_id"], @(5));
}

- (void)testReceivedGift_AsksWithTheId {
	TGClient *c = T3();
	[c receivedGift:@"gift-1" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getReceivedGift")[@"received_gift_id"], @"gift-1");
}

- (void)testUpgradedGift_ReadAndValue {
	TGClient *c = T3();
	[c upgradedGiftNamed:@"bear-1" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getUpgradedGift")[@"name"], @"bear-1");
	[c upgradedGiftValueInfoNamed:@"bear-1" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getUpgradedGiftValueInfo")[@"name"], @"bear-1");
}

- (void)testUpgradedGiftVariants_AskForBothModelLists {
	TGClient *c = T3();
	[c upgradedGiftVariantsForGift:5 completion:nil];
	NSDictionary *r = lastT3(c, @"getUpgradedGiftVariants");
	XCTAssertEqualObjects(r[@"regular_gift_id"], @(5));
	XCTAssertEqualObjects(r[@"return_upgrade_models"], @YES);
	XCTAssertEqualObjects(r[@"return_craft_models"], @YES);
}

- (void)testGiftUpgradePreview_AsksWithTheRegularGift {
	TGClient *c = T3();
	[c giftUpgradePreviewForGift:5 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getGiftUpgradePreview")[@"regular_gift_id"], @(5));
}

- (void)testGiftCollections_UseTheOwnerSender {
	TGClient *c = T3();
	[c giftCollectionsForOwner:@"user" ownerId:1001 completion:nil];
	NSDictionary *r = lastT3(c, @"getGiftCollections");
	XCTAssertEqualObjects(r[@"owner_id"][@"@type"], @"messageSenderUser");
	XCTAssertEqualObjects(r[@"owner_id"][@"user_id"], @(1001));
}

- (void)testGiftsForCrafting_AndResale {
	TGClient *c = T3();
	[c giftsForCraftingFromGift:5 offset:@"" limit:20 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getGiftsForCrafting")[@"regular_gift_id"], @(5));
	[c searchGiftsForResaleFromGift:5 order:@"giftForResaleOrderPrice"
							 offset:@"" limit:20 completion:nil];
	NSDictionary *r = lastT3(c, @"searchGiftsForResale");
	XCTAssertEqualObjects(r[@"order"][@"@type"], @"giftForResaleOrderPrice");
	XCTAssertEqualObjects(r[@"attributes"], @[]);
}

- (void)testGiftStatusesThemesAndAnimation_AskForTheirLists {
	TGClient *c = T3();
	[c upgradedGiftEmojiStatusesWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"getUpgradedGiftEmojiStatuses"));
	[c giftChatThemesWithOffset:@"" limit:20 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getGiftChatThemes")[@"limit"], @(20));
	[c upgradedGiftsPromotionalAnimationWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"getUpgradedGiftsPromotionalAnimation"));
}

#pragma mark - browser settings and Web App links

- (void)testWebBrowserSettings_SendBothFlags {
	TGClient *c = T3();
	[c setWebBrowserSettingsOpenExternal:YES displayCloseButton:NO completion:nil];
	NSDictionary *r = lastT3(c, @"changeWebBrowserSettings");
	XCTAssertEqualObjects(r[@"open_external_browser"], @YES);
	XCTAssertEqualObjects(r[@"display_close_button"], @NO);
}

- (void)testWebBrowserExceptions_AddAndRemove {
	TGClient *c = T3();
	[c addWebBrowserException:@"https://example.com" openExternal:YES completion:nil];
	NSDictionary *a = lastT3(c, @"addWebBrowserSettingsException");
	XCTAssertEqualObjects(a[@"url"], @"https://example.com");
	XCTAssertEqualObjects(a[@"open_external_browser"], @YES);
	[c removeWebBrowserException:@"https://example.com" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"removeWebBrowserSettingsException")[@"url"],
						   @"https://example.com");
	[c removeAllWebBrowserExceptionsWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"removeAllWebBrowserSettingsExceptions"));
}

- (void)testGrossingWebAppBots_AskForThePage {
	TGClient *c = T3();
	[c grossingWebAppBotsOffset:@"" limit:20 completion:nil];
	NSDictionary *r = lastT3(c, @"getGrossingWebAppBots");
	XCTAssertEqualObjects(r[@"limit"], @(20));
	XCTAssertEqualObjects(r[@"offset"], @"");
}

- (void)testSearchWebApp_SendsTheBotAndShortName {
	TGClient *c = T3();
	[c searchWebAppForBot:123 shortName:@"app" completion:nil];
	NSDictionary *r = lastT3(c, @"searchWebApp");
	XCTAssertEqualObjects(r[@"bot_user_id"], @(123));
	XCTAssertEqualObjects(r[@"web_app_short_name"], @"app");
}

- (void)testWebAppPlaceholder_AsksForTheBot {
	TGClient *c = T3();
	[c webAppPlaceholderForBot:123 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getWebAppPlaceholder")[@"bot_user_id"], @(123));
}

- (void)testWebAppURLs_SendTheOpenParameters {
	TGClient *c = T3();
	[c webAppURLForBot:123 url:@"https://app" mode:@"compact" completion:nil];
	NSDictionary *a = lastT3(c, @"getWebAppUrl");
	XCTAssertEqualObjects(a[@"parameters"][@"application_name"], @"LegacyTG");
	XCTAssertEqualObjects(a[@"parameters"][@"mode"][@"@type"], @"webAppOpenModeCompact");
	[c mainWebAppForBot:123 chatId:0 startParameter:@"start" mode:@"fullSize"
			 completion:nil];
	NSDictionary *m = lastT3(c, @"getMainWebApp");
	XCTAssertEqualObjects(m[@"start_parameter"], @"start");
	XCTAssertEqualObjects(m[@"parameters"][@"mode"][@"@type"], @"webAppOpenModeFullSize");
	[c webAppLinkURLForBot:123 chatId:0 shortName:@"app" startParameter:@""
				allowWrite:YES mode:@"compact" completion:nil];
	NSDictionary *l = lastT3(c, @"getWebAppLinkUrl");
	XCTAssertEqualObjects(l[@"web_app_short_name"], @"app");
	XCTAssertEqualObjects(l[@"allow_write_access"], @YES);
}

- (void)testShareChatAndUsersWithBot_SendTheButtonSource {
	TGClient *c = T3();
	[c shareChatWithBot:123 sourceChat:10 sourceMessage:20 buttonId:3
			 sharedChat:30 checkOnly:NO completion:nil];
	NSDictionary *chat = lastT3(c, @"shareChatWithBot");
	XCTAssertEqualObjects(chat[@"source"][@"@type"], @"keyboardButtonSourceMessage");
	XCTAssertEqualObjects(chat[@"source"][@"chat_id"], @(10));
	XCTAssertEqualObjects(chat[@"shared_chat_id"], @(30));
	[c shareUsersWithBot:123 sourceChat:10 sourceMessage:20 buttonId:3
				 userIds:@[@1001, @1002] checkOnly:YES completion:nil];
	NSDictionary *users = lastT3(c, @"shareUsersWithBot");
	XCTAssertEqualObjects(users[@"shared_user_ids"], (@[@1001, @1002]));
	XCTAssertEqualObjects(users[@"only_check"], @YES);
}

#pragma mark - boosts and revenue

- (void)testAvailableBoostSlots_AskForTheList {
	TGClient *c = T3();
	[c availableChatBoostSlotsWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"getAvailableChatBoostSlots"));
}

- (void)testChatBoostStatus_SendsTheChat {
	TGClient *c = T3();
	[c chatBoostStatusForChat:77 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatBoostStatus")[@"chat_id"], @(77));
}

- (void)testChatBoostFeatures_SendTheChannelFlag {
	TGClient *c = T3();
	[c chatBoostFeaturesForChannel:YES completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatBoostFeatures")[@"is_channel"], @YES);
	[c chatBoostLevelFeaturesForChannel:NO level:3 completion:nil];
	NSDictionary *r = lastT3(c, @"getChatBoostLevelFeatures");
	XCTAssertEqualObjects(r[@"is_channel"], @NO);
	XCTAssertEqualObjects(r[@"level"], @(3));
}

- (void)testChatBoostLinkAndInfo {
	TGClient *c = T3();
	[c chatBoostLinkForChat:77 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatBoostLink")[@"chat_id"], @(77));
	[c chatBoostLinkInfo:@"https://t.me/boost/x" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatBoostLinkInfo")[@"url"],
						   @"https://t.me/boost/x");
}

- (void)testChatBoostsAndBoost_SendTheIds {
	TGClient *c = T3();
	[c chatBoostsForChat:77 offset:@"" limit:20 completion:nil];
	NSDictionary *r = lastT3(c, @"getChatBoosts");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"limit"], @(20));
	[c boostChat:77 slotIds:@[@1, @2] completion:nil];
	NSDictionary *b = lastT3(c, @"boostChat");
	XCTAssertEqualObjects(b[@"chat_id"], @(77));
	XCTAssertEqualObjects(b[@"slot_ids"], (@[@1, @2]));
}

- (void)testRevenueReads_SendTheOwnerAndChat {
	TGClient *c = T3();
	[c chatRevenueStatisticsForChat:77 dark:NO completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatRevenueStatistics")[@"chat_id"], @(77));
	[c chatRevenueTransactionsForChat:77 offset:@"" limit:20 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatRevenueTransactions")[@"chat_id"], @(77));
	[c starRevenueStatisticsForOwner:@"user" ownerId:1001 dark:NO completion:nil];
	NSDictionary *s = lastT3(c, @"getStarRevenueStatistics");
	XCTAssertEqualObjects(s[@"owner_id"][@"@type"], @"messageSenderUser");
	XCTAssertEqualObjects(s[@"owner_id"][@"user_id"], @(1001));
	[c gramRevenueStatisticsWithDark:NO completion:nil];
	XCTAssertNotNil(lastT3(c, @"getGramRevenueStatistics"));
}

- (void)testPaidAndTopicRevenue_SendTheirIds {
	TGClient *c = T3();
	[c paidMessageRevenueForUser:1001 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getPaidMessageRevenue")[@"user_id"], @(1001));
	[c directMessagesChatTopicRevenueForChat:77 topic:5 completion:nil];
	NSDictionary *r = lastT3(c, @"getDirectMessagesChatTopicRevenue");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"topic_id"], @(5));
}

- (void)testGiveawayAndCollectible_AskForTheirTargets {
	TGClient *c = T3();
	[c giveawayInfoForChat:77 message:9 completion:nil];
	NSDictionary *g = lastT3(c, @"getGiveawayInfo");
	XCTAssertEqualObjects(g[@"chat_id"], @(77));
	XCTAssertEqualObjects(g[@"message_id"], @(9));
	[c collectibleItemInfoForKind:@"phoneNumber" value:@"+380441234567"
					   completion:nil];
	NSDictionary *r = lastT3(c, @"getCollectibleItemInfo");
	XCTAssertEqualObjects(r[@"type"][@"@type"], @"collectibleItemTypePhoneNumber");
	XCTAssertEqualObjects(r[@"type"][@"phone_number"], @"+380441234567");
}

- (void)testPremiumSubscribeButton_IsItsOwnSignal {
	TGClient *c = T3();
	[c clickPremiumSubscriptionButtonWithCompletion:nil];
	XCTAssertNotNil(lastT3(c, @"clickPremiumSubscriptionButton"));
}

- (void)testUnpaidMessagesRules_SendTheUserAndToken {
	TGClient *c = T3();
	[c allowUnpaidMessagesFromUser:1001 refund:YES completion:nil];
	NSDictionary *a = lastT3(c, @"allowUnpaidMessagesFromUser");
	XCTAssertEqualObjects(a[@"user_id"], @(1001));
	XCTAssertEqualObjects(a[@"refund_payments"], @YES);
	[c applyUnpaidMessagesToken:@"tok" forUser:1001 completion:nil];
	NSDictionary *b = lastT3(c, @"applyUnpaidMessagesToken");
	XCTAssertEqualObjects(b[@"token"], @"tok");
}

- (void)testPaidMessageSettings_SendThePrices {
	TGClient *c = T3();
	[c paidReactionSendersForChat:77 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getChatAvailablePaidMessageReactionSenders")[@"chat_id"], @(77));
	[c setChatPaidMessageStarCount:77 count:5 completion:nil];
	NSDictionary *r = lastT3(c, @"setChatPaidMessageStarCount");
	XCTAssertEqualObjects(r[@"paid_message_star_count"], @(5));
	[c setGroupCallPaidMessageStarCount:9 count:7 completion:nil];
	NSDictionary *g = lastT3(c, @"setGroupCallPaidMessageStarCount");
	XCTAssertEqualObjects(g[@"group_call_id"], @(9));
	XCTAssertEqualObjects(g[@"paid_message_star_count"], @(7));
}

- (void)testDirectMessagesTopicUnpaid_SendsBothFlags {
	TGClient *c = T3();
	[c setDirectMessagesTopicUnpaid:77 topic:5 allowed:YES refund:NO completion:nil];
	NSDictionary *r = lastT3(c, @"toggleDirectMessagesChatTopicCanSendUnpaidMessages");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"topic_id"], @(5));
	XCTAssertEqualObjects(r[@"can_send_unpaid_messages"], @YES);
	XCTAssertEqualObjects(r[@"refund_payments"], @NO);
}

- (void)testPaymentReceipt_SendsTheMessage {
	TGClient *c = T3();
	[c paymentReceiptForChat:77 message:9 completion:nil];
	NSDictionary *r = lastT3(c, @"getPaymentReceipt");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(9));
}

- (void)testStarAdAccountURL_SendsTheOwner {
	TGClient *c = T3();
	[c starAdAccountURLForOwner:@"chat" ownerId:77 completion:nil];
	NSDictionary *r = lastT3(c, @"getStarAdAccountUrl");
	XCTAssertEqualObjects(r[@"owner_id"][@"@type"], @"messageSenderChat");
	XCTAssertEqualObjects(r[@"owner_id"][@"chat_id"], @(77));
}

- (void)testUnrestrictBoostCount_SendsTheSetting {
	TGClient *c = T3();
	[c setSupergroupUnrestrictBoostCount:4 supergroupId:77 completion:nil];
	NSDictionary *r = lastT3(c, @"setSupergroupUnrestrictBoostCount");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(77));
	XCTAssertEqualObjects(r[@"unrestrict_boost_count"], @(4));
}

- (void)testGiftAuctionReadsAndSignals_DoNotSpend {
	TGClient *c = T3();
	[c giftAuctionStateForAuction:@"auction-1" completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getGiftAuctionState")[@"auction_id"], @"auction-1");
	[c giftAuctionAcquiredGiftsForGift:5 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"getGiftAuctionAcquiredGifts")[@"gift_id"], @(5));
	[c openGiftAuctionForGift:5 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"openGiftAuction")[@"gift_id"], @(5));
	[c closeGiftAuctionForGift:5 completion:nil];
	XCTAssertEqualObjects(lastT3(c, @"closeGiftAuction")[@"gift_id"], @(5));
}

@end

// vim:ft=objc
