//
// TGUpdatesCatchUpTests.m - the story, message, chat and Star updates that
// used to be dropped before handleUpdate saw them.
//
// Each test drives the update through handleUpdate, the way the receive loop
// sends it, and reads the same state or notification a screen reads. A branch
// removed from handleUpdate makes the test fail rather than silently leaving
// the row on yesterday's story or revenue.
//
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGUpdatesCatchUpTests : XCTestCase @end

static TGClient *CatchUpClient(void) {
	TGClient *c = TGClient.shared;
	[c.chatsById removeAllObjects];
	c.chats = @[];
	c.archivedChats = @[];
	c.onChatsChanged = nil;
	c.onMessage = nil;
	c.storyMainListChatCount = 0;
	c.storyArchiveListChatCount = 0;
	c.storyStealthModeValue = nil;
	c.ownedStarCountValue = 0;
	c.chatRevenueAmountByChat = [NSMutableDictionary dictionary];
	c.starRevenueStatusByOwner = [NSMutableDictionary dictionary];
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.updateCoalescer reset];
	return c;
}

static NSDictionary *CatchUpStory(long long storyId, long long chatId) {
	return @{
		@"@type" : @"story",
		@"id" : @(storyId),
		@"poster_chat_id" : @(chatId),
		@"date" : @(1700000000),
		@"caption" : @{@"text" : @"A caption", @"entities" : @[]},
		@"content" : @{@"@type" : @"storyContentPhoto",
					   @"photo" : @{@"sizes" : @[
						   @{@"width" : @1080, @"height" : @1920,
							 @"photo" : @{@"id" : @(555)}}]}},
		@"privacy_settings" : @{@"@type" : @"storyPrivacySettingsEveryone",
								 @"except_user_ids" : @[]},
	};
}

@implementation TGUpdatesCatchUpTests

#pragma mark - stories

- (void)testStoryUpdate_FlattensTheStoryForTheViewer {
	TGClient *c = CatchUpClient();
	__block NSDictionary *seen = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStoriesChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		if ([n.userInfo[@"story"] isKindOfClass:NSDictionary.class])
			seen = n.userInfo[@"story"];
	}];

	[c handleUpdate:@{@"@type" : @"updateStory",
					  @"story" : CatchUpStory(9, 5)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(seen[@"storyId"], @(9));
	XCTAssertEqualObjects(seen[@"chatId"], @(5));
	XCTAssertEqualObjects(seen[@"caption"], @"A caption");
	XCTAssertEqualObjects(seen[@"photoId"], @(555));
}

- (void)testStoryDeleted_NamesTheStoryTheViewerMustDrop {
	TGClient *c = CatchUpClient();
	__block NSNumber *deleted = nil;
	__block NSNumber *chat = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStoriesChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		if (n.userInfo[@"deletedStoryId"]){
			deleted = n.userInfo[@"deletedStoryId"];
			chat = n.userInfo[@"chatId"];
		}
	}];

	[c handleUpdate:@{@"@type" : @"updateStoryDeleted",
					  @"story_poster_chat_id" : @(5), @"story_id" : @(9)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(deleted, @(9));
	XCTAssertEqualObjects(chat, @(5));
}

- (void)testStoryPostSucceeded_AnnouncesTheFinishedStory {
	TGClient *c = CatchUpClient();
	__block NSDictionary *info = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStoryPostFinishedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ info = n.userInfo; }];

	[c handleUpdate:@{@"@type" : @"updateStoryPostSucceeded",
					  @"story" : CatchUpStory(9, 5), @"old_story_id" : @(3)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(info[@"ok"], @YES);
	XCTAssertEqualObjects(info[@"chatId"], @(5));
	XCTAssertEqualObjects(info[@"storyId"], @(9));
	XCTAssertEqualObjects(info[@"story"][@"storyId"], @(9));
}

- (void)testStoryPostFailed_CarriesTelegramReason {
	TGClient *c = CatchUpClient();
	__block NSDictionary *info = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStoryPostFinishedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ info = n.userInfo; }];

	[c handleUpdate:@{@"@type" : @"updateStoryPostFailed",
					  @"story_poster_chat_id" : @(5), @"story_id" : @(9),
					  @"error" : @{@"@type" : @"error", @"code" : @(400),
								   @"message" : @"Story file is too big"}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(info[@"ok"], @NO);
	XCTAssertEqualObjects(info[@"chatId"], @(5));
	XCTAssertEqualObjects(info[@"storyId"], @(9));
	XCTAssertEqualObjects(info[@"error"], @"Story file is too big");
}

- (void)testStoryListChatCount_IsKeptPerList {
	TGClient *c = CatchUpClient();
	[c handleUpdate:@{@"@type" : @"updateStoryListChatCount",
					  @"story_list" : @{@"@type" : @"storyListMain"},
					  @"chat_count" : @(3)}];
	[c handleUpdate:@{@"@type" : @"updateStoryListChatCount",
					  @"story_list" : @{@"@type" : @"storyListArchive"},
					  @"chat_count" : @(7)}];

	XCTAssertEqual([c storyListChatCountForList:@"main"], (NSInteger)3);
	XCTAssertEqual([c storyListChatCountForList:@"archive"], (NSInteger)7);
	XCTAssertEqual([c storyListChatCountForList:@"anything"], (NSInteger)3);
}

- (void)testStoryStealthMode_KeepsBothDates {
	TGClient *c = CatchUpClient();
	[c handleUpdate:@{@"@type" : @"updateStoryStealthMode",
					  @"active_until_date" : @(1700000000),
					  @"cooldown_until_date" : @(1700003600)}];

	XCTAssertEqualObjects([c storyStealthMode][@"activeUntilDate"], @(1700000000));
	XCTAssertEqualObjects([c storyStealthMode][@"cooldownUntilDate"], @(1700003600));
}

#pragma mark - messages

- (void)testMessageFields_NudgeTheOpenChat {
	TGClient *c = CatchUpClient();
	__block int nudges = 0;
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0 && chatId == 3)
			nudges++;
	};

	for (NSString *type in @[@"updateMessageFactCheck",
							 @"updateMessageEphemeralContent",
							 @"updateMessageSuggestedPostInfo"]){
		[c handleUpdate:@{@"@type" : type, @"chat_id" : @(3),
						  @"message_id" : @(8)}];
	}
	c.onMessage = nil;

	XCTAssertEqual(nudges, 3);
}

