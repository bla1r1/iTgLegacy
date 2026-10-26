#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGAlertSheet.h"

@interface TGSessionsViewController ()
@property (nonatomic, strong) NSArray *sessions;
@end

@implementation TGSessionsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Devices";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	[self refresh];

	__weak typeof(self) weakSelf = self;
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

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

- (void)refresh {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sessionsWithCompletion:^(NSArray *sessions){
		weakSelf.sessions = sessions;
		[weakSelf.tableView reloadData];
	}];
}

/// Current session first, the way every client orders this list.
- (NSArray *)othersOnly {
	NSMutableArray *others = [NSMutableArray array];
	for (NSDictionary *session in self.sessions)
		if (![session[@"isCurrent"] boolValue])
			[others addObject:session];
	return others;
}

- (NSDictionary *)currentSession {
	for (NSDictionary *session in self.sessions)
		if ([session[@"isCurrent"] boolValue])
			return session;
	return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// A third section only when there is more than this device to sign out.
	return [self othersOnly].count ? 3 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"This device";
	if (section == 1) return [self othersOnly].count ? @"Active sessions" : nil;
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1 && [self othersOnly].count)
		return @"Tap a session to sign that device out.";
	if (section == 2)
		return @"Signs out every device but this one, including any this list "
			   @"has not shown yet.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return [self currentSession] ? 1 : 0;
	if (section == 1) return [self othersOnly].count;
	return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];

	if (indexPath.section == 2){
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.text = @"Terminate All Other Sessions";
		cell.textLabel.textColor = [[TGTheme shared] destructiveColour];
		cell.detailTextLabel.text = nil;
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}
	cell.textLabel.textAlignment = NSTextAlignmentLeft;

	NSDictionary *session = indexPath.section == 0
			? [self currentSession] : [self othersOnly][indexPath.row];
	cell.textLabel.text = session[@"name"];
	[[TGTheme shared] styleCell:cell];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
			session[@"platform"], session[@"ip"]];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = indexPath.section == 0
			? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 2){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"Every device but this one is signed out, "
								  @"including any this list has not shown yet."
							title:@"Terminate All Other Sessions"
						   action:@"Terminate"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
			[[TGClient shared] terminateAllOtherSessions:^(BOOL ok){
				TGSessionsViewController *me = weakSelf;
				if (!ok){
					[TGAlertSheet showMessage:@"Telegram refused that."
										title:@"Active Sessions" inView:me.view];
					return;
				}
				// The server needs a moment before the list reflects it.
				[me performSelector:@selector(refresh) withObject:nil afterDelay:1.0];
			}];
		}];
		return;
	}

	if (indexPath.section != 1)
		return;

	NSDictionary *session = [self othersOnly][indexPath.row];
	int64_t sessionId = [session[@"id"] longLongValue];
	if (!sessionId)
		return;

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"Sign %@ out of this account?", session[@"name"]]
						title:@"Sign out"
					   action:@"Sign out"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] terminateSession:sessionId];
		// The server needs a moment before the list reflects it.
		[weakSelf performSelector:@selector(refresh) withObject:nil afterDelay:1.0];
	}];
}

@end

// vim:ft=objc
