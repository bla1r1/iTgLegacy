//
// TGStickerPacksViewController.m - see the header.
//
#import "TGStickerPacksViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGStickerEditorViewController.h"
#import "TGStickerGalleryViewController.h"
#import "TGStyle.h"
#import "TGTheme.h"

@implementation TGStickerPacksViewController {
	NSArray *_ownedSets;
	NSArray *_archivedSets;
	NSArray *_trendingSets;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = @"Stickers";
	self.tableView.rowHeight = TGMetricPersonRow;
	_ownedSets = @[];
	_archivedSets = @[];
	_trendingSets = @[];
	[self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self reloadOwnedPacks];
	[self reloadArchivedPacks];
	[self reloadTrending];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - loading

- (void)reloadOwnedPacks {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] ownedStickerSetsWithCompletion:^(NSArray *sets){
		TGStickerPacksViewController *me = weakSelf;
		if (!me)
			return;
		_ownedSets = sets ?: @[];
		[me.tableView reloadData];
	}];
}

/// The archived shelf keeps a pack that was removed by mistake. Telegram
/// does not show it with the installed packs, so this page has its own
/// section and a restore that is one tap.
- (void)reloadArchivedPacks {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] archivedStickerSetsWithCompletion:^(NSArray *sets){
		TGStickerPacksViewController *me = weakSelf;
		if (!me)
			return;
		_archivedSets = sets ?: @[];
		[me.tableView reloadData];
	}];
}

/// Showing the shelf is what marks it seen. Telegram drops the ids this
/// request names from the next recommendation, so the write belongs at the
/// moment the rows are drawn rather than at app launch.
- (void)reloadTrending {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] trendingStickerSetsWithCompletion:^(NSArray *sets){
		TGStickerPacksViewController *me = weakSelf;
		if (!me)
			return;
		_trendingSets = sets ?: @[];
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *set in _trendingSets)
			if (set[@"id"])
				[ids addObject:set[@"id"]];
		[[TGClient shared] viewTrendingStickerSets:ids];
		[me.tableView reloadData];
	}];
}

#pragma mark - rows

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section){
		case 0: return 3;             // new, search, clear recents
		case 1: return MAX((NSInteger)_ownedSets.count, 1);
		case 2: return MAX((NSInteger)_archivedSets.count, 1);
		case 3: return MAX((NSInteger)_trendingSets.count, 1);
		case 4: return 4;             // three default shelves, id lookup
		default: return 1;            // greeting stickers
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section){
		case 1: return @"MY PACKS";
		case 2: return _archivedSets.count ? @"ARCHIVED" : nil;
		case 3: return @"TRENDING";
		case 4: return @"CUSTOM EMOJI";
		default: return section == 5 ? @"GREETINGS" : nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1)
		return _ownedSets.count ? @"Tap a pack to edit its stickers, its title and "
				@"its thumbnail." : @"Make one from the row above and it appears here.";
	if (section == 2 && _archivedSets.count)
		return @"A removed pack stays here. Tap one to put it back on the shelf.";
	if (section == 3)
		return _trendingSets.count ? @"Showing these marks them viewed, so they stop "
				@"being recommended." : nil;
	if (section == 4)
		return @"The default custom emoji Telegram allows on photos, chats and "
				@"backgrounds, plus a lookup by id.";
	return nil;
}

