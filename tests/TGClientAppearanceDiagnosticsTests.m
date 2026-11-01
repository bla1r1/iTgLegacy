//
// TGClientAppearanceDiagnosticsTests.m - the background catalogue and the
// network/diagnostics panel.
//
// The wire shapes matter more than usual here: these requests carry nested
// TDLib objects (BackgroundType, NetworkType, NetworkStatisticsEntry) whose
// fields are easy to flatten into something Telegram accepts but the screen
// then draws wrong. The fixtures below are the shapes the server answers.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGDatabaseKey.h"
#import "TGBase64.h"

@interface TGClientAppearanceDiagnosticsTests : XCTestCase @end

static TGClient *ADClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c removeAllFileWaiters];
	[TGDatabaseKey storeKey:nil error:nil];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *ADDecode(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *ADLast(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = ADDecode(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static NSUInteger ADCount(TGClient *c, NSString *type) {
	NSUInteger count = 0;
	for (NSData *data in c.outbox)
		if ([ADDecode(data)[@"@type"] isEqualToString:type])
			count++;
	return count;
}

/// Answers the oldest request of this type that is still waiting. A client
/// that follows an async graph sends a second request before the test answers
/// the first, so "the last one in the outbox" is not always the one to answer.
static void ADAnswer(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = ADDecode(data);
		NSString *extra = request[@"@extra"];
		if ([request[@"@type"] isEqualToString:type] && extra &&
			c.pendingRequests[extra]){
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

/// Literal dictionaries answer nil one level down; a real TDLib answer is
/// parsed, so round-trip every fixture through JSON first.
static NSDictionary *ADPlain(NSDictionary *dictionary) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *ADBackground(void) {
	return ADPlain(@{
		@"@type" : @"background",
		@"id" : @(11),
		@"is_default" : @YES,
		@"is_dark" : @NO,
		@"name" : @"cat",
		@"document" : @{@"thumbnail" : @{@"file" : @{@"id" : @(77)}}},
		@"type" : @{
			@"@type" : @"backgroundTypePattern",
			@"fill" : @{@"@type" : @"backgroundFillGradient",
						@"top_color" : @(0x336699)},
			@"intensity" : @(50),
			@"is_inverted" : @NO,
			@"is_moving" : @NO,
		},
	});
}

@implementation TGClientAppearanceDiagnosticsTests

#pragma mark - backgrounds

- (void)testInstalledBackgrounds_ReadTheDarkListAndFlattenTheRecord {
	TGClient *c = ADClient();
	__block NSArray *got = nil;
	__block NSString *error = nil;
	[c installedBackgroundsForDarkTheme:YES completion:^(NSArray *backgrounds,
														 NSString *why){
		got = backgrounds; error = why;
	}];
	NSDictionary *request = ADLast(c, @"getInstalledBackgrounds");
	XCTAssertEqualObjects(request[@"for_dark_theme"], @YES);

	ADAnswer(c, @"getInstalledBackgrounds", @{@"@type" : @"backgrounds",
			@"backgrounds" : @[ADBackground()]});
	XCTAssertNil(error);
	XCTAssertEqual(got.count, (NSUInteger)1);
	XCTAssertEqualObjects(got[0][@"id"], @(11));
	XCTAssertEqualObjects(got[0][@"name"], @"cat");
	XCTAssertEqualObjects(got[0][@"isDefault"], @YES);
	XCTAssertEqualObjects(got[0][@"typeName"], @"pattern");
	XCTAssertEqualObjects(got[0][@"fileId"], @(77));
	XCTAssertEqualObjects(got[0][@"fillColour"], @(0x336699));
}

- (void)testInstalledBackgrounds_AnErrorKeepsTheServersSentence {
	TGClient *c = ADClient();
	__block NSArray *got = @[];
	__block NSString *error = nil;
	[c installedBackgroundsForDarkTheme:NO completion:^(NSArray *backgrounds,
														NSString *why){
		got = backgrounds; error = why;
	}];
	ADAnswer(c, @"getInstalledBackgrounds", @{@"@type" : @"error",
			@"message" : @"BACKGROUNDS_UNAVAILABLE"});
	XCTAssertEqual(got.count, (NSUInteger)0);
	XCTAssertEqualObjects(error, @"BACKGROUNDS_UNAVAILABLE");
}

- (void)testSearchBackground_SendsTheNameAndFlattensTheResult {
	TGClient *c = ADClient();
	__block NSDictionary *got = nil;
	[c searchBackgroundNamed:@"cat" completion:^(NSDictionary *background,
												 NSString *error){
		got = background;
	}];
	XCTAssertEqualObjects(ADLast(c, @"searchBackground")[@"name"], @"cat");
	ADAnswer(c, @"searchBackground", ADBackground());
	XCTAssertEqualObjects(got[@"name"], @"cat");
	XCTAssertEqualObjects(got[@"type"][@"@type"], @"backgroundTypePattern");
}

- (void)testSearchBackground_AnErrorAnswersNilAndTheMessage {
	TGClient *c = ADClient();
	__block NSDictionary *got = @{};
	__block NSString *error = nil;
	[c searchBackgroundNamed:@"missing" completion:^(NSDictionary *background,
													NSString *why){
		got = background; error = why;
	}];
	ADAnswer(c, @"searchBackground", @{@"@type" : @"error",
			@"message" : @"BACKGROUND_NOT_FOUND"});
	XCTAssertNil(got);
	XCTAssertEqualObjects(error, @"BACKGROUND_NOT_FOUND");
}

- (void)testSetDefaultBackground_SendsTheRemoteIdAndKeepsTheType {
	TGClient *c = ADClient();
	__block NSDictionary *got = nil;
	[c setDefaultBackground:ADBackground() forDarkTheme:YES
			completion:^(NSDictionary *installed, NSString *error){
		got = installed;
	}];
	NSDictionary *request = ADLast(c, @"setDefaultBackground");
	XCTAssertEqualObjects(request[@"background"][@"@type"], @"inputBackgroundRemote");
	XCTAssertEqualObjects(request[@"background"][@"background_id"], @(11));
	XCTAssertEqualObjects(request[@"for_dark_theme"], @YES);
	XCTAssertEqualObjects(request[@"type"][@"@type"], @"backgroundTypePattern");
	ADAnswer(c, @"setDefaultBackground", ADBackground());
	XCTAssertEqualObjects(got[@"id"], @(11));
}

- (void)testSetDefaultBackground_AnErrorKeepsTheRefusal {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c setDefaultBackground:ADBackground() forDarkTheme:NO
			completion:^(NSDictionary *installed, NSString *why){
		error = why;
	}];
	ADAnswer(c, @"setDefaultBackground", @{@"@type" : @"error",
			@"message" : @"BACKGROUND_INVALID"});
	XCTAssertEqualObjects(error, @"BACKGROUND_INVALID");
}

- (void)testSetDefaultBackground_WithoutAnIdSendsNothing {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c setDefaultBackground:@{@"name" : @"nameless"} forDarkTheme:NO
			completion:^(NSDictionary *installed, NSString *why){
		error = why;
	}];
	XCTAssertEqual(ADCount(c, @"setDefaultBackground"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

- (void)testRemoveInstalledBackground_NamesTheId {
	TGClient *c = ADClient();
	__block BOOL ok = NO;
	[c removeInstalledBackground:11 completion:^(BOOL good, NSString *error){
		ok = good;
	}];
	XCTAssertEqualObjects(ADLast(c, @"removeInstalledBackground")[@"background_id"],
			@(11));
	ADAnswer(c, @"removeInstalledBackground", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testResetInstalledBackgrounds_ReportsTheRefusal {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c resetInstalledBackgroundsWithCompletion:^(BOOL ok, NSString *why){
		error = why;
	}];
	XCTAssertNotNil(ADLast(c, @"resetInstalledBackgrounds"));
	ADAnswer(c, @"resetInstalledBackgrounds", @{@"@type" : @"error",
			@"message" : @"CANNOT_RESET"});
	XCTAssertEqualObjects(error, @"CANNOT_RESET");
}

- (void)testDeleteDefaultBackground_CarriesTheTheme {
	TGClient *c = ADClient();
	__block BOOL ok = NO;
	[c deleteDefaultBackgroundForDarkTheme:YES completion:^(BOOL good, NSString *error){
		ok = good;
	}];
	XCTAssertEqualObjects(ADLast(c, @"deleteDefaultBackground")[@"for_dark_theme"],
			@YES);
	ADAnswer(c, @"deleteDefaultBackground", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testBackgroundUrl_SendsTheNameAndTypeAndReturnsTheAddress {
	TGClient *c = ADClient();
	__block NSString *url = nil;
	[c backgroundUrlForBackground:ADBackground() completion:^(NSString *address,
															  NSString *error){
		url = address;
	}];
	NSDictionary *request = ADLast(c, @"getBackgroundUrl");
	XCTAssertEqualObjects(request[@"name"], @"cat");
	XCTAssertEqualObjects(request[@"type"][@"@type"], @"backgroundTypePattern");
	ADAnswer(c, @"getBackgroundUrl", @{@"@type" : @"httpUrl",
			@"url" : @"https://cdn.example/cat.jpg"});
	XCTAssertEqualObjects(url, @"https://cdn.example/cat.jpg");
}

- (void)testBackgroundUrl_AThemeAndANamelessBackgroundAreRefusedLocally {
	TGClient *c = ADClient();
	__block NSString *themeError = nil;
	[c backgroundUrlForBackground:@{@"name" : @"night",
			@"typeName" : @"chatTheme",
			@"type" : @{@"@type" : @"backgroundTypeChatTheme"}}
			completion:^(NSString *url, NSString *why){ themeError = why; }];
	__block NSString *nameError = nil;
	[c backgroundUrlForBackground:@{@"typeName" : @"wallpaper",
			@"type" : @{@"@type" : @"backgroundTypeWallpaper"}}
			completion:^(NSString *url, NSString *why){ nameError = why; }];
	XCTAssertEqual(ADCount(c, @"getBackgroundUrl"), (NSUInteger)0);
	XCTAssertNotNil(themeError);
	XCTAssertNotNil(nameError);
}

#pragma mark - state and configuration

- (void)testCurrentState_FlattensAuthorizationConnectionAndOptions {
	TGClient *c = ADClient();
	__block NSArray *got = nil;
	[c currentStateWithCompletion:^(NSArray *updates, NSString *error){ got = updates; }];
	XCTAssertNotNil(ADLast(c, @"getCurrentState"));
	ADAnswer(c, @"getCurrentState", @{@"@type" : @"updates", @"updates" : @[
			@{@"@type" : @"authorizationStateReady"},
			@{@"@type" : @"connectionStateReady"},
			@{@"@type" : @"updateOption", @"name" : @"version",
			  @"value" : @{@"@type" : @"jsonValueString", @"value" : @"1.0"}},
	]});
	XCTAssertEqual(got.count, (NSUInteger)3);
	XCTAssertEqualObjects(got[0][@"type"], @"authorizationStateReady");
	XCTAssertEqualObjects(got[0][@"summary"], @"Ready");
	XCTAssertEqualObjects(got[1][@"summary"], @"Ready");
	XCTAssertEqualObjects(got[2][@"summary"], @"version = 1.0");
}

- (void)testCurrentState_AnErrorIsEmptyAndCarriesTheMessage {
	TGClient *c = ADClient();
	__block NSArray *got = @[];
	__block NSString *error = nil;
	[c currentStateWithCompletion:^(NSArray *updates, NSString *why){
		got = updates; error = why;
	}];
	ADAnswer(c, @"getCurrentState", @{@"@type" : @"error",
			@"message" : @"STATE_UNAVAILABLE"});
	XCTAssertEqual(got.count, (NSUInteger)0);
	XCTAssertEqualObjects(error, @"STATE_UNAVAILABLE");
}

- (void)testApplicationConfig_UnwrapsNestedJsonValues {
	TGClient *c = ADClient();
	__block NSDictionary *got = nil;
	[c applicationConfigWithCompletion:^(NSDictionary *config, NSString *error){
		got = config;
	}];
	XCTAssertNotNil(ADLast(c, @"getApplicationConfig"));
	ADAnswer(c, @"getApplicationConfig", @{@"@type" : @"jsonValueObject",
			@"members" : @[
				@{@"name" : @"language_pack_version",
				  @"value" : @{@"@type" : @"jsonValueNumber", @"value" : @(3)}},
				@{@"name" : @"nested",
				  @"value" : @{@"@type" : @"jsonValueObject", @"members" : @[
						@{@"name" : @"enabled",
						  @"value" : @{@"@type" : @"jsonValueBoolean", @"value" : @YES}},
				  ]}},
			]});
	XCTAssertEqualObjects(got[@"language_pack_version"], @(3));
	XCTAssertEqualObjects(got[@"nested"][@"enabled"], @YES);
}

- (void)testApplicationConfig_AnErrorAnswersNil {
	TGClient *c = ADClient();
	__block NSDictionary *got = @{};
	__block NSString *error = nil;
	[c applicationConfigWithCompletion:^(NSDictionary *config, NSString *why){
		got = config; error = why;
	}];
	ADAnswer(c, @"getApplicationConfig", @{@"@type" : @"error",
			@"message" : @"CONFIG_UNAVAILABLE"});
	XCTAssertNil(got);
	XCTAssertEqualObjects(error, @"CONFIG_UNAVAILABLE");
}

- (void)testDatabaseStatistics_ReturnsTheServersReport {
	TGClient *c = ADClient();
	__block NSString *got = nil;
	[c databaseStatisticsWithCompletion:^(NSString *statistics, NSString *error){
		got = statistics;
	}];
	XCTAssertNotNil(ADLast(c, @"getDatabaseStatistics"));
	ADAnswer(c, @"getDatabaseStatistics", @{@"@type" : @"databaseStatistics",
			@"statistics" : @"sqlite3 3.8\npages 120"});
	XCTAssertEqualObjects(got, @"sqlite3 3.8\npages 120");
}

- (void)testDatabaseStatistics_AnErrorAnswersNil {
	TGClient *c = ADClient();
	__block NSString *got = @"";
	__block NSString *error = nil;
	[c databaseStatisticsWithCompletion:^(NSString *statistics, NSString *why){
		got = statistics; error = why;
	}];
	ADAnswer(c, @"getDatabaseStatistics", @{@"@type" : @"error",
			@"message" : @"DB_UNAVAILABLE"});
	XCTAssertNil(got);
	XCTAssertEqualObjects(error, @"DB_UNAVAILABLE");
}

#pragma mark - network

- (void)testSetNetworkType_SendsTheObjectAndKeepsTheRefusal {
	TGClient *c = ADClient();
	__block BOOL ok = NO;
	[c setNetworkType:@"wifi" completion:^(BOOL good, NSString *error){ ok = good; }];
	XCTAssertEqualObjects(ADLast(c, @"setNetworkType")[@"type"][@"@type"],
			@"networkTypeWiFi");
	ADAnswer(c, @"setNetworkType", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	__block NSString *error = nil;
	[c setNetworkType:@"mobile" completion:^(BOOL good, NSString *why){ error = why; }];
	ADAnswer(c, @"setNetworkType", @{@"@type" : @"error",
			@"message" : @"NETWORK_TYPE_INVALID"});
	XCTAssertEqualObjects(error, @"NETWORK_TYPE_INVALID");
}

- (void)testSetNetworkType_AnUnknownNameSendsNothing {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c setNetworkType:@"carrier-pigeon" completion:^(BOOL ok, NSString *why){
		error = why;
	}];
	XCTAssertEqual(ADCount(c, @"setNetworkType"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

- (void)testAddNetworkStatistics_SendsACallEntry {
	TGClient *c = ADClient();
	__block BOOL ok = NO;
	[c addNetworkStatisticsForNetworkType:@"roaming" sentBytes:100
			receivedBytes:200 duration:3.5 completion:^(BOOL good, NSString *error){
		ok = good;
	}];
	NSDictionary *request = ADLast(c, @"addNetworkStatistics");
	XCTAssertEqualObjects(request[@"entry"][@"@type"], @"networkStatisticsEntryCall");
	XCTAssertEqualObjects(request[@"entry"][@"network_type"][@"@type"],
			@"networkTypeMobileRoaming");
	XCTAssertEqualObjects(request[@"entry"][@"sent_bytes"], @(100));
	XCTAssertEqualObjects(request[@"entry"][@"received_bytes"], @(200));
	XCTAssertEqualObjects(request[@"entry"][@"duration"], @(3.5));
	ADAnswer(c, @"addNetworkStatistics", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testAddNetworkStatistics_AnErrorKeepsTheRefusal {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c addNetworkStatisticsForNetworkType:@"wifi" sentBytes:1 receivedBytes:2
			duration:0.5 completion:^(BOOL ok, NSString *why){ error = why; }];
	ADAnswer(c, @"addNetworkStatistics", @{@"@type" : @"error",
			@"message" : @"STATS_REFUSED"});
	XCTAssertEqualObjects(error, @"STATS_REFUSED");
}

#pragma mark - statistical graph

- (void)testStatisticalGraph_ParsesPointsIntoLines {
	TGClient *c = ADClient();
	__block NSDictionary *got = nil;
	[c statisticalGraphForChat:-100 token:@"token" x:0
			completion:^(NSDictionary *graph, NSString *error){ got = graph; }];
	NSDictionary *request = ADLast(c, @"getStatisticalGraph");
	XCTAssertEqualObjects(request[@"chat_id"], @(-100));
	XCTAssertEqualObjects(request[@"token"], @"token");
	XCTAssertEqualObjects(request[@"x"], @(0));

	ADAnswer(c, @"getStatisticalGraph", @{@"@type" : @"statisticalGraphData",
			@"json_data" : @"{\"points\":[{\"x\":1,\"y\":2},{\"x\":2,\"y\":4}],"
							"\"zoom_token\":\"z\"}",
			@"zoom_token" : @"z"});
	XCTAssertEqualObjects(got[@"kind"], @"data");
	XCTAssertEqualObjects(got[@"zoomToken"], @"z");
	XCTAssertEqual([got[@"json"][@"points"] count], (NSUInteger)2);
	NSArray *lines = got[@"lines"];
	XCTAssertEqual(lines.count, (NSUInteger)3);
	XCTAssertTrue([lines[0] hasPrefix:@"2 points"]);
	XCTAssertTrue([lines[1] hasPrefix:@"1 "]);
}

- (void)testStatisticalGraph_FollowsAnAsyncToken {
	TGClient *c = ADClient();
	__block NSDictionary *got = nil;
	[c statisticalGraphForChat:-100 token:@"first" x:0
			completion:^(NSDictionary *graph, NSString *error){ got = graph; }];
	ADAnswer(c, @"getStatisticalGraph", @{@"@type" : @"statisticalGraphAsync",
			@"token" : @"second"});
	// The follow-up is in the outbox now, carrying the token Telegram named.
	XCTAssertEqualObjects(ADLast(c, @"getStatisticalGraph")[@"token"], @"second");
	XCTAssertEqual(ADCount(c, @"getStatisticalGraph"), (NSUInteger)2);
	ADAnswer(c, @"getStatisticalGraph", @{@"@type" : @"statisticalGraphData",
			@"json_data" : @"{\"points\":[{\"x\":1,\"y\":1}]}", @"zoom_token" : @""});
	XCTAssertEqualObjects(got[@"kind"], @"data");
	XCTAssertEqual([got[@"json"][@"points"] count], (NSUInteger)1);
}

- (void)testStatisticalGraph_AnErrorKeepsTheMessage {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c statisticalGraphForChat:-100 token:@"token" x:0
			completion:^(NSDictionary *graph, NSString *why){ error = why; }];
	ADAnswer(c, @"getStatisticalGraph", @{@"@type" : @"statisticalGraphError",
			@"error_message" : @"STATISTICS_TOO_OLD"});
	XCTAssertEqualObjects(error, @"STATISTICS_TOO_OLD");
}

- (void)testStatisticalGraph_WithoutATokenSendsNothing {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c statisticalGraphForChat:-100 token:@"" x:0
			completion:^(NSDictionary *graph, NSString *why){ error = why; }];
	XCTAssertEqual(ADCount(c, @"getStatisticalGraph"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

#pragma mark - custom request

- (void)testSendCustomRequest_CarriesMethodAndParameters {
	TGClient *c = ADClient();
	__block NSString *got = nil;
	[c sendCustomRequestMethod:@"getOption"
					parameters:@"{\"name\":\"version\"}"
					completion:^(NSString *result, NSString *error){ got = result; }];
	NSDictionary *request = ADLast(c, @"sendCustomRequest");
	XCTAssertEqualObjects(request[@"method"], @"getOption");
	XCTAssertEqualObjects(request[@"parameters"], @"{\"name\":\"version\"}");
	ADAnswer(c, @"sendCustomRequest", @{@"@type" : @"customRequestResult",
			@"result" : @"{\"@type\":\"optionValueString\",\"value\":\"1.0\"}"});
	XCTAssertEqualObjects(got, @"{\"@type\":\"optionValueString\",\"value\":\"1.0\"}");
}

- (void)testSendCustomRequest_AnEmptyMethodSendsNothing {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c sendCustomRequestMethod:@"" parameters:@"{}"
					completion:^(NSString *result, NSString *why){ error = why; }];
	XCTAssertEqual(ADCount(c, @"sendCustomRequest"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

#pragma mark - database key

- (void)testSetDatabaseEncryptionKey_SavesAndSendsTheBase64Key {
	TGClient *c = ADClient();
	NSData *key = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
	__block BOOL ok = NO;
	[c setDatabaseEncryptionKey:key completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *request = ADLast(c, @"setDatabaseEncryptionKey");
	XCTAssertEqualObjects(request[@"new_encryption_key"], TGBase64Encode(key));
	ADAnswer(c, @"setDatabaseEncryptionKey", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertEqualObjects([TGDatabaseKey currentKey], key);
	XCTAssertTrue([c databaseEncryptionKeyIsSet]);
}

- (void)testSetDatabaseEncryptionKey_AnEmptyKeySendsNothing {
	TGClient *c = ADClient();
	__block NSString *error = nil;
	[c setDatabaseEncryptionKey:[NSData data] completion:^(BOOL ok, NSString *why){
		error = why;
	}];
	XCTAssertEqual(ADCount(c, @"setDatabaseEncryptionKey"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

- (void)testSetDatabaseEncryptionKey_RefusalRestoresTheOldKey {
	TGClient *c = ADClient();
	NSData *old = [@"old-key" dataUsingEncoding:NSUTF8StringEncoding];
	[TGDatabaseKey storeKey:old error:nil];
	NSData *changed = [@"new-key" dataUsingEncoding:NSUTF8StringEncoding];
	__block NSString *error = nil;
	[c setDatabaseEncryptionKey:changed completion:^(BOOL ok, NSString *why){
		error = why;
	}];
	ADAnswer(c, @"setDatabaseEncryptionKey", @{@"@type" : @"error",
			@"message" : @"KEY_INVALID"});
	XCTAssertEqualObjects(error, @"KEY_INVALID");
	XCTAssertEqualObjects([TGDatabaseKey currentKey], old);
}

@end
