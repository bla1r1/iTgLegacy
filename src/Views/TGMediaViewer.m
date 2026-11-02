#import "TGMediaViewer.h"
#import "TGMediaStore.h"
#import "TGClient.h"
#import "TGStickerStore.h"
#import "TGSnackbar.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "UIImage+WebP.h"
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGDevShowcase.h"
#import "TGFileInfoViewController.h"
#import "TGForwardPicker.h"

// The chrome sits over the picture rather than beside it, which is what makes
// the picture the whole screen. Both strips fade out on a tap and come back on
// the next one, as theirs do.
static const CGFloat kTopBar    = TGMetricViewerTopBar;
static const CGFloat kBottomBar = TGMetricViewerBottomBar;
static const NSInteger kZoomTag = 0x7001;
static const NSInteger kSpinnerOffset = 2;   // kZoomTag + 2 is a page's spinner

/// The top bar stacks the counter over the date; Done sits beside them. The
/// bottom bar carries the caption, Save, and - on a video - a transport strip
/// under both. These are this viewer's own, named here rather than in TGStyle.
static const CGFloat kChromeInset   = TGMetricPadSmall;
static const CGFloat kCaptionInset  = TGMetricPadMedium + TGMetricPadTiny;
static const CGFloat kCaptionHeight = 34.0f;
static const CGFloat kSaveWidth     = 68.0f;
static const CGFloat kStripTop      = 38.0f;
static const CGFloat kStripHeight   = 22.0f;
static const CGFloat kPlayWidth     = 30.0f;
static const CGFloat kScrubberLeft  = 42.0f;
static const CGFloat kClockWidth    = 52.0f;
static const CGFloat kThumbSide     = 42.0f;
static const CGFloat kThumbGap      = 6.0f;
static const CGFloat kThumbStripH   = 54.0f;

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
@property (nonatomic, assign) BOOL isAlbum;

@property (nonatomic, strong) TGMediaViewer *self_;   // held up while on screen
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIView *statusPlate;
@property (nonatomic, assign) BOOL statusBarWasHidden;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *authorAvatar;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) NSNumber *avatarFileId;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIScrollView *thumbStrip;
@property (nonatomic, strong) NSMutableArray *thumbButtons;
@property (nonatomic, assign) BOOL chromeHidden;
/// Where the drag that may dismiss the viewer started, and the page it is
/// carrying. Zero width means no drag is in progress.
@property (nonatomic, assign) CGPoint dragOrigin;
@property (nonatomic, assign) BOOL dragging;

/// The bubble the picture grew from. Weak: the chat owns it, and a cell can be
/// reused or gone by the time the viewer closes. `startIndex` is the page it
/// stands for - the zoom back only makes sense while that page is still up.
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic, assign) NSInteger startIndex;
@property (nonatomic, assign) BOOL sourceHidden;
@property (nonatomic, assign) BOOL dismissing;
/// Pages whose picture is a thumbnail standing in for the original, so Share
/// and Save do not hand out the blurry copy.
@property (nonatomic, strong) NSMutableSet *placeholderPages;
/// Work in flight per page (poster, original, video file). A counted set,
/// because a video page has the poster and the movie coming at once.
@property (nonatomic, strong) NSCountedSet *loading;

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

+ (void)presentItems:(NSArray *)items startAt:(NSInteger)index inChat:(int64_t)chatId isAlbum:(BOOL)isAlbum {
	[self presentItems:items startAt:index inChat:chatId isAlbum:isAlbum fromView:nil];
}

+ (void)presentItems:(NSArray *)items startAt:(NSInteger)index inChat:(int64_t)chatId
			 isAlbum:(BOOL)isAlbum fromView:(UIView *)sourceView {
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
	viewer.isAlbum = isAlbum;
	viewer.sourceView = sourceView;
	[viewer present];
}

+ (void)presentItems:(NSArray *)items startAt:(NSInteger)index inChat:(int64_t)chatId {
	[self presentItems:items startAt:index inChat:chatId isAlbum:NO];
}

- (id)init {
	if ((self = [super init])){
		_pages = [NSMutableDictionary dictionary];
		_originals = [NSMutableDictionary dictionary];
		_requested = [NSMutableSet set];
		_placeholderPages = [NSMutableSet set];
		_loading = [NSCountedSet set];
		_moviePage = NSNotFound;
	}
	return self;
}

#pragma mark - presenting

- (void)present {
	self.self_ = self;      // nothing else owns this while it is up

	// The viewer is the whole screen, as Telegram's is: the status bar goes
	// while it is up. Where the system keeps it (a view controller decides
	// from iOS 7), buildChrome leaves it room instead.
	UIApplication *app = [UIApplication sharedApplication];
	self.statusBarWasHidden = app.statusBarHidden;
	[app setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];

	self.window = app.keyWindow;
	CGRect bounds = self.window.bounds;

	// A window-sized view and nobody owning it but itself: no layout pass
	// comes through here, so a rotation is carried by this notification.
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(relayoutViewer)
			name:UIApplicationDidChangeStatusBarOrientationNotification
			object:nil];

	self.backdrop = [[UIView alloc] initWithFrame:bounds];
	// Clear to start with, and brought up to the backdrop colour by the open
	// transition. Fading the view's alpha instead would fade the grown picture
	// and the chrome with it.
	self.backdrop.backgroundColor = [UIColor clearColor];
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
	if (self.isAlbum) {
		[self buildThumbStrip];
	}

	UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(tapAt:)];
	single.delegate = self;
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

	// The file's own lot - the download list, the copy on this device - is
	// not a message action: it follows the picture, whichever page is up.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(mediaHeld:)];
	hold.minimumPressDuration = 0.5;
	[self.backdrop addGestureRecognizer:hold];

	[self loadPagesAround:self.index];
	[self refreshChrome];

	self.startIndex = self.index;
	[self runOpenTransition];
}

#pragma mark - open and close transitions

/// Where the viewer's picture lands and leaves from, as a transform. The ghost
/// is laid out at its resting frame and scaled down onto the bubble, so the
/// render server moves one texture and the main thread does nothing for the
/// length of the animation. The scale is not uniform: a bubble that crops its
/// photo is a different shape from the photo, and for 250 ms nobody sees the
/// difference.
static CGAffineTransform TGTransformOnto(CGRect resting, CGRect target) {
	CGFloat sx = target.size.width  / MAX(resting.size.width,  TGMetricScaleFull);
	CGFloat sy = target.size.height / MAX(resting.size.height, TGMetricScaleFull);
	return CGAffineTransformMake(sx, 0, 0, sy,
			CGRectGetMidX(target) - CGRectGetMidX(resting),
			CGRectGetMidY(target) - CGRectGetMidY(resting));
}

