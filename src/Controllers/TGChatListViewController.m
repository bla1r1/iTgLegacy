#import "TGChatListViewControllerInternal.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

// Height of the folder pill strip above the chat list (official-style tabs).
static const CGFloat kFolderTabRow = TGMetricFolderTabRow;

@implementation TGChatListViewController

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
							  duration:(NSTimeInterval)duration {
	[super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
	// The search bar and the folder pill strip are built to the width at
	// header build time; a rotated screen needs both re-measured. The pills
	// live in the sticky section header, so the table has to re-ask for it.
	[self rebuildTableHeader];
	[self.tableView reloadData];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.showsArchive ? @"Archived" : @"Chats";
	// The top "Folders" button retired: the pill strip is the switcher now,
	// and every action on the list sits on the bars already.
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
	// Each row draws its own hairline from under the text; see TGChatCell.
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
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
		// While the cache fills, updates arrive in floods - one per chat.
		// A reload for each means the table re-lays out dozens of times and
		// the old 4S crawls; coalescing the floods to a few ticks keeps the
		// load quick and visibly the same.
		[NSObject cancelPreviousPerformRequestsWithTarget:weakSelf
				selector:@selector(reload) object:nil];
		[weakSelf performSelector:@selector(reload) withObject:nil afterDelay:0.3];
	};
	[TGClient shared].onArchiveChanged = ^{
		[weakSelf.tableView reloadData];
	};
	[TGClient shared].onConnectionState = ^(TGConnectionState state, NSString *text){
		NSString *line = TGNetworkSubtitleForState((NSInteger)state, text);
		// The list title reads "Chats"/"Archived"/the folder while the
		// connection is fine; the network names it otherwise. Before, READY
		// reset the title to "Chats" and a chosen folder got erased (B4).
		weakSelf.title = line ?: [weakSelf titleForCurrentList];
	};
	[self reload];
}

/// A horizontal strip of folder pills, the way the official clients show
/// them: "All chats" first, then every folder, the active one filled with
/// the accent colour. Tapping one switches the list in place - no sheet,
/// no navigation.
- (void)buildFolderTabsInto:(UIView *)header atY:(CGFloat)y width:(CGFloat)width folders:(NSArray *)folders {
	UIScrollView *strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, width, kFolderTabRow)];
	strip.showsHorizontalScrollIndicator = NO;
	strip.alwaysBounceHorizontal = YES;
	strip.backgroundColor = [UIColor clearColor];
	[header addSubview:strip];

	UIFont *font = TGFontCaptionStrong();
	CGFloat x = 8;
	for (NSInteger i = 0; i <= (NSInteger)folders.count; i++){
		NSString *title = nil;
		if (i > 0)
			title = [folders[i - 1] isKindOfClass:NSDictionary.class]
					? folders[i - 1][@"title"] : nil;
		NSString *label = (i == 0) ? @"All chats" : nil;
		if (!label)
			label = [title isKindOfClass:NSString.class] && title.length
					? title : @"Folder";
		BOOL active = (i == 0 && self.folderId == 0) ||
				(i > 0 && [folders[i - 1] isKindOfClass:NSDictionary.class] &&
				 [folders[i - 1][@"id"] integerValue] == self.folderId);
		CGFloat w = MIN([label sizeWithFont:font].width + 26, 150);
		UIButton *pill = [UIButton buttonWithType:UIButtonTypeCustom];
		pill.frame = CGRectMake(x, 5, w, kFolderTabRow - 10);
		pill.tag = 100 + i;
		[pill setTitle:label forState:UIControlStateNormal];
		pill.titleLabel.font = font;
		pill.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		pill.layer.cornerRadius = TGHalf(kFolderTabRow - TGDoubled(TGMetricPadMedium));
		if (active){
			[pill setBackgroundColor:[[TGTheme shared] accentColour]];
			[pill setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		} else {
			[pill setBackgroundColor:[[TGTheme shared] cardBackgroundColour]];
			[pill setTitleColor:[[TGTheme shared] primaryTextColour]
					   forState:UIControlStateNormal];
			pill.layer.borderWidth = TGMetricHairline;
			pill.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
		}
		[pill addTarget:self action:@selector(folderTabTapped:)
			  forControlEvents:UIControlEventTouchUpInside];
		if (i > 0){
			// A folder pill can be picked up and put elsewhere: held long
			// enough it follows the finger, and wherever it drops is the
			// order the strip keeps. "All chats" stays first - its slot is
			// what main_chat_list_position says, and the strip never moves.
			UILongPressGestureRecognizer *drag =
					[[UILongPressGestureRecognizer alloc]
					initWithTarget:self action:@selector(folderDragged:)];
			drag.minimumPressDuration = 0.45;
			[pill addGestureRecognizer:drag];
		}
		[strip addSubview:pill];
		x += w + 6;
	}

	strip.contentSize = CGSizeMake(x, kFolderTabRow);
}

