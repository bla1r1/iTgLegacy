// TGClientAuthFunctionsTests.m — the sign-in, email, phone and password
// requests the account flows are built on.
//
// Every test here pins one wire shape: the parameter names TDLib accepts,
// which optional fields are sent as null, and how the answer is flattened
// for a sheet. The result mapping is the part that used to be guessed at -
// an "ok" where the screen wanted a boolean, or a session where it wanted a
// word - so most tests answer with a real server object rather than @{@"ok":1}.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#include <string.h>

@interface TGClientAuthFunctionsTests : XCTestCase @end

static TGClient *AF(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	[c noteApplicationVerificationWithId:0 nonce:@""];
	c.td_exec = NULL;
	return c;
}

static NSDictionary *decodeF(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastF(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeF(d)[@"@type"] isEqualToString:type])
			found = decodeF(d);
	return found;
}

static NSUInteger countF(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeF(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

/// Answers the most recent request that carried an @extra. Tests that send
/// two requests in a row call this between them, as the client does.
static void answerF(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeF(d)[@"@extra"])
			sent = decodeF(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

/// Literal dictionaries answer nil one level down; TDLib answers are parsed,
/// so round-trip a fixture through JSON before feeding it back.
static NSDictionary *plainF(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

// ─── login email address ─────────────────────────────────────────────────────

@implementation TGClientAuthFunctionsTests

- (void)testLoginEmailRequired_OkMeansRequired {
	TGClient *c = AF();
	__block BOOL required = NO;
	__block NSString *error = @"x";
	[c loginEmailAddressRequiredWithCompletion:^(BOOL yes, NSString *why){
		required = yes; error = why;
	}];
	XCTAssertNotNil(lastF(c, @"isLoginEmailAddressRequired"));
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(required);
	XCTAssertNil(error);
}

- (void)testLoginEmailRequired_AnErrorIsTheServersNo {
	TGClient *c = AF();
	__block BOOL required = YES;
	__block NSString *error = nil;
	[c loginEmailAddressRequiredWithCompletion:^(BOOL yes, NSString *why){
		required = yes; error = why;
	}];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Not required"});
	XCTAssertFalse(required);
	XCTAssertEqualObjects(error, @"Not required");
}

- (void)testSetLoginEmailAddress_SendsTheAddressAndAnswersItsPattern {
	TGClient *c = AF();
	__block NSString *pattern = nil;
	[c setLoginEmailAddress:@"me@example.com"
				 completion:^(NSString *masked, NSString *error){
		pattern = masked;
	}];
	NSDictionary *r = lastF(c, @"setLoginEmailAddress");
	XCTAssertEqualObjects(r[@"new_login_email_address"], @"me@example.com");
	answerF(c, plainF(@{@"@type" : @"emailAddressAuthenticationCodeInfo",
						@"email_address_pattern" : @"m*@example.com",
						@"length" : @(5)}));
	XCTAssertEqualObjects(pattern, @"m*@example.com");
}

- (void)testSetLoginEmailAddress_ARefusalIsHandedBack {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c setLoginEmailAddress:@"me@example.com"
				 completion:^(NSString *pattern, NSString *why){ error = why; }];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"EMAIL_NOT_ALLOWED"});
	XCTAssertEqualObjects(error, @"EMAIL_NOT_ALLOWED");
}

- (void)testResendLoginEmailCode_AsksAndAnswersTheNewPattern {
	TGClient *c = AF();
	__block NSString *pattern = nil;
	[c resendLoginEmailAddressCodeWithCompletion:^(NSString *masked, NSString *error){
		pattern = masked;
	}];
	XCTAssertNotNil(lastF(c, @"resendLoginEmailAddressCode"));
	answerF(c, plainF(@{@"@type" : @"emailAddressAuthenticationCodeInfo",
						@"email_address_pattern" : @"n*@example.com"}));
	XCTAssertEqualObjects(pattern, @"n*@example.com");
}

- (void)testCheckLoginEmailCode_WrapsTheCodeInEmailAddressAuthentication {
	TGClient *c = AF();
	__block NSString *error = @"x";
	[c checkLoginEmailAddressCode:@"12345" completion:^(NSString *why){ error = why; }];
	NSDictionary *r = lastF(c, @"checkLoginEmailAddressCode");
	XCTAssertEqualObjects(r[@"code"][@"@type"], @"emailAddressAuthenticationCode");
	XCTAssertEqualObjects(r[@"code"][@"code"], @"12345");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertNil(error);
}

// ─── web tokens and QR login ─────────────────────────────────────────────────

- (void)testCheckWebToken_SendsTheTokenAndDatacenter {
	TGClient *c = AF();
	__block NSString *error = @"x";
	[c checkAuthenticationWebToken:@"tok" dcId:2 completion:^(NSString *why){ error = why; }];
	NSDictionary *r = lastF(c, @"checkAuthenticationWebToken");
	XCTAssertEqualObjects(r[@"token"], @"tok");
	XCTAssertEqualObjects(r[@"dc_id"], @(2));
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertNil(error);
}

- (void)testCheckWebToken_ARefusalIsShown {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c checkAuthenticationWebToken:@"bad" dcId:5 completion:^(NSString *why){ error = why; }];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"INVALID_TOKEN"});
	XCTAssertEqualObjects(error, @"INVALID_TOKEN");
}

