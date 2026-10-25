#import "TGProfileViewControllerInternal.h"

/// Flattened messages carry a unix date, not a formatted stamp; the shared
/// lists want a short one beside each row.
static NSString *TGProfileShortDate(NSNumber *date) {
	if (![date isKindOfClass:NSNumber.class] || !date.doubleValue)
		return nil;
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	}
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date.doubleValue]];
}

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

	// Saved Messages is the chat with yourself, so asking for its presence
	// answers your own - and a bookmark folder reading "online" is nonsense.
	if (self.chatId && self.chatId == [[TGClient shared] savedMessagesChatId]){
		self.statusLabel.text = nil;
	} else if (self.userId){
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
	[[TGClient shared] downloadFile:fileId.integerValue
						   priority:TGDownloadPriorityAvatar
						 completion:^(NSString *path){
		[TGIcons loadImageAtPath:path into:weakSelf.avatarView];
	}];
}

- (void)loadDetails {
	self.muted = [[TGClient shared] isChatMuted:self.chatId];

	if (!self.userId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
			weakSelf.members = members;
			[weakSelf reloadTableDebounced];
		}];
		// Group details: description, member count, invite link.
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
			[[TGClient shared] downloadFile:photoId.integerValue
								   priority:TGDownloadPriorityAvatar
								 completion:^(NSString *path){
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

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kSectionDetails) return self.details.count;
	// Stories and Gifts live in the bar above the shared section now, so the
	// standalone sections would show the same rows a second time.
	if (section == kSectionStories) return 0;
	if (section == kSectionGifts)   return 0;
	if (section == kSectionMembers) return self.members.count;

	if (section == kSectionMedia) {
		// The photo strip is one row holding a scroller; every other category
		// is a plain list.
		// Media and Stories are both strips of pictures: one row holding a
		// scroller. The rest are plain lists.
		if ([self selectedTabIsStrip] || [self selectedTabIsGrid])
			return [self selectedMediaRows].count ? 1 : 0;
		return [self selectedMediaRows].count;
	}

	if (section == kSectionLogout){
		// Show "Log out" only when this is the signed-in user's own profile.
		int64_t myId = [[TGClient shared].me[@"id"] longLongValue];
		return (self.userId && self.userId == myId) ? 1 : 0;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == kSectionMembers && self.members.count)
		return [NSString stringWithFormat:@"%lu members", (unsigned long)self.members.count];
	return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section == kSectionMedia) {
		UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 38)];
		header.backgroundColor = [UIColor clearColor];
		NSArray *tabs = [self currentMediaTabs];
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *tab in tabs)
			[titles addObject:tab[@"title"]];
		UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:titles];
		segments.frame = CGRectMake(10, 3, tableView.bounds.size.width - 20, 30);
		segments.selectedSegmentIndex = MIN(MAX(0, self.selectedMediaTab),
											(NSInteger)titles.count - 1);
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
	if (section == kSectionMedia) return 38;
	// Stories and Gifts are categories in the bar now and have no rows left.
	// A grouped table still pads an empty section at both ends, and two of
	// them in a row opened a gap the size of a screen above the bar.
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return CGFLOAT_MIN;
	return [super tableView:tableView heightForHeaderInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return CGFLOAT_MIN;
	if (section == kSectionMedia)
		return CGFLOAT_MIN;
	return [super tableView:tableView heightForFooterInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kSectionMedia && [self selectedTabIsStrip])
		return 84;
	if (indexPath.section == kSectionMedia && [self selectedTabIsGrid])
		return [self storyGridHeight];
	if (indexPath.section == kSectionStories) return 56;
	return indexPath.section == kSectionDetails ? 52 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kSectionMedia && [self selectedTabIsStrip])
		return [self photoStripCell:tableView];
	if (indexPath.section == kSectionMedia && [self selectedTabIsGrid])
		return [self storyGridCell:tableView];

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
		NSNumber *fileId = story[@"thumbPhotoId"] ?: story[@"photoId"];
		if ([fileId isKindOfClass:NSNumber.class]){
			__weak UITableView *weakTable = tableView;
			[[TGClient shared] downloadFile:fileId.integerValue
								   priority:TGDownloadPriorityOnScreen
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

	if (indexPath.section == kSectionLogout){
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.textLabel.text = @"Log out";
		cell.textLabel.textColor = [UIColor colorWithRed:1.0f green:0.23f blue:0.18f alpha:1.0f];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		cell.detailTextLabel.text = nil;
		cell.imageView.image = nil;
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
		NSString *kind = [self selectedMediaKind];
		NSArray *rows = [self selectedMediaRows];
		if (indexPath.row < (NSInteger)rows.count) {
			NSDictionary *m = rows[indexPath.row];
			if ([kind isEqualToString:@"files"]) {
				cell.textLabel.text = m[@"docName"] ?: @"File";
				cell.detailTextLabel.text = nil;
				cell.imageView.image = [TGIcons document];
			} else if ([kind isEqualToString:@"voice"]) {
				cell.textLabel.text = @"Voice message";
				cell.detailTextLabel.text = TGProfileShortDate(m[@"date"]);
				cell.imageView.image = [TGIcons microphone];
			} else if ([kind isEqualToString:@"links"]) {
				// The link itself is the title; the message it came in is the
				// detail, which is what makes a list of them readable.
				cell.textLabel.text = m[@"link"] ?: m[@"text"] ?: @"Link";
				cell.textLabel.numberOfLines = 2;
				cell.detailTextLabel.text = TGProfileShortDate(m[@"date"]);
				cell.imageView.image = [TGIcons glyphNamed:@"copy"
													colour:[[TGTheme shared] secondaryTextColour]
													  side:24];
			} else if ([kind isEqualToString:@"gifts"]) {
				cell.textLabel.text = m[@"title"] ?: @"Gift";
				cell.detailTextLabel.text = m[@"subtitle"];
			}
		}
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == kSectionLogout){
		UIAlertView *alert = [[UIAlertView alloc]
				initWithTitle:@"Log out"
				      message:@"Are you sure you want to log out?"
				     delegate:self
			cancelButtonTitle:@"Cancel"
			otherButtonTitles:@"Log out", nil];
		alert.tag = 72;
		[alert show];
		return;
	}

	if (indexPath.section == kSectionMedia)
		return;

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
	toast.textColor = [[TGTheme shared] hudTextColour];
	toast.backgroundColor = [[TGTheme shared] hudBackgroundColour];
	toast.layer.cornerRadius = 6;
	toast.clipsToBounds = YES;
	[self.view addSubview:toast];
	[UIView animateWithDuration:0.3 delay:1.0 options:0
					 animations:^{ toast.alpha = 0; }
					 completion:^(BOOL done){ [toast removeFromSuperview]; }];
}

@end
