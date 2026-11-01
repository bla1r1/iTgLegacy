// TGClientChatToolsTests.m — Tier 2's chat surface.
//
// Every method here is driven once: the point of the file is the wire shape,
// because these requests sit behind sheets where a wrong field is invisible
// until Telegram refuses it. The nested ones (a read before a write) are
// answered in order, the way the receive loop would.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientChatToolsTests : XCTestCase @end

static TGClient *CT(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *ctDecode(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *ctLast(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([ctDecode(d)[@"@type"] isEqualToString:type])
			found = ctDecode(d);
	return found;
}

static NSUInteger ctCount(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([ctDecode(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void ctAnswer(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *r = ctDecode(d);
		if (r[@"@extra"])
			sent = r;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *ctPlain(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientChatToolsTests

#pragma mark - folders

- (void)testChatCountForFolder_SendsTheFolderAndReadsTheCount {
	TGClient *c = CT();
	__block NSInteger got = -1;
	[c chatCountForFolder:@{@"name" : @{@"text" : @{@"text" : @"Work"}}}
			   completion:^(NSInteger count){ got = count; }];
	NSDictionary *r = ctLast(c, @"getChatFolderChatCount");
	XCTAssertEqualObjects(r[@"folder"][@"@type"], @"chatFolder");
	ctAnswer(c, ctPlain(@{@"@type" : @"count", @"count" : @(42)}));
	XCTAssertEqual(got, (NSInteger)42);
}

- (void)testChatsToLeaveForFolder_ReadsTheSuggestedIds {
	TGClient *c = CT();
	__block NSArray *got = nil;
	[c chatsToLeaveForFolder:3 completion:^(NSArray *ids){ got = ids; }];
	XCTAssertEqualObjects(ctLast(c, @"getChatFolderChatsToLeave")[@"chat_folder_id"], @(3));
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(7), @(8)]});
	XCTAssertEqualObjects(got, (@[@(7), @(8)]));
}

- (void)testDefaultIconNameForFolder_FallsBackToTheRequestPath {
	TGClient *c = CT();
	__block NSString *got = nil;
	[c defaultIconNameForFolder:@{@"name" : @{@"text" : @{@"text" : @"Work"}}}
					 completion:^(NSString *name){ got = name; }];
	XCTAssertNotNil(ctLast(c, @"getChatFolderDefaultIconName"));
	ctAnswer(c, @{@"@type" : @"chatFolderIcon", @"name" : @"Cat"});
	XCTAssertEqualObjects(got, @"Cat");
}

- (void)testFolderInviteLinks_CreateEditDeleteAndRead {
	TGClient *c = CT();
	__block NSArray *links = nil;
	[c inviteLinksForFolder:3 completion:^(NSArray *l){ links = l; }];
	ctAnswer(c, @{@"@type" : @"chatFolderInviteLinks",
				  @"invite_links" : @[@{@"invite_link" : @"https://t.me/addlist/x",
										@"name" : @"Work", @"chat_ids" : @[@(5)]}]});
	XCTAssertEqualObjects(links[0][@"link"], @"https://t.me/addlist/x");
	XCTAssertEqualObjects(links[0][@"chatIds"], (@[@(5)]));

	__block NSArray *suitable = nil;
	[c chatsForFolderInviteLink:3 completion:^(NSArray *ids){ suitable = ids; }];
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(5), @(6)]});
	XCTAssertEqualObjects(suitable, (@[@(5), @(6)]));

	__block NSString *made = nil;
	[c createInviteLinkForFolder:3 name:@"Work" chatIds:@[@(5)]
					  completion:^(NSString *link){ made = link; }];
	NSDictionary *create = ctLast(c, @"createChatFolderInviteLink");
	XCTAssertEqualObjects(create[@"chat_folder_id"], @(3));
	XCTAssertEqualObjects(create[@"chat_ids"], (@[@(5)]));
	ctAnswer(c, @{@"@type" : @"chatFolderInviteLink",
				  @"invite_link" : @"https://t.me/addlist/y"});
	XCTAssertEqualObjects(made, @"https://t.me/addlist/y");

	__block BOOL edited = NO;
	[c editInviteLinkForFolder:3 link:@"https://t.me/addlist/y" name:@"New"
						chatIds:@[@(5)] completion:^(BOOL ok){ edited = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"editChatFolderInviteLink")[@"name"], @"New");
	ctAnswer(c, @{@"@type" : @"chatFolderInviteLink"});
	XCTAssertTrue(edited);

	__block BOOL deleted = NO;
	[c deleteInviteLinkForFolder:3 link:@"https://t.me/addlist/y"
					   completion:^(BOOL ok){ deleted = ok; }];
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(deleted);
}

- (void)testCheckAndAddFolderLink_FlattenTheFolder {
	TGClient *c = CT();
	__block NSDictionary *got = nil;
	[c checkFolderInviteLink:@"https://t.me/addlist/x"
				  completion:^(NSDictionary *f){ got = f; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"chatFolderInviteLinkInfo",
						  @"chat_folder_info" : @{
							  @"@type" : @"chatFolderInfo", @"id" : @(9),
							  @"name" : @{@"@type" : @"chatFolderName",
										  @"text" : @{@"@type" : @"formattedText",
													  @"text" : @"Shared"}}},
						  @"missing_chat_ids" : @[@(5)],
						  @"added_chat_ids" : @[@(6)]}));
	XCTAssertEqualObjects(got[@"name"], @"Shared");
	XCTAssertEqualObjects(got[@"missing"], (@[@(5)]));

	__block BOOL added = NO;
	[c addFolderByInviteLink:@"https://t.me/addlist/x" chatIds:@[@(5)]
				  completion:^(BOOL ok){ added = ok; }];
	NSDictionary *r = ctLast(c, @"addChatFolderByInviteLink");
	XCTAssertEqualObjects(r[@"chat_ids"], (@[@(5)]));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(added);
}

- (void)testFolderNewChats_AndProcessThem {
	TGClient *c = CT();
	__block NSArray *ids = nil;
	[c newChatsForFolder:3 completion:^(NSArray *i){ ids = i; }];
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(11)]});
	XCTAssertEqualObjects(ids, (@[@(11)]));

	__block BOOL ok = NO;
	[c processNewChats:@[@(11)] forFolder:3 completion:^(BOOL o){ ok = o; }];
	XCTAssertEqualObjects(ctLast(c, @"processChatFolderNewChats")[@"added_chat_ids"],
						  (@[@(11)]));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testChatListsForChat_AndEnablingFolderTags {
	TGClient *c = CT();
	__block NSArray *lists = nil;
	[c chatListsForChat:77 completion:^(NSArray *l){ lists = l; }];
	XCTAssertEqualObjects(ctLast(c, @"getChatListsToAddChat")[@"chat_id"], @(77));
	ctAnswer(c, @{@"@type" : @"chatLists",
				  @"chat_lists" : @[@{@"@type" : @"chatListMain"},
									@{@"@type" : @"chatListFolder", @"chat_folder_id" : @(3)}]});
	XCTAssertEqual(lists.count, (NSUInteger)2);
	XCTAssertEqualObjects(lists[1][@"@type"], @"chatListFolder");

	[c toggleFolderTags:YES];
	XCTAssertEqualObjects(ctLast(c, @"toggleChatFolderTags")[@"are_tags_enabled"], @YES);
}

