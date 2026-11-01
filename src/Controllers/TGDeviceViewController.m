#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGCapabilities.h"
#import "TGTheme.h"
#import "TGClient.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@interface TGDeviceViewController ()
@property (nonatomic, strong) NSArray *capabilities;
@end

@implementation TGDeviceViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"This Device";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	self.capabilities = [TGCapabilities all];

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
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section){
		case 0: return @"SOFTWARE";
		case 1: return @"HARDWARE";
		case 2: return @"FEATURES";
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1)
		return @"Vintage: iPhone 3GS and 4. Legacy: 4S, 5 and 5c. "
			   @"Modern: 5s and 6. Full: 6s and later.";
	if (section == 2)
		return @"A feature that is off here is not missing from the app - this "
			   @"device cannot run it. The reason beside each row is the same "
			   @"one the rest of the app checks before it draws the button.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 2;
	if (section == 1) return 3;
	if (section == 2) return self.capabilities.count;
	return 1; // Log out
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.font = TGFontSubhead();
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	if (indexPath.section == 0){
		NSDictionary *info = [NSBundle mainBundle].infoDictionary;
		if (indexPath.row == 0){
			cell.textLabel.text = @"iOS";
			cell.detailTextLabel.text = [UIDevice currentDevice].systemVersion;
		} else {
			cell.textLabel.text = @"LegacyTG";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)",
					info[@"CFBundleShortVersionString"] ?: @"?",
					info[@"CFBundleVersion"] ?: @"?"];
		}
		return cell;
	}

	if (indexPath.section == 1){
		switch (indexPath.row){
			case 0:
				cell.textLabel.text = @"Model";
				cell.detailTextLabel.text = [TGDevice modelName];
				break;
			case 1:
				cell.textLabel.text = @"Chip and Memory";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %lu MB",
						[TGDevice chip] ?: @"?", (unsigned long)[TGDevice memoryMB]];
				break;
			default:
				cell.textLabel.text = @"Device Tier";
				cell.detailTextLabel.text = [TGDevice tierName];
				break;
		}
		return cell;
	}

	if (indexPath.section == 3){
		// Log out — red, centred, tappable
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.textLabel.text = @"Log out";
		cell.textLabel.textColor = [[TGTheme shared] destructiveColour];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.detailTextLabel.text = nil;
		return cell;
	}

	TGCapability *capability = self.capabilities[indexPath.row];
	cell.textLabel.text = capability.name;
	cell.detailTextLabel.text = capability.available ? @"On" : capability.requirement;
	cell.detailTextLabel.textColor = capability.available
			? [[TGTheme shared] onlineColour]
			: [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = capability.available
			? [[TGTheme shared] primaryTextColour]
			: [[TGTheme shared] secondaryTextColour];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 3)
		return;
	// Log out — confirm before doing anything irreversible
	[TGAlertSheet showConfirm:@"Are you sure you want to log out?"
						title:@"Log out"
					   action:@"Log out"
				  destructive:YES
					   inView:self.view
					onConfirm:^{ [[TGClient shared] logOut]; }];
}



@end

// vim:ft=objc
