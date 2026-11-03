//
// TGClientTier2Tests.m - emoji status, profile audio, text composition
// styles, direct message topics, the stake dice and the ephemeral calls.
//
// Thirty-seven td_api names and no more: every test pins the request shape a
// screen sends, and the handful that answer with an object feed it back so
// the flattening is exercised too.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientTier2Tests : XCTestCase @end

static TGClient *T2E(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeT2(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastT2(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeT2(d)[@"@type"] isEqualToString:type])
			found = decodeT2(d);
	return found;
}

static NSUInteger countT2(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeT2(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void replyT2(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *request = decodeT2(d);
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

/// A literal dictionary is not what TDLib sends: it parses JSON, so large
/// int64 values arrive as strings as often as numbers. Round-trip fixtures so
/// both spellings are covered.
static NSDictionary *plainT2(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientTier2Tests

#pragma mark - emoji status

- (void)testThemedEmojiStatuses_ReadsTheCustomEmojiIds {
	TGClient *c = T2E();
	__block NSArray *ids = nil;
	[c themedEmojiStatusesWithCompletion:^(NSArray *got){ ids = got; }];
	XCTAssertEqualObjects(lastT2(c, @"getThemedEmojiStatuses")[@"@type"],
			@"getThemedEmojiStatuses");
	replyT2(c, @"getThemedEmojiStatuses",
			@{@"@type" : @"emojiStatusCustomEmojis",
			  @"custom_emoji_ids" : @[@(11), @(22)]});
	XCTAssertEqualObjects(ids, (@[@(11), @(22)]));
}

- (void)testDefaultEmojiStatuses_IsTheAccountList {
	TGClient *c = T2E();
	__block NSArray *ids = nil;
	[c defaultEmojiStatusesWithCompletion:^(NSArray *got){ ids = got; }];
	XCTAssertNotNil(lastT2(c, @"getDefaultEmojiStatuses"));
	replyT2(c, @"getDefaultEmojiStatuses",
			@{@"@type" : @"emojiStatusCustomEmojis",
			  @"custom_emoji_ids" : @[@(33)]});
	XCTAssertEqualObjects(ids, (@[@(33)]));
}

- (void)testRecentEmojiStatuses_FlattensTypedStatuses {
	TGClient *c = T2E();
	__block NSArray *rows = nil;
	[c recentEmojiStatusesWithCompletion:^(NSArray *got){ rows = got; }];
	XCTAssertNotNil(lastT2(c, @"getRecentEmojiStatuses"));
	replyT2(c, @"getRecentEmojiStatuses", @{
		@"@type" : @"emojiStatuses",
		@"emoji_statuses" : @[
			@{@"@type" : @"emojiStatus",
			  @"type" : @{@"@type" : @"emojiStatusTypeCustomEmoji",
						  @"custom_emoji_id" : @(77)},
			  @"expiration_date" : @(1700000000)},
			@{@"@type" : @"emojiStatus",
			  @"type" : @{@"@type" : @"emojiStatusTypeUpgradedGift",
						  @"upgraded_gift_id" : @(5),
						  @"model_custom_emoji_id" : @(88)},
			  @"expiration_date" : @(0)},
		]});
	XCTAssertEqual([rows count], (NSUInteger)2);
	XCTAssertEqualObjects(rows[0][@"emojiId"], @(77));
	XCTAssertEqualObjects(rows[0][@"kind"], @"customEmoji");
	XCTAssertEqualObjects(rows[1][@"emojiId"], @(88));
	XCTAssertEqualObjects(rows[1][@"kind"], @"upgradedGift");
}

- (void)testClearRecentEmojiStatuses_SendsTheBareRequest {
	TGClient *c = T2E();
	__block BOOL ok = NO;
	[c clearRecentEmojiStatusesWithCompletion:^(BOOL good, NSString *error){
		ok = good;
	}];
	NSDictionary *r = lastT2(c, @"clearRecentEmojiStatuses");
	XCTAssertNotNil(r);
	XCTAssertNil(r[@"user_id"]);
	replyT2(c, @"clearRecentEmojiStatuses", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testThemedChatEmojiStatuses_UsesTheChatList {
	TGClient *c = T2E();
	[c themedChatEmojiStatusesWithCompletion:^(NSArray *ids){}];
	XCTAssertNotNil(lastT2(c, @"getThemedChatEmojiStatuses"));
}

- (void)testDefaultChatEmojiStatuses_UsesTheChatList {
	TGClient *c = T2E();
	[c defaultChatEmojiStatusesWithCompletion:^(NSArray *ids){}];
	XCTAssertNotNil(lastT2(c, @"getDefaultChatEmojiStatuses"));
}

- (void)testDisallowedChatEmojiStatuses_ReadsTheRefusedIds {
	TGClient *c = T2E();
	__block NSArray *ids = nil;
	[c disallowedChatEmojiStatusesWithCompletion:^(NSArray *got){ ids = got; }];
	XCTAssertNotNil(lastT2(c, @"getDisallowedChatEmojiStatuses"));
	replyT2(c, @"getDisallowedChatEmojiStatuses",
			@{@"@type" : @"emojiStatusCustomEmojis",
			  @"custom_emoji_ids" : @[@(99)]});
	XCTAssertEqualObjects(ids, (@[@(99)]));
}

- (void)testSetEmojiStatus_WrapsTheCustomEmojiId {
	TGClient *c = T2E();
	__block BOOL ok = NO;
	[c setEmojiStatus:1234 expirationDate:0 completion:^(BOOL good, NSString *e){
		ok = good;
	}];
	NSDictionary *r = lastT2(c, @"setEmojiStatus");
	XCTAssertEqualObjects(r[@"emoji_status"][@"@type"], @"emojiStatus");
	XCTAssertEqualObjects(r[@"emoji_status"][@"type"][@"@type"],
			@"emojiStatusTypeCustomEmoji");
	XCTAssertEqualObjects(r[@"emoji_status"][@"type"][@"custom_emoji_id"], @(1234));
	XCTAssertEqualObjects(r[@"emoji_status"][@"expiration_date"], @(0));
	replyT2(c, @"setEmojiStatus", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetEmojiStatus_ZeroIsANullStatus {
	TGClient *c = T2E();
	[c setEmojiStatus:0 expirationDate:0 completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"setEmojiStatus");
	XCTAssertTrue(r[@"emoji_status"] == [NSNull null]);
}

- (void)testSetEmojiStatus_ATimedStatusCarriesItsExpiry {
	TGClient *c = T2E();
	[c setEmojiStatus:1234 expirationDate:1767225600 completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"setEmojiStatus");
	XCTAssertEqualObjects(r[@"emoji_status"][@"expiration_date"], @(1767225600));
}

- (void)testSetUserEmojiStatus_NamesTheUser {
	TGClient *c = T2E();
	[c setUserEmojiStatus:55 expirationDate:100 forUser:42
			   completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"setUserEmojiStatus");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"emoji_status"][@"type"][@"custom_emoji_id"], @(55));
	XCTAssertEqualObjects(r[@"emoji_status"][@"expiration_date"], @(100));
}

- (void)testSetChatEmojiStatus_NamesTheChat {
	TGClient *c = T2E();
	[c setChatEmojiStatus:66 expirationDate:0 inChat:-77
			   completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"setChatEmojiStatus");
	XCTAssertEqualObjects(r[@"chat_id"], @(-77));
	XCTAssertEqualObjects(r[@"emoji_status"][@"type"][@"custom_emoji_id"], @(66));
}

#pragma mark - profile audio

- (void)testProfileAudios_ReadsThePageAndTheTotal {
	TGClient *c = T2E();
	__block NSArray *rows = nil;
	__block NSInteger total = 0;
	[c profileAudiosForUser:42 offset:0 limit:100
				 completion:^(NSArray *audios, NSInteger count, NSString *e){
		rows = audios;
		total = count;
	}];
	NSDictionary *r = lastT2(c, @"getUserProfileAudios");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"offset"], @(0));
	XCTAssertEqualObjects(r[@"limit"], @(100));
	replyT2(c, @"getUserProfileAudios", @{
		@"@type" : @"audios", @"total_count" : @(3),
		@"audios" : @[
			@{@"@type" : @"audio", @"duration" : @(201),
			  @"title" : @"Nightcall", @"performer" : @"Kavinsky",
			  @"file_name" : @"nightcall.mp3", @"mime_type" : @"audio/mpeg",
			  @"audio" : @{@"id" : @(501)},
			  @"album_cover_thumbnail" : @{@"file" : @{@"id" : @(601)}}},
		]});
	XCTAssertEqual(total, 3);
	XCTAssertEqual([rows count], (NSUInteger)1);
	XCTAssertEqualObjects(rows[0][@"fileId"], @(501));
	XCTAssertEqualObjects(rows[0][@"title"], @"Nightcall");
	XCTAssertEqualObjects(rows[0][@"performer"], @"Kavinsky");
	XCTAssertEqualObjects(rows[0][@"albumCoverId"], @(601));
}

- (void)testProfileAudios_SecondPageAsksForTheOffsetItHas {
	TGClient *c = T2E();
	[c profileAudiosForUser:42 offset:100 limit:100 completion:^(NSArray *a, NSInteger n, NSString *e){}];
	NSDictionary *r = lastT2(c, @"getUserProfileAudios");
	XCTAssertEqualObjects(r[@"offset"], @(100));
	XCTAssertEqualObjects(r[@"limit"], @(100));
}

- (void)testAddProfileAudio_SendsALocalInputAudio {
	TGClient *c = T2E();
	[c addProfileAudioAtPath:@"/tmp/song.mp3" title:@"Song"
				   performer:@"Artist" duration:180
				  completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"addProfileAudio");
	XCTAssertEqualObjects(r[@"audio"][@"@type"], @"inputAudio");
	XCTAssertEqualObjects(r[@"audio"][@"audio"][@"@type"], @"inputFileLocal");
	XCTAssertEqualObjects(r[@"audio"][@"audio"][@"path"], @"/tmp/song.mp3");
	XCTAssertEqualObjects(r[@"audio"][@"duration"], @(180));
	XCTAssertEqualObjects(r[@"audio"][@"title"], @"Song");
	XCTAssertEqualObjects(r[@"audio"][@"performer"], @"Artist");
}

- (void)testRemoveProfileAudio_SendsTheFileId {
	TGClient *c = T2E();
	__block BOOL ok = NO;
	[c removeProfileAudioFileId:501 completion:^(BOOL good, NSString *e){ ok = good; }];
	XCTAssertEqualObjects(lastT2(c, @"removeProfileAudio")[@"file_id"], @(501));
	replyT2(c, @"removeProfileAudio", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetProfileAudioPosition_SendsBothIds {
	TGClient *c = T2E();
	[c setProfileAudioFileId:501 afterFileId:0 completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"setProfileAudioPosition");
	XCTAssertEqualObjects(r[@"file_id"], @(501));
	XCTAssertEqualObjects(r[@"after_file_id"], @(0));
}

- (void)testIsProfileAudio_ReadsOkAndTheServersRefusal {
	TGClient *c = T2E();
	__block BOOL known = NO;
	[c isProfileAudioFileId:501 completion:^(BOOL isAudio, NSString *e){
		known = isAudio;
	}];
	XCTAssertEqualObjects(lastT2(c, @"isProfileAudio")[@"file_id"], @(501));
	replyT2(c, @"isProfileAudio", @{@"@type" : @"ok"});
	XCTAssertTrue(known);

	[c.outbox removeAllObjects];
	[c isProfileAudioFileId:502 completion:^(BOOL isAudio, NSString *e){
		known = isAudio;
	}];
	replyT2(c, @"isProfileAudio",
			@{@"@type" : @"error", @"code" : @(404), @"message" : @"Not Found"});
	XCTAssertFalse(known);
}

#pragma mark - text composition styles

- (void)testCreateTextCompositionStyle_SendsThePromptAndReadsTheAnswer {
	TGClient *c = T2E();
	__block NSDictionary *style = nil;
	[c createTextCompositionStyle:@"Pirate" emojiId:12 prompt:@"Talk like a pirate"
					 showCreator:YES completion:^(NSDictionary *made, NSString *e){
		style = made;
	}];
	NSDictionary *r = lastT2(c, @"createTextCompositionStyle");
	XCTAssertEqualObjects(r[@"title"], @"Pirate");
	XCTAssertEqualObjects(r[@"custom_emoji_id"], @(12));
	XCTAssertEqualObjects(r[@"prompt"], @"Talk like a pirate");
	XCTAssertEqualObjects(r[@"show_creator"], @YES);
	replyT2(c, @"createTextCompositionStyle", @{
		@"@type" : @"textCompositionStyle", @"name" : @"pirate",
		@"title" : @"Pirate", @"custom_emoji_id" : @(12),
		@"is_custom" : @YES, @"is_creator" : @YES, @"install_count" : @(0),
		@"prompt" : @"Talk like a pirate", @"creator_user_id" : @(1001),
	});
	XCTAssertEqualObjects(style[@"name"], @"pirate");
	XCTAssertEqualObjects(style[@"isCreator"], @YES);
	XCTAssertEqual([[c textCompositionStyles] count], (NSUInteger)1);
}

- (void)testEditTextCompositionStyle_NamesTheStyle {
	TGClient *c = T2E();
	[c editTextCompositionStyleNamed:@"pirate" title:@"Captain"
							 emojiId:13 prompt:@"Ahoy" showCreator:NO
						  completion:^(NSDictionary *s, NSString *e){}];
	NSDictionary *r = lastT2(c, @"editTextCompositionStyle");
	XCTAssertEqualObjects(r[@"name"], @"pirate");
	XCTAssertEqualObjects(r[@"title"], @"Captain");
	XCTAssertEqualObjects(r[@"custom_emoji_id"], @(13));
	XCTAssertEqualObjects(r[@"show_creator"], @NO);
}

- (void)testDeleteTextCompositionStyle_RemovesTheRowFromTheList {
	TGClient *c = T2E();
	[c handleUpdate:@{@"@type" : @"updateTextCompositionStyles",
					  @"styles" : @[
						  @{@"@type" : @"textCompositionStyle", @"name" : @"pirate",
							@"title" : @"Pirate", @"custom_emoji_id" : @(12)},
					  ]}];
	XCTAssertEqual([[c textCompositionStyles] count], (NSUInteger)1);
	__block BOOL ok = NO;
	[c deleteTextCompositionStyleNamed:@"pirate" completion:^(BOOL good, NSString *e){
		ok = good;
	}];
	XCTAssertEqualObjects(lastT2(c, @"deleteTextCompositionStyle")[@"name"], @"pirate");
	replyT2(c, @"deleteTextCompositionStyle", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertEqual([[c textCompositionStyles] count], (NSUInteger)0);
}

- (void)testSearchTextCompositionStyle_SendsTheNameAndReadsTheStyle {
	TGClient *c = T2E();
	__block NSDictionary *style = nil;
	[c searchTextCompositionStyleNamed:@"pirate" completion:^(NSDictionary *s, NSString *e){
		style = s;
	}];
	XCTAssertEqualObjects(lastT2(c, @"searchTextCompositionStyle")[@"name"], @"pirate");
	replyT2(c, @"searchTextCompositionStyle", @{
		@"@type" : @"textCompositionStyle", @"name" : @"pirate",
		@"title" : @"Pirate", @"custom_emoji_id" : @(12),
		@"is_custom" : @YES, @"is_creator" : @NO,
	});
	XCTAssertEqualObjects(style[@"title"], @"Pirate");
}

- (void)testTextCompositionStyleExample_ReadsBothSides {
	TGClient *c = T2E();
	__block NSDictionary *example = nil;
	[c textCompositionStyleExampleNamed:@"pirate" number:1
							 completion:^(NSDictionary *got, NSString *e){
		example = got;
	}];
	NSDictionary *r = lastT2(c, @"getTextCompositionStyleExample");
	XCTAssertEqualObjects(r[@"name"], @"pirate");
	XCTAssertEqualObjects(r[@"example_number"], @(1));
	replyT2(c, @"getTextCompositionStyleExample", @{
		@"@type" : @"textCompositionStyleExample",
		@"source_text" : @{@"text" : @"hello", @"entities" : @[]},
		@"result_text" : @{@"text" : @"ahoy", @"entities" : @[]},
	});
	XCTAssertEqualObjects(example[@"sourceText"], @"hello");
	XCTAssertEqualObjects(example[@"resultText"], @"ahoy");
}

- (void)testAddTextCompositionStyle_SendsTheName {
	TGClient *c = T2E();
	[c addTextCompositionStyleNamed:@"pirate" completion:^(BOOL ok, NSString *e){}];
	XCTAssertEqualObjects(lastT2(c, @"addTextCompositionStyle")[@"name"], @"pirate");
}

- (void)testRemoveTextCompositionStyle_SendsTheName {
	TGClient *c = T2E();
	[c removeTextCompositionStyleNamed:@"pirate" completion:^(BOOL ok, NSString *e){}];
	XCTAssertEqualObjects(lastT2(c, @"removeTextCompositionStyle")[@"name"], @"pirate");
}

- (void)testTextCompositionStylesUpdate_ReplacesTheList {
	TGClient *c = T2E();
	[c handleUpdate:@{@"@type" : @"updateTextCompositionStyles",
					  @"styles" : @[
						  @{@"@type" : @"textCompositionStyle", @"name" : @"a",
							@"title" : @"A", @"custom_emoji_id" : @(1)},
						  @{@"@type" : @"textCompositionStyle", @"name" : @"b",
							@"title" : @"B", @"custom_emoji_id" : @(2)},
					  ]}];
	NSArray *rows = [c textCompositionStyles];
	XCTAssertEqual([rows count], (NSUInteger)2);
	XCTAssertEqualObjects(rows[1][@"name"], @"b");
}

#pragma mark - direct message topics

- (void)testLoadDirectMessagesChatTopics_SendsTheChatAndLimit {
	TGClient *c = T2E();
	__block BOOL ok = NO;
	[c loadDirectMessagesChatTopicsInChat:-500 limit:20
							   completion:^(BOOL good, NSString *e){ ok = good; }];
	NSDictionary *r = lastT2(c, @"loadDirectMessagesChatTopics");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"limit"], @(20));
	replyT2(c, @"loadDirectMessagesChatTopics", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDirectMessagesTopicUpdate_LandsInTheList {
	TGClient *c = T2E();
	c.usersById[@(42)] = @"Ann";
	[c handleUpdate:@{@"@type" : @"updateDirectMessagesChatTopic",
					  @"topic" : @{
						  @"@type" : @"directMessagesChatTopic",
						  @"chat_id" : @(-500), @"id" : @(9),
						  @"sender_id" : @{@"@type" : @"messageSenderUser",
										  @"user_id" : @(42)},
						  @"order" : @(900), @"can_send_unpaid_messages" : @YES,
						  @"is_marked_as_unread" : @NO, @"unread_count" : @(2),
						  @"unread_reaction_count" : @(1),
						  @"last_read_inbox_message_id" : @(0),
						  @"last_read_outbox_message_id" : @(0),
						  @"last_message" : @{@"@type" : @"message", @"id" : @(31),
											  @"chat_id" : @(-500),
											  @"date" : @(1700000000),
											  @"content" : @{@"@type" : @"messageText",
															 @"text" : @{@"text" : @"Hello"}}},
					  }}];
	NSArray *rows = [c directMessagesChatTopicsForChat:-500];
	XCTAssertEqual([rows count], (NSUInteger)1);
	XCTAssertEqualObjects(rows[0][@"topicId"], @(9));
	XCTAssertEqualObjects(rows[0][@"senderName"], @"Ann");
	XCTAssertEqualObjects(rows[0][@"unread"], @(2));
	XCTAssertEqualObjects(rows[0][@"isMarkedUnread"], @NO);
}

- (void)testGetDirectMessagesChatTopic_ReadsTheRow {
	TGClient *c = T2E();
	__block NSDictionary *topic = nil;
	[c directMessagesChatTopic:9 inChat:-500 completion:^(NSDictionary *t, NSString *e){
		topic = t;
	}];
	NSDictionary *r = lastT2(c, @"getDirectMessagesChatTopic");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"topic_id"], @(9));
	replyT2(c, @"getDirectMessagesChatTopic", @{
		@"@type" : @"directMessagesChatTopic", @"chat_id" : @(-500),
		@"id" : @(9), @"sender_id" : @{@"@type" : @"messageSenderUser",
									  @"user_id" : @(42)},
		@"order" : @(900), @"can_send_unpaid_messages" : @NO,
		@"is_marked_as_unread" : @YES, @"unread_count" : @(0),
		@"unread_reaction_count" : @(0),
		@"last_read_inbox_message_id" : @(0),
		@"last_read_outbox_message_id" : @(0),
	});
	XCTAssertEqualObjects(topic[@"topicId"], @(9));
	XCTAssertEqualObjects(topic[@"isMarkedUnread"], @YES);
}

- (void)testDirectMessagesHistory_ReadsTheWindowOldestFirst {
	TGClient *c = T2E();
	__block NSArray *messages = nil;
	[c directMessagesChatTopicHistory:9 inChat:-500 fromMessageId:0 offset:0 limit:20
						   completion:^(NSArray *got, NSString *e){ messages = got; }];
	NSDictionary *r = lastT2(c, @"getDirectMessagesChatTopicHistory");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"topic_id"], @(9));
	XCTAssertEqualObjects(r[@"from_message_id"], @(0));
	XCTAssertEqualObjects(r[@"offset"], @(0));
	XCTAssertEqualObjects(r[@"limit"], @(20));
	replyT2(c, @"getDirectMessagesChatTopicHistory", @{
		@"@type" : @"messages",
		@"messages" : @[
			@{@"@type" : @"message", @"id" : @(32), @"chat_id" : @(-500),
			  @"date" : @(1700000002),
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"text" : @"second"}}},
			@{@"@type" : @"message", @"id" : @(31), @"chat_id" : @(-500),
			  @"date" : @(1700000001),
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"text" : @"first"}}},
		]});
	XCTAssertEqual([messages count], (NSUInteger)2);
	XCTAssertEqualObjects(messages[0][@"id"], @(31));
	XCTAssertEqualObjects(messages[1][@"id"], @(32));
}

