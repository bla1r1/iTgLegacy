//
// TGPlayerView.m - iOS 6 Reimagined Player System
// Persistent Docked Mini-Player and Fullscreen iPod/Music Deck Modal.
//
#import "TGPlayerView.h"
#import "TGMusicPlayer.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGStyle.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Constants

static const CGFloat kMiniArtSide        = TGMetricPlayerArt;
static const CGFloat kMiniBtnSide        = 32.0f;
static const CGFloat kMiniCloseSide      = 28.0f;
static const CGFloat kProgressHeight     = 2.0f;
static const CGFloat kModalHeaderH       = TGMetricRow;
static const CGFloat kModalArtSide       = TGMetricPlayerModalArtSide;
static const CGFloat kModalMainBtnSide   = TGMetricPlayerModalButtonMain;
static const CGFloat kModalSideBtnSide   = TGMetricPlayerModalButtonSide;
static const CGFloat kModalVolIconSide   = 20.0f;
static const CGFloat kModalSliderH       = TGMetricPlayerModalSliderH;
static const CGFloat kModalTimeW         = 50.0f;
static const CGFloat kModalTimeH         = 16.0f;
static const CGFloat kModalQueueRowH     = 50.0f;
static const CGFloat kShadowOffsetY      = 3.0f;

static NSString *TGPlayerFormatTime(NSTimeInterval seconds) {
	if (seconds < 0 || isnan(seconds)) seconds = 0;
	NSInteger total = (NSInteger)lround(seconds);
	NSInteger m = total / 60;
	NSInteger s = total % 60;
	return [NSString stringWithFormat:@"%02ld:%02ld", (long)m, (long)s];
}

#pragma mark - TGPlayerMiniBar

@implementation TGPlayerMiniBar {
	UIImageView *_artworkView;
	UILabel *_titleLabel;
	UILabel *_artistLabel;
	UIButton *_playPauseBtn;
	UIButton *_closeBtn;
	UIView *_progressTrack;
	UIView *_progressBar;
	NSTimer *_timer;
}

+ (instancetype)miniBarWithFrame:(CGRect)frame {
	return [[self alloc] initWithFrame:frame];
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	self.clipsToBounds = YES;

	TGTheme *theme = [TGTheme shared];
	CGFloat barW = frame.size.width;
	CGFloat barH = frame.size.height;

	// Background satin bar
	self.backgroundColor = [theme listBackgroundColour];

	// Artwork thumbnail
	CGFloat artY = TGCenteredOrigin(barH, kMiniArtSide);
	_artworkView = [[UIImageView alloc] initWithFrame:
			CGRectMake(TGMetricPadMedium, artY, kMiniArtSide, kMiniArtSide)];
	_artworkView.layer.cornerRadius = TGMetricCornerSmall;
	_artworkView.clipsToBounds = YES;
	_artworkView.contentMode = UIViewContentModeScaleAspectFill;
	_artworkView.backgroundColor = [theme fileTileColour];
	[self addSubview:_artworkView];

	// Close / stop button at right end
	CGFloat closeY = TGCenteredOrigin(barH, kMiniCloseSide);
	_closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_closeBtn.frame = CGRectMake(barW - TGMetricPad - kMiniCloseSide, closeY, kMiniCloseSide, kMiniCloseSide);
	_closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_closeBtn setImage:[TGIcons glyphNamed:@"close" colour:[theme secondaryTextColour] side:TGMetricPadLarge] forState:UIControlStateNormal];
	[_closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:_closeBtn];

	// Play/Pause button beside close button
	CGFloat playY = TGCenteredOrigin(barH, kMiniBtnSide);
	_playPauseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_playPauseBtn.frame = CGRectMake(barW - TGMetricPad - kMiniCloseSide - TGMetricPadSmall - kMiniBtnSide, playY, kMiniBtnSide, kMiniBtnSide);
	_playPauseBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_playPauseBtn addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:_playPauseBtn];

	// Title and artist text column
	CGFloat textLeft = TGMetricPadMedium + kMiniArtSide + TGMetricPadMedium;
	CGFloat textRight = barW - TGMetricPad - kMiniCloseSide - TGMetricPadSmall - kMiniBtnSide - TGMetricPadSmall;
	CGFloat textW = MAX(textRight - textLeft, (CGFloat)0.0f);

	_titleLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(textLeft, TGMetricPadSmall + 1.0f, textW, TGMetricLineCaption)];
	_titleLabel.font = TGFontCaptionStrong();
	_titleLabel.textColor = [theme primaryTextColour];
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:_titleLabel];

	_artistLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(textLeft, TGMetricPadSmall + TGMetricLineCaption, textW, TGMetricLineMicro)];
	_artistLabel.font = TGFontMicro();
	_artistLabel.textColor = [theme secondaryTextColour];
	_artistLabel.backgroundColor = [UIColor clearColor];
	_artistLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self addSubview:_artistLabel];

	// Progress hairline at the bottom
	_progressTrack = [[UIView alloc] initWithFrame:
			CGRectMake(0, barH - kProgressHeight, barW, kProgressHeight)];
	_progressTrack.backgroundColor = [theme separatorColour];
	_progressTrack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	[self addSubview:_progressTrack];

	_progressBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, barH - kProgressHeight, 0, kProgressHeight)];
	_progressBar.backgroundColor = [theme accentColour];
	[self addSubview:_progressBar];

	// Tap to expand modal player
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(barTapped:)];
	[self addGestureRecognizer:tap];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateState)
												 name:TGMusicPlayerChangedNotification
											   object:nil];

	[self updateState];
	[self startTimer];
	return self;
}

