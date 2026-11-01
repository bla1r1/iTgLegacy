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

/// A notification that arrived while the app was running: TDLib turns it
/// into the ordinary updates.
- (void)processPushPayload:(NSDictionary *)payload;

/// What a push belongs to, decoded on Telegram's side: whether it went
/// through ("ok") and the chat and message it names. Answered even when the
/// push is undeliverable, which is how the half-configured certificate gets
/// told apart from a payload TDLib cannot read.
- (void)pushReceiverOfPayload:(NSDictionary *)payload
				   completion:(void (^)(BOOL ok, int64_t chatId, int64_t messageId))completion;

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

@end
