//
// TGProfileAppearanceViewController.m — the account's name colour and profile
// colour, drawn from the updateAccentColors palette as a grid of swatches
// rather than a word list. Two tabs, one live preview of the signed-in user,
// and an Apply step so a colour is never written before the user confirms it.
//
#import "TGProfileAppearanceViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import "TGAlertSheet.h"

/// Telegram's swatch is 44 pt on a phone, per the parity spec; the gap and
/// gutter come from the spacing scale.
static const CGFloat kSwatchSide = 44.0f;
static const CGFloat kSwatchGap = TGMetricPadSmall;
static const CGFloat kSwatchInset = TGMetricPadMedium;
static const NSInteger kSwatchColumns = 5;
static const CGFloat kSwatchRow = kSwatchSide + TGMetricPadMedium;

static const NSInteger kTabProfile = 0;
static const NSInteger kTabName = 1;

/// One swatch: the account colour filled into a rounded tile, with a selection
/// ring and a baked checkmark over it. The ring is the theme's accent, not the
/// swatch colour, so a selection is visible on any palette entry.
static UIImage *TGAppearanceSwatch(UIColor *colour, BOOL selected) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(kSwatchSide, kSwatchSide), NO, 0);
	CGRect rect = CGRectMake(0, 0, kSwatchSide, kSwatchSide);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
													cornerRadius:TGMetricCornerControl];
	[colour setFill];
	[path fill];
	if (selected) {
		UIBezierPath *ring = [UIBezierPath bezierPathWithRoundedRect:
				CGRectInset(rect, TGMetricBorderWidth, TGMetricBorderWidth)
				cornerRadius:TGMetricCornerControl];
		ring.lineWidth = TGMetricBorderThick;
		[[[TGTheme shared] accentColour] setStroke];
		[ring stroke];
		UIImage *tick = [TGIcons ticksColour:[[TGTheme shared] onAccentColour] read:NO];
		[tick drawInRect:CGRectMake(TGCenteredOrigin(kSwatchSide, TGMetricTicksWidth),
				TGCenteredOrigin(kSwatchSide, TGMetricTicksHeight),
				TGMetricTicksWidth, TGMetricTicksHeight)];
	}
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

/// The avatar with a 2 pt ring in the profile colour, baked so the preview row
/// never needs a masked layer over a scrolling table.
static UIImage *TGAppearanceAvatar(UIImage *avatar, UIColor *ring) {
	UIGraphicsBeginImageContextWithOptions(avatar.size, NO, 0);
	CGRect rect = CGRectMake(0, 0, avatar.size.width, avatar.size.height);
	[avatar drawInRect:rect];
	UIBezierPath *ringPath = [UIBezierPath bezierPathWithOvalInRect:
			CGRectInset(rect, TGMetricBorderWidth, TGMetricBorderWidth)];
	ringPath.lineWidth = TGMetricBorderThick;
	[ring setStroke];
	[ringPath stroke];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

#pragma mark - the swatch grid

@interface TGProfileSwatchCell : UITableViewCell
@property (nonatomic, copy) void (^onSwatch)(NSInteger index);
- (void)setSwatches:(NSArray *)swatches;   // array of UIImage
- (void)swatchTapped:(UIButton *)button;
@end

@implementation TGProfileSwatchCell {
	NSArray *_swatches;
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
	CGFloat usable = width - TGDoubled(kSwatchInset) -
			kSwatchGap * (kSwatchColumns - 1);
	CGFloat side = floorf(usable / kSwatchColumns);
	for (NSUInteger i = 0; i < _tiles.count; i++){
		UIButton *tile = _tiles[i];
		CGFloat x = kSwatchInset + i * (side + kSwatchGap);
		tile.frame = CGRectMake(x, TGCenteredOrigin(self.contentView.bounds.size.height, kSwatchSide),
				side, kSwatchSide);
	}
}

- (void)setSwatches:(NSArray *)swatches {
	_swatches = [swatches copy] ?: @[];
	while (_tiles.count < (NSUInteger)kSwatchColumns){
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.tag = (NSInteger)_tiles.count;
		[tile addTarget:self action:@selector(swatchTapped:)
	   forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:tile];
		[_tiles addObject:tile];
	}
	for (NSUInteger i = 0; i < _tiles.count; i++){
		UIButton *tile = _tiles[i];
		if (i >= _swatches.count){
			tile.hidden = YES;
			continue;
		}
		tile.hidden = NO;
		[tile setImage:_swatches[i] forState:UIControlStateNormal];
	}
	[self setNeedsLayout];
}

- (void)swatchTapped:(UIButton *)button {
	NSInteger index = button.tag;
	if (index < 0 || index >= (NSInteger)_swatches.count)
		return;
	if (self.onSwatch)
		self.onSwatch(index);
}

@end

#pragma mark - the screen

@interface TGProfileAppearanceViewController ()
@property (nonatomic, assign) NSInteger tab;
@property (nonatomic, assign) NSInteger pendingAccentId;
@property (nonatomic, assign) NSInteger pendingProfileId;
@property (nonatomic, assign) int64_t backgroundEmojiId;
@property (nonatomic, assign) int64_t profileBackgroundEmojiId;
@property (nonatomic, assign) BOOL accentChanged;
@property (nonatomic, assign) BOOL profileChanged;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong) NSArray *accentIds;
@property (nonatomic, strong) NSArray *profileIds;
@property (nonatomic, strong) NSCache *swatchCache;
@end

