#import "TGFileToolsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// The progress row draws a bar under the stage label. A stock cell puts the
/// label where the bar wants to be, so the two are laid out here once.
@interface TGFileProgressCell : UITableViewCell
@property (nonatomic, strong) UIProgressView *bar;
@end

@implementation TGFileProgressCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		self.bar = [[UIProgressView alloc]
				initWithProgressViewStyle:UIProgressViewStyleDefault];
		self.bar.progressTintColor = [[TGTheme shared] accentColour];
		[self.contentView addSubview:self.bar];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.contentView.bounds;
	CGFloat inset = TGMetricPadLarge;
	self.textLabel.frame = CGRectMake(inset, 0, bounds.size.width - TGDoubled(inset),
			TGMetricLineRow + TGMetricPadSmall);
	self.bar.frame = CGRectMake(inset,
			TGCenteredOrigin(bounds.size.height, TGMetricLineMicro),
			bounds.size.width - TGDoubled(inset), TGMetricLineMicro);
}

@end

@interface TGFileToolsViewController ()
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) float progress;
@property (nonatomic, copy) NSString *stage;
@property (nonatomic, assign) NSInteger fileId;
@property (nonatomic, copy) NSString *generatedPath;
@property (nonatomic, assign) long long generatedSize;
@property (nonatomic, copy) NSString *preview;
@end

@implementation TGFileToolsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"File Tools";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.stage = @"Ready";
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
	[self applyTheme];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf applyTheme];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	// The generation has its own progress block, but an upload that continues
	// past the generated file answering is only visible through updateFile.
	__weak typeof(self) weakSelf = self;
	[TGClient shared].onFileUploadProgress = ^(NSInteger fileId, float progress){
		TGFileToolsViewController *me = weakSelf;
		if (!me || me.fileId != fileId)
			return;
		me.progress = progress;
		me.stage = @"Uploading";
		[me.tableView reloadData];
	};
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[TGClient shared].onFileUploadProgress = nil;
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
}

- (BOOL)hasTransfer {
	return self.busy || self.fileId > 0;
}

- (BOOL)hasResult {
	return self.generatedPath.length > 0;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1 + (self.hasTransfer ? 1 : 0) + (self.hasResult ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return @"Generate and Upload";
	if (section == 1 && self.hasTransfer)
		return @"Transfer";
	return self.hasResult ? @"Generated File" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0)
		return @"TDLib asks this app for the bytes through updateFileGenerationStart. "
			   @"The file is written part by part, finished, and uploaded with "
			   @"preliminaryUploadFile - the same path a recording takes before it "
			   @"is sent. Cancel stops the upload.";
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return 1;
	if (section == 1 && self.hasTransfer)
		return 2;
	return self.hasResult ? 3 : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1 && indexPath.row == 0)
		return TGMetricRow + TGMetricLineMicro;
	return TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TGTheme *theme = [TGTheme shared];
	NSString *reuse = @"fileTools";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:reuse];
	[theme styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme cellDetailColour];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (indexPath.section == 0){
		cell.textLabel.text = self.busy ? @"Generating..." : @"Generate and Upload a File";
		cell.textLabel.textColor = self.busy
				? [theme secondaryTextColour] : [theme accentColour];
		cell.selectionStyle = self.busy
				? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
		return cell;
	}

	if (indexPath.section == 1){
		if (indexPath.row == 1){
			cell.textLabel.text = self.busy ? @"Cancel Upload" : @"Clear";
			cell.textLabel.textColor = [theme destructiveColour];
			cell.textLabel.textAlignment = NSTextAlignmentCenter;
			cell.selectionStyle = UITableViewCellSelectionStyleDefault;
			return cell;
		}

		TGFileProgressCell *progressCell = [tableView
				dequeueReusableCellWithIdentifier:@"fileProgress"];
		if (!progressCell)
			progressCell = [[TGFileProgressCell alloc]
					initWithStyle:UITableViewCellStyleDefault
				   reuseIdentifier:@"fileProgress"];
		[theme styleCell:progressCell];
		progressCell.textLabel.font = TGFontBody();
		progressCell.textLabel.textColor = [theme primaryTextColour];
		progressCell.textLabel.text = [NSString stringWithFormat:@"%@  %d%%",
				self.stage ?: @"Working", (int)(self.progress * 100)];
		progressCell.bar.progress = self.progress;
		progressCell.bar.progressTintColor = [theme accentColour];
		progressCell.selectionStyle = UITableViewCellSelectionStyleNone;
		return progressCell;
	}

	if (indexPath.row == 0){
		cell.textLabel.text = @"Path";
		cell.detailTextLabel.text = self.generatedPath;
	} else if (indexPath.row == 1){
		cell.textLabel.text = @"Size";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld bytes",
				self.generatedSize];
	} else {
		cell.textLabel.numberOfLines = 3;
		cell.textLabel.font = TGFontCaption();
		cell.textLabel.text = self.preview.length
				? [self.preview stringByReplacingOccurrencesOfString:@"\n"
														 withString:@" "]
				: @"Tap to read the first bytes back.";
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0){
		if (self.busy)
			return;
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Generate a File"
						message:@"A text file is written through TDLib's file-generation "
								@"API and uploaded preliminarily. The upload stops short of "
								@"a message, which is what preliminary means."
					placeholder:@"File name"
						   text:@"legacy-note.txt"
						 action:@"Create"
						 inView:self.view
					   onSubmit:^(NSString *name){
			[weakSelf startGenerationWithName:name];
		}];
		return;
	}

	if (indexPath.section == 1){
		if (indexPath.row == 0)
			return;
		if (self.busy){
			[[TGClient shared] cancelPreliminaryUploadOfFile:self.fileId];
			self.busy = NO;
			self.stage = @"Cancelled";
			self.progress = 0;
			self.fileId = 0;
		} else {
			self.generatedPath = nil;
			self.preview = nil;
			self.fileId = 0;
			self.generatedSize = 0;
			self.stage = @"Ready";
		}
		[self.tableView reloadData];
		return;
	}

	if (indexPath.section == 2 && indexPath.row == 2)
		[self readPreview];
}

