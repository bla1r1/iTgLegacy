// TGClientGroupsTests.m — making a group, who is in it, the links that let
// people in, secret chats, the download list and the sticker search.
//
// None of these had a request in the app before, so there is no old behaviour
// to protect; what the tests hold is the shape TDLib accepts and the branches
// that are easy to get backwards — a status word that must not be guessed at,
// a ban that is forever rather than until epoch, a cancelled download that
// has to release its waiter.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientGroupsTests : XCTestCase @end

static TGClient *G(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.fileWaiters removeAllObjects];
	[c.fileWaiterPriorities removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeG(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastG(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeG(d)[@"@type"] isEqualToString:type])
			found = decodeG(d);
	return found;
}

static NSUInteger countG(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeG(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void answerG(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeG(d)[@"@extra"])
			sent = decodeG(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

@implementation TGClientGroupsTests

#pragma mark - making a group

- (void)testCreateGroup_CarriesTheMembersAndTheName {
	TGClient *c = G();
	[c createGroupNamed:@"Walkers" withUsers:@[@(5), @(6)] completion:nil];

	NSDictionary *r = lastG(c, @"createNewBasicGroupChat");
	XCTAssertEqualObjects(r[@"title"], @"Walkers");
	XCTAssertEqualObjects(r[@"user_ids"], (@[@(5), @(6)]));
}

/// TDLib refuses a basic group with nobody in it, and a group with no name.
/// Both are caught here so the screen's message is the real reason.
- (void)testCreateGroup_RefusesAnEmptyNameOrAnEmptyMemberList {
	TGClient *c = G();
	__block NSInteger calls = 0;
    [c createGroupNamed:@"" withUsers:@[@(5)] completion:^(int64_t chatId, NSArray *failed){
		calls++;
		XCTAssertEqual(chatId, 0LL);
	}];
	[c createGroupNamed:@"Walkers" withUsers:@[] completion:^(int64_t chatId, NSArray *failed){
		calls++;
		XCTAssertEqual(chatId, 0LL);
	}];
	XCTAssertEqual(countG(c, @"createNewBasicGroupChat"), (NSUInteger)0);
	XCTAssertEqual(calls, (NSInteger)2);
}

/// Someone whose privacy settings refuse invitations is reported rather than
/// silently missing from the new group.
- (void)testCreateGroup_ReportsWhoCouldNotBeAdded {
	TGClient *c = G();
	__block NSArray *failed = nil;
	__block int64_t chatId = 0;
	[c createGroupNamed:@"Walkers" withUsers:@[@(5), @(6)]
			 completion:^(int64_t newChatId, NSArray *refused){
		chatId = newChatId; failed = refused;
	}];
	answerG(c, @{@"@type" : @"createdBasicGroupChat", @"chat_id" : @(-70),
			@"failed_to_add_members" : @{@"failed_to_add_members" : @[
					@{@"user_id" : @(6), @"premium_would_allow_invite" : @NO}]}});

	XCTAssertEqual(chatId, -70LL);
	XCTAssertEqualObjects(failed, @[@(6)]);
}

- (void)testCreateSupergroup_ChannelFlagIsWhatTellsThemApart {
	TGClient *c = G();
	[c createSupergroupNamed:@"News" description:@"what happened"
				   isChannel:YES completion:nil];
	NSDictionary *r = lastG(c, @"createNewSupergroupChat");
	XCTAssertTrue([r[@"is_channel"] boolValue]);
	XCTAssertFalse([r[@"is_forum"] boolValue]);
	XCTAssertEqualObjects(r[@"description"], @"what happened");

	[c createSupergroupNamed:@"Talk" description:nil isChannel:NO completion:nil];
	XCTAssertFalse([lastG(c, @"createNewSupergroupChat")[@"is_channel"] boolValue]);
}

/// The chat id changes when a basic group becomes a supergroup, which is the
/// whole reason this answers with one.
- (void)testUpgradeGroup_AnswersWithTheNewChatId {
	TGClient *c = G();
	__block int64_t newId = 0;
	[c upgradeGroupToSupergroup:-70 completion:^(int64_t chatId){ newId = chatId; }];
	answerG(c, @{@"@type" : @"chat", @"id" : @(-1001)});
	XCTAssertEqual(newId, -1001LL);
}

#pragma mark - members

- (void)testAddUser_FailedMembersMeanItDidNotWork {
	TGClient *c = G();
	__block BOOL ok = YES;
	__block NSArray *failed = nil;
	[c addUser:6 toChat:-70 completion:^(BOOL good, NSArray *refused){
		ok = good; failed = refused;
	}];
	XCTAssertEqual([lastG(c, @"addChatMember")[@"user_id"] longLongValue], 6LL);

	answerG(c, @{@"@type" : @"failedToAddMembers",
				 @"failed_to_add_members" : @[@{@"user_id" : @(6)}]});
	XCTAssertFalse(ok, @"a member the server refused is not an added member");
	XCTAssertEqualObjects(failed, @[@(6)]);
}

- (void)testAddUser_AnEmptyFailureListMeansItWorked {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c addUser:6 toChat:-70 completion:^(BOOL good, NSArray *refused){ ok = good; }];
	answerG(c, @{@"@type" : @"failedToAddMembers", @"failed_to_add_members" : @[]});
	XCTAssertTrue(ok);
}

/// A member is named as a MessageSender, not as a bare user id — the one
/// shape setChatMemberStatus takes.
- (void)testSetMemberStatus_NamesTheMemberAsASender {
	TGClient *c = G();
	[c setMember:6 inChat:-70 status:@"administrator" completion:nil];

	NSDictionary *r = lastG(c, @"setChatMemberStatus");
	XCTAssertEqualObjects(r[@"member_id"][@"@type"], @"messageSenderUser");
	XCTAssertEqual([r[@"member_id"][@"user_id"] longLongValue], 6LL);
	XCTAssertEqualObjects(r[@"status"][@"@type"], @"chatMemberStatusAdministrator");
	XCTAssertEqualObjects(r[@"status"][@"rights"][@"@type"], @"chatAdministratorRights");
}

- (void)testSetMemberStatus_DemoteAndRemoveAreTheirOwnStatuses {
	TGClient *c = G();
	[c setMember:6 inChat:-70 status:@"member" completion:nil];
	XCTAssertEqualObjects(lastG(c, @"setChatMemberStatus")[@"status"][@"@type"],
						  @"chatMemberStatusMember");

	[c setMember:6 inChat:-70 status:@"left" completion:nil];
	XCTAssertEqualObjects(lastG(c, @"setChatMemberStatus")[@"status"][@"@type"],
						  @"chatMemberStatusLeft");
}

/// The wrong word here removes people, so an unknown one sends nothing at all
/// rather than falling through to a default.
- (void)testSetMemberStatus_AnUnknownWordSendsNothing {
	TGClient *c = G();
	__block BOOL ok = YES;
	[c setMember:6 inChat:-70 status:@"banned" completion:^(BOOL good){ ok = good; }];
	[c setMember:6 inChat:-70 status:nil completion:nil];
	XCTAssertEqual(countG(c, @"setChatMemberStatus"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

/// A promoted administrator must not be able to promote others, or one admin
/// can hand the group away.
- (void)testSetMemberStatus_APromotedAdminCannotPromoteOrHide {
	TGClient *c = G();
	[c setMember:6 inChat:-70 status:@"administrator" completion:nil];
	NSDictionary *rights = lastG(c, @"setChatMemberStatus")[@"status"][@"rights"];
	XCTAssertFalse([rights[@"can_promote_members"] boolValue]);
	XCTAssertFalse([rights[@"is_anonymous"] boolValue]);
	XCTAssertTrue([rights[@"can_restrict_members"] boolValue]);
	XCTAssertTrue([rights[@"can_delete_messages"] boolValue]);
}

/// Zero is forever. A date in the past would unban them on the spot.
- (void)testBanMember_IsForeverAndKeepsTheirMessagesByDefault {
	TGClient *c = G();
	[c banMember:6 inChat:-70 revokeMessages:NO completion:nil];
	NSDictionary *r = lastG(c, @"banChatMember");
	XCTAssertEqual([r[@"banned_until_date"] integerValue], (NSInteger)0);
	XCTAssertFalse([r[@"revoke_messages"] boolValue]);
	XCTAssertEqualObjects(r[@"member_id"][@"@type"], @"messageSenderUser");
}

- (void)testSearchMembers_FlattensToIdNameAndStatus {
	TGClient *c = G();
	c.usersById[@(6)] = @"Pat";
	__block NSArray *members = nil;
	[c searchMembersInChat:-70 query:nil completion:^(NSArray *found){ members = found; }];
	XCTAssertEqualObjects(lastG(c, @"searchChatMembers")[@"query"], @"");

	answerG(c, @{@"@type" : @"chatMembers", @"total_count" : @(2), @"members" : @[
			@{@"member_id" : @{@"user_id" : @(6)},
			  @"status" : @{@"@type" : @"chatMemberStatusCreator"}},
			@{@"member_id" : @{@"user_id" : @(7)},
			  @"status" : @{@"@type" : @"chatMemberStatusMember"}}]});

	XCTAssertEqual(members.count, (NSUInteger)2);
	XCTAssertEqualObjects(members[0][@"name"], @"Pat");
	XCTAssertEqualObjects(members[0][@"status"], @"owner");
	XCTAssertEqualObjects(members[1][@"status"], @"member");
}

/// A member with no user id behind it — a channel posting as itself — is not
/// a row anything can act on.
- (void)testSearchMembers_SkipsAMemberThatIsNotAUser {
	TGClient *c = G();
	__block NSArray *members = nil;
	[c searchMembersInChat:-70 query:nil completion:^(NSArray *found){ members = found; }];
	answerG(c, @{@"@type" : @"chatMembers", @"members" : @[
			@{@"member_id" : @{@"@type" : @"messageSenderChat", @"chat_id" : @(-5)},
			  @"status" : @{@"@type" : @"chatMemberStatusMember"}}]});
	XCTAssertEqual(members.count, (NSUInteger)0);
}

/// Whether this account may change an administrator at all is can_be_edited,
/// and the menu is built from it rather than from hope.
- (void)testAdministrators_CarryOwnerAndWhetherTheyCanBeEdited {
	TGClient *c = G();
	__block NSArray *admins = nil;
	[c administratorsOfChat:-70 completion:^(NSArray *found){ admins = found; }];
	answerG(c, @{@"@type" : @"chatAdministrators", @"administrators" : @[
			@{@"user_id" : @(1001), @"is_owner" : @YES, @"can_be_edited" : @NO},
			@{@"user_id" : @(6), @"is_owner" : @NO, @"can_be_edited" : @YES}]});

	XCTAssertEqual(admins.count, (NSUInteger)2);
	XCTAssertTrue([admins[0][@"owner"] boolValue]);
	XCTAssertFalse([admins[0][@"editable"] boolValue]);
	XCTAssertTrue([admins[1][@"editable"] boolValue]);
}

#pragma mark - the chat itself

- (void)testSetTitle_RefusesAnEmptyOne {
	TGClient *c = G();
	__block BOOL ok = YES;
	[c setChat:-70 title:@"" completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countG(c, @"setChatTitle"), (NSUInteger)0);
	XCTAssertFalse(ok);

	[c setChat:-70 title:@"Walkers" completion:nil];
	XCTAssertEqualObjects(lastG(c, @"setChatTitle")[@"title"], @"Walkers");
}

- (void)testSetPhoto_SendsALocalFileAsAStaticChatPhoto {
	TGClient *c = G();
	[c setChat:-70 photoAtPath:@"/tmp/group.jpg" completion:nil];
	NSDictionary *photo = lastG(c, @"setChatPhoto")[@"photo"];
	XCTAssertEqualObjects(photo[@"@type"], @"inputChatPhotoStatic");
	XCTAssertEqualObjects(photo[@"photo"][@"@type"], @"inputFileLocal");
	XCTAssertEqualObjects(photo[@"photo"][@"path"], @"/tmp/group.jpg");
}

#pragma mark - invite links

- (void)testInviteLinks_FlattenToWhatARowShows {
	TGClient *c = G();
	__block NSArray *links = nil;
	[c inviteLinksForChat:-70 completion:^(NSArray *found){ links = found; }];
	XCTAssertEqual([lastG(c, @"getChatInviteLinks")[@"creator_user_id"]
			longLongValue], 1001LL);

	answerG(c, @{@"@type" : @"chatInviteLinks", @"invite_links" : @[
			@{@"invite_link" : @"https://t.me/+abc", @"is_primary" : @YES,
			  @"member_count" : @(3), @"member_limit" : @(0),
			  @"pending_join_request_count" : @(1)},
			@{@"invite_link" : @"", @"is_primary" : @NO}]});

	XCTAssertEqual(links.count, (NSUInteger)1, @"a link with no URL is not a link");
	XCTAssertEqualObjects(links[0][@"link"], @"https://t.me/+abc");
	XCTAssertTrue([links[0][@"primary"] boolValue]);
	XCTAssertEqual([links[0][@"requests"] integerValue], (NSInteger)1);
}

- (void)testCreateInviteLink_ANegativeLimitBecomesNoLimit {
	TGClient *c = G();
	[c createInviteLinkForChat:-70 name:@"Friends" memberLimit:-5 completion:nil];
	NSDictionary *r = lastG(c, @"createChatInviteLink");
	XCTAssertEqual([r[@"member_limit"] integerValue], (NSInteger)0);
	XCTAssertEqualObjects(r[@"name"], @"Friends");
	XCTAssertFalse([r[@"creates_join_request"] boolValue]);
}

- (void)testRevokeInviteLink_RefusesAnEmptyLinkAndReadsTheAnswer {
	TGClient *c = G();
	__block BOOL ok = YES;
	[c revokeInviteLink:@"" inChat:-70 completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countG(c, @"revokeChatInviteLink"), (NSUInteger)0);
	XCTAssertFalse(ok);

	[c revokeInviteLink:@"https://t.me/+abc" inChat:-70
			 completion:^(BOOL good){ ok = good; }];
	answerG(c, @{@"@type" : @"chatInviteLinks", @"invite_links" : @[]});
	XCTAssertTrue(ok);
}

/// A link to a chat this account is already in answers with a chat_id, and
/// Join has to read as Open instead.
- (void)testCheckInviteLink_SaysWhenThisAccountIsAlreadyIn {
	TGClient *c = G();
	__block BOOL already = NO;
	__block NSInteger members = 0;
	__block NSString *title = nil;
	[c checkInviteLink:@"https://t.me/+abc"
			completion:^(NSString *name, NSInteger count, BOOL isMember){
		title = name; members = count; already = isMember;
	}];
	answerG(c, @{@"@type" : @"chatInviteLinkInfo", @"chat_id" : @(-70),
				 @"title" : @"Walkers", @"member_count" : @(3)});

	XCTAssertEqualObjects(title, @"Walkers");
	XCTAssertEqual(members, (NSInteger)3);
	XCTAssertTrue(already);
}

- (void)testCheckInviteLink_ABadLinkAnswersWithNothingRatherThanThrowing {
	TGClient *c = G();
	__block NSString *title = @"unset";
	[c checkInviteLink:@"nonsense"
			completion:^(NSString *name, NSInteger count, BOOL isMember){ title = name; }];
	answerG(c, @{@"@type" : @"error", @"code" : @(400),
				 @"message" : @"INVITE_HASH_INVALID"});
	XCTAssertNil(title);
}

- (void)testJoinRequests_ApproveAndDeclineAreTheSameRequestWithOneFlag {
	TGClient *c = G();
	[c processJoinRequest:6 inChat:-70 approve:YES];
	XCTAssertTrue([lastG(c, @"processChatJoinRequest")[@"approve"] boolValue]);

	[c processJoinRequest:6 inChat:-70 approve:NO];
	XCTAssertFalse([lastG(c, @"processChatJoinRequest")[@"approve"] boolValue]);
}

#pragma mark - secret chats

- (void)testSecretChat_CreatesWithAUserAndRefusesNobody {
	TGClient *c = G();
	__block int64_t chatId = -1;
	[c createSecretChatWithUser:0 completion:^(int64_t newId){ chatId = newId; }];
	XCTAssertEqual(countG(c, @"createNewSecretChat"), (NSUInteger)0);
	XCTAssertEqual(chatId, 0LL);

	[c createSecretChatWithUser:6 completion:^(int64_t newId){ chatId = newId; }];
	answerG(c, @{@"@type" : @"chat", @"id" : @(-900)});
	XCTAssertEqual(chatId, -900LL);
}

/// A secret chat is unusable until the other device answers, and the state is
/// the only thing that says so.
- (void)testSecretChat_StateIsOneWord {
	TGClient *c = G();
	__block NSString *state = nil;
	__block BOOL outgoing = NO;
	[c secretChatState:12 completion:^(NSString *s, BOOL out){ state = s; outgoing = out; }];
	answerG(c, @{@"@type" : @"secretChat", @"id" : @(12), @"is_outbound" : @YES,
				 @"state" : @{@"@type" : @"secretChatStatePending"}});
	XCTAssertEqualObjects(state, @"pending");
	XCTAssertTrue(outgoing);
}

/// The key exchange answers while you watch, so the update carries it and
/// the hook hears the word the header is going to show.
- (void)testSecretChat_TheUpdateCarriesTheStateToTheHook {
	TGClient *c = G();
	__block NSInteger heard = 0;
	__block NSString *word = nil;
	c.onSecretChat = ^(NSInteger secretChatId, NSString *state){
		heard = secretChatId; word = state;
	};
	[c handleUpdate:@{@"@type" : @"updateSecretChat",
					  @"secret_chat" : @{@"id" : @(12),
										 @"state" : @{@"@type" : @"secretChatStateReady"}}}];
	XCTAssertEqual(heard, 12);
	XCTAssertEqualObjects(word, @"ready");
}

/// Every other secret-chat call takes the secret chat id, which is not the
/// chat id and only the chat's own type carries.
- (void)testSecretChat_IdComesOutOfTheChatTypeAndIsZeroForAnythingElse {
	TGClient *c = G();
	__block NSInteger secretId = -1;
	[c secretChatIdForChat:-900 completion:^(NSInteger found){ secretId = found; }];
	answerG(c, @{@"@type" : @"chat", @"id" : @(-900),
				 @"type" : @{@"@type" : @"chatTypeSecret",
							 @"secret_chat_id" : @(12), @"user_id" : @(6)}});
	XCTAssertEqual(secretId, (NSInteger)12);

	[c secretChatIdForChat:7 completion:^(NSInteger found){ secretId = found; }];
	answerG(c, @{@"@type" : @"chat", @"id" : @(7),
				 @"type" : @{@"@type" : @"chatTypePrivate", @"user_id" : @(6)}});
	XCTAssertEqual(secretId, (NSInteger)0);
}

#pragma mark - downloads

/// Cancelling has to release the waiter record as well, or every caller of
/// downloadFile: sits there until the 45-second watchdog fires.
- (void)testCancelDownload_ReleasesTheWaiterItWouldHaveStranded {
	TGClient *c = G();
	__block BOOL served = NO;
	[c downloadFile:42 completion:^(NSString *path){ served = YES; }];
	XCTAssertNotNil(c.fileWaiters[@(42)], @"the waiter must exist to be released");

	[c cancelDownloadOfFile:42 onlyIfPending:NO];
	NSDictionary *r = lastG(c, @"cancelDownloadFile");
	XCTAssertEqual([r[@"file_id"] integerValue], (NSInteger)42);
	XCTAssertFalse([r[@"only_if_pending"] boolValue]);
	XCTAssertNil(c.fileWaiters[@(42)]);
	XCTAssertNil(c.fileWaiterPriorities[@(42)]);
	(void)served;
}

- (void)testDownloadList_FlattensNameSizeAndState {
	TGClient *c = G();
	__block NSArray *downloads = nil;
	__block NSInteger active = -1;
	[c fileDownloadsMatching:nil activeOnly:NO
				  completion:^(NSArray *found, NSInteger running){
		downloads = found; active = running;
	}];
	answerG(c, @{@"@type" : @"foundFileDownloads",
			@"total_counts" : @{@"active_count" : @(1)},
			@"files" : @[
				@{@"file_id" : @(42), @"is_paused" : @NO, @"complete_date" : @(0),
				  @"message" : @{@"content" : @{@"@type" : @"messageDocument",
						@"document" : @{@"file_name" : @"notes.pdf",
										@"document" : @{@"size" : @(2048)}}}}},
				@{@"file_id" : @(43), @"is_paused" : @YES, @"complete_date" : @(99),
				  @"message" : @{@"content" : @{@"@type" : @"messageDocument",
						@"document" : @{@"document" : @{@"size" : @(10)}}}}}]});

	XCTAssertEqual(active, (NSInteger)1);
	XCTAssertEqual(downloads.count, (NSUInteger)2);
	XCTAssertEqualObjects(downloads[0][@"name"], @"notes.pdf");
	XCTAssertEqual([downloads[0][@"size"] longLongValue], 2048LL);
	XCTAssertFalse([downloads[0][@"done"] boolValue]);
	XCTAssertTrue([downloads[1][@"done"] boolValue], @"a complete_date means done");
	// A file with no name still needs something on its row.
	XCTAssertEqualObjects(downloads[1][@"name"], @"File");
}

/// Out of the list and off the disk are two different things, and the flag is
/// the only difference.
- (void)testRemoveDownload_CacheDeletionIsTheFlag {
	TGClient *c = G();
	[c removeFileFromDownloads:42 deleteFromCache:NO];
	XCTAssertFalse([lastG(c, @"removeFileFromDownloads")[@"delete_from_cache"] boolValue]);

	[c removeFileFromDownloads:42 deleteFromCache:YES];
	XCTAssertTrue([lastG(c, @"removeFileFromDownloads")[@"delete_from_cache"] boolValue]);
}

- (void)testPauseDownloads_OneAndAll {
	TGClient *c = G();
	[c setDownloadOfFile:42 paused:YES];
	XCTAssertTrue([lastG(c, @"toggleDownloadIsPaused")[@"is_paused"] boolValue]);

	[c setAllDownloadsPaused:NO];
	XCTAssertFalse([lastG(c, @"toggleAllDownloadsArePaused")[@"are_paused"] boolValue]);
}

#pragma mark - sticker search

/// TDLib searches stickers by emoji, not by word, and the two requests cover
/// the installed sets and everything public.
- (void)testStickerSearch_InstalledAndPublicAreTwoRequests {
	TGClient *c = G();
	[c stickersForEmoji:@"\U0001F603" completion:nil];
	NSDictionary *mine = lastG(c, @"getStickers");
	XCTAssertEqualObjects(mine[@"query"], @"\U0001F603");
	XCTAssertEqualObjects(mine[@"sticker_type"][@"@type"], @"stickerTypeRegular");

	[c searchStickersForEmoji:@"\U0001F603" completion:nil];
	XCTAssertEqualObjects(lastG(c, @"searchStickers")[@"emojis"], @"\U0001F603");
}

- (void)testStickerSearch_AnEmptyQuerySendsNothingAndAnswersEmpty {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c stickersForEmoji:@"" completion:^(NSArray *stickers){
		calls++; XCTAssertEqual(stickers.count, (NSUInteger)0);
	}];
	[c searchStickersForEmoji:nil completion:^(NSArray *stickers){
		calls++; XCTAssertEqual(stickers.count, (NSUInteger)0);
	}];
	[c searchStickerSetsNamed:@"" completion:^(NSArray *sets){
		calls++; XCTAssertEqual(sets.count, (NSUInteger)0);
	}];
	XCTAssertEqual(countG(c, @"getStickers"), (NSUInteger)0);
	XCTAssertEqual(countG(c, @"searchStickers"), (NSUInteger)0);
	XCTAssertEqual(countG(c, @"searchStickerSets"), (NSUInteger)0);
	XCTAssertEqual(calls, (NSInteger)3);
}

/// The installed list, the search and the trending list answer with the same
/// shape, and one flattener is why a row can be drawn from any of them.
- (void)testStickerSets_AllThreeListsFlattenTheSameWay {
	NSArray *flattened = TGFlattenStickerSets(@[
			@{@"id" : @"77", @"title" : @"Cats",
			  @"covers" : @[@{@"@type" : @"sticker", @"emoji" : @"\U0001F431",
							  @"sticker" : @{@"id" : @(9)}}]},
			@{@"title" : @"No id, not a set"}]);
	XCTAssertEqual(flattened.count, (NSUInteger)1);
	XCTAssertEqualObjects(flattened[0][@"title"], @"Cats");
	XCTAssertNotNil(flattened[0][@"cover"]);
}

#pragma mark - favourites, the archive shelf and the order

- (void)testFavourite_AnInputFileIdEitherWay {
	TGClient *c = G();
	[c setSticker:9 favourite:YES];
	NSDictionary *add = lastG(c, @"addFavoriteSticker");
	XCTAssertEqualObjects(add[@"sticker"][@"@type"], @"inputFileId");
	XCTAssertEqual([add[@"sticker"][@"id"] integerValue], 9);

	[c setSticker:9 favourite:NO];
	XCTAssertEqualObjects(lastG(c, @"removeFavoriteSticker")[@"sticker"][@"@type"],
						  @"inputFileId");
}

- (void)testFavourite_NonpositiveFileIdSendsNothing {
	TGClient *c = G();
	// An id that cannot exist is not a sticker this menu touched, and what
	// might have been sent is the outbox staying empty.
	[c setSticker:0 favourite:YES];
	[c setSticker:-3 favourite:NO];
	XCTAssertTrue(countG(c, @"addFavoriteSticker") == 0 &&
				  countG(c, @"removeFavoriteSticker") == 0);
}

/// changeStickerSet carries two flags TDLib gives no default to. The three
/// moves a menu offers are spelled out because the archive one silently
/// uninstalls when archived is left NO.
- (void)testStickerSets_UninstallArchiveAndRestoreCarryBothFlags {
	TGClient *c = G();
	[c setStickerSet:@"500" installed:NO archived:NO];
	NSDictionary *gone = lastG(c, @"changeStickerSet");
	XCTAssertFalse([gone[@"is_installed"] boolValue]);
	XCTAssertFalse([gone[@"is_archived"] boolValue]);

	[c setStickerSet:@"500" installed:NO archived:YES];
	NSDictionary *archived = lastG(c, @"changeStickerSet");
	XCTAssertFalse([archived[@"is_installed"] boolValue]);
	XCTAssertTrue([archived[@"is_archived"] boolValue]);

	[c setStickerSet:@"500" installed:YES archived:YES];
	NSDictionary *back = lastG(c, @"changeStickerSet");
	XCTAssertTrue([back[@"is_installed"] boolValue]);
	XCTAssertTrue([back[@"is_archived"] boolValue]);
}

- (void)testStickerSets_SearchingInstalledNeedsAWord {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c installedStickerSetsNamed:@"" completion:^(NSArray *sets){
		calls++; XCTAssertEqual(sets.count, (NSUInteger)0);
	}];
	XCTAssertEqual(countG(c, @"searchInstalledStickerSets"), (NSUInteger)0);

	[c installedStickerSetsNamed:@"c" completion:nil];
	NSDictionary *r = lastG(c, @"searchInstalledStickerSets");
	XCTAssertEqualObjects(r[@"query"], @"c");
	XCTAssertEqual([r[@"limit"] integerValue], 40);
	XCTAssertEqualObjects(r[@"sticker_type"][@"@type"], @"stickerTypeRegular");
}

- (void)testStickerSets_TheArchivedShelfAnswersLikeTheInstalled {
	TGClient *c = G();
	__block NSArray *sets = nil;
	[c archivedStickerSetsWithCompletion:^(NSArray *found){ sets = found; }];
	answerG(c, @{@"@type" : @"stickerSets", @"sets" : @[
			@{@"id" : @"51", @"title" : @"Archived cats",
			  @"covers" : @[@{@"@type" : @"sticker",
							  @"sticker" : @{@"id" : @(7)}}]}]});
	XCTAssertEqual(sets.count, (NSUInteger)1);
	XCTAssertEqualObjects(sets[0][@"title"], @"Archived cats");
}

/// A set is attached to a chat, and nothing answers for the absent one.
- (void)testStickerSets_AttachedBelongsToAChat {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c attachedStickerSetsInChat:0 completion:^(NSArray *sets){
		calls++; XCTAssertEqual(sets.count, (NSUInteger)0);
	}];
	XCTAssertEqual(countG(c, @"getAttachedStickerSets"), (NSUInteger)0);

	[c attachedStickerSetsInChat:-70 completion:nil];
	NSDictionary *r = lastG(c, @"getAttachedStickerSets");
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
}

/// One set has nothing to be ordered against, so the request is never made.
- (void)testReorderInstalledStickerSets_TwoOrMoreSetsMakeAnOrder {
	TGClient *c = G();
	[c reorderInstalledStickerSets:nil];
	[c reorderInstalledStickerSets:@[@"500"]];
	XCTAssertEqual(countG(c, @"reorderInstalledStickerSets"), (NSUInteger)0);

	[c reorderInstalledStickerSets:@[@"500", @"77"]];
	NSDictionary *r = lastG(c, @"reorderInstalledStickerSets");
	XCTAssertEqualObjects(r[@"set_ids"], (@[@"500", @"77"]));
	XCTAssertEqualObjects(r[@"sticker_type"][@"@type"], @"stickerTypeRegular");
}

- (void)testSavedAnimations_AnAnimationInAndOutOfTheShelf {	TGClient *c = G();
	[c saveAnimationFileId:4 saved:YES];
	NSDictionary *add = lastG(c, @"addSavedAnimation");
	XCTAssertEqualObjects(add[@"animation"][@"@type"], @"inputFileId");
	XCTAssertEqual([add[@"animation"][@"id"] integerValue], 4);

	[c saveAnimationFileId:4 saved:NO];
	XCTAssertEqualObjects(lastG(c, @"removeSavedAnimation")[@"animation"][@"@type"],
						  @"inputFileId");

	NSUInteger sent = countG(c, @"addSavedAnimation") + countG(c, @"removeSavedAnimation");
	[c saveAnimationFileId:0 saved:YES];
	[c saveAnimationFileId:-1 saved:NO];
	XCTAssertTrue(sent == countG(c, @"addSavedAnimation") + countG(c, @"removeSavedAnimation"),
				  @"a file id that cannot exist sends nothing");
}

#pragma mark - sending later

- (void)testScheduled_AtDateCarriesTheDateAndWhenOnlineCarriesNothing {
	NSDictionary *at = [TGClient scheduledAtDate:1234];
	XCTAssertEqualObjects(at[@"@type"], @"messageSchedulingStateSendAtDate");
	XCTAssertEqual([at[@"send_date"] integerValue], 1234);
	XCTAssertEqual([at[@"repeat_period"] integerValue], 0);
	XCTAssertEqualObjects([TGClient scheduledWhenOnline][@"@type"],
						  @"messageSchedulingStateSendWhenOnline");
}

- (void)testScheduled_ASendWithAStateCarriesItAtTheTop {
	TGClient *c = G();
	[c sendText:@"later" toChat:-70 thread:0 replyTo:4
		  scheduled:[TGClient scheduledAtDate:1234]];

	NSDictionary *r = lastG(c, @"sendMessage");
	XCTAssertEqualObjects(r[@"scheduling_state"][@"@type"],
						  @"messageSchedulingStateSendAtDate");
	XCTAssertEqual([r[@"scheduling_state"][@"send_date"] integerValue], 1234);
	// The reply still rides along: a scheduled answer to a message is an
	// answer the moment it appears.
	XCTAssertEqual([r[@"reply_to"][@"message_id"] longLongValue], 4LL);
}

- (void)testScheduled_ThePlainSendCarriesNoState {
	TGClient *c = G();
	[c sendText:@"now" toChat:-70 thread:0 replyTo:0];
	XCTAssertNil(lastG(c, @"sendMessage")[@"scheduling_state"]);
}

- (void)testScheduled_TheQueueAnswerIsFlattenedLikeHistory {
	TGClient *c = G();
	__block NSArray *waiting = nil;
	[c scheduledMessagesInChat:-70 completion:^(NSArray *messages){
		waiting = messages;
	}];
	answerG(c, @{@"@type" : @"messages", @"messages" : @[@{
			@"id" : @(140),
			@"date" : @(1234),
			@"content" : @{@"@type" : @"messageText",
						   @"text" : @{@"@type" : @"formattedText", @"text" : @"see you at eight"}}}]});

	XCTAssertEqual(waiting.count, (NSUInteger)1);
	XCTAssertEqualObjects(waiting[0][@"text"], @"see you at eight");
	XCTAssertEqual([waiting[0][@"id"] longLongValue], 140LL);
	XCTAssertEqual([waiting[0][@"date"] longLongValue], 1234LL);
}

/// An absent state means TDLib sends the message at once, which is what
/// "Send Now" is; a state means it moves to after.
- (void)testScheduled_MovingACarrierPhrase {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c setSchedulingState:nil forMessage:140 inChat:-70 completion:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastG(c, @"editMessageSchedulingState");
	XCTAssertTrue(r[@"scheduling_state"] == (id)kCFNull,
				  @"absent is the JSON null TDLib reads as send at once");
	XCTAssertEqual([r[@"message_id"] longLongValue], 140LL);
	answerG(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	[c setSchedulingState:[TGClient scheduledWhenOnline] forMessage:140
					inChat:-70 completion:nil];
	XCTAssertEqualObjects(lastG(c, @"editMessageSchedulingState")[@"scheduling_state"][@"@type"],
						  @"messageSchedulingStateSendWhenOnline");
}

#pragma mark - the batch, the one member, and the permissions preset

- (void)testAddMembers_TheBatchIsOneRequestAndAnEmptyPickSendsNone {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c addUsers:@[] toChat:-70 completion:^(BOOL ok, NSArray *refused){
		calls++; XCTAssertFalse(ok); XCTAssertEqual(refused.count, (NSUInteger)0);
	}];
	XCTAssertEqual(countG(c, @"addChatMembers"), (NSUInteger)0);

	[c addUsers:@[@(5), @(6)] toChat:-70 completion:nil];
	NSDictionary *r = lastG(c, @"addChatMembers");
	XCTAssertEqualObjects(r[@"user_ids"], (@[@(5), @(6)]));
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
	// forward_limit is what a basic group shows a new member of the history
	// before they arrived; the same 100 the single-member call carries.
	XCTAssertEqual([r[@"forward_limit"] integerValue], 100);

	// The failed half reads out of the answer the same way the one-member
	// call does, and an error is refused rather than called success.
	__block BOOL ok = NO;
	__block NSArray *refusedIds = nil;
	[c addUsers:@[@(5), @(6)] toChat:-70 completion:^(BOOL good, NSArray *failed){
		ok = good; refusedIds = failed;
	}];
	answerG(c, @{@"@type" : @"failedToAddMembers",
				 @"failed_to_add_members" : @[@{@"user_id" : @(6)}]});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(refusedIds, @[@(6)]);
	XCTAssertEqual(calls, (NSInteger)1);
}

/// The member detail: one user read back through a sender.
- (void)testChatMember_AskedBySenderAndNilForNobody {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c chatMember:0 inChat:-70 completion:^(NSDictionary *member){
		calls++; XCTAssertNil(member);
	}];
	XCTAssertEqual(countG(c, @"getChatMember"), (NSUInteger)0);

	[c chatMember:6 inChat:-70 completion:nil];
	NSDictionary *r = lastG(c, @"getChatMember");
	XCTAssertEqualObjects(r[@"member_id"], (@{@"@type" : @"messageSenderUser",
											  @"user_id" : @(6)}));
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);

	__block NSDictionary *member = @{};
	[c chatMember:6 inChat:-70 completion:^(NSDictionary *found){ member = found; }];
	answerG(c, @{@"@type" : @"error", @"message" : @"MEMBER_NOT_FOUND"});
	XCTAssertNil(member);
}

