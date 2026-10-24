#import "TGEmojiPanel.h"
#import "TGEmojiData.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGPopupMenu.h"
#import "TGClient.h"
#import "UIImage+WebP.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kStripHeight = 38.0f;   // categories / sets along the top
static const CGFloat kTabsHeight  = 36.0f;   // Emoji | Stickers | GIFs
static const CGFloat kEmojiCell   = 40.0f;

static const NSInteger kItemTagBase = 1000;  // grid buttons carry their index
static const NSInteger kHeaderTag   = 900;   // a section title in the feed
static const CGFloat   kHeaderHeight = 22.0f;

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
/// Stickers are one continuous feed the way their client shows it, so the
/// grid is cut into named sections over the flat `items`: each entry carries
/// a title, the range it covers, and the y it was laid out at, which is what
/// the strip scrolls to and highlights from.
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, assign) BOOL syncingStrip;
/// Where every item sits, worked out once per layout. Only the cells on
/// screen exist as views: a set of a hundred stickers times a dozen sets is
/// more buttons than an A5 will build in one run loop turn, and building
/// them all again for every set that answered froze the whole app.
@property (nonatomic, strong) NSArray *frames;
@property (nonatomic, strong) NSMutableDictionary *cells;   // index -> button
@property (nonatomic, strong) NSMutableArray *pool;         // buttons off screen
@property (nonatomic, assign) BOOL relayoutQueued;
@property (nonatomic, assign) NSTimeInterval menuOpenUntil;
@property (nonatomic, assign) NSInteger stripIndex;
@property (nonatomic, strong) NSMutableSet *requested;   // grid indexes asked for