- (void)testDismissWebToken_SendsOnlyTheToken {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c dismissWebToken:@"tok" completion:^(NSString *error){ done = (error == nil); }];
	NSDictionary *r = lastF(c, @"dismissWebToken");
	XCTAssertEqualObjects(r[@"token"], @"tok");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

- (void)testConfirmQrLink_ASessionIsSuccess {
	TGClient *c = AF();
	__block NSString *error = @"x";
	[c confirmQrCodeAuthenticationLink:@"tg://login?token=abc"
							completion:^(NSString *why){ error = why; }];
	NSDictionary *r = lastF(c, @"confirmQrCodeAuthentication");
	XCTAssertEqualObjects(r[@"link"], @"tg://login?token=abc");
	answerF(c, plainF(@{@"@type" : @"session", @"id" : @(7),
						@"is_current" : @YES}));
	XCTAssertNil(error);
}

- (void)testConfirmQrLink_AnythingElseIsTheRefusal {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c confirmQrCodeAuthenticationLink:@"tg://login?token=stale"
							completion:^(NSString *why){ error = why; }];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"LINK_EXPIRED"});
	XCTAssertEqualObjects(error, @"LINK_EXPIRED");
}

- (void)testSearchUserByToken_FlattensTheUserForAChatRow {
	TGClient *c = AF();
	__block NSDictionary *user = nil;
	[c searchUserByToken:@"abc" completion:^(NSDictionary *found, NSString *error){
		user = found;
	}];
	XCTAssertEqualObjects(lastF(c, @"searchUserByToken")[@"token"], @"abc");
	answerF(c, plainF(@{@"@type" : @"user", @"id" : @(42),
						@"first_name" : @"Ada", @"last_name" : @"Lovelace",
						@"usernames" : @{@"active_usernames" : @[@"ada"]},
						@"phone_number" : @"+441234"}));
	XCTAssertEqualObjects(user[@"id"], @(42));
	XCTAssertEqualObjects(user[@"name"], @"Ada Lovelace");
	XCTAssertEqualObjects(user[@"username"], @"ada");
}

- (void)testSearchUserByToken_ANullUsernameDoesNotThrow {
	TGClient *c = AF();
	__block NSDictionary *user = nil;
	[c searchUserByToken:@"abc" completion:^(NSDictionary *found, NSString *error){
		user = found;
	}];
	// A token link exists precisely because there is no username to search
	// by, so this is the ordinary answer, not an edge case.
	answerF(c, plainF(@{@"@type" : @"user", @"id" : @(43),
						@"first_name" : @"Ada", @"last_name" : @"",
						@"usernames" : [NSNull null],
						@"phone_number" : @""}));
	XCTAssertEqualObjects(user[@"id"], @(43));
	XCTAssertEqualObjects(user[@"username"], @"");
}

