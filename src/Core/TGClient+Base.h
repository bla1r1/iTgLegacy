//
// TGClient+Base - the client's own state: dylib availability, authorization,
// connection, and the callbacks that carry update streams to the screens.
// Also the per-account lookups every screen leans on.
//
#import <Foundation/Foundation.h>
#import "TGClientTypes.h"
#import "TGClientNotifications.h"

@interface TGClient : NSObject

+ (instancetype)shared;

/// YES once libtdjson.dylib is loaded and a client exists.
@property (nonatomic, readonly) BOOL available;

@property (nonatomic, readonly) TGAuthState authState;

/// Called on the main queue whenever the authorization state changes.
@property (nonatomic, copy) void (^onAuthState)(TGAuthState state);

/// Called on the main queue for TDLib errors that concern the user.
@property (nonatomic, copy) void (^onError)(NSString *message);

@property (nonatomic, readonly) TGConnectionState connectionState;

/// Main queue. `text` is nil when connected, a short status otherwise.
@property (nonatomic, copy) void (^onConnectionState)(TGConnectionState state, NSString *text);

/// Called on the main queue whenever the chat list changed. Read `chats`.
@property (nonatomic, copy) void (^onChatsChanged)(void);

/// Chats in the archive, same shape as `chats`.
@property (nonatomic, readonly) NSArray *archivedChats;

/// The Saved Messages topics, as they streamed in: dicts with "id" (the
/// topic's), "date", "title", "text", "pinned" and "order".
@property (nonatomic, readonly) NSArray *savedTopics;

/// How many chat records the client has actually cached - the merge uses it
/// to notice when the cache grew enough to be worth re-reading the folders.
@property (nonatomic, readonly) NSUInteger chatsCached;

/// Called on the main queue when the archive changes.
@property (nonatomic, copy) void (^onArchiveChanged)(void);

/// Chat folders the user has configured: "id" and "title".
@property (nonatomic, readonly) NSArray *folders;

/// Chat list, most recent first. Each entry is a dictionary with keys
/// "id" (NSNumber), "title", "text" (last message preview), "unread"
/// (NSNumber), "date" (NSNumber, unix time), "isGroup" (NSNumber BOOL - a
/// basic group, supergroup or channel, where messages need a sender name),
/// "action" (NSString - "typing..." and the like, empty when nobody is), and
/// "isOnline" (NSNumber BOOL, private chats only).
/// Main queue only.
@property (nonatomic, readonly) NSArray *chats;

/// The signed-in user: "id", "first_name", "username", "phone". Nil until the
/// session is ready. Main queue only.
@property (nonatomic, readonly) NSDictionary *me;

/// Loads the dylib, creates the client and starts the receive loop.
/// Safe to call more than once. Returns NO if TDLib is unavailable.
- (BOOL)start;

/// iOS kills a suspended app holding a file lock outside its container
/// (0xdead10cc), and installed in /Applications td.binlog is outside one.
/// So TDLib closes on the way to the background - `done` runs once it has,
/// on the main queue - and starts again on the way back. The screens keep
/// their state across it; no auth state reaches them.
- (void)pauseForBackground:(void (^)(void))done;

- (void)resumeFromBackground;

/// Request with a reply. `completion` runs on the main queue with the raw
/// TDLib object, or an object of @type "error".
- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *result))completion;

#pragma mark - files

/// Progress of a running download, 0..1, on the main queue. Fires for every
/// file TDLib is fetching, so listeners must check the id they care about.
@property (nonatomic, copy) void (^onFileProgress)(NSInteger fileId, float progress);

#pragma mark - messages

/// Someone is typing (or recording, or uploading) in a chat. `action` is a
/// short phrase to show, or nil when they stopped.
@property (nonatomic, copy) void (^onChatAction)(int64_t chatId, NSString *action);

/// A secret chat changed state - the answer to a key exchange, or the
/// moment one is closed. `secretChatId` is the secretchat's own id, and
/// `state` is "pending", "ready" or "closed".
@property (nonatomic, copy) void (^onSecretChat)(NSInteger secretChatId, NSString *state);

#pragma mark - account settings

/// Fired on the main queue when a message arrives, is edited or deleted in
/// any chat. `message` is the flattened form; nil means it was deleted.
@property (nonatomic, copy) void (^onMessage)(int64_t chatId, NSDictionary *message, int64_t deletedId);

#pragma mark - sticker sets and GIFs (TGClient+Stickers)

#pragma mark - message functions, the third wave

/// "typing...", as the other side sees it. Repeat it while typing goes on;

#pragma mark - contacts

#pragma mark - storage

#pragma mark - account

#pragma mark - people

#pragma mark - stickers, searching rather than browsing (TGClient+Stickers)

#pragma mark - downloads (TGClient+Downloads)

#pragma mark - secret chats (TGClient+Secret)

#pragma mark - groups and invite links (TGClient+Groups)

#pragma mark - proxies (TGClient+Proxy)

#pragma mark - chat folders, the writing half (TGClient+Chats)

/// The Archive screen's three settings as one archiveChatListSettings
/// dictionary, readable before the network answers anything.
@property (nonatomic, readonly) NSDictionary *archiveSettings;

#pragma mark - maintenance

@property (nonatomic, readonly) NSDictionary *codeInfo;

@property (nonatomic, readonly) NSString *qrCodeLink;

/// From authorizationStateWaitPassword: "password_hint",
/// "has_recovery_email_address", "recovery_email_address_pattern".
@property (nonatomic, readonly) NSDictionary *loginPasswordInfo;

/// From authorizationStateWaitEmailCode: "code_info" (with
/// "email_address_pattern" and "length") and "can_reset_email_address".
@property (nonatomic, readonly) NSDictionary *emailCodeInfo;

/// Fire-and-forget request. `request` is a JSON object; @extra is not tracked.
- (void)send:(NSDictionary *)request;

/// The synchronous half of td_api - a few functions answer with no round
/// trip. nil when the dylib has no execute symbol.
- (NSDictionary *)executeSynchronously:(NSDictionary *)request;

@end
