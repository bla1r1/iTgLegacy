#import "TGListViewController.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@implementation TGListViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.rows = self.rows ?: @[];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	if (self.offersCopy)
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Copy" style:UIBarButtonItemStylePlain
					   target:self action:@selector(copyAll)];

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
	self.title = self.listTitle ?: self.title;
	[self applyTheme];
	[self.tableView reloadData];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)setRows:(NSArray *)rows {
	_rows = rows ?: @[];
	if (self.isViewLoaded)
		[self.tableView reloadData];
}

- (void)setListTitle:(NSString *)listTitle {
	_listTitle = [listTitle copy];
	self.title = listTitle;
}

- (void)copyAll {
	NSMutableArray *lines = [NSMutableArray array];
	if (self.listFooter.length)
		[lines addObject:self.listFooter];
	for (NSDictionary *row in self.rows){
		NSString *title = row[@"title"] ?: @"";
		NSString *detail = row[@"detail"] ?: @"";
		[lines addObject:detail.length
				? [NSString stringWithFormat:@"%@: %@", title, detail]
				: title];
	}
	[UIPasteboard generalPasteboard].string =
			[lines componentsJoinedByString:@"\n"];
	[TGAlertSheet showMessage:@"Copied." title:nil inView:self.view];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.rows.count ?: 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.rows.count)
		return self.emptyText;
	return self.listFooter;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.rows.count){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"empty"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"empty"];
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.text = self.emptyText ?: @"Nothing here yet.";
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.textLabel.font = TGFontBody();
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSDictionary *row = self.rows[indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = row[@"title"] ?: @"";
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [row[@"destructive"] boolValue]
			? [[TGTheme shared] destructiveColour]
			: [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = row[@"detail"];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = row[@"tap"] ? UITableViewCellAccessoryDisclosureIndicator
									 : UITableViewCellAccessoryNone;
	cell.selectionStyle = row[@"tap"] ? UITableViewCellSelectionStyleBlue
									  : UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.rows.count)
		return;
	NSDictionary *row = self.rows[indexPath.row];
	void (^tap)(void) = row[@"tap"];
	if (tap)
		tap();
}

@end