#pragma mark - invite links

- (void)testInviteLink_ReadsTheWholeLink {
	TGClient *c = CT();
	__block NSDictionary *got = nil;
	[c inviteLink:@"https://t.me/+abc" inChat:77 completion:^(NSDictionary *i){ got = i; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"chatInviteLink",
						  @"invite_link" : @"https://t.me/+abc", @"name" : @"Crew",
						  @"member_count" : @(4), @"member_limit" : @(10),
						  @"creates_join_request" : @YES, @"is_revoked" : @NO}));
	XCTAssertEqualObjects(got[@"name"], @"Crew");
	XCTAssertEqualObjects(got[@"members"], @(4));
	XCTAssertEqualObjects(got[@"joinRequest"], @YES);
}

- (void)testInviteLinkCounts_AndMembers {
	TGClient *c = CT();
	__block NSArray *counts = nil;
	[c inviteLinkCountsForChat:77 completion:^(NSArray *r){ counts = r; }];
	ctAnswer(c, @{@"@type" : @"chatInviteLinkCounts",
				  @"invite_link_counts" : @[@{@"user_id" : @(1001),
											  @"invite_link_count" : @(3),
											  @"revoked_invite_link_count" : @(1)}]});
	XCTAssertEqualObjects(counts[0][@"active"], @(3));
	XCTAssertEqualObjects(counts[0][@"revoked"], @(1));

	__block NSArray *members = nil;
	[c membersOfInviteLink:@"https://t.me/+abc" inChat:77
				completion:^(NSArray *m){ members = m; }];
	NSDictionary *r = ctLast(c, @"getChatInviteLinkMembers");
	XCTAssertEqualObjects(r[@"limit"], @(100));
	ctAnswer(c, @{@"@type" : @"chatInviteLinkMembers", @"total_count" : @(1),
				  @"members" : @[@{@"user_id" : @(42),
								  @"joined_chat_date" : @(1700000000),
								  @"approver_user_id" : @(1001)}]});
	XCTAssertEqualObjects(members[0][@"id"], @(42));
}

