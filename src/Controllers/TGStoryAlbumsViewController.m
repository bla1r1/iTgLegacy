#import "TGStoryAlbumsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGListViewController.h"
#import "TGStoryViewerViewController.h"
#import "TGIcons.h"

/// The album list draws the album record (id and name); its stories are read
/// only when the album opens, which is one request instead of N.
@interface TGStoryAlbumsViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t storyToAdd;
@property (nonatomic, strong) NSMutableArray *albums;
@end

/// One album's stories with add, remove and drag-to-order. Private because
/// no other screen should need the album id without going through the list.
@interface TGStoryAlbumDetailViewController : UITableViewController
- (instancetype)initWithChatId:(int64_t)chatId
					   albumId:(int32_t)albumId
						  name:(NSString *)name;
@end

@implementation TGStoryAlbumsViewController

- (instancetype)initWithChatId:(int64_t)chatId storyToAdd:(int32_t)storyId {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_chatId = chatId;
		_storyToAdd = storyId;
		_albums = [NSMutableArray array];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"Story Albums";
	[[TGTheme shared] styleGroupedTable:self.tableView];
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
				target:self action:@selector(createAlbum)],
		self.editButtonItem,
	];
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf.tableView reloadData];
	}];
	[self reloadAlbums];
}

- (void)reloadAlbums {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storyAlbumsForChat:self.chatId completion:^(NSArray *albums){
		TGStoryAlbumsViewController *me = weakSelf;
		if (!me)
			return;
		me.albums = [albums mutableCopy] ?: [NSMutableArray array];
		[me.tableView reloadData];
	}];
}

- (void)createAlbum {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"New Album"
					message:@"1 to 12 characters."
				placeholder:@"Album name"
					   text:nil
					 action:@"Create"
					 inView:self.view
				   onSubmit:^(NSString *name){
		TGStoryAlbumsViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] createStoryAlbumNamed:name
										  inChat:me.chatId
										storyIds:@[]
									  completion:^(NSDictionary *album, NSString *error){
			if (!album){
				[TGAlertSheet showMessage:error ?: @"Telegram refused the album."
									title:@"New Album" inView:me.view];
				return;
			}
			[me reloadAlbums];
		}];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.albums.count ?: 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return self.albums.count ? @"Drag an album to change its order. Swipe to delete."
							 : @"No story albums yet. Add one with +.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"album"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"album"];
	[[TGTheme shared] styleCell:cell];
	if (!self.albums.count){
		cell.textLabel.text = @"No Albums";
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}
	NSDictionary *album = self.albums[indexPath.row];
	cell.textLabel.text = album[@"name"] ?: @"Album";
	cell.detailTextLabel.text = self.storyToAdd
			? @"Tap to add the story here" : @"Tap to open";
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.font = TGFontSubhead();
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	NSNumber *photoId = album[@"photoFileId"];
	if ([photoId isKindOfClass:NSNumber.class] && photoId.integerValue > 0){
		__weak UITableViewCell *weakCell = cell;
		[[TGClient shared] downloadFile:photoId.integerValue
							   priority:TGDownloadPriorityOnScreen
							 completion:^(NSString *path){
			[weakCell.imageView setImage:path.length
					? [UIImage imageWithContentsOfFile:path] : nil];
			[weakCell setNeedsLayout];
		}];
	} else {
		cell.imageView.image = [TGIcons avatarWithInitials:@"A"
													 size:TGMetricListAvatar
												 colourId:[album[@"albumId"] longLongValue]];
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.albums.count)
		return;
	NSDictionary *album = self.albums[indexPath.row];
	int32_t albumId = [album[@"albumId"] intValue];
	if (self.storyToAdd){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:[NSString stringWithFormat:@"Add the story to %@?",
				album[@"name"] ?: @"this album"]
							title:@"Story Album"
						   action:@"Add"
					  destructive:NO
						   inView:self.view
						onConfirm:^{
			TGStoryAlbumsViewController *me = weakSelf;
			if (!me)
				return;
			[[TGClient shared] addStories:@[@(me.storyToAdd)]
								toAlbum:albumId
								 inChat:me.chatId
							 completion:^(NSDictionary *changed, NSString *error){
				if (!changed){
					[TGAlertSheet showMessage:error ?: @"Telegram refused that."
										title:@"Story Album" inView:me.view];
					return;
				}
				[me.navigationController popViewControllerAnimated:YES];
			}];
		}];
		return;
	}
	TGStoryAlbumDetailViewController *detail = [[TGStoryAlbumDetailViewController alloc]
			initWithChatId:self.chatId albumId:albumId name:album[@"name"] ?: @"Album"];
	detail.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:detail animated:YES];
}

