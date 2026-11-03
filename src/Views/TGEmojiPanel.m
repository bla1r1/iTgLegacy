#import "TGEmojiPanel.h"
#import "TGEmojiData.h"
#import "TGEmojiStore.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGPopupMenu.h"
#import "TGStickerStore.h"
#import "TGClientNotifications.h"
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

/// A set row as the search feed draws it: the tile carries the whole record
/// so the install sheet has the id and the count, and a cover to show.
static NSArray *TGPackSearchTiles(NSArray *sets) {
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
	return found;
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
/// The emoji card's header is the glyph alone; an animation preview adds a
/// caption line under the renderer.
static const CGFloat   kEmojiCardHeaderHeight = 100.0f;
static const CGFloat   kEmojiPreviewHeaderHeight = 150.0f;
static const CGFloat   kEmojiPreviewCaptionHeight = 24.0f;

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

@property (nonatomic, strong) NSArray *stickerSets;      // installed, as the store gives them
@property (nonatomic, strong) NSString *gifQuery;        // nil for the saved ones
/// Telegram's categories once they have arrived. Empty means the built-in set
/// from TGEmojiData is still what the strip draws.
@property (nonatomic, strong) NSArray *serverCategories;
/// The word the emoji tab is searching for, or nil for the category grid.
@property (nonatomic, strong) NSString *emojiQuery;
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

+ (void)initialize {
	if (self != [TGEmojiPanel class])
		return;
	// The decoded-thumbnail cache is keyed by TDLib file id, so one id names a
	// different picture after an account switch. The cache is a file-scope
	// static shared by every panel, so it is emptied when the account changes
	// instead of drawing the previous account's sticker under a new one.
	[[NSNotificationCenter defaultCenter]
			addObserverForName:TGAccountDidSwitchNotification
						object:nil queue:[NSOperationQueue mainQueue]
				 usingBlock:^(NSNotification *note){
		[TGPanelImageCache() removeAllObjects];
	}];
}

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
	// A set installed, a GIF saved or a sticker favourited on another client
	// lands here; the tab is re-asked rather than latched until it is reopened.
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(stickerListsChanged)
				name:TGStickerListsChangedNotification object:nil];
	[self applyTheme];
	[self selectTab:TGEmojiPanelTabEmoji];
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

/// Installing a set fires one update per list it touches, so the re-read waits
/// out the burst. The emoji tab reads none of these lists.
- (void)stickerListsChanged {
	if (self.tab == TGEmojiPanelTabEmoji)
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(reselectCurrentTab) object:nil];
	[self performSelector:@selector(reselectCurrentTab) withObject:nil afterDelay:0.3];
}

