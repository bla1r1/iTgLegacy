#import "TGMediaViewer.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

// The chrome sits over the picture rather than beside it, which is what makes
// the picture the whole screen. Both strips fade out on a tap and come back on
// the next one, as theirs do.
static const CGFloat kTopBar    = 54.0f;
static const CGFloat kBottomBar = 62.0f;
static const NSInteger kZoomTag = 0x7001;

@interface TGMediaViewer () <UIScrollViewDelegate>
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) int64_t chatId;

@property (nonatomic, strong) TGMediaViewer *self_;   // held up while on screen
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, assign) BOOL chromeHidden;

/// One page per item, built lazily: twenty full-size pictures at once is more
/// memory than this device has.
@property (nonatomic, strong) NSMutableDictionary *pages;     // index -> UIView
@property (nonatomic, strong) NSMutableDictionary *originals; // index -> UIImage
@property (nonatomic, strong) NSMutableSet *requested;

@property (nonatomic, strong) MPMoviePlayerController *movie;
@property (nonatomic, assign) NSInteger moviePage;
@property (nonatomic, strong) NSTimer *movieTimer;
@property (nonatomic, strong) UISlider *scrubber;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UILabel *timeLabel;
@end

@implementation TGMediaViewer

+ (void)presentItems:(NSArray *)items startAt:(NSInteger)index inChat:(int64_t)chatId {
	NSMutableArray *media = [NSMutableArray array];
	NSInteger adjusted = 0;
	for (NSUInteger i = 0; i < items.count; i++){
		NSDictionary *m = items[i];
		NSString *kind = m[@"kind"];
		BOOL isPhoto = [kind isEqualToString:@"messagePhoto"];
		BOOL isVideo = [kind isEqualToString:@"messageVideo"];
		if (!isPhoto && !isVideo)
			continue;
		if ((NSInteger)i <= index)
			adjusted = media.count;      // where the tapped one landed
		[media addObject:m];
	}
	if (!media.count)
		return;

	TGMediaViewer *viewer = [[TGMediaViewer alloc] init];
	viewer.items = media;
	viewer.index = MIN(MAX(adjusted, 0), (NSInteger)media.count - 1);
	viewer.chatId = chatId;
	[viewer present];
}

- (id)init {
	if ((self = [super init])){
		_pages = [NSMutableDictionary dictionary];
		_originals = [NSMutableDictionary dictionary];
		_requested = [NSMutableSet set];
		_moviePage = NSNotFound;
	}
	return self;
}

#pragma mark - presenting

- (void)present {
	self.self_ = self;      // nothing else owns this while it is up

	self.window = [UIApplication sharedApplication].keyWindow;
	CGRect bounds = self.window.bounds;

	self.backdrop = [[UIView alloc] initWithFrame:bounds];
	self.backdrop.backgroundColor = [UIColor blackColor];
	self.backdrop.alpha = 0;
	[self.window addSubview:self.backdrop];

	self.pager = [[UIScrollView alloc] initWithFrame:bounds];
	self.pager.pagingEnabled = YES;
	self.pager.delegate = self;
	self.pager.showsHorizontalScrollIndicator = NO;
	self.pager.contentSize = CGSizeMake(bounds.size.width * self.items.count,
										bounds.size.height);
	self.pager.contentOffset = CGPointMake(bounds.size.width * self.index, 0);
	[self.backdrop addSubview:self.pager];

	[self buildChrome];

	[self.backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(toggleChrome)]];
	// Their viewer closes on a flick down, which is quicker than reaching for
	// a button with the hand that is already holding the phone.
	UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc]
			initWithTarget:self action:@selector(dismiss)];
	down.direction = UISwipeGestureRecognizerDirectionDown;
	[self.backdrop addGestureRecognizer:down];

	[self loadPagesAround:self.index];
	[self refreshChrome];

	[UIView animateWithDuration:0.2 animations:^{ self.backdrop.alpha = 1; }];
}

- (void)dismiss {
	[self stopMovie];
	[UIView animateWithDuration:0.2 animations:^{
		self.backdrop.alpha = 0;
	} completion:^(BOOL done){
		[self.backdrop removeFromSuperview];
		self.self_ = nil;       // and now it can go
	}];
}

#pragma mark - chrome

