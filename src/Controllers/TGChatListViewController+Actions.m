#import "TGChatListViewControllerInternal.h"
#import "TGCapabilities.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"

/// A flick that never reached half the buttons' width still opens the row.
/// Below this the pan reads as a slow drag and the half-way rule decides.
static const CGFloat kSwipeFlickVelocity = 500.0f;

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

	// The folder list opens through TGPopupMenu, which routes plain lists to
	// a system action sheet (8e0d1b4). This spot once hit B3 on the 4S - the
	// sheet threw inside addButtonWithTitle: - which is why every parsed
	// folder title is type-checked and stays non-nil. The defensive parsing
	// remains although the parse bug itself is fixed.
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
	CGPoint where = CGPointMake(TGHalf(self.view.bounds.size.width),
								TGHalf(self.view.bounds.size.height));
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
	// Redraw the title view and the pill strip so the newly chosen tab is
	// the filled one and the name above the rows is the folder's.
	[self refreshListTitleView];
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
	// Pinned chats keep the order they are given; these two are how it is
	// given on a device with no drag-to-reorder list.
	NSArray *pinnedIds = [self pinnedChatIds];
	NSUInteger at = [pinnedIds indexOfObject:self.actionChat[@"id"]];
	if (pinned && !self.showsArchive && at != NSNotFound) {
		NSMutableArray *more = [items mutableCopy];
		if (at > 0)
			[more insertObject:@{@"title" : @"Move Up", @"icon" : @"pin"} atIndex:1];
		if (at + 1 < pinnedIds.count)
			[more insertObject:@{@"title" : @"Move Down", @"icon" : @"pin"} atIndex:(at > 0 ? 2 : 1)];
		items = more;
	}

	CGRect rect = [self.tableView rectForRowAtIndexPath:
			[NSIndexPath indexPathForRow:row inSection:0]];
	CGPoint where = [self.tableView convertPoint:
			CGPointMake(TGMetricChatListMenuX, CGRectGetMaxY(rect) - TGMetricPadMedium) toView:self.navigationController.view];

	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger choice, NSString *title){
		[weakSelf runChatAction:title];
	}];
}

/// The pinned chats of the main list, top first, as their ids.
- (NSArray *)pinnedChatIds {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *chat in [TGClient shared].chats)
		if ([chat[@"isPinned"] boolValue] && chat[@"id"])
			[ids addObject:chat[@"id"]];
	return ids;
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

	// Case-blind: "Unpin", "Unmute" and "Unarchive" end in a lower-case
	// "pin", "mute", "archive", missed every branch below and fell through to
	// the last one - deleting the chat.
	NSString *verb = action.lowercaseString;
	if ([action hasPrefix:@"Move "]) {
		NSMutableArray *ids = [[self pinnedChatIds] mutableCopy];
		NSUInteger at = [ids indexOfObject:@(chatId)];
		NSUInteger to = [action isEqualToString:@"Move Up"] ? at - 1 : at + 1;
		if (at != NSNotFound && to < ids.count) {
			[ids exchangeObjectAtIndex:at withObjectAtIndex:to];
			[[TGClient shared] setPinnedChatIds:ids];
		}
	} else if ([verb hasSuffix:@"pin"])
		[[TGClient shared] setChat:chatId
							pinned:![self.actionChat[@"isPinned"] boolValue]];
	else if ([verb hasSuffix:@"mute"])
		[[TGClient shared] setChat:chatId
							 muted:![self.actionChat[@"isMuted"] boolValue]];
	else if ([verb hasSuffix:@"archive"])
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
/// does. The API for more than a single Delete arrived in iOS 8; this is the
/// system path, and the older one lives in the section below.
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
	BOOL pinned = [chat[@"isPinned"] boolValue];
	BOOL unread = [chat[@"markedUnread"] boolValue] ||
				  [chat[@"unread"] integerValue] > 0;

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
	// Pin and read are on the same row as the two destructive verbs in the
	// official client; leaving them only in the hold menu made the swipe a
	// different tool rather than a shortcut to the same one.
	id pin = [rowAction rowActionWithStyle:UITableViewRowActionStyleNormal
									 title:pinned ? @"Unpin" : @"Pin"
								   handler:^(id action, NSIndexPath *path){ run(@"Pin"); }];
	[pin setBackgroundColor:[[TGTheme shared] muteActionColour]];
	id read = [rowAction rowActionWithStyle:UITableViewRowActionStyleNormal
									  title:unread ? @"Mark as Read" : @"Mark as Unread"
									handler:^(id action, NSIndexPath *path){
		run(unread ? @"Mark as Read" : @"Mark as Unread");
	}];
	[read setBackgroundColor:[[TGTheme shared] archiveActionColour]];
	// Right to left: Delete sits at the edge.
	return @[delete, archive, mute, pin, read];
}