/// Sixteen booleans TDLib gives no default to, spelled out of one word:
/// "all" opens everything, "read" closes even the plain text, and "text" is
/// the middle - messages, previews and invites without the media.
- (void)testChatPermissions_ThePresetsSpellTheSixteenBooleans {
	NSDictionary *all = [TGClient chatPermissionsForPreset:@"all"];
	NSMutableArray *shut = [NSMutableArray array];
	[all enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop){
		if (![key isEqualToString:@"@type"] && ![value boolValue])
			[shut addObject:key];
	}];
	XCTAssertEqual(shut.count, (NSUInteger)0, @"%@ closed in the all preset", shut);
	XCTAssertEqual(all.count, (NSUInteger)17, @"the type word plus sixteen booleans");

	NSDictionary *text = [TGClient chatPermissionsForPreset:@"text"];
	XCTAssertTrue([text[@"can_send_basic_messages"] boolValue]);
	XCTAssertFalse([text[@"can_send_photos"] boolValue]);
	XCTAssertFalse([text[@"can_send_videos"] boolValue]);
	XCTAssertFalse([text[@"can_send_other_messages"] boolValue]);
	XCTAssertFalse([text[@"can_change_info"] boolValue]);
	// Previews ride with the words; so does inviting, which a text-only chat
	// still wants to be talked into new members by.
	XCTAssertTrue([text[@"can_add_link_previews"] boolValue]);
	XCTAssertTrue([text[@"can_invite_users"] boolValue]);

	NSDictionary *read = [TGClient chatPermissionsForPreset:@"read"];
	[read enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop){
		if (![key isEqualToString:@"@type"])
			XCTAssertFalse([value boolValue], @"%@ open in the read preset", key);
	}];
}

