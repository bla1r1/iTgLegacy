//
// TGClient+Stories.m - the stories wire, from the chat list strip to the live
// story call.
//
// The screens want one dictionary per story and one per row; TDLib sends
// storyInfo, story, storyInteraction and a handful of wrappers around them.
// The flattening lives here so the viewer, the album manager and the search
// list all read the same keys.
//
#import "TGDevice.h"
#import "TGClient+Stories.h"
#import "TGClientInternal.h"

#pragma mark - small helpers

/// TDLib spells an absent object as NSNull, and Objective-C will happily send
/// objectForKeyedSubscript: to it and die. Every nested lookup in this file
/// goes through this so a missing field reads as empty instead.
static NSDictionary *TGStoryDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *TGStoryArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGStoryErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class]
			? message : @"Telegram refused that.";
}

/// TDLib answers every request with @"@type" : @"ok" on success. A few answer
/// an object; those callers check for "error" directly.
static BOOL TGStorySucceeded(NSDictionary *result) {
	return ![result[@"@type"] isEqualToString:@"error"];
}

/// A photo's largest size, or a thumbnail's file. TDLib puts the usable file
/// in a different place for a photo, a chat photo and a video, and every
/// caller here just wants the one id to hand to downloadFile.
static NSNumber *TGStoryPhotoFileId(NSDictionary *photo) {
	if (![photo isKindOfClass:NSDictionary.class])
		return nil;
	NSArray *sizes = photo[@"sizes"];
	if ([sizes isKindOfClass:NSArray.class] && sizes.count){
		NSDictionary *largest = nil;
		for (NSDictionary *size in sizes){
			if (![size isKindOfClass:NSDictionary.class])
				continue;
			if (!largest ||
				[size[@"width"] doubleValue] > [largest[@"width"] doubleValue])
				largest = size;
		}
		NSNumber *fileId = largest[@"photo"][@"id"];
		if ([fileId isKindOfClass:NSNumber.class])
			return fileId;
	}
	NSNumber *fileId = photo[@"file"][@"id"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : nil;
}

static NSNumber *TGStoryChatPhotoFileId(NSDictionary *chat) {
	NSDictionary *photo = chat[@"photo"];
	NSNumber *fileId = photo[@"small"][@"id"];
	if (![fileId isKindOfClass:NSNumber.class])
		fileId = photo[@"big"][@"id"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : nil;
}

/// A video's poster frame is what a list can draw without a decoder.
static NSNumber *TGStoryVideoThumbFileId(NSDictionary *video) {
	NSNumber *fileId = video[@"thumbnail"][@"file"][@"id"];
	if ([fileId isKindOfClass:NSNumber.class])
		return fileId;
	return TGStoryPhotoFileId(video);
}

/// One sender, as every screen in this file spells it.
static NSDictionary *TGStoryFlattenSender(NSDictionary *sender) {
	if (![sender isKindOfClass:NSDictionary.class])
		return @{@"kind" : @"user", @"id" : @(0), @"name" : @""};
	if ([sender[@"@type"] isEqualToString:@"messageSenderChat"]){
		int64_t chatId = [sender[@"chat_id"] longLongValue];
		return @{@"kind" : @"chat", @"id" : @(chatId),
				 @"name" : [[TGClient shared] titleForChat:chatId] ?: @""};
	}
	int64_t userId = [sender[@"user_id"] longLongValue];
	return @{@"kind" : @"user", @"id" : @(userId),
			 @"name" : [[TGClient shared] nameForUserId:userId] ?: @""};
}

/// The privacy filter in the words a list row shows, and back again. TDLib
/// sends five types; this client offers the four a story can be posted with.
static NSString *TGStoryPrivacyName(NSDictionary *privacy) {
	NSString *type = privacy[@"@type"];
	if ([type isEqualToString:@"storyPrivacySettingsEveryone"])
		return @"everyone";
	if ([type isEqualToString:@"storyPrivacySettingsContacts"])
		return @"contacts";
	if ([type isEqualToString:@"storyPrivacySettingsCloseFriends"])
		return @"closeFriends";
	if ([type isEqualToString:@"storyPrivacySettingsSelectedUsers"])
		return @"selected";
	return @"";
}

static NSDictionary *TGStoryPrivacyObject(NSString *privacy, NSArray *userIds) {
	NSArray *ids = [userIds isKindOfClass:NSArray.class] ? userIds : @[];
	if ([privacy isEqualToString:@"contacts"])
		return @{@"@type" : @"storyPrivacySettingsContacts",
				 @"except_user_ids" : ids};
	if ([privacy isEqualToString:@"closeFriends"])
		return @{@"@type" : @"storyPrivacySettingsCloseFriends"};
	if ([privacy isEqualToString:@"selected"])
		return @{@"@type" : @"storyPrivacySettingsSelectedUsers",
				 @"user_ids" : ids};
	return @{@"@type" : @"storyPrivacySettingsEveryone",
			 @"except_user_ids" : ids};
}

/// One reaction as TDLib wants it. nil means "remove", which TDLib spells as
/// a null reaction_type rather than an empty emoji.
static id TGStoryReactionObject(NSString *reaction) {
	if (![reaction isKindOfClass:NSString.class] || !reaction.length)
		return [NSNull null];
	if ([reaction hasPrefix:@"custom:"]){
		NSString *identifier = [reaction substringFromIndex:@"custom:".length];
		long long customId = identifier.longLongValue;
		if (customId > 0)
			return @{@"@type" : @"reactionTypeCustomEmoji",
					 @"custom_emoji_id" : @(customId)};
	}
	return @{@"@type" : @"reactionTypeEmoji", @"emoji" : reaction};
}

static NSArray *TGStoryReactionEmojis(NSArray *reactions) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *reaction in TGStoryArray(reactions)){
		NSDictionary *type = TGStoryDict(reaction[@"type"]);
		if ([type[@"@type"] isEqualToString:@"reactionTypeEmoji"] &&
			[type[@"emoji"] isKindOfClass:NSString.class])
			[out addObject:type[@"emoji"]];
		else if ([type[@"@type"] isEqualToString:@"reactionTypeCustomEmoji"] &&
				 type[@"custom_emoji_id"])
			[out addObject:[NSString stringWithFormat:@"custom:%lld",
					[type[@"custom_emoji_id"] longLongValue]]];
	}
	return out;
}

/// TDLib's statistical graph is either data with a JSON payload, a token to
/// poll, or a sentence saying why there is nothing. The list draws lines and
/// never follows the token: a graph that arrives after the page closed has
/// nowhere to go.
static NSDictionary *TGStoryGraph(NSDictionary *graph) {
	if (![graph isKindOfClass:NSDictionary.class])
		return @{@"kind" : @"none", @"lines" : @[]};
	NSString *type = graph[@"@type"];
	if ([type isEqualToString:@"statisticalGraphData"]){
		NSString *raw = graph[@"json_data"];
		if (![raw isKindOfClass:NSString.class])
			raw = @"";
		id parsed = nil;
		NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
		if (data.length)
			parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		NSMutableArray *lines = [NSMutableArray array];
		if ([parsed isKindOfClass:NSDictionary.class]){
			NSArray *points = parsed[@"points"];
			if ([points isKindOfClass:NSArray.class] && points.count){
				double peak = 0;
				for (NSDictionary *point in points){
					double y = [point[@"y"] doubleValue];
					if (fabs(y) > peak)
						peak = fabs(y);
				}
				[lines addObject:[NSString stringWithFormat:@"%lu points",
						(unsigned long)points.count]];
				NSUInteger shown = MIN(points.count, (NSUInteger)60);
				for (NSUInteger i = 0; i < shown; i++){
					NSDictionary *point = points[i];
					double x = [point[@"x"] doubleValue];
					double y = [point[@"y"] doubleValue];
					NSUInteger bars = peak > 0
							? (NSUInteger)lround((fabs(y) / peak) * 20.0) : 0;
					NSMutableString *bar = [NSMutableString string];
					for (NSUInteger b = 0; b < bars; b++)
						[bar appendString:@"#"];
					[lines addObject:[NSString stringWithFormat:@"%lld %@ %g",
							(long long)x, bar, y]];
				}
			}
		}
		return @{@"kind" : @"data", @"lines" : lines, @"raw" : raw};
	}
	if ([type isEqualToString:@"statisticalGraphAsync"])
		return @{@"kind" : @"async",
				 @"token" : graph[@"token"] ?: @"",
				 @"lines" : @[@"Telegram is preparing this graph."]};
	if ([type isEqualToString:@"statisticalGraphError"])
		return @{@"kind" : @"error",
				 @"error" : graph[@"error"] ?: @"No statistics.",
				 @"lines" : @[graph[@"error"] ?: @"No statistics."]};
	return @{@"kind" : @"none", @"lines" : @[]};
}

