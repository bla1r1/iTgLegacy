#import "TGAttachSheet.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGTextDraw.h"
#import "TGAlertSheet.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

/// The most photos the grid reads. A C array of this size holds the tick
/// order, so ticking a tile never allocates.
enum { kMaxPhotos = 60 };

static const CGFloat kRow          = TGMetricRow;
/// Two thirds of the screen: tall enough for two rows of tiles on a 480 pt
/// iPod, short enough that the chat still shows behind it.
static const CGFloat kSheetShare   = 2.0f / 3.0f;
static const CGFloat kGridGap      = 1.0f;
static const CGFloat kGridColumns  = 3.0f;
static const CGFloat kCameraGlyph  = 32.0f;
/// About two screens of thumbnails. Anything older is read from its asset
/// again, which costs less than the memory on a 256 MB device.
static const NSUInteger kThumbCacheLimit = 24;

static NSString *const kTileIdentifier = @"tile";

#pragma mark - grid tile

/// One square of the grid: a photo, or the camera. Opaque all the way down so
/// scrolling composites nothing but the small tick.
@interface TGAttachTile : UICollectionViewCell
@property (nonatomic, strong) UIImageView *photo;
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UIImageView *check;
- (void)showGlyph:(UIImage *)glyph;
- (void)showPhoto:(UIImage *)photo tick:(UIImage *)tick;
- (void)popCheck;
@end

@implementation TGAttachTile

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	UIColor *plain = [[TGTheme shared] fileTileColour];
	self.backgroundColor = plain;
	self.contentView.backgroundColor = plain;

	self.photo = [[UIImageView alloc] initWithFrame:CGRectZero];
	self.photo.opaque = YES;
	self.photo.backgroundColor = plain;
	[self.contentView addSubview:self.photo];

	self.glyph = [[UIImageView alloc] initWithFrame:CGRectZero];
	self.glyph.contentMode = UIViewContentModeCenter;
	[self.contentView addSubview:self.glyph];

	self.check = [[UIImageView alloc] initWithFrame:CGRectZero];
	[self.contentView addSubview:self.check];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	self.photo.frame = b;
	self.glyph.frame = b;
	self.check.frame = CGRectMake(b.size.width - TGMetricAttachTick - TGMetricPadSmall,
			TGMetricPadSmall, TGMetricAttachTick, TGMetricAttachTick);
}

- (void)showGlyph:(UIImage *)glyph {
	self.photo.image = nil;
	self.photo.hidden = YES;
	self.check.hidden = YES;
	self.glyph.hidden = NO;
	self.glyph.image = glyph;
}

- (void)showPhoto:(UIImage *)photo tick:(UIImage *)tick {
	self.glyph.hidden = YES;
	self.photo.hidden = NO;
	self.photo.image = photo;
	self.check.hidden = NO;
	self.check.image = tick;
}

/// The tick was just added by a tap, so it lands with a small pop. Reused
/// cells get their check without this.
- (void)popCheck {
	CAKeyframeAnimation *pop = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
	pop.values = @[@0.6f, @1.1f, @1.0f];
	pop.duration = TGAnimationDurationNormal;
	[self.check.layer addAnimation:pop forKey:@"tickPop"];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.photo.image = nil;
	// The reused cell must not carry on popping its previous photo's tick.
	[self.check.layer removeAnimationForKey:@"tickPop"];
}

@end

#pragma mark - sheet

@interface TGAttachSheet () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) UINavigationItem *header;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) NSArray *choiceItems;
@property (nonatomic, strong) UIBarButtonItem *sendItem;
@property (nonatomic, strong) UILabel *message;
/// Holds the assets alive: an ALAsset is only valid while its library is.
@property (nonatomic, strong) ALAssetsLibrary *library;
@property (nonatomic, strong) NSArray *assets;
/// Keyed by the asset itself. Cleared with the sheet.
@property (nonatomic, strong) NSCache *thumbs;
/// The round tick bitmaps, 0 for the empty ring and n for the filled one
/// numbered n. Drawn on first use, so a sheet that ticks three photos draws four.
@property (nonatomic, strong) NSMutableArray *ticks;
@property (nonatomic, strong) UIImage *cameraGlyph;
@end

@implementation TGAttachSheet {
	/// Tick position of each asset, 0 when it is not ticked.
	NSInteger _order[kMaxPhotos];
	NSInteger _ticked;
	CGFloat _tile;
	CGFloat _gridTop;
	CGFloat _gridHeight;
	BOOL _closing;
}

