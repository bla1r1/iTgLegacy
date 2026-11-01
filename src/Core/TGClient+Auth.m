#import "TGClientInternal.h"
#import <objc/runtime.h>

@interface TGClient (AuthPrivate)
- (void)setPushReceiverId:(int64_t)receiverId;
@end

@implementation TGClient (Auth)

- (int64_t)pushReceiverId {
	return [objc_getAssociatedObject(self, @selector(pushReceiverId)) longLongValue];
}

- (void)setPushReceiverId:(int64_t)receiverId {
	objc_setAssociatedObject(self, @selector(pushReceiverId), @(receiverId),
							 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - authorization steps

- (void)sendPhoneNumber:(NSString *)phoneNumber {
	// Arriving before TDLib is ready is normal - the number can be handed in
	// milliseconds after launch, while the client is still starting - and
	// send: silently drops anything sent too early. Hold it and flush once
	// the state machine actually asks for a number.
	self.pendingPhoneNumber = phoneNumber;
	if (self.available && (self.authState == TGAuthStateWaitPhoneNumber || self.authState == TGAuthStateWaitCode))
		[self flushPendingPhoneNumber];
}

- (void)flushPendingPhoneNumber {
	if (!self.pendingPhoneNumber.length)
		return;
	NSString *number = self.pendingPhoneNumber;
	self.pendingPhoneNumber = nil;
	[self send:@{
		@"@type"        : @"setAuthenticationPhoneNumber",
		@"phone_number" : number,
	}];
}

- (void)resendAuthenticationCode {
	[self send:@{
		@"@type" : @"resendAuthenticationCode"
	}];
}

- (void)requestQrCodeAuthentication {
	[self send:@{
		@"@type" : @"requestQrCodeAuthentication",
		@"other_user_ids" : @[]
	}];
}

- (void)destroySession {
	NSLog(@"TGClient: >>> destroySession called");
	[self send:@{
		@"@type" : @"destroy"
	}];
}

- (void)sendCode:(NSString *)code {
	[self send:@{
		@"@type" : @"checkAuthenticationCode",
		@"code"  : code ?: @"",
	}];
}

- (void)sendPassword:(NSString *)password {
	[self send:@{
		@"@type"    : @"checkAuthenticationPassword",
		@"password" : password ?: @"",
	}];
}

- (void)sendEmailAddress:(NSString *)email {
	[self send:@{@"@type" : @"setAuthenticationEmailAddress",
				 @"email_address" : email ?: @""}];
}

- (void)sendEmailCode:(NSString *)code {
	[self send:@{@"@type" : @"checkAuthenticationEmailCode",
				 @"code" : @{@"@type" : @"emailAddressAuthenticationCode",
							 @"code" : code ?: @""}}];
}

- (void)resetAuthenticationEmailAddress {
	[self send:@{@"@type" : @"resetAuthenticationEmailAddress"}];
}

- (void)reportAuthenticationCodeMissing {
	// The mobile network code is optional and this app cannot read one.
	[self send:@{@"@type" : @"reportAuthenticationCodeMissing",
				 @"mobile_network_code" : @""}];
}

static NSString *TGAuthError(NSDictionary *result) {
	if ([result[@"@type"] isEqualToString:@"ok"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

- (void)requestPasswordRecoveryWithCompletion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"requestAuthenticationPasswordRecovery"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)recoverPasswordWithCode:(NSString *)code
					 completion:(void (^)(NSString *))completion {
	NSString *trimmed = code ?: @"";
	// Checked first so a mistyped code says so, instead of the recovery
	// itself failing with a less useful message.
	[self request:@{@"@type" : @"checkAuthenticationPasswordRecoveryCode",
					@"recovery_code" : trimmed}
	   completion:^(NSDictionary *checked){
		NSString *error = TGAuthError(checked);
		if (error) {
			if (completion) completion(error);
			return;
		}
		// An empty new password is how TDLib spells "no password": recovery
		// signs in and removes it, as the official client does.
		[self request:@{@"@type" : @"recoverAuthenticationPassword",
						@"recovery_code" : trimmed,
						@"new_password" : @"",
						@"new_hint" : @""}
		   completion:^(NSDictionary *result){
			if (completion)
				completion(TGAuthError(result));
		}];
	}];
}

/// passwordState has no "recovery_email_address_pattern": it carries a flag
/// for whether there is an address, and a pattern only while a code sent to
/// a new one is outstanding. Reading the absent key meant the Two-Step screen
/// never once showed an address.
- (void)hasPasswordWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"getPasswordState"} completion:^(NSDictionary *state){
		if (!completion)
			return;
		NSString *pattern = state[@"recovery_email_address_code_info"]
				[@"email_address_pattern"];
		NSString *email = pattern.length ? pattern
				: ([state[@"has_recovery_email_address"] boolValue] ? @"set" : @"");
		completion([state[@"has_password"] boolValue], email);
	}];
}

/// A phone number Telegram has never seen lands in authorizationStateWait-
/// Registration, and the only way out of it is this. Without it a new account
/// could enter a code and then sit on the code screen forever.
- (void)registerWithFirstName:(NSString *)firstName
					 lastName:(NSString *)lastName
				   completion:(void (^)(BOOL ok, NSString *error))completion {
	if (!firstName.length){
		if (completion) completion(NO, @"A first name is needed.");
		return;
	}
	[self request:@{
		@"@type"      : @"registerUser",
		@"first_name" : firstName,
		@"last_name"  : lastName ?: @"",
		@"disable_notification" : @NO,
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		BOOL ok = [result[@"@type"] isEqualToString:@"ok"];
		completion(ok, ok ? nil : (result[@"message"] ?: @"Telegram refused that."));
	}];
}

/// The terms a new account has to be shown before it is made. Empty when
/// Telegram sent none with the registration state.
- (NSString *)registrationTerms {
	NSString *text = self.registrationTermsText;
	return text.length ? text : @"";
}

/// Every country Telegram knows, for the picker on the phone step. Entries
/// carry "code" (ISO), "name", "prefix" (the calling code with its +) and
/// "flag". Hidden countries are left out, as their own client leaves them.
- (void)countriesWithCompletion:(void (^)(NSArray *countries))completion {
	[self request:@{@"@type" : @"getCountries"} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *country in result[@"countries"]){
			if ([country[@"is_hidden"] boolValue])
				continue;
			NSString *prefix = [country[@"calling_codes"] firstObject];
			if (![country[@"country_code"] length] || !prefix.length)
				continue;
			[out addObject:@{
				@"code"   : country[@"country_code"],
				@"name"   : country[@"name"] ?: country[@"english_name"] ?: @"",
				@"prefix" : [NSString stringWithFormat:@"+%@", prefix],
				@"flag"   : country[@"flag_emoji"] ?: @"",
			}];
		}
		if (completion)
			completion(out);
	}];
}

