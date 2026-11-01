// TGClientTier2CommunitiesTests.m — the communities, checklist, quick-reply,
// suggested-post and AI/rich-message wire.
//
// Every one of the 35 functions this branch wires is driven once. The point
// is the request shape: these sit behind screens where a wrong field is
// invisible until Telegram refuses it. Nested reads (getMessage before a
// checklist editor) are answered in order, the way the receive loop would.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientTier2CommunitiesTests : XCTestCase @end

static TGClient *T2(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.communitiesById = [NSMutableDictionary dictionary];
	c.communityOrder = [NSMutableArray array];
	c.communityFullInfoById = [NSMutableDictionary dictionary];
	c.quickReplyShortcutsById = [NSMutableDictionary dictionary];
	c.quickReplyShortcutOrder = [NSMutableArray array];
	c.quickReplyMessagesByShortcut = [NSMutableDictionary dictionary];
	c.suggestedActionsValue = @[];
	c.checklistCache = [NSMutableDictionary dictionary];
	return c;
}

static NSDictionary *t2Decode(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *t2Last(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = t2Decode(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static void t2Answer(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = t2Decode(data);
		if (request[@"@extra"])
			sent = request;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *t2Plain(NSDictionary *dictionary) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *t2Message(NSDictionary *content) {
	return @{@"@type" : @"message", @"id" : @(55), @"chat_id" : @(77),
			 @"date" : @(1700000000), @"is_outgoing" : @NO,
			 @"content" : content};
}

@implementation TGClientTier2CommunitiesTests

#pragma mark - communities

- (void)testCreateCommunity_SendsTheNameChatAndVisibility {
	TGClient *c = T2();
	__block int64_t made = 0;
	[c createCommunity:@"Work" chatId:42 hidden:YES
			completion:^(int64_t communityId, NSString *error){ made = communityId; }];
	NSDictionary *request = t2Last(c, @"createCommunity");
	XCTAssertEqualObjects(request[@"name"], @"Work");
	XCTAssertEqualObjects(request[@"chat_id"], @(42));
	XCTAssertEqualObjects(request[@"is_chat_hidden"], @YES);
	t2Answer(c, @{@"@type" : @"communityId", @"id" : @(900)});
	XCTAssertEqual(made, (int64_t)900);
}

- (void)testCommunityFullInfo_SendsTheIdAndFlattensChatsAndCounts {
	TGClient *c = T2();
	__block NSDictionary *got = nil;
	[c communityFullInfo:12 completion:^(NSDictionary *info, NSString *error){ got = info; }];
	XCTAssertEqualObjects(t2Last(c, @"getCommunityFullInfo")[@"community_id"], @(12));
	t2Answer(c, t2Plain(@{@"@type" : @"communityFullInfo",
						  @"photo" : @{@"@type" : @"chatPhoto", @"sizes" : @[]},
						  @"chats" : @[@{@"chat_id" : @(77),
										@"can_view_history" : @YES,
										@"is_hidden" : @NO}],
						  @"administrator_count" : @(3),
						  @"banned_count" : @(1),
						  @"add_chat_request_count" : @(2)}));
	XCTAssertEqualObjects(got[@"administratorCount"], @(3));
	XCTAssertEqualObjects(got[@"bannedCount"], @(1));
	XCTAssertEqualObjects(got[@"addChatRequestCount"], @(2));
	XCTAssertEqualObjects(got[@"chats"][0][@"chatId"], @(77));
	XCTAssertEqualObjects(got[@"chats"][0][@"canViewHistory"], @YES);
	XCTAssertNotNil([c cachedCommunityFullInfo:12]);
}

- (void)testSetCommunityName_SendsTheIdAndTheName {
	TGClient *c = T2();
	__block BOOL done = NO;
	[c setCommunityName:12 name:@"Studio"
			 completion:^(BOOL ok, NSString *error){ done = ok; }];
	NSDictionary *request = t2Last(c, @"setCommunityName");
	XCTAssertEqualObjects(request[@"community_id"], @(12));
	XCTAssertEqualObjects(request[@"name"], @"Studio");
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

- (void)testSetCommunityPhoto_SendsAStaticPhotoAndHonoursRemoval {
	TGClient *c = T2();
	[c setCommunityPhoto:12 path:@"/tmp/photo.jpg" completion:nil];
	NSDictionary *request = t2Last(c, @"setCommunityPhoto");
	XCTAssertEqualObjects(request[@"community_id"], @(12));
	XCTAssertEqualObjects(request[@"photo"][@"@type"], @"inputChatPhotoStatic");
	XCTAssertEqualObjects(request[@"photo"][@"photo"][@"@type"], @"inputFileLocal");
	XCTAssertEqualObjects(request[@"photo"][@"photo"][@"path"], @"/tmp/photo.jpg");

	t2Answer(c, @{@"@type" : @"ok"});
	[c setCommunityPhoto:12 path:nil completion:nil];
	NSDictionary *clear = t2Last(c, @"setCommunityPhoto");
	XCTAssertTrue(clear[@"photo"] == [NSNull null]);
}

- (void)testSetCommunityPermissions_CarriesTheOnePermissionObject {
	TGClient *c = T2();
	[c setCommunityPermissions:12 canEditChatList:YES completion:nil];
	NSDictionary *request = t2Last(c, @"setCommunityPermissions");
	XCTAssertEqualObjects(request[@"community_id"], @(12));
	XCTAssertEqualObjects(request[@"permissions"][@"@type"], @"communityPermissions");
	XCTAssertEqualObjects(request[@"permissions"][@"can_edit_chat_list"], @YES);
}

- (void)testDeleteCommunity_SendsTheIdAndDropsTheCachedRow {
	TGClient *c = T2();
	[c applyCommunityUpdate:@{@"community" : @{@"id" : @(12), @"name" : @"Work"}}];
	XCTAssertEqual(c.communities.count, (NSUInteger)1);
	__block BOOL done = NO;
	[c deleteCommunity:12 completion:^(BOOL ok, NSString *error){ done = ok; }];
	XCTAssertEqualObjects(t2Last(c, @"deleteCommunity")[@"community_id"], @(12));
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
	XCTAssertEqual(c.communities.count, (NSUInteger)0);
}

- (void)testCommunityUpdate_KeepsTheOrderAndTheStatusWord {
	TGClient *c = T2();
	[c applyCommunityUpdate:@{@"community" : @{@"id" : @(1), @"name" : @"A",
			@"have_access" : @YES, @"status" : @{@"@type" : @"communityMemberStatusCreator"}}}];
	[c applyCommunityUpdate:@{@"community" : @{@"id" : @(2), @"name" : @"B",
			@"have_access" : @YES, @"status" : @{@"@type" : @"communityMemberStatusMember"}}}];
	XCTAssertEqualObjects(c.communities[0][@"name"], @"B");
	XCTAssertEqualObjects(c.communities[1][@"status"], @"Owner");
}

#pragma mark - quick replies

- (void)testLoadQuickReplyShortcuts_RequestsAndReadsTheUpdates {
	TGClient *c = T2();
	__block NSArray *got = nil;
	[c loadQuickReplyShortcutsWithCompletion:^(NSArray *shortcuts){ got = shortcuts; }];
	XCTAssertNotNil(t2Last(c, @"loadQuickReplyShortcuts"));
	[c handleUpdate:@{@"@type" : @"updateQuickReplyShortcut",
					  @"shortcut" : @{@"id" : @(4), @"name" : @"Hello",
									  @"message_count" : @(2),
									  @"first_message" : @{@"id" : @(8),
										  @"content" : @{@"@type" : @"messageText",
														 @"text" : @{@"@type" : @"formattedText",
																	 @"text" : @"Hi"}}}}}];
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertEqual(got.count, (NSUInteger)1);
	XCTAssertEqualObjects(got[0][@"name"], @"Hello");
	XCTAssertEqualObjects(got[0][@"messageCount"], @(2));
	XCTAssertEqualObjects(got[0][@"preview"], @"Hi");
}

- (void)testCheckQuickReplyShortcutName_ReportsTheServerAnswer {
	TGClient *c = T2();
	__block BOOL ok = YES;
	__block NSString *why = nil;
	[c checkQuickReplyShortcutName:@"Hello"
						completion:^(BOOL allowed, NSString *error){ ok = allowed; why = error; }];
	XCTAssertEqualObjects(t2Last(c, @"checkQuickReplyShortcutName")[@"name"], @"Hello");
	t2Answer(c, @{@"@type" : @"error", @"code" : @(400), @"message" : @"TAKEN"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(why, @"TAKEN");
}

- (void)testSetQuickReplyShortcutName_SendsTheIdAndNewName {
	TGClient *c = T2();
	[c setQuickReplyShortcutName:4 name:@"Goodbye" completion:nil];
	NSDictionary *request = t2Last(c, @"setQuickReplyShortcutName");
	XCTAssertEqualObjects(request[@"shortcut_id"], @(4));
	XCTAssertEqualObjects(request[@"name"], @"Goodbye");
}

- (void)testDeleteQuickReplyShortcut_RemovesTheCachedRow {
	TGClient *c = T2();
	[c applyQuickReplyShortcutUpdate:@{@"shortcut" : @{@"id" : @(4), @"name" : @"Hello",
			@"message_count" : @(1)}}];
	[c deleteQuickReplyShortcut:4 completion:nil];
	XCTAssertEqualObjects(t2Last(c, @"deleteQuickReplyShortcut")[@"shortcut_id"], @(4));
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertEqual(c.quickReplyShortcuts.count, (NSUInteger)0);
}

- (void)testReorderQuickReplyShortcuts_SendsTheWholeOrder {
	TGClient *c = T2();
	[c reorderQuickReplyShortcuts:@[@(3), @(1), @(2)] completion:nil];
	NSDictionary *request = t2Last(c, @"reorderQuickReplyShortcuts");
	XCTAssertEqualObjects(request[@"shortcut_ids"], (@[@(3), @(1), @(2)]));
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertEqualObjects(c.quickReplyShortcutOrder, (@[@(3), @(1), @(2)]));
}

- (void)testLoadQuickReplyMessages_ReadsTheUpdateAndFlattensText {
	TGClient *c = T2();
	__block NSArray *got = nil;
	[c loadQuickReplyMessagesForShortcut:4 completion:^(NSArray *messages){ got = messages; }];
	XCTAssertEqualObjects(t2Last(c, @"loadQuickReplyShortcutMessages")[@"shortcut_id"], @(4));
	[c handleUpdate:@{@"@type" : @"updateQuickReplyShortcutMessages",
					  @"shortcut_id" : @(4),
					  @"messages" : @[@{@"id" : @(9),
						  @"content" : @{@"@type" : @"messageText",
										 @"text" : @{@"@type" : @"formattedText",
													 @"text" : @"Saved line"}}}]}];
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertEqual(got.count, (NSUInteger)1);
	XCTAssertEqualObjects(got[0][@"text"], @"Saved line");
}

- (void)testAddQuickReplyShortcutMessage_SendsTheNameAndTheContent {
	TGClient *c = T2();
	__block NSDictionary *made = nil;
	[c addQuickReplyShortcutMessage:@"Hello" text:@"First"
						 completion:^(NSDictionary *message, NSString *error){ made = message; }];
	NSDictionary *request = t2Last(c, @"addQuickReplyShortcutMessage");
	XCTAssertEqualObjects(request[@"shortcut_name"], @"Hello");
	XCTAssertEqualObjects(request[@"input_message_content"][@"@type"], @"inputMessageText");
	XCTAssertEqualObjects(request[@"input_message_content"][@"text"][@"text"], @"First");
	t2Answer(c, @{@"@type" : @"quickReplyMessage", @"id" : @(10),
				  @"content" : @{@"@type" : @"messageText",
								 @"text" : @{@"@type" : @"formattedText", @"text" : @"First"}}});
	XCTAssertEqualObjects(made[@"id"], @(10));
}

- (void)testAddQuickReplyShortcutMessageAlbum_SendsEveryContent {
	TGClient *c = T2();
	__block NSArray *made = nil;
	[c addQuickReplyShortcutMessageAlbum:@"Hello" texts:@[@"One", @"Two"]
							  completion:^(NSArray *messages, NSString *error){ made = messages; }];
	NSDictionary *request = t2Last(c, @"addQuickReplyShortcutMessageAlbum");
	XCTAssertEqualObjects(request[@"shortcut_name"], @"Hello");
	XCTAssertEqual([request[@"input_message_contents"] count], (NSUInteger)2);
	XCTAssertEqualObjects(request[@"input_message_contents"][1][@"text"][@"text"], @"Two");
	t2Answer(c, @{@"@type" : @"quickReplyMessages", @"messages" : @[
			@{@"id" : @(1), @"content" : @{@"@type" : @"messageText",
				@"text" : @{@"@type" : @"formattedText", @"text" : @"One"}}},
			@{@"id" : @(2), @"content" : @{@"@type" : @"messageText",
				@"text" : @{@"@type" : @"formattedText", @"text" : @"Two"}}}]});
	XCTAssertEqual(made.count, (NSUInteger)2);
}

- (void)testEditQuickReplyMessage_SendsTheShortcutMessageAndContent {
	TGClient *c = T2();
	[c editQuickReplyMessage:10 shortcutId:4 text:@"Changed" completion:nil];
	NSDictionary *request = t2Last(c, @"editQuickReplyMessage");
	XCTAssertEqualObjects(request[@"shortcut_id"], @(4));
	XCTAssertEqualObjects(request[@"message_id"], @(10));
	XCTAssertEqualObjects(request[@"input_message_content"][@"text"][@"text"], @"Changed");
}

- (void)testDeleteQuickReplyShortcutMessages_SendsTheIdsAndDropsThem {
	TGClient *c = T2();
	c.quickReplyMessagesByShortcut[@(4)] = [@[@{@"id" : @(9)}] mutableCopy];
	[c deleteQuickReplyShortcutMessages:@[@(9)] shortcutId:4 completion:nil];
	NSDictionary *request = t2Last(c, @"deleteQuickReplyShortcutMessages");
	XCTAssertEqualObjects(request[@"shortcut_id"], @(4));
	XCTAssertEqualObjects(request[@"message_ids"], (@[@(9)]));
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertEqual([c.quickReplyMessagesByShortcut[@(4)] count], (NSUInteger)0);
}

- (void)testReaddQuickReplyShortcutMessages_SendsTheNameAndIds {
	TGClient *c = T2();
	__block NSArray *made = nil;
	[c readdQuickReplyShortcutMessages:@[@(9)] shortcutName:@"Hello"
							completion:^(NSArray *messages, NSString *error){ made = messages; }];
	NSDictionary *request = t2Last(c, @"readdQuickReplyShortcutMessages");
	XCTAssertEqualObjects(request[@"shortcut_name"], @"Hello");
	XCTAssertEqualObjects(request[@"message_ids"], (@[@(9)]));
	t2Answer(c, @{@"@type" : @"quickReplyMessages", @"messages" : @[
			@{@"id" : @(9), @"content" : @{@"@type" : @"messageText",
				@"text" : @{@"@type" : @"formattedText", @"text" : @"Back"}}}]});
	XCTAssertEqualObjects(made[0][@"text"], @"Back");
}

- (void)testSendQuickReplyShortcutMessages_SendsChatShortcutAndMarker {
	TGClient *c = T2();
	__block NSArray *sent = nil;
	[c sendQuickReplyShortcutMessages:4 toChat:77 sendingId:1234
						   completion:^(NSArray *messages, NSString *error){ sent = messages; }];
	NSDictionary *request = t2Last(c, @"sendQuickReplyShortcutMessages");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"shortcut_id"], @(4));
	XCTAssertEqualObjects(request[@"sending_id"], @(1234));
	t2Answer(c, @{@"@type" : @"messages", @"total_count" : @(1), @"messages" : @[
			@{@"id" : @(31), @"chat_id" : @(77), @"date" : @(1700000000),
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"@type" : @"formattedText", @"text" : @"Hi"}}}]});
	XCTAssertEqual(sent.count, (NSUInteger)1);
}

#pragma mark - checklists

- (void)testChecklistForMessage_ReadsTheListAndItsFlags {
	TGClient *c = T2();
	__block NSDictionary *got = nil;
	[c checklistForMessage:55 inChat:77 completion:^(NSDictionary *checklist, NSString *error){
		got = checklist;
	}];
	NSDictionary *request = t2Last(c, @"getMessage");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	t2Answer(c, t2Message(@{@"@type" : @"messageChecklist",
						   @"checklist" : @{@"title" : @{@"@type" : @"formattedText", @"text" : @"Trip"},
										   @"tasks" : @[
											   @{@"id" : @(1),
												 @"text" : @{@"@type" : @"formattedText", @"text" : @"Passport"},
												 @"completed_by" : @{@"@type" : @"messageSenderUser",
																	 @"user_id" : @(1001)}},
											   @{@"id" : @(2),
												 @"text" : @{@"@type" : @"formattedText", @"text" : @"Tickets"},
												 @"completed_by" : [NSNull null]}],
										   @"can_add_tasks" : @YES,
										   @"can_mark_tasks_as_done" : @YES,
										   @"others_can_add_tasks" : @NO,
										   @"others_can_mark_tasks_as_done" : @YES}}));
	XCTAssertEqualObjects(got[@"title"], @"Trip");
	XCTAssertEqual([got[@"tasks"] count], (NSUInteger)2);
	XCTAssertEqualObjects(got[@"tasks"][0][@"done"], @YES);
	XCTAssertEqualObjects(got[@"tasks"][1][@"done"], @NO);
	XCTAssertEqualObjects(got[@"canAddTasks"], @YES);
	XCTAssertEqualObjects(got[@"othersCanAddTasks"], @NO);
}

- (void)testEditMessageChecklist_SendsTitleTasksAndFlags {
	TGClient *c = T2();
	[c editMessageChecklist:55 inChat:77 title:@"Trip"
					 tasks:@[@{@"id" : @(1), @"text" : @"Passport"},
							 @{@"id" : @(0), @"text" : @"Tickets"}]
			  othersCanAdd:YES othersCanMark:NO completion:nil];
	NSDictionary *request = t2Last(c, @"editMessageChecklist");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertTrue(request[@"reply_markup"] == [NSNull null]);
	NSDictionary *checklist = request[@"checklist"];
	XCTAssertEqualObjects(checklist[@"@type"], @"inputChecklist");
	XCTAssertEqualObjects(checklist[@"title"][@"text"], @"Trip");
	XCTAssertEqualObjects(checklist[@"tasks"][1][@"id"], @(0));
	XCTAssertEqualObjects(checklist[@"others_can_add_tasks"], @YES);
	XCTAssertEqualObjects(checklist[@"others_can_mark_tasks_as_done"], @NO);
}

- (void)testAddChecklistTasks_SendsInputTasks {
	TGClient *c = T2();
	[c addChecklistTasks:@[@{@"id" : @(0), @"text" : @"Sunscreen"}]
			   toMessage:55 inChat:77 completion:nil];
	NSDictionary *request = t2Last(c, @"addChecklistTasks");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"tasks"][0][@"@type"], @"inputChecklistTask");
	XCTAssertEqualObjects(request[@"tasks"][0][@"text"][@"text"], @"Sunscreen");
}

- (void)testMarkChecklistTasksAsDone_SendsBothSides {
	TGClient *c = T2();
	[c markChecklistTasksAsDone:@[@(1)] notDoneTaskIds:@[@(2)]
					  onMessage:55 inChat:77 completion:nil];
	NSDictionary *request = t2Last(c, @"markChecklistTasksAsDone");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"marked_as_done_task_ids"], (@[@(1)]));
	XCTAssertEqualObjects(request[@"marked_as_not_done_task_ids"], (@[@(2)]));
}