- (void)testSubscriptionLink_CreateAndRename {
	TGClient *c = CT();
	__block NSString *made = nil;
	[c createSubscriptionInviteLink:77 name:@"Monthly" stars:5 period:2592000
						 completion:^(NSString *l){ made = l; }];
	NSDictionary *r = ctLast(c, @"createChatSubscriptionInviteLink");
	XCTAssertEqualObjects(r[@"subscription_pricing"][@"star_count"], @(5));
	XCTAssertEqualObjects(r[@"subscription_pricing"][@"period"], @(2592000));
	ctAnswer(c, @{@"@type" : @"chatInviteLink", @"invite_link" : @"https://t.me/+sub"});
	XCTAssertEqualObjects(made, @"https://t.me/+sub");

	__block BOOL renamed = NO;
	[c editSubscriptionInviteLink:@"https://t.me/+sub" inChat:77 name:@"Yearly"
					   completion:^(BOOL ok){ renamed = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"editChatSubscriptionInviteLink")[@"name"], @"Yearly");
	ctAnswer(c, @{@"@type" : @"chatInviteLink"});
	XCTAssertTrue(renamed);
}

- (void)testEditInviteLink_AnApprovalLinkLosesItsMemberLimit {
	TGClient *c = CT();
	__block BOOL ok = NO;
	[c editInviteLink:@"https://t.me/+abc" inChat:77 name:@"Crew" expiration:0
			memberLimit:50 joinRequest:YES completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = ctLast(c, @"editChatInviteLink");
	XCTAssertEqualObjects(r[@"member_limit"], @(0));
	XCTAssertEqualObjects(r[@"creates_join_request"], @YES);
	ctAnswer(c, @{@"@type" : @"chatInviteLink"});
	XCTAssertTrue(ok);
}

- (void)testDeleteRevokedLinks_BothShapes {
	TGClient *c = CT();
	__block BOOL one = NO;
	[c deleteRevokedInviteLink:@"https://t.me/+old" inChat:77
					completion:^(BOOL ok){ one = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"deleteRevokedChatInviteLink")[@"invite_link"],
						  @"https://t.me/+old");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(one);

	__block BOOL all = NO;
	[c deleteAllRevokedInviteLinks:77 creator:1001 completion:^(BOOL ok){ all = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"deleteAllRevokedChatInviteLinks")[@"creator_user_id"],
						  @(1001));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(all);
}

#pragma mark - join requests and keyboards

- (void)testAnswerJoinRequestQuery_ApprovedAndDeclined {
	TGClient *c = CT();
	__block BOOL ok = NO;
	[c answerJoinRequestQuery:9001 approve:YES completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = ctLast(c, @"answerChatJoinRequestQuery");
	XCTAssertEqualObjects(r[@"query_id"], @(9001));
	XCTAssertEqualObjects(r[@"result"][@"@type"], @"chatJoinRequestResultApproved");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testProcessAllJoinRequests_CarriesTheEmptyLinkForAll {
	TGClient *c = CT();
	__block BOOL ok = NO;
	[c processAllJoinRequests:77 link:@"" approve:NO completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = ctLast(c, @"processChatJoinRequests");
	XCTAssertEqualObjects(r[@"invite_link"], @"");
	XCTAssertEqualObjects(r[@"approve"], @NO);
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeleteReplyMarkup_ExplicitAndFromTheChatRow {
	TGClient *c = CT();
	[c deleteReplyMarkupInChat:77 messageId:55];
	XCTAssertEqualObjects(ctLast(c, @"deleteChatReplyMarkup")[@"message_id"], @(55));
	XCTAssertNil(ctLast(c, @"deleteChatReplyMarkup")[@"@extra"]);

	[c.outbox removeAllObjects];
	c.chatsById[@(77)] = [@{@"replyMarkupMessageId" : @(56)} mutableCopy];
	[c dismissReplyMarkupInChat:77];
	XCTAssertEqualObjects(ctLast(c, @"deleteChatReplyMarkup")[@"message_id"], @(56));
}

#pragma mark - recently found

- (void)testRecentlyFound_SearchRemoveClear {
	TGClient *c = CT();
	c.chatsById[@(5)] = [@{@"id" : @(5), @"title" : @"Ada"} mutableCopy];
	__block NSArray *rows = nil;
	[c searchRecentlyFoundChats:@"ad" completion:^(NSArray *r){ rows = r; }];
	NSDictionary *r = ctLast(c, @"searchRecentlyFoundChats");
	XCTAssertEqualObjects(r[@"limit"], @(50));
	XCTAssertTrue(r[@"type_filter"] == [NSNull null]);
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(5)]});
	XCTAssertEqualObjects(rows[0][@"title"], @"Ada");

	[c forgetRecentlyFoundChat:5];
	XCTAssertEqualObjects(ctLast(c, @"removeRecentlyFoundChat")[@"chat_id"], @(5));
	[c clearRecentlyFoundChats];
	XCTAssertNotNil(ctLast(c, @"clearRecentlyFoundChats"));
}

#pragma mark - discovery

- (void)testSimilarChats_CountThenListAndTheOpenNotice {
	TGClient *c = CT();
	c.chatsById[@(9)] = [@{@"id" : @(9), @"title" : @"Twin"} mutableCopy];
	__block NSArray *rows = nil;
	__block NSInteger total = -1;
	[c similarChatsForChat:77 completion:^(NSArray *r, NSInteger t){
		rows = r; total = t;
	}];
	ctAnswer(c, @{@"@type" : @"count", @"count" : @(12)});
	XCTAssertNotNil(ctLast(c, @"getChatSimilarChats"));
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(9)]});
	XCTAssertEqual(total, (NSInteger)12);
	XCTAssertEqualObjects(rows[0][@"title"], @"Twin");

	[c openSimilarChat:9 fromChat:77];
	NSDictionary *open = ctLast(c, @"openChatSimilarChat");
	XCTAssertEqualObjects(open[@"chat_id"], @(77));
	XCTAssertEqualObjects(open[@"opened_chat_id"], @(9));
}

