//
// TGClient+Tier3.h - the part of the old "never" list a user account can
// actually call.
//
// The tier script parked these because their names matched a broad pattern:
// "Sponsored" read as an advertising stack, "Log" as a developer console,
// "Bot" as a bot session. That is not what TDLib says. A user client sees
// sponsored messages in channels, reads and writes its own bot records when
// it owns one, controls TDLib's log, and can redeem a Premium code. The
// methods here send the real request and hand back the server's answer; the
// ones that stay out are the payment, wallet, Web App, Passport and bot-session
// calls listed in scripts/tdlib_tiers.py.
//
#import "TGClient+Base.h"

@interface TGClient (Tier3)

#pragma mark - sponsored messages and video advertisements

/// Advertisements Telegram wants under a channel or bot chat. Each entry is
/// "messageId", "isRecommended", "canBeReported", "title", "buttonText",
/// "sponsor", "additionalInfo" and "contentType".
- (void)sponsoredMessagesForChat:(int64_t)chatId
					  completion:(void (^)(NSArray *messages,
										   NSString *error))completion;

/// Tells Telegram the advertisement was opened: its name, its media or its
/// full-screen video. The answer is Telegram's, usually just ok.
- (void)clickSponsoredMessage:(int64_t)messageId
					   inChat:(int64_t)chatId
					mediaClick:(BOOL)mediaClick
				  fromFullscreen:(BOOL)fromFullscreen
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Reports a sponsored message. An empty option id asks Telegram for the
/// reason list; the answer says whether it wants a choice, accepted the
/// report, hid ads, or requires Premium.
- (void)reportSponsoredMessage:(int64_t)messageId
						inChat:(int64_t)chatId
						option:(NSString *)optionId
					completion:(void (^)(NSDictionary *result,
										 NSString *error))completion;

/// The account-wide switch. Telegram ignores it for non-Premium accounts,
/// where sponsored messages are always shown; the server's answer says so.
- (void)setSponsoredMessagesEnabled:(BOOL)enabled
						 completion:(void (^)(BOOL ok, NSString *error))completion;

/// The owner's switch for one channel. `supergroupId` is the supergroup id,
/// not the chat id; the screen says so where it asks.
- (void)setChannelSponsoredMessagesEnabled:(BOOL)enabled
							  supergroupId:(int64_t)supergroupId
							   completion:(void (^)(BOOL ok,
													NSString *error))completion;

/// Sponsored chats in search results. Each row is "uniqueId", "chatId",
/// "sponsorInfo" and "additionalInfo".
- (void)searchSponsoredChats:(NSString *)query
				  completion:(void (^)(NSArray *chats,
									   NSString *error))completion;

- (void)openSponsoredChat:(int64_t)uniqueId
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)viewSponsoredChat:(int64_t)uniqueId
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)reportSponsoredChat:(int64_t)uniqueId
					 option:(NSString *)optionId
				 completion:(void (^)(NSDictionary *result,
									 NSString *error))completion;

/// Advertisements that play before or under one video message. Each row is
/// "uniqueId", "text", "minDisplayDuration", "maxDisplayDuration",
/// "canBeReported", "title", "sponsor" and "additionalInfo".
- (void)videoAdvertisementsForChat:(int64_t)chatId
						 message:(int64_t)messageId
					  completion:(void (^)(NSArray *advertisements,
										   NSString *error))completion;

- (void)clickVideoAdvertisement:(int64_t)uniqueId
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)viewVideoAdvertisement:(int64_t)uniqueId
					completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)reportVideoAdvertisement:(int64_t)uniqueId
						  option:(NSString *)optionId
					  completion:(void (^)(NSDictionary *result,
										   NSString *error))completion;

#pragma mark - speech recognition

/// Asks Telegram's own recognizer to transcribe a voice or video note. TDLib
/// answers ok at once and the text arrives in updateMessageContent; the chat
/// re-reads the message and the bubble shows the result. No speech engine is
/// shipped with the app, and none is needed.
- (void)recognizeSpeechInChat:(int64_t)chatId
					  message:(int64_t)messageId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Quality vote for a finished transcript.
- (void)rateSpeechInChat:(int64_t)chatId
				 message:(int64_t)messageId
					isGood:(BOOL)isGood
			  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Informs TDLib that a music file was listened to for `duration` seconds.
