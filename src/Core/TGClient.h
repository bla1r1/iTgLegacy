//
// TGClient - TDLib client wrapper.
// Dynamically loads libtdjson.dylib; background receive loop dispatches to main queue.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGAuthState) {
    TGAuthStateUnknown = 0,
    TGAuthStateWaitPhoneNumber,
    TGAuthStateWaitCode,
    TGAuthStateWaitPassword,
    TGAuthStateWaitRegistration,
    TGAuthStateWaitOtherDeviceConfirmation,
    TGAuthStateReady,
    TGAuthStateLoggingOut,
    TGAuthStateClosed
};

/// Posted on the main queue when the other side reads your messages in a
/// chat; userInfo carries "chatId".
extern NSString *const TGChatReadOutboxChangedNotification;
// Fired when updateConnectionState arrives, so screens that need not own the
// single onConnectionState slot can still see the network change (B4).
extern NSString *const TGConnectionStateChangedNotification;
// Fired when updateUserStatus arrives: chat headers and profile status
// labels re-render their line instead of freezing at the fetched one.
extern NSString *const TGUserStatusChangedNotification;

@interface TGClient : NSObject

+ (instancetype)shared;

/// YES once libtdjson.dylib is loaded and a client exists.
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) TGAuthState authState;

/// Called on the main queue whenever the authorization state changes.
@property (nonatomic, copy) void (^onAuthState)(TGAuthState state);
/// Called on the main queue for TDLib errors that concern the user.
@property (nonatomic, copy) void (^onError)(NSString *message);
/// Connection state to Telegram as reported by TDLib.
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

/// The newest of your own messages in a chat the other side has read; 0 when
/// nothing is known. Anything at or below it carries two ticks.
- (int64_t)lastReadOutboxForChat:(int64_t)chatId;
/// The newest incoming message you have read in a chat; 0 when unknown.
- (int64_t)lastReadInboxForChat:(int64_t)chatId;

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

/// How many chat records the client has actually cached - the merge uses it
/// to notice when the cache grew enough to be worth re-reading the folders.
@property (nonatomic, readonly) NSUInteger chatsCached;
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

/// Making and minding a forum's topics. `colour` is one of TDLib's forum
/// hues, 0-6.
- (void)createForumTopicInChat:(int64_t)chatId
						  name:(NSString *)name
				   iconColour:(NSInteger)colour
				   completion:(void (^)(int64_t threadId, NSString *name))completion;
/// Renaming only, unless `iconEmojiId` says the icon changes with it.
- (void)renameForumTopic:(int64_t)threadId
				  inChat:(int64_t)chatId
					name:(NSString *)name
			iconEmojiId:(int64_t)iconEmojiId
			 completion:(void (^)(BOOL ok))completion;
- (void)toggleForumTopic:(int64_t)threadId inChat:(int64_t)chatId closed:(BOOL)closed;
- (void)toggleForumTopic:(int64_t)threadId inChat:(int64_t)chatId pinned:(BOOL)pinned;
- (void)deleteForumTopic:(int64_t)threadId inChat:(int64_t)chatId;
/// A forum shown as one flow of messages instead of a list of topics.
- (void)chatWithViewAsTopics:(int64_t)chatId
				  completion:(void (^)(BOOL viewAsTopics))completion;
- (void)setChatViewAsTopics:(int64_t)chatId
			   viewAsTopics:(BOOL)viewAsTopics
				 completion:(void (^)(BOOL ok))completion;

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
/// How eagerly TDLib downloads; 1 is lowest, 32 highest. A file asked again
/// at a higher rank than its standing request re-raises it on the wire, so an
/// avatar can overtake a photo grid that started earlier.
typedef NS_ENUM(NSInteger, TGDownloadPriority) {
	TGDownloadPriorityBackground = 1,   // media a scroll may never reach
	TGDownloadPriorityOnScreen   = 16,  // tiles the user is looking at right now
	TGDownloadPriorityAvatar     = 32,  // avatars: small files, always wanted
};

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *path))completion;
- (void)downloadFile:(NSInteger)fileId priority:(NSInteger)priority completion:(void (^)(NSString *path))completion;

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

