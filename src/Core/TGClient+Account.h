//
// TGClient+Account.h - the client surface for the account and its people: sessions, contacts, blocked users, storage stats.
//
#import "TGClient+Base.h"

@interface TGClient (Account)

/// Display name for a user TDLib has told us about, or nil.
- (NSString *)nameForUserId:(int64_t)userId;

/// "online", "last seen recently", "last seen at 12:30" - what a private chat
/// shows under the name. Nil for anything that is not a user.
- (void)statusForUser:(int64_t)userId completion:(void (^)(NSString *status))completion;

/// Chat id of Saved Messages, which is the signed-in user's own chat.
- (int64_t)savedMessagesChatId;

/// YES once getMe has named the active account. The dev contacts are a
/// signed-out fixture; a real account with no contacts must see its empty state.
- (BOOL)hasSignedInAccount;

/// Profile photo file id for a user, or nil if TDLib has not sent one.
- (NSNumber *)photoFileIdForUserId:(int64_t)userId;

/// The same id, asking Telegram when the user record is not cached yet. A
/// member list only carries ids and names, so every face there starts here;
/// the answer is kept in the same map photoFileIdForUserId reads.
- (void)profilePhotoFileIdForUser:(int64_t)userId
                       completion:(void (^)(NSNumber *fileId))completion;

/// Full user record: "first_name", "last_name", "usernames", "phone_number".
- (void)userInfo:(int64_t)userId completion:(void (^)(NSDictionary *user))completion;

/// Shared media of a chat. `filter` is a TDLib SearchMessagesFilter type name,
/// e.g. "searchMessagesFilterPhotoAndVideo" or "searchMessagesFilterDocument".
- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
         completion:(void (^)(NSArray *messages))completion;

- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
      fromMessageId:(int64_t)fromMessageId limit:(NSInteger)limit
         completion:(void (^)(NSArray *messages))completion;

/// Fetch a user TDLib has not volunteered yet, so a group message can be
/// attributed. `completion` runs once the name is cached.
- (void)ensureUserName:(int64_t)userId completion:(void (^)(void))completion;

/// Everything a profile shows that the plain user record does not carry:
/// "bio", "commonGroups" (NSNumber), "birthday" (NSString, empty when unset),
/// "canCall" and "canVideoCall" (NSNumber BOOL).
- (void)userProfile:(int64_t)userId completion:(void (^)(NSDictionary *info))completion;

#pragma mark - local notifications

/// TDLib's active notification groups, the ones it would have shown while the
/// app was closed. Each group: "id", "type" (a label), "typeName", "chatId",
/// "totalCount" and "notifications" - rows with "id", "date", "silent", "kind"
/// and the text to draw. Kept by the four updateNotification* branches, so the
/// screen never has to rebuild the list from raw TDLib records.
@property (nonatomic, readonly) NSArray *activeNotificationGroups;
@property (nonatomic, readonly) BOOL haveDelayedNotifications;
@property (nonatomic, readonly) BOOL haveUnreceivedNotifications;
/// Delayed or unreceived notifications are outstanding; the screen shows a
/// refresh indicator until both flags are off.
@property (nonatomic, readonly) BOOL havePendingNotifications;

/// Remove one row. TDLib also sends updateNotificationGroup, but applying it
/// here too keeps a screen that asked for the removal from blinking back.
- (void)removeNotification:(int32_t)notificationId
				   inGroup:(int32_t)groupId
				completion:(void (^)(BOOL ok))completion;

/// Remove a whole group. `maxNotificationId` is the highest id in it; TDLib
/// needs it to close the group rather than only the rows the client knows.
- (void)removeNotificationGroup:(int32_t)groupId
			  maxNotificationId:(int32_t)maxNotificationId
					 completion:(void (^)(BOOL ok))completion;

/// Notification settings are kept per scope rather than per chat: private
/// chats, groups and channels each have their own. `scope` is "private",
/// "groups" or "channels"; `muted` is what the switch shows.
- (void)notificationsMutedForScope:(NSString *)scope
                        completion:(void (^)(BOOL muted))completion;

- (void)setScope:(NSString *)scope muted:(BOOL)muted;

/// Whether a scope's notifications carry the message text.
- (void)notificationPreviewForScope:(NSString *)scope
                         completion:(void (^)(BOOL show))completion;

