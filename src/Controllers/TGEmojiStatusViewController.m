#import "TGEmojiStatusViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGStickerStore.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"

/// Six per row is what fits beside the gutter at the smallest supported
/// width, and it is the column count Telegram's own picker uses on a phone.
static const NSInteger kStatusColumns = 6;
static const CGFloat kStatusGridGap = TGMetricPadSmall;
static const CGFloat kStatusGridInset = TGMetricPadMedium;
static const CGFloat kStatusGridRow = TGMetricEmojiCell + TGMetricPad;

/// The status durations Telegram offers. Forever is 0, which is what TDLib
/// stores for a status with no end.
static const NSTimeInterval kStatusHour = 60 * 60;
static const NSTimeInterval kStatusTwoHours = 2 * kStatusHour;
static const NSTimeInterval kStatusEightHours = 8 * kStatusHour;
static const NSTimeInterval kStatusTwoDays = 48 * kStatusHour;

/// A still picture from a downloaded sticker: PNG and JPEG through UIKit,
/// WebP through the decoder the app carries.
static UIImage *TGStatusImageAtPath(NSString *path) {
	if (!path.length)
		return nil;
	UIImage *image = nil;
	if (![path.pathExtension.lowercaseString isEqualToString:@"webp"])
		image = [UIImage imageWithContentsOfFile:path];
	if (!image)
		image = [UIImage convertFromWebP:path compressedData:nil error:nil];
	return image;
}

#pragma mark - the tile grid

@interface TGEmojiStatusGridCell : UITableViewCell

/// Each entry: "emojiId", "emoji" (character), "image" (UIImage or NSNull),
/// "disallowed" (NSNumber BOOL). Tapping a tile calls the block with its
/// index; a disallowed tile never calls it.
@property (nonatomic, copy) void (^onTile)(NSInteger index);

- (void)setItems:(NSArray *)items;
- (void)tileTapped:(UIButton *)button;

@end

