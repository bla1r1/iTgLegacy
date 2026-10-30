// TGClientChatsTests.m — regression tests for dialog (chat list) loading.
//
// Zone this covers (frequently-fixed, never tested before): how TGClient
// turns TDLib's updateNewChat / updateChatPosition / updateLastMessage
// stream into the ordered chat lists, then keeps them in step.
//
// Compiles against the real src/Core/TGClient.m and its +Chats/+Messages
// categories: requests only land in the outbox (tdjson is never loaded on
// the host), and answers are pushed in through the same parsing entry
// points the receive loop uses.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

static TGClient *T(void) {
	TGClient *c = TGClient.shared;
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	[c.forumSupergroups removeAllObjects];
	c.chats = @[];
	c.archivedChats = @[];
	c.folders = @[];
	c.me = nil;
	c.chatListComplete = NO;
	c.loadChatsAttempts = 0;
	c.onChatsChanged = nil;
	c.onArchiveChanged = nil;
	return c;
}

/// A position as TDLib sends it: order is an int64 delivered as a string.
static NSDictionary *pos(NSString *listType, long long order, BOOL pinned) {
	NSMutableDictionary *d = [@{@"@type" : @"chatPosition",
			@"list"  : @{@"@type" : listType},
			@"order" : [NSString stringWithFormat:@"%lld", order]} mutableCopy];
	if (pinned)
		d[@"is_pinned"] = @YES;
	return d;
}

static NSDictionary *chatDict(int64_t id_, NSString *title, long long order) {
	return @{ @"@type" : @"chat",
			  @"id"    : [NSNumber numberWithLongLong:id_],
			  @"title" : title ?: @"",
			  @"positions" : @[pos(@"chatListMain", order, NO)],
			  @"last_message" : @{
					  @"@type" : @"message", @"id" : @(order), @"date" : @(order),
					  @"is_outgoing" : @NO,
					  @"content" : @{@"@type" : @"messageText",
									 @"text"  : @{@"@type" : @"formattedText",
												 @"text"  : @"last"}} } };
}

/// updateNewChat-shaped update, as TDLib streams when loadChats runs.
static void deliverNewChat(TGClient *c, NSDictionary *chat) {
	[c handleUpdate:@{@"@type" : @"updateNewChat", @"chat" : chat}];
}

static NSMutableDictionary *knownChat(TGClient *c, int64_t id_) {
	NSMutableDictionary *info = c.chatsById[@(id_)];
	if (!info){
		info = [NSMutableDictionary dictionary];
		info[@"id"] = @(id_);
		c.chatsById[@(id_)] = info;
	}
	return info;
}

static void giveLastChatMessage(TGClient *c, int64_t chatId, NSString *text,
								long long date) {
	[c applyChatUpdate:@{@"@type" : @"updateChatLastMessage",
			@"chat_id" : @(chatId),
			@"last_message" : @{
				@"@type"     : @"message",
				@"id"        : @(date),
				@"date"      : @(date),
				@"is_outgoing" : @NO,
				@"content"   : @{@"@type" : @"messageText",
								 @"text"  : @{@"@type" : @"formattedText",
											 @"text"  : text}},
			}}];
}

static NSDictionary *chatInfo(NSArray *chats, int64_t id_) {
	for (NSDictionary *info in chats)
		if ([info[@"id"] longLongValue] == id_)
			return info;
	return nil;
}

static int64_t orderOf(NSArray *chats, int64_t id_) {
	NSDictionary *info = chatInfo(chats, id_);
	return [info[@"order"] longLongValue];
}

@interface TGClientChatsTests : XCTestCase
@end

@implementation TGClientChatsTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - order parsing (the int64-as-string regression)

