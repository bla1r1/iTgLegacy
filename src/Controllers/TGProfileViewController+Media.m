#import "TGProfileViewControllerInternal.h"
#import "TGGiftViewer.h"
#import <AVFoundation/AVFoundation.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// Only one story is ever open, so the player it needs can live here rather
/// than as state on a category that cannot hold any.
static AVPlayer *sStoryPlayer = nil;
static AVPlayerLayer *sStoryLayer = nil;

@implementation TGProfileViewController (Media)

- (void)loadMedia {
	__weak typeof(self) weakSelf = self;
	if (self.userId){
		[[TGClient shared] giftsForUser:self.userId completion:^(NSArray *gifts){
			weakSelf.gifts = gifts;
			[weakSelf reloadTableDebounced];
		}];
		[[TGClient shared] isUserBlocked:self.userId completion:^(BOOL blocked){
			weakSelf.blocked = blocked;
			[weakSelf reloadTableDebounced];
		}];
	}

	// Stories sit on a profile the way shared media does, and this screen had
	// a "Posts" row standing in for them that always said there were none.
	[[TGClient shared] storiesForChat:self.chatId completion:^(NSArray *stories){
		BOOL gainedTile = stories.count && !weakSelf.stories.count;
		weakSelf.stories = stories;
		// A fresh set means the cached grid cell still shows the old tiles.
		weakSelf.storyGridCellCache = nil;
		if (gainedTile)
			[weakSelf buildHeader];      // the tile row is one shorter without it
		[weakSelf reloadTableDebounced];
	}];

	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		weakSelf.photos = messages;
		// Same for the grid: without this, late-arriving media is invisible
		// until the user pokes another tab (B1's cache family).
		weakSelf.storyGridCellCache = nil;
		weakSelf.mediaGridCacheContent = nil;
		[weakSelf reloadTableDebounced];
	}];
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterDocument"
						completion:^(NSArray *messages){
		weakSelf.files = messages;
		[weakSelf reloadTableDebounced];
	}];
	// Voice and Links were tabs that always came back empty because nothing
	// ever asked for them.
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterVoiceNote"
						completion:^(NSArray *messages){
		weakSelf.voice = messages;
		[weakSelf reloadTableDebounced];
	}];
	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterUrl"
						completion:^(NSArray *messages){
		weakSelf.links = messages;
		[weakSelf reloadTableDebounced];
	}];
}

/// The bar across the top of the shared section, in their order: what the
/// profile has to show comes first, then the message categories. A category
/// with nothing in it is left out rather than offered as an empty tab.
- (NSArray *)currentMediaTabs {
	NSMutableArray *out = [NSMutableArray array];
	// The bar reads left-to-right the way the official profile does. The
	// order is fixed: stories and gifts keep their slots at the end whether
	// they have content yet or not, so a category that loads late cannot
	// slide the user's selected tab out from under their finger - holding
	// reorderable positions was the whole "the grids simply swapped" bug
	// family (B1).
	[out addObject:@{@"title" : @"Media",   @"kind" : @"media"}];
	if (self.files.count)
		[out addObject:@{@"title" : @"Files", @"kind" : @"files"}];
	if (self.voice.count)
		[out addObject:@{@"title" : @"Voice", @"kind" : @"voice"}];
	if (self.links.count)
		[out addObject:@{@"title" : @"Links", @"kind" : @"links"}];
	if (self.stories.count)
		[out addObject:@{@"title" : @"Stories", @"kind" : @"stories"}];
	if (self.gifts.count)
		[out addObject:@{@"title" : @"Gifts",   @"kind" : @"gifts"}];
	return out;
}

/// Media is a strip you push sideways; Stories is a grid that wraps, the way
/// the sticker panel lays its rows out.
- (BOOL)selectedTabIsGrid {
	NSString *kind = [self selectedMediaKind];
	// Media became a grid of its own: one row of the table holds the tiles
	// the photo strip used to (B1). Stories share the same renderer, and
	// gifts read like the official sheet: big square tiles.
	return [kind isEqualToString:@"media"] || [kind isEqualToString:@"stories"] ||
		   [kind isEqualToString:@"gifts"];
}

