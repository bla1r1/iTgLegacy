#import "TGChatListViewControllerInternal.h"
#import "TGPerf.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGDevShowcase.h"
#import "TGFastDate.h"
#import "TGOptions.h"
#import "TGStoryViewerViewController.h"
#import "TGStoryComposerViewController.h"
#import "TGStoriesMenuViewController.h"
#import "TGChatListRowGeometry.h"

// Height of the folder pill strip above the chat list (official-style tabs).
static const CGFloat kFolderTabRow = TGMetricFolderTabRow;
/// The mute and pin marks on a row are drawn at this side and then fitted into
/// the smaller box the cell gives them, which is what keeps their strokes even.
static const CGFloat kRowGlyph     = 28.0f;
/// The title view's box: the name, then the connection line under it. 200 pt
/// is the chat header's width on the same 320 pt bar, so neither nav button
/// loses its target to a long folder name.
static const CGFloat kListTitleWidth  = 200.0f;
static const CGFloat kListTitleHeight = TGMetricRow;
/// The archive pill's tag, outside the folder indexes (100 + slot).
static const NSInteger kFolderArchiveTag = 1000;
/// A folder pill's side padding, its widest form and the gap to the next pill.
static const CGFloat kFolderPillPad = 26.0f;
static const CGFloat kFolderPillMax = 150.0f;
static const CGFloat kFolderPillGap = 6.0f;

@implementation TGChatListViewController

/// The first frame after a launch used to be an empty table until TDLib
/// answered loadChats - seconds on the A4 when the cache is cold. The last
/// painted list is written here and drawn again on the next start; the live
/// list replaces it as soon as it arrives.
static NSString *TGChatSnapshotPath(void) {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	return [dir stringByAppendingPathComponent:@"chat-list-snapshot.plist"];
}

/// Only primitive fields go to the plist. chatsById also holds TDLib records
/// (permissions, action bar, background) that are not plist values and are
/// not read by a list row.
static NSDictionary *TGChatSnapshotRow(NSDictionary *chat) {
	static NSArray *keys = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[@"id", @"title", @"date", @"text", @"previewText", @"lastAuthor",
				@"unread", @"unreadMentions", @"markedUnread", @"isMuted",
				@"isPinned", @"isOnline", @"isSaved", @"lastId", @"lastOutgoing",
				@"readOutbox", @"readInbox", @"photoFileId", @"isGroup", @"isForum",
				@"isSecret", @"order", @"archiveOrder", @"supergroupId", @"draft"];
	});
	NSMutableDictionary *row = [NSMutableDictionary dictionaryWithCapacity:keys.count];
	for (NSString *key in keys){
		id value = chat[key];
		if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class])
			row[key] = value;
	}
	return row[@"id"] ? row : nil;
}

- (NSArray *)loadChatSnapshot {
	NSArray *rows = [NSArray arrayWithContentsOfFile:TGChatSnapshotPath()];
	if (![rows isKindOfClass:NSArray.class])
		return @[];
	NSMutableArray *chats = [NSMutableArray arrayWithCapacity:rows.count];
	for (NSDictionary *row in rows)
		if ([row isKindOfClass:NSDictionary.class] && row[@"id"])
			[chats addObject:row];
	return chats;
}

- (void)saveChatSnapshot:(NSArray *)chats {
	if (!chats.count)
		return;
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.snapshotWrittenAt < 5.0)
		return;
	self.snapshotWrittenAt = now;
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:chats.count];
	for (NSDictionary *chat in chats){
		NSDictionary *row = TGChatSnapshotRow(chat);
		if (row)
			[rows addObject:row];
	}
	if (!rows.count)
		return;
	NSString *path = TGChatSnapshotPath();
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		[rows writeToFile:path atomically:YES];
	});
}

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
	[self buildListTitleView];
	[self refreshListTitleView];
	// The last list is drawn before TDLib answers, so a cold start is the
	// previous conversation list rather than a blank screen.
	self.cachedChats = (self.showsArchive || self.folderId != 0)
			? @[] : [self loadChatSnapshot];
	self.chats = self.cachedChats;
	self.avatars = [[TGImageLruCache alloc] initWithCapacity:50];
	self.avatarsRequested = [NSMutableSet set];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
				   target:self action:@selector(composeTapped)];

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, TGMetricScreenWidth, TGMetricRow)];
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
		[weakSelf refreshListTitleView];
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
		// The list keeps its name; the network line is the second line of the
		// title view. Replacing the title took a chosen folder away on every
		// reconnect (B4), and the state is not what the screen is.
		weakSelf.connectionLine = TGNetworkSubtitleForState((NSInteger)state, text);
		[weakSelf refreshListTitleView];
	};
	[self reload];
}

