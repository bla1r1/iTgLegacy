// TGClientAutosaveContactsTests.m - gallery autosave settings, imported
// contacts and the application download link.
//
// All three are answers behind a settings row. The wire shape is pinned here;
// the screens are the callers tdlib_wired.py checks.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientAutosaveContactsTests : XCTestCase @end

static TGClient *ACClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *ACDecode(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *ACLast(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = ACDecode(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static void ACAnswer(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = ACDecode(data);
		if (request[@"@extra"])
			sent = request;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *ACPlain(NSDictionary *dictionary) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientAutosaveContactsTests

// ─── autosave ────────────────────────────────────────────────────────────────

- (NSDictionary *)autosaveFixture {
	return @{
		@"@type" : @"autosaveSettings",
		@"private_chat_settings" : @{
			@"@type" : @"scopeAutosaveSettings",
			@"autosave_photos" : @YES,
			@"autosave_videos" : @NO,
			@"max_video_file_size" : @(1024 * 1024),
		},
		@"group_settings" : @{
			@"@type" : @"scopeAutosaveSettings",
			@"autosave_photos" : @NO,
			@"autosave_videos" : @YES,
			@"max_video_file_size" : @(2048 * 1024),
		},
		@"channel_settings" : @{
			@"@type" : @"scopeAutosaveSettings",
			@"autosave_photos" : @YES,
			@"autosave_videos" : @YES,
			@"max_video_file_size" : @(4096 * 1024),
		},
		@"exceptions" : @[
			@{
				@"@type" : @"autosaveSettingsException",
				@"chat_id" : @(77),
				@"settings" : @{
					@"@type" : @"scopeAutosaveSettings",
					@"autosave_photos" : @NO,
					@"autosave_videos" : @YES,
					@"max_video_file_size" : @(8192 * 1024),
				},
			},
		],
	};
}

- (void)testAutosaveSettings_FlattensTheThreeScopesAndExceptions {
	TGClient *c = ACClient();
	__block NSDictionary *got = nil;
	[c autosaveSettingsWithCompletion:^(NSDictionary *settings){ got = settings; }];

	XCTAssertNotNil(ACLast(c, @"getAutosaveSettings"));
	ACAnswer(c, ACPlain([self autosaveFixture]));

	XCTAssertEqualObjects(got[@"private"][@"photos"], @YES);
	XCTAssertEqualObjects(got[@"private"][@"videos"], @NO);
	XCTAssertEqualObjects(got[@"private"][@"maxVideoSize"], @(1024 * 1024));
	XCTAssertEqualObjects(got[@"groups"][@"videos"], @YES);
	XCTAssertEqualObjects([got[@"exceptions"] firstObject][@"chatId"], @(77));
	XCTAssertEqualObjects([got[@"exceptions"] firstObject][@"photos"], @NO);
}

- (void)testAutosaveSettings_AnErrorIsNil {
	TGClient *c = ACClient();
	__block NSDictionary *got = @{};
	[c autosaveSettingsWithCompletion:^(NSDictionary *settings){ got = settings; }];
	ACAnswer(c, @{@"@type" : @"error", @"code" : @(400), @"message" : @"NO_AUTOSAVE"});
	XCTAssertNil(got);
}

- (void)testSetAutosaveScope_SendsTheScopeSettings {
	TGClient *c = ACClient();
	__block BOOL ok = NO;
	[c setAutosaveSettingsForScope:@"groups" photos:YES videos:NO
					  maxVideoSize:2048 completion:^(BOOL result){ ok = result; }];

	NSDictionary *asked = ACLast(c, @"setAutosaveSettings");
	XCTAssertEqualObjects(asked[@"scope"][@"@type"], @"autosaveSettingsScopeGroupChats");
	XCTAssertEqualObjects(asked[@"settings"][@"autosave_photos"], @YES);
	XCTAssertEqualObjects(asked[@"settings"][@"autosave_videos"], @NO);
	XCTAssertEqualObjects(asked[@"settings"][@"max_video_file_size"], @(2048));
	ACAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testClearAutosaveExceptions_SendsTheRequest {
	TGClient *c = ACClient();
	__block BOOL ok = NO;
	[c clearAutosaveSettingsExceptionsWithCompletion:^(BOOL result){ ok = result; }];
	XCTAssertNotNil(ACLast(c, @"clearAutosaveSettingsExceptions"));
	ACAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

// ─── imported contacts ───────────────────────────────────────────────────────

- (void)testImportedContactCount_ReadsTheCount {
	TGClient *c = ACClient();
	__block NSInteger got = -1;
	[c importedContactCountWithCompletion:^(NSInteger count){ got = count; }];
	XCTAssertNotNil(ACLast(c, @"getImportedContactCount"));
	ACAnswer(c, ACPlain(@{@"@type" : @"count", @"count" : @(12)}));
	XCTAssertEqual(got, 12);
}

- (void)testChangeImportedContacts_SendsTheRowsAndCountsTheAnswer {
	TGClient *c = ACClient();
	__block NSInteger imported = -1;
	__block NSArray *userIds = nil;
	[c changeImportedContacts:@[
		@{@"phone_number" : @"+15550001111", @"first_name" : @"Jane", @"last_name" : @"Doe"},
		@{@"phone_number" : @"+15550002222", @"first_name" : @"Richard", @"last_name" : @"Roe"},
		@{@"phone_number" : @"", @"first_name" : @"No", @"last_name" : @"Phone"},
	] completion:^(NSInteger count, NSArray *ids){
		imported = count;
		userIds = ids;
	}];

	NSDictionary *asked = ACLast(c, @"changeImportedContacts");
	XCTAssertEqual([asked[@"contacts"] count], (NSUInteger)2,
				   @"a row without a phone number is not sent");
	XCTAssertEqualObjects(asked[@"contacts"][0][@"phone_number"], @"+15550001111");
	XCTAssertEqualObjects(asked[@"contacts"][0][@"first_name"], @"Jane");
	XCTAssertEqualObjects(asked[@"contacts"][0][@"@type"], @"importedContact");

	ACAnswer(c, ACPlain(@{
		@"@type" : @"importedContacts",
		@"user_ids" : @[@(2001), @(2002)],
		@"importer_count" : @[@(1), @(2)],
	}));
	XCTAssertEqual(imported, 2);
	XCTAssertEqualObjects(userIds, (@[@(2001), @(2002)]));
}

// ─── application link ────────────────────────────────────────────────────────

- (void)testApplicationDownloadLink_ReadsTheUrl {
	TGClient *c = ACClient();
	__block NSString *got = nil;
	[c applicationDownloadLinkWithCompletion:^(NSString *url){ got = url; }];
	XCTAssertNotNil(ACLast(c, @"getApplicationDownloadLink"));
	ACAnswer(c, ACPlain(@{@"@type" : @"httpUrl",
						  @"url" : @"https://telegram.org/dl/desktop"}));
	XCTAssertEqualObjects(got, @"https://telegram.org/dl/desktop");
}

@end
