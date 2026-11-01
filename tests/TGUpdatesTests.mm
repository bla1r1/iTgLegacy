// TGUpdatesTests.mm — the updates the receive loop used to throw away.
//
// Every one of these left a screen showing what the server had already
// changed: a draft typed on another device, an avatar, the @ badge, a limit
// or the clock. The store behind updateOption is C++ and is tested as such,
// the rest goes in through handleUpdate the way the receive loop sends it.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGOptions.h"
#import "TGOptionStore.hpp"

@interface TGUpdatesTests : XCTestCase @end

static TGClient *U(void) {
	TGClient *c = TGClient.shared;
	[c.chatsById removeAllObjects];
	c.chats = @[];
	c.archivedChats = @[];
	c.onChatsChanged = nil;
	c.onMessage = nil;
	[c.updateCoalescer reset];
	TGOptionReset();
	return c;
}

static NSMutableDictionary *info(TGClient *c, int64_t chatId) {
	return c.chatsById[@(chatId)];
}

@implementation TGUpdatesTests

// ─── chat state ──────────────────────────────────────────────────────────────

- (void)testChatDraftMessage_LandsInTheChatRow {
	TGClient *c = U();
	[c handleUpdate:@{@"@type"   : @"updateChatDraftMessage",
					  @"chat_id" : @(5),
					  @"draft_message" : @{@"@type" : @"draftMessage",
						  @"input_message_text" : @{@"@type" : @"inputMessageText",
							  @"text" : @{@"@type" : @"formattedText",
										  @"text"  : @"half a sentence"}}}}];

	XCTAssertEqualObjects(info(c, 5)[@"draft"], @"half a sentence");
	XCTAssertEqualObjects([c draftForChat:5], @"half a sentence");
}

- (void)testChatDraftMessage_ANullDraftClearsIt {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateChatDraftMessage", @"chat_id" : @(5),
					  @"draft_message" : @{@"@type" : @"draftMessage",
						  @"input_message_text" : @{@"@type" : @"inputMessageText",
							  @"text" : @{@"@type" : @"formattedText", @"text" : @"x"}}}}];
	// Sent, or cleared elsewhere: TDLib omits draft_message entirely.
	[c handleUpdate:@{@"@type" : @"updateChatDraftMessage", @"chat_id" : @(5)}];

	XCTAssertEqualObjects(info(c, 5)[@"draft"], @"");
}

- (void)testChatPhoto_SwapsTheFileIdAndAnEmptyOneClearsIt {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateChatPhoto", @"chat_id" : @(7),
					  @"photo" : @{@"@type" : @"chatPhotoInfo",
								   @"small" : @{@"@type" : @"file", @"id" : @(42)}}}];
	XCTAssertEqualObjects([c photoFileIdForChat:7], @(42));

	[c handleUpdate:@{@"@type" : @"updateChatPhoto", @"chat_id" : @(7)}];
	XCTAssertNil([c photoFileIdForChat:7]);
}

- (void)testChatUnreadMentionCount_IsKeptApartFromUnread {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateChatUnreadMentionCount",
					  @"chat_id" : @(9), @"unread_mention_count" : @(3)}];
	[c handleUpdate:@{@"@type" : @"updateChatUnreadReactionCount",
					  @"chat_id" : @(9), @"unread_reaction_count" : @(1)}];

	XCTAssertEqualObjects(info(c, 9)[@"unreadMentions"], @(3));
	XCTAssertEqualObjects(info(c, 9)[@"unreadReactions"], @(1));
	XCTAssertNil(info(c, 9)[@"unread"]);
}