@implementation TGProfileAppearanceViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (instancetype)initWithProfileTab:(BOOL)profileTab {
	self = [self init];
	if (self)
		_tab = profileTab ? kTabProfile : kTabName;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"Your Color";
	self.swatchCache = [[NSCache alloc] init];
	[self applyTheme];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Apply" style:UIBarButtonItemStyleDone
				   target:self action:@selector(applyTapped)];

	UISegmentedControl *tabs = [[UISegmentedControl alloc]
			initWithItems:@[@"Profile", @"Name"]];
	tabs.selectedSegmentIndex = self.tab;
	[tabs addTarget:self action:@selector(tabChanged:)
   forControlEvents:UIControlEventValueChanged];
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, self.tableView.bounds.size.width,
					   TGMetricSegmentedHeight + TGDoubled(TGMetricPadMedium))];
	header.backgroundColor = [UIColor clearColor];
	tabs.frame = CGRectMake(TGMetricGutter, TGMetricPadMedium,
			header.bounds.size.width - TGDoubled(TGMetricGutter),
			TGMetricSegmentedHeight);
	[header addSubview:tabs];
	self.tableView.tableHeaderView = header;

	[self loadColours];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadColours)
			name:TGAccentColorsChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme)
			name:TGThemeChangedNotification object:nil];
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

- (void)tabChanged:(UISegmentedControl *)tabs {
	self.tab = tabs.selectedSegmentIndex;
	[self.tableView reloadData];
}

/// The ids come from updateAccentColors (cached on the client), the two chosen
/// ids and the two background-emoji ids from getMe. The emoji ids are what a
/// colour write has to hand back so picking a colour never erases the pattern.
- (void)loadColours {
	self.accentIds = [[TGClient shared] availableAccentColorIds];
	self.profileIds = [[TGClient shared] availableProfileAccentColorIds];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] myAccentColoursWithCompletion:
			^(NSInteger accent, NSInteger profile, int64_t emoji, int64_t profileEmoji){
		TGProfileAppearanceViewController *me = weakSelf;
		if (!me || me.loaded)
			return;
		me.loaded = YES;
		me.pendingAccentId = accent;
		me.pendingProfileId = profile;
		me.backgroundEmojiId = emoji;
		me.profileBackgroundEmojiId = profileEmoji;
		[me.tableView reloadData];
	}];
}

- (NSInteger)activeId {
	return self.tab == kTabProfile ? self.pendingProfileId : self.pendingAccentId;
}

- (NSArray *)activeIds {
	return self.tab == kTabProfile ? self.profileIds : self.accentIds;
}

- (UIColor *)colourForActiveId:(NSInteger)colourId {
	UIColor *colour = [[TGClient shared] accentColourForId:colourId
												  profile:(self.tab == kTabProfile)];
	return colour ?: [[TGTheme shared] fileTileColour];
}