/// The two lines at the top of the list. The name is always there; the
/// connection line appears under it only while TDLib is not ready, the way the
/// official client keeps "Chats" and breathes "Connecting..." beneath it.
- (void)buildListTitleView {
	UIView *box = [[UIView alloc] initWithFrame:CGRectMake(TGMetricZero, TGMetricZero,
			kListTitleWidth, kListTitleHeight)];
	box.backgroundColor = [UIColor clearColor];

	UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricZero,
			TGMetricBorderWidth, kListTitleWidth, TGMetricLineRow)];
	name.font = TGFontHeader();
	name.textColor = [[TGTheme shared] barTitleColour];
	name.backgroundColor = [UIColor clearColor];
	name.textAlignment = NSTextAlignmentCenter;
	name.lineBreakMode = NSLineBreakByTruncatingTail;
	name.shadowColor = [[TGTheme shared] navBarTextShadowColour];
	name.shadowOffset = TGMetricShadowOffsetNav;
	[box addSubview:name];

	UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricZero,
			TGMetricBorderWidth + TGMetricLineRow, kListTitleWidth,
			TGMetricLineMicro)];
	subtitle.font = TGFontMeta();
	subtitle.textColor = [[TGTheme shared] barSubtitleColour];
	subtitle.backgroundColor = [UIColor clearColor];
	subtitle.textAlignment = NSTextAlignmentCenter;
	subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
	subtitle.hidden = YES;
	[box addSubview:subtitle];

	self.listTitleView = box;
	self.listTitleLabel = name;
	self.listSubtitleLabel = subtitle;
	self.navigationItem.titleView = box;
}

- (void)refreshListTitleView {
	if (!self.listTitleView)
		[self buildListTitleView];

	NSString *name = [self titleForCurrentList];
	BOOL hasLine = self.connectionLine.length > 0;
	self.title = name;
	self.listTitleLabel.text = name;
	self.listSubtitleLabel.text = hasLine ? self.connectionLine : @"";
	self.listSubtitleLabel.hidden = !hasLine;
	// One line centres itself in the bar; two share it, the name on top and
	// the network beneath, which is the same stack the chat header uses.
	self.listTitleLabel.frame = CGRectMake(TGMetricZero,
			hasLine ? TGMetricBorderWidth : TGCenteredOrigin(kListTitleHeight,
					TGMetricLineRow),
			kListTitleWidth, TGMetricLineRow);
	self.listTitleLabel.textColor = [[TGTheme shared] barTitleColour];
	self.listTitleLabel.shadowColor = [[TGTheme shared] navBarTextShadowColour];
	self.listSubtitleLabel.textColor = [[TGTheme shared] barSubtitleColour];
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
		NSString *label = (i == 0) ? @"All" : nil;
		if (!label)
			label = [title isKindOfClass:NSString.class] && title.length
					? title : @"Folder";
		BOOL active = (i == 0 && self.folderId == 0) ||
				(i > 0 && [folders[i - 1] isKindOfClass:NSDictionary.class] &&
				 [folders[i - 1][@"id"] integerValue] == self.folderId);
		CGFloat w = MIN([label sizeWithFont:font].width + kFolderPillPad, kFolderPillMax);
		UIButton *pill = [UIButton buttonWithType:UIButtonTypeCustom];
		// One expression for the height, used again for the radius below: a
		// capsule is half of whatever this comes to.
		CGFloat pillHeight = kFolderTabRow - TGDoubled(TGMetricFolderPillInset);
		pill.frame = CGRectMake(x, TGMetricFolderPillInset, w, pillHeight);
		pill.tag = 100 + i;
		[pill setTitle:label forState:UIControlStateNormal];
		pill.titleLabel.font = font;
		pill.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		pill.layer.cornerRadius = TGHalf(pillHeight);
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
		x += w + kFolderPillGap;
	}

	// The archive is a list too, and the strip is where the folders are
	// switched; leaving it out meant a small account had no archive at all
	// until the list grew past the point that used to reveal the strip.
	if ([TGClient shared].archivedChats.count > 0){
		NSString *label = @"Archived";
		CGFloat w = MIN([label sizeWithFont:font].width + kFolderPillPad, kFolderPillMax);
		UIButton *pill = [UIButton buttonWithType:UIButtonTypeCustom];
		CGFloat pillHeight = kFolderTabRow - TGDoubled(TGMetricFolderPillInset);
		pill.frame = CGRectMake(x, TGMetricFolderPillInset, w, pillHeight);
		pill.tag = kFolderArchiveTag;
		[pill setTitle:label forState:UIControlStateNormal];
		pill.titleLabel.font = font;
		pill.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
		pill.layer.cornerRadius = TGHalf(pillHeight);
		[pill setBackgroundColor:[[TGTheme shared] cardBackgroundColour]];
		[pill setTitleColor:[[TGTheme shared] primaryTextColour]
				   forState:UIControlStateNormal];
		pill.layer.borderWidth = TGMetricHairline;
		pill.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
		[pill addTarget:self action:@selector(folderTabTapped:)
			  forControlEvents:UIControlEventTouchUpInside];
		[strip addSubview:pill];
		x += w + kFolderPillGap;
	}

	strip.contentSize = CGSizeMake(x, kFolderTabRow);
}

