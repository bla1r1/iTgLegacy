#import "TGClient.h"
#import "TGUpdateBatcher.hpp"
#import "TGImageLruCache.h"

/// Raw TDLib user records held in memory. 1000 is far more than any screen
/// shows and still a hard ceiling - see the 16 MB cache budget in
/// C_CPP_MIGRATION_PLAN.md.
#define TGRawUserCacheCap 1000
#import <UIKit/UIKit.h>

typedef void *(*td_create_fn)(void);
typedef void  (*td_send_fn)(void *client, const char *request);
typedef const char *(*td_recv_fn)(void *client, double timeout);
typedef const char *(*td_exec_fn)(void *client, const char *request);

#ifdef __cplusplus
extern "C" {
#endif

/// A TDLib sticker in the shape the panel uses; nil without a file.
NSDictionary *TGStickerInfo(NSDictionary *sticker);

/// One profileAudio object flattened for a row: "fileId", "title",
/// "performer", "duration", "fileName", "mimeType", "albumCoverId". Nil when
/// the object names no audio file. Shared by the profile list and the header
/// strip so both draw the same shape from `first_profile_audio`.
NSDictionary *TGProfileAudioRow(NSDictionary *audio);

/// The birthday a profile row shows, or nil for none. "Birthday today" when
/// `now` lands on the day and month, otherwise "March 5" or, with a year,
/// "March 5, 1990 (34 years old)". `now` is a parameter so a host test can
/// pin today instead of depending on the wall clock.
NSString *TGProfileBirthdayText(NSInteger day, NSInteger month, NSInteger year, NSDate *now);
BOOL TGProfileBirthdayIsToday(NSInteger day, NSInteger month, NSDate *now);

/// The first active username of a raw TDLib user, or nil. TDLib sends an
/// empty active_usernames array for an account with no username, so a bare
/// `[0]` subscript raises and must never be written at a call site.
NSString *TGFirstUsername(NSDictionary *user);

/// Appends one search page to an existing list, dropping a message id that is
/// already there. TDLib starts a search at the message named in
/// from_message_id, so the last row of the current page comes back first.
NSArray *TGMediaPageAppending(NSArray *existing, NSArray *more);

#ifdef __cplusplus
}
#endif