/// Telegram uses it for the "listened" mark and for recommendations.
- (void)markAudioListened:(int32_t)fileId
				 duration:(int32_t)duration
			   completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - TDLib environment and log

/// Converts JSON text to TDLib's JsonValue tree. Nil with `error` when the
/// text is not JSON or the dylib has no execute symbol.
- (void)jsonValueForText:(NSString *)text
			  completion:(void (^)(NSDictionary *value,
								   NSString *error))completion;

/// The reverse: a JsonValue tree down to compact JSON text.
- (void)jsonTextForValue:(NSDictionary *)value
			  completion:(void (^)(NSString *text,
								   NSString *error))completion;

/// The colour set Telegram's payment and Web App surfaces expect, serialised.
/// The caller supplies the roles; missing ones are zero, which is how TDLib
/// represents black.
- (void)themeParametersJSONString:(NSDictionary *)colours
					   completion:(void (^)(NSString *text,
											NSString *error))completion;

- (void)logStreamWithCompletion:(void (^)(NSDictionary *stream,
										  NSString *error))completion;

- (void)logVerbosityLevelWithCompletion:(void (^)(int32_t level,
												  NSString *error))completion;

- (void)logTagsWithCompletion:(void (^)(NSArray *tags, NSString *error))completion;

- (void)logVerbosityForTag:(NSString *)tag
				completion:(void (^)(int32_t level, NSString *error))completion;

- (void)setLogVerbosityForTag:(NSString *)tag
						level:(int32_t)level
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Switches TDLib's log to a file, to stderr or off. `kind` is "file",
/// "default" or "empty"; a file stream needs a path.
- (void)setLogStreamKind:(NSString *)kind
					path:(NSString *)path
			  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Writes one line into TDLib's log at `level`; useful when a device log has
/// to line up with what the app did. `text` is not user data.
- (void)addLogMessage:(NSString *)text
				level:(int32_t)level
		   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Sends one application event to the server's log. Can be called before
/// sign-in, so it is also the login screen's only diagnostic.
- (void)saveApplicationLogEvent:(NSString *)type
						chatId:(int64_t)chatId
						  data:(NSString *)data
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// The time zones TDLib knows, as "id", "name" and "offset" (seconds).
- (void)timeZonesWithCompletion:(void (^)(NSArray *zones,
										  NSString *error))completion;

/// Exchange rates to USD, as "currency" and "rate".
- (void)currencyExchangeRatesWithCompletion:(void (^)(NSArray *rates,
													 NSString *error))completion;

/// Weather at one point, from Telegram's weather source: "temperature" and
/// "emoji".
- (void)currentWeatherAtLatitude:(double)latitude
					   longitude:(double)longitude
					  completion:(void (^)(NSDictionary *weather,
										   NSString *error))completion;

/// Succeeds after `seconds`. The only user-visible use is a deliberate wait
/// in the diagnostics screen; TDLib keeps the timer, not the app.
- (void)alarmAfterSeconds:(double)seconds
			   completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - bots the user owns and inline bots

/// YES when the cached user record says this account is a bot. The profile
/// uses it to decide whether the Bot Settings row can do anything.
- (BOOL)userIsBot:(int64_t)userId;

/// Every bot owned by this account, as "id", "name" and "username".
- (void)ownedBotsWithCompletion:(void (^)(NSArray *bots,
										  NSString *error))completion;

/// Whether a username is free for a new bot or as a secondary name. The
/// answer is a word: "ok", "invalid", "occupied", "purchasable",
/// "tooLong", "tooShort" or "unsupported".
- (void)checkBotUsername:(NSString *)username
			  isSecondary:(BOOL)isSecondary
			   completion:(void (^)(NSString *result,
									NSString *error))completion;

- (void)botNameForBot:(int64_t)botUserId
			 language:(NSString *)language
		   completion:(void (^)(NSString *name, NSString *error))completion;

- (void)setBotName:(NSString *)name
			forBot:(int64_t)botUserId
		  language:(NSString *)language
		completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)botDescriptionForBot:(int64_t)botUserId
					language:(NSString *)language
				  completion:(void (^)(NSString *text,
									   NSString *error))completion;