/// A secret chat changed state - the answer to a key exchange, or the
/// moment one is closed. `secretChatId` is the secretchat's own id, and
/// `state` is "pending", "ready" or "closed".
@property (nonatomic, copy) void (^onSecretChat)(NSInteger secretChatId, NSString *state);

/// The pinned message of a chat, flattened, or nil if there is none.
- (void)pinnedMessageForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *message))completion;

/// Pin or unpin a chat in the main list.
- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned;
/// Mute forever, or unmute.
- (void)setChat:(int64_t)chatId muted:(BOOL)muted;

/// Pin a message to the top of the chat, or take it down again. `notify`
/// posts the "pinned a message" service message the way their clients do.
- (void)pinMessage:(int64_t)messageId inChat:(int64_t)chatId notify:(BOOL)notify;
- (void)unpinMessage:(int64_t)messageId inChat:(int64_t)chatId;

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

/// Reporting is a conversation: the first call answers with the reasons to
/// choose from, and the chosen option id goes in the second. The completion
/// gets either a title and a list of options - each with "id" and "text" -
/// to put to the user, or an empty list and `done` once it is accepted.
- (void)reportChat:(int64_t)chatId
		  optionId:(NSString *)optionId
			  text:(NSString *)text
		completion:(void (^)(NSString *title, NSArray *options, BOOL done))completion;

/// Dismisses the "Report spam / Add to contacts" bar above a chat from
/// someone this account does not know.
- (void)removeActionBarInChat:(int64_t)chatId;

/// Who this account talks to most, as Telegram ranks it - the people row in
/// search. Entries are the same chat dictionaries the chat list holds.
- (void)topChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// Opening a chat from search puts it in the recently-found list.
- (void)rememberFoundChat:(int64_t)chatId;
/// Takes someone out of the frequent-contacts ranking.
- (void)forgetTopChat:(int64_t)chatId;

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

/// Look up a public chat by its @username, creating it locally if needed.
/// Answers 0 when there is no such account.
- (void)chatWithUsername:(NSString *)username
              completion:(void (^)(int64_t chatId, NSString *title))completion;

- (void)joinChatByInviteLink:(NSString *)inviteLink
                  completion:(void (^)(int64_t chatId, NSString *title))completion;

/// Move a chat into the archive, or back out of it.
- (void)setChat:(int64_t)chatId archived:(BOOL)archived;

/// The unsent message in the composer, kept on Telegram's side so it is
/// there on the next launch and on every other device. Empty text clears it.
- (void)setDraft:(NSString *)text
		  inChat:(int64_t)chatId
		  thread:(int64_t)threadId
		 replyTo:(int64_t)replyToId;

/// What was last typed into this chat and not sent, by any client of this
/// account. Empty when there is none.
- (NSString *)draftForChat:(int64_t)chatId;

/// The blue dot you put there yourself; it survives until the chat is opened.
- (void)setChat:(int64_t)chatId markedUnread:(BOOL)unread;

/// Clears the @ and the reaction badge. Reading the messages does not: those
/// two counts are kept apart from unread.
- (void)readAllMentionsAndReactionsInChat:(int64_t)chatId;

/// Informs TDLib that chat is opened or closed, freeing background resources.
- (void)openChat:(int64_t)chatId;
- (void)closeChat:(int64_t)chatId;

/// Fired on the main queue when a message arrives, is edited or deleted in
/// any chat. `message` is the flattened form; nil means it was deleted.
@property (nonatomic, copy) void (^onMessage)(int64_t chatId, NSDictionary *message, int64_t deletedId);

- (void)sendText:(NSString *)text toChat:(int64_t)chatId;
/// Send into a forum topic.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId thread:(int64_t)threadId;
/// Send as a reply to a message.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId;

