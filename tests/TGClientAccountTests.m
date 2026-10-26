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

@end

// vim:ft=objc
