#import "TGDMTopicViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const NSInteger kSectionInfo = 0;
static const NSInteger kSectionActions = 1;
static const NSInteger kSectionHistory = 2;

@interface TGDMTopicViewController ()
@property (nonatomic, strong) NSArray *history;
@property (nonatomic, strong) NSArray *actionTitles;
@end

@implementation TGDMTopicViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	NSString *name = self.topic[@"senderName"];
	self.title = name.length ? name : @"Topic";
	self.history = @[];
	self.tableView.rowHeight = TGMetricRow;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Reply" style:UIBarButtonItemStylePlain
				   target:self action:@selector(replyTapped)];
	[self applyTheme];
	[self rebuildActions];
	[self loadTopic];
	[self loadHistory];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TGThemeChangedNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)rebuildActions {
	NSMutableArray *actions = [NSMutableArray arrayWithObjects:
			@"Send Direct Message",
			(@"Jump to Date"), @"Read All Reactions", @"Unpin All Messages",
			@"Delete Messages by Date", @"Delete All Messages", nil];
	if ([self.topic[@"isMarkedUnread"] boolValue])
		[actions insertObject:@"Mark as Read" atIndex:0];
	else
		[actions insertObject:@"Mark as Unread" atIndex:0];
	self.actionTitles = actions;
}

- (void)replyTapped {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Direct Message"
					message:@"Reply to subscriber:"
				placeholder:@"Type a message…"
					   text:nil
					 action:@"Send"
					 inView:self.view
				   onSubmit:^(NSString *text){
		[weakSelf sendDirectMessage:text];
	}];
}

- (void)sendDirectMessage:(NSString *)text {
	if (!text.length)
		return;
	NSDictionary *topicIdObj = @{
		@"@type" : @"messageTopicDirectMessages",
		@"direct_messages_chat_topic_id" : @(self.topicId)
	};
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{
		@"@type" : @"sendMessage",
		@"chat_id" : @(self.chatId),
		@"topic_id" : topicIdObj,
		@"input_message_content" : @{
			@"@type" : @"inputMessageText",
			@"text" : @{
				@"@type" : @"formattedText",
				@"text" : text ?: @""
			}
		}
	} completion:^(NSDictionary *result){
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf loadHistory];
		});
	}];
}

- (void)loadTopic {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] directMessagesChatTopic:self.topicId inChat:self.chatId
									completion:^(NSDictionary *topic, NSString *error){
		TGDMTopicViewController *me = weakSelf;
		if (!me || !topic)
			return;
		me.topic = topic;
		[me rebuildActions];
		[me.tableView reloadData];
	}];
}

- (void)loadHistory {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] directMessagesChatTopicHistory:self.topicId
											  inChat:self.chatId
									   fromMessageId:0 offset:0 limit:30
										  completion:^(NSArray *messages, NSString *error){
		TGDMTopicViewController *me = weakSelf;
		if (!me)
			return;
		me.history = messages ?: @[];
		[me.tableView reloadData];
	}];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kSectionInfo)
		return 5;
	if (section == kSectionActions)
		return self.actionTitles.count;
	return self.history.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == kSectionInfo)
		return @"Topic";
	if (section == kSectionActions)
		return @"Actions";
	return self.history.count ? @"Recent Messages" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == kSectionActions)
		return @"These are the channel-direct-messages calls. A topic id from a "
			   @"chat this account does not administer is refused by Telegram.";
	if (section == kSectionHistory && !self.history.count)
		return @"No messages were returned for this topic.";
	return nil;
}