/// The country this phone is in, as Telegram guesses it from the network -
/// which is what their phone step preselects. An ISO code, or nil.
- (void)countryCodeWithCompletion:(void (^)(NSString *code))completion {
	[self request:@{@"@type" : @"getCountryCode"} completion:^(NSDictionary *result){
		if (completion)
			completion([result[@"text"] length] ? result[@"text"] : nil);
	}];
}

#pragma mark - push

/// Hands the APNs token to Telegram, which is what makes a notification
/// arrive while the app is closed. Without it the app had no notifications
/// at all, however the certificate was set up.
///
/// `sandbox` has to match the certificate the build was signed against: a
/// production token registered as sandbox is silently never delivered to.
- (void)registerPushToken:(NSString *)token
				  sandbox:(BOOL)sandbox
			   completion:(void (^)(BOOL ok))completion {
	if (!token.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type" : @"registerDevice",
		@"device_token" : @{@"@type" : @"deviceTokenApplePush",
							@"device_token" : token,
							@"is_app_sandbox" : @(sandbox)},
		@"other_user_ids" : @[],
	} completion:^(NSDictionary *result){
		BOOL ok = [result[@"@type"] isEqualToString:@"pushReceiverId"];
		if (ok)
			[self setPushReceiverId:[result[@"id"] longLongValue]];
		if (completion)
			completion(ok);
	}];
}

/// A notification that arrived while the app was running: TDLib decrypts it
/// and turns it into the ordinary updates, so the chat list moves without
/// waiting for the next poll.
///
/// APNs wraps Telegram's blob under "p", which is the one piece TDLib wants;
/// the alert above it is display data Telegram's own clients ignore.
- (void)processPushPayload:(NSDictionary *)payload {
	if (!payload)
		return;
	NSString *blob = payload[@"p"];
	NSDictionary *clean = [blob isKindOfClass:NSString.class] && blob.length
			? @{@"p" : blob} : payload;
	NSData *json = [NSJSONSerialization dataWithJSONObject:clean options:0 error:nil];
	if (!json)
		return;
	[self send:@{@"@type" : @"processPushNotification",
				 @"payload" : [[NSString alloc] initWithData:json
												   encoding:NSUTF8StringEncoding]}];
}

