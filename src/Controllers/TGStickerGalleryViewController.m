//
// TGStickerGalleryViewController.m - a preview grid of a sticker list.
//
#import "TGStickerGalleryViewController.h"
#import "TGAlertSheet.h"
#import "TGStickerStore.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"
#import <QuartzCore/QuartzCore.h>

@interface TGStickerGalleryViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *grid;
@property (nonatomic, strong) NSMutableArray *tiles;
@property (nonatomic, strong) NSMutableDictionary *images;   // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *requested;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation TGStickerGalleryViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	if (!self.title.length)
		self.title = @"Stickers";
	self.images = [NSMutableDictionary dictionary];
	self.requested = [NSMutableSet set];
	self.tiles = [NSMutableArray array];

	[self applyTheme];
	self.grid = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.grid.alwaysBounceVertical = YES;
	self.grid.showsVerticalScrollIndicator = NO;
	self.grid.delegate = self;
	[self.view addSubview:self.grid];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(applyTheme)
				name:TGThemeChangedNotification object:nil];
	[self rebuildGrid];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self rebuildGrid];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme listBackgroundColour];
	self.grid.backgroundColor = [theme listBackgroundColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	self.grid.frame = self.view.bounds;
	[self layoutGrid];
}

#pragma mark - grid

- (NSInteger)columns {
	CGFloat usable = self.grid.bounds.size.width - TGDoubled(TGMetricPadLarge);
	CGFloat step = TGMetricStickerPreviewCell + TGMetricStickerPreviewGap;
	return MAX(3, (NSInteger)((usable + TGMetricStickerPreviewGap) / step));
}

- (void)rebuildGrid {
	for (UIView *view in [self.grid.subviews copy])
		[view removeFromSuperview];
	[self.tiles removeAllObjects];

	if (!self.stickers.count){
		self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		self.emptyLabel.text = self.emptyText ?: @"Nothing here yet.";
		self.emptyLabel.font = TGFontBody();
		self.emptyLabel.textAlignment = NSTextAlignmentCenter;
		self.emptyLabel.numberOfLines = 2;
		self.emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
		self.emptyLabel.backgroundColor = [UIColor clearColor];
		[self.grid addSubview:self.emptyLabel];
		[self layoutGrid];
		return;
	}
	self.emptyLabel = nil;

	for (NSInteger i = 0; i < (NSInteger)self.stickers.count; i++){
		NSDictionary *sticker = self.stickers[(NSUInteger)i];
		UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
		tile.tag = i;
		tile.backgroundColor = [[TGTheme shared] cardBackgroundColour];
		tile.layer.cornerRadius = TGMetricCornerSmall;
		tile.layer.borderWidth = TGMetricHairline;
		tile.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
		tile.clipsToBounds = YES;
		tile.imageView.contentMode = UIViewContentModeScaleAspectFit;
		tile.adjustsImageWhenHighlighted = NO;
		[tile addTarget:self action:@selector(stickerTapped:)
			  forControlEvents:UIControlEventTouchUpInside];

		UILabel *emoji = [[UILabel alloc] initWithFrame:CGRectZero];
		emoji.tag = 3;
		emoji.font = TGFontEmojiMeta();
		emoji.textAlignment = NSTextAlignmentCenter;
		emoji.backgroundColor = [[TGTheme shared] mediaOverlayColour];
		emoji.textColor = [[TGTheme shared] onMediaColour];
		emoji.text = sticker[@"emoji"] ?: @"";
		[tile addSubview:emoji];

		[self.grid addSubview:tile];
		[self.tiles addObject:tile];
		[self loadImageForSticker:sticker into:tile];
	}
	[self layoutGrid];
}