/// The two scheduling states a send can carry; nil fields are refused by
/// TDLib, so the request without one is the send-now call in the header.
+ (NSDictionary *)scheduledAtDate:(NSTimeInterval)date;
+ (NSDictionary *)scheduledWhenOnline;
/// The reply send with one of those states attached.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId
        scheduled:(NSDictionary *)schedulingState;

/// What a chat has waiting. Flattened like the history is.
- (void)scheduledMessagesInChat:(int64_t)chatId
                     completion:(void (^)(NSArray *messages))completion;
/// Move a scheduled message: nil for `state` sends it now, which is TDLib's
/// meaning of an absent scheduling state.
- (void)setSchedulingState:(NSDictionary *)state
                forMessage:(int64_t)messageId
                    inChat:(int64_t)chatId
                completion:(void (^)(BOOL ok))completion;

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

#pragma mark - sticker sets and GIFs (TGClient+Stickers)

/// Installed sets: "id" (pass back as is), "title", and "cover" - a sticker
/// in the same shape recentStickers gives.
- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;
- (void)stickersInSet:(id)setId completion:(void (^)(NSArray *stickers))completion;
- (void)favoriteStickersWithCompletion:(void (^)(NSArray *stickers))completion;
/// Add or remove a sticker from Favourites, which is what holding one does.
- (void)setSticker:(NSInteger)fileId favourite:(BOOL)favourite;
/// Drop one sticker out of Recently Used.
- (void)removeRecentSticker:(NSInteger)fileId;
/// Uninstall a sticker set, which is what removing a pack means.
/// `archived` with `installed` NO moves it to the archived shelf instead of
/// throwing it away; YES YES puts it back among the installed.
- (void)setStickerSet:(id)setId installed:(BOOL)installed archived:(BOOL)archived;

/// Installed sets whose titles match, for finding a pack the account has.
- (void)installedStickerSetsNamed:(NSString *)query
                       completion:(void (^)(NSArray *sets))completion;
/// The archived shelf, which is where a set removed by accident survives.
- (void)archivedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;
/// The sets that used to be attached in a chat - what their client shows
/// when you send media there.
- (void)attachedStickerSetsInChat:(int64_t)chatId
                       completion:(void (^)(NSArray *sets))completion;
/// The installed order after a move. `setIds` is the whole list, the
/// first id becoming the first strip slot.
- (void)reorderInstalledStickerSets:(NSArray *)setIds;

/// Put a GIF in Saved GIFs, and take one out again.
- (void)saveAnimationFileId:(NSInteger)fileId saved:(BOOL)saved;

/// GIFs: "fileId", "width", "height", "duration", optional "thumbId" (a
/// still picture) and "minithumbnail" (NSData, a tiny inline JPEG). Search
/// results also carry "queryId" and "resultId".
- (void)savedAnimationsWithCompletion:(void (^)(NSArray *animations))completion;
- (void)searchAnimations:(NSString *)query
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *animations))completion;
- (void)sendAnimation:(NSDictionary *)animation toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send a recorded voice note (.oga), with its duration in seconds.
- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
                 toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send a video file from the library.
- (void)sendVideoAtPath:(NSString *)path toChat:(int64_t)chatId;

/// Share a point on the map.
- (void)sendLocation:(double)latitude longitude:(double)longitude toChat:(int64_t)chatId;

/// A place that keeps changing, for `seconds` more. The send is answered
/// with the message itself - its id is what every later edit answers
/// through.
- (void)sendLiveLocation:(NSInteger)seconds
				latitude:(double)latitude
			   longitude:(double)longitude
				  toChat:(int64_t)chatId
			  completion:(void (^)(int64_t messageId))completion;

/// The moving pin, moved again, for `seconds` more of its period. 0 stops
/// it. nil id is refused, because a pin nobody can move is a lie on the map.
- (void)editLiveLocationOfMessage:(int64_t)messageId
						   inChat:(int64_t)chatId
						 latitude:(double)latitude
						longitude:(double)longitude
					   livePeriod:(NSInteger)seconds
					   completion:(void (^)(BOOL ok))completion;

