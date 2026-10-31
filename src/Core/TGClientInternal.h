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
@property (nonatomic, copy)   NSString *pendingPhoneNumber;
@property (nonatomic, strong) NSMutableDictionary *chatsById;   // id -> mutable info
@property (nonatomic, strong) NSMutableDictionary *usersById;   // id -> display name
/// Bounded at TGRawUserCacheCap: every user the session has ever seen used
/// to stay here, and a busy account meets tens of thousands of them.
@property (nonatomic, strong) TGObjectLruCache *rawUsersById; // id -> raw user dict
@property (nonatomic, strong) NSMutableDictionary *userPhotosById; // id -> photo file id
@property (nonatomic, strong) NSMutableDictionary *forumSupergroups;
@property (nonatomic, strong) NSArray *archivedChats;
@property (nonatomic, strong) NSArray *folders;
@property (nonatomic, strong) NSDictionary *archiveSettings;
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL batchingUpdates;
@property (nonatomic, assign) BOOL chatsNeedRebuild;
@property (nonatomic, strong) TGUpdateCoalescer *updateCoalescer;
@property (nonatomic, strong) NSMutableArray *outbox;   // JSON strings awaiting send
@property (nonatomic, strong) NSLock *outboxLock;
@property (nonatomic, assign) NSUInteger chatsAtLastLoad;
@property (nonatomic, assign) BOOL chatListComplete;
@property (nonatomic, assign) NSUInteger loadChatsAttempts;
@property (nonatomic, strong) NSDictionary *me;
@property (nonatomic, assign) TGConnectionState connectionState;
@property (nonatomic, strong) NSMutableDictionary *pendingRequests;  // @extra -> completion
@property (nonatomic, assign) NSUInteger requestSeq;
@property (nonatomic, strong) NSDictionary *codeInfo;
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
- (NSUInteger)fileWaiterCount:(NSInteger)fileId;
- (BOOL)hasFileWaiterRecord:(NSInteger)fileId;
- (NSInteger)fileWaiterPriority:(NSInteger)fileId;

// The download watchdog timeout, 45 s in production; the host tests shrink
// it so the timer fires inside a test runtime.
extern double TGFileWaiterTimeoutSeconds;
- (void)cacheProfilePhoto:(NSDictionary *)user;
- (void)mergeChat:(NSDictionary *)chat;
- (void)applyChatUpdate:(NSDictionary *)update;
- (void)rebuildChats;
/// One field on one chat row changed, so the list is stale but nothing is
/// waiting on it this instant. Updates that arrive in floods - a typing
/// storm, the presence burst at login, a forum flag landing on twenty chats
/// at once - go through here instead of rebuilding per event.
- (void)markChatRowDirty:(int64_t)chatId;
- (NSString *)previewForLastMessage:(NSDictionary *)last inChat:(NSMutableDictionary *)info;

@end

#ifdef __cplusplus
extern "C" {
#endif

// Common helpers shared between TGClient and categories
NSDictionary *TGFlattenMessage(NSDictionary *m);
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
