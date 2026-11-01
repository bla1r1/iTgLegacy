#import "TGGroupCallViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGGroupCallParticipantCell.h"
#import "TGGroupCallParticipantsViewController.h"
#import "TGVideoChatSetupViewController.h"
#import "TGCallMessagesViewController.h"
#import "TGVideoChatStreamViewController.h"

/// The header carries the title and the one line of state; the table below
/// is the controls and the first people in the call.
static const CGFloat kGCCallHeaderHeight = 112.0f;
static const CGFloat kGCCallRowsShown = 5;
static const CGFloat kGCCallStatusHeight = TGMetricLineBody;
static const CGFloat kGCCallStatusLines = 2.0f;
static const CGFloat kGCCallNoteHeight = TGMetricLineCaption;

@interface TGGroupCallViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) NSDictionary *call;
@property (nonatomic, strong) NSArray *participants;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, copy) NSString *joinPayload;
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic, strong) NSDate *openedAt;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, strong) NSArray *observers;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGGroupCallViewController

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId {
	self = [super initWithNibName:nil bundle:nil];
	if (self){
		_chatId = chatId;
		_groupCallId = groupCallId;
		self.title = @"Group Call";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.view.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[self buildHeader];
	[self buildTable];
	[self observe];
	[self loadChatAndCall];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self startTicker];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopTicker];
}

/// The clock is the only thing on this screen that needs a timer, and a timer
/// retains its target: leaving it running after the screen is popped keeps the
/// controller and the timer alive together. It runs only while the screen is.
- (void)startTicker {
	[self stopTicker];
	self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
			selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)stopTicker {
	[self.ticker invalidate];
	self.ticker = nil;
}

- (void)dealloc {
	[self.ticker invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildHeader {
	CGRect bounds = self.view.bounds;
	CGFloat gutter = TGMetricPadLarge;
	CGFloat width = bounds.size.width - TGDoubled(gutter);
	self.header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, bounds.size.width, kGCCallHeaderHeight)];
	self.header.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

	self.titleLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(gutter, TGMetricPad, width, TGMetricLineHeader)];
	self.titleLabel.font = TGFontHeader();
	self.titleLabel.backgroundColor = [UIColor clearColor];
	[self.header addSubview:self.titleLabel];

	CGFloat statusY = TGMetricPad + TGMetricLineHeader + TGMetricPadSmall;
	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(gutter, statusY, width, kGCCallStatusHeight * kGCCallStatusLines)];
	self.statusLabel.font = TGFontSubhead();
	self.statusLabel.numberOfLines = 2;
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[self.header addSubview:self.statusLabel];

	CGFloat noteY = statusY + kGCCallStatusHeight * kGCCallStatusLines + TGMetricPadSmall;
	self.noteLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(gutter, noteY, width, kGCCallNoteHeight)];
	self.noteLabel.font = TGFontCaption();
	self.noteLabel.backgroundColor = [UIColor clearColor];
	[self.header addSubview:self.noteLabel];
}

- (void)buildTable {
	UIView *container = [[UIView alloc] initWithFrame:self.view.bounds];
	self.table = [[UITableView alloc] initWithFrame:container.bounds
											  style:UITableViewStyleGrouped];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = TGMetricPersonRow;
	self.table.tableHeaderView = self.header;
	[self.view addSubview:self.table];
}

- (void)observe {
	__weak typeof(self) weakSelf = self;
	void (^changed)(NSNotification *) = ^(NSNotification *note){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		int32_t callId = [note.userInfo[TGGroupCallIdKey] intValue];
		if (callId && me.groupCallId && callId != me.groupCallId)
			return;
		if (callId)
			me.groupCallId = callId;
		[me reload];
	};
	self.observers = @[
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGGroupCallChangedNotification
							object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed],
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGGroupCallParticipantsChangedNotification
							object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed],
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGGroupCallMessagesChangedNotification
							object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed],
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGThemeChangedNotification
							object:nil queue:[NSOperationQueue mainQueue]
						usingBlock:^(NSNotification *note){
			[weakSelf applyTheme];
		}],
	];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.table];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.header.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[self updateHeader];
	[self.table reloadData];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = self.view.bounds.size.width;
	if (width <= 0)
		return;
	CGRect frame = self.header.frame;
	frame.size.width = width;
	self.header.frame = frame;
	self.table.tableHeaderView = self.header;
	CGFloat gutter = TGMetricPadLarge;
	CGFloat textWidth = width - TGDoubled(gutter);
	CGRect title = self.titleLabel.frame;
	title.size.width = textWidth;
	self.titleLabel.frame = title;
	CGRect status = self.statusLabel.frame;
	status.size.width = textWidth;
	self.statusLabel.frame = status;
	CGRect note = self.noteLabel.frame;
	note.size.width = textWidth;
	self.noteLabel.frame = note;
}