- (void)testMessageMentionRead_DropsTheCountAndNudgesTheOpenChat {
	TGClient *c = U();
	__block int nudges = 0;
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0 && chatId == 9) nudges++;
	};
	[c handleUpdate:@{@"@type" : @"updateChatUnreadMentionCount",
					  @"chat_id" : @(9), @"unread_mention_count" : @(2)}];
	[c handleUpdate:@{@"@type" : @"updateMessageMentionRead", @"chat_id" : @(9),
					  @"message_id" : @(1000), @"unread_mention_count" : @(1)}];
	c.onMessage = nil;

	XCTAssertEqualObjects(info(c, 9)[@"unreadMentions"], @(1));
	XCTAssertEqual(nudges, 1);
}

- (void)testChatIsMarkedAsUnread_ReachesTheRow {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateChatIsMarkedAsUnread",
					  @"chat_id" : @(11), @"is_marked_as_unread" : @YES}];
	XCTAssertEqualObjects(info(c, 11)[@"markedUnread"], @YES);
}

- (void)testMessageEditedAndPinned_ReReadTheOpenChat {
	TGClient *c = U();
	NSMutableArray *nudged = [NSMutableArray array];
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0) [nudged addObject:@(chatId)];
	};
	[c handleUpdate:@{@"@type" : @"updateMessageEdited", @"chat_id" : @(3),
					  @"message_id" : @(8), @"edit_date" : @(1700000000)}];
	[c handleUpdate:@{@"@type" : @"updateMessageIsPinned", @"chat_id" : @(3),
					  @"message_id" : @(8), @"is_pinned" : @YES}];
	[c handleUpdate:@{@"@type" : @"updateMessageContentOpened", @"chat_id" : @(3),
					  @"message_id" : @(8)}];
	c.onMessage = nil;

	XCTAssertEqualObjects(nudged, (@[@(3), @(3), @(3)]));
}

// ─── options ─────────────────────────────────────────────────────────────────

- (void)testOption_EachShapeLandsTyped {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateOption", @"name" : @"is_premium",
					  @"value" : @{@"@type" : @"optionValueBoolean", @"value" : @YES}}];
	// int64 arrives as a string over JSON.
	[c handleUpdate:@{@"@type" : @"updateOption", @"name" : @"message_caption_length_max",
					  @"value" : @{@"@type" : @"optionValueInteger", @"value" : @"2048"}}];
	[c handleUpdate:@{@"@type" : @"updateOption", @"name" : @"language_pack_id",
					  @"value" : @{@"@type" : @"optionValueString", @"value" : @"ru"}}];

	XCTAssertEqual(TGOptionBoolean("is_premium", 0), 1);
	XCTAssertEqual(TGOptionInteger("message_caption_length_max", 0), 2048LL);
	char buf[32] = {0};
	XCTAssertEqual(TGOptionString("language_pack_id", buf, sizeof(buf)), (size_t)2);
	XCTAssertEqualObjects([NSString stringWithUTF8String:buf], @"ru");
	XCTAssertEqual(TGOptionCount(), (size_t)3);
}

- (void)testOption_EmptyRemovesItAndTheFallbackComesBack {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateOption", @"name" : @"is_premium",
					  @"value" : @{@"@type" : @"optionValueBoolean", @"value" : @YES}}];
	[c handleUpdate:@{@"@type" : @"updateOption", @"name" : @"is_premium",
					  @"value" : @{@"@type" : @"optionValueEmpty"}}];

	XCTAssertEqual(TGOptionBoolean("is_premium", 0), 0);
	XCTAssertEqual(TGOptionBoolean("is_premium", 1), 1);
	XCTAssertEqual(TGOptionCount(), (size_t)0);
}

- (void)testOption_AWrongTypeIsNotAnswered {
	// A limit read as a boolean would silently come back true.
	TGOptionReset();
	TGOptionSetInteger("message_caption_length_max", 1024);
	XCTAssertEqual(TGOptionBoolean("message_caption_length_max", 0), 0);
	XCTAssertEqual(TGOptionInteger("is_premium", -1), -1LL);
}

