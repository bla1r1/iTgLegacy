#import "TGClientInternal.h"
#import "TGBase64.h"
#import "TGDatabaseKey.h"
#import "TGOptions.h"
#import "TGCall.h"
#import "TGJson.h"
#include "TGUpdateType.h"
#include <dlfcn.h>
#include "api_id.h"

/// The plain string a folder is named with. tdlib nests the name two levels
/// deep: chatFolderInfo.name is a chatFolderName whose "text" is itself a
/// formattedText, and only THAT "text" is the string. The old chain stopped
/// one level short (B3 - every folder parsed as an empty string), and the
/// pill strip had three nameless tabs to show for it.
NSString *TGPlainTitle(id value){
	while ([value isKindOfClass:NSDictionary.class])
		value = value[@"text"];
	return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *TGFolderTitle(NSDictionary *f){
	NSString *answer = TGPlainTitle(f[@"title"]) ?: TGPlainTitle(f[@"name"]);
	if (!answer.length)
		answer = @"";
	return answer;
}

/// Effect ids arrive as a vector<int64>; over JSON that is either a number or
/// a decimal string. Both are reduced to NSNumber here so every reader can
/// pass one straight back to getMessageEffect.
static NSArray *TGEffectIdList(id value){
	if (![value isKindOfClass:NSArray.class])
		return @[];
	NSMutableArray *ids = [NSMutableArray array];
	for (id raw in value){
		if (![raw isKindOfClass:NSNumber.class] &&
			![raw isKindOfClass:NSString.class])
			continue;
		[ids addObject:@([raw longLongValue])];
	}
	return ids;
}

NSString *const TGChatReadOutboxChangedNotification = @"TGChatReadOutboxChangedNotification";
NSString *const TGChatReplyMarkupChangedNotification = @"TGChatReplyMarkupChangedNotification";
NSString *const TGConnectionStateChangedNotification = @"TGConnectionStateChangedNotification";
NSString *const TGUserStatusChangedNotification = @"TGUserStatusChangedNotification";
NSString *const TGUnreadTotalChangedNotification = @"TGUnreadTotalChangedNotification";
NSString *const TGDownloadsChangedNotification = @"TGDownloadsChangedNotification";
NSString *const TGFullInfoChangedNotification = @"TGFullInfoChangedNotification";
NSString *const TGStickerListsChangedNotification = @"TGStickerListsChangedNotification";
NSString *const TGChatMembersChangedNotification = @"TGChatMembersChangedNotification";
NSString *const TGNotificationSettingsChangedNotification = @"TGNotificationSettingsChangedNotification";
NSString *const TGForumTopicsChangedNotification = @"TGForumTopicsChangedNotification";
NSString *const TGTextCompositionStylesChangedNotification = @"TGTextCompositionStylesChangedNotification";
NSString *const TGDirectMessagesTopicsChangedNotification = @"TGDirectMessagesTopicsChangedNotification";
NSString *const TGStakeDiceStateChangedNotification = @"TGStakeDiceStateChangedNotification";
NSString *const TGApplicationVerificationRequiredNotification = @"TGApplicationVerificationRequiredNotification";
NSString *const TGChatActionBarChangedNotification = @"TGChatActionBarChangedNotification";
NSString *const TGSavedTopicsChangedNotification = @"TGSavedTopicsChangedNotification";
NSString *const TGServiceNotificationReceivedNotification = @"TGServiceNotificationReceivedNotification";
NSString *const TGTermsOfServiceReceivedNotification = @"TGTermsOfServiceReceivedNotification";
NSString *const TGPrivacyRulesChangedNotification = @"TGPrivacyRulesChangedNotification";
NSString *const TGSessionsChangedNotification = @"TGSessionsChangedNotification";
NSString *const TGAccentColorsChangedNotification = @"TGAccentColorsChangedNotification";
NSString *const TGContactCloseBirthdaysChangedNotification = @"TGContactCloseBirthdaysChangedNotification";
NSString *const TGAccountStatusChangedNotification = @"TGAccountStatusChangedNotification";
NSString *const TGAppearanceDefaultsChangedNotification = @"TGAppearanceDefaultsChangedNotification";
NSString *const TGMessageEffectsChangedNotification = @"TGMessageEffectsChangedNotification";
NSString *const TGChatDraftStoppedNotification = @"TGChatDraftStoppedNotification";
NSString *const TGChatVideoPublishedNotification = @"TGChatVideoPublishedNotification";
NSString *const TGActiveNotificationsChangedNotification = @"TGActiveNotificationsChangedNotification";
NSString *const TGAutosaveSettingsChangedNotification = @"TGAutosaveSettingsChangedNotification";
NSString *const TGLanguagePackStringsChangedNotification = @"TGLanguagePackStringsChangedNotification";
NSString *const TGCommunitiesChangedNotification = @"TGCommunitiesChangedNotification";
NSString *const TGStoriesChangedNotification = @"TGStoriesChangedNotification";
NSString *const TGQuickRepliesChangedNotification = @"TGQuickRepliesChangedNotification";
NSString *const TGSuggestedActionsChangedNotification = @"TGSuggestedActionsChangedNotification";

@implementation TGClient

- (NSUInteger)chatsCached {
	return self.chatsById.count;
}

/// The update's emoji, or nil while it has not arrived; the picker keeps its
/// own order then.
- (NSString *)defaultReactionEmoji {
	return self.reactionDefaultEmoji;
}

/// "gif" is the provider every client ships with, and the one the update
/// starts from until Telegram names another.
- (NSString *)animationSearchProvider {
	return self.gifSearchProvider ?: @"gif";
}

- (NSArray *)animationSearchEmojis {
	return self.gifSearchEmojis ?: @[];
}

// The public account-status surface reads the records handleUpdate keeps.
// Each one is nil or empty until its update arrives, never a made-up default:
// the Settings rows have to distinguish "Telegram says none" from "not told".
- (NSDictionary *)freezeState {
	return self.freezeStateValue;
}

- (NSDictionary *)ageVerificationParameters {
	return self.ageVerificationParametersValue;
}

- (NSDictionary *)recaptchaVerificationRequest {
	return self.recaptchaVerificationRequestValue;
}

- (NSDictionary *)subscriptionForUserId:(int64_t)userId {
	id row = self.userSubscriptionsById[@(userId)];
	return [row isKindOfClass:NSDictionary.class] ? row : nil;
}

- (NSArray *)availableMessageEffectIds {
	return self.reactionMessageEffectIds ?: @[];
}

- (NSArray *)availableStickerEffectIds {
	return self.stickerMessageEffectIds ?: @[];
}

- (NSDictionary *)defaultBackground {
	return self.defaultBackgroundValue;
}

- (NSArray *)emojiChatThemes {
	return self.emojiChatThemesValue ?: @[];
}

- (NSDictionary *)stoppedMessageDraft {
	return self.stoppedMessageDraftValue;
}

- (NSDictionary *)publishedVideo {
	return self.publishedVideoValue;
}

// The Saved Messages topics, array-shaped the way the screen reads them:
// pinned rows first, the rest newest activity on top.
- (NSArray *)savedTopics {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *row in self.savedTopicsById.allValues)
		[out addObject:row];
	return [out sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		BOOL pa = [a[@"pinned"] boolValue], pb = [b[@"pinned"] boolValue];
		if (pa != pb)
			return pa ? NSOrderedAscending : NSOrderedDescending;
		id da = a[@"date"], db = b[@"date"];
		long long ta = da ? [da longLongValue] : 0;
		long long tb = db ? [db longLongValue] : 0;
		if (tb > ta)
			return NSOrderedAscending;
		if (tb < ta)
			return NSOrderedDescending;
		return NSOrderedSame;
	}];
}