- (void)testSetChatPermissions_ThePresetRidesAsThePermissionsField {
	TGClient *c = G();
	[c setChatPermissionsFromPreset:@"read" inChat:-70 completion:nil];
	NSDictionary *r = lastG(c, @"setChatPermissions");
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
	XCTAssertEqualObjects(r[@"permissions"][@"@type"], @"chatPermissions");
	XCTAssertFalse([r[@"permissions"][@"can_send_basic_messages"] boolValue]);
}

/// Handover carries the password two-factor asks for; the chat id and the
/// successor ride along, and the password is sent as it was given - the
/// server owns the verdict, not a guess here.
- (void)testTransferOwnership_ThePasswordRidesWithTheRequest {
	TGClient *c = G();
	[c transferOwnershipOfChat:-70 toUser:6 password:@"s3cret" completion:nil];
	NSDictionary *r = lastG(c, @"transferChatOwnership");
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
	XCTAssertEqual([r[@"user_id"] longLongValue], 6LL);
	XCTAssertEqualObjects(r[@"password"], @"s3cret");
}

#pragma mark - the topics a forum makes and minds

- (void)testCreateForumTopic_TheNameAndOneOfSevenHues {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c createForumTopicInChat:-70 name:@"" iconColour:3 completion:^(int64_t threadId, NSString *name){
		calls++; XCTAssertEqual(threadId, 0LL);
	}];
	XCTAssertEqual(countG(c, @"createForumTopic"), (NSUInteger)0);

	[c createForumTopicInChat:-70 name:@"Ideas" iconColour:11 completion:nil];
	NSDictionary *r = lastG(c, @"createForumTopic");
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
	XCTAssertEqualObjects(r[@"name"], @"Ideas");
	XCTAssertFalse([r[@"is_name_implicit"] boolValue]);
	// The palette is seven hues; a colour past its end wraps rather than
	// being refused, which is what makes the menu's 0-6 safe.
	XCTAssertEqual([r[@"icon"][@"color"] integerValue], 4);
	XCTAssertEqualObjects(r[@"icon"][@"@type"], @"forumTopicIcon");

	// The answer is the topic's own record: its thread id is what every
	// later edit answers through.
	__block int64_t threadId = 0;
	[c createForumTopicInChat:-70 name:@"Ideas" iconColour:1
				   completion:^(int64_t made, NSString *name){
		threadId = made;
	}];
	answerG(c, @{@"@type" : @"forumTopicInfo", @"forum_topic_id" : @(42),
				 @"name" : @"Ideas"});
	XCTAssertEqual(threadId, 42LL);
	XCTAssertEqual(calls, (NSInteger)1);
}

