#import "TGProfileViewControllerInternal.h"
#import "TGMediaViewer.h"
#import "TGGiftViewer.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGStoryViewerViewController.h"
#import "TGProfileTrackCell.h"
#import "TGClientInternal.h"
#import "TGIcons.h"

/// The address a piece of text links to: a text link's own URL, or the first URL
/// typed in it. Nil when it has none.
NSURL *TGProfileFirstURL(NSString *text, NSArray *entities) {
	if (![entities isKindOfClass:NSArray.class])
		return nil;
	for (NSDictionary *entity in entities){
		NSDictionary *type = entity[@"type"];
		NSString *name = [type isKindOfClass:NSDictionary.class] ? type[@"@type"] : nil;
		NSString *url = nil;
		if ([name isEqualToString:@"textEntityTypeTextUrl"])
			url = type[@"url"];
		else if ([name isEqualToString:@"textEntityTypeUrl"]){
			NSInteger offset = [entity[@"offset"] integerValue], length = [entity[@"length"] integerValue];
			if (length > 0 && (NSUInteger)(offset + length) <= text.length)
				url = [text substringWithRange:NSMakeRange((NSUInteger)offset, (NSUInteger)length)];
		}
		if (!url.length)
			continue;
		NSURL *parsed = [NSURL URLWithString:url];
		return parsed.scheme.length ? parsed
				: [NSURL URLWithString:[@"http://" stringByAppendingString:url]];
	}
	return nil;
}

@implementation TGProfileViewController (Media)

- (void)loadMedia {
	// The two panes that decide whether their tabs exist at all. Everything
	// else waits for its tab: the old screen fired four searchChatMessages
	// calls at open, before the first frame, on a one-core device.
	[self fetchMediaForKind:@"stories"];
	[self fetchMediaForKind:@"gifts"];
}

/// One pane's first page. A kind is fetched once and re-used until the
/// profile is reopened; switching tabs does not send the same search again.
- (void)fetchMediaForKind:(NSString *)kind {
	if (!kind.length)
		return;
	if ([self.loadedMediaKinds containsObject:kind] ||
			[self.loadingMediaKinds containsObject:kind])
		return;
	if ([kind isEqualToString:@"groups"] && !self.userId)
		return;
	[self.loadingMediaKinds addObject:kind];

	NSDictionary *filters = @{@"media" : @"searchMessagesFilterPhotoAndVideo",
							  @"files" : @"searchMessagesFilterDocument",
							  @"music" : @"searchMessagesFilterAudio",
							  @"voice" : @"searchMessagesFilterVoiceAndVideoNote",
							  @"links" : @"searchMessagesFilterUrl"};
	NSString *filterForCount = filters[kind];
	__weak typeof(self) weakSelf = self;
	void (^done)(NSArray *) = ^(NSArray *rows){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		[me.loadingMediaKinds removeObject:kind];
		[me.loadedMediaKinds addObject:kind];
		NSArray *safe = rows ?: @[];
		if ([kind isEqualToString:@"media"])
			me.photos = safe;
		else if ([kind isEqualToString:@"files"])
			me.files = safe;
		else if ([kind isEqualToString:@"music"])
			me.music = safe;
		else if ([kind isEqualToString:@"voice"])
			me.voice = safe;
		else if ([kind isEqualToString:@"links"])
			me.links = safe;
		else if ([kind isEqualToString:@"groups"])
			me.groupsInCommon = safe;
		else if ([kind isEqualToString:@"stories"])
			me.stories = safe;
		else if ([kind isEqualToString:@"gifts"])
			me.gifts = safe;
		// A search answers one page, so its total is asked for separately. The
		// other kinds arrive whole.
		if (filterForCount)
			[[TGClient shared] messageCountInChat:me.chatId filter:filterForCount
									   completion:^(NSInteger count){
				me.mediaCounts[kind] = @(count);
				[me reloadTableDebounced];
			}];
		else
			me.mediaCounts[kind] = @(safe.count);
		if ([kind isEqualToString:@"media"] || [kind isEqualToString:@"stories"] ||
				[kind isEqualToString:@"gifts"]){
			me.storyGridCellCache = nil;
			me.mediaGridCacheContent = nil;
		}
		[me reloadTableDebounced];
	};

	if ([kind isEqualToString:@"stories"]){
		[[TGClient shared] storiesForChat:self.chatId completion:done];
	} else if ([kind isEqualToString:@"gifts"]){
		if (self.userId)
			[[TGClient shared] giftsForUser:self.userId completion:done];
		else
			done(@[]);
	} else if ([kind isEqualToString:@"groups"]){
		[[TGClient shared] groupsInCommonWithUser:self.userId completion:done];
	} else {
		if (!filterForCount){
			[self.loadingMediaKinds removeObject:kind];
			return;
		}
		[[TGClient shared] mediaInChat:self.chatId filter:filterForCount completion:done];
	}
}

