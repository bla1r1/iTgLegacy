// TGClientEmojiReactionsTests.m - the emoji panel, reaction bar and topic
// reaction requests.
//
// The panel and the settings rows are UIKit and are checked on a device; what
// is pinned down here is that every row has a request behind it, that the
// answer lands in the field the row draws, and that the two settings writes
// keep the parts of their TDLib record this app does not show.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientEmojiReactionsTests : XCTestCase @end

static TGClient *ER(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	c.reactionDefaultEmoji = nil;
	c.reactionNotificationSettingsValue = nil;
	return c;
}

static NSDictionary *decodeER(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastER(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeER(d)[@"@type"] isEqualToString:type])
			found = decodeER(d);
	return found;
}

static NSDictionary *lastRequestedER(TGClient *c) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeER(d)[@"@extra"])
			sent = decodeER(d);
	return sent;
}

static void answerER(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = lastRequestedER(c);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainER(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *stickerER(NSInteger fileId, NSString *emoji) {
	return @{@"@type" : @"sticker",
			 @"sticker" : @{@"@type" : @"file", @"id" : @(fileId)},
			 @"format" : @{@"@type" : @"stickerFormatTgs"},
			 @"emoji" : emoji ?: @"",
			 @"width" : @(512), @"height" : @(512)};
}

@implementation TGClientEmojiReactionsTests

#pragma mark - categories and search

- (void)testEmojiCategories_AsksForTheDefaultsAndReadsTheSource {
	TGClient *c = ER();
	__block NSArray *got = nil;
	[c emojiCategoriesWithCompletion:^(NSArray *categories){ got = categories; }];

	NSDictionary *r = lastER(c, @"getEmojiCategories");
	XCTAssertNotNil(r);
	// td_api spells "the default categories" as a null type.
	XCTAssertEqualObjects(r[@"type"], [NSNull null]);

	answerER(c, plainER(@{@"@type" : @"emojiCategories",
		@"categories" : @[
			@{@"@type" : @"emojiCategory",
			  @"name" : @"Smileys & People",
			  @"icon" : stickerER(31, @"😀"),
			  @"source" : @{@"@type" : @"emojiCategorySourceSearch",
							@"emojis" : @[@"😀", @"😂"]},
			  @"is_greeting" : @NO},
			@{@"@type" : @"emojiCategory",
			  @"name" : @"Premium",
			  @"icon" : stickerER(32, @"⭐"),
			  @"source" : @{@"@type" : @"emojiCategorySourcePremium"},
			  @"is_greeting" : @NO}]}));

	XCTAssertEqual(got.count, 2);
	XCTAssertEqualObjects(got[0][@"name"], @"Smileys & People");
	XCTAssertEqualObjects(got[0][@"icon"], @"😀");
	XCTAssertEqualObjects(got[0][@"kind"], @"emojiCategorySourceSearch");
	XCTAssertEqualObjects(got[0][@"emojis"], (@[@"😀", @"😂"]));
	XCTAssertEqualObjects(got[1][@"kind"], @"emojiCategorySourcePremium");
	XCTAssertEqualObjects(got[1][@"emojis"], @[]);
}

- (void)testSearchEmojis_SendsTheTextAndLanguageAndDropsDuplicateGlyphs {
	TGClient *c = ER();
	__block NSArray *got = nil;
	[c searchEmojis:@"heart" languageCodes:@[@"en"] completion:^(NSArray *e){ got = e; }];

	NSDictionary *r = lastER(c, @"searchEmojis");
	XCTAssertEqualObjects(r[@"text"], @"heart");
	XCTAssertEqualObjects(r[@"input_language_codes"], (@[@"en"]));

	answerER(c, plainER(@{@"@type" : @"emojiKeywords",
		@"emoji_keywords" : @[
			@{@"@type" : @"emojiKeyword", @"emoji" : @"❤️", @"keyword" : @"heart"},
			@{@"@type" : @"emojiKeyword", @"emoji" : @"❤️", @"keyword" : @"love"},
			@{@"@type" : @"emojiKeyword", @"emoji" : @"💛", @"keyword" : @"heart"}]}));

	XCTAssertEqualObjects(got, (@[@"❤️", @"💛"]));
}

- (void)testKeywordEmojis_IsTheSuggestedRow {
	TGClient *c = ER();
	__block NSArray *got = nil;
	[c keywordEmojis:@"cat" languageCodes:@[] completion:^(NSArray *e){ got = e; }];

	NSDictionary *r = lastER(c, @"getKeywordEmojis");
	XCTAssertEqualObjects(r[@"text"], @"cat");
	XCTAssertEqualObjects(r[@"input_language_codes"], @[]);

	answerER(c, plainER(@{@"@type" : @"emojis", @"emojis" : @[@"🐱", @"🐈"]}));
	XCTAssertEqualObjects(got, (@[@"🐱", @"🐈"]));
}

- (void)testEmojiSuggestionsUrl_IsTheLinksText {
	TGClient *c = ER();
	__block NSString *got = nil;
	[c emojiSuggestionsUrlForLanguage:@"en" completion:^(NSString *u){ got = u; }];

	XCTAssertEqualObjects(lastER(c, @"getEmojiSuggestionsUrl")[@"language_code"], @"en");
	answerER(c, @{@"@type" : @"httpUrl",
				  @"url" : @"https://translations.telegram.org/en/suggest_emoji"});
	XCTAssertEqualObjects(got, @"https://translations.telegram.org/en/suggest_emoji");
}

#pragma mark - emoji metadata

- (void)testEmojiReaction_ReadsTheTitleAndTheAnimation {
	TGClient *c = ER();
	__block NSDictionary *got = nil;
	[c emojiReactionForEmoji:@"❤️" completion:^(NSDictionary *r){ got = r; }];

	XCTAssertEqualObjects(lastER(c, @"getEmojiReaction")[@"emoji"], @"❤️");
	answerER(c, plainER(@{@"@type" : @"emojiReaction",
		@"emoji" : @"❤️", @"title" : @"Red Heart", @"is_active" : @YES,
		@"static_icon" : stickerER(30, @"❤️"),
		@"center_animation" : stickerER(90, @"❤️"),
		@"appear_animation" : stickerER(91, @"❤️")}));

	XCTAssertEqualObjects(got[@"title"], @"Red Heart");
	XCTAssertEqualObjects(got[@"active"], @YES);
	// The centre animation is the one a card plays when it opens.
	XCTAssertEqualObjects(got[@"animation"][@"fileId"], @(90));
	XCTAssertEqualObjects(got[@"static"][@"fileId"], @(30));
}

- (void)testEmojiReaction_AnUnknownEmojiIsNil {
	TGClient *c = ER();
	__block NSDictionary *got = @{};
	[c emojiReactionForEmoji:@"🫠" completion:^(NSDictionary *r){ got = r; }];
	answerER(c, @{@"@type" : @"error", @"code" : @(404), @"message" : @"Not Found"});
	XCTAssertNil(got);
}

- (void)testAnimatedEmoji_ReadsTheStickerAndSound {
	TGClient *c = ER();
	__block NSDictionary *got = nil;
	[c animatedEmojiForEmoji:@"🎉" completion:^(NSDictionary *a){ got = a; }];

	XCTAssertEqualObjects(lastER(c, @"getAnimatedEmoji")[@"emoji"], @"🎉");
	answerER(c, plainER(@{@"@type" : @"animatedEmoji",
		@"sticker" : stickerER(77, @"🎉"),
		@"sticker_width" : @(512), @"sticker_height" : @(512),
		@"fitzpatrick_type" : @(0),
		@"sound" : @{@"@type" : @"file", @"id" : @(78)},
		@"is_regular_emoji" : @YES}));

	XCTAssertEqualObjects(got[@"fileId"], @(77));
	XCTAssertEqualObjects(got[@"soundId"], @(78));
	XCTAssertEqualObjects(got[@"regularEmoji"], @YES);
}

- (void)testCustomEmojiReactionAnimations_FlattensTheStickerList {
	TGClient *c = ER();
	__block NSArray *got = nil;
	[c customEmojiReactionAnimationsWithCompletion:^(NSArray *s){ got = s; }];
	XCTAssertNotNil(lastER(c, @"getCustomEmojiReactionAnimations"));

	NSMutableDictionary *first = [stickerER(55, @"🔥") mutableCopy];
	first[@"full_type"] = @{@"@type" : @"stickerFullTypeCustomEmoji",
							@"custom_emoji_id" : @(900),
							@"needs_repainting" : @NO};
	answerER(c, plainER(@{@"@type" : @"stickers", @"stickers" : @[first]}));

	XCTAssertEqual(got.count, 1);
	XCTAssertEqualObjects(got[0][@"fileId"], @(55));
	XCTAssertEqualObjects(got[0][@"customEmojiId"], @(900));
}

#pragma mark - reaction settings

- (void)testClearRecentReactions_IsAnswered {
	TGClient *c = ER();
	__block BOOL ok = NO;
	[c clearRecentReactionsWithCompletion:^(BOOL o){ ok = o; }];
	XCTAssertNotNil(lastRequestedER(c));
	XCTAssertEqualObjects(lastRequestedER(c)[@"@type"], @"clearRecentReactions");
	answerER(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetDefaultReaction_SendsTheEmojiAndLeadsTheBarAtOnce {
	TGClient *c = ER();
	__block BOOL ok = NO;
	[c setDefaultReactionEmoji:@"🔥" completion:^(BOOL o){ ok = o; }];

	NSDictionary *r = lastER(c, @"setDefaultReactionType");
	XCTAssertEqualObjects(r[@"reaction_type"][@"@type"], @"reactionTypeEmoji");
	XCTAssertEqualObjects(r[@"reaction_type"][@"emoji"], @"🔥");

	answerER(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	// The picker reads this the next time it opens; waiting for the update
	// would make it flick back to the old default in between.
	XCTAssertEqualObjects(c.defaultReactionEmoji, @"🔥");
}

- (void)testReactionNotificationSettings_TheUpdateIsKept {
	TGClient *c = ER();
	NSDictionary *record = @{@"@type" : @"reactionNotificationSettings",
							 @"message_reaction_source" :
								 @{@"@type" : @"reactionNotificationSourceContacts"},
							 @"story_reaction_source" :
								 @{@"@type" : @"reactionNotificationSourceNone"},
							 @"poll_vote_source" :
								 @{@"@type" : @"reactionNotificationSourceAll"},
							 @"sound_id" : @(4), @"show_preview" : @NO};
	[c handleUpdate:@{@"@type" : @"updateReactionNotificationSettings",
					  @"notification_settings" : record}];

	XCTAssertEqualObjects(c.reactionNotificationSettings[@"message_reaction_source"][@"@type"],
						 @"reactionNotificationSourceContacts");
	XCTAssertTrue(c.reactionNotificationsEnabled);
	XCTAssertEqualObjects(c.reactionNotificationSettings[@"sound_id"], @(4));
}

- (void)testReactionNotificationSettings_OffKeepsTheSourcesThisScreenDoesNotShow {
	TGClient *c = ER();
	[c handleUpdate:@{@"@type" : @"updateReactionNotificationSettings",
		@"notification_settings" : @{@"@type" : @"reactionNotificationSettings",
			@"message_reaction_source" : @{@"@type" : @"reactionNotificationSourceAll"},
			@"story_reaction_source" : @{@"@type" : @"reactionNotificationSourceContacts"},
			@"poll_vote_source" : @{@"@type" : @"reactionNotificationSourceAll"},
			@"sound_id" : @(4), @"show_preview" : @NO}}];

	__block BOOL ok = NO;
	[c setReactionNotificationsEnabled:NO completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = lastER(c, @"setReactionNotificationSettings");
	XCTAssertEqualObjects(r[@"notification_settings"][@"message_reaction_source"][@"@type"],
						 @"reactionNotificationSourceNone");
	// The switch owns one source; the others are Telegram's to keep.
	XCTAssertEqualObjects(r[@"notification_settings"][@"story_reaction_source"][@"@type"],
						 @"reactionNotificationSourceContacts");
	XCTAssertEqualObjects(r[@"notification_settings"][@"poll_vote_source"][@"@type"],
						 @"reactionNotificationSourceAll");
	XCTAssertEqualObjects(r[@"notification_settings"][@"sound_id"], @(4));
	XCTAssertEqualObjects(r[@"notification_settings"][@"show_preview"], @NO);

	answerER(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertFalse(c.reactionNotificationsEnabled);
}

- (void)testReactionNotificationSettings_DefaultIsOnWithNoRecord {
	TGClient *c = ER();
	XCTAssertNil(c.reactionNotificationSettings);
	XCTAssertTrue(c.reactionNotificationsEnabled);
}

#pragma mark - forum topics

- (void)testReadAllForumTopicReactions_SendsTheChatAndTopic {
	TGClient *c = ER();
	__block BOOL ok = NO;
	[c readAllForumTopicReactionsInChat:77 topic:12 completion:^(BOOL o){ ok = o; }];

	NSDictionary *r = lastER(c, @"readAllForumTopicReactions");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"forum_topic_id"], @(12));
	answerER(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testForumTopics_CarryTheUnreadReactionCount {
	TGClient *c = ER();
	__block NSArray *got = nil;
	[c forumTopicsForChat:77 completion:^(NSArray *t){ got = t; }];
	XCTAssertNotNil(lastER(c, @"getForumTopics"));

	answerER(c, plainER(@{@"@type" : @"forumTopics",
		@"topics" : @[@{
			@"@type" : @"forumTopic",
			@"info" : @{@"@type" : @"forumTopicInfo",
						@"message_thread_id" : @(12),
						@"name" : @"News"},
			@"last_message" : @{@"@type" : @"message", @"id" : @(5),
				@"date" : @(1700000000),
				@"content" : @{@"@type" : @"messageText",
					@"text" : @{@"@type" : @"formattedText", @"text" : @"hello"}}},
			@"unread_count" : @(1), @"unread_reaction_count" : @(3),
			@"is_pinned" : @NO}],
		@"total_count" : @(1)}));

	XCTAssertEqual(got.count, 1);
	XCTAssertEqualObjects(got[0][@"unreadReactions"], @(3));
}

@end
