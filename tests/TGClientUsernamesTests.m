//
// TGClientUsernamesTests.m - the account's usernames, a supergroup's username
// and mode switches, the default administrator-rights presets, and the basic
// group record the debug resolver reads.
//
// The requests are small; what these tests hold is the shape each one takes
// and the two places it is easy to get backwards: a username that must be
// switched off without touching the editable one, and a broadcast conversion
// that has no inverse.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientUsernamesTests : XCTestCase @end

static TGClient *UsernamesClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c removeAllFileWaiters];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeUsernamesClient(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastUsernamesClient(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeUsernamesClient(d)[@"@type"] isEqualToString:type])
			found = decodeUsernamesClient(d);
	return found;
}

static NSUInteger countUsernamesClient(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeUsernamesClient(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

/// Answers the oldest request of `type` that is still waiting for a reply.
/// A category that resolves the supergroup id first sends two requests in a
/// row, so "the last request in the outbox" is not always the one to answer.
static void replyUsernamesClient(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *request = decodeUsernamesClient(d);
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

static void resolveSupergroupUsernamesClient(TGClient *c, int64_t supergroupId) {
	replyUsernamesClient(c, @"getChat", @{@"@type" : @"chat", @"id" : @(-70),
			@"type" : @{@"@type" : @"chatTypeSupergroup",
						@"supergroup_id" : @(supergroupId)}});
}

@implementation TGClientUsernamesTests

#pragma mark - the account

- (void)testAccountUsernames_ReadTheThreeListsFromGetMe {
	TGClient *c = UsernamesClient();
	__block NSDictionary *got = nil;
	[c accountUsernamesWithCompletion:^(NSDictionary *usernames){ got = usernames; }];
	XCTAssertEqualObjects(lastUsernamesClient(c, @"getMe")[@"@type"], @"getMe");

	replyUsernamesClient(c, @"getMe", @{@"@type" : @"user", @"id" : @(1001),
			@"usernames" : @{@"active_usernames" : @[@"main", @"second"],
							 @"disabled_usernames" : @[@"old"],
							 @"editable_username" : @"main"}});

	XCTAssertEqualObjects(got[@"editable_username"], @"main");
	XCTAssertEqualObjects(got[@"active_usernames"], (@[@"main", @"second"]));
	XCTAssertEqualObjects(got[@"disabled_usernames"], (@[@"old"]));
}

- (void)testAccountUsernames_AnErrorAnswersNil {
	TGClient *c = UsernamesClient();
	__block BOOL called = NO;
	__block NSDictionary *got = @{};
	[c accountUsernamesWithCompletion:^(NSDictionary *usernames){
		called = YES; got = usernames;
	}];
	replyUsernamesClient(c, @"getMe", @{@"@type" : @"error", @"code" : @(401),
			@"message" : @"UNAUTHORIZED"});
	XCTAssertTrue(called);
	XCTAssertNil(got);
}

- (void)testToggleUsernameIsActive_SendsTheNameAndTheFlag {
	TGClient *c = UsernamesClient();
	__block BOOL ok = NO;
	[c toggleUsernameIsActive:@"second" isActive:NO
			completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastUsernamesClient(c, @"toggleUsernameIsActive");
	XCTAssertEqualObjects(r[@"username"], @"second");
	XCTAssertFalse([r[@"is_active"] boolValue]);
	replyUsernamesClient(c, @"toggleUsernameIsActive", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testToggleUsernameIsActive_AnEmptyNameSendsNothing {
	TGClient *c = UsernamesClient();
	__block NSString *error = nil;
	[c toggleUsernameIsActive:@"" isActive:YES
			completion:^(BOOL ok, NSString *why){ error = why; }];
	XCTAssertEqual(countUsernamesClient(c, @"toggleUsernameIsActive"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

- (void)testReorderActiveUsernames_SendsEveryActiveNameInOrder {
	TGClient *c = UsernamesClient();
	__block BOOL ok = NO;
	[c reorderActiveUsernames:@[@"second", @"main"]
			completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastUsernamesClient(c, @"reorderActiveUsernames");
	XCTAssertEqualObjects(r[@"usernames"], (@[@"second", @"main"]));
	replyUsernamesClient(c, @"reorderActiveUsernames", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testReorderActiveUsernames_ARejectionKeepsTelegramSWords {
	TGClient *c = UsernamesClient();
	__block NSString *error = nil;
	[c reorderActiveUsernames:@[@"main"]
			completion:^(BOOL ok, NSString *why){ error = why; }];
	replyUsernamesClient(c, @"reorderActiveUsernames", @{@"@type" : @"error",
			@"message" : @"USERNAMES_ACTIVE_TOO_MUCH"});
	XCTAssertEqualObjects(error, @"USERNAMES_ACTIVE_TOO_MUCH");
}

#pragma mark - the supergroup's record

- (void)testSupergroupSettings_ReadBothRecordsAndFlattenTheTab {
	TGClient *c = UsernamesClient();
	__block NSDictionary *settings = nil;
	[c supergroupSettingsForChat:-70 completion:^(NSDictionary *found){ settings = found; }];
	resolveSupergroupUsernamesClient(c, 4);
	XCTAssertEqual([lastUsernamesClient(c, @"getSupergroup")[@"supergroup_id"] longLongValue], 4LL);

	replyUsernamesClient(c, @"getSupergroup", @{@"@type" : @"supergroup", @"id" : @(4),
			@"usernames" : @{@"active_usernames" : @[@"walkers"],
							 @"disabled_usernames" : @[@"old_walkers"],
							 @"editable_username" : @"walkers"},
			@"is_forum" : @YES, @"has_forum_tabs" : @YES,
			@"join_by_request" : @YES, @"is_broadcast_group" : @NO,
			@"has_automatic_translation" : @YES});
	replyUsernamesClient(c, @"getSupergroupFullInfo", @{@"@type" : @"supergroupFullInfo",
			@"can_set_username" : @YES, @"can_hide_members" : @YES,
			@"has_hidden_members" : @YES,
			@"main_profile_tab" : @{@"@type" : @"profileTabFiles"}});

	XCTAssertEqualObjects(settings[@"editable"], @"walkers");
	XCTAssertEqualObjects(settings[@"active"], (@[@"walkers"]));
	XCTAssertEqualObjects(settings[@"disabled"], (@[@"old_walkers"]));
	XCTAssertTrue([settings[@"isForum"] boolValue]);
	XCTAssertTrue([settings[@"joinByRequest"] boolValue]);
	XCTAssertTrue([settings[@"hiddenMembers"] boolValue]);
	XCTAssertTrue([settings[@"automaticTranslation"] boolValue]);
	XCTAssertEqualObjects(settings[@"mainTab"], @"files");
}

- (void)testSupergroupSettings_ABasicGroupAnswersNil {
	TGClient *c = UsernamesClient();
	__block BOOL called = NO;
	__block NSDictionary *settings = @{};
	[c supergroupSettingsForChat:-70 completion:^(NSDictionary *found){
		called = YES; settings = found;
	}];
	replyUsernamesClient(c, @"getChat", @{@"@type" : @"chat", @"id" : @(-70),
			@"type" : @{@"@type" : @"chatTypeBasicGroup", @"basic_group_id" : @(3)}});
	XCTAssertTrue(called);
	XCTAssertNil(settings);
}

#pragma mark - the supergroup's username

- (void)testSetSupergroupUsername_NamesTheSupergroupId {
	TGClient *c = UsernamesClient();
	__block BOOL ok = NO;
	[c setSupergroupUsername:@"walkers" inChat:-70
			completion:^(BOOL good, NSString *error){ ok = good; }];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"setSupergroupUsername");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertEqualObjects(r[@"username"], @"walkers");
	replyUsernamesClient(c, @"setSupergroupUsername", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetSupergroupUsername_AnEmptyStringRemovesIt {
	TGClient *c = UsernamesClient();
	[c setSupergroupUsername:@"" inChat:-70 completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	XCTAssertEqualObjects(lastUsernamesClient(c, @"setSupergroupUsername")[@"username"], @"");
}

- (void)testToggleSupergroupUsernameIsActive_CarriesTheFlag {
	TGClient *c = UsernamesClient();
	[c toggleSupergroupUsernameIsActive:@"old_walkers" inChat:-70 isActive:YES
			completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"toggleSupergroupUsernameIsActive");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertEqualObjects(r[@"username"], @"old_walkers");
	XCTAssertTrue([r[@"is_active"] boolValue]);
}

- (void)testReorderSupergroupActiveUsernames_SendsTheWholeList {
	TGClient *c = UsernamesClient();
	[c reorderSupergroupActiveUsernames:@[@"b", @"a"] inChat:-70 completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"reorderSupergroupActiveUsernames");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertEqualObjects(r[@"usernames"], (@[@"b", @"a"]));
}

- (void)testDisableAllSupergroupUsernames_IsOneRequest {
	TGClient *c = UsernamesClient();
	__block BOOL ok = NO;
	[c disableAllSupergroupUsernamesInChat:-70
			completion:^(BOOL good, NSString *error){ ok = good; }];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"disableAllSupergroupUsernames");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	replyUsernamesClient(c, @"disableAllSupergroupUsernames", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - the mode switches

- (void)testForumMode_SendsTheFlagAndTheTabsTogether {
	TGClient *c = UsernamesClient();
	[c setSupergroupForumInChat:-70 on:YES completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"toggleSupergroupIsForum");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertTrue([r[@"is_forum"] boolValue]);
	XCTAssertTrue([r[@"has_forum_tabs"] boolValue]);
}

- (void)testJoinByRequest_KeepsTheGroupsGuardBotAndAppliesToLinks {
	TGClient *c = UsernamesClient();
	[c setSupergroupJoinByRequestInChat:-70 on:YES guardBotUserId:42 completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"toggleSupergroupJoinByRequest");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertTrue([r[@"join_by_request"] boolValue]);
	XCTAssertEqual([r[@"guard_bot_user_id"] longLongValue], 42LL);
	XCTAssertTrue([r[@"apply_to_invite_links"] boolValue]);
}

- (void)testHiddenMembers_SendsTheFlag {
	TGClient *c = UsernamesClient();
	[c setSupergroupHiddenMembersInChat:-70 on:NO completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"toggleSupergroupHasHiddenMembers");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertFalse([r[@"has_hidden_members"] boolValue]);
}

- (void)testBroadcastConversion_HasNoBooleanToSend {
	TGClient *c = UsernamesClient();
	__block NSString *error = nil;
	[c convertSupergroupToBroadcastInChat:-70
			completion:^(BOOL ok, NSString *why){ error = why; }];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"toggleSupergroupIsBroadcastGroup");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertNil(r[@"is_broadcast_group"]);
	replyUsernamesClient(c, @"toggleSupergroupIsBroadcastGroup", @{@"@type" : @"error",
			@"message" : @"CHAT_NOT_MODIFIED"});
	XCTAssertEqualObjects(error, @"CHAT_NOT_MODIFIED");
}

- (void)testAutomaticTranslation_SendsTheFlag {
	TGClient *c = UsernamesClient();
	[c setSupergroupAutomaticTranslationInChat:-70 on:YES completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"toggleSupergroupHasAutomaticTranslation");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertTrue([r[@"has_automatic_translation"] boolValue]);
}

- (void)testMainProfileTab_MapsTheWordToTDLibsObject {
	TGClient *c = UsernamesClient();
	[c setSupergroupMainProfileTab:@"media" inChat:-70 completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	NSDictionary *r = lastUsernamesClient(c, @"setSupergroupMainProfileTab");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 4LL);
	XCTAssertEqualObjects(r[@"main_profile_tab"][@"@type"], @"profileTabMedia");

	// An unknown word must not produce a constructor TDLib has never heard of.
	[c.outbox removeAllObjects];
	[c setSupergroupMainProfileTab:@"nonsense" inChat:-70 completion:nil];
	resolveSupergroupUsernamesClient(c, 4);
	XCTAssertEqualObjects(lastUsernamesClient(c, @"setSupergroupMainProfileTab")[@"main_profile_tab"][@"@type"],
						  @"profileTabPosts");
}

#pragma mark - default administrator rights

- (void)testAdministratorRightsPresets_FillEveryBooleanTDLibAsksFor {
	NSDictionary *standard = [TGClient administratorRightsForPreset:@"standard"];
	NSDictionary *posting  = [TGClient administratorRightsForPreset:@"posting"];
	NSDictionary *full     = [TGClient administratorRightsForPreset:@"full"];
	XCTAssertEqualObjects(standard[@"@type"], @"chatAdministratorRights");
	XCTAssertTrue([standard[@"can_manage_chat"] boolValue]);
	XCTAssertFalse([standard[@"can_post_messages"] boolValue]);
	XCTAssertTrue([posting[@"can_post_messages"] boolValue]);
	XCTAssertTrue([full[@"can_promote_members"] boolValue]);
	// Every field is present: a missing one makes the object malformed, not
	// merely permissive.
	XCTAssertEqual(standard.count, (NSUInteger)19);
}

- (void)testDefaultGroupRights_SendsTheRightsObject {
	TGClient *c = UsernamesClient();
	__block BOOL ok = NO;
	[c setDefaultGroupAdministratorRightsPreset:@"posting"
			completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastUsernamesClient(c, @"setDefaultGroupAdministratorRights");
	NSDictionary *rights = r[@"default_group_administrator_rights"];
	XCTAssertEqualObjects(rights[@"@type"], @"chatAdministratorRights");
	XCTAssertTrue([rights[@"can_post_messages"] boolValue]);
	replyUsernamesClient(c, @"setDefaultGroupAdministratorRights", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDefaultChannelRights_ShowsTheServersRefusal {
	TGClient *c = UsernamesClient();
	__block BOOL ok = YES;
	__block NSString *error = nil;
	[c setDefaultChannelAdministratorRightsPreset:@"full"
			completion:^(BOOL good, NSString *why){ ok = good; error = why; }];
	XCTAssertNotNil(lastUsernamesClient(c, @"setDefaultChannelAdministratorRights")
			[@"default_channel_administrator_rights"]);
	replyUsernamesClient(c, @"setDefaultChannelAdministratorRights", @{@"@type" : @"error",
			@"message" : @"The method is available only for bots"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(error, @"The method is available only for bots");
}

#pragma mark - the basic group record

- (void)testBasicGroupInfo_ReadsTheRecordAndTheChatName {
	TGClient *c = UsernamesClient();
	__block NSDictionary *info = nil;
	[c basicGroupInfo:12 completion:^(NSDictionary *found){ info = found; }];
	XCTAssertEqual([lastUsernamesClient(c, @"getBasicGroup")[@"basic_group_id"] longLongValue], 12LL);

	replyUsernamesClient(c, @"getBasicGroup", @{@"@type" : @"basicGroup", @"id" : @(12),
			@"member_count" : @(7), @"is_active" : @YES,
			@"upgraded_to_supergroup_id" : @(0),
			@"status" : @{@"@type" : @"chatMemberStatusAdministrator"}});
	replyUsernamesClient(c, @"createBasicGroupChat", @{@"@type" : @"chat", @"id" : @(-70),
			@"title" : @"Walkers"});

	XCTAssertEqualObjects(info[@"title"], @"Walkers");
	XCTAssertEqual([info[@"members"] integerValue], 7);
	XCTAssertEqualObjects(info[@"status"], @"admin");
	XCTAssertTrue([info[@"active"] boolValue]);
	XCTAssertEqual([info[@"upgradedTo"] longLongValue], 0LL);
}

- (void)testBasicGroupInfo_AnErrorAnswersNil {
	TGClient *c = UsernamesClient();
	__block BOOL called = NO;
	[c basicGroupInfo:12 completion:^(NSDictionary *found){ called = YES; }];
	replyUsernamesClient(c, @"getBasicGroup", @{@"@type" : @"error",
			@"message" : @"Basic group not found"});
	XCTAssertTrue(called);
	XCTAssertEqual(countUsernamesClient(c, @"createBasicGroupChat"), (NSUInteger)0);
}

@end
