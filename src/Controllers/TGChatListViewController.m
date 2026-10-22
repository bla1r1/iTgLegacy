#import "TGChatListViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGContactsViewController.h"
#import "TGTopicsViewController.h"
#import "TGPopupMenu.h"
#import "TGSnackbar.h"
#import "TGSearchViewController.h"
#import <QuartzCore/QuartzCore.h>

// Standard Telegram iOS row and avatar metrics
static const CGFloat kRowHeight = 72.0f;
static const CGFloat kAvatar    = 52.0f;

#pragma mark - cell

@interface TGChatCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *tick;   // your own last message
@property (nonatomic, strong) UIImageView *pin;   // pinned to the top
@end

@implementation TGChatCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;

	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(10, (kRowHeight - kAvatar) / 2, kAvatar, kAvatar)];
	self.avatar.layer.cornerRadius = kAvatar / 2;
	self.avatar.clipsToBounds = YES;
	self.avatar.layer.shouldRasterize = YES;
	self.avatar.layer.rasterizationScale = scale;
	self.avatar.backgroundColor = [[TGTheme shared] fileTileColour];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:12];
	self.dateLabel.textColor = [[TGTheme shared] timeColour];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.dateLabel];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:13];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [[TGTheme shared] badgeColour];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.layer.cornerRadius = 10;
	self.badge.clipsToBounds = YES;
	self.badge.layer.shouldRasterize = YES;
	self.badge.layer.rasterizationScale = scale;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(10 + kAvatar - 14, (kRowHeight - kAvatar) / 2 + kAvatar - 14, 14, 14)];
	self.onlineDot.backgroundColor = [[TGTheme shared] onlineColour];
	self.onlineDot.layer.cornerRadius = 7;
	self.onlineDot.layer.borderWidth = 2;
	self.onlineDot.layer.shouldRasterize = YES;
	self.onlineDot.layer.rasterizationScale = scale;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	self.pin = [[UIImageView alloc] init];
	self.pin.contentMode = UIViewContentModeScaleAspectFit;
	self.pin.hidden = YES;
	[self.contentView addSubview:self.pin];

	self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat left = kAvatar + 20;
	CGFloat right = 78;   // room for date and the disclosure arrow

	self.dateLabel.frame  = CGRectMake(w - right, 10, right - 8, 16);
	self.titleLabel.frame = CGRectMake(left, 9, w - left - right, 20);
	self.previewLabel.frame = CGRectMake(left, 30, w - left - right + 40, 32);

	// Your own last message is marked, the way it is in their chat item.
	if (!self.tick.hidden){
		CGSize s = [self.dateLabel.text sizeWithFont:self.dateLabel.font];
		self.tick.frame = CGRectMake(w - 8 - s.width - 19, 13, 15, 9);
	}

	if (!self.badge.hidden){
		CGSize s = [self.badge.text sizeWithFont:self.badge.font];
		CGFloat bw = MAX(20, s.width + 12);
		self.badge.frame = CGRectMake(w - right + 30, 36, bw, 20);
	}
	if (!self.pin.hidden)
		self.pin.frame = CGRectMake(w - right + 34, 38, 16, 16);
}

@end

#pragma mark - controller

@interface TGChatListViewController () <UISearchBarDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, assign) BOOL showsArchive;      // this IS the archive screen
@property (nonatomic, assign) NSInteger folderId;     // 0 = no folder
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *searchResults;   // nil = not searching
@property (nonatomic, strong) NSDictionary *actionChat; // long-pressed row
@property (nonatomic, assign) int64_t chatPendingDeletion;
@property (nonatomic, assign) CGFloat headerHeight;
@end

@implementation TGChatListViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.showsArchive ? @"Archived" : @"Chats";
	if (!self.showsArchive)
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Folders" style:UIBarButtonItemStylePlain
					   target:self action:@selector(foldersTapped)];
	self.chats = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
				   target:self action:@selector(composeTapped)];

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	[self styleSearchBar];
	[self rebuildTableHeader];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	[self.tableView addGestureRecognizer:hold];

	self.tableView.rowHeight = kRowHeight;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	__weak typeof(self) weakSelf = self;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[[TGTheme shared] styleTabBar:self.tabBarController.tabBar];

	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		[TGIcons flush];
		[[TGTheme shared] styleNavigationBar:weakSelf.navigationController.navigationBar];
		weakSelf.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		weakSelf.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[[TGTheme shared] styleTabBar:weakSelf.tabBarController.tabBar];
		[weakSelf styleSearchBar];
		[weakSelf rebuildTableHeader];
		[weakSelf.tableView reloadData];
	}];

	[TGClient shared].onChatsChanged = ^{
		[weakSelf reload];
	};
	[TGClient shared].onArchiveChanged = ^{
		[weakSelf.tableView reloadData];
	};
	[TGClient shared].onConnectionState = ^(TGConnectionState state, NSString *text){
		weakSelf.title = text ?: @"Chats";
	};
	[self reload];
}

