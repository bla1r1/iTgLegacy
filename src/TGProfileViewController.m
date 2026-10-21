#import "TGProfileViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCallViewController.h"
#import "TGPopupMenu.h"
#import "TGForwardPicker.h"

@interface TGProfileViewController () <UIActionSheetDelegate, UIAlertViewDelegate,
		UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *mediaStrip;
@property (nonatomic, strong) NSMutableSet *thumbnailsRequested;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSArray *details;   // label/value pairs
@property (nonatomic, strong) NSArray *photos;    // flattened messages
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) NSArray *members;
@property (nonatomic, strong) NSArray *gifts;
@property (nonatomic, strong) NSArray *stories;
@property (nonatomic, assign) BOOL blocked;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UITableViewCell *mediaStripCell;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray *actionNames;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSString *phoneNumber;
@property (nonatomic, assign) NSInteger selectedMediaTab;
@end

// A tile in the action row: a glyph over a word.
static const CGFloat kActionTile = 52.0f;

@implementation TGProfileViewController

- (instancetype)initWithChatId:(int64_t)chatId userId:(int64_t)userId title:(NSString *)title {
	if ((self = [super initWithStyle:UITableViewStyleGrouped])){
		_chatId = chatId;
		_userId = userId;
		_name = title ?: @"";
		_details = @[];
		_photos = @[];
		_files = @[];
		_thumbnailsRequested = [NSMutableSet set];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Info";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];

	[self buildHeader];
	[self loadDetails];
	[self loadMedia];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf buildHeader];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme groupedBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

/// The profile as the current client draws it: a large picture centred, the
/// name and status under it, and a row of tiles for the things you actually do
/// here. The coloured block this replaced is the old design; everything since
- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width;
	CGFloat side = 80;
	CGFloat height = 16 + side + 8 + 26 + 18 + 10 + kActionTile + 12;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake((width - side) / 2, 16, side, side)];
	self.avatarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleRightMargin;
	self.avatarView.layer.cornerRadius = side / 2;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.layer.shouldRasterize = YES;
	self.avatarView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	NSString *initials = self.name.length ? [self.name substringToIndex:1] : @"?";
	self.avatarView.image = [TGIcons avatarWithInitials:initials.uppercaseString
												   size:side
											   colourId:self.userId ?: self.chatId];
	[header addSubview:self.avatarView];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 16 + side + 8, width - 20, 26)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = self.name;
	nameLabel.font = [UIFont boldSystemFontOfSize:21];
	nameLabel.textAlignment = NSTextAlignmentCenter;
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.textColor = [[TGTheme shared] primaryTextColour];
	[header addSubview:nameLabel];

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 16 + side + 34, width - 20, 18)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.font = [UIFont systemFontOfSize:14];
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[header addSubview:self.statusLabel];

	[self buildActionsIn:header atY:(16 + side + 62)];

	if (self.userId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] statusForUser:self.userId completion:^(NSString *status){
			weakSelf.statusLabel.text = status;
		}];
	} else {
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
			if (count > 0)
				weakSelf.statusLabel.text = [NSString stringWithFormat:@"%ld members",
						(long)count];
		}];
	}

	self.tableView.tableHeaderView = header;
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

	NSNumber *fileId = self.userId
			? [[TGClient shared] photoFileIdForUserId:self.userId]
			: [[TGClient shared] photoFileIdForChat:self.chatId];
	if (!fileId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		[TGIcons loadImageAtPath:path into:weakSelf.avatarView];
	}];
}