#pragma mark - swipe actions before iOS 8

/// The cell that is actually open. A reload can leave the weak pointer aimed
/// at a cell already back in the reuse pool; that cell has closed itself and
/// must not swallow the next tap on the list.
- (TGChatCell *)openSwipeCell {
	TGChatCell *cell = self.swipeActionsCell;
	if (!cell || !cell.swipeActionsOpen){
		self.swipeActionsCell = nil;
		self.swipeActionsChat = nil;
		return nil;
	}
	return cell;
}

/// The same rows - and the same exclusion of search and table editing - that
/// canEditRowAtIndexPath: answers for the system's own actions above iOS 8.
- (BOOL)swipeActionsCanStartAtPath:(NSIndexPath *)path {
	if (!path || self.searchResults || self.editingChats || self.tableView.editing)
		return NO;
	NSInteger index = path.row - (NSInteger)[self headerRows].count;
	return index >= 0 && index < (NSInteger)[self visibleChats].count;
}

- (void)installLegacySwipeActions {
	// UITableViewRowAction owns the swipe from iOS 8; do not put a second
	// recognizer in its way there.
	if ([TGCapabilities canSwipeRowActions])
		return;

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(swipeActionsPan:)];
	pan.delegate = self;
	[self.tableView addGestureRecognizer:pan];
	self.swipeActionsPan = pan;
	// Vertical drags have to scroll at once; this pan decides in a few points
	// whether it is horizontal and fails itself otherwise.
	if ([self.tableView respondsToSelector:@selector(panGestureRecognizer)])
		[self.tableView.panGestureRecognizer requireGestureRecognizerToFail:pan];

	// The tap only exists to close an open row. Its delegate refuses touches
	// while no row is open, so ordinary row selection is untouched.
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(swipeActionsTableTapped:)];
	tap.delegate = self;
	tap.cancelsTouchesInView = YES;
	[self.tableView addGestureRecognizer:tap];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
	if (gesture != self.swipeActionsPan)
		return YES;

	UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gesture;
	CGPoint delta = [pan translationInView:self.tableView];
	// Leftward and flatter than it is tall: a vertical drag belongs to the
	// table, and a rightward drag has no row to uncover.
	if (delta.x >= 0 || fabs(delta.x) <= fabs(delta.y))
		return NO;

	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
			[pan locationInView:self.tableView]];
	return [self swipeActionsCanStartAtPath:path];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
	if (![gesture isKindOfClass:UITapGestureRecognizer.class])
		return YES;
	if (![self openSwipeCell])
		return NO;

	// The three action buttons sit directly under the swiped row. Taking
	// their touches would close the row before the button could run.
	TGChatCell *cell = self.swipeActionsCell;
	UIView *view = touch.view;
	return !([view isKindOfClass:UIButton.class] && [view isDescendantOfView:cell] &&
			![view isDescendantOfView:cell.contentView]);
}

- (void)swipeActionsTableTapped:(UITapGestureRecognizer *)tap {
	if (tap.state != UIGestureRecognizerStateEnded)
		return;
	// The table may still deliver the touch after the recognizer closes the
	// row; selection has to stay cancelled for that one tap.
	self.swipeActionsSuppressSelection = YES;
	[self closeSwipeActionsAnimated:YES];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		weakSelf.swipeActionsSuppressSelection = NO;
	});
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.swipeActionsCell || self.swipeActionsSuppressSelection){
		[self closeSwipeActionsAnimated:NO];
		return nil;
	}
	return indexPath;
}