- (void)rebuildTableHeader {
	CGFloat width = self.tableView.bounds.size.width ?: 320;
	BOOL showArchive = !self.showsArchive && self.folderId == 0 &&
					   [TGClient shared].archivedChats.count > 0;
	CGFloat height = 44 + (showArchive ? kRowHeight : 0);
	UIColor *bg = [[TGTheme shared] listBackgroundColour];

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = bg;
	self.searchBar.frame = CGRectMake(0, 0, width, 44);
	[header addSubview:self.searchBar];

	if (showArchive){
		TGChatCell *row = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault
											reuseIdentifier:nil];
		row.frame = CGRectMake(0, 44, width, kRowHeight);
		row.backgroundColor = bg;
		row.contentView.backgroundColor = bg;
		row.titleLabel.text = @"Archived Chats";
		row.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
		row.titleLabel.backgroundColor = bg;
		row.previewLabel.text = [NSString stringWithFormat:@"%lu chats",
				(unsigned long)[TGClient shared].archivedChats.count];
		row.previewLabel.textColor = [[TGTheme shared] secondaryTextColour];
		row.previewLabel.backgroundColor = bg;
		row.dateLabel.backgroundColor = bg;
		row.avatar.image = [TGIcons archiveAvatarOfSide:kAvatar];
		row.avatar.backgroundColor = [UIColor clearColor];
		row.userInteractionEnabled = YES;
		[row addGestureRecognizer:[[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(openArchive)]];
		[row layoutSubviews];
		[header addSubview:row];

		UIView *hair = [[UIView alloc] initWithFrame:
				CGRectMake(0, height - 0.5f, width, 0.5f)];
		hair.backgroundColor = [[TGTheme shared] separatorColour];
		[header addSubview:hair];
	}

	CGFloat wasHidingHeader = self.headerHeight;
	self.tableView.tableHeaderView = header;
	self.headerHeight = height;
	[self hideHeaderAboveFrom:wasHidingHeader];
}

- (void)hideHeaderAboveFrom:(CGFloat)previousHeight {
	if (self.tableView.contentSize.height <= self.tableView.bounds.size.height)
		return;
	CGFloat y = self.tableView.contentOffset.y;
	if (y > 0.5f && fabs(y - previousHeight) > 0.5f)
		return;
	self.tableView.contentOffset = CGPointMake(0, self.headerHeight);
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
	TGSearchViewController *search = [[TGSearchViewController alloc] init];
	search.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:search animated:YES];
	return NO;
}

- (void)styleSearchBar {
	TGTheme *theme = [TGTheme shared];
	self.searchBar.barStyle = theme.isDark ? UIBarStyleBlack : UIBarStyleDefault;
	if ([self.searchBar respondsToSelector:@selector(setBarTintColor:)])
		self.searchBar.barTintColor = [theme listBackgroundColour];
	self.searchBar.tintColor = [theme accentColour];
}

/// Saved Messages is your own chat; it is not always in the list, and every
/// client keeps a way in regardless.
- (void)openSavedMessages {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId)
		return;
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = @"Saved Messages";
	vc.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)composeTapped {
	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	contacts.title = @"New Message";
	[self.navigationController pushViewController:contacts animated:YES];
}

- (void)reload {
	if (self.showsArchive){
		self.chats = [TGClient shared].archivedChats;
		[self.tableView reloadData];
		[self fetchMissingAvatars];
		return;
	}

	if (self.folderId != 0){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] chatsInFolder:self.folderId completion:^(NSArray *chats){
			weakSelf.chats = chats;
			[weakSelf.tableView reloadData];
			[weakSelf fetchMissingAvatars];
		}];
		return;
	}

	self.chats = [TGClient shared].chats;
	[self.tableView reloadData];
	[self rebuildTableHeader];
	[self fetchMissingAvatars];
}

