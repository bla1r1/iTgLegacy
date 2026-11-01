//
// TGClient+GroupCalls.m - group calls and video chats on the wire.
//
// Every request here names a group call id or the chat a video chat belongs
// to. TDLib answers a whole groupCall record, an opaque join payload, or
// bytes; the flattening below turns the record into the keys the two call
// screens read. Participants arrive as updates, so they are kept per call and
// handed to the screen through one notification instead of a polling loop.
//
#import "TGClient+GroupCalls.h"
#import "TGClientInternal.h"
#import "TGBase64.h"
#import <objc/runtime.h>

NSString * const TGGroupCallChangedNotification = @"TGGroupCallChanged";
NSString * const TGGroupCallParticipantsChangedNotification = @"TGGroupCallParticipantsChanged";
NSString * const TGGroupCallMessagesChangedNotification = @"TGGroupCallMessagesChanged";

NSString * const TGGroupCallIdKey = @"groupCallId";
NSString * const TGGroupCallValueKey = @"value";
NSString * const TGGroupCallErrorKey = @"error";

NSDictionary *TGGroupCallJoinParameters(int32_t audioSourceId, NSString *payload,
		BOOL muted, BOOL videoEnabled) {
	return @{
		@"@type" : @"groupCallJoinParameters",
		@"audio_source_id" : @(audioSourceId),
		@"payload" : payload ?: @"",
		@"is_muted" : @(muted),
		@"is_my_video_enabled" : @(videoEnabled),
	};
}

NSDictionary *TGGroupCallInput(int32_t groupCallId, int64_t accessHash) {
	return @{
		@"@type" : @"inputGroupCall",
		@"id" : @(groupCallId),
		@"access_hash" : @(accessHash),
	};
}

#pragma mark - helpers

