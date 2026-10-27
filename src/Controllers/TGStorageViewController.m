#import "TGStorageViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

// Their storage page opens with a ring: the total in the middle, one arc per
// kind of file, the same colours in the list underneath. A column of numbers
// says the same thing and none of it at a glance.
static const CGFloat kRingSide  = TGMetricStorageRingSide;
static const CGFloat kRingWidth = TGMetricStorageRingWidth;
/// Room under the ring for the total it holds, and the box that total is set
/// in - a line and a half, because it is two lines when the figure is long.
static const CGFloat kRingHeaderRoom = 54.0f;
static const CGFloat kRingTotalLine  = TGMetricVoicePillWidth;

@interface TGStorageViewController ()
@property (nonatomic, strong) NSArray *categories;   // name / bytes / kinds
@property (nonatomic, assign) long long total;
@property (nonatomic, assign) BOOL working;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation TGStorageViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Storage Usage";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.categories = @[];
	[self applyTheme];
	[self refresh];

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
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (void)refresh {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageBreakdownWithCompletion:^(NSArray *categories,
														long long total){
		weakSelf.categories = categories;
		weakSelf.total = total;
		weakSelf.loaded = YES;
		[weakSelf.tableView reloadData];
	}];
}

static NSString *TGHumanSize(long long bytes) {
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	if (bytes < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024 * 1024)];
}

/// Telegram's own chart palette, in the order their storage page uses it.
static UIColor *TGSliceColour(NSUInteger index) {
	NSArray *palette = [[TGTheme shared] chartPalette];
	return palette[index % palette.count];
}

#pragma mark - the ring

- (UIView *)ringHeader {
	TGTheme *theme = [TGTheme shared];
	CGFloat width = self.tableView.bounds.size.width ?: 320;
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, width, kRingSide + kRingHeaderRoom)];
	header.backgroundColor = [UIColor clearColor];

	CGRect box = CGRectMake(TGCenteredOrigin(width, kRingSide), TGMetricPad,
			kRingSide, kRingSide);
	CGPoint centre = CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box));
	CGFloat radius = TGHalf(kRingSide - kRingWidth);

	if (self.total > 0){
		CGFloat start = -M_PI_2;   // twelve o'clock, the way theirs starts
		for (NSUInteger i = 0; i < self.categories.count; i++){
			double share = [self.categories[i][@"bytes"] longLongValue] /
					(double)self.total;
			if (share <= 0)
				continue;
			CGFloat end = start + (CGFloat)(share * 2 * M_PI);

			CAShapeLayer *slice = [CAShapeLayer layer];
			slice.path = [UIBezierPath bezierPathWithArcCenter:centre radius:radius
					startAngle:start endAngle:end clockwise:YES].CGPath;
			slice.fillColor = [UIColor clearColor].CGColor;
			slice.strokeColor = TGSliceColour(i).CGColor;
			slice.lineWidth = kRingWidth;
			[header.layer addSublayer:slice];
			start = end;
		}
	} else {
		CAShapeLayer *empty = [CAShapeLayer layer];
		empty.path = [UIBezierPath bezierPathWithArcCenter:centre radius:radius
				startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
		empty.fillColor = [UIColor clearColor].CGColor;
		empty.strokeColor = [theme separatorColour].CGColor;
		empty.lineWidth = kRingWidth;
		[header.layer addSublayer:empty];
	}

	UILabel *totalLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(box.origin.x, centre.y - TGHalf(kRingTotalLine), kRingSide,
					kRingTotalLine)];
	totalLabel.text = self.loaded ? TGHumanSize(self.total) : @"...";
	totalLabel.font = TGFontTitle();
	totalLabel.textAlignment = NSTextAlignmentCenter;
	totalLabel.textColor = [theme primaryTextColour];
	totalLabel.backgroundColor = [UIColor clearColor];
	totalLabel.adjustsFontSizeToFitWidth = YES;
	[header addSubview:totalLabel];

	UILabel *caption = [[UILabel alloc] initWithFrame:
			CGRectMake(TGMetricPadMedium, kRingSide + TGMetricPadLarge,
					width - TGDoubled(TGMetricPadMedium), TGMetricLineRow)];
	caption.text = self.loaded
			? @"Telegram's cache on this device."
			: @"Reading the database...";
	caption.font = TGFontCaption();
	caption.textAlignment = NSTextAlignmentCenter;
	caption.textColor = [theme secondaryTextColour];
	caption.backgroundColor = [UIColor clearColor];
	[header addSubview:caption];

	return header;
}

/// A filled disc in the slice's colour, standing in for their tick.
- (UIImage *)dotOfColour:(UIColor *)colour {
	CGFloat side = 22;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	[colour setFill];
	[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
	UIImage *dot = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return dot;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	return section == 0 ? [self ringHeader] : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return section == 0 ? kRingSide + 54 : 24;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != 1)
		return nil;
	return @"Media stays in Telegram's cloud and is downloaded again when you "
		   @"open the message. Nothing is deleted from Telegram.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0)
		return self.loaded ? MAX((NSUInteger)1, self.categories.count) : 1;
	return 1;    // clear everything
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	TGTheme *theme = [TGTheme shared];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"row"];
	[theme styleCell:cell];
	cell.imageView.image = nil;
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.detailTextLabel.font = TGFontBody();
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;

	if (path.section == 1){
		cell.textLabel.text = self.working
				? @"Clearing..."
				: [NSString stringWithFormat:@"Clear All Cache  %@",
						TGHumanSize(self.total)];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.textLabel.textColor = self.working
				? [theme secondaryTextColour] : [theme accentColour];
		cell.detailTextLabel.text = @"";
		return cell;
	}

	if (!self.loaded){
		cell.textLabel.text = @"Reading...";
		cell.textLabel.textColor = [theme secondaryTextColour];
		cell.detailTextLabel.text = @"";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	if (!self.categories.count){
		cell.textLabel.text = @"Nothing cached";
		cell.textLabel.textColor = [theme secondaryTextColour];
		cell.detailTextLabel.text = @"";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSDictionary *category = self.categories[path.row];
	long long bytes = [category[@"bytes"] longLongValue];
	double share = self.total > 0 ? (bytes / (double)self.total) * 100 : 0;
	cell.textLabel.text = [NSString stringWithFormat:@"%@  %.1f%%",
			category[@"name"], share];
	cell.detailTextLabel.text = TGHumanSize(bytes);
	cell.imageView.image = [self dotOfColour:TGSliceColour(path.row)];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (self.working || !self.loaded)
		return;

	if (path.section == 1){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"%@ of cached media will be removed from this device.",
						TGHumanSize(self.total)]
							title:@"Clear All Cache"
						   action:@"Clear"
					  destructive:YES
						   inView:self.view
						onConfirm:^{ [weakSelf clearKinds:@[]]; }];  // empty means every type
		return;
	}

	if (!self.categories.count)
		return;
	NSDictionary *category = self.categories[path.row];
	if (![category[@"kinds"] count])
		return;               // "Other" is whatever the walk could not name

	[self clearKinds:category[@"kinds"]];
}

- (void)clearKinds:(NSArray *)kinds {
	self.working = YES;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearCacheOfTypes:kinds completion:^(long long freed){
		weakSelf.working = NO;
		[weakSelf refresh];
		[TGAlertSheet showMessage:[NSString stringWithFormat:@"Freed %@.",
						TGHumanSize(freed)]
							title:@"Storage" inView:weakSelf.view];
	}];
}

@end

// vim:ft=objc