/// The archive pill carries a tag outside the folder indexes, so it never
/// goes through runFolderChoice:; every other index is a regular switch.
- (void)folderTabTapped:(UIButton *)pill {
	if (pill.tag == kFolderArchiveTag){
		[self openArchive];
		return;
	}
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
			tableView.bounds.size.width ?: TGMetricScreenWidth, kFolderTabRow)];
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

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, TGMetricRow)];
	header.backgroundColor = bg;
	self.searchBar.frame = CGRectMake(0, 0, width, TGMetricRow);
	[header addSubview:self.searchBar];

	CGFloat wasHidingHeader = self.headerHeight;
	self.tableView.tableHeaderView = header;
	self.headerHeight = 44;
	// Once the chats load the park jumps past the search bar AND the archive
	// strip: scroll past both and the pinned pills sit alone over the rows,
	// because the chat rows start exactly at the band's lower edge. A pull
	// down walks both of them back into view.
	BOOL archiveParked = [[self headerRows] containsObject:@"archive"];
	// The stories strip is the first row and has to stay reachable after the
	// list loads; parking past it would hide Add Story behind a pull. So the
	// archive strip rides below it at the same park instead of being hidden.
	BOOL storiesFirst = [[[self headerRows] firstObject] isEqualToString:@"stories"];
	self.parkOffset = 44 + (archiveParked && !storiesFirst ? kRowHeight : 0);
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
		[weakSelf saveChatSnapshot:combined];
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
	[TGAlertSheet showChoices:@[@"New Message", @"New Group", @"New Channel",
								@"Join by Invite Link"]
						title:nil
			 destructiveIndex:-1
					   inView:self.navigationController.view ?: self.view
					 onChoice:^(NSInteger index){
		TGChatListViewController *me = weakSelf;
		if (index == 2){
			// A channel is a supergroup with one voice: TDLib names both with
			// one request, and the is_channel flag is the whole difference.
			[TGAlertSheet showInput:@"New Channel"
							message:@"A channel posts to subscribers. Anyone "
									@"with the link can read; only admins write."
						placeholder:@"Channel name"
							   text:nil
							 action:@"Create"
							 inView:me.view
						 onSubmit:^(NSString *title){
				[[TGClient shared] createSupergroupNamed:title
											description:@""
											  isChannel:YES
											 completion:^(int64_t chatId){
					if (!chatId)
						return;
					TGChatViewController *vc = [[TGChatViewController alloc] init];
					vc.chatId = chatId;
					vc.chatTitle = title;
					vc.hidesBottomBarWhenPushed = YES;
					[me.navigationController pushViewController:vc animated:YES];
				}];
			}];
			return;
		}
		if (index != 3){
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

	// A folder link is a different object behind the same t.me host. It is
	// checked first and adopted, not joined: addChatFolderByInviteLink is
	// what turns it into a pill on this screen.
	if ([link rangeOfString:@"/addlist/"].location != NSNotFound){
		[[TGClient shared] checkFolderInviteLink:link completion:^(NSDictionary *folder){
			TGChatListViewController *me = weakSelf;
			if (!me)
				return;
			if (!folder){
				[TGAlertSheet showMessage:@"That folder link answers nothing."
									title:@"Folder Link" inView:me.view];
				return;
			}
			NSArray *missing = folder[@"missing"] ?: @[];
			NSString *say = [NSString stringWithFormat:@"%@ · %lu chats to add",
					folder[@"name"] ?: @"Shared folder",
					(unsigned long)missing.count];
			[TGAlertSheet showConfirm:say title:@"Folder Link" action:@"Add"
						  destructive:NO inView:me.view onConfirm:^{
				[[TGClient shared] addFolderByInviteLink:link chatIds:missing
											 completion:^(BOOL ok){
					if (!ok)
						[TGAlertSheet showMessage:@"Telegram refused that folder."
											title:@"Folder Link" inView:weakSelf.view];
				}];
			}];
		}];
		return;
	}

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
	NSArray *baseChats = self.mergedChats ?: [TGClient shared].chats;
	if (!baseChats.count && self.cachedChats.count)
		baseChats = self.cachedChats;
	// Once the live list is here the snapshot has done its job; keeping it
	// would let a logout or a cleared account bring the old rows back.
	if ([TGClient shared].chats.count)
		self.cachedChats = @[];
	NSMutableArray *list = [NSMutableArray array];
	BOOL hasShowcase = NO;
	for (NSDictionary *c in baseChats) {
		if ([TGDevShowcase isDevChatId:[c[@"id"] longLongValue]]) {
			hasShowcase = YES;
			break;
		}
	}
	if (!hasShowcase) {
		[list addObjectsFromArray:[TGDevShowcase allShowcaseChats]];
	}
	[list addObjectsFromArray:baseChats];
	self.chats = list;
	[self reloadStoriesIfNeeded];
	[self.tableView reloadData];
	[self rebuildTableHeader];
	[self fetchMissingAvatars];
	if ([TGClient shared].chats.count)
		[self saveChatSnapshot:baseChats];
	[self mergeAllFolderChats];

	BOOL hasContent = ([self visibleChats].count > 0 || self.searchResults != nil || [self headerRows].count > 0);
	if (!hasContent) {
		if (!self.emptyView) {
			self.emptyView = [TGEmptyView emptyViewWithFrame:self.view.bounds
			                                           image:[TGIcons emptyChatsIllustration]
			                                           title:@"No chats yet"
			                                        subtitle:@"Start a conversation, join a group,\nor follow a channel."
			                                     buttonTitle:@"Start Messaging"
			                                          target:self
			                                          action:@selector(composeTapped)];
			[self.view addSubview:self.emptyView];
		}
		self.emptyView.hidden = NO;
	} else if (self.emptyView) {
		self.emptyView.hidden = YES;
	}
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
	NSMutableArray *rows = [NSMutableArray arrayWithObject:@"stories"];
	if ([TGClient shared].archivedChats.count > 0)
		[rows addObject:@"archive"];
	return rows;
}

- (BOOL)hasArchiveRow {
	return NO;
}

/// The strip is re-read at most once every half minute: the chat list reloads
/// on every chat update, and each refresh here is one request per chat.
- (void)reloadStoriesIfNeeded {
	if (self.showsArchive || self.folderId != 0 || self.storyRowsLoading)
		return;
	if (self.storyRowsReadAt &&
		-[self.storyRowsReadAt timeIntervalSinceNow] < 30.0)
		return;
	self.storyRowsLoading = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] activeStoryRowsForList:@"main" completion:^(NSArray *rows){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		me.storyRows = rows ?: @[];
		me.storyRowsReadAt = [NSDate date];
		me.storyRowsLoading = NO;
		[me.tableView reloadData];
		[me fetchMissingAvatars];
	}];
}