- (void)testRecommendationsAndSuitableLists_AllBecomeRows {
	TGClient *c = CT();
	c.chatsById[@(9)] = [@{@"id" : @(9), @"title" : @"Channel"} mutableCopy];

	__block NSArray *recommended = nil;
	[c recommendedChatsWithCompletion:^(NSArray *r){ recommended = r; }];
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(9)]});
	XCTAssertEqualObjects(recommended[0][@"title"], @"Channel");

	__block NSArray *discussion = nil;
	[c suitableDiscussionChatsWithCompletion:^(NSArray *r){ discussion = r; }];
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(9)]});
	XCTAssertEqual(discussion.count, (NSUInteger)1);

	__block NSArray *personal = nil;
	[c suitablePersonalChatsWithCompletion:^(NSArray *r){ personal = r; }];
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(9)]});
	XCTAssertEqual(personal.count, (NSUInteger)1);

	__block BOOL set = NO;
	[c setPersonalChat:9 completion:^(BOOL ok){ set = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"setPersonalChat")[@"chat_id"], @(9));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(set);

	__block NSArray *inactive = nil;
	[c inactiveSupergroupChatsWithCompletion:^(NSArray *r){ inactive = r; }];
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(9)]});
	XCTAssertEqual(inactive.count, (NSUInteger)1);
}