/// One full story, flattened. Every screen in this file reads the same keys,
/// so a story opened from the strip, from an album or from a public search
/// draws the same way.
static NSDictionary *TGStoryFlatten(NSDictionary *story) {
	if (![story isKindOfClass:NSDictionary.class])
		return @{};
	NSDictionary *content = TGStoryDict(story[@"content"]);
	NSString *kind = content[@"@type"];

	NSNumber *photoId = nil, *thumbPhotoId = nil, *videoId = nil;
	double duration = 0;
	NSString *contentKind = @"photo";
	if ([kind isEqualToString:@"storyContentPhoto"]){
		photoId = TGStoryPhotoFileId(content[@"photo"]);
		thumbPhotoId = photoId;
	} else if ([kind isEqualToString:@"storyContentVideo"]){
		contentKind = @"video";
		NSDictionary *video = TGStoryDict(content[@"alternative_video"]);
		if (!video.count)
			video = TGStoryDict(content[@"video"]);
		videoId = TGStoryDict(video[@"video"])[@"id"];
		thumbPhotoId = TGStoryVideoThumbFileId(video);
		photoId = thumbPhotoId;
		duration = [video[@"duration"] doubleValue];
	} else if ([kind isEqualToString:@"storyContentLive"]){
		contentKind = @"live";
	}

	NSDictionary *interactions = TGStoryDict(story[@"interaction_info"]);
	NSDictionary *repost = TGStoryDict(story[@"repost_info"]);
	NSDictionary *origin = TGStoryDict(repost[@"origin"]);
	NSString *chosen = TGStoryReactionEmojis(@[@{@"type" :
			TGStoryDict(story[@"chosen_reaction_type"])}]).firstObject ?: @"";
	NSMutableDictionary *out = [@{
		@"storyId"        : story[@"id"] ?: @(0),
		@"chatId"         : story[@"poster_chat_id"] ?: @(0),
		@"posterKind"     : TGStoryDict(story[@"poster_id"])[@"@type"] ?: @"",
		@"date"           : story[@"date"] ?: @(0),
		@"caption"        : TGStoryDict(story[@"caption"])[@"text"] ?: @"",
		@"contentKind"    : contentKind,
		@"isVideo"        : @([contentKind isEqualToString:@"video"]),
		@"isLive"         : @([contentKind isEqualToString:@"live"]),
		@"groupCallId"    : content[@"group_call_id"] ?: @(0),
		@"isRtmp"         : content[@"is_rtmp_stream"] ?: @NO,
		@"duration"       : @(duration),
		@"viewers"        : interactions[@"view_count"] ?: @(0),
		@"forwards"       : interactions[@"forward_count"] ?: @(0),
		@"reactions"      : interactions[@"reaction_count"] ?: @(0),
		@"chosenReaction" : chosen,
		@"isPostedToChatPage" : story[@"is_posted_to_chat_page"] ?: @NO,
		@"isBeingPosted" : story[@"is_being_posted"] ?: @NO,
		@"isBeingEdited" : story[@"is_being_edited"] ?: @NO,
		@"isEdited"      : story[@"is_edited"] ?: @NO,
		@"canBeDeleted"  : story[@"can_be_deleted"] ?: @NO,
		@"canBeEdited"   : story[@"can_be_edited"] ?: @NO,
		@"canBeForwarded": story[@"can_be_forwarded"] ?: @NO,
		@"canBeReplied"  : story[@"can_be_replied"] ?: @NO,
		@"canBeAddedToAlbum" : story[@"can_be_added_to_album"] ?: @NO,
		@"canSetPrivacySettings" : story[@"can_set_privacy_settings"] ?: @NO,
		@"canToggleIsPostedToChatPage" : story[@"can_toggle_is_posted_to_chat_page"] ?: @NO,
		@"canGetStatistics" : story[@"can_get_statistics"] ?: @NO,
		@"canGetInteractions" : story[@"can_get_interactions"] ?: @NO,
		@"hasExpiredViewers" : story[@"has_expired_viewers"] ?: @NO,
		@"privacy"       : TGStoryPrivacyName(TGStoryDict(story[@"privacy_settings"])),
		@"albumIds"      : TGStoryArray(story[@"album_ids"]),
	} mutableCopy];
	if ([photoId isKindOfClass:NSNumber.class])
		out[@"photoId"] = photoId;
	if ([thumbPhotoId isKindOfClass:NSNumber.class])
		out[@"thumbPhotoId"] = thumbPhotoId;
	if ([videoId isKindOfClass:NSNumber.class])
		out[@"videoId"] = videoId;
	if ([repost isKindOfClass:NSDictionary.class]){
		if ([origin[@"@type"] isEqualToString:@"storyOriginPublicStory"])
			out[@"repostedFrom"] = @{@"chatId" : origin[@"chat_id"] ?: @(0),
									  @"storyId" : origin[@"story_id"] ?: @(0)};
		else if ([origin[@"poster_name"] isKindOfClass:NSString.class])
			out[@"repostedFrom"] = @{@"name" : origin[@"poster_name"]};
	}
	out[@"title"] = [[TGClient shared] titleForChat:[story[@"poster_chat_id"] longLongValue]] ?: @"";
	return out;
}

static NSDictionary *TGStoryFlattenInfo(NSDictionary *info, NSDictionary *active) {
	if (![info isKindOfClass:NSDictionary.class])
		return @{};
	return @{
		@"storyId"   : info[@"story_id"] ?: @(0),
		@"date"      : info[@"date"] ?: @(0),
		@"isLive"    : info[@"is_live"] ?: @NO,
		@"closeFriends" : info[@"is_for_close_friends"] ?: @NO,
		@"chatId"    : active[@"chat_id"] ?: @(0),
	};
}

static NSDictionary *TGStoryFlattenAlbum(NSDictionary *album) {
	if (![album isKindOfClass:NSDictionary.class])
		return @{};
	NSMutableDictionary *out = [@{
		@"albumId" : album[@"id"] ?: @(0),
		@"name"    : album[@"name"] ?: @"",
	} mutableCopy];
	NSNumber *photoId = TGStoryPhotoFileId(album[@"photo_icon"]);
	NSNumber *videoId = TGStoryVideoThumbFileId(album[@"video_icon"]);
	if (photoId)
		out[@"photoFileId"] = photoId;
	if (videoId)
		out[@"videoFileId"] = videoId;
	return out;
}

static NSArray *TGStoryFlattenStoryList(NSDictionary *result) {
	NSArray *stories = result[@"stories"];
	if (![stories isKindOfClass:NSArray.class])
		return @[];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *story in stories)
		if ([story isKindOfClass:NSDictionary.class] &&
			[story[@"@type"] isEqualToString:@"story"])
			[out addObject:TGStoryFlatten(story)];
	return out;
}

@implementation TGClient (Stories)

#pragma mark - the feed

