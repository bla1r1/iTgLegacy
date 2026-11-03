#import "TGContactsViewController.h"
#import "TGNewContactViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGEmptyView.h"
#import "TGDevShowcase.h"
#import "TGImageLruCache.h"

/// Avatars kept decoded while the list is open.
static const NSUInteger kPhotoCacheCap = 50;


@interface TGContactsViewController ()
@property (nonatomic, strong) TGEmptyView *emptyView;
@property (nonatomic, strong) NSArray *users;
/// The same contacts split by their first letter, so the list reads like
/// Telegram's address book instead of one long run of names.
@property (nonatomic, strong) NSArray *sections;
/// Bounded: a long contact list scrolled end to end used to hold every
/// avatar it had ever decoded, and fifty is more than a screen holds.
@property (nonatomic, strong) TGImageLruCache *photos;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *photosRequested;
/// Who is ticked, while this screen is picking rather than opening.
@property (nonatomic, strong) NSMutableSet *picked;
/// How many contacts this account has uploaded from a phone's address book.
/// The footer is where it stays visible after an import.
@property (nonatomic, assign) NSInteger importedCount;
@end

/// A contact row with its avatar inset and a fixed size. The stock cell sized
/// the image view to the picture and put it at x 0 on iOS 6, so a large
/// photo filled the row's height flush against the screen edge.
@interface TGContactCell : UITableViewCell
@end

@implementation TGContactCell
- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat side = TGMetricListAvatar;
	CGFloat h = self.contentView.bounds.size.height;
	self.imageView.frame = CGRectMake(TGMetricPad, TGCenteredOrigin(h, side), side, side);
	CGFloat x = TGMetricPad + side + TGMetricPadMedium;
	// To the content view's edge: UIKit sized the labels for the picture as
	// it was before the inset, and the names came out cut short.
	CGFloat width = MAX(0, self.contentView.bounds.size.width - x - TGMetricPadMedium);
	for (UILabel *label in @[self.textLabel, self.detailTextLabel]) {
		CGRect f = label.frame;
		f.origin.x = x;
		f.size.width = width;
		label.frame = f;
	}
}
@end

static NSString *TGContactName(NSDictionary *u);

/// A name's section letter. Anything that is not a letter lands in "#", the
/// way the phone's address book groups punctuation and emoji.
static NSString *TGContactSectionTitle(NSString *name) {
	NSString *trimmed = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length)
		return @"#";
	NSString *first = [[trimmed substringToIndex:1] uppercaseString];
	unichar c = [first characterAtIndex:0];
	if ((c >= 'A' && c <= 'Z') || (c >= 0x0400 && c <= 0x04FF))
		return first;
	return @"#";
}

/// Contacts grouped in the order the list already sorted them. The "#"
/// bucket always comes last, so it does not push A down the screen.
static NSArray *TGContactSections(NSArray *users) {
	NSMutableArray *sections = [NSMutableArray array];
	NSMutableDictionary *byTitle = [NSMutableDictionary dictionary];
	for (NSDictionary *user in users){
		NSString *title = TGContactSectionTitle(TGContactName(user));
		NSMutableArray *bucket = byTitle[title];
		if (!bucket){
			bucket = [NSMutableArray array];
			byTitle[title] = bucket;
			[sections addObject:@{@"title" : title, @"users" : bucket}];
		}
		[bucket addObject:user];
	}
	// "#" is appended last; then the letters are already in sorted-name order.
	NSArray *sorted = [sections sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		NSString *ta = a[@"title"], *tb = b[@"title"];
		if ([ta isEqualToString:@"#"]) return NSOrderedDescending;
		if ([tb isEqualToString:@"#"]) return NSOrderedAscending;
		return [ta localizedCaseInsensitiveCompare:tb];
	}];
	return sorted;
}

