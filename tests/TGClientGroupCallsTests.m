//
// TGClientGroupCallsTests.m - the 42 group-call and video-chat requests.
//
// Each test pins the request shape Telegram expects and the answer the call
// screens read. A request with a missing id, a missing sender object or the
// wrong text wrapper is a screen that lies even when the server answers ok.
//
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGBase64.h"

@interface TGClientGroupCallsTests : XCTestCase @end

static TGClient *GCClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c removeAllFileWaiters];
	c.me = @{@"id" : @(1001), @"first_name" : @"Legacy"};
	c.chats = @[];
	c.chatsById = [NSMutableDictionary dictionary];
	c.usersById = [NSMutableDictionary dictionary];
	return c;
}

static NSDictionary *GCTestDecode(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *GCLast(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([GCTestDecode(d)[@"@type"] isEqualToString:type])
			found = GCTestDecode(d);
	return found;
}

static void GCReply(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *request = GCTestDecode(d);
		if ([request[@"@type"] isEqualToString:type] && request[@"@extra"]){
			sent = request;
			break;
		}
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *GCParticipantAnswer(long long userId, BOOL speaking, NSString *order) {
	return @{
		@"@type" : @"groupCallParticipant",
		@"participant_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
		@"audio_source_id" : @(7000 + userId),
		@"video_info" : @{@"@type" : @"groupCallParticipantVideoInfo",
						  @"source_groups" : @[],
						  @"endpoint_id" : @"ep",
						  @"is_paused" : @NO},
		@"screen_sharing_video_info" : [NSNull null],
		@"bio" : @"",
		@"is_current_user" : @(userId == 1001),
		@"is_speaking" : @(speaking),
		@"is_hand_raised" : @NO,
		@"can_be_muted_for_all_users" : @YES,
		@"can_be_unmuted_for_all_users" : @YES,
		@"can_be_muted_for_current_user" : @YES,
		@"can_be_unmuted_for_current_user" : @YES,
		@"is_muted_for_all_users" : @NO,
		@"is_muted_for_current_user" : @NO,
		@"can_unmute_self" : @NO,
		@"volume_level" : @(10000),
		@"order" : order ?: @"1",
	};
}

static NSDictionary *GCCallAnswer(long long callId) {
	return @{
		@"@type" : @"groupCall",
		@"id" : @(callId),
		@"unique_id" : @(9000),
		@"title" : @"Standup",
		@"invite_link" : @"https://t.me/call",
		@"paid_message_star_count" : @(0),
		@"scheduled_start_date" : @(0),
		@"enabled_start_notification" : @YES,
		@"is_active" : @YES,
		@"is_video_chat" : @YES,
		@"is_live_story" : @NO,
		@"is_rtmp_stream" : @NO,
		@"is_joined" : @YES,
		@"need_rejoin" : @NO,
		@"is_owned" : @YES,
		@"can_be_managed" : @YES,
		@"participant_count" : @(7),
		@"has_hidden_listeners" : @NO,
		@"loaded_all_participants" : @YES,
		@"message_sender_id" : [NSNull null],
		@"recent_speakers" : @[@{@"participant_id" : @{@"@type" : @"messageSenderUser",
														@"user_id" : @(12)},
								  @"is_speaking" : @YES}],
		@"is_my_video_enabled" : @YES,
		@"is_my_video_paused" : @NO,
		@"can_enable_video" : @YES,
		@"mute_new_participants" : @YES,
		@"can_toggle_mute_new_participants" : @YES,
		@"can_send_messages" : @YES,
		@"are_messages_allowed" : @YES,
		@"can_toggle_are_messages_allowed" : @YES,
		@"can_delete_messages" : @NO,
		@"record_duration" : @(30),
		@"is_video_recorded" : @NO,
		@"duration" : @(0),
	};
}

@implementation TGClientGroupCallsTests

#pragma mark - creating and joining

- (void)testCreateVideoChat_SendsTheChatTitleDateAndRtmp {
	TGClient *c = GCClient();
	__block int32_t got = 0;
	[c createVideoChatInChat:77 title:@"Planning" startDate:0 isRtmp:YES
				  completion:^(int32_t callId, NSString *error){ got = callId; }];
	NSDictionary *r = GCLast(c, @"createVideoChat");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"title"], @"Planning");
	XCTAssertEqualObjects(r[@"start_date"], @(0));
	XCTAssertEqualObjects(r[@"is_rtmp_stream"], @YES);
	GCReply(c, @"createVideoChat", @{@"@type" : @"groupCallId", @"id" : @(88)});
	XCTAssertEqual(got, 88);
}