/// What account a push belongs to, told by TDLib itself: works even while
/// the certificate is still on its way, because the blob sent over the wire
/// is all the answer needs. `ok` is NO for a payload TDLib cannot read.
- (void)pushReceiverOfPayload:(NSDictionary *)payload
				   completion:(void (^)(BOOL ok, int64_t receiverId))completion {
	NSString *blob = payload[@"p"];
	if (![blob isKindOfClass:NSString.class] || !blob.length){
		if (completion) completion(NO, 0);
		return;
	}
	[self request:@{@"@type" : @"getPushReceiverId", @"payload" : blob}
		completion:^(NSDictionary *result){
			if (!completion)
				return;
			BOOL ok = [result[@"@type"] isEqualToString:@"pushReceiverId"];
			completion(ok, [result[@"id"] longLongValue]);
		}];
}

/// Accepts the terms the update named, which is what lifts the restriction
/// the server put on the account until it happens.
- (void)acceptTermsOfService:(NSString *)termsId
				  completion:(void (^)(BOOL ok))completion {
	if (!termsId.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"acceptTermsOfService",
					@"terms_of_service_id" : termsId}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)logOut {
	[self send:@{@"@type" : @"logOut"}];
}

#pragma mark - login email address

/// The request has no boolean: "ok" is the yes and an error is the no, with
/// its own words for why. Both are handed on rather than flattened into a
/// bare flag, because "you must set one" and "Telegram refused to answer"
/// are different things for the screen to say.
- (void)loginEmailAddressRequiredWithCompletion:
		(void (^)(BOOL required, NSString *error))completion {
	[self request:@{@"@type" : @"isLoginEmailAddressRequired"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		BOOL ok = [result[@"@type"] isEqualToString:@"ok"];
		completion(ok, ok ? nil : TGAuthError(result));
	}];
}

- (void)setLoginEmailAddress:(NSString *)email
				  completion:(void (^)(NSString *pattern, NSString *error))completion {
	[self request:@{@"@type" : @"setLoginEmailAddress",
					@"new_login_email_address" : email ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"emailAddressAuthenticationCodeInfo"])
			completion(result[@"email_address_pattern"], nil);
		else
			completion(nil, TGAuthError(result));
	}];
}

- (void)resendLoginEmailAddressCodeWithCompletion:
		(void (^)(NSString *pattern, NSString *error))completion {
	[self request:@{@"@type" : @"resendLoginEmailAddressCode"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"emailAddressAuthenticationCodeInfo"])
			completion(result[@"email_address_pattern"], nil);
		else
			completion(nil, TGAuthError(result));
	}];
}

- (void)checkLoginEmailAddressCode:(NSString *)code
						completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"checkLoginEmailAddressCode",
					@"code" : @{@"@type" : @"emailAddressAuthenticationCode",
								@"code" : code ?: @""}}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

#pragma mark - web tokens and QR login

- (void)checkAuthenticationWebToken:(NSString *)token
							   dcId:(NSInteger)dcId
						 completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"checkAuthenticationWebToken",
					@"token" : token ?: @"",
					@"dc_id" : @((int32_t)dcId)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)dismissWebToken:(NSString *)token
			 completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"dismissWebToken", @"token" : token ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)confirmQrCodeAuthenticationLink:(NSString *)link
							 completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"confirmQrCodeAuthentication", @"link" : link ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		// A session is the success answer; anything else is the refusal.
		if ([result[@"@type"] isEqualToString:@"session"])
			completion(nil);
		else
			completion(TGAuthError(result));
	}];
}

- (void)searchUserByToken:(NSString *)token
			   completion:(void (^)(NSDictionary *user, NSString *error))completion {
	[self request:@{@"@type" : @"searchUserByToken", @"token" : token ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"user"]){
			completion(nil, TGAuthError(result));
			return;
		}
		NSString *first = result[@"first_name"] ?: @"";
		NSString *last = result[@"last_name"] ?: @"";
		NSString *name = [@[first, last] componentsJoinedByString:@" "];
		// A user found by token very often has no username at all - that is
		// why the link carried a token - and TDLib spells that as null, which
		// must not be subscripted.
		NSDictionary *usernames = [result[@"usernames"] isKindOfClass:NSDictionary.class]
				? result[@"usernames"] : nil;
		NSArray *actives = [usernames[@"active_usernames"] isKindOfClass:NSArray.class]
				? usernames[@"active_usernames"] : nil;
		NSString *username = [actives firstObject];
		completion(@{
			@"id" : result[@"id"] ?: @(0),
			@"name" : [name stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceCharacterSet]],
			@"username" : username ?: @"",
			@"phone" : result[@"phone_number"] ?: @"",
		}, nil);
	}];
}

