#import "TGSearchViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"


@interface TGSearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) NSArray *chatHits;
@property (nonatomic, strong) NSArray *messageHits;
/// Who this account talks to most, shown before anything is typed - their
/// search opens on this rather than on a blank screen.
@property (nonatomic, strong) NSArray *frequent;
/// Where this account was last, under the frequent list.
@property (nonatomic, strong) NSArray *recent;
/// Contacts Telegram matched, which is its own section: a person who is not
/// a chat yet has no row among the chats.
@property (nonatomic, strong) NSArray *contactHits;
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@end

@implementation TGSearchViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.chatHits = @[];
	self.messageHits = @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];
	self.tableView.rowHeight = 60;
	if ([self.tableView respondsToSelector:@selector(setKeyboardDismissMode:)])
		self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 240, 44)];
	self.bar.delegate = self;
	self.bar.placeholder = @"Search";
	self.navigationItem.titleView = self.bar;
	self.navigationItem.hidesBackButton = YES;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
				   target:self action:@selector(cancel)];

	[self applyTheme];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];

	[self loadFrequentChats];
	[self.bar becomeFirstResponder];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	self.bar.barStyle = theme.isDark ? UIBarStyleBlack : UIBarStyleDefault;
	if ([self.bar respondsToSelector:@selector(setBarTintColor:)])
		self.bar.barTintColor = [theme searchBarBackgroundColour];
	self.bar.tintColor = [theme accentColour];
	self.bar.backgroundColor = [theme searchBarBackgroundColour];
	if ([self.bar respondsToSelector:@selector(setImage:forSearchBarIcon:state:)]) {
		[self.bar setImage:[TGIcons searchLensOfSize:15.0f colour:[theme secondaryTextColour]]
		  forSearchBarIcon:UISearchBarIconSearch
					 state:UIControlStateNormal];
	}
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (void)cancel {
	[self.bar resignFirstResponder];
	[self.navigationController popViewControllerAnimated:YES];
}

/// Before a query there is nothing to match, and a blank list reads as a
/// broken screen. Telegram's own answer is the people you talk to most.
- (void)loadFrequentChats {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] topChatsWithCompletion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me || me.bar.text.length)
			return;
		me.frequent = chats ?: @[];
		[me.tableView reloadData];
	}];
	[[TGClient shared] recentlyOpenedChatsWithCompletion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me || me.bar.text.length)
			return;
		// What is already in the people row is not worth a second row.
		NSMutableSet *shown = [NSMutableSet set];
		for (NSDictionary *chat in me.frequent)
			if (chat[@"id"])
				[shown addObject:chat[@"id"]];
		NSMutableArray *rest = [NSMutableArray array];
		for (NSDictionary *chat in (chats ?: @[]))
			if (![shown containsObject:chat[@"id"]])
				[rest addObject:chat];
		me.recent = rest;
		[me.tableView reloadData];
	}];
}

/// True while the search is empty, which is when the frequent list is what
/// the table shows.
- (BOOL)showsFrequent {
	return !self.bar.text.length &&
		   (self.frequent.count > 0 || self.recent.count > 0);
}

/// While the search is empty the two sections are the people and the places,
/// so a row is read out of whichever list its section stands for.
- (NSDictionary *)emptyStateRowAt:(NSIndexPath *)indexPath {
	NSArray *list = indexPath.section == 0 ? self.frequent : self.recent;
	return indexPath.row < (NSInteger)list.count ? list[indexPath.row] : nil;
}

