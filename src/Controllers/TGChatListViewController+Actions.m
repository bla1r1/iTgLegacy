#import "TGChatListViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGAlertSheet.h"

@implementation TGChatListViewController (Actions)

/// Folders are a filter over the same chats, offered as a choice.
/// The names the list titles answer with: "Archived" when this screen is
/// showing the archive, the folder's own title when a folder is selected.
- (NSString *)titleForCurrentList {
	if (self.showsArchive)
		return @"Archived";
	for (NSDictionary *f in [TGClient shared].folders)
		if ([f[@"id"] integerValue] == self.folderId)
			return f[@"title"] ?: @"Chats";
	return @"Chats";
}

- (void)foldersTapped {
	NSArray *folders = [TGClient shared].folders;
	// Tapping and getting nothing back reads as a broken button; an account
	// with no folders has to say so.
	if (!folders.count){
		[TGAlertSheet showMessage:@"This account has no chat folders yet. They "
								  @"are made in Settings, under Chat Folders, "
								  @"and appear here as a strip."
							title:@"Folders" inView:self.view];
		return;
	}

	// A popup instead of a UIActionSheet: on the 4S the sheet threw inside
	// addButtonWithTitle: (B3 - folders crash on tap) even though every
	// parsed folder title is a non-nil string. The popup is the control the
	// chat rows already use, built from the same strings.
	NSMutableArray *items = [NSMutableArray array];
	[items addObject:@{@"title" : @"All chats"}];
	for (NSDictionary *f in folders){
		NSString *title = [f isKindOfClass:NSDictionary.class] ? f[@"title"] : nil;
		NSLog(@"TGClient: B3 folder id=%@ title=%@ class=%@",
				[f isKindOfClass:NSDictionary.class] ? f[@"id"] : nil,
				title, [title class]);
		if ([title isKindOfClass:NSString.class] && title.length)
			[items addObject:@{@"title" : title}];
	}
	// A trailing row that does not choose a folder: it reads the list that
	// is open, whoever it is, badge and all. Chosen last so the folder
	// indexes above stay untouched. On the main screen with no folder open
	// it reads "Mark All Read", elsewhere it becomes plain "Mark Read".
	NSString *markTitle = self.showsArchive || self.folderId
			? @"Mark Read" : @"Mark All Read";
	[items addObject:@{@"title" : markTitle}];
	NSInteger markItem = (NSInteger)items.count - 1;

	__weak typeof(self) weakSelf = self;
	CGPoint where = CGPointMake(self.view.bounds.size.width / 2,
								self.view.bounds.size.height / 2);
	[TGPopupMenu showItems:items
				   atPoint:where
					inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		if (choice == markItem){
			[[TGClient shared] readChatListOfFolder:weakSelf.folderId
										   archived:weakSelf.showsArchive];
			return;
		}
		[weakSelf runFolderChoice:choice];
	}];
}

- (void)runFolderChoice:(NSInteger)choice {
	// Saved Messages has its own row now, so the menu is All chats followed
	// by the folders themselves.
	NSArray *folders = [TGClient shared].folders;
	if (choice == 0){
		self.folderId = 0;
		self.title = self.showsArchive ? @"Archived" : @"Chats";
	} else if (choice - 1 < (NSInteger)folders.count){
		NSDictionary *f = folders[choice - 1];
		self.folderId = [f isKindOfClass:NSDictionary.class] ? [f[@"id"] integerValue] : 0;
		NSString *t = [f isKindOfClass:NSDictionary.class] ? f[@"title"] : nil;
		self.title = [t isKindOfClass:NSString.class] && t.length ? t : @"Chats";
	}
	NSLog(@"TGClient: B3 folder choice=%ld -> id=%lld title=%@", (long)choice,
			(long long)self.folderId, self.title);
	// Redraw the pill strip so the newly chosen tab is the filled one.
	[self rebuildTableHeader];
	[self reload];
}

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
	// A one-to-one chat is only deleted; a group is left as well, and the menu
	// has to say which of the two is about to happen.
	BOOL isGroup = [self.actionChat[@"isGroup"] boolValue];
	BOOL unread = [self.actionChat[@"markedUnread"] boolValue] ||
				  [self.actionChat[@"unread"] integerValue] > 0;
	NSArray *items = @[
		@{@"title" : (pinned ? @"Unpin" : @"Pin"),
		  @"icon"  : (pinned ? @"unpin" : @"pin")},
		@{@"title" : (muted ? @"Unmute" : @"Mute"),
		  @"icon"  : (muted ? @"unmute" : @"mute")},
		@{@"title" : (unread ? @"Mark as Read" : @"Mark as Unread"),
		  @"icon"  : @"select"},
		@{@"title" : (self.showsArchive ? @"Unarchive" : @"Archive"),
		  @"icon"  : (self.showsArchive ? @"unarchive" : @"archive")},
		@{@"title" : (isGroup ? @"Delete and Leave" : @"Delete Chat"),
		  @"icon"  : @"delete", @"destructive" : @YES},
	];

	CGRect rect = [self.tableView rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(120, CGRectGetMaxY(rect) - 10) toView:self.navigationController.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		[weakSelf runChatAction:title];
	}];
}