- (void)loadActiveStoriesForList:(NSString *)list
					  completion:(void (^)(BOOL, NSString *))completion {
	NSString *type = [list isEqualToString:@"archive"]
			? @"storyListArchive" : @"storyListMain";
	[self request:@{@"@type" : @"loadActiveStories", @"story_list" : @{@"@type" : type}}
	   completion:^(NSDictionary *result){
		// A 404 here means every active story is already loaded; the strip
		// still gets its rows from the per-chat reads below.
		BOOL failed = [result[@"@type"] isEqualToString:@"error"] &&
				[result[@"code"] integerValue] != 404;
		if (completion)
			completion(!failed, failed ? TGStoryErrorText(result) : nil);
	}];
}

/// updateChatActiveStories is the strip's real feed: loadActiveStories turns
/// the cache on, and every chat with something to watch then arrives here.
/// Reading only the first sixty chats missed a contact whose story sat below
/// them, which is why the strip could look empty while Telegram had stories.
- (void)applyChatActiveStoriesUpdate:(NSDictionary *)update {
	NSDictionary *active = [update[@"active_stories"] isKindOfClass:NSDictionary.class]
			? update[@"active_stories"] : nil;
	if (!active)
		return;
	int64_t chatId = [active[@"chat_id"] longLongValue];
	if (!chatId)
		return;
	NSArray *infos = [active[@"stories"] isKindOfClass:NSArray.class]
			? active[@"stories"] : @[];
	NSString *listType = TGStoryDict(active[@"list"])[@"@type"];
	if (!infos.count){
		if ([listType isEqualToString:@"storyListMain"])
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGStoriesChangedNotification object:self
								userInfo:@{@"chatId" : @(chatId), @"remove" : @YES}];
		return;
	}
	if (![listType isEqualToString:@"storyListMain"])
		return;

	NSMutableArray *stories = [NSMutableArray array];
	BOOL live = NO;
	int32_t maxRead = [active[@"max_read_story_id"] intValue];
	int32_t newest = 0;
	for (NSDictionary *info in infos){
		[stories addObject:TGStoryFlattenInfo(info, active)];
		int32_t storyId = [info[@"story_id"] intValue];
		if (storyId > newest)
			newest = storyId;
		if ([info[@"is_live"] boolValue])
			live = YES;
	}
	NSDictionary *chat = nil;
	for (NSDictionary *candidate in self.chats)
		if ([candidate[@"id"] longLongValue] == chatId){
			chat = candidate;
			break;
		}
	NSNumber *photoId = chat[@"photoFileId"] ?: TGStoryChatPhotoFileId(chat);
	NSMutableDictionary *row = [@{
		@"chatId"        : @(chatId),
		@"title"         : [[TGClient shared] titleForChat:chatId]
				?: chat[@"title"] ?: @"",
		@"isOwn"         : @(chatId == [[TGClient shared] savedMessagesChatId]),
		@"unread"        : @(newest > maxRead),
		@"isLive"        : @(live),
		@"maxReadStoryId": @(maxRead),
		@"order"         : active[@"order"] ?: @(0),
		@"canBeArchived" : active[@"can_be_archived"] ?: @NO,
		@"list"          : @"main",
		@"stories"       : stories,
	} mutableCopy];
	if ([photoId isKindOfClass:NSNumber.class])
		row[@"photoFileId"] = photoId;
	[[NSNotificationCenter defaultCenter] postNotificationName:TGStoriesChangedNotification
			object:self userInfo:@{@"row" : row}];

	// The update can arrive before the chat or the user behind a private
	// chat has been described, leaving a row with no name to draw. Ask for
	// the record once and post the row again when it lands.
	if (![row[@"title"] isKindOfClass:NSString.class] || ![row[@"title"] length]){
		[[TGClient shared] chatRecordForChat:chatId completion:^(NSDictionary *chat){
			if (!chat)
				return;
			NSMutableDictionary *fixed = [row mutableCopy];
			NSString *title = chat[@"title"];
			if ([title isKindOfClass:NSString.class] && title.length)
				fixed[@"title"] = title;
			NSNumber *photo = chat[@"photo"][@"small"][@"id"];
			if (photo)
				fixed[@"photoFileId"] = photo;
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGStoriesChangedNotification object:self
								userInfo:@{@"row" : fixed}];
		}];
	}
}

/// A story changed in place, for an open viewer. The strip's row is kept by
/// updateChatActiveStories; asking for the row here as well would be one request
/// per story, and loading a list of stories can bring many of these at once.
- (void)applyStoryUpdate:(NSDictionary *)update {
	NSDictionary *story = [update[@"story"] isKindOfClass:NSDictionary.class]
			? update[@"story"] : nil;
	int64_t chatId = [story[@"poster_chat_id"] longLongValue];
	if (!chatId)
		return;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGStoriesChangedNotification object:self
						userInfo:@{@"chatId" : @(chatId), @"story" : TGStoryFlatten(story)}];
}

/// The story is gone, for an open viewer, which drops it by id.
- (void)applyStoryDeletedUpdate:(NSDictionary *)update {
	int64_t chatId = [update[@"story_poster_chat_id"] longLongValue];
	if (!chatId)
		return;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGStoriesChangedNotification object:self
						userInfo:@{@"chatId" : @(chatId),
								   @"deletedStoryId" : @([update[@"story_id"] intValue])}];
}

/// postStory answers with a story that is still being posted; this is the
/// server saying it finished, or why it did not. One notification because the
/// composer only has to clear its button and say one sentence.
- (void)applyStoryPostUpdate:(NSDictionary *)update {
	BOOL ok = [update[@"@type"] isEqualToString:@"updateStoryPostSucceeded"];
	NSDictionary *story = [update[@"story"] isKindOfClass:NSDictionary.class]
			? update[@"story"] : nil;
	NSNumber *chatId = story[@"poster_chat_id"] ?: update[@"story_poster_chat_id"] ?: @(0);
	NSNumber *storyId = story[@"id"] ?: update[@"story_id"] ?: update[@"old_story_id"] ?: @(0);
	NSMutableDictionary *info = [@{
		@"ok"      : @(ok),
		@"chatId"  : chatId,
		@"storyId" : storyId,
	} mutableCopy];
	if (story)
		info[@"story"] = TGStoryFlatten(story);
	if (!ok){
		NSDictionary *error = [update[@"error"] isKindOfClass:NSDictionary.class]
				? update[@"error"] : @{};
		NSString *message = [error[@"message"] isKindOfClass:NSString.class]
				? error[@"message"] : @"Telegram could not post the story.";
		info[@"error"] = message;
	}
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGStoryPostFinishedNotification object:self
						userInfo:info];
}

- (void)applyStoryListChatCountUpdate:(NSDictionary *)update {
	NSString *listType = TGStoryDict(update[@"story_list"])[@"@type"];
	NSInteger count = [update[@"chat_count"] integerValue];
	if ([listType isEqualToString:@"storyListArchive"])
		self.storyArchiveListChatCount = count;
	else if ([listType isEqualToString:@"storyListMain"])
		self.storyMainListChatCount = count;
}

- (NSInteger)storyListChatCountForList:(NSString *)list {
	if ([list isEqualToString:@"archive"])
		return self.storyArchiveListChatCount;
	return self.storyMainListChatCount;
}

- (void)applyStoryStealthModeUpdate:(NSDictionary *)update {
	self.storyStealthModeValue = @{
		@"activeUntilDate"   : update[@"active_until_date"] ?: @(0),
		@"cooldownUntilDate" : update[@"cooldown_until_date"] ?: @(0),
	};
}

- (NSDictionary *)storyStealthMode {
	return self.storyStealthModeValue;
}