@property (nonatomic, strong) NSArray *stickerSets;      // installed, as TGClient gives them
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
	self.cells = [NSMutableDictionary dictionary];

	self.pool = [NSMutableArray array];
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

	// Asked for every time the tab is opened, not once: Favourites and the
	// installed sets change from other clients, and a latched list never
	// caught up. The feed is rebuilt once they land - the first build only
	// has Favourites and Recently Used, because the sets are not here yet.
	if (tab == TGEmojiPanelTabStickers){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] installedStickerSetsWithCompletion:^(NSArray *sets){
			TGEmojiPanel *me = weakSelf;
			if (!me || me.tab != TGEmojiPanelTabStickers)
				return;
			me.stickerSets = sets;
			[me reloadStrip];
			[me loadStickerFeed];
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
			NSMutableArray *out = [NSMutableArray arrayWithObject:@{@"glyph" : @"recent"}];
			for (NSDictionary *category in TGEmojiCategories())
				[out addObject:@{@"emoji" : category[@"icon"]}];
			return out;
		}
		case TGEmojiPanelTabStickers: {
			NSMutableArray *out = [NSMutableArray arrayWithObjects:
					@{@"glyph" : @"star"}, @{@"glyph" : @"recent"}, nil];
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
		} else if (entry[@"glyph"]){
			// Recent and Favourites are drawn, not set as emoji: iOS 7 has no
			// colour glyph for some of these on every device.
			[button setImage:[TGIcons glyphNamed:entry[@"glyph"]
										  colour:((NSInteger)i == self.stripIndex
												  ? [theme accentColour] : [theme secondaryTextColour])
											side:22]
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

	// Stickers are one feed: the strip moves within it rather than swapping
	// what the grid holds. A set still loading has no section yet.
	if (self.tab == TGEmojiPanelTabStickers && self.sections.count){
		for (NSDictionary *section in self.sections){
			if ([section[@"strip"] integerValue] != button.tag)
				continue;
			CGFloat limit = MAX(0, self.grid.contentSize.height - self.grid.bounds.size.height);
			self.syncingStrip = YES;
			[self.grid setContentOffset:
					CGPointMake(0, MIN([section[@"headerY"] floatValue], limit)) animated:YES];
			self.syncingStrip = NO;
			self.stripIndex = button.tag;
			[self updateStripHighlight];
			return;
		}
		return;
	}

	self.stripIndex = button.tag;
	[self updateStripHighlight];
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
		me.sections = nil;
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
		case TGEmojiPanelTabStickers:
			// One feed, not one set at a time: the strip only moves within it.
			[self loadStickerFeed];
			break;
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

/// Favourites, then Recently Used, then every installed set, in one scroll.
/// The sets are asked for one after another rather than all at once: a dozen
/// answers landing together rebuilt the feed a dozen times and froze the app.
- (void)loadStickerFeed {
	self.generation++;
	NSUInteger generation = self.generation;

	NSMutableArray *titles = [NSMutableArray arrayWithObjects:@"Favourites", @"Recently Used", nil];
	for (NSDictionary *set in self.stickerSets)
		[titles addObject:[set[@"title"] length] ? set[@"title"] : @"Stickers"];

	NSMutableArray *slots = [NSMutableArray array];
	for (NSUInteger i = 0; i < titles.count; i++)
		[slots addObject:@[]];

	self.items = @[];
	self.sections = nil;
	self.emptyLabel.text = @"No stickers yet";
	[self reloadGrid];

	__weak typeof(self) weakSelf = self;
	void (^fill)(NSUInteger, NSArray *) = ^(NSUInteger slot, NSArray *stickers){
		TGEmojiPanel *me = weakSelf;
		if (!me || me.generation != generation || slot >= slots.count)
			return;
		slots[slot] = stickers ?: @[];

		NSMutableArray *flat = [NSMutableArray array];
		NSMutableArray *sections = [NSMutableArray array];
		for (NSUInteger i = 0; i < slots.count; i++){
			NSArray *part = slots[i];
			if (!part.count)
				continue;   // an empty set keeps no header
			[sections addObject:[@{@"title"    : titles[i],
								   @"strip"    : @(i),
								   @"location" : @(flat.count),
								   @"length"   : @(part.count)} mutableCopy]];
			[flat addObjectsFromArray:part];
		}
		me.items = flat;
		me.sections = sections;
		[me setNeedsFeedRelayout];
	};

	// One request at a time, walking the strip order. The block clears itself
	// at the end, which is what releases it and the slots it holds.
	__block void (^next)(NSUInteger);
	next = ^(NSUInteger slot){
		TGEmojiPanel *me = weakSelf;
		if (!me || me.generation != generation || slot >= titles.count){
			next = nil;
			return;
		}
		void (^got)(NSArray *) = ^(NSArray *stickers){
			fill(slot, stickers);
			if (next)
				next(slot + 1);
		};
		if (slot == 0)
			[[TGClient shared] favoriteStickersWithCompletion:got];
		else if (slot == 1)
			[[TGClient shared] recentStickersWithCompletion:got];
		else
			[[TGClient shared] stickersInSet:me.stickerSets[slot - 2][@"id"] completion:got];
	};
	next(0);
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

/// Several sets answer in one run loop turn; lay out once for all of them.
- (void)setNeedsFeedRelayout {
	if (self.relayoutQueued)
		return;
	self.relayoutQueued = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		me.relayoutQueued = NO;
		[me reloadGrid];
	});
}

- (void)reloadGrid {
	for (UIView *view in [self.grid.subviews copy])
		if (view.tag == kHeaderTag)
			[view removeFromSuperview];
	for (UIButton *button in self.cells.allValues){
		[button removeFromSuperview];
		[self.pool addObject:button];
	}
	[self.cells removeAllObjects];
	[self.requested removeAllObjects];

	CGSize cell = [self cellSize];
	CGFloat w = self.grid.bounds.size.width;
	NSUInteger columns = MAX(1, (NSUInteger)floorf(w / cell.width));
	TGTheme *theme = [TGTheme shared];

	// Where each item lands. Without sections this is the plain grid; with
	// them every section starts on a fresh row under its own header.
	NSMutableArray *frames = [NSMutableArray arrayWithCapacity:self.items.count];
	CGFloat y = 0;
	if (self.sections.count){
		for (NSMutableDictionary *section in self.sections){
			section[@"headerY"] = @(y);
			UILabel *header = [[UILabel alloc] initWithFrame:
					CGRectMake(8, y + 4, w - 16, kHeaderHeight - 6)];
			header.tag = kHeaderTag;
			header.text = [section[@"title"] uppercaseString];
			header.font = [UIFont boldSystemFontOfSize:11];
			header.textColor = [theme secondaryTextColour];
			header.backgroundColor = [UIColor clearColor];
			[self.grid addSubview:header];
			y += kHeaderHeight;

			NSUInteger length = [section[@"length"] unsignedIntegerValue];
			for (NSUInteger i = 0; i < length; i++)
				[frames addObject:[NSValue valueWithCGRect:CGRectMake(
						(i % columns) * cell.width, y + (i / columns) * cell.height,
						cell.width, cell.height)]];
			y += ((length + columns - 1) / columns) * cell.height;
		}
	} else {
		for (NSUInteger i = 0; i < self.items.count; i++)
			[frames addObject:[NSValue valueWithCGRect:CGRectMake(
					(i % columns) * cell.width, (i / columns) * cell.height,
					cell.width, cell.height)]];
		y = ((self.items.count + columns - 1) / columns) * cell.height;
	}
	self.frames = frames;

	CGFloat previous = self.grid.contentOffset.y;
	self.grid.contentSize = CGSizeMake(w, y);
	// The feed fills in set by set, so keep where they are reading; only a
	// fresh grid starts at the top.
	CGFloat keep = self.sections.count ? MAX(0, MIN(previous, y - self.grid.bounds.size.height)) : 0;
	self.grid.contentOffset = CGPointMake(0, keep);
	self.emptyLabel.hidden = self.items.count > 0 || !self.emptyLabel.text.length;
	[self updateVisibleCells];
	[self syncStripToScroll];
}

/// Build what is on screen and one screen beyond, hand the rest back to the
/// pool. Called on every scroll, so it only ever touches the few cells that
/// crossed the edge.
- (void)updateVisibleCells {
	if (!self.frames.count)
		return;
	CGRect visible = self.grid.bounds;
	visible.origin.y -= visible.size.height / 2;
	visible.size.height *= 2;

	NSMutableArray *gone = [NSMutableArray array];
	for (NSNumber *key in self.cells){
		NSUInteger index = key.unsignedIntegerValue;
		if (index >= self.frames.count ||
			!CGRectIntersectsRect([self.frames[index] CGRectValue], visible))
			[gone addObject:key];
	}
	for (NSNumber *key in gone){
		UIButton *button = self.cells[key];
		[button removeFromSuperview];
		if (self.pool.count < 64)
			[self.pool addObject:button];
		[self.cells removeObjectForKey:key];
	}

	for (NSUInteger i = 0; i < self.frames.count; i++){
		CGRect frame = [self.frames[i] CGRectValue];
		if (!CGRectIntersectsRect(frame, visible))
			continue;
		if (self.cells[@(i)])
			continue;
		[self buildCellAtIndex:i frame:frame];
	}
	[self loadVisibleImages];
}

- (void)buildCellAtIndex:(NSUInteger)index frame:(CGRect)frame {
	TGTheme *theme = [TGTheme shared];
	UIButton *button = [self.pool lastObject];
	if (button){
		[self.pool removeLastObject];
	} else {
		button = [UIButton buttonWithType:UIButtonTypeCustom];
		[button addTarget:self action:@selector(itemTapped:)
			 forControlEvents:UIControlEventTouchUpInside];
		button.adjustsImageWhenHighlighted = YES;
		// On the button, not on the grid: a control inside a scroll view
		// takes the touch, and a recogniser on the scroller never saw it.
		[button addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(gridHeld:)]];
	}
	button.frame = frame;
	button.tag = kItemTagBase + (NSInteger)index;
	[button setTitle:nil forState:UIControlStateNormal];
	[button setImage:nil forState:UIControlStateNormal];
	UIImageView *tile = (UIImageView *)[button viewWithTag:1];
	tile.hidden = YES;
	tile.image = nil;

	id item = self.items[index];
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
			// The emoji stands in until the picture arrives - and for good,
			// for a sticker with no still thumbnail.
			button.titleLabel.font = [UIFont systemFontOfSize:36];
			[button setTitle:item[@"emoji"] forState:UIControlStateNormal];
		}
	} else {
		if (!tile){
			tile = [[UIImageView alloc] initWithFrame:CGRectZero];
			tile.contentMode = UIViewContentModeScaleAspectFill;
			tile.clipsToBounds = YES;
			tile.userInteractionEnabled = NO;
			tile.tag = 1;
			[button addSubview:tile];
		}
		tile.frame = CGRectInset(button.bounds, 1, 1);
		tile.backgroundColor = [theme fileTileColour];
		tile.hidden = NO;
		UIImage *cached = item[@"thumbId"] ? [TGPanelImageCache() objectForKey:item[@"thumbId"]] : nil;
		if (!cached && item[@"minithumbnail"])
			cached = [UIImage imageWithData:item[@"minithumbnail"]];
		tile.image = cached;
	}
	self.cells[@(index)] = button;
	[self.grid addSubview:button];
}

