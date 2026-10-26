#import "TGForwardPicker.h"
#import "TGClient.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"


@interface TGForwardPicker ()
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@end

@implementation TGForwardPicker

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Forward to";
	self.chats = [TGClient shared].chats ?: @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];

	self.tableView.rowHeight = 56;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
								 target:self action:@selector(cancel)];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		TGForwardPicker *me = weakSelf;
		if (!me) return;
		[TGIcons flush];
		me.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		me.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[[TGTheme shared] styleNavigationBar:me.navigationController.navigationBar];
		[me.tableView reloadData];
	}];

	[self fetchMissingAvatars];
}

- (void)cancel {
	if (self.navigationController && self.navigationController.viewControllers.count > 1 &&
		self.navigationController.viewControllers.firstObject != self){
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self.tableView selector:@selector(reloadData) object:nil];
	[self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.05];
}

- (void)fetchMissingAvatars {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *c in self.chats){
		NSNumber *fileId = c[@"photoFileId"];
		if (![fileId isKindOfClass:NSNumber.class] || self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
			continue;
		[self.avatarsRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			if (!path.length) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				UIImage *photo = [UIImage imageWithContentsOfFile:path];
				if (!photo) return;

				UIGraphicsBeginImageContextWithOptions(CGSizeMake(TGMetricListAvatar, TGMetricListAvatar), NO, 0);
				[photo drawInRect:CGRectMake(0, 0, TGMetricListAvatar, TGMetricListAvatar)];
				UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();

				dispatch_async(dispatch_get_main_queue(), ^{
					TGForwardPicker *me = weakSelf;
					if (!me) return;
					me.avatars[fileId] = scaled;
					[me reloadTableDebounced];
				});
			});
		}];
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGForwardCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *c = self.chats[indexPath.row];
	NSString *title = c[@"title"] ?: @"";
	UIColor *bg = [[TGTheme shared] listBackgroundColour];

	cell.backgroundColor = bg;
	cell.contentView.backgroundColor = bg;

	cell.textLabel.text = title;
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.textLabel.backgroundColor = bg;
	cell.textLabel.opaque = YES;

	cell.detailTextLabel.text = c[@"text"] ?: @"";
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.detailTextLabel.backgroundColor = bg;
	cell.detailTextLabel.opaque = YES;

	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = [fileId isKindOfClass:NSNumber.class] ? self.avatars[fileId] : nil;
	if ([c[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:TGMetricListAvatar];

	if (!photo){
		NSString *initials = title.length ? [title substringToIndex:1].uppercaseString : @"?";
		photo = [TGIcons avatarWithInitials:initials
									   size:TGMetricListAvatar
								   colourId:[c[@"id"] longLongValue]];
	}

	cell.imageView.image = photo;
	cell.imageView.layer.cornerRadius = TGMetricListAvatar / 2;
	cell.imageView.clipsToBounds = YES;
	cell.imageView.layer.shouldRasterize = YES;
	cell.imageView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	cell.imageView.contentMode = UIViewContentModeScaleAspectFill;

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.onPicked)
		self.onPicked([self.chats[indexPath.row][@"id"] longLongValue]);
	[self cancel];
}

@end

// vim:ft=objc