- (void)activeStoryRowForChat:(int64_t)chatId
				   completion:(void (^)(NSDictionary *))completion {
	if (!chatId){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getChatActiveStories", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"chatActiveStories"]){
			if (completion) completion(nil);
			return;
		}
		NSArray *infos = [result[@"stories"] isKindOfClass:NSArray.class]
				? result[@"stories"] : @[];
		if (!infos.count){
			if (completion) completion(nil);
			return;
		}
		NSMutableArray *stories = [NSMutableArray array];
		BOOL live = NO;
		int32_t maxRead = [result[@"max_read_story_id"] intValue];
		int32_t newest = 0;
		for (NSDictionary *info in infos){
			[stories addObject:TGStoryFlattenInfo(info, result)];
			int32_t storyId = [info[@"story_id"] intValue];
			if (storyId > newest)
				newest = storyId;
			if ([info[@"is_live"] boolValue])
				live = YES;
		}
		NSString *listName = @"";
		NSString *listType = TGStoryDict(result[@"list"])[@"@type"];
		if ([listType isEqualToString:@"storyListMain"])
			listName = @"main";
		else if ([listType isEqualToString:@"storyListArchive"])
			listName = @"archive";
		NSDictionary *chat = nil;
		for (NSDictionary *candidate in self.chats)
			if ([candidate[@"id"] longLongValue] == chatId){
				chat = candidate;
				break;
			}
		NSNumber *photoId = chat[@"photoFileId"] ?: TGStoryChatPhotoFileId(chat);
		NSMutableDictionary *row = [@{
			@"chatId"        : @(chatId),
			@"title"         : [[TGClient shared] titleForChat:chatId]
					?: chat[@"title"] ?: @"",
			@"isOwn"         : @(chatId == [[TGClient shared] savedMessagesChatId]),
			@"unread"        : @(newest > maxRead),
			@"isLive"        : @(live),
			@"maxReadStoryId": @(maxRead),
			@"order"         : result[@"order"] ?: @(0),
			@"canBeArchived" : result[@"can_be_archived"] ?: @NO,
			@"list"          : listName,
			@"stories"       : stories,
		} mutableCopy];
		if ([photoId isKindOfClass:NSNumber.class])
			row[@"photoFileId"] = photoId;
		if (completion) completion(row);
	}];
}

NSUInteger TGStoryRowProbeLimit(TGDeviceTier tier) {
	// A round trip per chat: 60 cover every account with stories near the top,
	// and on the A4's one core 74 of them at launch sit in front of everything
	// else, so it asks about a screenful.
	return tier == TGDeviceTierVintage ? 12 : 60;
}

- (void)activeStoryRowsForList:(NSString *)list
					completion:(void (^)(NSArray *))completion {
	NSArray *knownChats = self.chats ?: @[];
	int64_t savedId = [[TGClient shared] savedMessagesChatId];
	NSMutableArray *ids = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	if (savedId){
		[ids addObject:@(savedId)];
		[seen addObject:@(savedId)];
	}
	// The strip is a first screen, not an archive walk, and
	// updateChatActiveStories is its real feed: this only fills it sooner.
	NSUInteger probes = TGStoryRowProbeLimit([TGDevice tier]);
	for (NSDictionary *chat in knownChats){
		if (ids.count >= probes)
			break;
		NSNumber *chatId = chat[@"id"];
		if (![chatId isKindOfClass:NSNumber.class] || [seen containsObject:chatId])
			continue;
		[seen addObject:chatId];
		[ids addObject:chatId];
	}

	__weak typeof(self) weakSelf = self;
	[self loadActiveStoriesForList:list completion:^(BOOL ok, NSString *error){
		TGClient *me = weakSelf;
		if (!me)
			return;
		if (!ids.count){
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		__block NSUInteger outstanding = ids.count;
		for (NSNumber *chatId in ids){
			[me activeStoryRowForChat:chatId.longLongValue
						   completion:^(NSDictionary *row){
				if (row)
					[rows addObject:row];
				if (--outstanding == 0){
					[rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,
																  NSDictionary *b){
						NSComparisonResult byOrder = [b[@"order"] compare:a[@"order"]];
						if (byOrder != NSOrderedSame)
							return byOrder;
						return [b[@"chatId"] compare:a[@"chatId"]];
					}];
					if (completion)
						completion(rows);
				}
			}];
		}
	}];
}

- (void)setActiveStoriesList:(NSString *)list
					 forChat:(int64_t)chatId
				  completion:(void (^)(BOOL, NSString *))completion {
	NSString *type = [list isEqualToString:@"archive"]
			? @"storyListArchive" : @"storyListMain";
	[self request:@{@"@type" : @"setChatActiveStoriesList",
					@"chat_id" : @(chatId),
					@"story_list" : @{@"@type" : type}}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)setPinnedStoryIds:(NSArray *)storyIds
				   inChat:(int64_t)chatId
			   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"setChatPinnedStories",
					@"chat_id" : @(chatId),
					@"story_ids" : storyIds ?: @[]}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)archivedStoriesForChat:(int64_t)chatId
					completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getChatArchivedStories",
					@"chat_id" : @(chatId),
					@"from_story_id" : @(0),
					@"limit" : @(60)}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *story in TGStoryArray(result[@"stories"]))
			if ([story isKindOfClass:NSDictionary.class])
				[out addObject:TGFlattenStory(story)];
		if (completion)
			completion(out);
	}];
}

- (void)archivedStoryIdsForChat:(int64_t)chatId
					 fromStoryId:(int32_t)fromStoryId
						  limit:(NSInteger)limit
					 completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getChatArchivedStories",
					@"chat_id" : @(chatId),
					@"from_story_id" : @(fromStoryId),
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"stories"]){
			if (completion)
				completion(@[], TGStoryErrorText(result));
			return;
		}
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *story in TGStoryArray(result[@"stories"]))
			if ([story isKindOfClass:NSDictionary.class] && story[@"id"])
				[ids addObject:story[@"id"]];
		if (completion)
			completion(ids, nil);
	}];
}

- (void)story:(int32_t)storyId
	  fromChat:(int64_t)chatId
  completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"only_local" : @NO}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"story"]){
			if (completion) completion(nil);
			return;
		}
		if (completion) completion(TGStoryFlatten(result));
	}];
}

#pragma mark - viewing

- (void)openStory:(int32_t)storyId
		  fromChat:(int64_t)chatId
	   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"openStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)closeStory:(int32_t)storyId
		  fromChat:(int64_t)chatId
	   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"closeStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)storyAvailableReactionsWithCompletion:
		(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getStoryAvailableReactions", @"row_size" : @(25)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"availableReactions"]){
			if (completion) completion(nil);
			return;
		}
		NSString *reason = nil;
		NSDictionary *unavailable = result[@"unavailability_reason"];
		if ([unavailable isKindOfClass:NSDictionary.class]){
			reason = unavailable[@"@type"];
			if ([reason isEqualToString:@"reactionUnavailabilityReasonPremium"])
				reason = @"Telegram Premium is needed for story reactions.";
			else if ([reason isEqualToString:@"reactionUnavailabilityReasonAppNotUpdated"])
				reason = @"This Telegram version is too old for story reactions.";
			else if (reason.length)
				reason = @"Telegram is not offering story reactions right now.";
		}
		NSDictionary *out = @{
			@"emojis"    : TGStoryReactionEmojis(result[@"top_reactions"]),
			@"recent"    : TGStoryReactionEmojis(result[@"recent_reactions"]),
			@"popular"   : TGStoryReactionEmojis(result[@"popular_reactions"]),
			@"allowCustom" : result[@"allow_custom_emoji"] ?: @NO,
			@"unavailable" : reason ?: @"",
		};
		if (completion) completion(out);
	}];
}

- (void)setStoryReaction:(NSString *)emoji
				  onStory:(int32_t)storyId
				 fromChat:(int64_t)chatId
			  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"setStoryReaction",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"reaction_type" : TGStoryReactionObject(emoji),
					@"update_recent_reactions" : @YES}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

#pragma mark - posting and editing

