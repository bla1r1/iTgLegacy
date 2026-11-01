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
	// A new login waiting to be confirmed arrives as updateUnconfirmedSession
	// while this list is open; re-reading is how the row gets its Confirm.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGSessionsChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf refresh];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
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
	cell.detailTextLabel.text = [session[@"isUnconfirmed"] boolValue]
			? [NSString stringWithFormat:@"%@ - %@ · confirmation needed",
					session[@"platform"], session[@"ip"]]
			: [NSString stringWithFormat:@"%@ - %@",
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
	void (^signOut)(void) = ^{
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"Sign %@ out of this account?", session[@"name"]]
							title:@"Sign out"
						   action:@"Sign out"
					  destructive:YES
						   inView:weakSelf.view
						onConfirm:^{
			[[TGClient shared] terminateSession:sessionId];
			// The server needs a moment before the list reflects it.
			[weakSelf performSelector:@selector(refresh) withObject:nil afterDelay:1.0];
		}];
	};

	// A session's two switches are worth reaching from its row: a device that
	// should not accept secret chats can be told so without signing it out,
	// and a login Telegram has not seen confirmed gets its Confirm beside them.
	BOOL canAccept = [session[@"canAcceptSecretChats"] boolValue];
	NSString *secretTitle = canAccept ? @"Stop Accepting Secret Chats"
									  : @"Accept Secret Chats";
	NSMutableArray *choices = [NSMutableArray array];
	if ([session[@"isUnconfirmed"] boolValue])
		[choices addObject:@"Confirm This Device"];
	[choices addObject:secretTitle];
	[choices addObject:@"Sign Out"];

	[TGAlertSheet showChoices:choices
						title:session[@"name"]
			 destructiveIndex:(NSInteger)choices.count - 1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *choice = choices[index];
		if ([choice isEqualToString:@"Confirm This Device"]){
			[[TGClient shared] confirmSession:sessionId];
			[weakSelf performSelector:@selector(refresh) withObject:nil afterDelay:1.0];
			return;
		}
		if ([choice isEqualToString:secretTitle]){
			[[TGClient shared] toggleSession:sessionId canAcceptSecretChats:!canAccept];
			[weakSelf performSelector:@selector(refresh) withObject:nil afterDelay:0.5];
			return;
		}
		signOut();
	}];
}

@end

// vim:ft=objc
