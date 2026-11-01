#import "TGCloseFriendsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

@interface TGCloseFriendCell : UITableViewCell
- (void)applyContact:(NSDictionary *)contact
			  avatar:(UIImage *)avatar
			selected:(BOOL)selected
			   theme:(TGTheme *)theme;
@end

@implementation TGCloseFriendCell {
	UIImageView *_face;
	UILabel *_name;
	UILabel *_detail;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;
	_face = [[UIImageView alloc] initWithFrame:CGRectZero];
	_face.contentMode = UIViewContentModeScaleAspectFill;
	_face.layer.cornerRadius = TGHalf(TGMetricListAvatar);
	_face.clipsToBounds = YES;
	[self.contentView addSubview:_face];

	_name = [[UILabel alloc] initWithFrame:CGRectZero];
	_name.font = TGFontRow();
	_name.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:_name];

	_detail = [[UILabel alloc] initWithFrame:CGRectZero];
	_detail.font = TGFontCaption();
	_detail.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:_detail];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat h = self.contentView.bounds.size.height;
	CGFloat x = TGMetricGutter;
	_face.frame = CGRectMake(x, TGCenteredOrigin(h, TGMetricListAvatar),
			TGMetricListAvatar, TGMetricListAvatar);
	CGFloat textX = x + TGMetricListAvatar + TGMetricPadMedium;
	CGFloat width = MAX(0, self.contentView.bounds.size.width - textX - TGMetricPadLarge);
	_name.frame = CGRectMake(textX, TGMetricPadSmall, width, TGMetricLineRow);
	_detail.frame = CGRectMake(textX, TGMetricPadSmall + TGMetricLineRow,
			width, TGMetricLineCaption);
}

- (void)applyContact:(NSDictionary *)contact
			  avatar:(UIImage *)avatar
			selected:(BOOL)selected
			   theme:(TGTheme *)theme {
	NSString *first = contact[@"first_name"] ?: @"";
	NSString *last = contact[@"last_name"] ?: @"";
	NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (!name.length)
		name = contact[@"username"] ?: @"Contact";
	_face.image = avatar;
	_name.text = name;
	_name.textColor = [theme primaryTextColour];
	NSString *username = contact[@"username"];
	_detail.text = username.length ? [@"@" stringByAppendingString:username]
								   : (contact[@"phone"] ?: @"");
	_detail.textColor = [theme secondaryTextColour];

	self.accessoryView = [[UIImageView alloc] initWithImage:
			[TGIcons selectionCheckboxSelected:selected]];
	self.backgroundColor = [theme cardBackgroundColour];
	self.contentView.backgroundColor = [theme cardBackgroundColour];
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	[self setNeedsLayout];
}

@end

@interface TGCloseFriendsViewController ()
@property (nonatomic, strong) NSArray *contacts;
@property (nonatomic, strong) NSMutableSet *selected;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong) NSMutableDictionary *photos;
@property (nonatomic, strong) NSMutableSet *photosRequested;
@end

@implementation TGCloseFriendsViewController