/// Nothing sits above the chats any more. The archive lives in the table's
/// header, hidden above the top of the list until you pull down for it - which
/// is where Telegram keeps it - and Saved Messages is simply a chat, because
/// pinning your own notes to the top of the list is not something it does.
- (NSArray *)headerRows {
	return @[];
}

- (BOOL)hasArchiveRow {
	return NO;
}

- (void)openArchive {
	TGChatListViewController *archive = [[TGChatListViewController alloc] init];
	archive.showsArchive = YES;
	archive.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:archive animated:YES];
}

/// Folders are a filter over the same chats, offered as a choice.
- (void)foldersTapped {
	NSArray *folders = [TGClient shared].folders;
	// Tapping and getting nothing back reads as a broken button; an account
	// with no folders has to say so.
	if (!folders.count){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Folders"
				message:@"This account has no chat folders. They are set up in "
						@"Telegram on a desktop or a newer phone, and appear here."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Show"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:@"All chats", nil];
	for (NSDictionary *f in folders)
		[sheet addButtonWithTitle:f[@"title"]];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	// Saved Messages has its own row now, so this sheet is All chats followed
	// by the folders themselves.
	NSArray *folders = [TGClient shared].folders;
	if (index == 0){
		self.folderId = 0;
		self.title = self.showsArchive ? @"Archived" : @"Chats";
	} else if (index - 1 < (NSInteger)folders.count){
		NSDictionary *f = folders[index - 1];
		self.folderId = [f[@"id"] integerValue];
		self.title = f[@"title"];
	}
	[self reload];
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self.tableView selector:@selector(reloadData) object:nil];
	[self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.05];
}

/// Avatars are fetched once each and cached by file id.
- (void)fetchMissingAvatars {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *c in self.chats){
		NSNumber *fileId = c[@"photoFileId"];
		if (!fileId || self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
			continue;
		[self.avatarsRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			if (!path) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				UIImage *img = [UIImage imageWithContentsOfFile:path];
				if (!img) return;
				dispatch_async(dispatch_get_main_queue(), ^{
					TGChatListViewController *me = weakSelf;
					if (!me) return;
					me.avatars[fileId] = img;
					[me reloadTableDebounced];
				});
			});
		}];
	}
}

/// Today shows the time, this week the weekday, older the date - as clients do.
static NSString *TGChatDate(NSTimeInterval unix) {
	if (unix <= 0)
		return @"";

	NSDate *date = [NSDate dateWithTimeIntervalSince1970:unix];
	NSTimeInterval age = -[date timeIntervalSinceNow];

	static NSDateFormatter *time = nil, *weekday = nil, *full = nil;
	if (!time){
		time = [[NSDateFormatter alloc] init];    [time setDateFormat:@"HH:mm"];
		weekday = [[NSDateFormatter alloc] init]; [weekday setDateFormat:@"EEE"];
		full = [[NSDateFormatter alloc] init];    [full setDateFormat:@"dd.MM.yy"];
	}

	if (age < 24 * 3600)     return [time stringFromDate:date];
	if (age < 7 * 24 * 3600) return [weekday stringFromDate:date];
	return [full stringFromDate:date];
}

#pragma mark - table

static const NSInteger kChatActionsTag = 77;

- (void)rowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;

	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[hold locationInView:self.tableView]];
	if (path)
		[self showActionsForRow:path.row];
}

/// Split out from the gesture so itglegacy://holdrow/N can reach it: a long
/// press cannot be delivered through a URL, and this menu needs checking.
- (void)showActionsForRow:(NSInteger)row {
	NSInteger index = row - [self headerRows].count;
	if (index < 0)
		return;

	NSArray *rows = [self visibleChats];
	if (index >= (NSInteger)rows.count)
		return;
	self.actionChat = rows[index];

	BOOL pinned = [self.actionChat[@"isPinned"] boolValue];
	BOOL muted  = [self.actionChat[@"isMuted"] boolValue];
	NSArray *items = @[
		@{@"title" : (pinned ? @"Unpin" : @"Pin"),
		  @"icon"  : (pinned ? @"unpin" : @"pin")},
		@{@"title" : (muted ? @"Unmute" : @"Mute"),
		  @"icon"  : (muted ? @"unmute" : @"mute")},
		@{@"title" : (self.showsArchive ? @"Unarchive" : @"Archive"),
		  @"icon"  : (self.showsArchive ? @"unarchive" : @"archive")},
		@{@"title" : @"Delete and Leave", @"icon" : @"delete", @"destructive" : @YES},
	];

	CGRect rect = [self.tableView rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		[weakSelf runChatAction:choice];
	}];
}