@interface TGClient ()
@property (nonatomic, assign) void *handle;
@property (nonatomic, assign) void *client;
@property (nonatomic, assign) td_send_fn td_send;
@property (nonatomic, assign) td_recv_fn td_recv;
/// td_json_client_execute, for the handful of td_api functions that answer
/// without a round trip. Null when the dylib is missing the symbol, which
/// every caller has to survive.
@property (nonatomic, assign) td_exec_fn td_exec;
/// The terms Telegram sent with the registration state, kept for the screen
/// that has to show them before an account is made.
@property (nonatomic, copy) NSString *registrationTermsText;
@property (nonatomic, assign) TGAuthState authState;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL running;
/// The background close: asked for, finished, and a return that came first.
@property (nonatomic, assign) BOOL pausing;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL resumeWanted;
@property (nonatomic, copy)   void (^pauseDone)(void);
- (void)clientClosed;
@property (nonatomic, copy)   NSString *pendingPhoneNumber;
@property (nonatomic, strong) NSMutableDictionary *chatsById;   // id -> mutable info
@property (nonatomic, strong) NSMutableDictionary *usersById;   // id -> display name
/// Bounded at TGRawUserCacheCap: every user the session has ever seen used
/// to stay here, and a busy account meets tens of thousands of them.
@property (nonatomic, strong) TGObjectLruCache *rawUsersById; // id -> raw user dict
@property (nonatomic, strong) NSMutableDictionary *userPhotosById; // id -> photo file id
@property (nonatomic, strong) NSMutableDictionary *forumSupergroups;
@property (nonatomic, strong) NSArray *archivedChats;
@property (nonatomic, strong) NSMutableDictionary *savedTopicsById; // topic id -> row
/// The reaction Telegram names as the default, when updateDefaultReactionType
/// has said; the picker leads with it.
@property (nonatomic, copy) NSString *reactionDefaultEmoji;
/// The whole reactionNotificationSettings record Telegram last sent. The
/// public surface reads it; the setter rebuilds it so one switch does not
/// clear the sources this screen does not show.
@property (nonatomic, copy) NSDictionary *reactionNotificationSettingsValue;
/// TDLib's local notification groups, as updateActiveNotifications and the
/// two incremental updates shape them. Each group keeps its notifications
/// sorted by id; the Active Notifications screen draws this and only asks the
/// server again on first open or after its own removal.
@property (nonatomic, copy) NSArray *activeNotificationGroupRows;
/// updateHavePendingNotifications: TDLib is still fetching or delaying
/// notifications, so the list is incomplete and the screen shows a spinner.
@property (nonatomic, assign) BOOL haveDelayedNotifications;
@property (nonatomic, assign) BOOL haveUnreceivedNotifications;
/// The last autosaveSettings scope update, keyed by "private", "groups" and
/// "channels". Exceptions are not carried by updateAutosaveSettings; the
/// screen re-reads getAutosaveSettings for those.
@property (nonatomic, strong) NSMutableDictionary *autosaveSettingsByScope;
/// The last strings updateLanguagePackStrings carried for each pack. A later
/// update may be partial, so this is the last change, not a complete pack.
@property (nonatomic, copy) NSDictionary *languagePackStringsByPack;
/// The GIF provider and the emoji it suggests, from
/// updateAnimationSearchParameters. "gif" is the bot every client ships with.
@property (nonatomic, copy) NSString *gifSearchProvider;
@property (nonatomic, strong) NSArray *gifSearchEmojis;
@property (nonatomic, strong) NSArray *folders;
@property (nonatomic, strong) NSDictionary *archiveSettings;
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL batchingUpdates;
@property (nonatomic, assign) BOOL chatsNeedRebuild;
@property (nonatomic, strong) TGUpdateCoalescer *updateCoalescer;
@property (nonatomic, strong) NSMutableArray *outbox;   // JSON strings awaiting send
@property (nonatomic, strong) NSLock *outboxLock;
/// Wakes the idle receive thread as soon as there is something to send.
@property (nonatomic, strong) dispatch_semaphore_t outboxSignal;
@property (nonatomic, assign) NSUInteger chatsAtLastLoad;
@property (nonatomic, assign) BOOL chatListComplete;
@property (nonatomic, assign) NSUInteger loadChatsAttempts;
@property (nonatomic, strong) NSDictionary *me;
/// Accent ids Telegram says this account may pick. 0-6 are guaranteed by the
/// schema and fill in until updateAccentColors arrives; the profile list has
/// the same rule.
@property (nonatomic, strong) NSArray *accentColorIds;
@property (nonatomic, strong) NSArray *profileAccentColorIds;
/// The full accentColor / profileAccentColor records (id plus the light/dark
/// RGB arrays) behind those ids, so a swatch can be drawn from the server's
/// colours instead of a name list.
@property (nonatomic, strong) NSArray *accentColors;
@property (nonatomic, strong) NSArray *profileAccentColors;
/// Contacts with a birthday nearby, from updateContactCloseBirthdays. The
/// privacy page shows the count and hideContactCloseBirthdays empties it.
@property (nonatomic, strong) NSArray *contactCloseBirthdays;
/// Telegram's own account facts, kept whole rather than reduced to the one
/// line each Settings row shows: the sheet behind the row reads the reason,
/// the dates and the action the update named. Nil until that update arrives.
@property (nonatomic, copy) NSDictionary *freezeStateValue;
@property (nonatomic, copy) NSDictionary *ageVerificationParametersValue;
@property (nonatomic, copy) NSDictionary *recaptchaVerificationRequestValue;
/// Subscriptions are per user; the signed-in account is the one the Privacy
/// page draws, but the update names whoever it is about.
@property (nonatomic, strong) NSMutableDictionary *userSubscriptionsById;
/// The two effect lists from updateAvailableMessageEffects. The effect sheet
/// reads them live, so a list that changes while the menu is open is the one
/// the next hold shows.
@property (nonatomic, strong) NSArray *reactionMessageEffectIds;
@property (nonatomic, strong) NSArray *stickerMessageEffectIds;
/// The default background record (for_dark_theme plus the background object)
/// and the emoji chat themes, both read by Appearance.
@property (nonatomic, copy) NSDictionary *defaultBackgroundValue;
@property (nonatomic, strong) NSArray *emojiChatThemesValue;
/// The last draft stop and the last auto-published video, kept so a screen
/// that opens after the notification can still say what happened.
@property (nonatomic, copy) NSDictionary *stoppedMessageDraftValue;
@property (nonatomic, copy) NSDictionary *publishedVideoValue;
/// Voice and round notes being sent, by pending message id: the file being
/// uploaded, the last fraction, and the blocks waiting to hear about it.
@property (nonatomic, strong) NSMutableDictionary *noteSendWaiters;
- (void)noteUploadProgress:(NSInteger)fileId fraction:(float)fraction;
- (void)noteSendFinished:(int64_t)messageId sent:(BOOL)sent;
/// The story strip's chat counts per list, and the stealth window Telegram
/// last reported. The stories menu reads both from the client.
@property (nonatomic, assign) NSInteger storyMainListChatCount;
@property (nonatomic, assign) NSInteger storyArchiveListChatCount;
@property (nonatomic, copy) NSDictionary *storyStealthModeValue;
/// Star facts that only arrive as updates: the account's own balance, one
/// chat's revenue amount and one owner's revenue status. The revenue screens
/// ask for the same numbers, so each keeps its own notification.
@property (nonatomic, assign) int64_t ownedStarCountValue;
@property (nonatomic, strong) NSMutableDictionary *chatRevenueAmountByChat;
@property (nonatomic, strong) NSMutableDictionary *starRevenueStatusByOwner;
/// Text composition styles arrive whole in updateTextCompositionStyles and
/// change only through the seven calls in TGClient+TextStyles. The manager
/// and the composer read this one list.
@property (nonatomic, strong) NSArray *textCompositionStylesValue;
/// DM topics per chat and per topic id. loadDirectMessagesChatTopics answers
/// only OK; the rows stream in through updateDirectMessagesChatTopic.
@property (nonatomic, strong) NSMutableDictionary *directMessagesTopicsByChat;
/// The last stake dice state. The state hash expires, so the panel reads the
/// latest one before it offers a roll.
@property (nonatomic, copy) NSDictionary *stakeDiceStateValue;
/// updateActiveNotifications and its two incremental shapes, flattened for
/// the Active Notifications page. It is the only copy: TDLib has no request
/// that re-reads it.
@property (nonatomic, strong) NSArray *activeNotificationGroupsValue;
/// Communities, quick replies and suggested actions arrive as updates with
/// no listing request behind them; TGClient+Tier2 fills these and the screens
/// read them. The order arrays keep Telegram's order, which a dictionary
/// cannot.
@property (nonatomic, strong) NSMutableDictionary *communitiesById;
@property (nonatomic, strong) NSMutableArray *communityOrder;
@property (nonatomic, strong) NSMutableDictionary *communityFullInfoById;
@property (nonatomic, strong) NSMutableDictionary *quickReplyShortcutsById;
@property (nonatomic, strong) NSMutableArray *quickReplyShortcutOrder;
@property (nonatomic, strong) NSMutableDictionary *quickReplyMessagesByShortcut;
/// The last SuggestedAction rows, merged from updateSuggestedActions.
@property (nonatomic, copy) NSArray *suggestedActionsValue;
/// The checklist a message read last returned, keyed by message id. A write
/// drops its entry so the editor asks again rather than drawing a stale box.
@property (nonatomic, strong) NSMutableDictionary *checklistCache;
@property (nonatomic, assign) TGConnectionState connectionState;
@property (nonatomic, strong) NSMutableDictionary *pendingRequests;  // @extra -> completion
@property (nonatomic, assign) NSUInteger requestSeq;
@property (nonatomic, strong) NSDictionary *codeInfo;
@property (nonatomic, strong) NSDictionary *loginPasswordInfo;
@property (nonatomic, strong) NSDictionary *emailCodeInfo;
@property (nonatomic, copy)   NSString *qrCodeLink;