/// Share someone from the address book.
- (void)sendContactNamed:(NSString *)name phone:(NSString *)phone toChat:(int64_t)chatId;

/// Send a local image file. TDLib uploads it and echoes the message back.
- (void)sendPhotoAtPath:(NSString *)path toChat:(int64_t)chatId;
/// Vote in a poll. `optionIds` are indexes into the poll's options.
- (void)votePoll:(int64_t)messageId inChat:(int64_t)chatId options:(NSArray *)optionIds;

/// Reports messages in a supergroup as spam. Reads the chat first: the
/// request wants the supergroup's own id, which a chat id is not.
- (void)reportSpamMessages:(NSArray *)messageIds
				    inChat:(int64_t)chatId
				completion:(void (^)(BOOL ok))completion;

/// Blocks whoever sent a message from replying again, optionally deleting
/// what they wrote and reporting it.
- (void)blockSenderOfMessage:(int64_t)messageId
			  deleteMessages:(BOOL)deleteMessages
				  reportSpam:(BOOL)reportSpam;

/// Closes a poll you sent; nobody can vote after that.
- (void)stopPoll:(int64_t)messageId inChat:(int64_t)chatId;

/// Who voted for one answer. `optionIndex` is the 0-based one; entries
/// carry "id", "name", "date".
- (void)pollVotersOfOption:(NSInteger)optionIndex
                ofMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                completion:(void (^)(NSArray *voters, BOOL end))completion;

/// An option added after the poll went out, for polls that allow it.
- (void)addPollOption:(NSString *)text
            toMessage:(int64_t)messageId
                 inChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion;

/// An option taken out again; `optionId` is the string id pollOption
/// carries, not an index.
- (void)deletePollOption:(NSString *)optionId
               ofMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              completion:(void (^)(BOOL ok))completion;

/// Every poll in the chat read up on, so the fresh-vote badge is gone.
- (void)readAllChatPollVotes:(int64_t)chatId;

/// React to a message with an emoji, as the current user.
- (void)reactTo:(int64_t)messageId inChat:(int64_t)chatId emoji:(NSString *)emoji;

/// Takes your own reaction back off. Nothing happens if it was not there.
- (void)removeReaction:(NSString *)emoji
		   fromMessage:(int64_t)messageId
				inChat:(int64_t)chatId;

/// "typing...", as the other side sees it. Repeat it while typing goes on;
/// it expires a few seconds after the last one. Cancel sends the stop.
- (void)sendTypingToChat:(int64_t)chatId thread:(int64_t)threadId;
- (void)cancelTypingInChat:(int64_t)chatId thread:(int64_t)threadId;

/// Marks a voice note, a video note or a one-time picture as opened, so the
/// sender's ticks say it was played.
- (void)openContentOfMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// Sends failed messages again, by the ids they kept while failing.
- (void)resendMessages:(NSArray *)messageIds inChat:(int64_t)chatId;

/// The message a reply points at, fetched from the server - the history on
/// screen may not reach back far enough to hold it. nil when it is gone.
- (void)repliedMessageTo:(int64_t)messageId
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSDictionary *message))completion;

/// A t.me link to one message, or nil for a chat that has no public link.
- (void)linkToMessage:(int64_t)messageId
			   inChat:(int64_t)chatId
		   completion:(void (^)(NSString *link))completion;

- (void)deleteMessage:(int64_t)messageId inChat:(int64_t)chatId;
- (void)deleteMessages:(NSArray *)messageIds inChat:(int64_t)chatId;
- (void)deleteMessages:(NSArray *)messageIds inChat:(int64_t)chatId revoke:(BOOL)revoke;
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

/// Adds someone to your Telegram contacts. The phone number is what the
/// server matches on.
- (void)addContactWithUserId:(int64_t)userId
				   firstName:(NSString *)firstName
					lastName:(NSString *)lastName
					   phone:(NSString *)phone
				  completion:(void (^)(BOOL ok))completion;

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