static const CGFloat kStoryGridGap     = TGMetricCollageGap;
/// The poster's face in the corner of a story tile, and the mark that says a
/// tile is a video rather than a picture.
static const CGFloat kStoryFace      = 26.0f;
static const CGFloat kVideoMark      = 16.0f;
static const CGFloat kVideoMarkInset = TGMetricPadWide;
static const NSInteger kStoryGridCols  = 3;

/// Edge to edge, like the media strip: the tile is whatever is left after the
/// gaps, not a fixed 76 with the remainder thrown away as margin.
+ (CGFloat)storySideForWidth:(CGFloat)width {
	return floorf((width - kStoryGridGap * (kStoryGridCols - 1)) / kStoryGridCols);
}

/// A gift tile wears its emoji drawn large - the artwork the tab strip
/// carries until a decodable picture exists. Like TGGiftGlyph in the main
/// file, but sized for the grid, and the tile colour sits behind it (B5).
+ (UIImage *)giftTileGlyph:(NSString *)emoji side:(CGFloat)side {
	if (!emoji.length)
		emoji = @"🎁";
	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
	NSString *key = [emoji stringByAppendingFormat:@"@%g", side];
	UIImage *cached = [cache objectForKey:key];
	if (cached)
		return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	CGFloat inset = side * TGMetricEmojiArtworkInsetRatio * 2;
	[emoji drawInRect:CGRectMake(inset, inset, side - TGDoubled(inset), side - TGDoubled(inset))
			 withFont:TGFontBoldAtSize(TGHalf(side))
		lineBreakMode:NSLineBreakByClipping
		   alignment:NSTextAlignmentCenter];
#pragma clang diagnostic pop
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	[cache setObject:img forKey:key];
	return img;
}

- (CGFloat)storyGridHeight {
	NSString *kind = [self selectedMediaKind];
	BOOL storyKind = [kind isEqualToString:@"stories"];
	BOOL giftKind = [kind isEqualToString:@"gifts"];
	NSInteger dataCount = storyKind ? (NSInteger)self.stories.count
						: giftKind ? (NSInteger)self.gifts.count
						: (NSInteger)self.photos.count;
	NSInteger count = MIN(dataCount, 20);
	if (!count)
		return 0;
	NSInteger rows = (count + kStoryGridCols - 1) / kStoryGridCols;
	CGFloat side = [[self class] storySideForWidth:self.tableView.bounds.size.width];
	return rows * side + (rows - 1) * kStoryGridGap;
}