/// The tiles under the name: a glyph over a word, on a soft rounded plate.
/// Only the ones that mean something here - a group has no one to call.
- (void)buildActionsIn:(UIView *)header atY:(CGFloat)y {
	NSMutableArray *tiles = [NSMutableArray array];
	if (self.userId){
		[tiles addObject:@[@"call",  @"call"]];
		[tiles addObject:@[@"video", @"video"]];
	}
	// Only when there is something to open: a tile that always says "stories"
	// and always answers "none" is worse than no tile.
	if (self.stories.count)
		[tiles addObject:@[@"more", @"stories"]];
	[tiles addObject:@[(self.muted ? @"unmute" : @"mute"),
					   (self.muted ? @"unmute" : @"mute")]];
	if (self.onSearchTapped)
		[tiles addObject:@[@"search", @"search"]];
	[tiles addObject:@[@"more", @"more"]];

	CGFloat width = header.bounds.size.width;
	CGFloat gap = 6, margin = 10;
	CGFloat tileW = (width - 2 * margin - gap * (tiles.count - 1)) / tiles.count;
	TGTheme *theme = [TGTheme shared];

	for (NSUInteger i = 0; i < tiles.count; i++){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.frame = CGRectMake(margin + i * (tileW + gap), y, tileW, kActionTile);
		tile.backgroundColor = theme.isDark
				? [UIColor colorWithWhite:1.0f alpha:0.08f]
				: [UIColor colorWithWhite:0.0f alpha:0.05f];
		tile.layer.cornerRadius = 8;
		tile.tag = i;
		[tile addTarget:self action:@selector(actionTileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[header addSubview:tile];

		UIImageView *glyph = [[UIImageView alloc] initWithFrame:
				CGRectMake((tileW - 22) / 2, 8, 22, 22)];
		glyph.image = [TGIcons menuGlyphNamed:tiles[i][0]];
		glyph.contentMode = UIViewContentModeScaleAspectFit;
		glyph.tintColor = [theme accentColour];
		[tile addSubview:glyph];

		UILabel *label = [[UILabel alloc] initWithFrame:
				CGRectMake(0, kActionTile - 18, tileW, 14)];
		label.text = tiles[i][1];
		label.font = [UIFont systemFontOfSize:10];
		label.textAlignment = NSTextAlignmentCenter;
		label.textColor = [theme accentColour];
		label.backgroundColor = [UIColor clearColor];
		[tile addSubview:label];
	}
	self.actionNames = tiles;
}

- (void)actionTileTapped:(UIButton *)tile {
	NSString *action = self.actionNames[tile.tag][1];

	if ([action isEqualToString:@"call"] || [action isEqualToString:@"video"]){
		[TGCallViewController presentForUserId:self.userId
										  name:self.name
									  outgoing:YES];
	} else if ([action hasSuffix:@"mute"]){
		self.muted = !self.muted;
		[[TGClient shared] setChat:self.chatId muted:self.muted];
		[self buildHeader];              // the tile says the opposite now
	} else if ([action isEqualToString:@"stories"]){
		[self.tableView scrollToRowAtIndexPath:
				[NSIndexPath indexPathForRow:0 inSection:kSectionStories]
					  atScrollPosition:UITableViewScrollPositionTop animated:YES];
	} else if ([action isEqualToString:@"search"]){
		if (self.onSearchTapped) self.onSearchTapped();
	} else {
		[self showMoreMenuFrom:tile];
	}
}

/// The "more" menu from the current client, minus what this app cannot do:
/// no secret chats, no gifts.
- (void)showMoreMenuFrom:(UIView *)tile {
	NSMutableArray *items = [NSMutableArray array];
	if (self.userId)
		[items addObject:@{@"title" : @"Share contact", @"icon" : @"forward"}];
	[items addObject:@{@"title" : @"Auto-delete messages", @"icon" : @"delete"}];
	[items addObject:@{@"title" : @"Clear history", @"icon" : @"delete"}];
	if (self.userId)
		[items addObject:@{@"title" : (self.blocked ? @"Unblock" : @"Block"),
						   @"icon" : @"privacy", @"destructive" : @YES}];

	CGPoint where = [tile convertPoint:CGPointMake(tile.bounds.size.width / 2,
												   tile.bounds.size.height)
								toView:self.navigationController.view];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:self.navigationController.view
				  onChoice:^(NSInteger index, NSString *title){
		[weakSelf runMoreAction:title];
	}];
}

- (void)runMoreAction:(NSString *)title {
	if ([title isEqualToString:@"Share contact"]){
		TGForwardPicker *picker = [[TGForwardPicker alloc] init];
		NSString *name = self.name;
		int64_t userId = self.userId;
		__weak typeof(self) weakSelf = self;
		picker.onPicked = ^(int64_t targetChatId){
			NSString *phone = weakSelf.phoneNumber;
			if (!phone.length){
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Share contact"
						message:@"This account does not show its phone number."
					   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[alert show];
				return;
			}
			[[TGClient shared] sendContactNamed:name phone:phone toChat:targetChatId];
		};
		(void)userId;
		[self.navigationController pushViewController:picker animated:YES];
		return;
	}

	if ([title isEqualToString:@"Auto-delete messages"]){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Delete messages after"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:nil
												 otherButtonTitles:@"Off", @"1 day",
															   @"1 week", @"1 month", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 70;
		[sheet showInView:self.view];
		return;
	}

	if ([title isEqualToString:@"Clear history"]){
		UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Clear history"
				message:@"Every message in this chat will be removed for you."
			   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Clear", nil];
		confirm.tag = 71;
		[confirm show];
		return;
	}

	[[TGClient shared] setUser:self.userId blocked:!self.blocked];
	self.blocked = !self.blocked;
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (sheet.tag != 70 || index == sheet.cancelButtonIndex)
		return;
	static const NSInteger seconds[4] = {0, 86400, 604800, 2592000};
	[[TGClient shared] setChat:self.chatId autoDeleteSeconds:seconds[index]];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (alert.tag == 71 && index != alert.cancelButtonIndex)
		[[TGClient shared] clearHistoryInChat:self.chatId];
}

- (void)loadDetails {
	self.muted = [[TGClient shared] isChatMuted:self.chatId];

	if (!self.userId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
			weakSelf.members = members;
			[weakSelf reloadTableDebounced];
		}];
		// A group has a description, a size and a link, none of which this
		// screen used to ask for.
		[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
			NSMutableArray *rows = [NSMutableArray array];
			if ([info[@"description"] length])
				[rows addObject:@[@"about", info[@"description"]]];
			if ([info[@"members"] integerValue] > 0)
				[rows addObject:@[@"members", [info[@"members"] stringValue]]];
			if ([info[@"admins"] integerValue] > 0)
				[rows addObject:@[@"admins", [info[@"admins"] stringValue]]];
			if ([info[@"inviteLink"] length])
				[rows addObject:@[@"invite link", info[@"inviteLink"]]];
			weakSelf.details = rows;
			[weakSelf reloadTableDebounced];
		}];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:self.userId completion:^(NSDictionary *user){
		if (!user) return;
		NSMutableArray *rows = [NSMutableArray array];
		NSString *phone = user[@"phone_number"];
		if (phone.length){
			[rows addObject:@[@"mobile", [@"+" stringByAppendingString:phone]]];
			weakSelf.phoneNumber = phone;
		}
		NSString *username = user[@"usernames"][@"active_usernames"][0];
		if (username.length)
			[rows addObject:@[@"username", [@"@" stringByAppendingString:username]]];
		if ([user[@"is_premium"] boolValue])
			[rows addObject:@[@"subscription", @"Telegram Premium"]];
		weakSelf.details = rows;
		[weakSelf reloadTableDebounced];

		// The bio, the birthday and how many groups you share live in the full
		// record, which this screen never asked for - so "about" was missing
		// from a profile that has one.
		[[TGClient shared] userProfile:weakSelf.userId completion:^(NSDictionary *info){
			NSMutableArray *more = [rows mutableCopy];
			if ([info[@"bio"] length])
				[more insertObject:@[@"about", info[@"bio"]]
						   atIndex:MIN((NSUInteger)2, more.count)];
			if ([info[@"birthday"] length])
				[more addObject:@[@"birthday", info[@"birthday"]]];
			if ([info[@"commonGroups"] integerValue] > 0)
				[more addObject:@[@"groups in common",
						[info[@"commonGroups"] stringValue]]];
			weakSelf.details = more;
			[weakSelf reloadTableDebounced];
		}];

		// updateUser does not always carry a photo; getUser does.
		NSNumber *photoId = user[@"profile_photo"][@"small"][@"id"];
		if (photoId)
			[[TGClient shared] downloadFile:photoId.integerValue completion:^(NSString *path){
				[TGIcons loadImageAtPath:path into:weakSelf.avatarView];
			}];
	}];
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(doReloadTable) object:nil];
	[self performSelector:@selector(doReloadTable) withObject:nil afterDelay:0.05];
}