#pragma mark - stickers, searching rather than browsing (TGClient+Stickers)

/// Stickers for an emoji, out of the sets this account has installed.
- (void)stickersForEmoji:(NSString *)emoji
			  completion:(void (^)(NSArray *stickers))completion;
/// The same across every public set - the half that finds something new.
- (void)searchStickersForEmoji:(NSString *)emoji
					completion:(void (^)(NSArray *stickers))completion;
/// Sets by name. Entries are shaped as -installedStickerSetsWithCompletion:
/// answers: "id", "title", "cover".
- (void)searchStickerSetsNamed:(NSString *)query
					completion:(void (^)(NSArray *sets))completion;
- (void)trendingStickerSetsWithCompletion:(void (^)(NSArray *sets))completion;

#pragma mark - downloads (TGClient+Downloads)

/// Stops a download. `onlyIfPending` leaves one that has already started.
- (void)cancelDownloadOfFile:(NSInteger)fileId onlyIfPending:(BOOL)onlyIfPending;
/// Deletes the local copy; the file can be fetched again.
- (void)deleteLocalFile:(NSInteger)fileId;
/// Puts a file in the download list their Download Manager shows.
- (void)addFileToDownloads:(NSInteger)fileId
					inChat:(int64_t)chatId
				   message:(int64_t)messageId;
/// The list. Entries carry "fileId", "name", "size", "paused" and "done".
- (void)fileDownloadsMatching:(NSString *)query
				   activeOnly:(BOOL)activeOnly
				   completion:(void (^)(NSArray *downloads,
										NSInteger activeCount))completion;
- (void)setDownloadOfFile:(NSInteger)fileId paused:(BOOL)paused;
- (void)setAllDownloadsPaused:(BOOL)paused;
- (void)removeFileFromDownloads:(NSInteger)fileId deleteFromCache:(BOOL)deleteFromCache;
- (void)clearDownloadsDeletingFromCache:(BOOL)deleteFromCache;

#pragma mark - secret chats (TGClient+Secret)

/// Starts one. The chat exists at once but stays "pending" until the other
/// device answers the key exchange, and nothing can be sent before that.
- (void)createSecretChatWithUser:(int64_t)userId
					  completion:(void (^)(int64_t chatId))completion;
/// "pending", "ready" or "closed", by the secret chat's own id.
- (void)secretChatState:(NSInteger)secretChatId
			 completion:(void (^)(NSString *state, BOOL outgoing))completion;
/// Final: the key is gone and the chat cannot be reopened.
- (void)closeSecretChat:(NSInteger)secretChatId;
/// The secret chat id behind a chat, or 0 when it is not a secret chat. Every
/// other call here takes that rather than the chat id.
- (void)secretChatIdForChat:(int64_t)chatId
				 completion:(void (^)(NSInteger secretChatId))completion;

#pragma mark - groups and invite links (TGClient+Groups)

/// Makes a basic group - their New Group - holding `userIds`. TDLib refuses
/// an empty one, so at least one other person is required. The completion
/// gets the new chat's id, and the ids of anyone whose privacy settings
/// refused the invitation.
- (void)createGroupNamed:(NSString *)title
			   withUsers:(NSArray *)userIds
			  completion:(void (^)(int64_t chatId, NSArray *failedUserIds))completion;

/// A supergroup, or a channel with `isChannel`.
- (void)createSupergroupNamed:(NSString *)title
				  description:(NSString *)description
					isChannel:(BOOL)isChannel
				   completion:(void (^)(int64_t chatId))completion;

/// Past 200 members, or for a username or admins with rights, a basic group
/// has to become a supergroup. The chat id changes, hence the answer.
- (void)upgradeGroupToSupergroup:(int64_t)chatId
					  completion:(void (^)(int64_t newChatId))completion;