- (void)testSearchUserByToken_AnErrorIsHandedBackWithNoUser {	TGClient *c = AF();
	__block NSDictionary *user = @{};
	__block NSString *error = nil;
	[c searchUserByToken:@"gone" completion:^(NSDictionary *found, NSString *why){
		user = found; error = why;
	}];
	answerF(c, @{@"@type" : @"error", @"code" : @(404),
				  @"message" : @"User not found"});
	XCTAssertNil(user);
	XCTAssertEqualObjects(error, @"User not found");
}

// ─── phone number info and change ────────────────────────────────────────────

- (void)testPhoneNumberInfo_FlattensCountryAndFormatting {
	TGClient *c = AF();
	__block NSDictionary *info = nil;
	[c phoneNumberInfoForPrefix:@"+380441" completion:^(NSDictionary *found){
		info = found;
	}];
	XCTAssertEqualObjects(lastF(c, @"getPhoneNumberInfo")[@"phone_number_prefix"],
						   @"+380441");
	answerF(c, plainF(@{@"@type" : @"phoneNumberInfo",
						@"country" : @{@"@type" : @"countryInfo",
									   @"country_code" : @"UA",
									   @"name" : @"Ukraine",
									   @"flag_emoji" : @"🇺🇦"},
						@"country_calling_code" : @"+380",
						@"formatted_phone_number" : @"+380 44 123 4567",
						@"is_anonymous" : @NO}));
	XCTAssertEqualObjects(info[@"name"], @"Ukraine");
	XCTAssertEqualObjects(info[@"flag"], @"🇺🇦");
	XCTAssertEqualObjects(info[@"formatted"], @"+380 44 123 4567");
}

- (void)testPhoneNumberInfo_AnErrorAnswersNil {
	TGClient *c = AF();
	__block NSDictionary *info = @{};
	[c phoneNumberInfoForPrefix:@"+999" completion:^(NSDictionary *found){ info = found; }];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"PHONE_NUMBER_INVALID"});
	XCTAssertNil(info);
}

static char gFakeExecRequest[4096];
static char gFakeExecAnswer[4096];

static const char *FakeExec(void *client, const char *request) {
	(void)client;
	strncpy(gFakeExecRequest, request ?: "", sizeof(gFakeExecRequest) - 1);
	gFakeExecRequest[sizeof(gFakeExecRequest) - 1] = '\0';
	return gFakeExecAnswer;
}

- (void)testPhoneNumberInfoSync_UsesExecuteWithTheLanguageAndPrefix {
	TGClient *c = AF();
	snprintf(gFakeExecAnswer, sizeof(gFakeExecAnswer),
			"{\"@type\":\"phoneNumberInfo\",\"country\":{\"@type\":\"countryInfo\","
			"\"name\":\"Ukraine\",\"flag_emoji\":\"UA\"},"
			"\"country_calling_code\":\"+380\","
			"\"formatted_phone_number\":\"+380 44 123 4567\","
			"\"is_anonymous\":false}");
	c.td_exec = FakeExec;
	NSDictionary *info = [c phoneNumberInfoForPrefixSync:@"+38044"];
	c.td_exec = NULL;

	XCTAssertTrue(strstr(gFakeExecRequest, "\"getPhoneNumberInfoSync\"") != NULL);
	XCTAssertTrue(strstr(gFakeExecRequest, "\"language_code\":\"en\"") != NULL);
	XCTAssertTrue(strstr(gFakeExecRequest, "\"+38044\"") != NULL);
	XCTAssertEqualObjects(info[@"formatted"], @"+380 44 123 4567");
}

- (void)testPhoneNumberInfoSync_WithoutTheEngineIsNil {
	TGClient *c = AF();
	XCTAssertNil([c phoneNumberInfoForPrefixSync:@"+38044"]);
}