- (void)dealloc {
	[_timer invalidate];
	_timer = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)startTimer {
	[_timer invalidate];
	_timer = [NSTimer scheduledTimerWithTimeInterval:0.25
											  target:self
											selector:@selector(tick)
											userInfo:nil
											 repeats:YES];
}

- (void)tick {
	TGMusicPlayer *player = [TGMusicPlayer shared];
	if (!player.current || player.duration <= 0) {
		_progressBar.frame = CGRectMake(0, self.bounds.size.height - kProgressHeight, 0, kProgressHeight);
		return;
	}
	CGFloat frac = (CGFloat)(player.position / player.duration);
	frac = MIN(MAX(frac, (CGFloat)0.0f), (CGFloat)1.0f);
	CGFloat barW = self.bounds.size.width * frac;
	_progressBar.frame = CGRectMake(0, self.bounds.size.height - kProgressHeight, barW, kProgressHeight);
}

- (void)updateState {
	TGMusicPlayer *player = [TGMusicPlayer shared];
	if (!player.current) {
		self.hidden = YES;
		return;
	}
	self.hidden = NO;

	_titleLabel.text = [player titleForTrack:player.current];
	_artistLabel.text = [player performerForTrack:player.current];

	if (player.currentArtwork) {
		_artworkView.image = player.currentArtwork;
	} else {
		_artworkView.image = [TGIcons mediaDiscOfSide:kMiniArtSide playing:player.playing];
	}

	UIImage *playImg = player.playing ? [TGIcons pause] : [TGIcons play];
	[_playPauseBtn setImage:playImg forState:UIControlStateNormal];
	[_playPauseBtn setTintColor:[[TGTheme shared] accentColour]];

	[self tick];
}

- (void)playPauseTapped {
	[[TGMusicPlayer shared] togglePlayPause];
}

- (void)closeTapped {
	[[TGMusicPlayer shared] stop];
	if (self.onDismiss) self.onDismiss();
}

- (void)barTapped:(UITapGestureRecognizer *)gesture {
	CGPoint pt = [gesture locationInView:self];
	if (CGRectContainsPoint(_closeBtn.frame, pt) || CGRectContainsPoint(_playPauseBtn.frame, pt)) {
		return;
	}
	if (self.onTap) {
		self.onTap();
	} else {
		UIWindow *window = [UIApplication sharedApplication].keyWindow;
		UIViewController *root = window.rootViewController;
		while (root.presentedViewController) {
			root = root.presentedViewController;
		}
		[TGPlayerModalViewController presentFromViewController:root animated:YES];
	}
}

