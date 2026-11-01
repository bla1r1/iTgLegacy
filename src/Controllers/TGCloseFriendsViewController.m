#import "TGCloseFriendsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@interface TGCloseFriendsViewController ()
@property (nonatomic, strong) NSArray *contacts;
@property (nonatomic, strong) NSMutableSet *selected;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGCloseFriendsViewController

- (instancetype)init {
	if ((self = [super initWithStyle:UITableViewStyleGrouped])){
		_selected = [NSMutableSet set];
		_contacts = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Close Friends";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] closeFriendsWithCompletion:^(NSArray *ids){
		TGCloseFriendsViewController *me = weakSelf;
		if (!me)
			return;
		[me.selected setSet:[NSSet setWithArray:ids]];
		[[TGClient shared] contactsWithCompletion:^(NSArray *contacts){
			TGCloseFriendsViewController *again = weakSelf;
			if (!again)
				return;
			again.contacts = contacts;
			again.loaded = YES;
			[again.tableView reloadData];
		}];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!self.loaded)
		return 1;
	return self.contacts.count ? (NSInteger)self.contacts.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.loaded)
		return @"Reading the list from Telegram…";
	if (!self.contacts.count)
		return @"No contacts to pick from.";
	return @"Every change is sent to Telegram at once.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"friend"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"friend"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	if (!self.loaded || !self.contacts.count){
		cell.textLabel.text = self.loaded ? @"No contacts to pick from." : @"Loading…";
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	NSDictionary *contact = self.contacts[(NSUInteger)indexPath.row];
	NSNumber *userId = contact[@"id"];
	NSString *name = [[NSString stringWithFormat:@"%@ %@",
			contact[@"first_name"] ?: @"", contact[@"last_name"] ?: @""]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (!name.length)
		name = contact[@"username"] ?: @"Contact";
	BOOL on = [self.selected containsObject:userId];
	cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", (on ? @"✓" : @"○"), name];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = contact[@"username"] ?: nil;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.loaded || indexPath.row >= (NSInteger)self.contacts.count)
		return;

	NSDictionary *contact = self.contacts[(NSUInteger)indexPath.row];
	NSNumber *userId = contact[@"id"];
	if (![userId isKindOfClass:NSNumber.class])
		return;

	NSMutableSet *before = [self.selected copy];
	if ([self.selected containsObject:userId])
		[self.selected removeObject:userId];
	else
		[self.selected addObject:userId];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setCloseFriends:self.selected.allObjects
							completion:^(BOOL ok, NSString *error){
		TGCloseFriendsViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			// The check goes back where it was; the server's sentence is why.
			[me.selected setSet:before];
			[me.tableView reloadData];
			[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
								title:@"Close Friends" inView:me.view];
			return;
		}
		if (me.onCountChanged)
			me.onCountChanged((NSInteger)me.selected.count);
	}];
}

@end