- (void)testSendChecklist_SendsInputMessageChecklist {
	TGClient *c = T2();
	[c sendChecklist:@"Trip" tasks:@[@{@"text" : @"Passport"}] toChat:77 completion:nil];
	NSDictionary *request = t2Last(c, @"sendMessage");
	XCTAssertEqualObjects(request[@"input_message_content"][@"@type"], @"inputMessageChecklist");
	XCTAssertEqualObjects(request[@"input_message_content"][@"checklist"][@"tasks"][0][@"text"][@"text"],
						  @"Passport");
}

#pragma mark - suggested posts and actions

- (void)testSuggestedPostForMessage_ReadsPriceDateStateAndFlags {
	TGClient *c = T2();
	__block NSDictionary *got = nil;
	[c suggestedPostForMessage:55 inChat:77 completion:^(NSDictionary *post, NSString *error){
		got = post;
	}];
	XCTAssertEqualObjects(t2Last(c, @"getMessage")[@"message_id"], @(55));
	t2Answer(c, t2Plain(@{@"@type" : @"message", @"id" : @(55), @"chat_id" : @(77),
						 @"date" : @(1700000000),
						 @"content" : @{@"@type" : @"messageText",
										@"text" : @{@"@type" : @"formattedText", @"text" : @"Post"}},
						 @"suggested_post_info" : @{
							 @"price" : @{@"@type" : @"suggestedPostPriceStar",
										  @"star_count" : @(25)},
							 @"send_date" : @(1700001000),
							 @"state" : @{@"@type" : @"suggestedPostStatePending"},
							 @"can_be_approved" : @YES,
							 @"can_be_declined" : @YES}}));
	XCTAssertEqualObjects(got[@"price"], @"25 stars");
	XCTAssertEqualObjects(got[@"state"], @"Pending");
	XCTAssertEqualObjects(got[@"canBeApproved"], @YES);
	XCTAssertEqualObjects(got[@"sendDate"], @(1700001000));
}