#pragma mark - chat fields

- (void)testChatVideoChat_IsKeptOnTheRowAndCleared {
	TGClient *c = CatchUpClient();
	[c handleUpdate:@{@"@type" : @"updateChatVideoChat", @"chat_id" : @(7),
					  @"video_chat" : @{@"@type" : @"videoChat",
										@"group_call_id" : @(42),
										@"has_participants" : @YES}}];

	NSMutableDictionary *row = c.chatsById[@(7)];
	XCTAssertEqualObjects(row[@"videoChat"][@"group_call_id"], @(42));

	[c handleUpdate:@{@"@type" : @"updateChatVideoChat", @"chat_id" : @(7)}];
	XCTAssertNil(c.chatsById[@(7)][@"videoChat"]);
}

#pragma mark - Stars and revenue

- (void)testOwnedStarCount_IsKept {
	TGClient *c = CatchUpClient();
	[c handleUpdate:@{@"@type" : @"updateOwnedStarCount", @"star_count" : @"250"}];

	XCTAssertEqual(c.ownedStarCount, 250LL);
}

- (void)testChatRevenueAmount_IsKeptAndAnnouncesTheChat {
	TGClient *c = CatchUpClient();
	__block NSNumber *chat = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGChatRevenueChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ chat = n.userInfo[@"chatId"]; }];

	[c handleUpdate:@{@"@type" : @"updateChatRevenueAmount", @"chat_id" : @(5),
					  @"revenue_amount" : @{@"@type" : @"chatRevenueAmount",
											@"total_amount" : @"10",
											@"balance_amount" : @"8",
											@"available_amount" : @"6",
											@"withdrawal_enabled" : @YES}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(chat, @(5));
	XCTAssertEqualObjects([c chatRevenueAmountForChat:5][@"total_amount"], @"10");
	XCTAssertEqualObjects([c chatRevenueAmountForChat:5][@"withdrawal_enabled"], @YES);
	XCTAssertNil([c chatRevenueAmountForChat:6]);
}

- (void)testStarRevenueStatus_IsKeptPerOwnerAndAnnouncesIt {
	TGClient *c = CatchUpClient();
	__block NSString *kind = nil;
	__block NSNumber *ownerId = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStarRevenueChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		kind = n.userInfo[@"ownerKind"];
		ownerId = n.userInfo[@"ownerId"];
	}];

	[c handleUpdate:@{@"@type" : @"updateStarRevenueStatus",
					  @"owner_id" : @{@"@type" : @"messageSenderUser",
									  @"user_id" : @(9)},
					  @"status" : @{@"@type" : @"starRevenueStatus",
									@"total_amount" : @{@"@type" : @"starAmount",
														@"star_count" : @(100)},
									@"current_amount" : @{@"@type" : @"starAmount",
														  @"star_count" : @(40)},
									@"available_amount" : @{@"@type" : @"starAmount",
															@"star_count" : @(20)},
									@"withdrawal_enabled" : @YES}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(kind, @"user");
	XCTAssertEqualObjects(ownerId, @(9));
	NSDictionary *status = [c starRevenueStatusForOwner:@"user" ownerId:9];
	XCTAssertEqualObjects(status[@"total_amount"][@"star_count"], @(100));
	XCTAssertEqualObjects(status[@"withdrawal_enabled"], @YES);
	XCTAssertNil([c starRevenueStatusForOwner:@"chat" ownerId:9]);
}

@end