- (void)doReloadTable {
	[self.tableView reloadData];
}

- (void)loadMedia {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] giftsForUser:self.userId completion:^(NSArray *gifts){
			weakSelf.gifts = gifts;
			[weakSelf reloadTableDebounced];
		}];
		[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL blocked){
			weakSelf.blocked = blocked;
			[weakSelf reloadTableDebounced];
		}];
	}

	// Stories sit on a profile the way shared media does, and this screen had
	// a "Posts" row standing in for them that always said there were none.
	[[TGClient shared] storiesForChat:self.chatId completion:^(NSArray *stories){
		BOOL gainedTile = stories.count && !weakSelf.stories.count;
		weakSelf.stories = stories;
		if (gainedTile)
			[weakSelf buildHeader];      // the tile row is one shorter without it
		[weakSelf reloadTableDebounced];
	}];

	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		weakSelf.photos = messages;
		[weakSelf reloadTableDebounced];
	}];
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterDocument"
						completion:^(NSArray *messages){
		weakSelf.files = messages;
		[weakSelf reloadTableDebounced];
	}];
}

#pragma mark - table

// details, stories, gifts, members, media
static const NSInteger kSectionDetails = 0;
static const NSInteger kSectionStories = 1;
static const NSInteger kSectionGifts   = 2;
static const NSInteger kSectionMembers = 3;
static const NSInteger kSectionMedia   = 4;

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kSectionDetails) return self.details.count;
	if (section == kSectionStories) return self.stories.count;
	if (section == kSectionGifts)   return self.gifts.count;
	if (section == kSectionMembers) return self.members.count;

	if (section == kSectionMedia) {
		switch (self.selectedMediaTab) {
			case 0: return self.photos.count ? 1 : 0; // Media strip
			case 1: return self.files.count; // Files
			case 2: return 0; // Voice (dummy)
			case 3: return 0; // Links (dummy)
		}
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == kSectionStories && self.stories.count)
		return [NSString stringWithFormat:@"%lu stories", (unsigned long)self.stories.count];
	if (section == kSectionGifts && self.gifts.count)
		return [NSString stringWithFormat:@"%lu gifts", (unsigned long)self.gifts.count];
	if (section == kSectionMembers && self.members.count)
		return [NSString stringWithFormat:@"%lu members", (unsigned long)self.members.count];
	return nil;
}