- (void)testApproveSuggestedPost_SendsChatMessageAndDate {
	TGClient *c = T2();
	[c approveSuggestedPost:55 inChat:77 sendDate:1700001000 completion:nil];
	NSDictionary *request = t2Last(c, @"approveSuggestedPost");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"send_date"], @(1700001000));
}

- (void)testDeclineSuggestedPost_SendsTheComment {
	TGClient *c = T2();
	[c declineSuggestedPost:55 inChat:77 comment:@"Not this week" completion:nil];
	NSDictionary *request = t2Last(c, @"declineSuggestedPost");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"comment"], @"Not this week");
}

- (void)testHideSuggestedAction_MergesTheUpdateAndSendsTheObject {
	TGClient *c = T2();
	[c handleUpdate:@{@"@type" : @"updateSuggestedActions",
					  @"added_actions" : @[
						  @{@"@type" : @"suggestedActionSetPassword",
							@"authorization_delay" : @(0)},
						  @{@"@type" : @"suggestedActionCustom",
							@"name" : @"Nickname",
							@"title" : @{@"@type" : @"formattedText", @"text" : @"Pick a nickname"},
							@"description" : @{@"@type" : @"formattedText", @"text" : @""},
							@"url" : @"https://t.me/x"}],
					  @"removed_actions" : @[]}];
	XCTAssertEqual(c.suggestedActions.count, (NSUInteger)2);
	NSDictionary *row = c.suggestedActions[1];
	XCTAssertEqualObjects(row[@"title"], @"Nickname");
	[c hideSuggestedAction:row completion:nil];
	NSDictionary *request = t2Last(c, @"hideSuggestedAction");
	XCTAssertEqualObjects(request[@"action"][@"@type"], @"suggestedActionCustom");
	XCTAssertEqualObjects(request[@"action"][@"name"], @"Nickname");
	t2Answer(c, @{@"@type" : @"ok"});
	XCTAssertEqual(c.suggestedActions.count, (NSUInteger)1);
}