- (void)testOption_ServerClockIsTakenOnlyWhenItDisagreesEnough {
	TGOptionStore store;
	store.noteServerTime(1700000000, 1700000000 + 5);
	XCTAssertEqual(store.clockOffset(), 0);   // round trip, not drift

	store.noteServerTime(1700000000, 1600000000);
	XCTAssertEqual(store.clockOffset(), 100000000);
	XCTAssertEqual(store.now(1600000000), 1700000000LL);

	// A device ahead of the server gets a negative offset, not a clamp.
	store.noteServerTime(1700000000, 1700003600);
	XCTAssertEqual(store.clockOffset(), -3600);

	store.noteServerTime(0, 1700000000);
	XCTAssertEqual(store.clockOffset(), -3600);  // nonsense is ignored
}

- (void)testOption_UnixTimeArrivesAsAnOptionAndMovesTheClock {
	TGClient *c = U();
	long long device = (long long)time(NULL);
	[c handleUpdate:@{@"@type" : @"updateOption", @"name" : @"unix_time",
					  @"value" : @{@"@type" : @"optionValueInteger",
								   @"value" : [NSString stringWithFormat:@"%lld", device + 7200]}}];

	XCTAssertTrue(TGOptionClockOffset() > 7100 && TGOptionClockOffset() < 7300);
	XCTAssertTrue(TGOptionNow() >= device + 7100);
	TGOptionReset();
}

// ─── downloads and full info ─────────────────────────────────────────────────

- (void)testDownloadUpdates_EachOnePostsTheListNotification {
	TGClient *c = U();
	__block int posts = 0;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGDownloadsChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ posts++; }];

	[c handleUpdate:@{@"@type" : @"updateFileAddedToDownloads",
					  @"file_download" : @{@"@type" : @"fileDownload",
										   @"file_id" : @(3)}}];
	[c handleUpdate:@{@"@type" : @"updateFileDownload", @"file_id" : @(3),
					  @"complete_date" : @(1700000000)}];
	[c handleUpdate:@{@"@type" : @"updateFileDownloads", @"total_size" : @"100",
					  @"total_count" : @(1), @"downloaded_size" : @"100"}];
	[c handleUpdate:@{@"@type" : @"updateFileRemovedFromDownloads",
					  @"file_id" : @(3)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(posts, 4);
}

- (void)testFullInfo_NamesThePeerItBelongsTo {
	TGClient *c = U();
	NSMutableArray *seen = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGFullInfoChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[seen addObject:@[n.userInfo[@"kind"], n.userInfo[@"id"]]];
	}];

	[c handleUpdate:@{@"@type" : @"updateUserFullInfo", @"user_id" : @(55),
					  @"user_full_info" : @{@"@type" : @"userFullInfo",
											@"bio" : @{@"text" : @"hi"}}}];
	[c handleUpdate:@{@"@type" : @"updateSupergroupFullInfo",
					  @"supergroup_id" : @(66),
					  @"supergroup_full_info" : @{@"@type" : @"supergroupFullInfo",
												  @"member_count" : @(12)}}];
	[c handleUpdate:@{@"@type" : @"updateBasicGroupFullInfo",
					  @"basic_group_id" : @(77),
					  @"basic_group_full_info" : @{@"@type" : @"basicGroupFullInfo"}}];
	// updateBasicGroup carries the group itself, with the id one level down.
	[c handleUpdate:@{@"@type" : @"updateBasicGroup",
					  @"basic_group" : @{@"@type" : @"basicGroup", @"id" : @(88),
										 @"member_count" : @(3)}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(seen, (@[@[@"user", @(55)], @[@"supergroup", @(66)],
								   @[@"basicGroup", @(77)], @[@"basicGroup", @(88)]]));
}

- (void)testFullInfo_WithoutAnIdNothingIsPosted {
	TGClient *c = U();
	__block int posts = 0;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGFullInfoChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ posts++; }];
	[c handleUpdate:@{@"@type" : @"updateUserFullInfo"}];
	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(posts, 0);
}