+ (TGAttachSheet *)showInView:(UIView *)view {
	TGAttachSheet *sheet = [TGAttachSheet sheetForView:view];
	[sheet present];
	// The library answers on the main thread and opening a group is not free,
	// so it waits for the slide-up to finish instead of stuttering it.
	__weak TGAttachSheet *weakSheet = sheet;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
			(int64_t)(TGAnimationDurationMedium * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[weakSheet loadRecentPhotos];
	});
	return sheet;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.thumbs = [[NSCache alloc] init];
	self.thumbs.countLimit = kThumbCacheLimit;
	self.ticks = [NSMutableArray arrayWithCapacity:(NSUInteger)kMaxPhotos + 1];
	for (NSUInteger i = 0; i <= (NSUInteger)kMaxPhotos; i++)
		[self.ticks addObject:[NSNull null]];

	CGFloat cardH = floorf(self.bounds.size.height * kSheetShare);
	UIView *card = [self addCardOfHeight:cardH edgeToEdge:YES];
	CGFloat w = card.bounds.size.width;

	[self addHeaderToCard:card width:w];

	_tile = floorf((w - TGDoubled(kGridGap)) / kGridColumns);
	_gridTop = kRow;
	_gridHeight = cardH - TGDoubled(kRow);
	[self addGridToCard:card width:w];

	[self addToolbarToCard:card frame:CGRectMake(0, cardH - kRow, w, kRow)];
	return self;
}

#pragma mark - building

/// The system's own bars, top and bottom: they are glass on iOS 6 and flat from
/// iOS 7 with nothing here having to know which.
- (void)addHeaderToCard:(UIView *)card width:(CGFloat)w {
	UINavigationBar *bar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, w, kRow)];
	[[TGTheme shared] styleNavigationBar:bar];
	self.header = [[UINavigationItem alloc] initWithTitle:@"Recent"];
	self.header.leftBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
								 target:self action:@selector(dismiss)];
	bar.items = @[self.header];
	[card addSubview:bar];
}

- (void)addGridToCard:(UIView *)card width:(CGFloat)w {
	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.itemSize = CGSizeMake(_tile, _tile);
	layout.minimumInteritemSpacing = kGridGap;
	layout.minimumLineSpacing = kGridGap;
	layout.scrollDirection = UICollectionViewScrollDirectionVertical;

	self.grid = [[UICollectionView alloc] initWithFrame:CGRectMake(0, _gridTop, w, _gridHeight)
								   collectionViewLayout:layout];
	self.grid.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	self.grid.opaque = YES;
	self.grid.dataSource = self;
	self.grid.delegate = self;
	self.grid.scrollsToTop = NO;
	[self.grid registerClass:[TGAttachTile class] forCellWithReuseIdentifier:kTileIdentifier];
	[card addSubview:self.grid];

	self.cameraGlyph = [TGIcons glyphNamed:@"video"
									colour:[[TGTheme shared] accentColour]
									  side:kCameraGlyph];
}

- (UIBarButtonItem *)itemWithGlyph:(NSString *)glyph choice:(TGAttachChoice)choice label:(NSString *)label {
	UIBarButtonItem *item = [[UIBarButtonItem alloc]
			initWithImage:[TGIcons glyphNamed:glyph
									   colour:[[TGTheme shared] barButtonColour]
										 side:TGMetricMenuGlyph]
					style:UIBarButtonItemStylePlain
				   target:self action:@selector(choiceTapped:)];
	item.tag = (NSInteger)choice;
	item.accessibilityLabel = label;
	return item;
}

- (void)addToolbarToCard:(UIView *)card frame:(CGRect)frame {
	self.toolbar = [[UIToolbar alloc] initWithFrame:frame];
	if ([self.toolbar respondsToSelector:@selector(setBarTintColor:)]){
		self.toolbar.barTintColor = [[TGTheme shared] barColour];
		self.toolbar.translucent = NO;
		self.toolbar.tintColor = [[TGTheme shared] barButtonColour];
	}
	UIBarButtonItem *(^gap)(void) = ^{
		return [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
									 target:nil action:nil];
	};
	UIBarButtonItem *more = [[UIBarButtonItem alloc]
			initWithImage:[TGIcons glyphNamed:@"more"
									   colour:[[TGTheme shared] barButtonColour]
										 side:TGMetricMenuGlyph]
					style:UIBarButtonItemStylePlain
				   target:self action:@selector(moreTapped)];
	more.accessibilityLabel = @"More";
	self.choiceItems = @[gap(),
			[self itemWithGlyph:@"folder" choice:TGAttachChoiceGallery label:@"Gallery"], gap(),
			[self itemWithGlyph:@"pin" choice:TGAttachChoiceLocation label:@"Location"], gap(),
			[self itemWithGlyph:@"call" choice:TGAttachChoiceContact label:@"Contact"], gap(),
			more, gap()];
	self.sendItem = [[UIBarButtonItem alloc] initWithTitle:@"Send"
													 style:UIBarButtonItemStyleDone
													target:self action:@selector(sendSelected)];
	self.toolbar.items = self.choiceItems;
	[card addSubview:self.toolbar];
}