- (void)testSendPhoneNumberCode_IsAChangeRequestWithNullSettings {
	TGClient *c = AF();
	__block NSDictionary *info = nil;
	[c sendPhoneNumberChangeCode:@"+380441234567"
					  completion:^(NSDictionary *found, NSString *error){ info = found; }];
	NSDictionary *r = lastF(c, @"sendPhoneNumberCode");
	XCTAssertEqualObjects(r[@"phone_number"], @"+380441234567");
	XCTAssertEqualObjects(r[@"type"][@"@type"], @"phoneNumberCodeTypeChange");
	XCTAssertTrue(r[@"settings"] == [NSNull null], @"null is the protocol default");
	answerF(c, plainF(@{@"@type" : @"authenticationCodeInfo",
						@"phone_number" : @"+380*******67",
						@"type" : @{@"@type" : @"authenticationCodeTypeSms",
									@"length" : @(5)},
						@"timeout" : @(60)}));
	XCTAssertEqualObjects(info[@"type"], @"authenticationCodeTypeSms");
	XCTAssertEqualObjects(info[@"timeout"], @(60));
}

- (void)testSendPhoneNumberCode_ARefusalNamesTheReason {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c sendPhoneNumberChangeCode:@"+1" completion:^(NSDictionary *info, NSString *why){
		error = why;
	}];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"PHONE_NUMBER_INVALID"});
	XCTAssertEqualObjects(error, @"PHONE_NUMBER_INVALID");
}

- (void)testCheckPhoneNumberCode_SendsOnlyTheCode {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c checkPhoneNumberChangeCode:@"12345" completion:^(NSString *error){
		done = (error == nil);
	}];
	XCTAssertEqualObjects(lastF(c, @"checkPhoneNumberCode")[@"code"], @"12345");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

- (void)testResendPhoneNumberCode_SaysWhyItIsResent {
	TGClient *c = AF();
	__block NSInteger timeout = 0;
	[c resendPhoneNumberChangeCodeWithCompletion:^(NSDictionary *info, NSString *error){
		timeout = [info[@"timeout"] integerValue];
	}];
	NSDictionary *r = lastF(c, @"resendPhoneNumberCode");
	XCTAssertEqualObjects(r[@"reason"][@"@type"], @"resendCodeReasonUserRequest");
	answerF(c, plainF(@{@"@type" : @"authenticationCodeInfo",
						@"type" : @{@"@type" : @"authenticationCodeTypeSms"},
						@"timeout" : @(30)}));
	XCTAssertEqual(timeout, 30);
}

- (void)testReportPhoneNumberCodeMissing_SendsAnEmptyNetworkCode {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c reportPhoneNumberCodeMissingWithCompletion:^(NSString *error){
		done = (error == nil);
	}];
	NSDictionary *r = lastF(c, @"reportPhoneNumberCodeMissing");
	XCTAssertEqualObjects(r[@"mobile_network_code"], @"");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

- (void)testSendAuthenticationFirebaseSms_CarriesTheSecret {
	TGClient *c = AF();
	__block NSString *error = @"x";
	[c sendAuthenticationFirebaseSms:@"secret" completion:^(NSString *why){ error = why; }];
	XCTAssertEqualObjects(lastF(c, @"sendAuthenticationFirebaseSms")[@"token"], @"secret");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertNil(error);
}

- (void)testSendPhoneNumberFirebaseSms_CarriesTheSecret {
	TGClient *c = AF();
	__block NSString *error = @"x";
	[c sendPhoneNumberFirebaseSms:@"secret" completion:^(NSString *why){ error = why; }];
	XCTAssertEqualObjects(lastF(c, @"sendPhoneNumberFirebaseSms")[@"token"], @"secret");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertNil(error);
}

// ─── password recovery inside the account ────────────────────────────────────

- (void)testRequestPasswordRecovery_AnswersTheMaskedAddress {
	TGClient *c = AF();
	__block NSString *pattern = nil;
	[c requestAccountPasswordRecoveryWithCompletion:^(NSString *masked, NSString *error){
		pattern = masked;
	}];
	XCTAssertNotNil(lastF(c, @"requestPasswordRecovery"));
	answerF(c, plainF(@{@"@type" : @"emailAddressAuthenticationCodeInfo",
						@"email_address_pattern" : @"r*@example.com"}));
	XCTAssertEqualObjects(pattern, @"r*@example.com");
}