#pragma mark - phone numbers

/// The country record is optional in the answer - Telegram leaves it out for
/// a prefix it cannot place - so everything here has to survive an empty
/// dictionary rather than subscripting nil.
static NSDictionary *TGPhoneNumberInfo(NSDictionary *result) {
	if (![result isKindOfClass:NSDictionary.class] ||
			[result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSDictionary *country = [result[@"country"] isKindOfClass:NSDictionary.class]
			? result[@"country"] : @{};
	return @{
		@"name" : country[@"name"] ?: country[@"english_name"] ?: @"",
		@"flag" : country[@"flag_emoji"] ?: @"",
		@"countryCode" : country[@"country_code"] ?: @"",
		@"callingCode" : result[@"country_calling_code"] ?: @"",
		@"formatted" : result[@"formatted_phone_number"] ?: @"",
		@"anonymous" : @([result[@"is_anonymous"] boolValue]),
	};
}

- (void)phoneNumberInfoForPrefix:(NSString *)prefix
					  completion:(void (^)(NSDictionary *info))completion {
	if (!prefix.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getPhoneNumberInfo",
					@"phone_number_prefix" : prefix}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGPhoneNumberInfo(result));
	}];
}

- (NSDictionary *)phoneNumberInfoForPrefixSync:(NSString *)prefix {
	if (!prefix.length)
		return nil;
	return TGPhoneNumberInfo([self executeSynchronously:@{
		@"@type" : @"getPhoneNumberInfoSync",
		@"language_code" : @"en",
		@"phone_number_prefix" : prefix,
	}]);
}

/// The code info is flattened to the pieces a screen draws - the way the
/// code was sent, its length, the resend timeout and the masked phone - so
/// the login and change-number steps share one shape.
static NSDictionary *TGAuthenticationCodeInfo(NSDictionary *result) {
	if (![result isKindOfClass:NSDictionary.class] ||
			![result[@"@type"] isEqualToString:@"authenticationCodeInfo"])
		return nil;
	NSDictionary *type = [result[@"type"] isKindOfClass:NSDictionary.class]
			? result[@"type"] : @{};
	NSDictionary *next = [result[@"next_type"] isKindOfClass:NSDictionary.class]
			? result[@"next_type"] : @{};
	return @{
		@"phone" : result[@"phone_number"] ?: @"",
		@"type" : type[@"@type"] ?: @"",
		@"length" : type[@"length"] ?: @(0),
		@"nextType" : next[@"@type"] ?: @"",
		@"timeout" : result[@"timeout"] ?: @(0),
		// The two Firebase answers carry the pieces the push fallback needs.
		@"receipt" : type[@"receipt"] ?: @"",
		@"pushTimeout" : type[@"push_timeout"] ?: @(0),
	};
}

- (void)sendPhoneNumberChangeCode:(NSString *)phoneNumber
					   completion:(void (^)(NSDictionary *info,
											NSString *error))completion {
	[self request:@{
		@"@type" : @"sendPhoneNumberCode",
		@"phone_number" : phoneNumber ?: @"",
		// Null is the protocol's "default settings": no flash call, no SMS
		// retriever, which is all this OS can act on anyway.
		@"settings" : [NSNull null],
		@"type" : @{@"@type" : @"phoneNumberCodeTypeChange"},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *info = TGAuthenticationCodeInfo(result);
		completion(info, info ? nil : TGAuthError(result));
	}];
}

- (void)checkPhoneNumberChangeCode:(NSString *)code
						completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"checkPhoneNumberCode", @"code" : code ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)resendPhoneNumberChangeCodeWithCompletion:
		(void (^)(NSDictionary *info, NSString *error))completion {
	[self request:@{@"@type" : @"resendPhoneNumberCode",
					@"reason" : @{@"@type" : @"resendCodeReasonUserRequest"}}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *info = TGAuthenticationCodeInfo(result);
		completion(info, info ? nil : TGAuthError(result));
	}];
}