- (void)testPublicChats_LimitAndUsernameCheck {
	TGClient *c = CT();
	c.chatsById[@(9)] = [@{@"id" : @(9), @"title" : @"Public"} mutableCopy];

	__block NSArray *chats = nil;
	[c createdPublicChatsOfType:@"username" completion:^(NSArray *r){ chats = r; }];
	XCTAssertEqualObjects(ctLast(c, @"getCreatedPublicChats")[@"type"][@"@type"],
						  @"publicChatTypeHasUsername");
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(9)]});
	XCTAssertEqual(chats.count, (NSUInteger)1);

	__block BOOL allowed = NO;
	__block NSString *reason = @"x";
	[c checkCreatedPublicChatsLimitForType:@"username"
								completion:^(BOOL ok, NSString *why){
		allowed = ok; reason = why;
	}];
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(allowed);
	XCTAssertNil(reason);

	__block NSString *word = nil;
	[c checkUsername:@"crew" forChat:9 completion:^(NSString *w){ word = w; }];
	ctAnswer(c, @{@"@type" : @"checkChatUsernameResultUsernameOccupied"});
	XCTAssertEqualObjects(word, @"occupied");
}

#pragma mark - account preferences

- (void)testNewChatPrivacy_ReadThenWriteKeepingThePaidCount {
	TGClient *c = CT();
	__block NSDictionary *settings = nil;
	[c newChatPrivacySettingsWithCompletion:^(NSDictionary *s){ settings = s; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"newChatPrivacySettings",
						  @"allow_new_chats_from_unknown_users" : @YES,
						  @"incoming_paid_message_star_count" : @(2)}));
	XCTAssertEqualObjects(settings[@"allow_new_chats_from_unknown_users"], @YES);

	__block BOOL ok = NO;
	[c setNewChatPrivacyAllowUnknown:NO completion:^(BOOL o){ ok = o; }];
	ctAnswer(c, @{@"@type" : @"newChatPrivacySettings",
				  @"allow_new_chats_from_unknown_users" : @YES,
				  @"incoming_paid_message_star_count" : @(2)});
	NSDictionary *r = ctLast(c, @"setNewChatPrivacySettings");
	XCTAssertEqualObjects(r[@"settings"][@"allow_new_chats_from_unknown_users"], @NO);
	XCTAssertEqualObjects(r[@"settings"][@"incoming_paid_message_star_count"], @(2));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testNotificationExceptions_BecomeChatRows {
	TGClient *c = CT();
	c.chatsById[@(5)] = [@{@"id" : @(5), @"title" : @"Quiet"} mutableCopy];
	__block NSArray *rows = nil;
	[c notificationExceptionsWithCompletion:^(NSArray *r){ rows = r; }];
	XCTAssertTrue(ctLast(c, @"getChatNotificationSettingsExceptions")[@"scope"] ==
				  [NSNull null]);
	ctAnswer(c, @{@"@type" : @"chats", @"chat_ids" : @[@(5)]});
	XCTAssertEqualObjects(rows[0][@"title"], @"Quiet");
}

#pragma mark - the chat itself

- (void)testChatRecordAndGroupFullInfo_AreBothRead {
	TGClient *c = CT();
	__block NSDictionary *chat = nil;
	[c chatRecordForChat:77 completion:^(NSDictionary *o){ chat = o; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"chat", @"id" : @(77),
						  @"has_protected_content" : @YES,
						  @"client_data" : @"note"}));
	XCTAssertEqualObjects(chat[@"client_data"], @"note");

	__block NSDictionary *info = nil;
	[c groupFullInfoForChat:77 completion:^(NSDictionary *o){ info = o; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"chat", @"id" : @(77),
						  @"type" : @{@"@type" : @"chatTypeSupergroup",
									  @"supergroup_id" : @(900)}}));
	NSDictionary *ask = ctLast(c, @"getSupergroupFullInfo");
	XCTAssertEqualObjects(ask[@"supergroup_id"], @(900));
	ctAnswer(c, ctPlain(@{@"@type" : @"supergroupFullInfo", @"slow_mode_delay" : @(30)}));
	XCTAssertEqualObjects(info[@"slow_mode_delay"], @(30));
}