- (void)mediaTabChanged:(UISegmentedControl *)sender {
	self.selectedMediaTab = sender.selectedSegmentIndex;
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSectionMedia]
				  withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section == kSectionMedia) {
		UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
		header.backgroundColor = [UIColor clearColor];
		UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:@[@"Media", @"Files", @"Voice", @"Links"]];
		segments.frame = CGRectMake(10, 6, tableView.bounds.size.width - 20, 32);
		segments.selectedSegmentIndex = self.selectedMediaTab;
		segments.tintColor = [[TGTheme shared] accentColour];
		[segments addTarget:self action:@selector(mediaTabChanged:) forControlEvents:UIControlEventValueChanged];
		[header addSubview:segments];
		return header;
	}
	return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
		header.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section == kSectionMedia) return 44;
	return [super tableView:tableView heightForHeaderInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kSectionMedia && self.selectedMediaTab == 0) return 84;
	if (indexPath.section == kSectionStories) return 56;
	return indexPath.section == kSectionDetails ? 52 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kSectionMedia && self.selectedMediaTab == 0)
		return [self photoStripCell:tableView];

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = nil;
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = [UIFont systemFontOfSize:15];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	// The information card: what it is in small grey, the value itself under
	// it in the accent colour. Theirs reads that way round because the number
	// matters and the word "mobile" does not.
	if (indexPath.section == kSectionDetails){
		NSArray *pair = self.details[indexPath.row];
		cell.textLabel.text = pair[0];
		cell.textLabel.font = [UIFont systemFontOfSize:12];
		cell.textLabel.textColor = [[TGTheme shared] secondaryTextColour];
		cell.detailTextLabel.text = pair[1];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
		cell.detailTextLabel.textColor = [[TGTheme shared] accentColour];
		return cell;
	}

	// A story reads as its picture, its caption and when it went up - the
	// same three things the story list in a current client shows.
	if (indexPath.section == kSectionStories){
		NSDictionary *story = self.stories[indexPath.row];
		NSString *caption = [story[@"caption"] length] ? story[@"caption"]
				: ([story[@"isVideo"] boolValue] ? @"Video story" : @"Photo story");
		cell.textLabel.text = caption;
		cell.textLabel.font = [UIFont systemFontOfSize:15];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];

		static NSDateFormatter *when = nil;
		if (!when){
			when = [[NSDateFormatter alloc] init];
			when.dateStyle = NSDateFormatterShortStyle;
			when.timeStyle = NSDateFormatterShortStyle;
		}
		NSString *seen = [story[@"viewers"] integerValue] > 0
				? [NSString stringWithFormat:@" - %@ views", story[@"viewers"]] : @"";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@",
				[when stringFromDate:[NSDate dateWithTimeIntervalSince1970:
						[story[@"date"] doubleValue]]], seen];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		thumb.layer.cornerRadius = 6;
		cell.imageView.image = [TGIcons avatarWithInitials:@" " size:40
												  colourId:indexPath.row];
		NSNumber *fileId = story[@"photoId"];
		if ([fileId isKindOfClass:NSNumber.class]){
			__weak UITableView *weakTable = tableView;
			[[TGClient shared] downloadFile:fileId.integerValue
								 completion:^(NSString *path){
				if (!path.length) return;
				UIImage *image = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
										   fittingSize:CGSizeMake(40, 40) fill:YES
												 scale:[UIScreen mainScreen].scale];
				if (!image) return;
				cell.imageView.image = image;
				[cell setNeedsLayout];
				(void)weakTable;
			}];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == kSectionGifts){
		NSDictionary *gift = self.gifts[indexPath.row];
		cell.textLabel.text = gift[@"title"] ?: @"Gift";
		cell.textLabel.font = [UIFont systemFontOfSize:15];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ stars",
				gift[@"starCount"] ?: @(0)];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
		return cell;
	}

	if (indexPath.section == kSectionMembers){
		NSDictionary *member = self.members[indexPath.row];
		int64_t userId = [member[@"id"] longLongValue];
		NSString *name = [member[@"name"] length]
				? member[@"name"] : [[TGClient shared] nameForUserId:userId];
		cell.textLabel.text = name ?: @"";
		cell.detailTextLabel.text = nil;
		cell.imageView.image = [TGIcons avatarWithInitials:
				(name.length ? [name substringToIndex:1].uppercaseString : @"?")
													  size:32 colourId:userId];
	} else if (indexPath.section == kSectionMedia) {
		if (self.selectedMediaTab == 1) { // Files
			NSDictionary *m = self.files[indexPath.row];
			cell.textLabel.text = m[@"docName"] ?: @"File";
			cell.detailTextLabel.text = nil;
			cell.imageView.image = [TGIcons document];
		}
	}
	return cell;
}