- (void)reportPhoneNumberCodeMissingWithCompletion:
		(void (^)(NSString *error))completion {
	// The mobile network code is optional and this app cannot read one, as
	// on the login step.
	[self request:@{@"@type" : @"reportPhoneNumberCodeMissing",
					@"mobile_network_code" : @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)sendAuthenticationFirebaseSms:(NSString *)token
						   completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"sendAuthenticationFirebaseSms",
					@"token" : token ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)sendPhoneNumberFirebaseSms:(NSString *)token
						completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"sendPhoneNumberFirebaseSms",
					@"token" : token ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

#pragma mark - password recovery inside the account

/// passwordState flattened to the pieces a settings sheet draws. Some of the
/// fields are absent depending on state, so every one is read defensively.
static NSDictionary *TGPasswordStateSummary(NSDictionary *state) {
	if (![state isKindOfClass:NSDictionary.class] ||
			![state[@"@type"] isEqualToString:@"passwordState"])
		return nil;
	// Both of these are optional and arrive as null in most states; a chain
	// through them would throw on NSNull rather than read as "none".
	NSDictionary *codeInfo =
			[state[@"recovery_email_address_code_info"] isKindOfClass:NSDictionary.class]
			? state[@"recovery_email_address_code_info"] : nil;
	return @{
		@"hasPassword" : @([state[@"has_password"] boolValue]),
		@"hint" : state[@"password_hint"] ?: @"",
		@"hasRecoveryEmail" : @([state[@"has_recovery_email_address"] boolValue]),
		@"loginEmail" : state[@"login_email_address_pattern"] ?: @"",
		@"pendingResetDate" : state[@"pending_reset_date"] ?: @(0),
		@"recoveryPattern" : codeInfo[@"email_address_pattern"] ?: @"",
	};
}

- (void)requestAccountPasswordRecoveryWithCompletion:
		(void (^)(NSString *pattern, NSString *error))completion {
	[self request:@{@"@type" : @"requestPasswordRecovery"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"emailAddressAuthenticationCodeInfo"])
			completion(result[@"email_address_pattern"] ?: @"", nil);
		else
			completion(nil, TGAuthError(result));
	}];
}

- (void)checkAccountPasswordRecoveryCode:(NSString *)code
							  completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"checkPasswordRecoveryCode",
					@"recovery_code" : code ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

- (void)recoverAccountPasswordWithCode:(NSString *)code
						   newPassword:(NSString *)password
								  hint:(NSString *)hint
							completion:(void (^)(NSDictionary *state,
												 NSString *error))completion {
	[self request:@{@"@type" : @"recoverPassword",
					@"recovery_code" : code ?: @"",
					@"new_password" : password ?: @"",
					@"new_hint" : hint ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *state = TGPasswordStateSummary(result);
		completion(state, state ? nil : TGAuthError(result));
	}];
}

- (void)resetAccountPasswordWithCompletion:
		(void (^)(NSString *result, double date, NSString *error))completion {
	[self request:@{@"@type" : @"resetPassword"}
	   completion:^(NSDictionary *answer){
		if (!completion)
			return;
		NSString *type = answer[@"@type"] ?: @"";
		if ([type isEqualToString:@"resetPasswordResultOk"]){
			completion(@"ok", 0, nil);
		} else if ([type isEqualToString:@"resetPasswordResultPending"]){
			completion(@"pending", [answer[@"pending_reset_date"] doubleValue], nil);
		} else if ([type isEqualToString:@"resetPasswordResultDeclined"]){
			completion(@"declined", [answer[@"retry_date"] doubleValue], nil);
		} else {
			completion(nil, 0, TGAuthError(answer));
		}
	}];
}

