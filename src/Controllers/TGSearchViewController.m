//
// TGSearchViewController - search controller for chats and messages.
//
#import "TGSearchViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"


@interface TGSearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) NSArray *chatHits;
@property (nonatomic, strong) NSArray *messageHits;
/// Who this account talks to most, shown before anything is typed - their
/// search opens on this rather than on a blank screen.
@property (nonatomic, strong) NSArray *frequent;
/// Where this account was last, under the frequent list.
@property (nonatomic, strong) NSArray *recent;
/// Chats opened from search - Telegram's own recently-found log, which is
/// what the remove and clear buttons act on.
@property (nonatomic, strong) NSArray *recentlyFound;
/// Contacts Telegram matched, which is its own section: a person who is not
/// a chat yet has no row among the chats.
@property (nonatomic, strong) NSArray *contactHits;
/// Hashtags Telegram answers for the prefix, and the tags this account has
/// searched for before.
@property (nonatomic, strong) NSArray *hashtagHits;
@property (nonatomic, strong) NSArray *recentTags;
/// Chat titles and recent tags that start with the query, ranked by TDLib.
@property (nonatomic, strong) NSArray *suggestions;
/// Public posts matching the query. Raw message dictionaries; the row reads
/// the chat id for a title and the content for its line.
@property (nonatomic, strong) NSArray *publicHits;
/// What Telegram will charge for public post search, and the offset of the
/// next page. The footer says both.
@property (nonatomic, strong) NSDictionary *publicLimits;
@property (nonatomic, copy) NSString *publicNextOffset;
@property (nonatomic, assign) BOOL publicLimitExceeded;
/// The query waiting for the public-search debounce. Typing a word is one
/// search, not one per letter - public queries cost an allowance.
@property (nonatomic, copy) NSString *pendingPublicQuery;
/// t.me links this account followed before it had a chat list.
@property (nonatomic, strong) NSArray *recentLinks;
@property (nonatomic, strong) NSMutableDictionary *avatars;
@property (nonatomic, strong) NSMutableSet *avatarsRequested;
@end

/// The bar in the navigation item, which is narrower than the screen so the
/// Cancel button has somewhere to sit.
static const CGFloat kSearchBarWidth = 240.0f;

static NSString *TGPublicPostText(NSDictionary *message) {
	NSDictionary *content = [message[@"content"] isKindOfClass:NSDictionary.class]
			? message[@"content"] : nil;
	NSDictionary *text = [content[@"text"] isKindOfClass:NSDictionary.class]
			? content[@"text"] : nil;
	if (![text[@"text"] isKindOfClass:NSString.class])
		text = [content[@"caption"] isKindOfClass:NSDictionary.class]
				? content[@"caption"] : nil;
	if ([text[@"text"] isKindOfClass:NSString.class])
		return [text[@"text"] stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *kind = [content[@"@type"] isKindOfClass:NSString.class]
			? content[@"@type"] : nil;
	if ([kind hasPrefix:@"message"])
		return [kind substringFromIndex:7];
	return @"";
}

@implementation TGSearchViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.chatHits = @[];
	self.messageHits = @[];
	self.hashtagHits = @[];
	self.recentTags = @[];
	self.suggestions = @[];
	self.publicHits = @[];
	self.recentLinks = @[];
	self.publicNextOffset = @"";
	self.publicLimitExceeded = NO;
	self.avatars = [NSMutableDictionary dictionary];
	self.avatarsRequested = [NSMutableSet set];
	self.tableView.rowHeight = TGMetricPersonRow;
	if ([self.tableView respondsToSelector:@selector(setKeyboardDismissMode:)])
		self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, kSearchBarWidth, TGMetricRow)];
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

	// A row's fate is not a control: the hold reaches what a tap cannot, and
	// the same pattern as the topics list carries it.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(rowHeld:)];
	hold.minimumPressDuration = 0.55;
	[self.tableView addGestureRecognizer:hold];

	[self loadFrequentChats];
	[self loadRecentTags];
	[self loadRecentLinks];
	[self.bar becomeFirstResponder];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleSearchBar:self.bar];
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
	[self loadRecentlyFound];
}

- (void)loadRecentlyFound {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchRecentlyFoundChats:@"" completion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me || me.bar.text.length)
			return;
		me.recentlyFound = chats ?: @[];
		[me.tableView reloadData];
	}];
}

