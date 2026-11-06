//
// TGClient+EmojiStatus.m - the emoji status lists and the two setters.
//
// getDefaultEmojiStatuses and its chat twin answer custom_emoji_ids, while
// getRecentEmojiStatuses answers whole emojiStatus objects. Both become an
// NSNumber id here, because every screen draws the same sticker grid and the
// only thing a tap needs back is the id.
//
#import "TGClient+EmojiStatus.h"
#import "TGClientInternal.h"

static NSString *TGEmojiStatusError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

/// custom_emoji_ids is a list of int64 numbers, and TDLib writes a value too
/// large for a JSON double as a string. Both become one NSNumber so the same
/// id can be handed straight back to setEmojiStatus.
static NSArray *TGEmojiStatusIds(id value) {
	if (![value isKindOfClass:NSArray.class])
		return @[];
	NSMutableArray *out = [NSMutableArray array];
	for (id entry in (NSArray *)value){
		long long identifier = [entry longLongValue];
		if (identifier > 0)
			[out addObject:@(identifier)];
	}
	return out;
}

int64_t TGEmojiStatusCustomEmojiId(NSDictionary *status) {
	if (![status isKindOfClass:NSDictionary.class])
		return 0;
	NSDictionary *type = status[@"type"];
	if (![type isKindOfClass:NSDictionary.class])
		return 0;
	NSString *kind = type[@"@type"];
	if ([kind isEqualToString:@"emojiStatusTypeCustomEmoji"])
		return [type[@"custom_emoji_id"] longLongValue];
	if ([kind isEqualToString:@"emojiStatusTypeUpgradedGift"])
		return [type[@"model_custom_emoji_id"] longLongValue];
	return 0;
}

/// One emojiStatus with the type flattened to the three words a row shows.
static NSDictionary *TGEmojiStatusRow(NSDictionary *status) {
	if (![status isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *type = status[@"type"];
	NSString *kind = type[@"@type"] ?: @"";
	int64_t emojiId = 0;
	if ([kind isEqualToString:@"emojiStatusTypeCustomEmoji"])
		emojiId = [type[@"custom_emoji_id"] longLongValue];
	else if ([kind isEqualToString:@"emojiStatusTypeUpgradedGift"])
		emojiId = [type[@"model_custom_emoji_id"] longLongValue];
	const char *name = "unknown";
	if ([kind isEqualToString:@"emojiStatusTypeCustomEmoji"])
		name = "customEmoji";
	else if ([kind isEqualToString:@"emojiStatusTypeUpgradedGift"])
		name = "upgradedGift";
	return @{
		@"emojiId"        : @(emojiId),
		@"expirationDate" : status[@"expiration_date"] ?: @(0),
		@"kind"           : [NSString stringWithUTF8String:name],
	};
}

/// TDLib takes a null emoji_status to mean "the default badge". Building the
/// object here keeps every caller from repeating the nesting.
static id TGEmojiStatusObject(int64_t customEmojiId, NSInteger expirationDate) {
	if (customEmojiId <= 0)
		return [NSNull null];
	return @{
		@"@type" : @"emojiStatus",
		@"type" : @{
			@"@type" : @"emojiStatusTypeCustomEmoji",
			@"custom_emoji_id" : @(customEmojiId),
		},
		@"expiration_date" : @(expirationDate),
	};
}

@implementation TGClient (EmojiStatus)

- (void)emojiStatusIdsForType:(NSString *)type
                   completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : type} completion:^(NSDictionary *result){
		if (completion)
			completion(TGEmojiStatusIds(result[@"custom_emoji_ids"]));
	}];
}

- (void)themedEmojiStatusesWithCompletion:(void (^)(NSArray *))completion {
	[self emojiStatusIdsForType:@"getThemedEmojiStatuses" completion:completion];
}

- (void)defaultEmojiStatusesWithCompletion:(void (^)(NSArray *))completion {
	[self emojiStatusIdsForType:@"getDefaultEmojiStatuses" completion:completion];
}

- (void)themedChatEmojiStatusesWithCompletion:(void (^)(NSArray *))completion {
	[self emojiStatusIdsForType:@"getThemedChatEmojiStatuses" completion:completion];
}

- (void)defaultChatEmojiStatusesWithCompletion:(void (^)(NSArray *))completion {
	[self emojiStatusIdsForType:@"getDefaultChatEmojiStatuses" completion:completion];
}

- (void)disallowedChatEmojiStatusesWithCompletion:(void (^)(NSArray *))completion {
	[self emojiStatusIdsForType:@"getDisallowedChatEmojiStatuses" completion:completion];
}

- (void)recentEmojiStatusesWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getRecentEmojiStatuses"}
	   completion:^(NSDictionary *result){
		NSMutableArray *rows = [NSMutableArray array];
		NSArray *statuses = result[@"emoji_statuses"];
		if ([statuses isKindOfClass:NSArray.class])
			for (NSDictionary *status in statuses){
				NSDictionary *row = TGEmojiStatusRow(status);
				if (row)
					[rows addObject:row];
			}
		if (completion)
			completion(rows);
	}];
}

- (void)clearRecentEmojiStatusesWithCompletion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"clearRecentEmojiStatuses"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGEmojiStatusError(result) == nil,
					   TGEmojiStatusError(result));
	}];
}

- (void)setEmojiStatus:(int64_t)customEmojiId
        expirationDate:(NSInteger)expirationDate
            completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setEmojiStatus",
		@"emoji_status" : TGEmojiStatusObject(customEmojiId, expirationDate),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGEmojiStatusError(result) == nil,
					   TGEmojiStatusError(result));
	}];
}

- (void)setUserEmojiStatus:(int64_t)customEmojiId
            expirationDate:(NSInteger)expirationDate
                   forUser:(int64_t)userId
                completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setUserEmojiStatus",
		@"user_id" : @(userId),
		@"emoji_status" : TGEmojiStatusObject(customEmojiId, expirationDate),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGEmojiStatusError(result) == nil,
					   TGEmojiStatusError(result));
	}];
}

- (void)setChatEmojiStatus:(int64_t)customEmojiId
            expirationDate:(NSInteger)expirationDate
                    inChat:(int64_t)chatId
                completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setChatEmojiStatus",
		@"chat_id" : @(chatId),
		@"emoji_status" : TGEmojiStatusObject(customEmojiId, expirationDate),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(TGEmojiStatusError(result) == nil,
					   TGEmojiStatusError(result));
	}];
}

@end
