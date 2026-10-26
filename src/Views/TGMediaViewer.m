#import "TGMediaViewer.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

// The chrome sits over the picture rather than beside it, which is what makes
// the picture the whole screen. Both strips fade out on a tap and come back on
// the next one, as theirs do.
static const CGFloat kTopBar    = TGMetricViewerTopBar;
static const CGFloat kBottomBar = TGMetricViewerBottomBar;
static const NSInteger kZoomTag = 0x7001;

/// A view whose whole job is to keep the player layer filling it. A CALayer
/// does not autoresize, and this app rotates - the old movie view had its
/// frame set once too, and came out the wrong shape after a turn.
@interface TGPlayerView : UIView
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@end

@implementation TGPlayerView
- (void)setPlayerLayer:(AVPlayerLayer *)playerLayer {
	[_playerLayer removeFromSuperlayer];
	_playerLayer = playerLayer;
	if (playerLayer){
		playerLayer.frame = self.bounds;
		[self.layer addSublayer:playerLayer];
	}
}
- (void)layoutSubviews {
	[super layoutSubviews];
	self.playerLayer.frame = self.bounds;
}
@end

@interface TGMediaViewer () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
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
/// Where the drag that may dismiss the viewer started, and the page it is
/// carrying. Zero width means no drag is in progress.
@property (nonatomic, assign) CGPoint dragOrigin;
@property (nonatomic, assign) BOOL dragging;

/// One page per item, built lazily: twenty full-size pictures at once is more
/// memory than this device has.
@property (nonatomic, strong) NSMutableDictionary *pages;     // index -> UIView
@property (nonatomic, strong) NSMutableDictionary *originals; // index -> UIImage
@property (nonatomic, strong) NSMutableSet *requested;

/// AVPlayer rather than MPMoviePlayerController, which is a view controller
/// with opinions: it brings its own chrome, its own rotation, and a
/// currentPlaybackTime that seeks to the nearest keyframe, so dragging the
/// scrubber jumped in half-second steps. A layer plays where it is put.
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) TGPlayerView *playerView;
@property (nonatomic, assign) NSInteger moviePage;
@property (nonatomic, strong) NSTimer *movieTimer;
@property (nonatomic, assign) BOOL movieLoops;
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
		BOOL isVideo = [kind isEqualToString:@"messageVideo"] || [kind isEqualToString:@"messageAnimation"];
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
	self.backdrop.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
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

	UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(toggleChrome)];
	[self.backdrop addGestureRecognizer:single];

	// Two taps is how a picture is zoomed everywhere else, and this viewer
	// had only the pinch - which needs two hands on a phone being held.
	UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(doubleTapped:)];
	doubleTap.numberOfTapsRequired = 2;
	[self.backdrop addGestureRecognizer:doubleTap];
	[single requireGestureRecognizerToFail:doubleTap];

	// A flick down closed it at once, whatever the finger had been doing.
	// A drag is better: the picture comes with the finger, the backdrop
	// thins as it goes, and letting go before it has gone far enough puts
	// it back - so the gesture can be changed halfway through.
	UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(dragged:)];
	drag.delegate = self;
	[self.backdrop addGestureRecognizer:drag];

	[self loadPagesAround:self.index];
	[self refreshChrome];

	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{ self.backdrop.alpha = 1; }];
}

- (void)dismiss {
	[self stopMovie];
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		self.backdrop.alpha = 0;
	} completion:^(BOOL done){
		[self.backdrop removeFromSuperview];
		self.self_ = nil;       // and now it can go
	}];
}

#pragma mark - chrome

