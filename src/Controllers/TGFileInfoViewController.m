#import "TGFileInfoViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

@interface TGFileInfoViewController ()
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) NSDictionary *names;
@property (nonatomic, copy) NSString *suggestedName;
@property (nonatomic, assign) long long prefixBytes;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGFileInfoViewController

+ (void)presentForFile:(NSInteger)fileId fromView:(UIView *)host {
	UIWindow *window = host.window ?: [UIApplication sharedApplication].keyWindow;
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController)
		top = top.presentedViewController;
	if (!top)
		return;

	TGFileInfoViewController *info = [[TGFileInfoViewController alloc] init];
	info.fileId = fileId;
	UINavigationController *nav = [[UINavigationController alloc]
			initWithRootViewController:info];
	info.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemDone
								 target:info action:@selector(dismissSelf)];
	[top presentViewController:nav animated:YES completion:nil];
}

- (void)dismissSelf {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"File Info";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf applyTheme];
	}];
	[self load];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
}

static NSString *TGFileInfoBytes(long long bytes) {
	if (bytes <= 0)
		return @"0 B";
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	if (bytes < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

- (void)load {
	if (self.fileId <= 0){
		self.loaded = YES;
		[self.tableView reloadData];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] fileInfo:self.fileId completion:^(NSDictionary *info){
		weakSelf.info = info;
		weakSelf.loaded = YES;
		[weakSelf.tableView reloadData];
	}];
	[[TGClient shared] fileDownloadedPrefixSize:self.fileId offset:0
									 completion:^(long long bytes){
		weakSelf.prefixBytes = bytes;
		[weakSelf.tableView reloadData];
	}];
	NSString *documents = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	[[TGClient shared] suggestedFileNameForFile:self.fileId directory:documents
									 completion:^(NSString *name){
		weakSelf.suggestedName = name;
		[weakSelf.tableView reloadData];
		[[TGClient shared] fileNameInfo:name completion:^(NSDictionary *info){
			weakSelf.names = info;
			[weakSelf.tableView reloadData];
		}];
	}];
}

- (NSArray *)detailRows {
	NSDictionary *info = self.info ?: @{};
	NSDictionary *names = self.names ?: @{};
	NSString *name = self.suggestedName;
	if (!name.length)
		name = [info[@"localPath"] lastPathComponent];
	if (!name.length)
		name = self.loaded ? @"Unavailable" : @"Reading...";

	NSString *extension = names[@"extension"] ?: @"";
	NSString *mime = names[@"mime"] ?: @"";
	NSString *type = (extension.length || mime.length)
			? [NSString stringWithFormat:@"%@%@%@", extension,
					(extension.length && mime.length) ? @" - " : @"", mime]
			: @"Unknown";
	long long size = [info[@"size"] longLongValue];
	if (size <= 0)
		size = [info[@"expectedSize"] longLongValue];
	long long expected = [info[@"expectedSize"] longLongValue];
	NSString *localPath = info[@"localPath"];
	if (!localPath.length)
		localPath = [info[@"completed"] boolValue] ? @"Downloaded" : @"Not downloaded";
	NSString *remote = info[@"remoteId"];
	if (!remote.length)
		remote = @"None";
	else if ([info[@"remoteResolved"] boolValue])
		remote = [NSString stringWithFormat:@"%@ (available)", remote];
	else
		remote = [NSString stringWithFormat:@"%@ (unavailable)", remote];

	return @[
		@[@"Name", name],
		@[@"Type", type],
		@[@"Clean Name", names[@"cleanName"] ?: @"Unknown"],
		@[@"Size", TGFileInfoBytes(size)],
		@[@"Expected Size", TGFileInfoBytes(expected)],
		@[@"Downloaded", [NSString stringWithFormat:@"%@ of %@",
				TGFileInfoBytes(self.prefixBytes), TGFileInfoBytes(size)]],
		@[@"Local Path", localPath],
		@[@"Remote ID", remote],
	];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? @"File" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return section == 0
			? @"Values come from TDLib's own file record. The remote entry is "
			  @"resolved again, so a stale id is shown as unavailable."
			: nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? (NSInteger)[self detailRows].count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TGTheme *theme = [TGTheme shared];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fileInfo"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"fileInfo"];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme cellDetailColour];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.text = @"";
	cell.detailTextLabel.text = @"";

	if (indexPath.section == 1){
		cell.textLabel.text = @"Copy File Info";
		cell.textLabel.textColor = [theme accentColour];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		return cell;
	}

	NSArray *row = [self detailRows][(NSUInteger)indexPath.row];
	cell.textLabel.text = row[0];
	cell.detailTextLabel.text = row[1];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1)
		return;

	NSMutableArray *lines = [NSMutableArray array];
	for (NSArray *row in [self detailRows])
		[lines addObject:[NSString stringWithFormat:@"%@: %@", row[0], row[1]]];
	[UIPasteboard generalPasteboard].string = [lines componentsJoinedByString:@"\n"];
	[TGAlertSheet showMessage:@"The file details are on the clipboard."
						 title:@"File Info" inView:self.view];
}

@end

// vim:ft=objc
