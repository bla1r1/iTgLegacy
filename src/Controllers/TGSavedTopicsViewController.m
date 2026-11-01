//
// TGSavedTopicsViewController.m - the Saved Messages topics list.
//
// TDLib answers loadSavedMessagesTopics with an ok and topic rows ride
// updateSavedMessagesTopic one per touched row; the client keeps them, this
// screen reads that array. A row's id is a message thread id, so a tap
// opens the Saved chat at the topic the same way forum topics open.
#import "TGSavedTopicsViewController.h"
#import "TGAlertSheet.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#import "TGTheme.h"
#import "TGStyle.h"

@implementation TGSavedTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Saved Topics";
	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];

	// A topic's lot holds in the row, and rows are not controls: the hold
	// reaches what a tap cannot.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(topicHeld:)];
	hold.minimumPressDuration = 0.55;
	[self.tableView addGestureRecognizer:hold];

	// Topic rows stream from TDLib through the update the client keeps;
	// loading once is what starts the stream, an update is what continues it.
	[[TGClient shared] loadSavedMessagesTopics];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(topicsChanged:)
				name:TGSavedTopicsChangedNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserverForName:
			TGThemeChangedNotification object:nil
			queue:[NSOperationQueue mainQueue]
		   usingBlock:^(NSNotification *note){
		__weak typeof(self) weakSelf = self;
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)topicsChanged:(NSNotification *)note {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(reloadRows) object:nil];
	[self performSelector:@selector(reloadRows) withObject:nil afterDelay:0.3];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[[TGClient shared] loadSavedMessagesTopics];
	[self reloadRows];
}

- (void)reloadRows {
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf.tableView reloadData];
	});
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (NSArray *)topics {
	return [TGClient shared].savedTopics;
}

/// The hold lands wherever the finger is, so the row is found from the
/// point; a miss does nothing.
- (void)topicHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	CGPoint where = [hold locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:where];
	if (!path || path.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *t = self.topics[path.row];
	int64_t topicId = [t[@"id"] longLongValue];
	NSString *name = t[@"title"] ?: @"";
	if (!topicId)
		return;

	BOOL pinned = [t[@"pinned"] boolValue];
	NSMutableArray *items = [@[pinned ? @"Unpin" : @"Pin", @"Jump to Date",
							   @"Tags...", @"Unpin All"] mutableCopy];
	[items addObjectsFromArray:@[@"Clear Before Today", @"Clear Before Week",
								 @"Clear Before Month", @"Clear Everything"]];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:items
						title:name
			 destructiveIndex:(NSInteger)[items indexOfObject:@"Clear Everything"]
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *what = items[(NSUInteger)index];
		if ([what isEqualToString:@"Pin"] || [what isEqualToString:@"Unpin"]){
			[[TGClient shared] toggleSavedTopicPinned:topicId pinned:!pinned];
			[weakSelf reloadRows];
			return;
		}
		if ([what isEqualToString:@"Jump to Date"]){
			[weakSelf jumpToDateInTopic:topicId named:name];
			return;
		}
		if ([what isEqualToString:@"Tags..."]){
			[weakSelf showTagsOfTopic:topicId named:name];
			return;
		}
		if ([what isEqualToString:@"Unpin All"]){
			// One request takes the whole list down at once; toggling each
			// row would leave a half-pinned list if the screen closed.
			[TGAlertSheet showConfirm:@"Every topic leaves the top of the list."
								title:@"Unpin All"
							   action:@"Unpin"
						  destructive:NO
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] setPinnedSavedTopics:@[]];
				[weakSelf reloadRows];
			}];
			return;
		}
		// Clearing "before when" is a whole date range - days ago - and
		// every deletion keeps what came after it.
		if ([what isEqualToString:@"Clear Everything"]){
			[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"Every message in %@ is deleted, on every device. The topic "
					@"itself stays.",
					(name.length ? name : @"this topic")]
								title:@"Clear Everything"
							   action:@"Clear"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] deleteSavedTopicHistory:topicId];
				[weakSelf reloadRows];
			}];
			return;
		}
		NSString *say = [NSString stringWithFormat:
				@"Everything in %@ before that is deleted, on every device.",
				(name.length ? name : @"this topic")];
		[TGAlertSheet showConfirm:say
							title:@"Clear Saved Messages"
						   action:what
					  destructive:YES
						   inView:weakSelf.view
						onConfirm:^{
			NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
			// From the start of the boundary day: "before today" keeps today.
			NSInteger days = [what isEqualToString:@"Clear Before Today"] ? 1
					: ([what isEqualToString:@"Clear Before Week"] ? 7 : 30);
			[[TGClient shared] clearSavedTopicMessagesBefore:topicId
													minDate:(NSInteger)(now - days * 86400)
													maxDate:(NSInteger)now];
			[weakSelf reloadRows];
		}];
	}];
}

