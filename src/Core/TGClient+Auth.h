//
// TGClient+Auth.h - the client surface for sign-in: phone, code, password, email, QR, registration, push.
//
#import "TGClient+Base.h"

@interface TGClient (Auth)

/// Whether two-step verification is on, and the recovery address if it is.
- (void)hasPasswordWithCompletion:(void (^)(BOOL hasPassword,
                                            NSString *recoveryEmail))completion;

- (void)sendPhoneNumber:(NSString *)phoneNumber;

- (void)sendCode:(NSString *)code;

- (void)sendPassword:(NSString *)password;

- (void)resendAuthenticationCode;

- (void)requestQrCodeAuthentication;

/// A phone number Telegram has never seen waits here, and this is the only
/// way out of it: without it a new account enters its code and then sits on
/// the code screen forever.
- (void)registerWithFirstName:(NSString *)firstName
					 lastName:(NSString *)lastName
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// The terms Telegram sent with the registration state, or an empty string.
- (NSString *)registrationTerms;

/// Every country Telegram knows, for the phone step's picker: "code",
/// "name", "prefix" and "flag". Hidden ones are left out.
- (void)countriesWithCompletion:(void (^)(NSArray *countries))completion;

/// The country this phone is in, as Telegram guesses from the network.
- (void)countryCodeWithCompletion:(void (^)(NSString *code))completion;

/// Hands the APNs token to Telegram, which is what makes a notification
/// arrive while the app is closed. `sandbox` has to match the certificate
/// the build was signed against, or nothing is ever delivered.
- (void)registerPushToken:(NSString *)token
				  sandbox:(BOOL)sandbox
			   completion:(void (^)(BOOL ok))completion;

/// The id registerDevice answered with: this account's push identity, which
/// every notification addressed to it carries.
@property (nonatomic, readonly) int64_t pushReceiverId;

/// A notification that arrived while the app was running: TDLib turns it
/// into the ordinary updates.
- (void)processPushPayload:(NSDictionary *)payload;

/// Which account a push belongs to, decoded on Telegram's side. `ok` is NO
/// when TDLib cannot read the payload at all; the id is the same one
/// registerDevice answered with, so a push for another account on the same
/// phone can be told apart before anything is processed.
- (void)pushReceiverOfPayload:(NSDictionary *)payload
				   completion:(void (^)(BOOL ok, int64_t receiverId))completion;

/// Terms Telegram sent post-login have to be accepted before the account can
/// go on; the update names the id to accept.
- (void)acceptTermsOfService:(NSString *)termsId
				  completion:(void (^)(BOOL ok))completion;

- (void)destroySession;

- (void)logOut;

/// The email address Telegram asked for in TGAuthStateWaitEmailAddress.
- (void)sendEmailAddress:(NSString *)email;

/// The code from that email, in TGAuthStateWaitEmailCode.
- (void)sendEmailCode:(NSString *)code;

/// The address is lost: sends a fresh SMS code instead, when Telegram allows
/// it ("can_reset_email_address").
- (void)resetAuthenticationEmailAddress;

/// The phone number gets no code. Telegram logs it, which is the whole
/// official "didn't get the code?" path.
- (void)reportAuthenticationCodeMissing;

/// Forgot the cloud password at sign-in: mails a code to the recovery
/// address. `error` is nil on success; an account without a recovery address
/// gets Telegram's refusal.
- (void)requestPasswordRecoveryWithCompletion:(void (^)(NSString *error))completion;

/// Checks that code, then signs in with it - which removes the password, the
/// only thing recovery can do. `error` is nil on success.
- (void)recoverPasswordWithCode:(NSString *)code
					 completion:(void (^)(NSString *error))completion;

#pragma mark - login email address

/// Whether Telegram insists this account carries a login email before it can
/// sign in again. The request answers "ok" for a yes and an error for a no,
/// so the two are split here into a flag and the server's words.
- (void)loginEmailAddressRequiredWithCompletion:
		(void (^)(BOOL required, NSString *error))completion;

/// Point the login email somewhere else. The address is not in force until
/// the code Telegram mails it is checked; `pattern` is the masked address to
/// show while that code is outstanding.
- (void)setLoginEmailAddress:(NSString *)email
				  completion:(void (^)(NSString *pattern, NSString *error))completion;

- (void)resendLoginEmailAddressCodeWithCompletion:
		(void (^)(NSString *pattern, NSString *error))completion;

- (void)checkLoginEmailAddressCode:(NSString *)code
						completion:(void (^)(NSString *error))completion;

#pragma mark - web tokens and QR login

/// Signs in with a token from a web login, and the datacenter it belongs to.
/// Both come from the link Telegram Web shows, or from the notification an
/// official app hands over.
- (void)checkAuthenticationWebToken:(NSString *)token
							   dcId:(NSInteger)dcId
						 completion:(void (^)(NSString *error))completion;

/// Lets a web token expire without using it.
- (void)dismissWebToken:(NSString *)token
			 completion:(void (^)(NSString *error))completion;

/// Confirms a QR code scanned off another screen. `link` is the tg:// link
/// the QR was made from; success is the session Telegram creates, which
/// arrives as an authorization state.
- (void)confirmQrCodeAuthenticationLink:(NSString *)link
							 completion:(void (^)(NSString *error))completion;

/// Resolves a token from a user link to the account it names. Used by a
/// t.me user-token link, which has no username to search for.
- (void)searchUserByToken:(NSString *)token
			   completion:(void (^)(NSDictionary *user, NSString *error))completion;

