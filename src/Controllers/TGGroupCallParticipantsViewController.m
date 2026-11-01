#import "TGGroupCallParticipantsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGGroupCallParticipantCell.h"

@interface TGGroupCallParticipantsViewController ()
@property (nonatomic, strong) NSArray *participants;
@property (nonatomic, strong) NSArray *listedSenders;
@property (nonatomic, strong) NSDictionary *call;
@property (nonatomic, copy) NSString *footerText;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) NSArray *observers;
@end

@implementation TGGroupCallParticipantsViewController

- (instancetype)initWithChatId:(int64_t)chatId groupCallId:(int32_t)groupCallId {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_chatId = chatId;
		_groupCallId = groupCallId;
		self.title = @"Participants";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];
	[self observe];
	[self load];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)observe {
	__weak typeof(self) weakSelf = self;
	void (^changed)(NSNotification *) = ^(NSNotification *note){
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me)
			return;
		int32_t callId = [note.userInfo[TGGroupCallIdKey] intValue];
		if (callId && callId != me.groupCallId)
			return;
		[me refresh];
	};
	self.observers = @[
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGGroupCallParticipantsChangedNotification
							object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed],
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGGroupCallChangedNotification
							object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed],
		[[NSNotificationCenter defaultCenter]
				addObserverForName:TGThemeChangedNotification
							object:nil queue:[NSOperationQueue mainQueue]
						usingBlock:^(NSNotification *note){
			[weakSelf applyTheme];
			[weakSelf.tableView reloadData];
		}],
	];
}

- (void)load {
	if (!self.groupCallId)
		return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] groupCall:self.groupCallId completion:^(NSDictionary *call, NSString *error){
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me)
			return;
		me.loading = NO;
		me.call = call;
		if (!call){
			me.footerText = error ?: @"Telegram did not return this call.";
			[me refresh];
			return;
		}
		if ([call[@"isJoined"] boolValue]){
			[[TGClient shared] loadGroupCallParticipants:me.groupCallId limit:100
					completion:^(BOOL ok, NSString *why){
				TGGroupCallParticipantsViewController *again = weakSelf;
				if (!again)
					return;
				if (!ok)
					again.footerText = why;
				[again refresh];
			}];
		} else if (![call[@"isVideoChat"] boolValue]){
			// A call that is not bound to a chat has a participants request
			// of its own: getGroupCallParticipants takes the inputGroupCall
			// and answers ids. A video chat has no such request until this
			// account joins it.
			[[TGClient shared] groupCallParticipantsWithInput:
					TGGroupCallInput(me.groupCallId, 0) limit:100
					completion:^(NSDictionary *answer, NSString *why){
				TGGroupCallParticipantsViewController *again = weakSelf;
				if (!again)
					return;
				if (!answer){
					again.footerText = why;
					[again refresh];
					return;
				}
				again.listedSenders = answer[@"senders"];
				again.footerText = [NSString stringWithFormat:
						@"%ld participants Telegram listed. Join the call on the "
						@"call screen for their speaking and mute state.",
						(long)[answer[@"total"] integerValue]];
				[again refresh];
			}];
		} else {
			me.footerText = @"Join the call on the call screen to load its participants.";
			[me refresh];
		}
	}];
}

- (void)refresh {
	NSArray *rows = [[TGClient shared] groupCallParticipantSnapshot:self.groupCallId];
	if (!rows.count && self.listedSenders.count)
		rows = [self rowsFromSenders:self.listedSenders];
	self.participants = rows;
	if (!self.footerText.length){
		NSInteger count = [self.call[@"participantCount"] integerValue];
		if (count > 0)
			self.footerText = [NSString stringWithFormat:
					@"%ld in the call. Mute, volume and hand actions go to Telegram; "
					@"the server applies them and the list follows its answer.",
					(long)count];
		else
			self.footerText = @"Nobody has joined yet.";
	}
	[self.tableView reloadData];
}

- (NSArray *)rowsFromSenders:(NSArray *)senders {
	NSMutableArray *rows = [NSMutableArray array];
	int64_t meId = [[TGClient shared].me[@"id"] longLongValue];
	for (NSDictionary *sender in senders){
		if (![sender isKindOfClass:NSDictionary.class])
			continue;
		BOOL chat = [sender[@"@type"] isEqualToString:@"messageSenderChat"];
		int64_t userId = [sender[@"user_id"] longLongValue];
		int64_t chatId = [sender[@"chat_id"] longLongValue];
		NSString *name = chat ? [[TGClient shared] titleForChat:chatId]
							  : [[TGClient shared] nameForUserId:userId];
		NSMutableDictionary *row = [NSMutableDictionary dictionary];
		row[@"sender"] = sender;
		row[@"name"] = name ?: @"";
		row[@"userId"] = @(userId);
		row[@"chatId"] = @(chatId);
		row[@"kind"] = chat ? @"chat" : @"user";
		row[@"isCurrentUser"] = @(!chat && userId == meId);
		row[@"isSpeaking"] = @NO;
		row[@"isHandRaised"] = @NO;
		row[@"isMutedForAllUsers"] = @NO;
		row[@"isMutedForCurrentUser"] = @NO;
		row[@"hasVideo"] = @NO;
		row[@"volumeLevel"] = @(10000);
		[rows addObject:row];
	}
	return rows;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.participants.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return self.footerText;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)self.participants.count)
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	TGGroupCallParticipantCell *cell = [tableView dequeueReusableCellWithIdentifier:@"participant"];
	if (!cell)
		cell = [[TGGroupCallParticipantCell alloc] initWithStyle:UITableViewCellStyleDefault
												 reuseIdentifier:@"participant"];
	[cell setParticipant:self.participants[(NSUInteger)indexPath.row] inTable:tableView];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.participants.count)
		return;
	[self showActionsForParticipant:self.participants[(NSUInteger)indexPath.row]];
}