- (void)loadRecentTags {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentHashtagsWithCompletion:^(NSArray *tags){
		TGSearchViewController *me = weakSelf;
		if (!me || me.bar.text.length)
			return;
		me.recentTags = tags ?: @[];
		[me.tableView reloadData];
	}];
}

- (void)loadRecentLinks {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recentlyVisitedTMeUrlsWithReferrer:@""
											   completion:^(NSArray *urls){
		TGSearchViewController *me = weakSelf;
		if (!me || me.bar.text.length)
			return;
		me.recentLinks = urls ?: @[];
		[me.tableView reloadData];
	}];
}

/// True while the search is empty, which is when the frequent list is what
/// the table shows.
- (BOOL)showsFrequent {
	return !self.bar.text.length &&
		   (self.frequent.count > 0 || self.recent.count > 0 ||
			self.recentlyFound.count > 0 || self.recentTags.count > 0 ||
			self.recentLinks.count > 0);
}

/// While the search is empty the sections are the people, the places, the
/// recently-found log, the tags and the links. A row is read out of whichever
/// list its section stands for.
- (NSDictionary *)emptyStateRowAt:(NSIndexPath *)indexPath {
	NSArray *list = nil;
	if (indexPath.section == 0)
		list = self.frequent;
	else if (indexPath.section == 1)
		list = self.recent;
	else if (indexPath.section == 2)
		list = self.recentlyFound;
	return indexPath.row < (NSInteger)list.count ? list[indexPath.row] : nil;
}

/// The hold lands wherever the finger is, so the row is found from the point;
/// a miss does nothing rather than guessing the last row. Only the people row
/// answers it: Telegram ranks that list by numbers, and the only say anyone
/// has over it is to take someone out of it. The places row is a log, not a
/// ranking, and a chat falls out of it by itself the next day. A recent tag
/// has two lists behind it and the sheet offers both removals.
- (void)rowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || !self.showsFrequent)
		return;
	CGPoint where = [hold locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:where];
	if (!path)
		return;

	if (path.section == 3){
		if (path.row >= (NSInteger)self.recentTags.count)
			return;
		NSString *tag = self.recentTags[path.row];
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:@[@"Remove from Recent", @"Remove from Searched"]
							title:[NSString stringWithFormat:@"#%@", tag]
				 destructiveIndex:-1
						   inView:self.view
						 onChoice:^(NSInteger index){
			TGSearchViewController *me = weakSelf;
			if (!me)
				return;
			if (index == 0)
				[[TGClient shared] removeRecentHashtag:tag];
			else
				[[TGClient shared] removeSearchedForTag:tag];
			NSMutableArray *rest = [me.recentTags mutableCopy];
			[rest removeObject:tag];
			me.recentTags = rest;
			[me.tableView reloadData];
		}];
		return;
	}

	if (path.section != 0 && path.section != 2)
		return;
	if (path.row >= (NSInteger)(path.section == 0 ? self.frequent.count
												 : self.recentlyFound.count))
		return;

	NSDictionary *chat = path.section == 0 ? self.frequent[path.row]
										   : self.recentlyFound[path.row];
	NSString *name = chat[@"title"] ?: @"That chat";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:@"%@ goes out of this list.", name]
						title:name
					   action:@"Remove"
				  destructive:NO
					   inView:self.view
					onConfirm:^{
		if (path.section == 0)
			[[TGClient shared] forgetTopChat:[chat[@"id"] longLongValue]];
		else
			[[TGClient shared] forgetRecentlyFoundChat:[chat[@"id"] longLongValue]];
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *rest = [(path.section == 0 ? me.frequent
												   : me.recentlyFound) mutableCopy];
		[rest removeObject:chat];
		if (path.section == 0)
			me.frequent = rest;
		else
			me.recentlyFound = rest;
		[me.tableView reloadData];
	}];
}