- (void)buildChrome {
	CGRect bounds = self.backdrop.bounds;
	UIColor *plate = [[TGTheme shared] mediaOverlayColour];

	self.topBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, 0, bounds.size.width, kTopBar)];
	self.topBar.backgroundColor = plate;
	[self.backdrop addSubview:self.topBar];

	self.counterLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(TGMetricViewerTitleSide, 20, bounds.size.width - TGDoubled(TGMetricViewerTitleSide), 18)];
	self.counterLabel.font = TGFontBodyStrong();
	self.counterLabel.textAlignment = NSTextAlignmentCenter;
	self.counterLabel.textColor = [UIColor whiteColor];
	self.counterLabel.backgroundColor = [UIColor clearColor];
	[self.topBar addSubview:self.counterLabel];

	self.dateLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(TGMetricViewerTitleSide, 36, bounds.size.width - TGDoubled(TGMetricViewerTitleSide), 14)];
	self.dateLabel.font = TGFontMicro();
	self.dateLabel.textAlignment = NSTextAlignmentCenter;
	self.dateLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.dateLabel.backgroundColor = [UIColor clearColor];
	[self.topBar addSubview:self.dateLabel];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
	close.frame = CGRectMake(4, 18, 62, 30);
	[close setTitle:@"Done" forState:UIControlStateNormal];
	close.titleLabel.font = TGFontBody();
	[close addTarget:self action:@selector(dismiss)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.topBar addSubview:close];

	self.bottomBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - kBottomBar, bounds.size.width, kBottomBar)];
	self.bottomBar.backgroundColor = plate;
	[self.backdrop addSubview:self.bottomBar];

	self.captionLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(12, 4, bounds.size.width - TGMetricViewerCaptionMarginRight, 34)];
	self.captionLabel.font = TGFontCaption();
	self.captionLabel.numberOfLines = 2;
	self.captionLabel.textColor = [UIColor whiteColor];
	self.captionLabel.backgroundColor = [UIColor clearColor];
	[self.bottomBar addSubview:self.captionLabel];

	UIButton *save = [UIButton buttonWithType:UIButtonTypeCustom];
	save.frame = CGRectMake(bounds.size.width - 74, 4, 68, 34);
	[save setTitle:@"Save" forState:UIControlStateNormal];
	save.titleLabel.font = TGFontBody();
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
			CGRectMake(42, 38, bounds.size.width - TGMetricViewerScrubberMarginRight, 22)];
	self.scrubber.minimumTrackTintColor = [[TGTheme shared] accentColour];
	[self.scrubber addTarget:self action:@selector(scrubberMoved)
			forControlEvents:UIControlEventValueChanged];
	self.scrubber.hidden = YES;
	[self.bottomBar addSubview:self.scrubber];

	self.timeLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(bounds.size.width - 58, 38, 52, 22)];
	self.timeLabel.font = TGFontMicro();
	self.timeLabel.textColor = [UIColor whiteColor];
	self.timeLabel.textAlignment = NSTextAlignmentRight;
	self.timeLabel.backgroundColor = [UIColor clearColor];
	self.timeLabel.hidden = YES;
	[self.bottomBar addSubview:self.timeLabel];
}

- (void)toggleChrome {
	self.chromeHidden = !self.chromeHidden;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
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
	BOOL isAnim = [item[@"kind"] isEqualToString:@"messageAnimation"];
	self.playButton.hidden = !isVideo && !isAnim;
	self.scrubber.hidden = !isVideo;
	self.timeLabel.hidden = !isVideo;
	self.captionLabel.frame = CGRectMake(12, 4,
			self.backdrop.bounds.size.width - TGMetricViewerCaptionMarginRight, (isVideo || isAnim) ? 30 : 34);
}

#pragma mark - pages

