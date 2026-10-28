#import "TGEmojiPanel.h"
#import "TGEmojiData.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGPopupMenu.h"
#import "TGClient.h"
#import "UIImage+WebP.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGLottieView.h"
#import <objc/runtime.h>

static const char kTGItemDataKey = 0;

static inline void TGSetButtonItemData(UIButton *button, id item) {
	objc_setAssociatedObject(button, &kTGItemDataKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static inline id TGGetButtonItemData(UIButton *button) {
	return objc_getAssociatedObject(button, &kTGItemDataKey);
}

static const CGFloat kStripHeight = TGMetricEmojiStripHeight;   // categories / sets along the top
static const CGFloat kTabsHeight  = TGMetricEmojiTabsHeight;   // Emoji | Stickers | GIFs
static const CGFloat kEmojiCell   = TGMetricEmojiCell;
/// The backspace key at the end of the tab row, and the arrow drawn on it.
static const CGFloat kBackspaceWidth  = 46.0f;
static const CGFloat kBackspaceGlyphW = TGMetricBubbleDiscColumn;
static const CGFloat kBackspaceGlyphH = TGMetricStampTicksRoom;

static const NSInteger kItemTagBase = 1000;  // grid buttons carry their index
static const NSInteger kHeaderTag   = 900;   // a section title in the feed
static const CGFloat   kHeaderHeight = TGMetricEmojiHeader;
static const CGFloat   kPreviewHeaderWidth = 240.0f;
static const CGFloat   kPreviewHeaderHeight = 130.0f;
static const CGFloat   kPreviewSide = 110.0f;

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
	CGSize size = CGSizeMake(kBackspaceGlyphW, kBackspaceGlyphH);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
	CGContextSetLineWidth(ctx, TGMetricStrokeIcon);
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

@interface TGEmojiPanel () <UIScrollViewDelegate>
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
/// An emoji the sticker tab is searching for, or nil for the usual feed of
/// favourites, recents and installed sets.
@property (nonatomic, strong) NSString *stickerQuery;
/// Bumped every time the grid is rebuilt, so an answer for an older grid
/// is dropped rather than drawn into the wrong cell.
@property (nonatomic, assign) NSUInteger generation;
// A set pill being dragged along the strip: where the finger grabbed it,
// and the frame it lifted from.
@property (nonatomic, assign) CGFloat stickerDragOffset;
@property (nonatomic, assign) CGRect stickerDragFrame;
@end

@implementation TGEmojiPanel

+ (CGFloat)preferredHeight {
	return TGMetricEmojiPanelHeight;
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

	self.stripLine = [[UIView alloc] initWithFrame:CGRectMake(0, kStripHeight - TGMetricHairline, w, TGMetricHairline)];
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
	self.emptyLabel.font = TGFontBody();
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.numberOfLines = 2;
	self.emptyLabel.hidden = YES;
	[self addSubview:self.emptyLabel];

	self.tabs = [[UIView alloc] initWithFrame:CGRectMake(0, h - kTabsHeight, w, kTabsHeight)];
	self.tabs.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	[self addSubview:self.tabs];

	self.tabsLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, TGMetricHairline)];
	self.tabsLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.tabs addSubview:self.tabsLine];

	NSArray *titles = @[@"Emoji", @"Stickers", @"GIFs"];
	NSMutableArray *buttons = [NSMutableArray array];
	CGFloat tabW = TGMetricChatRow;
	CGFloat x = TGCenteredOrigin(w, tabW * titles.count);
	for (NSUInteger i = 0; i < titles.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x + tabW * i, 0, tabW, kTabsHeight);
		button.tag = (NSInteger)i;
		button.titleLabel.font = TGFontSubheadStrong();
		button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		[button setTitle:titles[i] forState:UIControlStateNormal];
		[button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.tabs addSubview:button];
		[buttons addObject:button];
	}
	self.tabButtons = buttons;

	self.backspace = [UIButton buttonWithType:UIButtonTypeCustom];
	self.backspace.frame = CGRectMake(w - kBackspaceWidth, 0, kBackspaceWidth, kTabsHeight);
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
	self.stickerQuery = nil;
	self.backspace.hidden = tab != TGEmojiPanelTabEmoji;
	self.items = @[];
	self.sections = nil;
	[self reloadGrid];
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
	} else {
		[self reloadStrip];
		[self loadItemsForStripIndex:0];
	}
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
			// The magnifier first, as their panel has it: the sets that
			// follow are an index into one feed, and a search replaces it.
			NSMutableArray *out = [NSMutableArray arrayWithObjects:
					@{@"glyph" : @"search"}, @{@"glyph" : @"star"},
					@{@"glyph" : @"recent"}, nil];
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
		button.frame = CGRectMake(x, TGMetricBubbleRowInset, width,
				kStripHeight - TGDoubled(TGMetricBubbleRowInset));
		button.tag = (NSInteger)i;
		button.layer.cornerRadius = TGMetricCornerMedium;
		button.backgroundColor = (NSInteger)i == self.stripIndex
				? [theme actionTileBackgroundColour] : [UIColor clearColor];
		if (entry[@"title"]){
			button.titleLabel.font = TGFontSubhead();
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
											side:TGMetricMenuGlyph]
					forState:UIControlStateNormal];
		} else {
			button.titleLabel.font = TGFontEmojiSmall();
			[button setTitle:entry[@"emoji"] forState:UIControlStateNormal];
		}
		[button addTarget:self action:@selector(stripTapped:) forControlEvents:UIControlEventTouchUpInside];
		// A set can be picked up and put elsewhere: held, it follows the
		// finger, and a drop right of its neighbours is the new installed
		// order. Favourites, recents, the magnifier stay put - they are
		// panels of the strip, not part of the installed order.
		if (self.tab == TGEmojiPanelTabStickers && (NSInteger)i >= 3){
			UILongPressGestureRecognizer *drag = [[UILongPressGestureRecognizer alloc]
					initWithTarget:self action:@selector(stickerSetDragged:)];
			drag.minimumPressDuration = 0.45;
			[button addGestureRecognizer:drag];
		}
		[self.strip addSubview:button];

		NSNumber *thumbId = entry[@"thumbId"];
		if (thumbId)
			[self loadImageForFile:thumbId.integerValue into:button generation:NSNotFound];
		x += width + 2;
	}
	self.strip.contentSize = CGSizeMake(x + TGMetricPadSmall, kStripHeight);
}

