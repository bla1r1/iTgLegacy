//
// TGClient+Stickers.m - sticker sets, favourites, saved GIFs and GIF search
// for the emoji / sticker / GIF panel.
//
#import "TGClientInternal.h"
#import "TGStickerPack.h"

/// One sticker as the panel wants it: what to send, and what to draw in the
/// grid. The thumbnail is drawn only when it is a still picture; a .tgs or
/// .webm thumbnail is left to the emoji beside it.
NSDictionary *TGStickerInfo(NSDictionary *sticker) {
	if (![sticker isKindOfClass:NSDictionary.class])
		return nil;
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

/// The panel's sticker rows, held as one flat POD buffer rather than a
/// dictionary per sticker - TGStickerPack is itself an NSArray, so nothing
/// downstream changes. See TGStickerPack.h for what that costs and saves.
static NSArray *TGStickerList(NSArray *stickers) {
	return [TGStickerPack packWithTDLibStickers:stickers];
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
		info[@"owned"] = @([set[@"is_owned"] boolValue]);
		// td_api settled on "name"; older fixtures and the search answer
		// this file has always read use "short_name". Both are the same
		// string, and a pack with neither is unnamed rather than wrong.
		info[@"shortName"] = set[@"name"] ?: (set[@"short_name"] ?: @"");
		// The editor and the group picker have to tell a custom emoji pack
		// from an ordinary one; the type is the only field that does it.
		info[@"stickerType"] = set[@"sticker_type"][@"@type"] ?: @"stickerTypeRegular";
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
					@"offset_sticker_set_id" : @(0),
					@"limit"        : @(100)}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

/// The sticker sets a piece of media carries. TDLib names them by the media
/// file's own id, which is what a bubble already has; this is how a photo
/// with stickers on it says which packs they came from.
- (void)attachedStickerSetsOfFile:(NSInteger)fileId
                       completion:(void (^)(NSArray *sets))completion {
	if (fileId <= 0){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"   : @"getAttachedStickerSets",
					@"file_id" : @(fileId)}
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
	// The provider is Telegram's to move; updateAnimationSearchParameters is
	// what says where, and "gif" is only the name it starts at.
	NSString *provider = self.animationSearchProvider;
	[self request:@{@"@type" : @"searchPublicChat", @"username" : provider}
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

#pragma mark - authoring a pack

/// The InputFile every sticker request names. A file id is enough: the
/// editor has just uploaded the file, so TDLib already knows the bytes.
static NSDictionary *TGStickerFile(int64_t fileId) {
	return @{@"@type" : @"inputFileId", @"id" : @(fileId)};
}

/// The three formats a pack may hold. A name the caller got wrong becomes
/// WebP, which is the static default rather than a silent .tgs upload.
static NSDictionary *TGStickerFormat(NSString *name) {
	NSString *type = @"stickerFormatWebp";
	if ([name isEqualToString:@"tgs"])
		type = @"stickerFormatTgs";
	else if ([name isEqualToString:@"webm"])
		type = @"stickerFormatWebm";
	return @{@"@type" : type};
}

/// A sticker type from the word the editor shows.
static NSDictionary *TGStickerType(NSString *name) {
	NSString *type = @"stickerTypeRegular";
	if ([name isEqualToString:@"mask"])
		type = @"stickerTypeMask";
	else if ([name isEqualToString:@"customEmoji"])
		type = @"stickerTypeCustomEmoji";
	return @{@"@type" : type};
}

/// One TDLib sticker with the two ids the flat pack drops: the custom emoji
/// it stands for and the set it belongs to. Used only by the custom emoji
/// screens, where those ids are the whole point.
static NSArray *TGCustomEmojiStickerList(NSArray *stickers) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *sticker in stickers){
		if (![sticker isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *info = TGStickerInfo(sticker);
		if (!info)
			continue;
		NSMutableDictionary *row = [info mutableCopy];
		// TDLib writes int64 either as a JSON number or as a string when it
		// is too large for a double; both become one NSNumber here so the
		// same id can be passed straight back to a request.
		row[@"customEmojiId"] = @([sticker[@"full_type"][@"custom_emoji_id"]
				longLongValue]);
		row[@"setId"] = @([sticker[@"set_id"] longLongValue]);
		row[@"format"] = sticker[@"format"][@"@type"] ?: @"";
		[out addObject:row];
	}
	return out;
}

- (int64_t)stickerOwnerUserId {
	return [self.me[@"id"] longLongValue];
}

- (void)ownedStickerSetsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getOwnedStickerSets",
					@"offset_sticker_set_id" : @(0),
					@"limit" : @(100)}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGFlattenStickerSets(result[@"sets"]));
	}];
}