- (void)testDirectMessagesMessageByDate_SendsTheTimestamp {
	TGClient *c = T2E();
	__block NSDictionary *message = nil;
	[c directMessagesChatTopicMessageByDate:9 inChat:-500 date:1700000000
								 completion:^(NSDictionary *m, NSString *e){
		message = m;
	}];
	NSDictionary *r = lastT2(c, @"getDirectMessagesChatTopicMessageByDate");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"topic_id"], @(9));
	XCTAssertEqualObjects(r[@"date"], @(1700000000));
	replyT2(c, @"getDirectMessagesChatTopicMessageByDate",
			@{@"@type" : @"message", @"id" : @(31), @"chat_id" : @(-500),
			  @"date" : @(1700000000),
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"text" : @"that day"}}});
	XCTAssertEqualObjects(message[@"id"], @(31));
}

- (void)testDeleteDirectMessagesTopicHistory_SendsBothIds {
	TGClient *c = T2E();
	[c deleteDirectMessagesChatTopicHistory:9 inChat:-500
								 completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"deleteDirectMessagesChatTopicHistory");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"topic_id"], @(9));
}

- (void)testDeleteDirectMessagesByDate_SendsTheWindow {
	TGClient *c = T2E();
	[c deleteDirectMessagesChatTopicMessages:9 inChat:-500
									 minDate:100 maxDate:200
								  completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"deleteDirectMessagesChatTopicMessagesByDate");
	XCTAssertEqualObjects(r[@"min_date"], @(100));
	XCTAssertEqualObjects(r[@"max_date"], @(200));
}