/// Every answer in this file goes through these two: a request either says
/// ok or carries an error object, and nil message means Telegram's own words
/// were empty rather than a success.
static NSString *TGGCErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static BOOL TGGCSucceeded(NSDictionary *result) {
	return ![result[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGGCDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *TGGCArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

/// The sender's identity as one dictionary key. Chat participants (a channel
/// posting into a group call) and users share the participant list, so the
/// type has to be part of the key or two id 42s would overwrite each other.
static NSString *TGGCSenderKey(NSDictionary *sender) {
	if ([sender[@"@type"] isEqualToString:@"messageSenderChat"])
		return [NSString stringWithFormat:@"c:%lld",
				[sender[@"chat_id"] longLongValue]];
	return [NSString stringWithFormat:@"u:%lld",
			[sender[@"user_id"] longLongValue]];
}

static NSDictionary *TGGCSenderOrNull(id sender) {
	return [sender isKindOfClass:NSDictionary.class] ? sender : (id)[NSNull null];
}

static NSDictionary *TGGCSenderFlatten(TGClient *client, NSDictionary *sender) {
	NSDictionary *raw = [sender isKindOfClass:NSDictionary.class] ? sender : @{};
	if ([raw[@"@type"] isEqualToString:@"messageSenderChat"]){
		int64_t chatId = [raw[@"chat_id"] longLongValue];
		NSString *name = [client titleForChat:chatId] ?: @"";
		return @{
			@"sender" : raw,
			@"senderKey" : TGGCSenderKey(raw),
			@"userId" : @(0),
			@"chatId" : @(chatId),
			@"kind" : @"chat",
			@"name" : name,
			@"photoFileId" : [client photoFileIdForChat:chatId] ?: [NSNull null],
		};
	}
	int64_t userId = [raw[@"user_id"] longLongValue];
	NSString *name = [client nameForUserId:userId] ?: @"";
	if (!name.length && [client.me[@"id"] longLongValue] == userId)
		name = [NSString stringWithFormat:@"%@ %@", client.me[@"first_name"] ?: @"",
				client.me[@"last_name"] ?: @""];
	return @{
		@"sender" : raw,
		@"senderKey" : TGGCSenderKey(raw),
		@"userId" : @(userId),
		@"chatId" : @(0),
		@"kind" : @"user",
		@"name" : [name stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]],
		@"photoFileId" : [client photoFileIdForUserId:userId] ?: [NSNull null],
	};
}

/// The three video-quality values TDLib accepts, or null for the worst one.
static id TGGCVideoQuality(NSString *quality) {
	if ([quality isEqualToString:@"thumbnail"])
		return @{@"@type" : @"groupCallVideoQualityThumbnail"};
	if ([quality isEqualToString:@"medium"])
		return @{@"@type" : @"groupCallVideoQualityMedium"};
	if ([quality isEqualToString:@"full"])
		return @{@"@type" : @"groupCallVideoQualityFull"};
	return [NSNull null];
}

static id TGGCDataChannel(NSString *channel) {
	if ([channel isEqualToString:@"screenSharing"])
		return @{@"@type" : @"groupCallDataChannelScreenSharing"};
	return @{@"@type" : @"groupCallDataChannelMain"};
}

#pragma mark - the per-call state

static char TGGroupCallStateKey;

static NSMutableDictionary *TGGCState(TGClient *client) {
	NSMutableDictionary *state = objc_getAssociatedObject(client, &TGGroupCallStateKey);
	if (![state isKindOfClass:NSMutableDictionary.class]){
		state = [NSMutableDictionary dictionaryWithDictionary:@{
			@"calls" : [NSMutableDictionary dictionary],
			@"participants" : [NSMutableDictionary dictionary],
			@"messages" : [NSMutableDictionary dictionary],
		}];
		objc_setAssociatedObject(client, &TGGroupCallStateKey, state,
				OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return state;
}

static NSMutableDictionary *TGGCCalls(TGClient *client) {
	return TGGCState(client)[@"calls"];
}

static NSMutableDictionary *TGGCParticipants(TGClient *client, int32_t callId) {
	NSMutableDictionary *all = TGGCState(client)[@"participants"];
	NSNumber *key = @(callId);
	NSMutableDictionary *rows = all[key];
	if (!rows){
		rows = [NSMutableDictionary dictionary];
		all[key] = rows;
	}
	return rows;
}

static NSMutableArray *TGGCMessages(TGClient *client, int32_t callId) {
	NSMutableDictionary *all = TGGCState(client)[@"messages"];
	NSNumber *key = @(callId);
	NSMutableArray *rows = all[key];
	if (!rows){
		rows = [NSMutableArray array];
		all[key] = rows;
	}
	return rows;
}

/// One groupCall record as the screens read it. The raw record is kept under
/// "raw" so a screen that needs a field this list has not grown yet does not
/// have to make a second request.
static NSDictionary *TGGCFlattenCall(NSDictionary *call) {
	NSDictionary *raw = [call isKindOfClass:NSDictionary.class] ? call : @{};
	NSMutableArray *speakers = [NSMutableArray array];
	for (NSDictionary *speaker in TGGCArray(raw[@"recent_speakers"])){
		NSDictionary *row = TGGCDict(speaker);
		[speakers addObject:@{
			@"sender" : TGGCSenderOrNull(row[@"participant_id"]),
			@"isSpeaking" : @([row[@"is_speaking"] boolValue]),
		}];
	}
	return @{
		@"callId" : @([raw[@"id"] intValue]),
		@"uniqueId" : @([raw[@"unique_id"] longLongValue]),
		@"title" : raw[@"title"] ?: @"",
		@"inviteLink" : raw[@"invite_link"] ?: @"",
		@"paidMessageStarCount" : @([raw[@"paid_message_star_count"] longLongValue]),
		@"scheduledStartDate" : @([raw[@"scheduled_start_date"] intValue]),
		@"enabledStartNotification" : @([raw[@"enabled_start_notification"] boolValue]),
		@"isActive" : @([raw[@"is_active"] boolValue]),
		@"isVideoChat" : @([raw[@"is_video_chat"] boolValue]),
		@"isLiveStory" : @([raw[@"is_live_story"] boolValue]),
		@"isRtmpStream" : @([raw[@"is_rtmp_stream"] boolValue]),
		@"isJoined" : @([raw[@"is_joined"] boolValue]),
		@"needRejoin" : @([raw[@"need_rejoin"] boolValue]),
		@"isOwned" : @([raw[@"is_owned"] boolValue]),
		@"canBeManaged" : @([raw[@"can_be_managed"] boolValue]),
		@"participantCount" : @([raw[@"participant_count"] intValue]),
		@"hasHiddenListeners" : @([raw[@"has_hidden_listeners"] boolValue]),
		@"loadedAllParticipants" : @([raw[@"loaded_all_participants"] boolValue]),
		@"messageSender" : TGGCSenderOrNull(raw[@"message_sender_id"]),
		@"recentSpeakers" : speakers,
		@"isMyVideoEnabled" : @([raw[@"is_my_video_enabled"] boolValue]),
		@"isMyVideoPaused" : @([raw[@"is_my_video_paused"] boolValue]),
		@"canEnableVideo" : @([raw[@"can_enable_video"] boolValue]),
		@"muteNewParticipants" : @([raw[@"mute_new_participants"] boolValue]),
		@"canToggleMuteNewParticipants" : @([raw[@"can_toggle_mute_new_participants"] boolValue]),
		@"canSendMessages" : @([raw[@"can_send_messages"] boolValue]),
		@"areMessagesAllowed" : @([raw[@"are_messages_allowed"] boolValue]),
		@"canToggleAreMessagesAllowed" : @([raw[@"can_toggle_are_messages_allowed"] boolValue]),
		@"canDeleteMessages" : @([raw[@"can_delete_messages"] boolValue]),
		@"recordDuration" : @([raw[@"record_duration"] intValue]),
		@"isVideoRecorded" : @([raw[@"is_video_recorded"] boolValue]),
		@"duration" : @([raw[@"duration"] intValue]),
		@"raw" : raw,
	};
}

static NSDictionary *TGGCVideoInfo(id value) {
	NSDictionary *info = [value isKindOfClass:NSDictionary.class] ? value : nil;
	if (!info)
		return @{@"hasVideo" : @NO, @"isPaused" : @NO, @"sources" : @[]};
	NSMutableArray *sources = [NSMutableArray array];
	for (NSDictionary *group in TGGCArray(info[@"source_groups"])){
		NSDictionary *row = TGGCDict(group);
		[sources addObject:@{
			@"semantics" : row[@"semantics"] ?: @"",
			@"sourceIds" : TGGCArray(row[@"source_ids"]),
		}];
	}
	return @{
		@"hasVideo" : @YES,
		@"isPaused" : @([info[@"is_paused"] boolValue]),
		@"endpointId" : info[@"endpoint_id"] ?: @"",
		@"sources" : sources,
	};
}

static NSDictionary *TGGCFlattenParticipant(TGClient *client, NSDictionary *participant) {
	NSDictionary *raw = [participant isKindOfClass:NSDictionary.class] ? participant : @{};
	NSDictionary *sender = TGGCSenderFlatten(client, TGGCDict(raw[@"participant_id"]));
	NSDictionary *video = TGGCVideoInfo(raw[@"video_info"]);
	NSDictionary *screen = TGGCVideoInfo(raw[@"screen_sharing_video_info"]);
	NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:sender];
	row[@"audioSourceId"] = @([raw[@"audio_source_id"] intValue]);
	row[@"screenAudioSourceId"] = @([raw[@"screen_sharing_audio_source_id"] intValue]);
	row[@"bio"] = raw[@"bio"] ?: @"";
	row[@"isCurrentUser"] = @([raw[@"is_current_user"] boolValue]);
	row[@"isSpeaking"] = @([raw[@"is_speaking"] boolValue]);
	row[@"isHandRaised"] = @([raw[@"is_hand_raised"] boolValue]);
	row[@"canBeMutedForAllUsers"] = @([raw[@"can_be_muted_for_all_users"] boolValue]);
	row[@"canBeUnmutedForAllUsers"] = @([raw[@"can_be_unmuted_for_all_users"] boolValue]);
	row[@"canBeMutedForCurrentUser"] = @([raw[@"can_be_muted_for_current_user"] boolValue]);
	row[@"canBeUnmutedForCurrentUser"] = @([raw[@"can_be_unmuted_for_current_user"] boolValue]);
	row[@"isMutedForAllUsers"] = @([raw[@"is_muted_for_all_users"] boolValue]);
	row[@"isMutedForCurrentUser"] = @([raw[@"is_muted_for_current_user"] boolValue]);
	row[@"canUnmuteSelf"] = @([raw[@"can_unmute_self"] boolValue]);
	row[@"volumeLevel"] = @([raw[@"volume_level"] intValue]);
	row[@"order"] = raw[@"order"] ?: @"";
	row[@"hasVideo"] = video[@"hasVideo"];
	row[@"videoPaused"] = video[@"isPaused"];
	row[@"videoInfo"] = video;
	row[@"screenInfo"] = screen;
	row[@"raw"] = raw;
	return row;
}

static NSDictionary *TGGCFlattenMessage(TGClient *client, NSDictionary *message) {
	NSDictionary *raw = [message isKindOfClass:NSDictionary.class] ? message : @{};
	NSDictionary *sender = TGGCSenderFlatten(client, TGGCDict(raw[@"sender_id"]));
	NSDictionary *text = TGGCDict(raw[@"text"]);
	return @{
		@"messageId" : @([raw[@"message_id"] intValue]),
		@"sender" : sender[@"sender"],
		@"senderKey" : sender[@"senderKey"],
		@"senderName" : sender[@"name"],
		@"date" : @([raw[@"date"] intValue]),
		@"text" : text[@"text"] ?: @"",
		@"paidStarCount" : @([raw[@"paid_message_star_count"] longLongValue]),
		@"isFromOwner" : @([raw[@"is_from_owner"] boolValue]),
		@"canBeDeleted" : @([raw[@"can_be_deleted"] boolValue]),
	};
}

@implementation TGClient (GroupCalls)

#pragma mark - calls and participation

- (void)groupCall:(int32_t)groupCallId
	   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"getGroupCall", @"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *call = TGGCFlattenCall(result);
		TGGCCalls(self)[@(groupCallId)] = call;
		if (completion) completion(call, nil);
	}];
}