- (void)setScope:(NSString *)scope showPreview:(BOOL)show;

/// Forget every per-chat notification exception, as their reset row does.
- (void)resetAllNotificationSettings;

/// The last reaction notification record Telegram sent. nil until
/// updateReactionNotificationSettings arrives.
@property (nonatomic, readonly) NSDictionary *reactionNotificationSettings;

/// Whether a message reaction may raise a notification. Telegram's default
/// is on; the stored record only turns it off by naming the "none" source.
@property (nonatomic, readonly) BOOL reactionNotificationsEnabled;

/// Turn message-reaction notifications on or off without disturbing the
/// story and poll sources or the chosen sound. Answered so the switch can
/// put itself back if Telegram refuses.
- (void)setReactionNotificationsEnabled:(BOOL)enabled
                             completion:(void (^)(BOOL ok))completion;

/// A TDLib option by name, and the boolean setter for the handful of them the
/// settings screens expose ("disable_top_chats", "disable_animated_emoji", ...).
- (void)optionValue:(NSString *)name completion:(void (^)(id value))completion;

- (void)setOption:(NSString *)name boolValue:(BOOL)value;

/// Drop the phone contacts this account uploaded to Telegram.
- (void)clearImportedContacts;

#pragma mark - imported contacts and the application link

/// How many contacts this account has uploaded from a device's address book.
- (void)importedContactCountWithCompletion:(void (^)(NSInteger count))completion;

/// Replaces the uploaded contact list with `contacts` (each "phone_number",
/// "first_name", "last_name"). `importerCount` is how many of the supplied
/// rows Telegram accepted; `userIds` is its answer, one id per row.
- (void)changeImportedContacts:(NSArray *)contacts
					completion:(void (^)(NSInteger importerCount,
										NSArray *userIds))completion;

/// The official client download page for this platform.
- (void)applicationDownloadLinkWithCompletion:(void (^)(NSString *url))completion;

#pragma mark - autosave

/// Telegram's gallery autosave settings. "private", "groups" and "channels"
/// each carry "photos", "videos" and "maxVideoSize"; "exceptions" is an array
/// of per-chat overrides with "chatId" and the same three fields.
- (void)autosaveSettingsWithCompletion:(void (^)(NSDictionary *settings))completion;

/// Writes one scope's settings. `scope` is "private", "groups" or "channels".
- (void)setAutosaveSettingsForScope:(NSString *)scope
							 photos:(BOOL)photos
							 videos:(BOOL)videos
					   maxVideoSize:(long long)maxVideoSize
						 completion:(void (^)(BOOL ok))completion;

/// Drops every per-chat exception; the three scope defaults stay.
- (void)clearAutosaveSettingsExceptionsWithCompletion:(void (^)(BOOL ok))completion;

/// Set the signed-in account's own picture from a local file.
- (void)setProfilePhotoAtPath:(NSString *)path completion:(void (^)(BOOL ok))completion;

/// Take one of this account's own profile photos off the account - the id a
/// chatPhoto carries, which the photo gallery is what reads back.
- (void)deleteProfilePhoto:(int64_t)photoId
				completion:(void (^)(BOOL ok))completion;

/// Every profile photo an account still has, oldest never first: each row
/// carries "photoId" (what deleteProfilePhoto answers to), "fileId" (the
/// small file to download) and "date" (when the photo was added).
- (void)userProfilePhotos:(int64_t)userId
			   completion:(void (^)(NSArray *photos))completion;

/// The t.me link of the signed-in account - Telegram answers for only the
/// current user, so there is no asking for someone else's.
- (void)myUserLink:(void (^)(NSString *link))completion;

/// The chats this account shares with another user, each as an ordinary chat
/// row ("id", "title"), so a tap opens it like any chat the list holds.
- (void)groupsInCommonWithUser:(int64_t)userId
					completion:(void (^)(NSArray *chats))completion;

/// Two-step verification, written whole: the old password opens the gate, an
/// empty new one removes the password, and the recovery email rides along
/// only when `setEmailAddress` says so.
- (void)setPassword:(NSString *)oldPassword
								 new:(NSString *)newPassword
							   hint:(NSString *)hint
					setEmailAddress:(BOOL)setEmailAddress
							 email:(NSString *)recoveryEmail
						 completion:(void (^)(BOOL ok))completion;

