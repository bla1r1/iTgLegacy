// TGClientSearchLanguageTests.m - the search, link, language and formatting
// requests behind the search screen, the link sheet and Settings > Language.
//
// Each test drives the public method the screen calls and checks the wire
// shape TDLib gets, then feeds back the answer the screen reads. The search
// screen itself is UIKit and is checked on a device; what can be pinned down
// here is that every row has a request behind it and every answer lands in a
// field the row shows.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientSearchLanguageTests : XCTestCase @end

static TGClient *SL(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeSL(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastSL(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeSL(d)[@"@type"] isEqualToString:type])
			found = decodeSL(d);
	return found;
}

static NSDictionary *lastRequestedSL(TGClient *c) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeSL(d)[@"@extra"])
			sent = decodeSL(d);
	return sent;
}

static void answerSL(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = lastRequestedSL(c);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainSL(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientSearchLanguageTests

#pragma mark - hashtags

- (void)testSearchHashtags_SendsThePrefixWithoutTheHash {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c searchHashtags:@"#tele" limit:5 completion:^(NSArray *tags){ got = tags; }];

	NSDictionary *r = lastSL(c, @"searchHashtags");
	XCTAssertEqualObjects(r[@"prefix"], @"tele");
	XCTAssertEqualObjects(r[@"limit"], @(5));

	answerSL(c, plainSL(@{@"@type" : @"hashtags",
						  @"hashtags" : @[@"telegram", @"telegraph"]}));
	XCTAssertEqualObjects(got, (@[@"telegram", @"telegraph"]));
}

- (void)testSearchedForTags_EmptyPrefixIsTheRecentList {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c searchedForTagsWithPrefix:@"" limit:20 completion:^(NSArray *tags){ got = tags; }];

	NSDictionary *r = lastSL(c, @"getSearchedForTags");
	XCTAssertEqualObjects(r[@"tag_prefix"], @"");
	XCTAssertEqualObjects(r[@"limit"], @(20));
	answerSL(c, @{@"@type" : @"hashtags", @"hashtags" : @[@"news"]});
	XCTAssertEqualObjects(got, (@[@"news"]));
}

- (void)testRecentHashtags_ReadsTheSearchedList {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c recentHashtagsWithCompletion:^(NSArray *tags){ got = tags; }];
	XCTAssertEqualObjects(lastSL(c, @"getSearchedForTags")[@"tag_prefix"], @"");
	answerSL(c, @{@"@type" : @"hashtags", @"hashtags" : @[@"moscow"]});
	XCTAssertEqualObjects(got, (@[@"moscow"]));
}

- (void)testRemoveRecentHashtag_IsOneShot {
	TGClient *c = SL();
	[c removeRecentHashtag:@"moscow"];
	NSDictionary *r = lastSL(c, @"removeRecentHashtag");
	XCTAssertEqualObjects(r[@"hashtag"], @"moscow");
	XCTAssertNil(r[@"@extra"]);
}

- (void)testRemoveSearchedForTag_IsOneShot {
	TGClient *c = SL();
	[c removeSearchedForTag:@"news"];
	NSDictionary *r = lastSL(c, @"removeSearchedForTag");
	XCTAssertEqualObjects(r[@"tag"], @"news");
	XCTAssertNil(r[@"@extra"]);
}

- (void)testClearSearchedForTags_IsOneShot {
	TGClient *c = SL();
	[c clearSearchedForTags];
	XCTAssertNotNil(lastSL(c, @"clearSearchedForTags"));
	XCTAssertNil(lastSL(c, @"clearSearchedForTags")[@"@extra"]);
}

#pragma mark - public posts

- (void)testPublicPostSearchLimits_AreReadIntoTheScreenShape {
	TGClient *c = SL();
	__block NSDictionary *got = nil;
	[c publicPostSearchLimitsForQuery:@"telegram"
						   completion:^(NSDictionary *limits){ got = limits; }];
	XCTAssertEqualObjects(lastSL(c, @"getPublicPostSearchLimits")[@"query"], @"telegram");

	answerSL(c, plainSL(@{@"@type" : @"publicPostSearchLimits",
						  @"daily_free_query_count" : @(10),
						  @"remaining_free_query_count" : @(3),
						  @"next_free_query_in" : @(120),
						  @"star_count" : @(5),
						  @"is_current_query_free" : @YES}));
	XCTAssertEqualObjects(got[@"remainingFree"], @(3));
	XCTAssertEqualObjects(got[@"nextFreeIn"], @(120));
	XCTAssertEqualObjects(got[@"currentIsFree"], @YES);
}