/// The topic's own jump: getSavedMessagesTopicMessageByDate answers the last
/// message on or before a day, which is what the chat's date picker looks up
/// for an ordinary chat.
- (void)jumpToDateInTopic:(int64_t)topicId named:(NSString *)name {
	NSArray *days = @[@"Today", @"A Week Ago", @"A Month Ago", @"A Year Ago"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:days
						title:(name.length ? name : @"Topic")
					  message:@"The last message saved on or before that day."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSInteger ago = index == 0 ? 0 : (index == 1 ? 7 : (index == 2 ? 30 : 365));
		NSInteger when = (NSInteger)[[NSDate date] timeIntervalSince1970]
				- ago * 86400;
		[[TGClient shared] savedTopicMessageAtDate:topicId
											 date:when
									   completion:^(NSDictionary *message){
			TGSavedTopicsViewController *me = weakSelf;
			if (!me)
				return;
			int64_t messageId = [message[@"id"] longLongValue];
			if (!messageId){
				[TGAlertSheet showMessage:@"Nothing was saved on or before "
										  @"that day."
									  title:(name.length ? name : @"Topic")
									 inView:me.view];
				return;
			}
			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = [TGClient shared].savedMessagesChatId;
			vc.threadId = topicId;
			vc.chatTitle = name.length ? name : @"Saved";
			vc.isGroup = NO;
			vc.initialMessageId = messageId;
			[me.navigationController pushViewController:vc animated:YES];
		}];
	}];
}

/// A topic's tags: the emoji is the tag and the label is what this account
/// wrote over it. setSavedMessagesTagLabel is how a label is changed, and it
/// is the only writable half.
- (void)showTagsOfTopic:(int64_t)topicId named:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] savedTopicsTags:topicId completion:^(NSArray *tags){
		TGSavedTopicsViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *list = [tags isKindOfClass:NSArray.class] ? tags : @[];
		if (!list.count){
			[TGAlertSheet showMessage:@"Nothing in here is tagged yet."
								  title:(name.length ? name : @"Topic")
								 inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *tag in list){
			NSString *label = [me labelForSavedTag:tag];
			[rows addObject:[NSString stringWithFormat:@"%@  ×%@", label,
							 tag[@"count"] ?: @(0)]];
		}
		[TGAlertSheet showChoices:rows
							title:(name.length ? name : @"Topic")
						  message:@"Pick a tag to give it a label of its own."
				   destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			NSDictionary *tag = list[(NSUInteger)index];
			[TGAlertSheet showInput:@"Tag Label"
							message:nil
						placeholder:[me labelForSavedTag:tag]
							   text:tag[@"label"]
							 action:@"Save"
							 inView:me.view
						 onSubmit:^(NSString *typed){
				[[TGClient shared] labelSavedTag:tag label:typed];
			}];
		}];
	}];
}

- (NSString *)labelForSavedTag:(NSDictionary *)tag {
	NSString *label = tag[@"label"];
	if (label.length)
		return label;
	NSString *emoji = tag[@"tag"][@"emoji"];
	return emoji.length ? emoji : @"Tag";
}

#pragma mark - the table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSavedTopicCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.contentView.backgroundColor = [theme listBackgroundColour];

	NSDictionary *t = self.topics[indexPath.row];
	NSString *name = [t[@"pinned"] boolValue]
			? [NSString stringWithFormat:@"📌 %@", t[@"title"]]
			: t[@"title"];
	cell.textLabel.text = name;
	cell.textLabel.font = TGFontRowStrong();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.backgroundColor = [theme listBackgroundColour];

	cell.detailTextLabel.text = t[@"text"];
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.backgroundColor = [theme listBackgroundColour];

	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *t = self.topics[indexPath.row];
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = [TGClient shared].savedMessagesChatId;
	vc.threadId = [t[@"id"] longLongValue];
	vc.chatTitle = t[@"title"] ?: @"Saved";
	vc.isGroup = NO;
	[self.navigationController pushViewController:vc animated:YES];
}

@end