// ─── reactions, sticker lists, membership ────────────────────────────────────

- (void)testInteractionInfo_IsCoalescedIntoOneNudgePerChat {
	TGClient *c = U();
	NSMutableArray *nudged = [NSMutableArray array];
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0) [nudged addObject:@(chatId)];
	};

	// A crowd reacting to one post, plus a second post in the same chat.
	for (int i = 0; i < 20; i++){
		[c handleUpdate:@{@"@type" : @"updateMessageInteractionInfo",
						  @"chat_id" : @(4), @"message_id" : @(100),
						  @"interaction_info" : @{@"@type" : @"messageInteractionInfo",
												  @"view_count" : @(i)}}];
	}
	[c handleUpdate:@{@"@type" : @"updateMessageInteractionInfo",
					  @"chat_id" : @(4), @"message_id" : @(200),
					  @"interaction_info" : @{@"@type" : @"messageInteractionInfo"}}];
	[c handleUpdate:@{@"@type" : @"updateMessageInteractionInfo",
					  @"chat_id" : @(5), @"message_id" : @(300),
					  @"interaction_info" : @{@"@type" : @"messageInteractionInfo"}}];

	// Nothing has been delivered yet - that is the point of the window.
	XCTAssertEqual(nudged.count, (NSUInteger)0);
	XCTAssertEqual([c.updateCoalescer pendingCount], (NSUInteger)2);

	[c.updateCoalescer flushNow];
	c.onMessage = nil;

	// Two chats, 21 messages, two nudges.
	XCTAssertEqual(nudged.count, (NSUInteger)2);
	XCTAssertTrue([nudged containsObject:@(4)] && [nudged containsObject:@(5)]);
}

- (void)testStickerLists_EveryListPostsTheSameNotification {
	TGClient *c = U();
	__block int posts = 0;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGStickerListsChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ posts++; }];

	for (NSString *type in @[@"updateInstalledStickerSets", @"updateTrendingStickerSets",
							 @"updateRecentStickers", @"updateFavoriteStickers",
							 @"updateSavedAnimations", @"updateStickerSet"]){
		[c handleUpdate:@{@"@type" : type, @"sticker_ids" : @[@(1)]}];
	}

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(posts, 6);
}

- (void)testMembership_NamesTheChatAndSkipsAnUpdateWithoutOne {
	TGClient *c = U();
	NSMutableArray *chats = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGChatMembersChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[chats addObject:n.userInfo[@"chatId"]];
	}];

	[c handleUpdate:@{@"@type" : @"updateChatMember", @"chat_id" : @(12),
					  @"actor_user_id" : @(1), @"new_chat_member" : @{}}];
	[c handleUpdate:@{@"@type" : @"updateChatPendingJoinRequests", @"chat_id" : @(12),
					  @"pending_join_requests" : @{@"total_count" : @(2)}}];
	[c handleUpdate:@{@"@type" : @"updateNewChatJoinRequest", @"chat_id" : @(13),
					  @"request" : @{@"user_id" : @(9)}}];
	[c handleUpdate:@{@"@type" : @"updateChatMember"}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(chats, (@[@(12), @(12), @(13)]));
}

// ─── group facts, notifications, topics, archive ─────────────────────────────

