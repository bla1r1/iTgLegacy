//
// TGClient+Business.h - Telegram Business settings, chat links and the
// business-bot message wire.
//
// The account-level settings (location, opening hours, greeting and away
// messages, intro, links to chat) are what Telegram Business subscribers
// change from Settings. The account profile and the message calls carry a
// business connection id: TDLib marks them "for bots only", so a user
// account gets Telegram's refusal and the screen shows it rather than
// pretending the row is not there.
//
#import "TGClient+Base.h"

/// The part after t.me/ in a business chat link. getBusinessChatLinkInfo
/// names the link, not its URL.
FOUNDATION_EXPORT NSString *TGBusinessLinkName(NSString *link);

@interface TGClient (Business)

/// getBusinessFeatures. `source` is a businessFeature* type name or nil for
/// the Settings page; the answer is the feature type names Telegram lists.
- (void)businessFeaturesForSource:(NSString *)source
					   completion:(void (^)(NSArray *features, NSString *error))completion;

/// The business_info half of this account's getUserFullInfo. Empty until a
/// Business subscription fills it in.
- (void)businessInfoWithCompletion:(void (^)(NSDictionary *info, NSString *error))completion;

/// getBusinessConnection. Bot-only in TDLib; a user account's refusal is
/// returned as `error` and shown on the connection screen.
- (void)businessConnectionWithId:(NSString *)connectionId
					  completion:(void (^)(NSDictionary *connection, NSString *error))completion;

#pragma mark - account profile (business connection)

- (void)setBusinessAccountName:(NSString *)firstName
						  last:(NSString *)lastName
				  connectionId:(NSString *)connectionId
					completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setBusinessAccountBio:(NSString *)bio
				 connectionId:(NSString *)connectionId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setBusinessAccountUsername:(NSString *)username
					  connectionId:(NSString *)connectionId
						completion:(void (^)(BOOL ok, NSString *error))completion;

/// An empty path removes the photo, which TDLib spells as a null photo.
- (void)setBusinessAccountProfilePhotoAtPath:(NSString *)path
									public:(BOOL)isPublic
								connectionId:(NSString *)connectionId
								  completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - links to chat

- (void)businessChatLinksWithCompletion:(void (^)(NSArray *links, NSString *error))completion;

- (void)createBusinessChatLinkWithText:(NSString *)text
								 title:(NSString *)title
							completion:(void (^)(NSDictionary *link, NSString *error))completion;

- (void)editBusinessChatLink:(NSString *)link
						text:(NSString *)text
					   title:(NSString *)title
				  completion:(void (^)(NSDictionary *edited, NSString *error))completion;

- (void)deleteBusinessChatLink:(NSString *)link
					completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)businessChatLinkInfoForName:(NSString *)linkName
						 completion:(void (^)(NSDictionary *info, NSString *error))completion;

#pragma mark - account settings

/// A nil latitude removes the location; TDLib spells that as a null object.
- (void)setBusinessLocationLatitude:(NSNumber *)latitude
						  longitude:(NSNumber *)longitude
							address:(NSString *)address
						 completion:(void (^)(BOOL ok, NSString *error))completion;

/// `intervals` are dictionaries with "start_minute" and "end_minute",
/// counted from Monday 00:00 in a week. Nil or empty removes the schedule.
- (void)setBusinessOpeningHoursTimeZone:(NSString *)timeZone
							  intervals:(NSArray *)intervals
							 completion:(void (^)(BOOL ok, NSString *error))completion;

/// `recipients` is a businessRecipients dictionary; nil means every
/// one-to-one chat. Off sends the null settings that disable the greeting.
- (void)setBusinessGreetingMessageEnabled:(BOOL)enabled
							   shortcutId:(NSInteger)shortcutId
						   inactivityDays:(NSInteger)inactivityDays
							   recipients:(NSDictionary *)recipients
							   completion:(void (^)(BOOL ok, NSString *error))completion;