/// The rightmost pill (index folders.count + 1) opens the archive; every
/// other index is a regular folder switch.
- (void)folderTabTapped:(UIButton *)pill {
	NSLog(@"TGClient: B3 pill tag=%ld folders=%lu", (long)pill.tag,
			(unsigned long)[TGClient shared].folders.count);
	[self runFolderChoice:pill.tag - 100];
}

/// A held pill follows the finger; where it drops is its new slot among the
/// folders. The strip's own scrolling is pinned shut while a pill is up -
/// otherwise the pan gesture and the drag fight over one finger.
- (void)folderDragged:(UILongPressGestureRecognizer *)gesture {
	UIButton *pill = (UIButton *)gesture.view;
	UIScrollView *strip = (UIScrollView *)pill.superview;
	if (![strip isKindOfClass:UIScrollView.class] || pill.tag <= 100)
		return;

	if (gesture.state == UIGestureRecognizerStateBegan){
		CGPoint here = [gesture locationInView:pill];
		self.folderDragOffset = here.x - TGHalf(pill.bounds.size.width);
		self.folderDragFrame = pill.frame;
		strip.scrollEnabled = NO;
		pill.transform = CGAffineTransformMakeScale(TGTransformScalePillActive, TGTransformScalePillActive);
		pill.alpha = TGAlphaPillInactive;
	}
	else if (gesture.state == UIGestureRecognizerStateChanged){
		CGPoint here = [gesture locationInView:strip];
		// Content coordinates: a pill's frame lives where the strip scrolls
		// over, and the finger's x is in the visible half of it.
		CGFloat x_in_content = here.x - strip.contentOffset.x
				- self.folderDragOffset;
		CGFloat first = TGMetricPad, last = strip.contentSize.width
				- self.folderDragFrame.size.width - TGMetricPad;
		if (x_in_content < first) x_in_content = first;
		if (x_in_content > last)  x_in_content = last;
		pill.frame = CGRectMake(x_in_content, self.folderDragFrame.origin.y,
				self.folderDragFrame.size.width,
				self.folderDragFrame.size.height);
	}
	else if (gesture.state == UIGestureRecognizerStateEnded ||
			 gesture.state == UIGestureRecognizerStateCancelled){
		strip.scrollEnabled = YES;
		pill.transform = CGAffineTransformIdentity;
		pill.alpha = TGAlphaOpaque;

		BOOL cancelled = gesture.state == UIGestureRecognizerStateCancelled;
		if (cancelled){
			[self.tableView reloadData];   // back where the data says
			return;
		}

		// The slot is where the pill's centre sits among the other pills:
		// every centre it cleared on the way over counts as a slot ahead.
		NSArray *folders = [TGClient shared].folders;
		NSInteger from = pill.tag - 101;
		if (from < 0 || from >= (NSInteger)folders.count)
			return;
		CGPoint centreInStrip = [gesture locationInView:strip];
		CGFloat centre = centreInStrip.x - strip.contentOffset.x;
		NSInteger slot = 0;
		for (NSInteger i = 0; i < (NSInteger)folders.count; i++){
			if (i == from)
				continue;
			UIView *other = [strip viewWithTag:101 + i];
			if (!other)
				continue;
			if (other.center.x < centre)
				slot++;
		}
		if (slot == from){
			[self.tableView reloadData];   // a hand back down on its slot
			return;
		}

		NSMutableArray *order = [NSMutableArray array];
		// The dragged one leaves the line, then comes back wherever the
		// drop said - the slot already counts what stayed left of the
		// pill's centre on both readings of "left".
		[folders enumerateObjectsUsingBlock:^(NSDictionary *folder, NSUInteger idx,
											  BOOL *stop __unused){
			if ((NSInteger)idx != from)
				[order addObject:@([folder[@"id"] integerValue])];
		}];
		[order insertObject:folders[from][@"id"]
					atIndex:MIN(slot, (NSInteger)order.count)];
		[[TGClient shared] reorderFoldersToLocalIds:order mainListAt:0];
		[self.tableView reloadData];
	}
}