#pragma mark - searching

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
	if (!query.length) {
		self.chatHits = @[];
		self.messageHits = @[];
		self.contactHits = @[];
		self.hashtagHits = @[];
		self.suggestions = @[];
		self.publicHits = @[];
		self.publicLimits = nil;
		self.publicLimitExceeded = NO;
		self.pendingPublicQuery = nil;
		[NSObject cancelPreviousPerformRequestsWithTarget:self
				selector:@selector(flushPublicSearch) object:nil];
		// Back to the people and the places rather than to nothing.
		[self loadFrequentChats];
		[self loadRecentTags];
		[self loadRecentLinks];
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
	self.hashtagHits = @[];
	self.suggestions = @[];
	self.publicHits = @[];
	self.publicLimitExceeded = NO;
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	// Matching titles here only ever found chats already loaded, so a chat
	// this account has and has not opened, and every public chat, were
	// unfindable by name.
	[[TGClient shared] searchChatsForQuery:query completion:^(NSArray *chats){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query]) return;
		me.chatHits = chats ?: @[];
		[me refreshPrefixSuggestionsForQuery:query extra:@[]];
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
	[[TGClient shared] searchHashtags:query limit:10 completion:^(NSArray *tags){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query]) return;
		me.hashtagHits = tags ?: @[];
		[me refreshPrefixSuggestionsForQuery:query extra:tags];
		[me.tableView reloadData];
	}];
	[self refreshPrefixSuggestionsForQuery:query extra:@[]];
	[self searchPublicPostsForQuery:query];
}

/// Prefix suggestions are a local problem: the strings are the chat titles
/// this account already has and the tags it searched for. TDLib does the
/// word-prefix match, which is why "te leg" and "tel" agree here.
- (void)refreshPrefixSuggestionsForQuery:(NSString *)query extra:(NSArray *)extra {
	NSMutableArray *strings = [NSMutableArray array];
	for (NSDictionary *chat in [TGClient shared].chats){
		NSString *title = chat[@"title"];
		if (title.length && ![strings containsObject:title])
			[strings addObject:title];
	}
	for (NSString *tag in self.recentTags){
		NSString *hashed = [@"#" stringByAppendingString:tag];
		if (![strings containsObject:hashed])
			[strings addObject:hashed];
	}
	for (NSString *tag in extra ?: @[]){
		NSString *hashed = [@"#" stringByAppendingString:tag];
		if (![strings containsObject:hashed])
			[strings addObject:hashed];
	}
	if (!strings.count)
		return;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] stringsMatchingPrefix:strings query:query limit:10
								  completion:^(NSArray *matches){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query])
			return;
		me.suggestions = matches ?: @[];
		[me.tableView reloadData];
	}];
}

/// Public post search costs a server query, and Telegram says how many are
/// free before it is asked. The limit answer is shown whether or not the
/// search goes ahead, so a blocked row says why instead of looking broken.
/// The wait is one query per typed word rather than one per key.
- (void)searchPublicPostsForQuery:(NSString *)query {
	self.pendingPublicQuery = query;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(flushPublicSearch) object:nil];
	[self performSelector:@selector(flushPublicSearch)
			   withObject:nil afterDelay:0.4];
}

- (void)flushPublicSearch {
	NSString *query = self.pendingPublicQuery;
	if (!query.length || ![self.bar.text isEqualToString:query])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] publicPostSearchLimitsForQuery:query completion:^(NSDictionary *limits){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query])
			return;
		me.publicLimits = limits;
		if (limits &&
			![limits[@"currentIsFree"] boolValue] &&
			[limits[@"remainingFree"] integerValue] <= 0){
			me.publicLimitExceeded = YES;
			[me.tableView reloadData];
			return;
		}
		[[TGClient shared] searchPublicPosts:query offset:@"" limit:20 starCount:0
								  completion:^(NSArray *messages, NSString *next,
											   NSDictionary *answerLimits, BOOL exceeded){
			TGSearchViewController *live = weakSelf;
			if (!live || ![live.bar.text isEqualToString:query])
				return;
			live.publicHits = messages ?: @[];
			live.publicNextOffset = next ?: @"";
			if (answerLimits)
				live.publicLimits = answerLimits;
			live.publicLimitExceeded = exceeded;
			[live.tableView reloadData];
		}];
	}];
}