- (NSArray *)infoPairs {
	NSDictionary *topic = self.topic ?: @{};
	NSString *sender = topic[@"senderName"];
	if (!sender.length)
		sender = [NSString stringWithFormat:@"%@ %@",
				topic[@"senderKind"] ?: @"user", topic[@"senderId"] ?: @(0)];
	NSString *marked = [topic[@"isMarkedUnread"] boolValue] ? @"Yes" : @"No";
	id lastValue = topic[@"lastMessage"];
	NSString *last = @"—";
	if ([lastValue isKindOfClass:NSDictionary.class]){
		NSString *text = lastValue[@"text"];
		last = text.length ? text : @"(media)";
	}
	return @[
		@[@"From", sender],
		@[@"Unread", [NSString stringWithFormat:@"%@ messages, %@ reactions",
				topic[@"unread"] ?: @(0), topic[@"unreadReactions"] ?: @(0)]],
		@[@"Marked unread", marked],
		@[@"Paid messages", [topic[@"canSendUnpaid"] boolValue]
				? @"Unpaid allowed" : @"Paid only"],
		@[@"Last message", [last isKindOfClass:NSString.class] ? last : @"—"],
	];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (indexPath.section == kSectionInfo){
		NSArray *pair = [self infoPairs][indexPath.row];
		cell.textLabel.text = pair[0];
		cell.detailTextLabel.text = pair[1];
		return cell;
	}
	if (indexPath.section == kSectionActions){
		cell.textLabel.text = self.actionTitles[indexPath.row];
		cell.textLabel.textColor = [self.actionTitles[indexPath.row]
				hasPrefix:@"Delete"] ? [[TGTheme shared] destructiveColour]
									 : [[TGTheme shared] accentColour];
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	NSDictionary *message = self.history[indexPath.row];
	NSString *text = message[@"text"];
	cell.textLabel.text = text.length ? text : [self describeMessage:message];
	NSNumber *date = message[@"date"];
	NSString *when = [date isKindOfClass:NSNumber.class] && date.doubleValue > 0
			? [NSDateFormatter localizedStringFromDate:
					[NSDate dateWithTimeIntervalSince1970:date.doubleValue]
					dateStyle:NSDateFormatterShortStyle
					timeStyle:NSDateFormatterShortStyle]
			: @"";
	cell.detailTextLabel.text = [message[@"outgoing"] boolValue]
			? [NSString stringWithFormat:@"You · %@", when]
			: when;
	return cell;
}

- (NSString *)describeMessage:(NSDictionary *)message {
	NSString *kind = message[@"kind"];
	if ([kind isEqualToString:@"messagePhoto"]) return @"Photo";
	if ([kind isEqualToString:@"messageVideo"]) return @"Video";
	if ([kind isEqualToString:@"messageAudio"]) return @"Audio";
	if ([kind isEqualToString:@"messageVoiceNote"]) return @"Voice note";
	if ([kind isEqualToString:@"messageDocument"]) return @"File";
	if ([kind isEqualToString:@"messageSticker"]) return @"Sticker";
	return @"Message";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != kSectionActions)
		return;
	NSString *title = self.actionTitles[indexPath.row];
	if ([title isEqualToString:@"Send Direct Message"]){
		[self replyTapped];
		return;
	}
	if ([title hasPrefix:@"Mark as"]){
		BOOL mark = [title isEqualToString:@"Mark as Unread"];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] setDirectMessagesChatTopic:self.topicId
											  inChat:self.chatId
									markedAsUnread:mark
										  completion:^(BOOL ok, NSString *error){
			TGDMTopicViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
									title:@"Topic" inView:me.view];
				return;
			}
			NSMutableDictionary *patched = [me.topic mutableCopy];
			patched[@"isMarkedUnread"] = @(mark);
			me.topic = patched;
			[me rebuildActions];
			[me.tableView reloadData];
		}];
		return;
	}
	if ([title isEqualToString:@"Jump to Date"]){
		[self jumpToDate];
		return;
	}
	if ([title isEqualToString:@"Read All Reactions"]){
		[self runSimple:@"readAllDirectMessagesChatTopicReactions"
				  title:@"Read All Reactions"];
		return;
	}
	if ([title isEqualToString:@"Unpin All Messages"]){
		[self runSimple:@"unpinAllDirectMessagesChatTopicMessages"
				  title:@"Unpin All Messages"];
		return;
	}
	if ([title isEqualToString:@"Delete Messages by Date"]){
		[self deleteByDate];
		return;
	}
	if ([title isEqualToString:@"Delete All Messages"]){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"Delete every message in this topic?"
							title:@"Delete All Messages" action:@"Delete"
					  destructive:YES inView:self.view onConfirm:^{
			[[TGClient shared] deleteDirectMessagesChatTopicHistory:weakSelf.topicId
														  inChat:weakSelf.chatId
													  completion:^(BOOL ok,
																   NSString *error){
				[weakSelf finish:ok error:error title:@"Delete All Messages"];
			}];
		}];
	}
}