- (void)setBotDescription:(NSString *)text
				   forBot:(int64_t)botUserId
				 language:(NSString *)language
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)botShortDescriptionForBot:(int64_t)botUserId
						 language:(NSString *)language
					   completion:(void (^)(NSString *text,
											NSString *error))completion;

- (void)setBotShortDescription:(NSString *)text
						forBot:(int64_t)botUserId
					  language:(NSString *)language
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// Removes an owned bot's photo. A replacement needs an uploaded photo, which
/// is the same static-photo path the profile screen already owns; this call
/// is the null half of setBotProfilePhoto.
- (void)removeBotProfilePhoto:(int64_t)botUserId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)addBotSecondaryUsername:(NSString *)username
						 forBot:(int64_t)botUserId
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteBotSecondaryUsernameForBot:(int64_t)botUserId
							  completion:(void (^)(BOOL ok,
												   NSString *error))completion;

- (void)setBotUsername:(NSString *)username
				active:(BOOL)active
				forBot:(int64_t)botUserId
			completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)reorderBotActiveUsernames:(NSArray *)usernames
						   forBot:(int64_t)botUserId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// The owned bot's media previews, as "fileId", "date" and "contentType".
- (void)botMediaPreviewsForBot:(int64_t)botUserId
					completion:(void (^)(NSArray *previews,
										 NSString *error))completion;

/// Previews for one language plus the languages the bot has for them.
- (void)botMediaPreviewInfoForBot:(int64_t)botUserId
						 language:(NSString *)language
					   completion:(void (^)(NSDictionary *info,
											NSString *error))completion;

/// Adds a preview from a file already known to TDLib. `video` chooses the
/// video content shape; the duration and cover frame default to a still
/// preview's values when it is NO.
- (void)addBotMediaPreviewForBot:(int64_t)botUserId
						language:(NSString *)language
						  fileId:(int32_t)fileId
						   video:(BOOL)video
					  completion:(void (^)(NSDictionary *preview,
										   NSString *error))completion;

- (void)editBotMediaPreviewForBot:(int64_t)botUserId
						 language:(NSString *)language
						   fileId:(int32_t)fileId
					   newFileId:(int32_t)newFileId
							video:(BOOL)video
					   completion:(void (^)(NSDictionary *preview,
											NSString *error))completion;

- (void)deleteBotMediaPreviewsForBot:(int64_t)botUserId
							language:(NSString *)language
							 fileIds:(NSArray *)fileIds
						  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)reorderBotMediaPreviewsForBot:(int64_t)botUserId
							 language:(NSString *)language
							  fileIds:(NSArray *)fileIds
						   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)similarBotCountForBot:(int64_t)botUserId
						local:(BOOL)localOnly
				   completion:(void (^)(int32_t count, NSString *error))completion;

- (void)similarBotsForBot:(int64_t)botUserId
			   completion:(void (^)(NSArray *bots, NSString *error))completion;

- (void)openSimilarBot:(int64_t)openedBotId
			   fromBot:(int64_t)botUserId
			completion:(void (^)(BOOL ok, NSString *error))completion;

/// Whether an owned bot may change this account's emoji status.
- (void)setBotCanManageEmojiStatus:(BOOL)allowed
							forBot:(int64_t)botUserId
						completion:(void (^)(BOOL ok, NSString *error))completion;

/// An owned bot's verification mark on a user or chat. `kind` is "user" or
/// "chat"; an empty description uses Telegram's default wording.
- (void)setBotVerification:(int64_t)botUserId
			 verifiedKind:(NSString *)kind
				 verifiedId:(int64_t)verifiedId
				description:(NSString *)description
				 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)removeBotVerification:(int64_t)botUserId
				 verifiedKind:(NSString *)kind
					 verifiedId:(int64_t)verifiedId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Creates a bot managed by `managerBotId`. Returns the new user row.
- (void)createBotNamed:(NSString *)name
			  username:(NSString *)username
			  manager:(int64_t)managerBotId
			completion:(void (^)(NSDictionary *bot, NSString *error))completion;

/// The user's recently used inline bots.
- (void)recentInlineBotsWithCompletion:(void (^)(NSArray *bots,
												NSString *error))completion;

