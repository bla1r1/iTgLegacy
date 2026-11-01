// TGClientBusinessTests.m - the 32 Telegram Business, anti-spam and web
// proxy carrier requests.
//
// Each test pins the request Telegram expects and the answer a screen reads.
// The profile and message calls are marked bot-only in td_api.tl; the tests
// still drive the real request shape because that is what a screen sends
// before Telegram's refusal arrives.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientBusinessTests : XCTestCase @end

static TGClient *BizClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.me = @{@"id" : @(1001), @"first_name" : @"Ada", @"last_name" : @"Lovelace",
			 @"username" : @"ada"};
	return c;
}

static NSDictionary *decodeBiz(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastBiz(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeBiz(d)[@"@type"] isEqualToString:type])
			found = decodeBiz(d);
	return found;
}

static void replyBiz(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *request = decodeBiz(d);
		if ([request[@"@type"] isEqualToString:type] && request[@"@extra"]){
			sent = request;
			break;
		}
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainBiz(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *businessMessageAnswer(long long messageId) {
	return plainBiz(@{@"@type" : @"businessMessage",
					  @"message" : @{@"@type" : @"message", @"id" : @(messageId),
									 @"date" : @(1700000000),
									 @"content" : @{@"@type" : @"messageText",
													@"text" : @{@"@type" : @"formattedText",
																@"text" : @"hello"}}}});
}

/// The supergroup record `supergroupIdForChat:` reads before the two admin
/// requests can be sent.
static void replySupergroupChat(TGClient *c, long long chatId, long long supergroupId) {
	replyBiz(c, @"getChat", plainBiz(@{@"@type" : @"chat", @"id" : @(chatId),
			@"type" : @{@"@type" : @"chatTypeSupergroup",
						@"supergroup_id" : @(supergroupId),
						@"is_channel" : @NO}}));
}

@implementation TGClientBusinessTests

#pragma mark - features, connection, links

- (void)testGetBusinessFeatures_AsksWithNullSourceAndReadsTheList {
	TGClient *c = BizClient();
	__block NSArray *got = nil;
	[c businessFeaturesForSource:nil completion:^(NSArray *features, NSString *error){
		got = features;
	}];
	NSDictionary *r = lastBiz(c, @"getBusinessFeatures");
	XCTAssertEqualObjects(r[@"source"], [NSNull null]);
	replyBiz(c, @"getBusinessFeatures", plainBiz(@{
		@"@type" : @"businessFeatures",
		@"features" : @[@{@"@type" : @"businessFeatureLocation"},
						@{@"@type" : @"businessFeatureOpeningHours"}]}));
	XCTAssertEqualObjects(got, (@[@"businessFeatureLocation",
								 @"businessFeatureOpeningHours"]));
}

- (void)testGetBusinessConnection_SendsTheIdAndKeepsTheRecord {
	TGClient *c = BizClient();
	__block NSDictionary *got = nil;
	[c businessConnectionWithId:@"conn-7" completion:^(NSDictionary *connection,
													   NSString *error){
		got = connection;
	}];
	NSDictionary *r = lastBiz(c, @"getBusinessConnection");
	XCTAssertEqualObjects(r[@"connection_id"], @"conn-7");
	replyBiz(c, @"getBusinessConnection", plainBiz(@{
		@"@type" : @"businessConnection", @"id" : @"conn-7",
		@"user_id" : @(1001), @"is_enabled" : @YES}));
	XCTAssertEqualObjects(got[@"id"], @"conn-7");
	XCTAssertTrue([got[@"is_enabled"] boolValue]);
}

- (void)testGetBusinessConnection_RefusalIsTheMessage {
	TGClient *c = BizClient();
	__block NSString *gotError = nil;
	[c businessConnectionWithId:@"" completion:^(NSDictionary *connection,
												 NSString *error){
		gotError = error;
	}];
	replyBiz(c, @"getBusinessConnection", @{@"@type" : @"error", @"code" : @(400),
			@"message" : @"Business connection not found"});
	XCTAssertEqualObjects(gotError, @"Business connection not found");
}

- (void)testGetBusinessChatLinks_ReturnsEveryLink {
	TGClient *c = BizClient();
	__block NSArray *got = nil;
	[c businessChatLinksWithCompletion:^(NSArray *links, NSString *error){ got = links; }];
	XCTAssertEqualObjects(lastBiz(c, @"getBusinessChatLinks")[@"@type"],
						   @"getBusinessChatLinks");
	replyBiz(c, @"getBusinessChatLinks", plainBiz(@{
		@"@type" : @"businessChatLinks",
		@"links" : @[@{@"@type" : @"businessChatLink",
					   @"link" : @"https://t.me/m/abc",
					   @"title" : @"Shop",
					   @"text" : @{@"text" : @"Hi", @"entities" : @[]},
					   @"view_count" : @(4)}]}));
	XCTAssertEqual([got count], (NSUInteger)1);
	XCTAssertEqualObjects(got[0][@"title"], @"Shop");
}

- (void)testCreateBusinessChatLink_SendsTitleAndPresetText {
	TGClient *c = BizClient();
	__block NSDictionary *got = nil;
	[c createBusinessChatLinkWithText:@"Hello" title:@"Shop"
						   completion:^(NSDictionary *link, NSString *error){
		got = link;
	}];
	NSDictionary *r = lastBiz(c, @"createBusinessChatLink");
	XCTAssertEqualObjects(r[@"link_info"][@"title"], @"Shop");
	XCTAssertEqualObjects(r[@"link_info"][@"text"][@"text"], @"Hello");
	replyBiz(c, @"createBusinessChatLink", plainBiz(@{
		@"@type" : @"businessChatLink", @"link" : @"https://t.me/m/new",
		@"title" : @"Shop", @"view_count" : @(0),
		@"text" : @{@"text" : @"Hello", @"entities" : @[]}}));
	XCTAssertEqualObjects(got[@"link"], @"https://t.me/m/new");
}

- (void)testEditBusinessChatLink_NamesTheLinkAndTheNewInfo {
	TGClient *c = BizClient();
	__block NSDictionary *got = nil;
	[c editBusinessChatLink:@"https://t.me/m/abc" text:@"New text" title:@"Renamed"
				 completion:^(NSDictionary *edited, NSString *error){ got = edited; }];
	NSDictionary *r = lastBiz(c, @"editBusinessChatLink");
	XCTAssertEqualObjects(r[@"link"], @"https://t.me/m/abc");
	XCTAssertEqualObjects(r[@"link_info"][@"text"][@"text"], @"New text");
	replyBiz(c, @"editBusinessChatLink", plainBiz(@{
		@"@type" : @"businessChatLink", @"link" : @"https://t.me/m/abc",
		@"title" : @"Renamed", @"view_count" : @(2),
		@"text" : @{@"text" : @"New text", @"entities" : @[]}}));
	XCTAssertEqualObjects(got[@"title"], @"Renamed");
}

- (void)testDeleteBusinessChatLink_SendsTheUrl {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c deleteBusinessChatLink:@"https://t.me/m/abc"
				   completion:^(BOOL ok, NSString *error){ got = ok; }];
	XCTAssertEqualObjects(lastBiz(c, @"deleteBusinessChatLink")[@"link"],
						   @"https://t.me/m/abc");
	replyBiz(c, @"deleteBusinessChatLink", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testGetBusinessChatLinkInfo_AsksByNameAndReadsTheChat {
	TGClient *c = BizClient();
	__block NSDictionary *got = nil;
	[c businessChatLinkInfoForName:@"abc"
						completion:^(NSDictionary *info, NSString *error){ got = info; }];
	XCTAssertEqualObjects(lastBiz(c, @"getBusinessChatLinkInfo")[@"link_name"], @"abc");
	replyBiz(c, @"getBusinessChatLinkInfo", plainBiz(@{
		@"@type" : @"businessChatLinkInfo", @"chat_id" : @(77),
		@"text" : @{@"text" : @"Hello", @"entities" : @[]}}));
	XCTAssertEqualObjects(got[@"chat_id"], @(77));
	XCTAssertEqualObjects(got[@"text"][@"text"], @"Hello");
}

- (void)testLinkName_StripsEveryTmeSpelling {
	XCTAssertEqualObjects(TGBusinessLinkName(@"https://t.me/m/abc"), @"m/abc");
	XCTAssertEqualObjects(TGBusinessLinkName(@"t.me/m/abc"), @"m/abc");
	XCTAssertEqualObjects(TGBusinessLinkName(@"abc"), @"abc");
}

#pragma mark - account profile

- (void)testSetBusinessAccountName_SendsFirstAndLast {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c setBusinessAccountName:@"Ada" last:@"Lovelace" connectionId:@"conn"
				   completion:^(BOOL ok, NSString *error){ got = ok; }];
	NSDictionary *r = lastBiz(c, @"setBusinessAccountName");
	XCTAssertEqualObjects(r[@"business_connection_id"], @"conn");
	XCTAssertEqualObjects(r[@"first_name"], @"Ada");
	XCTAssertEqualObjects(r[@"last_name"], @"Lovelace");
	replyBiz(c, @"setBusinessAccountName", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testSetBusinessAccountBio_SendsTheBio {
	TGClient *c = BizClient();
	[c setBusinessAccountBio:@"A shop" connectionId:@"conn" completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessAccountBio");
	XCTAssertEqualObjects(r[@"bio"], @"A shop");
	XCTAssertEqualObjects(r[@"business_connection_id"], @"conn");
}

- (void)testSetBusinessAccountUsername_SendsTheName {
	TGClient *c = BizClient();
	[c setBusinessAccountUsername:@"shop" connectionId:@"conn" completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessAccountUsername");
	XCTAssertEqualObjects(r[@"username"], @"shop");
}

- (void)testSetBusinessAccountProfilePhoto_LocalPathIsStaticPhoto {
	TGClient *c = BizClient();
	[c setBusinessAccountProfilePhotoAtPath:@"/tmp/a.jpg" public:YES
							   connectionId:@"conn" completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessAccountProfilePhoto");
	XCTAssertEqualObjects(r[@"photo"][@"@type"], @"inputChatPhotoStatic");
	XCTAssertEqualObjects(r[@"photo"][@"photo"][@"path"], @"/tmp/a.jpg");
	XCTAssertEqualObjects(r[@"is_public"], @YES);
}

- (void)testSetBusinessAccountProfilePhoto_NilRemovesIt {
	TGClient *c = BizClient();
	[c setBusinessAccountProfilePhotoAtPath:nil public:NO
							   connectionId:@"conn" completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessAccountProfilePhoto")[@"photo"],
						   [NSNull null]);
}

#pragma mark - account settings

- (void)testSetBusinessLocation_SendsAddressAndPoint {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c setBusinessLocationLatitude:@(50.45) longitude:@(30.52) address:@"Kyiv"
						completion:^(BOOL ok, NSString *error){ got = ok; }];
	NSDictionary *r = lastBiz(c, @"setBusinessLocation");
	XCTAssertEqualObjects(r[@"location"][@"address"], @"Kyiv");
	XCTAssertEqualObjects(r[@"location"][@"location"][@"latitude"], @(50.45));
	XCTAssertEqualObjects(r[@"location"][@"location"][@"longitude"], @(30.52));
	replyBiz(c, @"setBusinessLocation", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testSetBusinessLocation_NilRemovesIt {
	TGClient *c = BizClient();
	[c setBusinessLocationLatitude:nil longitude:nil address:nil completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessLocation")[@"location"],
						   [NSNull null]);
}

- (void)testSetBusinessOpeningHours_SendsEachInterval {
	TGClient *c = BizClient();
	[c setBusinessOpeningHoursTimeZone:@"Europe/Kyiv"
							 intervals:@[@{@"@type" : @"businessOpeningHoursInterval",
										   @"start_minute" : @(540),
										   @"end_minute" : @(1080)}]
							completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessOpeningHours");
	XCTAssertEqualObjects(r[@"opening_hours"][@"time_zone_id"], @"Europe/Kyiv");
	XCTAssertEqual([r[@"opening_hours"][@"opening_hours"] count], (NSUInteger)1);
	XCTAssertEqualObjects(r[@"opening_hours"][@"opening_hours"][0][@"start_minute"],
						   @(540));
}

- (void)testSetBusinessGreetingMessage_SendsShortcutRecipientsAndDays {
	TGClient *c = BizClient();
	[c setBusinessGreetingMessageEnabled:YES shortcutId:4 inactivityDays:7
							  recipients:@{@"existing" : @YES, @"new" : @NO}
							  completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessGreetingMessageSettings");
	NSDictionary *settings = r[@"greeting_message_settings"];
	XCTAssertEqualObjects(settings[@"shortcut_id"], @(4));
	XCTAssertEqualObjects(settings[@"inactivity_days"], @(7));
	XCTAssertEqualObjects(settings[@"recipients"][@"select_existing_chats"], @YES);
	XCTAssertEqualObjects(settings[@"recipients"][@"select_new_chats"], @NO);
	// The categories the screen did not name stay on, rather than silently
	// cutting people out of the audience.
	XCTAssertEqualObjects(settings[@"recipients"][@"select_contacts"], @YES);
}

- (void)testSetBusinessGreetingMessage_OffSendsNull {
	TGClient *c = BizClient();
	[c setBusinessGreetingMessageEnabled:NO shortcutId:0 inactivityDays:0
							  recipients:nil completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessGreetingMessageSettings")
			[@"greeting_message_settings"], [NSNull null]);
}

- (void)testSetBusinessAwayMessage_CustomScheduleCarriesBothDates {
	TGClient *c = BizClient();
	[c setBusinessAwayMessageEnabled:YES shortcutId:2 schedule:@"custom"
						   startDate:1700000000 endDate:1700086400
						 offlineOnly:YES recipients:nil completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessAwayMessageSettings");
	NSDictionary *settings = r[@"away_message_settings"];
	XCTAssertEqualObjects(settings[@"schedule"][@"@type"],
						   @"businessAwayMessageScheduleCustom");
	XCTAssertEqualObjects(settings[@"schedule"][@"start_date"], @(1700000000));
	XCTAssertEqualObjects(settings[@"schedule"][@"end_date"], @(1700086400));
	XCTAssertEqualObjects(settings[@"offline_only"], @YES);
}

- (void)testSetBusinessAwayMessage_OutsideHoursType {
	TGClient *c = BizClient();
	[c setBusinessAwayMessageEnabled:YES shortcutId:2 schedule:@"outside"
						   startDate:0 endDate:0 offlineOnly:NO
						   recipients:nil completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessAwayMessageSettings")
			[@"away_message_settings"][@"schedule"][@"@type"],
			@"businessAwayMessageScheduleOutsideOfOpeningHours");
}

- (void)testSetBusinessStartPage_SendsTitleMessageAndSticker {
	TGClient *c = BizClient();
	[c setBusinessStartPageTitle:@"Hi" message:@"Welcome" stickerPath:@"/tmp/s.jpg"
					  completion:nil];
	NSDictionary *r = lastBiz(c, @"setBusinessStartPage");
	XCTAssertEqualObjects(r[@"start_page"][@"title"], @"Hi");
	XCTAssertEqualObjects(r[@"start_page"][@"message"], @"Welcome");
	XCTAssertEqualObjects(r[@"start_page"][@"sticker"][@"path"], @"/tmp/s.jpg");
}

- (void)testSetBusinessStartPage_EmptyRemovesIt {
	TGClient *c = BizClient();
	[c setBusinessStartPageTitle:@"" message:@"" stickerPath:nil completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessStartPage")[@"start_page"],
						   [NSNull null]);
}

#pragma mark - business messages

- (void)testSendBusinessMessage_SendsTextAndFlags {
	TGClient *c = BizClient();
	__block NSDictionary *got = nil;
	[c sendBusinessMessageWithConnectionId:@"conn" chatId:77 text:@"Hello"
					  disableNotification:YES protectContent:YES
								completion:^(NSDictionary *message, NSString *error){
		got = message;
	}];
	NSDictionary *r = lastBiz(c, @"sendBusinessMessage");
	XCTAssertEqualObjects(r[@"business_connection_id"], @"conn");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"input_message_content"][@"text"][@"text"], @"Hello");
	XCTAssertEqualObjects(r[@"disable_notification"], @YES);
	XCTAssertEqualObjects(r[@"protect_content"], @YES);
	XCTAssertEqualObjects(r[@"reply_to"], [NSNull null]);
	replyBiz(c, @"sendBusinessMessage", businessMessageAnswer(91));
	XCTAssertEqualObjects(got[@"message"][@"id"], @(91));
}

- (void)testSendBusinessMessageAlbum_SendsEveryPhoto {
	TGClient *c = BizClient();
	__block NSArray *got = nil;
	[c sendBusinessMessageAlbumWithConnectionId:@"conn" chatId:77
										 paths:@[@"/tmp/a.jpg", @"/tmp/b.jpg"]
									   caption:@"Two"
						   disableNotification:NO protectContent:NO
									 completion:^(NSArray *messages, NSString *error){
		got = messages;
	}];
	NSDictionary *r = lastBiz(c, @"sendBusinessMessageAlbum");
	XCTAssertEqual([r[@"input_message_contents"] count], (NSUInteger)2);
	XCTAssertEqualObjects(r[@"input_message_contents"][0][@"@type"],
						   @"inputMessagePhoto");
	XCTAssertEqualObjects(r[@"input_message_contents"][0][@"caption"][@"text"], @"Two");
	// Only the first photo carries the album caption.
	XCTAssertEqualObjects(r[@"input_message_contents"][1][@"caption"][@"text"], @"");
	replyBiz(c, @"sendBusinessMessageAlbum", plainBiz(@{
		@"@type" : @"businessMessages",
		@"messages" : @[businessMessageAnswer(91), businessMessageAnswer(92)]}));
	XCTAssertEqual([got count], (NSUInteger)2);
}

- (void)testEditBusinessMessageText_SendsTheNewText {
	TGClient *c = BizClient();
	[c editBusinessMessageTextWithConnectionId:@"conn" chatId:77 messageId:91
										 text:@"Edited"
									completion:nil];
	NSDictionary *r = lastBiz(c, @"editBusinessMessageText");
	XCTAssertEqualObjects(r[@"message_id"], @(91));
	XCTAssertEqualObjects(r[@"input_message_content"][@"text"][@"text"], @"Edited");
}

- (void)testEditBusinessMessageCaption_SendsCaptionAndPlacement {
	TGClient *c = BizClient();
	[c editBusinessMessageCaptionWithConnectionId:@"conn" chatId:77 messageId:91
										  caption:@"Caption" completion:nil];
	NSDictionary *r = lastBiz(c, @"editBusinessMessageCaption");
	XCTAssertEqualObjects(r[@"caption"][@"text"], @"Caption");
	XCTAssertEqualObjects(r[@"show_caption_above_media"], @NO);
}

- (void)testEditBusinessMessageMedia_SendsPhotoContent {
	TGClient *c = BizClient();
	[c editBusinessMessageMediaWithConnectionId:@"conn" chatId:77 messageId:91
										   path:@"/tmp/a.jpg" isVideo:NO caption:@"New"
									 completion:nil];
	NSDictionary *r = lastBiz(c, @"editBusinessMessageMedia");
	XCTAssertEqualObjects(r[@"input_message_content"][@"@type"], @"inputMessagePhoto");
	XCTAssertEqualObjects(r[@"input_message_content"][@"photo"][@"path"], @"/tmp/a.jpg");
}

- (void)testEditBusinessMessageLiveLocation_SendsThePointAndPeriod {
	TGClient *c = BizClient();
	[c editBusinessMessageLiveLocationWithConnectionId:@"conn" chatId:77 messageId:91
											  latitude:50.45 longitude:30.52
											livePeriod:900 completion:nil];
	NSDictionary *r = lastBiz(c, @"editBusinessMessageLiveLocation");
	XCTAssertEqualObjects(r[@"location"][@"live_period"], @(900));
	XCTAssertEqualObjects(r[@"location"][@"location"][@"latitude"], @(50.45));
}

- (void)testEditBusinessMessageLiveLocation_ZeroStopsSharing {
	TGClient *c = BizClient();
	[c editBusinessMessageLiveLocationWithConnectionId:@"conn" chatId:77 messageId:91
											  latitude:0 longitude:0
											livePeriod:0 completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"editBusinessMessageLiveLocation")[@"location"],
						   [NSNull null]);
}

- (void)testEditBusinessMessageChecklist_SendsTasks {
	TGClient *c = BizClient();
	[c editBusinessMessageChecklistWithConnectionId:@"conn" chatId:77 messageId:91
											 title:@"Tasks" tasks:@[@"One", @"Two"]
										completion:nil];
	NSDictionary *r = lastBiz(c, @"editBusinessMessageChecklist");
	XCTAssertEqualObjects(r[@"checklist"][@"title"][@"text"], @"Tasks");
	XCTAssertEqual([r[@"checklist"][@"tasks"] count], (NSUInteger)2);
	XCTAssertEqualObjects(r[@"checklist"][@"tasks"][1][@"text"][@"text"], @"Two");
}

- (void)testEditBusinessMessageReplyMarkup_ClearsIt {
	TGClient *c = BizClient();
	[c editBusinessMessageReplyMarkupWithConnectionId:@"conn" chatId:77 messageId:91
										   completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"editBusinessMessageReplyMarkup")
			[@"reply_markup"], [NSNull null]);
}

- (void)testStopBusinessPoll_SendsTheMessage {
	TGClient *c = BizClient();
	[c stopBusinessPollWithConnectionId:@"conn" chatId:77 messageId:91
							 completion:nil];
	NSDictionary *r = lastBiz(c, @"stopBusinessPoll");
	XCTAssertEqualObjects(r[@"message_id"], @(91));
	XCTAssertEqualObjects(r[@"reply_markup"], [NSNull null]);
}

- (void)testReadBusinessMessage_SendsTheMessage {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c readBusinessMessageWithConnectionId:@"conn" chatId:77 messageId:91
								completion:^(BOOL ok, NSString *error){ got = ok; }];
	NSDictionary *r = lastBiz(c, @"readBusinessMessage");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(91));
	replyBiz(c, @"readBusinessMessage", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testSetBusinessMessagePinned_TrueAndFalse {
	TGClient *c = BizClient();
	[c setBusinessMessagePinnedWithConnectionId:@"conn" chatId:77 messageId:91
										 pinned:YES completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessMessageIsPinned")[@"is_pinned"], @YES);
	[c.outbox removeAllObjects];
	[c setBusinessMessagePinnedWithConnectionId:@"conn" chatId:77 messageId:91
										 pinned:NO completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"setBusinessMessageIsPinned")[@"is_pinned"], @NO);
}

- (void)testDeleteBusinessMessages_SendsEveryId {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c deleteBusinessMessagesWithConnectionId:@"conn" messageIds:@[@(91), @(92)]
								   completion:^(BOOL ok, NSString *error){ got = ok; }];
	NSDictionary *r = lastBiz(c, @"deleteBusinessMessages");
	XCTAssertEqualObjects(r[@"business_connection_id"], @"conn");
	XCTAssertEqualObjects(r[@"message_ids"], (@[@(91), @(92)]));
	replyBiz(c, @"deleteBusinessMessages", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testDeleteBusinessMessages_EmptyListIsRefusedBeforeSending {
	TGClient *c = BizClient();
	__block NSString *gotError = nil;
	[c deleteBusinessMessagesWithConnectionId:@"conn" messageIds:@[]
								   completion:^(BOOL ok, NSString *error){
		gotError = error;
	}];
	XCTAssertNil(lastBiz(c, @"deleteBusinessMessages"));
	XCTAssertNotNil(gotError);
}

#pragma mark - anti-spam

- (void)testAggressiveAntiSpam_ReadsTheFullGroupRecord {
	TGClient *c = BizClient();
	__block BOOL enabled = NO, canToggle = NO;
	[c aggressiveAntiSpamForChat:-77 completion:^(BOOL on, BOOL can, NSString *error){
		enabled = on;
		canToggle = can;
	}];
	replySupergroupChat(c, -77, 55);
	replyBiz(c, @"getSupergroupFullInfo", plainBiz(@{
		@"@type" : @"supergroupFullInfo",
		@"has_aggressive_anti_spam_enabled" : @YES,
		@"can_toggle_aggressive_anti_spam" : @YES}));
	XCTAssertTrue(enabled);
	XCTAssertTrue(canToggle);
}

- (void)testToggleAggressiveAntiSpam_SendsTheSupergroupId {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c setChat:-77 aggressiveAntiSpam:YES completion:^(BOOL ok, NSString *error){
		got = ok;
	}];
	replySupergroupChat(c, -77, 55);
	NSDictionary *r = lastBiz(c, @"toggleSupergroupHasAggressiveAntiSpamEnabled");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(55));
	XCTAssertEqualObjects(r[@"has_aggressive_anti_spam_enabled"], @YES);
	replyBiz(c, @"toggleSupergroupHasAggressiveAntiSpamEnabled", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testAntiSpamCandidates_KeepsOnlyReportableDeletions {
	TGClient *c = BizClient();
	__block NSArray *got = nil;
	[c antiSpamFalsePositiveCandidatesForChat:-77 completion:^(NSArray *rows,
															   NSString *error){
		got = rows;
	}];
	NSDictionary *r = lastBiz(c, @"getChatEventLog");
	XCTAssertEqualObjects(r[@"filters"][@"message_deletions"], @YES);
	XCTAssertEqualObjects(r[@"filters"][@"message_edits"], @NO);
	replyBiz(c, @"getChatEventLog", plainBiz(@{
		@"@type" : @"chatEvents",
		@"events" : @[
			@{@"@type" : @"chatEvent", @"id" : @(1), @"date" : @(1700000000),
			  @"action" : @{@"@type" : @"chatEventMessageDeleted",
							@"can_report_anti_spam_false_positive" : @YES,
							@"message" : @{@"@type" : @"message", @"id" : @(91),
										   @"date" : @(1700000000),
										   @"content" : @{@"@type" : @"messageText",
														  @"text" : @{@"text" : @"Blocked"}}}}},
			@{@"@type" : @"chatEvent", @"id" : @(2), @"date" : @(1700000001),
			  @"action" : @{@"@type" : @"chatEventMessageDeleted",
							@"can_report_anti_spam_false_positive" : @NO,
							@"message" : @{@"@type" : @"message", @"id" : @(92),
										   @"date" : @(1700000001),
										   @"content" : @{@"@type" : @"messageText",
														  @"text" : @{@"text" : @"Gone"}}}}}]}));
	XCTAssertEqual([got count], (NSUInteger)1);
	XCTAssertEqualObjects(got[0][@"messageId"], @(91));
}

- (void)testReportAntiSpamFalsePositive_SendsSupergroupIdAndMessage {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c reportAntiSpamFalsePositiveInChat:-77 messageId:91
							  completion:^(BOOL ok, NSString *error){ got = ok; }];
	replySupergroupChat(c, -77, 55);
	NSDictionary *r = lastBiz(c, @"reportSupergroupAntiSpamFalsePositive");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(55));
	XCTAssertEqualObjects(r[@"message_id"], @(91));
	replyBiz(c, @"reportSupergroupAntiSpamFalsePositive", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

#pragma mark - web proxy carrier

- (void)testProcessWebProxyCarrierText_SendsTheTextMessage {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c processWebProxyCarrierMessage:5 text:@"{hello:1}"
						  completion:^(BOOL ok, NSString *error){ got = ok; }];
	NSDictionary *r = lastBiz(c, @"processWebProxyCarrierMessage");
	XCTAssertEqualObjects(r[@"carrier_id"], @(5));
	XCTAssertEqualObjects(r[@"message"][@"@type"], @"webProxyCarrierMessageText");
	XCTAssertEqualObjects(r[@"message"][@"text"], @"{hello:1}");
	replyBiz(c, @"processWebProxyCarrierMessage", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testProcessWebProxyCarrierBinary_SendsBase64Data {
	TGClient *c = BizClient();
	[c processWebProxyCarrierMessage:5 base64:@"AAECAw==" completion:nil];
	NSDictionary *r = lastBiz(c, @"processWebProxyCarrierMessage");
	XCTAssertEqualObjects(r[@"message"][@"@type"], @"webProxyCarrierMessageBinary");
	XCTAssertEqualObjects(r[@"message"][@"data"], @"AAECAw==");
}

- (void)testReportWebProxyCarrierError_LoadFailedCarriesTheSentence {
	TGClient *c = BizClient();
	__block BOOL got = NO;
	[c reportWebProxyCarrierError:5 kind:@"loadFailed" message:@"404"
					   completion:^(BOOL ok, NSString *error){ got = ok; }];
	NSDictionary *r = lastBiz(c, @"reportWebProxyCarrierError");
	XCTAssertEqualObjects(r[@"carrier_id"], @(5));
	XCTAssertEqualObjects(r[@"error"][@"@type"], @"webProxyCarrierErrorLoadFailed");
	XCTAssertEqualObjects(r[@"error"][@"message"], @"404");
	replyBiz(c, @"reportWebProxyCarrierError", @{@"@type" : @"ok"});
	XCTAssertTrue(got);
}

- (void)testReportWebProxyCarrierError_UnsupportedHasNoSentence {
	TGClient *c = BizClient();
	[c reportWebProxyCarrierError:5 kind:@"unsupported" message:nil completion:nil];
	XCTAssertEqualObjects(lastBiz(c, @"reportWebProxyCarrierError")
			[@"error"][@"@type"], @"webProxyCarrierErrorUnsupported");
}

@end

// vim:ft=objc