- (void)loadMorePublicPosts {
	NSString *query = self.bar.text;
	NSString *offset = self.publicNextOffset;
	if (!query.length || !offset.length || self.publicLimitExceeded)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchPublicPosts:query offset:offset limit:20 starCount:0
							  completion:^(NSArray *messages, NSString *next,
										   NSDictionary *limits, BOOL exceeded){
		TGSearchViewController *me = weakSelf;
		if (!me || ![me.bar.text isEqualToString:query])
			return;
		NSMutableArray *joined = [me.publicHits mutableCopy];
		[joined addObjectsFromArray:messages ?: @[]];
		me.publicHits = joined;
		me.publicNextOffset = next ?: @"";
		if (limits)
			me.publicLimits = limits;
		me.publicLimitExceeded = exceeded;
		[me.tableView reloadData];
	}];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// Before a query: people, places, recently found, tags and links. While
	// searching: suggestions, chats, contacts, messages, tags and posts.
	return [self showsFrequent] ? 5 : 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ([self showsFrequent]){
		if (section == 0) return self.frequent.count;
		if (section == 1) return self.recent.count;
		// The last row of a log is the clear action; it exists only when
		// there is a log to clear.
		if (section == 2) return self.recentlyFound.count ? self.recentlyFound.count + 1 : 0;
		if (section == 3) return self.recentTags.count ? self.recentTags.count + 1 : 0;
		return self.recentLinks.count;
	}
	if (section == 0) return self.suggestions.count;
	if (section == 1) return self.chatHits.count;
	if (section == 2) return self.contactHits.count;
	if (section == 3) return self.messageHits.count;
	if (section == 4) return self.hashtagHits.count;
	return self.publicHits.count +
			((self.publicNextOffset.length && !self.publicLimitExceeded) ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self showsFrequent]){
		if (section == 0) return self.frequent.count ? @"People" : nil;
		if (section == 1) return self.recent.count ? @"Recent" : nil;
		if (section == 2) return self.recentlyFound.count ? @"Recently Found" : nil;
		if (section == 3) return self.recentTags.count ? @"Recent Hashtags" : nil;
		return self.recentLinks.count ? @"Recently Visited Links" : nil;
	}
	if (section == 0) return self.suggestions.count ? @"Suggestions" : nil;
	if (section == 1) return self.chatHits.count ? @"Chats" : nil;
	if (section == 2) return self.contactHits.count ? @"Contacts" : nil;
	if (section == 3) return self.messageHits.count ? @"Messages" : nil;
	if (section == 4) return self.hashtagHits.count ? @"Hashtags" : nil;
	return self.publicHits.count ? @"Public Posts" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if ([self showsFrequent] || section != 5 || !self.bar.text.length)
		return nil;
	if (self.publicLimitExceeded){
		NSInteger wait = [self.publicLimits[@"nextFreeIn"] integerValue];
		return wait > 0
				? [NSString stringWithFormat:@"Public post search needs Telegram Stars. Next free search in %ld s.",
						(long)wait]
				: @"Public post search needs Telegram Stars right now.";
	}
	NSInteger left = [self.publicLimits[@"remainingFree"] integerValue];
	if (self.publicLimits && left > 0)
		return left == 1 ? @"1 free public post search left today."
						 : [NSString stringWithFormat:@"%ld free public post searches left today.",
								(long)left];
	return self.publicHits.count ? nil : @"Telegram answers public posts here.";
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
		cell.imageView.layer.cornerRadius = TGHalf(TGMetricListAvatar);
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
	cell.imageView.image = nil;

	if ([self showsFrequent]) {
		// The last row of a log is the clear action.
		if (indexPath.section == 2 &&
			indexPath.row >= (NSInteger)self.recentlyFound.count){
			cell.textLabel.text = @"Clear Recently Found";
			cell.textLabel.textColor = [theme destructiveColour];
			cell.detailTextLabel.text = nil;
			cell.accessoryType = UITableViewCellAccessoryNone;
			return cell;
		}
		if (indexPath.section == 3 &&
			indexPath.row >= (NSInteger)self.recentTags.count){
			cell.textLabel.text = @"Clear Recent Hashtags";
			cell.textLabel.textColor = [theme destructiveColour];
			cell.detailTextLabel.text = nil;
			cell.accessoryType = UITableViewCellAccessoryNone;
			return cell;
		}
		if (indexPath.section == 3){
			cell.textLabel.text = [NSString stringWithFormat:@"#%@", self.recentTags[indexPath.row]];
			cell.detailTextLabel.text = @"Recent hashtag";
			return cell;
		}
		if (indexPath.section == 4){
			NSDictionary *link = self.recentLinks[indexPath.row];
			cell.textLabel.text = link[@"url"] ?: @"";
			cell.detailTextLabel.text = @"Recently visited";
			return cell;
		}
		NSDictionary *c = [self emptyStateRowAt:indexPath];
		cell.textLabel.text = c[@"title"];
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = c[@"previewText"];
		cell.imageView.image = [self avatarForChat:[c[@"id"] longLongValue]
											 title:c[@"title"]
											fileId:c[@"photoFileId"]];
	} else if (indexPath.section == 0) {
		cell.textLabel.text = self.suggestions[indexPath.row];
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = @"Suggestion";
	} else if (indexPath.section == 1) {
		NSDictionary *c = self.chatHits[indexPath.row];
		// A public chat the list has never seen answers with no title until
		// its own fetch lands; the row says so rather than being blank.
		NSString *title = [c[@"title"] length] ? c[@"title"] : @"Loading...";
		cell.textLabel.text = title;
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = c[@"text"];
		cell.imageView.image = [self avatarForChat:[c[@"id"] longLongValue]
											 title:title
											fileId:c[@"photoFileId"]];
	} else if (indexPath.section == 2) {
		NSDictionary *u = self.contactHits[indexPath.row];
		NSString *name = [u[@"name"] length] ? u[@"name"]
				: [[TGClient shared] nameForUserId:[u[@"id"] longLongValue]];
		cell.textLabel.text = name ?: @"";
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = nil;
		cell.imageView.image = [self avatarForChat:[u[@"id"] longLongValue]
											 title:name
											fileId:nil];
	} else if (indexPath.section == 3) {
		NSDictionary *m = self.messageHits[indexPath.row];
		cell.textLabel.text = m[@"chatTitle"];
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = m[@"text"];
		cell.imageView.image = [self avatarForChat:[m[@"chatId"] longLongValue]
											 title:m[@"chatTitle"]
											fileId:nil];
	} else if (indexPath.section == 4) {
		cell.textLabel.text = [NSString stringWithFormat:@"#%@", self.hashtagHits[indexPath.row]];
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = @"Search public posts";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		if (indexPath.row >= (NSInteger)self.publicHits.count){
			cell.textLabel.text = @"Load More Public Posts";
			cell.textLabel.textColor = [theme accentColour];
			cell.detailTextLabel.text = nil;
			cell.accessoryType = UITableViewCellAccessoryNone;
			return cell;
		}
		NSDictionary *m = self.publicHits[indexPath.row];
		int64_t chatId = [m[@"chat_id"] longLongValue];
		NSString *title = [[TGClient shared] titleForChat:chatId] ?: @"Public Post";
		cell.textLabel.text = title;
		cell.textLabel.textColor = [theme primaryTextColour];
		cell.detailTextLabel.text = TGPublicPostText(m);
		cell.imageView.image = [self avatarForChat:chatId title:title fileId:nil];
	}

	return cell;
}