/// The recovery address a two-step password still points at - which is also
/// TDLib's way of checking a password the user typed.
- (void)recoveryEmailAddress:(NSString *)password
				  completion:(void (^)(NSString *email))completion;

/// Point the recovery address somewhere else; TDLib confirms the new one by
/// letter, so the answer says the request landed, not that it is live.
- (void)setRecoveryEmailAddress:(NSString *)password
							 to:(NSString *)email
					 completion:(void (^)(BOOL ok))completion;

/// Sign every other device out in one stroke - the sessions screen keeps the
/// per-device version.
- (void)terminateAllOtherSessions:(void (^)(BOOL ok))completion;

/// The code Telegram emails when a recovery address is given. Until it goes
/// through, the old address - or none - is still the one in force.
- (void)checkRecoveryEmailCode:(NSString *)code
					completion:(void (^)(BOOL ok))completion;

- (void)resendRecoveryEmailCode;

/// The end of the road: reason is what Telegram's form asks about, the
/// password only when two-step verification is on.
- (void)deleteAccountWithReason:(NSString *)reason
					   password:(NSString *)password
					 completion:(void (^)(BOOL ok))completion;

/// The account's own birthday. Day 0 means it is not set; year 0 means it is
/// set but the year was left out, which Telegram allows.
- (void)myBirthdayWithCompletion:(void (^)(NSInteger day, NSInteger month,
                                           NSInteger year))completion;

- (void)setBirthdayDay:(NSInteger)day month:(NSInteger)month year:(NSInteger)year
			completion:(void (^)(BOOL ok, NSString *error))completion;

/// Calls this account made or received, newest first: "userId", "chatId",
/// "messageId" (the call record in the history), "name", "outgoing",
/// "missed", "date", "duration".
- (void)recentCallsWithCompletion:(void (^)(NSArray *calls))completion;

/// Queries privacy rule value ("everybody", "contacts", "nobody") for setting:
/// "ShowStatus", "ShowProfilePhoto", "AllowCalls", "AllowChatInvites",
/// "ShowLinkInForwardedMessages", "ShowPhoneNumber".
- (void)privacyRule:(NSString *)setting
         completion:(void (^)(NSString *value))completion;

- (void)setPrivacyRule:(NSString *)setting to:(NSString *)value;

/// Everyone you have blocked: "id" and "name".
- (void)blockedUsersWithCompletion:(void (^)(NSArray *users))completion;

/// Days of inactivity before the account deletes itself.
- (void)accountTtlWithCompletion:(void (^)(NSInteger days))completion;

- (void)setAccountTtlDays:(NSInteger)days;

/// Language packs this account can use: "id" and "name". `current` is the one
/// in use.
- (void)languagesWithCompletion:(void (^)(NSArray *languages, NSString *current))completion;

- (void)setLanguage:(NSString *)packId;

/// Telegram contacts as dictionaries with "id", "first_name", "last_name",
/// "phone", "username".
- (void)contactsWithCompletion:(void (^)(NSArray *users))completion;

/// Chat id for a private conversation with a user, creating it if needed.
- (void)privateChatWithUser:(int64_t)userId completion:(void (^)(int64_t chatId))completion;

/// Resolve an address-book phone number to a Telegram user, or nil.
/// Same dictionary shape as -contactsWithCompletion:.
- (void)userForPhone:(NSString *)phone completion:(void (^)(NSDictionary *user))completion;

/// Other devices signed into this account: "id", "name", "platform", "ip",
/// "isCurrent", "isUnconfirmed", "acceptSecretChats", "canAcceptCalls",
/// "lastActive".
- (void)sessionsWithCompletion:(void (^)(NSArray *sessions))completion;

/// The same list plus the idle timeout Telegram stores for the account.
- (void)sessionsWithInactiveTtlCompletion:(void (^)(NSArray *sessions,
												  NSInteger ttlDays))completion;

- (void)terminateSession:(long long)sessionId;

/// Confirms a login Telegram flagged as unconfirmed, which is what the
/// updateUnconfirmedSession row in Devices is for.
- (void)confirmSession:(long long)sessionId;