@end

#pragma mark - TGPlayerModalViewController

@interface TGPlayerModalViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TGPlayerModalViewController {
	UIView *_navBarView;
	UIButton *_dismissBtn;
	UILabel *_navTitleLabel;
	UIButton *_queueToggleBtn;

	UIView *_deckView;
	UIImageView *_artworkView;
	UIView *_artworkGlassOverlay;
	UILabel *_titleLabel;
	UILabel *_artistLabel;

	UIView *_scrubTrack;
	UIView *_scrubProgress;
	UIView *_scrubThumb;
	UILabel *_elapsedLabel;
	UILabel *_remainingLabel;
	BOOL _isScrubbing;

	UIButton *_prevBtn;
	UIButton *_playPauseBtn;
	UIButton *_nextBtn;

	UIButton *_repeatBtn;
	UISlider *_volumeSlider;
	UIButton *_shuffleBtn;

	UIView *_queueContainer;
	UITableView *_queueTable;
	NSTimer *_tickTimer;
}

+ (void)presentFromViewController:(UIViewController *)parent animated:(BOOL)animated {
	if (!parent) return;
	TGPlayerModalViewController *vc = [[TGPlayerModalViewController alloc] init];
	UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:vc];
	nc.navigationBarHidden = YES;
	nc.modalPresentationStyle = UIModalPresentationFullScreen;
	[parent presentViewController:nc animated:animated completion:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme groupedBackgroundColour];

	CGFloat screenW = self.view.bounds.size.width;
	CGFloat screenH = self.view.bounds.size.height;

	// 1. Navigation / Header Bar
	_navBarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, kModalHeaderH)];
	_navBarView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_navBarView.backgroundColor = [theme barColour];
	[self.view addSubview:_navBarView];

	// Down Chevron dismiss button
	_dismissBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_dismissBtn.frame = CGRectMake(TGMetricPadSmall, 0, kModalHeaderH, kModalHeaderH);
	[_dismissBtn setImage:[TGIcons chevronDown] forState:UIControlStateNormal];
	[_dismissBtn setTintColor:[theme barButtonColour]];
	[_dismissBtn addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];
	[_navBarView addSubview:_dismissBtn];

	// Header Title "Now Playing"
	_navTitleLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(kModalHeaderH, 0, screenW - TGDoubled(kModalHeaderH), kModalHeaderH)];
	_navTitleLabel.font = TGFontRowStrong();
	_navTitleLabel.textColor = [theme barTitleColour];
	_navTitleLabel.textAlignment = NSTextAlignmentCenter;
	_navTitleLabel.text = @"Now Playing";
	_navTitleLabel.backgroundColor = [UIColor clearColor];
	_navTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[_navBarView addSubview:_navTitleLabel];

	// Queue toggle button on right
	_queueToggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_queueToggleBtn.frame = CGRectMake(screenW - kModalHeaderH - TGMetricPadSmall, 0, kModalHeaderH, kModalHeaderH);
	_queueToggleBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_queueToggleBtn setImage:[TGIcons queueList] forState:UIControlStateNormal];
	[_queueToggleBtn setTintColor:[theme barButtonColour]];
	[_queueToggleBtn addTarget:self action:@selector(toggleQueueTapped) forControlEvents:UIControlEventTouchUpInside];
	[_navBarView addSubview:_queueToggleBtn];

	// 2. Main Deck View
	_deckView = [[UIView alloc] initWithFrame:
			CGRectMake(0, kModalHeaderH, screenW, screenH - kModalHeaderH)];
	_deckView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:_deckView];

	[self buildDeckContent];

	// 3. Queue Container View (Hidden initially)
	_queueContainer = [[UIView alloc] initWithFrame:
			CGRectMake(0, kModalHeaderH, screenW, screenH - kModalHeaderH)];
	_queueContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_queueContainer.backgroundColor = [theme listBackgroundColour];
	_queueContainer.hidden = YES;

	_queueTable = [[UITableView alloc] initWithFrame:_queueContainer.bounds style:UITableViewStylePlain];
	_queueTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_queueTable.dataSource = self;
	_queueTable.delegate = self;
	_queueTable.backgroundColor = [theme listBackgroundColour];
	_queueTable.separatorColor = [theme separatorColour];
	[_queueContainer addSubview:_queueTable];
	[self.view addSubview:_queueContainer];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(playerChanged)
												 name:TGMusicPlayerChangedNotification
											   object:nil];

	[self playerChanged];
}