- (void)checkStickerSetName:(NSString *)name
				 completion:(void (^)(NSString *, NSString *))completion {
	if (!name.length){
		if (completion) completion(@"invalid", @"A pack needs a short name.");
		return;
	}
	[self request:@{@"@type" : @"checkStickerSetName", @"name" : name}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSString *type = result[@"@type"] ?: @"error";
		if ([type isEqualToString:@"checkStickerSetNameResultOk"]){
			completion(@"ok", @"This name is free.");
			return;
		}
		if ([type isEqualToString:@"checkStickerSetNameResultNameOccupied"]){
			completion(@"occupied", @"That name is taken by another pack.");
			return;
		}
		if ([type isEqualToString:@"checkStickerSetNameResultNameInvalid"]){
			completion(@"invalid", @"Use 1 to 64 letters, numbers and "
					@"underscores, starting with a letter.");
			return;
		}
		completion(@"invalid", result[@"message"] ?: @"Telegram refused the name.");
	}];
}

- (void)suggestStickerSetNameForTitle:(NSString *)title
						   completion:(void (^)(NSString *))completion {
	if (!title.length){
		if (completion) completion(@"");
		return;
	}
	[self request:@{@"@type" : @"getSuggestedStickerSetName", @"title" : title}
	   completion:^(NSDictionary *result){
		if (completion) completion(result[@"text"] ?: @"");
	}];
}

- (void)stickerSetNameForId:(int64_t)setId completion:(void (^)(NSString *))completion {
	if (!setId){
		if (completion) completion(@"");
		return;
	}
	[self request:@{@"@type" : @"getStickerSetName", @"set_id" : @(setId)}
	   completion:^(NSDictionary *result){
		if (completion) completion(result[@"text"] ?: @"");
	}];
}

- (void)searchStickerSetNamed:(NSString *)name
				  ignoreCache:(BOOL)ignoreCache
				   completion:(void (^)(NSDictionary *))completion {
	if (!name.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"searchStickerSet",
					@"name" : name,
					@"ignore_cache" : @(ignoreCache)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"stickerSet"] || !result[@"id"]){
			completion(nil);
			return;
		}
		NSDictionary *flat = TGFlattenStickerSets(@[result]).firstObject;
		NSMutableDictionary *set = [flat mutableCopy];
		set[@"name"] = result[@"name"] ?: name;
		set[@"stickers"] = TGStickerList(result[@"stickers"]);
		completion(set);
	}];
}

- (NSDictionary *)newStickerWithFileId:(NSInteger)fileId
								format:(NSString *)format
								emojis:(NSString *)emojis
							  keywords:(NSArray *)keywords
						  maskPosition:(NSDictionary *)maskPosition {
	NSMutableDictionary *sticker = [NSMutableDictionary dictionary];
	sticker[@"@type"] = @"newSticker";
	sticker[@"sticker"] = TGStickerFile(fileId);
	sticker[@"format"] = TGStickerFormat(format);
	sticker[@"emojis"] = emojis ?: @"";
	sticker[@"keywords"] = keywords ?: @[];
	if (maskPosition)
		sticker[@"mask_position"] = maskPosition;
	return sticker;
}

- (void)createStickerSetNamed:(NSString *)name
						title:(NSString *)title
				  stickerType:(NSString *)type
					 stickers:(NSArray *)stickers
				   completion:(void (^)(NSDictionary *))completion {
	if (!name.length || !title.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"createNewStickerSet",
					@"user_id" : @([self stickerOwnerUserId]),
					@"title" : title,
					@"name" : name,
					@"sticker_type" : TGStickerType(type),
					@"needs_repainting" : @NO,
					@"stickers" : stickers ?: @[],
					@"source" : @"legacy"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (![result[@"@type"] isEqualToString:@"stickerSet"] || !result[@"id"]){
			completion(nil);
			return;
		}
		NSDictionary *flat = TGFlattenStickerSets(@[result]).firstObject;
		NSMutableDictionary *set = [flat mutableCopy];
		set[@"name"] = result[@"name"] ?: name;
		set[@"stickers"] = TGStickerList(result[@"stickers"]);
		completion(set);
	}];
}

