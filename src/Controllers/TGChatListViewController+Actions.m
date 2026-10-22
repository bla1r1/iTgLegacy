#import "TGChatListViewControllerInternal.h"

@implementation TGChatListViewController (Actions)

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

@end
