#import "TGChatListViewControllerInternal.h"
#import "TGPerf.h"
#import "TGStatusText.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGMemberAvatarStore.h"
#import "TGFastDate.h"
#import "TGOptions.h"
#import "TGStoryViewerViewController.h"
#import "TGStoryComposerViewController.h"
#import "TGProfileViewController.h"
#import "TGPasscode.h"
#import "TGPasscodeViewController.h"
#import "TGChatListRowGeometry.h"

// Height of the folder pill strip above the chat list (official-style tabs).
static const CGFloat kFolderTabRow = TGMetricFolderTabRow;
/// The mute and pin marks on a row are drawn at this side and then fitted into
/// the smaller box the cell gives them, which is what keeps their strokes even.
static const CGFloat kRowGlyph     = 28.0f;
/// The title view's box: the name, then the connection line under it. 200 pt
/// is the chat header's width on the same 320 pt bar, so neither nav button
/// loses its target to a long folder name.
static const CGFloat kListTitleWidth  = 150.0f;
static const CGFloat kListTitleHeight = TGMetricRow;
static const CGFloat kListChevronWidth = 12.0f;
static const CGFloat kListChevronGap   = TGMetricPadTiny;
static const CGFloat kListStorySide    = 24.0f;
static const CGFloat kListStoryGap     = TGMetricPadSmall;
/// The chat-list bar controls: the Edit pill, the circled add and the blue
/// compose button. Named here because only this header stacks them.
static const CGFloat kBarEditWidth    = 66.0f;
static const CGFloat kBarEditHeight   = TGMetricSegmentedHeight;
static const CGFloat kBarRightWidth   = 92.0f;
static const CGFloat kBarControlSide  = TGMetricButtonMediumH;
static const CGFloat kBarComposeSide  = 46.0f;
static const CGFloat kBarComposeX     = 46.0f;
static const CGFloat kBarControlTop   = 5.0f;
/// The archive pill's tag, outside the folder indexes (100 + slot).
static const NSInteger kFolderArchiveTag = 1000;
/// A folder pill's side padding, its widest form and the gap to the next pill.
static const CGFloat kFolderPillPad = 26.0f;
static const CGFloat kFolderPillMax = 150.0f;
static const CGFloat kFolderPillGap = 6.0f;

/// A 3.5" screen shows six rows of 76 pt; this is two screens.
static const NSUInteger kAvatarWindowRows = 14;

/// One pill's two states. The strip rebuilds on every switch, so the old and
/// new chosen pills are repainted here after the new header is on screen.
static void TGPaintFolderPill(UIButton *pill, BOOL active) {
	TGTheme *theme = [TGTheme shared];
	if (active){
		[pill setBackgroundColor:[theme accentColour]];
		[pill setTitleColor:[theme onAccentColour] forState:UIControlStateNormal];
		pill.layer.borderWidth = TGMetricBorderNone;
	} else {
		[pill setBackgroundColor:[theme cardBackgroundColour]];
		[pill setTitleColor:[theme primaryTextColour] forState:UIControlStateNormal];
		pill.layer.borderWidth = TGMetricHairline;
		pill.layer.borderColor = [theme separatorColour].CGColor;
	}
}

@interface TGChatListViewController ()
/// A folder pill was tapped. The strip repaints its highlight once, and the
/// list fades only when that folder's chats have actually arrived.
@property (nonatomic, assign) BOOL folderHighlightPending;
@property (nonatomic, assign) NSInteger folderHighlightPreviousId;
@property (nonatomic, assign) BOOL folderListFadePending;
/// The stories strip was just pulled out or walked away; the next header
/// rebuild fades instead of replacing the strip in one frame.
@property (nonatomic, assign) BOOL storiesFadePending;
- (void)applyFolderListFadeIfNeeded;
- (void)hideEditBarAnimated;
@end

@implementation TGChatListViewController