/// Sticky section header. In a plain table the pinning keeps the pill strip
/// at the top edge while the chat list scrolls beneath it, so the folder
/// switcher outlives the collapsing search header - after the chats load,
/// hideHeaderAboveFrom still parks the big header above the fold, as it
/// always has, and the pills are no longer riding along with it.
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (self.showsArchive || [TGClient shared].folders.count == 0)
		return 0;
	return kFolderTabRow;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (self.showsArchive || [TGClient shared].folders.count == 0)
		return nil;
	UIView *strip = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
			tableView.bounds.size.width ?: 320, kFolderTabRow)];
	strip.backgroundColor = [[TGTheme shared] listBackgroundColour];
	[self buildFolderTabsInto:strip atY:0 width:strip.bounds.size.width
			folders:[TGClient shared].folders];
	return strip;
}

- (void)rebuildTableHeader {
	// Search alone in the collapsing header now; the archive strip lives in
	// the table as the first row (see headerRows) and hides behind the
	// pinned pills on load - hideHeaderAboveFrom parks both of them.
	CGFloat width = self.tableView.bounds.size.width ?: 320;
	UIColor *bg = [[TGTheme shared] listBackgroundColour];

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44)];
	header.backgroundColor = bg;
	self.searchBar.frame = CGRectMake(0, 0, width, 44);
	[header addSubview:self.searchBar];

	CGFloat wasHidingHeader = self.headerHeight;
	self.tableView.tableHeaderView = header;
	self.headerHeight = 44;
	// Once the chats load the park jumps past the search bar AND the archive
	// strip: scroll past both and the pinned pills sit alone over the rows,
	// because the chat rows start exactly at the band's lower edge. A pull
	// down walks both of them back into view.
	BOOL archiveParked = [[self headerRows] containsObject:@"archive"];
	self.parkOffset = 44 + (archiveParked ? kRowHeight : 0);
	[self hideHeaderAboveFrom:wasHidingHeader];
}