/// A tab only loads when its section is on screen; the details card stays the
/// first thing an open profile costs.
- (void)loadVisibleMediaTabIfNeeded {
	CGRect section = [self.tableView rectForSection:kSectionMedia];
	if (!CGRectIntersectsRect(section, self.tableView.bounds))
		return;
	NSString *kind = [self selectedMediaKind];
	if (kind)
		[self fetchMediaForKind:kind];
}

/// The bar across the top of the shared section, in their order: Media,
/// Files, Music, Voice, Links, Groups, then Stories and Gifts when they have
/// something to show. The category a profile was set to open on moves first.
- (NSArray *)currentMediaTabs {
	NSMutableArray *out = [NSMutableArray array];
	// Your own user id is also your Saved Messages chat. Those tabs belong to that
	// chat's profile; the one others see has only what you publish.
	if (!self.isOwnProfile || [self showsSavedMessages]){
		[out addObject:@{@"title" : @"Media", @"kind" : @"media"}];
		[out addObject:@{@"title" : @"Files", @"kind" : @"files"}];
		[out addObject:@{@"title" : @"Music", @"kind" : @"music"}];
		[out addObject:@{@"title" : @"Voice", @"kind" : @"voice"}];
		[out addObject:@{@"title" : @"Links", @"kind" : @"links"}];
	}
	if (self.commonGroupCount > 0)
		[out addObject:@{@"title" : @"Groups", @"kind" : @"groups"}];
	if (self.stories.count)
		[out addObject:@{@"title" : @"Stories", @"kind" : @"stories"}];
	if (self.gifts.count)
		[out addObject:@{@"title" : @"Gifts", @"kind" : @"gifts"}];

	// main_profile_tab moves the chosen pane to the front. "posts" and "gifs"
	// have no pane of their own here; both read as Media.
	// It is not the selected tab: tabs do not change places when tapped.
	NSString *chosen = self.mainMediaKind;
	if ([chosen isEqualToString:@"posts"] || [chosen isEqualToString:@"gifs"])
		chosen = @"media";
	for (NSUInteger i = 0; i < out.count; i++){
		if ([out[i][@"kind"] isEqualToString:chosen]){
			if (i > 0)
				[out exchangeObjectAtIndex:0 withObjectAtIndex:i];
			break;
		}
	}
	return out;
}