/// The first frame after a launch used to be an empty table until TDLib
/// answered loadChats - seconds on the A4 when the cache is cold. The last
/// painted list is written here and drawn again on the next start; the live
/// list replaces it as soon as it arrives.
static NSString *TGChatSnapshotPath(void) {
	NSString *dir = [NSSearchPathForDirectoriesInDomains(
			NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	// The snapshot is one account's list. Slot 0 keeps the pre-accounts name
	// so an update does not discard the last list it saved; later slots get
	// their own file so switching never shows another account's rows.
	NSInteger slot = [TGClient activeAccountSlot];
	NSString *name = slot > 0
			? [NSString stringWithFormat:@"chat-list-snapshot-%ld.plist", (long)slot]
			: @"chat-list-snapshot.plist";
	return [dir stringByAppendingPathComponent:name];
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

/// The first search result replaces the chats with a different list. The
/// category sets this property just before reloadData, so a transition on the
/// table's layer makes those rows dissolve over the old list instead of
/// swapping in one frame.
- (void)setSearchResults:(NSArray *)searchResults {
	BOOL wasSearching = self.searchResults != nil;
	_searchResults = searchResults;
	if (!wasSearching && searchResults != nil && self.tableView.window){
		CATransition *fade = [CATransition animation];
		fade.type = kCATransitionFade;
		fade.duration = TGAnimationDurationFast;
		[self.tableView.layer addAnimation:fade forKey:@"tg.searchResults"];
	}
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

	self.navigationItem.rightBarButtonItem = nil;
	[self buildHeaderButtons];

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, TGMetricScreenWidth, TGMetricRow)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	[self styleSearchBar];
	[self rebuildTableHeader];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	[self.tableView addGestureRecognizer:hold];
	[self installLegacySwipeActions];

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
	[[NSNotificationCenter defaultCenter] addObserverForName:TGStoriesChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		usingBlock:^(NSNotification *note){
		TGChatListViewController *me = weakSelf;
		if (!me)
			return;
		NSNumber *chatId = note.userInfo[@"chatId"];
		if (!chatId)
			chatId = note.userInfo[@"row"][@"chatId"];
		if (note.userInfo[@"remove"]){
			NSMutableArray *kept = [NSMutableArray array];
			for (NSDictionary *row in me.storyRows)
				if ([row[@"chatId"] longLongValue] != [chatId longLongValue])
					[kept addObject:row];
			me.storyRows = kept;
		} else if (note.userInfo[@"row"]){
			NSMutableArray *rows = [me.storyRows mutableCopy] ?: [NSMutableArray array];
			NSMutableArray *kept = [NSMutableArray array];
			for (NSDictionary *row in rows)
				if ([row[@"chatId"] longLongValue] != [chatId longLongValue])
					[kept addObject:row];
			[kept addObject:note.userInfo[@"row"]];
			[kept sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
				return [b[@"order"] compare:a[@"order"]];
			}];
			rows = kept;
			me.storyRows = rows;
		}
		[me rebuildTableHeader];
		[me refreshListTitleView];
		[me fetchMissingAvatars];
	}];

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

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self buildHeaderButtons];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	// The header cannot be parked inside viewDidLoad: the table has no
	// height yet there, so the first layout left the search field on screen.
	if (!self.userRevealed && !self.searchResults && !self.showsArchive &&
			self.folderId == 0 && self.tableView.contentOffset.y < self.parkOffset - 1.0f &&
			self.tableView.contentSize.height > self.tableView.bounds.size.height)
		self.tableView.contentOffset = CGPointMake(TGMetricZero, self.parkOffset);
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

	// Telegram puts the folder switcher on the title itself, not on a second
	// row of pills: a chevron after the name opens the list of folders.
	UILabel *chevron = [[UILabel alloc] initWithFrame:CGRectZero];
	chevron.font = TGFontCaptionStrong();
	chevron.text = @"\u25BE";
	chevron.textColor = [[TGTheme shared] barTitleColour];
	chevron.backgroundColor = [UIColor clearColor];
	chevron.userInteractionEnabled = YES;
	[chevron addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(foldersTapped)]];
	[box addSubview:chevron];
	self.listChevron = chevron;

	// The collapsed story: an active peer's face appears beside the title
	// once the strip is scrolled away, and tapping it opens that story.
	UIButton *story = [UIButton buttonWithType:UIButtonTypeCustom];
	story.frame = CGRectMake(TGMetricZero, TGCenteredOrigin(kListTitleHeight,
			kListStorySide), kListStorySide, kListStorySide);
	story.layer.cornerRadius = TGHalf(kListStorySide);
	story.clipsToBounds = YES;
	story.hidden = YES;
	[story addTarget:self action:@selector(openCollapsedStory)
   forControlEvents:UIControlEventTouchUpInside];
	[box addSubview:story];
	self.listStoryAvatar = story;

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
	if (![name isKindOfClass:NSString.class])
		name = @"Chats";
	BOOL hasLine = self.connectionLine.length > 0;
	self.title = name;
	self.listTitleLabel.text = name;
	NSString *line = hasLine ? self.connectionLine : @"";
	// "Connecting" and "Updating" are different sentences under the same
	// title; replacing one with the other read as a blink. Only a visible
	// line changing needs the fade - a first appearance is the label's own
	// hidden flag.
	if (hasLine && self.listSubtitleLabel.text.length &&
			![self.listSubtitleLabel.text isEqualToString:line] &&
			self.listSubtitleLabel.window){
		CATransition *fade = [CATransition animation];
		fade.type = kCATransitionFade;
		fade.duration = TGAnimationDurationFast;
		[self.listSubtitleLabel.layer addAnimation:fade forKey:@"tg.connection"];
	}
	self.listSubtitleLabel.text = line;
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

	BOOL hasFolders = [TGClient shared].folders.count > 0 && !self.showsArchive;
	NSDictionary *story = [self collapsedStoryRow];
	BOOL showStory = story != nil && !hasLine && !self.storiesExpanded;
	self.listStoryAvatar.hidden = !showStory;
	self.listChevron.hidden = !hasFolders;

	CGSize text = [name sizeWithFont:self.listTitleLabel.font];
	CGFloat total = text.width;
	if (showStory)
		total += kListStorySide + kListStoryGap;
	if (hasFolders)
		total += kListChevronGap + kListChevronWidth;
	CGFloat x = TGHalf(kListTitleWidth) - TGHalf(total);
	CGFloat top = CGRectGetMinY(self.listTitleLabel.frame);

	if (showStory){
		self.listStoryAvatar.frame = CGRectMake(x, TGCenteredOrigin(kListTitleHeight,
				kListStorySide), kListStorySide, kListStorySide);
		UIImage *image = story[@"avatarImage"];
		NSNumber *fileId = story[@"photoFileId"];
		if (!image && fileId)
			image = self.avatars[fileId];
		if (!image){
			NSString *title = [story[@"title"] isKindOfClass:NSString.class]
					? story[@"title"] : @"?";
			NSString *first = [TGIcons initialsForTitle:title];
			image = [TGIcons avatarWithInitials:first size:kListStorySide
									 colourId:[story[@"chatId"] longLongValue]];
		}
		[self.listStoryAvatar setImage:image forState:UIControlStateNormal];
		if (!story[@"avatarImage"] && !story[@"isOwn"]){
			int64_t userId = [story[@"chatId"] longLongValue];
			__weak typeof(self) weakSelf = self;
			[[TGMemberAvatarStore shared] loadAvatarForUser:userId
													 side:kListStorySide
											   completion:^(UIImage *loaded){
				if (!loaded)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					[weakSelf.listStoryAvatar setImage:loaded
											  forState:UIControlStateNormal];
				});
			}];
		}
		x += kListStorySide + kListStoryGap;
	}
	self.listTitleLabel.frame = CGRectMake(x, top, text.width, TGMetricLineRow);
	if (hasFolders){
		self.listChevron.frame = CGRectMake(x + text.width + kListChevronGap,
				top, kListChevronWidth, TGMetricLineRow);
	}
}