- (void)testGroupFacts_MergeAndTellTheProfile {
	TGClient *c = U();
	NSMutableArray *kinds = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGFullInfoChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[kinds addObject:@[n.userInfo[@"kind"], n.userInfo[@"id"]]];
	}];

	[c handleUpdate:@{@"@type" : @"updateChatPermissions", @"chat_id" : @(20),
					  @"permissions" : @{@"@type" : @"chatPermissions",
										 @"can_send_basic_messages" : @NO}}];
	[c handleUpdate:@{@"@type" : @"updateChatMessageAutoDeleteTime",
					  @"chat_id" : @(20), @"message_auto_delete_time" : @(86400)}];
	[c handleUpdate:@{@"@type" : @"updateChatOnlineMemberCount",
					  @"chat_id" : @(20), @"online_member_count" : @(7)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	NSMutableDictionary *chat = c.chatsById[@(20)];
	XCTAssertEqualObjects(chat[@"permissions"][@"can_send_basic_messages"], @NO);
	XCTAssertEqualObjects(chat[@"autoDeleteTime"], @(86400));
	XCTAssertEqualObjects(chat[@"onlineMembers"], @(7));
	XCTAssertEqualObjects(kinds, (@[@[@"chat", @(20)], @[@"chat", @(20)],
									@[@"chat", @(20)]]));
}

- (void)testRemovedFromList_ClearsTheOrderForThatListOnly {
	TGClient *c = U();
	[c handleUpdate:@{@"@type" : @"updateChatPosition", @"chat_id" : @(21),
					  @"position" : @{@"@type" : @"chatPosition",
									  @"list" : @{@"@type" : @"chatListMain"},
									  @"order" : @"500"}}];
	XCTAssertEqualObjects(c.chatsById[@(21)][@"order"], @(500));

	[c handleUpdate:@{@"@type" : @"updateChatRemovedFromList", @"chat_id" : @(21),
					  @"chat_list" : @{@"@type" : @"chatListArchive"}}];
	XCTAssertEqualObjects(c.chatsById[@(21)][@"order"], @(500));  // not this list

	[c handleUpdate:@{@"@type" : @"updateChatRemovedFromList", @"chat_id" : @(21),
					  @"chat_list" : @{@"@type" : @"chatListMain"}}];
	XCTAssertEqualObjects(c.chatsById[@(21)][@"order"], @(0));
}

- (void)testPollVotes_CountOnTheChatAndTheMessageCoalesced {
	TGClient *c = U();
	NSMutableArray *nudged = [NSMutableArray array];
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0) [nudged addObject:@(chatId)];
	};
	[c handleUpdate:@{@"@type" : @"updateChatUnreadPollVoteCount",
					  @"chat_id" : @(22), @"unread_poll_vote_count" : @(4)}];
	[c handleUpdate:@{@"@type" : @"updateMessageContainsUnreadPollVotes",
					  @"chat_id" : @(22), @"message_id" : @(900),
					  @"contains_unread_poll_votes" : @YES,
					  @"unread_poll_vote_count" : @(4)}];
	[c.updateCoalescer flushNow];
	c.onMessage = nil;

	XCTAssertEqualObjects(c.chatsById[@(22)][@"unreadPollVotes"], @(4));
	XCTAssertEqualObjects(nudged, @[@(22)]);
}

- (void)testNotificationSettings_BothShapesPostOnce {
	TGClient *c = U();
	__block int posts = 0;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGNotificationSettingsChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ posts++; }];

	[c handleUpdate:@{@"@type" : @"updateScopeNotificationSettings",
					  @"scope" : @{@"@type" : @"notificationSettingsScopeGroupChats"},
					  @"notification_settings" : @{@"mute_for" : @(0)}}];
	[c handleUpdate:@{@"@type" : @"updateChatDefaultDisableNotification",
					  @"chat_id" : @(23), @"default_disable_notification" : @YES}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(posts, 2);
	// The per-chat one is also a chat field.
	XCTAssertEqualObjects(c.chatsById[@(23)][@"defaultSilent"], @YES);
}