+ (instancetype)shared {
	static TGClient *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		s = [[TGClient alloc] init];
		s.chatsById = [NSMutableDictionary dictionary];
		s.usersById = [NSMutableDictionary dictionary];
		s.rawUsersById = [[TGObjectLruCache alloc] initWithCapacity:TGRawUserCacheCap];
		s.userPhotosById = [NSMutableDictionary dictionary];
		s.forumSupergroups = [NSMutableDictionary dictionary];
		s.archivedChats = @[];
		s.folders = @[];
		s.chats = @[];
		s.userSubscriptionsById = [NSMutableDictionary dictionary];
		s.outbox = [NSMutableArray array];
		s.pendingRequests = [NSMutableDictionary dictionary];
		s.outboxLock = [[NSLock alloc] init];
		s.updateCoalescer = [[TGUpdateCoalescer alloc] initWithIntervalMs:100];
		__weak TGClient *weakClient = s;
		[s.updateCoalescer setFlushHandler:^(NSSet *dirtyChatIds, NSSet *dirtyUserIds, BOOL orderChanged) {
			TGClient *client = weakClient;
			if (!client) return;
			if (orderChanged || dirtyChatIds.count > 0) {
				[client rebuildChats];
			}
		}];
		// Message-level churn - reaction and view counts - comes out of the
		// same 100 ms window as one nudge per chat, however many messages in
		// it moved. A crowd reacting to a channel post otherwise re-reads the
		// history per reaction.
		[s.updateCoalescer setMessagesHandler:^(NSDictionary *messageIdsByChat) {
			TGClient *client = weakClient;
			if (!client || !client.onMessage) return;
			for (NSNumber *chatId in messageIdsByChat)
				client.onMessage([chatId longLongValue], nil, 0);
		}];
	});
	return s;
}

#pragma mark - lifecycle

- (BOOL)start {
	if (self.running)
		return self.available;

	NSString *path = [[NSBundle mainBundle].bundlePath
			stringByAppendingPathComponent:@"libtdjson.dylib"];

	// armv7 carries TDLib as a dylib beside the binary: linked statically its
	// __TEXT goes past the 16MB a Thumb branch can reach. arm64 has no such
	// limit and no dylib was ever built for it, so there TDLib is linked in
	// and the symbols are already in this image - which is what RTLD_DEFAULT
	// searches. One lookup handles both.
	self.handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
	void *lookup = self.handle ?: RTLD_DEFAULT;
	if (!self.handle)
		NSLog(@"TGClient: no libtdjson.dylib (%s) - looking in the app itself",
				dlerror());

	td_create_fn create = dlsym(lookup, "td_json_client_create");
	td_exec_fn   exec   = dlsym(lookup, "td_json_client_execute");
	self.td_exec = exec;
	self.td_send = dlsym(lookup, "td_json_client_send");
	self.td_recv = dlsym(lookup, "td_json_client_receive");
	if (!create || !self.td_send || !self.td_recv){
		NSLog(@"TGClient: missing td_json_client_* symbols");
		return NO;
	}

	if (exec)
		exec(NULL, "{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":1}");

	self.client = create();
	if (!self.client){
		NSLog(@"TGClient: td_json_client_create returned NULL");
		return NO;
	}

	self.available = YES;
	self.running = YES;

	// The single-threaded ClientManager creates its scheduler lazily, on the
	// first request - without this nothing ever runs and no update arrives.
	// Queued before the thread starts so it goes out on the receive thread.
	[self send:@{@"@type" : @"getAuthorizationState"}];

	// TDLib refuses every language-pack call until a localization target is
	// named, and this client's only target is the one iOS packs carry. The
	// option can be set before sign-in, which is when Settings > Language and
	// the custom-pack editor need it.
	[self send:@{@"@type" : @"setOption",
				@"name" : @"localization_target",
				@"value" : @{@"@type" : @"optionValueString", @"value" : @"ios"}}];

	// TDLib runs single-threaded on armv7 (no thread-local storage), so its
	// scheduler only advances while we are inside td_json_client_receive.
	// Keep one thread parked in it.
	[NSThread detachNewThreadSelector:@selector(receiveLoop) toTarget:self withObject:nil];

	NSLog(@"TGClient: started");
	return YES;
}

- (void)receiveLoop {
	while (self.running){
		@autoreleasepool {
			[self drainOutbox];

			const char *res = self.td_recv(self.client, 1.0);
			if (!res)
				continue;

			NSMutableArray *batch = [NSMutableArray arrayWithCapacity:32];

			NSError *err = nil;
			size_t resLen = strlen(res);
			NSDictionary *obj = TGJsonParseUpdate(res, resLen, &err);
			if ([obj isKindOfClass:NSDictionary.class]){
				[batch addObject:obj];
			} else if (err){
				NSLog(@"TGClient: bad JSON: %@", err);
			}

			// Drain further available updates immediately without waiting
			while (batch.count < 64 && self.running){
				const char *next = self.td_recv(self.client, 0.002);
				if (!next)
					break;
				size_t nextLen = strlen(next);
				NSDictionary *nextObj = TGJsonParseUpdate(next, nextLen, nil);
				if ([nextObj isKindOfClass:NSDictionary.class]){
					[batch addObject:nextObj];
				}
			}

			if (batch.count > 0){
				dispatch_async(dispatch_get_main_queue(), ^{
					[self handleUpdateBatch:batch];
				});
			}
		}
	}

	// Out of the loop means TDLib said it closed. Freeing the client here, on
	// the thread that used it, is what lets the next start make a new one.
	void (*destroy)(void *) = dlsym(self.handle ?: RTLD_DEFAULT, "td_json_client_destroy");
	if (destroy && self.client)
		destroy(self.client);
	self.client = NULL;
	dispatch_async(dispatch_get_main_queue(), ^{ [self clientClosed]; });
}

#pragma mark - background

- (void)pauseForBackground:(void (^)(void))done {
	if (!self.running || self.pausing){
		if (done)
			done();
		return;
	}
	self.pausing = YES;
	self.resumeWanted = NO;
	self.pauseDone = done;
	[self send:@{@"@type" : @"close"}];
}

- (void)resumeFromBackground {
	if (self.pausing){
		self.resumeWanted = YES;      // back before the close finished
		return;
	}
	if (!self.paused)
		return;
	self.paused = NO;
	// A new TDLib instance sends chat positions only for lists asked for again.
	self.chatListComplete = NO;
	self.loadChatsAttempts = 0;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self start];
	});
}

- (void)clientClosed {
	if (!self.pausing)
		return;
	self.pausing = NO;
	self.paused = YES;
	void (^done)(void) = self.pauseDone;
	self.pauseDone = nil;
	if (self.resumeWanted){
		self.resumeWanted = NO;
		[self resumeFromBackground];
	}
	if (done)
		done();
}

- (void)handleUpdateBatch:(NSArray *)batch {
	self.batchingUpdates = YES;
	for (NSDictionary *obj in batch){
		[self handleUpdate:obj];
	}
	self.batchingUpdates = NO;

	if (self.chatsNeedRebuild){
		[self rebuildChats];
	}
}

#pragma mark - sending

// The single-threaded ClientManager requires send and receive on the SAME
// thread: sending from elsewhere while the receive loop holds the scheduler
// guard aborts on `Scheduler.cpp:126 Check !scheduler_->has_guard_ failed`.
// So callers only enqueue here, and the receive thread does the sending.
- (void)send:(NSDictionary *)request {
	NSMutableData *z = TGJsonSerializeForSend(request);
	if (!z){
		NSLog(@"TGClient: cannot encode %@", request);
		return;
	}

	[self.outboxLock lock];
	[self.outbox addObject:z];
	[self.outboxLock unlock];
}

/// Runs on the receive thread only.
- (void)drainOutbox {
	if (!self.available)
		return;

	NSArray *pending;
	[self.outboxLock lock];
	pending = [self.outbox copy];
	[self.outbox removeAllObjects];
	[self.outboxLock unlock];

	for (NSData *d in pending) {
		NSString *reqStr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
		NSLog(@"TGClient: >>> SEND: %@", reqStr);
		self.td_send(self.client, d.bytes);
	}
}

- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
	if (!completion){
		[self send:request];
		return;
	}
	NSString *extra = [NSString stringWithFormat:@"r%lu", (unsigned long)(++self.requestSeq)];
	self.pendingRequests[extra] = [completion copy];

	NSMutableDictionary *withExtra = [request mutableCopy];
	withExtra[@"@extra"] = extra;
	[self send:withExtra];
}

