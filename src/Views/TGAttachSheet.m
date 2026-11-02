#import "TGAttachSheet.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGTextDraw.h"
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
static const CGFloat kCancelWidth  = 80.0f;
static const CGFloat kGridGap      = 1.0f;
static const CGFloat kGridColumns  = 3.0f;
static const CGFloat kCameraGlyph  = 32.0f;
static const CGFloat kStripHeight  = 76.0f;
static const CGFloat kStripTile    = 44.0f;
static const CGFloat kStripItem    = 72.0f;
static const CGFloat kStripTileTop = TGMetricPad;
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
@property (nonatomic, strong) UIScrollView *strip;
@property (nonatomic, strong) UIButton *sendButton;
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
	TGTheme *theme = [TGTheme shared];
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
	_gridHeight = cardH - kRow - kStripHeight;
	[self addGridToCard:card width:w];

	CGFloat stripY = cardH - kStripHeight;
	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, stripY, w, TGMetricHairline)];
	hair.backgroundColor = [theme separatorColour];
	[card addSubview:hair];
	[self addStripToCard:card frame:CGRectMake(0, stripY, w, kStripHeight)];
	return self;
}

#pragma mark - building

- (void)addHeaderToCard:(UIView *)card width:(CGFloat)w {
	TGTheme *theme = [TGTheme shared];
	UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
	cancel.frame = CGRectMake(0, 0, kCancelWidth, kRow);
	cancel.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	cancel.contentEdgeInsets = UIEdgeInsetsMake(0, TGMetricPadLarge, 0, 0);
	cancel.titleLabel.font = TGFontInput();
	[cancel setTitle:@"Cancel" forState:UIControlStateNormal];
	[cancel setTitleColor:[theme accentColour] forState:UIControlStateNormal];
	[cancel setTitleColor:[theme secondaryTextColour] forState:UIControlStateHighlighted];
	[cancel addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
	[card addSubview:cancel];

	// Same margin both sides, so the title stays on the centre line whatever
	// Cancel's width.
	UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(kCancelWidth, 0,
			w - TGDoubled(kCancelWidth), kRow)];
	title.text = @"Recent";
	title.textAlignment = NSTextAlignmentCenter;
	title.font = TGFontHeader();
	title.textColor = [theme primaryTextColour];
	title.backgroundColor = [UIColor clearColor];
	[card addSubview:title];

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, kRow - TGMetricHairline, w, TGMetricHairline)];
	hair.backgroundColor = [theme separatorColour];
	[card addSubview:hair];
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

