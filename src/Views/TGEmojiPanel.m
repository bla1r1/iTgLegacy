#import "TGEmojiPanel.h"
#import "TGEmojiData.h"
#import "TGTheme.h"
#import "TGClient.h"
#import "UIImage+WebP.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kStripHeight = 38.0f;   // categories / sets along the top
static const CGFloat kTabsHeight  = 36.0f;   // Emoji | Stickers | GIFs
static const CGFloat kEmojiCell   = 40.0f;

static const NSInteger kItemTagBase = 1000;  // grid buttons carry their index

/// Pictures decoded for the grid and the strip, by file id; shared by every
/// panel so reopening one draws at once.
static NSCache *TGPanelImageCache(void) {
	static NSCache *cache = nil;
	if (!cache){
		cache = [[NSCache alloc] init];
		cache.countLimit = 160;
	}
	return cache;
}

/// A still picture from a file TDLib downloaded: JPEG and PNG through UIKit,
/// WebP through the decoder the app carries.
static UIImage *TGPanelDecode(NSString *path) {
	if (!path.length)
		return nil;
	UIImage *image = nil;
	if (![path.pathExtension.lowercaseString isEqualToString:@"webp"])
		image = [UIImage imageWithContentsOfFile:path];
	if (!image)
		image = [UIImage convertFromWebP:path compressedData:nil error:nil];
	return image;
}

/// The key that deletes backwards: a pentagon pointing left with a cross.
static UIImage *TGBackspaceImage(UIColor *colour) {
	CGSize size = CGSizeMake(24, 18);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
	CGContextSetLineWidth(ctx, 1.6f);
	CGContextSetLineJoin(ctx, kCGLineJoinRound);
	CGContextSetLineCap(ctx, kCGLineCapRound);
	CGContextMoveToPoint(ctx, 7, 1.5f);
	CGContextAddLineToPoint(ctx, 22.5f, 1.5f);
	CGContextAddLineToPoint(ctx, 22.5f, 16.5f);
	CGContextAddLineToPoint(ctx, 7, 16.5f);
	CGContextAddLineToPoint(ctx, 1, 9);
	CGContextClosePath(ctx);
	CGContextStrokePath(ctx);
	CGContextMoveToPoint(ctx, 11, 5.5f);
	CGContextAddLineToPoint(ctx, 18, 12.5f);
	CGContextMoveToPoint(ctx, 18, 5.5f);
	CGContextAddLineToPoint(ctx, 11, 12.5f);
	CGContextStrokePath(ctx);
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

@interface TGEmojiPanel () <UIScrollViewDelegate, UIAlertViewDelegate>
@property (nonatomic, assign) TGEmojiPanelTab tab;
@property (nonatomic, strong) UIScrollView *strip;
@property (nonatomic, strong) UIScrollView *grid;
@property (nonatomic, strong) UIView *tabs;
@property (nonatomic, strong) UIView *stripLine;
@property (nonatomic, strong) UIView *tabsLine;
@property (nonatomic, strong) NSArray *tabButtons;
@property (nonatomic, strong) UIButton *backspace;
@property (nonatomic, strong) UILabel *emptyLabel;

/// What the grid shows right now, and the strip entry it came from.
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) NSInteger stripIndex;
@property (nonatomic, strong) NSMutableSet *requested;   // grid indexes asked for

@property (nonatomic, strong) NSArray *stickerSets;      // installed, as TGClient gives them
@property (nonatomic, assign) BOOL stickerSetsLoaded;
@property (nonatomic, strong) NSString *gifQuery;        // nil for the saved ones
/// Bumped every time the grid is rebuilt, so an answer for an older grid
/// is dropped rather than drawn into the wrong cell.
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation TGEmojiPanel