/// The synchronous half of td_api: a few functions answer on the spot, with
/// no client and no round trip. nil when the dylib has no execute symbol,
/// which is also how the host tests see it.
- (NSDictionary *)executeSynchronously:(NSDictionary *)request {
	if (!self.td_exec || !request)
		return nil;
	NSData *json = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
	if (!json)
		return nil;
	const char *answer = self.td_exec(NULL, [[[NSString alloc]
			initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
	if (!answer)
		return nil;
	NSData *data = [[NSString stringWithUTF8String:answer]
			dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:data
														   options:0 error:nil];
	return [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
}

/// What goes into an inputMessageText. Bold, italic, code and links are
/// written the way Telegram Desktop writes them - *bold*, _italic_, `code` -
/// and read back out here, because a UITextField on this OS has no way to
/// mark up a selection.
///
/// Markup that does not pair up is left alone: a lone asterisk is an
/// asterisk. When the parse is not available at all the text is sent as
/// written, which is what this app did for every message until now.
NSDictionary *TGFormattedText(NSString *text) {
	NSDictionary *plain = @{@"@type" : @"formattedText",
							@"text"  : text ?: @"",
							@"entities" : @[]};
	if (!text.length)
		return plain;

	NSDictionary *parsed = [[TGClient shared] executeSynchronously:@{
		@"@type" : @"parseTextEntities",
		@"text"  : text,
		@"parse_mode" : @{@"@type" : @"textParseModeMarkdown",
						  // Version 2 is the one that needs every reserved
						  // character escaped; version 1 is what people type.
						  @"version" : @(1)},
	}];
	if (![parsed[@"@type"] isEqualToString:@"formattedText"])
		return plain;
	return parsed;
}

#pragma mark - updates

- (void)handleUpdate:(NSDictionary *)obj {
	// A reply to one of our requests: route it and stop.
	NSString *extra = obj[@"@extra"];
	if ([extra isKindOfClass:NSString.class]){
		void (^completion)(NSDictionary *) = self.pendingRequests[extra];
		if (completion){
			[self.pendingRequests removeObjectForKey:extra];
			completion(obj);
			return;
		}
	}
	NSString *type = obj[@"@type"];
	const char *typeName = type.UTF8String;
	size_t typeLen = typeName ? strlen(typeName) : 0;

	if ([type hasPrefix:@"updateAuthorization"] || [type hasPrefix:@"authorization"] || [type isEqualToString:@"error"] || [type isEqualToString:@"ok"]) {
		NSLog(@"TGClient: <<< RECV: %@", obj);
	}

	// Log each response kind once - enough to see what TDLib actually sends
	// without dumping the user's messages into the log.
	static NSMutableSet *seen = nil;
	if (!seen) seen = [NSMutableSet set];
	if (type && ![seen containsObject:type]){
		[seen addObject:type];
		NSLog(@"TGClient: first %@", type);
	}

	// Answer to getMe. updateUser also carries our own record, but the direct
	// reply is the one that always has the phone number.
	if ([type isEqualToString:@"user"] && obj[@"phone_number"]){
		self.me = @{
			@"id"         : obj[@"id"] ?: @(0),
			@"first_name" : obj[@"first_name"] ?: @"",
			@"username"   : obj[@"usernames"][@"active_usernames"][0] ?: (obj[@"username"] ?: @""),
			@"phone"      : obj[@"phone_number"] ?: @"",
		};
		NSLog(@"TGClient: signed in as +%@", self.me[@"phone"]);
		return;
	}

	switch (TGUpdateTypeFor(typeName, typeLen)){
	case TGUpdateAuthorizationState: {
		[self handleAuthState:obj[@"authorization_state"]];
		return;
	}
	case TGUpdateUser: {
		NSDictionary *u = obj[@"user"];
		if (u[@"id"]){
			if (!self.rawUsersById)
				self.rawUsersById = [[TGObjectLruCache alloc] initWithCapacity:TGRawUserCacheCap];
			self.rawUsersById[u[@"id"]] = u;
		}
		NSString *name = [[NSString stringWithFormat:@"%@ %@",
				u[@"first_name"] ?: @"", u[@"last_name"] ?: @""]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!name.length)
			name = u[@"usernames"][@"active_usernames"][0] ?: @"";
		if (u[@"id"] && name.length)
			self.usersById[u[@"id"]] = name;
		[self cacheProfilePhoto:u];
		if (u[@"id"] && self.updateCoalescer) {
			[self.updateCoalescer markUserDirty:[u[@"id"] longLongValue]];
		}
		return;
	}

	// Live message updates - without these a chat only refreshes when reopened.
	case TGUpdateNewMessage: {
		NSDictionary *m = obj[@"message"];
		if (self.onMessage && m)
			self.onMessage([m[@"chat_id"] longLongValue], TGFlattenMessage(m), 0);
		return;
	}
	case TGUpdateMessageSendSucceeded:
	case TGUpdateMessageSendFailed: {
		// The echo we showed carries a temporary id, larger than any real one,
		// and a pending sending_state. The server's id arrives only here, so
		// without this branch the bubble keeps its clock and every later
		// request about it (reply, delete, read) names an id that is gone.
		// A failed send keeps the old id and comes back with the failed flag.
		NSDictionary *m = obj[@"message"];
		if (!self.onMessage || !m)
			return;
		int64_t chatId = [m[@"chat_id"] longLongValue];
		int64_t oldId  = [obj[@"old_message_id"] longLongValue];
		if (oldId)
			self.onMessage(chatId, nil, oldId);
		self.onMessage(chatId, TGFlattenMessage(m), 0);
		return;
	}
	case TGUpdateMessageContent: {
		// Content changed in place (a photo finished uploading, a text edited).
		if (self.onMessage)
			self.onMessage([obj[@"chat_id"] longLongValue], nil, 0);
		return;
	}
	case TGUpdateDeleteMessages: {
		if ([obj[@"is_permanent"] boolValue] && self.onMessage){
			int64_t chatId = [obj[@"chat_id"] longLongValue];
			for (NSNumber *mid in obj[@"message_ids"])
				self.onMessage(chatId, nil, [mid longLongValue]);
		}
		return;
	}
	case TGUpdateNewChat: {
		[self mergeChat:obj[@"chat"]];
		return;
	}
	case TGUpdateChatReplyMarkup: {
		// A bot's keyboard arrived on a chat or was taken off it. The message
		// rides along whole, so the keyboard is read from it here.
		NSNumber *chatId = obj[@"chat_id"];
		NSMutableDictionary *chat = chatId ? self.chatsById[chatId] : nil;
		NSDictionary *message = [obj[@"reply_markup_message"] isKindOfClass:NSDictionary.class]
				? obj[@"reply_markup_message"] : nil;
		if (chat) {
			chat[@"replyMarkupMessageId"] = message[@"id"] ?: @0;
			chat[@"replyKeyboard"] = TGFlattenReplyMarkup(message[@"reply_markup"])[@"replyKeyboard"]
					?: [NSNull null];
		}
		if (chatId)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGChatReplyMarkupChangedNotification
								  object:nil userInfo:@{@"chatId" : chatId}];
		return;
	}
	case TGUpdateChatLastMessage:
	case TGUpdateChatPosition:
	case TGUpdateChatTitle:
	case TGUpdateChatPhoto:
	case TGUpdateChatDraftMessage:
	case TGUpdateChatIsMarkedAsUnread:
	case TGUpdateChatUnreadMentionCount:
	case TGUpdateChatUnreadReactionCount:
	case TGUpdateChatReadInbox:
	case TGUpdateChatReadOutbox:
	case TGUpdateChatUnreadPollVoteCount:
	case TGUpdateChatAddedToList:
	case TGUpdateChatRemovedFromList:
	case TGUpdateChatNotificationSettings: {
		[self applyChatUpdate:obj];
		return;
	}
	case TGUpdateChatPermissions:
	case TGUpdateChatMessageAutoDeleteTime:
	case TGUpdateChatOnlineMemberCount: {
		// Group-level facts the profile shows. They are chat fields, not full
		// info, so they are merged here and the screen is told the same way a
		// full record tells it.
		[self applyChatUpdate:obj];
		NSNumber *chatId = obj[@"chat_id"];
		if (chatId)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGFullInfoChangedNotification object:self
								userInfo:@{@"kind" : @"chat", @"id" : chatId}];
		return;
	}
	// Chat fields nothing draws yet - block list, protected content, the
	// scheduled bar, view-as-topics, translation, reactions, theme, accent
	// colours, send-as, welcome messages, background. Merged into the row so
	// the screen that starts reading one is already fed, and told the same
	// way the group facts are told: an open profile re-reads.
	case TGUpdateChatBlockList:
	case TGUpdateChatHasProtectedContent:
	case TGUpdateChatHasScheduledMessages:
	case TGUpdateChatViewAsTopics:
	case TGUpdateChatIsTranslatable:
	case TGUpdateChatHasWelcomeMessages:
	case TGUpdateChatAvailableReactions:
	case TGUpdateChatTheme:
	case TGUpdateChatAccentColors:
	case TGUpdateChatMessageSender:
	case TGUpdateChatWelcomeMessages:
	case TGUpdateChatBackground: {
		[self applyChatUpdate:obj];
		NSNumber *chatId = obj[@"chat_id"];
		if (chatId)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGFullInfoChangedNotification object:self
								userInfo:@{@"kind" : @"chat", @"id" : chatId}];
		return;
	}
	case TGUpdateMessageReaction:
	case TGUpdateMessageReactions:
	case TGUpdateMessageLiveLocationViewed:
	case TGUpdateAnimatedEmojiMessageClicked: {
		// Who reacted, who watched, what was tapped: all fields of the
		// message, so the open chat re-reads it - coalesced, the way a crowd
		// reacting to a channel post stays one nudge per chat.
		if (self.updateCoalescer)
			[self.updateCoalescer markMessageDirty:[obj[@"message_id"] longLongValue]
											inChat:[obj[@"chat_id"] longLongValue]];
		return;
	}
	case TGUpdateActiveLiveLocationMessages: {
		// The list of running live locations moved; every rider nudges its
		// own chat, the same shape a content change arrives in.
		for (NSDictionary *m in obj[@"messages"]){
			if (self.updateCoalescer)
				[self.updateCoalescer markMessageDirty:[m[@"message_id"] longLongValue]
												inChat:[m[@"chat_id"] longLongValue]];
		}
		return;
	}
	case TGUpdateUnreadMessageCount: {
		// The one global counter in the app: the badge. The update fires per
		// chat list, and only the main list's total is the badge's number -
		// a folder's slice shrinking it would be a lie. A missing or null
		// chat_list is the main list; zero in the field is a real count and
		// goes out as one.
		id list = obj[@"chat_list"];
		BOOL mainList = !list || [list isKindOfClass:[NSNull class]];
		if (!mainList && [list isKindOfClass:NSDictionary.class])
			mainList = [list[@"@type"] isEqualToString:@"chatListMain"];
		if (!mainList)
			return;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGUnreadTotalChangedNotification object:self
							userInfo:@{@"count" : obj[@"unread_unmuted_count"] ?: @0}];
		return;
	}
	case TGUpdateSavedMessagesTopic:
	case TGUpdateSavedMessagesTopicCount:
	case TGUpdateSavedMessagesTags: {
		// A Saved Messages topic arrived, moved, or got a label: asked for by
		// loadSavedMessagesTopics, changing while the topics screen is open.
		// The tags update patches the row the tag belonged to.
		NSDictionary *topic = obj[@"topic"];
		NSString *topicId = [topic[@"id"] isKindOfClass:NSString.class] ?
				topic[@"id"] : [@(topic[@"id"] ? [topic[@"id"] longLongValue] : 0) stringValue];
		if (topicId && !self.savedTopicsById)
			self.savedTopicsById = [NSMutableDictionary dictionary];
		if (topicId && self.savedTopicsById){
			NSMutableDictionary *row = self.savedTopicsById[topicId] ?:
					[NSMutableDictionary dictionary];
			row[@"id"] = @(topicId.length ? [topicId longLongValue] : 0);
			NSString *type = topic[@"type"][@"@type"] ?: @"";
			NSString *title = @"Forwarded";
			if ([type isEqualToString:@"savedMessagesTopicTypeMyNotes"])
				title = @"My Notes";
			else if ([type isEqualToString:@"savedMessagesTopicTypeAuthorHidden"])
				title = @"Hidden Author";
			else if ([type isEqualToString:@"savedMessagesTopicTypeSavedFromChat"]){
				NSString *chatTitle = [[TGClient shared] titleForChat:
						[topic[@"type"][@"chat_id"] longLongValue]];
				title = chatTitle.length ? chatTitle : @"Forwarded Chat";
			}
			row[@"title"] = title;
			NSString *text = TGFlattenMessage(topic[@"last_message"])[@"text"];
			row[@"text"] = text ?: @"";
			if (topic[@"date"] && topic[@"date"] != [NSNull null])
				row[@"date"] = topic[@"date"];
			row[@"pinned"] = topic[@"is_pinned"];
			row[@"order"] = topic[@"order"];
			self.savedTopicsById[topicId] = row;
		}
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGSavedTopicsChangedNotification object:self];
		return;
	}
	// Three that used to sit in the marker block and now have somewhere to go.
	case TGUpdateDefaultReactionType: {
		// The reaction their bar leads with. Kept here so the picker can put
		// it first without asking the server again.
		NSString *emoji = obj[@"reaction_type"][@"emoji"];
		if ([emoji isKindOfClass:NSString.class] && emoji.length)
			self.reactionDefaultEmoji = emoji;
		return;
	}
	case TGUpdateAnimationSearchParameters: {
		// Which bot answers GIF search, and the emoji it suggests for it.
		NSString *provider = obj[@"provider"];
		if ([provider isKindOfClass:NSString.class] && provider.length)
			self.gifSearchProvider = provider;
		NSArray *emojis = obj[@"emojis"];
		if ([emojis isKindOfClass:NSArray.class])
			self.gifSearchEmojis = emojis;
		return;
	}
	case TGUpdateServiceNotification: {
		// The protocol says to show these as a popup: there is no chat they
		// belong to, so the window is the only place they can land.
		NSString *text = nil;
		id content = obj[@"content"];
		if ([content isKindOfClass:NSDictionary.class]){
			id body = content[@"text"];
			if ([body isKindOfClass:NSDictionary.class])
				text = body[@"text"];
			else if ([body isKindOfClass:NSString.class])
				text = body;
		}
		if (!text.length)
			text = obj[@"type"];
		if ([text isKindOfClass:NSString.class] && text.length)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGServiceNotificationReceivedNotification
								object:self userInfo:@{@"text" : text}];
		return;
	}
	case TGUpdateTermsOfService: {
		// The protocol wants these shown before the account goes on. A
		// terms object that does not ask for a popup is accepted silently;
		// the rest go to the window, which is the only surface with no chat
		// to belong to.
		NSString *termsId = obj[@"terms_of_service_id"];
		NSDictionary *terms = [obj[@"terms_of_service"] isKindOfClass:NSDictionary.class]
				? obj[@"terms_of_service"] : @{};
		id body = terms[@"text"];
		NSString *text = [body isKindOfClass:NSDictionary.class] ? body[@"text"] : nil;
		if (![text isKindOfClass:NSString.class])
			text = @"";
		BOOL popup = [terms[@"show_popup"] boolValue];
		if (![termsId isKindOfClass:NSString.class] || !termsId.length)
			return;
		if (popup){
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGTermsOfServiceReceivedNotification
								object:self
							userInfo:@{@"id" : termsId, @"text" : text ?: @""}];
		} else {
			[self acceptTermsOfService:termsId completion:nil];
		}
		return;
	}
	case TGUpdateUserPrivacySettingRules: {
		// A rule flipped here or on another client; the privacy page holds
		// the copy, so it re-reads rather than guessing which row moved.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGPrivacyRulesChangedNotification object:self];
		return;
	}
	case TGUpdateAccentColors: {
		// Appearance offers these as the account's accent; the ids are what
		// setAccentColor takes, and 0-6 stay implicit per the schema.
		NSArray *ids = obj[@"available_accent_color_ids"];
		if ([ids isKindOfClass:NSArray.class])
			self.accentColorIds = ids;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccentColorsChangedNotification object:self];
		return;
	}
	case TGUpdateProfileAccentColors: {
		NSArray *ids = obj[@"available_accent_color_ids"];
		if ([ids isKindOfClass:NSArray.class])
			self.profileAccentColorIds = ids;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccentColorsChangedNotification object:self];
		return;
	}
	case TGUpdateContactCloseBirthdays: {
		// The count is the only thing the privacy page draws, and hiding the
		// strip is what an empty answer means. Keep the rows so a future
		// birthday strip has the names ready.
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *entry in obj[@"close_birthday_users"]){
			if (![entry isKindOfClass:NSDictionary.class])
				continue;
			NSNumber *userId = entry[@"user_id"];
			if (![userId isKindOfClass:NSNumber.class])
				continue;
			NSDictionary *birth = entry[@"birthdate"] ?: @{};
			[rows addObject:@{
				@"userId" : userId,
				@"day"    : birth[@"day"] ?: @0,
				@"month"  : birth[@"month"] ?: @0,
				@"year"   : birth[@"year"] ?: @0,
			}];
		}
		self.contactCloseBirthdays = rows;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGContactCloseBirthdaysChangedNotification object:self];
		return;
	}
	case TGUpdateUnconfirmedSession: {
		// A login waiting to be confirmed. The devices list is where it can
		// be confirmed or signed out, so it re-reads while it is open.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGSessionsChangedNotification object:self];
		return;
	}
	case TGUpdateApplicationVerificationRequired: {
		// Telegram wants a token from the platform's verification service.
		// There is no such service on this OS, so the request is handed to
		// the settings sheet, which asks the user for the token and sends
		// the server's answer back. The id is kept on the client so the row
		// can show what is pending after the scroll is gone.
		int64_t verificationId = [obj[@"verification_id"] longLongValue];
		NSString *nonce = [obj[@"nonce"] isKindOfClass:NSString.class]
				? obj[@"nonce"] : @"";
		[self noteApplicationVerificationWithId:verificationId nonce:nonce];
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGApplicationVerificationRequiredNotification
							  object:self
							userInfo:@{@"verificationId" : @(verificationId),
									   @"nonce" : nonce}];
		return;
	}
	case TGUpdateFreezeState: {
		// A restriction Telegram puts on the account, with the dates and the
		// appeal address it wants shown. Kept whole because the row is one
		// line but the sheet behind it has to answer "until when" and "where
		// do I appeal"; the Privacy page re-reads both.
		id appeal = obj[@"appeal_link"];
		self.freezeStateValue = @{
			@"is_frozen"     : @([obj[@"is_frozen"] boolValue]),
			@"freezing_date" : obj[@"freezing_date"] ?: @(0),
			@"deletion_date" : obj[@"deletion_date"] ?: @(0),
			@"appeal_link"   : [appeal isKindOfClass:NSString.class] ? appeal : @"",
		};
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccountStatusChangedNotification object:self];
		return;
	}
	case TGUpdateAgeVerificationParameters: {
		// The age gate: how old the country requires, which bot answers it,
		// and the country. A nil parameters clears the row rather than leaving
		// yesterday's minimum age on screen.
		id parameters = obj[@"parameters"];
		self.ageVerificationParametersValue =
				[parameters isKindOfClass:NSDictionary.class] ? parameters : nil;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccountStatusChangedNotification object:self];
		return;
	}
	case TGUpdateApplicationRecaptchaVerificationRequired: {
		// Telegram wants a reCAPTCHA solved before the request goes through.
		// The request is not an age-verification token: it carries the action,
		// the site key and an id of its own, so it gets its own record and the
		// Privacy row shows exactly what the server asked for.
		id action = obj[@"action"];
		id keyId = obj[@"recaptcha_key_id"];
		self.recaptchaVerificationRequestValue = @{
			@"verification_id"  : @([obj[@"verification_id"] longLongValue]),
			@"action"           : [action isKindOfClass:NSString.class] ? action : @"",
			@"recaptcha_key_id" : [keyId isKindOfClass:NSString.class] ? keyId : @"",
		};
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccountStatusChangedNotification object:self];
		return;
	}
	case TGUpdateUserSubscription: {
		// A subscription changed, for this account or for someone it names.
		// The update is about a user id, so it is filed by that id; the
		// Privacy page asks for the signed-in one and shows its flags.
		if (!obj[@"user_id"])
			return;
		// int64 may arrive as a decimal string; the dictionary key has to be
		// the same NSNumber the screen asks about.
		NSNumber *userId = @([obj[@"user_id"] longLongValue]);
		id payload = obj[@"payload"];
		NSMutableDictionary *record = [@{
			@"payload"           : [payload isKindOfClass:NSString.class] ? payload : @"",
			@"is_canceled"       : @([obj[@"is_canceled"] boolValue]),
			@"is_restored"       : @([obj[@"is_restored"] boolValue]),
			@"is_payment_failed" : @([obj[@"is_payment_failed"] boolValue]),
		} mutableCopy];
		if (!self.userSubscriptionsById)
			self.userSubscriptionsById = [NSMutableDictionary dictionary];
		self.userSubscriptionsById[userId] = record;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAccountStatusChangedNotification object:self
							userInfo:@{@"userId" : userId}];
		return;
	}
	case TGUpdateAvailableMessageEffects: {
		// The effects the effect sheet may offer. Ids are kept as numbers so
		// the sheet can name one in getMessageEffect without re-parsing a
		// string; a second list is the sticker effects, which the same sheet
		// lists under their own label.
		self.reactionMessageEffectIds = TGEffectIdList(obj[@"reaction_effect_ids"]);
		self.stickerMessageEffectIds = TGEffectIdList(obj[@"sticker_effect_ids"]);
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGMessageEffectsChangedNotification object:self];
		return;
	}
	case TGUpdateDefaultBackground: {
		// Telegram's own background for new chats. The whole background is
		// kept because its name, id and type are what Appearance has to show;
		// for_dark_theme says which of the two defaults moved.
		id background = obj[@"background"];
		self.defaultBackgroundValue = @{
			@"for_dark_theme" : @([obj[@"for_dark_theme"] boolValue]),
			@"background"     : [background isKindOfClass:NSDictionary.class]
					? background : @{},
		};
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAppearanceDefaultsChangedNotification object:self];
		return;
	}
	case TGUpdateEmojiChatThemes: {
		// The emoji chat themes Telegram offers. The names and their light and
		// dark settings are kept whole; Appearance lists the names and the
		// sheet behind one reads its settings.
		id themes = obj[@"chat_themes"];
		self.emojiChatThemesValue =
				[themes isKindOfClass:NSArray.class] ? themes : @[];
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGAppearanceDefaultsChangedNotification object:self];
		return;
	}
	case TGUpdateStopMessageDraft: {
		// A streaming draft was stopped. The cached text in the chat row is
		// what the composer would put back, so it is cleared here; the open
		// chat hears which text it was and clears the field only when the
		// field still holds that text, not something typed over it.
		if (!obj[@"chat_id"])
			return;
		int64_t chat = [obj[@"chat_id"] longLongValue];
		NSNumber *chatId = @(chat);
		NSString *previous = self.chatsById[chatId][@"draft"];
		if (![previous isKindOfClass:NSString.class])
			previous = @"";
		NSMutableDictionary *row = self.chatsById[chatId];
		if (row) {
			row[@"draft"] = @"";
			[self markChatRowDirty:chat];
		}
		NSDictionary *state = @{
			@"chat_id"       : @(chat),
			@"forum_topic_id": obj[@"forum_topic_id"] ?: @(0),
			@"draft_id"      : @([obj[@"draft_id"] longLongValue]),
			@"draft_text"    : previous,
		};
		self.stoppedMessageDraftValue = state;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGChatDraftStoppedNotification object:self
							userInfo:state];
		return;
	}
	case TGUpdateChatActiveStories: {
		[self applyChatActiveStoriesUpdate:obj];
		return;
	}
	case TGUpdateVideoPublished: {
		// A scheduled video went live. It is a message change plus a chat-list
		// change (the preview and order move), so both windows are nudged; the
		// open chat also gets the id to re-read that one message.
		if (!obj[@"chat_id"] || !obj[@"message_id"])
			return;
		NSNumber *chatId = @([obj[@"chat_id"] longLongValue]);
		NSNumber *messageId = @([obj[@"message_id"] longLongValue]);
		NSDictionary *state = @{
			@"chat_id"    : chatId,
			@"message_id" : messageId,
		};
		self.publishedVideoValue = state;
		if (self.updateCoalescer)
			[self.updateCoalescer markMessageDirty:[messageId longLongValue]
											inChat:[chatId longLongValue]];
		[self markChatRowDirty:[chatId longLongValue]];
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGChatVideoPublishedNotification object:self
							userInfo:state];
		return;
	}

	case TGUpdateCommunity:
		[self applyCommunityUpdate:obj];
		return;
	case TGUpdateCommunityFullInfo:
		[self applyCommunityFullInfoUpdate:obj];
		return;
	case TGUpdateQuickReplyShortcut:
		[self applyQuickReplyShortcutUpdate:obj];
		return;
	case TGUpdateQuickReplyShortcutDeleted:
		[self applyQuickReplyShortcutDeleted:obj];
		return;
	case TGUpdateQuickReplyShortcuts:
		[self applyQuickReplyShortcutsUpdate:obj];
		return;
	case TGUpdateQuickReplyShortcutMessages:
		[self applyQuickReplyShortcutMessagesUpdate:obj];
		return;
	case TGUpdateSuggestedActions:
		[self applySuggestedActionsUpdate:obj];
		return;

	// TDLib's local notification list. The page that removes entries reads
	// this copy, because no request re-reads what updateActiveNotifications
	// sent.
	case TGUpdateActiveNotifications:
	case TGUpdateNotification:
	case TGUpdateNotificationGroup:
		[self applyActiveNotificationUpdate:obj];
		return;
	case TGUpdateHavePendingNotifications: {
		// TDLib is still fetching or delaying notifications. The screen keeps
		// a spinner up until both flags are off rather than calling the list
		// final while rows are still on the way.
		[self applyHavePendingNotificationsUpdate:obj];
		return;
	}
	case TGUpdateAutosaveSettings: {
		// One scope, here or on another client. The exception list is not in
		// this update, so the page re-reads the whole record.
		[self applyAutosaveSettingsUpdate:obj];
		return;
	}
	case TGUpdateLanguagePackStrings: {
		// The strings that changed, not a whole pack. The Language page
		// re-reads the pack record and any string list it already showed.
		[self applyLanguagePackStringsUpdate:obj];
		return;
	}
	case TGUpdateMessageContainsUnreadPollVotes: {
		// The badge on a poll whose votes you have not looked at. Same storm
		// risk as a reaction count, same window.
		if (self.updateCoalescer)
			[self.updateCoalescer markMessageDirty:[obj[@"message_id"] longLongValue]
											inChat:[obj[@"chat_id"] longLongValue]];
		return;
	}
	case TGUpdateScopeNotificationSettings:
	case TGUpdateChatDefaultDisableNotification:
	case TGUpdateReactionNotificationSettings:
	case TGUpdateSavedNotificationSounds: {
		// The settings page re-reads all three scopes and the sounds list;
		// nothing finer is carried for it to read piecemeal.
		if ([type isEqualToString:@"updateReactionNotificationSettings"]){
			NSDictionary *settings = obj[@"notification_settings"];
			if ([settings isKindOfClass:NSDictionary.class])
				self.reactionNotificationSettingsValue = settings;
		}
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGNotificationSettingsChangedNotification object:self];
		if ([type isEqualToString:@"updateChatDefaultDisableNotification"])
			[self applyChatUpdate:obj];
		return;
	}
	case TGUpdateForumTopic:
	case TGUpdateForumTopicInfo:
	case TGUpdateTopicMessageCount: {
		// updateForumTopicInfo nests the chat one level down, in the info.
		NSNumber *chatId = obj[@"chat_id"] ?: obj[@"info"][@"chat_id"];
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGForumTopicsChangedNotification object:self
							userInfo:chatId ? @{@"chatId" : chatId} : nil];
		return;
	}
	case TGUpdateMessageMentionRead:
	case TGUpdateMessageUnreadReactions: {
		// Both carry the chat's new counter and the message that caused it:
		// the row's badge comes from the counter, the open chat has to drop
		// the mark on that one message.
		[self applyChatUpdate:obj];
		if (self.onMessage)
			self.onMessage([obj[@"chat_id"] longLongValue], nil, 0);
		return;
	}
	case TGUpdateMessageEdited:
	case TGUpdateMessageIsPinned:
	case TGUpdateMessageContentOpened: {
		// An edit date, a pin flag, a played voice note: the fields are on
		// the message, so the open chat re-reads it the way a content change
		// already does. Nothing to merge into the chat row.
		if (self.onMessage)
			self.onMessage([obj[@"chat_id"] longLongValue], nil, 0);
		return;
	}
	case TGUpdateMessageInteractionInfo: {
		// Reaction totals and a channel's view count live on the message and
		// were frozen at whatever the history fetch said, while this client
		// can already put a reaction on. Coalesced, not acted on per update.
		if (self.updateCoalescer)
			[self.updateCoalescer markMessageDirty:[obj[@"message_id"] longLongValue]
											inChat:[obj[@"chat_id"] longLongValue]];
		return;
	}
	case TGUpdateInstalledStickerSets:
	case TGUpdateTrendingStickerSets:
	case TGUpdateRecentStickers:
	case TGUpdateFavoriteStickers:
	case TGUpdateSavedAnimations:
	case TGUpdateStickerSet: {
		// Six lists, one notification: the panel asks for whichever tab it is
		// showing, so there is nothing finer to tell it.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGStickerListsChangedNotification object:self];
		return;
	}
	case TGUpdateChatMember:
	case TGUpdateChatPendingJoinRequests:
	case TGUpdateNewChatJoinRequest:
	case TGUpdateChatJoinResult: {
		// updateChatJoinResult is the answer to our own join request, sent
		// the way the other three are: the chat's members sheet re-reads.
		NSNumber *chatId = obj[@"chat_id"];
		if (!chatId)
			return;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGChatMembersChangedNotification object:self
							userInfo:@{@"chatId" : chatId}];
		return;
	}
	case TGUpdateFileAddedToDownloads:
	case TGUpdateFileDownload:
	case TGUpdateFileDownloads:
	case TGUpdateFileRemovedFromDownloads:
	case TGUpdateSpeedLimitNotification: {
		// Settings > Downloads is the one screen built from a single
		// searchFileDownloads answer, so it had no way of noticing a download
		// that finished, paused or was removed from another device.
		// updateFile carries the bytes; the list membership is only here.
		// The speed limit rides along: throttled progress is a change the
		// rows should re-read too.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGDownloadsChangedNotification object:self];
		return;
	}
	case TGUpdateUserFullInfo:
	case TGUpdateBasicGroup:
	case TGUpdateBasicGroupFullInfo:
	case TGUpdateSupergroupFullInfo: {
		// Bios, member counts and admin rights live in the full record, which
		// is fetched per screen and never refreshed. updateSupergroup was
		// handled, none of the full infos were - so a bio edited elsewhere
		// needed the profile closed and reopened.
		NSString *kind = @"user";
		NSNumber *peerId = obj[@"user_id"];
		if (!peerId){
			peerId = obj[@"basic_group_id"] ?: obj[@"basic_group"][@"id"];
			kind = @"basicGroup";
		}
		if (!peerId){
			peerId = obj[@"supergroup_id"];
			kind = @"supergroup";
		}
		if (!peerId)
			return;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGFullInfoChangedNotification object:self
							userInfo:@{@"kind" : kind, @"id" : peerId}];
		return;
	}
	case TGUpdateOption: {
		// Limits, flags and the server clock. Kept in the C++ store rather
		// than answered once by getOption and never corrected.
		NSString *name = obj[@"name"];
		NSDictionary *value = obj[@"value"];
		if (!name.length || ![value isKindOfClass:NSDictionary.class])
			return;
		NSString *kind = value[@"@type"];
		const char *key = name.UTF8String;
		if ([kind isEqualToString:@"optionValueBoolean"]){
			TGOptionSetBoolean(key, [value[@"value"] boolValue]);
		} else if ([kind isEqualToString:@"optionValueInteger"]){
			// int64 comes over JSON as a string; both shapes answer this.
			TGOptionSetInteger(key, [value[@"value"] longLongValue]);
		} else if ([kind isEqualToString:@"optionValueString"]){
			TGOptionSetString(key, [value[@"value"] UTF8String]);
		} else {
			TGOptionClear(key);
		}
		return;
	}
	case TGUpdateConnectionState: {
		NSString *st = obj[@"state"][@"@type"];
		NSLog(@"TGClient: connection %@", st);

		TGConnectionState state = TGConnectionStateUnknown;
		NSString *text = nil;
		if ([st isEqualToString:@"connectionStateWaitingForNetwork"]){
			state = TGConnectionStateWaitingForNetwork; text = @"Waiting for network";
		} else if ([st isEqualToString:@"connectionStateConnecting"] ||
				   [st isEqualToString:@"connectionStateConnectingToProxy"]){
			state = TGConnectionStateConnecting; text = @"Connecting";
		} else if ([st isEqualToString:@"connectionStateUpdating"]){
			state = TGConnectionStateUpdating; text = @"Updating";
		} else if ([st isEqualToString:@"connectionStateReady"]){
			state = TGConnectionStateReady; text = nil;
		}

		self.connectionState = state;
		if (self.onConnectionState)
			self.onConnectionState(state, text);
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGConnectionStateChangedNotification
							  object:nil
							userInfo:@{@"state" : @(state),
									   @"text"  : text ?: @""}];
		return;
	}
	// The state of a secret chat - whether the other device has answered
	// the exchange yet - is the one thing its header has to breathe.
	case TGUpdateSecretChat: {
		NSDictionary *sc = obj[@"secret_chat"];
		NSString *st = sc[@"state"][@"@type"] ?: @"";
		NSString *word = @"pending";
		if ([st isEqualToString:@"secretChatStatePending"])      word = @"pending";
		else if ([st isEqualToString:@"secretChatStateReady"])   word = @"ready";
		else if ([st isEqualToString:@"secretChatStateClosed"])  word = @"closed";
		else                                                     word = @"unknown";
		if (self.onSecretChat)
			self.onSecretChat([sc[@"id"] integerValue], word);
		return;
	}

	case TGUpdateNewCallSignalingData: {
		NSData *data = TGBase64Decode(obj[@"data"]);
		NSLog(@"TGClient: <<< updateNewCallSignalingData call_id=%@ len=%lu", obj[@"call_id"], (unsigned long)data.length);
		[[TGCall shared] handleSignalingData:data];
		return;
	}

	case TGUpdateCall: {
		NSLog(@"TGClient: <<< updateCall: %@", obj[@"call"]);
		// TDLib signals the call; TGCall owns the audio.
		[[TGCall shared] handleUpdate:obj[@"call"]];
		return;
	}

	case TGUpdateFile: {
		NSDictionary *file = obj[@"file"];
		NSInteger fid = [file[@"id"] integerValue];
		NSDictionary *local = file[@"local"];
		if (self.onFileProgress && [local[@"is_downloading_active"] boolValue]){
			double expected = [file[@"expected_size"] doubleValue];
			double got = [local[@"downloaded_size"] doubleValue];
			if (expected > 0)
				self.onFileProgress(fid, (float)(got / expected));
		}
		if ([file[@"remote"][@"is_uploading_active"] boolValue]){
			double expected = [file[@"expected_size"] doubleValue];
			double uploaded = [file[@"remote"][@"uploaded_size"] doubleValue];
			if (self.onFileUploadProgress && expected > 0)
				self.onFileUploadProgress(fid, (float)(uploaded / expected));
			[self handleFileUploadProgress:fid file:file];
		}
		BOOL done = [local[@"is_downloading_completed"] boolValue];
		NSString *path = local[@"path"];
		if (done && path.length){
			[self notifyFileWaiters:fid path:path];
		}
		return;
	}

	case TGUpdateFileGenerationStart: {
		// TDLib asks the app to produce a file. +Files owns the pending
		// request, writes the parts and finishes the generation.
		[self handleFileGenerationStart:obj];
		return;
	}

	case TGUpdateFileGenerationStop: {
		// The generation is no longer needed: drop the pending blocks so a
		// screen waiting on it learns it stopped rather than hangs.
		[self handleFileGenerationStop:obj];
		return;
	}

	case TGUpdateChatAction: {
		// TDLib names the action; the client turns it into the phrase every
		// other client shows.
		NSString *kind = obj[@"action"][@"@type"];
		NSString *phrase = nil;
		if ([kind isEqualToString:@"chatActionTyping"])
			phrase = @"typing...";
		else if ([kind isEqualToString:@"chatActionRecordingVoiceNote"])
			phrase = @"recording audio...";
		else if ([kind isEqualToString:@"chatActionRecordingVideoNote"] ||
				 [kind isEqualToString:@"chatActionRecordingVideo"])
			phrase = @"recording video...";
		else if ([kind isEqualToString:@"chatActionUploadingPhoto"])
			phrase = @"sending a photo...";
		else if ([kind hasPrefix:@"chatActionUploading"])
			phrase = @"sending a file...";
		// chatActionCancel and anything unknown clear it.
		int64_t actingChat = [obj[@"chat_id"] longLongValue];
		// The chat list shows this in place of the preview, so it has to live
		// on the chat rather than only reach whichever chat is open.
		NSMutableDictionary *acting = self.chatsById[@(actingChat)];
		if (acting){
			acting[@"action"] = phrase ?: @"";
			[self markChatRowDirty:actingChat];
		}
		if (self.onChatAction)
			self.onChatAction(actingChat, phrase);
		return;
	}

	// Whether a supergroup is a forum is a property of the supergroup, not of
	// the chat, and it arrives in an update of its own. Chats already built
	// from that supergroup have to be told.
	case TGUpdateSupergroup: {
		NSDictionary *group = obj[@"supergroup"];
		NSNumber *groupId = group[@"id"];
		if (!groupId)
			return;
		BOOL isForum = [group[@"is_forum"] boolValue];
		if ([self.forumSupergroups[groupId] boolValue] == isForum &&
			self.forumSupergroups[groupId])
			return;
		self.forumSupergroups[groupId] = @(isForum);

		for (NSMutableDictionary *chat in self.chatsById.allValues){
			if (![chat[@"supergroupId"] isEqual:groupId])
				continue;
			chat[@"isForum"] = @(isForum);
			[self markChatRowDirty:[chat[@"id"] longLongValue]];
		}
		return;
	}

	// A private chat's id is the user's id, so presence lands straight on the
	// chat the list is drawing.
	case TGUpdateUserStatus: {
		int64_t userId = [obj[@"user_id"] longLongValue];
		if (self.rawUsersById[@(userId)] && [obj[@"status"] isKindOfClass:NSDictionary.class]){
			NSMutableDictionary *cachedUser = [self.rawUsersById[@(userId)] mutableCopy];
			cachedUser[@"status"] = obj[@"status"];
			self.rawUsersById[@(userId)] = cachedUser;
		}
		NSMutableDictionary *chat = self.chatsById[obj[@"user_id"]];
		// Presence screens (chat header, profile status) hear this even when
		// the user sits in no loaded chat.
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGUserStatusChangedNotification
							  object:nil
							userInfo:@{@"userId" : @(userId)}];
		if (!chat)
			return;
		BOOL online = [obj[@"status"][@"@type"] isEqualToString:@"userStatusOnline"];
		if ([chat[@"isOnline"] boolValue] == online)
			return;
		chat[@"isOnline"] = @(online);
		[self markChatRowDirty:userId];
		return;
	}

	case TGUpdateChatActionBar: {
		// The bar over a chat nobody knows follows the update, not only the
		// fetch; whichever chat is open hears the notification and redraws.
		int64_t chatId = [obj[@"chat_id"] longLongValue];
		NSMutableDictionary *row = self.chatsById[@(chatId)];
		if (row){
			[self mergeActionBar:obj[@"action_bar"] intoChatRow:row];
			[self markChatRowDirty:chatId];
		}
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGChatActionBarChangedNotification
							  object:@(chatId)];
		return;
	}

	case TGUpdateChatFolders: {
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *f in obj[@"chat_folders"]){
			NSString *title = TGFolderTitle(f);
			// A raw dump only when tdlib's nested naming defeats us again -
			// the syslog line then tells the exact key it moved to.
			if (!title.length)
				NSLog(@"TGClient: B3 chat_folders raw: %@", f);
			[out addObject:@{@"id" : @(f[@"id"] ? [f[@"id"] longLongValue] : 0),
							 @"title" : title}];
		}
		self.folders = out;
		NSLog(@"TGClient: %lu folders", (unsigned long)out.count);
		// The chat list learns the pill strip and the All chats merge from
		// this update too; silently returning left both stale until the
		// user wandered into a folder and back. The call site is main.
		if (self.onChatsChanged)
			self.onChatsChanged();
		return;
	}
	case TGUpdateGroupCall:
		[self applyGroupCallUpdate:obj];
		return;
	case TGUpdateGroupCallParticipant:
		[self applyGroupCallParticipantUpdate:obj];
		return;
	case TGUpdateGroupCallParticipants:
		[self applyGroupCallParticipantsUpdate:obj];
		return;
	case TGUpdateNewGroupCallMessage:
		[self applyNewGroupCallMessage:obj];
		return;
	case TGUpdateGroupCallMessagesDeleted:
		[self applyGroupCallMessagesDeleted:obj];
		return;
	case TGUpdateGroupCallMessageSendFailed:
		[self applyGroupCallMessageSendFailed:obj];
		return;
	case TGUpdateDirectMessagesChatTopic:
		[self applyDirectMessagesChatTopic:obj[@"topic"]];
		return;
	case TGUpdateTextCompositionStyles:
		[self applyTextCompositionStylesUpdate:obj];
		return;
	case TGUpdateStakeDiceState:
		[self applyStakeDiceStateUpdate:obj];
		return;
	case TGUpdateChatEmojiStatus: {
		// The badge on a chat: keep it on the row, and tell an open profile.
		[self applyChatUpdate:obj];
		NSNumber *chatId = obj[@"chat_id"];
		if (chatId)
			[[NSNotificationCenter defaultCenter]
					postNotificationName:TGFullInfoChangedNotification object:self
								userInfo:@{@"kind" : @"chat", @"id" : chatId}];
		return;
	}
	case TGUpdateUnreadChatCount: {
		NSLog(@"TGClient: %@ total=%@ list=%@", type, obj[@"total_count"],
				obj[@"chat_list"][@"@type"]);
		return;
	}
	default:
		break;
	}

	if ([type isEqualToString:@"error"]){
		NSString *msg = obj[@"message"] ?: @"unknown error";
		NSLog(@"TGClient: <<< ERROR code=%@ msg=%@ details: %@", obj[@"code"], msg, obj);
		if ([obj[@"code"] intValue] == 404){
			// loadChats answers 404 when the whole list is loaded
			self.chatListComplete = YES;
			NSLog(@"TGClient: chat list complete (%lu)",
					(unsigned long)self.chatsById.count);
			return;
		}
		if (self.onError)
			self.onError(msg);
		return;
	}
}

