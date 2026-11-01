//
// TGClient+Secret.m - secret chats.
//
// The encryption is TDLib's, not this app's: a secret chat is a chat like any
// other once it exists, with its own id and the same message stream. What was
// missing was the three requests that make one, read its state and close it.
//
#import "TGClientInternal.h"

/// A secret chat's state as one word, for a header that has to say whether
/// the other side has turned up yet.
static NSString *TGSecretStateName(NSString *type) {
	if ([type isEqualToString:@"secretChatStatePending"]) return @"pending";
	if ([type isEqualToString:@"secretChatStateReady"])   return @"ready";
	if ([type isEqualToString:@"secretChatStateClosed"])  return @"closed";
	return @"unknown";
}

@implementation TGClient (Secret)

/// Starts one with someone. The chat exists at once but stays "pending" until
/// their device comes online and answers the key exchange - nothing can be
/// sent before that, and the screen has to say so rather than look broken.
- (void)createSecretChatWithUser:(int64_t)userId
					  completion:(void (^)(int64_t chatId))completion {
	if (!userId){
		if (completion) completion(0);
		return;
	}
	[self request:@{@"@type" : @"createNewSecretChat", @"user_id" : @(userId)}
	   completion:^(NSDictionary *result){
		int64_t chatId = [result[@"id"] longLongValue];
		NSNumber *secretChatId = result[@"type"][@"secret_chat_id"];
		// The compatibility path travels with creation: createSecretChat is
		// the older spelling that turns the inner id back into the chat, and
		// running it here means a caller on an older layer still gets a chat
		// id even when createNewSecretChat's answer is the other shape.
		if (secretChatId && chatId){
			[self request:@{@"@type" : @"createSecretChat",
							@"secret_chat_id" : secretChatId}
			   completion:^(NSDictionary *resolved){
				int64_t resolvedId = [resolved[@"id"] longLongValue];
				if (completion)
					completion(resolvedId ? resolvedId : chatId);
			}];
			return;
		}
		if (completion)
			completion(chatId);
	}];
}

/// The state of one, by the secret chat's own id - which is not the chat id.
/// A chat's type carries it: chatTypeSecret{secret_chat_id, user_id}.
- (void)secretChatState:(NSInteger)secretChatId
			 completion:(void (^)(NSString *state, BOOL outgoing))completion {
	[self request:@{@"@type" : @"getSecretChat",
					@"secret_chat_id" : @(secretChatId)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"secretChat"]){
			completion(@"unknown", NO);
			return;
		}
		completion(TGSecretStateName(result[@"state"][@"@type"]),
				   [result[@"is_outbound"] boolValue]);
	}];
}

/// Closing one is final: the key is gone and the chat cannot be reopened.
- (void)closeSecretChat:(NSInteger)secretChatId {
	[self send:@{@"@type" : @"closeSecretChat",
				 @"secret_chat_id" : @(secretChatId)}];
}

/// The secret chat id behind a chat, or 0 if that chat is not a secret one.
/// Every other secret-chat call takes this rather than the chat id.
- (void)secretChatIdForChat:(int64_t)chatId
				 completion:(void (^)(NSInteger secretChatId))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		if (!completion)
			return;
		NSDictionary *type = chat[@"type"];
		if (![type[@"@type"] isEqualToString:@"chatTypeSecret"]){
			completion(0);
			return;
		}
		completion([type[@"secret_chat_id"] integerValue]);
	}];
}

@end

// vim:ft=objc