/// The rest of the choices, in the system's own list.
- (void)moreTapped {
	UIView *host = self.superview;
	void (^onChoice)(TGAttachChoice) = self.onChoice;
	static const TGAttachChoice rest[] = {TGAttachChoiceChecklist, TGAttachChoiceQuickReply,
			TGAttachChoiceDice, TGAttachChoiceEphemeral};
	[self dismiss];
	[TGAlertSheet showChoices:@[@"Checklist", @"Quick Reply", @"Stake Dice", @"Ephemeral Message"]
						title:nil destructiveIndex:-1 inView:host onChoice:^(NSInteger choice){
		if (onChoice && choice >= 0 && choice < 4)
			onChoice(rest[choice]);
	}];
}

/// What the bars say follows what is ticked: a count for a title, and Send where
/// the choices were. The toolbar's own animated change crossfades them.
- (void)refreshBarsWithAdded:(BOOL)added {
	self.sendItem.title = [NSString stringWithFormat:@"Send %ld", (long)_ticked];
	self.header.title = _ticked ? [NSString stringWithFormat:@"%ld Selected", (long)_ticked]
								: @"Recent";
	if (added && _ticked == 1){
		UIBarButtonItem *gapLeft = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		UIBarButtonItem *gapRight = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		[self.toolbar setItems:@[gapLeft, self.sendItem, gapRight] animated:YES];
	} else if (!added && _ticked == 0){
		[self.toolbar setItems:self.choiceItems animated:YES];
	}
}

/// The check in a tile's corner as a bitmap, so a tile with one costs a blit
/// and not a layer with a corner radius.
- (UIImage *)tickForPosition:(NSInteger)position {
	if (position < 0 || position > kMaxPhotos)
		position = 0;
	id cached = self.ticks[position];
	if (cached != [NSNull null])
		return cached;

	TGTheme *theme = [TGTheme shared];
	CGFloat side = TGMetricAttachTick;
	CGFloat stroke = TGMetricBorderMedium;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
	UIBezierPath *disc = [UIBezierPath bezierPathWithOvalInRect:
			CGRectInset(CGRectMake(0, 0, side, side), TGHalf(stroke), TGHalf(stroke))];
	// The empty ring is dimmed inside so it shows on a white photo too.
	UIColor *fill = position ? [theme accentColour] : [theme scrimColour];
	[fill setFill];
	[disc fill];
	[[theme onMediaColour] setStroke];
	disc.lineWidth = stroke;
	[disc stroke];
	if (position){
		NSString *number = [NSString stringWithFormat:@"%ld", (long)position];
		UIFont *font = TGFontMicroStrong();
		CGSize size = TGLineTextSize(number, font);
		TGDrawText(number, CGRectMake(0, TGCenteredOrigin(side, size.height), side, size.height),
				font, [theme onAccentColour], NSTextAlignmentCenter, nil);
	}
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	self.ticks[position] = image;
	return image;
}

#pragma mark - life

- (void)dismiss {
	_closing = YES;
	[super dismiss];
}

/// The sheet is gone from the screen: hand back the thumbnails and the
/// library. Done here and not in -dismiss because TGSheet can also drop a sheet
/// without the animation.
- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window)
		return;
	_closing = YES;
	self.grid.dataSource = nil;
	self.grid.delegate = nil;
	[self.thumbs removeAllObjects];
	self.assets = nil;
	self.library = nil;
}

#pragma mark - recent photos

- (void)loadRecentPhotos {
	if (_closing)
		return;
	self.library = [[ALAssetsLibrary alloc] init];
	NSMutableArray *found = [NSMutableArray array];
	__block BOOL finished = NO;
	__weak typeof(self) weakSelf = self;
	// Whichever of the group block's two calls (the album, then nil) or the
	// failure block gets here first wins; the main queue gets one answer.
	void (^finish)(BOOL) = ^(BOOL denied){
		if (finished)
			return;
		finished = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf libraryDidRead:found denied:denied];
		});
	};
	[self.library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop){
		if (!group){
			finish(NO);
			return;
		}
		[group setAssetsFilter:[ALAssetsFilter allPhotos]];
		[group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *asset, NSUInteger index, BOOL *stopAssets){
			if (!asset)
				return;
			[found addObject:asset];
			if (found.count >= (NSUInteger)kMaxPhotos)
				*stopAssets = YES;
		}];
		*stop = YES;
		finish(NO);
	} failureBlock:^(NSError *error){
		finish(YES);
	}];
}

- (void)libraryDidRead:(NSArray *)found denied:(BOOL)denied {
	if (_closing)
		return;
	self.assets = found;
	[self.grid reloadData];
	if (denied)
		[self showMessage:@"Allow access to Photos in Settings"];
	else if (!found.count)
		[self showMessage:@"No photos yet"];
}