- (void)cancelAccountPasswordResetWithCompletion:
		(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"cancelPasswordReset"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

#pragma mark - temporary password and saved credentials

static void TGAnswerTemporaryPasswordState(NSDictionary *result,
		void (^completion)(BOOL, NSInteger, NSString *)) {
	if (!completion)
		return;
	if ([result[@"@type"] isEqualToString:@"temporaryPasswordState"]){
		completion([result[@"has_password"] boolValue],
				   (NSInteger)[result[@"valid_for"] integerValue], nil);
	} else {
		completion(NO, 0, TGAuthError(result));
	}
}

- (void)temporaryPasswordStateWithCompletion:
		(void (^)(BOOL has, NSInteger validFor, NSString *error))completion {
	[self request:@{@"@type" : @"getTemporaryPasswordState"}
	   completion:^(NSDictionary *result){
		TGAnswerTemporaryPasswordState(result, completion);
	}];
}

- (void)createTemporaryPassword:(NSString *)password
					   validFor:(NSInteger)seconds
					 completion:(void (^)(BOOL has, NSInteger validFor,
										  NSString *error))completion {
	[self request:@{@"@type" : @"createTemporaryPassword",
					@"password" : password ?: @"",
					@"valid_for" : @((int32_t)seconds)}
	   completion:^(NSDictionary *result){
		TGAnswerTemporaryPasswordState(result, completion);
	}];
}

- (void)deleteSavedCredentialsWithCompletion:
		(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"deleteSavedCredentials"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

#pragma mark - recovery email and email verification

- (void)cancelRecoveryEmailAddressVerificationWithCompletion:
		(void (^)(NSDictionary *state, NSString *error))completion {
	[self request:@{@"@type" : @"cancelRecoveryEmailAddressVerification"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *state = TGPasswordStateSummary(result);
		completion(state, state ? nil : TGAuthError(result));
	}];
}

- (void)sendEmailAddressVerificationCodeTo:(NSString *)email
								completion:(void (^)(NSString *pattern,
													 NSString *error))completion {
	[self request:@{@"@type" : @"sendEmailAddressVerificationCode",
					@"email_address" : email ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"emailAddressAuthenticationCodeInfo"])
			completion(result[@"email_address_pattern"] ?: @"", nil);
		else
			completion(nil, TGAuthError(result));
	}];
}

- (void)resendEmailAddressVerificationCodeWithCompletion:
		(void (^)(NSString *pattern, NSString *error))completion {
	[self request:@{@"@type" : @"resendEmailAddressVerificationCode"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if ([result[@"@type"] isEqualToString:@"emailAddressAuthenticationCodeInfo"])
			completion(result[@"email_address_pattern"] ?: @"", nil);
		else
			completion(nil, TGAuthError(result));
	}];
}

- (void)checkEmailAddressVerificationCode:(NSString *)code
							   completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"checkEmailAddressVerificationCode",
					@"code" : code ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGAuthError(result));
	}];
}

#pragma mark - ownership and application verification

/// The result list is small and each member means something different to the
/// screen: allowed, password wanted, or a wait. Retry times are handed back
/// in seconds so the sheet can say how long rather than "later".
- (void)canTransferOwnershipWithCompletion:
		(void (^)(NSString *result, NSInteger retryAfter,
				  NSString *error))completion {
	[self request:@{@"@type" : @"canTransferOwnership"}
	   completion:^(NSDictionary *answer){
		if (!completion)
			return;
		NSString *type = answer[@"@type"] ?: @"";
		if ([type isEqualToString:@"canTransferOwnershipResultOk"]){
			completion(@"ok", 0, nil);
		} else if ([type isEqualToString:@"canTransferOwnershipResultPasswordNeeded"]){
			completion(@"passwordNeeded", 0, nil);
		} else if ([type isEqualToString:@"canTransferOwnershipResultPasswordTooFresh"]){
			completion(@"passwordTooFresh",
					   (NSInteger)[answer[@"retry_after"] integerValue], nil);
		} else if ([type isEqualToString:@"canTransferOwnershipResultSessionTooFresh"]){
			completion(@"sessionTooFresh",
					   (NSInteger)[answer[@"retry_after"] integerValue], nil);
		} else {
			completion(nil, 0, TGAuthError(answer));
		}
	}];
}

- (int64_t)pendingApplicationVerificationId {
	return [objc_getAssociatedObject(self,
			@selector(pendingApplicationVerificationId)) longLongValue];
}

- (NSString *)pendingApplicationVerificationNonce {
	NSString *nonce = objc_getAssociatedObject(self,
			@selector(pendingApplicationVerificationNonce));
	return [nonce isKindOfClass:NSString.class] ? nonce : @"";
}

/// The update can arrive more than once while the request is outstanding;
/// the last one is the one the token has to answer, so it is simply replaced.
- (void)noteApplicationVerificationWithId:(int64_t)verificationId
									nonce:(NSString *)nonce {
	objc_setAssociatedObject(self, @selector(pendingApplicationVerificationId),
			@(verificationId), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, @selector(pendingApplicationVerificationNonce),
			nonce ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)setApplicationVerificationToken:(NSString *)token
						 verificationId:(int64_t)verificationId
							 completion:(void (^)(NSString *error))completion {
	[self request:@{@"@type" : @"setApplicationVerificationToken",
					@"verification_id" : @(verificationId),
					@"token" : token ?: @""}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *error = TGAuthError(result);
		if (!error)
			[self noteApplicationVerificationWithId:0 nonce:@""];
		completion(error);
	}];
}

@end