@implementation TGEmojiStatusGridCell {
	NSArray *_items;
	NSMutableArray *_tiles;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuse {
	self = [super initWithStyle:style reuseIdentifier:reuse];
	if (!self)
		return nil;
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.contentView.backgroundColor = [UIColor clearColor];
	self.backgroundColor = [UIColor clearColor];
	_tiles = [NSMutableArray array];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = self.contentView.bounds.size.width;
	CGFloat usable = width - TGDoubled(kStatusGridInset) -
			kStatusGridGap * (kStatusColumns - 1);
	CGFloat side = floorf(usable / kStatusColumns);
	CGFloat y = TGCenteredOrigin(self.contentView.bounds.size.height,
								 TGMetricEmojiCell);
	for (NSUInteger i = 0; i < _tiles.count; i++){
		UIButton *tile = _tiles[i];
		CGFloat x = kStatusGridInset + i * (side + kStatusGridGap);
		tile.frame = CGRectMake(x, y, side, TGMetricEmojiCell);
		tile.layer.cornerRadius = TGMetricCornerSmall;
	}
}

- (void)setItems:(NSArray *)items {
	_items = [items copy] ?: @[];
	while (_tiles.count < (NSUInteger)kStatusColumns){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.tag = (NSInteger)_tiles.count;
		tile.titleLabel.font = TGFontEmoji();
		tile.titleLabel.textAlignment = NSTextAlignmentCenter;
		tile.backgroundColor = [[TGTheme shared] fileTileColour];
		tile.titleLabel.adjustsFontSizeToFitWidth = YES;
		tile.titleLabel.minimumFontSize = TGFontSizeMicro;
		[tile addTarget:self action:@selector(tileTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:tile];
		[_tiles addObject:tile];
	}
	for (NSUInteger i = 0; i < _tiles.count; i++){
		UIButton *tile = _tiles[i];
		if (i >= _items.count){
			tile.hidden = YES;
			continue;
		}
		NSDictionary *item = _items[i];
		tile.hidden = NO;
		tile.enabled = ![item[@"disallowed"] boolValue];
		tile.alpha = tile.enabled ? TGAlphaOpaque : TGAlphaSecondary;
		id image = item[@"image"];
		if ([image isKindOfClass:UIImage.class]){
			[tile setImage:image forState:UIControlStateNormal];
			[tile setTitle:nil forState:UIControlStateNormal];
		} else {
			[tile setImage:nil forState:UIControlStateNormal];
			[tile setTitle:(item[@"emoji"] ?: @"🙂") forState:UIControlStateNormal];
		}
	}
	[self setNeedsLayout];
}

- (void)tileTapped:(UIButton *)button {
	NSInteger index = button.tag;
	if (index < 0 || index >= (NSInteger)_items.count)
		return;
	if ([_items[index][@"disallowed"] boolValue])
		return;
	if (self.onTile)
		self.onTile(index);
}

@end

#pragma mark - the picker

@interface TGEmojiStatusViewController ()
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSMutableDictionary *stickerByEmojiId;
@property (nonatomic, strong) NSMutableSet *imagesRequested;
@end

@implementation TGEmojiStatusViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.subjectTitle.length ? self.subjectTitle : @"Emoji Status";
	self.sections = @[];
	self.stickerByEmojiId = [NSMutableDictionary dictionary];
	self.imagesRequested = [NSMutableSet set];
	self.tableView.rowHeight = kStatusGridRow;
	[self applyTheme];

	if (self.target != TGEmojiStatusTargetChat)
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Clear" style:UIBarButtonItemStylePlain
					   target:self action:@selector(clearTapped)];

	[self loadLists];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TGThemeChangedNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - the lists

/// Three lists, in the order Telegram shows them: the themed strip first,
/// the default shelf under it, then what was worn lately. A chat has no
/// recent list, and it has one extra list of statuses it refuses.
- (void)loadLists {
	__weak typeof(self) weakSelf = self;
	if (self.target == TGEmojiStatusTargetChat){
		__block NSArray *themed = nil, *standard = nil, *refused = nil;
		__block NSInteger pending = 3;
		void (^done)(void) = ^{
			TGEmojiStatusViewController *me = weakSelf;
			if (!me || --pending > 0)
				return;
			[me buildSectionsWithThemed:themed default:standard
								recent:@[] refused:refused];
		};
		[[TGClient shared] themedChatEmojiStatusesWithCompletion:^(NSArray *ids){
			themed = ids; done();
		}];
		[[TGClient shared] defaultChatEmojiStatusesWithCompletion:^(NSArray *ids){
			standard = ids; done();
		}];
		[[TGClient shared] disallowedChatEmojiStatusesWithCompletion:^(NSArray *ids){
			refused = ids; done();
		}];
		return;
	}

	__block NSArray *themed = nil, *standard = nil, *recent = nil;
	__block NSInteger pending = 3;
	void (^done)(void) = ^{
		TGEmojiStatusViewController *me = weakSelf;
		if (!me || --pending > 0)
			return;
		NSMutableArray *recentIds = [NSMutableArray array];
		for (NSDictionary *row in recent)
			if ([row[@"emojiId"] longLongValue] > 0)
				[recentIds addObject:row[@"emojiId"]];
		[me buildSectionsWithThemed:themed default:standard
							recent:recentIds refused:@[]];
	};
	[[TGClient shared] themedEmojiStatusesWithCompletion:^(NSArray *ids){
		themed = ids; done();
	}];
	[[TGClient shared] defaultEmojiStatusesWithCompletion:^(NSArray *ids){
		standard = ids; done();
	}];
	[[TGClient shared] recentEmojiStatusesWithCompletion:^(NSArray *rows){
		recent = rows; done();
	}];
}

- (NSArray *)uniqueIds:(NSArray *)ids excluding:(NSSet *)excluded {
	NSMutableArray *out = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (id raw in ids ?: @[]){
		NSNumber *identifier = @([raw longLongValue]);
		if ([identifier longLongValue] <= 0)
			continue;
		if ([seen containsObject:identifier] || [excluded containsObject:identifier])
			continue;
		[seen addObject:identifier];
		[out addObject:identifier];
	}
	return out;
}

- (void)buildSectionsWithThemed:(NSArray *)themed
						default:(NSArray *)standard
						 recent:(NSArray *)recent
						refused:(NSArray *)refused {
	NSMutableSet *refusedSet = [NSMutableSet set];
	for (NSNumber *identifier in refused ?: @[])
		[refusedSet addObject:identifier];

	NSMutableArray *sections = [NSMutableArray array];
	NSArray *themedIds = [self uniqueIds:themed excluding:nil];
	NSMutableSet *used = [NSMutableSet setWithArray:themedIds];
	NSArray *defaultIds = [self uniqueIds:standard excluding:used];
	[used addObjectsFromArray:defaultIds];
	NSArray *recentIds = [self uniqueIds:recent excluding:used];
	[used addObjectsFromArray:recentIds];

	if (themedIds.count)
		[sections addObject:@{@"header" : @"Themed",
							  @"ids" : themedIds}];
	if (defaultIds.count)
		[sections addObject:@{@"header" : @"Default",
							  @"ids" : defaultIds}];
	if (recentIds.count)
		[sections addObject:@{@"header" : @"Recently Used",
							  @"ids" : recentIds}];
	if (refusedSet.count){
		NSArray *refusedIds = [self uniqueIds:refused excluding:nil];
		[sections addObject:@{@"header" : @"Not Allowed in This Chat",
							  @"ids" : refusedIds}];
	}
	self.sections = sections;

	NSMutableArray *all = [NSMutableArray array];
	for (NSDictionary *section in sections)
		[all addObjectsFromArray:section[@"ids"]];
	[self fetchStickersForIds:all];
	[self.tableView reloadData];
}

/// Custom emoji ids are not characters: the character and the picture both
/// come from getCustomEmojiStickers. One request covers every id on screen.
- (void)fetchStickersForIds:(NSArray *)ids {
	if (!ids.count)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] customEmojiStickersForIds:ids
									  completion:^(NSArray *stickers){
		TGEmojiStatusViewController *me = weakSelf;
		if (!me)
			return;
		for (NSDictionary *sticker in stickers){
			NSNumber *identifier = sticker[@"customEmojiId"];
			if (![identifier isKindOfClass:NSNumber.class])
				continue;
			me.stickerByEmojiId[identifier] = sticker;
		}
		[me downloadThumbs];
		[me.tableView reloadData];
	}];
}