#pragma mark - loading

- (void)loadChatAndCall {
	if (!self.chatId){
		[self loadCall];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		NSString *title = chat[@"title"];
		if (title.length)
			me.chatTitle = title;
		int32_t fromChat = [chat[@"video_chat"][@"group_call_id"] intValue];
		if (!me.groupCallId && fromChat)
			me.groupCallId = fromChat;
		[me loadCall];
	}];
}

- (void)loadCall {
	if (!self.groupCallId){
		[self reload];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupCall:self.groupCallId completion:^(NSDictionary *call, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		me.call = call;
		me.loadError = call ? nil : (error ?: @"Telegram did not return this call.");
		if (!call){
			[TGAlertSheet showMessage:me.loadError title:@"Group Call" inView:me.view];
			[me reload];
			return;
		}
		if ([call[@"isJoined"] boolValue]){
			[[TGClient shared] loadGroupCallParticipants:me.groupCallId limit:100
					completion:^(BOOL ok, NSString *why){ [weakSelf reload]; }];
		}
		[me reload];
	}];
}

- (void)reload {
	self.participants = [[TGClient shared] groupCallParticipantSnapshot:self.groupCallId];
	if (!self.openedAt && self.call)
		self.openedAt = [NSDate date];
	[self updateHeader];
	self.sections = [self buildSections];
	[self.table reloadData];
}

- (void)tick {
	[self updateHeader];
}