/// "All chats" is the union of the main list and every folder's chats.
/// The folder asks run in parallel; whatever each returns that the
/// list has not seen yet joins the merge. The result refreshes the table
/// only while the user is still looking at All chats.
- (void)mergeAllFolderChats {
	if (self.showsArchive || self.folderId != 0)
		return;

	NSString *sig = [NSString stringWithFormat:@"c%lu f%lu",
			(unsigned long)[TGClient shared].chatsCached,
			(unsigned long)[TGClient shared].folders.count];
	if (!self.mergedChats &&
			![sig isEqualToString:self.mergedSignature]) {
		// first pass, wait for the chain
	} else if ([sig isEqualToString:self.mergedSignature]) {
		// nothing new for the merge to gather
		return;
	}

	NSMutableArray *folders = [NSMutableArray arrayWithArray:
			[TGClient shared].folders];
	if (!folders.count){
		self.mergedChats = [TGClient shared].chats;
		self.mergedSignature = sig;
		return;
	}

	if (self.mergeInFlight)
		return;
	self.mergeInFlight = YES;

	NSArray *base = [TGClient shared].chats ?: @[];
	NSMutableArray *merged = [NSMutableArray arrayWithArray:base];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *c in merged){
		id cid = c[@"id"];
		if (cid)
			[seen addObject:[NSString stringWithFormat:@"%@", cid]];
	}

	__weak typeof(self) weakSelf = self;
	NSString *signature = sig;
	__block NSInteger pendings = 0;
	dispatch_group_t group = dispatch_group_create();
	// The asks run together: one round trip per folder at once instead of
	// a chain where each folder waits for the one before it.
	for (NSDictionary *folder in folders){
		NSInteger askId = [folder[@"id"] integerValue];
		dispatch_group_enter(group);
		[[TGClient shared] chatsInFolder:askId completion:^(NSArray *chats){
			for (NSDictionary *c in chats){
				// A folder may hold archived chats too (the archive is a
				// flag, not a separate bucket from the folders); they belong
				// to the archive strip, not to All chats. Pending entries -
				// ids tdlib named in the folder but has not described yet -
				// wait for the retry below instead of joining the list.
				if ([c[@"pending"] boolValue]){
					pendings++;
					continue;
				}
				if ([c[@"archiveOrder"] longLongValue] > 0)
					continue;
				NSString *key = [NSString stringWithFormat:@"%@", c[@"id"]];
				if (key.length && ![seen containsObject:key]){
					[seen addObject:key];
					[merged addObject:c];
				}
			}
			dispatch_group_leave(group);
		}];
	}
	// The completions above all land on the main queue, so merged, seen and
	// pendings stay single-threaded.
	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		if (!weakSelf || weakSelf.folderId != 0){
			weakSelf.mergeInFlight = NO;
			weakSelf.mergedChats = nil;
			weakSelf.mergedSignature = nil;
			return;
		}
		// Pinned first, then newest last message first: the merge
		// appended the folders after the main list, and without a sort
		// All chats read like a grab bag. Within the pinned block the
		// same date rule applies, so the order stays stable.
		NSArray *combined = [merged sortedArrayUsingComparator:
				^NSComparisonResult(NSDictionary *a, NSDictionary *b){
			BOOL pa = [a[@"isPinned"] boolValue], pb = [b[@"isPinned"] boolValue];
			if (pa != pb)
				return pa ? NSOrderedAscending : NSOrderedDescending;
			if (pa){
				// A pin keeps its slot through newer messages: the sort
				// inside the pinned block reads tdlib's position order,
				// not the message date.
				int64_t oa = [a[@"order"] longLongValue];
				int64_t ob = [b[@"order"] longLongValue];
				if (oa != ob)
					return oa > ob ? NSOrderedAscending : NSOrderedDescending;
			}
			int64_t da = [a[@"date"] longLongValue], db = [b[@"date"] longLongValue];
			if (da == db)
				return NSOrderedSame;
			return da > db ? NSOrderedAscending : NSOrderedDescending;
		}];
		weakSelf.mergedChats = combined;
		// A folder answer that dropped unseen ids is not the whole
		// picture: withholding the signature makes the next pass run
		// again, and a short retry covers a silent cache (no chat
		// update will fire onChatsChanged meanwhile).
		weakSelf.mergedSignature = pendings ? nil : signature;
		weakSelf.mergeInFlight = NO;
		[weakSelf.tableView reloadData];
		[weakSelf fetchMissingAvatars];
		if (pendings){
			[NSObject cancelPreviousPerformRequestsWithTarget:weakSelf
					selector:@selector(mergeAllFolderChats) object:nil];
			[weakSelf performSelector:@selector(mergeAllFolderChats)
						   withObject:nil afterDelay:1.0];
		}
	});
}

- (void)hideHeaderAboveFrom:(CGFloat)previousHeight {
	// The user pulled the strip out themselves and left it there; parking
	// again on the next cache tick would snap it shut under their eyes.
	if (self.userRevealed)
		return;
	// reloadData does not refresh contentSize until the next layout pass;
	// measuring here reads the pre-reload size and misjudges the park. Lay
	// the table out first, then decide.
	[self.tableView layoutIfNeeded];
	NSLog(@"TGClient: park? content=%0.0f bounds=%0.0f y=%0.0f prev=%0.0f park=%0.0f rows=%lu",
			self.tableView.contentSize.height,
			self.tableView.bounds.size.height,
			self.tableView.contentOffset.y, previousHeight,
			self.parkOffset, (unsigned long)[self headerRows].count);
	if (self.tableView.contentSize.height <= self.tableView.bounds.size.height)
		return;
	CGFloat y = self.tableView.contentOffset.y;
	if (y > TGMetricHairline && fabs(y - previousHeight) > TGMetricHairline)
		return;
	self.tableView.contentOffset = CGPointMake(0, self.parkOffset);
}