- (void)stripTapped:(UIButton *)button {
	if (self.tab == TGEmojiPanelTabGIFs && button.tag == 1){
		[self askForGifSearch];
		return;
	}
	if (self.tab == TGEmojiPanelTabStickers && button.tag == 0){
		[self askForStickerSearch];
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

/// A held set pill follows the finger along the strip; where it drops is
/// its slot in the installed order. The strip's own scrolling is pinned
/// shut while the pill is up, one finger cannot steer a pill and pan a
/// scrollview at once - the same school of geometry the folder strip's
/// drag learned the hard way.
- (void)stickerSetDragged:(UILongPressGestureRecognizer *)gesture {
	UIButton *pill = (UIButton *)gesture.view;
	UIScrollView *strip = (UIScrollView *)pill.superview;
	if (![strip isKindOfClass:UIScrollView.class] ||
			self.tab != TGEmojiPanelTabStickers || pill.tag < 3)
		return;

	if (gesture.state == UIGestureRecognizerStateBegan){
		CGPoint here = [gesture locationInView:pill];
		self.stickerDragOffset = here.x - TGHalf(pill.bounds.size.width);
		self.stickerDragFrame = pill.frame;
		self.strip.scrollEnabled = NO;
		pill.transform = CGAffineTransformMakeScale(TGTransformScalePillActive, TGTransformScalePillActive);
		pill.alpha = TGAlphaPillInactive;
	}
	else if (gesture.state == UIGestureRecognizerStateChanged){
		CGPoint here = [gesture locationInView:strip];
		// Content coordinates, the strip's own currency: the frame lives
		// in them and the finger's press point rides along.
		CGFloat x = here.x - strip.contentOffset.x - self.stickerDragOffset;
		CGFloat first = TGMetricPadSmall, last = strip.contentSize.width
				- self.stickerDragFrame.size.width - TGMetricPadSmall;
		if (x < first) x = first;
		if (x > last)  x = last;
		pill.frame = CGRectMake(x, self.stickerDragFrame.origin.y,
				self.stickerDragFrame.size.width,
				self.stickerDragFrame.size.height);
	}
	else if (gesture.state == UIGestureRecognizerStateEnded ||
			 gesture.state == UIGestureRecognizerStateCancelled){
		strip.scrollEnabled = YES;
		pill.transform = CGAffineTransformIdentity;
		pill.alpha = TGAlphaOpaque;

		NSInteger from = pill.tag - 3;
		NSArray *sets = self.stickerSets;
		if (gesture.state == UIGestureRecognizerStateCancelled ||
				from < 0 || from >= (NSInteger)sets.count)
			return;   // reloadStrip puts the pill back where the data says

		// The slot is what the pill's centre cleared on the way over:
		// every other set pill it passed counts one slot ahead.
		CGPoint here = [gesture locationInView:strip];
		CGFloat centre = here.x - strip.contentOffset.x;
		NSInteger slot = 0;
		for (UIView *view in strip.subviews){
			if (![view isKindOfClass:UIButton.class])
				continue;
			NSInteger tag = view.tag;
			if (tag < 3 || tag - 3 == from)
				continue;
			if (view.center.x < centre)
				slot++;
		}
		if (slot == from)
			return;   // a hand back down on its own slot

		// Whatever pill is lit stays lit, even after the tags have moved
		// underneath it: the selection belongs to the set, not the index.
		NSDictionary *selected = nil;
		NSInteger selectedSet = self.stripIndex - 3;
		if (selectedSet >= 0 && selectedSet < (NSInteger)sets.count)
			selected = sets[selectedSet];

		NSMutableArray *order = [NSMutableArray array];
		[sets enumerateObjectsUsingBlock:^(NSDictionary *set, NSUInteger idx,
										   BOOL *stop __unused){
			if ((NSInteger)idx != from)
				[order addObject:set];
		}];
		[order insertObject:sets[from] atIndex:MIN(slot, (NSInteger)order.count)];

		// Local first: the strip re-renders off stickerSets, so a change
		// that only went to TDLib would snap the pills back mid-flight.
		self.stickerSets = order;
		if (selected){
			NSInteger found = (NSInteger)[order indexOfObject:selected];
			if (found != NSNotFound)
				self.stripIndex = found + 3;
		}
		[self reloadStrip];

		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *set in order)
			if (set[@"id"])
				[ids addObject:set[@"id"]];
		[[TGClient shared] reorderInstalledStickerSets:ids];
	}
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
			// A search is the exception - it puts its results there instead.
			if (self.stickerQuery.length)
				[self loadStickerSearch];
			else
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
/// Stickers for an emoji: the installed sets first, because those are the
/// ones already on the phone, then everything public under them.
- (void)loadStickerSearch {
	self.generation++;
	NSUInteger generation = self.generation;
	NSString *query = self.stickerQuery;

	self.items = @[];
	self.sections = nil;
	self.emptyLabel.text = @"Searching...";
	[self reloadGrid];

	__weak typeof(self) weakSelf = self;
	__block NSArray *mine = @[];
	__block NSArray *everywhere = @[];
	__block NSArray *packs = @[];
	__block NSUInteger left = 3;

	void (^show)(void) = ^{
		TGEmojiPanel *me = weakSelf;
		if (!me || me.generation != generation || --left > 0)
			return;

		NSMutableArray *flat = [NSMutableArray array];
		NSMutableArray *sections = [NSMutableArray array];
		// A pack tile carries a pack, not a sticker: it is its own section,
		// and strip -9 is no strip's slot, so the highlight stays on the pill
		// already lit.
		NSArray *parts = @[mine, everywhere, packs];
		NSArray *titles = @[@"Yours", @"All stickers", @"Packs"];
		for (NSUInteger i = 0; i < parts.count; i++){
			NSArray *part = parts[i];
			if (!part.count)
				continue;
			[sections addObject:[@{@"title"    : titles[i],
								   @"strip"    : (i == 2 ? @(-9) : @(0)),
								   @"location" : @(flat.count),
								   @"length"   : @(part.count)} mutableCopy]];
			[flat addObjectsFromArray:part];
		}
		me.items = flat;
		me.sections = sections;
		me.emptyLabel.text = [NSString stringWithFormat:@"No stickers for %@", query];
		[me setNeedsFeedRelayout];
	};

	[[TGClient shared] stickersForEmoji:query completion:^(NSArray *stickers){
		mine = stickers ?: @[];
		show();
	}];
	[[TGClient shared] searchStickersForEmoji:query completion:^(NSArray *stickers){
		// What is already in "Yours" is not worth a second tile.
		NSMutableSet *known = [NSMutableSet set];
		for (NSDictionary *sticker in mine)
			if (sticker[@"fileId"])
				[known addObject:sticker[@"fileId"]];
		NSMutableArray *rest = [NSMutableArray array];
		for (NSDictionary *sticker in (stickers ?: @[]))
			if (![known containsObject:sticker[@"fileId"]])
				[rest addObject:sticker];
		everywhere = rest;
		show();
	}];

	// The word side of the query finds packs: a search meant to install
	// something ends here, given the same query TDLib's set search also
	// takes. Each entry carries the whole record the install sheet needs -
	// id, count, covers, and whether it is already installed.
	[[TGClient shared] searchStickerSetsNamed:query completion:^(NSArray *sets){
		NSMutableArray *found = [NSMutableArray array];
		for (NSDictionary *set in (sets ?: @[])){
			if (![set isKindOfClass:NSDictionary.class] || !set[@"id"])
				continue;
			NSMutableDictionary *tile = [NSMutableDictionary dictionary];
			tile[@"pack"] = set;
			NSDictionary *cover = set[@"cover"];
			NSString *icon = cover[@"emoji"];
			if ([icon length])
				tile[@"emoji"] = icon;
			else if ([set[@"title"] length])
				tile[@"emoji"] = [set[@"title"] substringToIndex:1];
			NSNumber *thumbId = cover[@"thumbId"];
			if ([thumbId isKindOfClass:NSNumber.class])
				tile[@"thumbId"] = thumbId;
			[found addObject:tile];
		}
		packs = found;
		show();
	}];
}

/// An emoji rather than a word: that is what TDLib searches stickers by, and
/// saying so in the sheet saves a round of confusion.
- (void)askForStickerSearch {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Search Stickers"
					message:@"By emoji - the one a sticker is filed under."
				placeholder:@"\U0001F603"
					   text:self.stickerQuery
					 action:@"Search"
					 inView:(self.window ?: self)
				   onSubmit:^(NSString *query){
		TGEmojiPanel *panel = weakSelf;
		panel.stickerQuery = query.length ? query : nil;
		panel.stripIndex = 0;
		[panel updateStripHighlight];
		[panel loadItemsForStripIndex:0];
	}];
}

- (void)loadStickerFeed {
	self.generation++;
	NSUInteger generation = self.generation;

	// Strip slot 0 is the magnifier, so the feed's own sections start at 1.
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
								   @"strip"    : @(i + 1),
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
			return CGSizeMake(side, floorf(side * TGMetricGIFCellAspect));
		}
	}
	return CGSizeMake(kEmojiCell, kEmojiCell);
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
					CGRectMake(TGMetricPad, y + TGMetricPadSmall, w - TGDoubled(TGMetricPad),
					kHeaderHeight - TGDoubled(TGMetricBubbleRowInset))];
			header.tag = kHeaderTag;
			header.text = [section[@"title"] uppercaseString];
			header.font = TGFontMicroStrong();
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
	visible.origin.y -= TGHalf(visible.size.height);
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
	id item = (index < self.items.count) ? self.items[index] : nil;
	TGSetButtonItemData(button, item);
	[button setTitle:nil forState:UIControlStateNormal];
	[button setImage:nil forState:UIControlStateNormal];
	UIImageView *tile = (UIImageView *)[button viewWithTag:1];
	tile.hidden = YES;
	tile.image = nil;

	if (self.tab == TGEmojiPanelTabEmoji){
		button.titleLabel.font = TGFontEmoji();
		NSString *str = [item isKindOfClass:NSString.class] ? (NSString *)item : @"";
		[button setTitle:str forState:UIControlStateNormal];
	} else if (self.tab == TGEmojiPanelTabStickers){
		button.imageEdgeInsets = UIEdgeInsetsMake(TGMetricAlertTextGap, TGMetricAlertTextGap, TGMetricAlertTextGap, TGMetricAlertTextGap);
		button.imageView.contentMode = UIViewContentModeScaleAspectFit;
		NSDictionary *dict = [item isKindOfClass:NSDictionary.class] ? (NSDictionary *)item : nil;
		UIImage *cached = dict[@"thumbId"] ? [TGPanelImageCache() objectForKey:dict[@"thumbId"]] : nil;
		if (cached)
			[button setImage:cached forState:UIControlStateNormal];
		else {
			// The emoji stands in until the picture arrives - and for good,
			// for a sticker with no still thumbnail.
			button.titleLabel.font = TGFontEmojiLarge();
			[button setTitle:dict[@"emoji"] ?: @"" forState:UIControlStateNormal];
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
		NSDictionary *dict = [item isKindOfClass:NSDictionary.class] ? (NSDictionary *)item : nil;
		UIImage *cached = dict[@"thumbId"] ? [TGPanelImageCache() objectForKey:dict[@"thumbId"]] : nil;
		if (!cached && dict[@"minithumbnail"])
			cached = [UIImage imageWithData:dict[@"minithumbnail"]];
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
		id rawItem = self.items[index];
		if (![rawItem isKindOfClass:NSDictionary.class])
			continue;
		NSNumber *thumbId = rawItem[@"thumbId"];
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

/// Holding a sticker or a GIF opens the same kind of card the rest of the
/// app uses, with the things that can be done to it from here.
- (void)gridHeld:(UILongPressGestureRecognizer *)hold {
	BOOL isSticker = self.tab == TGEmojiPanelTabStickers;
	BOOL isGif = self.tab == TGEmojiPanelTabGIFs;
	if (hold.state != UIGestureRecognizerStateBegan || (!isSticker && !isGif))
		return;
	UIButton *button = (UIButton *)hold.view;
	id item = TGGetButtonItemData(button);
	NSInteger index = button.tag - kItemTagBase;
	if (!item && index >= 0 && index < (NSInteger)self.items.count)
		item = self.items[index];
	if (!item) return;

	NSInteger fileId = [item[@"fileId"] integerValue];
	if (fileId <= 0){
		NSLog(@"TGEmojiPanel: hold on item with no fileId");
		return;
	}

	// Which section it came from decides what can be done to it.
	NSDictionary *section = isSticker ? [self sectionForItemIndex:index] : nil;
	NSInteger strip = section ? [section[@"strip"] integerValue] : -1;

	NSMutableArray *items = [NSMutableArray array];
	NSMutableArray *actions = [NSMutableArray array];

	if (isGif){
		// The un-searched feed is the saved shelf; results of a query are
		// strangers until they are saved.
		BOOL inSaved = self.gifQuery.length == 0;
		[items addObject:(inSaved
				? @{@"title" : @"Remove from Saved GIFs", @"icon" : @"delete",
					@"destructive" : @YES}
				: @{@"title" : @"Save GIF", @"icon" : @"star"})];
		[actions addObject:inSaved ? @"unsavegif" : @"savegif"];
	}
	else {
		BOOL already = [self stickerIsFavourite:fileId];
		[items addObject:(already
				? @{@"title" : @"Remove from Favourites", @"icon" : @"unpin",
					@"destructive" : @YES}
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
	}

	UIView *host = self.window ?: (self.superview ?: self);
	CGPoint where = [self.grid convertPoint:button.center toView:host];
	self.menuOpenUntil = [NSDate timeIntervalSinceReferenceDate] + 1.0;

	// Floating preview card header inside TGPopupMenu
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(TGMetricZero, TGMetricZero, kPreviewHeaderWidth, kPreviewHeaderHeight)];
	header.backgroundColor = [UIColor clearColor];

	CGFloat pSide = kPreviewSide;
	CGRect pFrame = CGRectMake(TGCenteredOrigin(kPreviewHeaderWidth, pSide),
							   TGCenteredOrigin(kPreviewHeaderHeight, pSide),
							   pSide, pSide);

	BOOL isAnimated = [item[@"isAnimated"] boolValue] || [item[@"docName"] isEqualToString:@"tgs"];
	if (isAnimated) {
		TGLottieView *lottie = [[TGLottieView alloc] initWithFrame:pFrame];
		UIImageView *thumb = [[UIImageView alloc] initWithFrame:pFrame];
		thumb.contentMode = UIViewContentModeScaleAspectFit;
		UIImage *cached = item[@"thumbId"] ? [TGPanelImageCache() objectForKey:item[@"thumbId"]] : nil;
		if (cached) thumb.image = cached;
		[header addSubview:thumb];
		[header addSubview:lottie];

		[[TGClient shared] downloadFile:fileId priority:TGDownloadPriorityOnScreen completion:^(NSString *path){
			if (!path) return;
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([lottie loadTGSFile:path]) {
					thumb.hidden = YES;
					[lottie play];
				}
			});
		}];
	} else {
		UIImageView *preview = [[UIImageView alloc] initWithFrame:pFrame];
		preview.contentMode = UIViewContentModeScaleAspectFit;
		UIImage *cached = item[@"thumbId"] ? [TGPanelImageCache() objectForKey:item[@"thumbId"]] : nil;
		if (!cached && item[@"minithumbnail"])
			cached = [UIImage imageWithData:item[@"minithumbnail"]];
		if (cached) preview.image = cached;
		[header addSubview:preview];

		[[TGClient shared] downloadFile:fileId priority:TGDownloadPriorityOnScreen completion:^(NSString *path){
			if (!path) return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *img = TGPanelDecode(path);
				if (img) {
					dispatch_async(dispatch_get_main_queue(), ^{
						preview.image = img;
					});
				}
			});
		}];
	}

	id setId = (isSticker && strip >= 2 && (NSUInteger)(strip - 2) < self.stickerSets.count)
			? self.stickerSets[strip - 2][@"id"] : nil;
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:host headerView:header
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
			[[TGClient shared] setStickerSet:setId installed:NO archived:NO];
		else if ([action isEqualToString:@"savegif"])
			[[TGClient shared] saveAnimationFileId:fileId saved:YES];
		else if ([action isEqualToString:@"unsavegif"])
			[[TGClient shared] saveAnimationFileId:fileId saved:NO];

		// The answers come back as updates the panel does not listen for, so
		// re-read the feed shortly after. A removed pack also changes the
		// strip, so the sets are asked for again with it.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			TGEmojiPanel *panel = weakSelf;
			if (panel && (panel.tab == TGEmojiPanelTabStickers ||
						  panel.tab == TGEmojiPanelTabGIFs))
				[panel selectTab:panel.tab];
		});
	}];
}