/// Which section the feed is showing now, lit up on the strip.
- (void)syncStripToScroll {
	if (!self.sections.count || self.syncingStrip)
		return;
	CGFloat top = self.grid.contentOffset.y + 1;
	NSInteger strip = self.stripIndex;
	for (NSDictionary *section in self.sections){
		if ([section[@"headerY"] floatValue] > top)
			break;
		strip = [section[@"strip"] integerValue];
	}
	if (strip == self.stripIndex)
		return;
	self.stripIndex = strip;
	[self updateStripHighlight];
}

/// Only the colours change as the feed scrolls. Rebuilding the strip for this
/// threw away the buttons the cover downloads were aimed at and asked for them
/// all over again - once per scroll event, which is what wedged the app.
- (void)updateStripHighlight {
	TGTheme *theme = [TGTheme shared];
	for (UIView *view in self.strip.subviews){
		if (![view isKindOfClass:UIButton.class])
			continue;
		UIButton *button = (UIButton *)view;
		BOOL on = button.tag == self.stripIndex;
		button.backgroundColor = on ? [theme actionTileBackgroundColour] : [UIColor clearColor];
		[button setTitleColor:on ? [theme accentColour] : [theme secondaryTextColour]
					 forState:UIControlStateNormal];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.grid){
		[self updateVisibleCells];
		[self syncStripToScroll];
	}
}

