#import "TGLiveStoryViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@interface TGLiveStoryViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t groupCallId;
@property (nonatomic, assign) int32_t storyId;
@property (nonatomic, copy) NSString *rtmpUrl;
@property (nonatomic, copy) NSString *streamKey;
@end

@implementation TGLiveStoryViewController

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId {
	self = [super init];
	if (self){
		_chatId = chatId;
		_groupCallId = groupCallId;
		self.listTitle = @"Live Story";
		self.emptyText = @"No live story data yet.";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.listFooter = @"This client has no camera encoder. Starting asks Telegram "
			@"for a live story and, for an RTMP stream, shows the address and "
			@"key a broadcast app would use. Joining returns Telegram's join "
			@"payload as text.";
	[self rebuildRows];
}

- (void)rebuildRows {
	NSMutableArray *rows = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;

	[rows addObject:@{@"title" : self.groupCallId ? @"Start Another Live Story"
												  : @"Start Live Story",
					  @"detail" : @"Telegram creates the live story",
					  @"tap" : ^{ [weakSelf startLiveStory]; }}];
	if (self.groupCallId){
		[rows addObject:@{@"title" : @"Join Live Story",
						  @"detail" : @"Returns the tgcalls join payload",
						  @"tap" : ^{ [weakSelf joinLiveStory]; }}];
		[rows addObject:@{@"title" : @"Streamer",
						  @"detail" : @"Who is broadcasting",
						  @"tap" : ^{ [weakSelf loadStreamer]; }}];
		[rows addObject:@{@"title" : @"Load Message Senders",
						  @"detail" : @"Who messages may be sent as",
						  @"tap" : ^{ [weakSelf loadMessageSenders]; }}];
		[rows addObject:@{@"title" : @"Top Donors",
						  @"detail" : @"Stars spent on the live story",
						  @"tap" : ^{ [weakSelf loadTopDonors]; }}];
		[rows addObject:@{@"title" : @"Add 1★ Pending Reaction",
						  @"detail" : @"Then commit or cancel it",
						  @"tap" : ^{ [weakSelf addPendingReaction]; }}];
		[rows addObject:@{@"title" : @"Commit Pending Reactions",
						  @"detail" : @"Send everything pending",
						  @"tap" : ^{ [weakSelf commitPendingReactions]; }}];
		[rows addObject:@{@"title" : @"Cancel Pending Reactions",
						  @"detail" : @"Drop the pending stars",
						  @"tap" : ^{ [weakSelf removePendingReactions]; }}];
	}
	[rows addObject:@{@"title" : @"Get RTMP URL",
					  @"detail" : self.rtmpUrl.length ? self.rtmpUrl
							  : @"Asks Telegram for the stream address",
					  @"tap" : ^{ [weakSelf loadRtmpUrl]; }}];
	[rows addObject:@{@"title" : @"Replace RTMP URL",
					  @"detail" : @"Invalidates the current stream key",
					  @"tap" : ^{ [weakSelf replaceRtmpUrl]; }}];
	self.rows = rows;
	[self.tableView reloadData];
}

- (void)appendTitle:(NSString *)title detail:(NSString *)detail {
	NSMutableArray *rows = [self.rows mutableCopy];
	NSMutableDictionary *row = [@{@"title" : title ?: @"",
								   @"detail" : detail ?: @""} mutableCopy];
	[rows addObject:row];
	self.rows = rows;
	[self.tableView reloadData];
}

#pragma mark - start and join

- (void)startLiveStory {
	NSArray *choices = @[@"RTMP stream", @"Group call"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:@"Start Live Story"
				destructiveIndex:-1 inView:self.view onChoice:^(NSInteger choice){
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		BOOL rtmp = choice == 0;
		[[TGClient shared] startLiveStoryInChat:me.chatId
										privacy:@"everyone"
										userIds:@[]
								 protectContent:NO
										 rtmp:rtmp
							   enableMessages:YES
								paidMessageStars:0
									completion:^(NSDictionary *answer){
			if (![answer[@"ok"] boolValue]){
				[TGAlertSheet showMessage:answer[@"error"] ?: @"Telegram refused that."
									title:@"Live Story" inView:me.view];
				[me appendTitle:@"Start Failed"
						 detail:answer[@"error"] ?: @"Telegram refused that."];
				return;
			}
			NSDictionary *story = answer[@"story"] ?: @{};
			me.groupCallId = [answer[@"groupCallId"] intValue];
			me.storyId = [story[@"storyId"] intValue];
			[me appendTitle:@"Started"
					 detail:[NSString stringWithFormat:@"Story %d, group call %d",
							 me.storyId, me.groupCallId]];
			[me rebuildRows];
			if (rtmp)
				[me loadRtmpUrl];
		}];
	}];
}

- (void)joinLiveStory {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] joinLiveStoryCall:self.groupCallId
							  completion:^(NSString *payload, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		if (!payload.length){
			[TGAlertSheet showMessage:error ?: @"Telegram refused the join."
								title:@"Join Live Story" inView:me.view];
			[me appendTitle:@"Join Failed" detail:error ?: @"Refused."];
			return;
		}
		[me appendTitle:@"Join Payload"
				 detail:payload.length > 500
						 ? [payload substringToIndex:500] : payload];
		[UIPasteboard generalPasteboard].string = payload;
	}];
}

