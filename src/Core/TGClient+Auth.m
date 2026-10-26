#import "TGClientInternal.h"

@implementation TGClient (Auth)

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

- (void)logOut {
	[self send:@{@"@type" : @"logOut"}];
}

@end