/// A horizontal strip of thumbnails: a grid would mean a collection view,
/// which iOS 6 has but this screen does not need.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == kSectionStories){
		[self openStoryAtIndex:indexPath.row];
		return;
	}

	// The actions live in the tiles now; a row of the card copies its value,
	// which is the only thing there is to do with a phone number or a link.
	if (indexPath.section != kSectionDetails ||
		indexPath.row >= (NSInteger)self.details.count)
		return;
	NSString *value = self.details[indexPath.row][1];
	[UIPasteboard generalPasteboard].string = value;

	UILabel *toast = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, 120, 34)];
	toast.center = CGPointMake(self.view.bounds.size.width / 2,
							   self.view.bounds.size.height - 70);
	toast.text = @"Copied";
	toast.textAlignment = NSTextAlignmentCenter;
	toast.font = [UIFont systemFontOfSize:14];
	toast.textColor = [UIColor whiteColor];
	toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
	toast.layer.cornerRadius = 6;
	toast.clipsToBounds = YES;
	[self.view addSubview:toast];
	[UIView animateWithDuration:0.3 delay:1.0 options:0
					 animations:^{ toast.alpha = 0; }
					 completion:^(BOOL done){ [toast removeFromSuperview]; }];
}

/// A story opens full screen over the profile: the picture, the caption under
/// it, and a tap anywhere to close. A video story shows its poster frame -
/// playing one needs the file itself, which is a download this screen does not
/// start on a tap.
- (void)openStoryAtIndex:(NSInteger)index {
	if (index >= (NSInteger)self.stories.count)
		return;
	NSDictionary *story = self.stories[index];
	NSNumber *fileId = story[@"photoId"];
	if (![fileId isKindOfClass:NSNumber.class]){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Story"
				message:@"This story has nothing this app can show."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}

	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
	backdrop.backgroundColor = [UIColor blackColor];
	backdrop.alpha = 0;

	UIImageView *picture = [[UIImageView alloc] initWithFrame:
			CGRectInset(window.bounds, 0, 40)];
	picture.contentMode = UIViewContentModeScaleAspectFit;
	[backdrop addSubview:picture];

	NSString *caption = story[@"caption"];
	if (caption.length){
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				16, window.bounds.size.height - 76, window.bounds.size.width - 32, 60)];
		label.text = caption;
		label.numberOfLines = 3;
		label.font = [UIFont systemFontOfSize:14];
		label.textColor = [UIColor whiteColor];
		label.backgroundColor = [UIColor clearColor];
		[backdrop addSubview:label];
	}

	if ([story[@"isVideo"] boolValue]){
		UILabel *note = [[UILabel alloc] initWithFrame:
				CGRectMake(0, 24, window.bounds.size.width, 18)];
		note.text = @"Video story - showing the first frame";
		note.font = [UIFont systemFontOfSize:12];
		note.textAlignment = NSTextAlignmentCenter;
		note.textColor = [UIColor colorWithWhite:1 alpha:0.6f];
		note.backgroundColor = [UIColor clearColor];
		[backdrop addSubview:note];
	}

	backdrop.userInteractionEnabled = YES;
	[backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(closeStory:)]];
	[window addSubview:backdrop];
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 1; }];

	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		[TGIcons loadImageAtPath:path into:picture];
	}];
}