static NSString *TGGroupCallClock(NSTimeInterval seconds) {
	NSInteger total = (NSInteger)MAX(0, seconds);
	if (total >= 3600)
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld",
				(long)(total / 3600), (long)((total % 3600) / 60), (long)(total % 60)];
	return [NSString stringWithFormat:@"%02ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

static NSString *TGGroupCallWhen(int32_t stamp) {
	if (!stamp)
		return @"";
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateFormat = @"d MMM HH:mm";
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
}

- (NSString *)speakingLine {
	NSMutableArray *names = [NSMutableArray array];
	for (NSDictionary *row in self.participants)
		if ([row[@"isSpeaking"] boolValue] && ![row[@"isMutedForAllUsers"] boolValue]){
			NSString *name = row[@"name"];
			if (name.length)
				[names addObject:name];
		}
	if (names.count)
		return [NSString stringWithFormat:@"Speaking: %@",
				[names componentsJoinedByString:@", "]];
	for (NSDictionary *speaker in self.call[@"recentSpeakers"])
		if ([speaker[@"isSpeaking"] boolValue])
			return @"Someone is speaking";
	return @"";
}

- (void)updateHeader {
	if (!self.isViewLoaded)
		return;
	NSString *title = self.call[@"title"];
	if (!title.length)
		title = self.chatTitle;
	if (!title.length)
		title = @"Group Call";
	self.titleLabel.text = title;
	self.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.noteLabel.textColor = [[TGTheme shared] secondaryTextColour];

	if (!self.call){
		self.statusLabel.text = self.groupCallId
				? (self.loadError.length ? self.loadError : @"Reading the call from Telegram...")
				: @"No video chat in this chat yet.";
		self.noteLabel.text = self.groupCallId
				? @"" : @"Open Setup to create one or to schedule it.";
		return;
	}

	NSInteger count = [self.call[@"participantCount"] integerValue];
	NSMutableArray *line = [NSMutableArray array];
	if ([self.call[@"isActive"] boolValue]){
		[line addObject:@"Live"];
		[line addObject:[NSString stringWithFormat:@"%ld %@", (long)count,
				count == 1 ? @"participant" : @"participants"]];
		if ([self.call[@"isJoined"] boolValue] && self.openedAt)
			[line addObject:TGGroupCallClock(-[self.openedAt timeIntervalSinceNow])];
		else
			[line addObject:@"not joined"];
	} else if ([self.call[@"scheduledStartDate"] intValue] > 0){
		[line addObject:[NSString stringWithFormat:@"Scheduled for %@",
				TGGroupCallWhen([self.call[@"scheduledStartDate"] intValue])]];
	} else {
		[line addObject:@"Ended"];
		NSInteger duration = [self.call[@"duration"] intValue];
		if (duration > 0)
			[line addObject:[NSString stringWithFormat:@"lasted %@",
					TGGroupCallClock(duration)]];
	}
	if ([self.call[@"recordDuration"] intValue] > 0)
		[line addObject:[NSString stringWithFormat:@"recording %@",
				TGGroupCallClock([self.call[@"recordDuration"] intValue])]];
	self.statusLabel.text = [line componentsJoinedByString:@" · "];

	NSString *speaking = [self speakingLine];
	if (speaking.length){
		self.noteLabel.text = speaking;
	} else if ([self.call[@"isJoined"] boolValue]) {
		self.noteLabel.text = @"Joined. This client has no group-call audio engine.";
	} else {
		self.noteLabel.text = @"Join asks Telegram for the tgcalls payload; "
				@"there is no media engine here to play it.";
	}
}

#pragma mark - sections

- (NSDictionary *)row:(NSString *)title detail:(NSString *)detail tap:(void (^)(void))tap {
	NSMutableDictionary *row = [NSMutableDictionary dictionary];
	row[@"kind"] = @"row";
	row[@"title"] = title ?: @"";
	if (detail.length)
		row[@"detail"] = detail;
	if (tap)
		row[@"tap"] = tap;
	return row;
}

- (NSDictionary *)destructiveRow:(NSString *)title detail:(NSString *)detail tap:(void (^)(void))tap {
	NSMutableDictionary *row = [[self row:title detail:detail tap:tap] mutableCopy];
	row[@"destructive"] = @YES;
	return row;
}

- (NSArray *)buildSections {
	NSMutableArray *sections = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;

	if (!self.call && !self.groupCallId){
		[sections addObject:@{@"header" : @"Video Chat",
			@"rows" : @[[self row:@"Create a Video Chat"
						   detail:@"Title, schedule and participant"
								  tap:^{ [weakSelf openSetup]; }]]}];
		return sections;
	}
	if (!self.call){
		NSString *detail = self.loadError.length ? self.loadError
				: @"Reading the call from Telegram";
		[sections addObject:@{@"header" : @"Call",
			@"rows" : @[[self row:(self.loadError.length ? @"Unavailable" : @"Loading")
						   detail:detail tap:nil]]}];
		return sections;
	}

	NSMutableArray *callRows = [NSMutableArray array];
	BOOL joined = [self.call[@"isJoined"] boolValue];
	BOOL active = [self.call[@"isActive"] boolValue];
	if (active){
		[callRows addObject:[self row:(joined ? @"Leave Call" : @"Join Call")
				detail:(joined ? @"Stops listening in this client"
						: @"Asks Telegram for the join payload")
				tap:^{ joined ? [weakSelf leaveCall] : [weakSelf joinCall]; }]];
	}
	if (!active && [self.call[@"scheduledStartDate"] intValue] > 0){
		[callRows addObject:[self row:@"Start Scheduled Call"
				detail:@"Telegram starts it now" tap:^{ [weakSelf startScheduled]; }]];
	}
	if (joined){
		NSDictionary *me = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
		BOOL muted = [me[@"isMutedForAllUsers"] boolValue] ||
					 [me[@"isMutedForCurrentUser"] boolValue];
		[callRows addObject:[self row:(muted ? @"Unmute Myself" : @"Mute Myself")
				detail:(muted ? @"Speak in the call" : @"Stop sending audio")
				tap:^{ [weakSelf toggleSelfMuted]; }]];
		BOOL hand = [me[@"isHandRaised"] boolValue];
		[callRows addObject:[self row:(hand ? @"Lower My Hand" : @"Raise My Hand")
				detail:(hand ? @"Take the hand down" : @"Ask to speak")
				tap:^{ [weakSelf toggleSelfHand]; }]];
		BOOL speaking = [me[@"isSpeaking"] boolValue];
		[callRows addObject:[self row:(speaking ? @"Stop Speaking" : @"Mark Myself Speaking")
				detail:@"setGroupCallParticipantIsSpeaking"
				tap:^{ [weakSelf toggleSelfSpeaking]; }]];
	}
	BOOL videoOn = [self.call[@"isMyVideoEnabled"] boolValue];
	[callRows addObject:[self row:(videoOn ? @"Turn My Video Off" : @"Turn My Video On")
			detail:@"Needs a camera pipeline this client does not have"
			tap:^{ [weakSelf toggleMyVideo]; }]];
	BOOL paused = [self.call[@"isMyVideoPaused"] boolValue];
	[callRows addObject:[self row:(paused ? @"Resume My Video" : @"Pause My Video")
			detail:@"TDLib records the flag; there is no frame to pause"
			tap:^{ [weakSelf toggleMyVideoPaused]; }]];
	[sections addObject:@{@"header" : @"Call", @"rows" : callRows}];

	NSMutableArray *people = [NSMutableArray array];
	NSInteger shown = MIN((NSInteger)self.participants.count, (NSInteger)kGCCallRowsShown);
	for (NSInteger i = 0; i < shown; i++){
		NSMutableDictionary *row = [NSMutableDictionary dictionary];
		row[@"kind"] = @"participant";
		row[@"value"] = self.participants[(NSUInteger)i];
		row[@"tap"] = ^{ [weakSelf openParticipants]; };
		[people addObject:row];
	}
	NSInteger count = [self.call[@"participantCount"] integerValue];
	if (self.participants.count || count > shown){
		[people addObject:[self row:(self.participants.count
						? @"All Participants" : @"Load Participants")
				detail:[NSString stringWithFormat:@"%ld in the call", (long)count]
				tap:^{ [weakSelf openParticipants]; }]];
	}
	[sections addObject:@{@"header" : @"People", @"rows" : people}];

	NSMutableArray *messages = [NSMutableArray array];
	NSArray *callMessages = [[TGClient shared] groupCallMessageSnapshot:self.groupCallId];
	NSInteger first = MAX(0, (NSInteger)callMessages.count - 3);
	for (NSInteger i = first; i < (NSInteger)callMessages.count; i++){
		NSDictionary *message = callMessages[(NSUInteger)i];
		[messages addObject:[self row:(message[@"senderName"] ?: @"Participant")
				detail:(message[@"text"] ?: @"Paid reaction")
				tap:^{ [weakSelf openMessages]; }]];
	}
	[messages addObject:[self row:(callMessages.count ? @"All Call Messages" : @"Send a Call Message")
			detail:@"Open the message bar" tap:^{ [weakSelf openMessages]; }]];
	[sections addObject:@{@"header" : @"Messages", @"rows" : messages}];

	NSMutableArray *tools = [NSMutableArray array];
	[tools addObject:[self row:@"Setup and Management"
						detail:@"Title, recording, invite link, RTMP, switches"
						   tap:^{ [weakSelf openSetup]; }]];
	[tools addObject:[self row:@"Streams and Data"
						detail:@"Channels, segments, encryption check"
						   tap:^{ [weakSelf openStreams]; }]];
	[sections addObject:@{@"header" : @"Tools", @"rows" : tools}];

	NSMutableArray *invite = [NSMutableArray array];
	[invite addObject:[self row:@"Invite a Member"
						 detail:@"Video chat or group call, by user id"
							tap:^{ [weakSelf inviteMember]; }]];
	[invite addObject:[self row:@"Copy Invite Link"
						 detail:self.call[@"inviteLink"] ?: @"Ask Telegram for the link"
							tap:^{ [weakSelf copyInviteLink]; }]];
	[invite addObject:[self row:@"Decline an Invitation"
						 detail:@"By the service message id"
							tap:^{ [weakSelf declineInvitation]; }]];
	[sections addObject:@{@"header" : @"Invitation", @"rows" : invite}];

	NSMutableArray *end = [NSMutableArray array];
	if (active){
		[end addObject:[self destructiveRow:@"End Call"
				detail:@"For everybody in the call" tap:^{ [weakSelf endCall]; }]];
	}
	[sections addObject:@{@"header" : @"End", @"rows" : end}];
	return sections;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [(NSArray *)self.sections[(NSUInteger)section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.sections[(NSUInteger)section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	NSString *header = self.sections[(NSUInteger)section][@"header"];
	if ([header isEqualToString:@"Call"])
		return @"The clock counts from when this screen opened: Telegram's active "
				@"groupCall record carries no start timestamp.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
	if ([row[@"kind"] isEqualToString:@"participant"]){
		TGGroupCallParticipantCell *cell = [tableView dequeueReusableCellWithIdentifier:@"participant"];
		if (!cell)
			cell = [[TGGroupCallParticipantCell alloc] initWithStyle:UITableViewCellStyleDefault
													 reuseIdentifier:@"participant"];
		[cell setParticipant:row[@"value"] inTable:tableView];
		return cell;
	}
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = row[@"title"];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [row[@"destructive"] boolValue]
			? [[TGTheme shared] destructiveColour] : [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = row[@"detail"];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = row[@"tap"] ? UITableViewCellAccessoryDisclosureIndicator
									 : UITableViewCellAccessoryNone;
	cell.selectionStyle = row[@"tap"] ? UITableViewCellSelectionStyleBlue
									  : UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section >= (NSInteger)self.sections.count)
		return;
	NSArray *rows = self.sections[(NSUInteger)indexPath.section][@"rows"];
	if (indexPath.row >= (NSInteger)rows.count)
		return;
	void (^tap)(void) = rows[(NSUInteger)indexPath.row][@"tap"];
	if (tap)
		tap();
}

#pragma mark - call actions

- (void)joinCall {
	if (!self.groupCallId){
		[self openSetup];
		return;
	}
	if (self.busy)
		return;
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused the join."
								title:@"Join" inView:me.view];
			return;
		}
		me.openedAt = [NSDate date];
		[me loadCall];
	};
	NSDictionary *parameters = TGGroupCallJoinParameters(0, @"", NO, NO);
	if ([self.call[@"isVideoChat"] boolValue] || [self.call[@"isLiveStory"] boolValue]){
		[[TGClient shared] joinVideoChat:self.groupCallId participant:nil
							   parameters:parameters inviteHash:@""
							   completion:^(NSString *payload, NSString *error){
			if (payload)
				weakSelf.joinPayload = payload;
			done(error.length == 0, error);
		}];
	} else {
		[[TGClient shared] joinGroupCallWithInput:TGGroupCallInput(self.groupCallId, 0)
									   parameters:parameters
									   completion:^(NSDictionary *info, NSString *error){
			if (info[@"joinPayload"])
				weakSelf.joinPayload = info[@"joinPayload"];
			done(error.length == 0, error);
		}];
	}
}

- (void)leaveCall {
	if (self.busy)
		return;
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] leaveGroupCall:self.groupCallId completion:^(BOOL ok, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok)
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Leave" inView:me.view];
		[me loadCall];
	}];
}