/// chatPosition.order arrives as a string and must be compared as a number.
/// "1200000000000000000" > "900000000000000000" numerically but not as text,
/// so a string sort puts the newer chat at the bottom.
- (void)testOrderInList_ParsesIntFullWidth {
	int64_t a = TGOrderInList(@[pos(@"chatListMain", 1200000000000000000LL, NO)],
							  @"chatListMain");
	int64_t b = TGOrderInList(@[pos(@"chatListMain",  900000000000000000LL, NO)],
							  @"chatListMain");
	XCTAssertEqual(a, 1200000000000000000LL, @"value must survive the string round trip");
	XCTAssertEqual(b,  900000000000000000LL, @"value must survive the string round trip");
	XCTAssertGreaterThan(a, b, "numeric comparison");
}

- (void)testOrderInList_ListFilter {
	NSDictionary *main    = pos(@"chatListMain",    222, NO);
	NSDictionary *archive = pos(@"chatListArchive", 111, NO);
	XCTAssertEqual(TGOrderInList(@[main, archive], @"chatListArchive"), 111);
	XCTAssertEqual(TGOrderInList(@[main, archive], @"chatListMain"), 222);
	XCTAssertEqual(TGOrderInList(@[main], @"chatListFolder"), 0);
	XCTAssertEqual(TGOrderInList(@[], @"chatListMain"), 0);
}

- (void)testPinnedInMain_OnlyTheMainListCounts {
	NSDictionary *mainPinned    = pos(@"chatListMain",    5, YES);
	NSDictionary *archivePinned = pos(@"chatListArchive", 5, YES);
	XCTAssertTrue(TGPinnedInMain(@[mainPinned]));
	XCTAssertFalse(TGPinnedInMain(@[archivePinned]));
	XCTAssertFalse(TGPinnedInMain(@[]));
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - rebuildChats: ordering

- (void)testRebuildChats_NewestFirstRegardlessOfMergeOrder {
	TGClient *c = T();
	// Merged in the wrong order on purpose: the older chat lands first, as
	// TDLib batches respond in load order.
	deliverNewChat(c, chatDict(100, @"Old",   1000000000000000000LL));
	deliverNewChat(c, chatDict(200, @"Newer", 1200000000000000000LL));
	XCTAssertEqual((NSInteger)c.chats.count, 2);
	XCTAssertEqual(orderOf(c.chats, 200), 1200000000000000000LL,
			@"the newer chat must sit first despite its merge order");
	NSArray *ids = [c.chats valueForKey:@"id"];
	XCTAssertEqualObjects(ids.firstObject, @200);
}

- (void)testRebuildChats_NumericallyNotLexicographically {
	// The classic regression: the same chat pair sorted as strings would
	// come out backwards.
	TGClient *c = T();
	deliverNewChat(c, chatDict(1, @"1.2e18", 1200000000000000000LL));
	deliverNewChat(c, chatDict(2, @"9e17",    900000000000000000LL));
	XCTAssertEqual(orderOf(c.chats, 1), 1200000000000000000LL);
	XCTAssertTrue([c.chats.firstObject[@"id"] longLongValue] == 1,
			@"1200000000000000000 must outrank 900000000000000000");
}

- (void)testRebuildChats_MainVsArchiveLists {
	TGClient *c = T();
	deliverNewChat(c, chatDict(10, @"Main chat", 300));

	// A chat sitting in the archive with no message yet is a phantom.
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(20), @"title" : @"Archive chat",
			@"positions"    : @[pos(@"chatListArchive", 300, NO)] });
	XCTAssertEqual((NSInteger)c.archivedChats.count, 0,
			@"an empty archived chat must not be listed");
	XCTAssertEqual((NSInteger)c.chats.count, 1);

	giveLastChatMessage(c, 20, @"hi", 50);
	XCTAssertEqual((NSInteger)c.chats.count, 1);
	XCTAssertEqual((NSInteger)c.archivedChats.count, 1);
	XCTAssertEqual([chatInfo(c.archivedChats, 20)[@"archiveOrder"] longLongValue], 300);
}