#pragma mark - editing

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.row < (NSInteger)self.albums.count;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
			  toIndexPath:(NSIndexPath *)destinationIndexPath {
	NSMutableArray *albums = self.albums;
	NSDictionary *album = albums[sourceIndexPath.row];
	[albums removeObjectAtIndex:sourceIndexPath.row];
	[albums insertObject:album atIndex:MIN(destinationIndexPath.row,
										   (NSInteger)albums.count)];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *item in albums)
		[ids addObject:item[@"albumId"] ?: @(0)];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reorderStoryAlbums:ids inChat:self.chatId
							   completion:^(BOOL ok, NSString *error){
		if (!ok){
			TGStoryAlbumsViewController *me = weakSelf;
			[TGAlertSheet showMessage:error ?: @"Telegram refused the order."
								title:@"Story Albums" inView:me.view];
			[me reloadAlbums];
		}
	}];
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete ||
		indexPath.row >= (NSInteger)self.albums.count)
		return;
	NSDictionary *album = self.albums[indexPath.row];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteStoryAlbum:[album[@"albumId"] intValue]
								 inChat:self.chatId
							 completion:^(BOOL ok, NSString *error){
		TGStoryAlbumsViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:error ?: @"Telegram refused the delete."
								title:@"Story Albums" inView:me.view];
			return;
		}
		[me reloadAlbums];
	}];
}

@end

#pragma mark - one album

@interface TGStoryAlbumDetailViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t albumId;
@property (nonatomic, copy) NSString *albumName;
@property (nonatomic, strong) NSMutableArray *stories;
@end

@implementation TGStoryAlbumDetailViewController

- (instancetype)initWithChatId:(int64_t)chatId
					   albumId:(int32_t)albumId
						  name:(NSString *)name {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_chatId = chatId;
		_albumId = albumId;
		_albumName = [name copy] ?: @"Album";
		_stories = [NSMutableArray array];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.albumName;
	[[TGTheme shared] styleGroupedTable:self.tableView];
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
				target:self action:@selector(addStory)],
		[[UIBarButtonItem alloc] initWithTitle:@"More" style:UIBarButtonItemStylePlain
				target:self action:@selector(albumMenu)],
		self.editButtonItem,
	];
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf.tableView reloadData];
	}];
	[self reloadStories];
}

- (void)reloadStories {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storiesInAlbum:self.albumId inChat:self.chatId
								offset:0 limit:60
							completion:^(NSArray *stories, NSString *error){
		TGStoryAlbumDetailViewController *me = weakSelf;
		if (!me)
			return;
		me.stories = [stories mutableCopy] ?: [NSMutableArray array];
		[me.tableView reloadData];
		if (error.length)
			[TGAlertSheet showMessage:error title:@"Story Album" inView:me.view];
	}];
}

- (void)albumMenu {
	NSArray *choices = @[@"Rename Album", @"Delete Album"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:self.albumName destructiveIndex:1
					   inView:self.view onChoice:^(NSInteger choice){
		TGStoryAlbumDetailViewController *me = weakSelf;
		if (!me)
			return;
		if (choice == 0){
			[me renameAlbum];
			return;
		}
		[TGAlertSheet showConfirm:@"Delete this album? The stories stay."
							title:@"Delete Album"
						   action:@"Delete"
					  destructive:YES
						   inView:me.view
						onConfirm:^{
			[[TGClient shared] deleteStoryAlbum:me.albumId
										 inChat:me.chatId
									 completion:^(BOOL ok, NSString *error){
				if (!ok){
					[TGAlertSheet showMessage:error ?: @"Telegram refused the delete."
										title:@"Story Album" inView:me.view];
					return;
				}
				[me.navigationController popViewControllerAnimated:YES];
			}];
		}];
	}];
}

- (void)renameAlbum {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Rename Album"
					message:@"1 to 12 characters."
				placeholder:@"Album name"
					   text:self.albumName
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *name){
		TGStoryAlbumDetailViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] setStoryAlbumName:name
									 albumId:me.albumId
									  inChat:me.chatId
								  completion:^(NSDictionary *album, NSString *error){
			if (!album){
				[TGAlertSheet showMessage:error ?: @"Telegram refused the rename."
									title:@"Story Album" inView:me.view];
				return;
			}
			me.albumName = album[@"name"] ?: name;
			me.title = me.albumName;
			[me.tableView reloadData];
		}];
	}];
}

