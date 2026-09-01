//
// TGClient - TDLib client for iOS 7.1.2 / armv7.
//
// TDLib is loaded with dlopen rather than linked: statically linked it pushes
// the app's __TEXT past the 16MB armv7 thumb branch limit, which this linker
// cannot bridge. See scripts/build_tdlib_dylib.sh.
//
// Everything is JSON over td_json_client_*. One background thread owns the
// receive loop; handlers are always delivered on the main queue.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGAuthState) {
    TGAuthStateUnknown = 0,
    TGAuthStateWaitPhoneNumber,
    TGAuthStateWaitCode,
    TGAuthStateWaitPassword,
    TGAuthStateWaitRegistration,
    TGAuthStateReady,
    TGAuthStateLoggingOut,
    TGAuthStateClosed
};

@interface TGClient : NSObject

+ (instancetype)shared;

/// YES once libtdjson.dylib is loaded and a client exists.
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) TGAuthState authState;

/// Called on the main queue whenever the authorization state changes.
@property (nonatomic, copy) void (^onAuthState)(TGAuthState state);
/// Called on the main queue for TDLib errors that concern the user.
@property (nonatomic, copy) void (^onError)(NSString *message);
/// Connection to Telegram, as TDLib reports it. Replaces the old
/// SCNetworkReachability check: what matters is whether the client is talking
/// to Telegram, not whether the device has a route somewhere.
typedef NS_ENUM(NSInteger, TGConnectionState) {
    TGConnectionStateUnknown = 0,
    TGConnectionStateWaitingForNetwork,
    TGConnectionStateConnecting,
    TGConnectionStateUpdating,
    TGConnectionStateReady
};

@property (nonatomic, readonly) TGConnectionState connectionState;
/// Main queue. `text` is nil when connected, a short status otherwise.
@property (nonatomic, copy) void (^onConnectionState)(TGConnectionState state, NSString *text);

/// Called on the main queue whenever the chat list changed. Read `chats`.
@property (nonatomic, copy) void (^onChatsChanged)(void);

/// Display name for a user TDLib has told us about, or nil.
- (NSString *)nameForUserId:(int64_t)userId;

/// "online", "last seen recently", "last seen at 12:30" - what a private chat
/// shows under the name. Nil for anything that is not a user.
- (void)statusForUser:(int64_t)userId completion:(void (^)(NSString *status))completion;

/// Chat id of Saved Messages, which is the signed-in user's own chat.
- (int64_t)savedMessagesChatId;

/// Profile photo file id for a user, or nil if TDLib has not sent one.
- (NSNumber *)photoFileIdForUserId:(int64_t)userId;

/// Profile photo file id of a chat we already know about, or nil. Groups and
/// channels have no user record, so this is where their picture comes from.
- (NSNumber *)photoFileIdForChat:(int64_t)chatId;

/// Full user record: "first_name", "last_name", "usernames", "phone_number".
- (void)userInfo:(int64_t)userId completion:(void (^)(NSDictionary *user))completion;

/// Shared media of a chat. `filter` is a TDLib SearchMessagesFilter type name,
/// e.g. "searchMessagesFilterPhotoAndVideo" or "searchMessagesFilterDocument".
- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
         completion:(void (^)(NSArray *messages))completion;

/// Fetch a user TDLib has not volunteered yet, so a group message can be
/// attributed. `completion` runs once the name is cached.
- (void)ensureUserName:(int64_t)userId completion:(void (^)(void))completion;

/// Chats in the archive, same shape as `chats`.
@property (nonatomic, readonly) NSArray *archivedChats;
/// Called on the main queue when the archive changes.
@property (nonatomic, copy) void (^onArchiveChanged)(void);

/// Chat folders the user has configured: "id" and "title".
@property (nonatomic, readonly) NSArray *folders;

/// Chats of one folder.
- (void)chatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *chats))completion;