- (void)showStoryRow:(NSDictionary *)row {
	NSArray *infos = row[@"stories"];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *info in infos)
		if ([info[@"storyId"] isKindOfClass:NSNumber.class])
			[ids addObject:info[@"storyId"]];
	if (!ids.count){
		[TGAlertSheet showMessage:@"This chat has no active stories right now."
							title:@"Stories" inView:self.view];
		return;
	}
	TGStoryViewerViewController *viewer = [[TGStoryViewerViewController alloc]
			initWithChatId:[row[@"chatId"] longLongValue]
					 title:row[@"title"] ?: @"Stories"
				   stories:ids
				startIndex:0
				 canManage:[row[@"isOwn"] boolValue]];
	__weak typeof(self) weakSelf = self;
	viewer.onStoriesChanged = ^{
		TGChatListViewController *me = weakSelf;
		me.storyRowsReadAt = nil;
		[me reloadStoriesIfNeeded];
	};
	UINavigationController *nav = [[UINavigationController alloc]
			initWithRootViewController:viewer];
	nav.navigationBar.barStyle = UIBarStyleBlack;
	nav.navigationBar.translucent = YES;
	[self presentViewController:nav animated:YES completion:nil];
}

/// Held stories bubble: move the chat's stories between the main strip and
/// the archive, which is the hide Telegram offers for another account's
/// stories. Own stories have no archive move; the row says so.
- (void)runStoryRowMenu:(NSDictionary *)row {
	BOOL archived = [row[@"list"] isEqualToString:@"archive"];
	if ([row[@"isOwn"] boolValue] && !archived){
		[TGAlertSheet showMessage:@"Your own stories stay on the strip. Use the "
				@"story menu for the archive." title:@"Stories" inView:self.view];
		return;
	}
	NSArray *choices = archived
			? @[@"Move to Main Stories"] : @[@"Hide from Stories Row"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:row[@"title"] ?: @"Stories"
				destructiveIndex:-1 inView:self.view onChoice:^(NSInteger choice){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		int64_t chatId = [row[@"chatId"] longLongValue];
		[[TGClient shared] setActiveStoriesList:(archived ? @"main" : @"archive")
										forChat:chatId
									 completion:^(BOOL ok, NSString *error){
			if (!ok){
				[TGAlertSheet showMessage:error ?: @"Telegram refused that."
									title:@"Stories" inView:me.view];
				return;
			}
			me.storyRowsReadAt = nil;
			[me reloadStoriesIfNeeded];
		}];
	}];
}