- (void)addUser:(int64_t)userId
		 toChat:(int64_t)chatId
	 completion:(void (^)(BOOL ok, NSArray *failedUserIds))completion;

/// The picker's batch, in one request. Same failed-half answer.
- (void)addUsers:(NSArray *)userIds
		  toChat:(int64_t)chatId
	  completion:(void (^)(BOOL ok, NSArray *refused))completion;

/// One member's own record; nil when there is no such member.
- (void)chatMember:(int64_t)userId
			 inChat:(int64_t)chatId
		completion:(void (^)(NSDictionary *member))completion;

/// What members may do, as a preset word: "all", "text" or "read". The
/// fifteen booleans TDLib keeps are built from it.
+ (NSDictionary *)chatPermissionsForPreset:(NSString *)preset;
- (void)setChatPermissionsFromPreset:(NSString *)preset
							   inChat:(int64_t)chatId
						  completion:(void (^)(BOOL ok))completion;

/// Handing a chat over, with the password two-factor asks for. Final.
- (void)transferOwnershipOfChat:(int64_t)chatId
						 toUser:(int64_t)userId
					   password:(NSString *)password
					 completion:(void (^)(BOOL ok))completion;

/// Members of a chat, filtered by `query`; an empty query is the whole list.
/// Entries carry "id", "name" and "status" (owner/admin/member/...).
- (void)searchMembersInChat:(int64_t)chatId
					  query:(NSString *)query
				 completion:(void (^)(NSArray *members))completion;

/// Only the administrators - a different request, and the only one that says
/// who the owner is. Entries carry "id", "name", "owner" and "editable".
- (void)administratorsOfChat:(int64_t)chatId
				  completion:(void (^)(NSArray *admins))completion;

/// "administrator", "member" or "left". Anything else is refused rather than
/// guessed at, because the wrong word here removes people.
- (void)setMember:(int64_t)userId
		   inChat:(int64_t)chatId
		   status:(NSString *)status
	   completion:(void (^)(BOOL ok))completion;

/// Not the same as removing: a banned member cannot return on a link.
- (void)banMember:(int64_t)userId
		   inChat:(int64_t)chatId
   revokeMessages:(BOOL)revokeMessages
	   completion:(void (^)(BOOL ok))completion;

- (void)setChat:(int64_t)chatId title:(NSString *)title
	 completion:(void (^)(BOOL ok))completion;
/// A supergroup or channel only; a basic group has nowhere to put one.
- (void)setChat:(int64_t)chatId description:(NSString *)description
	 completion:(void (^)(BOOL ok))completion;
- (void)setChat:(int64_t)chatId photoAtPath:(NSString *)path
	 completion:(void (^)(BOOL ok))completion;

/// Every link the chat has, flattened to "link", "name", "members",
/// "memberLimit", "primary", "revoked" and "requests".
- (void)inviteLinksForChat:(int64_t)chatId
				completion:(void (^)(NSArray *links))completion;

/// A link of its own, revocable without taking the primary one down with it.
/// A `memberLimit` of zero is no limit.
- (void)createInviteLinkForChat:(int64_t)chatId
						   name:(NSString *)name
					memberLimit:(NSInteger)memberLimit
					 completion:(void (^)(NSString *link))completion;

/// Replaces the chat's primary link; the old one stops working at once.
- (void)replacePrimaryInviteLinkForChat:(int64_t)chatId
							 completion:(void (^)(NSString *link))completion;

- (void)revokeInviteLink:(NSString *)link inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok))completion;

/// What is behind a link before joining it.
- (void)checkInviteLink:(NSString *)link
			 completion:(void (^)(NSString *title, NSInteger members,
								  BOOL alreadyMember))completion;

/// People waiting at a link that creates join requests: "id", "name", "date".
- (void)joinRequestsForChat:(int64_t)chatId
				 completion:(void (^)(NSArray *requests))completion;
- (void)processJoinRequest:(int64_t)userId inChat:(int64_t)chatId approve:(BOOL)approve;