#pragma mark - AI text and rich messages

- (void)testComposeTextWithAi_SendsStyleLanguageAndEmoji {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c composeTextWithAi:@"hello there" translateTo:@"uk" style:@"formal" addEmojis:YES
			  completion:^(NSString *text, NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"composeTextWithAi");
	XCTAssertEqualObjects(request[@"text"][@"text"], @"hello there");
	XCTAssertEqualObjects(request[@"translate_to_language_code"], @"uk");
	XCTAssertEqualObjects(request[@"style_name"], @"formal");
	XCTAssertEqualObjects(request[@"add_emojis"], @YES);
	t2Answer(c, @{@"@type" : @"formattedText",
				  @"text" : @"Hello there.",
				  @"entities" : @[]});
	XCTAssertEqualObjects(got, @"Hello there.");
}

- (void)testComposeRichMessageWithAi_SendsParagraphBlocks {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c composeRichMessageWithAi:@"one\ntwo" translateTo:@"de" style:@"casual"
				   customPrompt:@"" addEmojis:NO
					 completion:^(NSString *text, NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"composeRichMessageWithAi");
	NSDictionary *message = request[@"message"];
	XCTAssertEqualObjects(message[@"@type"], @"inputRichMessage");
	XCTAssertEqualObjects(message[@"source"][@"@type"], @"richMessageSourceBlocks");
	XCTAssertEqual([message[@"source"][@"blocks"] count], (NSUInteger)2);
	XCTAssertEqualObjects(message[@"source"][@"blocks"][1][@"@type"],
						  @"inputPageBlockParagraph");
	XCTAssertEqualObjects(message[@"source"][@"blocks"][1][@"text"][@"text"], @"two");
	t2Answer(c, @{@"@type" : @"richMessage", @"is_full" : @YES, @"is_rtl" : @NO,
				  @"blocks" : @[@{@"@type" : @"pageBlockParagraph",
								 @"text" : @{@"@type" : @"richTextPlain",
											 @"text" : @"Eins\nZwei"}}]});
	XCTAssertEqualObjects(got, @"Eins\nZwei");
}

