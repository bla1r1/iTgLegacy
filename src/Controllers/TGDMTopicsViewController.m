#import "TGDMTopicsViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGDMTopicViewController.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGDMTopicsViewController ()
@property (nonatomic, strong) NSArray *topics;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGDMTopicsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.chatTitle.length
			? [NSString stringWithFormat:@"%@ · Direct", self.chatTitle]
			: @"Direct Messages";
	self.topics = [[TGClient shared] directMessagesChatTopicsForChat:self.chatId]
			?: @[];
	self.tableView.rowHeight = TGMetricPersonRow;
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"More" style:UIBarButtonItemStylePlain
				   target:self action:@selector(loadMoreTapped)];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(topicsChanged:)
				name:TGDirectMessagesTopicsChangedNotification object:nil];
	[self loadMore];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.topics = [[TGClient shared] directMessagesChatTopicsForChat:self.chatId]
			?: @[];
	[self.tableView reloadData];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)topicsChanged:(NSNotification *)note {
	NSNumber *chatId = note.userInfo[@"chatId"];
	if (chatId && [chatId longLongValue] != self.chatId)
		return;
	self.topics = [[TGClient shared] directMessagesChatTopicsForChat:self.chatId]
			?: @[];
	[self.tableView reloadData];
}

- (void)loadMore {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] loadDirectMessagesChatTopicsInChat:self.chatId limit:20
											   completion:^(BOOL ok, NSString *error){
		TGDMTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.loaded = YES;
		me.topics = [[TGClient shared] directMessagesChatTopicsForChat:me.chatId]
				?: @[];
		[me.tableView reloadData];
		if (!ok && error.length)
			[TGAlertSheet showMessage:error title:@"Direct Messages"
							   inView:me.view];
	}];
}

- (void)loadMoreTapped {
	[self loadMore];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.topics.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.topics.count ? @"Topics" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (self.topics.count)
		return @"One topic per person writing to the channel. Only a channel "
			   @"that turned on direct messages, administered by this account, "
			   @"answers the list.";
	return (self.loaded
			? @"No topics yet. Telegram sends them through "
			  @"updateDirectMessagesChatTopic after loadDirectMessagesChatTopics."
			: @"Loading topics…");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"topic"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"topic"];
	[[TGTheme shared] styleCell:cell];
	NSDictionary *topic = self.topics[indexPath.row];
	NSString *name = topic[@"senderName"];
	cell.textLabel.text = name.length ? name : @"Topic";
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	NSDictionary *last = topic[@"lastMessage"];
	NSString *preview = [last isKindOfClass:NSDictionary.class]
			? last[@"text"] : nil;
	NSInteger unread = [topic[@"unread"] integerValue];
	NSString *detail = preview.length ? preview : @"No messages yet";
	if (unread > 0)
		detail = [NSString stringWithFormat:@"%ld new · %@", (long)unread, detail];
	else if ([topic[@"isMarkedUnread"] boolValue])
		detail = [NSString stringWithFormat:@"Unread · %@", detail];
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.topics.count)
		return;
	NSDictionary *topic = self.topics[indexPath.row];
	TGDMTopicViewController *detail = [[TGDMTopicViewController alloc] init];
	detail.chatId = self.chatId;
	detail.topicId = [topic[@"topicId"] longLongValue];
	detail.topic = topic;
	detail.chatTitle = self.chatTitle;
	detail.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:detail animated:YES];
}

@end
