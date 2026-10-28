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

/// stickerSetInfo down to the three things a row needs. Shared by the
/// installed list, the search and the trending list, which all answer with
/// the same shape. The count, the flags and the short name ride along, which
/// is what an install sheet - and a refusal for an installed pack - needs.
NSArray *TGFlattenStickerSets(NSArray *sets) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *set in sets){
		if (![set isKindOfClass:NSDictionary.class] || !set[@"id"])
			continue;
		NSArray *covers = TGStickerList(set[@"covers"]);
		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		info[@"id"] = set[@"id"];
		info[@"title"] = set[@"title"] ?: @"";
		info[@"count"] = set[@"count"] ?: @(0);
		info[@"installed"] = @([set[@"is_installed"] boolValue]);
		info[@"archived"] = @([set[@"is_archived"] boolValue]);
		info[@"shortName"] = set[@"short_name"] ?: @"";
		if (covers.count)
			info[@"cover"] = covers.firstObject;
		[out addObject:info];
	}
	return out;
}

- (void)installedStickerSetsWithCompletion:(void (^)(NSArray *))completion {
	// Both spellings of "regular stickers, not masks": TDLib changed the
	// parameter, and it ignores the one it does not know.
	[self request:@{@"@type"        : @"getInstalledStickerSets",
					@"is_masks"     : @NO,
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"}}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

/// Stickers for an emoji, from the sets this account has installed. Their
/// panel does this as you type an emoji into the composer; here it is what
/// the sticker tab's search asks for.
- (void)stickersForEmoji:(NSString *)emoji
			  completion:(void (^)(NSArray *stickers))completion {
	if (!emoji.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"        : @"getStickers",
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
					@"query"        : emoji,
					@"limit"        : @(40),
					@"chat_id"      : @(0)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGStickerList(result[@"stickers"]));
	}];
}

/// The same, but across every public set rather than the installed ones -
/// which is the half that finds something new.
- (void)searchStickersForEmoji:(NSString *)emoji
					completion:(void (^)(NSArray *stickers))completion {
	if (!emoji.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"                : @"searchStickers",
					@"sticker_type"         : @{@"@type" : @"stickerTypeRegular"},
					@"emojis"               : emoji,
					@"query"                : @"",
					@"input_language_codes"  : @[],
					@"offset"               : @(0),
					@"limit"                : @(40)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGStickerList(result[@"stickers"]));
	}];
}

/// Sets by name, for finding one that is not installed. Entries are the same
/// shape -installedStickerSets answers with: "id", "title", "cover".
- (void)searchStickerSetsNamed:(NSString *)query
					completion:(void (^)(NSArray *sets))completion {
	if (!query.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"        : @"searchStickerSets",
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
					@"query"        : query}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

/// What is popular now, which is the other half of finding a new set.
- (void)trendingStickerSetsWithCompletion:(void (^)(NSArray *sets))completion {
	[self request:@{@"@type"        : @"getTrendingStickerSets",
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
					@"offset"       : @(0),
					@"limit"        : @(20)}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(TGFlattenStickerSets(result[@"sets"]));
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

/// A pack by the name a t.me/addstickers link carries. The record Telegram
/// answers with carries everything the sheet needs - the id to install by,
/// the count, and whether the account already has it.
- (void)stickerSetByShortName:(NSString *)shortName
				   completion:(void (^)(NSDictionary *set))completion {
	if (!shortName.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"  : @"getStickerSet",
		@"set_id" : @{@"@type" : @"inputStickerSetShortName",
					  @"short_name" : shortName},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"stickerSet"] || !result[@"id"]){
			completion(nil);
			return;
		}
		NSArray *flattened = TGFlattenStickerSets(@[result]);
		completion(flattened.firstObject);
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

- (void)setStickerSet:(id)setId installed:(BOOL)installed archived:(BOOL)archived {
	if (!setId)
		return;
	// Answered rather than fire-and-forget: a declined removal is otherwise
	// silent, and "nothing happened" is the hardest kind of bug to chase.
	[self request:@{@"@type"        : @"changeStickerSet",
					@"set_id"       : setId,
					@"is_installed" : @(installed),
					@"is_archived"  : @(archived)}
	   completion:^(NSDictionary *result){
		NSLog(@"TGClient: change set %@ (installed %d, archived %d) -> %@",
				setId, installed, archived, result[@"@type"]);
	}];
}

/// Installed sets whose titles match. Their own client reaches for this when
/// the search says the word and the answer is a pack the account already has.
- (void)installedStickerSetsNamed:(NSString *)query
                       completion:(void (^)(NSArray *sets))completion {
	if (!query.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"        : @"searchInstalledStickerSets",
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
					@"query"        : query,
					@"limit"        : @(40)}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

/// The archived shelf is where a set deleted by accident survives, so this
/// is the second half the "Remove from Recent"-style removal needs.
- (void)archivedStickerSetsWithCompletion:(void (^)(NSArray *sets))completion {
	[self request:@{@"@type"        : @"getArchivedStickerSets",
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
					@"offset"       : @(0),
					@"limit"        : @(100)}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

/// Sets that were attached in a chat. Their client feeds this into the
/// media composer; here it answers with the same rows as the installed list.
- (void)attachedStickerSetsInChat:(int64_t)chatId
                       completion:(void (^)(NSArray *sets))completion {
	if (!chatId){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"   : @"getAttachedStickerSets",
					@"chat_id" : @(chatId),
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"}}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

- (void)reorderInstalledStickerSets:(NSArray *)setIds {
	if (setIds.count < 2)
		return;   // one set or none: nothing to order
	// The request is answered with a unit, but failure is better heard than
	// assumed, which is why this is a request and not a send.
	[self request:@{@"@type"   : @"reorderInstalledStickerSets",
					@"sticker_type" : @{@"@type" : @"stickerTypeRegular"},
					@"set_ids"  : setIds}
	   completion:^(NSDictionary *result){
		NSLog(@"TGClient: reorder installed sets -> %@", result[@"@type"]);
	}];
}

- (void)saveAnimationFileId:(NSInteger)fileId saved:(BOOL)saved {
	if (fileId <= 0)
		return;
	[self request:@{@"@type"     : saved ? @"addSavedAnimation" : @"removeSavedAnimation",
					@"animation" : @{@"@type" : @"inputFileId", @"id" : @(fileId)}}
	   completion:^(NSDictionary *result){
		NSLog(@"TGClient: %@ saved animation %ld -> %@", saved ? @"add" : @"remove",
				(long)fileId, result[@"@type"]);
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