- (void)testCreateRichMessageWithAi_SendsPromptLanguageAndEmoji {
	TGClient *c = T2();
	[c createRichMessageWithAi:@"a launch note" languageCode:@"en" addEmojis:YES
					completion:nil];
	NSDictionary *request = t2Last(c, @"createRichMessageWithAi");
	XCTAssertEqualObjects(request[@"prompt"], @"a launch note");
	XCTAssertEqualObjects(request[@"language_code"], @"en");
	XCTAssertEqualObjects(request[@"add_emojis"], @YES);
}

- (void)testFixTextWithAi_ReadsTheFixedTextAndDiff {
	TGClient *c = T2();
	__block NSString *fixed = nil;
	__block NSString *diff = nil;
	[c fixTextWithAi:@"teh cat" completion:^(NSString *text, NSString *changes, NSString *error){
		fixed = text;
		diff = changes;
	}];
	XCTAssertEqualObjects(t2Last(c, @"fixTextWithAi")[@"text"][@"text"], @"teh cat");
	t2Answer(c, @{@"@type" : @"fixedText",
				  @"text" : @{@"@type" : @"formattedText", @"text" : @"the cat", @"entities" : @[]},
				  @"diff_text" : @{@"@type" : @"diffText", @"text" : @"teh → the"}});
	XCTAssertEqualObjects(fixed, @"the cat");
	XCTAssertEqualObjects(diff, @"teh → the");
}