- (void)downloadThumbs {
	for (NSNumber *identifier in self.stickerByEmojiId){
		if ([self.imagesRequested containsObject:identifier])
			continue;
		NSDictionary *sticker = self.stickerByEmojiId[identifier];
		NSNumber *fileId = sticker[@"thumbId"];
		if ([fileId longLongValue] <= 0)
			fileId = sticker[@"fileId"];
		if ([fileId longLongValue] <= 0)
			continue;
		[self.imagesRequested addObject:identifier];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue
							 completion:^(NSString *path){
			TGEmojiStatusViewController *me = weakSelf;
			if (!me || !path.length)
				return;
			UIImage *image = TGStatusImageAtPath(path);
			if (!image)
				return;
			NSMutableDictionary *sticker = [me.stickerByEmojiId[identifier] mutableCopy];
			sticker[@"image"] = image;
			me.stickerByEmojiId[identifier] = sticker;
			[me.tableView reloadData];
		}];
	}
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	NSInteger extra = (self.target != TGEmojiStatusTargetChat) ? 1 : 0;
	return self.sections.count + extra;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section < (NSInteger)self.sections.count){
		NSInteger count = [(NSArray *)self.sections[section][@"ids"] count];
		return (count + kStatusColumns - 1) / kStatusColumns;
	}
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section < (NSInteger)self.sections.count)
		return self.sections[section][@"header"];
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == (NSInteger)self.sections.count &&
			self.target != TGEmojiStatusTargetChat)
		return @"A status is worn beside your name until it expires. "
			   @"The lists come from Telegram; a non-Premium account is refused "
			   @"with the server's own sentence.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"clear"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"clear"];
		[[TGTheme shared] styleCell:cell];
		cell.textLabel.text = @"Clear Recently Used";
		cell.textLabel.font = TGFontBody();
		cell.textLabel.textColor = [[TGTheme shared] accentColour];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	static NSString *reuse = @"grid";
	TGEmojiStatusGridCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGEmojiStatusGridCell alloc] initWithStyle:UITableViewCellStyleDefault
											 reuseIdentifier:reuse];
	NSArray *ids = self.sections[indexPath.section][@"ids"];
	NSInteger start = indexPath.row * kStatusColumns;
	NSInteger end = MIN(start + kStatusColumns, (NSInteger)ids.count);
	NSMutableArray *items = [NSMutableArray array];
	BOOL refusedSection = [self.sections[indexPath.section][@"header"]
			isEqualToString:@"Not Allowed in This Chat"];
	for (NSInteger i = start; i < end; i++){
		NSNumber *identifier = ids[i];
		NSDictionary *sticker = self.stickerByEmojiId[identifier] ?: @{};
		[items addObject:@{
			@"emojiId" : identifier,
			@"emoji" : sticker[@"emoji"] ?: @"🙂",
			@"image" : sticker[@"image"] ?: [NSNull null],
			@"disallowed" : @(refusedSection),
		}];
	}
	__weak typeof(self) weakSelf = self;
	cell.onTile = ^(NSInteger index){
		NSInteger absolute = start + index;
		if (absolute < (NSInteger)ids.count)
			[weakSelf chooseEmojiId:[ids[absolute] longLongValue]];
	};
	[cell setItems:items];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section < (NSInteger)self.sections.count)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] clearRecentEmojiStatusesWithCompletion:^(BOOL ok, NSString *error){
		[weakSelf showResult:ok error:error title:@"Recently Used"];
		if (ok)
			[weakSelf loadLists];
	}];
}