/// The stories as a wrapping grid of pictures, each one opening its story.
/// Cached like the media strip: rebuilding it on every pass through
/// cellForRow handed back a grid whose pictures had already been asked for
/// and so never arrived again - scrolling away and back emptied it.
/// One grid renderer serves every tile-shaped category: photos for "media"
/// and story tiles for "stories". A grid means no collection view - iOS 6
/// has one, but this screen stretches a grouped table instead, and one row
/// of it holds this scroller-less cell (B1: media drew the story tiles and
/// the photo strip was a second, forgetful cache).
- (UITableViewCell *)mediaGridCell:(UITableView *)tableView {
	NSString *kind = [self selectedMediaKind];
	BOOL storyKind = [kind isEqualToString:@"stories"];
	BOOL giftKind = [kind isEqualToString:@"gifts"];
	// One cache per kind: the rows themselves change shape between them,
	// and a grid built for photos cannot be re-faced for gifts.
	NSString *cacheName = kind;

	if ([self.mediaGridCacheContent isEqualToString:cacheName] && self.storyGridCellCache)
		return self.storyGridCellCache;

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
												   reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	NSArray *rows = [self selectedMediaRows];
	CGFloat width = tableView.bounds.size.width;
	CGFloat side = [[self class] storySideForWidth:width];
	NSInteger count = MIN((NSInteger)rows.count, 20);

	for (NSInteger i = 0; i < count; i++){
		NSDictionary *tile = rows[i];
		CGRect frame = CGRectMake((i % kStoryGridCols) * (side + kStoryGridGap),
								  (i / kStoryGridCols) * (side + kStoryGridGap),
								  side, side);

		if (giftKind){
			// Gift tiles read like the official gifts grid: the emoji is
			// the artwork, tile colour behind it, and the sender's face
			// rides the top-left corner. No download ride-alongs on the
			// strip - the glyph is cached and free, and the 4S has paid
			// enough queue time (B5).
			NSString *emoji = tile[@"emoji"];
			UIImageView *glyph = [[UIImageView alloc] initWithFrame:frame];
			glyph.image = [[self class] giftTileGlyph:emoji side:side];
			glyph.contentMode = UIViewContentModeScaleAspectFit;
			glyph.backgroundColor = [[TGTheme shared] fileTileColour];
			glyph.clipsToBounds = YES;
			[cell.contentView addSubview:glyph];

			NSInteger userId = [tile[@"senderUserId"] longLongValue];
			NSString *name = [[TGClient shared] nameForUserId:userId];
			NSString *first = name.length
					? [name substringToIndex:1].uppercaseString : @"?";
			UIButton *face = [UIButton buttonWithType:UIButtonTypeCustom];
			face.frame = CGRectMake(TGMetricPadSmall, TGMetricPadSmall, kStoryFace, kStoryFace);
			face.layer.cornerRadius = TGMetricCornerCard;
			face.layer.masksToBounds = YES;
			face.enabled = NO;
			[face setImage:[TGIcons avatarWithInitials:first size:kStoryFace
											  colourId:userId]
				  forState:UIControlStateNormal];
			[cell.contentView addSubview:face];

			UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
			tap.frame = frame;
			tap.tag = 700 + i;
			[tap addTarget:self action:@selector(giftTileTapped:)
				  forControlEvents:UIControlEventTouchUpInside];
			[cell.contentView addSubview:tap];
			continue;
		}

		// Story tiles render their thumbnail, photo tiles whatever the
		// message carries. The tile list asks for the list-sized render,
		// not the largest one; a 105 pt square is at most 220 px wide and
		// the queue is shared with everything else (B2).
		NSNumber *fileId = storyKind
				? (tile[@"thumbPhotoId"] ?: tile[@"photoId"])
				: (tile[@"photoId"] ?: tile[@"thumbPhotoId"]);

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:frame];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		[cell.contentView addSubview:thumb];

		if (storyKind){
			if ([tile[@"isVideo"] boolValue]){
				UIImageView *mark = [[UIImageView alloc] initWithFrame:
						CGRectMake(side - kVideoMarkInset, side - kVideoMarkInset, kVideoMark, kVideoMark)];
				mark.image = [TGIcons glyphNamed:@"video" colour:[UIColor whiteColor]
									  side:kVideoMark];
				[thumb addSubview:mark];
			}

			UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
			tap.frame = frame;
			tap.tag = 500 + i;
			[tap addTarget:self action:@selector(storyTileTapped:)
				  forControlEvents:UIControlEventTouchUpInside];
			[cell.contentView addSubview:tap];
		}

		if ([fileId integerValue] > 0){
			__weak typeof(self) weakSelf = self;
			[[TGClient shared] downloadFile:fileId.integerValue
								   priority:TGDownloadPriorityOnScreen
								 completion:^(NSString *path){
				[TGIcons loadImageAtPath:path into:thumb];
				(void)weakSelf;
			}];
		}
	}

	self.storyGridCellCache = cell;
	self.mediaGridCacheContent = cacheName;
	return cell;
}

