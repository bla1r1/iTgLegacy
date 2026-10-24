//
// TGClient+Stickers.m - sticker sets, favourites, saved GIFs and GIF search
// for the emoji / sticker / GIF panel.
//
#import "TGClientInternal.h"

/// One sticker as the panel wants it: what to send, and what to draw in the
/// grid. The thumbnail is drawn only when it is a still picture; a .tgs or
/// .webm thumbnail is left to the emoji beside it.
NSDictionary *TGStickerInfo(NSDictionary *sticker) {
	NSNumber *fileId = sticker[@"sticker"][@"id"];
	if (!fileId)
		return nil;
	NSString *format = sticker[@"format"][@"@type"] ?: @"";
	BOOL webp = [format isEqualToString:@"stickerFormatWebp"];

	NSDictionary *thumbnail = sticker[@"thumbnail"];
	NSString *thumbFormat = thumbnail[@"format"][@"@type"] ?: @"";
	NSNumber *thumbId = thumbnail[@"file"][@"id"];
	BOOL thumbIsPicture = [thumbFormat isEqualToString:@"thumbnailFormatWebp"] ||
						  [thumbFormat isEqualToString:@"thumbnailFormatJpeg"] ||
						  [thumbFormat isEqualToString:@"thumbnailFormatPng"];
	if (!thumbId || !thumbIsPicture){
		// A plain WebP sticker is its own thumbnail.
		thumbId = webp ? fileId : @0;
	}
	return @{
		@"fileId"     : fileId,
		@"emoji"      : sticker[@"emoji"] ?: @"",
		@"isAnimated" : @(!webp),
		@"thumbId"    : thumbId ?: @0,
		@"width"      : sticker[@"width"] ?: @512,
		@"height"     : sticker[@"height"] ?: @512,
	};
}

static NSArray *TGStickerList(NSArray *stickers) {
	NSMutableArray *out = [NSMutableArray array];
	if (![stickers isKindOfClass:NSArray.class])
		return out;
	for (NSDictionary *sticker in stickers){
		NSDictionary *info = TGStickerInfo(sticker);
		if (info)
			[out addObject:info];
	}
	return out;
}

/// One GIF as the panel wants it. "minithumbnail" is a tiny JPEG carried
/// inline, so the grid has something to show before any download.
static NSDictionary *TGAnimationInfo(NSDictionary *animation) {
	NSNumber *fileId = animation[@"animation"][@"id"];
	if (!fileId)
		return nil;
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"fileId"]   = fileId;
	info[@"width"]    = animation[@"width"] ?: @0;
	info[@"height"]   = animation[@"height"] ?: @0;
	info[@"duration"] = animation[@"duration"] ?: @0;

	NSString *mini = animation[@"minithumbnail"][@"data"];
	if ([mini isKindOfClass:NSString.class] && mini.length){
		NSData *data = nil;
		if ([NSData instancesRespondToSelector:@selector(initWithBase64EncodedString:options:)])
			data = [[NSData alloc] initWithBase64EncodedString:mini options:0];
		else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			data = [[NSData alloc] initWithBase64Encoding:mini];
#pragma clang diagnostic pop
		}
		if (data)
			info[@"minithumbnail"] = data;
	}

	NSDictionary *thumbnail = animation[@"thumbnail"];
	NSString *thumbFormat = thumbnail[@"format"][@"@type"] ?: @"";
	if ([thumbFormat isEqualToString:@"thumbnailFormatJpeg"] ||
		[thumbFormat isEqualToString:@"thumbnailFormatPng"] ||
		[thumbFormat isEqualToString:@"thumbnailFormatWebp"]){
		NSNumber *thumbId = thumbnail[@"file"][@"id"];
		if (thumbId)
			info[@"thumbId"] = thumbId;
	}
	return info;
}

@implementation TGClient (Stickers)

- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *))completion {
	// Both spellings of "regular stickers, not masks": TDLib changed the
	// parameter, and it ignores the one it does not know.
	[self request:@{@"@type"        : @"getInstalledStickerSets",
					@"is_masks"     : @NO,
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"}}
	   completion:^(NSDictionary *result){
		NSMutableArray *sets = [NSMutableArray array];
		for (NSDictionary *set in result[@"sets"]){
			if (![set isKindOfClass:NSDictionary.class] || !set[@"id"])
				continue;
			NSArray *covers = TGStickerList(set[@"covers"]);
			NSMutableDictionary *info = [NSMutableDictionary dictionary];
			info[@"id"] = set[@"id"];
			info[@"title"] = set[@"title"] ?: @"";
			if (covers.count)
				info[@"cover"] = covers.firstObject;
			[sets addObject:info];
		}
		if (completion) completion(sets);
	}];
}

- (void)stickersInSet:(id)setId completion:(void (^)(NSArray *))completion {
	if (!setId){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type" : @"getStickerSet", @"set_id" : setId}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGStickerList(result[@"stickers"]));
	}];
}