- (void)testCreateVideoChat_RejectsAScheduleOutsideTelegramWindow {
	TGClient *c = GCClient();
	__block NSString *error = nil;
	[c createVideoChatInChat:77 title:@"" startDate:5 isRtmp:NO
				  completion:^(int32_t callId, NSString *why){ error = why; }];
	XCTAssertNil(GCLast(c, @"createVideoChat"));
	XCTAssertNotNil(error);
}

- (void)testCreateGroupCall_SendsTheJoinParametersAndReadsThePayload {
	TGClient *c = GCClient();
	__block NSDictionary *info = nil;
	[c createGroupCallWithParameters:TGGroupCallJoinParameters(0, @"", NO, NO)
						  completion:^(NSDictionary *got, NSString *error){ info = got; }];
	NSDictionary *r = GCLast(c, @"createGroupCall");
	XCTAssertEqualObjects(r[@"join_parameters"][@"@type"], @"groupCallJoinParameters");
	GCReply(c, @"createGroupCall", @{@"@type" : @"groupCallInfo",
									@"group_call_id" : @(21),
									@"join_payload" : @"payload"});
	XCTAssertEqualObjects(info[@"groupCallId"], @(21));
	XCTAssertEqualObjects(info[@"joinPayload"], @"payload");
}

- (void)testJoinGroupCall_SendsInputAndParametersAndReadsInfo {
	TGClient *c = GCClient();
	__block NSDictionary *info = nil;
	NSDictionary *input = TGGroupCallInput(21, 0);
	[c joinGroupCallWithInput:input
				   parameters:TGGroupCallJoinParameters(3, @"payload", YES, NO)
				   completion:^(NSDictionary *got, NSString *error){ info = got; }];
	NSDictionary *r = GCLast(c, @"joinGroupCall");
	XCTAssertEqualObjects(r[@"input_group_call"][@"id"], @(21));
	XCTAssertEqualObjects(r[@"join_parameters"][@"audio_source_id"], @(3));
	XCTAssertEqualObjects(r[@"join_parameters"][@"is_muted"], @YES);
	GCReply(c, @"joinGroupCall", @{@"@type" : @"groupCallInfo",
								  @"group_call_id" : @(21),
								  @"join_payload" : @"joined"});
	XCTAssertEqualObjects(info[@"joinPayload"], @"joined");
}

- (void)testJoinVideoChat_SendsTheParticipantAndReturnsThePayload {
	TGClient *c = GCClient();
	__block NSString *payload = nil;
	[c joinVideoChat:77 participant:nil
		   parameters:TGGroupCallJoinParameters(0, @"p", NO, YES)
		   inviteHash:@"hash"
		   completion:^(NSString *text, NSString *error){ payload = text; }];
	NSDictionary *r = GCLast(c, @"joinVideoChat");
	XCTAssertEqualObjects(r[@"group_call_id"], @(77));
	XCTAssertTrue(r[@"participant_id"] == [NSNull null]);
	XCTAssertEqualObjects(r[@"invite_hash"], @"hash");
	GCReply(c, @"joinVideoChat", @{@"@type" : @"text", @"text" : @"join-response"});
	XCTAssertEqualObjects(payload, @"join-response");
}

