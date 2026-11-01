#import "TGVideoChatSetupViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGVideoChatStreamViewController.h"
#import "TGGroupCallViewController.h"

@interface TGVideoChatSetupViewController ()
@property (nonatomic, strong) NSDictionary *call;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, copy) NSString *statusLine;
@property (nonatomic, copy) NSString *joinPayload;
@property (nonatomic, strong) NSArray *availableSenders;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGVideoChatSetupViewController

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId {
	self = [super init];
	if (self){
		_chatId = chatId;
		_groupCallId = groupCallId;
		self.listTitle = @"Video Chat";
		self.emptyText = @"No video chat settings yet.";
		_statusLine = @"Create the video chat first, or open this from an active call.";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.listFooter = self.statusLine;
	[self reload];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	if (self.chatId){
		[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
			TGVideoChatSetupViewController *me = weakSelf;
			if (!me)
				return;
			if ([chat[@"title"] isKindOfClass:NSString.class])
				me.chatTitle = chat[@"title"];
			int32_t fromChat = [chat[@"video_chat"][@"group_call_id"] intValue];
			if (!me.groupCallId && fromChat)
				me.groupCallId = fromChat;
			[me loadCall];
		}];
	} else {
		[self loadCall];
	}
}

- (void)loadCall {
	if (!self.groupCallId){
		[self rebuildRows];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupCall:self.groupCallId completion:^(NSDictionary *call, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		me.call = call;
		if (!call && error.length)
			me.statusLine = error;
		[me rebuildRows];
	}];
}