- (UIImageView *)sourceImageView {
	UIView *source = self.sourceView;
	return [source isKindOfClass:UIImageView.class] ? (UIImageView *)source : nil;
}

- (void)setEdgeChromeAlpha:(CGFloat)alpha {
	self.topBar.alpha = alpha;
	self.bottomBar.alpha = alpha;
	self.thumbStrip.alpha = alpha;
	self.statusPlate.alpha = alpha;
}

/// The chrome comes in after the picture has landed, so the eye has one thing
/// to follow at a time.
- (void)fadeInChrome {
	self.backdrop.userInteractionEnabled = YES;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		CGFloat alpha = self.chromeHidden ? TGAlphaTransparent : TGAlphaOpaque;
		self.topBar.alpha = alpha;
		self.bottomBar.alpha = alpha;
		self.thumbStrip.alpha = alpha;
		self.statusPlate.alpha = TGAlphaOpaque;
	}];
}

- (void)runOpenTransition {
	UIColor *dim = [[TGTheme shared] mediaViewerBackdropColour];
	UIImageView *source = [self sourceImageView];
	UIImage *thumb = source.image;
	CGRect from = source ? [source convertRect:source.bounds toView:self.backdrop] : CGRectZero;
	BOOL grows = thumb && thumb.size.width > 0 && thumb.size.height > 0 &&
			source.window && !source.hidden &&
			CGRectIntersectsRect(from, self.backdrop.bounds);

	[self setEdgeChromeAlpha:TGAlphaTransparent];
	// Touches during the 250 ms would meet a viewer that is half built.
	self.backdrop.userInteractionEnabled = NO;

	if (!grows){
		self.sourceView = nil;      // nothing to hide, nothing to return to
		self.pager.alpha = TGAlphaTransparent;
		[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
			self.backdrop.backgroundColor = dim;
			self.pager.alpha = TGAlphaOpaque;
		} completion:^(BOOL done){
			[self fadeInChrome];
		}];
		return;
	}

	CGRect resting = AVMakeRectWithAspectRatioInsideRect(thumb.size, self.backdrop.bounds);
	UIImageView *ghost = [[UIImageView alloc] initWithFrame:resting];
	ghost.image = thumb;
	ghost.contentMode = UIViewContentModeScaleToFill;
	ghost.userInteractionEnabled = NO;
	ghost.transform = TGTransformOnto(resting, from);
	// The pager waits until the ghost has landed: its page is still empty, and
	// its spinner would show beside a picture that is on its way.
	self.pager.alpha = TGAlphaTransparent;
	[self.backdrop insertSubview:ghost aboveSubview:self.pager];

	source.hidden = YES;
	self.sourceHidden = YES;

	__weak typeof(self) weakSelf = self;
	[UIView animateWithDuration:TGAnimationDurationMedium
						  delay:0
						options:UIViewAnimationOptionCurveEaseOut
					 animations:^{
		ghost.transform = CGAffineTransformIdentity;
		self.backdrop.backgroundColor = dim;
	} completion:^(BOOL done){
		TGMediaViewer *me = weakSelf;
		if (me)
			[me landedWithGhost:ghost thumbnail:thumb];
		else
			[ghost removeFromSuperview];
	}];
}

/// The thumbnail stays on the page as its picture until the original arrives,
/// so the swap from ghost to page is the same pixels in the same place.
- (void)landedWithGhost:(UIImageView *)ghost thumbnail:(UIImage *)thumb {
	UIImageView *picture = (UIImageView *)[[self currentPage] viewWithTag:kZoomTag + 1];
	if (picture && !picture.image){
		picture.image = thumb;
		[self.placeholderPages addObject:@(self.startIndex)];
	}
	self.pager.alpha = TGAlphaOpaque;
	[ghost removeFromSuperview];
	[self fadeInChrome];
}

/// A ghost of the picture as it is on screen now, with the rect it should
/// shrink into. Nil whenever the way back is not certain: the page was changed
/// or zoomed, the bubble has scrolled away or been reused, or the picture has
/// not arrived. Those fade instead.
- (UIImageView *)closingGhostTarget:(CGRect *)target {
	UIImageView *source = [self sourceImageView];
	if (!source || !source.window || self.dragging || self.index != self.startIndex)
		return nil;
	UIScrollView *page = [self currentPage];
	UIImageView *picture = (UIImageView *)[page viewWithTag:kZoomTag + 1];
	UIImage *image = picture.image;
	if (!image || page.zoomScale > page.minimumZoomScale + TGAlphaEpsilon)
		return nil;
	CGRect to = [source convertRect:source.bounds toView:self.backdrop];
	if (!CGRectIntersectsRect(to, self.backdrop.bounds))
		return nil;

	CGRect fit = AVMakeRectWithAspectRatioInsideRect(image.size, picture.bounds);
	UIImageView *ghost = [[UIImageView alloc] initWithFrame:
			[picture convertRect:fit toView:self.backdrop]];
	ghost.image = image;
	ghost.contentMode = UIViewContentModeScaleToFill;
	ghost.userInteractionEnabled = NO;
	*target = to;
	return ghost;
}

- (void)restoreSource {
	if (self.sourceHidden)
		self.sourceView.hidden = NO;
	self.sourceHidden = NO;
}

- (void)dismiss {
	[self dismissWithZoom:YES];
}

- (void)dismissWithZoom:(BOOL)zoom {
	if (self.dismissing)
		return;
	self.dismissing = YES;
	self.backdrop.userInteractionEnabled = NO;
	[self stopMovie];
	[[UIApplication sharedApplication] setStatusBarHidden:self.statusBarWasHidden
											withAnimation:UIStatusBarAnimationFade];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	// The completion blocks hold the backdrop rather than self: the viewer
	// holds itself up until they run, and nothing should keep it past that.
	UIView *backdrop = self.backdrop;
	__weak typeof(self) weakSelf = self;
	void (^finish)(void) = ^{
		[backdrop removeFromSuperview];
		weakSelf.self_ = nil;       // and now it can go
	};

	CGRect target = CGRectZero;
	UIImageView *ghost = zoom ? [self closingGhostTarget:&target] : nil;
	if (!ghost){
		// The bubble shows through the fading backdrop, so it comes back first.
		[self restoreSource];
		[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
			backdrop.alpha = TGAlphaTransparent;
		} completion:^(BOOL done){ finish(); }];
		return;
	}

	// The ghost is drawn over the picture it copies, so hiding the pager the
	// same instant changes nothing on screen.
	CGRect resting = ghost.frame;
	[self.backdrop insertSubview:ghost aboveSubview:self.pager];
	self.pager.hidden = YES;
	[UIView animateWithDuration:TGAnimationDurationMedium
						  delay:0
						options:UIViewAnimationOptionCurveEaseInOut
					 animations:^{
		ghost.transform = TGTransformOnto(resting, target);
		backdrop.backgroundColor = [UIColor clearColor];
		[self setEdgeChromeAlpha:TGAlphaTransparent];
	} completion:^(BOOL done){
		// The ghost is a squashed copy with square corners; the bubble is the
		// real thing. Letting one dissolve into the other hides the join.
		[weakSelf restoreSource];
		[UIView animateWithDuration:TGAnimationDurationFast animations:^{
			ghost.alpha = TGAlphaTransparent;
		} completion:^(BOOL finished){ finish(); }];
	}];
}