#pragma mark - setting a status

- (void)chooseEmojiId:(int64_t)emojiId {
	__weak typeof(self) weakSelf = self;
	NSArray *titles = @[@"1 hour", @"2 hours", @"8 hours", @"2 days", @"Forever"];
	NSArray *durations = @[@(kStatusHour), @(kStatusTwoHours),
						   @(kStatusEightHours), @(kStatusTwoDays), @(0)];
	[TGAlertSheet showChoices:titles
						title:@"Keep This Status For"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index >= (NSInteger)durations.count)
			return;
		NSTimeInterval seconds = [durations[(NSUInteger)index] doubleValue];
		int64_t expiration = seconds > 0
				? (int64_t)([[NSDate date] timeIntervalSince1970] + seconds) : 0;
		[weakSelf applyEmojiId:emojiId expirationDate:expiration];
	}];
}

- (void)applyEmojiId:(int64_t)emojiId expirationDate:(int64_t)expiration {
	__weak typeof(self) weakSelf = self;
	NSString *title = self.subjectTitle ?: @"Emoji Status";
	if (self.target == TGEmojiStatusTargetChat){
		[[TGClient shared] setChatEmojiStatus:emojiId expirationDate:expiration
									  inChat:self.chatId
								  completion:^(BOOL ok, NSString *error){
			[weakSelf showResult:ok error:error title:title];
		}];
		return;
	}
	if (self.target == TGEmojiStatusTargetUser){
		[[TGClient shared] setUserEmojiStatus:emojiId expirationDate:expiration
									  forUser:self.userId
								   completion:^(BOOL ok, NSString *error){
			[weakSelf showResult:ok error:error title:title];
		}];
		return;
	}
	[[TGClient shared] setEmojiStatus:emojiId expirationDate:expiration
						  completion:^(BOOL ok, NSString *error){
		[weakSelf showResult:ok error:error title:title];
	}];
}

- (void)clearTapped {
	__weak typeof(self) weakSelf = self;
	if (self.target == TGEmojiStatusTargetUser){
		[[TGClient shared] setUserEmojiStatus:0 expirationDate:0
									  forUser:self.userId
								   completion:^(BOOL ok, NSString *error){
			[weakSelf showResult:ok error:error title:@"Emoji Status"];
		}];
		return;
	}
	[[TGClient shared] setEmojiStatus:0 expirationDate:0
						  completion:^(BOOL ok, NSString *error){
		[weakSelf showResult:ok error:error title:@"Emoji Status"];
	}];
}

- (void)showResult:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	[TGAlertSheet showMessage:(ok ? @"The emoji status is set."
								   : (error ?: @"Telegram refused that status."))
						title:title inView:self.view];
}

@end
