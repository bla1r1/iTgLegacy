//
// TGProfilePhotosViewController - every profile photo an account still has,
// one to a row, with taking one off the account close by: the swipe, or the
// tap's confirm. The avatar tap is what leads here.
//
#import "TGProfilePhotosViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

@interface TGProfilePhotosViewController ()
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSArray *photos;   // @{"photoId", "fileId"}
@end

@implementation TGProfilePhotosViewController

- (instancetype)initWithUserId:(int64_t)userId {
	if ((self = [super initWithStyle:UITableViewStylePlain])){
		_userId = userId;
		_photos = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Profile Photos";
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

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

- (void)refresh {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userProfilePhotos:self.userId completion:^(NSArray *photos){
		weakSelf.photos = photos;
		[weakSelf.tableView reloadData];
	}];
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.photos.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	// Photos sit one to a row, at the size the avatar behind them is drawn.
	return TGMetricProfilePhotoRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:
			@"TGProfilePhoto"];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"TGProfilePhoto"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		CGFloat side = TGMetricProfilePhotoSide;
		CGFloat x = TGCenteredOrigin(UIScreen.mainScreen.bounds.size.width, side);
		UIImageView *image = [[UIImageView alloc] initWithFrame:
				CGRectMake(x, 20, side, side)];
		image.tag = 1;
		image.layer.cornerRadius = TGHalf(side);
		image.clipsToBounds = YES;
		image.contentMode = UIViewContentModeScaleAspectFill;
		image.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
				UIViewAutoresizingFlexibleRightMargin;
		[cell.contentView addSubview:image];

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadMedium, 130,
				UIScreen.mainScreen.bounds.size.width - TGDoubled(TGMetricPadMedium), 16)];
		label.tag = 2;
		label.font = TGFontMeta();
		label.textAlignment = NSTextAlignmentCenter;
		label.textColor = [[TGTheme shared] secondaryTextColour];
		label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[cell.contentView addSubview:label];
	}

	NSDictionary *photo = self.photos[indexPath.row];
	UIImageView *image = (UIImageView *)[cell.contentView viewWithTag:1];
	UILabel *label = (UILabel *)[cell.contentView viewWithTag:2];
	label.text = [NSString stringWithFormat:@"Photo %ld of %lu - swipe to remove",
			(long)(indexPath.row + 1), (unsigned long)self.photos.count];

	NSInteger fileId = [photo[@"fileId"] integerValue];
	image.image = [TGIcons avatarWithInitials:@"?" size:TGMetricProfilePhotoSide
									 colourId:[photo[@"photoId"] longLongValue]];
	if (fileId)
		[[TGClient shared] downloadFile:fileId
							   priority:TGDownloadPriorityAvatar
							 completion:^(NSString *path){
		[TGIcons loadImageAtPath:path into:image];
	}];
	return cell;
}

/// The swipe reveals a Delete button: the photo comes off the account, and
/// the row leaves the gallery with it.
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
						   editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView
	titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return @"Remove";
}

- (void)tableView:(UITableView *)tableView
	commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
   forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;
	NSDictionary *photo = self.photos[indexPath.row];
	int64_t photoId = [photo[@"photoId"] longLongValue];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"Photo %ld of %lu comes off this profile. The others stay.",
					(long)(indexPath.row + 1), (unsigned long)self.photos.count]
						title:@"Remove Photo"
					   action:@"Remove"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] deleteProfilePhoto:photoId completion:^(BOOL ok){
			if (!ok)
				return;
			NSMutableArray *fresh = [weakSelf.photos mutableCopy];
			[fresh removeObjectAtIndex:indexPath.row];
			weakSelf.photos = fresh;
			[weakSelf.tableView deleteRowsAtIndexPaths:@[indexPath]
									  withRowAnimation:UITableViewRowAnimationFade];
		}];
	}];
}

@end

// vim:ft=objc