- (void)deleteStickerSetNamed:(NSString *)name completion:(void (^)(BOOL))completion {
	if (!name.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"deleteStickerSet", @"name" : name}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"deleteStickerSet %@: %@", name, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)addStickerToSetNamed:(NSString *)name
					 sticker:(NSDictionary *)sticker
				  completion:(void (^)(BOOL))completion {
	if (!name.length || !sticker){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"addStickerToSet",
					@"user_id" : @([self stickerOwnerUserId]),
					@"name" : name,
					@"sticker" : sticker}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"addStickerToSet %@: %@", name, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)removeStickerFileId:(NSInteger)fileId completion:(void (^)(BOOL))completion {
	if (fileId <= 0){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"removeStickerFromSet",
					@"sticker" : TGStickerFile(fileId)}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"removeStickerFromSet %ld: %@", (long)fileId, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)replaceStickerInSetNamed:(NSString *)name
					  oldFileId:(NSInteger)oldFileId
					  newSticker:(NSDictionary *)sticker
					  completion:(void (^)(BOOL))completion {
	if (!name.length || oldFileId <= 0 || !sticker){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"replaceStickerInSet",
					@"user_id" : @([self stickerOwnerUserId]),
					@"name" : name,
					@"old_sticker" : TGStickerFile(oldFileId),
					@"new_sticker" : sticker}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"replaceStickerInSet %@: %@", name, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)setStickerFileId:(NSInteger)fileId
		   positionInSet:(NSInteger)position
			  completion:(void (^)(BOOL))completion {
	if (fileId <= 0 || position < 0){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setStickerPositionInSet",
					@"sticker" : TGStickerFile(fileId),
					@"position" : @(position)}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (completion) completion(ok);
	}];
}