+ (CGFloat)preferredHeight {
	return 216.0f;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;

	CGFloat w = frame.size.width;
	CGFloat h = frame.size.height;

	self.strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, kStripHeight)];
	self.strip.showsHorizontalScrollIndicator = NO;
	self.strip.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.strip.scrollsToTop = NO;
	[self addSubview:self.strip];

	self.stripLine = [[UIView alloc] initWithFrame:CGRectMake(0, kStripHeight - 0.5f, w, 0.5f)];
	self.stripLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:self.stripLine];

	self.grid = [[UIScrollView alloc] initWithFrame:
			CGRectMake(0, kStripHeight, w, h - kStripHeight - kTabsHeight)];
	self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.grid.alwaysBounceVertical = YES;
	self.grid.scrollsToTop = NO;
	self.grid.delegate = self;
	[self addSubview:self.grid];

	self.emptyLabel = [[UILabel alloc] initWithFrame:self.grid.frame];
	self.emptyLabel.autoresizingMask = self.grid.autoresizingMask;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.numberOfLines = 2;
	self.emptyLabel.hidden = YES;
	[self addSubview:self.emptyLabel];

	self.tabs = [[UIView alloc] initWithFrame:CGRectMake(0, h - kTabsHeight, w, kTabsHeight)];
	self.tabs.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	[self addSubview:self.tabs];

	self.tabsLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5f)];
	self.tabsLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.tabs addSubview:self.tabsLine];

	NSArray *titles = @[@"Emoji", @"Stickers", @"GIFs"];
	NSMutableArray *buttons = [NSMutableArray array];
	CGFloat tabW = 76.0f;
	CGFloat x = (w - tabW * titles.count) / 2;
	for (NSUInteger i = 0; i < titles.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x + tabW * i, 0, tabW, kTabsHeight);
		button.tag = (NSInteger)i;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		[button setTitle:titles[i] forState:UIControlStateNormal];
		[button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.tabs addSubview:button];
		[buttons addObject:button];
	}
	self.tabButtons = buttons;

	self.backspace = [UIButton buttonWithType:UIButtonTypeCustom];
	self.backspace.frame = CGRectMake(w - 46, 0, 46, kTabsHeight);
	self.backspace.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.backspace addTarget:self action:@selector(backspaceTapped)
			 forControlEvents:UIControlEventTouchUpInside];
	[self.tabs addSubview:self.backspace];

	self.requested = [NSMutableSet set];
	[self applyTheme];
	[self selectTab:TGEmojiPanelTabEmoji];
	return self;
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.backgroundColor = [theme inputBarColour];
	self.stripLine.backgroundColor = [theme separatorColour];
	self.tabsLine.backgroundColor = [theme separatorColour];
	self.emptyLabel.textColor = [theme secondaryTextColour];
	[self.backspace setImage:TGBackspaceImage([theme secondaryTextColour]) forState:UIControlStateNormal];
	for (UIButton *button in self.tabButtons){
		BOOL on = button.tag == self.tab;
		[button setTitleColor:on ? [theme accentColour] : [theme secondaryTextColour]
					 forState:UIControlStateNormal];
	}
	[self reloadStrip];
}

#pragma mark - tabs

- (void)tabTapped:(UIButton *)button {
	[self selectTab:(TGEmojiPanelTab)button.tag];
}

- (void)selectTab:(TGEmojiPanelTab)tab {
	self.tab = tab;
	self.stripIndex = 0;
	self.gifQuery = nil;
	self.backspace.hidden = tab != TGEmojiPanelTabEmoji;
	TGTheme *theme = [TGTheme shared];
	for (UIButton *button in self.tabButtons){
		BOOL on = button.tag == tab;
		[button setTitleColor:on ? [theme accentColour] : [theme secondaryTextColour]
					 forState:UIControlStateNormal];
	}

	if (tab == TGEmojiPanelTabStickers && !self.stickerSetsLoaded){
		self.stickerSetsLoaded = YES;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] installedStickerSetsWithCompletion:^(NSArray *sets){
			weakSelf.stickerSets = sets;
			if (weakSelf.tab == TGEmojiPanelTabStickers)
				[weakSelf reloadStrip];
		}];
	}
	[self reloadStrip];
	[self loadItemsForStripIndex:0];
}

#pragma mark - strip