/// The file this item *is*, not the one it shows. A video message carries both
/// - "docId" is the video and "photoId" is its poster frame - so preferring
/// photoId handed the movie player a JPEG and it sat there doing nothing.
- (NSNumber *)fileIdForItem:(NSDictionary *)item {
	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"] || [item[@"kind"] isEqualToString:@"messageAnimation"];
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
		zoom.minimumZoomScale = TGMetricZoomMin;
		zoom.maximumZoomScale = TGMetricZoomMax;
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

/// Downloads and displays full-resolution media, using thumbnail as placeholder.
- (void)fetchOriginalForPage:(NSInteger)page into:(UIImageView *)picture {
	NSDictionary *item = self.items[page];
	NSNumber *fileId = [self fileIdForItem:item];
	if (!fileId)
		return;

	CGSize screen = self.backdrop.bounds.size;
	CGFloat scale = [UIScreen mainScreen].scale;

	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	BOOL isAnim = [item[@"kind"] isEqualToString:@"messageAnimation"];
	if (isVideo || isAnim){
		// A video/GIF poster frame is its thumbnail; the file itself is only
		// fetched when the play button is pressed (or auto-started for GIFs).
		NSNumber *thumb = item[@"photoId"];
		if ([thumb isKindOfClass:NSNumber.class]){
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
		}
		if (isAnim && page == self.index){
			[self toggleMovie];
		}
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

/// A picture smaller than the screen sticks to the top left as it is zoomed
/// out, which is the usual scroll view behaviour and the wrong one here.
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
	if (scrollView == self.pager)
		return;
	UIView *picture = [scrollView viewWithTag:kZoomTag + 1];
	if (!picture)
		return;
	CGSize bounds = scrollView.bounds.size;
	CGRect frame = picture.frame;
	frame.origin.x = frame.size.width  < bounds.width
			? TGCenteredOrigin(bounds.width, frame.size.width) : 0;
	frame.origin.y = frame.size.height < bounds.height
			? TGCenteredOrigin(bounds.height, frame.size.height) : 0;
	picture.frame = frame;
}

/// The page the pager is on, which is where a zoom or a drag applies.
- (UIScrollView *)currentPage {
	return self.pages[@(self.index)];
}

- (void)doubleTapped:(UITapGestureRecognizer *)tap {
	UIScrollView *page = [self currentPage];
	if (!page)
		return;
	if (page.zoomScale > page.minimumZoomScale + TGAlphaEpsilon){
		[page setZoomScale:page.minimumZoomScale animated:YES];
		return;
	}
	// Zoomed about the point that was tapped rather than about the middle,
	// so the thing being looked at stays where it is.
	CGPoint at = [tap locationInView:[page viewWithTag:kZoomTag + 1]];
	CGFloat scale = MIN(page.maximumZoomScale, TGMetricZoomDoubleTap);
	CGSize size = page.bounds.size;
	[page zoomToRect:CGRectMake(at.x - TGHalf(size.width / scale),
								at.y - TGHalf(size.height / scale),
								size.width / scale, size.height / scale)
			animated:YES];
}

/// The drag only belongs to the viewer while the page is not zoomed; once it
/// is, the scroll view owns every pan inside it.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
	if (![gesture isKindOfClass:UIPanGestureRecognizer.class])
		return YES;
	UIScrollView *page = [self currentPage];
	if (page && page.zoomScale > page.minimumZoomScale + TGAlphaEpsilon)
		return NO;
	// Downwards only: sideways is the pager's, and it has to stay the
	// pager's or the viewer closes while flicking between pictures.
	CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self.backdrop];
	return fabs(velocity.y) > fabs(velocity.x);
}

- (void)dragged:(UIPanGestureRecognizer *)drag {
	UIScrollView *page = [self currentPage];
	if (!page)
		return;

	CGPoint moved = [drag translationInView:self.backdrop];

	if (drag.state == UIGestureRecognizerStateBegan){
		self.dragging = YES;
		self.dragOrigin = page.center;
		// The chrome is in the way of a picture being thrown off screen.
		[UIView animateWithDuration:TGAnimationDurationFast animations:^{
			self.topBar.alpha = TGAlphaTransparent;
			self.bottomBar.alpha = TGAlphaTransparent;
		}];
		return;
	}

	if (drag.state == UIGestureRecognizerStateChanged){
		page.center = CGPointMake(self.dragOrigin.x + TGHalf(moved.x),
								  self.dragOrigin.y + moved.y);
		// Thinner the further it has gone, down to a third - what is behind
		// the picture is where the drag is heading.
		CGFloat fade = TGAlphaOpaque - MIN(TGMetricViewerMaxFadeRatio, fabs(moved.y) / TGMetricViewerFadeDistance);
		self.backdrop.backgroundColor = [[[TGTheme shared] mediaViewerBackdropColour] colorWithAlphaComponent:fade];
		return;
	}

	if (drag.state != UIGestureRecognizerStateEnded &&
		drag.state != UIGestureRecognizerStateCancelled)
		return;

	self.dragging = NO;
	CGFloat velocity = [drag velocityInView:self.backdrop].y;
	BOOL leaves = fabs(moved.y) > TGMetricViewerDismissDistance || fabs(velocity) > TGMetricViewerDismissVelocity;
	if (leaves){
		// It keeps going the way it was thrown rather than stopping where
		// the finger let go.
		CGFloat direction = (moved.y > 0 || velocity > 0) ? 1 : -1;
		[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
			page.center = CGPointMake(page.center.x, self.dragOrigin.y +
					direction * self.backdrop.bounds.size.height);
			self.backdrop.backgroundColor = [UIColor clearColor];
		} completion:^(BOOL done){
			[self dismiss];
		}];
		return;
	}

	[UIView animateWithDuration:TGAnimationDurationMedium animations:^{
		page.center = self.dragOrigin;
		self.backdrop.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
		self.topBar.alpha = self.chromeHidden ? 0 : 1;
		self.bottomBar.alpha = self.chromeHidden ? 0 : 1;
	}];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.pager)
		return;
	NSInteger page = (NSInteger)roundf(scrollView.contentOffset.x /
			MAX(TGMetricScaleFull, scrollView.bounds.size.width));
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
	if (self.player){
		// rate rather than a playback state: AVPlayer has no "playing" flag,
		// and a rate of zero is what paused means.
		if (self.player.rate > TGPlaybackSpeedStopped){
			[self.player pause];
			[self.playButton setImage:[TGIcons play] forState:UIControlStateNormal];
		} else {
			[self.player play];
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

/// A layer in the page, playing where it was put. The controls above it are
/// the viewer's own, as the voice note's are: nothing here is the system's.
- (void)startMovieAtPath:(NSString *)path {
	UIView *page = self.pages[@(self.index)];
	if (!page)
		return;
	[self stopMovie];

	NSDictionary *item = self.items[self.index];
	self.movieLoops = [item[@"kind"] isEqualToString:@"messageAnimation"];

	// A GIF has no sound and should not duck what is already playing; a video
	// takes the session over, as any player does.
	if (!self.movieLoops){
		[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
											   error:nil];
		[[AVAudioSession sharedInstance] setActive:YES error:nil];
	}

	AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:
			[NSURL fileURLWithPath:path]];
	self.player = [AVPlayer playerWithPlayerItem:playerItem];
	self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

	self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
	self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;

	self.playerView = [[TGPlayerView alloc] initWithFrame:page.bounds];
	self.playerView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
									   UIViewAutoresizingFlexibleHeight;
	self.playerView.backgroundColor = [UIColor clearColor];
	self.playerView.playerLayer = self.playerLayer;
	[page addSubview:self.playerView];

	self.moviePage = self.index;
	[self.playButton setImage:[TGIcons pause] forState:UIControlStateNormal];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(movieFinished)
				name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];

	[self.player play];
	self.movieTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self
			selector:@selector(movieTicked) userInfo:nil repeats:YES];
}