- (void)setStatus:(NSString *)status {
	self.statusLine = status ?: @"";
	self.listFooter = self.statusLine;
	[self rebuildRows];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail tap:(void (^)(void))tap {
	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	row[@"title"] = title ?: @"";
	if (detail.length)
		row[@"detail"] = detail;
	if (tap)
		row[@"tap"] = tap;
	return row;
}

- (NSString *)callDetail:(NSString *)key yes:(NSString *)yes no:(NSString *)no {
	if (!self.call)
		return @"No call";
	return [self.call[key] boolValue] ? yes : no;
}

- (void)rebuildRows {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *rows = [NSMutableArray array];

	[rows addObject:[self rowWithTitle:@"Create Video Chat"
			detail:@"Title, start time, video or RTMP"
			tap:^{ [weakSelf createVideoChat]; }]];
	[rows addObject:[self rowWithTitle:@"Create Standalone Group Call"
			detail:@"createGroupCall - a call link, not bound to a chat"
			tap:^{ [weakSelf createStandaloneGroupCall]; }]];
	if (self.groupCallId){
		[rows addObject:[self rowWithTitle:@"Join Call"
				detail:@"Returns the tgcalls join payload"
				tap:^{ [weakSelf joinCall]; }]];
		[rows addObject:[self rowWithTitle:@"Start Scheduled Video Chat"
				detail:@"Only valid before the call starts"
				tap:^{ [weakSelf startScheduled]; }]];
		[rows addObject:[self rowWithTitle:@"Call Title"
				detail:self.call[@"title"] ?: @"Not loaded"
				tap:^{ [weakSelf editTitle]; }]];
	}

	if (self.groupCallId){
		[rows addObject:[self rowWithTitle:@"Default Participant"
				detail:@"Who this account joins as"
				tap:^{ [weakSelf chooseDefaultParticipant]; }]];
		[rows addObject:[self rowWithTitle:@"Invite Participants"
				detail:@"inviteVideoChatParticipants, one at a time"
				tap:^{ [weakSelf inviteParticipants]; }]];
		[rows addObject:[self rowWithTitle:@"Invite Link"
				detail:self.call[@"inviteLink"] ?: @"Ask Telegram, then copy it"
				tap:^{ [weakSelf fetchInviteLink]; }]];
		[rows addObject:[self rowWithTitle:@"Revoke Invite Link"
				detail:@"Keeps the call, changes the link"
				tap:^{ [weakSelf revokeInviteLink]; }]];
		[rows addObject:[self rowWithTitle:@"Get RTMP URL"
				detail:@"For an RTMP stream video chat"
				tap:^{ [weakSelf fetchRtmpUrl]; }]];
		[rows addObject:[self rowWithTitle:@"Replace RTMP URL"
				detail:@"Invalidates the current stream key"
				tap:^{ [weakSelf replaceRtmpUrl]; }]];
		[rows addObject:[self rowWithTitle:@"Start Recording"
				detail:[self callDetail:@"recordDuration" yes:@"Recording is on" no:@"Audio or video"]
				tap:^{ [weakSelf startRecording]; }]];
		[rows addObject:[self rowWithTitle:@"End Recording"
				detail:@"Stops the running recording"
				tap:^{ [weakSelf endRecording]; }]];
		[rows addObject:[self rowWithTitle:@"Start Screen Sharing"
				detail:@"Sends the join payload and an audio source"
				tap:^{ [weakSelf startScreenSharing]; }]];
		[rows addObject:[self rowWithTitle:@"Pause Screen Sharing"
				detail:@"Toggle the pause flag"
				tap:^{ [weakSelf pauseScreenSharing]; }]];
		[rows addObject:[self rowWithTitle:@"Resume Screen Sharing"
				detail:@"Toggle the pause flag back"
				tap:^{ [weakSelf resumeScreenSharing]; }]];
		[rows addObject:[self rowWithTitle:@"Stop Screen Sharing"
				detail:@"endGroupCallScreenSharing"
				tap:^{ [weakSelf stopScreenSharing]; }]];
		[rows addObject:[self rowWithTitle:@"Messages Allowed"
				detail:[self callDetail:@"areMessagesAllowed" yes:@"On" no:@"Off"]
				tap:^{ [weakSelf toggleMessagesAllowed]; }]];
		[rows addObject:[self rowWithTitle:@"Mute New Participants"
				detail:[self callDetail:@"muteNewParticipants" yes:@"On" no:@"Off"]
				tap:^{ [weakSelf toggleMuteNewParticipants]; }]];
		[rows addObject:[self rowWithTitle:@"Start Notification"
				detail:[self callDetail:@"enabledStartNotification" yes:@"On" no:@"Off"]
				tap:^{ [weakSelf toggleStartNotification]; }]];
		[rows addObject:[self rowWithTitle:@"Streams and Data"
				detail:@"Channels, segments, encryption check"
				tap:^{ [weakSelf openStreams]; }]];
		[rows addObject:[self rowWithTitle:@"Decline an Invitation"
				detail:@"By the service message id"
				tap:^{ [weakSelf declineInvitation]; }]];
		[rows addObject:[self rowWithTitle:@"End Call"
				detail:@"Ends it for everybody"
				tap:^{ [weakSelf endCall]; }]];
	}

	self.rows = rows;
}

#pragma mark - create

- (void)createVideoChat {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Video chat, start now",
								@"Video chat, in 1 hour",
								@"RTMP stream, start now",
								@"RTMP stream, in 1 hour"]
						title:@"Create Video Chat"
			   destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		BOOL rtmp = index >= 2;
		BOOL scheduled = (index == 1 || index == 3);
		[TGAlertSheet showInput:@"Video Chat Title"
						message:@"Empty uses the chat title."
					placeholder:me.chatTitle ?: @"Video chat"
						   text:me.chatTitle action:@"Create" inView:me.view
					   onSubmit:^(NSString *text){
			TGVideoChatSetupViewController *again = weakSelf;
			if (!again)
				return;
			int32_t start = scheduled
					? (int32_t)([[NSDate date] timeIntervalSince1970] + 3600) : 0;
			[[TGClient shared] createVideoChatInChat:again.chatId title:text
					startDate:start isRtmp:rtmp completion:^(int32_t callId, NSString *error){
				TGVideoChatSetupViewController *got = weakSelf;
				if (!got)
					return;
				if (!callId){
					[got setStatus:error ?: @"Telegram refused that."];
					return;
				}
				got.groupCallId = callId;
				[got setStatus:[NSString stringWithFormat:
						@"Video chat %d created%@.", callId,
						scheduled ? @" for one hour from now" : @""]];
				[got loadCall];
				[got pushCallScreen];
			}];
		}];
	}];
}