/// The peer whose story collapses into the title when the strip is off
/// screen. Own stories stay in the strip; this is the first other account
/// with something to watch.
- (NSDictionary *)collapsedStoryRow {
	for (NSDictionary *row in self.storyRows){
		if ([row[@"isOwn"] boolValue])
			continue;
		if ([row[@"stories"] count])
			return row;
	}
	return nil;
}

- (void)openCollapsedStory {
	if (![self collapsedStoryRow])
		return;
	self.storiesExpanded = YES;
	self.storiesFadePending = YES;
	[self rebuildTableHeader];
	[self.tableView reloadData];
}

/// Telegram's chat list bar: a pill-shaped Edit on the left, and on the right
/// the dashed add-story circle beside the blue compose button. Both are
/// custom views because the stock bar items cannot carry those shapes.
- (void)buildHeaderButtons {
	if (self.showsArchive || self.folderId != 0)
		return;

	UIBarButtonItem *edit = [[UIBarButtonItem alloc]
			initWithTitle:(self.editingChats ? @"Done" : @"Edit")
					style:(self.editingChats ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain)
				   target:self
				   action:@selector(toggleChatListEditing)];

	if ([TGPasscode hasPasscode] && !self.editingChats) {
		UIBarButtonItem *lock = [[UIBarButtonItem alloc]
				initWithImage:[TGIcons glyphNamed:@"privacy" colour:[[TGTheme shared] barButtonColour] side:TGMetricMenuGlyph]
						style:UIBarButtonItemStylePlain
					   target:self
					   action:@selector(lockAppTapped)];
		self.navigationItem.leftBarButtonItems = @[edit, lock];
		self.navigationItem.leftItemsSupplementBackButton = YES;
	} else {
		self.navigationItem.leftBarButtonItems = @[edit];
		self.navigationItem.leftBarButtonItem = edit;
	}

	if (self.editingChats) {
		self.navigationItem.rightBarButtonItems = nil;
		self.navigationItem.rightBarButtonItem = nil;
	} else {
		UIBarButtonItem *compose = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
									 target:self
									 action:@selector(composeTapped)];
		UIBarButtonItem *camera = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
									 target:self
									 action:@selector(openStoryComposer)];
		self.navigationItem.rightBarButtonItems = @[compose, camera];
	}
}

- (void)lockAppTapped {
	[TGPasscode setLocked:YES];
	[TGPasscodeViewController presentUnlockIfLocked];
}

/// Telegram's Edit is multi-select, not a settings mode: check the chats,
/// then delete, archive or mute them together. The table's own editing mode
/// draws the checks; the toolbar carries the three verbs.
- (void)toggleChatListEditing {
	self.editingChats = !self.editingChats;
	self.tableView.allowsMultipleSelectionDuringEditing = YES;
	[self.tableView setEditing:self.editingChats animated:YES];
	[self buildHeaderButtons];

	if (!self.editingChats){
		[self hideEditBarAnimated];
		return;
	}
	if (!self.editBar){
		CGFloat h = TGMetricRow;
		UIView *host = self.tabBarController.view ?: self.view;
		CGFloat bottom = host.bounds.size.height;
		if (self.tabBarController && !self.tabBarController.tabBar.hidden)
			bottom = CGRectGetMinY(self.tabBarController.tabBar.frame);
		self.editBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0,
				bottom - h, host.bounds.size.width, h)];
		self.editBar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
				UIViewAutoresizingFlexibleTopMargin;
		[host addSubview:self.editBar];
		// Start below the tab bar, then slide up: the bar arriving in place
		// on one frame is the part that looked unfinished.
		self.editBar.transform = CGAffineTransformMakeTranslation(0, h);
	}
	// A bar that was already on screen is at identity, so this only moves
	// one that is arriving or reversing a hide that was still running.
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.editBar.transform = CGAffineTransformIdentity;
	}];
	[self refreshEditToolbar];
}