- (void)endCall {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Everybody in the call is disconnected."
						title:@"End Call" action:@"End" destructive:YES
					   inView:self.view onConfirm:^{
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] endGroupCall:me.groupCallId completion:^(BOOL ok, NSString *error){
			if (!ok)
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"End Call" inView:me.view];
			[me loadCall];
		}];
	}];
}

- (NSDictionary *)selfSender {
	NSDictionary *participant = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
	if (participant[@"sender"])
		return participant[@"sender"];
	int64_t meId = [[TGClient shared].me[@"id"] longLongValue];
	return @{@"@type" : @"messageSenderUser", @"user_id" : @(meId)};
}

- (void)toggleSelfMuted {
	if (!self.busy){
		self.busy = YES;
		NSDictionary *participant = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
		BOOL muted = [participant[@"isMutedForAllUsers"] boolValue] ||
					 [participant[@"isMutedForCurrentUser"] boolValue];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] toggleGroupCallParticipant:[self selfSender]
											   inCall:self.groupCallId isMuted:!muted
											completion:^(BOOL ok, NSString *error){
			TGGroupCallViewController *me = weakSelf;
			if (!me)
				return;
			me.busy = NO;
			if (!ok)
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"Mute" inView:me.view];
			[me loadCall];
		}];
	}
}