- (void)testRebuildChats_PinnedChatSurvivesEvenWithNoHistory {
	// Pinned chats have no "last message" yet — pinning keeps them on the list.
	TGClient *c = T();
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(30), @"title" : @"Fresh",
			@"positions" : @[pos(@"chatListMain", 400, YES)] });
	XCTAssertEqual((NSInteger)c.chats.count, 1,
			@"a pinned chat must be listed before any message lands");
}

- (void)testRebuildChats_PhantomEmptyChatHidden {
	// Deleted/transferred groups come back as empty chats; the list must
	// not show rows with no name, message, pin or draft.
	TGClient *c = T();
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(40), @"title" : @"Empty husk",
			@"positions" : @[pos(@"chatListMain", 500, NO)] });
	XCTAssertEqual((NSInteger)c.chats.count, 0);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - mergeChat semantics

- (void)testMergeChat_KeepsExistingFieldsOnReMerge {
	TGClient *c = T();
	deliverNewChat(c, chatDict(50, @"Renamed", 600));
	// A later batch without positions last_message etc must not wipe the row.
	[c mergeChat:@{@"@type" : @"chat", @"id" : @(50)}];
	XCTAssertEqualObjects(chatInfo(c.chats, 50)[@"title"], @"Renamed");
	XCTAssertEqual(orderOf(c.chats, 50), 600);
}

- (void)testMergeChat_GroupKindIsFlaggedForGroupsOnly {
	TGClient *c = T();
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(60), @"title" : @"Private",
			@"type"      : @{@"@type" : @"chatTypePrivate"},
			@"positions" : @[pos(@"chatListMain", 700, NO)] });
	NSMutableDictionary *info = knownChat(c, 60);
	[info removeObjectForKey:@"isGroup"];
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(60), @"title" : @"Private",
			@"type"      : @{@"@type" : @"chatTypePrivate"},
			@"positions" : @[pos(@"chatListMain", 700, NO)] });
	XCTAssertFalse([knownChat(c, 60)[@"isGroup"] boolValue],
			@"a private chat is not a group");

	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(61), @"title" : @"Basic group",
			@"type"      : @{@"@type" : @"chatTypeBasicGroup"},
			@"positions" : @[pos(@"chatListMain", 701, NO)] });
	XCTAssertTrue([knownChat(c, 61)[@"isGroup"] boolValue],
			@"basic groups need sender names in the preview");
}

- (void)testMergeChat_SupergroupAsksForItsForumFlag {
	TGClient *c = T();
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(62), @"title" : @"Supergroup",
			@"type" : @{@"@type" : @"chatTypeSupergroup", @"supergroup_id" : @(7)},
			@"positions" : @[pos(@"chatListMain", 702, NO)] });
	// The getSupergroup request must have gone out, queued in the outbox.
	__block BOOL asked = NO;
	for (NSData *d in c.outbox){
		NSString *json = [[NSString alloc] initWithData:d
				encoding:NSUTF8StringEncoding];
		if ([json containsString:@"getSupergroup"])
			asked = YES;
	}
	XCTAssertTrue(asked, @"outbox: %@", [c.outbox componentsJoinedByString:@","]);
	NSDictionary *info = knownChat(c, 62);
	XCTAssertEqualObjects(info[@"supergroupId"], @7);
}

- (void)testMergeChat_ForumFlagArrivesAndApplies {
	TGClient *c = T();
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(63), @"title" : @"Forum",
			@"type" : @{@"@type" : @"chatTypeSupergroup", @"supergroup_id" : @(8)},
			@"positions" : @[pos(@"chatListMain", 703, NO)] });
	// The answer TDLib would give: the supergroup IS a forum.
	[c handleUpdate:@{@"@type" : @"updateSupergroup",
			@"supergroup" : @{@"id" : @(8), @"is_forum" : @YES}}];
	XCTAssertTrue([knownChat(c, 63)[@"isForum"] boolValue],
			@"the arriving forum flag must reach every chat of that supergroup");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - saved messages