- (void)addStripToCard:(UIView *)card frame:(CGRect)frame {
	TGTheme *theme = [TGTheme shared];
	self.strip = [[UIScrollView alloc] initWithFrame:frame];
	self.strip.showsHorizontalScrollIndicator = NO;
	self.strip.alwaysBounceHorizontal = YES;
	self.strip.scrollsToTop = NO;
	[card addSubview:self.strip];

	// Index is the TGAttachChoice the tile reports.
	NSArray *titles = @[@"Gallery", @"Location", @"Contact", @"Checklist",
						@"Quick Reply", @"Dice", @"Ephemeral"];
	NSArray *glyphs = @[@"folder", @"pin", @"call", @"select", @"reply",
						@"star", @"recent"];
	NSArray *hues = @[TGIconTileAzure(), TGIconTileGreen(), TGIconTileAmber(),
					  TGIconTileCyan(), TGIconTileViolet(), TGIconTileCoral(),
					  TGIconTileSlate()];

	CGFloat x = TGMetricPad;
	for (NSUInteger i = 0; i < titles.count; i++){
		UIButton *item = [UIButton buttonWithType:UIButtonTypeCustom];
		item.frame = CGRectMake(x, 0, kStripItem, kStripHeight);
		item.tag = (NSInteger)i;
		item.accessibilityLabel = titles[i];
		// The tile is the button's own image so the stock dimming on touch
		// comes with it; the insets drop it to the top, above the label.
		item.contentVerticalAlignment = UIControlContentVerticalAlignmentTop;
		item.imageEdgeInsets = UIEdgeInsetsMake(kStripTileTop, 0, 0, 0);
		[item setImage:[self stripTileWithGlyph:glyphs[i] hue:hues[i]]
			  forState:UIControlStateNormal];
		[item addTarget:self action:@selector(choiceTapped:) forControlEvents:UIControlEventTouchUpInside];

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0,
				kStripTileTop + kStripTile + TGMetricPadSmall, kStripItem, TGMetricLineMicro)];
		label.text = titles[i];
		label.textAlignment = NSTextAlignmentCenter;
		label.font = TGFontMicro();
		label.textColor = [theme secondaryTextColour];
		label.backgroundColor = [UIColor clearColor];
		label.userInteractionEnabled = NO;
		[item addSubview:label];

		[self.strip addSubview:item];
		x += kStripItem;
	}
	self.strip.contentSize = CGSizeMake(x + TGMetricPad, frame.size.height);

	// Same slot as the strip, so the button slides over it without a relayout,
	// which happens under a finger.
	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.sendButton.frame = frame;
	self.sendButton.hidden = YES;
	self.sendButton.backgroundColor = [theme accentColour];
	self.sendButton.titleLabel.font = TGFontHeader();
	[self.sendButton setTitleColor:[theme onAccentColour] forState:UIControlStateNormal];
	self.sendButton.showsTouchWhenHighlighted = YES;
	[self.sendButton addTarget:self action:@selector(sendSelected)
			  forControlEvents:UIControlEventTouchUpInside];
	[card addSubview:self.sendButton];
}

/// The send button covers the strip once there is something to send. Both
/// slides are transforms, so the strip stays under it and is revealed again
/// as the button leaves.
- (void)showSendButton {
	self.sendButton.hidden = NO;
	self.sendButton.transform = CGAffineTransformMakeTranslation(0, kStripHeight);
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.sendButton.transform = CGAffineTransformIdentity;
	}];
}

- (void)hideSendButton {
	__weak TGAttachSheet *weakSheet = self;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		weakSheet.sendButton.transform = CGAffineTransformMakeTranslation(0, kStripHeight);
	} completion:^(BOOL finished){
		// Ticking again during the slide has already taken the button back.
		TGAttachSheet *sheet = weakSheet;
		if (!sheet || sheet->_ticked > 0)
			return;
		sheet.sendButton.hidden = YES;
		sheet.sendButton.transform = CGAffineTransformIdentity;
	}];
}

/// One round bitmap per tile, hue and glyph together, so the strip scrolls as
/// seven plain images and not seven layers with corner masks.
- (UIImage *)stripTileWithGlyph:(NSString *)glyph hue:(UIColor *)hue {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(kStripTile, kStripTile), NO, 0);
	CGRect oval = CGRectMake(0, 0, kStripTile, kStripTile);
	[hue setFill];
	[[UIBezierPath bezierPathWithOvalInRect:oval] fill];
	if ([TGTheme drawsSkeuomorphicChrome])
		[TGTheme drawGlossOnOvalInRect:oval baseColour:hue];
	UIImage *mark = [TGIcons glyphNamed:glyph
								 colour:[[TGTheme shared] onAccentColour]
								   side:TGMetricMenuGlyph];
	CGFloat origin = TGCenteredOrigin(kStripTile, TGMetricMenuGlyph);
	[mark drawInRect:CGRectMake(origin, origin, TGMetricMenuGlyph, TGMetricMenuGlyph)];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
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

	[self.sendButton setTitle:[NSString stringWithFormat:@"Send %ld", (long)_ticked]
					 forState:UIControlStateNormal];
	if (added && _ticked == 1)
		[self showSendButton];
	else if (!added && _ticked == 0)
		[self hideSendButton];
}

#pragma mark - actions

- (void)choiceTapped:(UIButton *)button {
	[self finishWithChoice:(TGAttachChoice)button.tag];
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