- (void)testRequestPasswordRecovery_NoAddressIsTheServersRefusal {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c requestAccountPasswordRecoveryWithCompletion:^(NSString *pattern, NSString *why){
		error = why;
	}];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"RECOVERY_EMAIL_NOT_SET"});
	XCTAssertEqualObjects(error, @"RECOVERY_EMAIL_NOT_SET");
}

- (void)testCheckPasswordRecoveryCode_SendsTheCode {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c checkAccountPasswordRecoveryCode:@"123456" completion:^(NSString *error){
		done = (error == nil);
	}];
	XCTAssertEqualObjects(lastF(c, @"checkPasswordRecoveryCode")[@"recovery_code"],
						   @"123456");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

- (void)testRecoverPassword_SetsTheNewPasswordAndHint {
	TGClient *c = AF();
	__block NSDictionary *state = nil;
	[c recoverAccountPasswordWithCode:@"123456" newPassword:@"newpass" hint:@"a clue"
						   completion:^(NSDictionary *result, NSString *error){
		state = result;
	}];
	NSDictionary *r = lastF(c, @"recoverPassword");
	XCTAssertEqualObjects(r[@"recovery_code"], @"123456");
	XCTAssertEqualObjects(r[@"new_password"], @"newpass");
	XCTAssertEqualObjects(r[@"new_hint"], @"a clue");
	answerF(c, plainF(@{@"@type" : @"passwordState", @"has_password" : @YES,
						@"password_hint" : @"a clue",
						@"has_recovery_email_address" : @YES}));
	XCTAssertTrue([state[@"hasPassword"] boolValue]);
	XCTAssertEqualObjects(state[@"hint"], @"a clue");
}

- (void)testRecoverPassword_AnEmptyNewPasswordReadsAsRemoved {
	TGClient *c = AF();
	__block NSDictionary *state = nil;
	[c recoverAccountPasswordWithCode:@"1" newPassword:@"" hint:@""
						   completion:^(NSDictionary *result, NSString *error){
		state = result;
	}];
	answerF(c, plainF(@{@"@type" : @"passwordState", @"has_password" : @NO}));
	XCTAssertFalse([state[@"hasPassword"] boolValue]);
}

- (void)testResetPassword_OkClearsThePassword {
	TGClient *c = AF();
	__block NSString *result = nil;
	[c resetAccountPasswordWithCompletion:^(NSString *what, double date, NSString *error){
		result = what;
	}];
	XCTAssertNotNil(lastF(c, @"resetPassword"));
	answerF(c, @{@"@type" : @"resetPasswordResultOk"});
	XCTAssertEqualObjects(result, @"ok");
}

- (void)testResetPassword_PendingCarriesTheDate {
	TGClient *c = AF();
	__block double date = 0;
	__block NSString *result = nil;
	[c resetAccountPasswordWithCompletion:^(NSString *what, double when, NSString *error){
		result = what; date = when;
	}];
	answerF(c, @{@"@type" : @"resetPasswordResultPending",
				  @"pending_reset_date" : @(1700000000)});
	XCTAssertEqualObjects(result, @"pending");
	XCTAssertEqual(date, 1700000000.0);
}

- (void)testResetPassword_DeclinedCarriesTheRetryDate {
	TGClient *c = AF();
	__block double date = 0;
	__block NSString *result = nil;
	[c resetAccountPasswordWithCompletion:^(NSString *what, double when, NSString *error){
		result = what; date = when;
	}];
	answerF(c, @{@"@type" : @"resetPasswordResultDeclined",
				  @"retry_date" : @(1800000000)});
	XCTAssertEqualObjects(result, @"declined");
	XCTAssertEqual(date, 1800000000.0);
}

- (void)testCancelPasswordReset_SendsTheRequest {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c cancelAccountPasswordResetWithCompletion:^(NSString *error){
		done = (error == nil);
	}];
	XCTAssertNotNil(lastF(c, @"cancelPasswordReset"));
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