/// Returning to the top after the archive strip has been scrolled away
/// settles on the park again - the official client hides the strip once the
/// list has been walked, and only a deliberate pull down reveals it.
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
					 withVelocity:(CGPoint)velocity
		  targetContentOffset:(inout CGPoint *)targetContentOffset {
	if (self.searchResults || self.showsArchive || self.folderId != 0)
		return;
	if (![[self headerRows] containsObject:@"archive"])
		return;
	CGFloat from = scrollView.contentOffset.y;
	CGFloat target = targetContentOffset->y;
	if (target < self.parkOffset - 20){
		if (from > self.parkOffset + 1){
			// walking back to the top after the strip was scrolled away:
			// settle on the park and wake up to hide it again later
			self.userRevealed = NO;
			targetContentOffset->y = self.parkOffset;
			[scrollView setContentOffset:CGPointMake(0, self.parkOffset)
								animated:YES];
		} else {
			// a deliberate pull upward from the park into the reveal zone:
			// the strip stays until the list gets walked again
			self.userRevealed = YES;
		}
	}
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
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"New Message", @"New Group", @"Join by Invite Link"]
						title:nil
			 destructiveIndex:-1
					   inView:self.navigationController.view ?: self.view
					 onChoice:^(NSInteger index){
		TGChatListViewController *me = weakSelf;
		if (index != 2){
			TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
			if (index == 1)
				contacts.picksGroupMembers = YES;
			else
				contacts.title = @"New Message";
			[me.navigationController pushViewController:contacts animated:YES];
			return;
		}
		// A link is joined from anywhere: the sheet starts from the
		// pasteboard, which is where a copied link already sits.
		[TGAlertSheet showInput:@"Join by Invite Link"
						message:nil
					placeholder:@"t.me/joinchat/… or t.me/+…"
						   text:[UIPasteboard generalPasteboard].string
						 action:@"Check"
						 inView:me.view
					   onSubmit:^(NSString *link){
			[me joinByInviteLink:link];
		}];
	}];
}

/// A pasted t.me link joined: what it is first, then the chat. The account
/// already in the chat does not join again - it only opens it.
- (void)joinByInviteLink:(NSString *)rawLink {
	NSString *link = [rawLink stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (![link hasPrefix:@"http"])
		link = [@"https://" stringByAppendingString:link];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] checkInviteLink:link completion:
			^(NSString *title, NSInteger members, BOOL alreadyMember){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		if (!title.length){
			[TGAlertSheet showMessage:@"That link answers nothing - expired, "
									  @"revoked, or mistyped."
								title:@"Invite Link" inView:me.view];
			return;
		}
		NSString *say = [NSString stringWithFormat:@"%@ · %ld members",
						 title, (long)members];
		NSString *action = alreadyMember ? @"Open Chat" : @"Join";
		[TGAlertSheet showConfirm:say
							title:@"Invite Link"
						   action:action
					  destructive:NO
						   inView:me.view
						onConfirm:^{
			TGChatListViewController *inner = weakSelf;
			[[TGClient shared] joinChatByInviteLink:link completion:^(int64_t chatId, NSString *name){
				if (!chatId){
					if (inner)
						[TGAlertSheet showMessage:@"Telegram refused the join."
											title:@"Invite Link" inView:inner.view];
					return;
				}
				dispatch_async(dispatch_get_main_queue(), ^{
					TGChatListViewController *after = weakSelf;
					if (!after)
						return;
					// The chat appears in the list with the update; it is
					// used straight out of it when it has arrived, forced
					// into the shape a joined group has when it has not.
					NSDictionary *found = nil;
					for (NSDictionary *c in [TGClient shared].chats)
						if ([c[@"id"] longLongValue] == chatId){
							found = c;
							break;
						}
					NSDictionary *c = found ?: (@{@"id" : @(chatId),
												  @"title" : (name ?: title ?: @""),
												  @"isGroup" : @YES});
					[after openChatInfo:c];
				});
			}];
		}];
	}];
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

	// "All chats" means all of them: tdlib's chatListMain holds only the
	// chats with no folder, the rest lives behind chatListFolder requests.
	// The merge below fills the gap in the background.
	self.chats = self.mergedChats ?: [TGClient shared].chats;
	[self.tableView reloadData];
	[self rebuildTableHeader];
	[self fetchMissingAvatars];
	[self mergeAllFolderChats];
}