/// Starts a bot in a chat with the deep-link parameter. Returns the sent
/// message record's id and text, or Telegram's refusal.
- (void)startBot:(int64_t)botUserId
		  inChat:(int64_t)chatId
	   parameter:(NSString *)parameter
	  completion:(void (^)(NSDictionary *message,
						   NSString *error))completion;

/// Whether a bot can be put on the attachment menu and whether it already is.
- (void)attachmentMenuBot:(int64_t)botUserId
			   completion:(void (^)(NSDictionary *bot,
									NSString *error))completion;

- (void)setBotOnAttachmentMenu:(int64_t)botUserId
					   added:(BOOL)added
			 allowWriteAccess:(BOOL)allowWriteAccess
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// Whether a bot is allowed to message this account. A 404 means it may ask;
/// the error text is Telegram's.
- (void)canBotSendMessages:(int64_t)botUserId
				completion:(void (^)(BOOL can, NSString *error))completion;

- (void)allowBotToSendMessages:(int64_t)botUserId
					completion:(void (^)(BOOL ok, NSString *error))completion;

/// Adds one inline result to a saved reply shortcut, for the inline flow the
/// composer already knows how to run.
- (void)addInlineResultToQuickReply:(NSString *)shortcutName
						 replyToId:(int64_t)replyToMessageId
						   queryId:(int64_t)queryId
						  resultId:(NSString *)resultId
						 hideViaBot:(BOOL)hideViaBot
						completion:(void (^)(NSDictionary *message,
											 NSString *error))completion;

#pragma mark - web browser settings and Web App links

/// How this account opens links: in the system browser or in an in-app one.
/// This client has no in-app browser, so `displayCloseButton` is sent as NO
/// and the setting still records Telegram's choice.
- (void)setWebBrowserSettingsOpenExternal:(BOOL)openExternal
						displayCloseButton:(BOOL)displayCloseButton
							   completion:(void (^)(BOOL ok,
													NSString *error))completion;

/// One URL handled differently from the default.
- (void)addWebBrowserException:(NSString *)url
				  openExternal:(BOOL)openExternal
					completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)removeWebBrowserException:(NSString *)url
					   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)removeAllWebBrowserExceptionsWithCompletion:(void (^)(BOOL ok,
															 NSString *error))completion;

/// The Web App catalogue a user can browse without a Web App host.
- (void)grossingWebAppBotsOffset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *bots, NSString *error))completion;

- (void)searchWebAppForBot:(int64_t)botUserId
				 shortName:(NSString *)shortName
				completion:(void (^)(NSDictionary *app, NSString *error))completion;

- (void)webAppPlaceholderForBot:(int64_t)botUserId
					 completion:(void (^)(NSString *outline, NSString *error))completion;

/// The three URL getters. They answer a link; opening it needs a Web App host,
/// which this client does not have, so the screen copies it instead.
- (void)webAppURLForBot:(int64_t)botUserId
					url:(NSString *)url
				   mode:(NSString *)mode
			 completion:(void (^)(NSString *link, NSString *error))completion;

- (void)mainWebAppForBot:(int64_t)botUserId
				  chatId:(int64_t)chatId
		  startParameter:(NSString *)startParameter
					mode:(NSString *)mode
			  completion:(void (^)(NSString *link, NSString *error))completion;

- (void)webAppLinkURLForBot:(int64_t)botUserId
					 chatId:(int64_t)chatId
				  shortName:(NSString *)shortName
			 startParameter:(NSString *)startParameter
				 allowWrite:(BOOL)allowWrite
					   mode:(NSString *)mode
				 completion:(void (^)(NSString *link, NSString *error))completion;

/// The two keyboard-button answers a person gives a bot: share one chat, or
/// share a list of users. `sourceChat`/`sourceMessage` name the message the
/// button came from.
- (void)shareChatWithBot:(int64_t)botUserId
			 sourceChat:(int64_t)sourceChatId
		  sourceMessage:(int64_t)sourceMessageId
			   buttonId:(int32_t)buttonId
			  sharedChat:(int64_t)sharedChatId
				checkOnly:(BOOL)checkOnly
			   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)shareUsersWithBot:(int64_t)botUserId
			  sourceChat:(int64_t)sourceChatId
		   sourceMessage:(int64_t)sourceMessageId
				buttonId:(int32_t)buttonId
				 userIds:(NSArray *)userIds
			   checkOnly:(BOOL)checkOnly
			  completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - OAuth links