- (void)buildDeckContent {
	CGFloat width = _deckView.bounds.size.width;
	TGTheme *theme = [TGTheme shared];

	// Calculate vertical layout
	CGFloat artX = TGCenteredOrigin(width, kModalArtSide);
	CGFloat y = TGMetricPadLarge;

	// Artwork Container with realistic drop shadow
	UIView *artShadowView = [[UIView alloc] initWithFrame:CGRectMake(artX, y, kModalArtSide, kModalArtSide)];
	artShadowView.layer.shadowColor = [UIColor blackColor].CGColor;
	artShadowView.layer.shadowOpacity = 0.35f;
	artShadowView.layer.shadowOffset = CGSizeMake(0, kShadowOffsetY);
	artShadowView.layer.shadowRadius = 4.0f;
	artShadowView.layer.cornerRadius = TGMetricCornerCard;
	[_deckView addSubview:artShadowView];

	_artworkView = [[UIImageView alloc] initWithFrame:artShadowView.bounds];
	_artworkView.layer.cornerRadius = TGMetricCornerCard;
	_artworkView.layer.borderColor = [UIColor whiteColor].CGColor;
	_artworkView.layer.borderWidth = 1.0f;
	_artworkView.clipsToBounds = YES;
	_artworkView.contentMode = UIViewContentModeScaleAspectFill;
	_artworkView.backgroundColor = [theme fileTileColour];
	[artShadowView addSubview:_artworkView];

	// Curved glass gloss reflection overlay across artwork
	_artworkGlassOverlay = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kModalArtSide, TGHalf(kModalArtSide))];
	_artworkGlassOverlay.backgroundColor = [theme skeuoShineColour];
	_artworkGlassOverlay.userInteractionEnabled = NO;
	[_artworkView addSubview:_artworkGlassOverlay];

	y += kModalArtSide + TGMetricPadLarge;

	// Track Title & Artist
	_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadWide, y, width - TGDoubled(TGMetricPadWide), TGMetricLineTitle)];
	_titleLabel.font = TGFontTitle();
	_titleLabel.textColor = [theme primaryTextColour];
	_titleLabel.textAlignment = NSTextAlignmentCenter;
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[_deckView addSubview:_titleLabel];

	y += TGMetricLineTitle + TGMetricPadTiny;

	_artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(TGMetricPadWide, y, width - TGDoubled(TGMetricPadWide), TGMetricLineRow)];
	_artistLabel.font = TGFontRow();
	_artistLabel.textColor = [theme secondaryTextColour];
	_artistLabel.textAlignment = NSTextAlignmentCenter;
	_artistLabel.backgroundColor = [UIColor clearColor];
	_artistLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[_deckView addSubview:_artistLabel];

	y += TGMetricLineRow + TGMetricPadLarge;

	// Scrubber Timeline
	CGFloat scrubMargin = TGMetricPadWide + TGMetricPad;
	CGFloat scrubW = width - TGDoubled(scrubMargin);

	UIView *scrubTapArea = [[UIView alloc] initWithFrame:CGRectMake(scrubMargin, y, scrubW, kModalSliderH)];
	scrubTapArea.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[_deckView addSubview:scrubTapArea];

	CGFloat trackY = TGCenteredOrigin(kModalSliderH, kProgressHeight);
	_scrubTrack = [[UIView alloc] initWithFrame:CGRectMake(0, trackY, scrubW, kProgressHeight)];
	_scrubTrack.backgroundColor = [theme separatorColour];
	_scrubTrack.layer.cornerRadius = TGHalf(kProgressHeight);
	_scrubTrack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[scrubTapArea addSubview:_scrubTrack];

	_scrubProgress = [[UIView alloc] initWithFrame:CGRectMake(0, trackY, 0, kProgressHeight)];
	_scrubProgress.backgroundColor = [theme accentColour];
	_scrubProgress.layer.cornerRadius = TGHalf(kProgressHeight);
	[scrubTapArea addSubview:_scrubProgress];

	_scrubThumb = [[UIImageView alloc] initWithImage:[TGTheme skeuomorphicSliderThumbWithRadius:TGMetricPad]];
	_scrubThumb.frame = CGRectMake(-TGMetricPad, TGCenteredOrigin(kModalSliderH, TGMetricPadWide), TGMetricPadWide, TGMetricPadWide);
	[scrubTapArea addSubview:_scrubThumb];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubGesture:)];
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrubGesture:)];
	[scrubTapArea addGestureRecognizer:pan];
	[scrubTapArea addGestureRecognizer:tap];

	y += kModalSliderH;

	// Elapsed & Remaining Time labels
	_elapsedLabel = [[UILabel alloc] initWithFrame:CGRectMake(scrubMargin, y, kModalTimeW, kModalTimeH)];
	_elapsedLabel.font = TGFontMicro();
	_elapsedLabel.textColor = [theme secondaryTextColour];
	_elapsedLabel.backgroundColor = [UIColor clearColor];
	[_deckView addSubview:_elapsedLabel];

	_remainingLabel = [[UILabel alloc] initWithFrame:CGRectMake(width - scrubMargin - kModalTimeW, y, kModalTimeW, kModalTimeH)];
	_remainingLabel.font = TGFontMicro();
	_remainingLabel.textColor = [theme secondaryTextColour];
	_remainingLabel.textAlignment = NSTextAlignmentRight;
	_remainingLabel.backgroundColor = [UIColor clearColor];
	_remainingLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_deckView addSubview:_remainingLabel];

	y += kModalTimeH + TGMetricPadLarge;

	// Main Transport Controls (Prev, Play/Pause, Next)
	CGFloat mainBtnY = y;
	CGFloat centerBtnX = TGCenteredOrigin(width, kModalMainBtnSide);

	_playPauseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_playPauseBtn.frame = CGRectMake(centerBtnX, mainBtnY, kModalMainBtnSide, kModalMainBtnSide);
	[TGTheme applySkeuomorphicStyleToButton:_playPauseBtn style:TGButtonStyleAction];
	[_playPauseBtn addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
	[_deckView addSubview:_playPauseBtn];

	CGFloat prevX = centerBtnX - TGMetricPadWide - kModalSideBtnSide;
	_prevBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_prevBtn.frame = CGRectMake(prevX, mainBtnY + TGCenteredOrigin(kModalMainBtnSide, kModalSideBtnSide), kModalSideBtnSide, kModalSideBtnSide);
	[TGTheme applySkeuomorphicStyleToButton:_prevBtn style:TGButtonStyleSilver];
	[_prevBtn setImage:[TGIcons previousTrack] forState:UIControlStateNormal];
	[_prevBtn addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
	[_deckView addSubview:_prevBtn];

	CGFloat nextX = centerBtnX + kModalMainBtnSide + TGMetricPadWide;
	_nextBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_nextBtn.frame = CGRectMake(nextX, mainBtnY + TGCenteredOrigin(kModalMainBtnSide, kModalSideBtnSide), kModalSideBtnSide, kModalSideBtnSide);
	[TGTheme applySkeuomorphicStyleToButton:_nextBtn style:TGButtonStyleSilver];
	[_nextBtn setImage:[TGIcons nextTrack] forState:UIControlStateNormal];
	[_nextBtn addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
	[_deckView addSubview:_nextBtn];

	y += kModalMainBtnSide + TGMetricPadWide;

	// Secondary Controls (Repeat, Volume Slider, Shuffle)
	CGFloat secY = y;
	CGFloat secSide = 36.0f;

	_repeatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_repeatBtn.frame = CGRectMake(scrubMargin, secY, secSide, secSide);
	[_repeatBtn addTarget:self action:@selector(repeatTapped) forControlEvents:UIControlEventTouchUpInside];
	[_deckView addSubview:_repeatBtn];

	_shuffleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
	_shuffleBtn.frame = CGRectMake(width - scrubMargin - secSide, secY, secSide, secSide);
	_shuffleBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_shuffleBtn addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
	[_deckView addSubview:_shuffleBtn];

	CGFloat volX = scrubMargin + secSide + TGMetricPadMedium;
	CGFloat volW = width - TGDoubled(volX);
	_volumeSlider = [[UISlider alloc] initWithFrame:CGRectMake(volX, secY + TGCenteredOrigin(secSide, TGMetricPadLarge), volW, TGMetricPadLarge)];
	_volumeSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_volumeSlider.minimumValueImage = [TGIcons volumeMin];
	_volumeSlider.maximumValueImage = [TGIcons volumeMax];
	_volumeSlider.value = [TGMusicPlayer shared].volume;
	[_volumeSlider setThumbImage:[TGTheme skeuomorphicSliderThumbWithRadius:TGMetricPad] forState:UIControlStateNormal];
	[_volumeSlider addTarget:self action:@selector(volumeChanged:) forControlEvents:UIControlEventValueChanged];
	[_deckView addSubview:_volumeSlider];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self startTimer];
	[self playerChanged];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_tickTimer invalidate];
	_tickTimer = nil;
}