/// A tab tap: the pane's first page is fetched now, not when the profile was
/// opened. The grid caches are per kind, so they are dropped with the switch.
- (void)mediaTabSelected:(NSString *)kind {
	if (!kind.length)
		return;
	self.storedMediaKind = kind;
	self.storyGridCellCache = nil;
	self.mediaGridCacheContent = nil;
	[self.thumbnailsRequested removeAllObjects];
	[self fetchMediaForKind:kind];
	CGPoint offset = self.tableView.contentOffset;
	CGFloat mediaTop = [self.tableView rectForHeaderInSection:kSectionMedia].origin.y;
	[self.tableView reloadData];
	CGFloat maxY = self.tableView.contentSize.height - self.tableView.bounds.size.height;
	maxY = MAX(0, maxY);
	if (offset.y > maxY + TGMetricHairline ||
			offset.y < mediaTop - self.tableView.bounds.size.height)
		offset.y = mediaTop;
	offset.y = MIN(MAX(offset.y, 0), maxY);
	[self.tableView setContentOffset:offset animated:NO];
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

/// The poster's face in the corner of a story tile, and the mark that says a
/// tile is a video rather than a picture.
static const CGFloat kStoryFace      = 26.0f;
static const CGFloat kVideoMark      = 16.0f;
static const CGFloat kVideoMarkInset = TGMetricPadWide;

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
	NSInteger count = MIN(dataCount, 120);
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
- (void)photoTileTapped:(UIButton *)button {
	NSInteger index = button.tag - 600;
	if (index >= 0 && index < (NSInteger)self.photos.count) {
		[TGMediaViewer presentItems:self.photos startAt:index inChat:self.chatId];
	}
}

- (UITableViewCell *)mediaGridCellForTableView:(UITableView *)tableView atRow:(NSInteger)row {
	static NSString *const kGridReuseId = @"TGMediaGridRowCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGridReuseId];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:kGridReuseId];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.backgroundColor = [UIColor clearColor];
	}

	for (UIView *v in [cell.contentView.subviews copy]) {
		[v removeFromSuperview];
	}

	NSString *kind = [self selectedMediaKind];
	BOOL storyKind = [kind isEqualToString:@"stories"];
	BOOL giftKind  = [kind isEqualToString:@"gifts"];

	NSArray *rows = [self selectedMediaRows];
	CGFloat width = tableView.bounds.size.width;
	CGFloat side  = [[self class] storySideForWidth:width];

	for (NSInteger c = 0; c < kStoryGridCols; c++) {
		NSInteger i = row * kStoryGridCols + c;
		if (i >= (NSInteger)rows.count)
			break;

		NSDictionary *tile = rows[i];
		CGRect frame = CGRectMake(c * (side + kStoryGridGap), 0, side, side);

		if (giftKind) {
			NSString *emoji = tile[@"emoji"];
			UIImageView *glyph = [[UIImageView alloc] initWithFrame:frame];
			glyph.image = [[self class] giftTileGlyph:emoji side:side];
			glyph.contentMode = UIViewContentModeScaleAspectFit;
			glyph.backgroundColor = [[TGTheme shared] fileTileColour];
			glyph.clipsToBounds = YES;
			[cell.contentView addSubview:glyph];

			NSInteger userId = [tile[@"senderUserId"] longLongValue];
			NSString *name = [[TGClient shared] nameForUserId:userId];
			NSString *first = name.length ? [name substringToIndex:1].uppercaseString : @"?";
			UIButton *face = [UIButton buttonWithType:UIButtonTypeCustom];
			face.frame = CGRectMake(frame.origin.x + TGMetricPadSmall, TGMetricPadSmall, kStoryFace, kStoryFace);
			face.layer.cornerRadius = TGMetricCornerCard;
			face.layer.masksToBounds = YES;
			face.enabled = NO;
			[face setImage:[TGIcons avatarWithInitials:first size:kStoryFace colourId:userId]
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

		NSNumber *fileId = storyKind
				? (tile[@"thumbPhotoId"] ?: tile[@"photoId"])
				: (tile[@"photoId"] ?: tile[@"thumbPhotoId"]);

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:frame];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		[cell.contentView addSubview:thumb];

		if (storyKind || [tile[@"kind"] isEqualToString:@"messageVideo"] || [tile[@"isVideo"] boolValue]) {
			if ([tile[@"isVideo"] boolValue] || [tile[@"kind"] isEqualToString:@"messageVideo"]) {
				UIImageView *mark = [[UIImageView alloc] initWithFrame:
						CGRectMake(side - kVideoMarkInset, side - kVideoMarkInset, kVideoMark, kVideoMark)];
				mark.image = [TGIcons glyphNamed:@"video" colour:[[TGTheme shared] onMediaColour] side:kVideoMark];
				[thumb addSubview:mark];
			}
		}

		UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
		tap.frame = frame;
		if (storyKind) {
			tap.tag = 500 + i;
			[tap addTarget:self action:@selector(storyTileTapped:) forControlEvents:UIControlEventTouchUpInside];
		} else {
			tap.tag = 600 + i;
			[tap addTarget:self action:@selector(photoTileTapped:) forControlEvents:UIControlEventTouchUpInside];
		}
		[cell.contentView addSubview:tap];

		if ([fileId integerValue] > 0) {
			__weak typeof(thumb) weakThumb = thumb;
			[[TGClient shared] downloadFile:fileId.integerValue
								   priority:TGDownloadPriorityOnScreen
								 completion:^(NSString *path){
				dispatch_async(dispatch_get_main_queue(), ^{
					[TGIcons loadImageAtPath:path into:weakThumb];
				});
			}];
		}
	}

	return cell;
}

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
	NSInteger count = MIN((NSInteger)rows.count, 120);

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
				mark.image = [TGIcons glyphNamed:@"video" colour:[[TGTheme shared] onMediaColour]
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

/// The cover is downloaded once per file id and kept with the other profile
/// pictures. A 44 pt row asks for the same thumbnail the chat's track bubble
/// uses, not a 300 px render.
- (void)applyArtworkToTrackCell:(UITableViewCell *)cell
						message:(NSDictionary *)message
					  indexPath:(NSIndexPath *)indexPath {
	TGProfileTrackCell *trackCell = (TGProfileTrackCell *)cell;
	NSNumber *coverId = [message[@"albumCoverId"] isKindOfClass:NSNumber.class]
			? message[@"albumCoverId"] : nil;
	if (!coverId){
		[trackCell setArtworkImage:nil];
		return;
	}
	UIImage *cover = self.coverImages[coverId];
	[trackCell setArtworkImage:cover];
	if (cover || [self.thumbnailsRequested containsObject:coverId])
		return;
	[self.thumbnailsRequested addObject:coverId];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:coverId.integerValue
						   priority:TGDownloadPriorityOnScreen
						 completion:^(NSString *path){
		if (!path.length)
			return;
		UIImage *image = [TGIcons decodedImageAtPath:path
										fittingSize:CGSizeMake(TGMetricTrackArt, TGMetricTrackArt)
											   fill:YES
											  scale:[UIScreen mainScreen].scale];
		UIImage *rounded = [TGIcons roundedImage:image
										 size:CGSizeMake(TGMetricTrackArt, TGMetricTrackArt)
									   radius:TGMetricCornerSmall
									  corners:UIRectCornerAllCorners];
		TGProfileViewController *me = weakSelf;
		if (!rounded || !me)
			return;
		me.coverImages[coverId] = rounded;
		[me.tableView reloadRowsAtIndexPaths:@[indexPath]
							withRowAnimation:UITableViewRowAnimationNone];
	}];
}

/// The host of the first URL entity in a message, or nil. The profile's Links
/// tab shows where a link goes, not the paragraph it arrived in.
- (NSString *)linkDomainForMessage:(NSDictionary *)message {
	return TGProfileFirstURL(message[@"text"], message[@"entities"]).host.lowercaseString;
}

/// What the selected tab shows; nil for the photo strip, which is not a list.
- (NSString *)selectedMediaKind {
	NSString *kind = self.storedMediaKind;
	// Edit Profile still offers "posts" and "gifs"; there is no pane for
	// either here, so both open the media grid rather than a dead kind.
	if ([kind isEqualToString:@"posts"] || [kind isEqualToString:@"gifs"])
		kind = @"media";
	// The answer is only valid while that kind still has a tab: stories end,
	// gifts empty out, and holding a dead kind would render a toolbar
	// selection that no longer matches. Falling back to the photo strip is
	// what the official clients do.
	NSArray *tabs = [self currentMediaTabs];
	for (NSDictionary *tab in tabs)
		if ([tab[@"kind"] isEqualToString:kind])
			return kind;
	return tabs.firstObject[@"kind"];
}

/// Saved Messages' own profile: the chat opened it, and the chat passes a search.
/// Settings' My Profile reaches the same id without one.
- (BOOL)showsSavedMessages {
	return self.chatId && self.chatId == [[TGClient shared] savedMessagesChatId] &&
			self.onSearchTapped != nil;
}

/// The rows behind the selected tab, for the list-shaped categories.
- (NSArray *)selectedMediaRows {
	NSString *kind = [self selectedMediaKind];
	if ([kind isEqualToString:@"media"])   return self.photos ?: @[];
	if ([kind isEqualToString:@"files"])   return self.files ?: @[];
	if ([kind isEqualToString:@"music"])   return self.music ?: @[];
	if ([kind isEqualToString:@"voice"])   return self.voice ?: @[];
	if ([kind isEqualToString:@"links"])   return self.links ?: @[];
	if ([kind isEqualToString:@"groups"])  return self.groupsInCommon ?: @[];
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

/// Displays full-screen view for the selected story.
- (void)openStoryAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.stories.count)
		return;
	// The profile grid and the chat list's strip open the same viewer. The
	// old inline backdrop lived here and knew nothing about openStory,
	// reactions or the own-story menu.
	TGStoryViewerViewController *viewer = [[TGStoryViewerViewController alloc]
			initWithChatId:self.chatId
					 title:self.title ?: @"Stories"
				   stories:self.stories
				startIndex:index
				 canManage:self.chatId == [[TGClient shared] savedMessagesChatId]];
	UINavigationController *nav = [[UINavigationController alloc]
			initWithRootViewController:viewer];
	nav.navigationBar.barStyle = UIBarStyleBlack;
	nav.navigationBar.translucent = YES;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)loadMoreMediaForCurrentTab {
	if (self.isLoadingMoreMedia) return;

	NSString *kind = [self selectedMediaKind];
	NSString *filter = nil;
	NSArray *currentList = nil;

	if ([kind isEqualToString:@"media"]) {
		filter = @"searchMessagesFilterPhotoAndVideo";
		currentList = self.photos;
	} else if ([kind isEqualToString:@"files"]) {
		filter = @"searchMessagesFilterDocument";
		currentList = self.files;
	} else if ([kind isEqualToString:@"music"]) {
		filter = @"searchMessagesFilterAudio";
		currentList = self.music;
	} else if ([kind isEqualToString:@"voice"]) {
		filter = @"searchMessagesFilterVoiceAndVideoNote";
		currentList = self.voice;
	} else if ([kind isEqualToString:@"links"]) {
		filter = @"searchMessagesFilterUrl";
		currentList = self.links;
	}

	if (!filter || !currentList.count) return;

	int64_t lastId = [currentList.lastObject[@"id"] longLongValue];
	if (!lastId) return;

	self.isLoadingMoreMedia = YES;
	__weak typeof(self) weakProfile = self;
	[[TGClient shared] mediaInChat:self.chatId filter:filter fromMessageId:lastId limit:60 completion:^(NSArray *more){
		dispatch_async(dispatch_get_main_queue(), ^{
			TGProfileViewController *me = weakProfile;
			if (!me) return;
			me.isLoadingMoreMedia = NO;
			if (!more.count) return;

			if ([kind isEqualToString:@"media"]) {
				me.photos = TGMediaPageAppending(me.photos, more);
				me.storyGridCellCache = nil;
				me.mediaGridCacheContent = nil;
			} else if ([kind isEqualToString:@"files"]) {
				me.files = TGMediaPageAppending(me.files, more);
			} else if ([kind isEqualToString:@"music"]) {
				me.music = TGMediaPageAppending(me.music, more);
			} else if ([kind isEqualToString:@"voice"]) {
				me.voice = TGMediaPageAppending(me.voice, more);
			} else if ([kind isEqualToString:@"links"]) {
				me.links = TGMediaPageAppending(me.links, more);
			}
			[me reloadTableDebounced];
		});
	}];
}

@end
