//
// TGClientMiscTests.m - the tier 2 long tail: saved orders and a card lookup,
// the two call diagnostics, the session's calls switch and idle timeout, the
// connected-website list, prepared keyboard buttons and a poll answer's
// properties.
//
// Each test holds the shape the request leaves in the outbox, because that is
// where these calls are easiest to get wrong: a required field left out of an
// orderInfo, a card number with spaces, a call log that names a message but
// writes no file.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientMiscTests : XCTestCase @end

static TGClient *MiscClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c removeAllFileWaiters];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeMisc(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastMisc(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeMisc(d)[@"@type"] isEqualToString:type])
			found = decodeMisc(d);
	return found;
}

static NSUInteger countMisc(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeMisc(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void answerMisc(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *request = decodeMisc(d);
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

@implementation TGClientMiscTests

#pragma mark - payments and orders

- (void)testSavedOrderInfo_ReadsTheOrderTelegramKept {
	TGClient *c = MiscClient();
	__block NSDictionary *got = nil;
	__block NSString *failure = nil;
	[c savedOrderInfoWithCompletion:^(NSDictionary *order, NSString *error){
		got = order; failure = error;
	}];
	XCTAssertEqualObjects(lastMisc(c, @"getSavedOrderInfo")[@"@type"],
						  @"getSavedOrderInfo");
	answerMisc(c, @"getSavedOrderInfo", @{@"@type" : @"orderInfo",
			@"name" : @"Jane Doe", @"phone_number" : @"+441234",
			@"email_address" : @"jane@example.com",
			@"shipping_address" : @{@"@type" : @"address", @"city" : @"London"}});
	XCTAssertEqualObjects(got[@"name"], @"Jane Doe");
	XCTAssertEqualObjects(got[@"shipping_address"][@"city"], @"London");
	XCTAssertNil(failure);
}

- (void)testSavedOrderInfo_NoOrderIsTheServersSentence {
	TGClient *c = MiscClient();
	__block NSDictionary *got = @{};
	__block NSString *failure = nil;
	[c savedOrderInfoWithCompletion:^(NSDictionary *order, NSString *error){
		got = order; failure = error;
	}];
	answerMisc(c, @"getSavedOrderInfo", @{@"@type" : @"error",
			@"code" : @404, @"message" : @"Order info not found"});
	XCTAssertNil(got);
	XCTAssertEqualObjects(failure, @"Order info not found");
}

- (void)testDeleteSavedOrderInfo_SendsTheRequestAndKeepsTheRefusal {
	TGClient *c = MiscClient();
	__block BOOL ok = YES;
	__block NSString *failure = nil;
	[c deleteSavedOrderInfoWithCompletion:^(BOOL good, NSString *error){
		ok = good; failure = error;
	}];
	XCTAssertEqualObjects(lastMisc(c, @"deleteSavedOrderInfo")[@"@type"],
						  @"deleteSavedOrderInfo");
	answerMisc(c, @"deleteSavedOrderInfo", @{@"@type" : @"error",
			@"code" : @400, @"message" : @"Payment provider is not available"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(failure, @"Payment provider is not available");
}

- (void)testBankCardInfo_StripsSpacesBeforeTheLookup {
	TGClient *c = MiscClient();
	__block NSDictionary *got = nil;
	[c bankCardInfoForNumber:@"4111 1111 1111 1111"
				  completion:^(NSDictionary *info, NSString *error){ got = info; }];
	NSDictionary *request = lastMisc(c, @"getBankCardInfo");
	XCTAssertEqualObjects(request[@"bank_card_number"], @"4111111111111111");
	answerMisc(c, @"getBankCardInfo", @{@"@type" : @"bankCardInfo",
			@"title" : @"VISA - CREDIT",
			@"actions" : @[@{@"@type" : @"bankCardActionOpenUrl",
							 @"text" : @"Open 3-D Secure",
							 @"url" : @"https://example.com/3ds"}]});
	XCTAssertEqualObjects(got[@"title"], @"VISA - CREDIT");
	XCTAssertEqualObjects(got[@"actions"][0][@"url"], @"https://example.com/3ds");
}

- (void)testBankCardInfo_AShortNumberNeverLeavesTheDevice {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c bankCardInfoForNumber:@"4111"
				  completion:^(NSDictionary *info, NSString *error){ failure = error; }];
	XCTAssertEqual(countMisc(c, @"getBankCardInfo"), (NSUInteger)0);
	XCTAssertTrue(failure.length > 0);
}

- (void)testAddOffer_BuildsEverySendOptionAndTheStarPrice {
	TGClient *c = MiscClient();
	__block NSDictionary *sent = nil;
	[c addOfferToMessage:77 inChat:-100123 starCount:250 sendDate:0
			  completion:^(NSDictionary *message, NSString *error){ sent = message; }];
	NSDictionary *request = lastMisc(c, @"addOffer");
	XCTAssertEqualObjects(request[@"chat_id"], @(-100123));
	XCTAssertEqualObjects(request[@"message_id"], @(77));
	NSDictionary *options = request[@"options"];
	XCTAssertEqualObjects(options[@"@type"], @"messageSendOptions");
	XCTAssertEqualObjects(options[@"suggested_post_info"][@"@type"],
						  @"inputSuggestedPostInfo");
	XCTAssertEqualObjects(options[@"suggested_post_info"][@"price"][@"@type"],
						  @"suggestedPostPriceStar");
	XCTAssertEqualObjects(options[@"suggested_post_info"][@"price"][@"star_count"],
						  @(250));
	XCTAssertEqualObjects(options[@"suggested_post_info"][@"send_date"], @(0));
	XCTAssertEqualObjects(options[@"scheduling_state"], [NSNull null]);
	XCTAssertEqualObjects(options[@"paid_message_star_count"], @(0));
	answerMisc(c, @"addOffer", @{@"@type" : @"message", @"id" : @(9001)});
	XCTAssertEqualObjects(sent[@"id"], @(9001));
}

- (void)testAddOffer_NoPriceSendsNothing {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c addOfferToMessage:77 inChat:-100123 starCount:0 sendDate:0
			  completion:^(NSDictionary *message, NSString *error){ failure = error; }];
	XCTAssertEqual(countMisc(c, @"addOffer"), (NSUInteger)0);
	XCTAssertTrue(failure.length > 0);
}

- (void)testValidateOrderInfo_BuildsEveryRequiredOrderField {
	TGClient *c = MiscClient();
	__block NSDictionary *validated = nil;
	NSDictionary *order = @{@"name" : @"Jane Doe",
							@"phone_number" : @"+441234",
							@"email_address" : @"jane@example.com",
							@"street_line1" : @"1 High Street",
							@"city" : @"London",
							@"postal_code" : @"SW1A 1AA",
							@"country_code" : @"GB"};
	[c validateOrderInfoForInvoice:@"invoice-name" order:order allowSave:YES
						completion:^(NSDictionary *result, NSString *error){
		validated = result;
	}];
	NSDictionary *request = lastMisc(c, @"validateOrderInfo");
	XCTAssertEqualObjects(request[@"input_invoice"][@"@type"], @"inputInvoiceName");
	XCTAssertEqualObjects(request[@"input_invoice"][@"name"], @"invoice-name");
	XCTAssertTrue([request[@"allow_save"] boolValue]);
	NSDictionary *info = request[@"order_info"];
	XCTAssertEqualObjects(info[@"@type"], @"orderInfo");
	XCTAssertEqualObjects(info[@"name"], @"Jane Doe");
	XCTAssertEqualObjects(info[@"shipping_address"][@"@type"], @"address");
	XCTAssertEqualObjects(info[@"shipping_address"][@"city"], @"London");
	XCTAssertEqualObjects(info[@"shipping_address"][@"street_line2"], @"",
						  @"a required key is empty, not missing");
	answerMisc(c, @"validateOrderInfo", @{@"@type" : @"validatedOrderInfo",
			@"order_info_id" : @"ord-1", @"shipping_options" : @[]});
	XCTAssertEqualObjects(validated[@"order_info_id"], @"ord-1");
}

- (void)testValidateOrderInfo_NoInvoiceNameSendsNothing {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c validateOrderInfoForInvoice:@"  " order:@{} allowSave:NO
						completion:^(NSDictionary *result, NSString *error){
		failure = error;
	}];
	XCTAssertEqual(countMisc(c, @"validateOrderInfo"), (NSUInteger)0);
	XCTAssertTrue(failure.length > 0);
}

#pragma mark - call diagnostics

- (void)testSendCallLog_WritesALocalFileForTheCallMessage {
	TGClient *c = MiscClient();
	__block BOOL ok = NO;
	[c sendCallLog:@"LegacyTG call log\nDuration: 12 s"
		forMessage:55 inChat:-1007
		completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *request = lastMisc(c, @"sendCallLog");
	XCTAssertEqualObjects(request[@"call_id"][@"@type"], @"inputCallFromMessage");
	XCTAssertEqualObjects(request[@"call_id"][@"chat_id"], @(-1007));
	XCTAssertEqualObjects(request[@"call_id"][@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"log_file"][@"@type"], @"inputFileLocal");
	NSString *path = request[@"log_file"][@"path"];
	XCTAssertTrue(path.length > 0);
	NSString *written = [NSString stringWithContentsOfFile:path
												 encoding:NSUTF8StringEncoding
													error:NULL];
	XCTAssertTrue([written rangeOfString:@"Duration: 12 s"].location != NSNotFound,
				  @"the log the server reads is the log the screen wrote");
	answerMisc(c, @"sendCallLog", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path],
				   @"the temporary copy goes away once the server has it");
}

- (void)testSendCallLog_RefusalCarriesTheServersSentence {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c sendCallLog:@"log" forMessage:55 inChat:-1007
		completion:^(BOOL ok, NSString *error){ failure = error; }];
	answerMisc(c, @"sendCallLog", @{@"@type" : @"error",
			@"code" : @400, @"message" : @"Call log is too big"});
	XCTAssertEqualObjects(failure, @"Call log is too big");
}

- (void)testSendCallDebugInformation_NamesTheCallAndCarriesTheJSON {
	TGClient *c = MiscClient();
	__block BOOL ok = NO;
	[c sendCallDebugInformation:@"{\"duration\":12}"
					 forMessage:55
						 inChat:-1007
					 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *request = lastMisc(c, @"sendCallDebugInformation");
	XCTAssertEqualObjects(request[@"call_id"][@"@type"], @"inputCallFromMessage");
	XCTAssertEqualObjects(request[@"debug_information"], @"{\"duration\":12}");
	answerMisc(c, @"sendCallDebugInformation", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSendCallDebugInformation_EmptyTextNeverLeavesTheDevice {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c sendCallDebugInformation:@"  " forMessage:55 inChat:-1007
					 completion:^(BOOL ok, NSString *error){ failure = error; }];
	XCTAssertEqual(countMisc(c, @"sendCallDebugInformation"), (NSUInteger)0);
	XCTAssertTrue(failure.length > 0);
}

#pragma mark - sessions

- (void)testSessions_CarryTheIdleTimeoutAndCallsSwitch {
	TGClient *c = MiscClient();
	__block NSArray *sessions = nil;
	__block NSInteger ttl = 0;
	[c sessionsWithInactiveTtlCompletion:^(NSArray *list, NSInteger days){
		sessions = list; ttl = days;
	}];
	answerMisc(c, @"getActiveSessions", @{@"@type" : @"sessions",
			@"inactive_session_ttl_days" : @(30),
			@"sessions" : @[@{@"@type" : @"session", @"id" : @"5",
					@"application_name" : @"Phone",
					@"platform" : @"iOS", @"system_version" : @"12.5",
					@"ip_address" : @"1.2.3.4", @"is_current" : @NO,
					@"can_accept_secret_chats" : @YES,
					@"can_accept_calls" : @NO}]});
	XCTAssertEqual(ttl, (NSInteger)30);
	XCTAssertEqualObjects(sessions[0][@"canAcceptCalls"], @NO);
	XCTAssertEqualObjects(sessions[0][@"name"], @"Phone");
}

- (void)testToggleSessionCanAcceptCalls_SendsTheBooleanAndTheRefusal {
	TGClient *c = MiscClient();
	__block BOOL ok = YES;
	__block NSString *failure = nil;
	[c toggleSession:5 canAcceptCalls:NO completion:^(BOOL good, NSString *error){
		ok = good; failure = error;
	}];
	NSDictionary *request = lastMisc(c, @"toggleSessionCanAcceptCalls");
	XCTAssertEqualObjects(request[@"session_id"], @(5));
	XCTAssertEqualObjects(request[@"can_accept_calls"], @NO);
	answerMisc(c, @"toggleSessionCanAcceptCalls", @{@"@type" : @"error",
			@"code" : @400, @"message" : @"Session not found"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(failure, @"Session not found");
}

- (void)testSetInactiveSessionTtl_SendsTheDaysAndRefusesOutOfRange {
	TGClient *c = MiscClient();
	__block BOOL ok = NO;
	[c setInactiveSessionTtlDays:90 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *request = lastMisc(c, @"setInactiveSessionTtl");
	XCTAssertEqualObjects(request[@"inactive_session_ttl_days"], @(90));
	answerMisc(c, @"setInactiveSessionTtl", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	[c.outbox removeAllObjects];
	__block NSString *failure = nil;
	[c setInactiveSessionTtlDays:0 completion:^(BOOL good, NSString *error){
		failure = error;
	}];
	XCTAssertEqual(countMisc(c, @"setInactiveSessionTtl"), (NSUInteger)0,
				   @"TDLib's 1-366 range is checked before the wire");
	XCTAssertTrue(failure.length > 0);
}

#pragma mark - connected websites

- (void)testConnectedWebsites_ReadsEverySite {
	TGClient *c = MiscClient();
	__block NSArray *sites = nil;
	__block NSString *failure = nil;
	[c connectedWebsitesWithCompletion:^(NSArray *list, NSString *error){
		sites = list; failure = error;
	}];
	answerMisc(c, @"getConnectedWebsites", @{@"@type" : @"connectedWebsites",
			@"websites" : @[@{@"@type" : @"connectedWebsite", @"id" : @"9",
					@"domain_name" : @"example.com", @"bot_user_id" : @(42),
					@"browser" : @"Safari", @"platform" : @"macOS",
					@"ip_address" : @"5.6.7.8", @"location" : @"London",
					@"log_in_date" : @(100), @"last_active_date" : @(200)}]});
	XCTAssertNil(failure);
	XCTAssertEqualObjects(sites[0][@"id"], @9);
	XCTAssertEqualObjects(sites[0][@"domain"], @"example.com");
	XCTAssertEqualObjects(sites[0][@"location"], @"London");
	XCTAssertEqualObjects(sites[0][@"lastActive"], @200);
}

- (void)testConnectedWebsites_RefusalIsTheServersSentence {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c connectedWebsitesWithCompletion:^(NSArray *list, NSString *error){
		failure = error;
	}];
	answerMisc(c, @"getConnectedWebsites", @{@"@type" : @"error",
			@"code" : @400, @"message" : @"Not supported"});
	XCTAssertEqualObjects(failure, @"Not supported");
}

- (void)testDisconnectWebsite_NamesTheWebsiteId {
	TGClient *c = MiscClient();
	__block BOOL ok = NO;
	[c disconnectWebsite:9 completion:^(BOOL good, NSString *error){ ok = good; }];
	XCTAssertEqualObjects(lastMisc(c, @"disconnectWebsite")[@"website_id"], @9);
	answerMisc(c, @"disconnectWebsite", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDisconnectAllWebsites_SendsTheOneRequest {
	TGClient *c = MiscClient();
	__block BOOL ok = NO;
	[c disconnectAllWebsitesWithCompletion:^(BOOL good, NSString *error){ ok = good; }];
	XCTAssertEqual(countMisc(c, @"disconnectAllWebsites"), (NSUInteger)1);
	answerMisc(c, @"disconnectAllWebsites", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - prepared keyboard buttons

- (void)testPreparedKeyboardButton_ReadsTheButtonAndTheRefusal {
	TGClient *c = MiscClient();
	__block NSDictionary *button = nil;
	[c preparedKeyboardButtonFromBot:42 preparedButtonId:@"prep-1"
						  completion:^(NSDictionary *result, NSString *error){
		button = result;
	}];
	NSDictionary *request = lastMisc(c, @"getPreparedKeyboardButton");
	XCTAssertEqualObjects(request[@"bot_user_id"], @(42));
	XCTAssertEqualObjects(request[@"prepared_button_id"], @"prep-1");
	answerMisc(c, @"getPreparedKeyboardButton", @{@"@type" : @"keyboardButton",
			@"text" : @"Send file",
			@"icon_custom_emoji_id" : @0,
			@"style" : @{@"@type" : @"buttonStylePrimary"},
			@"type" : @{@"@type" : @"keyboardButtonTypeText"}});
	XCTAssertEqualObjects(button[@"text"], @"Send file");
	XCTAssertEqualObjects(button[@"type"], @"text");
	XCTAssertEqualObjects(button[@"style"], @"primary");

	[c.outbox removeAllObjects];
	__block NSString *failure = nil;
	[c preparedKeyboardButtonFromBot:42 preparedButtonId:@"gone"
						  completion:^(NSDictionary *result, NSString *error){
		failure = error;
	}];
	answerMisc(c, @"getPreparedKeyboardButton", @{@"@type" : @"error",
			@"code" : @404, @"message" : @"Button not found"});
	XCTAssertEqualObjects(failure, @"Button not found");
}

- (void)testSavePreparedKeyboardButton_BuildsACompleteTextButton {
	TGClient *c = MiscClient();
	__block NSString *preparedId = nil;
	[c savePreparedKeyboardButtonText:@"Send me the file" forUser:42
						   completion:^(NSString *identifier, NSString *error){
		preparedId = identifier;
	}];
	NSDictionary *request = lastMisc(c, @"savePreparedKeyboardButton");
	XCTAssertEqualObjects(request[@"user_id"], @(42));
	NSDictionary *button = request[@"button"];
	XCTAssertEqualObjects(button[@"@type"], @"keyboardButton");
	XCTAssertEqualObjects(button[@"text"], @"Send me the file");
	XCTAssertEqualObjects(button[@"type"][@"@type"], @"keyboardButtonTypeText");
	XCTAssertEqualObjects(button[@"style"][@"@type"], @"buttonStyleDefault");
	XCTAssertEqualObjects(button[@"icon_custom_emoji_id"], @0);
	answerMisc(c, @"savePreparedKeyboardButton",
			   @{@"@type" : @"text", @"text" : @"prepared-7"});
	XCTAssertEqualObjects(preparedId, @"prepared-7");
}

- (void)testSavePreparedKeyboardButton_NoTextSendsNothing {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c savePreparedKeyboardButtonText:@"  " forUser:42
						   completion:^(NSString *identifier, NSString *error){
		failure = error;
	}];
	XCTAssertEqual(countMisc(c, @"savePreparedKeyboardButton"), (NSUInteger)0);
	XCTAssertTrue(failure.length > 0);
}

#pragma mark - poll option properties

- (void)testPollOptionProperties_ReadsEveryFlag {
	TGClient *c = MiscClient();
	__block NSDictionary *properties = nil;
	[c pollOptionProperties:@"opt-1" ofMessage:600 inChat:-1009
				 completion:^(NSDictionary *result, NSString *error){
		properties = result;
	}];
	NSDictionary *request = lastMisc(c, @"getPollOptionProperties");
	XCTAssertEqualObjects(request[@"chat_id"], @(-1009));
	XCTAssertEqualObjects(request[@"message_id"], @(600));
	XCTAssertEqualObjects(request[@"poll_option_id"], @"opt-1");
	answerMisc(c, @"getPollOptionProperties", @{@"@type" : @"pollOptionProperties",
			@"can_be_deleted" : @YES, @"can_be_replied" : @YES,
			@"can_be_replied_in_another_chat" : @NO, @"can_get_link" : @YES});
	XCTAssertEqualObjects(properties[@"canBeDeleted"], @YES);
	XCTAssertEqualObjects(properties[@"canBeReplied"], @YES);
	XCTAssertEqualObjects(properties[@"canBeRepliedInAnotherChat"], @NO);
	XCTAssertEqualObjects(properties[@"canGetLink"], @YES);
}

- (void)testPollOptionProperties_RefusalIsTheServersSentence {
	TGClient *c = MiscClient();
	__block NSString *failure = nil;
	[c pollOptionProperties:@"opt-1" ofMessage:600 inChat:-1009
				 completion:^(NSDictionary *result, NSString *error){
		failure = error;
	}];
	answerMisc(c, @"getPollOptionProperties", @{@"@type" : @"error",
			@"code" : @400, @"message" : @"Poll option not found"});
	XCTAssertEqualObjects(failure, @"Poll option not found");
}

@end