#pragma mark - chrome

/// The viewer lives in a backdrop nobody lays out, so chrome and pages are
/// rebuilt from the window's present bounds whenever they change. The pages
/// keep their pictures - a rotated album does not download again.
- (void)relayoutViewer {
	if (!self.backdrop)
		return;
	CGRect bounds = self.window.bounds;
	self.backdrop.frame = bounds;
	self.pager.frame = bounds;
	self.pager.contentSize = CGSizeMake(bounds.size.width * self.items.count,
										bounds.size.height);
	self.pager.contentOffset = CGPointMake(bounds.size.width * self.index, 0);

	for (NSNumber *key in self.pages) {
		NSInteger i = key.integerValue;
		UIScrollView *zoom = self.pages[key];
		zoom.frame = CGRectMake(bounds.size.width * i, 0,
				bounds.size.width, bounds.size.height);
		zoom.zoomScale = TGMetricZoomMin;
		UIImageView *picture = [zoom viewWithTag:kZoomTag + 1];
		picture.frame = zoom.bounds;
		[zoom viewWithTag:kZoomTag + kSpinnerOffset].center =
				CGPointMake(TGHalf(zoom.bounds.size.width), TGHalf(zoom.bounds.size.height));
	}

	[self.topBar removeFromSuperview];   self.topBar = nil;
	self.counterLabel = nil;             self.dateLabel = nil;
	self.authorAvatar = nil;             self.moreButton = nil;
	[self.bottomBar removeFromSuperview]; self.bottomBar = nil;
	self.captionLabel = nil;             self.playButton = nil;
	self.scrubber = nil;                 self.timeLabel = nil;
	[self.thumbStrip removeFromSuperview]; self.thumbStrip = nil;
	self.thumbButtons = nil;
	[self buildChrome];
	[self buildThumbStrip];
	[self refreshChrome];
}

- (void)buildChrome {
	CGRect bounds = self.backdrop.bounds;
	UIColor *plate = [[TGTheme shared] mediaOverlayColour];

	UIApplication *app = [UIApplication sharedApplication];
	CGFloat statusRoom = app.statusBarHidden ? 0 : MIN(app.statusBarFrame.size.width,
			app.statusBarFrame.size.height);
	[self.statusPlate removeFromSuperview];
	self.statusPlate = nil;
	if (statusRoom > 0){
		self.statusPlate = [[UIView alloc] initWithFrame:
				CGRectMake(0, 0, bounds.size.width, statusRoom)];
		self.statusPlate.backgroundColor = plate;
		[self.backdrop addSubview:self.statusPlate];
	}
	self.topBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, statusRoom, bounds.size.width, kTopBar)];
	self.topBar.backgroundColor = plate;
	[self.backdrop addSubview:self.topBar];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
	close.frame = CGRectMake(kChromeInset,
			TGCenteredOrigin(kTopBar, TGMetricViewerHeaderIcon),
			TGMetricViewerHeaderIcon, TGMetricViewerHeaderIcon);
	[close setImage:[TGIcons glyphNamed:@"close" colour:[[TGTheme shared] onMediaColour]
								  side:TGMetricPadLarge]
		   forState:UIControlStateNormal];
	[close addTarget:self action:@selector(dismiss)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.topBar addSubview:close];

	self.moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.moreButton.frame = CGRectMake(
			bounds.size.width - kChromeInset - TGMetricViewerHeaderIcon,
			TGCenteredOrigin(kTopBar, TGMetricViewerHeaderIcon),
			TGMetricViewerHeaderIcon, TGMetricViewerHeaderIcon);
	[self.moreButton setImage:[TGIcons glyphNamed:@"more" colour:[[TGTheme shared] onMediaColour]
										   side:TGMetricPadLarge]
					 forState:UIControlStateNormal];
	[self.moreButton addTarget:self action:@selector(moreTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[self.topBar addSubview:self.moreButton];

	self.authorAvatar = [[UIImageView alloc] initWithFrame:CGRectMake(
			CGRectGetMaxX(close.frame) + TGMetricViewerHeaderGap,
			TGCenteredOrigin(kTopBar, TGMetricViewerAvatarSide),
			TGMetricViewerAvatarSide, TGMetricViewerAvatarSide)];
	self.authorAvatar.contentMode = UIViewContentModeScaleAspectFill;
	self.authorAvatar.clipsToBounds = YES;
	self.authorAvatar.layer.cornerRadius = TGHalf(TGMetricViewerAvatarSide);
	self.authorAvatar.backgroundColor = [[TGTheme shared] fileTileColour];
	[self.topBar addSubview:self.authorAvatar];

	CGFloat labelsX = CGRectGetMaxX(self.authorAvatar.frame) + TGMetricViewerHeaderGap;
	CGFloat labelsW = CGRectGetMinX(self.moreButton.frame) - labelsX -
			TGMetricViewerHeaderGap;
	CGFloat labelsTop = TGCenteredOrigin(kTopBar,
			TGMetricLineBody + TGMetricLineMicro);

	self.counterLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(labelsX, labelsTop, labelsW, TGMetricLineBody)];
	self.counterLabel.font = TGFontBodyStrong();
	self.counterLabel.textAlignment = NSTextAlignmentLeft;
	self.counterLabel.textColor = [[TGTheme shared] onMediaColour];
	self.counterLabel.backgroundColor = [UIColor clearColor];
	self.counterLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.topBar addSubview:self.counterLabel];

	self.dateLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(labelsX, labelsTop + TGMetricLineBody, labelsW,
					TGMetricLineMicro)];
	self.dateLabel.font = TGFontMicro();
	self.dateLabel.textAlignment = NSTextAlignmentLeft;
	self.dateLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.dateLabel.backgroundColor = [UIColor clearColor];
	self.dateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.topBar addSubview:self.dateLabel];

	self.bottomBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - kBottomBar, bounds.size.width, kBottomBar)];
	self.bottomBar.backgroundColor = plate;
	[self.backdrop addSubview:self.bottomBar];

	self.captionLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(kCaptionInset, kChromeInset,
					bounds.size.width - TGMetricViewerCaptionMarginRight, kCaptionHeight)];
	self.captionLabel.font = TGFontCaption();
	self.captionLabel.numberOfLines = 2;
	self.captionLabel.textColor = [[TGTheme shared] onMediaColour];
	self.captionLabel.backgroundColor = [UIColor clearColor];
	[self.bottomBar addSubview:self.captionLabel];

	UIButton *save = [UIButton buttonWithType:UIButtonTypeCustom];
	save.frame = CGRectMake(bounds.size.width - kSaveWidth - kCaptionInset - TGMetricBorderThick,
			kChromeInset, kSaveWidth, kCaptionHeight);
	[save setTitle:@"Save" forState:UIControlStateNormal];
	save.titleLabel.font = TGFontBody();
	[save setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSecondary highlighted:NO height:kCaptionHeight] forState:UIControlStateNormal];
	[save setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSecondary highlighted:YES height:kCaptionHeight] forState:UIControlStateHighlighted];
	save.layer.cornerRadius = TGMetricCornerControl;
	save.clipsToBounds = YES;
	[save addTarget:self action:@selector(saveCurrent)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar addSubview:save];

	// The video strip lives in the bottom bar and only appears on a video page.
	self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.playButton.frame = CGRectMake(TGMetricPad, kStripTop, kPlayWidth, kStripHeight);
	[self.playButton setImage:[self playGlyph] forState:UIControlStateNormal];
	self.playButton.tintColor = [[TGTheme shared] onMediaColour];
	[self.playButton addTarget:self action:@selector(toggleMovie)
			  forControlEvents:UIControlEventTouchUpInside];
	self.playButton.hidden = YES;
	[self.bottomBar addSubview:self.playButton];

	self.scrubber = [[UISlider alloc] initWithFrame:
			CGRectMake(kScrubberLeft, kStripTop,
					bounds.size.width - TGMetricViewerScrubberMarginRight, kStripHeight)];
	self.scrubber.minimumTrackTintColor = [[TGTheme shared] accentColour];
	[self.scrubber setThumbImage:[TGTheme skeuomorphicSliderThumbWithRadius:TGHalf(TGMetricSliderThumbD)] forState:UIControlStateNormal];
	[self.scrubber setMinimumTrackImage:[TGTheme skeuomorphicSliderTrackImageFilled:YES] forState:UIControlStateNormal];
	[self.scrubber setMaximumTrackImage:[TGTheme skeuomorphicSliderTrackImageFilled:NO] forState:UIControlStateNormal];
	[self.scrubber addTarget:self action:@selector(scrubberMoved)
			forControlEvents:UIControlEventValueChanged];
	self.scrubber.hidden = YES;
	[self.bottomBar addSubview:self.scrubber];

	self.timeLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(bounds.size.width - kClockWidth - kChromeInset - TGMetricPadTiny,
					kStripTop, kClockWidth, kStripHeight)];
	self.timeLabel.font = TGFontMicro();
	self.timeLabel.textColor = [[TGTheme shared] onMediaColour];
	self.timeLabel.textAlignment = NSTextAlignmentRight;
	self.timeLabel.backgroundColor = [UIColor clearColor];
	self.timeLabel.hidden = YES;
	[self.bottomBar addSubview:self.timeLabel];
}