- (void)dealloc {
	[_tickTimer invalidate];
	_tickTimer = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)startTimer {
	[_tickTimer invalidate];
	_tickTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
												  target:self
												selector:@selector(tick)
												userInfo:nil
												 repeats:YES];
}

- (void)tick {
	if (_isScrubbing) return;
	TGMusicPlayer *player = [TGMusicPlayer shared];
	if (!player.current || player.duration <= 0) {
		_elapsedLabel.text = @"00:00";
		_remainingLabel.text = @"-00:00";
		_scrubProgress.frame = CGRectMake(0, _scrubProgress.frame.origin.y, 0, kProgressHeight);
		_scrubThumb.center = CGPointMake(0, _scrubThumb.center.y);
		return;
	}

	CGFloat frac = (CGFloat)(player.position / player.duration);
	frac = MIN(MAX(frac, (CGFloat)0.0f), (CGFloat)1.0f);

	CGFloat totalW = _scrubTrack.bounds.size.width;
	_scrubProgress.frame = CGRectMake(0, _scrubProgress.frame.origin.y, totalW * frac, kProgressHeight);
	_scrubThumb.center = CGPointMake(totalW * frac, _scrubTrack.center.y);

	_elapsedLabel.text = TGPlayerFormatTime(player.position);
	_remainingLabel.text = [@"-" stringByAppendingString:TGPlayerFormatTime(player.duration - player.position)];
}

