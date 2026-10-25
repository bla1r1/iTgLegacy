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
		if (gainedTile)
			[weakSelf buildHeader];      // the tile row is one shorter without it
		[weakSelf reloadTableDebounced];
	}];

	[[TGClient shared] mediaInChat:self.chatId
							filter:@"searchMessagesFilterPhotoAndVideo"
						completion:^(NSArray *messages){
		weakSelf.photos = messages;
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
	if (self.stories.count)
		[out addObject:@{@"title" : @"Stories", @"kind" : @"stories"}];
	if (self.gifts.count)
		[out addObject:@{@"title" : @"Gifts",   @"kind" : @"gifts"}];
	[out addObject:@{@"title" : @"Media", @"kind" : @"media"}];
	if (self.files.count)
		[out addObject:@{@"title" : @"Files", @"kind" : @"files"}];
	if (self.voice.count)
		[out addObject:@{@"title" : @"Voice", @"kind" : @"voice"}];
	if (self.links.count)
		[out addObject:@{@"title" : @"Links", @"kind" : @"links"}];
	return out;
}

/// Media is a strip you push sideways; Stories is a grid that wraps, the way
/// the sticker panel lays its rows out.
- (BOOL)selectedTabIsStrip {
	return [[self selectedMediaKind] isEqualToString:@"media"];
}

- (BOOL)selectedTabIsGrid {
	return [[self selectedMediaKind] isEqualToString:@"stories"];
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
- (UITableViewCell *)storyGridCell:(UITableView *)tableView {
	if (self.storyGridCellCache)
		return self.storyGridCellCache;

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
												   reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	CGFloat width = tableView.bounds.size.width;
	CGFloat side = [[self class] storySideForWidth:width];
	NSInteger count = MIN((NSInteger)self.stories.count, 20);

	for (NSInteger i = 0; i < count; i++){
		NSDictionary *story = self.stories[i];
		// The tile list asks for the list-sized render, not the largest one;
		// a 105 pt square is at most 220 px wide and the queue is shared
		// with everything else (B2).
		NSNumber *fileId = story[@"thumbPhotoId"] ?: story[@"photoId"];
		CGRect frame = CGRectMake((i % kStoryGridCols) * (side + kStoryGridGap),
								  (i / kStoryGridCols) * (side + kStoryGridGap),
								  side, side);

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:frame];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		[cell.contentView addSubview:thumb];

		if ([story[@"isVideo"] boolValue]){
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

		if ([fileId integerValue] > 0)
			[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
				[TGIcons loadImageAtPath:path into:thumb];
			}];
	}
	self.storyGridCellCache = cell;
	return cell;
}

/// What the selected tab shows; nil for the photo strip, which is not a list.
- (NSString *)selectedMediaKind {
	NSArray *tabs = [self currentMediaTabs];
	if (!tabs.count)
		return @"media";
	NSInteger index = MIN(MAX(0, self.selectedMediaTab), (NSInteger)tabs.count - 1);
	return tabs[index][@"kind"];
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
	self.selectedMediaTab = sender.selectedSegmentIndex;
	// The strip is cached, and the next tab may want different pictures in it.
	self.mediaStripCell = nil;
	self.mediaStrip = nil;
	self.storyGridCellCache = nil;
	[self.thumbnailsRequested removeAllObjects];
	// Switching a tab is not a change of content to be animated. Even with no
	// row animation, reloading the one section slid the outgoing rows up out
	// of the way; reloading the table swaps them in place.
	[self.tableView reloadData];
}

/// A horizontal strip of thumbnails: a grid would mean a collection view,
/// which iOS 6 has but this screen does not need.
- (UITableViewCell *)photoStripCell:(UITableView *)tableView {
	if (self.mediaStripCell) {
		return self.mediaStripCell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	
	UIScrollView *strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 2, tableView.bounds.size.width, 80)];
	strip.showsHorizontalScrollIndicator = NO;
	[cell.contentView addSubview:strip];

	strip.delegate = self;
	self.mediaStrip = strip;

	BOOL showingStories = NO;
	NSArray *rows = self.photos;

	CGFloat side = 76, gap = 4, x = gap;
	NSInteger limit = MIN((NSInteger)rows.count, 20);
	for (NSInteger i = 0; i < limit; i++){
		NSDictionary *m = rows[i];
		NSNumber *fileId = m[@"photoId"];
		if (!fileId) continue;

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectMake(x, 2, side, side)];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		// The id rides on the view so the scroll handler can ask for it later
		// rather than the strip asking for all twenty the moment it is built.
		thumb.tag = fileId.integerValue;
		[strip addSubview:thumb];

		if (showingStories){
			// A video story says so in the corner, and the whole tile opens it.
			if ([m[@"isVideo"] boolValue]){
				UIImageView *mark = [[UIImageView alloc] initWithFrame:
						CGRectMake(side - 20, side - 20, 16, 16)];
				mark.image = [TGIcons glyphNamed:@"video" colour:[UIColor whiteColor] side:16];
				[thumb addSubview:mark];
			}
			UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
			tap.frame = CGRectMake(x, 2, side, side);
			tap.tag = 500 + i;
			[tap addTarget:self action:@selector(storyTileTapped:)
				  forControlEvents:UIControlEventTouchUpInside];
			[strip addSubview:tap];
		}
		x += side + gap;
	}
	strip.contentSize = CGSizeMake(x, 80);
	self.mediaStripCell = cell;
	[self fetchVisibleThumbnails];
	return cell;
}

/// Lazily downloads thumbnails visible in the media strip viewport.
- (void)fetchVisibleThumbnails {
	UIScrollView *strip = self.mediaStrip;
	if (!strip)
		return;

	CGRect window = CGRectMake(strip.contentOffset.x - strip.bounds.size.width, 0,
							   strip.bounds.size.width * 3, strip.bounds.size.height);
	for (UIView *view in strip.subviews){
		if (![view isKindOfClass:UIImageView.class] || view.tag == 0)
			continue;
		if (!CGRectIntersectsRect(view.frame, window))
			continue;

		UIImageView *thumb = (UIImageView *)view;
		NSNumber *fileId = @(thumb.tag);
		if ([self.thumbnailsRequested containsObject:fileId])
			continue;
		[self.thumbnailsRequested addObject:fileId];

		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue
							   priority:TGDownloadPriorityOnScreen
							 completion:^(NSString *path){
			// A nil callback means the watchdog gave up or the download
			// errored: lifting the mark turns the next scroll pass into the
			// retry, instead of leaving the tile empty forever (B2).
			if (!path.length){
				TGProfileViewController *me = weakSelf;
				[me.thumbnailsRequested removeObject:fileId];
				return;
			}
			[TGIcons loadImageAtPath:path into:thumb];
		}];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.mediaStrip)
		[self fetchVisibleThumbnails];
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
