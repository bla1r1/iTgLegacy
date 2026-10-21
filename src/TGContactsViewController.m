#import "TGContactsViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kContactAvatar = 40.0f;

@interface TGContactsViewController ()
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSMutableDictionary *photos;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *photosRequested;
@end

@implementation TGContactsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Contacts";
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.users = @[];
	self.photos = [NSMutableDictionary dictionary];
	self.photosRequested = [NSMutableSet set];
	self.tableView.rowHeight = 56;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	__weak typeof(self) weakContacts = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		TGContactsViewController *me = weakContacts;
		[TGIcons flush];
		me.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		me.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[[TGTheme shared] styleNavigationBar:me.navigationController.navigationBar];
		[me.tableView reloadData];
	}];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.users = [users sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
			return [a[@"first_name"] localizedCaseInsensitiveCompare:b[@"first_name"]];
		}];
		[me.tableView reloadData];
		[me fetchMissingPhotos];
	}];
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self.tableView selector:@selector(reloadData) object:nil];
	[self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.05];
}

- (void)fetchMissingPhotos {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *u in self.users){
		NSNumber *fileId = u[@"photoFileId"];
		if (![fileId isKindOfClass:NSNumber.class]) continue;
		if (self.photos[fileId] || [self.photosRequested containsObject:fileId])
			continue;
		[self.photosRequested addObject:fileId];

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				UIImage *photo = [UIImage imageWithContentsOfFile:path];
				if (!photo) return;
				
				// A cell's own imageView takes the image's size, so a 160px photo
				// would shove the name off the row. Scale once, on arrival.
				UIGraphicsBeginImageContextWithOptions(
						CGSizeMake(kContactAvatar, kContactAvatar), NO, 0);
				[photo drawInRect:CGRectMake(0, 0, kContactAvatar, kContactAvatar)];
				UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();
				
				dispatch_async(dispatch_get_main_queue(), ^{
					TGContactsViewController *me = weakSelf;
					if (!me) return;
					me.photos[fileId] = scaled;
					[me reloadTableDebounced];
				});
			});
		}];
	}
}

static NSString *TGContactName(NSDictionary *u) {
	NSString *first = u[@"first_name"] ?: @"";
	NSString *last  = u[@"last_name"] ?: @"";
	NSString *name  = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (name.length)
		return name;
	if ([u[@"username"] length])
		return [NSString stringWithFormat:@"@%@", u[@"username"]];
	return u[@"phone"] ?: @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.users.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *u = self.users[indexPath.row];
	NSString *name = TGContactName(u);
	UIColor *bg = [[TGTheme shared] listBackgroundColour];
	cell.backgroundColor = bg;
	cell.textLabel.backgroundColor = bg;
	cell.textLabel.opaque = YES;
	cell.textLabel.text = name;
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.detailTextLabel.backgroundColor = bg;
	cell.detailTextLabel.opaque = YES;
	cell.detailTextLabel.text = [u[@"phone"] length]
		? [NSString stringWithFormat:@"+%@", u[@"phone"]] : @"";
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	NSNumber *fileId = u[@"photoFileId"];
	UIImage *photo = [fileId isKindOfClass:NSNumber.class] ? self.photos[fileId] : nil;
	if (!photo)
		photo = [TGIcons avatarWithInitials:
					(name.length ? [name substringToIndex:1].uppercaseString : @"?")
									   size:kContactAvatar
								   colourId:[u[@"id"] longLongValue]];
	cell.imageView.image = photo;
	cell.imageView.layer.cornerRadius = kContactAvatar / 2;
	cell.imageView.clipsToBounds = YES;
	cell.imageView.layer.shouldRasterize = YES;
	cell.imageView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *u = self.users[indexPath.row];
	NSString *name = TGContactName(u);
	__weak typeof(self) weakSelf = self;

	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me || chatId == 0)
			return;
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = name;
		vc.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// vim:ft=objc