#pragma mark - searching

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length) {
		self.chatHits = @[];
		self.messageHits = @[];
		self.contactHits = @[];
		// Back to the people and the places rather than to nothing.
		[self loadFrequentChats];
		[self.tableView reloadData];
		return;
	}

	// The loaded list first, so there is something on screen before the
	// server answers; what comes back replaces it.
	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *c in [TGClient shared].chats)
		if ([c[@"title"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
			[titles addObject:c];
	self.chatHits = titles;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	// Matching titles here only ever found chats already loaded, so a chat
	// this account has and has not opened, and every public chat, were
	// unfindable by name.
	[[TGClient shared] searchChatsForQuery:query completion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query]) return;
		me.chatHits = chats ?: @[];
		[me.tableView reloadData];
	}];
	[[TGClient shared] searchContactsForQuery:query completion:^(NSArray *users){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query]) return;
		me.contactHits = users ?: @[];
		[me.tableView reloadData];
	}];
	[[TGClient shared] searchMessages:query completion:^(NSArray *messages) {
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query]) return;
		me.messageHits = messages ?: @[];
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// Chats, people, messages - the people section only while searching.
	return [self showsFrequent] ? 2 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ([self showsFrequent])
		return section == 0 ? self.frequent.count : self.recent.count;
	if (section == 0) return self.chatHits.count;
	if (section == 1) return self.contactHits.count;
	return self.messageHits.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self showsFrequent])
		return section == 0 ? (self.frequent.count ? @"People" : nil)
							: (self.recent.count ? @"Recent" : nil);
	if (section == 0)
		return self.chatHits.count ? @"Chats" : nil;
	if (section == 1)
		return self.contactHits.count ? @"Contacts" : nil;
	return self.messageHits.count ? @"Messages" : nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
		header.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (UIImage *)avatarForChat:(int64_t)chatId
					 title:(NSString *)title
					fileId:(NSNumber *)fileId
{
	UIImage *cached = [fileId isKindOfClass:NSNumber.class] ? self.avatars[fileId] : nil;
	if (cached)
		return cached;

	if ([fileId isKindOfClass:NSNumber.class] &&
		![self.avatarsRequested containsObject:fileId]){
		[self.avatarsRequested addObject:fileId];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			TGSearchViewController *me = weakSelf;
			UIImage *photo = path ? [UIImage imageWithContentsOfFile:path] : nil;
			if (!me || !photo)
				return;
			UIGraphicsBeginImageContextWithOptions(
					CGSizeMake(TGMetricListAvatar, TGMetricListAvatar), NO, 0);
			[photo drawInRect:CGRectMake(0, 0, TGMetricListAvatar, TGMetricListAvatar)];
			me.avatars[fileId] = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			[me.tableView reloadData];
		}];
	}

	return [TGIcons avatarWithInitials:
				(title.length ? [title substringToIndex:1].uppercaseString : @"?")
								  size:TGMetricListAvatar
							  colourId:chatId];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *reuse = @"TGSearchCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
		cell.imageView.layer.cornerRadius = TGMetricListAvatar / 2;
		cell.imageView.clipsToBounds = YES;
		cell.imageView.layer.shouldRasterize = YES;
		cell.imageView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	}

	TGTheme *theme = [TGTheme shared];
	UIColor *bg = [theme listBackgroundColour];
	cell.backgroundColor = bg;
	cell.textLabel.font = TGFontBodyStrong();
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.textLabel.backgroundColor = bg;
	cell.textLabel.opaque = YES;

	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.backgroundColor = bg;
	cell.detailTextLabel.opaque = YES;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	if ([self showsFrequent]) {
		NSDictionary *c = [self emptyStateRowAt:indexPath];
		cell.textLabel.text = c[@"title"];
		cell.detailTextLabel.text = c[@"previewText"];
		cell.imageView.image = [self avatarForChat:[c[@"id"] longLongValue]
											 title:c[@"title"]
											fileId:c[@"photoFileId"]];
	} else if (indexPath.section == 0) {
		NSDictionary *c = self.chatHits[indexPath.row];
		// A public chat the list has never seen answers with no title until
		// its own fetch lands; the row says so rather than being blank.
		NSString *title = [c[@"title"] length] ? c[@"title"] : @"Loading...";
		cell.textLabel.text = title;
		cell.detailTextLabel.text = c[@"text"];
		cell.imageView.image = [self avatarForChat:[c[@"id"] longLongValue]
											 title:title
											fileId:c[@"photoFileId"]];
	} else if (indexPath.section == 1) {
		NSDictionary *u = self.contactHits[indexPath.row];
		NSString *name = [u[@"name"] length] ? u[@"name"]
				: [[TGClient shared] nameForUserId:[u[@"id"] longLongValue]];
		cell.textLabel.text = name ?: @"";
		cell.detailTextLabel.text = nil;
		cell.imageView.image = [self avatarForChat:[u[@"id"] longLongValue]
											 title:name
											fileId:nil];
	} else {
		NSDictionary *m = self.messageHits[indexPath.row];
		cell.textLabel.text = m[@"chatTitle"];
		cell.detailTextLabel.text = m[@"text"];
		cell.imageView.image = [self avatarForChat:[m[@"chatId"] longLongValue]
											 title:m[@"chatTitle"]
											fileId:nil];
	}

	if (theme.isDark) {
		UIView *selected = [[UIView alloc] init];
		selected.backgroundColor = [theme bubbleTheirsColour];
		cell.selectedBackgroundView = selected;
	} else {
		cell.selectedBackgroundView = nil;
	}

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.bar resignFirstResponder];

	BOOL fromFrequent = [self showsFrequent];

	// A contact is a person, not a chat: the private chat with them has to be
	// asked for before there is anything to open.
	if (!fromFrequent && indexPath.section == 1){
		NSDictionary *u = self.contactHits[indexPath.row];
		NSString *name = [u[@"name"] length] ? u[@"name"]
				: [[TGClient shared] nameForUserId:[u[@"id"] longLongValue]];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
									completion:^(int64_t privateId){
			TGSearchViewController *me = weakSelf;
			if (!me || !privateId)
				return;
			[[TGClient shared] rememberFoundChat:privateId];
			TGChatViewController *chat = [[TGChatViewController alloc] init];
			chat.chatId = privateId;
			chat.chatTitle = name ?: @"";
			chat.hidesBottomBarWhenPushed = YES;
			[me.navigationController pushViewController:chat animated:YES];
		}];
		return;
	}

	NSDictionary *row = fromFrequent ? [self emptyStateRowAt:indexPath]
			: (indexPath.section == 0 ? self.chatHits[indexPath.row]
									  : self.messageHits[indexPath.row]);
	int64_t chatId = [((fromFrequent || indexPath.section == 0)
			? row[@"id"] : row[@"chatId"]) longLongValue];
	if (!chatId)
		return;

	// Opening a chat from search is what puts it in the recently-found list,
	// which is the other half of what this screen shows when it is empty.
	[[TGClient shared] rememberFoundChat:chatId];

	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = (fromFrequent || indexPath.section == 0)
			? row[@"title"] : row[@"chatTitle"];
	chat.isGroup = [row[@"isGroup"] boolValue];
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

@end

// vim:ft=objc