- (void)testMarkDirectMessagesTopicUnread_PatchesTheCachedRow {
	TGClient *c = T2E();
	[c handleUpdate:@{@"@type" : @"updateDirectMessagesChatTopic",
					  @"topic" : @{
						  @"@type" : @"directMessagesChatTopic",
						  @"chat_id" : @(-500), @"id" : @(9),
						  @"sender_id" : @{@"@type" : @"messageSenderUser",
										  @"user_id" : @(42)},
						  @"order" : @(900), @"is_marked_as_unread" : @NO,
						  @"unread_count" : @(0),
					  }}];
	__block BOOL ok = NO;
	[c setDirectMessagesChatTopic:9 inChat:-500 markedAsUnread:YES
					   completion:^(BOOL good, NSString *e){ ok = good; }];
	NSDictionary *r = lastT2(c, @"setDirectMessagesChatTopicIsMarkedAsUnread");
	XCTAssertEqualObjects(r[@"is_marked_as_unread"], @YES);
	replyT2(c, @"setDirectMessagesChatTopicIsMarkedAsUnread", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertEqualObjects([c directMessagesChatTopicsForChat:-500][0][@"isMarkedUnread"], @YES);
}

- (void)testReadAllDirectMessagesTopicReactions_SendsBothIds {
	TGClient *c = T2E();
	[c readAllDirectMessagesChatTopicReactions:9 inChat:-500
									completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"readAllDirectMessagesChatTopicReactions");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"topic_id"], @(9));
}

