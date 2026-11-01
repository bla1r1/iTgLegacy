#import "TGFileInfoViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"

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

/// The things a file record can be acted on with. Telegram's file sheet puts
/// Share and Save above the record, not behind a hold, and offers Delete only
/// when the bytes are actually on this device.
- (NSArray *)actionRows {
	NSMutableArray *rows = [NSMutableArray array];
	NSDictionary *info = self.info ?: @{};
	NSString *path = [info[@"localPath"] isKindOfClass:NSString.class]
			? info[@"localPath"] : @"";
	if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]){
		[rows addObject:@"Share File"];
		NSString *extension = path.pathExtension.lowercaseString;
		if ([@[@"jpg", @"jpeg", @"png", @"webp"] containsObject:extension] ||
			[@[@"mp4", @"mov", @"m4v"] containsObject:extension])
			[rows addObject:@"Save to Photos"];
	}
	[rows addObject:@"Copy File Info"];
	if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path])
		[rows addObject:@"Delete from Device"];
	return rows;
}

- (NSString *)heroName {
	NSDictionary *info = self.info ?: @{};
	NSString *name = self.suggestedName;
	if (!name.length)
		name = [info[@"localPath"] lastPathComponent];
	return name.length ? name : (self.loaded ? @"Unavailable" : @"Reading...");
}

- (long long)heroSize {
	NSDictionary *info = self.info ?: @{};
	long long size = [info[@"size"] longLongValue];
	if (size <= 0)
		size = [info[@"expectedSize"] longLongValue];
	return size;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"File";
	if (section == 1) return @"Actions";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"Values come from TDLib's own file record. The remote entry is "
			   @"resolved again, so a stale id is shown as unavailable.";
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView
		heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0 && indexPath.row == 0)
		return TGMetricFileInfoHero;
	return TGMetricRow;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1 + (NSInteger)[self detailRows].count;
	if (section == 1) return (NSInteger)[self actionRows].count;
	return (NSInteger)0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TGTheme *theme = [TGTheme shared];

	if (indexPath.section == 0 && indexPath.row == 0){
		UITableViewCell *hero = [tableView dequeueReusableCellWithIdentifier:@"hero"];
		if (!hero){
			hero = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"hero"];
			hero.selectionStyle = UITableViewCellSelectionStyleNone;

			UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(
					TGMetricPadLarge,
					TGCenteredOrigin(TGMetricFileInfoHero, TGMetricFileInfoIcon),
					TGMetricFileInfoIcon, TGMetricFileInfoIcon)];
			icon.tag = 1;
			icon.contentMode = UIViewContentModeScaleAspectFit;
			[hero.contentView addSubview:icon];

			CGFloat textX = CGRectGetMaxX(icon.frame) + TGMetricPadMedium;
			UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(textX,
					TGMetricPadMedium + TGMetricPadSmall,
					tableView.bounds.size.width - textX - TGMetricPadLarge,
					TGMetricLineHeader)];
			name.tag = 2;
			name.font = TGFontHeader();
			name.lineBreakMode = NSLineBreakByTruncatingMiddle;
			[hero.contentView addSubview:name];

			UILabel *size = [[UILabel alloc] initWithFrame:CGRectMake(textX,
					CGRectGetMaxY(name.frame), name.bounds.size.width,
					TGMetricLineCaption)];
			size.tag = 3;
			size.font = TGFontSubhead();
			[hero.contentView addSubview:size];
		}
		[theme styleCell:hero];
		[[hero.contentView viewWithTag:1] setImage:
				[TGIcons fileDiscOfSide:TGMetricFileInfoIcon]];
		UILabel *name = (UILabel *)[hero.contentView viewWithTag:2];
		UILabel *size = (UILabel *)[hero.contentView viewWithTag:3];
		CGFloat contentWidth = hero.contentView.bounds.size.width;
		if (contentWidth > 0){
			CGFloat textX = TGMetricPadLarge + TGMetricFileInfoIcon +
					TGMetricPadMedium;
			name.frame = CGRectMake(textX, TGMetricPadMedium + TGMetricPadSmall,
					contentWidth - textX - TGMetricPadLarge,
					TGMetricLineHeader);
			size.frame = CGRectMake(textX, CGRectGetMaxY(name.frame),
					name.bounds.size.width, TGMetricLineCaption);
		}
		name.text = [self heroName];
		name.textColor = [theme primaryTextColour];
		size.text = TGFileInfoBytes([self heroSize]);
		size.textColor = [theme secondaryTextColour];
		return hero;
	}

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
	cell.textLabel.textAlignment = NSTextAlignmentLeft;

	if (indexPath.section == 1){
		NSArray *actions = [self actionRows];
		if (indexPath.row >= (NSInteger)actions.count)
			return cell;
		NSString *action = actions[(NSUInteger)indexPath.row];
		cell.textLabel.text = action;
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = [action isEqualToString:@"Delete from Device"]
				? [theme destructiveColour] : [theme accentColour];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		return cell;
	}

	NSArray *rows = [self detailRows];
	if (indexPath.row < 1 || indexPath.row - 1 >= (NSInteger)rows.count)
		return cell;
	NSArray *row = rows[(NSUInteger)(indexPath.row - 1)];
	cell.textLabel.text = row[0];
	cell.detailTextLabel.text = row[1];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1)
		return;
	NSArray *actions = [self actionRows];
	if (indexPath.row >= (NSInteger)actions.count)
		return;
	NSString *action = actions[(NSUInteger)indexPath.row];

	if ([action isEqualToString:@"Share File"]){
		[self shareFile];
		return;
	}
	if ([action isEqualToString:@"Save to Photos"]){
		[self saveFile];
		return;
	}
	if ([action isEqualToString:@"Delete from Device"]){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"The downloaded copy comes off this device. "
				@"Telegram can download it again."
							title:@"Delete from Device"
						   action:@"Delete" destructive:YES
						   inView:self.view
						onConfirm:^{
			TGFileInfoViewController *me = weakSelf;
			if (!me)
				return;
			[[TGClient shared] deleteLocalFile:me.fileId];
			[TGAlertSheet showMessage:@"The copy was deleted."
								  title:@"File" inView:me.view];
			[me load];
		}];
		return;
	}

	NSMutableArray *lines = [NSMutableArray array];
	for (NSArray *row in [self detailRows])
		[lines addObject:[NSString stringWithFormat:@"%@: %@", row[0], row[1]]];
	[UIPasteboard generalPasteboard].string = [lines componentsJoinedByString:@"\n"];
	[TGAlertSheet showMessage:@"The file details are on the clipboard."
						 title:@"File Info" inView:self.view];
}