- (void)testSearchPublicPosts_CarriesTheOffsetStarsAndAnswerLimits {
	TGClient *c = SL();
	__block NSArray *messages = nil;
	__block NSString *next = nil;
	__block NSDictionary *limits = nil;
	__block BOOL exceeded = YES;
	[c searchPublicPosts:@"telegram" offset:@"20" limit:20 starCount:2
			  completion:^(NSArray *m, NSString *n, NSDictionary *l, BOOL x){
		messages = m; next = n; limits = l; exceeded = x;
	}];
	NSDictionary *r = lastSL(c, @"searchPublicPosts");
	XCTAssertEqualObjects(r[@"query"], @"telegram");
	XCTAssertEqualObjects(r[@"offset"], @"20");
	XCTAssertEqualObjects(r[@"star_count"], @(2));

	answerSL(c, plainSL(@{@"@type" : @"foundPublicPosts",
						  @"messages" : @[@{@"id" : @(7), @"chat_id" : @(9)}],
						  @"next_offset" : @"40",
						  @"are_limits_exceeded" : @NO,
						  @"search_limits" : @{@"daily_free_query_count" : @(10),
											   @"remaining_free_query_count" : @(0),
											   @"next_free_query_in" : @(60),
											   @"star_count" : @(5),
											   @"is_current_query_free" : @NO}}));
	XCTAssertEqual(messages.count, 1);
	XCTAssertEqualObjects(next, @"40");
	XCTAssertEqualObjects(limits[@"nextFreeIn"], @(60));
	XCTAssertFalse(exceeded);
}

- (void)testSearchPublicPosts_ARefusalIsMarkedExceeded {
	TGClient *c = SL();
	__block BOOL exceeded = NO;
	[c searchPublicPosts:@"x" offset:@"" limit:5 starCount:0
			  completion:^(NSArray *m, NSString *n, NSDictionary *l, BOOL x){ exceeded = x; }];
	answerSL(c, @{@"@type" : @"error", @"code" : @(429), @"message" : @"Too Many Requests"});
	XCTAssertTrue(exceeded);
}

#pragma mark - links

- (void)testExternalLink_AsksWithTheWriteAccessFlag {
	TGClient *c = SL();
	__block NSString *got = nil;
	[c externalLinkForURL:@"https://example.com/login" allowWriteAccess:YES
			   completion:^(NSString *link){ got = link; }];
	NSDictionary *r = lastSL(c, @"getExternalLink");
	XCTAssertEqualObjects(r[@"link"], @"https://example.com/login");
	XCTAssertEqualObjects(r[@"allow_write_access"], @YES);
	answerSL(c, @{@"@type" : @"httpUrl", @"url" : @"https://example.com/authorized"});
	XCTAssertEqualObjects(got, @"https://example.com/authorized");
}

- (void)testExternalLinkInfo_ConfirmationNamesTheDomainAndBot {
	TGClient *c = SL();
	__block NSDictionary *got = nil;
	[c externalLinkInfoForURL:@"https://example.com" completion:^(NSDictionary *info){ got = info; }];
	answerSL(c, plainSL(@{@"@type" : @"loginUrlInfoRequestConfirmation",
						  @"url" : @"https://example.com",
						  @"domain" : @"example.com",
						  @"bot_user_id" : @(44),
						  @"request_write_access" : @YES}));
	XCTAssertEqualObjects(got[@"kind"], @"confirm");
	XCTAssertEqualObjects(got[@"domain"], @"example.com");
	XCTAssertEqualObjects(got[@"botUserId"], @(44));
	XCTAssertEqualObjects(got[@"requestWriteAccess"], @YES);
}