/// The strip entries for the current tab: each is @{"title" or "emoji" or
/// "thumbId"}. Emoji: Recent, then the categories. Stickers: Recent,
/// Favourites, then each installed set. GIFs: Saved and Search.
- (NSArray *)stripEntries {
	switch (self.tab){
		case TGEmojiPanelTabEmoji: {
			NSMutableArray *out = [NSMutableArray arrayWithObject:@{@"emoji" : @"🕘"}];
			for (NSDictionary *category in TGEmojiCategories())
				[out addObject:@{@"emoji" : category[@"icon"]}];
			return out;
		}
		case TGEmojiPanelTabStickers: {
			NSMutableArray *out = [NSMutableArray arrayWithObjects:
					@{@"emoji" : @"🕘"}, @{@"emoji" : @"⭐️"}, nil];
			for (NSDictionary *set in self.stickerSets){
				NSDictionary *cover = set[@"cover"];
				NSMutableDictionary *entry = [NSMutableDictionary dictionary];
				entry[@"emoji"] = [cover[@"emoji"] length] ? cover[@"emoji"]
						: ([set[@"title"] length] ? [set[@"title"] substringToIndex:1] : @"?");
				if ([cover[@"thumbId"] integerValue] > 0)
					entry[@"thumbId"] = cover[@"thumbId"];
				[out addObject:entry];
			}
			return out;
		}
		case TGEmojiPanelTabGIFs:
			return @[@{@"title" : @"Saved"}, @{@"title" : @"Search"}];
	}
	return @[];
}