- (void)buildChrome {
	CGRect bounds = self.backdrop.bounds;
	UIColor *plate = [UIColor colorWithWhite:0 alpha:0.55f];

	self.topBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, bounds.size.width, kTopBar)];
	self.topBar.backgroundColor = plate;
	[self.backdrop addSubview:self.topBar];

	self.counterLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(70, 20, bounds.size.width - 140, 18)];
	self.counterLabel.font = [UIFont boldSystemFontOfSize:15];
	self.counterLabel.textAlignment = NSTextAlignmentCenter;
	self.counterLabel.textColor = [UIColor whiteColor];
	self.counterLabel.backgroundColor = [UIColor clearColor];
	[self.topBar addSubview:self.counterLabel];

	self.dateLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(70, 36, bounds.size.width - 140, 14)];
	self.dateLabel.font = [UIFont systemFontOfSize:11];
	self.dateLabel.textAlignment = NSTextAlignmentCenter;
	self.dateLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7f];
	self.dateLabel.backgroundColor = [UIColor clearColor];
	[self.topBar addSubview:self.dateLabel];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
	close.frame = CGRectMake(4, 18, 62, 30);
	[close setTitle:@"Done" forState:UIControlStateNormal];
	close.titleLabel.font = [UIFont systemFontOfSize:15];
	[close addTarget:self action:@selector(dismiss)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.topBar addSubview:close];

	self.bottomBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - kBottomBar, bounds.size.width, kBottomBar)];
	self.bottomBar.backgroundColor = plate;
	[self.backdrop addSubview:self.bottomBar];

	self.captionLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(12, 4, bounds.size.width - 88, 34)];
	self.captionLabel.font = [UIFont systemFontOfSize:13];
	self.captionLabel.numberOfLines = 2;
	self.captionLabel.textColor = [UIColor whiteColor];
	self.captionLabel.backgroundColor = [UIColor clearColor];
	[self.bottomBar addSubview:self.captionLabel];

	UIButton *save = [UIButton buttonWithType:UIButtonTypeCustom];
	save.frame = CGRectMake(bounds.size.width - 74, 4, 68, 34);
	[save setTitle:@"Save" forState:UIControlStateNormal];
	save.titleLabel.font = [UIFont systemFontOfSize:15];
	[save addTarget:self action:@selector(saveCurrent)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar addSubview:save];

	// The video strip lives in the bottom bar and only appears on a video page.
	self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.playButton.frame = CGRectMake(8, 38, 30, 22);
	[self.playButton setImage:[TGIcons play] forState:UIControlStateNormal];
	self.playButton.tintColor = [UIColor whiteColor];
	[self.playButton addTarget:self action:@selector(toggleMovie)
			  forControlEvents:UIControlEventTouchUpInside];
	self.playButton.hidden = YES;
	[self.bottomBar addSubview:self.playButton];

	self.scrubber = [[UISlider alloc] initWithFrame:
			CGRectMake(42, 38, bounds.size.width - 104, 22)];
	self.scrubber.minimumTrackTintColor = [[TGTheme shared] accentColour];
	[self.scrubber addTarget:self action:@selector(scrubberMoved)
			forControlEvents:UIControlEventValueChanged];
	self.scrubber.hidden = YES;
	[self.bottomBar addSubview:self.scrubber];

	self.timeLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(bounds.size.width - 58, 38, 52, 22)];
	self.timeLabel.font = [UIFont systemFontOfSize:11];
	self.timeLabel.textColor = [UIColor whiteColor];
	self.timeLabel.textAlignment = NSTextAlignmentRight;
	self.timeLabel.backgroundColor = [UIColor clearColor];
	self.timeLabel.hidden = YES;
	[self.bottomBar addSubview:self.timeLabel];
}

- (void)toggleChrome {
	self.chromeHidden = !self.chromeHidden;
	[UIView animateWithDuration:0.2 animations:^{
		self.topBar.alpha = self.chromeHidden ? 0 : 1;
		self.bottomBar.alpha = self.chromeHidden ? 0 : 1;
	}];
}

- (void)refreshChrome {
	NSDictionary *item = self.items[self.index];

	self.counterLabel.text = [NSString stringWithFormat:@"%ld of %lu",
			(long)(self.index + 1), (unsigned long)self.items.count];

	static NSDateFormatter *when = nil;
	if (!when){
		when = [[NSDateFormatter alloc] init];
		when.dateStyle = NSDateFormatterMediumStyle;
		when.timeStyle = NSDateFormatterShortStyle;
	}
	NSString *sender = [[TGClient shared] nameForUserId:
			[item[@"senderId"] longLongValue]];
	NSString *date = [when stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[item[@"date"] doubleValue]]];
	self.dateLabel.text = sender.length
			? [NSString stringWithFormat:@"%@ - %@", sender, date] : date;

	self.captionLabel.text = item[@"text"] ?: @"";

	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	self.playButton.hidden = !isVideo;
	self.scrubber.hidden = !isVideo;
	self.timeLabel.hidden = !isVideo;
	self.captionLabel.frame = CGRectMake(12, 4,
			self.backdrop.bounds.size.width - 88, isVideo ? 30 : 34);
}

