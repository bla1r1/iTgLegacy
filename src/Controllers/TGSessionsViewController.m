#import "TGSessionsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGAlertSheet.h"
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
	// The timeout row and the connected-websites row belong to every account;
	// the sign-out-everything section appears only when there is more than
	// this device to sign out.
	return [self othersOnly].count ? 5 : 4;
}

/// The section indices follow whether there is an "Active sessions" block;
/// one helper keeps the five table callbacks agreeing on that.
- (NSInteger)settingsSection {
	return [self othersOnly].count ? 2 : 1;
}

- (NSInteger)websitesSection {
	return [self othersOnly].count ? 3 : 2;
}

- (NSInteger)terminateSection {
	return [self othersOnly].count ? 4 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"This device";
	if ([self othersOnly].count && section == 1) return @"Active sessions";
	if (section == [self settingsSection]) return @"Session settings";
	if (section == [self websitesSection]) return @"Websites";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if ([self othersOnly].count && section == 1)
		return @"Tap a session to change whether it rings or sign it out.";
	if (section == [self settingsSection])
		return @"A session idle for this long is signed out automatically. "
			   @"The choice applies to every device, including this one.";
	if (section == [self websitesSection])
		return @"Sites that signed in through a bot. Each one can be signed out "
			   @"on its own, or all at once.";
	if (section == [self terminateSection])
		return @"Signs out every device but this one, including any this list "
			   @"has not shown yet.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return [self currentSession] ? 1 : 0;
	if ([self othersOnly].count && section == 1) return [self othersOnly].count;
	if (section == [self settingsSection]) return 1;
	if (section == [self websitesSection]) return 1;
	return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];

	if (indexPath.section == [self settingsSection]){
		NSString *detail = self.ttlLoaded
				? [NSString stringWithFormat:@"%ld days", (long)self.inactiveTtl]
				: @"...";
		cell.textLabel.text = @"Inactive Session Timeout";
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.textLabel.textAlignment = NSTextAlignmentLeft;
		cell.detailTextLabel.text = detail;
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == [self websitesSection]){
		cell.textLabel.text = @"Connected Websites";
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.textLabel.textAlignment = NSTextAlignmentLeft;
		cell.detailTextLabel.text = @"Sites signed in through a bot";
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (indexPath.section == [self terminateSection]){
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
	cell.detailTextLabel.text = [session[@"isUnconfirmed"] boolValue]
			? [NSString stringWithFormat:@"%@ - %@ · confirmation needed",
					session[@"platform"], session[@"ip"]]
			: [NSString stringWithFormat:@"%@ - %@",
					session[@"platform"], session[@"ip"]];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	// This device's own row opens the same two switches, because a phone that
	// should not ring is a setting about the session, not about the others.
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == [self settingsSection]){
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

	if (indexPath.section == [self websitesSection]){
		TGWebsitesViewController *sites = [[TGWebsitesViewController alloc] init];
		sites.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:sites animated:YES];
		return;
	}

	if (indexPath.section == [self terminateSection]){
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