- (void)toggleSelfHand {
	NSDictionary *participant = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
	BOOL raised = [participant[@"isHandRaised"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallParticipant:[self selfSender]
										   inCall:self.groupCallId
									 isHandRaised:!raised
									   completion:^(BOOL ok, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok)
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Hand" inView:me.view];
		[me loadCall];
	}];
}

- (void)toggleSelfSpeaking {
	NSDictionary *participant = [[TGClient shared] currentGroupCallParticipant:self.groupCallId];
	BOOL speaking = [participant[@"isSpeaking"] boolValue];
	int32_t source = [participant[@"audioSourceId"] intValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setGroupCallParticipantSpeaking:source inCall:self.groupCallId
											isSpeaking:!speaking
											completion:^(NSDictionary *sender, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		if (error.length)
			[TGAlertSheet showMessage:error title:@"Speaking" inView:me.view];
		[me loadCall];
	}];
}

- (void)toggleMyVideo {
	BOOL on = [self.call[@"isMyVideoEnabled"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallMyVideoEnabled:self.groupCallId enabled:!on
										  completion:^(BOOL ok, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok)
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Video" inView:me.view];
		[me loadCall];
	}];
}

- (void)toggleMyVideoPaused {
	BOOL paused = [self.call[@"isMyVideoPaused"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallMyVideoPaused:self.groupCallId paused:!paused
										 completion:^(BOOL ok, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok)
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Video" inView:me.view];
		[me loadCall];
	}];
}

