// TGClientMessagesFunctionsTests.m — the message functions the second wave
// of screens ask for: what a t.me message link resolves to, whether a
// compose with a user can go through at all, the drafts broom, the global
// auto-delete timer, and the two supergroup switches the group menu grew.
//
// Requests sit in the outbox where their shape can be asserted, answers
// come back through handleUpdate the way the receive loop delivers them.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGBase64.h"

@interface TGClientMessagesFunctionsTests : XCTestCase @end

static TGClient *M(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.me = @{@"id" : @(1001)};
	// A loaded chat row, for the cached-supergroup-id branch.
	[c.chatsById removeAllObjects];
	c.chatsById[@(77)] = [@{@"id" : @(77), @"title" : @"Legacy Club",
							@"supergroupId" : @(9001)} mutableCopy];
	// A fresh chat each test; one prior instance would answer the wrong test.
	c.chats = @[];
	return c;
}

static NSDictionary *decodeM(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastM(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeM(d)[@"@type"] isEqualToString:type])
			found = decodeM(d);
	return found;
}

static void answerM(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeM(d)[@"@extra"])
			sent = decodeM(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

/// A literal inside a test file is the compiler's NSConstantDictionary,
/// whose subscripts answer nil one level down. Real answers from TDLib are
/// parsed dictionaries, so the wire shape is what the app sees; the helper
/// is the same round trip.
static NSDictionary *plain(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientMessagesFunctionsTests

// ─── message links ───────────────────────────────────────────────────────────

- (void)testMessageLinkInfo_NamesTheChatAndTheMessage {
	TGClient *c = M();
	__block int64_t chatId = 0, messageId = 0;
	[[TGClient shared] messageLinkInfo:@"https://t.me/duplex/42"
							completion:^(int64_t aChat, int64_t aMessage){
		chatId = aChat; messageId = aMessage;
	}];

	NSDictionary *r = lastM(c, @"getMessageLinkInfo");
	XCTAssertEqualObjects(r[@"url"], @"https://t.me/duplex/42");

	// int53 arrives as a string; a naïve integerValue on a number would
	// break the day TDLib stops stringifying it - both shapes answer this.
	answerM(c, @{@"@type" : @"messageLinkInfo",
				 @"chat_id" : @"77123",
				 @"message" : @{@"@type" : @"message", @"id" : @(456)}});
	XCTAssertEqual(chatId, 77123LL);
	XCTAssertEqual(messageId, 456LL);
}

- (void)testMessageLinkInfo_ARefusalIsAZeroChat {
	TGClient *c = M();
	__block int64_t chatId = -1, messageId = -1;
	[[TGClient shared] messageLinkInfo:@"https://t.me/gone/1"
							completion:^(int64_t aChat, int64_t aMessage){
		chatId = aChat; messageId = aMessage;
	}];
	answerM(c, @{@"@type" : @"error", @"code" : @(400),
				 @"message" : @"MESSAGE_LINK_NOT_FOUND"});
	XCTAssertEqual(chatId, 0LL);
	XCTAssertEqual(messageId, 0LL);
}

- (void)testMessageLinkInfo_AnEmptyLinkSkipsTheRoundTrip {
	TGClient *c = M();
	__block int64_t chatId = -1;
	[c messageLinkInfo:@"" completion:^(int64_t aChat, int64_t aMessage){ chatId = aChat; }];
	XCTAssertEqual(chatId, 0LL);
	XCTAssertNil(lastM(c, @"getMessageLinkInfo"));
}

// ─── can send ────────────────────────────────────────────────────────────────

- (void)testCanSendMessageToUser_AllFourAnswersGetWords {
	TGClient *c = M();
	__block NSString *got = nil;

	[[TGClient shared] canSendMessageToUser:5 completion:^(NSString *r){ got = r; }];
	XCTAssertEqualObjects(lastM(c, @"canSendMessageToUser")[@"user_id"], @(5));
	answerM(c, @{@"@type" : @"canSendMessageToUserResultOk"});
	XCTAssertEqualObjects(got, @"ok");

	[c.outbox removeAllObjects];
	got = nil;
	[[TGClient shared] canSendMessageToUser:5 completion:^(NSString *r){ got = r; }];
	answerM(c, @{@"@type" : @"canSendMessageToUserResultUserHasPaidMessages",
				 @"outgoing_paid_message_star_count" : @(25)});
	// Paying is not free, but it is a go - the caller names the price.
	XCTAssertEqualObjects(got, @"paidMessages");

	[c.outbox removeAllObjects];
	got = nil;
	[[TGClient shared] canSendMessageToUser:5 completion:^(NSString *r){ got = r; }];
	answerM(c, @{@"@type" : @"canSendMessageToUserResultUserRestrictsNewChats"});
	XCTAssertEqualObjects(got, @"userRestrictsNewChats");

	[c.outbox removeAllObjects];
	got = nil;
	[[TGClient shared] canSendMessageToUser:5 completion:^(NSString *r){ got = r; }];
	answerM(c, @{@"@type" : @"canSendMessageToUserResultUserIsDeleted"});
	XCTAssertEqualObjects(got, @"userDeleted");

	// A zero user asks nothing and answers the refuse word.
	[c.outbox removeAllObjects];
	got = nil;
	[[TGClient shared] canSendMessageToUser:0 completion:^(NSString *r){ got = r; }];
	XCTAssertEqualObjects(got, @"userDeleted");
	XCTAssertNil(lastM(c, @"canSendMessageToUser"));
}

// ─── drafts and the default timer ────────────────────────────────────────────

- (void)testClearAllDraftMessages_SendsAndNeedsNoExtra {
	TGClient *c = M();
	[c clearAllDraftMessages];
	NSDictionary *r = lastM(c, @"clearAllDraftMessages");
	XCTAssertNotNil(r);
	// No completion was handed in, so no @extra rides along: one-shot.
	XCTAssertNil(r[@"@extra"]);
}

- (void)testDefaultAutoDelete_OffAndWeekReadBack {
	TGClient *c = M();
	__block NSInteger got = -99;
	[[TGClient shared] defaultMessageAutoDeleteTimeWithCompletion:^(NSInteger seconds){
		got = seconds;
	}];
	answerM(c, @{@"@type" : @"messageAutoDeleteTime", @"time" : @(604800)});
	XCTAssertEqual(got, 604800);

	[c.outbox removeAllObjects];
	[c setDefaultMessageAutoDeleteTime:0];
	NSDictionary *r = lastM(c, @"setDefaultMessageAutoDeleteTime");
	// Zero is the answer for "off": the timer lives until set again.
	XCTAssertEqual([r[@"auto_delete_seconds"] integerValue], 0);
}

// ─── the two supergroup switches ─────────────────────────────────────────────

- (void)testSupergroupFlags_FullInfoCarriesBothSwitches {
	TGClient *c = M();
	__block BOOL sign = NO, join = NO, ok = NO;
	[c supergroupFlagsForChat:77 completion:^(BOOL s, BOOL j, BOOL o){
		sign = s; join = j; ok = o;
	}];
	NSDictionary *chat = lastM(c, @"getChat");
	XCTAssertEqual([chat[@"chat_id"] longLongValue], 77LL);
	answerM(c, @{@"@type" : @"chat",
				 @"type" : @{@"@type" : @"chatTypeSupergroup", @"supergroup_id" : @"9001"}});
	NSDictionary *full = lastM(c, @"getSupergroupFullInfo");
	XCTAssertEqualObjects(full[@"supergroup_id"], @(9001));
	answerM(c, @{@"@type" : @"supergroupFullInfo",
				 @"sign_messages" : @YES, @"join_to_send" : @NO});
	XCTAssertTrue(ok);
	XCTAssertTrue(sign);
	XCTAssertFalse(join);
}

- (void)testSupergroupFlags_ABasicGroupIsNotASupergroup {
	TGClient *c = M();
	[c.chatsById removeObjectForKey:@(77)];
	__block BOOL ok = YES;
	[c supergroupFlagsForChat:77 completion:^(BOOL s, BOOL j, BOOL o){ ok = o; }];
	answerM(c, @{@"@type" : @"chat",
				 @"type" : @{@"@type" : @"chatTypeBasicGroup", @"basic_group_id" : @"17"}});
	XCTAssertFalse(ok);
	// No toggle was named for a chat that has no such switch.
	XCTAssertNil(lastM(c, @"getSupergroupFullInfo"));
}

- (void)testSignMessages_TheToggleNamesTheSupergroupNotTheChat {
	TGClient *c = M();
	[c setChatSignMessages:77 on:YES completion:nil];

	// The chat id alone is not the toggle's key: getChat resolves the
	// supergroup first, and the toggle names the supergroup.
	NSDictionary *chat = lastM(c, @"getChat");
	XCTAssertNotNil(chat);
	answerM(c, @{@"@type" : @"chat",
				 @"type" : @{@"@type" : @"chatTypeSupergroup", @"supergroup_id" : @"9001"}});
	NSDictionary *r = lastM(c, @"toggleSupergroupSignMessages");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(9001));
	XCTAssertTrue([r[@"sign_messages"] boolValue]);
}

- (void)testJoinToSend_CachedRowKeyServesWhenTheTypeIsGone {
	TGClient *c = M();
	[c setChatJoinToSendMessages:77 on:YES completion:nil];
	// The chat is a basic group on TDLib's side, but the list's row knows it
	// became a supergroup moments ago: the cached key is the toggle's key.
	answerM(c, @{@"@type" : @"chat",
				 @"type" : @{@"@type" : @"chatTypeBasicGroup", @"basic_group_id" : @"17"}});
	NSDictionary *r = lastM(c, @"toggleSupergroupJoinToSendMessages");
	XCTAssertEqualObjects(r[@"supergroup_id"], @(9001));
	XCTAssertTrue([r[@"join_to_send"] boolValue]);
}

- (void)testSignMessages_RefusalsSaidNotPassedThrough {
	TGClient *c = M();
	__block BOOL ok = YES;
	[c setChatSignMessages:77 on:YES completion:^(BOOL done){ ok = done; }];
	answerM(c, @{@"@type" : @"chat",
				 @"type" : @{@"@type" : @"chatTypeSupergroup", @"supergroup_id" : @"9001"}});
	answerM(c, @{@"@type" : @"error", @"code" : @(400),
				 @"message" : @"PREMIUM_ACCOUNTS_REQUIRED"});
	XCTAssertFalse(ok);
}

// ─── batches two to six: links, moderation, saved topics, welcome ───────────

- (void)testCalendarJump_AnswersTheMessageAndTheTotal {
	TGClient *c = M();
	__block int64_t landId = 0;
	__block NSInteger total = 0;
	[c calendarJumpForChat:31 endDate:1700000000
			completion:^(int64_t id2, NSInteger count){
		landId = id2; total = count;
	}];
	NSDictionary *r = lastM(c, @"getChatMessageCalendar");
	XCTAssertEqual([r[@"chat_id"] longLongValue], 31LL);
	// A plain chat asks the main topic: one topic at a time.
	XCTAssertEqualObjects(r[@"topic_id"][@"@type"], @"messageTopicMain");
	// int53 arrives as a string; both spellings stand for the same answer.
	NSDictionary *answer = @{@"@type" : @"messageCalendar",
							 @"last_message_id" : @"5551",
							 @"total_count" : @(120),
							 @"messages" : @[@{@"@type" : @"message",
											   @"id" : @(5551)}]};
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox)
		if (decodeM(data)[@"@extra"])
			sent = decodeM(data);
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
	XCTAssertEqual(landId, 5551LL);
	XCTAssertEqual(total, 120);
}