/// Thumbnails for what is on screen and a screen beyond it; the rest wait
/// until scrolled to, so opening a set of a hundred does not start a hundred
/// downloads.
- (void)loadVisibleImages {
	if (self.tab == TGEmojiPanelTabEmoji)
		return;
	for (NSNumber *key in [self.cells allKeys]){
		NSUInteger index = key.unsignedIntegerValue;
		if (index >= self.items.count || [self.requested containsObject:key])
			continue;
		[self.requested addObject:key];
		NSNumber *thumbId = self.items[index][@"thumbId"];
		if ([thumbId integerValue] <= 0 || [TGPanelImageCache() objectForKey:thumbId])
			continue;
		[self loadImageForFile:thumbId.integerValue into:self.cells[key] generation:self.generation];
	}
}

/// Download and decode a picture, then put it on the button (or the GIF
/// tile inside it). `generation` is NSNotFound for strip buttons, which do
/// not go stale with the grid.
- (void)loadImageForFile:(NSInteger)fileId into:(UIButton *)button generation:(NSUInteger)generation {
	UIImage *cached = [TGPanelImageCache() objectForKey:@(fileId)];
	__weak typeof(self) weakSelf = self;
	__weak UIButton *weakButton = button;
	// The cell this was asked for may have been recycled onto another sticker
	// by the time the picture arrives. Without this the wrong picture lands on
	// the button - and then tapping what you see sends something else.
	NSInteger expectedTag = button.tag;
	void (^apply)(UIImage *) = ^(UIImage *image){
		TGEmojiPanel *me = weakSelf;
		UIButton *target = weakButton;
		if (!me || !target || !image)
			return;
		if (generation != NSNotFound && generation != me.generation)
			return;
		if (target.tag != expectedTag)
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

/// Holding a sticker opens the same kind of card the rest of the app uses,
/// with the one thing that can be done to it from here.
- (void)gridHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan || self.tab != TGEmojiPanelTabStickers)
		return;
	UIButton *button = (UIButton *)hold.view;
	NSInteger index = button.tag - kItemTagBase;
	if (index < 0 || index >= (NSInteger)self.items.count){
		NSLog(@"TGEmojiPanel: hold on item %ld, out of %lu",
				(long)index, (unsigned long)self.items.count);
		return;
	}
	NSInteger fileId = [self.items[index][@"fileId"] integerValue];
	if (fileId <= 0){
		NSLog(@"TGEmojiPanel: hold on item %ld with no fileId", (long)index);
		return;
	}

	// Which section it came from decides what can be done to it.
	NSDictionary *section = [self sectionForItemIndex:index];
	NSInteger strip = section ? [section[@"strip"] integerValue] : -1;
	BOOL already = [self stickerIsFavourite:fileId];

	NSMutableArray *items = [NSMutableArray array];
	NSMutableArray *actions = [NSMutableArray array];
	[items addObject:(already
			? @{@"title" : @"Remove from Favourites", @"icon" : @"unpin", @"destructive" : @YES}
			: @{@"title" : @"Add to Favourites", @"icon" : @"pin"})];
	[actions addObject:already ? @"unfav" : @"fav"];

	if (strip == 1){   // Recently Used
		[items addObject:@{@"title" : @"Remove from Recent", @"icon" : @"delete",
						   @"destructive" : @YES}];
		[actions addObject:@"unrecent"];
	}
	if (strip >= 2 && (NSUInteger)(strip - 2) < self.stickerSets.count){
		[items addObject:@{@"title" : @"Remove Sticker Pack", @"icon" : @"delete",
						   @"destructive" : @YES}];
		[actions addObject:@"unset"];
	}

	UIView *host = self.window ?: (self.superview ?: self);
	CGPoint where = [self.grid convertPoint:button.center toView:host];
	self.menuOpenUntil = [NSDate timeIntervalSinceReferenceDate] + 1.0;
	NSLog(@"TGEmojiPanel: hold on %ld (file %ld, strip %ld), menu in %@",
			(long)index, (long)fileId, (long)strip, [host class]);

	id setId = (strip >= 2 && (NSUInteger)(strip - 2) < self.stickerSets.count)
			? self.stickerSets[strip - 2][@"id"] : nil;
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:host
				  onChoice:^(NSInteger choice, NSString *title){
		NSLog(@"TGEmojiPanel: menu chose %ld (%@)", (long)choice, title);
		if (choice < 0 || choice >= (NSInteger)actions.count)
			return;
		NSString *action = actions[choice];
		if ([action isEqualToString:@"fav"])
			[[TGClient shared] setSticker:fileId favourite:YES];
		else if ([action isEqualToString:@"unfav"])
			[[TGClient shared] setSticker:fileId favourite:NO];
		else if ([action isEqualToString:@"unrecent"])
			[[TGClient shared] removeRecentSticker:fileId];
		else if ([action isEqualToString:@"unset"])
			[[TGClient shared] removeStickerSet:setId];

		// The answers come back as updates the panel does not listen for, so
		// re-read the feed shortly after. A removed pack also changes the
		// strip, so the sets are asked for again with it.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			TGEmojiPanel *panel = weakSelf;
			if (panel && panel.tab == TGEmojiPanelTabStickers)
				[panel selectTab:TGEmojiPanelTabStickers];
		});
	}];
}