- (void)layoutGrid {
	CGFloat width = self.grid.bounds.size.width;
	NSInteger columns = [self columns];
	CGFloat step = TGMetricStickerPreviewCell + TGMetricStickerPreviewGap;
	CGFloat used = columns * TGMetricStickerPreviewCell +
			(columns - 1) * TGMetricStickerPreviewGap;
	CGFloat left = MAX(TGMetricPadLarge, TGHalf(width - used));

	for (NSInteger i = 0; i < (NSInteger)self.tiles.count; i++){
		NSInteger column = i % columns;
		NSInteger row = i / columns;
		UIButton *tile = self.tiles[(NSUInteger)i];
		tile.frame = CGRectMake(left + column * step,
				TGMetricPadLarge + row * step,
				TGMetricStickerPreviewCell, TGMetricStickerPreviewCell);
		UIView *emoji = [tile viewWithTag:3];
		emoji.frame = CGRectMake(0, TGMetricStickerPreviewCell - TGMetricLineCaption,
				TGMetricStickerPreviewCell, TGMetricLineCaption);
	}

	NSInteger rows = ((NSInteger)self.tiles.count + columns - 1) / MAX(1, columns);
	self.grid.contentSize = CGSizeMake(width, TGMetricPadLarge +
			rows * step + TGMetricPadLarge);

	if (self.emptyLabel)
		self.emptyLabel.frame = CGRectMake(TGMetricPadLarge,
				MAX(0, TGHalf(self.grid.bounds.size.height) - TGMetricLineBody),
				width - TGDoubled(TGMetricPadLarge),
				TGMetricLineBody + TGMetricLineBody);
}

- (void)loadImageForSticker:(NSDictionary *)sticker into:(UIButton *)tile {
	NSNumber *fileId = sticker[@"fileId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0)
		return;
	UIImage *cached = self.images[fileId];
	if (cached){
		[tile setImage:cached forState:UIControlStateNormal];
		return;
	}
	if ([self.requested containsObject:fileId])
		return;
	[self.requested addObject:fileId];

	__weak typeof(self) weakSelf = self;
	__weak UIButton *weakTile = tile;
	NSInteger expected = tile.tag;
	[[TGStickerStore shared] downloadFile:fileId.integerValue
							  priority:TGDownloadPriorityOnScreen
							completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				image = [UIImage convertFromWebP:path compressedData:nil error:nil];
			if (!image)
				return;
			image = [TGIcons decodedImage:image
					fittingSize:CGSizeMake(TGMetricStickerPreviewCell,
										   TGMetricStickerPreviewCell)
							 fill:NO scale:[UIScreen mainScreen].scale];
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				TGStickerGalleryViewController *me = weakSelf;
				if (!me || !weakTile || weakTile.tag != expected)
					return;
				me.images[fileId] = image;
				[weakTile setImage:image forState:UIControlStateNormal];
			});
		});
	}];
}

#pragma mark - actions

- (void)stickerTapped:(UIButton *)tile {
	NSInteger index = tile.tag;
	if (index < 0 || index >= (NSInteger)self.stickers.count)
		return;
	NSDictionary *sticker = self.stickers[(NSUInteger)index];
	NSString *emoji = [sticker[@"emoji"] length] ? sticker[@"emoji"] : @"Sticker";
	NSString *message = [NSString stringWithFormat:
			@"Emoji: %@\nFile: %@\nSet: %@\nCustom emoji id: %@",
			emoji, sticker[@"fileId"] ?: @"-", sticker[@"setId"] ?: @"-",
			sticker[@"customEmojiId"] ?: @"-"];
	NSArray *choices = @[@"Add to Favourites", @"Remove from Favourites",
						 @"Copy File ID", @"Done"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:emoji message:message
			 destructiveIndex:-1 inView:self.view
					 onChoice:^(NSInteger choice){
		TGStickerGalleryViewController *me = weakSelf;
		if (!me)
			return;
		NSNumber *fileId = sticker[@"fileId"];
		if (choice == 0 && [fileId isKindOfClass:NSNumber.class]){
			[[TGStickerStore shared] setSticker:fileId.integerValue favourite:YES];
			[TGAlertSheet showMessage:@"The sticker is in Favourites."
								  title:@"Sticker" inView:me.view];
		} else if (choice == 1 && [fileId isKindOfClass:NSNumber.class]){
			[[TGStickerStore shared] setSticker:fileId.integerValue favourite:NO];
			[TGAlertSheet showMessage:@"The sticker is out of Favourites."
								  title:@"Sticker" inView:me.view];
		} else if (choice == 2 && [fileId isKindOfClass:NSNumber.class]){
			[UIPasteboard generalPasteboard].string = [fileId stringValue];
		}
	}];
}

@end

// vim:ft=objc