- (void)testExternalLinkInfo_ANormalLinkHasNoRecord {
	TGClient *c = SL();
	__block NSDictionary *got = @{};
	[c externalLinkInfoForURL:@"https://example.com" completion:^(NSDictionary *info){ got = info; }];
	answerSL(c, @{@"@type" : @"error", @"code" : @(404), @"message" : @"Not Found"});
	XCTAssertNil(got);
}

- (void)testInternalLink_ConvertsTheTypeBackToAUrl {
	TGClient *c = SL();
	__block NSString *got = nil;
	[c internalLinkForType:@{@"@type" : @"internalLinkTypePublicChat",
							 @"chat_username" : @"durov"}
					   http:YES completion:^(NSString *link){ got = link; }];
	NSDictionary *r = lastSL(c, @"getInternalLink");
	XCTAssertEqualObjects(r[@"type"][@"chat_username"], @"durov");
	XCTAssertEqualObjects(r[@"is_http"], @YES);
	answerSL(c, @{@"@type" : @"httpUrl", @"url" : @"https://t.me/durov"});
	XCTAssertEqualObjects(got, @"https://t.me/durov");
}

- (void)testStringsByPrefix_ReturnsTheMatchedStringsInTDLibOrder {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c stringsMatchingPrefix:@[@"Telegram", @"Telegraph", @"Moscow"]
					   query:@"tele" limit:10
				  completion:^(NSArray *matches){ got = matches; }];
	NSDictionary *r = lastRequestedSL(c);
	XCTAssertEqualObjects(r[@"@type"], @"searchStringsByPrefix");
	XCTAssertEqualObjects(r[@"strings"], (@[@"Telegram", @"Telegraph", @"Moscow"]));
	XCTAssertEqualObjects(r[@"query"], @"tele");
	XCTAssertEqualObjects(r[@"return_none_for_empty_query"], @YES);
	answerSL(c, @{@"@type" : @"foundPositions", @"total_count" : @(2),
				   @"positions" : @[@(1), @(0)]});
	XCTAssertEqualObjects(got, (@[@"Telegraph", @"Telegram"]));
}

- (void)testLinkWebBrowserType_SaysExternalOrInApp {
	TGClient *c = SL();
	__block NSString *got = nil;
	[c webBrowserTypeForURL:@"https://example.com" completion:^(NSString *kind){ got = kind; }];
	answerSL(c, @{@"@type" : @"webBrowserTypeInApp"});
	XCTAssertEqualObjects(got, @"inApp");

	[c.outbox removeAllObjects];
	[c webBrowserTypeForURL:@"https://example.com" completion:^(NSString *kind){ got = kind; }];
	answerSL(c, @{@"@type" : @"webBrowserTypeExternal"});
	XCTAssertEqualObjects(got, @"external");
}

- (void)testInstantView_CarriesBlocksAndTheFlags {
	TGClient *c = SL();
	__block NSDictionary *got = nil;
	[c instantViewForURL:@"https://example.com/story" onlyLocal:NO
			  completion:^(NSDictionary *view){ got = view; }];
	NSDictionary *r = lastSL(c, @"getWebPageInstantView");
	XCTAssertEqualObjects(r[@"url"], @"https://example.com/story");
	XCTAssertEqualObjects(r[@"only_local"], @NO);
	answerSL(c, plainSL(@{@"@type" : @"webPageInstantView",
						  @"blocks" : @[@{@"@type" : @"pageBlockParagraph"}],
						  @"view_count" : @(120),
						  @"version" : @(2),
						  @"is_rtl" : @NO,
						  @"is_full" : @YES}));
	XCTAssertEqual([got[@"blocks"] count], 1);
	XCTAssertEqualObjects(got[@"viewCount"], @(120));
	XCTAssertEqualObjects(got[@"full"], @YES);
}

- (void)testRecentlyVisitedTMeUrls_NormalizesTheKind {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c recentlyVisitedTMeUrlsWithReferrer:@"campaign"
							   completion:^(NSArray *urls){ got = urls; }];
	XCTAssertEqualObjects(lastSL(c, @"getRecentlyVisitedTMeUrls")[@"referrer"], @"campaign");
	answerSL(c, plainSL(@{@"@type" : @"tMeUrls",
						  @"urls" : @[@{@"url" : @"https://t.me/durov",
									   @"type" : @{@"@type" : @"tMeUrlTypeUser",
												   @"user_id" : @(42)}}]}));
	XCTAssertEqualObjects(got[0][@"url"], @"https://t.me/durov");
	XCTAssertEqualObjects(got[0][@"kind"], @"tMeUrlTypeUser");
	XCTAssertEqualObjects(got[0][@"userId"], @(42));
}