- (void)reloadStrip {
	for (UIView *view in [self.strip.subviews copy])
		[view removeFromSuperview];

	TGTheme *theme = [TGTheme shared];
	NSArray *entries = [self stripEntries];
	CGFloat x = 4;
	for (NSUInteger i = 0; i < entries.count; i++){
		NSDictionary *entry = entries[i];
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		CGFloat width = entry[@"title"] ? 80 : 38;
		button.frame = CGRectMake(x, 3, width, kStripHeight - 6);
		button.tag = (NSInteger)i;
		button.layer.cornerRadius = 6;
		button.backgroundColor = (NSInteger)i == self.stripIndex
				? [theme actionTileBackgroundColour] : [UIColor clearColor];
		if (entry[@"title"]){
			button.titleLabel.font = [UIFont systemFontOfSize:14];
			[button setTitle:entry[@"title"] forState:UIControlStateNormal];
			[button setTitleColor:(NSInteger)i == self.stripIndex ? [theme accentColour]
																 : [theme secondaryTextColour]
						 forState:UIControlStateNormal];
		} else {
			button.titleLabel.font = [UIFont systemFontOfSize:20];
			[button setTitle:entry[@"emoji"] forState:UIControlStateNormal];
		}
		[button addTarget:self action:@selector(stripTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.strip addSubview:button];

		NSNumber *thumbId = entry[@"thumbId"];
		if (thumbId)
			[self loadImageForFile:thumbId.integerValue into:button generation:NSNotFound];
		x += width + 2;
	}
	self.strip.contentSize = CGSizeMake(x + 4, kStripHeight);
}

- (void)stripTapped:(UIButton *)button {
	if (self.tab == TGEmojiPanelTabGIFs && button.tag == 1){
		[self askForGifSearch];
		return;
	}
	if (self.tab == TGEmojiPanelTabGIFs)
		self.gifQuery = nil;   // "Saved"
	self.stripIndex = button.tag;
	[self reloadStrip];
	[self loadItemsForStripIndex:button.tag];
}

#pragma mark - items

- (void)loadItemsForStripIndex:(NSInteger)index {
	self.generation++;
	NSUInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	void (^show)(NSArray *, NSString *) = ^(NSArray *items, NSString *empty){
		TGEmojiPanel *me = weakSelf;
		if (!me || me.generation != generation)
			return;
		me.items = items ?: @[];
		me.emptyLabel.text = empty;
		[me reloadGrid];
	};

	switch (self.tab){
		case TGEmojiPanelTabEmoji: {
			NSArray *categories = TGEmojiCategories();
			if (index == 0)
				show(TGRecentEmoji(), nil);
			else if (index - 1 < (NSInteger)categories.count)
				show(categories[index - 1][@"emoji"], nil);
			break;
		}
		case TGEmojiPanelTabStickers: {
			show(@[], nil);
			void (^got)(NSArray *) = ^(NSArray *stickers){
				show(stickers, index == 1 ? @"Stickers you add to Favourites\nshow up here"
										   : @"No stickers yet");
			};
			if (index == 0)
				[[TGClient shared] recentStickersWithCompletion:got];
			else if (index == 1)
				[[TGClient shared] favoriteStickersWithCompletion:got];
			else if (index - 2 < (NSInteger)self.stickerSets.count)
				[[TGClient shared] stickersInSet:self.stickerSets[index - 2][@"id"] completion:got];
			break;
		}
		case TGEmojiPanelTabGIFs: {
			show(@[], nil);
			void (^got)(NSArray *) = ^(NSArray *gifs){
				show(gifs, weakSelf.gifQuery ? @"Nothing found" : @"GIFs you save show up here");
			};
			if (self.gifQuery)
				[[TGClient shared] searchAnimations:self.gifQuery inChat:self.chatId completion:got];
			else
				[[TGClient shared] savedAnimationsWithCompletion:got];
			break;
		}
	}
}

- (CGSize)cellSize {
	CGFloat w = self.grid.bounds.size.width;
	switch (self.tab){
		case TGEmojiPanelTabEmoji: {
			NSUInteger columns = MAX(1, (NSUInteger)floorf(w / kEmojiCell));
			CGFloat side = floorf(w / columns);
			return CGSizeMake(side, kEmojiCell);
		}
		case TGEmojiPanelTabStickers: {
			CGFloat side = floorf(w / 4);
			return CGSizeMake(side, side);
		}
		case TGEmojiPanelTabGIFs: {
			CGFloat side = floorf(w / 3);
			return CGSizeMake(side, floorf(side * 0.8f));
		}
	}
	return CGSizeMake(40, 40);
}

- (void)reloadGrid {
	for (UIView *view in [self.grid.subviews copy])
		if (view.tag >= kItemTagBase)
			[view removeFromSuperview];
	[self.requested removeAllObjects];

	CGSize cell = [self cellSize];
	CGFloat w = self.grid.bounds.size.width;
	NSUInteger columns = MAX(1, (NSUInteger)floorf(w / cell.width));
	TGTheme *theme = [TGTheme shared];

	for (NSUInteger i = 0; i < self.items.count; i++){
		CGRect frame = CGRectMake((i % columns) * cell.width, (i / columns) * cell.height,
								  cell.width, cell.height);
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = frame;
		button.tag = kItemTagBase + (NSInteger)i;
		button.adjustsImageWhenHighlighted = YES;
		[button addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];

		id item = self.items[i];
		if (self.tab == TGEmojiPanelTabEmoji){
			button.titleLabel.font = [UIFont systemFontOfSize:28];
			[button setTitle:item forState:UIControlStateNormal];
		} else if (self.tab == TGEmojiPanelTabStickers){
			button.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
			button.imageView.contentMode = UIViewContentModeScaleAspectFit;
			UIImage *cached = [TGPanelImageCache() objectForKey:item[@"thumbId"]];
			if (cached)
				[button setImage:cached forState:UIControlStateNormal];
			else {
				// The emoji stands in until the picture arrives - and for
				// good, for a sticker with no still thumbnail.
				button.titleLabel.font = [UIFont systemFontOfSize:36];
				[button setTitle:item[@"emoji"] forState:UIControlStateNormal];
			}
		} else {
			UIImageView *picture = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 1, 1)];
			picture.contentMode = UIViewContentModeScaleAspectFill;
			picture.clipsToBounds = YES;
			picture.backgroundColor = [theme fileTileColour];
			picture.userInteractionEnabled = NO;
			picture.tag = 1;
			UIImage *cached = item[@"thumbId"] ? [TGPanelImageCache() objectForKey:item[@"thumbId"]] : nil;
			if (!cached && item[@"minithumbnail"])
				cached = [UIImage imageWithData:item[@"minithumbnail"]];
			picture.image = cached;
			[button addSubview:picture];
		}
		[self.grid addSubview:button];
	}

	NSUInteger rows = (self.items.count + columns - 1) / columns;
	self.grid.contentSize = CGSizeMake(w, rows * cell.height);
	self.grid.contentOffset = CGPointZero;
	self.emptyLabel.hidden = self.items.count > 0 || !self.emptyLabel.text.length;
	[self loadVisibleImages];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.grid)
		[self loadVisibleImages];
}