- (instancetype)init {
	if ((self = [super initWithStyle:UITableViewStyleGrouped])){
		_selected = [NSMutableSet set];
		_contacts = @[];
		_photos = [NSMutableDictionary dictionary];
		_photosRequested = [NSMutableSet set];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Close Friends";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[TGIcons flush];
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];

	[[TGClient shared] closeFriendsWithCompletion:^(NSArray *ids){
		TGCloseFriendsViewController *me = weakSelf;
		if (!me)
			return;
		[me.selected setSet:[NSSet setWithArray:ids]];
		[[TGClient shared] contactsWithCompletion:^(NSArray *contacts){
			TGCloseFriendsViewController *again = weakSelf;
			if (!again)
				return;
			again.contacts = contacts;
			again.loaded = YES;
			[again.tableView reloadData];
			[again loadAvatars];
		}];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)loadAvatars {
	for (NSDictionary *contact in self.contacts)
		[self requestAvatarForContact:contact];
}

- (void)requestAvatarForContact:(NSDictionary *)contact {
	NSNumber *fileId = contact[@"photoFileId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0)
		return;
	if (self.photos[fileId] || [self.photosRequested containsObject:fileId])
		return;
	[self.photosRequested addObject:fileId];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *photo = [TGIcons decodedImageAtPath:path
					fittingSize:CGSizeMake(TGMetricListAvatar, TGMetricListAvatar)
						   fill:YES
						  scale:[UIScreen mainScreen].scale];
			if (photo)
				photo = [TGIcons roundedImage:photo
						size:CGSizeMake(TGMetricListAvatar, TGMetricListAvatar)
					  radius:TGHalf(TGMetricListAvatar)
					 corners:UIRectCornerAllCorners];
			if (!photo)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				TGCloseFriendsViewController *me = weakSelf;
				if (!me)
					return;
				me.photos[fileId] = photo;
				[me.tableView reloadData];
			});
		});
	}];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (!self.loaded)
		return 1;
	return self.contacts.count ? (NSInteger)self.contacts.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return @"Close Friends";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (!self.loaded)
		return @"Reading the list from Telegram…";
	if (!self.contacts.count)
		return @"No contacts to pick from. Add someone in Contacts first.";
	return [NSString stringWithFormat:
			@"%lu selected · every change is sent to Telegram at once.",
			(unsigned long)self.selected.count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return TGMetricRow - TGMetricPadLarge;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *sectionHeader = (UITableViewHeaderFooterView *)view;
		sectionHeader.textLabel.font = TGFontMetaStrong();
		sectionHeader.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TGTheme *theme = [TGTheme shared];

	if (!self.loaded || !self.contacts.count){
		static NSString *empty = @"TGCloseFriendEmpty";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:empty];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:empty];
		cell.textLabel.text = self.loaded ? @"No contacts to pick from." : @"Loading…";
		cell.textLabel.font = TGFontBody();
		cell.textLabel.textColor = [theme secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessoryView = nil;
		cell.backgroundColor = [theme cardBackgroundColour];
		return cell;
	}

	static NSString *reuse = @"TGCloseFriend";
	TGCloseFriendCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGCloseFriendCell alloc] initWithStyle:UITableViewCellStyleDefault
									   reuseIdentifier:reuse];

	NSDictionary *contact = self.contacts[(NSUInteger)indexPath.row];
	NSNumber *userId = contact[@"id"];
	NSNumber *fileId = contact[@"photoFileId"];
	UIImage *photo = [fileId isKindOfClass:NSNumber.class] ? self.photos[fileId] : nil;
	if (!photo){
		NSString *name = [NSString stringWithFormat:@"%@ %@",
				contact[@"first_name"] ?: @"", contact[@"last_name"] ?: @""];
		NSString *initials = [TGIcons initialsForTitle:name];
		photo = [TGIcons avatarWithInitials:initials.length ? initials : @"?"
				size:TGMetricListAvatar
				colourId:[userId longLongValue]];
	}
	[cell applyContact:contact
				avatar:photo
			  selected:[self.selected containsObject:userId]
				 theme:theme];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.loaded || indexPath.row >= (NSInteger)self.contacts.count)
		return;

	NSDictionary *contact = self.contacts[(NSUInteger)indexPath.row];
	NSNumber *userId = contact[@"id"];
	if (![userId isKindOfClass:NSNumber.class])
		return;

	NSMutableSet *before = [self.selected copy];
	if ([self.selected containsObject:userId])
		[self.selected removeObject:userId];
	else
		[self.selected addObject:userId];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setCloseFriends:self.selected.allObjects
							completion:^(BOOL ok, NSString *error){
		TGCloseFriendsViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			// The check goes back where it was; the server's sentence is why.
			[me.selected setSet:before];
			[me.tableView reloadData];
			[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
								title:@"Close Friends" inView:me.view];
			return;
		}
		if (me.onCountChanged)
			me.onCountChanged((NSInteger)me.selected.count);
		[me.tableView reloadData];
	}];
}

@end