/// Topics of a forum supergroup - a forum holds several independent threads
/// in one chat. Each entry: "threadId", "name", "text", "unread", "date".
/// Empty for a chat that is not a forum.
- (void)forumTopicsForChat:(int64_t)chatId completion:(void (^)(NSArray *topics))completion;

/// Whether the signed-in user may post in a chat. A channel you only follow
/// says NO, and the composer has to go away rather than fail on send.
- (void)canSendInChat:(int64_t)chatId completion:(void (^)(BOOL canSend, BOOL isChannel))completion;

/// Delete a chat's history for the current user, and leave it if it is a group.
- (void)deleteChat:(int64_t)chatId;

/// Join or leave a channel or supergroup.
- (void)setChat:(int64_t)chatId joined:(BOOL)joined;

/// Members of a group or supergroup: "id" and "name". Empty for anything else.
- (void)membersOfChat:(int64_t)chatId completion:(void (^)(NSArray *members))completion;

/// Members in a group or supergroup; 0 for anything else.
- (void)memberCountForChat:(int64_t)chatId completion:(void (^)(NSInteger count))completion;

/// Chat list, most recent first. Each entry is a dictionary with keys
/// "id" (NSNumber), "title", "text" (last message preview), "unread"
/// (NSNumber), "date" (NSNumber, unix time), "isGroup" (NSNumber BOOL - a
/// basic group, supergroup or channel, where messages need a sender name),
/// "action" (NSString - "typing..." and the like, empty when nobody is), and
/// "isOnline" (NSNumber BOOL, private chats only).
/// Main queue only.
@property (nonatomic, readonly) NSArray *chats;

/// Ask TDLib to populate the main chat list. Only meaningful once authorized.
- (void)loadChats;

/// The signed-in user: "id", "first_name", "username", "phone". Nil until the
/// session is ready. Main queue only.
@property (nonatomic, readonly) NSDictionary *me;

/// Loads the dylib, creates the client and starts the receive loop.
/// Safe to call more than once. Returns NO if TDLib is unavailable.
- (BOOL)start;

/// Request with a reply. `completion` runs on the main queue with the raw
/// TDLib object, or an object of @type "error".
- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *result))completion;

#pragma mark - files

/// Progress of a running download, 0..1, on the main queue. Fires for every
/// file TDLib is fetching, so listeners must check the id they care about.
@property (nonatomic, copy) void (^onFileProgress)(NSInteger fileId, float progress);

/// Download a file by TDLib id. `completion` gets the local path, or nil.
/// Already-downloaded files complete immediately.
- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion;

#pragma mark - messages

/// Newest `limit` messages of a chat, oldest first. Each entry has "id",
/// "text", "date", "outgoing" (NSNumber BOOL), "senderId", "photoId"
/// (NSNumber file id or nil).
- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

- (void)historyForChat:(int64_t)chatId
         fromMessageId:(int64_t)fromMessageId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

/// History of one forum topic. `threadId` is the topic's message_thread_id.
- (void)historyForChat:(int64_t)chatId
                thread:(int64_t)threadId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

/// Someone is typing (or recording, or uploading) in a chat. `action` is a
/// short phrase to show, or nil when they stopped.
@property (nonatomic, copy) void (^onChatAction)(int64_t chatId, NSString *action);

/// The pinned message of a chat, flattened, or nil if there is none.
- (void)pinnedMessageForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *message))completion;

/// Pin or unpin a chat in the main list.
- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned;
/// Mute forever, or unmute.
- (void)setChat:(int64_t)chatId muted:(BOOL)muted;

/// Everything a profile shows that the plain user record does not carry:
/// "bio", "commonGroups" (NSNumber), "birthday" (NSString, empty when unset),
/// "canCall" and "canVideoCall" (NSNumber BOOL).
- (void)userProfile:(int64_t)userId completion:(void (^)(NSDictionary *info))completion;

