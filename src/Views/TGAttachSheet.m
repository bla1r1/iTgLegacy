#import "TGAttachSheet.h"
#import "TGTheme.h"
#import "TGCapabilities.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

static const CGFloat kRow       = TGMetricActionRow;
static const CGFloat kStrip     = TGMetricAttachStrip;
static const CGFloat kThumb     = TGMetricAttachThumb;
static const NSUInteger kRecentPhotos = 24;

@interface TGAttachSheet ()
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIView *cancelCard;
@property (nonatomic, strong) UIScrollView *strip;
/// Holds the assets alive: an ALAsset is only valid while its library is.
@property (nonatomic, strong) ALAssetsLibrary *library;
@property (nonatomic, strong) NSMutableArray *assets;
/// Which tiles are ticked, in the order they were. Empty until a tile is
/// held, which is what starts a selection.
@property (nonatomic, strong) NSMutableArray *selected;
@property (nonatomic, strong) UIButton *sendButton;
@end

@implementation TGAttachSheet

+ (TGAttachSheet *)showInView:(UIView *)view {
	TGAttachSheet *sheet = [TGAttachSheet sheetForView:view];
	[sheet present];
	return sheet;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	TGTheme *theme = [TGTheme shared];

	BOOL strip = [TGCapabilities canShowRecentPhotos];
	NSArray *titles = @[@"Photo or Video", @"Location", @"Contact"];
	CGFloat cardH = (strip ? kStrip : 0) + kRow * titles.count;

	// Two floating cards, the way their attach menu stacks them: the
	// choices, and Cancel on its own under them.
	self.card = [self addCardOfHeight:cardH edgeToEdge:NO];
	CGFloat w = self.card.bounds.size.width;

	CGFloat y = 0;
	if (strip){
		self.strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, kStrip)];
		self.strip.showsHorizontalScrollIndicator = NO;
		self.strip.alwaysBounceHorizontal = YES;
		self.strip.scrollsToTop = NO;
		[self.card addSubview:self.strip];
		y = kStrip;
		[self loadRecentPhotos];
	}

	for (NSUInteger i = 0; i < titles.count; i++){
		if (y > 0){
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, TGMetricHairline)];
			hair.backgroundColor = [theme separatorColour];
			[self.card addSubview:hair];
		}
		UIButton *button = [self rowButtonTitled:titles[i] bold:NO frame:CGRectMake(0, y, w, kRow)];
		button.tag = (NSInteger)i;
		[button addTarget:self action:@selector(choiceTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.card addSubview:button];
		y += kRow;
	}

	// Send sits on the Cancel card, hidden until something is ticked: a card
	// that appears and shifts the stack while a finger is on it is worse
	// than a button that was always there.
	self.cancelCard = [self addCardOfHeight:kRow edgeToEdge:NO];
	UIButton *cancel = [self rowButtonTitled:@"Cancel" bold:YES frame:self.cancelCard.bounds];
	[cancel addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
	[self.cancelCard addSubview:cancel];

	if (strip){
		self.sendButton = [self rowButtonTitled:@"Send" bold:YES
										  frame:self.cancelCard.bounds];
		self.sendButton.hidden = YES;
		self.sendButton.backgroundColor = [theme cardBackgroundColour];
		[self.sendButton addTarget:self action:@selector(sendSelected)
				  forControlEvents:UIControlEventTouchUpInside];
		[self.cancelCard addSubview:self.sendButton];
	}

	return self;
}

- (UIButton *)rowButtonTitled:(NSString *)title bold:(BOOL)bold frame:(CGRect)frame {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = frame;
	button.titleLabel.font = bold ? TGFontHeader() : TGFontInput();
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
	[button setTitleColor:[[TGTheme shared] secondaryTextColour] forState:UIControlStateHighlighted];
	return button;
}

- (void)choiceTapped:(UIButton *)button {
	void (^onChoice)(TGAttachChoice) = self.onChoice;
	[self dismiss];
	if (onChoice)
		onChoice((TGAttachChoice)button.tag);
}

#pragma mark - recent photos

- (void)loadRecentPhotos {
	self.library = [[ALAssetsLibrary alloc] init];
	self.assets = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	[self.library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop){
		if (!group){
			[weakSelf fillStrip];
			return;
		}
		[group setAssetsFilter:[ALAssetsFilter allPhotos]];
		[group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *asset, NSUInteger index, BOOL *stopAssets){
			TGAttachSheet *me = weakSelf;
			if (!me || !asset)
				return;
			[me.assets addObject:asset];
			if (me.assets.count >= kRecentPhotos)
				*stopAssets = YES;
		}];
		*stop = YES;
		[weakSelf fillStrip];
	} failureBlock:^(NSError *error){
		// No access to the library: the strip says so instead of sitting empty.
		[weakSelf showStripMessage:@"Allow access to Photos in Settings to send them from here"];
	}];
}

- (void)showStripMessage:(NSString *)text {
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.strip.bounds, 16, 0)];
	label.text = text;
	label.numberOfLines = 2;
	label.textAlignment = NSTextAlignmentCenter;
	label.font = TGFontSubhead();
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	[self.strip addSubview:label];
}