- (void)oauthLinkInfo:(NSString *)url
			   origin:(NSString *)origin
		   completion:(void (^)(NSDictionary *info,
								NSString *error))completion;

- (void)checkOauthMatchCode:(NSString *)code
						forURL:(NSString *)url
					  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Accepts an OAuth request and answers the URL that finishes it. The URL is
/// opened in the browser; this client hosts no in-app browser.
- (void)acceptOauthRequest:(NSString *)url
				 matchCode:(NSString *)code
			allowWriteAccess:(BOOL)allowWriteAccess
		 allowPhoneNumberAccess:(BOOL)allowPhoneNumberAccess
				completion:(void (^)(NSString *link, NSString *error))completion;

- (void)declineOauthRequest:(NSString *)url
				 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - business bot

/// The business bot connected to this account. Nil with Telegram's 404 text
/// when there is none.
- (void)businessConnectedBotWithCompletion:(void (^)(NSDictionary *bot,
													 NSString *error))completion;

/// Connects or replaces the business bot. `recipients` follows
/// businessRecipients; missing keys are false.
- (void)setBusinessConnectedBot:(int64_t)botUserId
					 recipients:(NSDictionary *)recipients
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteBusinessConnectedBot:(int64_t)botUserId
						completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)confirmBusinessConnectedBot:(int64_t)botUserId
						 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)removeBusinessConnectedBotFromChat:(int64_t)chatId
								completion:(void (^)(BOOL ok,
													 NSString *error))completion;

- (void)pauseBusinessConnectedBotInChat:(int64_t)chatId
								 paused:(BOOL)paused
							 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - Premium, Stars and gifts, read-only

/// The feature and limit lists on the Premium page. Each feature is its type
/// name; each limit keeps "type", "defaultValue" and "premiumValue".
- (void)premiumFeaturesFromSource:(NSString *)source
					   completion:(void (^)(NSDictionary *features,
											NSString *error))completion;

/// Tells Telegram a Premium feature card was opened.
- (void)viewPremiumFeature:(NSString *)featureType
				completion:(void (^)(BOOL ok, NSString *error))completion;

/// One limit's free and Premium values, as "type", "defaultValue" and
/// "premiumValue".
- (void)premiumLimitOfType:(NSString *)limitType
				completion:(void (^)(NSDictionary *limit,
									 NSString *error))completion;

/// Premium stickers, examples and the month-specific info sticker.
- (void)premiumStickersWithLimit:(int32_t)limit
					  completion:(void (^)(NSArray *stickers,
										   NSString *error))completion;

- (void)premiumStickerExamplesWithCompletion:(void (^)(NSArray *stickers,
													   NSString *error))completion;

- (void)premiumInfoStickerForMonths:(int32_t)months
						 completion:(void (^)(NSDictionary *sticker,
											 NSString *error))completion;

/// Checks a Premium gift code without redeeming it. The answer keeps
/// "monthCount", "dayCount", "isFromGiveaway", "userId" and "useDate".
- (void)checkPremiumGiftCode:(NSString *)code
				  completion:(void (^)(NSDictionary *info,
									   NSString *error))completion;

- (void)applyPremiumGiftCode:(NSString *)code
				  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Tells Telegram the Premium subscribe button was pressed. The purchase
/// itself is the App Store's, which this build does not carry; the signal is
/// still real and is what the server logs.
- (void)clickPremiumSubscriptionButtonWithCompletion:(void (^)(BOOL ok,
															  NSString *error))completion;

#pragma mark - boosts

/// Boost slots this account can still spend, as "slotId",
/// "currentlyBoostedChatId", "startDate", "expirationDate" and
/// "cooldownUntilDate".
- (void)availableChatBoostSlotsWithCompletion:(void (^)(NSArray *slots,
													   NSString *error))completion;

/// A chat's boost level and counts, as "level", "boostCount",
/// "currentLevelBoostCount", "nextLevelBoostCount" and "boostUrl".
- (void)chatBoostStatusForChat:(int64_t)chatId
					completion:(void (^)(NSDictionary *status,
										 NSString *error))completion;