- (void)openStoryComposer {
	int64_t savedId = [[TGClient shared] savedMessagesChatId];
	if (!savedId){
		[TGAlertSheet showMessage:@"Telegram has not sent the Saved Messages chat yet."
							title:@"New Story" inView:self.view];
		return;
	}
	TGStoryComposerViewController *composer = [[TGStoryComposerViewController alloc]
			initWithChatId:savedId title:@"Your Story"];
	__weak typeof(self) weakSelf = self;
	composer.onPosted = ^{
		TGChatListViewController *me = weakSelf;
		me.storyRowsReadAt = nil;
		[me reloadStoriesIfNeeded];
	};
	composer.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:composer animated:YES];
}

- (void)openStoriesMenu {
	int64_t savedId = [[TGClient shared] savedMessagesChatId];
	if (!savedId){
		[TGAlertSheet showMessage:@"Telegram has not sent the Saved Messages chat yet."
							title:@"Stories" inView:self.view];
		return;
	}
	TGStoriesMenuViewController *menu = [[TGStoriesMenuViewController alloc]
			initWithChatId:savedId title:@"Your Story"];
	__weak typeof(self) weakSelf = self;
	menu.onStoriesChanged = ^{
		TGChatListViewController *me = weakSelf;
		me.storyRowsReadAt = nil;
		[me reloadStoriesIfNeeded];
	};
	menu.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:menu animated:YES];
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
// The decode side of the avatar flood. Two at a time, one autorelease pool
// each: the parallel burst once filled a GCD thread with no pool until the
// thread's memory blew out mid-chat-load (a real-account crash, SIGSEGV 0x0
// inside the icon decode - every avatar asked for the same thread).
static dispatch_semaphore_t TGAvtDecodeGate(NSInteger cap) {
	static dispatch_semaphore_t gate = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		gate = dispatch_semaphore_create((long)cap);
	});
	return gate;
}