- (void)testTemporaryPasswordState_ReadsHasAndValidity {
	TGClient *c = AF();
	__block BOOL has = NO;
	__block NSInteger validFor = 0;
	[c temporaryPasswordStateWithCompletion:^(BOOL yes, NSInteger left, NSString *error){
		has = yes; validFor = left;
	}];
	XCTAssertNotNil(lastF(c, @"getTemporaryPasswordState"));
	answerF(c, @{@"@type" : @"temporaryPasswordState",
				  @"has_password" : @YES, @"valid_for" : @(600)});
	XCTAssertTrue(has);
	XCTAssertEqual(validFor, 600);
}

- (void)testCreateTemporaryPassword_CarriesPasswordAndLifetime {
	TGClient *c = AF();
	__block NSInteger validFor = 0;
	[c createTemporaryPassword:@"secret" validFor:3600
					completion:^(BOOL has, NSInteger left, NSString *error){
		validFor = left;
	}];
	NSDictionary *r = lastF(c, @"createTemporaryPassword");
	XCTAssertEqualObjects(r[@"password"], @"secret");
	XCTAssertEqualObjects(r[@"valid_for"], @(3600));
	answerF(c, @{@"@type" : @"temporaryPasswordState",
				  @"has_password" : @YES, @"valid_for" : @(3599)});
	XCTAssertEqual(validFor, 3599);
}

- (void)testCreateTemporaryPassword_AWrongPasswordIsAServerError {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c createTemporaryPassword:@"wrong" validFor:3600
					completion:^(BOOL has, NSInteger left, NSString *why){ error = why; }];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"PASSWORD_HASH_INVALID"});
	XCTAssertEqualObjects(error, @"PASSWORD_HASH_INVALID");
}

- (void)testDeleteSavedCredentials_SendsTheRequest {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c deleteSavedCredentialsWithCompletion:^(NSString *error){
		done = (error == nil);
	}];
	XCTAssertNotNil(lastF(c, @"deleteSavedCredentials"));
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

// ─── recovery email and email verification ───────────────────────────────────

- (void)testCancelRecoveryEmailVerification_AnswersTheStateItLeaves {
	TGClient *c = AF();
	__block NSDictionary *state = nil;
	[c cancelRecoveryEmailAddressVerificationWithCompletion:
			^(NSDictionary *result, NSString *error){ state = result; }];
	XCTAssertNotNil(lastF(c, @"cancelRecoveryEmailAddressVerification"));
	answerF(c, plainF(@{@"@type" : @"passwordState", @"has_password" : @YES,
						@"has_recovery_email_address" : @NO,
						@"recovery_email_address_code_info" : [NSNull null]}));
	XCTAssertFalse([state[@"hasRecoveryEmail"] boolValue]);
	XCTAssertEqualObjects(state[@"recoveryPattern"], @"");
}

- (void)testSendEmailVerificationCode_AnswersThePattern {
	TGClient *c = AF();
	__block NSString *pattern = nil;
	[c sendEmailAddressVerificationCodeTo:@"me@example.com"
								completion:^(NSString *masked, NSString *error){
		pattern = masked;
	}];
	XCTAssertEqualObjects(lastF(c, @"sendEmailAddressVerificationCode")[@"email_address"],
						   @"me@example.com");
	answerF(c, plainF(@{@"@type" : @"emailAddressAuthenticationCodeInfo",
						@"email_address_pattern" : @"m*@example.com"}));
	XCTAssertEqualObjects(pattern, @"m*@example.com");
}

- (void)testResendEmailVerificationCode_AnswersThePattern {
	TGClient *c = AF();
	__block NSString *pattern = nil;
	[c resendEmailAddressVerificationCodeWithCompletion:^(NSString *masked, NSString *error){
		pattern = masked;
	}];
	XCTAssertNotNil(lastF(c, @"resendEmailAddressVerificationCode"));
	answerF(c, plainF(@{@"@type" : @"emailAddressAuthenticationCodeInfo",
						@"email_address_pattern" : @"p*@example.com"}));
	XCTAssertEqualObjects(pattern, @"p*@example.com");
}