- (void)testMessageCount_TopicOrWholeChat {
	TGClient *c = M();
	__block NSInteger count = -1;
	[c messageCountInChat:32 thread:77 completion:^(NSInteger got){ count = got; }];
	NSDictionary *r = lastM(c, @"getChatMessageCount");
	// The thread selects the topic it counts; zero means the whole chat.
	XCTAssertTrue([r[@"topic_id"][@"messageThread_id"] longLongValue] == 77LL);
	answerM(c, @{@"@type" : @"count", @"count" : @(42)});
	XCTAssertEqual(count, 42);
}

- (void)testViewersAndReadDate_NamesWhoAndWhyNot {
	TGClient *c = M();
	__block NSArray *viewers = nil;
	[c viewersOfMessage:100 inChat:33 completion:^(NSArray *list){ viewers = list; }];
	answerM(c, @{@"@type" : @"messageViewers",
				 @"viewers" : @[@{@"@type" : @"messageViewer",
								  @"user_id" : @55,
								  @"view_date" : @(1700000000)}]});
	XCTAssertEqual(viewers.count, (NSUInteger)1);

	[c.outbox removeAllObjects];
	__block NSTimeInterval date = -1;
	__block NSString *reason = nil;
	[c readDateOfMessage:100 inChat:33 completion:^(NSTimeInterval got, NSString *why){
		date = got; reason = why;
	}];
	answerM(c, @{@"@type" : @"messageReadDateUserPrivacyRestricted"});
	XCTAssertEqual(date, 0);
	XCTAssertEqualObjects(reason, @"They hide their read receipts");
}

