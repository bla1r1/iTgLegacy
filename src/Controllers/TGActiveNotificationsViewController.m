#import "TGActiveNotificationsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// One date format for every row; creating one per cell was the usual
/// reason a notification list scrolls badly on an A5.
static NSString *TGNotificationDateText(NSNumber *timestamp) {
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	}
	return [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[timestamp doubleValue]]];
}

@implementation TGActiveNotificationsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"Active Notifications";
	[self applyTheme];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Clear All" style:UIBarButtonItemStylePlain
				   target:self action:@selector(clearAll)];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter]
			addObserverForName:TGActiveNotificationsChangedNotification
						object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf reloadList];
	}];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
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
	[self reloadList];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (NSArray *)groups {
	return [TGClient shared].activeNotificationGroups ?: @[];
}

- (BOOL)pending {
	return [TGClient shared].havePendingNotifications;
}

- (void)reloadList {
	self.navigationItem.rightBarButtonItem.enabled = self.groups.count > 0;
	[self.tableView reloadData];
}

/// Section 0 is the pending banner when one is due; the group sections follow.
- (NSInteger)groupIndexForSection:(NSInteger)section {
	return self.pending ? section - 1 : section;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (self.pending)
		return (NSInteger)self.groups.count + 1;
	return MAX((NSInteger)1, (NSInteger)self.groups.count);
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
	if (self.pending && section == 0)
		return 1;
	NSInteger index = [self groupIndexForSection:section];
	if (index < 0 || index >= (NSInteger)self.groups.count)
		return 1;   // the empty state
	NSArray *notifications = self.groups[(NSUInteger)index][@"notifications"];
	return MAX((NSInteger)1, (NSInteger)notifications.count);
}

- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section {
	if (self.pending && section == 0)
		return nil;
	NSInteger index = [self groupIndexForSection:section];
	if (index < 0 || index >= (NSInteger)self.groups.count)
		return nil;
	NSDictionary *group = self.groups[(NSUInteger)index];
	NSString *title = [[TGClient shared] titleForChat:
			[group[@"chatId"] longLongValue]] ?: @"Notifications";
	return [NSString stringWithFormat:@"%@ · %@ · %@",
			title, group[@"type"] ?: @"Messages", group[@"totalCount"] ?: @(0)];
}

- (NSString *)tableView:(UITableView *)tableView
titleForFooterInSection:(NSInteger)section {
	if (self.pending && section == 0)
		return @"TDLib still has delayed or unreceived notifications.";
	if (section != (NSInteger)[self numberOfSectionsInTableView:tableView] - 1)
		return nil;
	if (!self.groups.count)
		return @"Nothing arrived while the app was in the background.";
	return @"Removing a row here removes it on this device only. "
		   @"The conversation stays in its chat.";
}

- (UITableViewCell *)pendingCellForTableView:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"pending"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"pending"];
		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		[spinner startAnimating];
		cell.accessoryView = spinner;
	}
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = @"Updating notifications...";
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)emptyCellForTableView:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"empty"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"empty"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = @"No active notifications";
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.pending && indexPath.section == 0)
		return [self pendingCellForTableView:tableView];
	NSInteger index = [self groupIndexForSection:indexPath.section];
	if (index < 0 || index >= (NSInteger)self.groups.count)
		return [self emptyCellForTableView:tableView];
	NSDictionary *group = self.groups[(NSUInteger)index];
	NSArray *notifications = group[@"notifications"];
	if (indexPath.row >= (NSInteger)notifications.count)
		return [self emptyCellForTableView:tableView];

	NSDictionary *row = notifications[(NSUInteger)indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = row[@"text"] ?: @"Notification";
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@%@",
			row[@"kind"] ?: @"Notification",
			TGNotificationDateText(row[@"date"]),
			[row[@"silent"] boolValue] ? @" · silent" : @""];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.pending && indexPath.section == 0)
		return;
	NSInteger index = [self groupIndexForSection:indexPath.section];
	if (index < 0 || index >= (NSInteger)self.groups.count)
		return;
	NSDictionary *group = self.groups[(NSUInteger)index];
	NSArray *notifications = group[@"notifications"];
	if (indexPath.row >= (NSInteger)notifications.count)
		return;
	NSDictionary *row = notifications[(NSUInteger)indexPath.row];
	int32_t groupId = (int32_t)[group[@"id"] intValue];
	int32_t notificationId = (int32_t)[row[@"id"] intValue];
	__weak typeof(self) weakSelf = self;

	[TGAlertSheet showChoices:@[@"Remove Notification"]
						title:row[@"text"] ?: @"Notification"
			 destructiveIndex:0
					   inView:self.view
					 onChoice:^(NSInteger choice){
		[[TGClient shared] removeNotification:notificationId inGroup:groupId
								   completion:^(BOOL ok, NSString *error){
			if (!ok)
				[TGAlertSheet showMessage:(error ?: @"Telegram refused to remove that notification.")
									title:@"Active Notifications"
								   inView:weakSelf.view];
			[weakSelf reloadList];
		}];
	}];
}

- (void)clearAll {
	if (!self.groups.count)
		return;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every active notification is removed from this "
							  @"device. The messages stay in their chats."
						title:@"Clear All Notifications"
					   action:@"Clear"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		NSArray *groups = weakSelf.groups;
		for (NSDictionary *group in groups){
			int32_t maxId = 0;
			for (NSDictionary *row in group[@"notifications"])
				maxId = MAX(maxId, (int32_t)[row[@"id"] intValue]);
			[[TGClient shared] removeNotificationGroup:(int32_t)[group[@"id"] intValue]
									  maxNotificationId:maxId
											 completion:^(BOOL ok, NSString *error){
				(void)error;
				[weakSelf reloadList];
			}];
		}
	}];
}

@end