- (void)fetchMissingAvatars {
	__weak typeof(self) weakSelf = self;
	CGFloat screenScale = [UIScreen mainScreen].scale;
	dispatch_semaphore_t gate = TGAvtDecodeGate(2);
	NSMutableArray *rows = [NSMutableArray arrayWithArray:self.chats ?: @[]];
	[rows addObjectsFromArray:self.storyRows ?: @[]];
	for (NSDictionary *c in rows){
		NSNumber *fileId = c[@"photoFileId"];
		if (!fileId || fileId.longLongValue < 0 || self.avatars[fileId] || [self.avatarsRequested containsObject:fileId])
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
				// The gate is taken inside the block, not before: an entry
				// slot costs the wait, and the semaphore release happens in
				// the same block that took it.
				dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
				@autoreleasepool {
					NSData *bytes = [NSData dataWithContentsOfFile:path];
					UIImage *img = [TGIcons decodedImage:[UIImage imageWithData:bytes
																  scale:screenScale]
											  fittingSize:CGSizeMake(TGMetricListAvatar, TGMetricListAvatar)
													fill:YES
												   scale:screenScale];
					if (!img && bytes.length)
						img = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
											fittingSize:CGSizeMake(TGMetricListAvatar, TGMetricListAvatar)
											   fill:YES
											  scale:screenScale];
					if (img){
						dispatch_async(dispatch_get_main_queue(), ^{
							TGChatListViewController *me = weakSelf;
							if (!me) { dispatch_semaphore_signal(gate); return; }
							me.avatars[fileId] = img;
							[me reloadTableDebounced];
							dispatch_semaphore_signal(gate);
						});
						return;
					}
					dispatch_semaphore_signal(gate);
				}
			});
		}];
	}
}

/// Today shows the time, this week the weekday, older the date - as clients do.
static NSString *TGChatDate(NSTimeInterval unix) {
	char buf[TGFastDateBufferSize];
	// The server's clock, not this device's: a 4S off by a year grades every
	// date as "today" until the option arrives.
	size_t len = TGFastChatDate((time_t)unix, (time_t)TGOptionNow(), buf, sizeof(buf));
	if (!len)
		return @"";
	return [[NSString alloc] initWithBytes:buf length:len
								  encoding:NSASCIIStringEncoding];
}