- (void)testAddedReactions_AndAnAdminUndo {
	TGClient *c = M();
	__block NSArray *rows = nil;
	[c addedReactionsOfMessage:100 inChat:33 emoji:@"🔥" offset:nil
					   completion:^(NSArray *got, NSString *next){
		rows = got;
	}];
	NSDictionary *r = lastM(c, @"getMessageAddedReactions");
	XCTAssertEqualObjects(r[@"reaction_type"][@"emoji"], @"🔥");
	answerM(c, @{@"@type" : @"addedReactions",
				 @"total_count" : @(2),
				 @"reactions" : @[@{@"@type" : @"addedReaction",
								   @"type" : @{@"@type" : @"reactionTypeEmoji",
											  @"emoji" : @"🔥"},
								   @"sender_id" : @{@"@type" : @"messageSenderUser",
													@"user_id" : @(9)},
								   @"is_outgoing" : @NO, @"date" : @(1)}],
				 @"next_offset" : @""});
	XCTAssertEqual(rows.count, (NSUInteger)1);
	XCTAssertEqualObjects(rows[0][@"sender"][@"user_id"], @(9));

	[c.outbox removeAllObjects];
	[c deleteReactionsOfSender:@{@"@type" : @"messageSenderUser", @"user_id" : @(9)}
					 ofMessage:100 inChat:33];
	XCTAssertEqualObjects(lastM(c, @"deleteMessageReactionsFromSender")[@"sender_id"][@"user_id"], @(9));
	[c.outbox removeAllObjects];
	[c deleteAllReactionsOfSender:@{@"@type" : @"messageSenderUser", @"user_id" : @(9)} inChat:33];
	XCTAssertNotNil(lastM(c, @"deleteAllRecentMessageReactionsFromSender"));
}