- (UITableViewCell *)baseCell:(UITableView *)tableView {
	static NSString *cellId = @"row";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:cellId];
	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.textLabel.font = TGFontRow();
	cell.detailTextLabel.font = TGFontCaption();
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [self baseCell:tableView];

	if (indexPath.section == 0){
		if (indexPath.row == 0){
			cell.textLabel.text = @"New Sticker Pack";
			cell.detailTextLabel.text = @"Title, short name and a first sticker";
		} else if (indexPath.row == 1){
			cell.textLabel.text = @"Search by Short Name";
			cell.detailTextLabel.text = @"Look up a pack by its t.me name";
		} else {
			cell.textLabel.text = @"Clear Recent Stickers";
			cell.detailTextLabel.text = @"Empty the Recently Used shelf";
			cell.textLabel.textColor = [TGTheme shared].destructiveColour;
		}
		return cell;
	}

	if (indexPath.section == 1){
		if (!_ownedSets.count){
			cell.textLabel.text = @"No packs yet";
			cell.detailTextLabel.text = @"New Sticker Pack makes the first one";
			cell.accessoryType = UITableViewCellAccessoryNone;
			return cell;
		}
		NSDictionary *set = _ownedSets[(NSUInteger)indexPath.row];
		cell.textLabel.text = [set[@"title"] length] ? set[@"title"] : @"Pack";
		NSString *type = [self typeWord:set[@"stickerType"]];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %lu stickers  ·  %@",
				set[@"shortName"] ?: @"-",
				(unsigned long)[set[@"count"] unsignedIntegerValue], type];
		return cell;
	}

	if (indexPath.section == 2){
		if (!_archivedSets.count){
			cell.textLabel.text = @"No archived packs";
			cell.detailTextLabel.text = @"Removed packs collect here";
			cell.accessoryType = UITableViewCellAccessoryNone;
			return cell;
		}
		NSDictionary *set = _archivedSets[(NSUInteger)indexPath.row];
		cell.textLabel.text = [set[@"title"] length] ? set[@"title"] : @"Archived pack";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu stickers  ·  tap to restore",
				(unsigned long)[set[@"count"] unsignedIntegerValue]];
		return cell;
	}

	if (indexPath.section == 3){
		if (!_trendingSets.count){
			cell.textLabel.text = @"Telegram has nothing to recommend";
			cell.detailTextLabel.text = nil;
			cell.accessoryType = UITableViewCellAccessoryNone;
			return cell;
		}
		NSDictionary *set = _trendingSets[(NSUInteger)indexPath.row];
		cell.textLabel.text = [set[@"title"] length] ? set[@"title"] : @"Trending pack";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu stickers%@",
				(unsigned long)[set[@"count"] unsignedIntegerValue],
				[set[@"installed"] boolValue] ? @"  ·  installed" : @""];
		return cell;
	}

	if (indexPath.section == 4){
		NSArray *titles = @[@"Profile Photo Emoji", @"Chat Photo Emoji",
							@"Background Emoji", @"Look Up Custom Emoji IDs..."];
		NSArray *notes = @[@"The default shelf for a profile picture",
						   @"The default shelf for a chat picture",
						   @"The default shelf for a wallpaper",
						   @"Paste ids from a message that carries them"];
		cell.textLabel.text = titles[(NSUInteger)indexPath.row];
		cell.detailTextLabel.text = notes[(NSUInteger)indexPath.row];
		return cell;
	}

	cell.textLabel.text = @"Greeting Stickers";
	cell.detailTextLabel.text = @"What Telegram suggests for a greeting";
	return cell;
}

- (NSString *)typeWord:(NSString *)type {
	if ([type isEqualToString:@"stickerTypeCustomEmoji"] ||
		[type isEqualToString:@"customEmoji"])
		return @"custom emoji";
	if ([type isEqualToString:@"stickerTypeMask"] || [type isEqualToString:@"mask"])
		return @"masks";
	return @"regular";
}

#pragma mark - choosing

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 0){
		if (indexPath.row == 0)
			[self openNewPack];
		else if (indexPath.row == 1)
			[self askForShortName];
		else
			[self confirmClearRecent];
		return;
	}

	if (indexPath.section == 1){
		if (!_ownedSets.count)
			return;
		NSDictionary *set = _ownedSets[(NSUInteger)indexPath.row];
		TGStickerEditorViewController *editor =
				[[TGStickerEditorViewController alloc] init];
		editor.setId = [set[@"id"] longLongValue];
		editor.setName = set[@"shortName"];
		editor.setTitle = set[@"title"];
		editor.stickerType = set[@"stickerType"];
		editor.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:editor animated:YES];
		return;
	}

	if (indexPath.section == 2){
		if (!_archivedSets.count)
			return;
		[self restoreArchivedPack:_archivedSets[(NSUInteger)indexPath.row]];
		return;
	}

	if (indexPath.section == 3){
		if (!_trendingSets.count)
			return;
		[self offerPack:_trendingSets[(NSUInteger)indexPath.row]];
		return;
	}

	if (indexPath.section == 4){
		if (indexPath.row == 0)
			[self loadDefaultEmojiShelf:@"Profile Photo Emoji" kind:0];
		else if (indexPath.row == 1)
			[self loadDefaultEmojiShelf:@"Chat Photo Emoji" kind:1];
		else if (indexPath.row == 2)
			[self loadDefaultEmojiShelf:@"Background Emoji" kind:2];
		else
			[self askForCustomEmojiIds];
		return;
	}

	[self loadGreetingStickers];
}

