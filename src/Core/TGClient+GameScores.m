//
// TGClient+GameScores.m
//
// The score table is part of the message's game content, not a separate
// cache. Both getters return the rows Telegram sent; the setter returns the
// edited message, flattened through the same routine every chat cell uses.
//
#import "TGClient+GameScores.h"
#import "TGClientInternal.h"

static NSArray *TGGameArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSNumber *TGGameNumber(id value) {
	return [value isKindOfClass:NSNumber.class] ? value : @0;
}

static NSString *TGGameString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *TGGameErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] && message.length
			? message : @"Telegram refused that.";
}

static BOOL TGGameFailed(NSDictionary *result) {
	return [result[@"@type"] isEqualToString:@"error"];
}

static NSArray *TGGameScores(NSDictionary *result) {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *score in TGGameArray(result[@"scores"])){
		if (![score isKindOfClass:NSDictionary.class])
			continue;
		[rows addObject:@{
			@"position" : TGGameNumber(score[@"position"]),
			@"userId" : TGGameNumber(score[@"user_id"]),
			@"score" : TGGameNumber(score[@"score"]),
		}];
	}
	return rows;
}

@implementation TGClient (GameScores)

- (void)gameHighScoresForChat:(int64_t)chatId
					  message:(int64_t)messageId
						 user:(int64_t)userId
				   completion:(void (^)(NSArray *, NSString *))completion {
	if (!chatId || !messageId || !userId){
		if (completion)
			completion(nil, @"A chat id, a message id and a user id are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"getGameHighScores",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"user_id" : @(userId),
	} completion:^(NSDictionary *result){
		if (TGGameFailed(result)){
			if (completion) completion(nil, TGGameErrorText(result));
			return;
		}
		if (completion) completion(TGGameScores(result), nil);
	}];
}

- (void)inlineGameHighScores:(NSString *)inlineMessageId
						 user:(int64_t)userId
				   completion:(void (^)(NSArray *, NSString *))completion {
	NSString *identifier = TGGameString(inlineMessageId);
	if (!identifier.length || !userId){
		if (completion)
			completion(nil, @"An inline message id and a user id are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"getInlineGameHighScores",
		@"inline_message_id" : identifier,
		@"user_id" : @(userId),
	} completion:^(NSDictionary *result){
		if (TGGameFailed(result)){
			if (completion) completion(nil, TGGameErrorText(result));
			return;
		}
		if (completion) completion(TGGameScores(result), nil);
	}];
}

- (void)setGameScoreForChat:(int64_t)chatId
					message:(int64_t)messageId
					 user:(int64_t)userId
					  score:(int32_t)score
					  force:(BOOL)force
			 editMessage:(BOOL)editMessage
				 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId || !messageId || !userId){
		if (completion)
			completion(nil, @"A chat id, a message id and a user id are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"setGameScore",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"edit_message" : @(editMessage),
		@"user_id" : @(userId),
		@"score" : @(score),
		@"force" : @(force),
	} completion:^(NSDictionary *result){
		if (TGGameFailed(result)){
			if (completion) completion(nil, TGGameErrorText(result));
			return;
		}
		NSDictionary *flat = TGFlattenMessage(result);
		NSDictionary *message = @{
			@"id" : flat[@"id"] ?: @0,
			@"text" : flat[@"text"] ?: @"",
			@"kind" : flat[@"kind"] ?: @"",
		};
		if (completion) completion(message, nil);
	}];
}

- (void)setInlineGameScore:(NSString *)inlineMessageId
					  user:(int64_t)userId
					 score:(int32_t)score
					 force:(BOOL)force
			   editMessage:(BOOL)editMessage
				completion:(void (^)(BOOL, NSString *))completion {
	NSString *identifier = TGGameString(inlineMessageId);
	if (!identifier.length || !userId){
		if (completion)
			completion(NO, @"An inline message id and a user id are needed.");
		return;
	}
	[self request:@{
		@"@type" : @"setInlineGameScore",
		@"inline_message_id" : identifier,
		@"edit_message" : @(editMessage),
		@"user_id" : @(userId),
		@"score" : @(score),
		@"force" : @(force),
	} completion:^(NSDictionary *result){
		BOOL ok = !TGGameFailed(result);
		if (completion) completion(ok, ok ? nil : TGGameErrorText(result));
	}];
}

@end

// vim:ft=objc