- (void)testCheckEmailVerificationCode_SendsTheCode {
	TGClient *c = AF();
	__block BOOL done = NO;
	[c checkEmailAddressVerificationCode:@"1234" completion:^(NSString *error){
		done = (error == nil);
	}];
	XCTAssertEqualObjects(lastF(c, @"checkEmailAddressVerificationCode")[@"code"],
						   @"1234");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(done);
}

// ─── ownership and application verification ─────────────────────────────────

- (void)testCanTransferOwnership_OkMeansAllowed {
	TGClient *c = AF();
	__block NSString *result = nil;
	[c canTransferOwnershipWithCompletion:^(NSString *what, NSInteger retry,
											NSString *error){ result = what; }];
	XCTAssertNotNil(lastF(c, @"canTransferOwnership"));
	answerF(c, @{@"@type" : @"canTransferOwnershipResultOk"});
	XCTAssertEqualObjects(result, @"ok");
}

- (void)testCanTransferOwnership_PasswordNeeded {
	TGClient *c = AF();
	__block NSString *result = nil;
	[c canTransferOwnershipWithCompletion:^(NSString *what, NSInteger retry,
											NSString *error){ result = what; }];
	answerF(c, @{@"@type" : @"canTransferOwnershipResultPasswordNeeded"});
	XCTAssertEqualObjects(result, @"passwordNeeded");
}

- (void)testCanTransferOwnership_SessionTooFreshCarriesTheWait {
	TGClient *c = AF();
	__block NSInteger retry = 0;
	[c canTransferOwnershipWithCompletion:^(NSString *what, NSInteger wait,
											NSString *error){ retry = wait; }];
	answerF(c, @{@"@type" : @"canTransferOwnershipResultSessionTooFresh",
				  @"retry_after" : @(3600)});
	XCTAssertEqual(retry, 3600);
}

- (void)testCanTransferOwnership_PasswordTooFreshCarriesTheWait {
	TGClient *c = AF();
	__block NSString *result = nil;
	__block NSInteger retry = 0;
	[c canTransferOwnershipWithCompletion:^(NSString *what, NSInteger wait,
											NSString *error){
		result = what; retry = wait;
	}];
	answerF(c, @{@"@type" : @"canTransferOwnershipResultPasswordTooFresh",
				  @"retry_after" : @(60)});
	XCTAssertEqualObjects(result, @"passwordTooFresh");
	XCTAssertEqual(retry, 60);
}

- (void)testCanTransferOwnership_AnErrorIsHandedBack {
	TGClient *c = AF();
	__block NSString *error = nil;
	[c canTransferOwnershipWithCompletion:^(NSString *what, NSInteger wait,
											NSString *why){ error = why; }];
	answerF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Not an owner"});
	XCTAssertEqualObjects(error, @"Not an owner");
}

- (void)testSetApplicationVerificationToken_SendsIdAndTokenAndClearsThePendingOne {
	TGClient *c = AF();
	[c noteApplicationVerificationWithId:77 nonce:@"nonce"];
	__block NSString *error = @"x";
	[c setApplicationVerificationToken:@"token" verificationId:77
							completion:^(NSString *why){ error = why; }];
	NSDictionary *r = lastF(c, @"setApplicationVerificationToken");
	XCTAssertEqualObjects(r[@"verification_id"], @(77));
	XCTAssertEqualObjects(r[@"token"], @"token");
	answerF(c, @{@"@type" : @"ok"});
	XCTAssertNil(error);
	XCTAssertEqual(c.pendingApplicationVerificationId, 0);
}

- (void)testApplicationVerificationUpdate_KeepsThePendingRequest {
	TGClient *c = AF();
	[c handleUpdate:@{@"@type" : @"updateApplicationVerificationRequired",
					  @"verification_id" : @(99),
					  @"nonce" : @"abc"}];
	XCTAssertEqual(c.pendingApplicationVerificationId, 99);
	XCTAssertEqualObjects(c.pendingApplicationVerificationNonce, @"abc");
}

@end