- (void)playerChanged {
	TGMusicPlayer *player = [TGMusicPlayer shared];
	if (!player.current) {
		[self dismissTapped];
		return;
	}

	_titleLabel.text = [player titleForTrack:player.current];
	_artistLabel.text = [player performerForTrack:player.current];

	if (player.currentArtwork) {
		_artworkView.image = player.currentArtwork;
	} else {
		_artworkView.image = [TGIcons mediaDiscOfSide:kModalArtSide playing:player.playing];
	}

	UIImage *playIcon = player.playing ? [TGIcons pause] : [TGIcons play];
	[_playPauseBtn setImage:playIcon forState:UIControlStateNormal];

	[_repeatBtn setImage:[TGIcons repeatModeIcon:player.repeatMode] forState:UIControlStateNormal];
	[_repeatBtn setTintColor:(player.repeatMode != TGMusicRepeatOff) ? [[TGTheme shared] accentColour] : [[TGTheme shared] secondaryTextColour]];

	[_shuffleBtn setImage:[TGIcons shuffleIconActive:player.shuffle] forState:UIControlStateNormal];
	[_shuffleBtn setTintColor:player.shuffle ? [[TGTheme shared] accentColour] : [[TGTheme shared] secondaryTextColour]];

	[_queueTable reloadData];
	[self tick];
}