#pragma mark - pages

/// The file this item *is*, not the one it shows. A video message carries both
/// - "docId" is the video and "photoId" is its poster frame - so preferring
/// photoId handed the movie player a JPEG and it sat there doing nothing.
- (NSNumber *)fileIdForItem:(NSDictionary *)item {
	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	NSNumber *fileId = isVideo ? item[@"docId"] : (item[@"bigPhotoId"] ?: item[@"photoId"]);
	if ([fileId isKindOfClass:NSNumber.class])
		return fileId;
	// A photo with no photoId, or a video with no docId: fall back to whatever
	// the other key holds rather than showing nothing at all.
	fileId = isVideo ? item[@"photoId"] : item[@"docId"];
	return [fileId isKindOfClass:NSNumber.class] ? fileId : nil;
}

/// Only the page in view and its two neighbours are built. Everything else is
/// dropped, so paging through a long chat does not walk the device out of
/// memory one full-size picture at a time.
- (void)loadPagesAround:(NSInteger)centre {
	CGRect bounds = self.backdrop.bounds;

	for (NSNumber *key in [self.pages allKeys]){
		NSInteger i = key.integerValue;
		if (labs(i - centre) <= 1)
			continue;
		[(UIView *)self.pages[key] removeFromSuperview];
		[self.pages removeObjectForKey:key];
		[self.originals removeObjectForKey:key];
	}

	for (NSInteger i = MAX(0, centre - 1);
		 i <= MIN((NSInteger)self.items.count - 1, centre + 1); i++){
		if (self.pages[@(i)])
			continue;

		UIScrollView *zoom = [[UIScrollView alloc] initWithFrame:
				CGRectMake(bounds.size.width * i, 0, bounds.size.width, bounds.size.height)];
		zoom.minimumZoomScale = 1.0f;
		zoom.maximumZoomScale = 4.0f;
		zoom.delegate = self;
		zoom.showsHorizontalScrollIndicator = NO;
		zoom.showsVerticalScrollIndicator = NO;
		zoom.tag = kZoomTag;

		UIImageView *picture = [[UIImageView alloc] initWithFrame:zoom.bounds];
		picture.contentMode = UIViewContentModeScaleAspectFit;
		picture.tag = kZoomTag + 1;
		[zoom addSubview:picture];

		[self.pager addSubview:zoom];
		self.pages[@(i)] = zoom;

		[self fetchOriginalForPage:i into:picture];
	}
}

/// The bubble's copy is a thumbnail scaled down to fit a 200pt bubble, so it
/// cannot be what a full screen shows. The original is fetched here and drawn
/// once it lands; the thumbnail stands in until then rather than leaving the
/// screen black.
- (void)fetchOriginalForPage:(NSInteger)page into:(UIImageView *)picture {
	NSDictionary *item = self.items[page];
	NSNumber *fileId = [self fileIdForItem:item];
	if (!fileId)
		return;

	CGSize screen = self.backdrop.bounds.size;
	CGFloat scale = [UIScreen mainScreen].scale;

	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	if (isVideo){
		// A video's poster frame is its thumbnail; the file itself is only
		// fetched when the play button is pressed. Fitted, not filled: the
		// shared loader crops to the view, and cropping a poster to a 3:2
		// screen cuts the middle out of a portrait video.
		NSNumber *thumb = item[@"photoId"];
		if (![thumb isKindOfClass:NSNumber.class])
			return;
		[[TGClient shared] downloadFile:thumb.integerValue completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *poster = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
											fittingSize:screen fill:NO scale:scale];
				if (!poster)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{ picture.image = poster; });
			});
		}];
		return;
	}

	if ([self.requested containsObject:fileId])
		return;
	[self.requested addObject:fileId];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				image = [UIImage convertFromWebP:path compressedData:nil error:nil];
			// Fitted to the screen rather than the bubble: a 4S has 512MB and
			// a 3000px photo decoded whole is most of what is left of it.
			image = [TGIcons decodedImage:image fittingSize:screen fill:NO scale:scale];
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				weakSelf.originals[@(page)] = image;
				picture.image = image;
			});
		});
	}];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return (scrollView == self.pager) ? nil : [scrollView viewWithTag:kZoomTag + 1];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.pager)
		return;
	NSInteger page = (NSInteger)roundf(scrollView.contentOffset.x /
			MAX(1.0f, scrollView.bounds.size.width));
	page = MIN(MAX(page, 0), (NSInteger)self.items.count - 1);
	if (page == self.index)
		return;

	// Leaving a video's page has to stop it, or it goes on playing behind a
	// picture two pages away.
	if (self.moviePage != NSNotFound && page != self.moviePage)
		[self stopMovie];

	self.index = page;
	[self loadPagesAround:page];
	[self refreshChrome];
}