/// The section a flat index falls in, so a hold knows where it was made.
- (NSDictionary *)sectionForItemIndex:(NSInteger)index {
	for (NSDictionary *section in self.sections){
		NSInteger location = [section[@"location"] integerValue];
		NSInteger length = [section[@"length"] integerValue];
		if (index >= location && index < location + length)
			return section;
	}
	return nil;
}

/// Favourites is the first section of the feed, so what is in it is known
/// here without asking the server again.
- (BOOL)stickerIsFavourite:(NSInteger)fileId {
	for (NSDictionary *section in self.sections){
		if ([section[@"strip"] integerValue] != 0)
			continue;
		NSUInteger location = [section[@"location"] unsignedIntegerValue];
		NSUInteger length = [section[@"length"] unsignedIntegerValue];
		for (NSUInteger i = location; i < location + length && i < self.items.count; i++)
			if ([self.items[i][@"fileId"] integerValue] == fileId)
				return YES;
		return NO;
	}
	return NO;
}

- (void)itemTapped:(UIButton *)button {
	// A held sticker opens the card; the touch that ends the hold must not
	// also send it.
	if ([NSDate timeIntervalSinceReferenceDate] < self.menuOpenUntil)
		return;
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
	[self updateStripHighlight];
	[self loadItemsForStripIndex:self.stripIndex];
}

@end
