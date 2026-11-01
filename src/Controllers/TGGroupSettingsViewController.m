//
// TGGroupSettingsViewController.m - one screen for the supergroup's identity
// and mode switches.
//
// The More menu used to grow one row per supergroup toggle: Sign Messages,
// Join to Send, All History, and no place for the username at all. Each row
// asked the server what it sat on and answered with an alert. This screen asks
// once, draws the switches from that answer, and sends the one that moved.
// Telegram's refusal is shown with the server's own sentence.
//
#import "TGGroupSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// A switch that names the setting it changes, so a reload can rebuild rows
/// without an index pointing at the wrong one.
@interface TGGroupSwitch : UISwitch
@property (nonatomic, copy) NSString *key;
@end

@implementation TGGroupSwitch
@end

@interface TGGroupSettingsViewController ()
@property (nonatomic, strong) NSDictionary *settings;
@property (nonatomic, strong) NSMutableArray *active;
@property (nonatomic, strong) NSMutableArray *disabled;
@property (nonatomic, copy) NSString *editable;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGGroupSettingsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.chatTitle.length ? self.chatTitle : @"Group Settings";
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
	// A switch moved on another device is a full-info update here. The screen
	// re-reads rather than showing the value it opened with.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGFullInfoChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		NSNumber *chatId = note.userInfo[@"id"];
		if (chatId && [chatId longLongValue] == weakSelf.chatId)
			[weakSelf load];
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
	[[TGClient shared] supergroupSettingsForChat:self.chatId
			completion:^(NSDictionary *settings){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.settings = settings;
		me.active = [settings[@"active"] isKindOfClass:NSArray.class]
				? [settings[@"active"] mutableCopy] : [NSMutableArray array];
		me.disabled = [settings[@"disabled"] isKindOfClass:NSArray.class]
				? [settings[@"disabled"] mutableCopy] : [NSMutableArray array];
		me.editable = settings[@"editable"] ?: @"";
		me.loaded = YES;
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

- (void)showRefusal:(NSString *)error title:(NSString *)title {
	[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
						title:title inView:self.view];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (!self.loaded)
		return 0;
	return self.settings ? 5 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (!self.settings) return nil;
	if (section == 1) return @"Active usernames";
	if (section == 2) return @"Disabled usernames";
	if (section == 4) return @"Group mode";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.settings)
		return @"A basic group has no username, forum mode or admin defaults. "
			   @"Upgrade it to a supergroup first.";
	if (section == 0)
		return [self.settings[@"canSetUsername"] boolValue]
				? @"The public @name in front of the group's link. Removing it "
				  @"keeps every active name below."
				: @"Telegram says this account may not change the group's "
				  @"username. The request is still sent so the server's reason "
				  @"is the one shown.";
	if (section == 1 && self.active.count > 1)
		return @"Tap Edit and drag a row to change the order of the names on "
			   @"the group's profile.";
	if (section == 2 && !self.disabled.count)
		return @"Every other name is active.";
	if (section == 3)
		return @"Switches off every active name except the editable one. "
			   @"The names stay on the group and can be switched back on.";
	if (section == 4)
		return @"Forum mode, join requests, hidden members and translation are "
			   @"administrator switches. Telegram applies the one that moved "
			   @"or refuses it with a reason.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!self.settings)
		return 1;
	if (section == 0) return self.editable.length ? 2 : 1;
	if (section == 1) return self.active.count;
	if (section == 2) return self.disabled.count;
	if (section == 3) return 1;
	return 6;
}

- (UITableViewCell *)plainCell:(NSString *)text detail:(NSString *)detail {
	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = text;
	cell.textLabel.font = TGFontRow();
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	TGTheme *theme = [TGTheme shared];
	if (!self.settings)
		return [self plainCell:@"Not a supergroup"
						detail:@"This chat has no supergroup settings."];

	if (path.section == 0){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.font = TGFontRow();
		cell.detailTextLabel.font = TGFontBody();
		cell.detailTextLabel.textColor = [theme cellDetailColour];
		if (path.row == 0){
			cell.textLabel.text = @"Editable Username";
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

	if (path.section == 3){
		UITableViewCell *cell = [[UITableViewCell alloc]
				initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		[theme styleCell:cell];
		cell.textLabel.text = @"Disable All Usernames";
		cell.textLabel.font = TGFontRow();
		cell.textLabel.textColor = [theme destructiveColour];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if (path.section == 4)
		return [self modeCellAtRow:(NSUInteger)path.row];

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

	TGGroupSwitch *toggle = [[TGGroupSwitch alloc] init];
	toggle.key = username;
	toggle.on = isActive;
	toggle.enabled = !(isActive && [username isEqualToString:self.editable]) && !self.busy;
	[toggle addTarget:self action:@selector(usernameSwitchChanged:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (UITableViewCell *)modeCellAtRow:(NSUInteger)row {
	static NSArray *keys = nil;
	static NSArray *titles = nil;
	if (!keys){
		keys = @[@"forum", @"join", @"hidden", @"translation"];
		titles = @[@"Forum Mode", @"Join by Request", @"Hidden Members",
				   @"Automatic Translation"];
	}
	TGTheme *theme = [TGTheme shared];
	if (row < keys.count){
		UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"mode"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
										  reuseIdentifier:@"mode"];
		[theme styleCell:cell];
		cell.textLabel.text = titles[row];
		cell.textLabel.font = TGFontRow();
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.font = TGFontCaption();
		cell.detailTextLabel.textColor = [theme secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		NSString *key = keys[row];
		BOOL on = NO;
		NSString *detail = nil;
		if ([key isEqualToString:@"forum"]){
			on = [self.settings[@"isForum"] boolValue];
			detail = on ? @"Topics are on" : @"One message stream";
		} else if ([key isEqualToString:@"join"]){
			on = [self.settings[@"joinByRequest"] boolValue];
			detail = on ? @"Administrators approve each join"
						: @"Anyone with the link joins";
		} else if ([key isEqualToString:@"hidden"]){
			on = [self.settings[@"hiddenMembers"] boolValue];
			detail = [self.settings[@"canHideMembers"] boolValue]
					? (on ? @"Members are hidden" : @"Members are listed")
					: @"Telegram does not allow this group to hide members";
		} else {
			on = [self.settings[@"automaticTranslation"] boolValue];
			detail = on ? @"The channel suggests a translation"
						: @"No automatic translation";
		}
		cell.detailTextLabel.text = detail;

		TGGroupSwitch *toggle = [[TGGroupSwitch alloc] init];
		toggle.key = key;
		toggle.on = on;
		toggle.enabled = !self.busy;
		[toggle addTarget:self action:@selector(modeSwitchChanged:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		return cell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontRow();
	cell.detailTextLabel.font = TGFontBody();
	cell.detailTextLabel.textColor = [theme cellDetailColour];
	if (row == 4){
		cell.textLabel.text = @"Main Profile Tab";
		cell.detailTextLabel.text = [self labelForTab:self.settings[@"mainTab"]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		BOOL broadcast = [self.settings[@"isBroadcast"] boolValue];
		cell.textLabel.text = @"Broadcast Group";
		cell.detailTextLabel.text = broadcast ? @"On" : @"Convert";
		cell.accessoryType = broadcast ? UITableViewCellAccessoryNone
									  : UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = broadcast ? UITableViewCellSelectionStyleNone
									   : UITableViewCellSelectionStyleBlue;
	}
	return cell;
}

- (NSString *)labelForTab:(NSString *)tab {
	if ([tab isEqualToString:@"media"]) return @"Media";
	if ([tab isEqualToString:@"files"]) return @"Files";
	if ([tab isEqualToString:@"links"]) return @"Links";
	if ([tab isEqualToString:@"music"]) return @"Music";
	if ([tab isEqualToString:@"voice"]) return @"Voice";
	if ([tab isEqualToString:@"gifs"])  return @"GIFs";
	return @"Posts";
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
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
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reorderSupergroupActiveUsernames:self.active inChat:self.chatId
			completion:^(BOOL ok, NSString *error){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			me.active = [before mutableCopy];
			[me.tableView reloadData];
			[me showRefusal:error title:@"Username Order"];
			return;
		}
		[me load];
	}];
}

#pragma mark - changes

- (void)usernameSwitchChanged:(TGGroupSwitch *)sender {
	if (self.busy){
		sender.on = !sender.on;
		return;
	}
	NSString *username = sender.key;
	BOOL on = sender.on;
	self.busy = YES;
	sender.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleSupergroupUsernameIsActive:username
												 inChat:self.chatId
											   isActive:on
											 completion:^(BOOL ok, NSString *error){
		TGGroupSettingsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (!ok){
			sender.on = !on;
			sender.enabled = YES;
			[me showRefusal:error title:@"Username"];
			return;
		}
		[me load];
	}];
}

- (void)modeSwitchChanged:(TGGroupSwitch *)sender {
	if (self.busy){
		sender.on = !sender.on;
		return;
	}
	NSString *key = sender.key;
	BOOL on = sender.on;
	void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
		self.busy = NO;
		if (!ok){
			sender.on = !on;
			sender.enabled = YES;
			[self showRefusal:error title:@"Group Settings"];
			return;
		}
		NSMutableDictionary *changed = [self.settings mutableCopy];
		if ([key isEqualToString:@"forum"])
			changed[@"isForum"] = @(on);
		else if ([key isEqualToString:@"join"])
			changed[@"joinByRequest"] = @(on);
		else if ([key isEqualToString:@"hidden"])
			changed[@"hiddenMembers"] = @(on);
		else
			changed[@"automaticTranslation"] = @(on);
		self.settings = changed;
		sender.enabled = YES;
		[self.tableView reloadData];
	};

	self.busy = YES;
	sender.enabled = NO;
	if ([key isEqualToString:@"forum"]){
		[[TGClient shared] setSupergroupForumInChat:self.chatId on:on completion:done];
	} else if ([key isEqualToString:@"join"]){
		[[TGClient shared] setSupergroupJoinByRequestInChat:self.chatId on:on
											 guardBotUserId:[self.settings[@"guardBotUserId"] longLongValue]
												 completion:done];
	} else if ([key isEqualToString:@"hidden"]){
		[[TGClient shared] setSupergroupHiddenMembersInChat:self.chatId on:on
												 completion:done];
	} else {
		[[TGClient shared] setSupergroupAutomaticTranslationInChat:self.chatId on:on
														completion:done];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (!self.settings)
		return;
	if (path.section == 0){
		if (path.row == 1)
			[self removeUsername];
		else
			[self editUsername];
		return;
	}
	if (path.section == 3){
		[self disableAll];
		return;
	}
	if (path.section != 4)
		return;
	if (path.row == 4)
		[self chooseMainTab];
	else if (path.row == 5 && ![self.settings[@"isBroadcast"] boolValue])
		[self confirmBroadcast];
}

- (void)editUsername {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Group Username"
					message:@"The public @name for this group or channel. Remove "
							@"it from the row above; active names below stay."
				placeholder:@"username"
					   text:self.editable
					 action:@"Save"
					 inView:self.view
				 onSubmit:^(NSString *text){
		NSString *username = [text stringByReplacingOccurrencesOfString:@"@"
															withString:@""];
		[[TGClient shared] setSupergroupUsername:username inChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Group Username"];
				return;
			}
			[weakSelf load];
		}];
	}];
}

- (void)removeUsername {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Removing the editable username leaves the group "
							  @"reachable only through its invite link or its "
							  @"active names. Names below are not touched."
						title:@"Remove Username"
					   action:@"Remove"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] setSupergroupUsername:@"" inChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Remove Username"];
				return;
			}
			[weakSelf load];
		}];
	}];
}

