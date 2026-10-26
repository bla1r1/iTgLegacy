// TGClientFoldersTests.m — the writing half of chat folders, the proxy list,
// and the report conversation.
//
// Folders were readable from the first day and could not be made, renamed or
// deleted; proxies had no request at all. All three are shapes that are easy
// to get subtly wrong — editChatFolder replaces a folder rather than patching
// it, reportChat answers before it accepts — so what the tests hold is the
// shape going out and the branch taken on the way back.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientFoldersTests : XCTestCase @end

static TGClient *F2(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	return c;
}

static NSDictionary *decode(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastOfType(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox){
		NSDictionary *r = decode(d);
		if ([r[@"@type"] isEqualToString:type])
			found = r;
	}
	return found;
}

static NSUInteger countOfType(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decode(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

/// Answers the request that is waiting on `extra`, the way the receive loop
/// does, so a completion handler runs inside the test.
static void answerLastRequest(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *r = decode(d);
		if (r[@"@extra"])
			sent = r;
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

@implementation TGClientFoldersTests

#pragma mark - folders

/// A folder TDLib will accept has every field of chatFolder on it, not just
/// the ones this app cares about.
- (void)testCreateFolder_SendsAWholeFolderObject {
	TGClient *c = F2();
	[c createFolderNamed:@"Work" icon:nil withChats:@[@(5), @(6)] completion:nil];

	NSDictionary *folder = lastOfType(c, @"createChatFolder")[@"folder"];
	XCTAssertNotNil(folder, @"createChatFolder must reach the outbox");
	XCTAssertEqualObjects(folder[@"@type"], @"chatFolder");
	XCTAssertEqualObjects(folder[@"name"][@"text"][@"text"], @"Work");
	XCTAssertEqualObjects(folder[@"included_chat_ids"], (@[@(5), @(6)]));
	// The flags TDLib has no default for.
	XCTAssertNotNil(folder[@"excluded_chat_ids"]);
	XCTAssertNotNil(folder[@"pinned_chat_ids"]);
	XCTAssertNotNil(folder[@"include_groups"]);
	XCTAssertNotNil(folder[@"exclude_archived"]);
}

/// A folder with no name is not a folder, and the request is not worth the
/// round trip.
- (void)testCreateFolder_NoNameSendsNothingAndAnswersZero {
	TGClient *c = F2();
	__block BOOL called = NO;
	__block NSInteger got = -1;
	[c createFolderNamed:@"" icon:nil withChats:@[] completion:^(NSInteger folderId){
		called = YES; got = folderId;
	}];
	XCTAssertEqual(countOfType(c, @"createChatFolder"), (NSUInteger)0);
	XCTAssertTrue(called);
	XCTAssertEqual(got, (NSInteger)0);
}

/// An edit replaces the folder, so a rename has to carry the chats it is not
/// touching — otherwise renaming a folder emptied it.
- (void)testEditFolder_RenameKeepsTheChatsItWasNotAskedAbout {
	TGClient *c = F2();
	[c editFolder:3 name:@"Renamed" chats:nil completion:nil];

	// It reads the folder first.
	XCTAssertNotNil(lastOfType(c, @"getChatFolder"));
	answerLastRequest(c, @{@"@type" : @"chatFolder",
			@"name" : @{@"@type" : @"chatFolderName",
						@"text" : @{@"@type" : @"formattedText", @"text" : @"Work"}},
			@"included_chat_ids" : @[@(5), @(6)],
			@"include_groups" : @YES});

	NSDictionary *folder = lastOfType(c, @"editChatFolder")[@"folder"];
	XCTAssertNotNil(folder, @"the edit must follow the read");
	XCTAssertEqualObjects(folder[@"name"][@"text"][@"text"], @"Renamed");
	XCTAssertEqualObjects(folder[@"included_chat_ids"], (@[@(5), @(6)]));
	XCTAssertTrue([folder[@"include_groups"] boolValue],
				  @"a flag the rename never mentioned must survive it");
}

/// The other way round: changing the chats must not lose the name.
- (void)testEditFolder_ChangingChatsKeepsTheName {
	TGClient *c = F2();
	[c editFolder:3 name:nil chats:@[@(9)] completion:nil];
	answerLastRequest(c, @{@"@type" : @"chatFolder",
			@"name" : @{@"@type" : @"chatFolderName",
						@"text" : @{@"@type" : @"formattedText", @"text" : @"Work"}},
			@"included_chat_ids" : @[@(5)]});

	NSDictionary *folder = lastOfType(c, @"editChatFolder")[@"folder"];
	XCTAssertEqualObjects(folder[@"name"][@"text"][@"text"], @"Work");
	XCTAssertEqualObjects(folder[@"included_chat_ids"], (@[@(9)]));
}

/// chatFolderInfo carries an id and chatFolder does not; sending one back
/// inside the folder is rejected.
- (void)testEditFolder_DoesNotSendTheIdBackInsideTheFolder {
	TGClient *c = F2();
	[c editFolder:3 name:@"Renamed" chats:nil completion:nil];
	answerLastRequest(c, @{@"@type" : @"chatFolder", @"id" : @(3),
						   @"has_my_invite_links" : @NO,
						   @"included_chat_ids" : @[]});

	NSDictionary *request = lastOfType(c, @"editChatFolder");
	XCTAssertEqual([request[@"chat_folder_id"] integerValue], (NSInteger)3);
	XCTAssertNil(request[@"folder"][@"id"]);
	XCTAssertNil(request[@"folder"][@"has_my_invite_links"]);
}

/// A folder that is gone answers with an error, and the edit must not be
/// built on it.
- (void)testEditFolder_AGoneFolderIsNotEdited {
	TGClient *c = F2();
	__block BOOL ok = YES;
	[c editFolder:3 name:@"Renamed" chats:nil completion:^(BOOL good){ ok = good; }];
	answerLastRequest(c, @{@"@type" : @"error", @"code" : @(400),
						   @"message" : @"CHAT_FOLDER_INVALID"});
	XCTAssertEqual(countOfType(c, @"editChatFolder"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

/// Deleting a folder is not leaving its chats, and the empty list is what
/// says so.
- (void)testDeleteFolder_LeavesNoChatsByDefault {
	TGClient *c = F2();
	[c deleteFolder:3 leavingChats:nil];
	NSDictionary *r = lastOfType(c, @"deleteChatFolder");
	XCTAssertEqual([r[@"chat_folder_id"] integerValue], (NSInteger)3);
	XCTAssertEqualObjects(r[@"leave_chat_ids"], @[]);
}

- (void)testReorderFolders_CarriesTheMainListPositionAndSkipsAnEmptyOrder {
	TGClient *c = F2();
	[c reorderFolderIds:@[] mainListAt:0];
	XCTAssertEqual(countOfType(c, @"reorderChatFolders"), (NSUInteger)0);

	[c reorderFolderIds:@[@(2), @(1)] mainListAt:1];
	NSDictionary *r = lastOfType(c, @"reorderChatFolders");
	XCTAssertEqualObjects(r[@"chat_folder_ids"], (@[@(2), @(1)]));
	XCTAssertEqual([r[@"main_chat_list_position"] integerValue], (NSInteger)1);
}

/// A suggestion comes with its own name and flags; adopting it must not
/// rewrite either.
- (void)testRecommendedFolders_FlattenToTitleAndDescriptionAndAreAdoptedWhole {
	TGClient *c = F2();
	__block NSArray *got = nil;
	[c recommendedFoldersWithCompletion:^(NSArray *folders){ got = folders; }];
	answerLastRequest(c, @{@"@type" : @"recommendedChatFolders",
			@"chat_folders" : @[@{@"description" : @"Unread chats only",
								  @"folder" : @{@"@type" : @"chatFolder",
												@"name" : @{@"text" : @{@"text" : @"Unread"}},
												@"exclude_read" : @YES}}]});
	XCTAssertEqual(got.count, (NSUInteger)1);
	XCTAssertEqualObjects(got[0][@"title"], @"Unread");
	XCTAssertEqualObjects(got[0][@"description"], @"Unread chats only");

	[c createRecommendedFolder:got[0][@"folder"] completion:nil];
	NSDictionary *folder = lastOfType(c, @"createChatFolder")[@"folder"];
	XCTAssertEqualObjects(folder[@"name"][@"text"][@"text"], @"Unread");
	XCTAssertTrue([folder[@"exclude_read"] boolValue]);
}

#pragma mark - proxies

- (void)testAddProxy_Socks5CarriesTheCredentialsAndEnablesAtOnce {
	TGClient *c = F2();
	[c addProxyAtServer:@"1.2.3.4" port:1080 kind:@"socks5"
			   username:@"u" password:@"p" secret:nil enable:YES completion:nil];

	NSDictionary *r = lastOfType(c, @"addProxy");
	XCTAssertEqualObjects(r[@"proxy"][@"server"], @"1.2.3.4");
	XCTAssertEqual([r[@"proxy"][@"port"] integerValue], (NSInteger)1080);
	XCTAssertEqualObjects(r[@"proxy"][@"type"][@"@type"], @"proxyTypeSocks5");
	XCTAssertEqualObjects(r[@"proxy"][@"type"][@"username"], @"u");
	XCTAssertTrue([r[@"enable"] boolValue]);
}

- (void)testAddProxy_MtprotoCarriesTheSecretInsteadOfCredentials {
	TGClient *c = F2();
	[c addProxyAtServer:@"host" port:443 kind:@"mtproto"
			   username:nil password:nil secret:@"deadbeef" enable:NO completion:nil];

	NSDictionary *type = lastOfType(c, @"addProxy")[@"proxy"][@"type"];
	XCTAssertEqualObjects(type[@"@type"], @"proxyTypeMtproto");
	XCTAssertEqualObjects(type[@"secret"], @"deadbeef");
	XCTAssertNil(type[@"username"]);
}

/// A port outside the range is a typo, and TDLib answers a plain error for
/// it; catching it here keeps the page's message useful.
- (void)testAddProxy_RefusesAnImpossibleServerOrPort {
	TGClient *c = F2();
	[c addProxyAtServer:@"" port:1080 kind:@"socks5" username:nil password:nil
				 secret:nil enable:YES completion:nil];
	[c addProxyAtServer:@"host" port:0 kind:@"socks5" username:nil password:nil
				 secret:nil enable:YES completion:nil];
	[c addProxyAtServer:@"host" port:70000 kind:@"socks5" username:nil password:nil
				 secret:nil enable:YES completion:nil];
	XCTAssertEqual(countOfType(c, @"addProxy"), (NSUInteger)0);
}

/// Their links are how a proxy actually arrives. A secret in one means
/// MTProto, a user name means SOCKS5.
- (void)testAddProxy_FromAnMtprotoLink {
	TGClient *c = F2();
	XCTAssertTrue([c addProxyFromLink:
			@"https://t.me/proxy?server=1.2.3.4&port=443&secret=ee00" completion:nil]);

	NSDictionary *proxy = lastOfType(c, @"addProxy")[@"proxy"];
	XCTAssertEqualObjects(proxy[@"server"], @"1.2.3.4");
	XCTAssertEqual([proxy[@"port"] integerValue], (NSInteger)443);
	XCTAssertEqualObjects(proxy[@"type"][@"@type"], @"proxyTypeMtproto");
	XCTAssertEqualObjects(proxy[@"type"][@"secret"], @"ee00");
}

- (void)testAddProxy_FromASocksLinkWithCredentials {
	TGClient *c = F2();
	XCTAssertTrue([c addProxyFromLink:
			@"tg://socks?server=h.example&port=1080&user=me&pass=secret" completion:nil]);

	NSDictionary *type = lastOfType(c, @"addProxy")[@"proxy"][@"type"];
	XCTAssertEqualObjects(type[@"@type"], @"proxyTypeSocks5");
	XCTAssertEqualObjects(type[@"username"], @"me");
	XCTAssertEqualObjects(type[@"password"], @"secret");
}

- (void)testAddProxy_ALinkWithNoServerIsRefusedRatherThanSent {
	TGClient *c = F2();
	XCTAssertFalse([c addProxyFromLink:@"https://t.me/proxy?port=443" completion:nil]);
	XCTAssertFalse([c addProxyFromLink:@"not a link at all" completion:nil]);
	XCTAssertEqual(countOfType(c, @"addProxy"), (NSUInteger)0);
}

/// The page shows which proxy is on, and the kind of each; both come out of
/// addedProxy rather than out of the proxy itself.
- (void)testProxies_FlattenToWhatARowNeeds {
	TGClient *c = F2();
	__block NSArray *got = nil;
	[c proxiesWithCompletion:^(NSArray *proxies){ got = proxies; }];
	answerLastRequest(c, @{@"@type" : @"addedProxies", @"proxies" : @[
			@{@"id" : @(2), @"is_enabled" : @YES, @"last_used_date" : @(99),
			  @"proxy" : @{@"server" : @"h", @"port" : @(1080),
						   @"type" : @{@"@type" : @"proxyTypeHttp"}}}]});

	XCTAssertEqual(got.count, (NSUInteger)1);
	XCTAssertEqual([got[0][@"id"] integerValue], (NSInteger)2);
	XCTAssertEqualObjects(got[0][@"kind"], @"http");
	XCTAssertTrue([got[0][@"enabled"] boolValue]);
}

/// Off carries no id: TDLib disables whichever one is on.
- (void)testDisableProxy_CarriesNoId {
	TGClient *c = F2();
	[c disableProxy];
	NSDictionary *r = lastOfType(c, @"disableProxy");
	XCTAssertNotNil(r);
	XCTAssertNil(r[@"proxy_id"]);
}

- (void)testPingProxy_NegativeWhenItDoesNotAnswer {
	TGClient *c = F2();
	__block double seconds = 0;
	[c pingProxyAtServer:@"h" port:1080 kind:@"socks5" username:nil password:nil
				  secret:nil completion:^(double s){ seconds = s; }];
	answerLastRequest(c, @{@"@type" : @"error", @"code" : @(400),
						   @"message" : @"Timeout"});
	XCTAssertTrue(seconds < 0, @"a proxy that does not answer must not read as 0 ms");
}

#pragma mark - reporting

/// The first call is a question, not a report: the options come back and
/// nothing has been sent yet.
- (void)testReportChat_FirstCallAnswersWithTheReasons {
	TGClient *c = F2();
	__block NSArray *options = nil;
	__block NSString *title = nil;
	__block BOOL done = YES;
	[c reportChat:7 optionId:nil text:nil
	   completion:^(NSString *t, NSArray *o, BOOL d){
		title = t; options = o; done = d;
	}];
	XCTAssertEqualObjects(lastOfType(c, @"reportChat")[@"option_id"], @"");

	answerLastRequest(c, @{@"@type" : @"reportChatResultOptionRequired",
			@"title" : @"Report", @"options" : @[
					@{@"id" : @"c3BhbQ", @"text" : @"Spam"},
					@{@"id" : @"dmlvbA", @"text" : @"Violence"}]});

	XCTAssertEqualObjects(title, @"Report");
	XCTAssertEqual(options.count, (NSUInteger)2);
	XCTAssertEqualObjects(options[0][@"text"], @"Spam");
	XCTAssertEqualObjects(options[0][@"id"], @"c3BhbQ");
	XCTAssertFalse(done);
}

- (void)testReportChat_SecondCallCarriesTheChosenOptionAndIsAccepted {
	TGClient *c = F2();
	__block BOOL done = NO;
	__block NSArray *options = nil;
	[c reportChat:7 optionId:@"c3BhbQ" text:@""
	   completion:^(NSString *t, NSArray *o, BOOL d){ options = o; done = d; }];
	XCTAssertEqualObjects(lastOfType(c, @"reportChat")[@"option_id"], @"c3BhbQ");

	answerLastRequest(c, @{@"@type" : @"reportChatResultOk"});
	XCTAssertTrue(done);
	XCTAssertEqual(options.count, (NSUInteger)0);
}

/// A reason that wants free text or named messages is a step this app has
/// none for; it must read as not done rather than as accepted.
- (void)testReportChat_AStepTheAppCannotTakeIsNotReportedAsDone {
	TGClient *c = F2();
	__block BOOL done = YES;
	__block NSArray *options = nil;
	[c reportChat:7 optionId:@"x" text:nil
	   completion:^(NSString *t, NSArray *o, BOOL d){ options = o; done = d; }];
	answerLastRequest(c, @{@"@type" : @"reportChatResultTextRequired",
						   @"option_id" : @"x", @"is_optional" : @NO});
	XCTAssertFalse(done);
	XCTAssertEqual(options.count, (NSUInteger)0);
}

#pragma mark - polls and the action bar

- (void)testStopPoll_NamesTheMessage {
	TGClient *c = F2();
	[c stopPoll:15 inChat:7];
	NSDictionary *r = lastOfType(c, @"stopPoll");
	XCTAssertEqual([r[@"message_id"] longLongValue], 15LL);
	XCTAssertEqual([r[@"chat_id"] longLongValue], 7LL);
}

- (void)testRemoveActionBar_SendsForTheChat {
	TGClient *c = F2();
	[c removeActionBarInChat:7];
	XCTAssertEqual([lastOfType(c, @"removeChatActionBar")[@"chat_id"]
			longLongValue], 7LL);
}

- (void)testRecents_RememberAndForgetNameTheChat {
	TGClient *c = F2();
	[c rememberFoundChat:7];
	XCTAssertEqual([lastOfType(c, @"addRecentlyFoundChat")[@"chat_id"]
			longLongValue], 7LL);

	[c forgetTopChat:7];
	NSDictionary *forget = lastOfType(c, @"removeTopChat");
	XCTAssertEqual([forget[@"chat_id"] longLongValue], 7LL);
	XCTAssertEqualObjects(forget[@"category"][@"@type"], @"topChatCategoryUsers");
}


#pragma mark - the strip dragged into a new order

- (void)testReorderFoldersLocally_TheStripHoldsItBeforeTheWireSaysSo {
	// The reorder is local-first: the strip re-renders from folders, so the
	// drag has to land there before the request is even on the wire.
	TGClient *c = F2();
	c.folders = (@[@{@"id" : @(1), @"title" : @"Work"},
				   @{@"id" : @(2), @"title" : @"Home"},
				   @{@"id" : @(3), @"title" : @"Noise"}]);

	__block NSInteger changed = 0;
	__weak TGClient *me = c;
	c.onChatsChanged = ^{ changed++; };

	// The drag moved Work to the end: noise would follow it down the list[0].
	[c reorderFoldersToLocalIds:@[@(2), @(3), @(1)] mainListAt:0];
	NSArray *order = c.folders;
	XCTAssertEqual(order.count, (NSUInteger)3);
	XCTAssertEqualObjects(order[0][@"title"], @"Home");
	XCTAssertEqualObjects(order[1][@"title"], @"Noise");
	XCTAssertEqualObjects(order[2][@"title"], @"Work");
	XCTAssertEqual(changed, 1, @"the strip rebuilds off the local order");

	NSDictionary *sent = lastOfType(c, @"reorderChatFolders");
	XCTAssertEqualObjects(sent[@"chat_folder_ids"], (@[@(2), @(3), @(1)]));
	XCTAssertEqual([sent[@"main_chat_list_position"] integerValue], 0);
}

- (void)testReorderFoldersLocally_AnIdTheDragForgotStillFitsSomewhere {
	// An order that names a folder the client never heard of, or drops one
	// it did: neither may take a folder off the strip. Unknown ids are
	// skipped, forgotten ones ride at the end - a pill that vanishes on a
	// successful drag is worse than one in a slot TDLib never asked for.
	TGClient *c = F2();
	c.folders = (@[@{@"id" : @(1), @"title" : @"Work"},
				   @{@"id" : @(2), @"title" : @"Home"}]);

	[c reorderFoldersToLocalIds:@[@(9), @(2)] mainListAt:0];
	NSArray *order = c.folders;
	XCTAssertEqual(order.count, (NSUInteger)2);
	XCTAssertEqualObjects(order[0][@"title"], @"Home");
	XCTAssertEqualObjects(order[1][@"title"], @"Work");

	NSDictionary *sent = lastOfType(c, @"reorderChatFolders");
	// The wire carries the dragged order itself, not the padded one - the
	// server's authority is what the finger did, and Telegram's answer
	// updates the strip on its own.
	XCTAssertEqualObjects(sent[@"chat_folder_ids"], (@[@(9), @(2)]));
}

#pragma mark - reading a whole list, the archive settings

/// The badge on "All chats" or a folder pill is a chat list's own counter,
/// and one request clears it: folder 0 speaks for chatListMain, a real id
/// for its chatListFolder.
- (void)testReadChatList_ThePillSaysWhichListItMeans {
	TGClient *c = F2();

	[c readChatListOfFolder:0 archived:NO];
	NSDictionary *main = lastOfType(c, @"readChatList");
	XCTAssertEqualObjects(main[@"chat_list"][@"@type"], @"chatListMain");

	[c readChatListOfFolder:7 archived:NO];
	NSDictionary *folder = lastOfType(c, @"readChatList");
	XCTAssertEqualObjects(folder[@"chat_list"][@"@type"], @"chatListFolder");
	XCTAssertEqual([folder[@"chat_list"][@"chat_folder_id"] integerValue], 7);
}

/// The archive screen is a chat list of its own, and its "Mark Read" has
/// to name that list and not the main one.
- (void)testReadChatList_TheArchiveIsAListOfItsOwn {
	TGClient *c = F2();

	[c readChatListOfFolder:0 archived:YES];
	NSDictionary *archive = lastOfType(c, @"readChatList");
	XCTAssertEqualObjects(archive[@"chat_list"][@"@type"], @"chatListArchive");
}

/// The settings page draws off the cached copy before any answer arrives,
/// so a refresh must swap the copy and run its completion either way.
- (void)testArchiveSettings_TheRefreshSwapsTheCachedCopyUnderThePage {
	TGClient *c = F2();
	c.archiveSettings = nil;

	__block BOOL ran = NO;
	[c refreshArchiveChatListSettings:^{ ran = YES; }];
	answerLastRequest(c, @{@"@type" : @"archiveChatListSettings",
			@"archive_and_mute_new_chats_from_unknown_users" : @YES,
			@"keep_unmuted_chats_archived"                   : @NO,
			@"keep_chats_from_folders_archived"              : @NO});
	XCTAssertTrue(ran, @"the page redraws on the fresh copy, good or bad");
	XCTAssertTrue([c.archiveSettings[@"archive_and_mute_new_chats_from_unknown_users"] boolValue],
			@"the copy the page reads holds the answer's bits");

	// A broken answer must not leave the page with nothing to read: an
	// error completion still runs, and the copy goes empty rather than nil.
	c.archiveSettings = nil;
	ran = NO;
	[c refreshArchiveChatListSettings:^{ ran = YES; }];
	answerLastRequest(c, @{@"@type" : @"error", @"code" : @400,
			@"message" : @"not now"});
	XCTAssertTrue(ran);
	XCTAssertNotNil(c.archiveSettings, @"empty, not nil - the page reads it");
}

/// The three switches are one TDLib object: the local copy flips first so
/// the redraw never flickers back, then the whole object goes on the wire.
- (void)testArchiveSettings_TheSwitchesSendOneObjectNotThree {
	TGClient *c = F2();
	c.archiveSettings = @{@"@type" : @"archiveChatListSettings",
			@"archive_and_mute_new_chats_from_unknown_users" : @NO,
			@"keep_unmuted_chats_archived"                   : @NO,
			@"keep_chats_from_folders_archived"              : @NO};

	[c setArchiveSettingsArchiveAndMute:YES
					keepUnmutedArchived:YES
			  keepFolderChatsArchived:NO];

	XCTAssertTrue([c.archiveSettings[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]);
	XCTAssertTrue([c.archiveSettings[@"keep_unmuted_chats_archived"] boolValue]);
	XCTAssertFalse([c.archiveSettings[@"keep_chats_from_folders_archived"] boolValue]);

	NSDictionary *sent = lastOfType(c, @"setArchiveChatListSettings");
	NSDictionary *settings = sent[@"settings"];
	XCTAssertTrue([settings isKindOfClass:NSDictionary.class]);
	XCTAssertEqualObjects(settings[@"@type"], @"archiveChatListSettings");
	XCTAssertTrue([settings[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]);
	XCTAssertTrue([settings[@"keep_unmuted_chats_archived"] boolValue]);
	XCTAssertFalse([settings[@"keep_chats_from_folders_archived"] boolValue]);
}

@end