#pragma mark - phone numbers

/// What a prefix is: country, calling code, formatted number, and whether
/// Telegram treats it as anonymous. `info` is nil when Telegram cannot parse
/// the prefix, whose refusal is then in the log.
- (void)phoneNumberInfoForPrefix:(NSString *)prefix
					  completion:(void (^)(NSDictionary *info))completion;

/// The same answer on the spot, for a sheet that has to fill itself before
/// it is shown. nil when the synchronous engine is unavailable (the host
/// tests) or Telegram does not know the prefix.
- (NSDictionary *)phoneNumberInfoForPrefixSync:(NSString *)prefix;

/// The change-number flow: Telegram sends a code to the new number, and the
/// number only moves once that code is checked. Answers the same code info
/// shape as the login step: "type", "pattern", "length", "timeout".
- (void)sendPhoneNumberChangeCode:(NSString *)phoneNumber
					   completion:(void (^)(NSDictionary *info,
											NSString *error))completion;

- (void)checkPhoneNumberChangeCode:(NSString *)code
						completion:(void (^)(NSString *error))completion;

- (void)resendPhoneNumberChangeCodeWithCompletion:
		(void (^)(NSDictionary *info, NSString *error))completion;

- (void)reportPhoneNumberCodeMissingWithCompletion:
		(void (^)(NSString *error))completion;

/// The code arrived by push instead of SMS: hand the secret Telegram sent to
/// the verification service. There is no SDK to fetch one here, so the sheet
/// asks for it; the server's answer is still the result.
- (void)sendAuthenticationFirebaseSms:(NSString *)token
						   completion:(void (^)(NSString *error))completion;

- (void)sendPhoneNumberFirebaseSms:(NSString *)token
						completion:(void (^)(NSString *error))completion;

#pragma mark - password recovery inside the account

/// Mails a recovery code to the address two-step verification points at.
/// `pattern` is the masked address, or nil with the server's refusal when no
/// recovery address is set.
- (void)requestAccountPasswordRecoveryWithCompletion:
		(void (^)(NSString *pattern, NSString *error))completion;

- (void)checkAccountPasswordRecoveryCode:(NSString *)code
							  completion:(void (^)(NSString *error))completion;

/// Spends a checked code: sets the new password and hint (empty password
/// removes it) and answers the resulting state.
- (void)recoverAccountPasswordWithCode:(NSString *)code
						   newPassword:(NSString *)password
								  hint:(NSString *)hint
							completion:(void (^)(NSDictionary *state,
												 NSString *error))completion;

/// Removes the password with neither the old one nor the recovery address.
/// Telegram can refuse for days: `result` is "ok", "pending" or "declined",
/// and `date` is the Unix time the next attempt or the reset is possible.
- (void)resetAccountPasswordWithCompletion:
		(void (^)(NSString *result, double date, NSString *error))completion;

- (void)cancelAccountPasswordResetWithCompletion:
		(void (^)(NSString *error))completion;

#pragma mark - temporary password and saved credentials

/// The temporary password Telegram keeps for payments. `has` and `validFor`
/// are the whole answer; there is nothing else to draw.
- (void)temporaryPasswordStateWithCompletion:
		(void (^)(BOOL has, NSInteger validFor, NSString *error))completion;

- (void)createTemporaryPassword:(NSString *)password
					   validFor:(NSInteger)seconds
					 completion:(void (^)(BOOL has, NSInteger validFor,
										  NSString *error))completion;

/// Forget every payment provider's saved credentials, as the privacy page's
/// delete row does.
- (void)deleteSavedCredentialsWithCompletion:
		(void (^)(NSString *error))completion;

#pragma mark - recovery email and email verification

/// Abandons a change of the two-step recovery address: the old address, or
/// none, stays in force. Answers the state it leaves behind.
- (void)cancelRecoveryEmailAddressVerificationWithCompletion:
		(void (^)(NSDictionary *state, NSString *error))completion;

/// Sends a verification code to an address for Telegram Passport. The app
/// has no Passport form of its own; this is the address-verification half,
/// which is the part a user can act on.
- (void)sendEmailAddressVerificationCodeTo:(NSString *)email
								completion:(void (^)(NSString *pattern,
													 NSString *error))completion;

- (void)resendEmailAddressVerificationCodeWithCompletion:
		(void (^)(NSString *pattern, NSString *error))completion;

- (void)checkEmailAddressVerificationCode:(NSString *)code
							   completion:(void (^)(NSString *error))completion;

#pragma mark - ownership and application verification

/// Whether this session may hand a chat over. Telegram answers "ok",
/// "passwordNeeded", "passwordTooFresh" or "sessionTooFresh"; the last two
/// carry the seconds to wait before trying again.
- (void)canTransferOwnershipWithCompletion:
		(void (^)(NSString *result, NSInteger retryAfter,
				  NSString *error))completion;

/// Remembers the verification Telegram asked for, so a settings row can show
/// what is pending instead of asking for an id the user cannot know.
- (void)noteApplicationVerificationWithId:(int64_t)verificationId
									nonce:(NSString *)nonce;

@property (nonatomic, readonly) int64_t pendingApplicationVerificationId;
@property (nonatomic, readonly, copy) NSString *pendingApplicationVerificationNonce;

/// Hands the verification service's token back for the pending request.
- (void)setApplicationVerificationToken:(NSString *)token
						 verificationId:(int64_t)verificationId
							 completion:(void (^)(NSString *error))completion;

@end
