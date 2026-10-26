// TGClientAccountTests.m — two-step verification, the recovery address, the
// end of the account, and the three profile reads behind the avatar gallery.
//
// All of these ask for or answer about a password, and every one of them is a
// request where getting the shape wrong is quiet rather than loud: an empty
// new password is how TDLib spells "turn it off", so a flow that sends one by
// accident removes the user's password instead of setting it.
//
// Nothing here stores a password. Each call carries the one just typed, and
// the tests use obvious stand-ins.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientAccountTests : XCTestCase @end

static TGClient *A(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

static NSDictionary *decodeA(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastA(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeA(d)[@"@type"] isEqualToString:type])
			found = decodeA(d);
	return found;
}

static NSUInteger countA(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeA(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void answerA(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeA(d)[@"@extra"])
			sent = decodeA(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

@implementation TGClientAccountTests

#pragma mark - the password state the screen is built from

/// passwordState has no "recovery_email_address_pattern". The screen read
/// that absent key, so it never once showed that an address was set.
- (void)testPasswordState_AnAddressThatIsSetIsReportedAsSet {
	TGClient *c = A();
	__block BOOL has = NO;
	__block NSString *email = nil;
	[c hasPasswordWithCompletion:^(BOOL hasPassword, NSString *address){
		has = hasPassword; email = address;
	}];
	answerA(c, @{@"@type" : @"passwordState",
				 @"has_password" : @YES,
				 @"has_recovery_email_address" : @YES,
				 @"password_hint" : @"the usual"});
	XCTAssertTrue(has);
	XCTAssertTrue(email.length > 0, @"an address that exists must not read as none");
}

/// While a code sent to a new address is outstanding, the pattern is what
/// there is to show, and it is more useful than the flag.
- (void)testPasswordState_APendingAddressShowsItsPattern {
	TGClient *c = A();
	__block NSString *email = nil;
	[c hasPasswordWithCompletion:^(BOOL has, NSString *address){ email = address; }];
	answerA(c, @{@"@type" : @"passwordState",
				 @"has_password" : @YES,
				 @"has_recovery_email_address" : @NO,
				 @"recovery_email_address_code_info" :
						@{@"email_address_pattern" : @"p**@example.com"}});
	XCTAssertEqualObjects(email, @"p**@example.com");
}

- (void)testPasswordState_NoPasswordAndNoAddressIsEmptyRatherThanNil {
	TGClient *c = A();
	__block BOOL has = YES;
	__block NSString *email = nil;
	[c hasPasswordWithCompletion:^(BOOL hasPassword, NSString *address){
		has = hasPassword; email = address;
	}];
	answerA(c, @{@"@type" : @"passwordState", @"has_password" : @NO});
	XCTAssertFalse(has);
	XCTAssertEqualObjects(email, @"");
}

#pragma mark - setting, changing, turning off

/// Setting a first password carries no old one, and must not offer to set a
/// recovery address it was not given.
- (void)testSetPassword_FirstOneCarriesNoOldPasswordAndNoAddress {
	TGClient *c = A();
	[c setPassword:nil new:@"correct-horse" hint:@"the usual"
   setEmailAddress:NO email:nil completion:nil];

	NSDictionary *r = lastA(c, @"setPassword");
	XCTAssertEqualObjects(r[@"old_password"], @"");
	XCTAssertEqualObjects(r[@"new_password"], @"correct-horse");
	XCTAssertEqualObjects(r[@"new_hint"], @"the usual");
	XCTAssertFalse([r[@"set_recovery_email_address"] boolValue]);
	XCTAssertEqualObjects(r[@"new_recovery_email_address"], @"");
}

- (void)testSetPassword_ChangingCarriesTheOldOne {
	TGClient *c = A();
	[c setPassword:@"old-one" new:@"new-one" hint:@"" setEmailAddress:NO
			 email:nil completion:nil];
	XCTAssertEqualObjects(lastA(c, @"setPassword")[@"old_password"], @"old-one");
}

/// Turning it off is an empty new password. This is the shape the flow must
/// only ever send on purpose.
- (void)testSetPassword_AnEmptyNewPasswordIsHowOffIsSpelled {
	TGClient *c = A();
	[c setPassword:@"old-one" new:@"" hint:@"" setEmailAddress:NO
			 email:nil completion:nil];
	NSDictionary *r = lastA(c, @"setPassword");
	XCTAssertEqualObjects(r[@"new_password"], @"");
	XCTAssertEqualObjects(r[@"old_password"], @"old-one");
}

/// A wrong current password is the common failure, and TDLib says so with an
/// error rather than a passwordState.
- (void)testSetPassword_AWrongOldPasswordIsNotSuccess {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c setPassword:@"wrong" new:@"new-one" hint:@"" setEmailAddress:NO
			 email:nil completion:^(BOOL good){ ok = good; }];
	answerA(c, @{@"@type" : @"error", @"code" : @(400),
				 @"message" : @"PASSWORD_HASH_INVALID"});
	XCTAssertFalse(ok);
}

- (void)testSetPassword_ARecoveryAddressRidesAlongOnlyWhenAsked {
	TGClient *c = A();
	[c setPassword:nil new:@"new-one" hint:@"" setEmailAddress:YES
			 email:@"me@example.com" completion:nil];
	NSDictionary *r = lastA(c, @"setPassword");
	XCTAssertTrue([r[@"set_recovery_email_address"] boolValue]);
	XCTAssertEqualObjects(r[@"new_recovery_email_address"], @"me@example.com");
}

#pragma mark - the recovery address

/// Reading the address back is also how a typed password is checked, so a
/// wrong one has to come back as nothing rather than as an empty address
/// that reads like "none is set".
- (void)testRecoveryAddress_ReadsBackWithTheRightPassword {
	TGClient *c = A();
	__block NSString *email = nil;
	[c recoveryEmailAddress:@"correct-horse" completion:^(NSString *address){
		email = address;
	}];
	XCTAssertEqualObjects(lastA(c, @"getRecoveryEmailAddress")[@"password"],
						  @"correct-horse");
	answerA(c, @{@"@type" : @"recoveryEmailAddress",
				 @"recovery_email_address" : @"me@example.com"});
	XCTAssertEqualObjects(email, @"me@example.com");
}

- (void)testRecoveryAddress_AWrongPasswordAnswersEmpty {
	TGClient *c = A();
	__block NSString *email = @"unset";
	[c recoveryEmailAddress:@"wrong" completion:^(NSString *address){ email = address; }];
	answerA(c, @{@"@type" : @"error", @"message" : @"PASSWORD_HASH_INVALID"});
	XCTAssertEqualObjects(email, @"");
}

- (void)testRecoveryAddress_SettingOneCarriesBothTheAddressAndThePassword {
	TGClient *c = A();
	[c setRecoveryEmailAddress:@"correct-horse" to:@"new@example.com"
					completion:nil];
	NSDictionary *r = lastA(c, @"setRecoveryEmailAddress");
	XCTAssertEqualObjects(r[@"password"], @"correct-horse");
	XCTAssertEqualObjects(r[@"new_recovery_email_address"], @"new@example.com");
}

#pragma mark - the end of the account

/// The reason is free text and the password is only needed when two-step
/// verification is on, so an account without one must still be deletable.
- (void)testDeleteAccount_CarriesTheReasonAndAnEmptyPasswordWhenThereIsNone {
	TGClient *c = A();
	[c deleteAccountWithReason:@"moving on" password:nil completion:nil];
	NSDictionary *r = lastA(c, @"deleteAccount");
	XCTAssertEqualObjects(r[@"reason"], @"moving on");
	XCTAssertEqualObjects(r[@"password"], @"");
}

- (void)testDeleteAccount_AnErrorIsNotSuccess {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c deleteAccountWithReason:@"" password:@"wrong"
					completion:^(BOOL good){ ok = good; }];
	answerA(c, @{@"@type" : @"error", @"message" : @"PASSWORD_HASH_INVALID"});
	XCTAssertFalse(ok);
}

- (void)testTerminateAllOtherSessions_IsOneRequestWithNothingInIt {
	TGClient *c = A();
	__block BOOL ok = NO;
	[c terminateAllOtherSessions:^(BOOL good){ ok = good; }];
	NSDictionary *r = lastA(c, @"terminateAllOtherSessions");
	XCTAssertNotNil(r);
	XCTAssertNil(r[@"session_id"], @"this one signs out every other device, not one");
	answerA(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - the avatar gallery

/// The gallery deletes by the photo's own id, which is not the file id it is
/// drawn from - mixing the two deletes the wrong picture or nothing at all.
- (void)testProfilePhotos_CarryBothTheirOwnIdAndTheFileToDraw {
	TGClient *c = A();
	__block NSArray *photos = nil;
	[c userProfilePhotos:1001 completion:^(NSArray *found){ photos = found; }];
	answerA(c, @{@"@type" : @"chatPhotos", @"total_count" : @(2), @"photos" : @[
			@{@"id" : @"7788", @"small" : @{@"id" : @(31)}},
			@{@"id" : @"7789", @"small" : @{@"id" : @(32)}}]});

	XCTAssertEqual(photos.count, (NSUInteger)2);
	XCTAssertEqual([photos[0][@"photoId"] longLongValue], 7788LL);
	XCTAssertEqual([photos[0][@"fileId"] integerValue], (NSInteger)31);
}

/// A photo with no file behind it cannot be drawn, and one with no id of its
/// own cannot be deleted; neither is a row.
- (void)testProfilePhotos_SkipsAnythingItCouldNotDrawOrDelete {
	TGClient *c = A();
	__block NSArray *photos = nil;
	[c userProfilePhotos:1001 completion:^(NSArray *found){ photos = found; }];
	answerA(c, @{@"@type" : @"chatPhotos", @"photos" : @[
			@{@"id" : @"7788"},
			@{@"small" : @{@"id" : @(32)}},
			@{@"id" : @"7790", @"small" : @{@"id" : @(33)}}]});
	XCTAssertEqual(photos.count, (NSUInteger)1);
	XCTAssertEqual([photos[0][@"photoId"] longLongValue], 7790LL);
}

- (void)testDeleteProfilePhoto_RefusesAZeroIdRatherThanSendingOne {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c deleteProfilePhoto:0 completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countA(c, @"deleteProfilePhoto"), (NSUInteger)0);
	XCTAssertFalse(ok);

	[c deleteProfilePhoto:7788 completion:nil];
	XCTAssertNotNil(lastA(c, @"deleteProfilePhoto"));
}

#pragma mark - my link, groups in common

- (void)testMyLink_AsksForThePermanentOneAndRevokesNothing {
	TGClient *c = A();
	__block NSString *link = nil;
	[c myUserLink:^(NSString *url){ link = url; }];
	NSDictionary *r = lastA(c, @"getUserLink");
	XCTAssertTrue([r[@"return_permanent_link"] boolValue]);
	XCTAssertFalse([r[@"revoke_previous_links"] boolValue],
				   @"reading the link must not invalidate the one already given out");

	answerA(c, @{@"@type" : @"userLink", @"url" : @"https://t.me/+xyz",
				 @"expires_in" : @(0)});
	XCTAssertEqualObjects(link, @"https://t.me/+xyz");
}

/// A group with no title is one the list cannot draw a row for.
- (void)testGroupsInCommon_NamedOffTheAnswerAndSkippedWhenNameless {
	TGClient *c = A();
	__block NSArray *groups = nil;
	[c groupsInCommonWithUser:6 completion:^(NSArray *found){ groups = found; }];
	answerA(c, @{@"@type" : @"chats", @"chats" : @[
			@{@"id" : @(-70), @"title" : @"Walkers"},
			@{@"id" : @(-71), @"title" : @""}]});

	XCTAssertEqual(groups.count, (NSUInteger)1);
	XCTAssertEqualObjects(groups[0][@"title"], @"Walkers");
	XCTAssertEqual([groups[0][@"chatId"] longLongValue], -70LL);
}

#pragma mark - recents, spam, blocking

/// The people row the search screen opens on. A chat the list has never
/// heard of has no row to draw, so it is skipped rather than drawn blank.
- (void)testTopChats_AreTheChatsTheListAlreadyKnows {
	TGClient *c = A();
	c.chatsById[@(7)] = [@{@"id" : @(7), @"title" : @"Pat"} mutableCopy];
	__block NSArray *chats = nil;
	[c topChatsWithCompletion:^(NSArray *found){ chats = found; }];

	NSDictionary *asked = lastA(c, @"getTopChats");
	XCTAssertEqualObjects(asked[@"category"][@"@type"], @"topChatCategoryUsers");

	answerA(c, @{@"@type" : @"chats", @"chat_ids" : @[@(7), @(999)]});
	XCTAssertEqual(chats.count, (NSUInteger)1);
	XCTAssertEqualObjects(chats[0][@"title"], @"Pat");
}

/// reportSupergroupSpam wants the supergroup's own id, and a chat id for a
/// supergroup is not it - so the chat is read first rather than the number
/// being arithmetic on the chat id.
- (void)testReportSpam_ReadsTheSupergroupIdOffTheChat {
	TGClient *c = A();
	__block BOOL ok = NO;
	[c reportSpamMessages:@[@(5)] inChat:-1001234 completion:^(BOOL good){ ok = good; }];

	XCTAssertNotNil(lastA(c, @"getChat"), @"the supergroup id has to be read first");
	XCTAssertEqual(countA(c, @"reportSupergroupSpam"), (NSUInteger)0);

	answerA(c, @{@"@type" : @"chat", @"id" : @(-1001234),
				 @"type" : @{@"@type" : @"chatTypeSupergroup",
							 @"supergroup_id" : @(1234)}});
	NSDictionary *r = lastA(c, @"reportSupergroupSpam");
	XCTAssertEqual([r[@"supergroup_id"] longLongValue], 1234LL);
	XCTAssertEqualObjects(r[@"message_ids"], @[@(5)]);

	answerA(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

/// A basic group or a private chat has no supergroup behind it, and the
/// request must not go out with a zero in place of one.
- (void)testReportSpam_AChatWithNoSupergroupSendsNothing {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c reportSpamMessages:@[@(5)] inChat:7 completion:^(BOOL good){ ok = good; }];
	answerA(c, @{@"@type" : @"chat", @"id" : @(7),
				 @"type" : @{@"@type" : @"chatTypePrivate", @"user_id" : @(6)}});
	XCTAssertEqual(countA(c, @"reportSupergroupSpam"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

- (void)testReportSpam_NoMessagesIsNotARequest {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c reportSpamMessages:@[] inChat:-1001234 completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countA(c, @"getChat"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

/// Deleting what they wrote means both flags: one message is the one in
/// hand, and the other is everything else of theirs.
- (void)testBlockFromReplies_DeletesBothTheMessageAndTheRest {
	TGClient *c = A();
	[c blockSenderOfMessage:5 deleteMessages:YES reportSpam:YES];
	NSDictionary *r = lastA(c, @"blockMessageSenderFromReplies");
	XCTAssertEqual([r[@"message_id"] longLongValue], 5LL);
	XCTAssertTrue([r[@"delete_message"] boolValue]);
	XCTAssertTrue([r[@"delete_all_messages"] boolValue]);
	XCTAssertTrue([r[@"report_spam"] boolValue]);

	[c blockSenderOfMessage:5 deleteMessages:NO reportSpam:NO];
	NSDictionary *quiet = lastA(c, @"blockMessageSenderFromReplies");
	XCTAssertFalse([quiet[@"delete_message"] boolValue]);
	XCTAssertFalse([quiet[@"report_spam"] boolValue]);
}

#pragma mark - what the tier-1 tail left open

/// The drawn map card shows roads that are not there. The real thumbnail is
/// a file record first and a picture second, so a cached one answers at once
/// and a fresh one goes through the download queue.
- (void)testMapThumbnail_ACachedOneAnswersWithoutADownload {
	TGClient *c = A();
	__block NSString *path = @"unset";
	[c mapThumbnailForLatitude:50.45 longitude:30.52 width:220 height:130
						inChat:7 completion:^(NSString *local){ path = local; }];

	NSDictionary *r = lastA(c, @"getMapThumbnailFile");
	XCTAssertEqual([r[@"location"][@"latitude"] doubleValue], 50.45);
	XCTAssertEqual([r[@"width"] integerValue], (NSInteger)220);
	// A retina plate is four times the bytes for a card 220 points wide.
	XCTAssertEqual([r[@"scale"] integerValue], (NSInteger)1);

	answerA(c, @{@"@type" : @"file", @"id" : @(55),
				 @"local" : @{@"path" : @"/tmp/map.png",
							  @"is_downloading_completed" : @YES}});
	XCTAssertEqualObjects(path, @"/tmp/map.png");
	XCTAssertEqual(countA(c, @"downloadFile"), (NSUInteger)0);
}

- (void)testMapThumbnail_AnUndownloadedOneGoesThroughTheQueue {
	TGClient *c = A();
	[c mapThumbnailForLatitude:50.45 longitude:30.52 width:220 height:130
						inChat:7 completion:nil];
	answerA(c, @{@"@type" : @"file", @"id" : @(55),
				 @"local" : @{@"is_downloading_completed" : @NO}});
	XCTAssertEqual([lastA(c, @"downloadFile")[@"file_id"] integerValue], (NSInteger)55);
}

/// Their own bounds are 16-1024; a request outside them is refused rather
/// than clamped, so the clamping has to happen here.
- (void)testMapThumbnail_SizeIsClampedToWhatTelegramAccepts {
	TGClient *c = A();
	[c mapThumbnailForLatitude:0 longitude:0 width:4000 height:2
						inChat:0 completion:nil];
	NSDictionary *r = lastA(c, @"getMapThumbnailFile");
	XCTAssertEqual([r[@"width"] integerValue], (NSInteger)1024);
	XCTAssertEqual([r[@"height"] integerValue], (NSInteger)16);
}

/// An error is the ordinary case on this device - no connection, or a
/// thumbnail over the megabyte Telegram will serve - and the caller falls
/// back to the drawn card on nil.
- (void)testMapThumbnail_NoAnswerIsNilRatherThanAnEmptyPath {
	TGClient *c = A();
	__block NSString *path = @"unset";
	[c mapThumbnailForLatitude:0 longitude:0 width:220 height:130
						inChat:0 completion:^(NSString *local){ path = local; }];
	answerA(c, @{@"@type" : @"error", @"code" : @(400), @"message" : @"Nope"});
	XCTAssertNil(path);
}

/// Editing in place keeps the proxy's position in the list and whether it is
/// the one in use; removing and re-adding lost both.
- (void)testEditProxy_CarriesTheIdAndKeepsItEnabled {
	TGClient *c = A();
	[c editProxy:3 server:@"new.host" port:1080 kind:@"socks5"
		username:nil password:nil secret:nil enable:YES completion:nil];
	NSDictionary *r = lastA(c, @"editProxy");
	XCTAssertEqual([r[@"proxy_id"] integerValue], (NSInteger)3);
	XCTAssertEqualObjects(r[@"proxy"][@"server"], @"new.host");
	XCTAssertTrue([r[@"enable"] boolValue]);
}

- (void)testEditProxy_RefusesAnImpossibleIdOrPort {
	TGClient *c = A();
	__block NSInteger refusals = 0;
	void (^count)(BOOL) = ^(BOOL ok){ if (!ok) refusals++; };
	[c editProxy:0 server:@"h" port:1080 kind:@"socks5" username:nil
		password:nil secret:nil enable:YES completion:count];
	[c editProxy:3 server:@"" port:1080 kind:@"socks5" username:nil
		password:nil secret:nil enable:YES completion:count];
	[c editProxy:3 server:@"h" port:0 kind:@"socks5" username:nil
		password:nil secret:nil enable:YES completion:count];
	XCTAssertEqual(countA(c, @"editProxy"), (NSUInteger)0);
	XCTAssertEqual(refusals, (NSInteger)3);
}

/// A ping says a proxy answered; this says it will carry Telegram, which is
/// the failure a ping alone calls success.
- (void)testTestProxy_AsksADataCentreAndReadsOkAsWorking {
	TGClient *c = A();
	__block BOOL works = NO;
	[c testProxyAtServer:@"h" port:1080 kind:@"socks5" username:nil
				password:nil secret:nil completion:^(BOOL good){ works = good; }];
	NSDictionary *r = lastA(c, @"testProxy");
	XCTAssertEqual([r[@"dc_id"] integerValue], (NSInteger)1);
	XCTAssertTrue([r[@"timeout"] doubleValue] > 0);

	answerA(c, @{@"@type" : @"ok"});
	XCTAssertTrue(works);
}

- (void)testTestProxy_AnErrorIsNotWorking {
	TGClient *c = A();
	__block BOOL works = YES;
	[c testProxyAtServer:@"h" port:1080 kind:@"socks5" username:nil
				password:nil secret:nil completion:^(BOOL good){ works = good; }];
	answerA(c, @{@"@type" : @"error", @"message" : @"Timeout"});
	XCTAssertFalse(works);
}

/// A new recovery address is not in force until this code goes through, and
/// a state that still carries the pattern means it did not.
- (void)testRecoveryCode_StillWaitingMeansTheCodeWasRefused {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c checkRecoveryEmailCode:@"12345" completion:^(BOOL good){ ok = good; }];
	XCTAssertEqualObjects(lastA(c, @"checkRecoveryEmailAddressCode")[@"code"], @"12345");

	answerA(c, @{@"@type" : @"passwordState", @"has_password" : @YES,
				 @"recovery_email_address_code_info" :
						@{@"email_address_pattern" : @"p**@example.com"}});
	XCTAssertFalse(ok, @"a state still asking for a code is not a confirmed address");
}

- (void)testRecoveryCode_AStateWithNoPendingPatternIsConfirmed {
	TGClient *c = A();
	__block BOOL ok = NO;
	[c checkRecoveryEmailCode:@"12345" completion:^(BOOL good){ ok = good; }];
	answerA(c, @{@"@type" : @"passwordState", @"has_password" : @YES,
				 @"has_recovery_email_address" : @YES});
	XCTAssertTrue(ok);
}

- (void)testRecoveryCode_AnEmptyCodeIsNotARequest {
	TGClient *c = A();
	__block BOOL ok = YES;
	[c checkRecoveryEmailCode:@"" completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countA(c, @"checkRecoveryEmailAddressCode"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

/// The other half of an empty search. A chat the list has never heard of has
/// no row to draw, as with the people above it.
- (void)testRecentlyOpenedChats_AreTheOnesTheListKnows {
	TGClient *c = A();
	c.chatsById[@(7)] = [@{@"id" : @(7), @"title" : @"Pat"} mutableCopy];
	__block NSArray *chats = nil;
	[c recentlyOpenedChatsWithCompletion:^(NSArray *found){ chats = found; }];
	XCTAssertNotNil(lastA(c, @"getRecentlyOpenedChats"));

	answerA(c, @{@"@type" : @"chats", @"chat_ids" : @[@(7), @(999)]});
	XCTAssertEqual(chats.count, (NSUInteger)1);
	XCTAssertEqualObjects(chats[0][@"title"], @"Pat");
}

@end

// vim:ft=objc