- (void)createVideoChatInChat:(int64_t)chatId
						title:(NSString *)title
					startDate:(int32_t)startDate
					   isRtmp:(BOOL)isRtmp
				   completion:(void (^)(int32_t, NSString *))completion {
	if (!chatId){
		if (completion) completion(0, @"Name the chat the video chat belongs to.");
		return;
	}
	// TDLib's window: 0 now, or at least ten seconds and at most eight days.
	if (startDate > 0){
		NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
		if (startDate < now + 10 || startDate > now + 8 * 86400){
			if (completion) completion(0, @"A scheduled video chat starts between "
					"10 seconds and 8 days from now.");
			return;
		}
	}
	[self request:@{
		@"@type" : @"createVideoChat",
		@"chat_id" : @(chatId),
		@"title" : title ?: @"",
		@"start_date" : @(startDate),
		@"is_rtmp_stream" : @(isRtmp),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(0, TGGCErrorText(result));
			return;
		}
		// The answer is groupCallId, a plain int32.
		int32_t callId = [result[@"id"] intValue];
		if (!callId)
			callId = [result[@"group_call_id"] intValue];
		if (!callId){
			if (completion) completion(0, @"Telegram did not name the new video chat.");
			return;
		}
		if (completion) completion(callId, nil);
	}];
}