- (void)closeStory:(UITapGestureRecognizer *)tap {
	UIView *backdrop = tap.view;
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 0; }
					 completion:^(BOOL done){ [backdrop removeFromSuperview]; }];
}

- (UITableViewCell *)photoStripCell:(UITableView *)tableView {
	if (self.mediaStripCell) {
		return self.mediaStripCell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	
	UIScrollView *strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 2, tableView.bounds.size.width, 80)];
	strip.showsHorizontalScrollIndicator = NO;
	[cell.contentView addSubview:strip];

	strip.delegate = self;
	self.mediaStrip = strip;

	CGFloat side = 76, gap = 4, x = gap;
	NSInteger limit = MIN((NSInteger)self.photos.count, 20); // only show up to 20 photos
	for (NSInteger i = 0; i < limit; i++){
		NSDictionary *m = self.photos[i];
		NSNumber *fileId = m[@"photoId"];
		if (!fileId) continue;

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectMake(x, 2, side, side)];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		// The id rides on the view so the scroll handler can ask for it later
		// rather than the strip asking for all twenty the moment it is built.
		thumb.tag = fileId.integerValue;
		[strip addSubview:thumb];
		x += side + gap;
	}
	strip.contentSize = CGSizeMake(x, 80);
	self.mediaStripCell = cell;
	[self fetchVisibleThumbnails];
	return cell;
}

/// Twenty downloads at once saturate TDLib's single scheduler, and every one
/// of its progress updates is handled on the main thread - which is what made
/// the profile stutter for as long as the strip was loading. Only what is on
/// screen, plus one screen ahead, is asked for.
- (void)fetchVisibleThumbnails {
	UIScrollView *strip = self.mediaStrip;
	if (!strip)
		return;

	CGRect window = CGRectMake(strip.contentOffset.x - strip.bounds.size.width, 0,
							   strip.bounds.size.width * 3, strip.bounds.size.height);
	for (UIView *view in strip.subviews){
		if (![view isKindOfClass:UIImageView.class] || view.tag == 0)
			continue;
		if (!CGRectIntersectsRect(view.frame, window))
			continue;

		UIImageView *thumb = (UIImageView *)view;
		NSNumber *fileId = @(thumb.tag);
		if ([self.thumbnailsRequested containsObject:fileId])
			continue;
		[self.thumbnailsRequested addObject:fileId];

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			[TGIcons loadImageAtPath:path into:thumb];
		}];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.mediaStrip)
		[self fetchVisibleThumbnails];
}

@end

// vim:ft=objc