/// What the selected tab shows; nil for the photo strip, which is not a list.
- (NSString *)selectedMediaKind {
	NSString *kind = self.storedMediaKind;
	// The answer is only valid while that kind still has a tab: stories end,
	// gifts empty out, and holding a dead kind would render a toolbar
	// selection that no longer matches. Falling back to the photo strip is
	// what the official clients do.
	for (NSDictionary *tab in [self currentMediaTabs])
		if ([tab[@"kind"] isEqualToString:kind])
			return kind;
	return @"media";
}

/// The rows behind the selected tab, for the list-shaped categories.
- (NSArray *)selectedMediaRows {
	NSString *kind = [self selectedMediaKind];
	if ([kind isEqualToString:@"media"])   return self.photos ?: @[];
	if ([kind isEqualToString:@"files"])   return self.files ?: @[];
	if ([kind isEqualToString:@"voice"])   return self.voice ?: @[];
	if ([kind isEqualToString:@"links"])   return self.links ?: @[];
	if ([kind isEqualToString:@"stories"]) return self.stories ?: @[];
	if ([kind isEqualToString:@"gifts"])   return self.gifts ?: @[];
	return @[];
}

- (void)storyTileTapped:(UIButton *)button {
	[self openStoryAtIndex:button.tag - 500];
}

/// A gift tile opens the detail sheet, the way the official grid does:
/// artwork on top, From / Date / Cost, an OK button (B5).
- (void)giftTileTapped:(UIButton *)button {
	NSString *kind = [self selectedMediaKind];
	if (![kind isEqualToString:@"gifts"])
		return;
	NSInteger index = button.tag - 700;
	NSArray *rows = [self selectedMediaRows];
	if (index < 0 || index >= (NSInteger)rows.count)
		return;
	[TGGiftViewer showGift:rows[index] inView:self.view];
}

- (void)mediaTabChanged:(UISegmentedControl *)sender {
	NSArray *tabs = [self currentMediaTabs];
	NSInteger index = MIN(MAX(0, sender.selectedSegmentIndex), (NSInteger)tabs.count - 1);
	// The kind is resolved here, at tap time. The tab array can reorder as
	// categories load (gifts before media, stories before both); holding a
	// number instead made the selection follow the array's rows, and the
	// profile's media grid turned into whatever moved into that position
	// (B1 - "the grids simply swapped").
	self.storedMediaKind = tabs[index][@"kind"];
	// The grid is cached per kind, and the next tab wants different tiles.
	self.storyGridCellCache = nil;
	self.mediaGridCacheContent = nil;
	[self.thumbnailsRequested removeAllObjects];
	// Switching a tab is not a change of content to be animated. Even with no
	// row animation, reloading the one section slid the outgoing rows up out
	// of the way; reloading the table swaps them in place.
	//
	// The offset is preserved rather than reset: the sections above the media
	// one do not change height, so keeping the offset holds the same part of
	// the media section on screen. When the new tab is shorter than the
	// current scroll position falls off it, land back on the section header
	// instead of letting the table clamp the offset into the footer.
	CGPoint offset = self.tableView.contentOffset;
	CGFloat mediaTop = [self.tableView rectForHeaderInSection:kSectionMedia].origin.y;
	[self.tableView reloadData];
	CGFloat maxY = self.tableView.contentSize.height - self.tableView.bounds.size.height;
	maxY = MAX(0, maxY);
	if (offset.y > maxY + TGMetricHairline || offset.y < mediaTop - self.tableView.bounds.size.height)
		offset.y = mediaTop;
	offset.y = MIN(MAX(offset.y, 0), maxY);
	[self.tableView setContentOffset:offset animated:NO];
}

