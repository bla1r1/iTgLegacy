// TGClientBareTests.m — the requests the app names but nothing calls yet.
//
// tdlib_coverage.sh --bare lists the td_api names written into a method that
// has no caller in src/. These tests drive those methods directly so the
// wire shape is pinned down before a screen is wired to them. They do not
// make the names reachable: only a call from src/ does that.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientBareTests : XCTestCase @end

static TGClient *B(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeB(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastB(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeB(d)[@"@type"] isEqualToString:type])
			found = decodeB(d);
	return found;
}

static void answerB(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeB(d)[@"@extra"])
			sent = decodeB(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

/// Literal dictionaries answer nil one level down; a real TDLib answer is
/// parsed, so round-trip the fixture through JSON before feeding it back.
static NSDictionary *plainB(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientBareTests

// ─── downloads ───────────────────────────────────────────────────────────────

- (void)testAddFileToDownloads_CarriesTheFileChatAndMessage {
	TGClient *c = B();
	[c addFileToDownloads:41 inChat:77 message:88];

	NSDictionary *r = lastB(c, @"addFileToDownloads");
	XCTAssertEqualObjects(r[@"file_id"], @(41));
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(88));
	// Priority 1 is what their client uses for a user-requested download.
	XCTAssertEqualObjects(r[@"priority"], @(1));
	// Nothing waits for an answer, so the request is one-shot.
	XCTAssertNil(r[@"@extra"]);
}

- (void)testDeleteLocalFile_SendsOnlyTheFileId {
	TGClient *c = B();
	[c deleteLocalFile:41];

	NSDictionary *r = lastB(c, @"deleteFile");
	XCTAssertEqualObjects(r[@"file_id"], @(41));
	XCTAssertNil(r[@"@extra"]);
}

// ─── dates and stored messages ───────────────────────────────────────────────

- (void)testMessageAtDate_AsksBySecondAndFlattensTheAnswer {
	TGClient *c = B();
	__block NSDictionary *got = nil;
	[c messageAtDate:1700000000.9 inChat:77 completion:^(NSDictionary *m){ got = m; }];

	NSDictionary *r = lastB(c, @"getChatMessageByDate");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	// TDLib takes an int32 date, so the fraction is cut, not rounded.
	XCTAssertEqualObjects(r[@"date"], @(1700000000));

	answerB(c, plainB(@{@"@type" : @"message",
						@"id" : @(55),
						@"date" : @(1700000000),
						@"content" : @{@"@type" : @"messageText",
									   @"text" : @{@"@type" : @"formattedText",
												   @"text" : @"at that second"}}}));
	XCTAssertEqualObjects(got[@"id"], @(55));
	XCTAssertEqualObjects(got[@"text"], @"at that second");
}

- (void)testMessageAtDate_AnEmptyAnswerIsNil {
	TGClient *c = B();
	__block NSDictionary *got = @{};
	[c messageAtDate:1700000000 inChat:77 completion:^(NSDictionary *m){ got = m; }];
	answerB(c, @{@"@type" : @"error", @"code" : @(400), @"message" : @"NO_MESSAGE"});
	XCTAssertNil(got);
}

- (void)testSavedTopicMessageAtDate_SendsTheTopicAndDate {
	TGClient *c = B();
	__block NSDictionary *got = nil;
	[c savedTopicMessageAtDate:12 date:1700000000 completion:^(NSDictionary *m){ got = m; }];

	NSDictionary *r = lastB(c, @"getSavedMessagesTopicMessageByDate");
	XCTAssertEqualObjects(r[@"saved_messages_topic_id"], @(12));
	XCTAssertEqualObjects(r[@"date"], @(1700000000));

	answerB(c, plainB(@{@"@type" : @"message",
						@"id" : @(91),
						@"date" : @(1700000000),
						@"content" : @{@"@type" : @"messageText",
									   @"text" : @{@"@type" : @"formattedText",
												   @"text" : @"saved"}}}));
	// Saved topics answer with the raw message: the screen flattens it.
	XCTAssertEqualObjects(got[@"id"], @(91));
}

- (void)testSavedTopicMessageAtDate_AnythingElseIsNil {
	TGClient *c = B();
	__block NSDictionary *got = @{};
	[c savedTopicMessageAtDate:12 date:1700000000 completion:^(NSDictionary *m){ got = m; }];
	answerB(c, @{@"@type" : @"error", @"code" : @(400), @"message" : @"NO_MESSAGE"});
	XCTAssertNil(got);
}

// ─── message detail ──────────────────────────────────────────────────────────

- (void)testAvailableReactions_ReturnsTheTopEmoji {
	TGClient *c = B();
	__block NSArray *got = @[];
	[c availableReactionsForMessage:55 inChat:77 completion:^(NSArray *emojis){ got = emojis; }];

	NSDictionary *r = lastB(c, @"getMessageAvailableReactions");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(55));
	XCTAssertEqualObjects(r[@"row_size"], @(8));

	answerB(c, plainB(@{@"@type" : @"availableReactions",
						@"top_reactions" : @[
							@{@"@type" : @"availableReaction", @"emoji" : @"👍"},
							@{@"@type" : @"availableReaction", @"emoji" : @"❤"}],
						@"recent_reactions" : @[],
						@"popular_reactions" : @[]}));
	XCTAssertEqualObjects(got, (@[@"👍", @"❤"]));
}