/// The same for a group or channel: "description", "members" (NSNumber),
/// "admins" (NSNumber), "inviteLink".
- (void)chatProfile:(int64_t)chatId completion:(void (^)(NSDictionary *info))completion;

/// Muted state of one chat, as the list already knows it.
- (BOOL)isChatMuted:(int64_t)chatId;

/// Erase the messages of a chat without leaving it.
- (void)clearHistoryInChat:(int64_t)chatId;

/// Messages in this chat delete themselves after `seconds`; 0 turns it off.
- (void)setChat:(int64_t)chatId autoDeleteSeconds:(NSInteger)seconds;

#pragma mark - account settings

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

/// Bytes over the wire since TDLib last reset its counters.
- (void)networkStatsWithCompletion:(void (^)(long long sent, long long received))completion;
- (void)resetNetworkStats;

/// Whether media downloads itself, per network. TDLib cannot read the setting
/// back, so these answer with what the app last wrote.
- (BOOL)autoDownloadOverMobile;
- (BOOL)autoDownloadOverWifi;
- (void)setAutoDownloadOverMobile:(BOOL)mobile wifi:(BOOL)wifi;

/// Whether two-step verification is on, and the recovery address if it is.
- (void)hasPasswordWithCompletion:(void (^)(BOOL hasPassword,
                                            NSString *recoveryEmail))completion;

/// Drop the phone contacts this account uploaded to Telegram.
- (void)clearImportedContacts;

/// Set the signed-in account's own picture from a local file.
- (void)setProfilePhotoAtPath:(NSString *)path completion:(void (^)(BOOL ok))completion;

/// The account's own birthday. Day 0 means it is not set; year 0 means it is
/// set but the year was left out, which Telegram allows.
- (void)myBirthdayWithCompletion:(void (^)(NSInteger day, NSInteger month,
                                           NSInteger year))completion;
- (void)setBirthdayDay:(NSInteger)day month:(NSInteger)month year:(NSInteger)year;

/// Calls this account made or received, newest first: "name", "outgoing",
/// "missed", "date", "duration", "userId".
- (void)recentCallsWithCompletion:(void (^)(NSArray *calls))completion;

/// The privacy rules, by the name TDLib gives them without the prefix:
/// "ShowStatus", "ShowProfilePhoto", "AllowCalls", "AllowChatInvites",
/// "ShowLinkInForwardedMessages", "ShowPhoneNumber". The answer and the new
/// value are one of "everybody", "contacts" or "nobody" - the three choices
/// every client offers, which is all the rule list can say without a screen
/// for picking individual people.
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

/// Look up a public chat by its @username, creating it locally if needed.
/// Answers 0 when there is no such account.
- (void)chatWithUsername:(NSString *)username
              completion:(void (^)(int64_t chatId, NSString *title))completion;

/// Move a chat into the archive, or back out of it.
- (void)setChat:(int64_t)chatId archived:(BOOL)archived;

/// Fired on the main queue when a message arrives, is edited or deleted in
/// any chat. `message` is the flattened form; nil means it was deleted.
@property (nonatomic, copy) void (^onMessage)(int64_t chatId, NSDictionary *message, int64_t deletedId);

- (void)sendText:(NSString *)text toChat:(int64_t)chatId;
/// Send into a forum topic.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId thread:(int64_t)threadId;
/// Send as a reply to a message.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId;

/// Forward messages into another chat.
- (void)forwardMessages:(NSArray *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId;

/// Replace the text of a message already sent.
- (void)editMessage:(int64_t)messageId inChat:(int64_t)chatId text:(NSString *)text;

/// One message by id, flattened. Used to show what a reply is answering.
- (void)messageWithId:(int64_t)messageId
               inChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *message))completion;
/// Stickers the user reached for lately: "fileId", "emoji", "isAnimated".
- (void)recentStickersWithCompletion:(void (^)(NSArray *stickers))completion;

