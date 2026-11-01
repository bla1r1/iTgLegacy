//
// TGClient+Secret.h - the client surface for secret chats.
//
#import "TGClient+Base.h"

@interface TGClient (Secret)

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

@end