/// Displays full-screen view for the selected story.
- (void)openStoryAtIndex:(NSInteger)index {
	if (index >= (NSInteger)self.stories.count)
		return;
	NSDictionary *story = self.stories[index];
	NSNumber *fileId = story[@"photoId"];
	if (![fileId isKindOfClass:NSNumber.class]){
		[TGAlertSheet showMessage:@"This story has nothing this app can show."
							title:@"Story" inView:self.view];
		return;
	}

	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
	backdrop.backgroundColor = [UIColor blackColor];
	backdrop.alpha = 0;

	UIImageView *picture = [[UIImageView alloc] initWithFrame:
			CGRectInset(window.bounds, 0, TGMetricListAvatar)];
	picture.contentMode = UIViewContentModeScaleAspectFit;
	[backdrop addSubview:picture];

	NSString *caption = story[@"caption"];
	if (caption.length){
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				TGMetricPadLarge, window.bounds.size.height - TGMetricStoryCaptionBottomOffset,
				window.bounds.size.width - TGDoubled(TGMetricPadLarge), TGMetricStoryCaptionHeight)];
		label.text = caption;
		label.numberOfLines = 3;
		label.font = TGFontSubhead();
		label.textColor = [UIColor whiteColor];
		label.backgroundColor = [UIColor clearColor];
		[backdrop addSubview:label];
	}

	UILabel *note = nil;
	if ([story[@"isVideo"] boolValue]){
		note = [[UILabel alloc] initWithFrame:
				CGRectMake(0, TGMetricBubbleDiscColumn, window.bounds.size.width,
					TGMetricLineBody)];
		note.text = story[@"videoId"] ? @"Loading video..."
									  : @"Video story - showing the first frame";
		note.font = TGFontMeta();
		note.textAlignment = NSTextAlignmentCenter;
		note.textColor = [[TGTheme shared] secondaryTextColour];
		note.backgroundColor = [UIColor clearColor];
		[backdrop addSubview:note];
	}

	backdrop.userInteractionEnabled = YES;
	[backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(closeStory:)]];
	[window addSubview:backdrop];
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{ backdrop.alpha = 1; }];

	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		[TGIcons loadImageAtPath:path into:picture];
	}];

	// The still is the poster frame; the video plays over it once it is here.
	NSNumber *videoId = story[@"videoId"];
	if (![videoId isKindOfClass:NSNumber.class] || videoId.integerValue <= 0)
		return;
	__weak UIView *weakBackdrop = backdrop;
	__weak UILabel *weakNote = note;
	[[TGClient shared] downloadFile:videoId.integerValue completion:^(NSString *path){
		UIView *host = weakBackdrop;
		if (!host || !host.superview || !path.length){
			weakNote.text = @"Video story - showing the first frame";
			return;
		}
		[self stopStoryPlayback];

		// Without this the session is still whatever the last recorder left
		// it as, and a story with sound plays silent.
		NSError *sessionError = nil;
		[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
											   error:&sessionError];
		[[AVAudioSession sharedInstance] setActive:YES error:NULL];

		AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
		if (!player){
			weakNote.text = @"Video story - showing the first frame";
			return;
		}
		player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
		AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
		layer.videoGravity = AVLayerVideoGravityResizeAspect;
		layer.frame = picture.frame;
		[host.layer addSublayer:layer];

		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(storyReachedEnd:)
					name:AVPlayerItemDidPlayToEndTimeNotification
				  object:player.currentItem];

		sStoryPlayer = player;
		sStoryLayer = layer;
		weakNote.hidden = YES;
		[player play];
	}];
}

- (void)storyReachedEnd:(NSNotification *)note {
	[sStoryPlayer seekToTime:kCMTimeZero];
	[sStoryPlayer play];
}

- (void)stopStoryPlayback {
	if (!sStoryPlayer && !sStoryLayer)
		return;
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
	[sStoryPlayer pause];
	[sStoryLayer removeFromSuperlayer];
	sStoryPlayer = nil;
	sStoryLayer = nil;
}

- (void)closeStory:(UITapGestureRecognizer *)tap {
	[self stopStoryPlayback];
	UIView *backdrop = tap.view;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{ backdrop.alpha = 0; }
					 completion:^(BOOL done){ [backdrop removeFromSuperview]; }];
}

@end