- (void)canPostStoryInChat:(int64_t)chatId
				completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"canPostStory", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		NSString *type = result[@"@type"];
		if ([type isEqualToString:@"error"]){
			if (completion)
				completion(@{@"ok" : @NO,
							 @"reason" : TGStoryErrorText(result),
							 @"type" : @"error"});
			return;
		}
		NSMutableDictionary *out = [@{
			@"ok" : @([type isEqualToString:@"canPostStoryResultOk"]),
			@"type" : type ?: @"",
			@"storyCount" : result[@"story_count"] ?: @(0),
			@"retryAfter" : result[@"retry_after"] ?: @(0),
			@"storyId" : result[@"story_id"] ?: @(0),
		} mutableCopy];
		if ([type isEqualToString:@"canPostStoryResultOk"])
			out[@"reason"] = @"";
		else if ([type isEqualToString:@"canPostStoryResultPremiumNeeded"])
			out[@"reason"] = @"Telegram Premium is needed to post more stories.";
		else if ([type isEqualToString:@"canPostStoryResultBoostNeeded"])
			out[@"reason"] = @"This chat has to be boosted before it can post another story.";
		else if ([type isEqualToString:@"canPostStoryResultActiveStoryLimitExceeded"])
			out[@"reason"] = @"Too many active stories. Delete one or wait for the oldest to expire.";
		else if ([type isEqualToString:@"canPostStoryResultWeeklyLimitExceeded"])
			out[@"reason"] = @"The weekly story limit is reached.";
		else if ([type isEqualToString:@"canPostStoryResultMonthlyLimitExceeded"])
			out[@"reason"] = @"The monthly story limit is reached.";
		else if ([type isEqualToString:@"canPostStoryResultLiveStoryIsActive"])
			out[@"reason"] = @"A live story is already running. Delete it first.";
		else
			out[@"reason"] = @"Telegram did not say why this story cannot be posted.";
		if (completion) completion(out);
	}];
}

- (void)chatsToPostStoriesWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChatsToPostStories"}
	   completion:^(NSDictionary *result){
		NSArray *chatIds = result[@"chat_ids"];
		if (![chatIds isKindOfClass:NSArray.class] || !chatIds.count){
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *chats = [NSMutableArray array];
		__block NSUInteger outstanding = MIN(chatIds.count, (NSUInteger)50);
		for (NSNumber *chatId in [chatIds subarrayWithRange:
				NSMakeRange(0, MIN(chatIds.count, (NSUInteger)50))]){
			[weakSelf request:@{@"@type" : @"getChat", @"chat_id" : chatId}
				   completion:^(NSDictionary *chat){
				if ([chat[@"@type"] isEqualToString:@"chat"]){
					NSMutableDictionary *row = [@{
						@"id" : chat[@"id"] ?: @(0),
						@"title" : chat[@"title"] ?: @"",
						@"isChannel" : @([chat[@"type"][@"@type"]
								isEqualToString:@"chatTypeSupergroup"] &&
								[chat[@"type"][@"is_channel"] boolValue]),
					} mutableCopy];
					NSNumber *photoId = TGStoryChatPhotoFileId(chat);
					if (photoId)
						row[@"photoFileId"] = photoId;
					[chats addObject:row];
				}
				if (--outstanding == 0){
					[chats sortUsingComparator:^NSComparisonResult(NSDictionary *a,
																  NSDictionary *b){
						return [a[@"title"] compare:b[@"title"]];
					}];
					if (completion) completion(chats);
				}
			}];
		}
	}];
}

- (void)postStoryToChat:(int64_t)chatId
				   path:(NSString *)path
				isVideo:(BOOL)isVideo
			   duration:(double)duration
				caption:(NSString *)caption
				privacy:(NSString *)privacy
				 userIds:(NSArray *)userIds
		   activePeriod:(NSInteger)seconds
		postedToChatPage:(BOOL)postedToChatPage
		  protectContent:(BOOL)protectContent
				albumIds:(NSArray *)albumIds
			 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId || !path.length){
		if (completion)
			completion(nil, @"Pick a picture or a video first.");
		return;
	}
	NSDictionary *content = nil;
	if (isVideo)
		content = @{@"@type" : @"inputStoryContentVideo",
					@"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
					@"added_sticker_file_ids" : @[],
					@"duration" : @(duration > 0 ? duration : 1),
					@"cover_frame_timestamp" : @(0),
					@"is_animation" : @NO};
	else
		content = @{@"@type" : @"inputStoryContentPhoto",
					@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
					@"added_sticker_file_ids" : @[]};

	id captionObject = caption.length
			? @{@"@type" : @"formattedText", @"text" : caption, @"entities" : @[]}
			: [NSNull null];
	NSInteger period = (seconds == 21600 || seconds == 43200 ||
						seconds == 86400 || seconds == 172800)
			? seconds : 86400;
	NSMutableDictionary *request = [@{
		@"@type" : @"postStory",
		@"chat_id" : @(chatId),
		@"content" : content,
		@"areas" : [NSNull null],
		@"caption" : captionObject,
		@"privacy_settings" : TGStoryPrivacyObject(privacy, userIds),
		@"album_ids" : albumIds ?: @[],
		@"active_period" : @(period),
		@"from_story_full_id" : [NSNull null],
		@"is_posted_to_chat_page" : @(postedToChatPage),
		@"protect_content" : @(protectContent),
	} mutableCopy];
	[self request:request completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"story"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion)
			completion(TGStoryFlatten(result), nil);
	}];
}

- (void)editStory:(int32_t)storyId
		  fromChat:(int64_t)chatId
			  path:(NSString *)path
		 isVideo:(BOOL)isVideo
		duration:(double)duration
		 caption:(NSString *)caption
	  completion:(void (^)(BOOL, NSString *))completion {
	id content = [NSNull null];
	if (path.length){
		if (isVideo)
			content = @{@"@type" : @"inputStoryContentVideo",
						@"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
						@"added_sticker_file_ids" : @[],
						@"duration" : @(duration > 0 ? duration : 1),
						@"cover_frame_timestamp" : @(0),
						@"is_animation" : @NO};
		else
			content = @{@"@type" : @"inputStoryContentPhoto",
						@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
						@"added_sticker_file_ids" : @[]};
	}
	id captionObject = [NSNull null];
	if ([caption isKindOfClass:NSString.class])
		captionObject = @{@"@type" : @"formattedText",
						  @"text" : caption,
						  @"entities" : @[]};
	[self request:@{@"@type" : @"editStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"content" : content,
					@"areas" : [NSNull null],
					@"caption" : captionObject}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)editStoryCover:(int32_t)storyId
			  fromChat:(int64_t)chatId
	  coverTimestamp:(double)timestamp
		  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"editStoryCover",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"cover_frame_timestamp" : @(timestamp)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)deleteStory:(int32_t)storyId
		   fromChat:(int64_t)chatId
		 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"deleteStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)toggleStory:(int32_t)storyId
			 fromChat:(int64_t)chatId
	  postedToChatPage:(BOOL)posted
		  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"toggleStoryIsPostedToChatPage",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"is_posted_to_chat_page" : @(posted)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)setStoryPrivacySettings:(int32_t)storyId
						privacy:(NSString *)privacy
						userIds:(NSArray *)userIds
					 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"setStoryPrivacySettings",
					@"story_id" : @(storyId),
					@"privacy_settings" : TGStoryPrivacyObject(privacy, userIds)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)deleteBusinessStory:(int32_t)storyId
				   fromChat:(int64_t)chatId
				 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"deleteBusinessStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)editBusinessStory:(int32_t)storyId
				 fromChat:(int64_t)chatId
					 path:(NSString *)path
				  isVideo:(BOOL)isVideo
				 duration:(double)duration
				  caption:(NSString *)caption
			   completion:(void (^)(BOOL, NSString *))completion {
	id content = [NSNull null];
	if (path.length){
		if (isVideo)
			content = @{@"@type" : @"inputStoryContentVideo",
						@"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
						@"added_sticker_file_ids" : @[],
						@"duration" : @(duration > 0 ? duration : 1),
						@"cover_frame_timestamp" : @(0),
						@"is_animation" : @NO};
		else
			content = @{@"@type" : @"inputStoryContentPhoto",
						@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
						@"added_sticker_file_ids" : @[]};
	}
	id captionObject = [NSNull null];
	if ([caption isKindOfClass:NSString.class])
		captionObject = @{@"@type" : @"formattedText",
						  @"text" : caption,
						  @"entities" : @[]};
	[self request:@{@"@type" : @"editBusinessStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"content" : content,
					@"areas" : [NSNull null],
					@"caption" : captionObject}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

#pragma mark - albums

- (void)storyAlbumsForChat:(int64_t)chatId
				completion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getChatStoryAlbums", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		NSArray *albums = result[@"albums"];
		if (![albums isKindOfClass:NSArray.class]){
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *album in albums)
			if ([album isKindOfClass:NSDictionary.class])
				[out addObject:TGStoryFlattenAlbum(album)];
		if (completion) completion(out);
	}];
}