- (void)addStory {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archivedStoryIdsForChat:self.chatId fromStoryId:0 limit:30
								   completion:^(NSArray *storyIds, NSString *error){
		TGStoryAlbumDetailViewController *me = weakSelf;
		if (!me)
			return;
		if (!storyIds.count){
			[TGAlertSheet showMessage:error ?: @"Telegram returned no stories to add."
								title:@"Album Stories" inView:me.view];
			return;
		}
		NSMutableArray *wanted = [NSMutableArray array];
		for (NSNumber *storyId in storyIds){
			BOOL already = NO;
			for (NSDictionary *story in me.stories)
				if ([story[@"storyId"] isEqualToNumber:storyId]){
					already = YES;
					break;
				}
			if (!already)
				[wanted addObject:storyId];
		}
		if (!wanted.count){
			[TGAlertSheet showMessage:@"Every available story is already in this album."
								title:@"Album Stories" inView:me.view];
			return;
		}
		NSMutableArray *titles = [NSMutableArray array];
		for (NSNumber *storyId in wanted)
			[titles addObject:[NSString stringWithFormat:@"Story %@", storyId]];
		[TGAlertSheet showChoices:titles title:@"Add Story" destructiveIndex:-1
						   inView:me.view onChoice:^(NSInteger choice){
			if (choice < 0 || choice >= (NSInteger)wanted.count)
				return;
			[[TGClient shared] addStories:@[wanted[choice]]
								toAlbum:me.albumId
								 inChat:me.chatId
							 completion:^(NSDictionary *album, NSString *error){
				if (!album){
					[TGAlertSheet showMessage:error ?: @"Telegram refused that."
										title:@"Album Stories" inView:me.view];
					return;
				}
				[me reloadStories];
			}];
		}];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.stories.count ?: 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return self.stories.count
			? @"Swipe a story to remove it. Drag to change the album order."
			: @"This album has no stories yet.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"albumStory"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"albumStory"];
	[[TGTheme shared] styleCell:cell];
	if (!self.stories.count){
		cell.textLabel.text = @"No Stories";
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	NSDictionary *story = self.stories[indexPath.row];
	cell.textLabel.text = story[@"caption"];
	if (!cell.textLabel.text.length)
		cell.textLabel.text = [story[@"isVideo"] boolValue] ? @"Video story" : @"Photo story";
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld views · %@",
			(long)[story[@"viewers"] integerValue],
			[story[@"date"] isKindOfClass:NSNumber.class]
					? [NSDateFormatter localizedStringFromDate:
							[NSDate dateWithTimeIntervalSince1970:
									[story[@"date"] doubleValue]]
							dateStyle:NSDateFormatterShortStyle
							timeStyle:NSDateFormatterShortStyle]
					: @"-"];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	NSNumber *photoId = story[@"thumbPhotoId"] ?: story[@"photoId"];
	if ([photoId isKindOfClass:NSNumber.class] && photoId.integerValue > 0){
		__weak UITableViewCell *weakCell = cell;
		[[TGClient shared] downloadFile:photoId.integerValue
							   priority:TGDownloadPriorityOnScreen
							 completion:^(NSString *path){
			UIImage *image = path.length ? [UIImage imageWithContentsOfFile:path] : nil;
			[weakCell.imageView setImage:image];
			[weakCell setNeedsLayout];
		}];
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.stories.count)
		return;
	NSDictionary *story = self.stories[indexPath.row];
	TGStoryViewerViewController *viewer = [[TGStoryViewerViewController alloc]
			initWithChatId:self.chatId
					 title:self.albumName
				   stories:self.stories
				startIndex:indexPath.row
				 canManage:YES];
	viewer.hidesBottomBarWhenPushed = YES;
	viewer.onStoriesChanged = ^{
		[tableView reloadData];
	};
	[self.navigationController pushViewController:viewer animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.row < (NSInteger)self.stories.count;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
			  toIndexPath:(NSIndexPath *)destinationIndexPath {
	NSDictionary *story = self.stories[sourceIndexPath.row];
	[self.stories removeObjectAtIndex:sourceIndexPath.row];
	[self.stories insertObject:story atIndex:MIN(destinationIndexPath.row,
												 (NSInteger)self.stories.count)];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *item in self.stories)
		[ids addObject:item[@"storyId"] ?: @(0)];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reorderStories:ids inAlbum:self.albumId inChat:self.chatId
						   completion:^(NSDictionary *album, NSString *error){
		TGStoryAlbumDetailViewController *me = weakSelf;
		if (!album){
			[TGAlertSheet showMessage:error ?: @"Telegram refused the order."
								title:@"Album Stories" inView:me.view];
			[me reloadStories];
		}
	}];
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete ||
		indexPath.row >= (NSInteger)self.stories.count)
		return;
	NSDictionary *story = self.stories[indexPath.row];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] removeStories:@[story[@"storyId"] ?: @(0)]
						   fromAlbum:self.albumId
							  inChat:self.chatId
						  completion:^(NSDictionary *album, NSString *error){
		TGStoryAlbumDetailViewController *me = weakSelf;
		if (!album){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Album Stories" inView:me.view];
			return;
		}
		[me reloadStories];
	}];
}

@end