- (void)testRenameForumTopic_TheIconRidesOnlyWhenItChanges {
	TGClient *c = G();
	[c renameForumTopic:42 inChat:-70 name:@"" iconEmojiId:0 completion:nil];
	XCTAssertEqual(countG(c, @"editForumTopic"), (NSUInteger)0);

	[c renameForumTopic:42 inChat:-70 name:@"Renamed" iconEmojiId:0
			 completion:nil];
	NSDictionary *r = lastG(c, @"editForumTopic");
	XCTAssertEqual([r[@"forum_topic_id"] integerValue], 42);
	XCTAssertEqualObjects(r[@"name"], @"Renamed");
	XCTAssertFalse([r[@"edit_icon_custom_emoji"] boolValue]);
	XCTAssertEqual([r[@"icon_custom_emoji_id"] longLongValue], 0LL);

	[c renameForumTopic:42 inChat:-70 name:@"Renamed" iconEmojiId:9 completion:nil];
	r = lastG(c, @"editForumTopic");
	XCTAssertTrue([r[@"edit_icon_custom_emoji"] boolValue]);
	XCTAssertEqual([r[@"icon_custom_emoji_id"] longLongValue], 9LL);
}

/// Closed, pinned, deleted: three sends, each naming the one topic.
- (void)testForumTopic_TheThreeSendsNameTheirTopic {
	TGClient *c = G();
	[c toggleForumTopic:42 inChat:-70 closed:YES];
	NSDictionary *closed = lastG(c, @"toggleForumTopicIsClosed");
	XCTAssertEqual([closed[@"forum_topic_id"] integerValue], 42);
	XCTAssertTrue([closed[@"is_closed"] boolValue]);

	[c toggleForumTopic:42 inChat:-70 pinned:YES];
	NSDictionary *pinned = lastG(c, @"toggleForumTopicIsPinned");
	XCTAssertEqual([pinned[@"forum_topic_id"] integerValue], 42);
	XCTAssertTrue([pinned[@"is_pinned"] boolValue]);

	[c deleteForumTopic:42 inChat:-70];
	NSDictionary *gone = lastG(c, @"deleteForumTopic");
	XCTAssertEqual([gone[@"forum_topic_id"] integerValue], 42);
	XCTAssertEqual([gone[@"chat_id"] longLongValue], -70LL);
}