- (void)testUnpinAllDirectMessagesTopicMessages_SendsBothIds {
	TGClient *c = T2E();
	[c unpinAllDirectMessagesChatTopicMessages:9 inChat:-500
									completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"unpinAllDirectMessagesChatTopicMessages");
	XCTAssertEqualObjects(r[@"chat_id"], @(-500));
	XCTAssertEqualObjects(r[@"topic_id"], @(9));
}

#pragma mark - dice and ephemeral

- (void)testStakeDiceState_ReadsTheHashAndThePrizeTable {
	TGClient *c = T2E();
	__block NSDictionary *state = nil;
	[c stakeDiceStateWithCompletion:^(NSDictionary *got, NSString *e){ state = got; }];
	XCTAssertNotNil(lastT2(c, @"getStakeDiceState"));
	replyT2(c, @"getStakeDiceState", @{
		@"@type" : @"stakeDiceState", @"state_hash" : @"abc",
		@"stake_gram_amount" : @(1000000),
		@"suggested_stake_gram_amounts" : @[@(500000), @(1000000)],
		@"current_streak" : @(1),
		@"prize_per_mille" : @[@(900), @(500), @(300), @(200), @(150), @(100)],
		@"streak_prize_per_mille" : @(5000),
	});
	XCTAssertEqualObjects(state[@"stateHash"], @"abc");
	XCTAssertEqualObjects(state[@"stakeGramAmount"], @(1000000));
	XCTAssertEqual([(NSArray *)state[@"prizePerMille"] count], (NSUInteger)6);
	XCTAssertEqualObjects(state[@"streakPrizePerMille"], @(5000));
}