- (void)testAddChatToList_CarriesTheRawList {
	TGClient *c = CT();
	__block BOOL ok = NO;
	[c addChat:77 toList:@{@"@type" : @"chatListFolder", @"chat_folder_id" : @(3)}
	 completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = ctLast(c, @"addChatToList");
	XCTAssertEqualObjects(r[@"chat_list"][@"chat_folder_id"], @(3));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testOwnerAfterLeaving_FlattensTheUser {
	TGClient *c = CT();
	__block NSDictionary *user = nil;
	[c ownerAfterLeavingChat:77 completion:^(NSDictionary *u){ user = u; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"user", @"id" : @(42),
						  @"first_name" : @"Ada", @"last_name" : @"Lovelace"}));
	XCTAssertEqualObjects(user[@"name"], @"Ada Lovelace");
}

- (void)testStatistics_FlattenToRows {
	TGClient *c = CT();
	__block NSArray *rows = nil;
	[c chatStatisticsForChat:77 completion:^(NSArray *r, NSString *kind){
		rows = r;
		XCTAssertEqualObjects(kind, @"chatStatisticsChannel");
	}];
	ctAnswer(c, ctPlain(@{@"@type" : @"chatStatisticsChannel",
						  @"member_count" : @{@"value" : @(1200),
											  @"growth_rate_percentage" : @(2.5)},
						  @"mean_message_view_count" : @{@"value" : @(80)}}));
	XCTAssertEqual(rows.count, (NSUInteger)5);
	XCTAssertEqualObjects(rows[0][@"detail"], @"1200 (+2.5%)");
}

- (void)testEventLog_AsksEveryFilterAndReadsTheAction {
	TGClient *c = CT();
	__block NSArray *events = nil;
	[c eventLogForChat:77 completion:^(NSArray *e){ events = e; }];
	NSDictionary *r = ctLast(c, @"getChatEventLog");
	XCTAssertEqualObjects(r[@"filters"][@"member_tag_changes"], @YES);
	XCTAssertEqualObjects(r[@"limit"], @(100));
	ctAnswer(c, ctPlain(@{@"@type" : @"chatEvents",
						  @"events" : @[@{@"id" : @(1), @"date" : @(1700000000),
										  @"member_id" : @{@"@type" : @"messageSenderUser",
														   @"user_id" : @(42)},
										  @"action" : @{@"@type" : @"chatEventMemberJoined"}}]}));
	XCTAssertEqualObjects(events[0][@"text"], @"joined the chat");
}

- (void)testReportChatPhoto_UsesTheLargestSize {
	TGClient *c = CT();
	__block BOOL ok = NO;
	[c reportChatPhotoInChat:77 reason:@"pornography" detail:@""
				  completion:^(BOOL o){ ok = o; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"chat", @"id" : @(77),
						  @"photo" : @{@"sizes" : @[
							  @{@"photo" : @{@"id" : @(10)}},
							  @{@"photo" : @{@"id" : @(20)}}]}}));
	NSDictionary *r = ctLast(c, @"reportChatPhoto");
	XCTAssertEqualObjects(r[@"file_id"], @(20));
	XCTAssertEqualObjects(r[@"reason"][@"@type"], @"reportReasonPornography");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testEmojiPhoto_ReadsTheDefaultsAndSetsTheSticker {
	TGClient *c = CT();
	__block NSArray *stickers = nil;
	[c defaultChatPhotoEmojiStickersWithCompletion:^(NSArray *s){ stickers = s; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"stickers",
						  @"stickers" : @[@{@"emoji" : @"🐱", @"set_id" : @(7),
											@"sticker" : @{@"id" : @(8)},
											@"full_type" : @{
												@"@type" : @"stickerFullTypeCustomEmoji",
												@"custom_emoji_id" : @(99)}}]}));
	XCTAssertEqualObjects(stickers[0][@"customEmojiId"], @(99));

	__block BOOL ok = NO;
	[c setEmojiPhotoForChat:77 customEmojiId:99 colour:0x336699
				 completion:^(BOOL o){ ok = o; }];
	NSDictionary *r = ctLast(c, @"setChatPhoto");
	XCTAssertEqualObjects(r[@"photo"][@"sticker"][@"type"][@"custom_emoji_id"], @(99));
	XCTAssertEqualObjects(r[@"photo"][@"sticker"][@"background_fill"][@"color"],
						  @(0x336699));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testChatAppearance_AccentThemeBackgroundAndReset {
	TGClient *c = CT();
	[c setChatAccentColour:77 colourId:3];
	XCTAssertEqualObjects(ctLast(c, @"setChatAccentColor")[@"accent_color_id"], @(3));
	[c setChatProfileAccentColour:77 colourId:4];
	XCTAssertEqualObjects(ctLast(c, @"setChatProfileAccentColor")[@"profile_accent_color_id"], @(4));

	__block BOOL themed = NO;
	[c setChatTheme:77 name:@"🔥" completion:^(BOOL ok){ themed = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"setChatTheme")[@"theme"][@"@type"],
						  @"inputChatThemeEmoji");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(themed);

	__block BOOL background = NO;
	[c setChatBackground:77 imagePath:@"/tmp/x.jpg" colour:0x112233
			  onlyForSelf:YES completion:^(BOOL ok){ background = ok; }];
	NSDictionary *r = ctLast(c, @"setChatBackground");
	XCTAssertEqualObjects(r[@"background"][@"@type"], @"inputBackgroundLocal");
	XCTAssertEqualObjects(r[@"only_for_self"], @YES);
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(background);

	[c deleteChatBackground:77 restorePrevious:YES];
	XCTAssertEqualObjects(ctLast(c, @"deleteChatBackground")[@"restore_previous"], @YES);
}

- (void)testChatFlags_ReactionsSlowModeTranslatableProtectedSilent {
	TGClient *c = CT();
	__block BOOL reactions = NO;
	[c setAvailableReactionsForChat:77 mode:@"some"
						 completion:^(BOOL ok){ reactions = ok; }];
	NSDictionary *r = ctLast(c, @"setChatAvailableReactions");
	XCTAssertEqualObjects(r[@"available_reactions"][@"@type"], @"chatAvailableReactionsSome");
	XCTAssertEqual([r[@"available_reactions"][@"reactions"] count], (NSUInteger)3);
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(reactions);

	__block BOOL slow = NO;
	[c setSlowModeDelayForChat:77 seconds:60 completion:^(BOOL ok){ slow = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"setChatSlowModeDelay")[@"slow_mode_delay"], @(60));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(slow);

	[c toggleTranslatableForChat:77 on:YES];
	XCTAssertEqualObjects(ctLast(c, @"toggleChatIsTranslatable")[@"is_translatable"], @YES);

	__block BOOL protectedOn = NO;
	[c toggleProtectedContentForChat:77 on:YES
						  completion:^(BOOL ok){ protectedOn = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"toggleChatHasProtectedContent")[@"has_protected_content"], @YES);
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(protectedOn);

	[c toggleDefaultSilentForChat:77 on:YES];
	XCTAssertEqualObjects(ctLast(c, @"toggleChatDefaultDisableNotification")[@"default_disable_notification"], @YES);
}

- (void)testChatMetadata_NoteDiscussionLocationTagAndProtectedRequest {
	TGClient *c = CT();
	__block BOOL note = NO;
	[c setClientNote:@"local" forChat:77 completion:^(BOOL ok){ note = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"setChatClientData")[@"client_data"], @"local");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(note);

	__block BOOL discussion = NO;
	[c setDiscussionGroup:88 forChat:77 completion:^(BOOL ok){ discussion = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"setChatDiscussionGroup")[@"discussion_chat_id"], @(88));
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(discussion);

	__block BOOL location = NO;
	[c setLocationAddress:@"Kyiv" forChat:77 completion:^(BOOL ok){ location = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"setChatLocation")[@"location"][@"address"], @"Kyiv");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(location);

	__block BOOL tag = NO;
	[c setMemberTag:@"Lead" forUser:42 inChat:77 completion:^(BOOL ok){ tag = ok; }];
	NSDictionary *r = ctLast(c, @"setChatMemberTag");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"tag"], @"Lead");
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(tag);

	__block BOOL answered = NO;
	[c processProtectedContentDisableRequestInChat:77 messageId:55 approve:NO
										completion:^(BOOL ok){ answered = ok; }];
	XCTAssertEqualObjects(ctLast(c, @"processChatHasProtectedContentDisableRequest")[@"approve"], @NO);
	ctAnswer(c, @{@"@type" : @"ok"});
	XCTAssertTrue(answered);
}