- (void)testViewAsTopics_TheFlipCarriesTheNewBool {
	TGClient *c = G();
	[c setChatViewAsTopics:-70 viewAsTopics:NO completion:nil];
	NSDictionary *r = lastG(c, @"toggleChatViewAsTopics");
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
	XCTAssertFalse([r[@"view_as_topics"] boolValue]);

	// What it is now reads straight off the chat.
	__block BOOL yes = NO;
	[c chatWithViewAsTopics:-70 completion:^(BOOL viewAsTopics){ yes = viewAsTopics; }];
	answerG(c, @{@"@type" : @"chat", @"view_as_topics" : @YES});
	XCTAssertTrue(yes);
}

#pragma mark - the crowd behind an answer, and answers made after

- (void)testPollVoters_TheOptionIndexAndTheNamesBack {
	TGClient *c = G();
	__block NSArray *voters = nil;
	__block BOOL end = NO;
	[c pollVotersOfOption:1 ofMessage:140 inChat:-70 completion:^(NSArray *found, BOOL done){
		voters = found; end = done;
	}];
	NSDictionary *r = lastG(c, @"getPollVoters");
	// The option is the 0-based index it sits at, not a string id - TDLib
	// keeps both, and this one asked in words is refused.
	XCTAssertEqual([r[@"option_id"] integerValue], 1);
	XCTAssertEqual([r[@"message_id"] longLongValue], 140LL);
	XCTAssertEqual([r[@"offset"] integerValue], 0);
	XCTAssertEqual([r[@"limit"] integerValue], 50);

	answerG(c, @{@"@type" : @"pollVoters",
				 @"total_count" : @(2),
				 @"voters" : @[@{@"@type" : @"pollVoter",
								 @"voter_id" : @{@"@type" : @"messageSenderUser",
												 @"user_id" : @(6)},
								 @"date" : @(1234)},
							   @{@"@type" : @"pollVoter",
								 @"voter_id" : @{@"@type" : @"messageSenderUser",
												 @"user_id" : @(7)},
								 @"date" : @(1235)}]});
	XCTAssertEqual(voters.count, (NSUInteger)2);
	XCTAssertEqual([voters[0][@"id"] longLongValue], 6LL);
	XCTAssertEqual([voters[0][@"date"] integerValue], 1234);
	// The end is read off the poll's own count: two voters returned and two
	// it says there are means the list is whole, whatever page size TDLib
	// chose.
	XCTAssertTrue(end);
}