- (void)testClearByDateAndBySender_CarryTheirRanges {
	TGClient *c = M();
	[c deleteChatMessagesByDate:33 minDate:0 maxDate:1000 revoke:YES];
	NSDictionary *r = lastM(c, @"deleteChatMessagesByDate");
	XCTAssertTrue([r[@"revoke"] boolValue]);

	[c.outbox removeAllObjects];
	[c deleteChatMessagesBySender:@{@"@type" : @"messageSenderUser", @"user_id" : @(9)}
							 inChat:33 revoke:YES];
	NSDictionary *bySender = lastM(c, @"deleteChatMessagesBySender");
	XCTAssertEqualObjects(bySender[@"sender_id"][@"user_id"], @(9));
}

- (void)testWelcomeMessages_TheRoundTripOfOne {
	TGClient *c = M();
	__block NSArray *welcomes = nil;
	[c welcomeMessagesOfChat:40 completion:^(NSArray *got){ welcomes = got; }];
	// The load answers nothing; the rows arrive on the update, the chat row
	// takes them through applyChatUpdate, and the wrapper hears the
	// full-info announcement that rides it.
	NSMutableDictionary *u = [@{} mutableCopy];
	u[@"@type"] = @"updateChatWelcomeMessages";
	u[@"chat_id"] = @(40);
	NSMutableDictionary *w = [@{} mutableCopy];
	w[@"id"] = @(3);
	NSMutableDictionary *content = [@{} mutableCopy];
	content[@"messageText"] = @{@"text" : @{@"text" : @"Welcome aboard"}};
	w[@"content"] = content;
	u[@"messages"] = @[w];
	[c handleUpdate:u];
	XCTAssertEqual(welcomes.count, (NSUInteger)1);
	XCTAssertEqualObjects(welcomes[0][@"text"], @"Welcome aboard");

	[c.outbox removeAllObjects];
	[c addWelcomeMessageToChat:40 text:@"Hello!" completion:nil];
	XCTAssertEqualObjects(lastM(c, @"addChatWelcomeMessage")[@"input_message_content"][@"@type"], @"inputMessageText");

	[c.outbox removeAllObjects];
	[c setWelcomeMessage:3 inChat:40 text:@"New text" completion:nil];
	XCTAssertEqual([lastM(c, @"editChatWelcomeMessage")[@"welcome_message_id"] integerValue], 3);

	[c.outbox removeAllObjects];
	[c deleteWelcomeMessage:3 inChat:40];
	XCTAssertNotNil(lastM(c, @"deleteChatWelcomeMessage"));
	[c.outbox removeAllObjects];
	[c clearAllWelcomeMessagesInChat:40];
	XCTAssertNotNil(lastM(c, @"deleteAllChatWelcomeMessages"));
}