- (void)createGroupCallWithParameters:(NSDictionary *)parameters
						   completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"createGroupCall",
		@"join_parameters" : [parameters isKindOfClass:NSDictionary.class]
				? parameters : (id)[NSNull null],
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *info = @{
			@"groupCallId" : @([result[@"group_call_id"] intValue]),
			@"joinPayload" : result[@"join_payload"] ?: @"",
		};
		if (completion) completion(info, nil);
	}];
}

- (void)joinGroupCallWithInput:(NSDictionary *)input
					parameters:(NSDictionary *)parameters
					completion:(void (^)(NSDictionary *, NSString *))completion {
	if (![input isKindOfClass:NSDictionary.class] || ![input[@"id"] intValue]){
		if (completion) completion(nil, @"An inputGroupCall is required to join.");
		return;
	}
	[self request:@{
		@"@type" : @"joinGroupCall",
		@"input_group_call" : input,
		@"join_parameters" : [parameters isKindOfClass:NSDictionary.class]
				? parameters : TGGroupCallJoinParameters(0, @"", NO, NO),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *info = @{
			@"groupCallId" : @([result[@"group_call_id"] intValue]),
			@"joinPayload" : result[@"join_payload"] ?: @"",
		};
		if (completion) completion(info, nil);
	}];
}

- (void)joinVideoChat:(int32_t)groupCallId
		  participant:(NSDictionary *)participant
		   parameters:(NSDictionary *)parameters
		   inviteHash:(NSString *)inviteHash
		   completion:(void (^)(NSString *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the video chat.");
		return;
	}
	[self request:@{
		@"@type" : @"joinVideoChat",
		@"group_call_id" : @(groupCallId),
		@"participant_id" : TGGCSenderOrNull(participant),
		@"join_parameters" : [parameters isKindOfClass:NSDictionary.class]
				? parameters : TGGroupCallJoinParameters(0, @"", NO, NO),
		@"invite_hash" : inviteHash ?: @"",
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		// TDLib's Text answer keeps its string in "text".
		if (completion) completion(result[@"text"] ?: @"", nil);
	}];
}