// Internal methods shared across categories
- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion;
- (void)drainOutbox;
- (void)handleUpdate:(NSDictionary *)obj;
- (void)handleUpdateBatch:(NSArray *)batch;
- (void)handleAuthState:(NSDictionary *)state;
- (void)sendTdlibParameters;
- (void)flushPendingPhoneNumber;
// The download waiter table lives in C++ behind its own mutex (see
// TGClient+Files.mm); these are the only ways in.
- (void)notifyFileWaiters:(NSInteger)fileId path:(NSString *)path;
- (void)expireFileWaiters:(NSInteger)fileId;
- (void)sweepFileWaiters:(NSInteger)fileId;
- (void)releaseFileWaiters:(NSInteger)fileId;
- (void)removeAllFileWaiters;
/// The preliminary-upload/generation records keyed by original path. Cleared
/// on an account switch: the file ids they track belong to the old client.
- (void)removeAllPendingGenerations;
- (NSUInteger)fileWaiterCount:(NSInteger)fileId;
- (BOOL)hasFileWaiterRecord:(NSInteger)fileId;
- (NSInteger)fileWaiterPriority:(NSInteger)fileId;
/// A TDLib generation request. The file-generation flow lives in +Files,
/// because the reply is sent with writeGeneratedFilePart and the pending
/// request is the record it finishes.
- (void)handleFileGenerationStart:(NSDictionary *)update;
- (void)handleFileGenerationStop:(NSDictionary *)update;
/// Upload progress on a file this client is generating; forwarded to the
/// pending generation's progress block.
- (void)handleFileUploadProgress:(NSInteger)fileId file:(NSDictionary *)file;