- (void)setStickerFileId:(NSInteger)fileId
				  emojis:(NSString *)emojis
			  completion:(void (^)(BOOL))completion {
	if (fileId <= 0){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setStickerEmojis",
					@"sticker" : TGStickerFile(fileId),
					@"emojis" : emojis ?: @""}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setStickerEmojis %ld: %@", (long)fileId, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)setStickerFileId:(NSInteger)fileId
				keywords:(NSArray *)keywords
			  completion:(void (^)(BOOL))completion {
	if (fileId <= 0){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setStickerKeywords",
					@"sticker" : TGStickerFile(fileId),
					@"keywords" : keywords ?: @[]}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setStickerKeywords %ld: %@", (long)fileId, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)setStickerFileId:(NSInteger)fileId
			maskPosition:(NSDictionary *)maskPosition
			  completion:(void (^)(BOOL))completion {
	if (fileId <= 0){
		if (completion) completion(NO);
		return;
	}
	// td_api: "pass null to remove mask position". The JSON tree cannot hold
	// a nil value, so the absence is written as NSNull and TDLib reads it
	// back as the null the function expects.
	id position = maskPosition ?: (id)[NSNull null];
	[self request:@{@"@type" : @"setStickerMaskPosition",
					@"sticker" : TGStickerFile(fileId),
					@"mask_position" : position}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setStickerMaskPosition %ld: %@", (long)fileId, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)setStickerSetNamed:(NSString *)name
					 title:(NSString *)title
				completion:(void (^)(BOOL))completion {
	if (!name.length || !title.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setStickerSetTitle",
					@"name" : name,
					@"title" : title}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setStickerSetTitle %@: %@", name, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)setStickerSetNamed:(NSString *)name
		 thumbnailAtPath:(NSString *)path
				  format:(NSString *)format
			  completion:(void (^)(BOOL))completion {
	if (!name.length || !path.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setStickerSetThumbnail",
					@"user_id" : @([self stickerOwnerUserId]),
					@"name" : name,
					@"thumbnail" : @{@"@type" : @"inputFileLocal", @"path" : path},
					@"format" : TGStickerFormat(format)}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setStickerSetThumbnail %@: %@", name, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)uploadStickerAtPath:(NSString *)path
					 format:(NSString *)format
				 completion:(void (^)(NSInteger))completion {
	if (!path.length){
		if (completion) completion(0);
		return;
	}
	[self request:@{@"@type" : @"uploadStickerFile",
					@"user_id" : @([self stickerOwnerUserId]),
					@"sticker_format" : TGStickerFormat(format),
					@"sticker" : @{@"@type" : @"inputFileLocal", @"path" : path}}
	   completion:^(NSDictionary *result){
		NSInteger fileId = 0;
		if ([result[@"@type"] isEqualToString:@"file"])
			fileId = [result[@"id"] integerValue];
		else
			NSLog(@"uploadStickerFile: %@", result[@"message"] ?: result[@"@type"]);
		if (completion) completion(fileId);
	}];
}

#pragma mark - emoji metadata and outlines

- (void)stickerEmojisForFileId:(NSInteger)fileId
					completion:(void (^)(NSArray *))completion {
	if (fileId <= 0){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type" : @"getStickerEmojis",
					@"sticker" : TGStickerFile(fileId)}
	   completion:^(NSDictionary *result){
		if (completion) completion(result[@"emojis"] ?: @[]);
	}];
}

- (void)allStickerEmojisForQuery:(NSString *)query
						  chatId:(int64_t)chatId
					 stickerType:(NSString *)type
						mainOnly:(BOOL)mainOnly
					  completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getAllStickerEmojis",
					@"sticker_type" : TGStickerType(type),
					@"query" : query ?: @"",
					@"chat_id" : @(chatId),
					@"return_only_main_emoji" : @(mainOnly)}
	   completion:^(NSDictionary *result){
		if (completion) completion(result[@"emojis"] ?: @[]);
	}];
}

- (void)stickerOutlineForFileId:(NSInteger)fileId
					 completion:(void (^)(NSArray *, NSInteger))completion {
	if (fileId <= 0){
		if (completion) completion(@[], 0);
		return;
	}
	[self request:@{@"@type" : @"getStickerOutline",
					@"sticker_file_id" : @(fileId),
					@"for_animated_emoji" : @NO,
					@"for_clicked_animated_emoji_message" : @NO}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSArray *paths = [result[@"paths"] isKindOfClass:NSArray.class]
				? result[@"paths"] : @[];
		NSInteger points = 0;
		for (NSDictionary *path in paths){
			NSArray *commands = path[@"commands"];
			if ([commands isKindOfClass:NSArray.class])
				points += (NSInteger)commands.count;
		}
		completion(paths, points);
	}];
}

- (void)stickerOutlineSvgPathForFileId:(NSInteger)fileId
							completion:(void (^)(NSString *))completion {
	if (fileId <= 0){
		if (completion) completion(@"");
		return;
	}
	[self request:@{@"@type" : @"getStickerOutlineSvgPath",
					@"sticker_file_id" : @(fileId),
					@"for_animated_emoji" : @NO,
					@"for_clicked_animated_emoji_message" : @NO}
	   completion:^(NSDictionary *result){
		if (completion) completion(result[@"text"] ?: @"");
	}];
}

#pragma mark - emoji panel and reactions

/// One category row as the strip reads it. Telegram's source is either a
/// search list or a premium shelf; the panel draws the first and has nothing
/// this account can open for the second, so both are handed over with the
/// kind that says which. The icon is a custom emoji sticker: its "emoji"
/// field is the only part a phone without custom-emoji rendering can draw.
- (void)emojiCategoriesWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getEmojiCategories",
					@"type" : [NSNull null]}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *category in result[@"categories"]){
			if (![category isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *source = category[@"source"];
			if (![source isKindOfClass:NSDictionary.class])
				source = @{};
			NSArray *emojis = [source[@"emojis"] isKindOfClass:NSArray.class]
					? source[@"emojis"] : @[];
			NSDictionary *iconInfo = [category[@"icon"] isKindOfClass:NSDictionary.class]
					? category[@"icon"] : nil;
			NSString *icon = iconInfo[@"emoji"];
			if (!icon.length && emojis.count)
				icon = emojis.firstObject;
			[out addObject:@{
				@"name"   : category[@"name"] ?: @"",
				@"icon"   : icon ?: @"",
				@"kind"   : source[@"@type"] ?: @"",
				@"emojis" : emojis,
			}];
		}
		if (completion) completion(out);
	}];
}