/// Baked once per id per selection state; a palette is at most a few dozen
/// entries, so the cache stays tiny against the 16 MB ceiling.
- (UIImage *)swatchImageForId:(NSInteger)colourId selected:(BOOL)selected {
	NSString *key = [NSString stringWithFormat:@"%ld-%d-%ld", (long)colourId,
			selected, (long)self.tab];
	UIImage *cached = [self.swatchCache objectForKey:key];
	if (cached)
		return cached;
	UIImage *image = TGAppearanceSwatch([self colourForActiveId:colourId], selected);
	[self.swatchCache setObject:image forKey:key];
	return image;
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.tab == kTabProfile ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 1){
		NSInteger count = (NSInteger)self.activeIds.count;
		return (count + kSwatchColumns - 1) / kSwatchColumns;
	}
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	if (path.section == 1)
		return kSwatchRow;
	if (path.section == 0)
		return TGMetricPersonRow;
	return TGMetricRow;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 1)
		return self.tab == kTabProfile ? @"Profile Colour" : @"Name Colour";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path {
	TGTheme *theme = [TGTheme shared];

	if (path.section == 0)
		return [self previewCellFor:tableView];

	if (path.section == 1){
		static NSString *reuse = @"swatch";
		TGProfileSwatchCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
		if (!cell)
			cell = [[TGProfileSwatchCell alloc] initWithStyle:UITableViewCellStyleDefault
											  reuseIdentifier:reuse];
		NSArray *ids = self.activeIds;
		NSInteger start = path.row * kSwatchColumns;
		NSInteger end = MIN(start + kSwatchColumns, (NSInteger)ids.count);
		NSInteger activeId = [self activeId];
		NSMutableArray *images = [NSMutableArray array];
		for (NSInteger i = start; i < end; i++){
			NSInteger colourId = [ids[i] integerValue];
			[images addObject:[self swatchImageForId:colourId selected:(colourId == activeId)]];
		}
		__weak typeof(self) weakSelf = self;
		cell.onSwatch = ^(NSInteger index){
			[weakSelf chooseColourId:[ids[start + index] integerValue]];
		};
		[cell setSwatches:images];
		return cell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleGroupedCell:cell forRow:0 totalRows:1];
	cell.textLabel.text = @"Reset Profile Colour";
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textColor = [theme destructiveColour];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (UITableViewCell *)previewCellFor:(UITableView *)tableView {
	TGTheme *theme = [TGTheme shared];
	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleGroupedCell:cell forRow:0 totalRows:1];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	NSDictionary *me = [TGClient shared].me;
	NSString *name = [me[@"first_name"] length] ? me[@"first_name"] : @"Your Name";
	if ([me[@"last_name"] length])
		name = [NSString stringWithFormat:@"%@ %@", name, me[@"last_name"]];

	CGFloat side = TGMetricListAvatar;
	UIImage *avatar = [TGIcons avatarWithInitials:[TGIcons initialsForTitle:name]
											 size:side
										 colourId:[me[@"id"] longLongValue]];
	UIColor *profileColour = [[TGClient shared] accentColourForId:self.pendingProfileId
														  profile:YES];
	avatar = TGAppearanceAvatar(avatar, profileColour ?: [theme separatorColour]);

	UIImageView *avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(TGMetricGutter, TGCenteredOrigin(TGMetricPersonRow, side), side, side)];
	avatarView.image = avatar;
	[cell.contentView addSubview:avatarView];

	UIColor *nameColour = [[TGClient shared] accentColourForId:self.pendingAccentId
													   profile:NO];
	CGFloat width = tableView.bounds.size.width;
	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(TGMetricGutter + side + TGMetricPadMedium,
					TGCenteredOrigin(TGMetricPersonRow, TGMetricLineRow),
					width - TGMetricGutter - side - TGMetricPadMedium - TGMetricGutter,
					TGMetricLineRow)];
	nameLabel.text = name;
	nameLabel.font = TGFontRowStrong();
	nameLabel.textColor = nameColour ?: [theme primaryTextColour];
	nameLabel.backgroundColor = [UIColor clearColor];
	[cell.contentView addSubview:nameLabel];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];
	if (path.section == 2){
		self.pendingProfileId = -1;
		self.profileChanged = YES;
		[self.tableView reloadData];
	}
}

#pragma mark - choosing and applying

- (void)chooseColourId:(NSInteger)colourId {
	if (self.tab == kTabProfile){
		self.pendingProfileId = colourId;
		self.profileChanged = YES;
	} else {
		self.pendingAccentId = colourId;
		self.accentChanged = YES;
	}
	[self.tableView reloadData];
}

- (void)applyTapped {
	if (!self.loaded)
		return;

	__weak typeof(self) weakSelf = self;
	__block NSInteger pending = 0;
	__block BOOL failed = NO;
	if (self.profileChanged) pending++;
	if (self.accentChanged) pending++;

	if (!pending)
		return;

	void (^finish)(BOOL, NSString *) = ^(BOOL ok, NSString *error){
		TGProfileAppearanceViewController *me = weakSelf;
		if (!me)
			return;
		if (!ok){
			if (!failed){
				failed = YES;
				[TGAlertSheet showMessage:(error ?: @"Telegram refused that colour.")
									title:@"Your Color" inView:me.view];
			}
			return;
		}
		if (--pending == 0 && !failed)
			[me.navigationController popViewControllerAnimated:YES];
	};

	// The background emoji ids stay with the account; a colour write that
	// drops them would erase the pattern Telegram already stores. The client
	// reads them again at write time rather than trusting this screen's copy.
	if (self.profileChanged)
		[[TGClient shared]
				setAccountProfileAccentColorPreservingBackgroundEmoji:self.pendingProfileId
														   completion:finish];
	if (self.accentChanged)
		[[TGClient shared] setAccountAccentColorPreservingBackgroundEmoji:self.pendingAccentId
															   completion:finish];
}

@end