- (UIImage *)playGlyph {
	return [TGIcons image:[TGIcons play] filledWith:[[TGTheme shared] onMediaColour]];
}

- (UIImage *)pauseGlyph {
	return [TGIcons image:[TGIcons pause] filledWith:[[TGTheme shared] onMediaColour]];
}

- (void)buildThumbStrip {
	if (!self.isAlbum || self.items.count <= 1)
		return;

	CGRect bounds = self.backdrop.bounds;
	CGFloat y = bounds.size.height - kBottomBar - kThumbStripH;
	self.thumbStrip = [[UIScrollView alloc] initWithFrame:
			CGRectMake(0, y, bounds.size.width, kThumbStripH)];
	self.thumbStrip.showsHorizontalScrollIndicator = NO;
	self.thumbStrip.showsVerticalScrollIndicator = NO;
	self.thumbStrip.backgroundColor = [UIColor clearColor];
	self.thumbStrip.clipsToBounds = NO;
	self.thumbButtons = [NSMutableArray arrayWithCapacity:self.items.count];

	CGFloat itemTotal = self.items.count * kThumbSide + (self.items.count - 1) * kThumbGap;
	CGFloat startX = (itemTotal < bounds.size.width) ? TGCenteredOrigin(bounds.size.width, itemTotal) : kThumbGap;

	for (NSUInteger i = 0; i < self.items.count; i++) {
		CGFloat x = startX + i * (kThumbSide + kThumbGap);
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
		btn.frame = CGRectMake(x, TGCenteredOrigin(kThumbStripH, kThumbSide), kThumbSide, kThumbSide);
		btn.tag = (NSInteger)i;
		btn.layer.cornerRadius = TGMetricCornerSmall;
		btn.layer.masksToBounds = YES;
		btn.imageView.contentMode = UIViewContentModeScaleAspectFill;
		btn.adjustsImageWhenHighlighted = NO;
		[btn addTarget:self action:@selector(thumbTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.thumbStrip addSubview:btn];
		[self.thumbButtons addObject:btn];
		[self fetchThumbnailForIndex:i into:btn];
	}

	CGFloat contentW = MAX(bounds.size.width, startX + self.items.count * (kThumbSide + kThumbGap) - kThumbGap + startX);
	self.thumbStrip.contentSize = CGSizeMake(contentW, kThumbStripH);
	[self.backdrop addSubview:self.thumbStrip];
	[self updateThumbStripSelection:NO];
}

- (void)fetchThumbnailForIndex:(NSUInteger)idx into:(UIButton *)btn {
	NSDictionary *item = self.items[idx];
	NSNumber *fileId = item[@"photoId"] ?: (item[@"thumbId"] ?: item[@"docId"]);
	if (![fileId isKindOfClass:NSNumber.class])
		return;

	if (fileId.longLongValue < 0) {
		UIImage *fixture = [TGDevShowcase imageForPhotoId:fileId.longLongValue];
		if (fixture) {
			[btn setImage:fixture forState:UIControlStateNormal];
			return;
		}
	}

	__weak typeof(self) weakSelf = self;
	__weak UIButton *weakBtn = btn;
	[[TGMediaStore shared] downloadFile:fileId.integerValue priority:TGDownloadPriorityOnScreen completion:^(NSString *path){
		if (!path.length) return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (!img && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				img = [UIImage convertFromWebP:path compressedData:nil error:nil];
			if (!img) return;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (weakBtn.tag == (NSInteger)idx) {
					[weakBtn setImage:img forState:UIControlStateNormal];
				}
			});
		});
	}];
}