- (void)testLeaveAndEndGroupCall_SendTheCallId {
	TGClient *c = GCClient();
	__block BOOL left = NO, ended = NO;
	[c leaveGroupCall:77 completion:^(BOOL ok, NSString *error){ left = ok; }];
	XCTAssertEqualObjects(GCLast(c, @"leaveGroupCall")[@"group_call_id"], @(77));
	GCReply(c, @"leaveGroupCall", @{@"@type" : @"ok"});
	XCTAssertTrue(left);

	[c endGroupCall:77 completion:^(BOOL ok, NSString *error){ ended = ok; }];
	XCTAssertEqualObjects(GCLast(c, @"endGroupCall")[@"group_call_id"], @(77));
	GCReply(c, @"endGroupCall", @{@"@type" : @"ok"});
	XCTAssertTrue(ended);
}

- (void)testStartScheduledVideoChat_SendsTheCallId {
	TGClient *c = GCClient();
	__block BOOL ok = NO;
	[c startScheduledVideoChat:77 completion:^(BOOL good, NSString *error){ ok = good; }];
	XCTAssertEqualObjects(GCLast(c, @"startScheduledVideoChat")[@"group_call_id"], @(77));
	GCReply(c, @"startScheduledVideoChat", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - reading the call

- (void)testGetGroupCall_FlattensTheRecordAndKeepsASnapshot {
	TGClient *c = GCClient();
	__block NSDictionary *call = nil;
	[c groupCall:77 completion:^(NSDictionary *got, NSString *error){ call = got; }];
	XCTAssertEqualObjects(GCLast(c, @"getGroupCall")[@"group_call_id"], @(77));
	GCReply(c, @"getGroupCall", GCCallAnswer(77));
	XCTAssertEqualObjects(call[@"title"], @"Standup");
	XCTAssertEqualObjects(call[@"participantCount"], @(7));
	XCTAssertEqualObjects(call[@"isJoined"], @YES);
	XCTAssertEqualObjects(call[@"isVideoChat"], @YES);
	XCTAssertEqualObjects(call[@"canToggleAreMessagesAllowed"], @YES);
	XCTAssertEqual([(NSArray *)call[@"recentSpeakers"] count], (NSUInteger)1);
	XCTAssertEqualObjects([c groupCallSnapshot:77][@"callId"], @(77));
}

- (void)testGetGroupCallParticipants_SendsTheInputAndReadsSenders {
	TGClient *c = GCClient();
	__block NSDictionary *answer = nil;
	[c groupCallParticipantsWithInput:TGGroupCallInput(21, 0) limit:0
						   completion:^(NSDictionary *got, NSString *error){ answer = got; }];
	NSDictionary *r = GCLast(c, @"getGroupCallParticipants");
	XCTAssertEqualObjects(r[@"input_group_call"][@"id"], @(21));
	XCTAssertEqualObjects(r[@"limit"], @(1));
	GCReply(c, @"getGroupCallParticipants",
			@{@"@type" : @"groupCallParticipants", @"total_count" : @(2),
			  @"participant_ids" : @[@{@"@type" : @"messageSenderUser", @"user_id" : @(12)}]});
	XCTAssertEqualObjects(answer[@"total"], @(2));
	XCTAssertEqual([(NSArray *)answer[@"senders"] count], (NSUInteger)1);
}

- (void)testLoadGroupCallParticipants_ClampsTheLimit {
	TGClient *c = GCClient();
	__block BOOL ok = NO;
	[c loadGroupCallParticipants:77 limit:500
					  completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"loadGroupCallParticipants");
	XCTAssertEqualObjects(r[@"group_call_id"], @(77));
	XCTAssertEqualObjects(r[@"limit"], @(100));
	GCReply(c, @"loadGroupCallParticipants", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - participant actions

- (void)testToggleParticipantMuted_SendsTheSenderAndFlag {
	TGClient *c = GCClient();
	NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(12)};
	__block BOOL ok = NO;
	[c toggleGroupCallParticipant:sender inCall:77 isMuted:YES
					   completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"toggleGroupCallParticipantIsMuted");
	XCTAssertEqualObjects(r[@"group_call_id"], @(77));
	XCTAssertEqualObjects(r[@"participant_id"][@"user_id"], @(12));
	XCTAssertEqualObjects(r[@"is_muted"], @YES);
	GCReply(c, @"toggleGroupCallParticipantIsMuted", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetParticipantVolume_ClampsToTelegramsRange {
	TGClient *c = GCClient();
	NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(12)};
	[c setGroupCallParticipant:sender inCall:77 volumeLevel:30000
					completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"setGroupCallParticipantVolumeLevel")[@"volume_level"],
						   @(20000));
	[c setGroupCallParticipant:sender inCall:77 volumeLevel:0
					completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"setGroupCallParticipantVolumeLevel")[@"volume_level"],
						   @(1));
}

- (void)testToggleParticipantHand_SendsTheSenderAndFlag {
	TGClient *c = GCClient();
	NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(1001)};
	__block BOOL ok = NO;
	[c toggleGroupCallParticipant:sender inCall:77 isHandRaised:YES
					   completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"toggleGroupCallParticipantIsHandRaised");
	XCTAssertEqualObjects(r[@"is_hand_raised"], @YES);
	XCTAssertEqualObjects(r[@"participant_id"][@"user_id"], @(1001));
	GCReply(c, @"toggleGroupCallParticipantIsHandRaised", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetSpeaking_SendsTheAudioSourceAndReadsTheParticipant {
	TGClient *c = GCClient();
	__block NSDictionary *sender = nil;
	[c setGroupCallParticipantSpeaking:0 inCall:77 isSpeaking:YES
							completion:^(NSDictionary *got, NSString *error){ sender = got; }];
	NSDictionary *r = GCLast(c, @"setGroupCallParticipantIsSpeaking");
	XCTAssertEqualObjects(r[@"audio_source"], @(0));
	XCTAssertEqualObjects(r[@"is_speaking"], @YES);
	GCReply(c, @"setGroupCallParticipantIsSpeaking",
			@{@"@type" : @"messageSenderUser", @"user_id" : @(1001)});
	XCTAssertEqualObjects(sender[@"user_id"], @(1001));
}

- (void)testInviteGroupCallParticipant_ReadsTheInviteOutcome {
	TGClient *c = GCClient();
	__block NSDictionary *answer = nil;
	[c inviteGroupCallParticipant:12 toCall:77 isVideo:YES
						completion:^(NSDictionary *got, NSString *error){ answer = got; }];
	NSDictionary *r = GCLast(c, @"inviteGroupCallParticipant");
	XCTAssertEqualObjects(r[@"user_id"], @(12));
	XCTAssertEqualObjects(r[@"is_video"], @YES);
	GCReply(c, @"inviteGroupCallParticipant",
			@{@"@type" : @"inviteGroupCallParticipantResultUserPrivacyRestricted"});
	XCTAssertEqualObjects(answer[@"outcome"], @"privacy");
}

- (void)testInviteVideoChatParticipants_SendsTheUserIds {
	TGClient *c = GCClient();
	__block BOOL ok = NO;
	[c inviteVideoChatParticipants:@[@12, @13] toCall:77
						completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"inviteVideoChatParticipants");
	XCTAssertEqualObjects(r[@"user_ids"], (@[@12, @13]));
	GCReply(c, @"inviteVideoChatParticipants", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testBanParticipants_SendsEveryId {
	TGClient *c = GCClient();
	__block BOOL ok = NO;
	[c banGroupCallParticipants:@[@12, @13] inCall:77
					 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"banGroupCallParticipants");
	XCTAssertEqualObjects(r[@"group_call_id"], @(77));
	XCTAssertEqualObjects(r[@"user_ids"], (@[@12, @13]));
	GCReply(c, @"banGroupCallParticipants", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeclineInvitation_SendsTheMessageItCameWith {
	TGClient *c = GCClient();
	__block BOOL ok = NO;
	[c declineGroupCallInvitationInChat:77 messageId:123
							 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"declineGroupCallInvitation");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"message_id"], @(123));
	GCReply(c, @"declineGroupCallInvitation", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

#pragma mark - call settings

- (void)testVideoChatTitle_RejectsAnEmptyOrLongOne {
	TGClient *c = GCClient();
	__block NSString *error = nil;
	[c setVideoChatTitle:@"" inCall:77 completion:^(BOOL ok, NSString *why){ error = why; }];
	XCTAssertNil(GCLast(c, @"setVideoChatTitle"));
	XCTAssertNotNil(error);
	[c setVideoChatTitle:@"Standup" inCall:77 completion:^(BOOL ok, NSString *why){}];
	XCTAssertEqualObjects(GCLast(c, @"setVideoChatTitle")[@"title"], @"Standup");
}

- (void)testToggleMuteNewParticipants_SendsTheFlag {
	TGClient *c = GCClient();
	[c toggleVideoChatMuteNewParticipants:77 muted:YES
							   completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"toggleVideoChatMuteNewParticipants");
	XCTAssertEqualObjects(r[@"group_call_id"], @(77));
	XCTAssertEqualObjects(r[@"mute_new_participants"], @YES);
}

- (void)testToggleMessagesAllowed_SendsTheFlag {
	TGClient *c = GCClient();
	[c toggleGroupCallMessagesAllowed:77 allowed:NO
						   completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"toggleGroupCallAreMessagesAllowed");
	XCTAssertEqualObjects(r[@"are_messages_allowed"], @NO);
}

- (void)testToggleStartNotification_SendsTheFlag {
	TGClient *c = GCClient();
	[c toggleVideoChatStartNotification:77 enabled:YES
							 completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"toggleVideoChatEnabledStartNotification");
	XCTAssertEqualObjects(r[@"enabled_start_notification"], @YES);
}

- (void)testToggleMyVideo_SendsEnabledAndPaused {
	TGClient *c = GCClient();
	[c toggleGroupCallMyVideoEnabled:77 enabled:YES
						  completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"toggleGroupCallIsMyVideoEnabled")[@"is_my_video_enabled"],
						   @YES);
	[c toggleGroupCallMyVideoPaused:77 paused:YES
						 completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"toggleGroupCallIsMyVideoPaused")[@"is_my_video_paused"],
						   @YES);
}

#pragma mark - recording and screen sharing

- (void)testStartRecording_SendsTitleAndMode {
	TGClient *c = GCClient();
	[c startGroupCallRecording:77 title:@"Weekly" recordVideo:YES portrait:YES
					completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"startGroupCallRecording");
	XCTAssertEqualObjects(r[@"title"], @"Weekly");
	XCTAssertEqualObjects(r[@"record_video"], @YES);
	XCTAssertEqualObjects(r[@"use_portrait_orientation"], @YES);
}

- (void)testEndRecording_SendsTheCallId {
	TGClient *c = GCClient();
	[c endGroupCallRecording:77 completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"endGroupCallRecording")[@"group_call_id"], @(77));
}

- (void)testScreenSharing_StartPauseAndEnd {
	TGClient *c = GCClient();
	__block NSString *answer = nil;
	[c startGroupCallScreenSharing:77 audioSourceId:42 payload:@"payload"
						completion:^(NSString *text, NSString *error){ answer = text; }];
	NSDictionary *r = GCLast(c, @"startGroupCallScreenSharing");
	XCTAssertEqualObjects(r[@"audio_source_id"], @(42));
	XCTAssertEqualObjects(r[@"payload"], @"payload");
	GCReply(c, @"startGroupCallScreenSharing", @{@"@type" : @"text", @"text" : @"share"});
	XCTAssertEqualObjects(answer, @"share");

	[c toggleGroupCallScreenSharingPaused:77 paused:YES
								completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"toggleGroupCallScreenSharingIsPaused")[@"is_paused"], @YES);
	[c endGroupCallScreenSharing:77 completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"endGroupCallScreenSharing")[@"group_call_id"], @(77));
}

#pragma mark - invite links and RTMP

- (void)testInviteLink_SendsCanSelfUnmuteAndReadsTheUrl {
	TGClient *c = GCClient();
	__block NSString *link = nil;
	[c videoChatInviteLink:77 canSelfUnmute:YES
				completion:^(NSString *url, NSString *error){ link = url; }];
	XCTAssertEqualObjects(GCLast(c, @"getVideoChatInviteLink")[@"can_self_unmute"], @YES);
	GCReply(c, @"getVideoChatInviteLink", @{@"@type" : @"httpUrl", @"url" : @"https://t.me/x"});
	XCTAssertEqualObjects(link, @"https://t.me/x");
}

- (void)testRevokeInviteLink_SendsTheCallId {
	TGClient *c = GCClient();
	[c revokeGroupCallInviteLink:77 completion:^(BOOL ok, NSString *error){}];
	XCTAssertEqualObjects(GCLast(c, @"revokeGroupCallInviteLink")[@"group_call_id"], @(77));
}

- (void)testRtmpUrl_GetAndReplaceReadTheUrlAndKey {
	TGClient *c = GCClient();
	__block NSDictionary *got = nil;
	[c videoChatRtmpUrlForChat:77 completion:^(NSDictionary *answer, NSString *error){ got = answer; }];
	XCTAssertEqualObjects(GCLast(c, @"getVideoChatRtmpUrl")[@"chat_id"], @(77));
	GCReply(c, @"getVideoChatRtmpUrl",
			@{@"@type" : @"rtmpUrl", @"url" : @"rtmp://a", @"stream_key" : @"key"});
	XCTAssertEqualObjects(got[@"url"], @"rtmp://a");
	XCTAssertEqualObjects(got[@"streamKey"], @"key");

	[c replaceVideoChatRtmpUrlForChat:77
						   completion:^(NSDictionary *answer, NSString *error){ got = answer; }];
	XCTAssertEqualObjects(GCLast(c, @"replaceVideoChatRtmpUrl")[@"chat_id"], @(77));
	GCReply(c, @"replaceVideoChatRtmpUrl",
			@{@"@type" : @"rtmpUrl", @"url" : @"rtmp://b", @"stream_key" : @"key2"});
	XCTAssertEqualObjects(got[@"url"], @"rtmp://b");
}

#pragma mark - participants as the video chat joins them

- (void)testAvailableParticipants_ReadsSenders {
	TGClient *c = GCClient();
	__block NSDictionary *answer = nil;
	[c videoChatAvailableParticipantsForChat:77
								  completion:^(NSDictionary *got, NSString *error){ answer = got; }];
	XCTAssertEqualObjects(GCLast(c, @"getVideoChatAvailableParticipants")[@"chat_id"], @(77));
	GCReply(c, @"getVideoChatAvailableParticipants",
			@{@"@type" : @"messageSenders", @"total_count" : @(1),
			  @"senders" : @[@{@"@type" : @"messageSenderUser", @"user_id" : @(1001)}]});
	XCTAssertEqualObjects(answer[@"total"], @(1));
	XCTAssertEqual([(NSArray *)answer[@"senders"] count], (NSUInteger)1);
}

- (void)testDefaultParticipant_SendsTheSender {
	TGClient *c = GCClient();
	NSDictionary *sender = @{@"@type" : @"messageSenderChat", @"chat_id" : @(55)};
	[c setVideoChatDefaultParticipant:sender forChat:77
						   completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"setVideoChatDefaultParticipant");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"default_participant_id"][@"chat_id"], @(55));
}