- (void)testAvailableReactions_AnUnavailableMessageHasNoBar {
	TGClient *c = B();
	__block NSArray *got = @[];
	[c availableReactionsForMessage:55 inChat:77 completion:^(NSArray *emojis){ got = emojis; }];

	answerB(c, plainB(@{@"@type" : @"availableReactions",
						@"top_reactions" : @[],
						@"recent_reactions" : @[],
						@"popular_reactions" : @[],
						@"unavailability_reason" : @{
							@"@type" : @"reactionUnavailabilityReasonGuest"}}));
	XCTAssertNil(got);
}

- (void)testEmbeddingCode_TextIsReturnedAsWritten {
	TGClient *c = B();
	__block NSString *got = nil;
	[c embeddingCodeOfMessage:55 inChat:77 album:YES completion:^(NSString *code){ got = code; }];

	NSDictionary *r = lastB(c, @"getMessageEmbeddingCode");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(55));
	XCTAssertEqualObjects(r[@"for_album"], @YES);

	answerB(c, @{@"@type" : @"text", @"text" : @"<script src=\"//t.me/embed\"></script>"});
	XCTAssertEqualObjects(got, @"<script src=\"//t.me/embed\"></script>");
}

- (void)testEmbeddingCode_ANonTextAnswerIsAnEmptyString {
	TGClient *c = B();
	__block NSString *got = nil;
	[c embeddingCodeOfMessage:55 inChat:77 album:NO completion:^(NSString *code){ got = code; }];
	answerB(c, @{@"@type" : @"error", @"code" : @(400), @"message" : @"NO_EMBED"});
	XCTAssertEqualObjects(got, @"");
}

// ─── phone step ──────────────────────────────────────────────────────────────

- (void)testCountryCode_ReturnsTheIsoCodeOrNil {
	TGClient *c = B();
	__block NSString *got = nil;
	[c countryCodeWithCompletion:^(NSString *code){ got = code; }];

	XCTAssertNotNil(lastB(c, @"getCountryCode"));
	answerB(c, @{@"@type" : @"text", @"text" : @"UA"});
	XCTAssertEqualObjects(got, @"UA");

	[c.outbox removeAllObjects];
	got = nil;
	[c countryCodeWithCompletion:^(NSString *code){ got = code; }];
	answerB(c, @{@"@type" : @"text", @"text" : @""});
	XCTAssertNil(got);
}

// ─── storage ─────────────────────────────────────────────────────────────────

- (void)testStorageStats_ReadsBytesAndFileCount {
	TGClient *c = B();
	__block long long bytes = -1;
	__block NSInteger files = -1;
	[c storageStatsWithCompletion:^(long long b, NSInteger f){ bytes = b; files = f; }];

	XCTAssertNotNil(lastB(c, @"getStorageStatisticsFast"));
	answerB(c, @{@"@type" : @"storageStatisticsFast",
				 @"files_size" : @(123456789),
				 @"file_count" : @(42)});
	XCTAssertEqual(bytes, 123456789LL);
	XCTAssertEqual(files, 42);
}

// ─── sticker sets ────────────────────────────────────────────────────────────

- (void)testInstalledStickerSets_AsksForRegularNotMasks {
	TGClient *c = B();
	__block NSArray *got = nil;
	[c installedStickerSetsWithCompletion:^(NSArray *sets){ got = sets; }];

	NSDictionary *r = lastB(c, @"getInstalledStickerSets");
	XCTAssertEqualObjects(r[@"is_masks"], @NO);
	XCTAssertEqualObjects(r[@"sticker_type"][@"@type"], @"stickerTypeRegular");

	answerB(c, plainB(@{@"@type" : @"stickerSets",
						@"sets" : @[@{@"@type" : @"stickerSetInfo",
									  @"id" : @"100",
									  @"title" : @"Cats",
									  @"count" : @(3),
									  @"is_installed" : @YES,
									  @"is_archived" : @NO,
									  @"short_name" : @"cats"}]}));
	XCTAssertEqualObjects(got.firstObject[@"id"], @"100");
	XCTAssertEqualObjects(got.firstObject[@"title"], @"Cats");
	XCTAssertEqualObjects(got.firstObject[@"count"], @(3));
	XCTAssertEqualObjects(got.firstObject[@"installed"], @YES);
	XCTAssertEqualObjects(got.firstObject[@"shortName"], @"cats");
}

- (void)testTrendingStickerSets_FlattensTheRows {
	TGClient *c = B();
	__block NSArray *got = nil;
	[c trendingStickerSetsWithCompletion:^(NSArray *sets){ got = sets; }];

	NSDictionary *r = lastB(c, @"getTrendingStickerSets");
	XCTAssertEqualObjects(r[@"sticker_type"][@"@type"], @"stickerTypeRegular");
	XCTAssertEqualObjects(r[@"offset"], @(0));
	XCTAssertEqualObjects(r[@"limit"], @(20));

	answerB(c, plainB(@{@"@type" : @"stickerSets",
						@"sets" : @[
							@{@"@type" : @"stickerSetInfo",
							  @"id" : @"200",
							  @"title" : @"Dogs",
							  @"count" : @(8),
							  @"is_installed" : @NO,
							  @"is_archived" : @YES,
							  @"short_name" : @"dogs",
							  @"covers" : @[
								  @{@"@type" : @"sticker",
									@"sticker" : @{@"@type" : @"file",
												   @"id" : @(501)}}]},
							// A row without an id cannot be opened, so it is
							// dropped instead of drawing a dead cell.
							@{@"@type" : @"stickerSetInfo", @"title" : @"Broken"}]}));
	XCTAssertEqual(got.count, 1);
	XCTAssertEqualObjects(got.firstObject[@"id"], @"200");
	XCTAssertEqualObjects(got.firstObject[@"archived"], @YES);
	XCTAssertEqualObjects(got.firstObject[@"cover"][@"fileId"], @(501));
}

@end