- (void)testForumTopics_NameTheirChatEvenWhenItIsNestedInTheInfo {
	TGClient *c = U();
	NSMutableArray *chats = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGForumTopicsChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[chats addObject:n.userInfo[@"chatId"] ?: @(0)];
	}];

	[c handleUpdate:@{@"@type" : @"updateForumTopic", @"chat_id" : @(24),
					  @"forum_topic_id" : @(2), @"is_pinned" : @YES}];
	[c handleUpdate:@{@"@type" : @"updateForumTopicInfo",
					  @"info" : @{@"@type" : @"forumTopicInfo", @"chat_id" : @(25),
								  @"name" : @"General"}}];
	[c handleUpdate:@{@"@type" : @"updateTopicMessageCount", @"chat_id" : @(26),
					  @"message_count" : @(3)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(chats, (@[@(24), @(25), @(26)]));
}

// ─── chat fields, reactions, the global unread total ─────────────────────────

- (void)testChatFields_MergeIntoTheRowAndTellAnOpenProfile {
	TGClient *c = U();
	NSMutableArray *kinds = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGFullInfoChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[kinds addObject:@[n.userInfo[@"kind"], n.userInfo[@"id"]]];
	}];

	[c handleUpdate:@{@"@type" : @"updateChatHasProtectedContent",
					  @"chat_id" : @(30), @"has_protected_content" : @YES}];
	[c handleUpdate:@{@"@type" : @"updateChatHasScheduledMessages",
					  @"chat_id" : @(30), @"has_scheduled_messages" : @YES}];
	[c handleUpdate:@{@"@type" : @"updateChatViewAsTopics",
					  @"chat_id" : @(30), @"view_as_topics" : @NO}];
	[c handleUpdate:@{@"@type" : @"updateChatIsTranslatable",
					  @"chat_id" : @(30), @"is_translatable" : @YES}];
	[c handleUpdate:@{@"@type" : @"updateChatTheme", @"chat_id" : @(30),
					  @"theme" : @{@"@type" : @"chatTheme", @"theme_name" : @"day"}}];
	[c handleUpdate:@{@"@type" : @"updateChatMessageSender", @"chat_id" : @(30),
					  @"message_sender_id" : @{@"@type" : @"messageSenderUser",
											   @"user_id" : @(3)}}];
	// A null block list is an unblock: the row has to lose the old value,
	// the way a removed photo clears the avatar.
	[c handleUpdate:@{@"@type" : @"updateChatBlockList", @"chat_id" : @(31),
					  @"block_list" : @{@"@type" : @"blockListMain"}}];
	[c handleUpdate:@{@"@type" : @"updateChatBlockList", @"chat_id" : @(31)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	NSMutableDictionary *chat = c.chatsById[@(30)];
	XCTAssertEqualObjects(chat[@"hasProtectedContent"], @YES);
	XCTAssertEqualObjects(chat[@"hasScheduledMessages"], @YES);
	XCTAssertEqualObjects(chat[@"viewAsTopics"], @NO);
	XCTAssertEqualObjects(chat[@"isTranslatable"], @YES);
	XCTAssertEqualObjects(chat[@"chatTheme"][@"theme_name"], @"day");
	XCTAssertEqualObjects(chat[@"messageSender"][@"user_id"], @(3));
	XCTAssertNil(c.chatsById[@(31)][@"blockList"]);   // unblocked: gone, not YES
	// One announcement per update, each pointing at its chat.
	XCTAssertTrue(kinds.count >= 7, @"kinds: %@", kinds);
}

- (void)testMessageReactions_CoalesceIntoOneNudgePerChat {
	TGClient *c = U();
	NSMutableArray *nudged = [NSMutableArray array];
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0) [nudged addObject:@(chatId)];
	};

	// A burst of reaction activity on several messages of one chat.
	for (int i = 0; i < 5; i++){
		[c handleUpdate:@{@"@type" : @"updateMessageReactions",
						  @"chat_id" : @(40), @"message_id" : @(100 + i),
						  @"reactions" : @[@{@"@type" : @"messageReaction",
											 @"reaction_type" : @{@"@type" : @"reactionTypeEmoji",
																  @"emoji" : @"🔥"}}]}];
	}
	[c handleUpdate:@{@"@type" : @"updateMessageReaction", @"chat_id" : @(40),
					  @"message_id" : @(100), @"date" : @(1700000000),
					  @"actor_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(9)},
					  @"old_reaction_types" : @[], @"new_reaction_types" : @[]}];
	[c handleUpdate:@{@"@type" : @"updateMessageLiveLocationViewed",
					  @"chat_id" : @(40), @"message_id" : @(600)}];
	// The second chat's nudge is separate.
	[c handleUpdate:@{@"@type" : @"updateAnimatedEmojiMessageClicked",
					  @"chat_id" : @(41), @"message_id" : @(700),
					  @"emoji" : @"🍫", @"sticker" : @{@"@type" : @"file", @"id" : @(1)}}];
	[c.updateCoalescer flushNow];
	c.onMessage = nil;

	// Seven message-level updates, two chats, two nudges after the window.
	XCTAssertEqual(nudged.count, (NSUInteger)2);
	XCTAssertTrue([nudged containsObject:@(40)] && [nudged containsObject:@(41)]);
}