- (void)createStandaloneGroupCall {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] createGroupCallWithParameters:TGGroupCallJoinParameters(0, @"", NO, NO)
			completion:^(NSDictionary *info, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		if (!info){
			[me setStatus:error ?: @"Telegram refused that."];
			return;
		}
		me.groupCallId = [info[@"groupCallId"] intValue];
		me.joinPayload = info[@"joinPayload"];
		[me setStatus:[NSString stringWithFormat:@"Group call %d created. %@",
				me.groupCallId, [info[@"joinPayload"] length]
						? @"Telegram sent a join payload." : @"No join payload."]];
		[me loadCall];
	}];
}

- (void)joinCall {
	if (!self.groupCallId)
		return;
	__weak typeof(self) weakSelf = self;
	NSDictionary *parameters = TGGroupCallJoinParameters(0, @"", NO, NO);
	void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[me setStatus:(ok ? @"Joined. The join payload is on the call screen."
				: (error ?: @"Telegram refused the join."))];
		[me loadCall];
	};
	if ([self.call[@"isVideoChat"] boolValue] || [self.call[@"isLiveStory"] boolValue]){
		[[TGClient shared] joinVideoChat:self.groupCallId participant:nil
							   parameters:parameters inviteHash:@""
							   completion:^(NSString *payload, NSString *error){
			TGVideoChatSetupViewController *me = weakSelf;
			if (me && payload.length)
				me.joinPayload = payload;
			done(error.length == 0, error);
		}];
	} else {
		[[TGClient shared] joinGroupCallWithInput:TGGroupCallInput(self.groupCallId, 0)
									   parameters:parameters
									   completion:^(NSDictionary *info, NSString *error){
			TGVideoChatSetupViewController *me = weakSelf;
			if (me && info[@"joinPayload"])
				me.joinPayload = info[@"joinPayload"];
			done(error.length == 0, error);
		}];
	}
}

- (void)startScheduled {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] startScheduledVideoChat:self.groupCallId
									completion:^(BOOL ok, NSString *error){
		[weakSelf setStatus:(ok ? @"Telegram started the scheduled call."
				: (error ?: @"Telegram refused that."))];
		[weakSelf loadCall];
	}];
}

- (void)editTitle {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Call Title" message:@"1 to 64 characters."
				placeholder:@"Video chat"
					   text:self.call[@"title"] action:@"Save" inView:self.view
				   onSubmit:^(NSString *text){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] setVideoChatTitle:text inCall:me.groupCallId
								  completion:^(BOOL ok, NSString *error){
			[me setStatus:(ok ? @"Title saved." : (error ?: @"Telegram refused that."))];
			[me loadCall];
		}];
	}];
}

#pragma mark - participants

- (void)loadAvailableSenders:(void (^)(void))done {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] videoChatAvailableParticipantsForChat:self.chatId
			completion:^(NSDictionary *answer, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		me.availableSenders = answer[@"senders"] ?: @[];
		if (!answer)
			[me setStatus:error ?: @"Telegram did not name a participant."];
		if (done)
			done();
	}];
}

- (NSString *)labelForSender:(NSDictionary *)sender {
	if ([sender[@"@type"] isEqualToString:@"messageSenderChat"])
		return [[TGClient shared] titleForChat:[sender[@"chat_id"] longLongValue]] ?: @"Chat";
	return [[TGClient shared] nameForUserId:[sender[@"user_id"] longLongValue]] ?: @"User";
}

- (void)chooseDefaultParticipant {
	__weak typeof(self) weakSelf = self;
	[self loadAvailableSenders:^{
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *sender in me.availableSenders)
			[titles addObject:[me labelForSender:sender]];
		if (!titles.count){
			[me setStatus:@"Telegram returned no participants this account may join as."];
			return;
		}
		[TGAlertSheet showChoices:titles title:@"Join Video Chat As"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			if (index < 0 || index >= (NSInteger)me.availableSenders.count)
				return;
			NSDictionary *sender = me.availableSenders[(NSUInteger)index];
			[[TGClient shared] setVideoChatDefaultParticipant:sender forChat:me.chatId
					completion:^(BOOL ok, NSString *error){
				[me setStatus:(ok ? @"Default participant saved."
						: (error ?: @"Telegram refused that."))];
				[me loadCall];
			}];
		}];
	}];
}