- (void)runChatAction:(NSInteger)choice {
	int64_t chatId = [self.actionChat[@"id"] longLongValue];
	if (choice == 0)
		[[TGClient shared] setChat:chatId pinned:![self.actionChat[@"isPinned"] boolValue]];
	else if (choice == 1)
		[[TGClient shared] setChat:chatId muted:![self.actionChat[@"isMuted"] boolValue]];
	else if (choice == 2)
		[[TGClient shared] setChat:chatId archived:!self.showsArchive];
	else
		[self confirmDeleteChat:chatId];
	self.actionChat = nil;
}

/// Leaving cannot be taken back once it has happened, so it does not happen at
/// once: the row goes, and the count on the plate is the window to change your
/// mind. Their design answers this with a snackbar rather than a dialog.
- (void)confirmDeleteChat:(int64_t)chatId {
	self.chatPendingDeletion = chatId;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[TGSnackbar showInView:self.navigationController.view
					  text:@"Chat deleted"
				   seconds:5
				  onCommit:^{
		[[TGClient shared] deleteChat:chatId];
		TGChatListViewController *me = weakSelf;
		me.chatPendingDeletion = 0;
		[me reload];
	}];

	// UNDO simply never commits; the row has to come back when it does not.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGChatListViewController *me = weakSelf;
		if (me.chatPendingDeletion == chatId){
			me.chatPendingDeletion = 0;
			[me.tableView reloadData];
		}
	});
}