/// The offline feature table for channels or groups.
- (void)chatBoostFeaturesForChannel:(BOOL)isChannel
						 completion:(void (^)(NSDictionary *features,
											  NSString *error))completion;

- (void)chatBoostLevelFeaturesForChannel:(BOOL)isChannel
								   level:(int32_t)level
							  completion:(void (^)(NSDictionary *features,
												   NSString *error))completion;

- (void)chatBoostLinkForChat:(int64_t)chatId
				  completion:(void (^)(NSString *link, NSString *error))completion;

- (void)chatBoostLinkInfo:(NSString *)url
			   completion:(void (^)(NSDictionary *info, NSString *error))completion;

/// The boosts on a chat; `offset` and `limit` page the list.
- (void)chatBoostsForChat:(int64_t)chatId
				   offset:(NSString *)offset
					limit:(int32_t)limit
			   completion:(void (^)(NSDictionary *page, NSString *error))completion;

/// Spends the named slots on a chat. No payment provider is involved: the
/// slots are the Premium boost allowance.
- (void)boostChat:(int64_t)chatId
		  slotIds:(NSArray *)slotIds
	   completion:(void (^)(NSArray *slots, NSString *error))completion;

#pragma mark - revenue

- (void)chatRevenueStatisticsForChat:(int64_t)chatId
							  dark:(BOOL)dark
						  completion:(void (^)(NSDictionary *statistics,
											   NSString *error))completion;

- (void)chatRevenueTransactionsForChat:(int64_t)chatId
								offset:(NSString *)offset
								 limit:(int32_t)limit
							completion:(void (^)(NSDictionary *page,
												 NSString *error))completion;

- (void)starRevenueStatisticsForOwner:(NSString *)ownerKind
							  ownerId:(int64_t)ownerId
								 dark:(BOOL)dark
						   completion:(void (^)(NSDictionary *statistics,
												NSString *error))completion;

- (void)gramRevenueStatisticsWithDark:(BOOL)dark
						   completion:(void (^)(NSDictionary *statistics,
												NSString *error))completion;

- (void)paidMessageRevenueForUser:(int64_t)userId
					   completion:(void (^)(int64_t starCount,
											NSString *error))completion;

- (void)directMessagesChatTopicRevenueForChat:(int64_t)chatId
										topic:(int64_t)topicId
								   completion:(void (^)(int64_t starCount,
														NSString *error))completion;

#pragma mark - discovery

/// Lets a user send this account unpaid messages after they paid before.
- (void)allowUnpaidMessagesFromUser:(int64_t)userId
							 refund:(BOOL)refund
						 completion:(void (^)(BOOL ok, NSString *error))completion;

/// Redeems the token a t.me link carries so one unpaid message can be sent.
- (void)applyUnpaidMessagesToken:(NSString *)token
						  forUser:(int64_t)userId
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// The senders that may carry a paid reaction in a chat.
- (void)paidReactionSendersForChat:(int64_t)chatId
						completion:(void (^)(NSArray *senders,
											 NSString *error))completion;

/// The Star price a supergroup charges per message, and the same for a live
/// story's call messages.
- (void)setChatPaidMessageStarCount:(int64_t)chatId
							  count:(int32_t)starCount
						 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setGroupCallPaidMessageStarCount:(int32_t)groupCallId
								   count:(int32_t)starCount
							  completion:(void (^)(BOOL ok,
												   NSString *error))completion;

/// Whether one direct-messages topic accepts unpaid messages, with an option
/// to refund the messages already paid for.
- (void)setDirectMessagesTopicUnpaid:(int64_t)chatId
							   topic:(int64_t)topicId
							 allowed:(BOOL)allowed
							  refund:(BOOL)refund
						  completion:(void (^)(BOOL ok, NSString *error))completion;

/// A receipt for a successful payment message.
- (void)paymentReceiptForChat:(int64_t)chatId
					  message:(int64_t)messageId
				   completion:(void (^)(NSDictionary *receipt,
										NSString *error))completion;

/// The Telegram Ads account URL for a channel or bot this account owns.
- (void)starAdAccountURLForOwner:(NSString *)ownerKind
						 ownerId:(int64_t)ownerId
					  completion:(void (^)(NSString *link, NSString *error))completion;