/// Telegram's own link handler, trimmed to what a recent t.me URL can be:
/// a chat, a message, an invite or a plain address.
- (void)openRecentTMeLink:(NSString *)link {
	if (!link.length)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] internalLinkKind:link completion:^(NSString *kind, NSString *value){
		TGSearchViewController *me = weakSelf;
		if (!me)
			return;
		if ([kind isEqualToString:@"publicChat"] && value.length){
			[[TGClient shared] chatWithUsername:value completion:^(int64_t chatId, NSString *title){
				TGSearchViewController *live = weakSelf;
				if (!live || !chatId)
					return;
				TGChatViewController *chat = [[TGChatViewController alloc] init];
				chat.chatId = chatId;
				chat.chatTitle = title.length ? title : value;
				chat.hidesBottomBarWhenPushed = YES;
				[live.navigationController pushViewController:chat animated:YES];
			}];
			return;
		}
		if ([kind isEqualToString:@"message"] && value.length){
			[[TGClient shared] messageLinkInfo:value completion:^(int64_t chatId, int64_t messageId){
				TGSearchViewController *live = weakSelf;
				if (!live || !chatId)
					return;
				TGChatViewController *chat = [[TGChatViewController alloc] init];
				chat.chatId = chatId;
				chat.chatTitle = [[TGClient shared] titleForChat:chatId] ?: @"Chat";
				chat.initialMessageId = messageId;
				chat.hidesBottomBarWhenPushed = YES;
				[live.navigationController pushViewController:chat animated:YES];
			}];
			return;
		}
		if ([kind isEqualToString:@"inviteLink"] && value.length){
			[[TGClient shared] joinChatByInviteLink:value completion:^(int64_t chatId, NSString *title){
				TGSearchViewController *live = weakSelf;
				if (!live || !chatId)
					return;
				TGChatViewController *chat = [[TGChatViewController alloc] init];
				chat.chatId = chatId;
				chat.chatTitle = title.length ? title : @"Chat";
				chat.hidesBottomBarWhenPushed = YES;
				[live.navigationController pushViewController:chat animated:YES];
			}];
			return;
		}
		NSURL *url = [NSURL URLWithString:link];
		if (url)
			[[UIApplication sharedApplication] openURL:url];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.bar resignFirstResponder];

	BOOL fromFrequent = [self showsFrequent];

	if (fromFrequent && indexPath.section == 3){
		if (indexPath.row >= (NSInteger)self.recentTags.count){
			__weak typeof(self) weakSelf = self;
			[TGAlertSheet showConfirm:@"Every searched-for hashtag is forgotten. The tags themselves stay on Telegram."
								title:@"Clear Recent Hashtags"
							   action:@"Clear" destructive:YES inView:self.view
							onConfirm:^{
				[[TGClient shared] clearSearchedForTags];
				weakSelf.recentTags = @[];
				[weakSelf.tableView reloadData];
			}];
			return;
		}
		NSString *tag = self.recentTags[indexPath.row];
		self.bar.text = [NSString stringWithFormat:@"#%@", tag];
		[self searchBar:self.bar textDidChange:self.bar.text];
		return;
	}
	if (fromFrequent && indexPath.section == 4){
		[self openRecentTMeLink:self.recentLinks[indexPath.row][@"url"]];
		return;
	}

	// A contact is a person, not a chat: the private chat with them has to be
	// asked for before there is anything to open.
	if (!fromFrequent && indexPath.section == 2){
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

	if (!fromFrequent && indexPath.section == 0){
		NSString *suggestion = self.suggestions[indexPath.row];
		self.bar.text = suggestion;
		[self searchBar:self.bar textDidChange:suggestion];
		return;
	}

	if (!fromFrequent && indexPath.section == 4){
		NSString *tag = self.hashtagHits[indexPath.row];
		self.bar.text = [NSString stringWithFormat:@"#%@", tag];
		[self searchBar:self.bar textDidChange:self.bar.text];
		return;
	}

	if (!fromFrequent && indexPath.section == 5){
		if (indexPath.row >= (NSInteger)self.publicHits.count){
			[self loadMorePublicPosts];
			return;
		}
		NSDictionary *m = self.publicHits[indexPath.row];
		int64_t chatId = [m[@"chat_id"] longLongValue];
		if (!chatId)
			return;
		[[TGClient shared] rememberFoundChat:chatId];
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = chatId;
		chat.chatTitle = [[TGClient shared] titleForChat:chatId] ?: @"Public Post";
		chat.initialMessageId = [m[@"id"] longLongValue];
		chat.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:chat animated:YES];
		return;
	}

	if (fromFrequent && indexPath.section == 2 &&
		indexPath.row >= (NSInteger)self.recentlyFound.count){
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showConfirm:@"Every chat in the recently-found list is "
								  @"forgotten. The chats themselves stay."
							title:@"Clear Recently Found"
						   action:@"Clear" destructive:YES inView:self.view
						onConfirm:^{
			[[TGClient shared] clearRecentlyFoundChats];
			weakSelf.recentlyFound = @[];
			[weakSelf.tableView reloadData];
		}];
		return;
	}

	NSDictionary *row = fromFrequent ? [self emptyStateRowAt:indexPath]
			: (indexPath.section == 1 ? self.chatHits[indexPath.row]
									  : self.messageHits[indexPath.row]);
	int64_t chatId = [((fromFrequent || indexPath.section == 1)
			? row[@"id"] : row[@"chatId"]) longLongValue];
	if (!chatId)
		return;

	// Opening a chat from search is what puts it in the recently-found list,
	// which is the other half of what this screen shows when it is empty.
	[[TGClient shared] rememberFoundChat:chatId];

	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = (fromFrequent || indexPath.section == 1)
			? row[@"title"] : row[@"chatTitle"];
	chat.isGroup = [row[@"isGroup"] boolValue];
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

@end

// vim:ft=objc
