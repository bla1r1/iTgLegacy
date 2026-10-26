#import "TGTopicsViewController.h"
#import "TGAlertSheet.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGTopicsViewController ()
@property (nonatomic, strong) NSArray *topics;
@end

@implementation TGTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = self.chatTitle ?: @"Topics";
	self.topics = @[];
	self.tableView.rowHeight = 56;
	[self applyTheme];

	// Making a topic is the one thing the list needs beyond its rows; the
	// plus sits where a mail folder's compose sits.
	__weak typeof(self) weakSelf = self;
	UIBarButtonItem *plus = [[UIBarButtonItem alloc] initWithTitle:@"+"
			style:UIBarButtonItemStylePlain
			target:self action:@selector(createTopicTapped)];
	self.navigationItem.rightBarButtonItem = plus;

	// A topic's lot holds in the row, and rows are not controls: the hold
	// reaches what a tap cannot.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(topicHeld:)];
	hold.minimumPressDuration = 0.55;
	[self.tableView addGestureRecognizer:hold];

	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.topics = topics;
		[me.tableView reloadData];
		NSLog(@"TDLIB TOPICS: %lu", (unsigned long)topics.count);
	}];

	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self reloadTopics];
}

- (void)reloadTopics {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.topics = topics;
		[me.tableView reloadData];
	}];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

/// A topic made: the name asked for, then one of TDLib's seven forum hues.
/// The general topic TDLib makes itself; this only makes named ones.
- (void)createTopicTapped {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"New Topic"
					message:nil
				placeholder:@"Topic name"
					   text:nil
					 action:@"Next"
					 inView:self.view
				   onSubmit:^(NSString *name){
		NSString *what = [name stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!what.length)
			return;
		[TGAlertSheet showChoices:@[@"Red", @"Orange", @"Violet", @"Green",
									@"Cyan", @"Blue", @"Pink"]
							title:@"Icon colour"
				 destructiveIndex:-1
						   inView:weakSelf.view
						 onChoice:^(NSInteger colour){
			[[TGClient shared] createForumTopicInChat:weakSelf.chatId
												 name:what
										   iconColour:colour
										   completion:^(int64_t threadId, NSString *made){
				if (!threadId){
					[TGAlertSheet showMessage:@"Only a forum supergroup holds "
											  @"topics, and only an "
											  @"administrator makes one."
										title:@"New Topic" inView:weakSelf.view];
					return;
				}
				[weakSelf reloadTopics];
			}];
		}];
	}];
}

/// The hold lands wherever the finger is, so the row is found from the
/// point; a miss does nothing rather than guessing the last row.
- (void)topicHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	CGPoint where = [hold locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:where];
	if (!path || path.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *t = self.topics[path.row];
	int64_t threadId = [t[@"threadId"] longLongValue];
	NSString *name = t[@"name"] ?: @"";
	if (!threadId)
		return;

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Rename", @"Pin", @"Close", @"Delete"]
						title:name
			 destructiveIndex:3
					   inView:self.view
					 onChoice:^(NSInteger index){
		void (^refresh)(void) = ^{
			[weakSelf reloadTopics];
		};
		if (index == 0)
			[weakSelf renameTopic:threadId name:name];
		else if (index == 1){
			[[TGClient shared] toggleForumTopic:threadId inChat:weakSelf.chatId pinned:YES];
			refresh();
		}
		else if (index == 2){
			[[TGClient shared] toggleForumTopic:threadId inChat:weakSelf.chatId closed:YES];
			refresh();
		}
		else
			[TGAlertSheet showConfirm:@"The topic and every message in it is "
									  @"removed, for everyone."
								title:name
							   action:@"Delete"
						  destructive:YES
							   inView:self.view
							onConfirm:^{
				[[TGClient shared] deleteForumTopic:threadId inChat:weakSelf.chatId];
				refresh();
			}];
	}];
}

/// The rename asked for; the sheet is where a topic gets the words.
- (void)renameTopic:(int64_t)threadId name:(NSString *)old {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Rename Topic"
					message:nil
				placeholder:old ?: @"Topic name"
					   text:old
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *name){
		NSString *what = [name stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!what.length)
			return;
		[[TGClient shared] renameForumTopic:threadId
									 inChat:weakSelf.chatId
									   name:what
							   iconEmojiId:0
								completion:^(BOOL ok){
			TGTopicsViewController *me = weakSelf;
			if (ok)
				[me reloadTopics];
			else
				[TGAlertSheet showMessage:@"Telegram refused the rename. Only "
										  @"an administrator or the topic's "
										  @"maker renames one."
									title:@"Rename" inView:me.view];
		}];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGTopicCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.contentView.backgroundColor = [theme listBackgroundColour];

	NSDictionary *t = self.topics[indexPath.row];
	NSInteger unread = [t[@"unread"] integerValue];

	cell.textLabel.text = unread > 0
		? [NSString stringWithFormat:@"%@  (%ld)", t[@"name"], (long)unread]
		: t[@"name"];
	cell.textLabel.font = TGFontRowStrong();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.backgroundColor = [theme listBackgroundColour];

	cell.detailTextLabel.text = t[@"text"];
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.backgroundColor = [theme listBackgroundColour];

	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	if (theme.isDark) {
		UIView *selected = [[UIView alloc] init];
		selected.backgroundColor = [theme bubbleTheirsColour];
		cell.selectedBackgroundView = selected;
	} else {
		cell.selectedBackgroundView = nil;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *t = self.topics[indexPath.row];
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = self.chatId;
	vc.threadId = [t[@"threadId"] longLongValue];
	vc.chatTitle = t[@"name"];
	vc.isGroup = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

@end

// vim:ft=objc