- (void)startScheduled {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] startScheduledVideoChat:self.groupCallId
									completion:^(BOOL ok, NSString *error){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok)
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Scheduled Call" inView:me.view];
		[me loadCall];
	}];
}

#pragma mark - invitation actions

- (void)inviteMember {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Invite a Member" message:@"Telegram user id."
				placeholder:@"123456789" text:nil action:@"Invite"
					 inView:self.view onSubmit:^(NSString *text){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		int64_t userId = text.longLongValue;
		if (userId <= 0)
			return;
		if ([me.call[@"isVideoChat"] boolValue]){
			[[TGClient shared] inviteVideoChatParticipants:@[@(userId)]
					toCall:me.groupCallId completion:^(BOOL ok, NSString *error){
				[me reportInvite:ok error:error];
			}];
		} else {
			[[TGClient shared] inviteGroupCallParticipant:userId toCall:me.groupCallId
					isVideo:NO completion:^(NSDictionary *answer, NSString *error){
				NSString *outcome = answer[@"outcome"];
				NSString *sentence = error;
				if (!sentence.length){
					sentence = [outcome isEqualToString:@"success"] ? @"Invited."
							: [outcome isEqualToString:@"privacy"] ? @"Their privacy settings refused it."
							: [outcome isEqualToString:@"already"] ? @"They are already in the call."
							: @"They were banned from this call.";
				}
				[TGAlertSheet showMessage:sentence title:@"Invite" inView:me.view];
				[me loadCall];
			}];
		}
	}];
}

- (void)reportInvite:(BOOL)ok error:(NSString *)error {
	if (!ok)
		[TGAlertSheet showMessage:error ?: @"Telegram refused that."
							title:@"Invite" inView:self.view];
	else
		[TGAlertSheet showMessage:@"Invited." title:@"Invite" inView:self.view];
	[self loadCall];
}

- (void)copyInviteLink {
	NSString *link = self.call[@"inviteLink"];
	if (link.length){
		[UIPasteboard generalPasteboard].string = link;
		[TGAlertSheet showMessage:link title:@"Invite Link Copied" inView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Can unmute themselves", @"Join muted"]
						title:@"Invite Link" destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] videoChatInviteLink:me.groupCallId canSelfUnmute:index == 0
									completion:^(NSString *url, NSString *error){
			if (!url.length){
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"Invite Link" inView:me.view];
				return;
			}
			[UIPasteboard generalPasteboard].string = url;
			[TGAlertSheet showMessage:url title:@"Invite Link Copied" inView:me.view];
		}];
	}];
}

- (void)declineInvitation {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Decline Invitation"
					message:@"The id of the messageGroupCall message."
				placeholder:@"Message id" text:nil action:@"Decline"
					 inView:self.view onSubmit:^(NSString *text){
		TGGroupCallViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] declineGroupCallInvitationInChat:me.chatId
				messageId:text.longLongValue completion:^(BOOL ok, NSString *error){
			[TGAlertSheet showMessage:(ok ? @"Invitation declined."
					: (error ?: @"Telegram refused that."))
								title:@"Invitation" inView:me.view];
		}];
	}];
}

#pragma mark - tools

- (void)openParticipants {
	TGGroupCallParticipantsViewController *screen =
			[[TGGroupCallParticipantsViewController alloc] initWithChatId:self.chatId
															 groupCallId:self.groupCallId];
	screen.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:screen animated:YES];
}

- (void)openSetup {
	TGVideoChatSetupViewController *screen =
			[[TGVideoChatSetupViewController alloc] initWithChatId:self.chatId
													   groupCallId:self.groupCallId];
	screen.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:screen animated:YES];
}

- (void)openMessages {
	TGCallMessagesViewController *screen =
			[[TGCallMessagesViewController alloc] initWithChatId:self.chatId
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