/// Keyed by what the row said rather than by its position: the menu and the
/// swipe offer different subsets in a different order, and an index that
/// means Archive in one of them meant Delete in the other.
- (void)runChatAction:(NSString *)action {
	int64_t chatId = [self.actionChat[@"id"] longLongValue];
	if (!chatId){
		self.actionChat = nil;
		return;
	}

	if ([action hasSuffix:@"Pin"])
		[[TGClient shared] setChat:chatId
							pinned:![self.actionChat[@"isPinned"] boolValue]];
	else if ([action hasSuffix:@"Mute"])
		[[TGClient shared] setChat:chatId
							 muted:![self.actionChat[@"isMuted"] boolValue]];
	else if ([action hasSuffix:@"Archive"])
		[[TGClient shared] setChat:chatId archived:!self.showsArchive];
	else if ([action isEqualToString:@"Mark as Unread"])
		[[TGClient shared] setChat:chatId markedUnread:YES];
	else if ([action isEqualToString:@"Mark as Read"])
		[[TGClient shared] setChat:chatId markedUnread:NO];
	else
		[self confirmDeleteChat:chatId];
	self.actionChat = nil;
}

/// Leaving cannot be taken back once it has happened, so it does not happen at
/// once: the row goes, and the count on the plate is the window to change your
/// mind. Their design answers this with a snackbar rather than a dialog.
- (void)confirmDeleteChat:(int64_t)chatId {
	// Read before the row goes: visibleChats drops whatever is waiting on the
	// undo plate, and the snackbar is the only place left that can say a group
	// was also left.
	BOOL isGroup = NO;
	for (NSDictionary *chat in self.chats)
		if ([chat[@"id"] longLongValue] == chatId){
			isGroup = [chat[@"isGroup"] boolValue];
			break;
		}

	self.chatPendingDeletion = chatId;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[TGSnackbar showInView:self.navigationController.view
					  text:(isGroup ? @"Left and deleted" : @"Chat deleted")
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

#pragma mark - swipe actions

/// Swipe a row left for Mute, Archive and Delete, the way their iOS client
/// does. The API for more than a single Delete arrived in iOS 8; before that
/// rows are not swiped at all and holding one opens the same choices.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (![TGCapabilities canSwipeRowActions] || self.searchResults)
		return NO;
	NSInteger index = indexPath.row - (NSInteger)[self headerRows].count;
	return index >= 0 && index < (NSInteger)[self visibleChats].count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	// Required for the swipe to appear; the buttons below do the work.
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
	Class rowAction = NSClassFromString(@"UITableViewRowAction");
	NSInteger index = indexPath.row - (NSInteger)[self headerRows].count;
	NSArray *chats = [self visibleChats];
	if (!rowAction || index < 0 || index >= (NSInteger)chats.count)
		return @[];
	NSDictionary *chat = chats[index];
	BOOL muted = [chat[@"isMuted"] boolValue];

	__weak typeof(self) weakSelf = self;
	void (^run)(NSString *) = ^(NSString *choice){
		TGChatListViewController *me = weakSelf;
		[me.tableView setEditing:NO animated:YES];
		me.actionChat = chat;
		[me runChatAction:choice];
	};
	id delete = [rowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
										title:([chat[@"isGroup"] boolValue] ? @"Leave" : @"Delete")
									  handler:^(id action, NSIndexPath *path){ run(@"Delete"); }];
	id archive = [rowAction rowActionWithStyle:UITableViewRowActionStyleNormal
										 title:self.showsArchive ? @"Unarchive" : @"Archive"
									   handler:^(id action, NSIndexPath *path){ run(@"Archive"); }];
	[archive setBackgroundColor:[[TGTheme shared] archiveActionColour]];
	id mute = [rowAction rowActionWithStyle:UITableViewRowActionStyleNormal
									  title:muted ? @"Unmute" : @"Mute"
									handler:^(id action, NSIndexPath *path){ run(@"Mute"); }];
	[mute setBackgroundColor:[[TGTheme shared] muteActionColour]];
	// Right to left: Delete sits at the edge.
	return @[delete, archive, mute];
}

@end