- (void)testPositions_SparseAndOneMessage {
	TGClient *c = CT();
	__block NSInteger total = -1;
	__block NSArray *positions = nil;
	[c sparsePositionsInChat:77 filter:@"photo" fromMessage:0
				  completion:^(NSInteger t, NSArray *p){ total = t; positions = p; }];
	NSDictionary *r = ctLast(c, @"getChatSparseMessagePositions");
	XCTAssertEqualObjects(r[@"filter"][@"@type"], @"searchMessagesFilterPhoto");
	ctAnswer(c, ctPlain(@{@"@type" : @"messagePositions", @"total_count" : @(9),
						  @"positions" : @[@{@"position" : @(1),
											@"message_id" : @(55),
											@"date" : @(1700000000)}]}));
	XCTAssertEqual(total, (NSInteger)9);
	XCTAssertEqualObjects(positions[0][@"messageId"], @(55));

	__block NSInteger position = -1;
	[c messagePosition:55 inChat:77 filter:@"photo"
			 completion:^(NSInteger p, NSInteger t){ position = p; }];
	XCTAssertTrue(ctLast(c, @"getChatMessagePosition")[@"topic_id"] == [NSNull null]);
	ctAnswer(c, @{@"@type" : @"count", @"count" : @(3)});
	XCTAssertEqual(position, (NSInteger)3);
}