#pragma mark - search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length){
		self.searchResults = nil;
		[self.tableView reloadData];
		return;
	}

	// Chat titles match locally and instantly; messages need the server. Both
	// land in one list, chats first, which is what the query usually means.
	NSMutableArray *results = [NSMutableArray array];
	for (NSDictionary *c in [TGClient shared].chats)
		if ([c[@"title"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			[results addObject:c];
	self.searchResults = results;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchMessages:query completion:^(NSArray *messages){
		TGChatListViewController *me = weakSelf;
		// A slower answer to an older query must not replace a newer one.
		if (!me || ![me.searchBar.text isEqualToString:query])
			return;
		NSMutableArray *combined = [results mutableCopy];
		for (NSDictionary *m in messages)
			[combined addObject:@{
				@"id"    : m[@"chatId"] ?: @0,
				@"title" : m[@"chatTitle"] ?: @"",
				@"text"  : m[@"text"] ?: @"",
				@"date"  : m[@"date"] ?: @0,
			}];
		me.searchResults = combined;
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.searchResults = nil;
	[searchBar resignFirstResponder];
	[self.tableView reloadData];
}

/// Saved Messages has a row of its own above the list, so leaving it among the
/// chats as well would show it twice.
- (NSArray *)visibleChats {
	if (self.searchResults)
		return self.searchResults;

	BOOL hideSaved = [[self headerRows] containsObject:@"saved"];
	int64_t saved = hideSaved ? [[TGClient shared] savedMessagesChatId] : 0;
	if (!hideSaved && !self.chatPendingDeletion)
		return self.chats;

	NSMutableArray *rest = [NSMutableArray array];
	for (NSDictionary *c in self.chats){
		int64_t chatId = [c[@"id"] longLongValue];
		// A chat waiting on the undo plate is already off the list; putting it
		// back is what UNDO does.
		if (chatId == saved || chatId == self.chatPendingDeletion)
			continue;
		[rest addObject:c];
	}
	return rest;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.searchResults)
		return self.searchResults.count;
	return [self visibleChats].count + [self headerRows].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGChatCell";
	TGChatCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	UIColor *bg = [theme listBackgroundColour];
	cell.backgroundColor = bg;
	cell.contentView.backgroundColor = bg;
	cell.titleLabel.backgroundColor = bg;
	cell.titleLabel.opaque = YES;
	cell.titleLabel.textColor = [theme primaryTextColour];
	cell.previewLabel.backgroundColor = bg;
	cell.previewLabel.opaque = YES;
	cell.previewLabel.textColor = [theme secondaryTextColour];
	cell.dateLabel.backgroundColor = bg;
	cell.dateLabel.opaque = YES;
	cell.dateLabel.textColor = [theme secondaryTextColour];
	cell.onlineDot.hidden = YES;
	cell.tick.hidden = YES;
	cell.onlineDot.layer.borderColor = bg.CGColor;

	if (theme.isDark) {
		UIView *selected = [[UIView alloc] init];
		selected.backgroundColor = [theme bubbleTheirsColour];
		cell.selectedBackgroundView = selected;
	} else {
		cell.selectedBackgroundView = nil;
	}

	NSArray *header = [self headerRows];
	if (indexPath.row < (NSInteger)header.count){
		BOOL isArchive = [header[indexPath.row] isEqualToString:@"archive"];
		cell.titleLabel.text = isArchive ? @"Archived Chats" : @"Saved Messages";
		cell.previewLabel.text = isArchive
				? [NSString stringWithFormat:@"%lu chats",
						(unsigned long)[TGClient shared].archivedChats.count]
				: @"Your own notes and forwards";
		cell.dateLabel.text = @"";
		cell.badge.hidden = YES;
		cell.avatar.image = isArchive
				? [TGIcons archiveAvatarOfSide:kAvatar]
				: [TGIcons savedMessagesAvatarOfSide:kAvatar];
		cell.avatar.backgroundColor = [UIColor clearColor];
		[cell setNeedsLayout];
		return cell;
	}

	NSDictionary *c = [self visibleChats][indexPath.row - header.count];
	cell.titleLabel.text = c[@"title"];
	cell.dateLabel.text = TGChatDate([c[@"date"] doubleValue]);

	// Someone typing takes the preview over for as long as it lasts, in their
	// blurple rather than the grey the preview uses.
	NSString *action = c[@"action"];
	if ([action length]){
		cell.previewLabel.text = action;
		cell.previewLabel.textColor = [theme typingColour];
	} else {
		cell.previewLabel.text = c[@"text"];
	}

	cell.onlineDot.hidden = ![c[@"isOnline"] boolValue];

	// A muted chat says so in its title; a pinned one keeps a marker where the
	// date sits when it has none.
	cell.titleLabel.text = [c[@"isMuted"] boolValue]
			? [NSString stringWithFormat:@"%@ \U0001F507", c[@"title"] ?: @""]
			: c[@"title"];

	NSInteger unread = [c[@"unread"] integerValue];
	cell.badge.hidden = (unread <= 0);
	cell.pin.hidden = !([c[@"isPinned"] boolValue] && unread <= 0);
	if (!cell.pin.hidden){
		cell.pin.image = [TGIcons menuGlyphNamed:@"pin"];
		cell.pin.tintColor = [theme secondaryTextColour];
	}
	cell.badge.text = unread > 0 ? [NSString stringWithFormat:@"%ld", (long)unread] : @"";
	// A muted chat still counts, it just stops shouting about it.
	cell.badge.backgroundColor = [c[@"isMuted"] boolValue]
			? [theme mutedBadgeColour] : [theme badgeColour];

	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
	if ([c[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:kAvatar];
	if (!photo){
		NSString *title = c[@"title"] ?: @"";
		NSString *initials = title.length ? [title substringToIndex:1] : @"?";
		photo = [TGIcons avatarWithInitials:initials.uppercaseString
									   size:kAvatar
								   colourId:[c[@"id"] longLongValue]];
	}
	cell.avatar.image = photo;
	cell.avatar.backgroundColor = [UIColor clearColor];

	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSArray *header = [self headerRows];
	if (indexPath.row < (NSInteger)header.count){
		if ([header[indexPath.row] isEqualToString:@"archive"])
			[self openArchive];
		else
			[self openSavedMessages];
		return;
	}

	NSDictionary *c = [self visibleChats][indexPath.row - header.count];
	NSLog(@"open chat: group=%@ forum=%@", c[@"isGroup"], c[@"isForum"] ?: @"(absent)");

	if ([c[@"isForum"] boolValue]){
		TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
		topics.chatId = [c[@"id"] longLongValue];
		topics.chatTitle = c[@"title"];
		topics.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:topics animated:YES];
		return;
	}

	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = [c[@"id"] longLongValue];
	vc.chatTitle = c[@"title"];
	vc.isGroup = [c[@"isGroup"] boolValue];
	vc.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

@end

// vim:ft=objc