- (void)leaveGroupCall:(int32_t)groupCallId
			completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"leaveGroupCall", @"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)endGroupCall:(int32_t)groupCallId
		  completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"endGroupCall", @"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)startScheduledVideoChat:(int32_t)groupCallId
					 completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the video chat.");
		return;
	}
	[self request:@{@"@type" : @"startScheduledVideoChat",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)groupCallParticipantsWithInput:(NSDictionary *)input
								 limit:(NSInteger)limit
							completion:(void (^)(NSDictionary *, NSString *))completion {
	if (![input isKindOfClass:NSDictionary.class] || ![input[@"id"] intValue]){
		if (completion) completion(nil, @"An inputGroupCall is required.");
		return;
	}
	[self request:@{
		@"@type" : @"getGroupCallParticipants",
		@"input_group_call" : input,
		@"limit" : @(MAX(1, limit)),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *answer = @{
			@"total" : @([result[@"total_count"] intValue]),
			@"senders" : TGGCArray(result[@"participant_ids"]),
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)loadGroupCallParticipants:(int32_t)groupCallId
							limit:(NSInteger)limit
					   completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"loadGroupCallParticipants",
		@"group_call_id" : @(groupCallId),
		@"limit" : @(MAX(1, MIN(100, limit))),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

#pragma mark - participants

- (void)toggleGroupCallParticipant:(NSDictionary *)participant
							inCall:(int32_t)groupCallId
							isMuted:(BOOL)muted
						completion:(void (^)(BOOL, NSString *))completion {
	if (![participant isKindOfClass:NSDictionary.class] || !groupCallId){
		if (completion) completion(NO, @"Name the participant and the call.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleGroupCallParticipantIsMuted",
		@"group_call_id" : @(groupCallId),
		@"participant_id" : participant,
		@"is_muted" : @(muted),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)setGroupCallParticipant:(NSDictionary *)participant
						 inCall:(int32_t)groupCallId
					volumeLevel:(NSInteger)volumeLevel
					 completion:(void (^)(BOOL, NSString *))completion {
	if (![participant isKindOfClass:NSDictionary.class] || !groupCallId){
		if (completion) completion(NO, @"Name the participant and the call.");
		return;
	}
	// TDLib's range is 1-20000 in hundredths of a percent. Clamping here
	// keeps a bad slider value from becoming a server-side error sentence.
	NSInteger level = MAX(1, MIN(20000, volumeLevel));
	[self request:@{
		@"@type" : @"setGroupCallParticipantVolumeLevel",
		@"group_call_id" : @(groupCallId),
		@"participant_id" : participant,
		@"volume_level" : @(level),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)toggleGroupCallParticipant:(NSDictionary *)participant
							inCall:(int32_t)groupCallId
					  isHandRaised:(BOOL)raised
						completion:(void (^)(BOOL, NSString *))completion {
	if (![participant isKindOfClass:NSDictionary.class] || !groupCallId){
		if (completion) completion(NO, @"Name the participant and the call.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleGroupCallParticipantIsHandRaised",
		@"group_call_id" : @(groupCallId),
		@"participant_id" : participant,
		@"is_hand_raised" : @(raised),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)setGroupCallParticipantSpeaking:(int32_t)audioSource
								 inCall:(int32_t)groupCallId
							  isSpeaking:(BOOL)speaking
							  completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"setGroupCallParticipantIsSpeaking",
		@"group_call_id" : @(groupCallId),
		@"audio_source" : @(audioSource),
		@"is_speaking" : @(speaking),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		// The answer is the participant TDLib matched, or a bare MessageSender.
		NSDictionary *sender = [result[@"@type"] isEqualToString:@"messageSenderUser"] ||
				[result[@"@type"] isEqualToString:@"messageSenderChat"]
				? result : TGGCDict(result[@"participant_id"]);
		if (completion) completion(sender[@"@type"] ? sender : nil, nil);
	}];
}

- (void)inviteGroupCallParticipant:(int64_t)userId
							toCall:(int32_t)groupCallId
							isVideo:(BOOL)isVideo
						 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!userId || !groupCallId){
		if (completion) completion(nil, @"Name the user and the call.");
		return;
	}
	[self request:@{
		@"@type" : @"inviteGroupCallParticipant",
		@"group_call_id" : @(groupCallId),
		@"user_id" : @(userId),
		@"is_video" : @(isVideo),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSString *type = result[@"@type"] ?: @"";
		NSString *outcome = @"success";
		if ([type isEqualToString:@"inviteGroupCallParticipantResultUserPrivacyRestricted"])
			outcome = @"privacy";
		else if ([type isEqualToString:@"inviteGroupCallParticipantResultUserAlreadyParticipant"])
			outcome = @"already";
		else if ([type isEqualToString:@"inviteGroupCallParticipantResultUserWasBanned"])
			outcome = @"banned";
		NSDictionary *answer = @{
			@"outcome" : outcome,
			@"chatId" : @([result[@"chat_id"] longLongValue]),
			@"messageId" : @([result[@"message_id"] longLongValue]),
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)inviteVideoChatParticipants:(NSArray *)userIds
							 toCall:(int32_t)groupCallId
						 completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId || ![userIds isKindOfClass:NSArray.class] || !userIds.count){
		if (completion) completion(NO, @"Name the call and at least one user.");
		return;
	}
	[self request:@{
		@"@type" : @"inviteVideoChatParticipants",
		@"group_call_id" : @(groupCallId),
		@"user_ids" : userIds,
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)banGroupCallParticipants:(NSArray *)userIds
						  inCall:(int32_t)groupCallId
					  completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId || ![userIds isKindOfClass:NSArray.class] || !userIds.count){
		if (completion) completion(NO, @"Name the call and at least one user.");
		return;
	}
	[self request:@{
		@"@type" : @"banGroupCallParticipants",
		@"group_call_id" : @(groupCallId),
		@"user_ids" : userIds,
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)declineGroupCallInvitationInChat:(int64_t)chatId
							   messageId:(int64_t)messageId
							  completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || !messageId){
		if (completion) completion(NO, @"Name the invitation message.");
		return;
	}
	[self request:@{
		@"@type" : @"declineGroupCallInvitation",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

#pragma mark - the call's own settings

- (void)setVideoChatTitle:(NSString *)title
				   inCall:(int32_t)groupCallId
			   completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [title stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!groupCallId || !clean.length || clean.length > 64){
		if (completion) completion(NO, @"A video chat title is 1 to 64 characters.");
		return;
	}
	[self request:@{
		@"@type" : @"setVideoChatTitle",
		@"group_call_id" : @(groupCallId),
		@"title" : clean,
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)toggleVideoChatMuteNewParticipants:(int32_t)groupCallId
									muted:(BOOL)muted
							   completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the video chat.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleVideoChatMuteNewParticipants",
		@"group_call_id" : @(groupCallId),
		@"mute_new_participants" : @(muted),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)toggleGroupCallMessagesAllowed:(int32_t)groupCallId
							   allowed:(BOOL)allowed
							completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleGroupCallAreMessagesAllowed",
		@"group_call_id" : @(groupCallId),
		@"are_messages_allowed" : @(allowed),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)toggleVideoChatStartNotification:(int32_t)groupCallId
								   enabled:(BOOL)enabled
								completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the video chat.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleVideoChatEnabledStartNotification",
		@"group_call_id" : @(groupCallId),
		@"enabled_start_notification" : @(enabled),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)toggleGroupCallMyVideoEnabled:(int32_t)groupCallId
							  enabled:(BOOL)enabled
						   completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleGroupCallIsMyVideoEnabled",
		@"group_call_id" : @(groupCallId),
		@"is_my_video_enabled" : @(enabled),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)toggleGroupCallMyVideoPaused:(int32_t)groupCallId
							  paused:(BOOL)paused
						  completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleGroupCallIsMyVideoPaused",
		@"group_call_id" : @(groupCallId),
		@"is_my_video_paused" : @(paused),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

#pragma mark - recording and screen sharing

- (void)startGroupCallRecording:(int32_t)groupCallId
						  title:(NSString *)title
					recordVideo:(BOOL)recordVideo
					   portrait:(BOOL)portrait
					 completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [title stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!groupCallId || clean.length > 64){
		if (completion) completion(NO, @"A recording title is at most 64 characters.");
		return;
	}
	[self request:@{
		@"@type" : @"startGroupCallRecording",
		@"group_call_id" : @(groupCallId),
		@"title" : clean ?: @"",
		@"record_video" : @(recordVideo),
		@"use_portrait_orientation" : @(portrait && recordVideo),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)endGroupCallRecording:(int32_t)groupCallId
				   completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"endGroupCallRecording",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)startGroupCallScreenSharing:(int32_t)groupCallId
					 audioSourceId:(int32_t)audioSourceId
						   payload:(NSString *)payload
						completion:(void (^)(NSString *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"startGroupCallScreenSharing",
		@"group_call_id" : @(groupCallId),
		@"audio_source_id" : @(audioSourceId),
		@"payload" : payload ?: @"",
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		if (completion) completion(result[@"text"] ?: @"", nil);
	}];
}

- (void)toggleGroupCallScreenSharingPaused:(int32_t)groupCallId
									paused:(BOOL)paused
								completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"toggleGroupCallScreenSharingIsPaused",
		@"group_call_id" : @(groupCallId),
		@"is_paused" : @(paused),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)endGroupCallScreenSharing:(int32_t)groupCallId
					   completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"endGroupCallScreenSharing",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

#pragma mark - invite links and RTMP

- (void)videoChatInviteLink:(int32_t)groupCallId
			 canSelfUnmute:(BOOL)canSelfUnmute
				completion:(void (^)(NSString *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the video chat.");
		return;
	}
	[self request:@{
		@"@type" : @"getVideoChatInviteLink",
		@"group_call_id" : @(groupCallId),
		@"can_self_unmute" : @(canSelfUnmute),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		if (completion) completion(result[@"url"] ?: @"", nil);
	}];
}

- (void)revokeGroupCallInviteLink:(int32_t)groupCallId
					   completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(NO, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"revokeGroupCallInviteLink",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)videoChatRtmpUrlForChat:(int64_t)chatId
					 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"Name the chat.");
		return;
	}
	[self request:@{@"@type" : @"getVideoChatRtmpUrl", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *answer = @{
			@"url" : result[@"url"] ?: @"",
			@"streamKey" : result[@"stream_key"] ?: @"",
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)replaceVideoChatRtmpUrlForChat:(int64_t)chatId
							completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"Name the chat.");
		return;
	}
	[self request:@{@"@type" : @"replaceVideoChatRtmpUrl", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *answer = @{
			@"url" : result[@"url"] ?: @"",
			@"streamKey" : result[@"stream_key"] ?: @"",
		};
		if (completion) completion(answer, nil);
	}];
}

#pragma mark - who a video chat is joined as

- (void)videoChatAvailableParticipantsForChat:(int64_t)chatId
								   completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!chatId){
		if (completion) completion(nil, @"Name the chat.");
		return;
	}
	[self request:@{@"@type" : @"getVideoChatAvailableParticipants",
					@"chat_id" : @(chatId)}
	   completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSDictionary *answer = @{
			@"total" : @([result[@"total_count"] intValue]),
			@"senders" : TGGCArray(result[@"senders"]),
		};
		if (completion) completion(answer, nil);
	}];
}

