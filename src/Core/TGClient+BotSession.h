//
// TGClient+BotSession.h - the calls a bot account makes: answering the
// queries Telegram sends it, its command and menu-button records, the
// managed-bot token, and the Web App host calls a bot is allowed to send.
//
// A user session may name every one of these, and Telegram decides. The Bot
// Console sends the real request and prints whatever came back, including the
// refusal; nothing here pretends a user account is a bot.
//
#import "TGClient+Base.h"

@interface TGClient (BotSession)

#pragma mark - session and passkeys

/// TDLib's bot sign-in. Only valid while the client is waiting for a phone
/// number; in a ready user session Telegram answers with its refusal, which
/// is the honest result the console shows.
- (void)checkAuthenticationBotToken:(NSString *)token
						 completion:(void (^)(BOOL ok, NSString *error))completion;

/// The text Telegram uses to explain passkey support to this client.
- (void)passkeyParametersWithCompletion:(void (^)(NSString *text,
												  NSString *error))completion;

- (void)authenticationPasskeyParametersWithCompletion:
		(void (^)(NSString *text, NSString *error))completion;

/// Passkeys registered on this account. Each row keeps "id", "name",
/// "additionDate", "lastUsageDate" and "softwareIconCustomEmojiId".
- (void)loginPasskeysWithCompletion:(void (^)(NSArray *passkeys,
											 NSString *error))completion;

/// Registers a passkey. `attestationObject` is base64: TDLib's JSON carries
/// bytes as base64, and the OS passkey sheet is not part of this build.
- (void)addLoginPasskey:(NSString *)clientData
	  attestationObject:(NSString *)attestationObject
			 completion:(void (^)(NSDictionary *passkey,
								 NSString *error))completion;

- (void)removeLoginPasskey:(NSString *)passkeyId
				completion:(void (^)(BOOL ok, NSString *error))completion;

/// Finishes a passkey sign-in with the credential the authenticator produced.
/// The three byte fields are base64, as the OS would hand them over.
- (void)checkAuthenticationPasskey:(NSString *)credentialId
						clientData:(NSString *)clientData
				   authenticatorData:(NSString *)authenticatorData
						   signature:(NSString *)signature
						userHandle:(NSString *)userHandle
						completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - commands and menu button

/// "default" or "chat". A chat scope needs `chatId`; the server refuses a
/// chat command list from an account that cannot manage it.
- (void)commandsForScope:(NSString *)scope
				  chatId:(int64_t)chatId
				language:(NSString *)language
			  completion:(void (^)(NSDictionary *commands,
								   NSString *error))completion;

/// Each element is a dictionary with "command", "description" and optional
/// "ephemeral", or a bare command string.
- (void)setCommands:(NSArray *)commands
			  scope:(NSString *)scope
			 chatId:(int64_t)chatId
		   language:(NSString *)language
		 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteCommandsForScope:(NSString *)scope
						chatId:(int64_t)chatId
					  language:(NSString *)language
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// The menu button Telegram shows beside a bot. `botUserId` is the bot's
/// user id, not this account's.
- (void)menuButtonForBot:(int64_t)botUserId
			  completion:(void (^)(NSDictionary *button,
								   NSString *error))completion;

/// A text/URL menu button. TDLib's BotMenuButton is one concrete shape, so
/// both fields are required; an empty button is not a request this schema
/// can express.
- (void)setMenuButtonForBot:(int64_t)botUserId
					   text:(NSString *)text
						url:(NSString *)url
				 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - managed bot

/// The token of a bot this account manages. `revoke` asks Telegram to rotate
/// it, which invalidates the old one everywhere.
- (void)managedBotTokenForBot:(int64_t)botUserId
					   revoke:(BOOL)revoke
				   completion:(void (^)(NSString *token,
										NSString *error))completion;

/// "isRestricted" and "addedUserIds" as Telegram holds them.
- (void)managedBotAccessSettingsForBot:(int64_t)botUserId
							completion:(void (^)(NSDictionary *settings,
												 NSString *error))completion;

- (void)setManagedBotAccessSettingsForBot:(int64_t)botUserId
							  restricted:(BOOL)restricted
							   addedUserIds:(NSArray *)userIds
								completion:(void (^)(BOOL ok,
													 NSString *error))completion;

/// A bot tells Telegram how many updates are still queued. The count and the
/// last error text are the bot's own report; a user account usually gets a
/// refusal, which is what the console shows.
- (void)setBotUpdatesStatus:(int32_t)pendingUpdateCount
			   errorMessage:(NSString *)errorMessage
				 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - query answers

- (void)answerInlineQuery:(int64_t)inlineQueryId
			   isPersonal:(BOOL)isPersonal
			  resultTitle:(NSString *)title
				 resultId:(NSString *)resultId
					  url:(NSString *)url
				 cacheTime:(int32_t)cacheTime
				nextOffset:(NSString *)nextOffset
				completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)answerCallbackQuery:(int64_t)callbackQueryId
					   text:(NSString *)text
				  showAlert:(BOOL)showAlert
						url:(NSString *)url
				  cacheTime:(int32_t)cacheTime
				 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)answerCustomQuery:(int64_t)customQueryId
					 data:(NSString *)data
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)answerGuestQuery:(int64_t)guestQueryId
			 resultTitle:(NSString *)title
				resultId:(NSString *)resultId
					 url:(NSString *)url
			  completion:(void (^)(NSString *inlineMessageId,
								   NSString *error))completion;

- (void)answerWebAppQuery:(NSString *)webAppQueryId
			  resultTitle:(NSString *)title
				 resultId:(NSString *)resultId
					  url:(NSString *)url
			   completion:(void (^)(NSString *inlineMessageId,
									NSString *error))completion;

- (void)answerPreCheckoutQuery:(int64_t)preCheckoutQueryId
				  errorMessage:(NSString *)errorMessage
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// An empty option list with Telegram's error text is a valid answer for a
/// shipping query this bot cannot fulfil.
- (void)answerShippingQuery:(int64_t)shippingQueryId
			   errorMessage:(NSString *)errorMessage
				 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Replaces a callback's message with an ephemeral one. The content is a
/// plain text message; the callback id is the bot's own.
- (void)replyToCallbackQueryWithEphemeralMessage:(int64_t)callbackQueryId
										   text:(NSString *)text
					 replaceCallbackMessage:(BOOL)replaceCallbackMessage
							  protectContent:(BOOL)protectContent
								 completion:(void (^)(BOOL ok,
													  NSString *error))completion;

#pragma mark - Web App host

- (void)openWebAppInChat:(int64_t)chatId
				   bot:(int64_t)botUserId
					 url:(NSString *)url
				  mode:(NSString *)mode
			  completion:(void (^)(NSDictionary *info,
								   NSString *error))completion;

- (void)closeWebApp:(int64_t)launchId
		 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)checkWebAppFileDownload:(int64_t)botUserId
					   fileName:(NSString *)fileName
							url:(NSString *)url
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)guardBotWebAppURLForQuery:(int64_t)queryId
							 mode:(NSString *)mode
					   completion:(void (^)(NSString *link,
											NSString *error))completion;

- (void)sendWebAppData:(int64_t)botUserId
			buttonText:(NSString *)buttonText
				  data:(NSString *)data
			completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)sendWebAppCustomRequest:(int64_t)botUserId
						 method:(NSString *)method
					 parameters:(NSString *)parameters
					 completion:(void (^)(NSString *result,
										  NSString *error))completion;

@end

// vim:ft=objc