/// Saved Messages has a row of its own above the list, so leaving it among the
/// chats as well would show it twice.
- (NSArray *)visibleChats {
	if (self.searchResults)
		return self.searchResults;

	NSMutableArray *chats = [NSMutableArray array];
	if (self.folderId == 0 && !self.showsArchive) {
		[chats addObject:[TGDevShowcase devChatInfo]];
	}

	BOOL hideSaved = [[self headerRows] containsObject:@"saved"];
	int64_t saved = hideSaved ? [[TGClient shared] savedMessagesChatId] : 0;
	for (NSDictionary *c in self.chats){
		int64_t chatId = [c[@"id"] longLongValue];
		if (chatId == saved || chatId == self.chatPendingDeletion || chatId == kDevChatId)
			continue;
		[chats addObject:c];
	}
	return chats;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *header = [self headerRows];
	if (indexPath.row < (NSInteger)header.count &&
		[header[indexPath.row] isEqualToString:@"stories"])
		return TGMetricStoryStripRow;
	return kRowHeight;
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


	NSArray *header = [self headerRows];
	if (indexPath.row < (NSInteger)header.count){
		if ([header[indexPath.row] isEqualToString:@"stories"]){
			static NSString *storyReuse = @"TGStoriesCell";
			TGStoriesCell *strip = [tableView dequeueReusableCellWithIdentifier:storyReuse];
			if (!strip)
				strip = [[TGStoriesCell alloc] initWithStyle:UITableViewCellStyleDefault
											  reuseIdentifier:storyReuse];
			NSMutableArray *display = [NSMutableArray array];
			for (NSDictionary *row in self.storyRows){
				NSMutableDictionary *copy = [row mutableCopy];
				NSNumber *fileId = row[@"photoFileId"];
				if (fileId && self.avatars[fileId])
					copy[@"avatarImage"] = self.avatars[fileId];
				[display addObject:copy];
			}
			strip.stories = display;
			__weak typeof(self) weakSelf = self;
			strip.onAddStory = ^{ [weakSelf openStoryComposer]; };
			strip.onMore = ^{ [weakSelf openStoriesMenu]; };
			strip.onStoryTapped = ^(NSDictionary *row){ [weakSelf showStoryRow:row]; };
			strip.onStoryHeld = ^(NSDictionary *row){ [weakSelf runStoryRowMenu:row]; };
			return strip;
		}
		BOOL isArchive = [header[indexPath.row] isEqualToString:@"archive"];
		cell.titleLabel.text = isArchive ? @"Archived Chats" : @"Saved Messages";
		NSUInteger archived = [TGClient shared].archivedChats.count;
		cell.previewLabel.text = isArchive
				? TGChatListArchiveSubtitle(archived)
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
	double cellStart = TGPerfNow();
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
		cell.muteIcon.image = [TGIcons glyphNamed:@"mute" colour:[theme listDateColour]
											 side:kRowGlyph];

	NSInteger unread = [c[@"unread"] integerValue];
	// A mention is its own badge and outranks the count: official clients show
	// "@" on a chat whose only unread thing is a mention, muted or not.
	NSInteger mentions = [c[@"unreadMentions"] integerValue];
	BOOL anyBadge = unread > 0 || mentions > 0;
	cell.badge.hidden = !anyBadge;
	// The pin is not a place-holder for the badge: a pinned chat that is also
	// unread shows both, the count at the edge and the pin beside it.
	cell.pin.hidden = ![c[@"isPinned"] boolValue];
	if (!cell.pin.hidden)
		cell.pin.image = [TGIcons glyphNamed:@"pin" colour:[theme listDateColour]
									  side:kRowGlyph];
	cell.badge.text = mentions > 0 ? @"@"
			: (unread > 0 ? [NSString stringWithFormat:@"%ld", (long)unread] : @"");
	// A muted chat still counts, it just stops shouting about it.
	cell.badge.backgroundColor = [c[@"isMuted"] boolValue]
			? [theme mutedBadgeColour] : [theme badgeColour];

	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
	int64_t cid = [c[@"id"] longLongValue];
	if ([c[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:kAvatar];
	else if (cid == kDevChatId || cid == kDevBotChatId)
		photo = [TGDevShowcase avatarForUserId:10001];
	else if (cid == kDevDurovChatId)
		photo = [TGDevShowcase avatarForUserId:20002];
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
	TGPerfReport("list cell", [c[@"title"] UTF8String] ?: "", cellStart, 33.0);
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSArray *header = [self headerRows];
	if (indexPath.row < (NSInteger)header.count){
		if ([header[indexPath.row] isEqualToString:@"archive"])
			[self openArchive];
		else if ([header[indexPath.row] isEqualToString:@"stories"])
			return;
		else
			[self openSavedMessages];
		return;
	}

	NSDictionary *c = [self visibleChats][indexPath.row - header.count];
	NSLog(@"open chat: group=%@ forum=%@", c[@"isGroup"], c[@"isForum"] ?: @"(absent)");
	double pushStart = TGPerfNow();
	[self openChatInfo:c];
	// An open that feels instant lands its screen inside two frames; over
	// that the tap reads as nothing happening.
	TGPerfReport("chat open", "push", pushStart, 66.0);
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

@end
