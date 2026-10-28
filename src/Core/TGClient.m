#import "TGClientInternal.h"
#import "TGCall.h"
#import "TGJson.h"
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

NSString *const TGChatReadOutboxChangedNotification = @"TGChatReadOutboxChangedNotification";
NSString *const TGConnectionStateChangedNotification = @"TGConnectionStateChangedNotification";
NSString *const TGUserStatusChangedNotification = @"TGUserStatusChangedNotification";
NSString *const TGChatActionBarChangedNotification = @"TGChatActionBarChangedNotification";

@implementation TGClient

- (NSUInteger)chatsCached {
	return self.chatsById.count;
}

+ (instancetype)shared {
	static TGClient *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		s = [[TGClient alloc] init];
		s.chatsById = [NSMutableDictionary dictionary];
		s.usersById = [NSMutableDictionary dictionary];
		s.rawUsersById = [NSMutableDictionary dictionary];
		s.userPhotosById = [NSMutableDictionary dictionary];
		s.forumSupergroups = [NSMutableDictionary dictionary];
		s.archivedChats = @[];
		s.folders = @[];
		s.chats = @[];
		s.outbox = [NSMutableArray array];
		s.pendingRequests = [NSMutableDictionary dictionary];
		s.fileWaiters = [NSMutableDictionary dictionary];
		s.fileWaiterPriorities = [NSMutableDictionary dictionary];
		s.outboxLock = [[NSLock alloc] init];
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
			NSDictionary *obj = TGJsonParse(res, resLen, &err);
			if ([obj isKindOfClass:NSDictionary.class]){
				[batch addObject:obj];
			} else {
				NSLog(@"TGClient: bad JSON: %@", err);
			}

			// Drain further available updates immediately without waiting
			while (batch.count < 64 && self.running){
				const char *next = self.td_recv(self.client, 0.002);
				if (!next)
					break;
				size_t nextLen = strlen(next);
				NSDictionary *nextObj = TGJsonParse(next, nextLen, nil);
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

	if ([type isEqualToString:@"updateAuthorizationState"]){
		[self handleAuthState:obj[@"authorization_state"]];
		return;
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
	if ([type isEqualToString:@"updateUser"]){
		NSDictionary *u = obj[@"user"];
		if (u[@"id"]){
			if (!self.rawUsersById)
				self.rawUsersById = [NSMutableDictionary dictionary];
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
		return;
	}

	// Live message updates - without these a chat only refreshes when reopened.
	if ([type isEqualToString:@"updateNewMessage"]){
		NSDictionary *m = obj[@"message"];
		if (self.onMessage && m)
			self.onMessage([m[@"chat_id"] longLongValue], TGFlattenMessage(m), 0);
		return;
	}
	if ([type isEqualToString:@"updateMessageContent"]){
		// Content changed in place (a photo finished uploading, a text edited).
		if (self.onMessage)
			self.onMessage([obj[@"chat_id"] longLongValue], nil, 0);
		return;
	}
	if ([type isEqualToString:@"updateDeleteMessages"]){
		if ([obj[@"is_permanent"] boolValue] && self.onMessage){
			int64_t chatId = [obj[@"chat_id"] longLongValue];
			for (NSNumber *mid in obj[@"message_ids"])
				self.onMessage(chatId, nil, [mid longLongValue]);
		}
		return;
	}
	if ([type isEqualToString:@"updateNewChat"]){
		[self mergeChat:obj[@"chat"]];
		return;
	}
	if ([type isEqualToString:@"updateChatLastMessage"] ||
		[type isEqualToString:@"updateChatPosition"] ||
		[type isEqualToString:@"updateChatTitle"] ||
		[type isEqualToString:@"updateChatReadInbox"] ||
		[type isEqualToString:@"updateChatReadOutbox"] ||
		[type isEqualToString:@"updateChatNotificationSettings"]){
		[self applyChatUpdate:obj];
		return;
	}
	if ([type isEqualToString:@"updateConnectionState"]){
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
	if ([type isEqualToString:@"updateSecretChat"]){
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

	if ([type isEqualToString:@"updateNewCallSignalingData"]){
		NSData *data = [[NSData alloc] initWithBase64EncodedString:obj[@"data"] options:0];
		NSLog(@"TGClient: <<< updateNewCallSignalingData call_id=%@ len=%lu", obj[@"call_id"], (unsigned long)data.length);
		[[TGCall shared] handleSignalingData:data];
		return;
	}

	if ([type isEqualToString:@"updateCall"]){
		NSLog(@"TGClient: <<< updateCall: %@", obj[@"call"]);
		// TDLib signals the call; TGCall owns the audio.
		[[TGCall shared] handleUpdate:obj[@"call"]];
		return;
	}

	if ([type isEqualToString:@"updateFile"]){
		NSDictionary *file = obj[@"file"];
		NSInteger fid = [file[@"id"] integerValue];
		NSDictionary *local = file[@"local"];
		if (self.onFileProgress && [local[@"is_downloading_active"] boolValue]){
			double expected = [file[@"expected_size"] doubleValue];
			double got = [local[@"downloaded_size"] doubleValue];
			if (expected > 0)
				self.onFileProgress(fid, (float)(got / expected));
		}
		BOOL done = [local[@"is_downloading_completed"] boolValue];
		NSString *path = local[@"path"];
		if (done && path.length){
			[self notifyFileWaiters:fid path:path];
		}
		return;
	}

	if ([type isEqualToString:@"updateChatAction"]){
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
			[self rebuildChats];
		}
		if (self.onChatAction)
			self.onChatAction(actingChat, phrase);
		return;
	}

	// Whether a supergroup is a forum is a property of the supergroup, not of
	// the chat, and it arrives in an update of its own. Chats already built
	// from that supergroup have to be told.
	if ([type isEqualToString:@"updateSupergroup"]){
		NSDictionary *group = obj[@"supergroup"];
		NSNumber *groupId = group[@"id"];
		if (!groupId)
			return;
		BOOL isForum = [group[@"is_forum"] boolValue];
		if ([self.forumSupergroups[groupId] boolValue] == isForum &&
			self.forumSupergroups[groupId])
			return;
		self.forumSupergroups[groupId] = @(isForum);

		BOOL changed = NO;
		for (NSMutableDictionary *chat in self.chatsById.allValues){
			if (![chat[@"supergroupId"] isEqual:groupId])
				continue;
			chat[@"isForum"] = @(isForum);
			changed = YES;
		}
		if (changed)
			[self rebuildChats];
		return;
	}

	// A private chat's id is the user's id, so presence lands straight on the
	// chat the list is drawing.
	if ([type isEqualToString:@"updateUserStatus"]){
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
		[self rebuildChats];
		return;
	}

	if ([type isEqualToString:@"updateChatActionBar"]){
		// The bar over a chat nobody knows follows the update, not only the
		// fetch; whichever chat is open hears the notification and redraws.
		int64_t chatId = [obj[@"chat_id"] longLongValue];
		NSMutableDictionary *row = self.chatsById[@(chatId)];
		if (row){
			[self mergeActionBar:obj[@"action_bar"] intoChatRow:row];
			[self rebuildChats];
		}
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGChatActionBarChangedNotification
							  object:@(chatId)];
		return;
	}

	if ([type isEqualToString:@"updateChatFolders"]){
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
	if ([type isEqualToString:@"updateUnreadChatCount"]){
		NSLog(@"TGClient: %@ total=%@ list=%@", type, obj[@"total_count"],
				obj[@"chat_list"][@"@type"]);
		return;
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
		s = TGAuthStateClosed;
		self.running = NO;
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

	[self send:@{
		@"@type"                  : @"setTdlibParameters",
		@"database_directory"     : db,
		@"files_directory"        : [db stringByAppendingPathComponent:@"files"],
		@"use_message_database"   : @YES,
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