- (void)testFixRichMessageWithAi_SendsARichMessageAndReadsText {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c fixRichMessageWithAi:@"teh cat" completion:^(NSString *text, NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"fixRichMessageWithAi");
	XCTAssertEqualObjects(request[@"message"][@"@type"], @"inputRichMessage");
	t2Answer(c, @{@"@type" : @"richMessage", @"is_full" : @YES, @"is_rtl" : @NO,
				  @"blocks" : @[@{@"@type" : @"pageBlockParagraph",
								 @"text" : @{@"@type" : @"richTextPlain",
											 @"text" : @"the cat"}}]});
	XCTAssertEqualObjects(got, @"the cat");
}

- (void)testSummarizeMessage_SendsChatMessageLanguageAndTone {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c summarizeMessage:55 inChat:77 translateTo:@"uk" tone:@"formal"
			 completion:^(NSString *text, NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"summarizeMessage");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"translate_to_language_code"], @"uk");
	XCTAssertEqualObjects(request[@"tone"], @"formal");
	t2Answer(c, @{@"@type" : @"formattedText", @"text" : @"Коротко", @"entities" : @[]});
	XCTAssertEqualObjects(got, @"Коротко");
}

- (void)testTranslateMessageRichMessage_ReadsTheRichAnswer {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c translateMessageRichMessage:55 inChat:77 toCode:@"de" tone:@"casual"
					   completion:^(NSString *text, NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"translateMessageRichMessage");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	XCTAssertEqualObjects(request[@"to_language_code"], @"de");
	XCTAssertEqualObjects(request[@"tone"], @"casual");
	t2Answer(c, @{@"@type" : @"richMessage", @"is_full" : @YES, @"is_rtl" : @NO,
				  @"blocks" : @[@{@"@type" : @"pageBlockParagraph",
								 @"text" : @{@"@type" : @"richTextPlain",
											 @"text" : @"Hallo"}}]});
	XCTAssertEqualObjects(got, @"Hallo");
}