#pragma mark - call messages

- (void)testSendMessage_SendsFormattedTextAndStars {
	TGClient *c = GCClient();
	__block BOOL ok = NO;
	[c sendGroupCallMessage:@"  hello  " inCall:77 paidStarCount:0
				 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = GCLast(c, @"sendGroupCallMessage");
	XCTAssertEqualObjects(r[@"text"][@"@type"], @"formattedText");
	XCTAssertEqualObjects(r[@"text"][@"text"], @"hello");
	XCTAssertEqualObjects(r[@"paid_message_star_count"], @(0));
	GCReply(c, @"sendGroupCallMessage", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeleteMessages_SendsIdsAndSpamFlag {
	TGClient *c = GCClient();
	[c deleteGroupCallMessages:@[@5, @6] inCall:77 reportSpam:YES
					completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"deleteGroupCallMessages");
	XCTAssertEqualObjects(r[@"message_ids"], (@[@5, @6]));
	XCTAssertEqualObjects(r[@"report_spam"], @YES);
}

- (void)testDeleteBySender_SendsTheSenderObject {
	TGClient *c = GCClient();
	NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(12)};
	[c deleteGroupCallMessagesBySender:sender inCall:77 reportSpam:NO
							completion:^(BOOL ok, NSString *error){}];
	NSDictionary *r = GCLast(c, @"deleteGroupCallMessagesBySender");
	XCTAssertEqualObjects(r[@"sender_id"][@"user_id"], @(12));
	XCTAssertEqualObjects(r[@"report_spam"], @NO);
}

#pragma mark - streams and the data channel

- (void)testGroupCallStreams_FlattensEveryChannel {
	TGClient *c = GCClient();
	__block NSArray *streams = nil;
	[c groupCallStreams:77 completion:^(NSArray *got, NSString *error){ streams = got; }];
	XCTAssertEqualObjects(GCLast(c, @"getGroupCallStreams")[@"group_call_id"], @(77));
	GCReply(c, @"getGroupCallStreams",
			@{@"@type" : @"groupCallStreams",
			  @"streams" : @[@{@"channel_id" : @(3), @"scale" : @(1),
							   @"time_offset" : @(1700000000000)}]});
	XCTAssertEqualObjects(streams[0][@"channelId"], @(3));
	XCTAssertEqualObjects(streams[0][@"scale"], @(1));
}

- (void)testStreamSegment_SendsQualityAndReturnsBytes {
	TGClient *c = GCClient();
	NSData *bytes = [@"segment" dataUsingEncoding:NSUTF8StringEncoding];
	__block NSData *got = nil;
	[c groupCallStreamSegment:77 timeOffset:1700000000000 scale:1 channelId:3
					  quality:@"medium"
				   completion:^(NSData *data, NSString *error){ got = data; }];
	NSDictionary *r = GCLast(c, @"getGroupCallStreamSegment");
	XCTAssertEqualObjects(r[@"time_offset"], @(1700000000000));
	XCTAssertEqualObjects(r[@"channel_id"], @(3));
	XCTAssertEqualObjects(r[@"video_quality"][@"@type"], @"groupCallVideoQualityMedium");
	GCReply(c, @"getGroupCallStreamSegment",
			@{@"@type" : @"data", @"data" : TGBase64Encode(bytes)});
	XCTAssertEqualObjects(got, bytes);
}

- (void)testEncryptAndDecrypt_RoundTripTheBytes {
	TGClient *c = GCClient();
	NSData *plain = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *sealed = [@"SEALED" dataUsingEncoding:NSUTF8StringEncoding];
	__block NSData *encrypted = nil, *decrypted = nil;

	[c encryptGroupCallData:plain inCall:77 channel:@"screenSharing"
	   unencryptedPrefixSize:2 completion:^(NSData *data, NSString *error){ encrypted = data; }];
	NSDictionary *r = GCLast(c, @"encryptGroupCallData");
	XCTAssertEqualObjects(r[@"data"], TGBase64Encode(plain));
	XCTAssertEqualObjects(r[@"unencrypted_prefix_size"], @(2));
	XCTAssertEqualObjects(r[@"data_channel"][@"@type"], @"groupCallDataChannelScreenSharing");
	GCReply(c, @"encryptGroupCallData", @{@"@type" : @"data", @"data" : TGBase64Encode(sealed)});
	XCTAssertEqualObjects(encrypted, sealed);

	NSDictionary *sender = @{@"@type" : @"messageSenderUser", @"user_id" : @(12)};
	[c decryptGroupCallData:sealed fromParticipant:sender inCall:77 channel:nil
				 completion:^(NSData *data, NSString *error){ decrypted = data; }];
	NSDictionary *d = GCLast(c, @"decryptGroupCallData");
	XCTAssertEqualObjects(d[@"data"], TGBase64Encode(sealed));
	XCTAssertEqualObjects(d[@"participant_id"][@"user_id"], @(12));
	XCTAssertEqualObjects(d[@"data_channel"][@"@type"], @"groupCallDataChannelMain");
	GCReply(c, @"decryptGroupCallData", @{@"@type" : @"data", @"data" : TGBase64Encode(plain)});
	XCTAssertEqualObjects(decrypted, plain);
}

#pragma mark - state the screens read

- (void)testUpdateGroupCall_ReplacesTheSnapshot {
	TGClient *c = GCClient();
	[c handleUpdate:@{@"@type" : @"updateGroupCall", @"group_call" : GCCallAnswer(77)}];
	XCTAssertEqualObjects([c groupCallSnapshot:77][@"title"], @"Standup");
}

- (void)testUpdateParticipant_AddsSortsAndRemoves {
	TGClient *c = GCClient();
	[c handleUpdate:@{@"@type" : @"updateGroupCallParticipant", @"group_call_id" : @(310),
					  @"participant" : GCParticipantAnswer(12, YES, @"2")}];
	[c handleUpdate:@{@"@type" : @"updateGroupCallParticipant", @"group_call_id" : @(310),
					  @"participant" : GCParticipantAnswer(13, NO, @"5")}];
	NSArray *rows = [c groupCallParticipantSnapshot:310];
	XCTAssertEqual(rows.count, (NSUInteger)2);
	// Order 5 is higher than 2, so user 13 leads.
	XCTAssertEqualObjects(rows[0][@"userId"], @(13));
	XCTAssertTrue([rows[1][@"isSpeaking"] boolValue]);

	[c handleUpdate:@{@"@type" : @"updateGroupCallParticipant", @"group_call_id" : @(310),
					  @"participant" : GCParticipantAnswer(12, NO, @"")}];
	XCTAssertEqual([c groupCallParticipantSnapshot:310].count, (NSUInteger)1);
}

- (void)testCurrentParticipant_IsTheOneWithIsCurrentUser {
	TGClient *c = GCClient();
	[c handleUpdate:@{@"@type" : @"updateGroupCallParticipant", @"group_call_id" : @(311),
					  @"participant" : GCParticipantAnswer(1001, NO, @"1")}];
	XCTAssertEqualObjects([c currentGroupCallParticipant:311][@"userId"], @(1001));
}

- (void)testNewAndDeletedCallMessages_MoveTheSnapshot {
	TGClient *c = GCClient();
	[c handleUpdate:@{@"@type" : @"updateNewGroupCallMessage", @"group_call_id" : @(312),
					  @"message" : @{@"@type" : @"groupCallMessage", @"message_id" : @(5),
									 @"sender_id" : @{@"@type" : @"messageSenderUser",
													  @"user_id" : @(12)},
									 @"date" : @(1700000000),
									 @"text" : @{@"@type" : @"formattedText",
												 @"text" : @"hi", @"entities" : @[]},
									 @"paid_message_star_count" : @(0),
									 @"is_from_owner" : @NO,
									 @"can_be_deleted" : @YES}}];
	XCTAssertEqual([c groupCallMessageSnapshot:312].count, (NSUInteger)1);
	XCTAssertEqualObjects([c groupCallMessageSnapshot:312][0][@"text"], @"hi");

	[c handleUpdate:@{@"@type" : @"updateGroupCallMessagesDeleted",
					  @"group_call_id" : @(312), @"message_ids" : @[@5]}];
	XCTAssertEqual([c groupCallMessageSnapshot:312].count, (NSUInteger)0);
}

@end

// vim:ft=objc