#pragma mark - server data

- (void)loadStreamer {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] liveStoryStreamerForCall:self.groupCallId
									completion:^(NSDictionary *streamer, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		if (!streamer){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Streamer" inView:me.view];
			return;
		}
		[me appendTitle:streamer[@"name"] ?: @"Streamer"
				 detail:[NSString stringWithFormat:@"%@%@%@",
						 [streamer[@"isSpeaking"] boolValue] ? @"speaking · " : @"",
						 [streamer[@"isMuted"] boolValue] ? @"muted · " : @"",
						 streamer[@"bio"] ?: @""]];
	}];
}

- (void)loadRtmpUrl {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] liveStoryRtmpUrlForChat:self.chatId
									completion:^(NSDictionary *url, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		if (!url){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"RTMP URL" inView:me.view];
			return;
		}
		me.rtmpUrl = url[@"url"] ?: @"";
		me.streamKey = url[@"streamKey"] ?: @"";
		[me appendTitle:@"RTMP URL" detail:me.rtmpUrl];
		[me appendTitle:@"Stream Key" detail:me.streamKey];
		[me rebuildRows];
		[UIPasteboard generalPasteboard].string =
				[NSString stringWithFormat:@"%@/%@", me.rtmpUrl, me.streamKey];
	}];
}

- (void)replaceRtmpUrl {
	__weak typeof(self) weakSelf = self;
	void (^confirm)(void) = ^{
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] replaceLiveStoryRtmpUrlForChat:me.chatId
											   completion:^(NSDictionary *url, NSString *error){
			if (!url){
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"RTMP URL" inView:me.view];
				return;
			}
			me.rtmpUrl = url[@"url"] ?: @"";
			me.streamKey = url[@"streamKey"] ?: @"";
			[me appendTitle:@"New RTMP URL" detail:me.rtmpUrl];
			[me rebuildRows];
		}];
	};
	[TGAlertSheet showConfirm:@"The current stream key stops working."
						title:@"Replace RTMP URL"
					   action:@"Replace"
				  destructive:YES
					   inView:self.view
					onConfirm:confirm];
}

- (void)loadMessageSenders {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] liveStoryAvailableMessageSendersForCall:self.groupCallId
												   completion:^(NSArray *senders, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		if (!senders.count){
			[TGAlertSheet showMessage:error ?: @"Telegram returned no senders."
								title:@"Message Senders" inView:me.view];
			return;
		}
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *sender in senders)
			[titles addObject:[NSString stringWithFormat:@"%@%@",
					sender[@"name"] ?: @"Sender",
					[sender[@"needsPremium"] boolValue] ? @" · Premium" : @""]];
		[TGAlertSheet showChoices:titles title:@"Message Senders"
					destructiveIndex:-1 inView:me.view onChoice:^(NSInteger choice){
			if (choice < 0 || choice >= (NSInteger)senders.count)
				return;
			NSDictionary *sender = senders[choice];
			[[TGClient shared] setLiveStoryMessageSender:sender
												 forCall:me.groupCallId
											  completion:^(BOOL ok, NSString *why){
				[TGAlertSheet showMessage:ok
						? @"Messages will be sent as that sender."
						: (why ?: @"Telegram refused that.")
									title:@"Message Sender" inView:me.view];
			}];
		}];
	}];
}

- (void)loadTopDonors {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] liveStoryTopDonorsForCall:self.groupCallId
									 completion:^(NSDictionary *donors, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!me)
			return;
		if (!donors){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Top Donors" inView:me.view];
			return;
		}
		[me appendTitle:@"Top Donors"
				 detail:[NSString stringWithFormat:@"%@ stars",
						 donors[@"totalStarCount"] ?: @(0)]];
		for (NSDictionary *donor in donors[@"donors"] ?: @[])
			[me appendTitle:donor[@"name"] ?: @"Donor"
					 detail:[NSString stringWithFormat:@"%@ stars%@%@%@",
							 donor[@"stars"] ?: @(0),
							 [donor[@"isTop"] boolValue] ? @" · top" : @"",
							 [donor[@"isMe"] boolValue] ? @" · you" : @"",
							 [donor[@"isAnonymous"] boolValue] ? @" · anonymous" : @""]];
	}];
}

#pragma mark - pending reactions

- (void)addPendingReaction {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] addPendingLiveStoryReactionInCall:self.groupCallId
												   stars:1
											  completion:^(BOOL ok, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Live Reaction" inView:me.view];
			return;
		}
		[me appendTitle:@"Pending Reaction" detail:@"1 star added; commit or cancel."];
	}];
}

- (void)commitPendingReactions {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] commitPendingLiveStoryReactionsInCall:self.groupCallId
												  completion:^(BOOL ok, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Live Reaction" inView:me.view];
			return;
		}
		[me appendTitle:@"Committed" detail:@"Pending reactions were sent."];
	}];
}

- (void)removePendingReactions {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removePendingLiveStoryReactionsInCall:self.groupCallId
												  completion:^(BOOL ok, NSString *error){
		TGLiveStoryViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Live Reaction" inView:me.view];
			return;
		}
		[me appendTitle:@"Cancelled" detail:@"Pending reactions were dropped."];
	}];
}

@end
