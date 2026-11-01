//
// TGUsernameSettingsViewController.m - the account's usernames.
//
// Telegram now keeps more than one username on an account: one editable name
// and any number of collectible ones, each switched on or off and ordered.
// The Edit Profile row used to show the first of them as a string with nothing
// to do about the rest. This is the screen behind that row.
//
#import "TGUsernameSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// A switch that remembers which username it changes. The row is rebuilt on
/// every reload, so an index would point at whatever moved into its place.
@interface TGUsernameSwitch : UISwitch
@property (nonatomic, copy) NSString *username;
@end

@implementation TGUsernameSwitch
@end

@interface TGUsernameSettingsViewController ()
@property (nonatomic, strong) NSDictionary *usernames;
@property (nonatomic, strong) NSMutableArray *active;
@property (nonatomic, strong) NSMutableArray *disabled;
@property (nonatomic, copy) NSString *editable;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGUsernameSettingsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Usernames";
	self.active = [NSMutableArray array];
	self.disabled = [NSMutableArray array];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	[self load];

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

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self load];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)load {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] accountUsernamesWithCompletion:^(NSDictionary *usernames){
		TGUsernameSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.usernames = usernames;
		me.active = [usernames[@"active_usernames"] isKindOfClass:NSArray.class]
				? [usernames[@"active_usernames"] mutableCopy] : [NSMutableArray array];
		me.disabled = [usernames[@"disabled_usernames"] isKindOfClass:NSArray.class]
				? [usernames[@"disabled_usernames"] mutableCopy] : [NSMutableArray array];
		me.editable = usernames[@"editable_username"] ?: @"";
		[me updateEditButton];
		[me.tableView reloadData];
	}];
}

- (void)updateEditButton {
	BOOL canOrder = self.active.count > 1;
	self.navigationItem.rightBarButtonItem = canOrder
			? [[UIBarButtonItem alloc] initWithTitle:(self.tableView.editing ? @"Done" : @"Edit")
											  style:UIBarButtonItemStylePlain
											 target:self action:@selector(toggleEditing)]
			: nil;
}

- (void)toggleEditing {
	[self.tableView setEditing:!self.tableView.editing animated:YES];
	[self updateEditButton];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 1) return @"Active usernames";
	if (section == 2) return @"Disabled usernames";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"This is the username Telegram shows first. The names below are "
			   @"kept on the account and can be switched back on.";
	if (section == 1 && self.active.count > 1)
		return @"Tap Edit and drag a row to change the order on your profile.";
	if (section == 2 && !self.disabled.count)
		return @"Every other username is switched on.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return self.editable.length ? 2 : 1;
	if (section == 1)
		return self.active.count;
	return self.disabled.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	TGTheme *theme = [TGTheme shared];
	if (path.section == 0){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.detailTextLabel.font = TGFontBody();
		cell.detailTextLabel.textColor = [theme cellDetailColour];
		if (path.row == 0){
			cell.textLabel.text = @"Username";
			cell.detailTextLabel.text = self.editable.length
					? [@"@" stringByAppendingString:self.editable] : @"None";
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
			cell.textLabel.text = @"Remove Username";
			cell.textLabel.textColor = [theme destructiveColour];
			cell.textLabel.textAlignment = NSTextAlignmentCenter;
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		return cell;
	}

	BOOL isActive = path.section == 1;
	NSString *username = isActive ? self.active[(NSUInteger)path.row]
								 : self.disabled[(NSUInteger)path.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"username"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"username"];
	[theme styleCell:cell];
	cell.textLabel.text = [@"@" stringByAppendingString:username];
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.text = isActive
			? ([username isEqualToString:self.editable] ? @"Primary" : @"Active")
			: @"Disabled";
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.showsReorderControl = isActive;

	TGUsernameSwitch *toggle = [[TGUsernameSwitch alloc] init];
	toggle.username = username;
	toggle.on = isActive;
	// The editable name cannot be switched off; Telegram refuses it and the
	// switch says so before the request is sent.
	toggle.enabled = !(isActive && [username isEqualToString:self.editable]) && !self.busy;
	[toggle addTarget:self action:@selector(usernameSwitchChanged:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
	// Editing here is ordering only: a username is removed by switching it
	// off or by changing the editable name, not by deleting a row.
	return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path {
	return path.section == 1 && self.active.count > 1;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)from
			  toIndexPath:(NSIndexPath *)to
{
	NSArray *before = [self.active copy];
	NSString *name = self.active[(NSUInteger)from.row];
	[self.active removeObjectAtIndex:(NSUInteger)from.row];
	[self.active insertObject:name atIndex:(NSUInteger)to.row];
	[self saveOrderRestoring:before];
}

- (void)saveOrderRestoring:(NSArray *)before {
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reorderActiveUsernames:self.active
			completion:^(BOOL ok, NSString *error){
		TGUsernameSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			me.active = [before mutableCopy];
			[me.tableView reloadData];
			[TGAlertSheet showMessage:(error ?: @"Telegram refused that order.")
								title:@"Username Order" inView:me.view];
			return;
		}
		[me load];
	}];
}

- (void)usernameSwitchChanged:(TGUsernameSwitch *)sender {
	if (self.busy){
		sender.on = !sender.on;
		return;
	}
	NSString *username = sender.username;
	BOOL on = sender.on;
	self.busy = YES;
	sender.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleUsernameIsActive:username isActive:on
			completion:^(BOOL ok, NSString *error){
		TGUsernameSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			sender.on = !on;
			sender.enabled = YES;
			[TGAlertSheet showMessage:(error ?: @"Telegram refused that username.")
								title:@"Usernames" inView:me.view];
			return;
		}
		// A name moving between active and disabled changes both sections,
		// so the list is re-read rather than the one row being flipped.
		[me load];
	}];
}

#pragma mark - choosing

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (path.section != 0)
		return;
	if (path.row == 1){
		[self removeUsername];
		return;
	}

	NSString *current = self.editable;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Username"
					message:@"The name Telegram shows first. Letters, digits and "
							@"underscores; 5 to 32 characters."
				placeholder:@"username"
					   text:current
					 action:@"Save"
					 inView:self.view
				 onSubmit:^(NSString *text){
		NSString *username = [text stringByReplacingOccurrencesOfString:@"@"
															withString:@""];
		[[TGClient shared] setUsername:username completion:^(BOOL ok){
			if (!ok){
				[TGAlertSheet showMessage:@"That username is not available, or "
										  @"Telegram refused the change."
									title:@"Username" inView:weakSelf.view];
				return;
			}
			[weakSelf load];
		}];
	}];
}

- (void)removeUsername {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Removing the editable username leaves the "
							  @"account reachable only by your phone number. "
							  @"Other active or disabled names keep it from "
							  @"being removed completely."
						title:@"Remove Username"
					   action:@"Remove"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] setUsername:@"" completion:^(BOOL ok){
			if (!ok){
				[TGAlertSheet showMessage:@"Telegram refused that. A name cannot "
										  @"be removed while another one is active "
										  @"or disabled."
									title:@"Remove Username" inView:weakSelf.view];
				return;
			}
			[weakSelf load];
		}];
	}];
}

@end