- (void)testTranslateRichMessage_SendsABuiltRichMessage {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c translateRichMessage:@"hello" toCode:@"uk" tone:@"" completion:^(NSString *text,
																	 NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"translateRichMessage");
	XCTAssertEqualObjects(request[@"message"][@"@type"], @"inputRichMessage");
	XCTAssertEqualObjects(request[@"to_language_code"], @"uk");
	t2Answer(c, @{@"@type" : @"richMessage", @"is_full" : @YES, @"is_rtl" : @NO,
				  @"blocks" : @[@{@"@type" : @"pageBlockParagraph",
								 @"text" : @{@"@type" : @"richTextPlain",
											 @"text" : @"привіт"}}]});
	XCTAssertEqualObjects(got, @"привіт");
}

- (void)testGetFullRichMessage_ReadsTheWholeBlockList {
	TGClient *c = T2();
	__block NSString *got = nil;
	[c getFullRichMessage:55 inChat:77 completion:^(NSString *text, NSDictionary *message,
													 NSString *error){ got = text; }];
	NSDictionary *request = t2Last(c, @"getFullRichMessage");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"message_id"], @(55));
	t2Answer(c, @{@"@type" : @"richMessage", @"is_full" : @YES, @"is_rtl" : @NO,
				  @"blocks" : @[
					  @{@"@type" : @"pageBlockSectionHeading",
						@"text" : @{@"@type" : @"richTextPlain", @"text" : @"Plan"}},
					  @{@"@type" : @"pageBlockList", @"items" : @[
						  @{@"@type" : @"pageBlockListItem", @"has_checkbox" : @YES,
							@"is_checked" : @NO,
							@"blocks" : @[@{@"@type" : @"pageBlockParagraph",
										   @"text" : @{@"@type" : @"richTextPlain",
													   @"text" : @"Book"}}]}]}]});
	XCTAssertEqualObjects(got, @"Plan\n☐ Book");
}