/// Thumbnails for what is on screen and a screen beyond it; the rest wait
/// until scrolled to, so opening a set of a hundred does not start a hundred
/// downloads.
- (void)loadVisibleImages {
	if (self.tab == TGEmojiPanelTabEmoji)
		return;
	CGRect visible = self.grid.bounds;
	visible.size.height *= 2;
	for (UIView *view in self.grid.subviews){
		if (view.tag < kItemTagBase || !CGRectIntersectsRect(view.frame, visible))
			continue;
		NSInteger index = view.tag - kItemTagBase;
		if (index >= (NSInteger)self.items.count || [self.requested containsObject:@(index)])
			continue;
		[self.requested addObject:@(index)];
		NSNumber *thumbId = self.items[index][@"thumbId"];
		if ([thumbId integerValue] <= 0 || [TGPanelImageCache() objectForKey:thumbId])
			continue;
		[self loadImageForFile:thumbId.integerValue into:(UIButton *)view generation:self.generation];
	}
}

/// Download and decode a picture, then put it on the button (or the GIF
/// tile inside it). `generation` is NSNotFound for strip buttons, which do
/// not go stale with the grid.
- (void)loadImageForFile:(NSInteger)fileId into:(UIButton *)button generation:(NSUInteger)generation {
	UIImage *cached = [TGPanelImageCache() objectForKey:@(fileId)];
	__weak typeof(self) weakSelf = self;
	__weak UIButton *weakButton = button;
	void (^apply)(UIImage *) = ^(UIImage *image){
		TGEmojiPanel *me = weakSelf;
		UIButton *target = weakButton;
		if (!me || !target || !image)
			return;
		if (generation != NSNotFound && generation != me.generation)
			return;
		UIImageView *tile = (UIImageView *)[target viewWithTag:1];
		if ([tile isKindOfClass:UIImageView.class]){
			tile.image = image;
		} else {
			[target setTitle:nil forState:UIControlStateNormal];
			target.imageView.contentMode = UIViewContentModeScaleAspectFit;
			[target setImage:image forState:UIControlStateNormal];
		}
	};
	if (cached){
		apply(cached);
		return;
	}
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *image = TGPanelDecode(path);
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				[TGPanelImageCache() setObject:image forKey:@(fileId)];
				apply(image);
			});
		});
	}];
}

- (void)itemTapped:(UIButton *)button {
	NSInteger index = button.tag - kItemTagBase;
	if (index < 0 || index >= (NSInteger)self.items.count)
		return;
	id item = self.items[index];
	switch (self.tab){
		case TGEmojiPanelTabEmoji:
			TGNoteEmojiUsed(item);
			[self.delegate emojiPanel:self didPickEmoji:item];
			break;
		case TGEmojiPanelTabStickers:
			[self.delegate emojiPanel:self didPickSticker:item];
			break;
		case TGEmojiPanelTabGIFs:
			[self.delegate emojiPanel:self didPickAnimation:item];
			break;
	}
}

- (void)backspaceTapped {
	[self.delegate emojiPanelDidBackspace:self];
}

#pragma mark - GIF search

/// A text field inside the panel would raise the keyboard the panel is
/// standing in for, so the query is asked for in an alert.
- (void)askForGifSearch {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Search GIFs"
													message:nil
												   delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Search", nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	[alert textFieldAtIndex:0].text = self.gifQuery;
	[alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	if (index == alertView.cancelButtonIndex)
		return;
	NSString *query = [[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	self.gifQuery = query.length ? query : nil;
	self.stripIndex = self.gifQuery ? 1 : 0;
	[self reloadStrip];
	[self loadItemsForStripIndex:self.stripIndex];
}

@end