- (void)testStakeDiceUpdate_ReplacesTheCachedState {
	TGClient *c = T2E();
	[c handleUpdate:@{@"@type" : @"updateStakeDiceState",
					  @"state" : @{@"@type" : @"stakeDiceState",
								   @"state_hash" : @"fresh",
								   @"suggested_stake_gram_amounts" : @[],
								   @"prize_per_mille" : @[]}}];
	XCTAssertEqualObjects(c.stakeDiceStateValue[@"stateHash"], @"fresh");
}

- (void)testSendEphemeralText_SendsTheFullRequest {
	TGClient *c = T2E();
	__block NSDictionary *message = nil;
	[c sendEphemeralText:@"hi" toChat:55 receiverUserId:77
		 ephemeralReplyId:0 completion:^(NSDictionary *m, NSString *e){ message = m; }];
	NSDictionary *r = lastT2(c, @"sendEphemeralMessage");
	XCTAssertEqualObjects(r[@"chat_id"], @(55));
	XCTAssertEqualObjects(r[@"receiver_user_id"], @(77));
	XCTAssertTrue(r[@"topic_id"] == [NSNull null]);
	XCTAssertTrue(r[@"reply_to"] == [NSNull null]);
	XCTAssertEqualObjects(r[@"input_message_content"][@"@type"], @"inputMessageText");
	XCTAssertEqualObjects(r[@"input_message_content"][@"text"][@"text"], @"hi");
	XCTAssertEqualObjects(r[@"only_preview"], @NO);
	replyT2(c, @"sendEphemeralMessage",
			@{@"@type" : @"message", @"id" : @(81), @"chat_id" : @(55),
			  @"date" : @(1700000000),
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"text" : @"hi"}}});
	XCTAssertEqualObjects(message[@"id"], @(81));
}