@implementation TGContactsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.picked = [NSMutableSet set];
	self.title = [self isPicking]
			? (self.addingToChatId ? @"Add Members" : @"New Group")
			: @"Contacts";
	if ([self isPicking]){
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:(self.addingToChatId ? @"Add" : @"Create")
						style:UIBarButtonItemStyleDone
					   target:self action:@selector(commitPicking)];
		self.navigationItem.rightBarButtonItem.enabled = NO;
	} else {
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
									 target:self
									 action:@selector(addContactTapped)];
	}
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.users = @[];
	self.sections = @[];
	self.photos = [[TGImageLruCache alloc] initWithCapacity:kPhotoCacheCap];
	self.photosRequested = [NSMutableSet set];
	self.tableView.rowHeight = TGMetricPersonRow;
	// No separators drawn under the last contact, across the empty screen.
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	__weak typeof(self) weakContacts = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		TGContactsViewController *me = weakContacts;
		[TGIcons flush];
		me.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		me.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[[TGTheme shared] styleNavigationBar:me.navigationController.navigationBar];
		[me.tableView reloadData];
	}];

	[self loadContacts];
}

- (void)addContactTapped {
	TGNewContactViewController *vc = [[TGNewContactViewController alloc] init];
	vc.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

/// The count is the account's, not the list's: TDLib answers it separately,
/// and after an import it is the only place the result is visible.
- (void)updateImportedFooter {
	UILabel *footer = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, TGMetricLineRow)];
	footer.text = self.importedCount
			? [NSString stringWithFormat:@"%ld imported contacts",
					(long)self.importedCount]
			: @"No contacts imported from a phone book";
	footer.font = TGFontCaption();
	footer.textAlignment = NSTextAlignmentCenter;
	footer.textColor = [[TGTheme shared] secondaryTextColour];
	footer.backgroundColor = [UIColor clearColor];
	self.tableView.tableFooterView = footer;
}

- (void)loadContacts {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] importedContactCountWithCompletion:^(NSInteger count){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		me.importedCount = count;
		[me updateImportedFooter];
	}];
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *list = [NSMutableArray arrayWithArray:users ?: @[]];
		// The showcase people are a signed-out fixture. On a real account an
		// empty contact list must stay empty, so the empty view can show.
		if (list.count == 0 && ![[TGClient shared] hasSignedInAccount]) {
			[list addObjectsFromArray:[TGDevShowcase allShowcaseContacts]];
		}
		me.users = [list sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
			return [TGContactName(a) localizedCaseInsensitiveCompare:TGContactName(b)];
		}];
		me.sections = TGContactSections(me.users);
		[me.tableView reloadData];
		[me fetchMissingPhotos];

		if (me.users.count == 0) {
			if (!me.emptyView) {
				me.emptyView = [TGEmptyView emptyViewWithFrame:me.view.bounds
				                                         image:[TGIcons emptyContactsIllustration]
				                                         title:@"No Contacts"
				                                      subtitle:@"Find and add people to start\nchatting with them on Telegram."
				                                   buttonTitle:@"Add Contact"
				                                        target:me
				                                        action:@selector(addContactTapped)];
				[me.view addSubview:me.emptyView];
			}
			me.emptyView.hidden = NO;
		} else if (me.emptyView) {
			me.emptyView.hidden = YES;
		}
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self loadContacts];
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self.tableView selector:@selector(reloadData) object:nil];
	[self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.05];
}

- (void)fetchMissingPhotos {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *u in self.users){
		NSNumber *fileId = u[@"photoFileId"];
		if (![fileId isKindOfClass:NSNumber.class]) continue;
		if (self.photos[fileId] || [self.photosRequested containsObject:fileId])
			continue;
		[self.photosRequested addObject:fileId];

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				UIImage *photo = [UIImage imageWithContentsOfFile:path];
				if (!photo) return;
				
				// A cell's own imageView takes the image's size, so a 160px photo
				// would shove the name off the row. Scale once, on arrival.
				UIGraphicsBeginImageContextWithOptions(
						CGSizeMake(TGMetricListAvatar, TGMetricListAvatar), NO, 0);
				[photo drawInRect:CGRectMake(0, 0, TGMetricListAvatar, TGMetricListAvatar)];
				UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();
				
				dispatch_async(dispatch_get_main_queue(), ^{
					TGContactsViewController *me = weakSelf;
					if (!me) return;
					me.photos[fileId] = scaled;
					[me reloadTableDebounced];
				});
			});
		}];
	}
}