/// Slide the toolbar under the tab bar. Edit can be turned back on while the
/// slide is running, in which case the bar must stay where the new press put
/// it rather than disappear with the old slide.
- (void)hideEditBarAnimated {
	UIToolbar *bar = self.editBar;
	if (!bar)
		return;
	CGFloat h = bar.bounds.size.height;
	__weak typeof(self) weakSelf = self;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		bar.transform = CGAffineTransformMakeTranslation(0, h);
	} completion:^(BOOL finished){
		TGChatListViewController *me = weakSelf;
		if (!me || me.editingChats || me.editBar != bar)
			return;
		[bar removeFromSuperview];
		me.editBar = nil;
	}];
}

/// The toolbar follows the selection: Mute reads Unmute when every selected
/// chat is already silent, Pin reads Unpin, and Read flips the same way.
- (void)refreshEditToolbar {
	NSArray *selected = [self selectedChatIndexes];
	BOOL allMuted = selected.count > 0;
	BOOL allPinned = selected.count > 0;
	BOOL allUnread = selected.count > 0;
	for (NSDictionary *chat in selected){
		allMuted = allMuted && [chat[@"isMuted"] boolValue];
		allPinned = allPinned && [chat[@"isPinned"] boolValue];
		BOOL unread = [chat[@"unread"] integerValue] > 0 ||
				[chat[@"markedUnread"] boolValue];
		allUnread = allUnread && unread;
	}
	UIBarButtonItem *all = [[UIBarButtonItem alloc]
			initWithTitle:(selected.count == (NSInteger)[self visibleChats].count
					? @"None" : @"All")
					style:UIBarButtonItemStyleBordered target:self
				   action:@selector(selectAllChats)];
	UIBarButtonItem *delete = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
								 target:self action:@selector(deleteSelectedChats)];
	UIBarButtonItem *mute = [[UIBarButtonItem alloc]
			initWithTitle:(allMuted ? @"Unmute" : @"Mute")
					style:UIBarButtonItemStyleBordered target:self
				   action:@selector(muteSelectedChats)];
	UIBarButtonItem *pin = [[UIBarButtonItem alloc]
			initWithTitle:(allPinned ? @"Unpin" : @"Pin")
					style:UIBarButtonItemStyleBordered target:self
				   action:@selector(pinSelectedChats)];
	UIBarButtonItem *read = [[UIBarButtonItem alloc]
			initWithTitle:(allUnread ? @"Read" : @"Unread")
					style:UIBarButtonItemStyleBordered target:self
				   action:@selector(readSelectedChats)];
	UIBarButtonItem *archive = [[UIBarButtonItem alloc]
			initWithTitle:@"Archive" style:UIBarButtonItemStyleBordered
				   target:self action:@selector(archiveSelectedChats)];
	if (self.editBar)
		[self.editBar setItems:@[all, delete, mute, pin, read, archive] animated:NO];
}

- (void)selectAllChats {
	NSInteger header = [self headerRows].count;
	NSInteger total = (NSInteger)[self visibleChats].count;
	BOOL all = [self.tableView.indexPathsForSelectedRows count] == (NSUInteger)total;
	for (NSInteger i = 0; i < total; i++){
		NSIndexPath *path = [NSIndexPath indexPathForRow:i + header inSection:0];
		if (all)
			[self.tableView deselectRowAtIndexPath:path animated:NO];
		else
			[self.tableView selectRowAtIndexPath:path animated:NO
								   scrollPosition:UITableViewScrollPositionNone];
	}
	[self refreshEditToolbar];
}

- (void)pinSelectedChats {
	NSArray *selected = [self selectedChatIndexes];
	if (!selected.count)
		return;
	NSMutableSet *chosen = [NSMutableSet set];
	for (NSDictionary *chat in selected)
		[chosen addObject:chat[@"id"]];
	BOOL allPinned = YES;
	for (NSDictionary *chat in selected)
		allPinned = allPinned && [chat[@"isPinned"] boolValue];

	NSMutableArray *order = [NSMutableArray array];
	for (NSDictionary *chat in [self visibleChats])
		if ([chat[@"isPinned"] boolValue] && ![chosen containsObject:chat[@"id"]])
			[order addObject:chat[@"id"]];
	if (!allPinned){
		for (NSDictionary *chat in selected)
			if (![order containsObject:chat[@"id"]])
				[order insertObject:chat[@"id"] atIndex:0];
	}
	[[TGClient shared] setPinnedChatIds:order];
	[self finishChatEditingAction];
}

- (void)readSelectedChats {
	NSArray *selected = [self selectedChatIndexes];
	if (!selected.count)
		return;
	BOOL allUnread = YES;
	for (NSDictionary *chat in selected)
		allUnread = allUnread && ([chat[@"unread"] integerValue] > 0 ||
				[chat[@"markedUnread"] boolValue]);
	for (NSDictionary *chat in selected){
		int64_t chatId = [chat[@"id"] longLongValue];
		if (allUnread){
			NSNumber *lastId = chat[@"lastId"];
			if ([lastId longLongValue])
				[[TGClient shared] markRead:@[lastId] inChat:chatId];
			else
				[[TGClient shared] setChat:chatId markedUnread:NO];
		} else {
			[[TGClient shared] setChat:chatId markedUnread:YES];
		}
	}
	[self finishChatEditingAction];
}