- (void)testSentFilesAndCallHistory_TheDataPagePair {
	TGClient *c = M();
	__block NSArray *docs = nil;
	[c sentDocuments:nil completion:^(NSArray *got){ docs = got; }];
	NSMutableDictionary *doc = [@{} mutableCopy];
	doc[@"@type"] = @"message";
	doc[@"id"] = @(7);
	doc[@"chat_id"] = @"77";
	doc[@"content"] = @{@"@type" : @"messageDocument"};
	NSMutableDictionary *answer = [@{} mutableCopy];
	answer[@"@type"] = @"foundMessages";
	answer[@"total_count"] = @(1);
	answer[@"messages"] = @[doc];
	answerM(c, answer);
	XCTAssertEqual(docs.count, (NSUInteger)1);
	[c.outbox removeAllObjects];
	[c clearAllCallMessages];
	XCTAssertNotNil(lastM(c, @"deleteAllCallMessages"));
}

- (void)testSendAs_ListAndSet {
	TGClient *c = M();
	__block NSArray *senders = nil;
	[c availableMessageSendersInChat:41 completion:^(NSArray *got){ senders = got; }];
	NSMutableDictionary *sender = [@{} mutableCopy];
	sender[@"@type"] = @"messageSenderUser";
	sender[@"user_id"] = @(1001);
	NSMutableDictionary *answer = [@{} mutableCopy];
	answer[@"@type"] = @"chatMessageSenders";
	answer[@"message_senders"] = @[sender];
	answerM(c, answer);
	XCTAssertEqual(senders.count, (NSUInteger)1);
	[c.outbox removeAllObjects];
	[c setMessageSender:senders[0] inChat:41 completion:nil];
	NSDictionary *r = lastM(c, @"setChatMessageSender");
	XCTAssertTrue([r[@"message_sender_id"][@"user_id"] longLongValue] == 1001LL);
}