- (void)setVideoChatDefaultParticipant:(NSDictionary *)participant
							   forChat:(int64_t)chatId
							completion:(void (^)(BOOL, NSString *))completion {
	if (!chatId || ![participant isKindOfClass:NSDictionary.class]){
		if (completion) completion(NO, @"Name the chat and the participant.");
		return;
	}
	[self request:@{
		@"@type" : @"setVideoChatDefaultParticipant",
		@"chat_id" : @(chatId),
		@"default_participant_id" : participant,
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

#pragma mark - messages in a call

- (void)sendGroupCallMessage:(NSString *)text
					  inCall:(int32_t)groupCallId
			   paidStarCount:(int64_t)paidStarCount
				  completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!groupCallId || !clean.length){
		if (completion) completion(NO, @"Write the message and name the call.");
		return;
	}
	[self request:@{
		@"@type" : @"sendGroupCallMessage",
		@"group_call_id" : @(groupCallId),
		@"text" : @{
			@"@type" : @"formattedText",
			@"text" : clean,
			@"entities" : @[],
		},
		@"paid_message_star_count" : @(MAX(0, paidStarCount)),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)deleteGroupCallMessages:(NSArray *)messageIds
						 inCall:(int32_t)groupCallId
					 reportSpam:(BOOL)reportSpam
					 completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId || ![messageIds isKindOfClass:NSArray.class] || !messageIds.count){
		if (completion) completion(NO, @"Name the call and at least one message.");
		return;
	}
	[self request:@{
		@"@type" : @"deleteGroupCallMessages",
		@"group_call_id" : @(groupCallId),
		@"message_ids" : messageIds,
		@"report_spam" : @(reportSpam),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

- (void)deleteGroupCallMessagesBySender:(NSDictionary *)sender
								 inCall:(int32_t)groupCallId
							 reportSpam:(BOOL)reportSpam
							 completion:(void (^)(BOOL, NSString *))completion {
	if (!groupCallId || ![sender isKindOfClass:NSDictionary.class]){
		if (completion) completion(NO, @"Name the call and the sender.");
		return;
	}
	[self request:@{
		@"@type" : @"deleteGroupCallMessagesBySender",
		@"group_call_id" : @(groupCallId),
		@"sender_id" : sender,
		@"report_spam" : @(reportSpam),
	} completion:^(NSDictionary *result){
		BOOL ok = TGGCSucceeded(result);
		if (completion) completion(ok, ok ? nil : TGGCErrorText(result));
	}];
}

#pragma mark - streams and the data channel

- (void)groupCallStreams:(int32_t)groupCallId
			  completion:(void (^)(NSArray *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the group call.");
		return;
	}
	[self request:@{@"@type" : @"getGroupCallStreams",
					@"group_call_id" : @(groupCallId)}
	   completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		NSMutableArray *streams = [NSMutableArray array];
		for (NSDictionary *stream in TGGCArray(result[@"streams"])){
			NSDictionary *row = TGGCDict(stream);
			[streams addObject:@{
				@"channelId" : @([row[@"channel_id"] intValue]),
				@"scale" : @([row[@"scale"] intValue]),
				@"timeOffset" : @([row[@"time_offset"] longLongValue]),
			}];
		}
		if (completion) completion(streams, nil);
	}];
}

- (void)groupCallStreamSegment:(int32_t)groupCallId
					timeOffset:(int64_t)timeOffset
						 scale:(NSInteger)scale
					 channelId:(NSInteger)channelId
					   quality:(NSString *)quality
					completion:(void (^)(NSData *, NSString *))completion {
	if (!groupCallId){
		if (completion) completion(nil, @"Name the group call.");
		return;
	}
	[self request:@{
		@"@type" : @"getGroupCallStreamSegment",
		@"group_call_id" : @(groupCallId),
		@"time_offset" : @(timeOffset),
		@"scale" : @(scale),
		@"channel_id" : @(channelId),
		@"video_quality" : TGGCVideoQuality(quality),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		// Data crosses td_api as base64 in JSON; decode here so every caller
		// gets bytes rather than a string it has to remember to unwrap.
		NSData *data = TGBase64Decode(result[@"data"]);
		if (completion) completion(data, nil);
	}];
}

- (void)encryptGroupCallData:(NSData *)data
					  inCall:(int32_t)groupCallId
					 channel:(NSString *)channel
		 unencryptedPrefixSize:(NSInteger)prefixSize
				  completion:(void (^)(NSData *, NSString *))completion {
	if (!groupCallId || ![data isKindOfClass:NSData.class] || !data.length){
		if (completion) completion(nil, @"Name the call and the bytes to encrypt.");
		return;
	}
	[self request:@{
		@"@type" : @"encryptGroupCallData",
		@"group_call_id" : @(groupCallId),
		@"data_channel" : TGGCDataChannel(channel),
		@"data" : TGBase64Encode(data),
		@"unencrypted_prefix_size" : @(MAX(0, prefixSize)),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		if (completion) completion(TGBase64Decode(result[@"data"]), nil);
	}];
}

- (void)decryptGroupCallData:(NSData *)data
			  fromParticipant:(NSDictionary *)participant
					  inCall:(int32_t)groupCallId
					 channel:(NSString *)channel
				  completion:(void (^)(NSData *, NSString *))completion {
	if (!groupCallId || ![data isKindOfClass:NSData.class] || !data.length){
		if (completion) completion(nil, @"Name the call and the bytes to decrypt.");
		return;
	}
	[self request:@{
		@"@type" : @"decryptGroupCallData",
		@"group_call_id" : @(groupCallId),
		@"participant_id" : TGGCSenderOrNull(participant),
		@"data_channel" : TGGCDataChannel(channel),
		@"data" : TGBase64Encode(data),
	} completion:^(NSDictionary *result){
		if (!TGGCSucceeded(result)){
			if (completion) completion(nil, TGGCErrorText(result));
			return;
		}
		if (completion) completion(TGBase64Decode(result[@"data"]), nil);
	}];
}

#pragma mark - state the screens read

- (NSDictionary *)groupCallSnapshot:(int32_t)groupCallId {
	NSDictionary *call = TGGCCalls(self)[@(groupCallId)];
	return [call isKindOfClass:NSDictionary.class] ? call : nil;
}

- (NSArray *)groupCallParticipantSnapshot:(int32_t)groupCallId {
	NSMutableDictionary *rows = TGGCState(self)[@"participants"][@(groupCallId)];
	if (![rows isKindOfClass:NSDictionary.class] || !rows.count)
		return @[];
	NSArray *sorted = [[rows allValues] sortedArrayUsingComparator:
			^NSComparisonResult(NSDictionary *a, NSDictionary *b){
		return [b[@"order"] compare:a[@"order"]];
	}];
	return sorted;
}

- (NSArray *)groupCallMessageSnapshot:(int32_t)groupCallId {
	NSMutableArray *rows = TGGCState(self)[@"messages"][@(groupCallId)];
	return [rows isKindOfClass:NSArray.class] ? [rows copy] : @[];
}

- (NSDictionary *)currentGroupCallParticipant:(int32_t)groupCallId {
	for (NSDictionary *row in [self groupCallParticipantSnapshot:groupCallId])
		if ([row[@"isCurrentUser"] boolValue])
			return row;
	return nil;
}

#pragma mark - updates

- (void)applyGroupCallUpdate:(NSDictionary *)update {
	NSDictionary *call = TGGCDict(update[@"group_call"]);
	int32_t callId = [call[@"id"] intValue];
	if (!callId)
		return;
	NSDictionary *flat = TGGCFlattenCall(call);
	TGGCCalls(self)[@(callId)] = flat;
	[[NSNotificationCenter defaultCenter] postNotificationName:TGGroupCallChangedNotification
			object:self userInfo:@{TGGroupCallIdKey : @(callId), TGGroupCallValueKey : flat}];
}

- (void)applyGroupCallParticipantUpdate:(NSDictionary *)update {
	int32_t callId = [update[@"group_call_id"] intValue];
	NSDictionary *raw = TGGCDict(update[@"participant"]);
	if (!callId || !raw.count)
		return;
	NSMutableDictionary *rows = TGGCParticipants(self, callId);
	NSDictionary *flat = TGGCFlattenParticipant(self, raw);
	NSString *key = flat[@"senderKey"];
	BOOL removed = ![(NSString *)flat[@"order"] length];
	if (removed)
		[rows removeObjectForKey:key];
	else
		rows[key] = flat;
	[[NSNotificationCenter defaultCenter] postNotificationName:
			TGGroupCallParticipantsChangedNotification object:self
			userInfo:@{TGGroupCallIdKey : @(callId),
					   TGGroupCallValueKey : removed ? [NSNull null] : flat}];
}

- (void)applyGroupCallMessagesDeleted:(NSDictionary *)update {
	int32_t callId = [update[@"group_call_id"] intValue];
	NSArray *ids = TGGCArray(update[@"message_ids"]);
	if (!callId || !ids.count)
		return;
	NSMutableArray *rows = TGGCMessages(self, callId);
	NSSet *deleted = [NSSet setWithArray:ids];
	NSMutableArray *kept = [NSMutableArray arrayWithCapacity:rows.count];
	for (NSDictionary *row in rows)
		if (![deleted containsObject:row[@"messageId"]])
			[kept addObject:row];
	[TGGCState(self)[@"messages"] setObject:kept forKey:@(callId)];
	[[NSNotificationCenter defaultCenter] postNotificationName:
			TGGroupCallMessagesChangedNotification object:self
			userInfo:@{TGGroupCallIdKey : @(callId), TGGroupCallValueKey : ids}];
}

- (void)applyGroupCallMessageSendFailed:(NSDictionary *)update {
	int32_t callId = [update[@"group_call_id"] intValue];
	NSDictionary *error = TGGCDict(update[@"error"]);
	NSString *message = error[@"message"];
	if (!callId)
		return;
	[[NSNotificationCenter defaultCenter] postNotificationName:
			TGGroupCallMessagesChangedNotification object:self
			userInfo:@{TGGroupCallIdKey : @(callId),
					   TGGroupCallErrorKey : message.length ? message : @"The message was not sent."}];
}

/// updateGroupCallMessage is not a td_api name in every schema this client
/// builds against; the group call message itself arrives as updateNewGroupCallMessage.
/// This accepts the update's message object.
- (void)applyNewGroupCallMessage:(NSDictionary *)update {
	int32_t callId = [update[@"group_call_id"] intValue];
	NSDictionary *message = TGGCDict(update[@"message"]);
	if (!callId || !message.count)
		return;
	NSMutableArray *rows = TGGCMessages(self, callId);
	NSDictionary *flat = TGGCFlattenMessage(self, message);
	int32_t messageId = [flat[@"messageId"] intValue];
	if (!messageId)
		return;
	for (NSUInteger i = 0; i < rows.count; i++){
		if ([rows[i][@"messageId"] intValue] == messageId){
			rows[i] = flat;
			[[NSNotificationCenter defaultCenter] postNotificationName:
					TGGroupCallMessagesChangedNotification object:self
					userInfo:@{TGGroupCallIdKey : @(callId), TGGroupCallValueKey : flat}];
			return;
		}
	}
	[rows addObject:flat];
	[rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
		return [a[@"date"] compare:b[@"date"]];
	}];
	[[NSNotificationCenter defaultCenter] postNotificationName:
			TGGroupCallMessagesChangedNotification object:self
			userInfo:@{TGGroupCallIdKey : @(callId), TGGroupCallValueKey : flat}];
}

- (void)applyGroupCallParticipantsUpdate:(NSDictionary *)update {
	int32_t callId = [update[@"group_call_id"] intValue];
	if (!callId)
		return;
	// TDLib sends the full participant rows as updateGroupCallParticipant
	// after this; the batch only names who to expect, so the screen reloads
	// the snapshot it already has rather than inventing rows.
	[[NSNotificationCenter defaultCenter] postNotificationName:
			TGGroupCallParticipantsChangedNotification object:self
			userInfo:@{TGGroupCallIdKey : @(callId),
					   TGGroupCallValueKey : TGGCArray(update[@"participant_user_ids"])}];
}

@end

// vim:ft=objc