// The download watchdog timeout, 45 s in production; the host tests shrink
// it so the timer fires inside a test runtime.
extern double TGFileWaiterTimeoutSeconds;
- (void)cacheProfilePhoto:(NSDictionary *)user;
- (void)mergeChat:(NSDictionary *)chat;
- (void)applyChatUpdate:(NSDictionary *)update;
- (void)rebuildChats;
/// The local notification list's four updates. They live beside the public
/// activeNotifications read so the row shape and the incremental shape agree.
- (void)applyActiveNotificationsUpdate:(NSDictionary *)update;
- (void)applyNotificationUpdate:(NSDictionary *)update;
- (void)applyNotificationGroupUpdate:(NSDictionary *)update;
- (void)applyHavePendingNotificationsUpdate:(NSDictionary *)update;
/// updateAutosaveSettings carries one scope, never the exception list; the
/// page re-reads the whole record. Kept in TGClient+Account where the
/// getAutosaveSettings flattening lives.
- (void)applyAutosaveSettingsUpdate:(NSDictionary *)update;
/// updateLanguagePackStrings carries the strings that changed, not a whole
/// pack. Kept in TGClient+Language beside getLanguagePackStrings.
- (void)applyLanguagePackStringsUpdate:(NSDictionary *)update;
/// A channel direct messages topic arrived or moved. Kept beside the list
/// call in TGClient+DirectMessages so the row shape and the update agree.
- (void)applyDirectMessagesChatTopic:(NSDictionary *)topic;
/// updateTextCompositionStyles carries the whole list; replacing it is the
/// only merge Telegram defines.
- (void)applyTextCompositionStylesUpdate:(NSDictionary *)update;
/// updateStakeDiceState carries the state a roll must quote.
- (void)applyStakeDiceStateUpdate:(NSDictionary *)update;
/// Group call updates: the call record, one participant, a batch of ids, a
/// new message, a deletion, and a send failure. Kept in TGClient+GroupCalls
/// beside the flattening the call screens read.
- (void)applyGroupCallUpdate:(NSDictionary *)update;
/// Drops every group call, participant and message the client cached. Called
/// on an account switch so the next account's call screens do not read the
/// previous account's call ids and senders.
- (void)resetGroupCallState;
- (void)applyGroupCallParticipantUpdate:(NSDictionary *)update;
- (void)applyGroupCallParticipantsUpdate:(NSDictionary *)update;
- (void)applyNewGroupCallMessage:(NSDictionary *)update;
- (void)applyGroupCallMessagesDeleted:(NSDictionary *)update;
- (void)applyGroupCallMessageSendFailed:(NSDictionary *)update;
/// The communities, quick replies and suggested actions have no list request.
/// TGClient+Tier2 owns the caches these four fill.
- (void)applyCommunityUpdate:(NSDictionary *)update;
- (void)applyCommunityFullInfoUpdate:(NSDictionary *)update;
- (void)applyQuickReplyShortcutUpdate:(NSDictionary *)update;
- (void)applyQuickReplyShortcutDeleted:(NSDictionary *)update;
- (void)applyQuickReplyShortcutsUpdate:(NSDictionary *)update;
- (void)applyQuickReplyShortcutMessagesUpdate:(NSDictionary *)update;
- (void)applySuggestedActionsUpdate:(NSDictionary *)update;
/// updateChatActiveStories: the strip row for one chat. Kept in
/// TGClient+Stories beside the per-chat read it replaces.
- (void)applyChatActiveStoriesUpdate:(NSDictionary *)update;
/// The story updates: one story changed or went away, a post finished, the
/// strip count moved, and the stealth window changed. Kept in
/// TGClient+Stories so the row and viewer notifications use one shape.
- (void)applyStoryUpdate:(NSDictionary *)update;
- (void)applyStoryDeletedUpdate:(NSDictionary *)update;
- (void)applyStoryPostUpdate:(NSDictionary *)update;
- (void)applyStoryListChatCountUpdate:(NSDictionary *)update;
- (void)applyStoryStealthModeUpdate:(NSDictionary *)update;
/// Star balances and revenue. Kept in TGClient+Tier3 beside the requests the
/// Stars screen already makes for the same numbers.
- (void)applyOwnedStarCountUpdate:(NSDictionary *)update;
- (void)applyChatRevenueAmountUpdate:(NSDictionary *)update;
- (void)applyStarRevenueStatusUpdate:(NSDictionary *)update;
/// One field on one chat row changed, so the list is stale but nothing is
/// waiting on it this instant. Updates that arrive in floods - a typing
/// storm, the presence burst at login, a forum flag landing on twenty chats
/// at once - go through here instead of rebuilding per event.
- (void)markChatRowDirty:(int64_t)chatId;
- (NSString *)previewForLastMessage:(NSDictionary *)last inChat:(NSMutableDictionary *)info;