- (void)testSavedTopics_StreamAndPin {
	TGClient *c = M();
	[c loadSavedMessagesTopics];
	XCTAssertNotNil(lastM(c, @"loadSavedMessagesTopics"));
	// The topic row arrives on the update, one dispatch without an @extra.
	NSMutableDictionary *t = [@{} mutableCopy];
	t[@"@type"] = @"savedMessagesTopic";
	t[@"id"] = @"300";
	t[@"type"] = @{@"@type" : @"savedMessagesTopicTypeMyNotes"};
	t[@"is_pinned"] = @YES;
	t[@"order"] = @"9";
	t[@"date"] = @(1700000000);
	[c handleUpdate:@{@"@type" : @"updateSavedMessagesTopic", @"topic" : t}];
	NSArray *topics = [c savedTopics];
	XCTAssertEqual(topics.count, (NSUInteger)1);
	XCTAssertEqualObjects(topics[0][@"title"], @"My Notes");
	XCTAssertTrue([topics[0][@"pinned"] boolValue]);
	[c.outbox removeAllObjects];
	[c toggleSavedTopicPinned:300 pinned:NO];
	XCTAssertFalse([lastM(c, @"toggleSavedMessagesTopicIsPinned")[@"is_pinned"] boolValue]);
	[c.outbox removeAllObjects];
	[c setPinnedSavedTopics:@[@(300), @(301)]];
	NSDictionary *pinned = lastM(c, @"setPinnedSavedMessagesTopics");
	XCTAssertEqualObjects(pinned[@"saved_messages_topic_ids"], (@[@(300), @(301)]));
}

- (void)testSavedTags_AndTaggedSearch {
	TGClient *c = M();
	__block NSArray *tags = nil;
	[c savedTopicsTags:300 completion:^(NSArray *got){ tags = got; }];
	NSMutableDictionary *tagType = [@{} mutableCopy];
	tagType[@"@type"] = @"reactionTypeEmoji";
	tagType[@"emoji"] = @"🔥";
	NSMutableDictionary *tag = [@{} mutableCopy];
	tag[@"tag"] = tagType;
	tag[@"label"] = @"work";
	tag[@"count"] = @(4);
	NSMutableDictionary *answer = [@{} mutableCopy];
	answer[@"@type"] = @"savedMessagesTags";
	answer[@"tags"] = @[tag];
	answerM(c, answer);
	XCTAssertEqual(tags.count, (NSUInteger)1);
	[c.outbox removeAllObjects];
	[c labelSavedTag:tagType label:@"work"];
	XCTAssertEqualObjects(lastM(c, @"setSavedMessagesTagLabel")[@"label"], @"work");
	[c.outbox removeAllObjects];
	__block NSArray *found = nil;
	[c searchSavedMessagesInTopic:300 query:@"" tag:nil from:0
						   completion:^(NSArray *list, int64_t next){ found = list; }];
	XCTAssertTrue([lastM(c, @"searchSavedMessages")[@"tag"] isKindOfClass:[NSNull class]]);
	NSMutableDictionary *foundAnswer = [@{} mutableCopy];
	foundAnswer[@"@type"] = @"foundChatMessages";
	foundAnswer[@"total_count"] = @(0);
	foundAnswer[@"messages"] = @[@{@"@type" : @"message", @"id" : @(1)}];
	foundAnswer[@"next_from_message_id"] = @"5";
	answerM(c, foundAnswer);
	XCTAssertEqual(found.count, (NSUInteger)1);
}