/// searchEmojis answers emojiKeyword rows, one per (emoji, keyword) pair, so
/// the same glyph repeats. The grid wants glyphs, once, in TDLib's order.
- (void)searchEmojis:(NSString *)text
       languageCodes:(NSArray *)languageCodes
          completion:(void (^)(NSArray *))completion {
	if (!text.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"                 : @"searchEmojis",
					@"text"                  : text,
					@"input_language_codes"  : languageCodes ?: @[]}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];
		for (NSDictionary *row in result[@"emoji_keywords"]){
			NSString *emoji = row[@"emoji"];
			if (![emoji isKindOfClass:NSString.class] || !emoji.length ||
				[seen containsObject:emoji])
				continue;
			[seen addObject:emoji];
			[out addObject:emoji];
		}
		if (completion) completion(out);
	}];
}

- (void)keywordEmojis:(NSString *)text
        languageCodes:(NSArray *)languageCodes
           completion:(void (^)(NSArray *))completion {
	if (!text.length){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type"                 : @"getKeywordEmojis",
					@"text"                  : text,
					@"input_language_codes"  : languageCodes ?: @[]}
	   completion:^(NSDictionary *result){
		NSArray *emojis = [result[@"emojis"] isKindOfClass:NSArray.class]
				? result[@"emojis"] : @[];
		if (completion) completion(emojis);
	}];
}

- (void)emojiSuggestionsUrlForLanguage:(NSString *)languageCode
                            completion:(void (^)(NSString *))completion {
	NSString *code = languageCode.length ? languageCode
			: ([[NSLocale preferredLanguages] firstObject] ?: @"en");
	[self request:@{@"@type"          : @"getEmojiSuggestionsUrl",
					@"language_code"  : code}
	   completion:^(NSDictionary *result){
		NSString *url = [result[@"@type"] isEqualToString:@"error"]
				? @"" : (result[@"url"] ?: @"");
		if (completion) completion(url);
	}];
}

/// The animation Telegram names first is the one to play; the field order
/// here follows how a reaction is shown - centre, then appear, then select.
static NSDictionary *TGReactionAnimation(NSDictionary *reaction) {
	NSArray *names = @[@"center_animation", @"appear_animation",
					   @"select_animation", @"activate_animation",
					   @"effect_animation", @"around_animation"];
	for (NSString *name in names){
		NSDictionary *info = TGStickerInfo(reaction[name]);
		if (info)
			return info;
	}
	return nil;
}

- (void)emojiReactionForEmoji:(NSString *)emoji
                  completion:(void (^)(NSDictionary *))completion {
	if (!emoji.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getEmojiReaction", @"emoji" : emoji}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		NSDictionary *animation = TGReactionAnimation(result);
		NSDictionary *staticIcon = TGStickerInfo(result[@"static_icon"]);
		NSMutableDictionary *row = [NSMutableDictionary dictionary];
		row[@"emoji"]   = result[@"emoji"] ?: emoji;
		row[@"title"]   = result[@"title"] ?: @"";
		row[@"active"]  = @([result[@"is_active"] boolValue]);
		if (animation) row[@"animation"] = animation;
		if (staticIcon) row[@"static"] = staticIcon;
		if (completion) completion(row);
	}];
}

- (void)animatedEmojiForEmoji:(NSString *)emoji
                  completion:(void (^)(NSDictionary *))completion {
	if (!emoji.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getAnimatedEmoji", @"emoji" : emoji}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"]){
			if (completion) completion(nil);
			return;
		}
		NSDictionary *info = TGStickerInfo(result[@"sticker"]);
		if (!info){
			if (completion) completion(nil);
			return;
		}
		NSMutableDictionary *row = [info mutableCopy];
		NSDictionary *sound = [result[@"sound"] isKindOfClass:NSDictionary.class]
				? result[@"sound"] : nil;
		row[@"soundId"] = sound[@"id"] ?: @0;
		row[@"fitzpatrick"] = result[@"fitzpatrick_type"] ?: @0;
		row[@"regularEmoji"] = result[@"is_regular_emoji"] ?: @NO;
		if (completion) completion(row);
	}];
}