- (void)disableAll {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Every active name except the editable one is "
							  @"switched off. They stay on the group and can be "
							  @"switched back on here."
						title:@"Disable All Usernames"
					   action:@"Disable"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] disableAllSupergroupUsernamesInChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Disable Usernames"];
				return;
			}
			[weakSelf load];
		}];
	}];
}

- (void)chooseMainTab {
	NSArray *names = @[@"posts", @"media", @"files", @"links", @"music",
					   @"voice", @"gifs"];
	NSArray *titles = @[@"Posts", @"Media", @"Files", @"Links", @"Music",
						@"Voice", @"GIFs"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Main Profile Tab"
			destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		NSString *tab = names[(NSUInteger)index];
		[[TGClient shared] setSupergroupMainProfileTab:tab inChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Main Profile Tab"];
				return;
			}
			NSMutableDictionary *changed = [weakSelf.settings mutableCopy];
			changed[@"mainTab"] = tab;
			weakSelf.settings = changed;
			[weakSelf.tableView reloadData];
		}];
	}];
}

- (void)confirmBroadcast {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"A broadcast group is read by its members and "
							  @"posted to by administrators only. Telegram has "
							  @"no way back from this."
						title:@"Convert to Broadcast Group"
					   action:@"Convert"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] convertSupergroupToBroadcastInChat:weakSelf.chatId
				completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:error title:@"Broadcast Group"];
				return;
			}
			NSMutableDictionary *changed = [weakSelf.settings mutableCopy];
			changed[@"isBroadcast"] = @YES;
			weakSelf.settings = changed;
			[weakSelf.tableView reloadData];
		}];
	}];
}

@end