#pragma mark - proxies (TGClient+Proxy)

/// Every proxy TDLib has been told about. Entries carry "id", "server",
/// "port", "kind" (socks5/http/mtproto/web), "enabled" and "lastUsed".
- (void)proxiesWithCompletion:(void (^)(NSArray *proxies))completion;

/// Adds one and, with `enable`, switches to it at once. The completion gets
/// its id, or 0 when the server or port made no sense.
- (void)addProxyAtServer:(NSString *)server
					port:(NSInteger)port
					kind:(NSString *)kind
				username:(NSString *)username
				password:(NSString *)password
				  secret:(NSString *)secret
				  enable:(BOOL)enable
			  completion:(void (^)(NSInteger proxyId))completion;

/// Adds a proxy out of a t.me/proxy or tg://proxy link, which is how one is
/// nearly always passed around. NO when the link carries no server and port.
- (BOOL)addProxyFromLink:(NSString *)link
			  completion:(void (^)(NSInteger proxyId))completion;

- (void)enableProxy:(NSInteger)proxyId;
/// Back to a direct connection; there is no id in this one.
- (void)disableProxy;
- (void)removeProxy:(NSInteger)proxyId;

/// How long the handshake takes, in seconds, or a negative number when the
/// proxy does not answer.
- (void)pingProxyAtServer:(NSString *)server
					 port:(NSInteger)port
					 kind:(NSString *)kind
				 username:(NSString *)username
				 password:(NSString *)password
				   secret:(NSString *)secret
			   completion:(void (^)(double seconds))completion;

#pragma mark - chat folders, the writing half (TGClient+Chats)

/// Makes a folder holding `chatIds`. `icon` is one of Telegram's own icon
/// names and may be nil. The completion gets the new folder's id, or 0.
- (void)createFolderNamed:(NSString *)name
					 icon:(NSString *)icon
				withChats:(NSArray *)chatIds
			   completion:(void (^)(NSInteger folderId))completion;

/// The folder as it stands - its chats, its flags - or nil if it is gone.
- (void)folderDetails:(NSInteger)folderId
		   completion:(void (^)(NSDictionary *folder))completion;

/// Renames a folder, or changes which chats it holds, or both: a nil leaves
/// that part as it was. An edit replaces the whole folder on Telegram's side,
/// so this reads it first.
- (void)editFolder:(NSInteger)folderId
			  name:(NSString *)name
			 chats:(NSArray *)chatIds
		completion:(void (^)(BOOL ok))completion;

/// Drops the folder. The chats in it stay; `leaveChatIds` is for the ones
/// you also want out of, and is usually empty.
- (void)deleteFolder:(NSInteger)folderId leavingChats:(NSArray *)leaveChatIds;

/// The order of the pill strip. "All chats" is a position in that order
/// rather than a folder of its own.
- (void)reorderFolderIds:(NSArray *)folderIds mainListAt:(NSInteger)position;

/// Telegram's own suggestions, each with the sentence their client shows
/// under it: "title", "description", and "folder" ready to be created.
- (void)recommendedFoldersWithCompletion:(void (^)(NSArray *folders))completion;
- (void)createRecommendedFolder:(NSDictionary *)folder
					 completion:(void (^)(NSInteger folderId))completion;

#pragma mark - maintenance

/// Drop TDLib's local database. The session stays.
- (void)clearLocalDatabase;

- (void)sendPhoneNumber:(NSString *)phoneNumber;
- (void)sendCode:(NSString *)code;
- (void)sendPassword:(NSString *)password;
- (void)resendAuthenticationCode;
- (void)requestQrCodeAuthentication;
- (void)destroySession;
- (void)logOut;

@property (nonatomic, readonly) NSDictionary *codeInfo;
@property (nonatomic, readonly) NSString *qrCodeLink;

/// Fire-and-forget request. `request` is a JSON object; @extra is not tracked.
- (void)send:(NSDictionary *)request;

@end
