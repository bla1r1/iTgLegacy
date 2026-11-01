#import "TGForwardPicker.h"
#import "TGClient.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGUIFormat.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

@interface TGForwardPicker () <UISearchBarDelegate>
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSMutableDictionary *avatars;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@property (nonatomic, strong) NSMutableSet *selectedChatIds;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIBarButtonItem *sendItem;
@property (nonatomic, copy) NSString *query;
@end

@implementation TGForwardPicker

- (instancetype)init {
	return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Forward to";
	self.chats = [TGClient shared].chats ?: @[];
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];
	self.selectedChatIds = [NSMutableSet set];
	self.query = @"";

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.tableView.rowHeight = TGMetricPersonRow;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
								 target:self action:@selector(cancel)];
	self.sendItem = [[UIBarButtonItem alloc] initWithTitle:@"Send"
			style:UIBarButtonItemStyleDone target:self action:@selector(send)];
	self.navigationItem.rightBarButtonItem = self.sendItem;
	[self updateSendItem];

	self.searchBar = [[UISearchBar alloc] initWithFrame:
			CGRectMake(0, 0, self.tableView.bounds.size.width, TGMetricRow)];
	self.searchBar.placeholder = @"Search";
	self.searchBar.delegate = self;
	self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[[TGTheme shared] styleSearchBar:self.searchBar];
	self.tableView.tableHeaderView = self.searchBar;

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
		[[TGTheme shared] styleSearchBar:me.searchBar];
		[me.tableView reloadData];
	}];

	[self fetchMissingAvatars];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cancel {
	if (self.navigationController && self.navigationController.viewControllers.count > 1 &&
		self.navigationController.viewControllers.firstObject != self){
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

#pragma mark - what the table shows

- (NSArray *)matchingChats {
	NSMutableArray *matches = [NSMutableArray array];
	for (NSDictionary *chat in self.chats) {
		NSString *title = chat[@"title"] ?: @"";
		NSString *username = chat[@"username"] ?: @"";
		if (TGUIFormatChatMatches(title, self.query) ||
				TGUIFormatChatMatches(username, self.query))
			[matches addObject:chat];
	}
	return matches;
}

- (NSArray *)recentChats {
	NSArray *matches = [self matchingChats];
	if (self.query.length)
		return @[];
	NSUInteger count = MIN((NSUInteger)5, matches.count);
	return [matches subarrayWithRange:NSMakeRange(0, count)];
}

- (NSArray *)otherChats {
	NSArray *matches = [self matchingChats];
	if (self.query.length)
		return matches;
	NSArray *recent = [self recentChats];
	if (recent.count >= matches.count)
		return @[];
	return [matches subarrayWithRange:NSMakeRange(recent.count,
			matches.count - recent.count)];
}

- (NSArray *)chatsInSection:(NSInteger)section {
	if (self.query.length)
		return [self matchingChats];
	return section == 0 ? [self recentChats] : [self otherChats];
}

- (NSDictionary *)chatAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self chatsInSection:indexPath.section];
	if (indexPath.row >= (NSInteger)rows.count)
		return nil;
	return rows[(NSUInteger)indexPath.row];
}

- (void)updateSendItem {
	NSUInteger count = self.selectedChatIds.count;
	self.sendItem.title = count > 0
			? [NSString stringWithFormat:@"Send (%lu)", (unsigned long)count]
			: @"Send";
	self.sendItem.enabled = count > 0;
}

- (NSArray *)selectedChatIdsInOrder {
	NSMutableArray *ids = [NSMutableArray array];
	NSArray *all = [self matchingChats];
	for (NSDictionary *chat in all) {
		NSNumber *chatId = chat[@"id"];
		if ([chatId isKindOfClass:NSNumber.class] &&
				[self.selectedChatIds containsObject:chatId])
			[ids addObject:chatId];
	}
	return ids;
}

- (void)send {
	NSArray *ids = [self selectedChatIdsInOrder];
	if (!ids.count)
		return;
	// One pick per chat keeps every existing caller working: each one already
	// knows how to forward one message set into one chat.
	if (self.onPicked)
		for (NSNumber *chatId in ids)
			self.onPicked(chatId.longLongValue);
	[self cancel];
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

#pragma mark - search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	self.query = [searchText stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (self.query.length)
		return 1;
	// "All Chats" is only a second heading when there is something below it.
	return [self otherChats].count ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSArray *rows = [self chatsInSection:section];
	if (rows.count)
		return (NSInteger)rows.count;
	// One sentence in place of an empty list; a second, empty group (all
	// chats already shown under Recent) gets no row at all.
	if (self.query.length || section == 0)
		return 1;
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (self.query.length)
		return @"Results";
	return section == 0 ? @"Recent Chats" : @"All Chats";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return TGMetricRow - TGMetricPadLarge;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *sectionHeader = (UITableViewHeaderFooterView *)view;
		sectionHeader.textLabel.font = TGFontMetaStrong();
		sectionHeader.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
		sectionHeader.contentView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGForwardCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *c = [self chatAtIndexPath:indexPath];
	UIColor *bg = [[TGTheme shared] listBackgroundColour];
	cell.backgroundColor = bg;
	cell.contentView.backgroundColor = bg;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.imageView.image = nil;

	if (!c) {
		cell.textLabel.text = self.query.length
				? @"No chats match that search."
				: @"No chats yet.";
		cell.textLabel.font = TGFontBody();
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.textLabel.backgroundColor = bg;
		cell.detailTextLabel.text = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	NSString *title = c[@"title"] ?: @"";
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
	cell.imageView.layer.cornerRadius = TGHalf(TGMetricListAvatar);
	cell.imageView.clipsToBounds = YES;
	cell.imageView.layer.shouldRasterize = YES;
	cell.imageView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	cell.imageView.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	cell.imageView.layer.borderWidth = 1.0f;
	cell.imageView.contentMode = UIViewContentModeScaleAspectFill;

	NSNumber *chatId = c[@"id"];
	BOOL selected = [chatId isKindOfClass:NSNumber.class] &&
			[self.selectedChatIds containsObject:chatId];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark
								  : UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *c = [self chatAtIndexPath:indexPath];
	NSNumber *chatId = c[@"id"];
	if (![chatId isKindOfClass:NSNumber.class])
		return;
	if ([self.selectedChatIds containsObject:chatId])
		[self.selectedChatIds removeObject:chatId];
	else
		[self.selectedChatIds addObject:chatId];
	[self updateSendItem];
	[tableView reloadRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationNone];
}

@end

// vim:ft=objc
