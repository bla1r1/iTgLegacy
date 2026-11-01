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
	NSMutableArray *items = [@[pinned ? @"Unpin" : @"Pin"] mutableCopy];
	[items addObjectsFromArray:@[@"Clear Before Today", @"Clear Before Week",
								 @"Clear Before Month"]];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:items
						title:name
			 destructiveIndex:(pinned ? -1 : (NSInteger)items.count - 1)
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0){
			[[TGClient shared] toggleSavedTopicPinned:topicId pinned:!pinned];
			[weakSelf reloadRows];
			return;
		}
		// Clearing "before when" is a whole date range - days ago - and
		// every deletion keeps what came after it.
		NSString *which = items[index];
		NSString *say = [NSString stringWithFormat:
				@"Everything in %@ before that is deleted, on every device.",
				(name.length ? name : @"this topic")];
		[TGAlertSheet showConfirm:say
							title:@"Clear Saved Messages"
						   action:which
					  destructive:YES
						   inView:weakSelf.view
						onConfirm:^{
			NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
			// From the start of the boundary day: "before today" keeps today.
			NSInteger days = index == 1 ? 1 : (index == 2 ? 7 : 30);
			NSString *which = items[index];
			[[TGClient shared] clearSavedTopicMessagesBefore:topicId
													minDate:(NSInteger)(now - days * 86400)
													maxDate:(NSInteger)now];
			[weakSelf reloadRows];
		}];
	}];
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