/// Chat list header rows. The archive strip sits below the pinned pills as
/// the first row of the list, and the initial scroll parks it behind the
/// pills band, so All chats opens clean and the strip needs a pull down.
/// The strip only joins once the list holds enough rows to park it: a bare
/// start (archive row drawn over an empty list) parks nothing and the strip
/// would sit there for the whole load.
- (NSArray *)headerRows {
	if (self.searchResults || self.showsArchive || self.folderId != 0)
		return @[];
	if ([TGClient shared].archivedChats.count > 0 && self.chats.count > 9)
		return @[@"archive"];
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
		// The mark follows the request from start to finish: set here, and
		// lifted on a nil callback, so a watchdog timeout or a lost download
		// reads as "ask me again on the next pass" instead of leaving the
		// avatar a placeholder forever (B2).
		[self.avatarsRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue]
							   priority:TGDownloadPriorityAvatar
							 completion:^(NSString *path){
			if (!path){
				TGChatListViewController *me = weakSelf;
				[me.avatarsRequested removeObject:fileId];
				return;
			}
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
	cell.dateLabel.textColor = [theme listDateColour];
	cell.onlineDot.hidden = YES;
	cell.tick.hidden = YES;
	cell.muteIcon.hidden = YES;
	cell.pin.hidden = YES;
	cell.onlineDot.layer.borderColor = bg.CGColor;
	cell.separator.backgroundColor = [theme separatorColour];

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
	} else if (c[@"previewText"]){
		[cell setPreview:c[@"previewText"] author:c[@"lastAuthor"]];
	} else {
		cell.previewLabel.text = c[@"text"];
	}

	cell.onlineDot.hidden = ![c[@"isOnline"] boolValue];

	// Your own last message shows whether it has been read, beside the date.
	// Saved Messages has no one to read it.
	if ([c[@"lastOutgoing"] boolValue] && ![c[@"isSaved"] boolValue] && ![action length]){
		BOOL read = [c[@"lastId"] longLongValue] <= [c[@"readOutbox"] longLongValue];
		cell.tick.image = [TGIcons ticksColour:[theme ticksColour] read:read];
		cell.tick.hidden = NO;
	}

	// A muted chat carries a small speaker after its title; a pinned one keeps
	// a marker where the badge sits when it has none.
	BOOL muted = [c[@"isMuted"] boolValue];
	cell.muteIcon.hidden = !muted;
	if (muted)
		cell.muteIcon.image = [TGIcons glyphNamed:@"mute" colour:[theme listDateColour] side:28];

	NSInteger unread = [c[@"unread"] integerValue];
	cell.badge.hidden = (unread <= 0);
	cell.pin.hidden = !([c[@"isPinned"] boolValue] && unread <= 0);
	if (!cell.pin.hidden)
		cell.pin.image = [TGIcons glyphNamed:@"pin" colour:[theme listDateColour] side:28];
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
	[self openChatInfo:c];
}

/// The one place a chat dictionary becomes a screen: the forum check is what
/// decides a topics list from a plain chat, and both push the same way.
- (void)openChatInfo:(NSDictionary *)c {
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

/// The system's caption is grey on grey over a dark list, which is what
/// this screen had: every other list styles its own.
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

@end