/// With no coalescer the rebuild stays immediate, so nothing silently waits
/// on a main-queue timer that may never fire.
- (void)markChatRowDirty:(int64_t)chatId {
	if (self.updateCoalescer)
		[self.updateCoalescer markChatDirty:chatId];
	else
		[self rebuildChats];
}

- (void)handleAuthState:(NSDictionary *)state {
	NSString *type = state[@"@type"];
	NSLog(@"TGClient: <<< AUTH STATE: %@ details: %@", type, state);

	TGAuthState s = TGAuthStateUnknown;

	if ([type isEqualToString:@"authorizationStateWaitTdlibParameters"]){
		[self sendTdlibParameters];
		return;                       // not a user-visible state
	} else if ([type isEqualToString:@"authorizationStateWaitPhoneNumber"]){
		s = TGAuthStateWaitPhoneNumber;
	} else if ([type isEqualToString:@"authorizationStateWaitCode"]){
		s = TGAuthStateWaitCode;
		self.codeInfo = state[@"code_info"];
	} else if ([type isEqualToString:@"authorizationStateWaitPassword"]){
		s = TGAuthStateWaitPassword;
		self.loginPasswordInfo = state;
	} else if ([type isEqualToString:@"authorizationStateWaitEmailAddress"]){
		// These two fell through to "not a user-visible state": a number
		// Telegram wants an email for sat on the phone step for good.
		s = TGAuthStateWaitEmailAddress;
	} else if ([type isEqualToString:@"authorizationStateWaitEmailCode"]){
		s = TGAuthStateWaitEmailCode;
		self.emailCodeInfo = state;
	} else if ([type isEqualToString:@"authorizationStateWaitRegistration"]){
		s = TGAuthStateWaitRegistration;
		// The terms come with the state and nowhere else; a screen that has
		// to show them before making an account cannot ask for them later.
		self.registrationTermsText = state[@"terms_of_service"][@"text"][@"text"];
	} else if ([type isEqualToString:@"authorizationStateWaitOtherDeviceConfirmation"]){
		s = TGAuthStateWaitOtherDeviceConfirmation;
		self.qrCodeLink = state[@"link"];
	} else if ([type isEqualToString:@"authorizationStateReady"]){
		s = TGAuthStateReady;
	} else if ([type isEqualToString:@"authorizationStateLoggingOut"]){
		s = TGAuthStateLoggingOut;
	} else if ([type isEqualToString:@"authorizationStateClosed"]){
		self.running = NO;
		if (self.pausing)
			return;                   // our own close for the background
		s = TGAuthStateClosed;
	} else {
		return;                       // encryption-key states etc.
	}

	self.authState = s;
	if (s == TGAuthStateReady){
		[self loadChats];
		[self send:@{@"@type" : @"getMe"}];
	}
	if (s == TGAuthStateWaitPhoneNumber)
		[self flushPendingPhoneNumber];
	if (self.onAuthState)
		self.onAuthState(s);
}