- (void)testActiveLiveLocationMessages_NudgeEachRidingChat {
	TGClient *c = U();
	NSMutableArray *nudged = [NSMutableArray array];
	c.onMessage = ^(int64_t chatId, NSDictionary *message, int64_t deletedId){
		if (!message && deletedId == 0) [nudged addObject:@(chatId)];
	};

	[c handleUpdate:@{@"@type" : @"updateActiveLiveLocationMessages",
					  @"messages" : @[@{@"@type" : @"message", @"id" : @(1),
										@"chat_id" : @(50)},
									  @{@"@type" : @"message", @"id" : @(2),
										@"chat_id" : @(50)},
									  @{@"@type" : @"message", @"id" : @(3),
										@"chat_id" : @(51)}]}];
	[c.updateCoalescer flushNow];
	c.onMessage = nil;

	// Three riders, two chats, one nudge per chat.
	XCTAssertEqual(nudged.count, (NSUInteger)2);
	XCTAssertTrue([nudged containsObject:@(50)] && [nudged containsObject:@(51)]);
}

- (void)testUnreadMessageCount_IsTheBadgeOnlyForTheMainList {
	TGClient *c = U();
	NSMutableArray *totals = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGUnreadTotalChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[totals addObject:n.userInfo[@"count"]];
	}];

	// Folders carry their own slices; shrinking the badge for them is a lie.
	[c handleUpdate:@{@"@type" : @"updateUnreadMessageCount",
					  @"chat_list" : @{@"@type" : @"chatListFolder",
									   @"chat_folder_id" : @(2)},
					  @"unread_count" : @(9), @"unread_unmuted_count" : @(9)}];
	// The main list speaks with a null chat list, and a zero is a real count.
	[c handleUpdate:@{@"@type" : @"updateUnreadMessageCount",
					  @"chat_list" : [NSNull null],
					  @"unread_count" : @(7), @"unread_unmuted_count" : @(3)}];
	[c handleUpdate:@{@"@type" : @"updateUnreadMessageCount",
					  @"unread_count" : @(0)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(totals, (@[@(3), @(0)]));
}

- (void)testNotificationSettings_TheReactionAndSoundListsTellTheSamePage {
	TGClient *c = U();
	__block int posts = 0;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGNotificationSettingsChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){ posts++; }];

	[c handleUpdate:@{@"@type" : @"updateReactionNotificationSettings",
					  @"notification_settings" : @{@"@type" : @"reactionNotificationSettings",
												   @"show_reactions" : @YES}}];
	[c handleUpdate:@{@"@type" : @"updateSavedNotificationSounds",
					  @"notification_sound_ids" : @[@(5)]}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(posts, 2);
}