#pragma mark - generation

- (void)startGenerationWithName:(NSString *)name {
	NSMutableString *contents = [NSMutableString string];
	[contents appendString:@"LegacyTG generated file\n"];
	[contents appendFormat:@"Name: %@\n", name];
	[contents appendFormat:@"Created: %@\n\n", [NSDate date]];
	[contents appendString:@"This text was written to TDLib part by part through "
					   @"writeGeneratedFilePart and setFileGenerationProgress, then "
					   @"handed to preliminaryUploadFile.\n"];
	for (NSUInteger i = 0; i < 80; i++)
		[contents appendFormat:@"Line %lu - the file generator keeps writing so the "
						  @"progress bar has more than one part to move.\n",
						  (unsigned long)(i + 1)];

	self.busy = YES;
	self.progress = 0;
	self.stage = @"Preparing";
	self.fileId = 0;
	self.generatedPath = nil;
	self.generatedSize = 0;
	self.preview = nil;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] generateTextFileNamed:name contents:contents
			progress:^(NSInteger fileId, float progress, NSString *stage){
		TGFileToolsViewController *me = weakSelf;
		if (!me)
			return;
		if (fileId > 0)
			me.fileId = fileId;
		me.progress = progress;
		me.stage = stage;
		[me.tableView reloadData];
	} completion:^(NSInteger fileId, NSString *path, NSError *error){
		TGFileToolsViewController *me = weakSelf;
		if (!me)
			return;
		me.busy = NO;
		if (error){
			me.fileId = 0;
			me.stage = @"Stopped";
			me.progress = 0;
			[me.tableView reloadData];
			[TGAlertSheet showMessage:error.localizedDescription
								 title:@"File Tools" inView:me.view];
			return;
		}
		me.fileId = fileId;
		me.generatedPath = path;
		me.stage = @"Uploading";
		NSDictionary *attributes = [[NSFileManager defaultManager]
				attributesOfItemAtPath:path error:nil];
		me.generatedSize = [attributes[NSFileSize] longLongValue];
		[me.tableView reloadData];
		[me readPreview];
	}];
}

- (void)readPreview {
	if (self.fileId <= 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] readFilePartOfFile:self.fileId offset:0 count:320
							   completion:^(NSData *data){
		TGFileToolsViewController *me = weakSelf;
		if (!me)
			return;
		NSString *text = data.length
				? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
				: nil;
		me.preview = text.length ? text : (data.length
				? @"(The first bytes are not text.)"
				: @"TDLib has not cached the first part yet.");
		[me.tableView reloadData];
	}];
}

@end

// vim:ft=objc