- (NSArray *)selectedChatIndexes {
	NSMutableArray *ids = [NSMutableArray array];
	NSInteger header = [self headerRows].count;
	for (NSIndexPath *path in self.tableView.indexPathsForSelectedRows){
		if (path.row < header)
			continue;
		NSInteger index = path.row - header;
		NSArray *chats = [self visibleChats];
		if (index >= 0 && index < (NSInteger)chats.count)
			[ids addObject:chats[(NSUInteger)index]];
	}
	return ids;
}

- (void)finishChatEditingAction {
	self.editingChats = NO;
	[self.tableView setEditing:NO animated:YES];
	[self buildHeaderButtons];
	[self hideEditBarAnimated];
	[self reload];
}

- (void)deleteSelectedChats {
	NSArray *selected = [self selectedChatIndexes];
	if (!selected.count)
		return;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:@"Delete %lu chats?",
			(unsigned long)selected.count]
						title:@"Delete Chats" action:@"Delete" destructive:YES
					   inView:self.view onConfirm:^{
		for (NSDictionary *chat in selected)
			[[TGClient shared] deleteChat:[chat[@"id"] longLongValue]];
		[weakSelf finishChatEditingAction];
	}];
}

- (void)archiveSelectedChats {
	for (NSDictionary *chat in [self selectedChatIndexes])
		[[TGClient shared] setChat:[chat[@"id"] longLongValue] archived:YES];
	[self finishChatEditingAction];
}

- (void)muteSelectedChats {
	for (NSDictionary *chat in [self selectedChatIndexes])
		[[TGClient shared] setChat:[chat[@"id"] longLongValue] muted:YES];
	[self finishChatEditingAction];
}
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
		// The strip is rebuilt during a switch. Paint the pill that was
		// active with its old colour first, then fade it and the new active
		// pill to their new colours, so the highlight slides rather than
		// jumping from one pill to another in a single frame.
		BOOL shownActive = active;
		if (self.folderHighlightPending){
			shownActive = (i == 0 && self.folderHighlightPreviousId == 0) ||
					(i > 0 && [folders[i - 1] isKindOfClass:NSDictionary.class] &&
					 [folders[i - 1][@"id"] integerValue] ==
							self.folderHighlightPreviousId);
		}
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
		TGPaintFolderPill(pill, shownActive);
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
	NSInteger choice = pill.tag - 100;
	NSArray *folders = [TGClient shared].folders;
	NSInteger target = 0;
	if (choice > 0 && choice - 1 < (NSInteger)folders.count &&
			[folders[choice - 1] isKindOfClass:NSDictionary.class])
		target = [folders[choice - 1][@"id"] integerValue];
	if (target == self.folderId)
		return;
	// The strip is rebuilt during the choice, so remember which pill was lit
	// to let the old and new highlights trade places through one fade. The
	// list waits for its own answer: fading an empty table before a folder's
	// chats arrive would flash.
	self.folderHighlightPending = YES;
	self.folderHighlightPreviousId = self.folderId;
	self.folderListFadePending = YES;
	[self runFolderChoice:choice];
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
	// Folders live on the title's chevron now. Keeping a second sticky row
	// would put the old pill strip back above the stories every time.
	return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	return nil;
}