- (void)testChatJoinResult_HandsTheChatToTheMembersSheet {
	TGClient *c = U();
	NSMutableArray *chats = [NSMutableArray array];
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGChatMembersChangedNotification object:nil
			queue:nil usingBlock:^(NSNotification *n){
		[chats addObject:n.userInfo[@"chatId"]];
	}];

	[c handleUpdate:@{@"@type" : @"updateChatJoinResult", @"query_id" : @"11",
					  @"chat_id" : @(60),
					  @"result" : @{@"@type" : @"text", @"text" : @"approved"}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(chats, (@[@(60)]));
}

// ─── server defaults the screens now read ───────────────────────────────────

- (void)testDefaultReactionType_LeadsThePicker {
	TGClient *c = U();
	XCTAssertNil(c.defaultReactionEmoji);

	[c handleUpdate:@{@"@type" : @"updateDefaultReactionType",
					  @"reaction_type" : @{@"@type" : @"reactionTypeEmoji",
										   @"emoji" : @"🔥"}}];

	XCTAssertEqualObjects(c.defaultReactionEmoji, @"🔥");
}

- (void)testAnimationSearch_NamesTheProviderAndItsEmoji {
	TGClient *c = U();
	XCTAssertEqualObjects(c.animationSearchProvider, @"gif");
	XCTAssertEqual(c.animationSearchEmojis.count, (NSUInteger)0);

	[c handleUpdate:@{@"@type"    : @"updateAnimationSearchParameters",
					  @"provider" : @"gifbot",
					  @"emojis"   : @[@"👍", @"😂"]}];

	XCTAssertEqualObjects(c.animationSearchProvider, @"gifbot");
	XCTAssertEqualObjects(c.animationSearchEmojis, (@[@"👍", @"😂"]));
}

/// The protocol asks for a popup: these belong to no chat, so the window is
/// the only surface that can show them.
- (void)testServiceNotification_ArrivesWithItsText {
	TGClient *c = U();
	__block NSString *text = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGServiceNotificationReceivedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){ text = n.userInfo[@"text"]; }];

	[c handleUpdate:@{@"@type" : @"updateServiceNotification",
					  @"type"  : @"AUTH_KEY_UNREGISTERED",
					  @"content" : @{@"@type" : @"messageText",
									 @"text" : @{@"@type" : @"formattedText",
												 @"text" : @"Sign in again."}}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(text, @"Sign in again.");
}

- (void)testTermsOfService_ArrivesWithItsIdAndText {
	TGClient *c = U();
	__block NSDictionary *info = nil;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGTermsOfServiceReceivedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){ info = n.userInfo; }];

	[c handleUpdate:@{@"@type" : @"updateTermsOfService",
					  @"terms_of_service_id" : @"tos-1",
					  @"terms_of_service" : @{
						  @"@type" : @"termsOfService",
						  @"text" : @{@"@type" : @"formattedText",
									  @"text" : @"Read this."},
						  @"min_user_age" : @(13),
						  @"show_popup" : @YES}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqualObjects(info[@"id"], @"tos-1");
	XCTAssertEqualObjects(info[@"text"], @"Read this.");
}

- (void)testPrivacyRulesChange_TellsThePrivacyPage {
	TGClient *c = U();
	__block BOOL told = NO;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGPrivacyRulesChangedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){ told = YES; }];

	[c handleUpdate:@{@"@type" : @"updateUserPrivacySettingRules",
					  @"setting" : @{@"@type" : @"userPrivacySettingShowStatus"},
					  @"rules" : @{@"@type" : @"userPrivacySettingRules"}}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertTrue(told);
}

- (void)testUnconfirmedSession_TellsTheDevicesList {
	TGClient *c = U();
	__block BOOL told = NO;
	id token = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGSessionsChangedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){ told = YES; }];

	[c handleUpdate:@{@"@type" : @"updateUnconfirmedSession",
					  @"session" : @{@"@type" : @"unconfirmedSession",
									 @"date" : @(1)},
					  @"unconfirmed_session_count" : @(1)}];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertTrue(told);
}

@end