- (void)inviteParticipants {
	__weak typeof(self) weakSelf = self;
	[self loadAvailableSenders:^{
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *sender in me.availableSenders)
			[titles addObject:[me labelForSender:sender]];
		if (!titles.count){
			[TGAlertSheet showInput:@"Invite Participants" message:@"Telegram user id."
					placeholder:@"123456789" text:nil action:@"Invite"
						   inView:me.view onSubmit:^(NSString *text){
				int64_t userId = text.longLongValue;
				if (userId <= 0)
					return;
				[[TGClient shared] inviteVideoChatParticipants:@[@(userId)]
						toCall:me.groupCallId completion:^(BOOL ok, NSString *error){
					[me setStatus:(ok ? @"Invited." : (error ?: @"Telegram refused that."))];
				}];
			}];
			return;
		}
		[TGAlertSheet showChoices:titles title:@"Invite Participant"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			if (index < 0 || index >= (NSInteger)me.availableSenders.count)
				return;
			int64_t userId = [me.availableSenders[(NSUInteger)index][@"user_id"] longLongValue];
			if (!userId)
				return;
			[[TGClient shared] inviteVideoChatParticipants:@[@(userId)]
					toCall:me.groupCallId completion:^(BOOL ok, NSString *error){
				[me setStatus:(ok ? @"Invited." : (error ?: @"Telegram refused that."))];
			}];
		}];
	}];
}

#pragma mark - links

- (void)fetchInviteLink {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Can unmute themselves", @"Join muted"]
						title:@"Invite Link" destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] videoChatInviteLink:me.groupCallId canSelfUnmute:index == 0
									completion:^(NSString *link, NSString *error){
			if (!link.length){
				[me setStatus:error ?: @"Telegram refused that."];
				return;
			}
			[UIPasteboard generalPasteboard].string = link;
			[me setStatus:[NSString stringWithFormat:@"Link copied: %@", link]];
		}];
	}];
}

- (void)revokeInviteLink {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The old link stops working for new joins."
						title:@"Revoke Invite Link" action:@"Revoke" destructive:YES
					   inView:self.view onConfirm:^{
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] revokeGroupCallInviteLink:me.groupCallId
										  completion:^(BOOL ok, NSString *error){
			[me setStatus:(ok ? @"Invite link revoked."
					: (error ?: @"Telegram refused that."))];
			[me loadCall];
		}];
	}];
}

- (void)fetchRtmpUrl {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] videoChatRtmpUrlForChat:self.chatId
									completion:^(NSDictionary *answer, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		if (!answer){
			[me setStatus:error ?: @"Telegram refused that."];
			return;
		}
		NSString *sentence = [NSString stringWithFormat:@"RTMP: %@  Key: %@",
				answer[@"url"], answer[@"streamKey"]];
		[UIPasteboard generalPasteboard].string =
				[NSString stringWithFormat:@"%@/%@", answer[@"url"], answer[@"streamKey"]];
		[me setStatus:[sentence stringByAppendingString:@" (copied)"]];
	}];
}

- (void)replaceRtmpUrl {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The current stream key stops working."
						title:@"Replace RTMP URL" action:@"Replace" destructive:YES
					   inView:self.view onConfirm:^{
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] replaceVideoChatRtmpUrlForChat:me.chatId
				completion:^(NSDictionary *answer, NSString *error){
			if (!answer){
				[me setStatus:error ?: @"Telegram refused that."];
				return;
			}
			[me setStatus:[NSString stringWithFormat:@"New RTMP: %@  Key: %@",
					answer[@"url"], answer[@"streamKey"]]];
		}];
	}];
}

#pragma mark - recording and screen sharing

- (void)startRecording {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Audio recording", @"Video recording, landscape",
								@"Video recording, portrait"]
						title:@"Start Recording" destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[TGAlertSheet showInput:@"Recording Title" message:@"A name for the recording."
					placeholder:@"Recording" text:nil action:@"Start"
						   inView:me.view onSubmit:^(NSString *text){
			[[TGClient shared] startGroupCallRecording:me.groupCallId title:text
					recordVideo:index > 0 portrait:index == 2
					completion:^(BOOL ok, NSString *error){
				[me setStatus:(ok ? @"Recording started."
						: (error ?: @"Telegram refused that."))];
				[me loadCall];
			}];
		}];
	}];
}