- (void)favoriteStickersWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getFavoriteStickers"}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGStickerList(result[@"stickers"]));
	}];
}

- (void)setSticker:(NSInteger)fileId favourite:(BOOL)favourite {
	if (fileId <= 0)
		return;
	// Answered rather than fire-and-forget: a refused favourite is otherwise
	// silent, and "nothing happened" is the hardest kind of bug to chase.
	[self request:@{@"@type"   : favourite ? @"addFavoriteSticker" : @"removeFavoriteSticker",
					@"sticker" : @{@"@type" : @"inputFileId", @"id" : @(fileId)}}
	   completion:^(NSDictionary *result){
		NSLog(@"TGClient: %@ favourite %ld -> %@", favourite ? @"add" : @"remove",
				(long)fileId, result[@"@type"]);
	}];
}

- (void)removeRecentSticker:(NSInteger)fileId {
	if (fileId <= 0)
		return;
	[self request:@{@"@type"       : @"removeRecentSticker",
					@"is_attached" : @NO,
					@"sticker"     : @{@"@type" : @"inputFileId", @"id" : @(fileId)}}
	   completion:^(NSDictionary *result){
		NSLog(@"TGClient: remove recent %ld -> %@", (long)fileId, result[@"@type"]);
	}];
}

- (void)removeStickerSet:(id)setId {
	if (!setId)
		return;
	[self request:@{@"@type"        : @"changeStickerSet",
					@"set_id"       : setId,
					@"is_installed" : @NO,
					@"is_archived"  : @NO}
	   completion:^(NSDictionary *result){
		NSLog(@"TGClient: remove set %@ -> %@", setId, result[@"@type"]);
	}];
}

- (void)savedAnimationsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getSavedAnimations"}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *animation in result[@"animations"]){
			NSDictionary *info = [animation isKindOfClass:NSDictionary.class]
					? TGAnimationInfo(animation) : nil;
			if (info)
				[out addObject:info];
		}
		if (completion) completion(out);
	}];
}

/// GIF search is the @gif inline bot, which every client uses for it. Its
/// results are sent as inline results so the message credits the bot.
- (void)searchAnimations:(NSString *)query
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *))completion {
	void (^fail)(void) = ^{ if (completion) completion(@[]); };
	[self request:@{@"@type" : @"searchPublicChat", @"username" : @"gif"}
	   completion:^(NSDictionary *bot){
		NSNumber *botUserId = bot[@"type"][@"user_id"];
		if (!botUserId){
			fail();
			return;
		}
		[self request:@{@"@type"       : @"getInlineQueryResults",
						@"bot_user_id" : botUserId,
						@"chat_id"     : @(chatId),
						@"query"       : query ?: @"",
						@"offset"      : @""}
		   completion:^(NSDictionary *result){
			id queryId = result[@"inline_query_id"];
			NSMutableArray *out = [NSMutableArray array];
			for (NSDictionary *item in result[@"results"]){
				if (![item isKindOfClass:NSDictionary.class] ||
					![item[@"@type"] isEqualToString:@"inlineQueryResultAnimation"])
					continue;
				NSMutableDictionary *info = [TGAnimationInfo(item[@"animation"]) mutableCopy];
				if (!info || !queryId || !item[@"id"])
					continue;
				info[@"queryId"] = queryId;
				info[@"resultId"] = item[@"id"];
				[out addObject:info];
			}
			if (completion) completion(out);
		}];
	}];
}

- (void)sendAnimation:(NSDictionary *)animation toChat:(int64_t)chatId thread:(int64_t)threadId {
	if (animation[@"queryId"] && animation[@"resultId"]){
		[self send:@{@"@type"             : @"sendInlineQueryResultMessage",
					 @"chat_id"           : @(chatId),
					 @"message_thread_id" : @(threadId),
					 @"query_id"          : animation[@"queryId"],
					 @"result_id"         : animation[@"resultId"]}];
		return;
	}
	if (!animation[@"fileId"])
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		// Same nesting as stickers: inputMessageAnimation takes an
		// inputAnimation, and that is what holds the InputFile.
		@"input_message_content": @{
			@"@type"     : @"inputMessageAnimation",
			@"animation" : @{
				@"@type"     : @"inputAnimation",
				@"animation" : @{@"@type" : @"inputFileId", @"id" : animation[@"fileId"]},
				@"duration"  : animation[@"duration"] ?: @0,
				@"width"     : animation[@"width"] ?: @0,
				@"height"    : animation[@"height"] ?: @0,
			},
		},
	}];
}

@end