/// The record's own path, not a fresh download: the action is only offered
/// when the bytes are already here.
- (NSString *)localPath {
	NSDictionary *info = self.info ?: @{};
	NSString *path = [info[@"localPath"] isKindOfClass:NSString.class]
			? info[@"localPath"] : @"";
	return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

- (void)shareFile {
	NSString *path = [self localPath];
	if (!path.length)
		return;
	UIActivityViewController *share = [[UIActivityViewController alloc]
			initWithActivityItems:@[[NSURL fileURLWithPath:path]]
			applicationActivities:nil];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad &&
		[share respondsToSelector:@selector(popoverPresentationController)]){
		share.popoverPresentationController.sourceView = self.view;
		share.popoverPresentationController.sourceRect = self.view.bounds;
	}
	[self presentViewController:share animated:YES completion:nil];
}

- (void)saveFile {
	NSString *path = [self localPath];
	if (!path.length)
		return;
	NSString *extension = path.pathExtension.lowercaseString;
	if ([extension isEqualToString:@"mp4"] || [extension isEqualToString:@"mov"] ||
		[extension isEqualToString:@"m4v"]){
		UISaveVideoAtPathToSavedPhotosAlbum(path, self,
				@selector(video:didFinishSavingWithError:contextInfo:), NULL);
		return;
	}
	UIImage *image = [UIImage imageWithContentsOfFile:path];
	if (!image && [extension isEqualToString:@"webp"])
		image = [UIImage convertFromWebP:path compressedData:nil error:nil];
	if (!image){
		[TGAlertSheet showMessage:@"This file is not a picture or a video."
							  title:@"Save" inView:self.view];
		return;
	}
	UIImageWriteToSavedPhotosAlbum(image, self,
			@selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
	[TGAlertSheet showMessage:(error ? @"Could not save" : @"Saved to Camera Roll")
						 title:nil inView:self.view];
}

- (void)video:(NSString *)path didFinishSavingWithError:(NSError *)error
   contextInfo:(void *)contextInfo {
	[TGAlertSheet showMessage:(error ? @"Could not save" : @"Saved to Camera Roll")
						 title:nil inView:self.view];
}

@end

// vim:ft=objc