#pragma mark - actions

- (void)openNewPack {
	TGStickerEditorViewController *editor =
			[[TGStickerEditorViewController alloc] init];
	editor.creating = YES;
	editor.stickerType = @"regular";
	editor.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:editor animated:YES];
}

/// The name is searched, then read back by id: searchStickerSet is what
/// finds it, and getStickerSetName is what proves the row's short name is
/// the server's and not a local echo.
- (void)askForShortName {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Search by Short Name"
					message:@"The name in a t.me/addstickers link."
				placeholder:@"animals" text:@"" action:@"Search"
					 inView:self.view onSubmit:^(NSString *text){
		TGStickerPacksViewController *me = weakSelf;
		[[TGClient shared] searchStickerSetNamed:text ignoreCache:YES
				completion:^(NSDictionary *set){
			if (!set){
				[TGAlertSheet showMessage:@"Telegram does not know a pack by that name."
									  title:@"Search by Short Name" inView:me.view];
				return;
			}
			int64_t setId = [set[@"id"] longLongValue];
			[[TGClient shared] stickerSetNameForId:setId completion:^(NSString *name){
				TGStickerPacksViewController *panel = weakSelf;
				if (!panel)
					return;
				NSString *message = [NSString stringWithFormat:
						@"%@\n%@\n%lu stickers%@",
						set[@"title"] ?: @"Pack",
						name.length ? name : (set[@"name"] ?: text),
						(unsigned long)[set[@"count"] unsignedIntegerValue],
						[set[@"installed"] boolValue] ? @"\nAlready installed." : @""];
				NSArray *choices = [set[@"installed"] boolValue]
						? @[@"Open", @"Cancel"] : @[@"Install", @"Cancel"];
				[TGAlertSheet showChoices:choices title:@"Pack Found"
						message:message destructiveIndex:-1 inView:panel.view
						onChoice:^(NSInteger index){
					if (index != 0)
						return;
					if ([set[@"installed"] boolValue]){
						TGStickerEditorViewController *editor =
								[[TGStickerEditorViewController alloc] init];
						editor.setId = setId;
						editor.setName = name.length ? name : set[@"name"];
						editor.setTitle = set[@"title"];
						editor.stickerType = set[@"stickerType"];
						editor.hidesBottomBarWhenPushed = YES;
						[panel.navigationController pushViewController:editor
															 animated:YES];
						return;
					}
					[[TGClient shared] setStickerSet:set[@"id"] installed:YES archived:NO];
					[TGAlertSheet showMessage:@"The pack is now on the sticker shelf."
										  title:@"Installed" inView:panel.view];
				}];
			}];
		}];
	}];
}

- (void)confirmClearRecent {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The Recently Used shelf is emptied on every device."
						title:@"Clear Recent Stickers" action:@"Clear" destructive:YES
					   inView:self.view onConfirm:^{
		TGStickerPacksViewController *me = weakSelf;
		[[TGClient shared] clearRecentStickersAttached:NO];
		[TGAlertSheet showMessage:@"Recently Used is empty."
							  title:@"Clear Recent Stickers" inView:me.view];
	}];
}