#pragma mark - Actions

- (void)dismissTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleQueueTapped {
	BOOL show = _queueContainer.hidden;
	_queueContainer.hidden = !show;
	_deckView.hidden = show;
	_navTitleLabel.text = show ? @"Queue" : @"Now Playing";
	if (show) [_queueTable reloadData];
}

- (void)playPauseTapped {
	[[TGMusicPlayer shared] togglePlayPause];
}

- (void)prevTapped {
	[[TGMusicPlayer shared] previous];
}

- (void)nextTapped {
	[[TGMusicPlayer shared] next];
}

- (void)repeatTapped {
	[[TGMusicPlayer shared] cycleRepeatMode];
}

- (void)shuffleTapped {
	[[TGMusicPlayer shared] toggleShuffle];
}

- (void)volumeChanged:(UISlider *)slider {
	[TGMusicPlayer shared].volume = slider.value;
}

- (void)scrubGesture:(UIGestureRecognizer *)gesture {
	UIView *tapArea = gesture.view;
	CGFloat totalW = tapArea.bounds.size.width;
	if (totalW <= 0) return;

	CGPoint loc = [gesture locationInView:tapArea];
	CGFloat frac = MIN(MAX(loc.x / totalW, (CGFloat)0.0f), (CGFloat)1.0f);

	if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
		_isScrubbing = YES;
		_scrubProgress.frame = CGRectMake(0, _scrubProgress.frame.origin.y, totalW * frac, kProgressHeight);
		_scrubThumb.center = CGPointMake(totalW * frac, _scrubTrack.center.y);

		TGMusicPlayer *player = [TGMusicPlayer shared];
		NSTimeInterval pos = frac * player.duration;
		_elapsedLabel.text = TGPlayerFormatTime(pos);
		_remainingLabel.text = [@"-" stringByAppendingString:TGPlayerFormatTime(player.duration - pos)];
	} else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
		_isScrubbing = NO;
		[[TGMusicPlayer shared] seekToFraction:frac];
	}
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[TGMusicPlayer shared].tracks.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return kModalQueueRowH;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *ident = @"QueueCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
	}

	TGMusicPlayer *player = [TGMusicPlayer shared];
	if (indexPath.row < (NSInteger)player.tracks.count) {
		NSDictionary *track = player.tracks[indexPath.row];
		cell.textLabel.text = [player titleForTrack:track];
		cell.detailTextLabel.text = [player performerForTrack:track];

		BOOL isCurrent = (indexPath.row == player.index);
		if (isCurrent) {
			cell.textLabel.textColor = [[TGTheme shared] accentColour];
			cell.detailTextLabel.textColor = [[TGTheme shared] accentColour];
			cell.imageView.image = [TGIcons mediaDiscOfSide:TGMetricPadLarge playing:player.playing];
		} else {
			cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
			cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
			cell.imageView.image = [TGIcons mediaDiscOfSide:TGMetricPadLarge playing:NO];
		}
	}

	[[TGTheme shared] styleCell:cell];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	TGMusicPlayer *player = [TGMusicPlayer shared];
	if (indexPath.row < (NSInteger)player.tracks.count) {
		[player playTracks:player.tracks atIndex:indexPath.row inChat:player.currentMessageId];
		[self toggleQueueTapped];
	}
}

@end