- (void)testSendRichMessageDraft_SendsTheDraftShape {
	TGClient *c = T2();
	[c sendRichMessageDraft:@"draft body" toChat:77 topicId:9 draftId:123
					  canStop:YES keepOnStop:NO completion:nil];
	NSDictionary *request = t2Last(c, @"sendRichMessageDraft");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"forum_topic_id"], @(9));
	XCTAssertEqualObjects(request[@"draft_id"], @(123));
	XCTAssertEqualObjects(request[@"can_stop"], @YES);
	XCTAssertEqualObjects(request[@"keep_on_stop"], @NO);
	XCTAssertEqualObjects(request[@"message"][@"@type"], @"inputRichMessage");
}

- (void)testSetMessageFactCheck_SetsAndClearsWithANull {
	TGClient *c = T2();
	[c setMessageFactCheck:55 inChat:77 text:@"Checked" completion:nil];
	NSDictionary *set = t2Last(c, @"setMessageFactCheck");
	XCTAssertEqualObjects(set[@"chat_id"], @(77));
	XCTAssertEqualObjects(set[@"message_id"], @(55));
	XCTAssertEqualObjects(set[@"text"][@"text"], @"Checked");
	t2Answer(c, @{@"@type" : @"ok"});

	[c setMessageFactCheck:55 inChat:77 text:nil completion:nil];
	NSDictionary *clear = t2Last(c, @"setMessageFactCheck");
	XCTAssertTrue(clear[@"text"] == [NSNull null]);
}

@end