- (void)testMergeChat_SavedMessagesRowIsMarked {
	TGClient *c = T();
	c.me = @{@"id" : @777};

	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(777), @"title" : @"Dmytro",
			@"type"      : @{@"@type" : @"chatTypePrivate"},
			@"positions" : @[pos(@"chatListMain", 900, NO)],
			@"last_message" : @{
					@"@type" : @"message", @"id" : @(5), @"date" : @(5),
					@"is_outgoing" : @YES,
					@"content" : @{@"@type" : @"messageText",
								   @"text" : @{@"@type" : @"formattedText",
											   @"text" : @"keep this"}}} });

	NSDictionary *info = knownChat(c, 777);
	XCTAssertEqualObjects(info[@"title"], @"Saved Messages",
			@"the chat with yourself is Saved Messages");
	XCTAssertTrue([info[@"isSaved"] boolValue]);
	XCTAssertEqualObjects(info[@"lastAuthor"], nil,
			@"in Saved Messages nothing is 'You'");
}

/// In a group the row shows who spoke last; your own messages read "You"
/// everywhere but Saved Messages.
- (void)testPreviewForLastMessage_OutgoingMarksYouInPrivateChat {
	TGClient *c = T();
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(80), @"title" : @"Peer",
			@"type"      : @{@"@type" : @"chatTypePrivate"},
			@"positions" : @[pos(@"chatListMain", 1000, NO)],
			@"last_message" : @{
					@"@type" : @"message", @"id" : @(6), @"date" : @(6),
					@"is_outgoing" : @YES,
					@"content" : @{@"@type" : @"messageText",
								   @"text" : @{@"text" : @"hello"}}} });
	NSDictionary *info = knownChat(c, 80);
	XCTAssertEqualObjects(info[@"lastAuthor"], @"You");
	XCTAssertEqualObjects(info[@"previewText"], @"hello",
			@"previewText stays bare; the list prefixes the author itself");
}

- (void)testPreviewForLastMessage_GroupShowsTheSpeaker {
	TGClient *c = T();
	[c.usersById setObject:@"Nazar" forKey:@(555)];
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(81), @"title" : @"Group",
			@"type"      : @{@"@type" : @"chatTypeBasicGroup"},
			@"positions" : @[pos(@"chatListMain", 1001, NO)],
			@"last_message" : @{
					@"@type" : @"message", @"id" : @(7), @"date" : @(7),
					@"is_outgoing" : @NO,
					@"sender_id"   : @{@"user_id" : @555},
					@"content" : @{@"@type" : @"messageText",
								   @"text" : @{@"text" : @"privit"}}} });
	NSDictionary *info = knownChat(c, 81);
	XCTAssertEqualObjects(info[@"lastAuthor"], @"Nazar");
	XCTAssertEqualObjects(info[@"text"], @"Nazar: privit");
}