- (void)testAddPollOption_AnEmptyLineSendsNothing {
	TGClient *c = G();
	__block NSInteger calls = 0;
	[c addPollOption:@"" toMessage:140 inChat:-70 completion:^(BOOL ok){
		calls++; XCTAssertFalse(ok);
	}];
	XCTAssertEqual(countG(c, @"addPollOption"), (NSUInteger)0);

	[c addPollOption:@"New answer" toMessage:140 inChat:-70 completion:nil];
	NSDictionary *r = lastG(c, @"addPollOption");
	XCTAssertEqual([r[@"message_id"] longLongValue], 140LL);
	XCTAssertEqualObjects(r[@"option"][@"@type"], @"inputPollOption");
	XCTAssertEqualObjects(r[@"option"][@"text"][@"text"], @"New answer");
}

- (void)testDeletePollOption_TheStringIdAndItsRefusal {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c deletePollOption:@"" ofMessage:140 inChat:-70 completion:^(BOOL good){
		ok = good;
	}];
	XCTAssertFalse(ok);
	XCTAssertEqual(countG(c, @"deletePollOption"), (NSUInteger)0);

	[c deletePollOption:@"op1" ofMessage:140 inChat:-70 completion:^(BOOL good){
		ok = good;
	}];
	NSDictionary *r = lastG(c, @"deletePollOption");
	// The option id is the string pollOption carries - an index here would
	// answer for the wrong row once an option was deleted before it.
	XCTAssertEqualObjects(r[@"option_id"], @"op1");
	answerG(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testReadAllChatPollVotes_OneSendForTheWholeChat {
	TGClient *c = G();
	[c readAllChatPollVotes:-70];
	NSDictionary *r = lastG(c, @"readAllChatPollVotes");
	XCTAssertEqual([r[@"chat_id"] longLongValue], -70LL);
	XCTAssertEqualObjects(r[@"@type"], @"readAllChatPollVotes");
}

- (void)testPollFlattening_TheFlagsTheMenuAsksAbout {
	NSDictionary *m = @{@"content" : @{@"@type" : @"messagePoll", @"poll" : @{
			@"question" : @{@"@type" : @"formattedText", @"text" : @"Lunch?"},
			@"options" : @[@{@"@type" : @"pollOption", @"id" : @"op1",
							 @"text" : @{@"formattedText" : @"a"},
							 @"properties" : @{@"can_be_deleted" : @YES}},
						   @{@"@type" : @"pollOption", @"id" : @"op2",
							 @"text" : @{@"text" : @"b"}}],
			@"total_voter_count" : @2,
			@"can_get_voters" : @YES,
			@"is_closed" : @NO,
	}}};
	NSDictionary *flat = TGFlattenMessage(m);
	XCTAssertTrue([flat[@"pollVoters"] boolValue], @"opened to the crowd");
	XCTAssertTrue([flat[@"pollOpen"] boolValue]);
	XCTAssertTrue([flat[@"pollDeletable"] boolValue],
				  @"only where one option says so");
	XCTAssertEqual([flat[@"pollTotal"] integerValue], 2);

	m = @{@"content" : @{@"@type" : @"messagePoll", @"poll" : @{
			@"question" : @{@"@type" : @"formattedText", @"text" : @"Lunch?"},
			@"options" : @[],
			@"total_voter_count" : @0,
			@"can_get_voters" : @YES,
			@"is_closed" : @YES,
	}}};
	flat = TGFlattenMessage(m);
	XCTAssertFalse([flat[@"pollOpen"] boolValue], @"closed is closed");
}

#pragma mark - the pin that keeps moving

- (void)testSendLiveLocation_TheIdIsWhatTheAnswerCarries {
	TGClient *c = G();
	__block int64_t messageId = 0;
	[c sendLiveLocation:3600 latitude:50.45 longitude:30.52 toChat:-70
			 completion:^(int64_t made){ messageId = made; }];
	NSDictionary *r = lastG(c, @"sendMessage");
	XCTAssertEqualObjects(r[@"input_message_content"][@"@type"],
						  @"inputMessageLiveLocation");
	NSDictionary *live = r[@"input_message_content"][@"location"];
	XCTAssertEqualObjects(live[@"@type"], @"liveLocation");
	XCTAssertEqual([live[@"live_period"] integerValue], 3600);
	XCTAssertEqual([live[@"location"][@"latitude"] doubleValue], 50.45);
	XCTAssertEqual([live[@"location"][@"longitude"] doubleValue], 30.52);

	// The send is answered with the message itself: an orphaned live
	// location is one nobody can move or stop.
	answerG(c, @{@"@type" : @"message", @"id" : @(140)});
	XCTAssertEqual(messageId, 140LL);
}

- (void)testEditLiveLocation_ShapedLikeTheSendAndZeroIsTheStop {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c editLiveLocationOfMessage:0 inChat:-70 latitude:1 longitude:2
					  livePeriod:600 completion:^(BOOL good){ ok = good; }];
	XCTAssertFalse(ok);
	XCTAssertEqual(countG(c, @"editMessageLiveLocation"), (NSUInteger)0);

	[c editLiveLocationOfMessage:140 inChat:-70 latitude:50.45 longitude:30.52
					  livePeriod:600 completion:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastG(c, @"editMessageLiveLocation");
	XCTAssertEqual([r[@"message_id"] longLongValue], 140LL);
	XCTAssertEqual([r[@"location"][@"live_period"] integerValue], 600);
	answerG(c, @{@"@type" : @"message", @"id" : @(140)});
	XCTAssertTrue(ok);

	[c editLiveLocationOfMessage:140 inChat:-70 latitude:1 longitude:2
					  livePeriod:0 completion:nil];
	// The stop is the same request whose period says zero - TDLib keeps no
	// separate stop for a live location.
	XCTAssertEqual([lastG(c, @"editMessageLiveLocation")[@"location"][@"live_period"]
			integerValue], 0);
}

- (void)testLiveLocationFlattening_EditableOnlyWhileItRuns {
	// messageLiveLocation location:liveLocation expires_in:int32, and the
	// liveLocation itself nests the coordinates one further down - the
	// shape the flatten reads is the shape on the wire.
	NSDictionary *m = @{@"content" : @{@"@type" : @"messageLiveLocation",
			@"location" : @{@"location" : @{@"latitude" : @(50.45),
											@"longitude" : @(30.52)},
							@"live_period" : @(600)},
			@"expires_in" : @(240)}};
	NSDictionary *flat = TGFlattenMessage(m);
	XCTAssertTrue([flat[@"liveEditable"] boolValue]);
	// The card's own text says what is left, which is what a moving pin
	// reads as besides its map.
	XCTAssertTrue([flat[@"text"] hasPrefix:@"Live location"]);
	XCTAssertEqual([flat[@"lat"] doubleValue], 50.45);

	m = @{@"content" : @{@"@type" : @"messageLiveLocation",
			@"location" : @{@"location" : @{@"latitude" : @(50.45),
											@"longitude" : @(30.52)}},
			@"expires_in" : @(0)}};
	flat = TGFlattenMessage(m);
	XCTAssertFalse([flat[@"liveEditable"] boolValue],
				   @"a pin nobody can move is not a live location any more");
	XCTAssertEqual([flat[@"lat"] doubleValue], 50.45);
}


#pragma mark - the account's own door

- (void)testDeleteProfilePhoto_ThePhotoIdIsTheKey {
	TGClient *c = G();
	__block BOOL ok = YES;

	// Without an id there is nothing to name, and TDLib never hears it.
	[c deleteProfilePhoto:0 completion:^(BOOL good){ ok = good; }];
	XCTAssertFalse(ok);
	XCTAssertEqual(countG(c, @"deleteProfilePhoto"), (NSUInteger)0);

	[c deleteProfilePhoto:77 completion:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastG(c, @"deleteProfilePhoto");
	XCTAssertEqual([r[@"profile_photo_id"] longLongValue], 77LL);
	answerG(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	// Telegram refusing an id is not this app's lie to hide.
	[c deleteProfilePhoto:78 completion:^(BOOL good){ ok = good; }];
	answerG(c, @{@"@type" : @"error", @"message" : @"PHOTO_ID_INVALID"});
	XCTAssertFalse(ok);
}

- (void)testUserProfilePhotos_RowsCarryTheIdAndTheSmallFile {
	TGClient *c = G();
	__block NSArray *photos = nil;
	[c userProfilePhotos:1001 completion:^(NSArray *found){ photos = found; }];
	NSDictionary *r = lastG(c, @"getUserProfilePhotos");
	XCTAssertEqualObjects(r[@"@type"], @"getUserProfilePhotos");
	XCTAssertEqual([r[@"user_id"] longLongValue], 1001LL);
	XCTAssertEqual([r[@"offset"] integerValue], 0);
	XCTAssertTrue([r[@"limit"] integerValue] >= 50);

	// One good photo, one whose id is missing (nothing to delete it by),
	// one whose small file is missing (nothing to draw it from) - and the
	// answer keeps exactly the first.
	answerG(c, @{@"@type" : @"chatPhotos", @"total_count" : @3, @"photos" : @[
			@{@"@type" : @"chatPhoto", @"id" : @(9),
			  @"small" : @{@"@type" : @"file", @"id" : @(91)}},
			@{@"@type" : @"chatPhoto",
			  @"small" : @{@"@type" : @"file", @"id" : @(92)}},
			@{@"@type" : @"chatPhoto", @"id" : @(10)}]});
	XCTAssertEqual(photos.count, (NSUInteger)1);
	XCTAssertEqual([photos[0][@"photoId"] longLongValue], 9LL);
	XCTAssertEqual([photos[0][@"fileId"] integerValue], 91);
}

- (void)testMyUserLink_OnlyTheCurrentUsersLinkIsAskedFor {
	TGClient *c = G();
	__block NSString *link = nil;
	[c myUserLink:^(NSString *found){ link = found; }];
	NSDictionary *r = lastG(c, @"getUserLink");
	// The permanent link, without revoking the ones handed out before and
	// without charging anyone for messages across it.
	XCTAssertEqualObjects(r[@"remove_messages_fee"], @NO);
	XCTAssertEqualObjects(r[@"return_permanent_link"], @YES);
	XCTAssertEqualObjects(r[@"revoke_previous_links"], @NO);
	// The field on the wire is url, which is what a link is called here.
	answerG(c, @{@"@type" : @"userLink", @"url" : @"https://t.me/you",
				 @"expires_in" : @(0)});
	XCTAssertEqualObjects(link, @"https://t.me/you");
}

- (void)testGroupsInCommon_RowsThatOpenLikeChatRows {
	TGClient *c = G();
	__block NSArray *chats = nil;
	[c groupsInCommonWithUser:555 completion:^(NSArray *found){ chats = found; }];
	NSDictionary *r = lastG(c, @"getGroupsInCommon");
	XCTAssertEqual([r[@"user_id"] longLongValue], 555LL);
	XCTAssertEqual([r[@"offset_chat_id"] longLongValue], 0LL);
	XCTAssertTrue([r[@"limit"] integerValue] >= 50);
	// A group with no name is not a row anybody could tap; it is skipped
	// rather than shown blank.
	answerG(c, @{@"@type" : @"chats", @"chats" : @[
			@{@"@type" : @"chat", @"id" : @(-71), @"title" : @"Hike"},
			@{@"@type" : @"chat", @"id" : @(-72)},
			@{@"@type" : @"chat", @"id" : @(-73), @"title" : @""}]});
	XCTAssertEqual(chats.count, (NSUInteger)1);
	XCTAssertEqual([chats[0][@"chatId"] longLongValue], -71LL);
	XCTAssertEqualObjects(chats[0][@"title"], @"Hike");
}

#pragma mark - two-step verification from the wire's side

- (void)testSetPassword_WholeWriteInOneRequest {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c setPassword:@"old" new:@"fresh" hint:@"camp" setEmailAddress:NO email:nil
		  completion:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastG(c, @"setPassword");
	XCTAssertEqualObjects(r[@"old_password"], @"old");
	XCTAssertEqualObjects(r[@"new_password"], @"fresh");
	XCTAssertEqualObjects(r[@"new_hint"], @"camp");
	XCTAssertEqualObjects(r[@"set_recovery_email_address"], @NO);
	XCTAssertEqualObjects(r[@"new_recovery_email_address"], @"");
	answerG(c, @{@"@type" : @"passwordState"});
	XCTAssertTrue(ok);

	// An empty new password is the request that takes the password off, not
	// a refusal to write one.
	[c setPassword:@"old" new:@"" hint:@"" setEmailAddress:YES
			  email:@"e@example.com" completion:nil];
	r = lastG(c, @"setPassword");
	XCTAssertEqualObjects(r[@"new_password"], @"");
	XCTAssertEqualObjects(r[@"set_recovery_email_address"], @YES);
	XCTAssertEqualObjects(r[@"new_recovery_email_address"], @"e@example.com");
}

- (void)testRecoveryEmailAddress_ThePasswordThatOpensTheDoor {
	TGClient *c = G();
	__block NSString *email = nil;
	[c recoveryEmailAddress:@"wrong" completion:^(NSString *found){ email = found; }];
	NSDictionary *r = lastG(c, @"getRecoveryEmailAddress");
	XCTAssertEqualObjects(r[@"password"], @"wrong");
	// A wrong password is not the class with the address in it, and the
	// answer says so by being empty rather than by crashing.
	answerG(c, @{@"@type" : @"error", @"message" : @"PASSWORD_HASH_INVALID"});
	XCTAssertEqualObjects(email, @"");

	[c recoveryEmailAddress:@"right" completion:^(NSString *found){ email = found; }];
	answerG(c, @{@"@type" : @"recoveryEmailAddress",
				 @"recovery_email_address" : @"recovery@telegram.example"});
	XCTAssertEqualObjects(email, @"recovery@telegram.example");
}

- (void)testSetRecoveryEmailAddress_TheTwoFieldsItAnswersTo {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c setRecoveryEmailAddress:@"pw" to:@"recovery@telegram.example"
					completion:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastG(c, @"setRecoveryEmailAddress");
	XCTAssertEqualObjects(r[@"password"], @"pw");
	XCTAssertEqualObjects(r[@"new_recovery_email_address"],
						  @"recovery@telegram.example");
	answerG(c, @{@"@type" : @"passwordState"});
	XCTAssertTrue(ok);
}

#pragma mark - the last of the account

- (void)testTerminateAllOtherSessions_OneRequestThenOk {
	TGClient *c = G();
	__block BOOL ok = NO;
	[c terminateAllOtherSessions:^(BOOL good){ ok = good; }];
	XCTAssertEqualObjects(lastG(c, @"terminateAllOtherSessions")[@"@type"],
						  @"terminateAllOtherSessions");
	answerG(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeleteAccount_ReasonAndThePasswordItDemands {
	TGClient *c = G();
	__block BOOL ok = NO;

	// Two-step verification is on, so the password rides the last request.
	[c deleteAccountWithReason:@"unused phone" password:@"pw"
					completion:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastG(c, @"deleteAccount");
	XCTAssertEqualObjects(r[@"reason"], @"unused phone");
	XCTAssertEqualObjects(r[@"password"], @"pw");
	answerG(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);

	// Without a password, the field still says so, rather than being absent.
	[c deleteAccountWithReason:nil password:nil completion:nil];
	r = lastG(c, @"deleteAccount");
	XCTAssertEqualObjects(r[@"reason"], @"");
	XCTAssertEqualObjects(r[@"password"], @"");
}

@end