- (void)rebuildTableHeader {
	BOOL fadeStories = self.storiesFadePending;
	self.storiesFadePending = NO;
	// Telegram stacks the header in this order: the expanded story row,
	// the search field, then the folder pills. The story row is a pull-down
	// sheet that is normally collapsed into the title avatar.
	CGFloat width = self.tableView.bounds.size.width ?: 320;
	UIColor *bg = [[TGTheme shared] listBackgroundColour];
	BOOL hasStories = self.storiesExpanded && [self collapsedStoryRow] != nil;
	CGFloat storyH = hasStories ? TGMetricStoryStripRow : TGMetricZero;
	CGFloat searchH = TGMetricRow;
	BOOL hasFolders = !self.showsArchive && [TGClient shared].folders.count > 0;
	CGFloat folderH = hasFolders ? kFolderTabRow : TGMetricZero;
	CGFloat height = storyH + searchH + folderH;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = bg;

	if (hasStories){
		if (!self.headerStoriesCell)
			self.headerStoriesCell = [[TGStoriesCell alloc] initWithStyle:
					UITableViewCellStyleDefault reuseIdentifier:nil];
		self.headerStoriesCell.frame = CGRectMake(0, 0, width, storyH);
		self.headerStoriesCell.backgroundColor = bg;
		self.headerStoriesCell.contentView.backgroundColor = bg;
		[self configureStoriesCell:self.headerStoriesCell];
		[header addSubview:self.headerStoriesCell];
	}
	self.searchBar.frame = CGRectMake(0, storyH, width, searchH);
	[header addSubview:self.searchBar];

	if (hasFolders)
		[self buildFolderTabsInto:header atY:(storyH + searchH) width:width
				folders:[TGClient shared].folders];

	if (fadeStories && !hasStories){
		CATransition *fade = [CATransition animation];
		fade.type = kCATransitionFade;
		fade.duration = TGAnimationDurationFast;
		// Collapsing removes the strip and changes the header height; the
		// rows below move by that height in one frame, which the table fade
		// covers.
		[self.tableView.layer addAnimation:fade forKey:@"tg.stories"];
	}

	self.tableView.tableHeaderView = header;
	if (fadeStories && hasStories){
		// Expanding adds the strip as a new row. Fading its content in is
		// enough - the space for it is already part of the new header.
		UIView *content = self.headerStoriesCell.contentView;
		content.alpha = TGAlphaTransparent;
		[UIView animateWithDuration:TGAnimationDurationFast animations:^{
			content.alpha = TGAlphaOpaque;
		}];
	}
	if (self.folderHighlightPending){
		NSArray *folders = [TGClient shared].folders;
		NSInteger oldTag = 0, newTag = 0;
		for (NSInteger i = 0; i <= (NSInteger)folders.count; i++){
			NSInteger folderId = 0;
			if (i > 0 && [folders[i - 1] isKindOfClass:NSDictionary.class])
				folderId = [folders[i - 1][@"id"] integerValue];
			if (folderId == self.folderHighlightPreviousId)
				oldTag = 100 + i;
			if (folderId == self.folderId)
				newTag = 100 + i;
		}
		void (^fadePill)(NSInteger, BOOL) = ^(NSInteger tag, BOOL active){
			UIButton *pill = (UIButton *)[header viewWithTag:tag];
			if (![pill isKindOfClass:UIButton.class])
				return;
			CATransition *fade = [CATransition animation];
			fade.type = kCATransitionFade;
			fade.duration = TGAnimationDurationFast;
			[pill.layer addAnimation:fade forKey:@"tg.folderHighlight"];
			TGPaintFolderPill(pill, active);
		};
		// The old and new chosen pills are already in the header; only their
		// colours change, so one fade covers both halves of the move.
		if (oldTag && oldTag != newTag)
			fadePill(oldTag, NO);
		if (newTag && newTag != oldTag)
			fadePill(newTag, YES);
		self.folderHighlightPending = NO;
	}
	self.headerHeight = height;
	self.parkOffset = TGMetricZero;
	[self refreshListTitleView];
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

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	if (scrollView == self.tableView)
		[self fetchMissingAvatars];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (scrollView == self.tableView && !decelerate)
		[self fetchMissingAvatars];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.tableView)
		return;
	// Pulling the list down unfolds the stories; walking the list collapses
	// them again, which is the header's compact state.
	if (!self.storiesExpanded && scrollView.contentOffset.y < -TGMetricRow &&
			[self collapsedStoryRow]){
		self.storiesExpanded = YES;
		self.storiesFadePending = YES;
		[self rebuildTableHeader];
		return;
	}
	if (self.storiesExpanded && scrollView.contentOffset.y > TGMetricStoryStripRow){
		self.storiesExpanded = NO;
		self.storiesFadePending = YES;
		[self rebuildTableHeader];
		return;
	}
	[self refreshListTitleView];
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

/// A pill switch arms this before asking the folder for its chats; the answer
/// replaces the whole table, and that one swap fades. Spending the flag here
/// is what keeps the periodic reloads from crossfading the list too.
- (void)applyFolderListFadeIfNeeded {
	if (!self.folderListFadePending)
		return;
	self.folderListFadePending = NO;
	CATransition *fade = [CATransition animation];
	fade.type = kCATransitionFade;
	fade.duration = TGAnimationDurationFast;
	[self.tableView.layer addAnimation:fade forKey:@"tg.folderList"];
}