- (void)testPreviewForLastMessage_UnknownSpeakerFetchesThenRebuilds {
	TGClient *c = T();
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	__block BOOL changed = NO;
	c.onChatsChanged = ^{ changed = YES; };
	deliverNewChat(c, @{ @"@type" : @"chat",
			@"id" : @(82), @"title" : @"Group",
			@"type"      : @{@"@type" : @"chatTypeBasicGroup"},
			@"positions" : @[pos(@"chatListMain", 1002, NO)],
			@"last_message" : @{
					@"@type" : @"message", @"id" : @(8), @"date" : @(8),
					@"is_outgoing" : @NO,
					@"sender_id"   : @{@"user_id" : @999},
					@"content" : @{@"@type" : @"messageText",
								   @"text" : @{@"text" : @"?"}}} });
	// Name not known: no "someone" guess, and the rebuild fires so the row
	// fills in once the fetch answers.
	NSDictionary *info = knownChat(c, 82);
	XCTAssertNil(info[@"lastAuthor"],
			@"an unknown speaker must not be invented");
	XCTAssertEqualObjects(info[@"previewText"], @"?");

	// The fetch went out as a getUser; its answer is what rebuilds the list,
	// and the name then rides the row.
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSString *json = [[NSString alloc] initWithData:d
											   encoding:NSUTF8StringEncoding];
		NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
		NSDictionary *request = [NSJSONSerialization JSONObjectWithData:
				[trimmed dataUsingEncoding:NSUTF8StringEncoding]
						options:0 error:nil];
		if (request[@"@extra"]){
			sent = request;
			break;
		}
	}
	XCTAssertEqualObjects(sent[@"@type"], @"getUser");
	XCTAssertEqual([sent[@"user_id"] longLongValue], 999LL);
	NSMutableDictionary *reply = [@{ @"@type"     : @"user",
									 @"id"        : @(999),
									 @"first_name": @"Taras",
									 @"last_name" : @"" } mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
	XCTAssertTrue(changed, @"the answered fetch leads to a rebuild");
	// The name the fetch brought home, for the next render to use.
	XCTAssertEqualObjects(c.usersById[@(999)], @"Taras");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - preview text shapes

- (void)testMessagePreview_AllTheContentTypes {
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messageText",
			@"text" : @{@"text" : @"word"}}}), @"word");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messagePhoto"}}),
						  @"Photo");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messageSticker"}}),
						  @"Sticker");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messageVoiceNote"}}),
						  @"Voice message");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messageCall"}}),
						  @"Call");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messagePinMessage"}}),
						  @"pinned a message");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messageChatAddMembers"}}),
						  @"added a member");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messagePoll"}}),
						  @"Poll");
	// Everything else becomes a phrase of its own type name.
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{@"@type" : @"messageGameScore"}}),
						  @"Game score");
	XCTAssertEqualObjects(TGMessagePreview(@{@"content" : @{}}), @"");
	XCTAssertEqualObjects(TGMessagePreview(@{}), @"");
}

- (void)testPhraseFromTypeName_CamelCaseToWords {
	XCTAssertEqualObjects(TGPhraseFromTypeName(@"messageVideoChatStarted"),
						  @"Video chat started");
	XCTAssertEqualObjects(TGPhraseFromTypeName(@"message"), @"Message");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - applyChatUpdate: keeping rows in step

- (void)testApplyChatUpdate_ReadOutboxPostsNotification {
	TGClient *c = T();
	deliverNewChat(c, chatDict(90, @"Chat", 1100));

	__block NSNumber *notified = nil;
	id observer = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGChatReadOutboxChangedNotification
			object:nil
			queue:nil
			usingBlock:^(NSNotification *n){ notified = n.userInfo[@"chatId"]; }];

	[c applyChatUpdate:@{@"@type" : @"updateChatReadOutbox",
			@"chat_id" : @(90),
			@"last_read_outbox_message_id" : @(4242)}];
	[[NSNotificationCenter defaultCenter] removeObserver:observer];

	XCTAssertEqualObjects(notified, @90, @"the row that changed must be named");
	XCTAssertEqual([knownChat(c, 90)[@"readOutbox"] longLongValue], 4242);
}

- (void)testApplyChatUpdate_PositionSwitchBetweenLists {
	TGClient *c = T();
	deliverNewChat(c, chatDict(91, @"Chat", 1200));
	giveLastChatMessage(c, 91, @"hello", 10);
	XCTAssertEqual((NSInteger)c.chats.count, 1);
	XCTAssertEqual((NSInteger)c.archivedChats.count, 0);

	// The archive position arrives: row moves lists, content intact.
	[c applyChatUpdate:@{@"@type" : @"updateChatPosition",
			@"chat_id" : @(91),
			@"position" : @{@"@type" : @"chatPosition",
							@"list"  : @{@"@type" : @"chatListArchive"},
							@"order" : @"1300"}}];
	XCTAssertEqual((NSInteger)c.chats.count, 0);
	XCTAssertEqual((NSInteger)c.archivedChats.count, 1);
	XCTAssertEqualObjects(chatInfo(c.archivedChats, 91)[@"title"], @"Chat");
}