/// Restoring is the inverse of the archive: installed again, no longer
/// archived. The server answers by moving the set between shelves, so both
/// lists are re-read rather than patched locally.
- (void)restoreArchivedPack:(NSDictionary *)set {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"%@ goes back to My Packs.", set[@"title"] ?: @"This pack"]
						title:@"Restore Sticker Pack"
					   action:@"Restore"
				  destructive:NO
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] setStickerSet:set[@"id"] installed:YES archived:NO];
		TGStickerPacksViewController *me = weakSelf;
		[me performSelector:@selector(reloadOwnedPacks) withObject:nil afterDelay:0.5];
		[me performSelector:@selector(reloadArchivedPacks) withObject:nil afterDelay:0.5];
		[TGAlertSheet showMessage:@"The pack is back on the sticker shelf."
							  title:@"Restored" inView:me.view];
	}];
}

- (void)offerPack:(NSDictionary *)set {
	NSString *message = [NSString stringWithFormat:@"%lu stickers",
			(unsigned long)[set[@"count"] unsignedIntegerValue]];
	if ([set[@"installed"] boolValue]){
		[TGAlertSheet showMessage:message title:set[@"title"] inView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	int64_t setId = [set[@"id"] longLongValue];
	[TGAlertSheet showChoices:@[@"Install", @"Not Now"] title:set[@"title"]
					message:message destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger index){
		if (index != 0)
			return;
		TGStickerPacksViewController *me = weakSelf;
		[[TGClient shared] setStickerSet:@(setId) installed:YES archived:NO];
		[TGAlertSheet showMessage:@"The pack is now on the sticker shelf."
							  title:@"Installed" inView:me.view];
	}];
}

- (void)loadDefaultEmojiShelf:(NSString *)title kind:(NSInteger)kind {
	__weak typeof(self) weakSelf = self;
	void (^show)(NSArray *) = ^(NSArray *stickers){
		TGStickerPacksViewController *me = weakSelf;
		if (!me)
			return;
		[me showGallery:stickers title:title
				empty:@"Telegram sent no default emoji for this shelf."];
	};
	if (kind == 0)
		[[TGClient shared] defaultProfilePhotoCustomEmojiStickersWithCompletion:show];
	else if (kind == 1)
		[[TGClient shared] defaultChatPhotoCustomEmojiStickersWithCompletion:show];
	else
		[[TGClient shared] defaultBackgroundCustomEmojiStickersWithCompletion:show];
}

- (void)askForCustomEmojiIds {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Custom Emoji IDs"
					message:@"Comma separated ids, as a message carries them."
				placeholder:@"5368324170671202286" text:@"" action:@"Look Up"
					 inView:self.view onSubmit:^(NSString *text){
		TGStickerPacksViewController *me = weakSelf;
		NSMutableArray *ids = [NSMutableArray array];
		for (NSString *piece in [text componentsSeparatedByString:@","]){
			NSString *trimmed = [piece stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			long long value = [trimmed longLongValue];
			if (value > 0)
				[ids addObject:@(value)];
		}
		if (!ids.count){
			[TGAlertSheet showMessage:@"None of those looked like an id."
								  title:@"Custom Emoji" inView:me.view];
			return;
		}
		[[TGClient shared] customEmojiStickersForIds:ids completion:^(NSArray *stickers){
			TGStickerPacksViewController *panel = weakSelf;
			if (!panel)
				return;
			[panel showGallery:stickers title:@"Custom Emoji"
					empty:@"Telegram knows none of those ids."];
		}];
	}];
}

- (void)loadGreetingStickers {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] greetingStickersWithCompletion:^(NSArray *stickers){
		TGStickerPacksViewController *me = weakSelf;
		if (!me)
			return;
		[me showGallery:stickers title:@"Greeting Stickers"
				empty:@"Telegram sent no greeting stickers."];
	}];
}

- (void)showGallery:(NSArray *)stickers title:(NSString *)title empty:(NSString *)empty {
	if (!stickers.count){
		[TGAlertSheet showMessage:empty title:title inView:self.view];
		return;
	}
	TGStickerGalleryViewController *gallery =
			[[TGStickerGalleryViewController alloc] init];
	gallery.stickers = stickers;
	gallery.title = title;
	gallery.emptyText = empty;
	gallery.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:gallery animated:YES];
}

@end