- (void)updateThumbStripSelection:(BOOL)animated {
	if (!self.thumbButtons.count)
		return;

	// The ring is a layer property and snaps; the dimming is alpha, which the
	// render server eases, so the strip still reads as moving with the page.
	for (UIButton *btn in self.thumbButtons) {
		BOOL selected = (btn.tag == self.index);
		if (selected) {
			btn.layer.borderWidth = 2.0f;
			btn.layer.borderColor = [[TGTheme shared] onMediaColour].CGColor;
		} else {
			btn.layer.borderWidth = 0.0f;
			btn.layer.borderColor = [UIColor clearColor].CGColor;
		}
	}
	void (^dim)(void) = ^{
		for (UIButton *btn in self.thumbButtons)
			btn.alpha = (btn.tag == self.index) ? TGAlphaOpaque : TGAlphaDimmed;
	};
	if (animated)
		[UIView animateWithDuration:TGAnimationDurationFast animations:dim];
	else
		dim();

	if (self.index >= 0 && self.index < (NSInteger)self.thumbButtons.count) {
		UIButton *curr = self.thumbButtons[self.index];
		CGFloat targetX = curr.center.x - TGHalf(self.thumbStrip.bounds.size.width);
		CGFloat maxX = MAX(0.0f, self.thumbStrip.contentSize.width - self.thumbStrip.bounds.size.width);
		targetX = MAX(0.0f, MIN(targetX, maxX));
		[self.thumbStrip setContentOffset:CGPointMake(targetX, 0) animated:animated];
	}
}

- (void)thumbTapped:(UIButton *)btn {
	[self gotoPage:btn.tag animated:YES];
}

/// One page-change path for the thumb strip, the tap zones and a programmatic
/// move. Leaving a video's page stops it first, which is what keeps a movie
/// from playing behind a picture two pages away.
- (void)gotoPage:(NSInteger)idx animated:(BOOL)animated {
	if (idx < 0 || idx >= (NSInteger)self.items.count || idx == self.index)
		return;
	if (self.moviePage != NSNotFound && idx != self.moviePage)
		[self stopMovie];

	self.index = idx;
	[self.pager setContentOffset:CGPointMake(self.pager.bounds.size.width * idx, 0)
						animated:animated];
	[self loadPagesAround:idx];
	if (animated)
		[self fadeChromeText];
	[self refreshChrome];
	[self updateThumbStripSelection:animated];
}

/// The counter and the date change while the pages are still sliding, so the
/// new text dissolves in rather than snapping. A CATransition is done by the
/// render server and costs the main thread nothing after the call.
- (void)fadeChromeText {
	for (UILabel *label in @[self.counterLabel ?: [NSNull null],
							 self.dateLabel ?: [NSNull null],
							 self.captionLabel ?: [NSNull null]]){
		if (![label isKindOfClass:UILabel.class])
			continue;
		CATransition *fade = [CATransition animation];
		fade.type = kCATransitionFade;
		fade.duration = TGAnimationDurationFast;
		[label.layer addAnimation:fade forKey:@"tg.text"];
	}
}

/// Telegram's viewer splits the picture into three: the left third goes back,
/// the right third goes on, and the middle shows or hides the chrome. A tap
/// on a control never reaches here - the delegate below refuses it.
- (void)tapAt:(UITapGestureRecognizer *)tap {
	if (self.items.count < 2){
		[self toggleChrome];
		return;
	}
	CGPoint where = [tap locationInView:self.backdrop];
	CGFloat width = self.backdrop.bounds.size.width;
	if (where.x < width / 3.0f){
		if (self.index > 0)
			[self gotoPage:self.index - 1 animated:YES];
		return;
	}
	if (where.x > width - width / 3.0f){
		if (self.index < (NSInteger)self.items.count - 1)
			[self gotoPage:self.index + 1 animated:YES];
		return;
	}
	[self toggleChrome];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
		shouldReceiveTouch:(UITouch *)touch {
	// A tap, a hold or a drag that starts on a button belongs to the button.
	UIView *view = touch.view;
	while (view && view != self.backdrop){
		if ([view isKindOfClass:UIControl.class])
			return NO;
		view = view.superview;
	}
	return YES;
}

- (void)toggleChrome {
	self.chromeHidden = !self.chromeHidden;
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		self.topBar.alpha = self.chromeHidden ? 0 : 1;
		self.bottomBar.alpha = self.chromeHidden ? 0 : 1;
		self.thumbStrip.alpha = self.chromeHidden ? 0 : 1;
	}];
}

- (void)refreshChrome {
	NSDictionary *item = self.items[self.index];

	static NSDateFormatter *when = nil;
	if (!when){
		when = [[NSDateFormatter alloc] init];
		when.dateStyle = NSDateFormatterMediumStyle;
		when.timeStyle = NSDateFormatterShortStyle;
	}
	int64_t senderId = [item[@"senderId"] longLongValue];
	NSString *sender = [[TGMediaStore shared] nameForUserId:senderId];
	NSString *date = [when stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[item[@"date"] doubleValue]]];
	self.counterLabel.text = sender.length ? sender : @"Media";
	self.dateLabel.text = [NSString stringWithFormat:@"%ld of %lu · %@",
			(long)(self.index + 1), (unsigned long)self.items.count, date];
	[self refreshAvatarForUserId:senderId title:sender];

	self.captionLabel.text = item[@"text"] ?: @"";

	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	BOOL isAnim = [item[@"kind"] isEqualToString:@"messageAnimation"];
	self.playButton.hidden = !isVideo && !isAnim;
	self.scrubber.hidden = !isVideo;
	self.timeLabel.hidden = !isVideo;
	self.captionLabel.frame = CGRectMake(kCaptionInset, kChromeInset,
			self.backdrop.bounds.size.width - TGMetricViewerCaptionMarginRight,
			(isVideo || isAnim) ? kCaptionHeight - TGMetricPadSmall : kCaptionHeight);
}

