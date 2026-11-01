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
}@end