/// `schedule` is "always", "outside" or "custom"; custom uses the two int32
/// dates. Off sends the null settings that disable the away message.
- (void)setBusinessAwayMessageEnabled:(BOOL)enabled
						   shortcutId:(NSInteger)shortcutId
							 schedule:(NSString *)schedule
							startDate:(int32_t)startDate
							  endDate:(int32_t)endDate
						  offlineOnly:(BOOL)offlineOnly
						   recipients:(NSDictionary *)recipients
						   completion:(void (^)(BOOL ok, NSString *error))completion;

/// The intro people see before they start a chat. Empty title and message
/// remove it. The sticker is a local image path, or nil for none.
- (void)setBusinessStartPageTitle:(NSString *)title
						  message:(NSString *)message
					  stickerPath:(NSString *)stickerPath
					   completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - business messages (business connection)

- (void)sendBusinessMessageWithConnectionId:(NSString *)connectionId
									 chatId:(int64_t)chatId
									   text:(NSString *)text
						   disableNotification:(BOOL)disableNotification
							  protectContent:(BOOL)protectContent
								 completion:(void (^)(NSDictionary *message, NSString *error))completion;

- (void)sendBusinessMessageAlbumWithConnectionId:(NSString *)connectionId
										  chatId:(int64_t)chatId
										   paths:(NSArray *)paths
										  caption:(NSString *)caption
							  disableNotification:(BOOL)disableNotification
								 protectContent:(BOOL)protectContent
									  completion:(void (^)(NSArray *messages, NSString *error))completion;

- (void)editBusinessMessageTextWithConnectionId:(NSString *)connectionId
										 chatId:(int64_t)chatId
									  messageId:(int64_t)messageId
										   text:(NSString *)text
									 completion:(void (^)(NSDictionary *message, NSString *error))completion;

- (void)editBusinessMessageCaptionWithConnectionId:(NSString *)connectionId
											chatId:(int64_t)chatId
										 messageId:(int64_t)messageId
										   caption:(NSString *)caption
										completion:(void (^)(NSDictionary *message, NSString *error))completion;

- (void)editBusinessMessageMediaWithConnectionId:(NSString *)connectionId
										  chatId:(int64_t)chatId
									   messageId:(int64_t)messageId
											path:(NSString *)path
										 isVideo:(BOOL)isVideo
										 caption:(NSString *)caption
									  completion:(void (^)(NSDictionary *message, NSString *error))completion;

/// A `livePeriod` of zero stops the live location.
- (void)editBusinessMessageLiveLocationWithConnectionId:(NSString *)connectionId
												 chatId:(int64_t)chatId
											  messageId:(int64_t)messageId
											   latitude:(double)latitude
											  longitude:(double)longitude
											 livePeriod:(NSInteger)livePeriod
											 completion:(void (^)(NSDictionary *message, NSString *error))completion;

- (void)editBusinessMessageChecklistWithConnectionId:(NSString *)connectionId
											  chatId:(int64_t)chatId
										   messageId:(int64_t)messageId
											   title:(NSString *)title
											   tasks:(NSArray *)tasks
											completion:(void (^)(NSDictionary *message, NSString *error))completion;

/// TDLib takes null for no markup; this is the request that clears one.
- (void)editBusinessMessageReplyMarkupWithConnectionId:(NSString *)connectionId
												chatId:(int64_t)chatId
											 messageId:(int64_t)messageId
											completion:(void (^)(NSDictionary *message, NSString *error))completion;

- (void)stopBusinessPollWithConnectionId:(NSString *)connectionId
								  chatId:(int64_t)chatId
							   messageId:(int64_t)messageId
							  completion:(void (^)(NSDictionary *message, NSString *error))completion;

- (void)readBusinessMessageWithConnectionId:(NSString *)connectionId
									 chatId:(int64_t)chatId
								  messageId:(int64_t)messageId
								 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setBusinessMessagePinnedWithConnectionId:(NSString *)connectionId
										  chatId:(int64_t)chatId
									   messageId:(int64_t)messageId
										  pinned:(BOOL)pinned
									  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteBusinessMessagesWithConnectionId:(NSString *)connectionId
									 messageIds:(NSArray *)messageIds
									 completion:(void (^)(BOOL ok, NSString *error))completion;

@end

// vim:ft=objc