- (void)testTagSearch_AndRecentLocations_SendWhatTheServerAsks {
	TGClient *c = M();
	__block NSArray *wall = nil;
	[c publicMessagesByTag:@"#nochats" offset:nil
				completion:^(NSArray *list, NSString *next){ wall = list; }];
	NSDictionary *r = lastM(c, @"searchPublicMessagesByTag");
	XCTAssertEqualObjects(r[@"tag"], @"#nochats");
	[c handleUpdate:plain(@{@"@type" : @"foundMessages", @"total_count" : @(0),
							@"messages" : @[]})];
	XCTAssertEqual(wall.count, (NSUInteger)0);

	[c.outbox removeAllObjects];
	__block NSArray *locations = nil;
	[c recentLocationsInChat:41 completion:^(NSArray *got){ locations = got; }];
	NSDictionary *loc = lastM(c, @"searchChatRecentLocationMessages");
	XCTAssertEqual([loc[@"limit"] integerValue], 20);
	[c handleUpdate:plain(@{@"@type" : @"messages", @"total_count" : @(0),
							@"messages" : @[]})];
	XCTAssertEqual(locations.count, (NSUInteger)0);
}

- (void)testTranslateAndEmbed_SaidWhatItSays {
	TGClient *c = M();
	__block NSString *said = nil;
	[c translateMessage:100 inChat:41 toCode:@"ru" completion:^(NSString *text){ said = text; }];
	XCTAssertEqualObjects(lastM(c, @"translateMessageText")[@"to_language_code"], @"ru");
	NSMutableDictionary *answer = [@{} mutableCopy];
	answer[@"@type"] = @"formattedText";
	answer[@"text"] = @"Привет";
	answer[@"entities"] = @[];
	answerM(c, answer);
	XCTAssertEqualObjects(said, @"Привет");
	[c.outbox removeAllObjects];
	__block NSString *code = nil;
	[c embeddingCodeOfMessage:100 inChat:41 album:NO completion:^(NSString *got){ code = got; }];
	XCTAssertFalse([lastM(c, @"getMessageEmbeddingCode")[@"for_album"] boolValue]);
	answer = [@{} mutableCopy];
	answer[@"@type"] = @"text";
	answer[@"text"] = @"<iframe/>";
	answerM(c, answer);
	XCTAssertEqualObjects(code, @"<iframe/>");
}

- (void)testForwards_TheChannelQuestion {
	TGClient *c = M();
	__block NSArray *wall = nil;
	[c publicForwardsOfMessage:100 inChat:41 completion:^(NSArray *list){ wall = list; }];
	[c handleUpdate:plain(@{@"@type" : @"foundMessages", @"total_count" : @(0),
							@"messages" : @[]})];
	XCTAssertEqual(wall.count, (NSUInteger)0);
}

- (void)testBase64Decode_RoundTripsBothPaths {
	// The host runtime answers the iOS 7 spelling; on the 6.1.6 device the
	// same call used to throw (NSConcreteData has no such selector, B14).
	NSString *b64 = @"0gkAFgAASQEAAQAALQAALQAALQwAAAwAABQAABoAAAAA";
	XCTAssertTrue([TGBase64Decode(b64) isKindOfClass:[NSData class]]);
	XCTAssertEqual([TGBase64Decode(b64) length], (NSUInteger)33);

	// Empty and nil are empty answers, not throws - a voice note without a
	// waveform and a call without keys both land here.
	XCTAssertEqualObjects(TGBase64Decode(@""), [NSData data]);
	XCTAssertEqualObjects(TGBase64Decode(nil), [NSData data]);

	// The encoder the call engine sends its payload with round-trips.
	NSData *payload = TGBase64Decode(b64);
	NSString *back = TGBase64Encode(payload);
	XCTAssertTrue([TGBase64Decode(back) isEqual:payload]);
}
@end