- (void)testApplyChatUpdate_UnknownChatCreatesARow {
	TGClient *c = T();
	// An update for a chat mergeChat has not seen must not be dropped.
	[c applyChatUpdate:@{@"@type" : @"updateChatPosition",
			@"chat_id" : @(92),
			@"position" : @{@"@type" : @"chatPosition",
							@"list"  : @{@"@type" : @"chatListMain"},
							@"order" : @"1400"}}];
	// The row itself is known (the header can still open it)...
	NSDictionary *info = knownChat(c, 92);
	XCTAssertNotNil(info, @"an update must never be dropped for an unknown chat");
	XCTAssertEqual([info[@"order"] longLongValue], 1400,
			@"the update's order must reach the stored row");
	// ...but with no history, no pin and no draft it stays off the list.
	XCTAssertEqual((NSInteger)c.chats.count, 0,
			@"no history, no pin, no draft: still a phantom");
}

- (void)testApplyChatUpdate_TitleAndUnreadFlow {
	TGClient *c = T();
	deliverNewChat(c, chatDict(93, @"Old title", 1500));
	giveLastChatMessage(c, 93, @"m", 1);
	[c applyChatUpdate:@{@"@type" : @"updateChatTitle",
			@"chat_id" : @(93), @"title" : @"New title"}];
	[c applyChatUpdate:@{@"@type" : @"updateChatReadInbox",
			@"chat_id" : @(93),
			@"last_read_inbox_message_id" : @(77)}];
	XCTAssertEqualObjects(knownChat(c, 93)[@"title"], @"New title");
	XCTAssertEqual([knownChat(c, 93)[@"readInbox"] longLongValue], 77);

	// unread_count rides on updateChatPosition-style updates as well.
	[c mergeChat:@{
		@"@type"  : @"chat",
		@"id"     : @(93),
		@"title"  : @"New title",
		@"unread_count" : @3,
	}];
	NSMutableDictionary *info = knownChat(c, 93);
	XCTAssertEqual([info[@"unread"] integerValue], 3,
			@"unread must ride along on the merge");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - typing action handling

- (void)testUpdateChatAction_PhrasesMapLikeTheDeviceShows {
	TGClient *c = T();
	deliverNewChat(c, chatDict(94, @"Chat", 1600));
	giveLastChatMessage(c, 94, @"m", 2);

	[c handleUpdate:@{@"@type" : @"updateChatAction",
			@"chat_id" : @(94),
			@"action"  : @{@"@type" : @"chatActionTyping"}}];
	XCTAssertEqualObjects(knownChat(c, 94)[@"action"], @"typing...",
			@"the phrase lives on the chat row for the preview");

	[c handleUpdate:@{@"@type" : @"updateChatAction",
			@"chat_id" : @(94),
			@"action"  : @{@"@type" : @"chatActionCancel"}}];
	XCTAssertEqualObjects(knownChat(c, 94)[@"action"], @"",
			@"cancel clears it");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - batching and instant profile cache

- (void)testHandleUpdateBatch_CoalescesRebuildChats {
	TGClient *c = T();
	__block int chatsChangedCount = 0;
	c.onChatsChanged = ^{
		chatsChangedCount++;
	};

	NSMutableArray *batch = [NSMutableArray array];
	for (int i = 1; i <= 20; i++){
		[batch addObject:@{
			@"@type" : @"updateNewChat",
			@"chat"  : chatDict(1000 + i, [NSString stringWithFormat:@"Chat %d", i], 10000 + i),
		}];
	}

	[c handleUpdateBatch:batch];

	XCTAssertEqual((NSInteger)c.chats.count, 20);
	XCTAssertEqual(chatsChangedCount, 1, @"a batch of 20 updates must rebuild chats exactly once");
}

- (void)testUserInfo_CachedFromUpdateUserSynchronously {
	TGClient *c = T();
	[c.outbox removeAllObjects];

	NSDictionary *userUpdate = @{
		@"@type" : @"updateUser",
		@"user"  : @{
			@"@type"        : @"user",
			@"id"           : @(777),
			@"first_name"   : @"Alice",
			@"last_name"    : @"Wonder",
			@"phone_number" : @"123456789",
			@"status"       : @{@"@type" : @"userStatusOnline"},
		}
	};
	[c handleUpdate:userUpdate];

	__block BOOL called = NO;
	__block NSDictionary *retrieved = nil;
	[c userInfo:777 completion:^(NSDictionary *user){
		called = YES;
		retrieved = user;
	}];

	XCTAssertTrue(called, @"userInfo must return synchronously from cache without roundtrip");
	XCTAssertEqualObjects(retrieved[@"first_name"], @"Alice");
	XCTAssertEqual((NSInteger)c.outbox.count, 0, @"no TDLib request must be queued in outbox");
}

- (void)testStatusForUser_CachedFromUpdateUserStatusSynchronously {
	TGClient *c = T();
	[c.outbox removeAllObjects];

	[c handleUpdate:@{
		@"@type" : @"updateUser",
		@"user"  : @{
			@"@type"        : @"user",
			@"id"           : @(888),
			@"first_name"   : @"Bob",
			@"status"       : @{@"@type" : @"userStatusOffline", @"was_online" : @(100)},
		}
	}];

	// Simulate status change
	[c handleUpdate:@{
		@"@type"   : @"updateUserStatus",
		@"user_id" : @(888),
		@"status"  : @{@"@type" : @"userStatusOnline"},
	}];

	__block BOOL called = NO;
	__block NSString *statusText = nil;
	[c statusForUser:888 completion:^(NSString *status){
		called = YES;
		statusText = status;
	}];

	XCTAssertTrue(called, @"statusForUser must return synchronously from cache");
	XCTAssertEqualObjects(statusText, @"online");
	XCTAssertEqual((NSInteger)c.outbox.count, 0, @"no TDLib request must be queued in outbox");
}

- (void)testUpdateBatcher_CoalescingAndFlush {
	TGUpdateCoalescer *coalescer = [[TGUpdateCoalescer alloc] initWithIntervalMs:100];
	XCTAssertEqual(coalescer.pendingCount, (NSUInteger)0);

	__block NSSet *flushedChats = nil;
	__block NSSet *flushedUsers = nil;
	__block BOOL flushedOrder = NO;
	__block NSUInteger flushCount = 0;

	[coalescer setFlushHandler:^(NSSet *dirtyChatIds, NSSet *dirtyUserIds, BOOL orderChanged) {
		flushedChats = dirtyChatIds;
		flushedUsers = dirtyUserIds;
		flushedOrder = orderChanged;
		flushCount++;
	}];

	// Mark duplicate dirty events
	[coalescer markChatDirty:100];
	[coalescer markChatDirty:100];
	[coalescer markChatDirty:200];
	[coalescer markUserDirty:55];
	[coalescer markUserDirty:55];
	[coalescer markOrderDirty];

	XCTAssertEqual(coalescer.pendingCount, (NSUInteger)4); // 2 unique chats + 1 unique user + 1 order

	// Manual flush triggers immediately
	[coalescer flushNow];

	XCTAssertEqual(flushCount, (NSUInteger)1);
	XCTAssertEqual(flushedChats.count, (NSUInteger)2);
	XCTAssertTrue([flushedChats containsObject:@100]);
	XCTAssertTrue([flushedChats containsObject:@200]);
	XCTAssertEqual(flushedUsers.count, (NSUInteger)1);
	XCTAssertTrue([flushedUsers containsObject:@55]);
	XCTAssertTrue(flushedOrder);
	XCTAssertEqual(coalescer.pendingCount, (NSUInteger)0);

	// Second flush without updates is a no-op
	[coalescer flushNow];
	XCTAssertEqual(flushCount, (NSUInteger)1);

	// Reset clears without flushing
	[coalescer markChatDirty:300];
	XCTAssertEqual(coalescer.pendingCount, (NSUInteger)1);
	[coalescer reset];
	XCTAssertEqual(coalescer.pendingCount, (NSUInteger)0);
}

@end

