#import "TGDiceViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"

@interface TGDiceViewController ()
@property (nonatomic, strong) NSDictionary *state;
@end

@implementation TGDiceViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.chatTitle.length
			? [NSString stringWithFormat:@"%@ · Dice", self.chatTitle]
			: @"Stake Dice";
	self.tableView.rowHeight = TGMetricRow;
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain
				   target:self action:@selector(refreshTapped)];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(stateChanged:)
				name:TGStakeDiceStateChangedNotification object:nil];
	[self refresh];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stateChanged:(NSNotification *)note {
	// The cached state is internal; a notification means a newer one exists,
	// so the panel asks once rather than reading a property it may not see.
	[self refresh];
}

- (void)refreshTapped {
	[self refresh];
}

- (void)refresh {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] stakeDiceStateWithCompletion:^(NSDictionary *state,
													  NSString *error){
		TGDiceViewController *me = weakSelf;
		if (!me)
			return;
		if (error.length){
			[TGAlertSheet showMessage:error title:@"Stake Dice" inView:me.view];
			return;
		}
		me.state = state;
		[me.tableView reloadData];
	}];
}

/// The API counts in the smallest TON unit; the panel reads in TON, with
/// enough decimals to see a small suggested stake.
- (NSString *)ton:(NSNumber *)grams {
	double value = [grams doubleValue] / 1000000000.0;
	return [NSString stringWithFormat:@"%.4f TON", value];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return self.state ? 5 : 1;
	if (section == 1)
		return [self suggestedStakes].count;
	return [self prizeTable].count;
}

- (NSArray *)suggestedStakes {
	id value = self.state[@"suggestedStakeGramAmounts"];
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

- (NSArray *)prizeTable {
	id value = self.state[@"prizePerMille"];
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return @"State";
	if (section == 1)
		return @"Suggested Stakes";
	if (section == 2)
		return @"Prize per 1000";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"getStakeDiceState answers the hash a roll has to quote and "
			   @"the last amount staked. The hash expires; Refresh asks again.";
	if (section == 1)
		return @"Amounts Telegram suggests for the next roll.";
	if (section == 2)
		return @"Faces 1 to 6, in order. The streak row pays only when 6 lands "
			   @"three times in a row at the same stake.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (!self.state){
		cell.textLabel.text = @"Reading the stake dice state…";
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		return cell;
	}
	if (indexPath.section == 0){
		NSArray *pairs = @[
			@[@"State hash", self.state[@"stateHash"] ?: @"empty — this account cannot roll"],
			@[@"Last stake", [self ton:self.state[@"stakeGramAmount"] ?: @(0)]],
			@[@"Current streak", [NSString stringWithFormat:@"%@ of 3",
					self.state[@"currentStreak"] ?: @(0)]],
			@[@"Streak prize", [NSString stringWithFormat:@"%@ per 1000",
					self.state[@"streakPrizePerMille"] ?: @(0)]],
			@[@"Chat", self.chatId ? [NSString stringWithFormat:@"%lld", self.chatId]
								   : @"—"],
		];
		NSArray *pair = pairs[indexPath.row];
		cell.textLabel.text = pair[0];
		cell.detailTextLabel.text = pair[1];
		return cell;
	}
	if (indexPath.section == 1){
		cell.textLabel.text = [self ton:[self suggestedStakes][indexPath.row]];
		cell.detailTextLabel.text = @"Suggested for the next roll";
		return cell;
	}
	cell.textLabel.text = [NSString stringWithFormat:@"Face %ld", (long)indexPath.row + 1];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ per 1000 staked",
			[self prizeTable][indexPath.row]];
	return cell;
}

@end