- (void)createStoryAlbumNamed:(NSString *)name
					   inChat:(int64_t)chatId
					 storyIds:(NSArray *)storyIds
				   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!name.length){
		if (completion) completion(nil, @"An album needs a name.");
		return;
	}
	[self request:@{@"@type" : @"createStoryAlbum",
					@"story_poster_chat_id" : @(chatId),
					@"name" : name,
					@"story_ids" : storyIds ?: @[]}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"storyAlbum"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(TGStoryFlattenAlbum(result), nil);
	}];
}

- (void)deleteStoryAlbum:(int32_t)albumId
				  inChat:(int64_t)chatId
			  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"deleteStoryAlbum",
					@"chat_id" : @(chatId),
					@"story_album_id" : @(albumId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)setStoryAlbumName:(NSString *)name
				  albumId:(int32_t)albumId
				   inChat:(int64_t)chatId
			   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!name.length){
		if (completion) completion(nil, @"An album needs a name.");
		return;
	}
	[self request:@{@"@type" : @"setStoryAlbumName",
					@"chat_id" : @(chatId),
					@"story_album_id" : @(albumId),
					@"name" : name}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"storyAlbum"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(TGStoryFlattenAlbum(result), nil);
	}];
}

- (void)reorderStoryAlbums:(NSArray *)albumIds
					inChat:(int64_t)chatId
				completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"reorderStoryAlbums",
					@"chat_id" : @(chatId),
					@"story_album_ids" : albumIds ?: @[]}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)storiesInAlbum:(int32_t)albumId
				inChat:(int64_t)chatId
				offset:(NSInteger)offset
				 limit:(NSInteger)limit
			completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getStoryAlbumStories",
					@"chat_id" : @(chatId),
					@"story_album_id" : @(albumId),
					@"offset" : @(offset),
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"stories"]){
			if (completion)
				completion(@[], TGStoryErrorText(result));
			return;
		}
		if (completion) completion(TGStoryFlattenStoryList(result), nil);
	}];
}

- (void)addStories:(NSArray *)storyIds
		 toAlbum:(int32_t)albumId
			inChat:(int64_t)chatId
		completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!storyIds.count){
		if (completion) completion(nil, @"Pick at least one story.");
		return;
	}
	[self request:@{@"@type" : @"addStoryAlbumStories",
					@"chat_id" : @(chatId),
					@"story_album_id" : @(albumId),
					@"story_ids" : storyIds}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"storyAlbum"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(TGStoryFlattenAlbum(result), nil);
	}];
}

- (void)removeStories:(NSArray *)storyIds
		 fromAlbum:(int32_t)albumId
			 inChat:(int64_t)chatId
		 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!storyIds.count){
		if (completion) completion(nil, @"Pick at least one story.");
		return;
	}
	[self request:@{@"@type" : @"removeStoryAlbumStories",
					@"chat_id" : @(chatId),
					@"story_album_id" : @(albumId),
					@"story_ids" : storyIds}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"storyAlbum"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(TGStoryFlattenAlbum(result), nil);
	}];
}

- (void)reorderStories:(NSArray *)storyIds
			 inAlbum:(int32_t)albumId
				inChat:(int64_t)chatId
			completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!storyIds.count){
		if (completion) completion(nil, @"Pick at least one story.");
		return;
	}
	[self request:@{@"@type" : @"reorderStoryAlbumStories",
					@"chat_id" : @(chatId),
					@"story_album_id" : @(albumId),
					@"story_ids" : storyIds}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"storyAlbum"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(TGStoryFlattenAlbum(result), nil);
	}];
}

#pragma mark - interactions and statistics

static NSDictionary *TGStoryInteractionPage(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"storyInteractions"])
		return nil;
	NSMutableArray *rows = [NSMutableArray array];
	NSArray *interactions = [result[@"interactions"] isKindOfClass:NSArray.class]
			? result[@"interactions"] : @[];
	for (NSDictionary *interaction in interactions){
		if (![interaction isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *actor = TGStoryFlattenSender(interaction[@"actor_id"]);
		NSDictionary *type = TGStoryDict(interaction[@"type"]);
		NSString *kind = @"view";
		NSString *reaction = @"";
		NSString *detail = @"";
		if ([type[@"@type"] isEqualToString:@"storyInteractionTypeForward"]){
			kind = @"forward";
			NSDictionary *message = TGStoryDict(type[@"message"]);
			detail = TGStoryDict(TGStoryDict(message[@"content"])[@"caption"])[@"text"]
					?: TGStoryDict(TGStoryDict(message[@"content"])[@"text"])[@"text"] ?: @"";
			if (!detail.length)
				detail = [[TGClient shared] titleForChat:
						[message[@"chat_id"] longLongValue]] ?: @"";
		} else if ([type[@"@type"] isEqualToString:@"storyInteractionTypeRepost"]){
			kind = @"repost";
			NSDictionary *story = TGStoryDict(type[@"story"]);
			detail = TGStoryDict(story[@"caption"])[@"text"] ?: @"";
		} else {
			reaction = TGStoryReactionEmojis(@[@{@"type" :
					TGStoryDict(type[@"chosen_reaction_type"])}]).firstObject ?: @"";
		}
		NSMutableDictionary *row = [@{
			@"kind" : kind,
			@"actorKind" : actor[@"kind"],
			@"actorId" : actor[@"id"],
			@"name" : actor[@"name"],
			@"date" : interaction[@"interaction_date"] ?: @(0),
			@"reaction" : reaction,
			@"detail" : detail,
		} mutableCopy];
		[rows addObject:row];
	}
	return @{
		@"totalCount" : result[@"total_count"] ?: @(0),
		@"totalForwardCount" : result[@"total_forward_count"] ?: @(0),
		@"totalReactionCount" : result[@"total_reaction_count"] ?: @(0),
		@"nextOffset" : result[@"next_offset"] ?: @"",
		@"interactions" : rows,
	};
}

- (void)storyInteractionsForStory:(int32_t)storyId
							query:(NSString *)query
					 onlyContacts:(BOOL)onlyContacts
					preferForwards:(BOOL)preferForwards
				preferWithReaction:(BOOL)preferWithReaction
							 offset:(NSString *)offset
							  limit:(NSInteger)limit
						 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getStoryInteractions",
					@"story_id" : @(storyId),
					@"query" : query ?: @"",
					@"only_contacts" : @(onlyContacts),
					@"prefer_forwards" : @(preferForwards),
					@"prefer_with_reaction" : @(preferWithReaction),
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		NSDictionary *page = TGStoryInteractionPage(result);
		if (!page){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(page, nil);
	}];
}

- (void)chatStoryInteractionsForStory:(int32_t)storyId
							  fromChat:(int64_t)chatId
							reactionEmoji:(NSString *)emoji
						   preferForwards:(BOOL)preferForwards
								   offset:(NSString *)offset
									limit:(NSInteger)limit
							   completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getChatStoryInteractions",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"reaction_type" : TGStoryReactionObject(emoji),
					@"prefer_forwards" : @(preferForwards),
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		NSDictionary *page = TGStoryInteractionPage(result);
		if (!page){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(page, nil);
	}];
}