/// Send a sticker TDLib already knows, by file id.
- (void)sendStickerWithFileId:(NSInteger)fileId toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send a recorded voice note (.oga), with its duration in seconds.
- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
                 toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send a video file from the library.
- (void)sendVideoAtPath:(NSString *)path toChat:(int64_t)chatId;

/// Share a point on the map.
- (void)sendLocation:(double)latitude longitude:(double)longitude toChat:(int64_t)chatId;

/// Share someone from the address book.
- (void)sendContactNamed:(NSString *)name phone:(NSString *)phone toChat:(int64_t)chatId;

/// Send a local image file. TDLib uploads it and echoes the message back.
- (void)sendPhotoAtPath:(NSString *)path toChat:(int64_t)chatId;
/// Vote in a poll. `optionIds` are indexes into the poll's options.
- (void)votePoll:(int64_t)messageId inChat:(int64_t)chatId options:(NSArray *)optionIds;

/// React to a message with an emoji, as the current user.
- (void)reactTo:(int64_t)messageId inChat:(int64_t)chatId emoji:(NSString *)emoji;

- (void)deleteMessage:(int64_t)messageId inChat:(int64_t)chatId;
- (void)markRead:(NSArray *)messageIds inChat:(int64_t)chatId;

/// Search messages across every chat. Each result is a flattened message with
/// an extra "chatId" and "chatTitle" so it can be shown out of context.
- (void)searchMessages:(NSString *)query completion:(void (^)(NSArray *messages))completion;

/// Search inside one chat, newest first. Flattened messages.
- (void)searchInChat:(int64_t)chatId query:(NSString *)query
          completion:(void (^)(NSArray *messages))completion;

#pragma mark - contacts

/// Telegram contacts as dictionaries with "id", "first_name", "last_name",
/// "phone", "username".
- (void)contactsWithCompletion:(void (^)(NSArray *users))completion;

/// Chat id for a private conversation with a user, creating it if needed.
- (void)privateChatWithUser:(int64_t)userId completion:(void (^)(int64_t chatId))completion;

/// Resolve an address-book phone number to a Telegram user, or nil.
/// Same dictionary shape as -contactsWithCompletion:.
- (void)userForPhone:(NSString *)phone completion:(void (^)(NSDictionary *user))completion;

#pragma mark - storage

/// Cache size on disk, in bytes, and the file count. TDLib's fast variant:
/// the full one walks every file and takes seconds on this hardware.
- (void)storageStatsWithCompletion:(void (^)(long long bytes, NSInteger files))completion;

/// Delete cached media. `kinds` are TDLib FileType names, or nil for all of
/// them; `completion` gets the number of bytes freed.
- (void)clearCacheOfTypes:(NSArray *)kinds completion:(void (^)(long long freed))completion;

/// What the cache is made of, largest first: "name", "bytes", "kinds". Walks
/// the database, so it takes a moment on this hardware - ask once per screen.
- (void)storageBreakdownWithCompletion:(void (^)(NSArray *categories,
                                                 long long total))completion;

#pragma mark - account

/// Other devices signed into this account: "id", "name", "platform", "ip",
/// "isCurrent", "lastActive".
- (void)sessionsWithCompletion:(void (^)(NSArray *sessions))completion;
- (void)terminateSession:(long long)sessionId;

/// Change the signed-in user's own name and bio.
- (void)setName:(NSString *)firstName last:(NSString *)lastName;
- (void)setBio:(NSString *)bio;
- (void)setUsername:(NSString *)username completion:(void (^)(BOOL ok))completion;

#pragma mark - people

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

#pragma mark - maintenance

/// Drop TDLib's local database. The session stays.
- (void)clearLocalDatabase;

- (void)sendPhoneNumber:(NSString *)phoneNumber;
- (void)sendCode:(NSString *)code;
- (void)sendPassword:(NSString *)password;
- (void)logOut;

/// Fire-and-forget request. `request` is a JSON object; @extra is not tracked.
- (void)send:(NSDictionary *)request;

@end