/// The boost count a user needs before slow mode and restrictions stop
/// applying to them, for an owned supergroup.
- (void)setSupergroupUnrestrictBoostCount:(int32_t)count
							  supergroupId:(int64_t)supergroupId
							   completion:(void (^)(BOOL ok,
													NSString *error))completion;

- (void)giveawayInfoForChat:(int64_t)chatId
					message:(int64_t)messageId
				 completion:(void (^)(NSDictionary *info, NSString *error))completion;

- (void)collectibleItemInfoForKind:(NSString *)kind
							 value:(NSString *)value
						completion:(void (^)(NSDictionary *info,
											 NSString *error))completion;

/// The Star wallet: transactions and subscriptions. `ownerKind` is "user" or
/// "chat"; `direction` is "incoming", "outgoing" or empty for both.
- (void)starTransactionsForOwner:(NSString *)ownerKind
						 ownerId:(int64_t)ownerId
					 direction:(NSString *)direction
						offset:(NSString *)offset
						 limit:(int32_t)limit
					completion:(void (^)(NSDictionary *page,
										 NSString *error))completion;

- (void)starSubscriptionsOnlyExpiring:(BOOL)onlyExpiring
							   offset:(NSString *)offset
						   completion:(void (^)(NSDictionary *page,
												NSString *error))completion;

- (void)setStarSubscription:(NSString *)subscriptionId
				   canceled:(BOOL)canceled
				 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)reuseStarSubscription:(NSString *)subscriptionId
				   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Gifts that can be sent, the answer to "can this one be sent now", one
/// received gift, and the upgraded gift catalogue.
- (void)availableGiftsWithCompletion:(void (^)(NSArray *gifts,
											   NSString *error))completion;

- (void)canSendGift:(int64_t)giftId
		 completion:(void (^)(NSDictionary *result,
							  NSString *error))completion;

- (void)receivedGift:(NSString *)receivedGiftId
		  completion:(void (^)(NSDictionary *gift,
							   NSString *error))completion;

- (void)upgradedGiftNamed:(NSString *)name
			   completion:(void (^)(NSDictionary *gift,
									NSString *error))completion;

- (void)upgradedGiftValueInfoNamed:(NSString *)name
						completion:(void (^)(NSDictionary *info,
											 NSString *error))completion;

- (void)upgradedGiftVariantsForGift:(int64_t)regularGiftId
					   completion:(void (^)(NSDictionary *variants,
											NSString *error))completion;

- (void)giftUpgradePreviewForGift:(int64_t)regularGiftId
					   completion:(void (^)(NSDictionary *preview,
											NSString *error))completion;

- (void)giftCollectionsForOwner:(NSString *)ownerKind
						ownerId:(int64_t)ownerId
					 completion:(void (^)(NSArray *collections,
										  NSString *error))completion;

- (void)giftsForCraftingFromGift:(int64_t)regularGiftId
						  offset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *gifts,
										   NSString *error))completion;

- (void)searchGiftsForResaleFromGift:(int64_t)regularGiftId
							   order:(NSString *)order
						  offset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *gifts,
										   NSString *error))completion;

- (void)upgradedGiftEmojiStatusesWithCompletion:(void (^)(NSArray *statuses,
														 NSString *error))completion;

- (void)giftChatThemesWithOffset:(NSString *)offset
						   limit:(int32_t)limit
					  completion:(void (^)(NSArray *themes,
										   NSString *error))completion;

/// Auction reads and the two open/close signals. Bidding is the part that
/// spends Stars and is not here.
- (void)giftAuctionStateForAuction:(NSString *)auctionId
						completion:(void (^)(NSDictionary *state,
											 NSString *error))completion;

- (void)giftAuctionAcquiredGiftsForGift:(int64_t)giftId
							 completion:(void (^)(NSArray *gifts,
												  NSString *error))completion;

- (void)openGiftAuctionForGift:(int64_t)giftId
					completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)closeGiftAuctionForGift:(int64_t)giftId
					 completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)upgradedGiftsPromotionalAnimationWithCompletion:
		(void (^)(NSDictionary *animation, NSString *error))completion;

@end
