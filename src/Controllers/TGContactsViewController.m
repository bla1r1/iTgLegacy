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


@interface TGContactsViewController ()
@property (nonatomic, strong) TGEmptyView *emptyView;
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSMutableDictionary *photos;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *photosRequested;
/// Who is ticked, while this screen is picking rather than opening.
@property (nonatomic, strong) NSMutableSet *picked;
@end

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
	self.photos = [NSMutableDictionary dictionary];
	self.photosRequested = [NSMutableSet set];
	self.tableView.rowHeight = TGMetricPersonRow;
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

- (void)loadContacts {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] contactsWithCompletion:^(NSArray *users){
		TGContactsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *list = [NSMutableArray arrayWithArray:users ?: @[]];
		if (list.count == 0) {
			[list addObjectsFromArray:[TGDevShowcase allShowcaseContacts]];
		}
		me.users = [list sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
			return [a[@"first_name"] localizedCaseInsensitiveCompare:b[@"first_name"]];
		}];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.users.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGContactCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];

	NSDictionary *u = self.users[indexPath.row];
	NSString *name = TGContactName(u);
	UIColor *bg = [[TGTheme shared] listBackgroundColour];
	cell.backgroundColor = bg;
	cell.textLabel.backgroundColor = bg;
	cell.textLabel.opaque = YES;
	cell.textLabel.text = name;
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.backgroundColor = bg;
	cell.detailTextLabel.opaque = YES;
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
	if (uid == 20002 || uid == 10001) {
		photo = [TGDevShowcase avatarForUserId:uid];
	}
	if (!photo)
		photo = [TGIcons avatarWithInitials:
					(name.length ? [name substringToIndex:1].uppercaseString : @"?")
									   size:TGMetricListAvatar
								   colourId:[u[@"id"] longLongValue]];
	cell.imageView.image = photo;
	cell.imageView.layer.cornerRadius = TGHalf(TGMetricListAvatar);
	cell.imageView.clipsToBounds = YES;
	cell.imageView.layer.shouldRasterize = YES;
	cell.imageView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	cell.imageView.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	cell.imageView.layer.borderWidth = 1.0f;
	cell.imageView.contentMode = UIViewContentModeScaleAspectFill;

	if ([TGTheme shared].isDark) {
		UIView *selected = [[UIView alloc] init];
		selected.backgroundColor = [[TGTheme shared] bubbleTheirsColour];
		cell.selectedBackgroundView = selected;
	} else {
		cell.selectedBackgroundView = nil;
	}
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

	NSDictionary *u = self.users[indexPath.row];
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
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

@end

// vim:ft=objc