/// One line under the camera tile, where the photos would have been.
- (void)showMessage:(NSString *)text {
	CGFloat top = _gridTop + _tile + kGridGap;
	self.message = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadLarge, top,
			self.grid.bounds.size.width - TGDoubled(TGMetricPadLarge),
			_gridTop + _gridHeight - top)];
	self.message.text = text;
	self.message.numberOfLines = 1;
	self.message.textAlignment = NSTextAlignmentCenter;
	self.message.font = TGFontSubhead();
	self.message.textColor = [[TGTheme shared] secondaryTextColour];
	self.message.backgroundColor = [UIColor clearColor];
	[self.grid.superview addSubview:self.message];
}

- (UIImage *)thumbnailOfAsset:(ALAsset *)asset {
	UIImage *image = [self.thumbs objectForKey:asset];
	if (image)
		return image;
	// asset.thumbnail is already square and decoded, so the tile scales it as
	// it is and nothing is cropped or redrawn here.
	CGImageRef thumb = asset.thumbnail;
	if (!thumb)
		return nil;
	image = [UIImage imageWithCGImage:thumb];
	[self.thumbs setObject:image forKey:asset];
	return image;
}

#pragma mark - collection view

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
	return 1 + (NSInteger)MIN(self.assets.count, (NSUInteger)kMaxPhotos);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TGAttachTile *tile = [view dequeueReusableCellWithReuseIdentifier:kTileIdentifier
														 forIndexPath:indexPath];
	if (indexPath.item == 0){
		[tile showGlyph:self.cameraGlyph];
		return tile;
	}
	NSInteger index = indexPath.item - 1;
	[tile showPhoto:[self thumbnailOfAsset:self.assets[index]]
			   tick:[self tickForPosition:_order[index]]];
	return tile;
}

- (void)collectionView:(UICollectionView *)view didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	// Selection here is the sheet's own list, which has an order; UIKit's
	// selected state has none, so it is undone at once.
	[view deselectItemAtIndexPath:indexPath animated:NO];
	if (indexPath.item == 0){
		[self finishWithChoice:TGAttachChoiceCamera];
		return;
	}
	[self toggleAssetAtIndex:indexPath.item - 1];
}

- (void)toggleAssetAtIndex:(NSInteger)index {
	if (index < 0 || index >= kMaxPhotos || index >= (NSInteger)self.assets.count)
		return;
	BOOL added = NO;
	if (_order[index]){
		// Everything ticked after it moves up one, so the numbers read 1..n
		// with no gap, which is also the order the album goes out in.
		NSInteger removed = _order[index];
		_order[index] = 0;
		for (NSInteger i = 0; i < kMaxPhotos; i++){
			if (_order[i] > removed)
				_order[i]--;
		}
		_ticked--;
	} else {
		_order[index] = ++_ticked;
		added = YES;
	}

	for (TGAttachTile *tile in [self.grid visibleCells]){
		NSIndexPath *path = [self.grid indexPathForCell:tile];
		if (path && path.item > 0){
			tile.check.image = [self tickForPosition:_order[path.item - 1]];
			if (added && path.item - 1 == index)
				[tile popCheck];
		}
	}

	[self refreshBarsWithAdded:added];
}

#pragma mark - actions

- (void)choiceTapped:(UIBarButtonItem *)item {
	[self finishWithChoice:(TGAttachChoice)item.tag];
}

- (void)finishWithChoice:(TGAttachChoice)choice {
	void (^onChoice)(TGAttachChoice) = self.onChoice;
	[self dismiss];
	if (onChoice)
		onChoice(choice);
}

/// The screen-sized rendition of every ticked tile, in the order they were
/// ticked. It is already rotated upright and is what Telegram compresses a
/// photo down to anyway. Reading them is not instant, which is why it happens
/// on the tap that sends and not on each tick.
- (void)sendSelected {
	NSMutableArray *images = [NSMutableArray array];
	for (NSInteger position = 1; position <= _ticked; position++){
		for (NSInteger i = 0; i < kMaxPhotos && i < (NSInteger)self.assets.count; i++){
			if (_order[i] != position)
				continue;
			ALAsset *asset = self.assets[i];
			CGImageRef full = asset.defaultRepresentation.fullScreenImage;
			if (full)
				[images addObject:[UIImage imageWithCGImage:full]];
			break;
		}
	}
	void (^onPhotos)(NSArray *) = self.onPhotos;
	void (^onPhoto)(UIImage *) = self.onPhoto;
	[self dismiss];
	if (!images.count)
		return;
	// One picture is a picture, not an album of one.
	if (images.count == 1 && onPhoto)
		onPhoto(images[0]);
	else if (onPhotos)
		onPhotos(images);
}

@end