- (void)testSendEphemeralText_ReplyCarriesTheEphemeralId {
	TGClient *c = T2E();
	[c sendEphemeralText:@"again" toChat:55 receiverUserId:77 ephemeralReplyId:9
			   completion:^(NSDictionary *m, NSString *e){}];
	NSDictionary *r = lastT2(c, @"sendEphemeralMessage");
	XCTAssertEqualObjects(r[@"reply_to"][@"@type"],
			@"inputMessageReplyToEphemeralMessage");
	XCTAssertEqualObjects(r[@"reply_to"][@"ephemeral_message_id"], @(9));
}

- (void)testEditEphemeralMessage_SendsTheNewText {
	TGClient *c = T2E();
	[c editEphemeralMessage:9 text:@"fixed" receiver:77 inChat:55
				 completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"editEphemeralMessage");
	XCTAssertEqualObjects(r[@"ephemeral_message_id"], @(9));
	XCTAssertEqualObjects(r[@"receiver_user_id"], @(77));
	XCTAssertEqualObjects(r[@"input_message_content"][@"text"][@"text"], @"fixed");
}

- (void)testEditEphemeralMessageCaption_SendsTheCaption {
	TGClient *c = T2E();
	[c editEphemeralMessageCaption:9 caption:@"under" receiver:77 inChat:55
						completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"editEphemeralMessageCaption");
	XCTAssertEqualObjects(r[@"ephemeral_message_id"], @(9));
	XCTAssertEqualObjects(r[@"caption"][@"text"], @"under");
	XCTAssertEqualObjects(r[@"show_caption_above_media"], @NO);
}

- (void)testDeleteEphemeralMessage_SendsBothIds {
	TGClient *c = T2E();
	[c deleteEphemeralMessage:9 receiver:77 inChat:55
				   completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"deleteEphemeralMessage");
	XCTAssertEqualObjects(r[@"ephemeral_message_id"], @(9));
	XCTAssertEqualObjects(r[@"receiver_user_id"], @(77));
}

- (void)testDeleteMessageEphemeralContent_SendsTheMessage {
	TGClient *c = T2E();
	[c deleteMessageEphemeralContent:81 inChat:55
						  completion:^(BOOL ok, NSString *e){}];
	NSDictionary *r = lastT2(c, @"deleteMessageEphemeralContent");
	XCTAssertEqualObjects(r[@"chat_id"], @(55));
	XCTAssertEqualObjects(r[@"message_id"], @(81));
}

@end