- (void)reselectCurrentTab {
	[self selectTab:self.tab];
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
	self.emojiQuery = nil;
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

	// Telegram's categories describe the strip better than the built-in list
	// when the file database has them. The first draw keeps the built-in set;
	// the answer rebuilds the strip when it lands.
	if (tab == TGEmojiPanelTabEmoji)
		[self loadEmojiCategoriesIfNeeded];

	// Asked for every time the tab is opened, not once: Favourites and the
	// installed sets change from other clients, and a latched list never
	// caught up. The feed is rebuilt once they land - the first build only
	// has Favourites and Recently Used, because the sets are not here yet.
	if (tab == TGEmojiPanelTabStickers){
		__weak typeof(self) weakSelf = self;
		[[TGStickerStore shared] installedStickerSetsWithCompletion:^(NSArray *sets){
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

/// The categories the emoji tab draws. Telegram's list is only useful when
/// its source carries emoji this account may search for; a premium shelf has
/// no list and would be an empty tab, so it stays out.
- (NSArray *)emojiCategories {
	if (!self.serverCategories.count)
		return TGEmojiCategories();
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *category in self.serverCategories){
		NSArray *emojis = category[@"emojis"];
		if (![emojis isKindOfClass:NSArray.class] || !emojis.count)
			continue;
		[out addObject:category];
	}
	return out.count ? out : TGEmojiCategories();
}

/// Asked on every visit to the tab, answered from the store's cache after the
/// first one. An empty answer keeps the built-in list on screen.
- (void)loadEmojiCategoriesIfNeeded {
	__weak typeof(self) weakSelf = self;
	[[TGEmojiStore shared] categoriesWithCompletion:^(NSArray *categories){
		TGEmojiPanel *me = weakSelf;
		if (!me || me.tab != TGEmojiPanelTabEmoji || !categories.count)
			return;
		me.serverCategories = categories;
		[me reloadStrip];
		if (!me.emojiQuery.length)
			[me loadItemsForStripIndex:me.stripIndex];
	}];
}

/// The strip entries for the current tab: each is @{"title" or "emoji" or
/// "thumbId"}. Emoji: Recent, the search, then the categories. Stickers:
/// Recent, Favourites, then each installed set. GIFs: Saved and Search.
- (NSArray *)stripEntries {
	switch (self.tab){
		case TGEmojiPanelTabEmoji: {
			// Recent and the magnifier stay put; the categories after them are
			// Telegram's when it answered and the built-in set until then.
			NSMutableArray *out = [NSMutableArray arrayWithObjects:
					@{@"glyph" : @"recent"}, @{@"glyph" : @"search"}, nil];
			for (NSDictionary *category in [self emojiCategories])
				[out addObject:@{@"emoji" : category[@"icon"] ?: @""}];
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
	if (self.tab == TGEmojiPanelTabEmoji && button.tag == 1){
		[self askForEmojiSearch];
		return;
	}
	if (self.tab == TGEmojiPanelTabEmoji && button.tag != 1)
		self.emojiQuery = nil;   // a category leaves the search behind
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
		[[TGStickerStore shared] reorderInstalledStickerSets:ids];
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
			NSArray *categories = [self emojiCategories];
			if (index == 0)
				show(TGRecentEmoji(), nil);
			else if (index == 1)
				[self loadEmojiSearch];
			else if (index - 2 < (NSInteger)categories.count){
				NSDictionary *category = categories[index - 2];
				// Telegram's rows carry "emojis"; the built-in set from
				// TGEmojiData calls the same list "emoji".
				NSArray *emojis = category[@"emojis"] ?: category[@"emoji"];
				show(emojis, nil);
			}
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
				[[TGStickerStore shared] searchAnimations:self.gifQuery inChat:self.chatId completion:got];
			else
				[[TGStickerStore shared] savedAnimationsWithCompletion:got];
			break;
		}
	}
}

/// Both halves of an emoji search: TDLib's keyword suggestions and the
/// emoji search itself. They land as two sections so the row that says why
/// an emoji matched stays visible instead of being flattened away.
- (void)loadEmojiSearch {
	self.generation++;
	NSUInteger generation = self.generation;
	NSString *query = self.emojiQuery;
	if (!query.length){
		self.items = @[];
		self.sections = nil;
		self.emptyLabel.text = @"Search emoji by word";
		[self reloadGrid];
		return;
	}

	self.items = @[];
	self.sections = nil;
	self.emptyLabel.text = @"Searching...";
	[self reloadGrid];

	__weak typeof(self) weakSelf = self;
	__block NSArray *suggested = @[];
	__block NSArray *found = @[];
	__block NSUInteger left = 2;

	void (^show)(void) = ^{
		TGEmojiPanel *me = weakSelf;
		if (!me || me.generation != generation || --left > 0)
			return;

		NSMutableArray *flat = [NSMutableArray array];
		NSMutableArray *sections = [NSMutableArray array];
		NSArray *parts = @[suggested, found];
		NSArray *titles = @[@"Suggested", @"Results"];
		for (NSUInteger i = 0; i < parts.count; i++){
			NSArray *part = parts[i];
			if (!part.count)
				continue;
			[sections addObject:[@{@"title"    : titles[i],
								   @"strip"    : @(-9),
								   @"location" : @(flat.count),
								   @"length"   : @(part.count)} mutableCopy]];
			[flat addObjectsFromArray:part];
		}
		me.items = flat;
		me.sections = sections;
		me.emptyLabel.text = flat.count
				? nil : [NSString stringWithFormat:@"No emoji for %@", query];
		[me setNeedsFeedRelayout];
	};

	[[TGEmojiStore shared] keywordEmojis:query completion:^(NSArray *emojis){
		suggested = emojis ?: @[];
		show();
	}];
	[[TGEmojiStore shared] searchEmojis:query completion:^(NSArray *emojis){
		found = emojis ?: @[];
		show();
	}];
}

/// The panel stands in for the keyboard, so a field would raise it. The
/// query is asked for in the app's own sheet, as the sticker and GIF tabs do.
- (void)askForEmojiSearch {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Search Emoji"
					message:@"A word, or an emoji to see what it is filed under."
				placeholder:@"\U0001F603"
					   text:self.emojiQuery
					 action:@"Search"
					 inView:(self.window ?: self)
				   onSubmit:^(NSString *query){
		TGEmojiPanel *panel = weakSelf;
		NSString *what = [query stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		panel.emojiQuery = what.length ? what : nil;
		panel.stripIndex = panel.emojiQuery ? 1 : 0;
		[panel updateStripHighlight];
		[panel loadItemsForStripIndex:panel.stripIndex];
	}];
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
	__block NSArray *minePacks = @[];
	__block NSArray *trending = @[];
	__block NSUInteger left = 5;

	void (^show)(void) = ^{
		TGEmojiPanel *me = weakSelf;
		if (!me || me.generation != generation || --left > 0)
			return;

		NSMutableArray *flat = [NSMutableArray array];
		NSMutableArray *sections = [NSMutableArray array];
		// A pack tile carries a pack, not a sticker: it is its own section,
		// and strip -9 is no strip's slot, so the highlight stays on the pill
		// already lit. A query that finds no pack at all falls back to what
		// is popular, which is the only way the shelf advertises anything.
		NSArray *packRows = packs.count ? packs : trending;
		NSString *packTitle = packs.count ? @"Packs" : @"Trending";
		NSArray *parts = @[mine, everywhere, minePacks, packRows];
		NSArray *titles = @[@"Yours", @"All stickers", @"Your packs", packTitle];
		for (NSUInteger i = 0; i < parts.count; i++){
			NSArray *part = parts[i];
			if (!part.count)
				continue;
			[sections addObject:[@{@"title"    : titles[i],
								   @"strip"    : (i >= 2 ? @(-9) : @(0)),
								   @"location" : @(flat.count),
								   @"length"   : @(part.count)} mutableCopy]];
			[flat addObjectsFromArray:part];
		}
		me.items = flat;
		me.sections = sections;
		me.emptyLabel.text = [NSString stringWithFormat:@"No stickers for %@", query];
		[me setNeedsFeedRelayout];
	};

	[[TGStickerStore shared] stickersForEmoji:query completion:^(NSArray *stickers){
		mine = stickers ?: @[];
		show();
	}];
	[[TGStickerStore shared] searchStickersForEmoji:query completion:^(NSArray *stickers){
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
	[[TGStickerStore shared] searchStickerSetsNamed:query completion:^(NSArray *sets){
		packs = TGPackSearchTiles(sets);
		show();
	}];

	// The half of the search that answers "I already have this": the same
	// query over the installed shelf, shown before the public results.
	[[TGStickerStore shared] installedStickerSetsNamed:query completion:^(NSArray *sets){
		minePacks = TGPackSearchTiles(sets);
		show();
	}];

	[[TGStickerStore shared] trendingStickerSetsWithCompletion:^(NSArray *sets){
		trending = TGPackSearchTiles(sets);
		// The shelf is on screen now, so it is seen: Telegram drops what has
		// been viewed from the next recommendation. This is the write half of
		// the trending read, and it belongs where the read is drawn.
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *set in (sets ?: @[]))
			if (set[@"id"])
				[ids addObject:set[@"id"]];
		[[TGStickerStore shared] viewTrendingStickerSets:ids];
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
			[[TGStickerStore shared] favoriteStickersWithCompletion:got];
		else if (slot == 1)
			[[TGStickerStore shared] recentStickersWithCompletion:got];
		else
			[[TGStickerStore shared] stickersInSet:me.stickerSets[slot - 2][@"id"] completion:got];
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
	[[TGStickerStore shared] downloadFile:fileId completion:^(NSString *path){
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
	BOOL isEmoji = self.tab == TGEmojiPanelTabEmoji;
	if (hold.state != UIGestureRecognizerStateBegan ||
			(!isSticker && !isGif && !isEmoji))
		return;
	UIButton *button = (UIButton *)hold.view;
	id item = TGGetButtonItemData(button);
	NSInteger index = button.tag - kItemTagBase;
	if (!item && index >= 0 && index < (NSInteger)self.items.count)
		item = self.items[index];
	if (!item) return;

	// An emoji has no file of its own; holding it opens the metadata card
	// instead of the sticker actions below.
	if (isEmoji){
		NSString *glyph = [item isKindOfClass:NSString.class] ? (NSString *)item : @"";
		[self showEmojiCardForEmoji:glyph atButton:button];
		return;
	}

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
			[items addObject:@{@"title" : @"Archived Packs...", @"icon" : @"folder"}];
			[actions addObject:@"archived"];
		}
		// Filing and outline are facts about the sticker, not about the set
		// it is in: both work wherever the card was opened.
		[items addObject:@{@"title" : @"Emoji Tags...", @"icon" : @"star"}];
		[actions addObject:@"emojis"];
		[items addObject:@{@"title" : @"Sticker Outline...", @"icon" : @"edit"}];
		[actions addObject:@"outline"];
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

		[[TGStickerStore shared] downloadFile:fileId priority:TGDownloadPriorityOnScreen completion:^(NSString *path){
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

		[[TGStickerStore shared] downloadFile:fileId priority:TGDownloadPriorityOnScreen completion:^(NSString *path){
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
			[[TGStickerStore shared] setSticker:fileId favourite:YES];
		else if ([action isEqualToString:@"unfav"])
			[[TGStickerStore shared] setSticker:fileId favourite:NO];
		else if ([action isEqualToString:@"unrecent"])
			[[TGStickerStore shared] removeRecentSticker:fileId];
		else if ([action isEqualToString:@"unset"])
			[[TGStickerStore shared] setStickerSet:setId installed:NO archived:NO];
		else if ([action isEqualToString:@"archived"]){
			[weakSelf showArchivedPacks];
			return;
		}
		else if ([action isEqualToString:@"emojis"]){
			[weakSelf showEmojiTagsOfStickerWithFileId:fileId title:item[@"emoji"]];
			return;
		}
		else if ([action isEqualToString:@"outline"]){
			[weakSelf showOutlineOfStickerWithFileId:fileId];
			return;
		}
		else if ([action isEqualToString:@"savegif"])
			[[TGStickerStore shared] saveAnimationFileId:fileId saved:YES];
		else if ([action isEqualToString:@"unsavegif"])
			[[TGStickerStore shared] saveAnimationFileId:fileId saved:NO];

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

/// What a held emoji can say about itself. The card is the panel's own
/// version of the reaction picker's caption: the glyph, the reaction's title
/// and the animations Telegram publishes for it.
- (void)showEmojiCardForEmoji:(NSString *)emoji atButton:(UIButton *)button {
	if (!emoji.length)
		return;

	UIView *host = self.window ?: (self.superview ?: self);
	CGPoint where = [self.grid convertPoint:button.center toView:host];
	self.menuOpenUntil = [NSDate timeIntervalSinceReferenceDate] + 1.0;

	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, kPreviewHeaderWidth, kEmojiCardHeaderHeight)];
	header.backgroundColor = [UIColor clearColor];
	UILabel *glyph = [[UILabel alloc] initWithFrame:header.bounds];
	glyph.text = emoji;
	glyph.font = TGFontEmojiLarge();
	glyph.textAlignment = NSTextAlignmentCenter;
	[header addSubview:glyph];

	NSArray *items = @[
		@{@"title" : @"Animated Preview", @"icon" : @"sticker"},
		@{@"title" : @"Reaction Info", @"icon" : @"react"},
		@{@"title" : @"Custom Reaction Animation", @"icon" : @"video"},
		@{@"title" : @"Suggest Replacement Link...", @"icon" : @"copy"},
	];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items atPoint:where inView:host headerView:header
				  onChoice:^(NSInteger choice, NSString *title){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		if (choice == 0)
			[me showAnimatedEmoji:emoji];
		else if (choice == 1)
			[me showReactionInfoForEmoji:emoji];
		else if (choice == 2)
			[me showCustomReactionAnimation];
		else if (choice == 3)
			[me showEmojiSuggestionLink];
	}];
}

/// The animated version of one emoji, which most of the plain set does not
/// have; a 404 is the normal answer rather than a failure worth a red sheet.
- (void)showAnimatedEmoji:(NSString *)emoji {
	__weak typeof(self) weakSelf = self;
	[[TGEmojiStore shared] animatedEmojiForEmoji:emoji completion:^(NSDictionary *animated){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		if (!animated){
			[TGAlertSheet showMessage:
					[NSString stringWithFormat:@"Telegram has no animated %@.", emoji]
								 title:@"Animated Emoji"
								inView:(me.window ?: me)];
			return;
		}
		[me showStickerPreview:animated caption:emoji];
	}];
}

/// Title, availability, and the animation Telegram plays for the reaction.
/// A reaction that exists but carries no animation still gets its text card.
- (void)showReactionInfoForEmoji:(NSString *)emoji {
	__weak typeof(self) weakSelf = self;
	[[TGEmojiStore shared] reactionForEmoji:emoji completion:^(NSDictionary *reaction){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		if (!reaction){
			[TGAlertSheet showMessage:
					[NSString stringWithFormat:@"%@ is not a reaction.", emoji]
								 title:@"Reaction"
								inView:(me.window ?: me)];
			return;
		}
		NSString *title = [reaction[@"title"] length] ? reaction[@"title"] : emoji;
		NSString *caption = [NSString stringWithFormat:@"%@ · %@", title,
				[reaction[@"active"] boolValue] ? @"Available" : @"Not available"];
		NSDictionary *animation = reaction[@"animation"];
		if (animation){
			[me showStickerPreview:animation caption:caption];
			return;
		}
		[TGAlertSheet showMessage:caption title:@"Reaction" inView:(me.window ?: me)];
	}];
}

/// The generic TGS set Telegram ships for custom-emoji reactions. The first
/// one is the sample: the panel has no custom reaction to name, so playing
/// the set's own preview is the honest reading.
- (void)showCustomReactionAnimation {
	__weak typeof(self) weakSelf = self;
	[[TGEmojiStore shared] customEmojiReactionAnimationsWithCompletion:^(NSArray *stickers){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		NSDictionary *first = stickers.firstObject;
		if (!first){
			[TGAlertSheet showMessage:@"Telegram sent no custom reaction animations."
								 title:@"Custom Reactions"
								inView:(me.window ?: me)];
			return;
		}
		[me showStickerPreview:first caption:@"Custom reaction animation"];
	}];
}

/// The translation platform's link for proposing a better emoji keyword.
/// It expires after 30 seconds, so it is fetched when the card is opened and
/// never kept.
- (void)showEmojiSuggestionLink {
	__weak typeof(self) weakSelf = self;
	[[TGEmojiStore shared] suggestionsUrlForLanguage:nil completion:^(NSString *url){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		if (!url.length){
			[TGAlertSheet showMessage:@"Telegram did not return a suggestion link."
								 title:@"Suggest Emoji"
								inView:(me.window ?: me)];
			return;
		}
		UIView *host = me.window ?: me;
		[TGAlertSheet showChoices:@[@"Copy Link", @"Open", @"Cancel"]
							title:@"Suggest Emoji Replacement"
						  message:url
				   destructiveIndex:-1
						   inView:host
						 onChoice:^(NSInteger index){
			if (index == 0){
				[UIPasteboard generalPasteboard].string = url;
			} else if (index == 1){
				NSURL *link = [NSURL URLWithString:url];
				if (link)
					[[UIApplication sharedApplication] openURL:link];
			}
		}];
	}];
}

/// A card with an animated sticker in its header and one line under it. The
/// renderer is the same one the sticker tab uses, so .tgs and .webm both play
/// without the card knowing which one it was handed.
- (void)showStickerPreview:(NSDictionary *)info caption:(NSString *)caption {
	NSInteger fileId = [info[@"fileId"] integerValue];
	if (fileId <= 0){
		[TGAlertSheet showMessage:@"Telegram sent no animation for this."
							 title:caption
							inView:(self.window ?: self)];
		return;
	}

	UIView *host = self.window ?: (self.superview ?: self);
	UIView *header = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, kPreviewHeaderWidth, kEmojiPreviewHeaderHeight)];
	header.backgroundColor = [UIColor clearColor];

	CGRect picture = CGRectMake(TGCenteredOrigin(kPreviewHeaderWidth, kPreviewSide),
			TGMetricPadSmall, kPreviewSide, kPreviewSide);
	TGLottieView *lottie = [[TGLottieView alloc] initWithFrame:picture];
	[header addSubview:lottie];

	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0,
			CGRectGetMaxY(picture), kPreviewHeaderWidth, kEmojiPreviewCaptionHeight)];
	label.text = caption;
	label.font = TGFontBody();
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	[header addSubview:label];

	[[TGStickerStore shared] downloadFile:fileId
							 priority:TGDownloadPriorityOnScreen
						   completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			__weak TGLottieView *weakLottie = lottie;
			weakLottie.onStickerReady = ^{ [weakLottie play]; };
			if ([weakLottie loadStickerFile:path])
				[weakLottie play];
		});
	}];

	CGPoint where = [self convertPoint:CGPointMake(CGRectGetMidX(self.bounds),
			CGRectGetMidY(self.bounds)) toView:host];
	self.menuOpenUntil = [NSDate timeIntervalSinceReferenceDate] + 1.0;
	[TGPopupMenu showItems:@[@{@"title" : @"Close", @"icon" : @"close"}]
				   atPoint:where
					inView:host
				headerView:header
				  onChoice:^(NSInteger index, NSString *title){}];
}

/// The tags a sticker is filed under, straight from Telegram: the sticker's
/// own list, and every emoji in the installed sets that matches the first of
/// them. The second list is how the shelf is explorable from one sticker.
- (void)showEmojiTagsOfStickerWithFileId:(NSInteger)fileId title:(NSString *)emoji {
	__weak typeof(self) weakSelf = self;
	[[TGStickerStore shared] stickerEmojisForFileId:fileId completion:^(NSArray *own){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		NSString *query = own.count ? own.firstObject : (emoji ?: @"");
		[[TGStickerStore shared] allStickerEmojisForQuery:query completion:^(NSArray *all){
			TGEmojiPanel *panel = weakSelf;
			if (!panel)
				return;
			NSString *first = own.count
					? [own componentsJoinedByString:@" "] : @"none";
			NSString *rest = all.count
					? [all componentsJoinedByString:@" "] : @"none";
			NSString *message = [NSString stringWithFormat:
					@"Filed under: %@\n\nEvery tag matching %@:\n%@",
					first, query.length ? query : @"this sticker", rest];
			[TGAlertSheet showMessage:message
								  title:@"Emoji Tags"
								 inView:(panel.window ?: panel)];
		}];
	}];
}

/// The outline the vector pipeline publishes, plus the SVG path for it.
/// This card shows what Telegram sent rather than a guessed shape, which is
/// the honest reading on a device with no general vector fill.
- (void)showOutlineOfStickerWithFileId:(NSInteger)fileId {
	__weak typeof(self) weakSelf = self;
	[[TGStickerStore shared] stickerOutlineForFileId:fileId completion:
			^(NSArray *paths, NSInteger points){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		[[TGStickerStore shared] stickerOutlineSvgPathForFileId:fileId
				completion:^(NSString *svg){
			TGEmojiPanel *panel = weakSelf;
			if (!panel)
				return;
			NSString *path = svg ?: @"";
			NSString *shown = path.length > 240
					? [[path substringToIndex:240] stringByAppendingString:@"..."]
					: path;
			NSString *message = [NSString stringWithFormat:
					@"%lu closed paths, %ld points.\n\n%@",
					(unsigned long)paths.count, (long)points,
					shown.length ? shown : @"Telegram sent no SVG path."];
			UIView *host = panel.window ?: panel;
			if (!path.length){
				[TGAlertSheet showMessage:message title:@"Sticker Outline" inView:host];
				return;
			}
			[TGAlertSheet showChoices:@[@"Copy SVG Path", @"Done"]
								title:@"Sticker Outline"
								message:message
					 destructiveIndex:-1
							   inView:host
							 onChoice:^(NSInteger index){
				if (index == 0){
					[UIPasteboard generalPasteboard].string = path;
				}
			}];
		}];
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
		[[TGStickerStore shared] setStickerSet:set[@"id"] installed:YES archived:NO];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
				(int64_t)(TGAnimationDurationHighlight * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
			[weakSelf selectTab:TGEmojiPanelTabStickers];
		});
	}];
}

/// The shelf a removed pack lands on. A pack comes back by installing it
/// again from here; that is the whole reason the list is kept.
- (void)showArchivedPacks {
	__weak typeof(self) weakSelf = self;
	[[TGStickerStore shared] archivedStickerSetsWithCompletion:^(NSArray *sets){
		TGEmojiPanel *me = weakSelf;
		if (!me)
			return;
		NSArray *list = [sets isKindOfClass:NSArray.class] ? sets : @[];
		if (!list.count){
			[TGAlertSheet showMessage:@"No packs are archived."
								  title:@"Archived Packs"
								 inView:(me.window ?: me)];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *set in list){
			NSString *title = [set[@"title"] length] ? set[@"title"] : @"Pack";
			[rows addObject:[NSString stringWithFormat:@"%@  ·  %lu stickers",
					title, (unsigned long)[set[@"count"] unsignedIntegerValue]]];
		}
		UIView *host = me.window ?: me;
		[TGAlertSheet showChoices:rows
							title:@"Archived Packs"
						  message:@"Restoring one puts it back on the shelf."
				   destructiveIndex:-1
						   inView:host
						 onChoice:^(NSInteger index){
			NSDictionary *set = list[(NSUInteger)index];
			[[TGStickerStore shared] setStickerSet:set[@"id"] installed:YES archived:NO];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
					(int64_t)(TGAnimationDurationHighlight * NSEC_PER_SEC)),
					dispatch_get_main_queue(), ^{
				[weakSelf selectTab:TGEmojiPanelTabStickers];
			});
		}];
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
	NSArray *suggested = [[TGStickerStore shared] animationSearchEmojis];
	NSString *hint = suggested.count
			? [NSString stringWithFormat:@"Try %@, or type a word.",
					[suggested componentsJoinedByString:@" "]]
			: nil;
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Search GIFs"
					message:hint
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