/// The two calls with no options of their own share one path, so a typing
/// mistake in a selector cannot send the other one's request.
- (void)runSimple:(NSString *)selector title:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	if ([selector isEqualToString:@"readAllDirectMessagesChatTopicReactions"]){
		[[TGClient shared] readAllDirectMessagesChatTopicReactions:self.topicId
														  inChat:self.chatId
													  completion:^(BOOL ok,
																   NSString *error){
			[weakSelf finish:ok error:error title:title];
		}];
		return;
	}
	[[TGClient shared] unpinAllDirectMessagesChatTopicMessages:self.topicId
													   inChat:self.chatId
												   completion:^(BOOL ok,
																NSString *error){
		[weakSelf finish:ok error:error title:title];
	}];
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	[TGAlertSheet showMessage:(ok ? @"Done." : (error ?: @"Telegram refused that."))
						title:title inView:self.view];
	[self loadTopic];
	[self loadHistory];
}

- (NSArray *)dateChoices {
	return @[@"Today", @"Yesterday", @"Last 7 Days", @"Last 30 Days"];
}

- (NSTimeInterval)startOfDay:(NSDate *)date {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
	NSDateComponents *parts = [calendar components:units fromDate:date];
	return [[calendar dateFromComponents:parts] timeIntervalSince1970];
}

- (void)jumpToDate {
	__weak typeof(self) weakSelf = self;
	NSArray *choices = [self dateChoices];
	[TGAlertSheet showChoices:choices title:@"Jump to Date"
			destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
		NSTimeInterval day = [weakSelf startOfDay:[NSDate date]];
		NSInteger date = (NSInteger)day;
		if (index == 1)
			date = (NSInteger)(day - 86400);
		else if (index == 2)
			date = (NSInteger)(now - 7 * 86400);
		else if (index == 3)
			date = (NSInteger)(now - 30 * 86400);
		[[TGClient shared] directMessagesChatTopicMessageByDate:weakSelf.topicId
													   inChat:weakSelf.chatId
														 date:date
												   completion:^(NSDictionary *message,
																NSString *error){
			TGDMTopicViewController *me = weakSelf;
			if (!me)
				return;
			if (error.length){
				[TGAlertSheet showMessage:error title:@"Jump to Date"
								   inView:me.view];
				return;
			}
			if (!message){
				[TGAlertSheet showMessage:@"No message on or before that date."
									title:@"Jump to Date" inView:me.view];
				return;
			}
			NSString *text = message[@"text"];
			[TGAlertSheet showMessage:(text.length ? text
					: [me describeMessage:message])
								title:@"Jump to Date" inView:me.view];
		}];
	}];
}

- (void)deleteByDate {
	__weak typeof(self) weakSelf = self;
	NSArray *choices = @[@"Last Hour", @"Last 24 Hours", @"Last 7 Days",
						 @"All Time"];
	[TGAlertSheet showChoices:choices title:@"Delete Messages by Date"
			destructiveIndex:3 inView:self.view onChoice:^(NSInteger index){
		NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
		NSTimeInterval minDate = 0;
		if (index == 0)
			minDate = now - 3600;
		else if (index == 1)
			minDate = now - 86400;
		else if (index == 2)
			minDate = now - 7 * 86400;
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"Delete messages from %@?", choices[index]]
							title:@"Delete Messages by Date" action:@"Delete"
					  destructive:YES inView:weakSelf.view onConfirm:^{
			[[TGClient shared] deleteDirectMessagesChatTopicMessages:weakSelf.topicId
															inChat:weakSelf.chatId
														   minDate:(NSInteger)minDate
														   maxDate:(NSInteger)now
														completion:^(BOOL ok,
																	 NSString *error){
				[weakSelf finish:ok error:error title:@"Delete Messages by Date"];
			}];
		}];
	}];
}

@end