#pragma mark - quotes and formatting

- (void)testSearchQuote_NotFoundIsAFalseAnswer {
	TGClient *c = SL();
	__block NSInteger position = -2;
	__block BOOL found = YES;
	[c searchQuote:@"needle" inText:@"a haystack" position:0
		completion:^(NSInteger p, BOOL f){ position = p; found = f; }];
	NSDictionary *r = lastRequestedSL(c);
	XCTAssertEqualObjects(r[@"@type"], @"searchQuote");
	XCTAssertEqualObjects(r[@"text"][@"text"], @"a haystack");
	XCTAssertEqualObjects(r[@"quote"][@"text"], @"needle");
	answerSL(c, @{@"@type" : @"error", @"code" : @(404), @"message" : @"Not Found"});
	XCTAssertEqual(position, -1);
	XCTAssertFalse(found);
}

- (void)testSearchQuote_ReturnsTheFoundPosition {
	TGClient *c = SL();
	__block NSInteger position = -1;
	__block BOOL found = NO;
	[c searchQuote:@"needle" inText:@"a needle here" position:0
		completion:^(NSInteger p, BOOL f){ position = p; found = f; }];
	answerSL(c, @{@"@type" : @"foundPosition", @"position" : @(2)});
	XCTAssertEqual(position, 2);
	XCTAssertTrue(found);
}

- (void)testParseMarkdown_ReturnsTheParsedEntities {
	TGClient *c = SL();
	__block NSDictionary *got = nil;
	[c parseMarkdownText:@"**bold** and #tag" completion:^(NSDictionary *f){ got = f; }];
	NSDictionary *r = lastRequestedSL(c);
	XCTAssertEqualObjects(r[@"@type"], @"parseMarkdown");
	XCTAssertEqualObjects(r[@"text"][@"text"], @"**bold** and #tag");
	answerSL(c, plainSL(@{@"@type" : @"formattedText",
						  @"text" : @"bold and #tag",
						  @"entities" : @[@{@"@type" : @"textEntity", @"offset" : @(0),
											@"length" : @(4),
											@"type" : @{@"@type" : @"textEntityTypeBold"}}]}));
	XCTAssertEqualObjects(got[@"text"], @"bold and #tag");
	XCTAssertEqual([got[@"entities"] count], 1);
}

- (void)testTextEntities_ReadsWhatTDLibFinds {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c textEntitiesInText:@"@durov #news" completion:^(NSArray *e){ got = e; }];
	NSDictionary *r = lastRequestedSL(c);
	XCTAssertEqualObjects(r[@"@type"], @"getTextEntities");
	XCTAssertEqualObjects(r[@"text"], @"@durov #news");
	answerSL(c, plainSL(@{@"@type" : @"textEntities",
						  @"entities" : @[@{@"@type" : @"textEntity",
											@"offset" : @(0), @"length" : @(6),
											@"type" : @{@"@type" : @"textEntityTypeMention"}}]}));
	XCTAssertEqual([got count], 1);
}

- (void)testTranslateText_AsksForTheLocaleAndKeepsTheText {
	TGClient *c = SL();
	__block NSString *got = nil;
	[c translateText:@"hello" toLanguageCode:@"de" tone:@"" completion:^(NSString *t){ got = t; }];
	NSDictionary *r = lastSL(c, @"translateText");
	XCTAssertEqualObjects(r[@"text"][@"text"], @"hello");
	XCTAssertEqualObjects(r[@"to_language_code"], @"de");
	answerSL(c, plainSL(@{@"@type" : @"formattedText", @"text" : @"hallo", @"entities" : @[]}));
	XCTAssertEqualObjects(got, @"hallo");
}

#pragma mark - language packs

