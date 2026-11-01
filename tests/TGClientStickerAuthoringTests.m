// TGClientStickerAuthoringTests.m - the write half of stickers.
//
// Every request here changes something Telegram keeps: a pack is created,
// a sticker is added, moved, retagged or removed, a group's shelf is set.
// The tests hold the wire shape and the branch that is easy to invert -
// an InputFile id that is not a path, a mask point that is not a word, a
// custom emoji id that must survive the flattening.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientStickerAuthoringTests : XCTestCase @end

static TGClient *S(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeS(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastS(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeS(d)[@"@type"] isEqualToString:type])
			found = decodeS(d);
	return found;
}

static NSUInteger countS(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeS(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void answerS(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeS(d)[@"@extra"])
			sent = decodeS(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainS(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *newStickerS(NSInteger fileId) {
	return @{@"@type" : @"newSticker",
			 @"sticker" : @{@"@type" : @"inputFileId", @"id" : @(fileId)},
			 @"format" : @{@"@type" : @"stickerFormatWebp"},
			 @"emojis" : @"\U0001F600",
			 @"keywords" : @[@"cat"]};
}

@implementation TGClientStickerAuthoringTests

// ─── creating and naming ────────────────────────────────────────────────────

- (void)testNewSticker_CarriesTheFileAndItsTags {
	TGClient *c = S();
	NSDictionary *sticker = [[TGClient shared] newStickerWithFileId:77
			format:@"webp" emojis:@"\U0001F431" keywords:@[@"cat", @"pet"]
			maskPosition:nil];
	XCTAssertEqualObjects(sticker[@"@type"], @"newSticker");
	XCTAssertEqualObjects(sticker[@"sticker"][@"@type"], @"inputFileId");
	XCTAssertEqualObjects(sticker[@"sticker"][@"id"], @(77));
	XCTAssertEqualObjects(sticker[@"format"][@"@type"], @"stickerFormatWebp");
	XCTAssertEqualObjects(sticker[@"emojis"], @"\U0001F431");
	XCTAssertEqualObjects(sticker[@"keywords"], (@[@"cat", @"pet"]));
	XCTAssertNil(sticker[@"mask_position"]);
}

- (void)testCheckStickerSetName_AnswersThreeWords {
	TGClient *c = S();
	__block NSString *status = nil;
	[c checkStickerSetName:@"ducks" completion:^(NSString *s, NSString *message){
		status = s;
		XCTAssertEqualObjects(message, @"This name is free.");
	}];
	NSDictionary *r = lastS(c, @"checkStickerSetName");
	XCTAssertEqualObjects(r[@"name"], @"ducks");
	answerS(c, @{@"@type" : @"checkStickerSetNameResultOk"});
	XCTAssertEqualObjects(status, @"ok");

	[c checkStickerSetName:@"taken" completion:^(NSString *s, NSString *m){ status = s; }];
	answerS(c, @{@"@type" : @"checkStickerSetNameResultNameOccupied"});
	XCTAssertEqualObjects(status, @"occupied");

	[c checkStickerSetName:@"" completion:^(NSString *s, NSString *m){ status = s; }];
	XCTAssertEqualObjects(status, @"invalid");
	XCTAssertEqual(countS(c, @"checkStickerSetName"), (NSUInteger)2);
}

- (void)testSuggestedSetName_IsTheServersWord {
	TGClient *c = S();
	__block NSString *suggested = nil;
	[c suggestStickerSetNameForTitle:@"My Cats" completion:^(NSString *name){
		suggested = name;
	}];
	NSDictionary *r = lastS(c, @"getSuggestedStickerSetName");
	XCTAssertEqualObjects(r[@"title"], @"My Cats");
	answerS(c, @{@"@type" : @"text", @"text" : @"my_cats"});
	XCTAssertEqualObjects(suggested, @"my_cats");
}

- (void)testSetNameForId_ReturnsTheShortName {
	TGClient *c = S();
	__block NSString *name = nil;
	[c stickerSetNameForId:91 completion:^(NSString *n){ name = n; }];
	XCTAssertEqualObjects(lastS(c, @"getStickerSetName")[@"set_id"], @(91));
	answerS(c, @{@"@type" : @"text", @"text" : @"cats"});
	XCTAssertEqualObjects(name, @"cats");
}

- (void)testCreateSet_SendsTheFirstStickerAndTheOwner {
	TGClient *c = S();
	__block NSDictionary *made = nil;
	[c createStickerSetNamed:@"my_cats" title:@"My Cats" stickerType:@"regular"
			stickers:@[newStickerS(77)] completion:^(NSDictionary *set){ made = set; }];

	NSDictionary *r = lastS(c, @"createNewStickerSet");
	XCTAssertEqualObjects(r[@"user_id"], @(1001));
	XCTAssertEqualObjects(r[@"name"], @"my_cats");
	XCTAssertEqualObjects(r[@"title"], @"My Cats");
	XCTAssertEqualObjects(r[@"sticker_type"][@"@type"], @"stickerTypeRegular");
	XCTAssertEqualObjects(r[@"needs_repainting"], @NO);
	XCTAssertEqualObjects(r[@"stickers"], (@[newStickerS(77)]));
	XCTAssertEqualObjects(r[@"source"], @"legacy");

	answerS(c, plainS(@{@"@type" : @"stickerSet", @"id" : @"900",
						@"title" : @"My Cats", @"name" : @"my_cats",
						@"is_owned" : @YES, @"count" : @1,
						@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
						@"stickers" : @[@{@"@type" : @"sticker",
										  @"sticker" : @{@"@type" : @"file", @"id" : @(77)},
										  @"emoji" : @"\U0001F600"}]}));
	XCTAssertEqualObjects(made[@"id"], @"900");
	XCTAssertEqualObjects(made[@"name"], @"my_cats");
	XCTAssertEqualObjects(made[@"stickerType"], @"stickerTypeRegular");
	XCTAssertEqual([(NSArray *)made[@"stickers"] count], (NSUInteger)1);
}

- (void)testCreateSet_NoTitleMeansNoRequest {
	TGClient *c = S();
	__block BOOL answered = NO;
	[c createStickerSetNamed:@"x" title:@"" stickerType:@"regular" stickers:@[]
			completion:^(NSDictionary *set){ answered = YES; XCTAssertNil(set); }];
	XCTAssertTrue(answered);
	XCTAssertEqual(countS(c, @"createNewStickerSet"), (NSUInteger)0);
}

- (void)testDeleteSet_NamesThePack {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c deleteStickerSetNamed:@"my_cats" completion:^(BOOL value){ ok = value; }];
	XCTAssertEqualObjects(lastS(c, @"deleteStickerSet")[@"name"], @"my_cats");
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

// ─── stickers inside a set ──────────────────────────────────────────────────

- (void)testAddSticker_IsAnInputFileIdNotAPath {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c addStickerToSetNamed:@"my_cats" sticker:newStickerS(77)
			completion:^(BOOL value){ ok = value; }];
	NSDictionary *r = lastS(c, @"addStickerToSet");
	XCTAssertEqualObjects(r[@"user_id"], @(1001));
	XCTAssertEqualObjects(r[@"name"], @"my_cats");
	XCTAssertEqualObjects(r[@"sticker"], newStickerS(77));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testRemoveSticker_NamesTheFile {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c removeStickerFileId:77 completion:^(BOOL value){ ok = value; }];
	XCTAssertEqualObjects(lastS(c, @"removeStickerFromSet")[@"sticker"][@"id"], @(77));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	[c removeStickerFileId:0 completion:^(BOOL value){ ok = value; }];
	XCTAssertFalse(ok);
}

- (void)testReplaceSticker_SendsOldAndNewTogether {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c replaceStickerInSetNamed:@"my_cats" oldFileId:70 newSticker:newStickerS(77)
			completion:^(BOOL value){ ok = value; }];
	NSDictionary *r = lastS(c, @"replaceStickerInSet");
	XCTAssertEqualObjects(r[@"old_sticker"][@"@type"], @"inputFileId");
	XCTAssertEqualObjects(r[@"old_sticker"][@"id"], @(70));
	XCTAssertEqualObjects(r[@"new_sticker"][@"sticker"][@"id"], @(77));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testPositionInSet_IsZeroBasedAndRefusedBelowZero {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setStickerFileId:77 positionInSet:2 completion:^(BOOL value){ ok = value; }];
	NSDictionary *r = lastS(c, @"setStickerPositionInSet");
	XCTAssertEqualObjects(r[@"position"], @(2));
	XCTAssertEqualObjects(r[@"sticker"][@"id"], @(77));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	[c setStickerFileId:77 positionInSet:-1 completion:^(BOOL value){ ok = value; }];
	XCTAssertFalse(ok);
	XCTAssertEqual(countS(c, @"setStickerPositionInSet"), (NSUInteger)1);
}

- (void)testStickerEmojis_AndKeywords_AndMaskPosition {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setStickerFileId:77 emojis:@"\U0001F431" completion:^(BOOL value){ ok = value; }];
	XCTAssertEqualObjects(lastS(c, @"setStickerEmojis")[@"emojis"], @"\U0001F431");
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	[c setStickerFileId:77 keywords:@[@"cat", @"pet"] completion:^(BOOL value){ ok = value; }];
	XCTAssertEqualObjects(lastS(c, @"setStickerKeywords")[@"keywords"], (@[@"cat", @"pet"]));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	NSDictionary *mask = @{@"@type" : @"maskPosition",
						   @"point" : @{@"@type" : @"maskPointEyes"},
						   @"x_shift" : @0, @"y_shift" : @0, @"scale" : @1};
	[c setStickerFileId:77 maskPosition:mask completion:^(BOOL value){ ok = value; }];
	XCTAssertEqualObjects(lastS(c, @"setStickerMaskPosition")[@"mask_position"], mask);
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

/// td_api says "pass null to remove mask position". A nil Objective-C
/// dictionary cannot be a JSON value, so the request must carry NSNull.
- (void)testRemoveMaskPosition_SendsNullNotAMissingField {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setStickerFileId:77 maskPosition:nil completion:^(BOOL value){ ok = value; }];
	NSDictionary *r = lastS(c, @"setStickerMaskPosition");
	XCTAssertEqualObjects(r[@"mask_position"], [NSNull null]);
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetTitleAndThumbnail {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setStickerSetNamed:@"my_cats" title:@"Red Cats" completion:^(BOOL value){ ok = value; }];
	NSDictionary *title = lastS(c, @"setStickerSetTitle");
	XCTAssertEqualObjects(title[@"name"], @"my_cats");
	XCTAssertEqualObjects(title[@"title"], @"Red Cats");
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	[c setStickerSetNamed:@"my_cats" thumbnailAtPath:@"/tmp/cat.png" format:@"webp"
			completion:^(BOOL value){ ok = value; }];
	NSDictionary *thumb = lastS(c, @"setStickerSetThumbnail");
	XCTAssertEqualObjects(thumb[@"user_id"], @(1001));
	XCTAssertEqualObjects(thumb[@"thumbnail"][@"@type"], @"inputFileLocal");
	XCTAssertEqualObjects(thumb[@"thumbnail"][@"path"], @"/tmp/cat.png");
	XCTAssertEqualObjects(thumb[@"format"][@"@type"], @"stickerFormatWebp");
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testUploadSticker_ReturnsTheUploadedFileId {
	TGClient *c = S();
	__block NSInteger fileId = -1;
	[c uploadStickerAtPath:@"/tmp/cat.png" format:@"webp"
			completion:^(NSInteger value){ fileId = value; }];
	NSDictionary *r = lastS(c, @"uploadStickerFile");
	XCTAssertEqualObjects(r[@"user_id"], @(1001));
	XCTAssertEqualObjects(r[@"sticker_format"][@"@type"], @"stickerFormatWebp");
	XCTAssertEqualObjects(r[@"sticker"][@"@type"], @"inputFileLocal");
	answerS(c, @{@"@type" : @"file", @"id" : @(812)});
	XCTAssertEqual(fileId, 812);

	[c uploadStickerAtPath:@"" format:@"webp" completion:^(NSInteger value){ fileId = value; }];
	XCTAssertEqual(fileId, 0);
	XCTAssertEqual(countS(c, @"uploadStickerFile"), (NSUInteger)1);
}

// ─── reading a pack and its metadata ────────────────────────────────────────

- (void)testOwnedStickerSets_KeepsTheTypeAndShortName {
	TGClient *c = S();
	__block NSArray *sets = nil;
	[c ownedStickerSetsWithCompletion:^(NSArray *value){ sets = value; }];
	NSDictionary *r = lastS(c, @"getOwnedStickerSets");
	XCTAssertEqualObjects(r[@"offset_sticker_set_id"], @(0));
	XCTAssertEqualObjects(r[@"limit"], @(100));
	answerS(c, plainS(@{@"@type" : @"stickerSets",
						@"sets" : @[@{@"@type" : @"stickerSetInfo",
									  @"id" : @"900", @"title" : @"Cats",
									  @"name" : @"cats", @"count" : @4,
									  @"is_owned" : @YES,
									  @"sticker_type" : @{@"@type" : @"stickerTypeCustomEmoji"}}]}));
	XCTAssertEqualObjects(sets.firstObject[@"shortName"], @"cats");
	XCTAssertEqualObjects(sets.firstObject[@"stickerType"], @"stickerTypeCustomEmoji");
	XCTAssertEqualObjects(sets.firstObject[@"owned"], @YES);
}

- (void)testSearchStickerSet_ReturnsThePackAndItsStickers {
	TGClient *c = S();
	__block NSDictionary *set = nil;
	[c searchStickerSetNamed:@"cats" ignoreCache:YES completion:^(NSDictionary *value){
		set = value;
	}];
	NSDictionary *r = lastS(c, @"searchStickerSet");
	XCTAssertEqualObjects(r[@"name"], @"cats");
	XCTAssertEqualObjects(r[@"ignore_cache"], @YES);
	answerS(c, plainS(@{@"@type" : @"stickerSet", @"id" : @"900",
						@"title" : @"Cats", @"name" : @"cats",
						@"is_installed" : @NO, @"count" : @1,
						@"stickers" : @[@{@"@type" : @"sticker",
										  @"sticker" : @{@"@type" : @"file", @"id" : @(77)},
										  @"emoji" : @"\U0001F431"}]}));
	XCTAssertEqualObjects(set[@"id"], @"900");
	XCTAssertEqualObjects(set[@"name"], @"cats");
	XCTAssertEqual([(NSArray *)set[@"stickers"] count], (NSUInteger)1);
}

- (void)testStickerEmojis_ReadsTheOwnTags {
	TGClient *c = S();
	__block NSArray *emojis = nil;
	[c stickerEmojisForFileId:77 completion:^(NSArray *value){ emojis = value; }];
	XCTAssertEqualObjects(lastS(c, @"getStickerEmojis")[@"sticker"][@"id"], @(77));
	answerS(c, @{@"@type" : @"emojis", @"emojis" : @[@"\U0001F431", @"\U0001F408"]});
	XCTAssertEqualObjects(emojis, (@[@"\U0001F431", @"\U0001F408"]));
}

- (void)testAllStickerEmojis_CarriesTheScopeAndTheMainOnlyFlag {
	TGClient *c = S();
	__block NSArray *emojis = nil;
	[c allStickerEmojisForQuery:@"\U0001F431" chatId:0 stickerType:@"regular"
			mainOnly:NO completion:^(NSArray *value){ emojis = value; }];
	NSDictionary *r = lastS(c, @"getAllStickerEmojis");
	XCTAssertEqualObjects(r[@"query"], @"\U0001F431");
	XCTAssertEqualObjects(r[@"chat_id"], @(0));
	XCTAssertEqualObjects(r[@"sticker_type"][@"@type"], @"stickerTypeRegular");
	XCTAssertEqualObjects(r[@"return_only_main_emoji"], @NO);
	answerS(c, @{@"@type" : @"emojis", @"emojis" : @[@"\U0001F431"]});
	XCTAssertEqualObjects(emojis, (@[@"\U0001F431"]));
}

- (void)testOutline_CountsPathsAndPoints {
	TGClient *c = S();
	__block NSArray *paths = nil;
	__block NSInteger points = -1;
	[c stickerOutlineForFileId:77 completion:^(NSArray *p, NSInteger n){
		paths = p; points = n;
	}];
	NSDictionary *r = lastS(c, @"getStickerOutline");
	XCTAssertEqualObjects(r[@"sticker_file_id"], @(77));
	XCTAssertEqualObjects(r[@"for_animated_emoji"], @NO);
	XCTAssertEqualObjects(r[@"for_clicked_animated_emoji_message"], @NO);
	answerS(c, @{@"@type" : @"outline", @"paths" : @[
			@{@"@type" : @"closedVectorPath", @"commands" : @[
					@{@"@type" : @"vectorPathCommandLine"},
					@{@"@type" : @"vectorPathCommandCubicBezierCurve"}]},
			@{@"@type" : @"closedVectorPath", @"commands" : @[
					@{@"@type" : @"vectorPathCommandLine"}]}]});
	XCTAssertEqual(paths.count, (NSUInteger)2);
	XCTAssertEqual(points, (NSInteger)3);
}

- (void)testOutlineSvgPath_IsTheServersText {
	TGClient *c = S();
	__block NSString *path = nil;
	[c stickerOutlineSvgPathForFileId:77 completion:^(NSString *value){ path = value; }];
	XCTAssertEqualObjects(lastS(c, @"getStickerOutlineSvgPath")[@"sticker_file_id"], @(77));
	answerS(c, @{@"@type" : @"text", @"text" : @"M0 0H10V10Z"});
	XCTAssertEqualObjects(path, @"M0 0H10V10Z");
}

// ─── custom emoji ───────────────────────────────────────────────────────────

- (void)testCustomEmojiById_KeepsTheEmojiId {
	TGClient *c = S();
	__block NSArray *stickers = nil;
	[c customEmojiStickersForIds:@[@(55), @(56)] completion:^(NSArray *value){
		stickers = value;
	}];
	XCTAssertEqualObjects(lastS(c, @"getCustomEmojiStickers")[@"custom_emoji_ids"],
						   (@[@(55), @(56)]));
	answerS(c, plainS(@{@"@type" : @"stickers", @"stickers" : @[
			@{@"@type" : @"sticker", @"set_id" : @"900",
			  @"sticker" : @{@"@type" : @"file", @"id" : @(77)},
			  @"emoji" : @"\U0001F431",
			  @"full_type" : @{@"@type" : @"stickerFullTypeCustomEmoji",
							   @"custom_emoji_id" : @"55"}}]}));
	XCTAssertEqual(stickers.count, (NSUInteger)1);
	XCTAssertEqualObjects(stickers.firstObject[@"customEmojiId"], @(55));
	XCTAssertEqualObjects(stickers.firstObject[@"setId"], @(900));
}

- (void)testDefaultCustomEmojiShelves_AreThreeSeparateReads {
	TGClient *c = S();
	__block NSUInteger calls = 0;
	void (^got)(NSArray *) = ^(NSArray *stickers){
		calls++;
		XCTAssertEqual(stickers.count, (NSUInteger)1);
	};
	[c defaultProfilePhotoCustomEmojiStickersWithCompletion:got];
	XCTAssertNotNil(lastS(c, @"getDefaultProfilePhotoCustomEmojiStickers"));
	answerS(c, plainS(@{@"@type" : @"stickers", @"stickers" : @[
			@{@"@type" : @"sticker", @"sticker" : @{@"@type" : @"file", @"id" : @(1)}}]}));

	[c defaultChatPhotoCustomEmojiStickersWithCompletion:got];
	XCTAssertNotNil(lastS(c, @"getDefaultChatPhotoCustomEmojiStickers"));
	answerS(c, plainS(@{@"@type" : @"stickers", @"stickers" : @[
			@{@"@type" : @"sticker", @"sticker" : @{@"@type" : @"file", @"id" : @(2)}}]}));

	[c defaultBackgroundCustomEmojiStickersWithCompletion:got];
	XCTAssertNotNil(lastS(c, @"getDefaultBackgroundCustomEmojiStickers"));
	answerS(c, plainS(@{@"@type" : @"stickers", @"stickers" : @[
			@{@"@type" : @"sticker", @"sticker" : @{@"@type" : @"file", @"id" : @(3)}}]}));
	XCTAssertEqual(calls, (NSUInteger)3);
}

- (void)testGreetingStickers_AreAStickerList {
	TGClient *c = S();
	__block NSArray *stickers = nil;
	[c greetingStickersWithCompletion:^(NSArray *value){ stickers = value; }];
	XCTAssertNotNil(lastS(c, @"getGreetingStickers"));
	answerS(c, plainS(@{@"@type" : @"stickers", @"stickers" : @[
			@{@"@type" : @"sticker", @"sticker" : @{@"@type" : @"file", @"id" : @(7)},
			  @"emoji" : @"\U0001F382"}]}));
	XCTAssertEqualObjects(stickers.firstObject[@"fileId"], @(7));
}

- (void)testCustomEmojiThumbnail_NamesThePackAndTheEmoji {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setCustomEmojiStickerSetNamed:@"cats" thumbnailCustomEmojiId:55
			completion:^(BOOL value){ ok = value; }];
	NSDictionary *r = lastS(c, @"setCustomEmojiStickerSetThumbnail");
	XCTAssertEqualObjects(r[@"name"], @"cats");
	XCTAssertEqualObjects(r[@"custom_emoji_id"], @(55));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	// 0 is td_api's "remove the thumbnail", not a missing argument.
	[c setCustomEmojiStickerSetNamed:@"cats" thumbnailCustomEmojiId:0
			completion:^(BOOL value){ ok = value; }];
	XCTAssertEqualObjects(lastS(c, @"setCustomEmojiStickerSetThumbnail")
						   [@"custom_emoji_id"], @(0));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

// ─── trending and recents ───────────────────────────────────────────────────

- (void)testViewTrendingNamesTheIdsAndDoesNotAskTwice {
	TGClient *c = S();
	[c viewTrendingStickerSets:@[@(1), @(2)]];
	XCTAssertEqualObjects(lastS(c, @"viewTrendingStickerSets")[@"sticker_set_ids"],
						   (@[@(1), @(2)]));
	[c viewTrendingStickerSets:@[]];
	XCTAssertEqual(countS(c, @"viewTrendingStickerSets"), (NSUInteger)1);
}

- (void)testClearRecent_IsTheOrdinaryShelfNotTheAttachedOne {
	TGClient *c = S();
	[c clearRecentStickersAttached:NO];
	XCTAssertEqualObjects(lastS(c, @"clearRecentStickers")[@"is_attached"], @NO);
	[c clearRecentStickersAttached:YES];
	XCTAssertEqualObjects(lastS(c, @"clearRecentStickers")[@"is_attached"], @YES);
}

// ─── a supergroup's shelves ────────────────────────────────────────────────

- (void)testSupergroupStickerSet_ResolvesTheSupergroupIdFirst {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setSupergroupStickerSet:900 inChat:-1001 completion:^(BOOL value){ ok = value; }];
	NSDictionary *chat = lastS(c, @"getChat");
	XCTAssertEqualObjects(chat[@"chat_id"], @(-1001));
	answerS(c, @{@"@type" : @"chat", @"id" : @(-1001),
				 @"type" : @{@"@type" : @"chatTypeSupergroup",
							 @"supergroup_id" : @(44), @"is_channel" : @NO}});

	NSDictionary *r = lastS(c, @"setSupergroupStickerSet");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(44));
	XCTAssertEqualObjects(r[@"sticker_set_id"], @(900));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSupergroupCustomEmojiSet_IsItsOwnRequest {
	TGClient *c = S();
	__block BOOL ok = NO;
	[c setSupergroupCustomEmojiStickerSet:901 inChat:-1001
			completion:^(BOOL value){ ok = value; }];
	answerS(c, @{@"@type" : @"chat", @"id" : @(-1001),
				 @"type" : @{@"@type" : @"chatTypeSupergroup",
							 @"supergroup_id" : @(44), @"is_channel" : @NO}});
	NSDictionary *r = lastS(c, @"setSupergroupCustomEmojiStickerSet");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(44));
	XCTAssertEqualObjects(r[@"custom_emoji_sticker_set_id"], @(901));
	answerS(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSupergroupShelf_ABasicGroupIsRefusedWithoutASecondRequest {
	TGClient *c = S();
	__block BOOL answered = NO;
	__block BOOL ok = YES;
	[c setSupergroupStickerSet:900 inChat:-5 completion:^(BOOL value){
		answered = YES; ok = value;
	}];
	answerS(c, @{@"@type" : @"chat", @"id" : @(-5),
				 @"type" : @{@"@type" : @"chatTypeBasicGroup",
							 @"basic_group_id" : @(5)}});
	XCTAssertTrue(answered);
	XCTAssertFalse(ok);
	XCTAssertEqual(countS(c, @"setSupergroupStickerSet"), (NSUInteger)0);
}

@end