#pragma mark - video

- (void)toggleMovie {
	if (self.movie){
		if (self.movie.playbackState == MPMoviePlaybackStatePlaying){
			[self.movie pause];
			[self.playButton setImage:[TGIcons play] forState:UIControlStateNormal];
		} else {
			[self.movie play];
			[self.playButton setImage:[TGIcons pause] forState:UIControlStateNormal];
		}
		return;
	}

	NSDictionary *item = self.items[self.index];
	NSNumber *fileId = [self fileIdForItem:item];
	if (!fileId)
		return;

	self.timeLabel.text = @"...";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path.length){
			weakSelf.timeLabel.text = @"--:--";
			return;
		}
		[weakSelf startMovieAtPath:path];
	}];
}

/// MPMoviePlayerController is the only decoder this OS offers, but its own
/// controls take over the screen. Embedding it with the controls switched off
/// and driving it from the strip below keeps the viewer's chrome consistent
/// between a picture and a video.
- (void)startMovieAtPath:(NSString *)path {
	UIView *page = self.pages[@(self.index)];
	if (!page)
		return;

	MPMoviePlayerController *movie = [[MPMoviePlayerController alloc]
			initWithContentURL:[NSURL fileURLWithPath:path]];
	movie.controlStyle = MPMovieControlStyleNone;
	movie.scalingMode = MPMovieScalingModeAspectFit;
	movie.view.frame = page.bounds;
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
	movie.view.backgroundColor = [UIColor clearColor];
	[page addSubview:movie.view];
	[movie prepareToPlay];
	[movie play];

	self.movie = movie;
	self.moviePage = self.index;
	[self.playButton setImage:[TGIcons pause] forState:UIControlStateNormal];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(movieFinished)
				name:MPMoviePlayerPlaybackDidFinishNotification object:movie];

	self.movieTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self
			selector:@selector(movieTicked) userInfo:nil repeats:YES];
}

- (void)movieTicked {
	if (!self.movie || self.movie.duration <= 0)
		return;
	if (!self.scrubber.tracking)
		self.scrubber.value = (float)(self.movie.currentPlaybackTime /
									  self.movie.duration);
	NSInteger left = (NSInteger)MAX(0.0,
			self.movie.duration - self.movie.currentPlaybackTime);
	self.timeLabel.text = [NSString stringWithFormat:@"-%ld:%02ld",
			(long)(left / 60), (long)(left % 60)];
}

- (void)scrubberMoved {
	if (self.movie && self.movie.duration > 0)
		self.movie.currentPlaybackTime = self.scrubber.value * self.movie.duration;
}

- (void)movieFinished {
	[self.playButton setImage:[TGIcons play] forState:UIControlStateNormal];
	self.scrubber.value = 0;
	if (self.movie)
		self.movie.currentPlaybackTime = 0;
}

- (void)stopMovie {
	[self.movieTimer invalidate];
	self.movieTimer = nil;
	if (!self.movie)
		return;
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:MPMoviePlayerPlaybackDidFinishNotification object:self.movie];
	[self.movie stop];
	[self.movie.view removeFromSuperview];
	self.movie = nil;
	self.moviePage = NSNotFound;
	[self.playButton setImage:[TGIcons play] forState:UIControlStateNormal];
	self.scrubber.value = 0;
}

#pragma mark - saving

- (void)saveCurrent {
	UIImage *image = self.originals[@(self.index)];
	if (!image){
		UIView *page = self.pages[@(self.index)];
		image = [(UIImageView *)[page viewWithTag:kZoomTag + 1] image];
	}
	if (!image)
		return;
	UIImageWriteToSavedPhotosAlbum(image, self,
			@selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
			message:(error ? @"Could not save" : @"Saved to Camera Roll")
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)dealloc {
	[self.movieTimer invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// vim:ft=objc