- (void)storyPublicForwards:(int32_t)storyId
					fromChat:(int64_t)chatId
					  offset:(NSString *)offset
					   limit:(NSInteger)limit
				  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getStoryPublicForwards",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"publicForwards"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *forward in TGStoryArray(result[@"forwards"])){
			if (![forward isKindOfClass:NSDictionary.class])
				continue;
			if ([forward[@"@type"] isEqualToString:@"publicForwardMessage"]){
				NSDictionary *message = TGStoryDict(forward[@"message"]);
				NSDictionary *content = TGStoryDict(message[@"content"]);
				NSString *text = TGStoryDict(content[@"text"])[@"text"]
						?: TGStoryDict(content[@"caption"])[@"text"] ?: @"";
				[rows addObject:@{
					@"kind" : @"message",
					@"chatId" : message[@"chat_id"] ?: @(0),
					@"messageId" : message[@"id"] ?: @(0),
					@"title" : [[TGClient shared] titleForChat:
							[message[@"chat_id"] longLongValue]] ?: @"",
					@"text" : text,
					@"date" : message[@"date"] ?: @(0),
				}];
			} else if ([forward[@"@type"] isEqualToString:@"publicForwardStory"]){
				NSDictionary *story = TGStoryFlatten(forward[@"story"]);
				[rows addObject:@{
					@"kind" : @"story",
					@"chatId" : story[@"chatId"] ?: @(0),
					@"storyId" : story[@"storyId"] ?: @(0),
					@"title" : story[@"title"] ?: @"",
					@"text" : story[@"caption"] ?: @"",
					@"date" : story[@"date"] ?: @(0),
					@"story" : story,
				}];
			}
		}
		if (completion)
			completion(@{@"totalCount" : result[@"total_count"] ?: @(0),
						 @"nextOffset" : result[@"next_offset"] ?: @"",
						 @"forwards" : rows}, nil);
	}];
}

- (void)storyStatistics:(int32_t)storyId
			   fromChat:(int64_t)chatId
				 isDark:(BOOL)isDark
			 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getStoryStatistics",
					@"chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"is_dark" : @(isDark)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"storyStatistics"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion)
			completion(@{
				@"interaction" : TGStoryGraph(result[@"story_interaction_graph"]),
				@"reaction" : TGStoryGraph(result[@"story_reaction_graph"]),
			}, nil);
	}];
}

- (void)reportStory:(int32_t)storyId
		   fromChat:(int64_t)chatId
		   optionId:(NSString *)optionId
			   text:(NSString *)text
		 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"reportStory",
					@"story_poster_chat_id" : @(chatId),
					@"story_id" : @(storyId),
					@"option_id" : optionId ?: @"",
					@"text" : text ?: @""}
	   completion:^(NSDictionary *result){
		NSString *type = result[@"@type"];
		if ([type isEqualToString:@"error"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if ([type isEqualToString:@"reportStoryResultOk"]){
			if (completion) completion(@{@"state" : @"ok"}, nil);
			return;
		}
		if ([type isEqualToString:@"reportStoryResultOptionRequired"]){
			NSMutableArray *options = [NSMutableArray array];
			for (NSDictionary *option in TGStoryArray(result[@"options"]))
				if ([option isKindOfClass:NSDictionary.class])
					[options addObject:@{@"id" : option[@"id"] ?: @"",
										 @"text" : option[@"text"] ?: @""}];
			if (completion)
				completion(@{@"state" : @"options",
							 @"title" : result[@"title"] ?: @"Report Story",
							 @"options" : options}, nil);
			return;
		}
		if ([type isEqualToString:@"reportStoryResultTextRequired"]){
			if (completion)
				completion(@{@"state" : @"text",
							 @"optionId" : result[@"option_id"] ?: @"",
							 @"optional" : result[@"is_optional"] ?: @NO}, nil);
			return;
		}
		if (completion)
			completion(@{@"state" : @"unknown"}, nil);
	}];
}

#pragma mark - notifications

- (void)storyNotificationExceptionsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getStoryNotificationSettingsExceptions"}
	   completion:^(NSDictionary *result){
		NSArray *chatIds = result[@"chat_ids"];
		if (![chatIds isKindOfClass:NSArray.class] || !chatIds.count){
			if (completion) completion(@[]);
			return;
		}
		NSArray *wanted = [chatIds subarrayWithRange:
				NSMakeRange(0, MIN(chatIds.count, (NSUInteger)50))];
		NSMutableArray *rows = [NSMutableArray array];
		__block NSUInteger outstanding = wanted.count;
		for (NSNumber *chatId in wanted){
			[weakSelf request:@{@"@type" : @"getChat", @"chat_id" : chatId}
				   completion:^(NSDictionary *chat){
				if ([chat[@"@type"] isEqualToString:@"chat"]){
					NSDictionary *settings = chat[@"notification_settings"];
					NSMutableDictionary *row = [@{
						@"id" : chat[@"id"] ?: @(0),
						@"title" : chat[@"title"] ?: @"",
						@"muteStories" : settings[@"mute_stories"] ?: @NO,
						@"muteFor" : settings[@"mute_for"] ?: @(0),
					} mutableCopy];
					NSNumber *photoId = TGStoryChatPhotoFileId(chat);
					if (photoId)
						row[@"photoFileId"] = photoId;
					[rows addObject:row];
				}
				if (--outstanding == 0){
					[rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,
																  NSDictionary *b){
						return [a[@"title"] compare:b[@"title"]];
					}];
					if (completion) completion(rows);
				}
			}];
		}
	}];
}

#pragma mark - public discovery

static NSDictionary *TGStoryFoundStoriesPage(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"foundStories"])
		return nil;
	NSMutableArray *stories = [NSMutableArray array];
	for (NSDictionary *story in TGStoryArray(result[@"stories"]))
		if ([story isKindOfClass:NSDictionary.class])
			[stories addObject:TGStoryFlatten(story)];
	return @{
		@"totalCount" : result[@"total_count"] ?: @(0),
		@"nextOffset" : result[@"next_offset"] ?: @"",
		@"stories" : stories,
	};
}

- (void)searchPublicStoriesByTag:(NSString *)tag
						  offset:(NSString *)offset
						   limit:(NSInteger)limit
					  completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *clean = [tag isKindOfClass:NSString.class] ? tag : @"";
	if ([clean hasPrefix:@"#"])
		clean = [clean substringFromIndex:1];
	if (!clean.length){
		if (completion) completion(nil, @"Type a hashtag first.");
		return;
	}
	[self request:@{@"@type" : @"searchPublicStoriesByTag",
					@"story_tag" : clean,
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		NSDictionary *page = TGStoryFoundStoriesPage(result);
		if (!page){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(page, nil);
	}];
}

- (void)searchPublicStoriesByLocation:(NSDictionary *)address
							   offset:(NSString *)offset
								limit:(NSInteger)limit
						   completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *country = address[@"countryCode"] ?: @"";
	NSString *state = address[@"state"] ?: @"";
	NSString *city = address[@"city"] ?: @"";
	NSString *street = address[@"street"] ?: @"";
	if (!country.length && !state.length && !city.length && !street.length){
		if (completion) completion(nil, @"Name a country, city or street.");
		return;
	}
	[self request:@{@"@type" : @"searchPublicStoriesByLocation",
					@"address" : @{@"@type" : @"locationAddress",
								   @"country_code" : country,
								   @"state" : state,
								   @"city" : city,
								   @"street" : street},
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		NSDictionary *page = TGStoryFoundStoriesPage(result);
		if (!page){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(page, nil);
	}];
}