/// Creation runs the compatibility resolve too: the older spelling turns the
/// inner id back into the chat, so a caller sees one chat id either way.
- (void)testSecretChatCreation_AlsoResolvesTheInnerId {
	TGClient *c = CT();
	__block int64_t got = 0;
	[c createSecretChatWithUser:42 completion:^(int64_t chatId){ got = chatId; }];
	ctAnswer(c, ctPlain(@{@"@type" : @"chat", @"id" : @(700),
						  @"type" : @{@"@type" : @"chatTypeSecret",
									  @"secret_chat_id" : @(12),
									  @"user_id" : @(42)}}));
	NSDictionary *resolve = ctLast(c, @"createSecretChat");
	XCTAssertEqualObjects(resolve[@"secret_chat_id"], @(12));
	ctAnswer(c, @{@"@type" : @"chat", @"id" : @(700)});
	XCTAssertEqual(got, (int64_t)700);
}

- (void)testSessionSecretChatSwitch_AndTheThreeResolvers {
	TGClient *c = CT();
	[c toggleSession:900 canAcceptSecretChats:NO];
	NSDictionary *r = ctLast(c, @"toggleSessionCanAcceptSecretChats");
	XCTAssertEqualObjects(r[@"session_id"], @(900));
	XCTAssertEqualObjects(r[@"can_accept_secret_chats"], @NO);

	__block int64_t basic = 0;
	[c chatForBasicGroup:12 completion:^(int64_t chatId){ basic = chatId; }];
	XCTAssertEqualObjects(ctLast(c, @"createBasicGroupChat")[@"basic_group_id"], @(12));
	ctAnswer(c, @{@"@type" : @"chat", @"id" : @(700)});
	XCTAssertEqual(basic, (int64_t)700);

	__block int64_t super = 0;
	[c chatForSupergroup:13 completion:^(int64_t chatId){ super = chatId; }];
	XCTAssertEqualObjects(ctLast(c, @"createSupergroupChat")[@"supergroup_id"], @(13));
	ctAnswer(c, @{@"@type" : @"chat", @"id" : @(701)});
	XCTAssertEqual(super, (int64_t)701);

	__block int64_t secret = 0;
	[c chatForSecretChat:14 completion:^(int64_t chatId){ secret = chatId; }];
	XCTAssertEqualObjects(ctLast(c, @"createSecretChat")[@"secret_chat_id"], @(14));
	ctAnswer(c, @{@"@type" : @"chat", @"id" : @(702)});
	XCTAssertEqual(secret, (int64_t)702);
}

@end