/// A device that should not ring can be told so without signing it out.
- (void)toggleSession:(long long)sessionId
	   canAcceptCalls:(BOOL)canAccept
		   completion:(void (^)(BOOL ok, NSString *error))completion;

/// How many idle days a session gets before it is signed out, 1-366. The
/// screen re-reads the list because the server owns the stored value.
- (void)setInactiveSessionTtlDays:(NSInteger)days
					   completion:(void (^)(BOOL ok, NSString *error))completion;

/// Change the signed-in user's own name and bio. The completion answers so the
/// edit form can stay put and report a refusal instead of popping optimistically.
- (void)setName:(NSString *)firstName
			last:(NSString *)lastName
	  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setBio:(NSString *)bio
	completion:(void (^)(BOOL ok, NSString *error))completion;

/// The server's limit for a bio, in characters, read with getOption. 0 means
/// the answer has not arrived; the form hides the count then.
- (void)bioLengthMaxWithCompletion:(void (^)(NSInteger maxLength))completion;

- (void)setUsername:(NSString *)username completion:(void (^)(BOOL ok))completion;

/// Block or unblock a user.
- (void)setUser:(int64_t)userId blocked:(BOOL)blocked;

/// Whether a user is blocked right now.
- (void)isUserBlocked:(int64_t)userId completion:(void (^)(BOOL blocked))completion;

/// Gifts a user has received and kept on their profile: "title", "starCount".
- (void)giftsForUser:(int64_t)userId completion:(void (^)(NSArray *gifts))completion;

/// Stories on a profile: the ones kept on the page, or the ones still live if
/// none are kept. Each: "storyId", "date", "caption", "photoId" (a file id for
/// the picture or a video's poster frame), "isVideo", "viewers".
- (void)storiesForChat:(int64_t)chatId completion:(void (^)(NSArray *stories))completion;

/// Premium state of the signed-in account: nil when it is not active.
- (void)premiumStateWithCompletion:(void (^)(NSString *summary))completion;

#pragma mark - account status the server pushes

/// From updateFreezeState: "is_frozen", "freezing_date", "deletion_date" and
/// "appeal_link". Nil until Telegram has said anything about this account.
@property (nonatomic, readonly, copy) NSDictionary *freezeState;

/// From updateAgeVerificationParameters: "min_age", "verification_bot_username"
/// and "country". Nil until Telegram sends the parameters.
@property (nonatomic, readonly, copy) NSDictionary *ageVerificationParameters;

/// From updateApplicationRecaptchaVerificationRequired: "verification_id",
/// "action" and "recaptcha_key_id". Nil when no reCAPTCHA is being asked for.
@property (nonatomic, readonly, copy) NSDictionary *recaptchaVerificationRequest;

/// The subscription record updateUserSubscription last sent for `userId`:
/// "payload", "is_canceled", "is_restored" and "is_payment_failed". Nil when
/// Telegram has said nothing about that user.
- (NSDictionary *)subscriptionForUserId:(int64_t)userId;

#pragma mark - server defaults

/// From updateAvailableMessageEffects: the reaction-effect ids and the
/// sticker-effect ids Telegram offers. Empty arrays before the update arrives.
@property (nonatomic, readonly, copy) NSArray *availableMessageEffectIds;
@property (nonatomic, readonly, copy) NSArray *availableStickerEffectIds;

/// From updateDefaultBackground: a dictionary with "for_dark_theme" and the
/// whole "background" object. Nil before the update arrives.
@property (nonatomic, readonly, copy) NSDictionary *defaultBackground;

/// From updateEmojiChatThemes: emojiChatTheme records, each with a "name" and
/// its light and dark themeSettings. Empty before the update arrives.
@property (nonatomic, readonly, copy) NSArray *emojiChatThemes;

/// The last updateStopMessageDraft: "chat_id", "forum_topic_id", "draft_id"
/// and "draft_text" (the cache the stop cleared). Nil before the first stop.
@property (nonatomic, readonly, copy) NSDictionary *stoppedMessageDraft;

/// The last updateVideoPublished: "chat_id" and "message_id". Nil before the
/// first auto-published video.
@property (nonatomic, readonly, copy) NSDictionary *publishedVideo;

@end