- (void)customEmojiReactionAnimationsWithCompletion:
		(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getCustomEmojiReactionAnimations"}
	   completion:^(NSDictionary *result){
		NSArray *stickers = [result[@"stickers"] isKindOfClass:NSArray.class]
				? result[@"stickers"] : @[];
		if (completion) completion(TGCustomEmojiStickerList(stickers));
	}];
}

- (void)clearRecentReactionsWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"clearRecentReactions"}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (completion) completion(ok);
	}];
}

- (void)setDefaultReactionEmoji:(NSString *)emoji
                     completion:(void (^)(BOOL))completion {
	if (!emoji.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{
		@"@type"         : @"setDefaultReactionType",
		@"reaction_type" : @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji},
	} completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		// The update says the same thing later; setting it here keeps the
		// picker that asked from flicking back to the old default first.
		if (ok)
			self.reactionDefaultEmoji = emoji;
		else
			NSLog(@"setDefaultReactionType %@: %@", emoji, result[@"message"]);
		if (completion) completion(ok);
	}];
}

#pragma mark - custom emoji

- (void)customEmojiStickersForIds:(NSArray *)ids
					   completion:(void (^)(NSArray *))completion {
	if (!ids.count){
		if (completion) completion(@[]);
		return;
	}
	[self request:@{@"@type" : @"getCustomEmojiStickers",
					@"custom_emoji_ids" : ids}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGCustomEmojiStickerList(result[@"stickers"]));
	}];
}

- (void)defaultProfilePhotoCustomEmojiStickersWithCompletion:
		(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getDefaultProfilePhotoCustomEmojiStickers"}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGCustomEmojiStickerList(result[@"stickers"]));
	}];
}

- (void)defaultChatPhotoCustomEmojiStickersWithCompletion:
		(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getDefaultChatPhotoCustomEmojiStickers"}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGCustomEmojiStickerList(result[@"stickers"]));
	}];
}

- (void)defaultBackgroundCustomEmojiStickersWithCompletion:
		(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getDefaultBackgroundCustomEmojiStickers"}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGCustomEmojiStickerList(result[@"stickers"]));
	}];
}

- (void)greetingStickersWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getGreetingStickers"}
	   completion:^(NSDictionary *result){
		if (completion) completion(TGStickerList(result[@"stickers"]));
	}];
}

- (void)setCustomEmojiStickerSetNamed:(NSString *)name
				   thumbnailCustomEmojiId:(int64_t)customEmojiId
						  completion:(void (^)(BOOL))completion {
	// custom_emoji_id 0 is td_api's "remove the thumbnail", not a missing
	// argument: refusing it would leave a pack unable to clear its picture.
	if (!name.length){
		if (completion) completion(NO);
		return;
	}
	[self request:@{@"@type" : @"setCustomEmojiStickerSetThumbnail",
					@"name" : name,
					@"custom_emoji_id" : @(customEmojiId)}
	   completion:^(NSDictionary *result){
		BOOL ok = ![result[@"@type"] isEqualToString:@"error"];
		if (!ok)
			NSLog(@"setCustomEmojiStickerSetThumbnail %@: %@", name, result[@"message"]);
		if (completion) completion(ok);
	}];
}

- (void)viewTrendingStickerSets:(NSArray *)setIds {
	if (!setIds.count)
		return;
	// Fire and forget: marking a shelf seen changes nothing this screen draws
	// once, and a reordered answer would arrive after the next shelf anyway.
	[self request:@{@"@type" : @"viewTrendingStickerSets",
					@"sticker_set_ids" : setIds}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"viewTrendingStickerSets: %@", result[@"message"]);
	}];
}

- (void)clearRecentStickersAttached:(BOOL)attached {
	[self request:@{@"@type" : @"clearRecentStickers", @"is_attached" : @(attached)}
	   completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"clearRecentStickers: %@", result[@"message"]);
	}];
}

@end