/// The header's picture follows the sender, not the message: every page from
/// one person in a group carries the same face. A photo id is read from the
/// account map; the initials stand in until it arrives.
- (void)refreshAvatarForUserId:(int64_t)userId title:(NSString *)title {
	self.avatarFileId = nil;
	NSString *initial = title.length
			? [title substringToIndex:1].uppercaseString : @"?";
	self.authorAvatar.image = [TGIcons avatarWithInitials:initial
													size:TGMetricViewerAvatarSide
												colourId:userId];
	if (userId <= 0)
		return;
	NSNumber *fileId = [[TGMediaStore shared] photoFileIdForUserId:userId];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0)
		return;
	self.avatarFileId = fileId;

	__weak typeof(self) weakSelf = self;
	__weak UIImageView *weakAvatar = self.authorAvatar;
	[[TGMediaStore shared] downloadFile:fileId.integerValue
							  priority:TGDownloadPriorityOnScreen
							completion:^(NSString *path){
		if (!path.length)
			return;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image)
				return;
			image = [TGIcons decodedImage:image
					fittingSize:CGSizeMake(TGMetricViewerAvatarSide,
										   TGMetricViewerAvatarSide)
							 fill:YES scale:[UIScreen mainScreen].scale];
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				TGMediaViewer *me = weakSelf;
				if (me && [me.avatarFileId isEqual:fileId])
					weakAvatar.image = image;
			});
		});
	}];
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
		[self.placeholderPages removeObject:key];
		while ([self.loading containsObject:key])
			[self.loading removeObject:key];
		// Without this a page scrolled back to was built empty and never asked
		// again, because its file still counted as requested.
		NSNumber *dropped = [self fileIdForItem:self.items[i]];
		if (dropped)
			[self.requested removeObject:dropped];
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

#pragma mark - progress

/// Counts work in flight for a page and shows a white spinner while there is
/// any. The spinner waits TGAnimationDurationNormal before it fades in, so a
/// picture that is already on disk never flashes one.
- (void)beginLoadingPage:(NSInteger)page {
	[self.loading addObject:@(page)];
	[self refreshSpinnerForPage:page];
}

- (void)endLoadingPage:(NSInteger)page {
	if (![NSThread isMainThread]){
		dispatch_async(dispatch_get_main_queue(), ^{ [self endLoadingPage:page]; });
		return;
	}
	[self.loading removeObject:@(page)];
	[self refreshSpinnerForPage:page];
}

- (void)refreshSpinnerForPage:(NSInteger)page {
	UIScrollView *zoom = self.pages[@(page)];
	if (!zoom)
		return;
	UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)
			[zoom viewWithTag:kZoomTag + kSpinnerOffset];
	if ([self.loading countForObject:@(page)] == 0){
		[spinner stopAnimating];
		[spinner removeFromSuperview];
		return;
	}
	if (spinner)
		return;
	spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	spinner.tag = kZoomTag + kSpinnerOffset;
	spinner.center = CGPointMake(TGHalf(zoom.bounds.size.width), TGHalf(zoom.bounds.size.height));
	spinner.userInteractionEnabled = NO;
	spinner.alpha = TGAlphaTransparent;
	[zoom addSubview:spinner];
	[spinner startAnimating];
	[UIView animateWithDuration:TGAnimationDurationNormal
						  delay:TGAnimationDurationNormal
						options:0
					 animations:^{ spinner.alpha = TGAlphaOpaque; }
					 completion:nil];
}

/// The original replaces whatever the page was showing. On screen it dissolves
/// in; a hard swap from a blurry thumbnail to the sharp one reads as a glitch.
- (void)showOriginal:(UIImage *)image inPicture:(UIImageView *)picture page:(NSInteger)page {
	UIView *zoom = self.pages[@(page)];
	if (!zoom || [zoom viewWithTag:kZoomTag + 1] != picture)
		return;     // the page was dropped while this was decoding
	self.originals[@(page)] = image;
	[self.placeholderPages removeObject:@(page)];
	if (picture.window){
		CATransition *fade = [CATransition animation];
		fade.type = kCATransitionFade;
		fade.duration = TGAnimationDurationNormal;
		[picture.layer addAnimation:fade forKey:@"tg.original"];
	}
	picture.image = image;
}