- (void)testLanguagePackInfo_NormalizesTheRecord {
	TGClient *c = SL();
	__block NSDictionary *got = nil;
	[c languagePackInfo:@"en" completion:^(NSDictionary *i){ got = i; }];
	XCTAssertEqualObjects(lastSL(c, @"getLanguagePackInfo")[@"language_pack_id"], @"en");
	answerSL(c, plainSL(@{@"@type" : @"languagePackInfo",
						  @"id" : @"en", @"base_language_pack_id" : @"",
						  @"name" : @"English", @"native_name" : @"English",
						  @"plural_code" : @"en", @"is_official" : @YES,
						  @"is_rtl" : @NO, @"is_beta" : @NO, @"is_installed" : @YES,
						  @"total_string_count" : @(100), @"translated_string_count" : @(90),
						  @"local_string_count" : @(1), @"translation_url" : @""}));
	XCTAssertEqualObjects(got[@"name"], @"English");
	XCTAssertEqualObjects(got[@"total"], @(100));
	XCTAssertEqualObjects(got[@"official"], @YES);
}

- (void)testLanguagePackStrings_EmptyKeysAskForAll {
	TGClient *c = SL();
	__block NSArray *got = nil;
	[c languagePackStrings:@"en" keys:@[] completion:^(NSArray *s){ got = s; }];
	NSDictionary *r = lastSL(c, @"getLanguagePackStrings");
	XCTAssertEqualObjects(r[@"language_pack_id"], @"en");
	XCTAssertEqualObjects(r[@"keys"], @[]);
	answerSL(c, plainSL(@{@"@type" : @"languagePackStrings",
						  @"strings" : @[@{@"@type" : @"languagePackString",
										   @"key" : @"Continue",
										   @"value" : @{@"@type" : @"languagePackStringValueOrdinary",
														@"value" : @"Continue"}}]}));
	XCTAssertEqualObjects(got[0][@"key"], @"Continue");
	XCTAssertEqualObjects(got[0][@"kind"], @"ordinary");
}

- (void)testLanguagePackString_ReadsOneKeyBack {
	TGClient *c = SL();
	__block NSString *value = nil;
	__block NSString *kind = nil;
	[c languagePackString:@"Continue" pack:@"en" completion:^(NSString *v, NSString *k){
		value = v; kind = k;
	}];
	NSDictionary *option = lastSL(c, @"getOption");
	XCTAssertEqualObjects(option[@"name"], @"language_pack_database_path");
	answerSL(c, plainSL(@{@"@type" : @"optionValue",
						  @"name" : @"language_pack_database_path",
						  @"value" : @{@"@type" : @"optionValueString",
									   @"value" : @"/tmp/language_pack"}}));

	NSDictionary *r = lastRequestedSL(c);
	XCTAssertEqualObjects(r[@"@type"], @"getLanguagePackString");
	XCTAssertEqualObjects(r[@"language_pack_database_path"], @"/tmp/language_pack");
	XCTAssertEqualObjects(r[@"language_pack_id"], @"en");
	XCTAssertEqualObjects(r[@"key"], @"Continue");
	answerSL(c, @{@"@type" : @"languagePackStringValueOrdinary", @"value" : @"Weiter"});
	XCTAssertEqualObjects(value, @"Weiter");
	XCTAssertEqualObjects(kind, @"ordinary");
}