- (void)fillStrip {
	if (self.strip.subviews.count)
		return;   // the group block can finish twice
	if (!self.assets.count){
		[self showStripMessage:@"No photos yet"];
		return;
	}
	CGFloat x = 7;
	CGFloat y = TGCenteredOrigin(kStrip, kThumb);
	for (NSUInteger i = 0; i < self.assets.count; i++){
		ALAsset *asset = self.assets[i];
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x, y, kThumb, kThumb);
		button.tag = (NSInteger)i;
		button.layer.cornerRadius = TGMetricCornerMedium;
		button.clipsToBounds = YES;
		button.imageView.contentMode = UIViewContentModeScaleAspectFill;
		CGImageRef thumb = asset.thumbnail;
		if (thumb)
			[button setImage:[UIImage imageWithCGImage:thumb] forState:UIControlStateNormal];
		[button addTarget:self action:@selector(photoTapped:) forControlEvents:UIControlEventTouchUpInside];
		// Holding one starts picking several; there is no other free gesture
		// on a strip that already scrolls and taps.
		UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(photoHeld:)];
		[button addGestureRecognizer:hold];
		[self.strip addSubview:button];
		x += kThumb + 5;
	}
	self.strip.contentSize = CGSizeMake(x + 2, kStrip);
}

/// The tick drawn over a chosen tile, and its number - which is the order
/// the album will be in.
- (void)markTile:(UIButton *)button position:(NSInteger)position {
	UILabel *tick = (UILabel *)[button viewWithTag:0x5101];
	if (position <= 0){
		[tick removeFromSuperview];
		button.alpha = TGAlphaOpaque;
		return;
	}
	if (!tick){
		tick = [[UILabel alloc] initWithFrame:CGRectMake(
				button.bounds.size.width - TGMetricAttachTick - TGMetricPadSmall, TGMetricPadSmall, TGMetricAttachTick, TGMetricAttachTick)];
		tick.tag = 0x5101;
		tick.textAlignment = NSTextAlignmentCenter;
		tick.font = TGFontMicroStrong();
		tick.textColor = [UIColor whiteColor];
		tick.backgroundColor = [[TGTheme shared] accentColour];
		tick.layer.cornerRadius = TGHalf(TGMetricAttachTick);
		tick.clipsToBounds = YES;
		[button addSubview:tick];
	}
	tick.text = [NSString stringWithFormat:@"%ld", (long)position];
	button.alpha = TGAlphaSecondary;
}

/// Renumbers every tile after one is ticked or unticked, so the numbers
/// always read 1..n with no gaps.
- (void)refreshTileMarks {
	for (UIView *view in self.strip.subviews){
		if (![view isKindOfClass:UIButton.class])
			continue;
		UIButton *button = (UIButton *)view;
		NSUInteger at = [self.selected indexOfObject:@(button.tag)];
		[self markTile:button
			  position:(at == NSNotFound ? 0 : (NSInteger)at + 1)];
	}

	if (!self.sendButton)
		return;
	self.sendButton.hidden = self.selected.count == 0;
	[self.sendButton setTitle:[NSString stringWithFormat:@"Send %lu",
			(unsigned long)self.selected.count] forState:UIControlStateNormal];
}

- (void)photoHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	UIButton *button = (UIButton *)hold.view;
	if (![button isKindOfClass:UIButton.class] ||
		button.tag >= (NSInteger)self.assets.count)
		return;
	if (!self.selected)
		self.selected = [NSMutableArray array];
	if (![self.selected containsObject:@(button.tag)])
		[self.selected addObject:@(button.tag)];
	[self refreshTileMarks];
}

/// The screen-sized rendition of every ticked tile, in the order they were
/// ticked. Reading them is not instant, which is why it happens on the tap
/// that sends rather than on each tick.
- (void)sendSelected {
	NSMutableArray *images = [NSMutableArray array];
	for (NSNumber *index in self.selected){
		if (index.integerValue >= (NSInteger)self.assets.count)
			continue;
		ALAsset *asset = self.assets[index.integerValue];
		CGImageRef full = asset.defaultRepresentation.fullScreenImage;
		if (full)
			[images addObject:[UIImage imageWithCGImage:full]];
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

- (void)photoTapped:(UIButton *)button {
	if (button.tag >= (NSInteger)self.assets.count)
		return;

	// Once a selection has started, a tap ticks and unticks rather than
	// sending - otherwise the first tap after a hold would send one picture.
	if (self.selected.count){
		if ([self.selected containsObject:@(button.tag)])
			[self.selected removeObject:@(button.tag)];
		else
			[self.selected addObject:@(button.tag)];
		[self refreshTileMarks];
		return;
	}

	ALAsset *asset = self.assets[button.tag];
	// The screen-sized rendition is already rotated upright and is what
	// Telegram compresses a photo down to anyway.
	CGImageRef full = asset.defaultRepresentation.fullScreenImage;
	UIImage *image = full ? [UIImage imageWithCGImage:full] : nil;
	void (^onPhoto)(UIImage *) = self.onPhoto;
	[self dismiss];
	if (image && onPhoto)
		onPhoto(image);
}

@end
