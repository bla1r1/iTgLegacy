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

/// Profile photo file id for a user, or nil if TDLib has not sent one.
- (NSNumber *)photoFileIdForUserId:(int64_t)userId;

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

/// A TDLib option by name, and the boolean setter for the handful of them the
/// settings screens expose ("disable_top_chats", "disable_animated_emoji", ...).
- (void)optionValue:(NSString *)name completion:(void (^)(id value))completion;

- (void)setOption:(NSString *)name boolValue:(BOOL)value;

/// Drop the phone contacts this account uploaded to Telegram.
- (void)clearImportedContacts;

/// Set the signed-in account's own picture from a local file.
- (void)setProfilePhotoAtPath:(NSString *)path completion:(void (^)(BOOL ok))completion;

/// Take one of this account's own profile photos off the account - the id a
/// chatPhoto carries, which the photo gallery is what reads back.
- (void)deleteProfilePhoto:(int64_t)photoId
				completion:(void (^)(BOOL ok))completion;

/// Every profile photo an account still has, oldest never first: each row
/// carries "photoId" (what deleteProfilePhoto answers to) and "fileId" (the
/// small file to download).
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

- (void)setBirthdayDay:(NSInteger)day month:(NSInteger)month year:(NSInteger)year;

/// Calls this account made or received, newest first: "name", "outgoing",
/// "missed", "date", "duration", "userId".
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
/// "isCurrent", "lastActive".
- (void)sessionsWithCompletion:(void (^)(NSArray *sessions))completion;

- (void)terminateSession:(long long)sessionId;

/// Change the signed-in user's own name and bio.
- (void)setName:(NSString *)firstName last:(NSString *)lastName;

- (void)setBio:(NSString *)bio;

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

@end