static NSString *TGContactName(NSDictionary *u) {
	NSString *first = u[@"first_name"] ?: @"";
	NSString *last  = u[@"last_name"] ?: @"";
	NSString *name  = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (name.length)
		return name;
	if ([u[@"username"] length])
		return [NSString stringWithFormat:@"@%@", u[@"username"]];
	return u[@"phone"] ?: @"";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return 0;
	return [self.sections[(NSUInteger)section][@"users"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return nil;
	return self.sections[(NSUInteger)section][@"title"];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
	// A short list reads worse with a rail down the side; Telegram keeps it
	// for an address book that is actually long.
	if (self.sections.count < 8)
		return nil;
	NSMutableArray *titles = [NSMutableArray array];
	for (NSDictionary *section in self.sections)
		[titles addObject:section[@"title"]];
	return titles;
}

- (NSInteger)tableView:(UITableView *)tableView
 sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
	return index;
}

- (NSDictionary *)userAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || indexPath.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *users = self.sections[(NSUInteger)indexPath.section][@"users"];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)users.count)
		return nil;
	return users[(NSUInteger)indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									reuseIdentifier:reuse];

	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u)
		return cell;
	NSString *name = TGContactName(u);
	UIColor *bg = [[TGTheme shared] listBackgroundColour];
	cell.backgroundColor = bg;
	cell.textLabel.backgroundColor = bg;
	cell.textLabel.opaque = YES;
	cell.textLabel.text = name;
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.backgroundColor = bg;
	cell.detailTextLabel.opaque = YES;
	// Telegram puts the @name under a contact who has one and the number
	// under everyone else. The number is still what a call needs, so it is
	// the fallback rather than a second line that would not fit this row.
	if ([u[@"username"] length])
		cell.detailTextLabel.text = [@"@" stringByAppendingString:u[@"username"]];
	else
		cell.detailTextLabel.text = [u[@"phone"] length]
				? [NSString stringWithFormat:@"+%@", u[@"phone"]] : @"";
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.accessoryType = [self isPicking]
			? ([self.picked containsObject:u[@"id"]]
					? UITableViewCellAccessoryCheckmark
					: UITableViewCellAccessoryNone)
			: UITableViewCellAccessoryDisclosureIndicator;

	NSNumber *fileId = u[@"photoFileId"];
	UIImage *photo = [fileId isKindOfClass:NSNumber.class] ? self.photos[fileId] : nil;
	int64_t uid = [u[@"id"] longLongValue];
	if (![[TGClient shared] hasSignedInAccount] && (uid == 20002 || uid == 10001)) {
		photo = [TGDevShowcase avatarForUserId:uid];
	}
	if (!photo)
		photo = [TGIcons avatarWithInitials:
					(name.length ? [name substringToIndex:1].uppercaseString : @"?")
									   size:TGMetricListAvatar
								   colourId:[u[@"id"] longLongValue]];
	// Cropped and rounded once at the row's size: no clip, no rasterizing.
	cell.imageView.image = [TGIcons roundedImage:photo
										   size:CGSizeMake(TGMetricListAvatar, TGMetricListAvatar)
										 radius:TGHalf(TGMetricListAvatar)
										corners:UIRectCornerAllCorners];

	return cell;
}

/// Either mode ticks rows; the difference is what the button at the top does
/// with them.
- (BOOL)isPicking {
	return self.picksGroupMembers || self.addingToChatId != 0;
}

