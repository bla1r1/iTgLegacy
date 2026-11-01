//
// TGAdminRightsViewController.m - the two default administrator-rights
// presets, one for groups and one for channels.
//
// The protocol has no getter for these; Telegram keeps the last set value on
// the bot account. The row therefore remembers the preset this app last had
// accepted, and when the server refuses it says why rather than pretending
// the choice stuck. Both requests are bot-only: a user account is expected to
// see the refusal, which is the server answering the button.
//
#import "TGAdminRightsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

static NSString *const kGroupPresetKey   = @"TGDefaultGroupAdminRights";
static NSString *const kChannelPresetKey = @"TGDefaultChannelAdminRights";

@interface TGAdminRightsViewController ()
@property (nonatomic, assign) BOOL busy;
@end

@implementation TGAdminRightsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Default Admin Rights";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];

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
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (NSString *)savedPresetForKey:(NSString *)key {
	NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:key];
	return saved.length ? saved : nil;
}

- (NSString *)labelForPreset:(NSString *)preset {
	if ([preset isEqualToString:@"readonly"]) return @"Read-only";
	if ([preset isEqualToString:@"posting"])  return @"Posting";
	if ([preset isEqualToString:@"full"])     return @"Full";
	if ([preset isEqualToString:@"standard"]) return @"Standard";
	return @"Not set";
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? @"When added to a group"
						: @"When added to a channel";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"Telegram applies these rights automatically when this bot is "
			   @"added as a group administrator. The page is also where a "
			   @"bot account changes them; a user account gets the server's "
			   @"refusal and the row keeps only what Telegram accepted.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontRow();
	cell.detailTextLabel.font = TGFontBody();
	cell.detailTextLabel.textColor = [[TGTheme shared] cellDetailColour];
	cell.textLabel.text = path.section == 0 ? @"Group Preset" : @"Channel Preset";
	NSString *key = path.section == 0 ? kGroupPresetKey : kChannelPresetKey;
	cell.detailTextLabel.text = [self labelForPreset:[self savedPresetForKey:key]];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = self.busy ? UITableViewCellSelectionStyleNone
									: UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (self.busy)
		return;
	BOOL channel = path.section == 1;
	NSArray *presets = @[@"readonly", @"standard", @"posting", @"full"];
	NSArray *titles = @[@"Read-only", @"Standard", @"Posting", @"Full"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles
						title:(channel ? @"Channel Administrator Rights"
									   : @"Group Administrator Rights")
						message:@"The rights this account's bot gets when it is "
								@"added as an administrator."
			 destructiveIndex:-1
						 inView:self.view
					   onChoice:^(NSInteger index){
		NSString *preset = presets[(NSUInteger)index];
		weakSelf.busy = YES;
		[weakSelf.tableView reloadData];
		void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
			TGAdminRightsViewController *me = weakSelf;
			if (!me)
				return;
			me.busy = NO;
			if (!ok){
				[TGAlertSheet showMessage:(error ?: @"Telegram refused those rights.")
									title:@"Default Admin Rights" inView:me.view];
				[me.tableView reloadData];
				return;
			}
			[NSUserDefaults.standardUserDefaults setObject:preset
					forKey:(channel ? kChannelPresetKey : kGroupPresetKey)];
			[NSUserDefaults.standardUserDefaults synchronize];
			[me.tableView reloadData];
		};
		if (channel)
			[[TGClient shared] setDefaultChannelAdministratorRightsPreset:preset
																completion:done];
		else
			[[TGClient shared] setDefaultGroupAdministratorRightsPreset:preset
															  completion:done];
	}];
}

@end
