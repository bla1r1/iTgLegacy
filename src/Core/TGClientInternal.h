#import "TGClient.h"
#import <UIKit/UIKit.h>

typedef void *(*td_create_fn)(void);
typedef void  (*td_send_fn)(void *client, const char *request);
typedef const char *(*td_recv_fn)(void *client, double timeout);
typedef const char *(*td_exec_fn)(void *client, const char *request);

@interface TGClient ()
@property (nonatomic, assign) void *handle;
@property (nonatomic, assign) void *client;
@property (nonatomic, assign) td_send_fn td_send;
@property (nonatomic, assign) td_recv_fn td_recv;
@property (nonatomic, assign) TGAuthState authState;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, copy)   NSString *pendingPhoneNumber;
@property (nonatomic, strong) NSMutableDictionary *chatsById;   // id -> mutable info
@property (nonatomic, strong) NSMutableDictionary *usersById;   // id -> display name
@property (nonatomic, strong) NSMutableDictionary *userPhotosById; // id -> photo file id
@property (nonatomic, strong) NSMutableDictionary *forumSupergroups;
@property (nonatomic, strong) NSArray *archivedChats;
@property (nonatomic, strong) NSArray *folders;
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSMutableArray *outbox;   // JSON strings awaiting send
@property (nonatomic, strong) NSLock *outboxLock;
@property (nonatomic, assign) NSUInteger chatsAtLastLoad;
@property (nonatomic, assign) BOOL chatListComplete;
@property (nonatomic, assign) NSUInteger loadChatsAttempts;
@property (nonatomic, strong) NSDictionary *me;
@property (nonatomic, assign) TGConnectionState connectionState;
@property (nonatomic, strong) NSMutableDictionary *pendingRequests;  // @extra -> completion
@property (nonatomic, assign) NSUInteger requestSeq;
@property (nonatomic, strong) NSMutableDictionary *fileWaiters;      // fileId -> completions
@property (nonatomic, strong) NSDictionary *codeInfo;
@property (nonatomic, copy)   NSString *qrCodeLink;

// Internal methods shared across categories
- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion;
- (void)drainOutbox;
- (void)handleUpdate:(NSDictionary *)obj;
- (void)handleAuthState:(NSDictionary *)state;
- (void)sendTdlibParameters;
- (void)flushPendingPhoneNumber;
- (void)notifyFileWaiters:(NSInteger)fileId path:(NSString *)path;
- (void)cacheProfilePhoto:(NSDictionary *)user;
- (void)mergeChat:(NSDictionary *)chat;
- (void)applyChatUpdate:(NSDictionary *)update;
- (void)rebuildChats;
- (NSString *)previewForLastMessage:(NSDictionary *)last inChat:(NSMutableDictionary *)info;

@end

// Common helpers shared between TGClient and categories
NSDictionary *TGFlattenMessage(NSDictionary *m);
NSString *TGMessagePreview(NSDictionary *message);
NSString *TGPhraseFromTypeName(NSString *ctype);
NSString *TGReactionSummary(NSDictionary *m);
int64_t TGOrderInList(NSArray *positions, NSString *listType);
BOOL TGPinnedInMain(NSArray *positions);
int64_t TGMainListOrder(NSArray *positions);
int64_t TGArchiveOrder(NSArray *positions);
