#import "TGProfileViewControllerInternal.h"
#import <AVFoundation/AVFoundation.h>

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
	// the photo strip used to (B1). Stories share the same renderer.
	return [kind isEqualToString:@"media"] || [kind isEqualToString:@"stories"];
}

static const CGFloat kStoryGridGap     = 2.0f;
static const NSInteger kStoryGridCols  = 3;

/// Edge to edge, like the media strip: the tile is whatever is left after the
/// gaps, not a fixed 76 with the remainder thrown away as margin.
+ (CGFloat)storySideForWidth:(CGFloat)width {
	return floorf((width - kStoryGridGap * (kStoryGridCols - 1)) / kStoryGridCols);
}

- (CGFloat)storyGridHeight {
	NSInteger count = MIN((NSInteger)self.stories.count, 20);
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
	NSString *cacheName = storyKind ? @"story" : @"media";

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
		// Story tiles render their thumbnail, photo tiles whatever the
		// message carries. The tile list asks for the list-sized render,
		// not the largest one; a 105 pt square is at most 220 px wide and
		// the queue is shared with everything else (B2).
		NSNumber *fileId = storyKind
				? (tile[@"thumbPhotoId"] ?: tile[@"photoId"])
				: (tile[@"photoId"] ?: tile[@"thumbPhotoId"]);
		CGRect frame = CGRectMake((i % kStoryGridCols) * (side + kStoryGridGap),
								  (i / kStoryGridCols) * (side + kStoryGridGap),
								  side, side);

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:frame];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		[cell.contentView addSubview:thumb];

		if (storyKind){
			if ([tile[@"isVideo"] boolValue]){
				UIImageView *mark = [[UIImageView alloc] initWithFrame:
						CGRectMake(side - 20, side - 20, 16, 16)];
				mark.image = [TGIcons glyphNamed:@"video" colour:[UIColor whiteColor] side:16];
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
	[self.tableView reloadData];
}

/// Displays full-screen view for the selected story.
- (void)openStoryAtIndex:(NSInteger)index {
	if (index >= (NSInteger)self.stories.count)
		return;
	NSDictionary *story = self.stories[index];
	NSNumber *fileId = story[@"photoId"];
	if (![fileId isKindOfClass:NSNumber.class]){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Story"
				message:@"This story has nothing this app can show."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}

	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
	backdrop.backgroundColor = [UIColor blackColor];
	backdrop.alpha = 0;

	UIImageView *picture = [[UIImageView alloc] initWithFrame:
			CGRectInset(window.bounds, 0, 40)];
	picture.contentMode = UIViewContentModeScaleAspectFit;
	[backdrop addSubview:picture];

	NSString *caption = story[@"caption"];
	if (caption.length){
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
				16, window.bounds.size.height - 76, window.bounds.size.width - 32, 60)];
		label.text = caption;
		label.numberOfLines = 3;
		label.font = [UIFont systemFontOfSize:14];
		label.textColor = [UIColor whiteColor];
		label.backgroundColor = [UIColor clearColor];
		[backdrop addSubview:label];
	}

	UILabel *note = nil;
	if ([story[@"isVideo"] boolValue]){
		note = [[UILabel alloc] initWithFrame:
				CGRectMake(0, 24, window.bounds.size.width, 18)];
		note.text = story[@"videoId"] ? @"Loading video..."
									  : @"Video story - showing the first frame";
		note.font = [UIFont systemFontOfSize:12];
		note.textAlignment = NSTextAlignmentCenter;
		note.textColor = [UIColor colorWithWhite:1 alpha:0.6f];
		note.backgroundColor = [UIColor clearColor];
		[backdrop addSubview:note];
	}

	backdrop.userInteractionEnabled = YES;
	[backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(closeStory:)]];
	[window addSubview:backdrop];
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 1; }];

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
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 0; }
					 completion:^(BOOL done){ [backdrop removeFromSuperview]; }];
}

@end