/// A group needs a name and at least one other person - TDLib refuses an
/// empty one - so the name is asked for once the picking is done.
- (void)commitPicking {
	NSArray *userIds = self.picked.allObjects;
	if (!userIds.count)
		return;

	__weak typeof(self) weakSelf = self;
	if (self.addingToChatId){
		int64_t chatId = self.addingToChatId;
		// One person is addChatMember, the request their own client sends
		// when a profile's "Add to Group" names a single user; the batch
		// form is for the picker's many. Same answer either way.
		if (userIds.count == 1){
			NSNumber *only = userIds.firstObject;
			[[TGClient shared] addUser:only.longLongValue
								toChat:chatId
							completion:^(BOOL ok, NSArray *refused){
				TGContactsViewController *me = weakSelf;
				if (!ok)
					[TGAlertSheet showMessage:@"Telegram refused - their "
							@"privacy settings keep them out of new groups."
										  title:@"Add Members" inView:me.view];
				[me.navigationController popViewControllerAnimated:YES];
			}];
			return;
		}
		// One request for the whole pick: the N-request loop this replaced
		// answered the server once per contact and could strand half of the
		// batch on a slow connection.
		[[TGClient shared] addUsers:userIds toChat:chatId completion:^(BOOL ok, NSArray *refused){
			TGContactsViewController *me = weakSelf;
			if (refused.count)
				[TGAlertSheet showMessage:[NSString stringWithFormat:
								@"%lu of them could not be added - their "
								@"privacy settings refuse group invitations.",
								(unsigned long)refused.count]
									title:@"Add Members" inView:me.view];
			[me.navigationController popViewControllerAnimated:YES];
		}];
		return;
	}

	[TGAlertSheet showInput:@"New Group"
					message:[NSString stringWithFormat:@"%lu %@ selected.",
							(unsigned long)userIds.count,
							userIds.count == 1 ? @"person" : @"people"]
				placeholder:@"Group name"
					   text:nil
					 action:@"Create"
					 inView:self.view
				   onSubmit:^(NSString *title){
		[[TGClient shared] createGroupNamed:title withUsers:userIds
								 completion:^(int64_t chatId, NSArray *failed){
			TGContactsViewController *me = weakSelf;
			if (!chatId){
				[TGAlertSheet showMessage:@"Telegram refused that group."
									title:@"New Group" inView:me.view];
				return;
			}
			TGChatViewController *chat = [[TGChatViewController alloc] init];
			chat.chatId = chatId;
			chat.chatTitle = title;
			chat.hidesBottomBarWhenPushed = YES;
			// Replaces this screen rather than stacking on it: going back
			// from the new group belongs in the chat list.
			NSMutableArray *stack = [me.navigationController.viewControllers mutableCopy];
			[stack removeLastObject];
			[stack addObject:chat];
			[me.navigationController setViewControllers:stack animated:YES];

			if (failed.count)
				[TGAlertSheet showMessage:[NSString stringWithFormat:
								@"%lu of them could not be added - their privacy "
								@"settings refuse group invitations.",
								(unsigned long)failed.count]
									title:@"New Group" inView:chat.view];
		}];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSDictionary *u = [self userAtIndexPath:indexPath];
	if (!u)
		return;
	if ([self isPicking]){
		NSNumber *userId = u[@"id"];
		if ([self.picked containsObject:userId])
			[self.picked removeObject:userId];
		else
			[self.picked addObject:userId];
		self.navigationItem.rightBarButtonItem.enabled = self.picked.count > 0;
		[tableView reloadRowsAtIndexPaths:@[indexPath]
						 withRowAnimation:UITableViewRowAnimationNone];
		return;
	}
	NSString *name = TGContactName(u);
	int64_t uid = [u[@"id"] longLongValue];
	if (![[TGClient shared] hasSignedInAccount]) {
		// Signed-out bench only: real users can carry these ids too.
		if (uid == 20002) {
			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = kDevDurovChatId;
			vc.chatTitle = name;
			vc.hidesBottomBarWhenPushed = YES;
			[self.navigationController pushViewController:vc animated:YES];
			return;
		} else if (uid == 10001) {
			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = kDevBotChatId;
			vc.chatTitle = name;
			vc.hidesBottomBarWhenPushed = YES;
			[self.navigationController pushViewController:vc animated:YES];
			return;
		}
	}

	__weak typeof(self) weakSelf = self;

	[[TGClient shared] privateChatWithUser:[u[@"id"] longLongValue]
								completion:^(int64_t chatId){
		TGContactsViewController *me = weakSelf;
		if (!me || chatId == 0)
			return;
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = chatId;
		vc.chatTitle = name;
		vc.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// The system's caption is grey on grey over a dark list, which is what
/// this screen had: every other list styles its own.

@end

// vim:ft=objc
