// TGClientThreadsTests.m — channel comments, bot buttons and the everyday chat actions
// that had no request behind them: removing a contact, deleting a group for
// everyone, unpinning everything, ordering pinned chats, jumping to a date.
//
// Each is one request whose shape is easy to get quietly wrong (a topic id
// where a chat id goes, a pinned list that drops chats), so the tests read
// the outbox and answer through handleUpdate the way the receive loop does.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientThreadsTests : XCTestCase @end

static TGClient *H(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	return c;
}

static NSDictionary *decodeH(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastH(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeH(d)[@"@type"] isEqualToString:type])
			found = decodeH(d);
	return found;
}

static void answerH(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeH(d)[@"@extra"])
			sent = decodeH(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *post(BOOL channelPost, NSDictionary *replyInfo) {
	NSMutableDictionary *m = [@{@"id" : @(77), @"date" : @(1), @"chat_id" : @(-100),
			@"is_channel_post" : @(channelPost),
			@"content" : @{@"@type" : @"messageText", @"text" : @{@"text" : @"news"}}} mutableCopy];
	if (replyInfo)
		m[@"interaction_info"] = @{@"view_count" : @(10), @"reply_info" : replyInfo};
	return m;
}

@implementation TGClientThreadsTests

#pragma mark - channel comments

/// A post opened nothing: the reply count was never read off the message.
- (void)testComments_ChannelPostWithDiscussionCanComment {
	NSDictionary *flat = TGFlattenMessage(post(YES, @{@"reply_count" : @(12)}));
	XCTAssertTrue([flat[@"canComment"] boolValue]);
	XCTAssertEqual([flat[@"replyCount"] integerValue], 12);
}

/// Messages inside the discussion group carry reply_info as well; they are
/// the comments, and must not grow a "Comments" bar of their own.
- (void)testComments_DiscussionMessagesAreNotPosts {
	XCTAssertFalse([TGFlattenMessage(post(NO, @{@"reply_count" : @(3)}))[@"canComment"] boolValue]);
	XCTAssertFalse([TGFlattenMessage(post(YES, nil))[@"canComment"] boolValue],
				   @"a channel with no discussion group has nothing to open");
}

- (void)testComments_ThreadOpensInTheDiscussionGroup {
	TGClient *c = H();
	__block int64_t chat = 0, thread = 0;
	__block NSString *error = @"unset";
	[c commentThreadForChat:-100 messageId:77 completion:^(int64_t d, int64_t t, NSString *e){
		chat = d; thread = t; error = e;
	}];
	NSDictionary *sent = lastH(c, @"getMessageThread");
	XCTAssertEqual([sent[@"chat_id"] longLongValue], -100LL);
	XCTAssertEqual([sent[@"message_id"] longLongValue], 77LL);
	answerH(c, @{@"@type" : @"messageThreadInfo", @"chat_id" : @(-200),
				 @"message_thread_id" : @(5001), @"messages" : @[]});
	XCTAssertEqual(chat, -200LL);
	XCTAssertEqual(thread, 5001LL);
	XCTAssertNil(error);
}

- (void)testComments_RefusalIsReported {
	TGClient *c = H();
	__block NSString *error = nil;
	[c commentThreadForChat:-100 messageId:77 completion:^(int64_t d, int64_t t, NSString *e){ error = e; }];
	answerH(c, @{@"@type" : @"error", @"code" : @400, @"message" : @"MSG_ID_INVALID"});
	XCTAssertEqualObjects(error, @"MSG_ID_INVALID");
}

#pragma mark - everyday actions

- (void)testRemoveContact {
	TGClient *c = H();
	__block BOOL ok = NO;
	[c removeContactWithUserId:42 completion:^(BOOL done){ ok = done; }];
	XCTAssertEqualObjects(lastH(c, @"removeContacts")[@"user_ids"], (@[@42]));
	answerH(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

/// Deleting for everyone is not leaving: it must be deleteChat, and the row
/// only goes once Telegram agreed.
- (void)testDeleteForEveryone_RowStaysUntilTelegramAgrees {
	TGClient *c = H();
	c.chatsById[@(-300)] = [@{@"id" : @(-300), @"title" : @"Team"} mutableCopy];
	__block NSString *error = @"unset";
	[c deleteChatForEveryone:-300 completion:^(NSString *e){ error = e; }];
	XCTAssertEqual([lastH(c, @"deleteChat")[@"chat_id"] longLongValue], -300LL);
	XCTAssertNotNil(c.chatsById[@(-300)]);
	answerH(c, @{@"@type" : @"error", @"code" : @400, @"message" : @"CHAT_ADMIN_REQUIRED"});
	XCTAssertEqualObjects(error, @"CHAT_ADMIN_REQUIRED");
	XCTAssertNotNil(c.chatsById[@(-300)], @"a refused delete keeps the chat");
}

- (void)testUnpinAll_ChatOrTopic {
	TGClient *c = H();
	[c unpinAllMessagesInChat:-100 thread:0];
	XCTAssertEqual([lastH(c, @"unpinAllChatMessages")[@"chat_id"] longLongValue], -100LL);
	[c unpinAllMessagesInChat:-100 thread:9];
	NSDictionary *topic = lastH(c, @"unpinAllForumTopicMessages");
	XCTAssertEqual([topic[@"forum_topic_id"] longLongValue], 9LL);
}

- (void)testPinnedOrder_WholeListInOrder {
	TGClient *c = H();
	[c setPinnedChatIds:@[@3, @1, @2]];
	NSDictionary *sent = lastH(c, @"setPinnedChats");
	XCTAssertEqualObjects(sent[@"chat_ids"], (@[@3, @1, @2]));
	XCTAssertEqualObjects(sent[@"chat_list"][@"@type"], @"chatListMain");
}

- (void)testJumpToDate_FindsTheMessageOrNil {
	TGClient *c = H();
	__block NSDictionary *found = @{};
	[c messageAtDate:1700000000 inChat:-100 completion:^(NSDictionary *m){ found = m; }];
	XCTAssertEqual([lastH(c, @"getChatMessageByDate")[@"date"] longLongValue], 1700000000LL);
	answerH(c, @{@"@type" : @"message", @"id" : @(55), @"date" : @(1699999000),
				 @"content" : @{@"@type" : @"messageText", @"text" : @{@"text" : @"then"}}});
	XCTAssertEqual([found[@"id"] longLongValue], 55LL);

	[c messageAtDate:1 inChat:-100 completion:^(NSDictionary *m){ found = m; }];
	answerH(c, @{@"@type" : @"error", @"code" : @404, @"message" : @"Not Found"});
	XCTAssertNil(found);
}

#pragma mark - bot buttons

static NSDictionary *inlineMarkup(void) {
	return @{@"@type" : @"replyMarkupInlineKeyboard", @"rows" : @[
		@[@{@"text" : @"Yes", @"type" : @{@"@type" : @"inlineKeyboardButtonTypeCallback", @"data" : @"eWVz"}},
		  @{@"text" : @"Site", @"type" : @{@"@type" : @"inlineKeyboardButtonTypeUrl", @"url" : @"https://example.org"}}],
		@[@{@"text" : @"Log in", @"type" : @{@"@type" : @"inlineKeyboardButtonTypeLoginUrl",
											 @"url" : @"https://example.org/login", @"id" : @(9), @"forward_text" : @""}},
		  @{@"text" : @"App", @"type" : @{@"@type" : @"inlineKeyboardButtonTypeWebApp", @"url" : @"https://x"}}]]};
}

/// Buttons under a bot's message were dropped whole: nothing read
/// reply_markup, so a bot that asked a question offered no way to answer.
- (void)testBots_InlineKeyboardIsFlattenedRowByRow {
	NSMutableDictionary *m = [post(NO, nil) mutableCopy];
	m[@"reply_markup"] = inlineMarkup();
	NSArray *rows = TGFlattenMessage(m)[@"inlineRows"];
	XCTAssertEqual(rows.count, 2u);
	XCTAssertEqualObjects(rows[0][0][@"kind"], @"callback");
	XCTAssertEqualObjects(rows[0][0][@"data"], @"eWVz", @"bytes stay base64 for the callback");
	XCTAssertEqualObjects(rows[0][1][@"url"], @"https://example.org");
	XCTAssertEqualObjects(rows[1][0][@"buttonId"], @9);
	XCTAssertEqualObjects(rows[1][1][@"kind"], @"unsupported", @"a web app cannot run here");
}

- (void)testBots_ReplyKeyboardAndItsRemoval {
	NSDictionary *show = TGFlattenReplyMarkup(@{@"@type" : @"replyMarkupShowKeyboard",
			@"rows" : @[@[@{@"text" : @"Menu", @"type" : @{@"@type" : @"keyboardButtonTypeText"}},
						  @{@"text" : @"Help", @"type" : @{@"@type" : @"keyboardButtonTypeText"}}],
						@[@{@"text" : @"Share phone", @"type" : @{@"@type" : @"keyboardButtonTypeRequestPhoneNumber"}}]],
			@"one_time" : @YES, @"input_field_placeholder" : @"Pick one"});
	XCTAssertEqualObjects(show[@"replyKeyboard"][@"rows"], (@[@[@"Menu", @"Help"], @[@"Share phone"]]));
	XCTAssertTrue([show[@"replyKeyboard"][@"oneTime"] boolValue]);
	XCTAssertTrue([TGFlattenReplyMarkup(@{@"@type" : @"replyMarkupRemoveKeyboard"})[@"removeKeyboard"] boolValue]);
}

- (void)testBots_CallbackSendsTheButtonDataAndShowsTheAnswer {
	TGClient *c = H();
	__block NSString *text = nil;
	__block BOOL alert = NO;
	NSDictionary *button = @{@"kind" : @"callback", @"data" : @"eWVz", @"text" : @"Yes"};
	[c pressCallbackButton:button inChat:-5 messageId:12 completion:^(NSString *t, BOOL a, NSString *u, NSString *e){
		text = t; alert = a;
	}];
	NSDictionary *sent = lastH(c, @"getCallbackQueryAnswer");
	XCTAssertEqual([sent[@"message_id"] longLongValue], 12LL);
	XCTAssertEqualObjects(sent[@"payload"][@"@type"], @"callbackQueryPayloadData");
	XCTAssertEqualObjects(sent[@"payload"][@"data"], @"eWVz");
	answerH(c, @{@"@type" : @"callbackQueryAnswer", @"text" : @"Saved", @"show_alert" : @YES, @"url" : @""});
	XCTAssertEqualObjects(text, @"Saved");
	XCTAssertTrue(alert);
}

- (void)testBots_LoginAsksBeforeSigningIn {
	TGClient *c = H();
	__block NSString *domain = nil, *url = @"unset";
	NSDictionary *button = @{@"kind" : @"login", @"buttonId" : @9, @"url" : @"https://example.org/login"};
	[c loginURLForButton:button inChat:-5 messageId:12 completion:^(NSString *u, NSString *d, NSString *e){
		url = u; domain = d;
	}];
	XCTAssertEqual([lastH(c, @"getLoginUrlInfo")[@"button_id"] longLongValue], 9LL);
	answerH(c, @{@"@type" : @"loginUrlInfoRequestConfirmation", @"url" : @"https://example.org/login",
				 @"domain" : @"example.org", @"bot_user_id" : @(1), @"request_write_access" : @NO});
	XCTAssertEqualObjects(domain, @"example.org");
	XCTAssertNil(url, @"no link before the user agreed");
}

/// updateChatReplyMarkup was dropped, so a bot's keyboard never appeared and
/// a removed one never went.
- (void)testBots_ChatKeyboardFollowsTheUpdate {
	TGClient *c = H();
	c.chatsById[@(-5)] = [@{@"id" : @(-5), @"title" : @"Bot"} mutableCopy];
	__block BOOL told = NO;
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:TGChatReplyMarkupChangedNotification
			object:nil queue:nil usingBlock:^(NSNotification *n){ told = YES; }];
	[c handleUpdate:@{@"@type" : @"updateChatReplyMarkup", @"chat_id" : @(-5),
					  @"reply_markup_message" : @{@"id" : @(40), @"reply_markup" :
							@{@"@type" : @"replyMarkupShowKeyboard",
							  @"rows" : @[@[@{@"text" : @"Menu", @"type" : @{@"@type" : @"keyboardButtonTypeText"}}]]}}}];
	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertTrue(told);
	__block NSDictionary *keyboard = nil;
	[c replyKeyboardForChat:-5 completion:^(NSDictionary *k){ keyboard = k; }];
	XCTAssertEqualObjects(keyboard[@"rows"], (@[@[@"Menu"]]));

	[c handleUpdate:@{@"@type" : @"updateChatReplyMarkup", @"chat_id" : @(-5)}];
	keyboard = @{};
	[c replyKeyboardForChat:-5 completion:^(NSDictionary *k){ keyboard = k; }];
	XCTAssertNil(keyboard, @"no message means the keyboard is gone");
}

@end