@end

/// The local notification list's three update shapes, in one place because
/// they all end by posting the same notification. A category rather than the
/// class extension, because the implementation lives in TGClient+Notifications.
@interface TGClient (NotificationsInternal)
- (void)applyActiveNotificationUpdate:(NSDictionary *)update;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Common helpers shared between TGClient and categories
NSDictionary *TGFlattenMessage(NSDictionary *m);
NSDictionary *TGFlattenStory(NSDictionary *story);
NSNumber *TGPlayableVideoFileId(NSDictionary *video, NSArray *alternatives, int maxSide,
								NSNumber **fallback);
/// Vintage's software decoder: 720 pixels on the long side, square frames
/// included. Takes the largest H.264 copy inside that, or the original.
/// `width`/`height` receive the chosen file's size.
NSNumber *TGPlayableVideoFileIdVintage(NSDictionary *video, NSArray *alternatives,
									   NSNumber **fallback, int *width, int *height);
NSDictionary *TGFlattenReplyMarkup(NSDictionary *markup);
NSString *TGMessagePreview(NSDictionary *message);
NSString *TGKnownMessagePreview(NSDictionary *message);
NSString *TGPhraseFromTypeName(NSString *ctype);
NSString *TGReactionSummary(NSDictionary *m);

/// Unwraps whatever nesting a title arrived in - a plain string, a
/// chatFolderName, a formattedText - down to the string. nil when there is
/// none. Shared because the folder writing half builds these back up.
NSString *TGPlainTitle(id value);

/// stickerSetInfo entries down to "id", "title" and "cover".
NSArray *TGFlattenStickerSets(NSArray *sets);

/// A formattedText for `text`, with Bold, Italic, Code and the rest read out
/// of the markup the user typed. Falls back to the text as written when the
/// parse is unavailable or the markup does not pair up.
NSDictionary *TGFormattedText(NSString *text);

/// The emoji of your own reaction on a message, or nil.
NSString *TGMyReactionEmoji(NSDictionary *m);
int64_t TGOrderInList(NSArray *positions, NSString *listType);
BOOL TGPinnedInMain(NSArray *positions);
int64_t TGMainListOrder(NSArray *positions);
int64_t TGArchiveOrder(NSArray *positions);

#ifdef __cplusplus
}
#endif
