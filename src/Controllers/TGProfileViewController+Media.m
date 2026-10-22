#import "TGProfileViewControllerInternal.h"

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
}

- (void)mediaTabChanged:(UISegmentedControl *)sender {
	self.selectedMediaTab = sender.selectedSegmentIndex;
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSectionMedia]
				  withRowAnimation:UITableViewRowAnimationAutomatic];
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

	CGFloat side = 76, gap = 4, x = gap;
	NSInteger limit = MIN((NSInteger)self.photos.count, 20); // only show up to 20 photos
	for (NSInteger i = 0; i < limit; i++){
		NSDictionary *m = self.photos[i];
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
		x += side + gap;
	}
	strip.contentSize = CGSizeMake(x, 80);
	self.mediaStripCell = cell;
	[self fetchVisibleThumbnails];
	return cell;
}

/// Twenty downloads at once saturate TDLib's single scheduler, and every one
/// of its progress updates is handled on the main thread - which is what made
/// the profile stutter for as long as the strip was loading. Only what is on
/// screen, plus one screen ahead, is asked for.
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

		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			[TGIcons loadImageAtPath:path into:thumb];
		}];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView == self.mediaStrip)
		[self fetchVisibleThumbnails];
}

/// A story opens full screen over the profile: the picture, the caption under
/// it, and a tap anywhere to close. A video story shows its poster frame -
/// playing one needs the file itself, which is a download this screen does not
/// start on a tap.
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

	if ([story[@"isVideo"] boolValue]){
		UILabel *note = [[UILabel alloc] initWithFrame:
				CGRectMake(0, 24, window.bounds.size.width, 18)];
		note.text = @"Video story - showing the first frame";
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
}

- (void)closeStory:(UITapGestureRecognizer *)tap {
	UIView *backdrop = tap.view;
	[UIView animateWithDuration:0.2 animations:^{ backdrop.alpha = 0; }
					 completion:^(BOOL done){ [backdrop removeFromSuperview]; }];
}

@end
