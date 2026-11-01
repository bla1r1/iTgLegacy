#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGAlertSheet.h"
#import "TGQRViewController.h"
#import "TGWebsitesViewController.h"

@interface TGSessionsViewController ()
@property (nonatomic, strong) NSArray *sessions;
/// Days a session may sit idle before Telegram signs it out, from the same
/// getActiveSessions answer that filled `sessions`.
@property (nonatomic, assign) NSInteger inactiveTtl;
@property (nonatomic, assign) BOOL ttlLoaded;
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
	[[TGClient shared] sessionsWithInactiveTtlCompletion:^(NSArray *sessions, NSInteger ttlDays){
		weakSelf.sessions = sessions;
		weakSelf.inactiveTtl = ttlDays;
		weakSelf.ttlLoaded = YES;
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
	// Fixed sections, the way their page reads: this device, the others,
	// the two settings that apply to every session, and the sign-out. An
	// account with no other sessions keeps the section and says so, rather
	// than dropping it and leaving nothing where the explanation belongs.
	return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section){
		case 0: return @"CURRENT SESSION";
		case 1: return @"ACTIVE SESSIONS";
		case 2: return @"SESSION SETTINGS";
		case 3: return @"CONNECTED WEBSITES";
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	switch (section){
		case 0:
			return @"This device is the one you are using. A session's secret "
				   @"chats and calls are settings about it, not about this account.";
		case 1:
			return [self othersOnly].count
					? @"Tap a session to change whether it accepts calls or secret "
					  @"chats, or to sign it out."
					: @"You can log in on other phones, tablets and computers with "
					  @"this phone number. Everything stays in sync.";
		case 2:
			return @"A session idle for this long is signed out automatically. "
				   @"The choice applies to every device, including this one. "
				   @"Scan QR Code opens the t.me link the camera finds.";
		case 3:
			return @"Sites that signed in through a bot. Each one can be signed out "
				   @"on its own, or all at once.";
		default:
			return @"Signs out every device but this one, including any this list "
				   @"has not shown yet.";
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 1)
		return MAX((NSInteger)[self othersOnly].count, (NSInteger)1);
	if (section == 2)
		return 2;   // timeout, QR scanner
	return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;

	if (indexPath.section == 2){
		if (indexPath.row == 1){
			cell.textLabel.text = @"Scan QR Code";
			cell.detailTextLabel.text = @"Open a t.me link with the camera";
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			return cell;
		}
		NSString *detail = self.ttlLoaded
				? [NSString stringWithFormat:@"%ld days", (long)self.inactiveTtl]
				: @"...";
		cell.textLabel.text = @"Inactive Session Timeout";
		cell.detailTextLabel.text = detail;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == 3){
		cell.textLabel.text = @"Connected Websites";
		cell.detailTextLabel.text = @"Sites signed in through a bot";
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == 4){
		cell.textLabel.text = @"Terminate All Other Sessions";
		cell.textLabel.textColor = [[TGTheme shared] destructiveColour];
		cell.detailTextLabel.text = nil;
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == 1 && ![self othersOnly].count){
		cell.textLabel.text = @"No other sessions";
		cell.detailTextLabel.text = @"Only this device is signed in";
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSDictionary *session = indexPath.section == 0
			? [self currentSession] : [self othersOnly][indexPath.row];
	if (!session){
		cell.textLabel.text = @"Reading sessions...";
		cell.detailTextLabel.text = nil;
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	cell.textLabel.text = session[@"name"];
	NSMutableArray *parts = [NSMutableArray array];
	if ([session[@"platform"] length])
		[parts addObject:session[@"platform"]];
	if ([session[@"ip"] length])
		[parts addObject:session[@"ip"]];
	if (indexPath.section == 0)
		[parts addObject:@"This device"];
	if ([session[@"isUnconfirmed"] boolValue])
		[parts addObject:@"confirmation needed"];
	cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
	// This device's own row opens the same switches, because a phone that
	// should not ring is a setting about the session, not about the others.
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 2 && indexPath.row == 1){
		TGQRViewController *scanner = [[TGQRViewController alloc] init];
		scanner.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:scanner animated:YES];
		return;
	}

	if (indexPath.section == 2){
		// 1-366 days is TDLib's own range. The presets are the spans their
		// page offers; anything finer would be a number nobody means.
		NSArray *titles = @[@"1 week", @"1 month", @"3 months", @"6 months", @"1 year"];
		NSArray *days = @[@7, @30, @90, @180, @365];
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:titles
							title:@"Inactive Session Timeout"
						  message:@"How long a device may sit idle before Telegram "
								  @"signs it out."
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			[[TGClient shared] setInactiveSessionTtlDays:[days[(NSUInteger)index] integerValue]
											 completion:^(BOOL ok, NSString *error){
				if (!ok){
					[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
										title:@"Inactive Session Timeout"
									   inView:weakSelf.view];
					return;
				}
				[weakSelf performSelector:@selector(refresh)
							   withObject:nil afterDelay:0.5];
			}];
		}];
		return;
	}

	if (indexPath.section == 3){
		TGWebsitesViewController *sites = [[TGWebsitesViewController alloc] init];
		sites.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:sites animated:YES];
		return;
	}

	if (indexPath.section == 4){
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

	if (indexPath.section != 0 && indexPath.section != 1)
		return;
	BOOL isCurrent = indexPath.section == 0;
	if (!isCurrent && ![self othersOnly].count)
		return;

	NSDictionary *session = isCurrent
			? [self currentSession] : [self othersOnly][indexPath.row];
	if (!session)
		return;
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

	// A session's three switches are worth reaching from its row: a device that
	// should not accept secret chats or ring can be told so without signing it
	// out, and a login Telegram has not seen confirmed gets its Confirm beside
	// them.
	BOOL canAccept = [session[@"canAcceptSecretChats"] boolValue];
	NSString *secretTitle = canAccept ? @"Stop Accepting Secret Chats"
									  : @"Accept Secret Chats";
	BOOL canAcceptCalls = [session[@"canAcceptCalls"] boolValue];
	NSString *callsTitle = canAcceptCalls ? @"Stop Accepting Calls"
										  : @"Allow Accepting Calls";
	NSMutableArray *choices = [NSMutableArray array];
	if ([session[@"isUnconfirmed"] boolValue])
		[choices addObject:@"Confirm This Device"];
	[choices addObject:secretTitle];
	[choices addObject:callsTitle];
	if (!isCurrent)
		[choices addObject:@"Sign Out"];

	[TGAlertSheet showChoices:choices
						title:session[@"name"]
			 destructiveIndex:isCurrent ? -1 : (NSInteger)choices.count - 1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *choice = choices[(NSUInteger)index];
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
		if ([choice isEqualToString:callsTitle]){
			[[TGClient shared] toggleSession:sessionId
							   canAcceptCalls:!canAcceptCalls
								   completion:^(BOOL ok, NSString *error){
				if (!ok){
					[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
										title:session[@"name"]
									   inView:weakSelf.view];
					return;
				}
				[weakSelf performSelector:@selector(refresh)
							   withObject:nil afterDelay:0.5];
			}];
			return;
		}
		signOut();
	}];
}

@end

// vim:ft=objc