/// Downloads and displays full-resolution media, using thumbnail as placeholder.
- (void)fetchOriginalForPage:(NSInteger)page into:(UIImageView *)picture {
	NSDictionary *item = self.items[page];
	NSNumber *fileId = [self fileIdForItem:item];
	if (!fileId)
		return;

	if (fileId.longLongValue < 0) {
		UIImage *fixture = [TGDevShowcase imageForPhotoId:fileId.longLongValue];
		if (fixture) {
			self.originals[@(page)] = fixture;
			picture.image = fixture;
			return;
		}
	}

	CGSize screen = self.backdrop.bounds.size;
	CGFloat scale = [UIScreen mainScreen].scale;

	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	BOOL isAnim = [item[@"kind"] isEqualToString:@"messageAnimation"];
	if (isVideo || isAnim){
		// A video/GIF poster frame is its thumbnail; the file itself is only
		// fetched when the play button is pressed (or auto-started for GIFs).
		NSNumber *thumb = item[@"photoId"];
		if ([thumb isKindOfClass:NSNumber.class]){
			__weak typeof(self) posterSelf = self;
			[self beginLoadingPage:page];
			[[TGMediaStore shared] downloadFile:thumb.integerValue completion:^(NSString *path){
				if (!path.length){
					[posterSelf endLoadingPage:page];
					return;
				}
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					UIImage *poster = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
												fittingSize:screen fill:NO scale:scale];
					dispatch_async(dispatch_get_main_queue(), ^{
						TGMediaViewer *me = posterSelf;
						if (poster && me && !picture.image)
							picture.image = poster;
						[me endLoadingPage:page];
					});
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
	[self beginLoadingPage:page];
	[[TGMediaStore shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		if (!path.length){
			[weakSelf endLoadingPage:page];
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			UIImage *image = [UIImage imageWithContentsOfFile:path];
			if (!image && [path.pathExtension.lowercaseString isEqualToString:@"webp"])
				image = [UIImage convertFromWebP:path compressedData:nil error:nil];
			// Fitted to the screen rather than the bubble: a 4S has 512MB and
			// a 3000px photo decoded whole is most of what is left of it.
			image = [TGIcons decodedImage:image fittingSize:screen fill:NO scale:scale];
			dispatch_async(dispatch_get_main_queue(), ^{
				TGMediaViewer *me = weakSelf;
				if (image)
					[me showOriginal:image inPicture:picture page:page];
				[me endLoadingPage:page];
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
			self.thumbStrip.alpha = TGAlphaTransparent;
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
			[self dismissWithZoom:NO];
		}];
		return;
	}

	[UIView animateWithDuration:TGAnimationDurationMedium animations:^{
		page.center = self.dragOrigin;
		self.backdrop.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
		self.topBar.alpha = self.chromeHidden ? 0 : 1;
		self.bottomBar.alpha = self.chromeHidden ? 0 : 1;
		self.thumbStrip.alpha = self.chromeHidden ? 0 : 1;
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
	[self fadeChromeText];
	[self refreshChrome];
	[self updateThumbStripSelection:YES];
}

#pragma mark - video

- (void)toggleMovie {
	if (self.player){
		// rate rather than a playback state: AVPlayer has no "playing" flag,
		// and a rate of zero is what paused means.
		if (self.player.rate > TGPlaybackSpeedStopped){
			[self.player pause];
			[self.playButton setImage:[self playGlyph] forState:UIControlStateNormal];
		} else {
			[self.player play];
			[self.playButton setImage:[self pauseGlyph] forState:UIControlStateNormal];
		}
		return;
	}

	NSDictionary *item = self.items[self.index];
	NSNumber *fileId = [self fileIdForItem:item];
	if (!fileId)
		return;

	self.timeLabel.text = @"...";
	__weak typeof(self) weakSelf = self;
	NSInteger fetchingPage = self.index;
	[self beginLoadingPage:fetchingPage];
	[[TGMediaStore shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		[weakSelf endLoadingPage:fetchingPage];
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
	[self.playButton setImage:[self pauseGlyph] forState:UIControlStateNormal];

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
	[self.playButton setImage:[self playGlyph] forState:UIControlStateNormal];
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
	[self.playButton setImage:[self playGlyph] forState:UIControlStateNormal];
	self.scrubber.value = 0;
}

#pragma mark - the More sheet

/// The view controller a share sheet or the forward picker presents from.
/// The viewer is not one - it lives in the window directly - so the top of
/// the window's own stack stands in.
- (UIViewController *)hostController {
	UIWindow *window = self.window ?: [UIApplication sharedApplication].keyWindow;
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController)
		top = top.presentedViewController;
	return top;
}

/// Telegram's gallery keeps file actions behind the header's More button, not
/// behind a hold: the hold is the message menu, this is what can be done with
/// the picture itself.
- (void)moreTapped {
	NSDictionary *m = [self currentItem];
	if (!m)
		return;

	NSMutableArray *choices = [NSMutableArray arrayWithObjects:
			@"Share", @"Forward", @"Copy Caption", nil];
	NSInteger destructive = -1;
	if ([self currentFileId]){
		[choices addObject:@"Save to Camera Roll"];
		[choices addObject:@"Add to Downloads"];
		[choices addObject:@"File Info"];
		[choices addObject:@"Delete from Device"];
		destructive = (NSInteger)choices.count - 1;
	}
	if ([m[@"hasStickers"] boolValue])
		[choices addObject:@"Sticker Packs..."];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:@"Media"
			 destructiveIndex:destructive inView:self.backdrop
					 onChoice:^(NSInteger index){
		TGMediaViewer *me = weakSelf;
		if (!me)
			return;
		NSString *what = choices[(NSUInteger)index];
		if ([what isEqualToString:@"Share"])
			[me shareCurrent];
		else if ([what isEqualToString:@"Forward"])
			[me forwardCurrent];
		else if ([what isEqualToString:@"Copy Caption"])
			[me copyCaption];
		else if ([what isEqualToString:@"Save to Camera Roll"])
			[me saveCurrent];
		else if ([what isEqualToString:@"Add to Downloads"])
			[me addCurrentToDownloads];
		else if ([what isEqualToString:@"File Info"])
			[me showFileInfo];
		else if ([what isEqualToString:@"Delete from Device"])
			[me deleteCurrentFromDevice];
		else if ([what isEqualToString:@"Sticker Packs..."])
			[me showStickerPacksOfFile:[me currentFileId].integerValue];
	}];
}

- (void)shareCurrent {
	UIImage *image = self.originals[@(self.index)];
	if (!image && ![self.placeholderPages containsObject:@(self.index)]){
		UIView *page = self.pages[@(self.index)];
		image = [(UIImageView *)[page viewWithTag:kZoomTag + 1] image];
	}
	if (image){
		[self presentShareItems:@[image]];
		return;
	}

	NSNumber *fileId = [self currentFileId];
	if (!fileId){
		[self copyCaption];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGMediaStore shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		dispatch_async(dispatch_get_main_queue(), ^{
			TGMediaViewer *me = weakSelf;
			if (!me)
				return;
			if (!path.length){
				[TGAlertSheet showMessage:@"The file is not downloaded yet."
									  title:@"Share" inView:me.backdrop];
				return;
			}
			[me presentShareItems:@[[NSURL fileURLWithPath:path]]];
		});
	}];
}

- (void)presentShareItems:(NSArray *)items {
	UIViewController *top = [self hostController];
	if (!top || !items.count)
		return;
	UIActivityViewController *share = [[UIActivityViewController alloc]
			initWithActivityItems:items applicationActivities:nil];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad &&
		[share respondsToSelector:@selector(popoverPresentationController)]){
		share.popoverPresentationController.sourceView = self.backdrop;
		share.popoverPresentationController.sourceRect = CGRectMake(
				TGHalf(self.backdrop.bounds.size.width),
				TGHalf(self.backdrop.bounds.size.height), 0, 0);
	}
	[top presentViewController:share animated:YES completion:nil];
}

- (void)forwardCurrent {
	NSDictionary *m = [self currentItem];
	int64_t messageId = [m[@"id"] longLongValue];
	int64_t fromChat = self.chatId;
	if (!messageId || !fromChat){
		[TGAlertSheet showMessage:@"This item cannot be forwarded from the viewer."
							  title:@"Forward" inView:self.backdrop];
		return;
	}
	UIViewController *top = [self hostController];
	if (!top)
		return;

	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t toChatId){
		if (!toChatId)
			return;
		[[TGClient shared] forwardMessages:@[@(messageId)]
								  fromChat:fromChat toChat:toChatId];
		TGMediaViewer *me = weakSelf;
		UIView *host = me.backdrop ?: [UIApplication sharedApplication].keyWindow;
		[TGSnackbar showInView:host text:@"Forwarded" seconds:2 onCommit:nil];
	};
	UINavigationController *nav = [[UINavigationController alloc]
			initWithRootViewController:picker];
	[top presentViewController:nav animated:YES completion:nil];
}

- (void)copyCaption {
	NSString *caption = [self currentItem][@"text"];
	if (!caption.length){
		[TGAlertSheet showMessage:@"This item has no caption."
							  title:@"Copy Caption" inView:self.backdrop];
		return;
	}
	[UIPasteboard generalPasteboard].string = caption;
	[TGSnackbar showInView:self.backdrop text:@"Caption copied" seconds:2 onCommit:nil];
}

- (void)addCurrentToDownloads {
	NSNumber *fileId = [self currentFileId];
	NSDictionary *m = [self currentItem];
	if (!fileId || !m)
		return;
	[[TGClient shared] addFileToDownloads:fileId.integerValue
								   inChat:self.chatId
								  message:[m[@"id"] longLongValue]];
	[TGSnackbar showInView:self.backdrop text:@"Added to Downloads" seconds:2
				  onCommit:nil];
}

- (void)showFileInfo {
	NSNumber *fileId = [self currentFileId];
	if (!fileId)
		return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[TGFileInfoViewController presentForFile:fileId.integerValue
										fromView:self.backdrop];
	});
}

- (void)deleteCurrentFromDevice {
	NSNumber *fileId = [self currentFileId];
	if (!fileId)
		return;
	[[TGClient shared] deleteLocalFile:fileId.integerValue];
	[TGSnackbar showInView:self.backdrop text:@"Deleted from this device"
					 seconds:2 onCommit:nil];
}

#pragma mark - saving

/// The flattened message on screen, or nil past the ends of the album.
- (NSDictionary *)currentItem {
	if (self.index < 0 || self.index >= (NSInteger)self.items.count)
		return nil;
	return self.items[self.index];
}

/// The file behind the page: a document for a video, the largest photo
/// otherwise. Fixture ids are negative and have no file to act on.
- (NSNumber *)currentFileId {
	NSDictionary *m = [self currentItem];
	NSNumber *fileId = m[@"docId"] ?: m[@"photoId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.longLongValue <= 0)
		return nil;
	return fileId;
}

/// Holding the picture offers what belongs to the file rather than to the
/// message: a place in the download list their Download Manager reads, and
/// the local copy going away. Both have to name the chat and the message, so
/// the viewer is the only place that has all three.
- (void)mediaHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	NSNumber *fileId = [self currentFileId];
	if (!fileId)
		return;
	NSDictionary *m = [self currentItem];

	NSMutableArray *choices = [NSMutableArray arrayWithObjects:@"Add to Downloads",
							   @"File Info", @"Delete from Device", nil];
	// Media that other stickers were attached to knows which packs they came
	// from; TDLib answers that by the media file's own id.
	if ([m[@"hasStickers"] boolValue])
		[choices addObject:@"Sticker Packs..."];

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices
						title:@"File"
			 destructiveIndex:2
					   inView:self.backdrop
					 onChoice:^(NSInteger index){
		TGMediaViewer *me = weakSelf;
		UIView *host = me.backdrop ?: [UIApplication sharedApplication].keyWindow;
		NSString *what = choices[(NSUInteger)index];
		if ([what isEqualToString:@"Sticker Packs..."]){
			[me showStickerPacksOfFile:fileId.integerValue];
			return;
		}
		if ([what isEqualToString:@"File Info"]){
			// The action sheet must be gone before the info sheet presents.
			dispatch_async(dispatch_get_main_queue(), ^{
				[TGFileInfoViewController presentForFile:fileId.integerValue fromView:host];
			});
			return;
		}
		if ([what isEqualToString:@"Add to Downloads"]){
			[[TGClient shared] addFileToDownloads:fileId.integerValue
											inChat:me.chatId
										   message:[m[@"id"] longLongValue]];
			[TGSnackbar showInView:host text:@"Added to Downloads" seconds:2 onCommit:nil];
			return;
		}
		[[TGClient shared] deleteLocalFile:fileId.integerValue];
		[TGSnackbar showInView:host text:@"Deleted from this device" seconds:2 onCommit:nil];
	}];
}

/// The packs the stickers on this media belong to, with the packs this
/// account does not have offered for install.
- (void)showStickerPacksOfFile:(NSInteger)fileId {
	__weak typeof(self) weakSelf = self;
	[[TGStickerStore shared] attachedStickerSetsOfFile:fileId completion:^(NSArray *sets){
		TGMediaViewer *me = weakSelf;
		UIView *host = me.backdrop ?: [UIApplication sharedApplication].keyWindow;
		NSArray *list = [sets isKindOfClass:NSArray.class] ? sets : @[];
		if (!list.count){
			[TGAlertSheet showMessage:@"This media carries no sticker packs."
								  title:@"Sticker Packs" inView:host];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *set in list){
			NSString *title = [set[@"title"] length] ? set[@"title"] : @"Pack";
			NSString *state = [set[@"installed"] boolValue] ? @"" : @"  ·  tap to add";
			[rows addObject:[NSString stringWithFormat:@"%@%@", title, state]];
		}
		[TGAlertSheet showChoices:rows
							title:@"Sticker Packs"
				   destructiveIndex:-1
						   inView:host
						 onChoice:^(NSInteger index){
			NSDictionary *set = list[(NSUInteger)index];
			if ([set[@"installed"] boolValue])
				return;
			[[TGStickerStore shared] setStickerSet:set[@"id"] installed:YES archived:NO];
			[TGSnackbar showInView:host text:@"Sticker pack added" seconds:2 onCommit:nil];
		}];
	}];
}

- (void)saveCurrent {
	NSDictionary *item = [self currentItem];
	BOOL isVideo = [item[@"kind"] isEqualToString:@"messageVideo"];
	if (isVideo){
		NSNumber *fileId = [self currentFileId];
		if (!fileId)
			return;
		__weak typeof(self) weakSelf = self;
		[[TGMediaStore shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			dispatch_async(dispatch_get_main_queue(), ^{
				TGMediaViewer *me = weakSelf;
				if (!me)
					return;
				if (!path.length){
					[TGAlertSheet showMessage:@"The video is not downloaded yet."
										  title:@"Save" inView:me.backdrop];
					return;
				}
				UISaveVideoAtPathToSavedPhotosAlbum(path, me,
						@selector(video:didFinishSavingWithError:contextInfo:), NULL);
			});
		}];
		return;
	}

	UIImage *image = self.originals[@(self.index)];
	if (!image && ![self.placeholderPages containsObject:@(self.index)]){
		UIView *page = self.pages[@(self.index)];
		image = [(UIImageView *)[page viewWithTag:kZoomTag + 1] image];
	}
	if (!image)
		return;
	UIImageWriteToSavedPhotosAlbum(image, self,
			@selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)video:(NSString *)path didFinishSavingWithError:(NSError *)error
   contextInfo:(void *)contextInfo {
	[TGAlertSheet showMessage:(error ? @"Could not save" : @"Saved to Camera Roll")
						title:nil
					   inView:(self.backdrop ?: [UIApplication sharedApplication].keyWindow)];
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
	// The viewer is an NSObject, not a view: passing it here asked a plain
	// object for its bounds and brought the app down the moment a picture
	// finished saving. Its backdrop is the view on screen.
	[TGAlertSheet showMessage:(error ? @"Could not save" : @"Saved to Camera Roll")
						title:nil
					   inView:(self.backdrop ?: [UIApplication sharedApplication].keyWindow)];
}

- (void)dealloc {
	[self restoreSource];
	[self.movieTimer invalidate];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// vim:ft=objc
