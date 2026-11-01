//
// TGTier2ListViewController.m
//
#import "TGTier2ListViewController.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGSnackbar.h"

NSString *const TGTier2RowTitle       = @"title";
NSString *const TGTier2RowDetail      = @"detail";
NSString *const TGTier2RowKind        = @"kind";
NSString *const TGTier2RowTap         = @"tap";
NSString *const TGTier2RowChecked     = @"checked";
NSString *const TGTier2RowSubtitle    = @"subtitle";
NSString *const TGTier2RowDestructive = @"destructive";

NSString *const TGTier2KindPlain       = @"plain";
NSString *const TGTier2KindDisclosure  = @"disclosure";
NSString *const TGTier2KindCheck       = @"check";
NSString *const TGTier2KindAction      = @"action";
NSString *const TGTier2KindDestructive = @"destructive";

NSMutableDictionary *TGTier2Row(NSString *title, NSString *detail, void (^tap)(void)) {
	NSMutableDictionary *row = [@{TGTier2RowKind  : TGTier2KindDisclosure,
								  TGTier2RowTitle : title ?: @""} mutableCopy];
	if (detail.length)
		row[TGTier2RowDetail] = detail;
	if (tap)
		row[TGTier2RowTap] = [tap copy];
	return row;
}

NSMutableDictionary *TGTier2Action(NSString *title, void (^tap)(void)) {
	NSMutableDictionary *row = [@{TGTier2RowKind  : TGTier2KindAction,
								  TGTier2RowTitle : title ?: @""} mutableCopy];
	if (tap)
		row[TGTier2RowTap] = [tap copy];
	return row;
}

NSMutableDictionary *TGTier2Check(NSString *title, NSString *detail, BOOL checked,
								  void (^tap)(void)) {
	NSMutableDictionary *row = [@{TGTier2RowKind    : TGTier2KindCheck,
								  TGTier2RowTitle   : title ?: @"",
								  TGTier2RowChecked : @(checked)} mutableCopy];
	if (detail.length)
		row[TGTier2RowDetail] = detail;
	if (tap)
		row[TGTier2RowTap] = [tap copy];
	return row;
}

NSDictionary *TGTier2Section(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

@interface TGTier2ListViewController ()
@end

@implementation TGTier2ListViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){ [weakSelf applyTheme]; }];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
}

- (void)reloadRows {
	[self.tableView reloadData];
}

- (void)toast:(NSString *)text {
	UIView *host = self.navigationController.view ?: self.view;
	[TGSnackbar showInView:host text:text seconds:2 onCommit:nil];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.sections[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return self.sections[section][@"footer"];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	// The system's grouped header is left as it is: it follows the table's
	// style, and a hand-painted one was what the token lint exists to stop.
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
	NSString *kind = row[TGTier2RowKind] ?: TGTier2KindPlain;
	BOOL subtitle = [row[TGTier2RowSubtitle] boolValue];
	NSString *ident = subtitle ? @"subtitle" : (kind ?: @"plain");
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:(subtitle
				? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1)
									  reuseIdentifier:ident];
	}
	cell.textLabel.text = row[TGTier2RowTitle];
	cell.detailTextLabel.text = row[TGTier2RowDetail];
	cell.detailTextLabel.numberOfLines = subtitle ? 2 : 1;
	cell.textLabel.textColor = [kind isEqualToString:TGTier2KindDestructive]
			? [[TGTheme shared] destructiveColour] : [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	if ([kind isEqualToString:TGTier2KindCheck])
		cell.accessoryType = [row[TGTier2RowChecked] boolValue]
				? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	else if ([kind isEqualToString:TGTier2KindDisclosure])
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	else if ([kind isEqualToString:TGTier2KindAction])
		cell.textLabel.textColor = [[TGTheme shared] accentColour];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
	void (^tap)(void) = row[TGTier2RowTap];
	if (tap)
		tap();
}

@end

#pragma mark - result screen

@interface TGTier2ResultViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation TGTier2ResultViewController

- (instancetype)initWithTitle:(NSString *)title body:(NSString *)body {
	self = [super initWithNibName:nil bundle:nil];
	if (!self)
		return nil;
	self.title = title;
	_body = [body copy];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.view.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

	self.textView = [[UITextView alloc] initWithFrame:UIEdgeInsetsInsetRect(
			self.view.bounds, UIEdgeInsetsMake(TGMetricPadLarge, TGMetricPadLarge,
											   TGMetricPadLarge, TGMetricPadLarge))];
	self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									 UIViewAutoresizingFlexibleHeight;
	self.textView.editable = NO;
	self.textView.font = TGFontBody();
	self.textView.textColor = [[TGTheme shared] primaryTextColour];
	self.textView.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	self.textView.text = self.body ?: @"";
	[self.view addSubview:self.textView];

	__weak typeof(self) weakSelf = self;
	UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy"
			style:UIBarButtonItemStyleBordered
		   target:self action:@selector(copyText)];
	self.navigationItem.rightBarButtonItem = copy;
	if (self.onSend){
		UIBarButtonItem *send = [[UIBarButtonItem alloc] initWithTitle:@"Send"
				style:UIBarButtonItemStyleDone
			   target:self action:@selector(sendText)];
		self.navigationItem.rightBarButtonItems = @[send, copy];
	}
	(void)weakSelf;
}

- (void)copyText {
	[UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
	UIView *host = self.navigationController.view ?: self.view;
	[TGSnackbar showInView:host text:@"Copied" seconds:2 onCommit:nil];
}

- (void)sendText {
	if (self.onSend)
		self.onSend(self.textView.text ?: @"");
	[self.navigationController popViewControllerAnimated:YES];
}

@end