- (void)reload {
	if (self.showsArchive){
		self.chats = [TGClient shared].archivedChats;
		[self.tableView reloadData];
		[self fetchMissingAvatars];
		return;
	}

	if (self.folderId != 0){
		NSInteger folder = self.folderId;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] chatsInFolder:folder completion:^(NSArray *chats){
			weakSelf.chats = chats;
			// An answer for a folder the user already left must not spend
			// the next switch's fade.
			if (weakSelf.folderId == folder)
				[weakSelf applyFolderListFadeIfNeeded];
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
	self.chats = baseChats;
	[self reloadStoriesIfNeeded];
	[self applyFolderListFadeIfNeeded];
	[self.tableView reloadData];
	[self rebuildTableHeader];
	// The search field is a pull-down: Telegram opens on the stories row,
	// not on a search bar. Park past the header once the table has a real
	// height; a deliberate pull brings it back (scrollViewWillEndDragging).
	if (!self.userRevealed && !self.searchResults && !self.showsArchive &&
			self.folderId == 0 && self.tableView.contentOffset.y < self.parkOffset - 1.0f){
		[self.tableView layoutIfNeeded];
		if (self.tableView.contentSize.height > self.tableView.bounds.size.height)
			self.tableView.contentOffset = CGPointMake(TGMetricZero, self.parkOffset);
	}
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
	NSMutableArray *rows = [NSMutableArray array];
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
		// The per-chat read is a first pass; updateChatActiveStories may
		// already have delivered a row for a chat outside its sixty. Keep
		// both, with the fresh read winning for the ids it knows.
		NSMutableArray *merged = [rows mutableCopy] ?: [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];
		for (NSDictionary *row in merged)
			[seen addObject:[NSString stringWithFormat:@"%@", row[@"chatId"]]];
		for (NSDictionary *row in me.storyRows){
			NSString *key = [NSString stringWithFormat:@"%@", row[@"chatId"]];
			if (![seen containsObject:key])
				[merged addObject:row];
		}
		me.storyRows = merged;
		if (me.storiesExpanded && ![me collapsedStoryRow]){
			// The last story expired while the strip was open; fold it away
			// with the same fade as a scroll collapse.
			me.storiesExpanded = NO;
			me.storiesFadePending = YES;
		}
		// An empty answer often means the chat list had not loaded yet, not
		// that nobody has a story. Only a real answer earns the cooldown;
		// otherwise the strip stayed empty for thirty seconds after launch.
		me.storyRowsReadAt = merged.count ? [NSDate date] : nil;
		me.storyRowsLoading = NO;
		[me rebuildTableHeader];
		[me refreshListTitleView];
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
	__weak typeof(self) weakSelf = self;
	[TGStoryComposerViewController openFromController:self chatId:savedId
												title:@"Your Story" onPosted:^{
		TGChatListViewController *me = weakSelf;
		me.storyRowsReadAt = nil;
		[me reloadStoriesIfNeeded];
	}];
}

- (void)openStoriesMenu {
	int64_t savedId = [[TGClient shared] savedMessagesChatId];
	if (!savedId){
		[TGAlertSheet showMessage:@"Telegram has not sent the Saved Messages chat yet."
							title:@"Stories" inView:self.view];
		return;
	}
	// The manager is My Profile, as in the official client: Stories and Archive on
	// one screen. A story moved there shows in the strip on the way back.
	TGProfileViewController *profile = [[TGProfileViewController alloc]
			initWithChatId:savedId userId:savedId title:@"My Profile"];
	profile.storedMediaKind = @"stories";
	profile.hidesBottomBarWhenPushed = YES;
	self.storyRowsReadAt = nil;
	[self.navigationController pushViewController:profile animated:YES];
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
	// What is on screen and a screenful ahead, not the whole list: 176 downloads
	// and decodes at launch on the A4 paid for rows nobody had looked at yet.
	// The next stop of the scroll asks for what it reached.
	NSArray *chats = self.chats ?: @[];
	NSInteger first = [[self.tableView indexPathsForVisibleRows] firstObject]
			? [[[self.tableView indexPathsForVisibleRows] firstObject] row] : 0;
	NSRange window = TGAvatarWindow(first, kAvatarWindowRows, chats.count);
	NSMutableArray *rows = [NSMutableArray arrayWithArray:[chats subarrayWithRange:window]];
	[rows addObjectsFromArray:self.storyRows ?: @[]];
	NSNumber *ownPhoto = [TGClient shared].me[@"profile_photo"][@"small"][@"id"]
			?: [[TGClient shared] photoFileIdForUserId:
					[[TGClient shared].me[@"id"] longLongValue]];
	if (ownPhoto)
		[rows addObject:@{@"photoFileId" : ownPhoto}];
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
						UIImage *rounded = [TGIcons roundedImage:img
														    size:CGSizeMake(kAvatar, kAvatar)
														  radius:TGHalf(kAvatar)
														 corners:UIRectCornerAllCorners];
						dispatch_async(dispatch_get_main_queue(), ^{
							TGChatListViewController *me = weakSelf;
							if (!me) { dispatch_semaphore_signal(gate); return; }
							me.avatars[fileId] = rounded ?: img;
							[me refreshListTitleView];
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

	BOOL hideSaved = [[self headerRows] containsObject:@"saved"];
	int64_t saved = hideSaved ? [[TGClient shared] savedMessagesChatId] : 0;
	for (NSDictionary *c in self.chats){
		int64_t chatId = [c[@"id"] longLongValue];
		if (chatId == saved || chatId == self.chatPendingDeletion)
			continue;
		[chats addObject:c];
	}
	return chats;
}

/// Fills the strip whether it is the header's expanded row or a table cell.
- (void)configureStoriesCell:(TGStoriesCell *)strip {
	NSMutableArray *display = [NSMutableArray array];
	NSDictionary *own = nil;
	for (NSDictionary *row in self.storyRows){
		if ([row[@"isOwn"] boolValue]){
			own = row;
			continue;
		}
		NSMutableDictionary *copy = [row mutableCopy];
		NSNumber *fileId = row[@"photoFileId"];
		if (fileId && self.avatars[fileId])
			copy[@"avatarImage"] = self.avatars[fileId];
		[display addObject:copy];
	}
	int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
	NSMutableDictionary *mine = [own mutableCopy] ?: [NSMutableDictionary dictionary];
	mine[@"title"] = @"My Story";
	mine[@"isOwn"] = @YES;
	mine[@"userId"] = @(myId);
	if (!mine[@"chatId"])
		mine[@"chatId"] = @([[TGClient shared] savedMessagesChatId] ?: myId);
	NSNumber *ownPhoto = [TGClient shared].me[@"profile_photo"][@"small"][@"id"]
			?: [[TGClient shared] photoFileIdForUserId:myId]
			?: mine[@"photoFileId"];
	if (ownPhoto)
		mine[@"photoFileId"] = ownPhoto;
	if (ownPhoto && self.avatars[ownPhoto])
		mine[@"avatarImage"] = self.avatars[ownPhoto];
	strip.stories = display;
	strip.ownStory = mine;
	__weak typeof(self) weakSelf = self;
	strip.onAddStory = ^{ [weakSelf openStoryComposer]; };
	strip.onMore = ^{ [weakSelf openStoriesMenu]; };
	strip.onMyStoryTapped = ^{
		TGChatListViewController *me = weakSelf;
		if (!me) return;
		if ([own[@"stories"] count])
			[me showStoryRow:own];
		else
			[me openStoryComposer];
	};
	strip.onMyStoryHeld = ^{ [weakSelf openStoriesMenu]; };
	strip.onStoryTapped = ^(NSDictionary *row){ [weakSelf showStoryRow:row]; };
	strip.onStoryHeld = ^(NSDictionary *row){ [weakSelf runStoryRowMenu:row]; };
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
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
	NSString *draft = c[@"draft"];
	if ([action length]){
		cell.previewLabel.text = action;
		cell.previewLabel.textColor = [theme typingColour];
	} else if ([draft length]){
		[cell setDraftPreview:draft];
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
	NSInteger mentions = [c[@"unreadMentions"] integerValue];
	cell.mentionBadge.hidden = (mentions <= 0);

	BOOL marked = [c[@"markedUnread"] boolValue];
	BOOL anyBadge = unread > 0 || marked;
	cell.badge.hidden = !anyBadge;
	// The pin is not a place-holder for the badge: a pinned chat that is also
	// unread shows both, the count at the edge and the pin beside it.
	cell.pin.hidden = ![c[@"isPinned"] boolValue];
	if (!cell.pin.hidden)
		cell.pin.image = [TGIcons glyphNamed:@"pin" colour:[theme listDateColour]
									  side:kRowGlyph];
	cell.badge.text = unread > 0 ? (unread > 9999 ? @"9999+" : [NSString stringWithFormat:@"%ld", (long)unread]) : @"";
	// A muted chat still counts, it just stops shouting about it.
	cell.badge.backgroundColor = [c[@"isMuted"] boolValue]
			? [theme mutedBadgeColour] : [theme badgeColour];

	NSNumber *fileId = c[@"photoFileId"];
	UIImage *photo = fileId ? self.avatars[fileId] : nil;
	int64_t cid = [c[@"id"] longLongValue];
	if ([c[@"isSaved"] boolValue])
		photo = [TGIcons savedMessagesAvatarOfSide:kAvatar];
	if (!photo){
		NSString *title = c[@"title"] ?: @"";
		NSString *initials = [TGIcons initialsForTitle:title];
		photo = [TGIcons avatarWithInitials:initials
									   size:kAvatar
								   colourId:[c[@"id"] longLongValue]];
	}
	cell.avatar.image = photo;
	cell.avatar.opaque = NO;
	cell.avatar.backgroundColor = [UIColor clearColor];

	[cell setNeedsLayout];
	TGPerfReport("list cell", [c[@"title"] UTF8String] ?: "", cellStart, 33.0);
	return cell;
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.editingChats)
		return;
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	if ([cell isKindOfClass:TGChatCell.class])
		((TGChatCell *)cell).editCheck.hidden = YES;
	[self refreshEditToolbar];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.row >= (NSInteger)[self headerRows].count;
}

/// Edit also reorders the pinned chats: only a pinned row gets the move
/// handle, and the result is written as Telegram's whole pinned list.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.editingChats)
		return NO;
	NSInteger index = indexPath.row - (NSInteger)[self headerRows].count;
	NSArray *chats = [self visibleChats];
	return index >= 0 && index < (NSInteger)chats.count &&
			[chats[(NSUInteger)index][@"isPinned"] boolValue];
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
			  toIndexPath:(NSIndexPath *)destinationIndexPath {
	NSInteger header = [self headerRows].count;
	NSArray *chats = [self visibleChats];
	NSInteger from = sourceIndexPath.row - header;
	NSInteger to = destinationIndexPath.row - header;
	if (from < 0 || from >= (NSInteger)chats.count || to < 0)
		return;
	NSMutableArray *pinned = [NSMutableArray array];
	for (NSDictionary *chat in chats)
		if ([chat[@"isPinned"] boolValue])
			[pinned addObject:chat];
	if (to >= (NSInteger)chats.count)
		to = (NSInteger)chats.count - 1;
	NSInteger pinnedTo = 0;
	for (NSInteger i = 0; i <= to && i < (NSInteger)chats.count; i++)
		if ([chats[(NSUInteger)i][@"isPinned"] boolValue])
			pinnedTo++;
	NSInteger pinnedFrom = [pinned indexOfObjectIdenticalTo:chats[(NSUInteger)from]];
	if (pinnedFrom == NSNotFound)
		return;
	if (pinnedTo > pinnedFrom)
		pinnedTo--;
	if (pinnedTo < 0)
		pinnedTo = 0;
	if (pinnedTo >= (NSInteger)pinned.count)
		pinnedTo = (NSInteger)pinned.count - 1;
	if (pinnedFrom == pinnedTo)
		return;
	NSDictionary *moved = pinned[(NSUInteger)pinnedFrom];
	[pinned removeObjectAtIndex:(NSUInteger)pinnedFrom];
	[pinned insertObject:moved atIndex:(NSUInteger)pinnedTo];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *chat in pinned)
		[ids addObject:chat[@"id"]];
	[[TGClient shared] setPinnedChatIds:ids];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [weakSelf reload]; });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.editingChats){
		UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
		if ([cell isKindOfClass:TGChatCell.class]){
			TGChatCell *chatCell = (TGChatCell *)cell;
			chatCell.editCheck.hidden = NO;
			[chatCell.contentView bringSubviewToFront:chatCell.editCheck];
		}
		[self refreshEditToolbar];
		return;
	}
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