/// A pack found by search, installed on one confirm. The answer comes back
/// as an update the panel does not listen for, so the shelf is re-read
/// shortly after - one highlight's length, the same beat the hold menu uses.
- (void)askInstallForStickerSet:(NSDictionary *)set {
	NSString *title = [set[@"title"] length] ? set[@"title"] : @"This pack";
	NSString *counted = [NSString stringWithFormat:@"%@ - %lu stickers",
			title, (unsigned long)[set[@"count"] unsignedIntegerValue]];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Install", @"Not now"]
						title:counted
			  destructiveIndex:-1
						inView:(self.window ?: self)
					  onChoice:^(NSInteger index){
		TGEmojiPanel *panel = weakSelf;
		if (index != 0 || !panel)
			return;
		[[TGClient shared] setStickerSet:set[@"id"] installed:YES archived:NO];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
				(int64_t)(TGAnimationDurationHighlight * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			[weakSelf selectTab:TGEmojiPanelTabStickers];
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
	id item = TGGetButtonItemData(button);
	if (!item && index >= 0 && index < (NSInteger)self.items.count)
		item = self.items[index];
	if (!item)
		return;
	switch (self.tab){
		case TGEmojiPanelTabEmoji:
			TGNoteEmojiUsed(item);
			[self.delegate emojiPanel:self didPickEmoji:item];
			break;
		case TGEmojiPanelTabStickers:
			// A pack tile installs the pack; picking a sticker sends it.
			if ([item isKindOfClass:NSDictionary.class] && item[@"pack"]){
				[self askInstallForStickerSet:item[@"pack"]];
				return;
			}
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
/// standing in for, so the query is asked for in a sheet of its own.
- (void)askForGifSearch {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Search GIFs"
					message:nil
				placeholder:@"GIF"
					   text:self.gifQuery
					 action:@"Search"
					 inView:(self.window ?: self)
				   onSubmit:^(NSString *query){
		TGEmojiPanel *panel = weakSelf;
		panel.gifQuery = query.length ? query : nil;
		panel.stripIndex = panel.gifQuery ? 1 : 0;
		[panel updateStripHighlight];
		[panel loadItemsForStripIndex:panel.stripIndex];
	}];
}

@end