- (void)testAddCustomServerLanguagePack_SendsTheId {
	TGClient *c = SL();
	__block BOOL ok = NO;
	[c addCustomServerLanguagePack:@"de" completion:^(BOOL o){ ok = o; }];
	XCTAssertEqualObjects(lastSL(c, @"addCustomServerLanguagePack")[@"language_pack_id"], @"de");
	answerSL(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetCustomLanguagePack_PrefixesTheIdAndCarriesStrings {
	TGClient *c = SL();
	__block BOOL ok = NO;
	[c setCustomLanguagePack:@"test" name:@"Test" nativeName:@"Test"
					 strings:@[@{@"key" : @"Continue", @"value" : @"Go"}] completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = lastSL(c, @"setCustomLanguagePack");
	XCTAssertEqualObjects(r[@"info"][@"id"], @"Xtest");
	XCTAssertEqualObjects(r[@"info"][@"name"], @"Test");
	XCTAssertEqualObjects(r[@"strings"][0][@"key"], @"Continue");
	XCTAssertEqualObjects(r[@"strings"][0][@"value"][@"value"], @"Go");
	answerSL(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetCustomLanguagePackString_NilDeletesTheOverride {
	TGClient *c = SL();
	__block BOOL ok = NO;
	[c setCustomLanguagePackString:@"Continue" value:nil pack:@"Xtest" completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = lastSL(c, @"setCustomLanguagePackString");
	XCTAssertEqualObjects(r[@"language_pack_id"], @"Xtest");
	XCTAssertEqualObjects(r[@"new_string"][@"key"], @"Continue");
	XCTAssertEqualObjects(r[@"new_string"][@"value"][@"@type"],
						 @"languagePackStringValueDeleted");
	answerSL(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testEditCustomLanguagePackInfo_KeepsTheRecordShape {
	TGClient *c = SL();
	__block BOOL ok = NO;
	[c editCustomLanguagePackInfo:@{@"id" : @"Xtest", @"name" : @"Renamed",
									@"base" : @"en", @"nativeName" : @"Renamed"}
					   completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = lastSL(c, @"editCustomLanguagePackInfo");
	XCTAssertEqualObjects(r[@"info"][@"@type"], @"languagePackInfo");
	XCTAssertEqualObjects(r[@"info"][@"id"], @"Xtest");
	XCTAssertEqualObjects(r[@"info"][@"name"], @"Renamed");
	answerSL(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSynchronizeLanguagePack_SendsTheId {
	TGClient *c = SL();
	__block BOOL ok = NO;
	[c synchronizeLanguagePack:@"en" completion:^(BOOL o){ ok = o; }];
	XCTAssertEqualObjects(lastSL(c, @"synchronizeLanguagePack")[@"language_pack_id"], @"en");
	answerSL(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeleteLanguagePack_SendsTheId {
	TGClient *c = SL();
	__block BOOL ok = NO;
	[c deleteLanguagePack:@"Xtest" completion:^(BOOL o){ ok = o; }];
	XCTAssertEqualObjects(lastSL(c, @"deleteLanguagePack")[@"language_pack_id"], @"Xtest");
	answerSL(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - countries

- (void)testCountryInfo_NormalizesTheRecord {
	TGClient *c = SL();
	__block NSDictionary *got = nil;
	[c countryInfoForCode:@"de" completion:^(NSDictionary *country){ got = country; }];
	XCTAssertEqualObjects(lastSL(c, @"getCountry")[@"country_code"], @"DE");
	answerSL(c, plainSL(@{@"@type" : @"countryInfo",
						  @"country_code" : @"DE", @"name" : @"Deutschland",
						  @"english_name" : @"Germany", @"flag_emoji" : @"🇩🇪",
						  @"is_hidden" : @NO, @"calling_codes" : @[@"49"]}));
	XCTAssertEqualObjects(got[@"name"], @"Deutschland");
	XCTAssertEqualObjects(got[@"flag"], @"🇩🇪");
	XCTAssertEqualObjects(got[@"callingCodes"], (@[@"49"]));
}

- (void)testPreferredCountryLanguage_IsATextAnswer {
	TGClient *c = SL();
	__block NSString *got = nil;
	[c preferredCountryLanguageForCode:@"de" completion:^(NSString *code){ got = code; }];
	XCTAssertEqualObjects(lastSL(c, @"getPreferredCountryLanguage")[@"country_code"], @"DE");
	answerSL(c, @{@"@type" : @"text", @"text" : @"de"});
	XCTAssertEqualObjects(got, @"de");
}

- (void)testCountryFlagEmoji_IsATextAnswer {
	TGClient *c = SL();
	__block NSString *got = nil;
	[c countryFlagEmojiForCode:@"de" completion:^(NSString *emoji){ got = emoji; }];
	NSDictionary *r = lastRequestedSL(c);
	XCTAssertEqualObjects(r[@"@type"], @"getCountryFlagEmoji");
	XCTAssertEqualObjects(r[@"country_code"], @"DE");
	answerSL(c, @{@"@type" : @"text", @"text" : @"🇩🇪"});
	XCTAssertEqualObjects(got, @"🇩🇪");
}

@end