#pragma mark - one person's actions

- (void)showActionsForParticipant:(NSDictionary *)participant {
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *keys = [NSMutableArray array];
	BOOL mutedAll = [participant[@"isMutedForAllUsers"] boolValue];
	BOOL mutedMe = [participant[@"isMutedForCurrentUser"] boolValue];
	BOOL current = [participant[@"isCurrentUser"] boolValue];

	if (!current && ([participant[@"canBeMutedForAllUsers"] boolValue] ||
					 [participant[@"canBeUnmutedForAllUsers"] boolValue])){
		[titles addObject:(mutedAll ? @"Unmute for Everyone" : @"Mute for Everyone")];
		[keys addObject:@"muteAll"];
	}
	if (!current && ([participant[@"canBeMutedForCurrentUser"] boolValue] ||
					 [participant[@"canBeUnmutedForCurrentUser"] boolValue])){
		[titles addObject:(mutedMe ? @"Unmute for Me" : @"Mute for Me")];
		[keys addObject:@"muteMe"];
	}
	[titles addObject:@"Volume"];
	[keys addObject:@"volume"];
	if (current){
		[titles addObject:([participant[@"isHandRaised"] boolValue]
				? @"Lower My Hand" : @"Raise My Hand")];
		[keys addObject:@"hand"];
	} else if ([participant[@"isHandRaised"] boolValue]){
		[titles addObject:@"Lower Their Hand"];
		[keys addObject:@"hand"];
	}
	BOOL owned = [self.call[@"isOwned"] boolValue];
	if (owned && !current && [participant[@"userId"] longLongValue]){
		[titles addObject:@"Ban from Call"];
		[keys addObject:@"ban"];
	}

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:participant[@"name"]
			destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me || index < 0 || index >= (NSInteger)keys.count)
			return;
		NSString *key = keys[(NSUInteger)index];
		if ([key isEqualToString:@"volume"])
			[me askVolumeForParticipant:participant];
		else if ([key isEqualToString:@"muteAll"] || [key isEqualToString:@"muteMe"])
			[me toggleMuteForParticipant:participant forAll:[key isEqualToString:@"muteAll"]];
		else if ([key isEqualToString:@"hand"])
			[me toggleHandForParticipant:participant];
		else if ([key isEqualToString:@"ban"])
			[me banParticipant:participant];
	}];
}

- (void)toggleMuteForParticipant:(NSDictionary *)participant forAll:(BOOL)forAll {
	BOOL muted = forAll ? [participant[@"isMutedForAllUsers"] boolValue]
						: [participant[@"isMutedForCurrentUser"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallParticipant:participant[@"sender"]
										   inCall:self.groupCallId
										  isMuted:!muted
									   completion:^(BOOL ok, NSString *error){
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Mute" inView:me.view];
			return;
		}
		[me load];
	}];
}

- (void)toggleHandForParticipant:(NSDictionary *)participant {
	BOOL raised = [participant[@"isHandRaised"] boolValue];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGroupCallParticipant:participant[@"sender"]
										   inCall:self.groupCallId
									 isHandRaised:!raised
									   completion:^(BOOL ok, NSString *error){
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Hand" inView:me.view];
			return;
		}
		[me load];
	}];
}

- (void)askVolumeForParticipant:(NSDictionary *)participant {
	NSArray *titles = @[@"25%", @"50%", @"100%", @"150%", @"200%"];
	NSArray *levels = @[@(2500), @(5000), @(10000), @(15000), @(20000)];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Volume"
			destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me || index < 0 || index >= (NSInteger)levels.count)
			return;
		[[TGClient shared] setGroupCallParticipant:participant[@"sender"]
											inCall:me.groupCallId
									   volumeLevel:[levels[(NSUInteger)index] integerValue]
										completion:^(BOOL ok, NSString *error){
			if (!ok)
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"Volume" inView:me.view];
			else
				[me load];
		}];
	}];
}

- (void)banParticipant:(NSDictionary *)participant {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The owner can invite them back later."
						title:@"Ban from Call" action:@"Ban" destructive:YES
					   inView:self.view onConfirm:^{
		TGGroupCallParticipantsViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] banGroupCallParticipants:
				@[participant[@"userId"] ?: @(0)] inCall:me.groupCallId
				completion:^(BOOL ok, NSString *error){
			if (!ok)
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"Ban" inView:me.view];
			else
				[me load];
		}];
	}];
}

@end

// vim:ft=objc