- (BOOL)beginSwipeActionsAtPath:(NSIndexPath *)path {
	if (![self swipeActionsCanStartAtPath:path])
		return NO;

	NSInteger index = path.row - (NSInteger)[self headerRows].count;
	NSDictionary *chat = [self visibleChats][(NSUInteger)index];
	TGChatCell *cell = (TGChatCell *)[self.tableView cellForRowAtIndexPath:path];
	if (![cell isKindOfClass:TGChatCell.class])
		return NO;

	// Two rows open at once would leave two chat previews half hidden.
	[self closeSwipeActionsAnimated:NO];
	self.swipeActionsCell = cell;
	self.swipeActionsChat = chat;

	BOOL muted = [chat[@"isMuted"] boolValue];
	BOOL isGroup = [chat[@"isGroup"] boolValue];
	NSArray *titles = @[
		muted ? @"Unmute" : @"Mute",
		self.showsArchive ? @"Unarchive" : @"Archive",
		isGroup ? @"Leave" : @"Delete",
	];
	NSArray *colours = @[
		[[TGTheme shared] muteActionColour],
		[[TGTheme shared] archiveActionColour],
		[[TGTheme shared] destructiveColour],
	];
	[cell revealSwipeActionsWithTitles:titles colours:colours target:self
								action:@selector(swipeActionButtonTapped:)];
	return YES;
}

/// A row opened by itglegacy://swiperow: a pan cannot be sent over SSH on iOS 6.
- (void)openSwipeActionsAtRow:(NSInteger)row {
	NSIndexPath *path = [NSIndexPath indexPathForRow:row + (NSInteger)[self headerRows].count
										   inSection:0];
	if ([self beginSwipeActionsAtPath:path])
		[self.swipeActionsCell openSwipeActionsAnimated:YES];
}

- (void)swipeActionsPan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan){
		NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
				[pan locationInView:self.tableView]];
		if ([self beginSwipeActionsAtPath:path])
			[self.swipeActionsCell setSwipeActionsOffset:[pan translationInView:self.tableView].x];
		return;
	}

	TGChatCell *cell = self.swipeActionsCell;
	if (!cell)
		return;

	if (pan.state == UIGestureRecognizerStateChanged){
		[cell setSwipeActionsOffset:[pan translationInView:self.tableView].x];
		return;
	}

	CGFloat dx = [pan translationInView:self.tableView].x;
	CGPoint velocity = [pan velocityInView:self.tableView];
	BOOL open = pan.state == UIGestureRecognizerStateEnded &&
			(dx <= -TGHalf(cell.swipeActionsWidth) ||
			 velocity.x <= -kSwipeFlickVelocity);
	if (open){
		[cell openSwipeActionsAnimated:YES];
	} else {
		[self closeSwipeActionsAnimated:YES];
	}
}

/// Buttons say Unmute, Unarchive and Leave; the action names stay Mute,
/// Archive and Delete, exactly the words the iOS 8 row actions pass on.
- (void)swipeActionButtonTapped:(UIButton *)button {
	NSDictionary *chat = self.swipeActionsChat;
	TGChatCell *cell = self.swipeActionsCell;
	NSString *title = button.titleLabel.text;
	if (!chat)
		return;

	if ([title isEqualToString:@"Unmute"])
		title = @"Mute";
	else if ([title isEqualToString:@"Unarchive"])
		title = @"Archive";
	else if ([title isEqualToString:@"Leave"])
		title = @"Delete";

	self.actionChat = chat;
	[self runChatAction:title];
	[cell closeSwipeActionsAnimated:YES];
	self.swipeActionsCell = nil;
	self.swipeActionsChat = nil;
}

- (void)closeSwipeActionsAnimated:(BOOL)animated {
	TGChatCell *cell = self.swipeActionsCell;
	self.swipeActionsCell = nil;
	self.swipeActionsChat = nil;
	[cell closeSwipeActionsAnimated:animated];
}

/// A scroll of any kind - the user's drag, or a programmatic move - leaves
/// no row open.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	if (scrollView == self.tableView)
		[self closeSwipeActionsAnimated:YES];
}

/// reloadData builds or reuses cells for every visible row. Closing here is
/// what makes a reload close a swiped row even when its cell is reused.
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
		forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.swipeActionsCell)
		[self closeSwipeActionsAnimated:NO];
}

@end