- (void)searchPublicStoriesByVenue:(NSString *)venueProvider
						   venueId:(NSString *)venueId
							offset:(NSString *)offset
							 limit:(NSInteger)limit
						completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!venueProvider.length || !venueId.length){
		if (completion) completion(nil, @"A venue needs its provider and its id.");
		return;
	}
	[self request:@{@"@type" : @"searchPublicStoriesByVenue",
					@"venue_provider" : venueProvider,
					@"venue_id" : venueId,
					@"offset" : offset ?: @"",
					@"limit" : @(limit > 0 ? limit : 20)}
	   completion:^(NSDictionary *result){
		NSDictionary *page = TGStoryFoundStoriesPage(result);
		if (!page){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(page, nil);
	}];
}

#pragma mark - stealth

- (void)activateStoryStealthModeWithCompletion:
		(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"activateStoryStealthMode"}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

#pragma mark - live stories

- (void)startLiveStoryInChat:(int64_t)chatId
					 privacy:(NSString *)privacy
					  userIds:(NSArray *)userIds
			   protectContent:(BOOL)protectContent
					   rtmp:(BOOL)rtmp
			 enableMessages:(BOOL)enableMessages
			  paidMessageStars:(NSInteger)paidMessageStars
				  completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"startLiveStory",
					@"chat_id" : @(chatId),
					@"privacy_settings" : TGStoryPrivacyObject(privacy, userIds),
					@"protect_content" : @(protectContent),
					@"is_rtmp_stream" : @(rtmp),
					@"enable_messages" : @(enableMessages),
					@"paid_message_star_count" : @(MAX(0, paidMessageStars))}
	   completion:^(NSDictionary *result){
		NSString *type = result[@"@type"];
		if ([type isEqualToString:@"startLiveStoryResultOk"]){
			NSDictionary *story = TGStoryFlatten(result[@"story"]);
			if (completion)
				completion(@{@"ok" : @YES, @"story" : story,
							 @"groupCallId" : story[@"groupCallId"] ?: @(0),
							 @"error" : @""});
			return;
		}
		if ([type isEqualToString:@"startLiveStoryResultFail"]){
			NSDictionary *reason = result[@"error_type"];
			NSString *kind = reason[@"@type"] ?: @"";
			NSString *say = @"Telegram refused the live story.";
			if ([kind isEqualToString:@"canPostStoryResultPremiumNeeded"])
				say = @"Telegram Premium is needed to start a live story.";
			else if ([kind isEqualToString:@"canPostStoryResultBoostNeeded"])
				say = @"This chat needs a boost before it can start a live story.";
			else if ([kind isEqualToString:@"canPostStoryResultActiveStoryLimitExceeded"])
				say = @"Too many active stories. Delete one first.";
			else if ([kind isEqualToString:@"canPostStoryResultLiveStoryIsActive"])
				say = @"A live story is already running.";
			if (completion)
				completion(@{@"ok" : @NO, @"error" : say,
							 @"errorType" : kind, @"storyId" :
								 reason[@"story_id"] ?: @(0)});
			return;
		}
		if (completion)
			completion(@{@"ok" : @NO, @"error" : TGStoryErrorText(result)});
	}];
}

- (void)joinLiveStoryCall:(int32_t)groupCallId
			   completion:(void (^)(NSString *, NSString *))completion {
	[self request:@{@"@type" : @"joinLiveStory",
					@"group_call_id" : @(groupCallId),
					@"join_parameters" : @{
						@"@type" : @"groupCallJoinParameters",
						@"audio_source_id" : @(0),
						@"payload" : @"",
						@"is_muted" : @YES,
						@"is_my_video_enabled" : @NO,
					}}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"text"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion) completion(result[@"text"] ?: @"", nil);
	}];
}

- (void)liveStoryStreamerForCall:(int32_t)groupCallId
					  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getLiveStoryStreamer",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"groupCallParticipant"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		NSDictionary *sender = TGStoryFlattenSender(result[@"participant_id"]);
		if (completion)
			completion(@{
				@"kind" : sender[@"kind"],
				@"id" : sender[@"id"],
				@"name" : sender[@"name"],
				@"isCurrentUser" : result[@"is_current_user"] ?: @NO,
				@"isSpeaking" : result[@"is_speaking"] ?: @NO,
				@"isMuted" : result[@"is_muted_for_all_users"] ?: @NO,
				@"bio" : result[@"bio"] ?: @"",
			}, nil);
	}];
}

- (void)liveStoryRtmpUrlForChat:(int64_t)chatId
					 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getLiveStoryRtmpUrl", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"rtmpUrl"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion)
			completion(@{@"url" : result[@"url"] ?: @"",
						 @"streamKey" : result[@"stream_key"] ?: @""}, nil);
	}];
}

- (void)replaceLiveStoryRtmpUrlForChat:(int64_t)chatId
							completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"replaceLiveStoryRtmpUrl", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"rtmpUrl"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		if (completion)
			completion(@{@"url" : result[@"url"] ?: @"",
						 @"streamKey" : result[@"stream_key"] ?: @""}, nil);
	}];
}

- (void)liveStoryAvailableMessageSendersForCall:(int32_t)groupCallId
									 completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getLiveStoryAvailableMessageSenders",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		NSArray *senders = result[@"senders"];
		if (![senders isKindOfClass:NSArray.class]){
			if (completion)
				completion(@[], TGStoryErrorText(result));
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *entry in senders){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *sender = TGStoryFlattenSender(entry[@"sender"]);
			[rows addObject:@{
				@"kind" : sender[@"kind"],
				@"id" : sender[@"id"],
				@"name" : sender[@"name"],
				@"needsPremium" : entry[@"needs_premium"] ?: @NO,
			}];
		}
		if (completion) completion(rows, nil);
	}];
}

- (void)setLiveStoryMessageSender:(NSDictionary *)sender
						  forCall:(int32_t)groupCallId
					   completion:(void (^)(BOOL, NSString *))completion {
	NSString *kind = [sender[@"kind"] isEqualToString:@"chat"] ? @"chat" : @"user";
	int64_t identifier = [sender[@"id"] longLongValue];
	NSDictionary *object = [kind isEqualToString:@"chat"]
			? @{@"@type" : @"messageSenderChat", @"chat_id" : @(identifier)}
			: @{@"@type" : @"messageSenderUser", @"user_id" : @(identifier)};
	[self request:@{@"@type" : @"setLiveStoryMessageSender",
					@"group_call_id" : @(groupCallId),
					@"message_sender_id" : object}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)liveStoryTopDonorsForCall:(int32_t)groupCallId
					   completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getLiveStoryTopDonors",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		if (![result[@"@type"] isEqualToString:@"liveStoryDonors"]){
			if (completion)
				completion(nil, TGStoryErrorText(result));
			return;
		}
		NSMutableArray *donors = [NSMutableArray array];
		for (NSDictionary *entry in TGStoryArray(result[@"top_donors"])){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSDictionary *sender = TGStoryFlattenSender(entry[@"sender_id"]);
			[donors addObject:@{
				@"kind" : sender[@"kind"],
				@"id" : sender[@"id"],
				@"name" : sender[@"name"],
				@"stars" : entry[@"star_count"] ?: @(0),
				@"isTop" : entry[@"is_top"] ?: @NO,
				@"isMe" : entry[@"is_me"] ?: @NO,
				@"isAnonymous" : entry[@"is_anonymous"] ?: @NO,
			}];
		}
		if (completion)
			completion(@{@"totalStarCount" : result[@"total_star_count"] ?: @(0),
						 @"donors" : donors}, nil);
	}];
}

- (void)addPendingLiveStoryReactionInCall:(int32_t)groupCallId
								   stars:(NSInteger)stars
							  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"addPendingLiveStoryReaction",
					@"group_call_id" : @(groupCallId),
					@"star_count" : @(MAX(1, stars))}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)commitPendingLiveStoryReactionsInCall:(int32_t)groupCallId
								   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"commitPendingLiveStoryReactions",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

- (void)removePendingLiveStoryReactionsInCall:(int32_t)groupCallId
								   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"removePendingLiveStoryReactions",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGStorySucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGStoryErrorText(result));
	}];
}

@end