- (void)endRecording {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] endGroupCallRecording:self.groupCallId
								  completion:^(BOOL ok, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[me setStatus:(ok ? @"Recording stopped."
				: (error ?: @"Telegram refused that."))];
		[me loadCall];
	}];
}

- (void)startScreenSharing {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Screen Sharing Payload"
					message:@"The payload tgcalls returned at join time."
				placeholder:@"Join payload"
					   text:self.joinPayload action:@"Start" inView:self.view
				   onSubmit:^(NSString *text){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] startGroupCallScreenSharing:me.groupCallId
				audioSourceId:0 payload:text completion:^(NSString *answer, NSString *error){
			if (error.length){
				[me setStatus:error];
				return;
			}
			if (answer.length)
				me.joinPayload = answer;
			[me setStatus:@"Screen sharing started. Telegram returned a payload."];
			[me loadCall];
		}];
	}];
}

- (void)pauseScreenSharing {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallScreenSharingPaused:self.groupCallId paused:YES
											   completion:^(BOOL ok, NSString *error){
		[weakSelf setStatus:(ok ? @"Screen sharing paused."
				: (error ?: @"Telegram refused that."))];
	}];
}

- (void)resumeScreenSharing {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallScreenSharingPaused:self.groupCallId paused:NO
											   completion:^(BOOL ok, NSString *error){
		[weakSelf setStatus:(ok ? @"Screen sharing resumed."
				: (error ?: @"Telegram refused that."))];
	}];
}

- (void)stopScreenSharing {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] endGroupCallScreenSharing:self.groupCallId
									  completion:^(BOOL ok, NSString *error){
		[weakSelf setStatus:(ok ? @"Screen sharing stopped."
				: (error ?: @"Telegram refused that."))];
		[weakSelf loadCall];
	}];
}

#pragma mark - switches and endings

- (void)toggleMessagesAllowed {
	BOOL on = [self.call[@"areMessagesAllowed"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallMessagesAllowed:self.groupCallId allowed:!on
										   completion:^(BOOL ok, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[me setStatus:(ok ? @"Messages switch saved."
				: (error ?: @"Telegram refused that."))];
		[me loadCall];
	}];
}

- (void)toggleMuteNewParticipants {
	BOOL on = [self.call[@"muteNewParticipants"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleVideoChatMuteNewParticipants:self.groupCallId muted:!on
											   completion:^(BOOL ok, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[me setStatus:(ok ? @"New participants switch saved."
				: (error ?: @"Telegram refused that."))];
		[me loadCall];
	}];
}

- (void)toggleStartNotification {
	BOOL on = [self.call[@"enabledStartNotification"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleVideoChatStartNotification:self.groupCallId enabled:!on
											 completion:^(BOOL ok, NSString *error){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[me setStatus:(ok ? @"Start notification switch saved."
				: (error ?: @"Telegram refused that."))];
		[me loadCall];
	}];
}

- (void)declineInvitation {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Decline Invitation"
					message:@"The id of the messageGroupCall message."
				placeholder:@"Message id" text:nil action:@"Decline"
					 inView:self.view onSubmit:^(NSString *text){
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] declineGroupCallInvitationInChat:me.chatId
				messageId:text.longLongValue completion:^(BOOL ok, NSString *error){
			[me setStatus:(ok ? @"Invitation declined."
					: (error ?: @"Telegram refused that."))];
		}];
	}];
}

- (void)endCall {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Everybody is disconnected."
						title:@"End Call" action:@"End" destructive:YES
					   inView:self.view onConfirm:^{
		TGVideoChatSetupViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] endGroupCall:me.groupCallId completion:^(BOOL ok, NSString *error){
			[me setStatus:(ok ? @"Call ended." : (error ?: @"Telegram refused that."))];
			[me loadCall];
		}];
	}];
}

#pragma mark - navigation

- (void)pushCallScreen {
	TGGroupCallViewController *screen =
			[[TGGroupCallViewController alloc] initWithChatId:self.chatId
												 groupCallId:self.groupCallId];
	screen.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:screen animated:YES];
}

- (void)openStreams {
	TGVideoChatStreamViewController *screen =
			[[TGVideoChatStreamViewController alloc] initWithChatId:self.chatId
														groupCallId:self.groupCallId];
	screen.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:screen animated:YES];
}

@end

// vim:ft=objc