- (void)sendTdlibParameters {
	NSString *docs = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *db = [docs stringByAppendingPathComponent:@"tdlib"];

	int SETUP_API_ID(apiId)
	char * SETUP_API_HASH(apiHash)

	UIDevice *dev = [UIDevice currentDevice];

	// The key this app set through Debug Menu, if any. An empty string is
	// TDLib's unencrypted database, which is how every install starts.
	NSData *databaseKey = [TGDatabaseKey currentKey];

	[self send:@{
		@"@type"                  : @"setTdlibParameters",
		@"database_directory"     : db,
		@"files_directory"        : [db stringByAppendingPathComponent:@"files"],
		@"database_encryption_key": TGBase64Encode(databaseKey),
		@"use_message_database"   : @YES,
		// Chat rows and downloaded files have to survive a launch, or every
		// start is a cold sync: the list, avatars and media are fetched again.
		@"use_chat_info_database" : @YES,
		@"use_file_database"      : @YES,
		@"use_secret_chats"       : @NO,
		@"api_id"                 : @(apiId),
		@"api_hash"               : [NSString stringWithUTF8String:apiHash],
		@"system_language_code"   : @"en",
		@"device_model"           : dev.model ?: @"iPhone",
		@"system_version"         : dev.systemVersion ?: @"7.1.2",
		@"application_version"    : @"1.0",
	}];
}

@end