/// Seconds, or a negative number while the item is still working out how
/// long it is - which it does not know until it is ready to play.
- (NSTimeInterval)movieDuration {
	AVPlayerItem *item = self.player.currentItem;
	if (!item)
		return -1;
	CMTime duration = item.duration;
	if (CMTIME_IS_INDEFINITE(duration) || !CMTIME_IS_VALID(duration))
		return -1;
	return CMTimeGetSeconds(duration);
}

- (NSTimeInterval)moviePosition {
	if (!self.player)
		return 0;
	CMTime now = self.player.currentTime;
	return CMTIME_IS_VALID(now) ? CMTimeGetSeconds(now) : 0;
}

- (void)movieTicked {
	NSTimeInterval duration = [self movieDuration];
	if (duration <= 0)
		return;
	NSTimeInterval at = [self moviePosition];
	if (!self.scrubber.tracking)
		self.scrubber.value = (float)(at / duration);
	NSInteger left = (NSInteger)MAX(0.0, duration - at);
	self.timeLabel.text = [NSString stringWithFormat:@"-%ld:%02ld",
			(long)(left / 60), (long)(left % 60)];
}

/// Exact, which is the point of the change: MPMoviePlayerController seeks to
/// the nearest keyframe, so a drag landed up to half a second from where the
/// finger was.
- (void)scrubberMoved {
	NSTimeInterval duration = [self movieDuration];
	if (duration <= 0)
		return;
	CMTime target = CMTimeMakeWithSeconds(self.scrubber.value * duration,
										  NSEC_PER_SEC);
	[self.player seekToTime:target
			toleranceBefore:kCMTimeZero
			 toleranceAfter:kCMTimeZero];
}

- (void)movieFinished {
	if (self.movieLoops){
		[self.player seekToTime:kCMTimeZero];
		[self.player play];
		return;
	}
	[self.playButton setImage:[TGIcons play] forState:UIControlStateNormal];
	self.scrubber.value = 0;
	[self.player seekToTime:kCMTimeZero];
}

- (void)stopMovie {
	[self.movieTimer invalidate];
	self.movieTimer = nil;
	if (!self.player)
		return;
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:AVPlayerItemDidPlayToEndTimeNotification
			object:self.player.currentItem];
	[self.player pause];
	[self.playerView removeFromSuperview];
	self.playerView = nil;
	self.playerLayer = nil;
	self.player = nil;
	self.moviePage = NSNotFound;
	self.movieLoops = NO;
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
	[TGAlertSheet showMessage:(error ? @"Could not save" : @"Saved to Camera Roll")
						title:nil inView:self];
}

- (void)dealloc {
	[self.movieTimer invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// vim:ft=objc
