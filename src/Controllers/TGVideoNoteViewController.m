#import "TGVideoNoteViewController.h"
#import "TGVideoNoteRecorder.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPreviewMax   = 300.0f;
static const CGFloat kPreviewInset = 40.0f;
static const CGFloat kBarHeight    = 58.0f;
static const CGFloat kOnceSide     = 44.0f;
static const CGFloat kSendSide     = 54.0f;
static const CGFloat kDotSide      = 10.0f;
static const CGFloat kBarInset     = 14.0f;
static const CGFloat kBlurDownscale = 14.0f;
static const CGFloat kTimerWidth   = 82.0f;
static const CGFloat kCancelWidth  = 94.0f;
/// A soft backdrop without CoreImage: the same downsample/upscale trick the
/// hold presentation uses, which cannot fault on the A4.
static UIImage *TGVideoNoteBlurredImage(UIImage *image) {
	if (!image)
		return nil;
	CGSize size = image.size;
	if (size.width < 2 || size.height < 2)
		return nil;
	CGSize small = CGSizeMake(MAX(1.0f, floorf(size.width / kBlurDownscale)),
							  MAX(1.0f, floorf(size.height / kBlurDownscale)));
	UIGraphicsBeginImageContextWithOptions(small, NO, 1.0f);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	if (!ctx){
		UIGraphicsEndImageContext();
		return nil;
	}
	CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
	[image drawInRect:CGRectMake(0, 0, small.width, small.height)];
	UIImage *down = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (!down)
		return nil;
	UIGraphicsBeginImageContextWithOptions(size, NO, 1.0f);
	ctx = UIGraphicsGetCurrentContext();
	if (!ctx){
		UIGraphicsEndImageContext();
		return nil;
	}
	CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
	[down drawInRect:CGRectMake(0, 0, size.width, size.height)];
	UIImage *soft = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return soft;
}

@interface TGVideoNoteViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t threadId;
@property (nonatomic, strong) UIImage *background;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIButton *onceButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIView *flashView;
@property (nonatomic, assign) CGRect previewFrame;
@property (nonatomic, assign) BOOL onceOn;
@property (nonatomic, assign) BOOL sending;
@end

@implementation TGVideoNoteViewController

- (instancetype)initWithChatId:(int64_t)chatId
					  threadId:(int64_t)threadId
					background:(UIImage *)background {
	self = [super init];
	if (self){
		_chatId = chatId;
		_threadId = threadId;
		_background = background;
		_onceOn = NO;
	}
	return self;
}

/// Brings the camera picture in the moment the lens answers. Runs at most
/// once per overlay; whichever of viewDidAppear and the recorder's callback
/// comes first wins.
- (void)attachPreviewWithSession:(AVCaptureSession *)session {
	if (self.preview || !session)
		return;
	CGRect circle = self.previewFrame;
	self.preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
	self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	// The front camera hands its frames over sideways on this hardware: the
	// preview itself asks for portrait, and the mirroring is what makes
	// round video feel right in the hand, like Telegram.
	AVCaptureConnection *previewConnection = self.preview.connection;
	if ([previewConnection isVideoOrientationSupported])
		previewConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
	if ([previewConnection isVideoMirroringSupported] &&
			[[TGVideoNoteRecorder shared] isFrontCamera])
		previewConnection.videoMirrored = YES;
	UIView *host = [[UIView alloc] initWithFrame:circle];
	host.layer.cornerRadius = TGHalf(circle.size.width);
	host.layer.masksToBounds = YES;
	host.backgroundColor = [UIColor blackColor];
	// Just above the dim, below every control built over the chat.
	[self.view insertSubview:host atIndex:2];
	self.preview.frame = host.bounds;
	[host.layer addSublayer:self.preview];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	NSLog(@"TGVideoNoteVC: viewDidLoad bounds %@", NSStringFromCGRect(self.view.bounds));
	self.view.backgroundColor = [UIColor blackColor];

	UIImageView *backdrop = [[UIImageView alloc] initWithFrame:self.view.bounds];
	backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	backdrop.contentMode = UIViewContentModeScaleAspectFill;
	backdrop.clipsToBounds = YES;
	backdrop.image = TGVideoNoteBlurredImage(self.background);
	[self.view addSubview:backdrop];

	UIView *dim = [[UIView alloc] initWithFrame:self.view.bounds];
	dim.autoresizingMask = backdrop.autoresizingMask;
	dim.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	dim.alpha = 0.28f;
	[self.view addSubview:dim];

	// The circle fills in as soon as frames exist: the warm-up loop is
	// off-thread, so until then the circle is a black window the controls
	// already work around.
	CGFloat side = MIN(kPreviewMax, MIN(self.view.bounds.size.width - kPreviewInset,
									   self.view.bounds.size.height * 0.58f));
	CGFloat y = TGCenteredOrigin(self.view.bounds.size.height * 0.46f, side);
	self.previewFrame = CGRectMake(TGCenteredOrigin(self.view.bounds.size.width, side),
			y, side, side);
	// A warm camera from an earlier go attaches at once; otherwise the
	// recorder's own callback lands here when startRunning has seen the lens.
	if ([TGVideoNoteRecorder shared].session)
		[self attachPreviewWithSession:[TGVideoNoteRecorder shared].session];
	__weak typeof(self) weakSelf = self;
	[TGVideoNoteRecorder shared].onSession = ^(AVCaptureSession *session){
		[weakSelf attachPreviewWithSession:session];
	};

	CGFloat barY = self.view.bounds.size.height - kBarHeight - kBarInset;
	UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, barY,
			self.view.bounds.size.width, kBarHeight)];
	bar.backgroundColor = [[TGTheme shared] inputBarColour];
	bar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
			UIViewAutoresizingFlexibleWidth;

	UIImageView *barBg = [[UIImageView alloc] initWithFrame:bar.bounds];
	barBg.image = [TGTheme skeuomorphicInputBarImageWithHeight:kBarHeight];
	barBg.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	[bar addSubview:barBg];
	[self.view addSubview:bar];

	UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(kBarInset,
			TGCenteredOrigin(kBarHeight, kDotSide), kDotSide, kDotSide)];
	dot.backgroundColor = [[TGTheme shared] destructiveColour];
	dot.layer.cornerRadius = TGHalf(kDotSide);
	[bar addSubview:dot];

	self.timerLabel = [[UILabel alloc] initWithFrame:CGRectMake(kBarInset + kDotSide +
			TGMetricPadSmall, TGMetricZero, kTimerWidth, kBarHeight)];
	self.timerLabel.font = TGFontBody();
	self.timerLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.timerLabel.backgroundColor = [UIColor clearColor];
	self.timerLabel.text = @"0:00,0";
	[bar addSubview:self.timerLabel];

	UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
	cancel.frame = CGRectMake(CGRectGetMaxX(self.timerLabel.frame) + TGMetricPad,
			TGMetricZero, kCancelWidth, kBarHeight);
	[cancel setTitle:@"Cancel" forState:UIControlStateNormal];
	[cancel setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
	cancel.backgroundColor = [UIColor clearColor];
	cancel.titleLabel.font = TGFontRow();
	[cancel addTarget:self action:@selector(cancelTapped)
	 forControlEvents:UIControlEventTouchUpInside];
	[cancel setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
	[bar addSubview:cancel];

	UIButton *send = [UIButton buttonWithType:UIButtonTypeCustom];
	send.frame = CGRectMake(bar.bounds.size.width - kSendSide - TGMetricPadSmall,
			TGCenteredOrigin(kBarHeight, kSendSide), kSendSide, kSendSide);
	send.backgroundColor = [[TGTheme shared] accentColour];
	send.layer.cornerRadius = TGHalf(kSendSide);
	[send setImage:[TGIcons send] forState:UIControlStateNormal];
	[send setTintColor:[[TGTheme shared] onAccentColour]];
	[send addTarget:self action:@selector(sendTapped)
   forControlEvents:UIControlEventTouchUpInside];
	[bar addSubview:send];

	self.onceButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.onceButton.frame = CGRectMake(self.view.bounds.size.width - kOnceSide - kBarInset,
			barY - TGDoubled(kOnceSide) - TGMetricPadLarge - TGMetricPad,
			kOnceSide, kOnceSide);
	self.onceButton.layer.cornerRadius = TGHalf(kOnceSide);
	self.onceButton.layer.borderWidth = TGMetricHairline;
	self.onceButton.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	self.onceButton.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	self.onceButton.titleLabel.font = TGFontCaptionStrong();
	[self.onceButton setTitle:@"1" forState:UIControlStateNormal];
	self.onceButton.accessibilityLabel = @"View once";
	[self.onceButton setTitleColor:[[TGTheme shared] primaryTextColour]
						  forState:UIControlStateNormal];
	self.onceButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleTopMargin;
	[self.onceButton addTarget:self action:@selector(onceTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.onceButton];

	UIButton *pause = [UIButton buttonWithType:UIButtonTypeCustom];
	pause.frame = CGRectMake(self.view.bounds.size.width - kOnceSide - kBarInset,
			barY - kOnceSide - TGMetricPad,
			kOnceSide, kOnceSide);
	pause.layer.cornerRadius = TGHalf(kOnceSide);
	pause.layer.borderWidth = TGMetricHairline;
	pause.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	pause.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	[pause setImage:[TGIcons pause] forState:UIControlStateNormal];
	pause.tintColor = [[TGTheme shared] primaryTextColour];
	pause.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleTopMargin;
	[pause addTarget:self action:@selector(pauseTapped)
	 forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:pause];
	self.pauseButton = pause;

	UIButton *flip = [UIButton buttonWithType:UIButtonTypeCustom];
	flip.frame = CGRectMake(kBarInset, CGRectGetMinY(pause.frame),
			kOnceSide, kOnceSide);
	flip.layer.cornerRadius = TGHalf(kOnceSide);
	flip.layer.borderWidth = TGMetricHairline;
	flip.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	flip.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	[flip setImage:[TGIcons glyphNamed:@"video"
							   colour:[[TGTheme shared] primaryTextColour]
								 side:TGMetricMenuGlyph]
		  forState:UIControlStateNormal];
	flip.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
	// The screen-flash light takes the two dead controls' spot (the camera
	// flip and the mic mute, which the capture output could never do): a
	// bolt, and the flash itself is a bright wash over the screen - front
	// cameras on hardware with no torch light themselves this way. It stays
	// touch-transparent, so the controls above the wash keep working.
	UIButton *flash = [UIButton buttonWithType:UIButtonTypeCustom];
	flash.frame = CGRectMake(kBarInset, CGRectGetMinY(pause.frame),
			kOnceSide, kOnceSide);
	flash.layer.cornerRadius = TGHalf(kOnceSide);
	flash.layer.borderWidth = TGMetricHairline;
	flash.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	flash.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
	[flash setImage:[TGIcons glyphNamed:@"flash"
								 colour:[[TGTheme shared] primaryTextColour]
								   side:TGMetricMenuGlyph]
		  forState:UIControlStateNormal];
	flash.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
	[flash addTarget:self action:@selector(flashToggled)
    forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:flash];
	self.flashButton = flash;

	self.flashView = [[UIView alloc] initWithFrame:self.view.bounds];
	self.flashView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.flashView.backgroundColor = [UIColor whiteColor];
	self.flashView.alpha = 0.0f;
	self.flashView.userInteractionEnabled = NO;
	[self.view addSubview:self.flashView];
	[self.view bringSubviewToFront:self.flashView];

	self.timer = [NSTimer timerWithTimeInterval:0.1 target:self
									   selector:@selector(tick) userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	// Whatever came before this view had time to run, the lens may already
	// be up without the callback landing here - attach what is there.
	if (!self.preview && [TGVideoNoteRecorder shared].session)
		[self attachPreviewWithSession:[TGVideoNoteRecorder shared].session];
	NSLog(@"TGVideoNoteVC: appeared, preview %@", self.preview);
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.timer invalidate];
	self.timer = nil;
}

- (void)tick {
	NSTimeInterval d = [TGVideoNoteRecorder shared].duration;
	self.timerLabel.text = [NSString stringWithFormat:@"%ld:%02ld,%ld",
			(long)(d / 60), (long)((NSInteger)d % 60),
			(long)((NSInteger)(d * 10) % 10)];
	// Once a second is enough for the same fact in the log: when the clock
	// refuses to walk on the device, this is where the line stops.
	if (((NSInteger)(d * 10)) % 10 < 1)
		NSLog(@"TGVideoNote: clock %.1f s (recording=%d paused=%d)",
				d,
				[[TGVideoNoteRecorder shared] recording],
				[[TGVideoNoteRecorder shared] paused]);
}

- (void)onceTapped {
	self.onceOn = !self.onceOn;
	BOOL on = self.onceOn;
	[self.onceButton setTitleColor:on ? [[TGTheme shared] onAccentColour]
									 : [[TGTheme shared] barButtonColour]
						  forState:UIControlStateNormal];
	self.onceButton.backgroundColor = on ? [[TGTheme shared] accentColour]
										 : [UIColor clearColor];
}

/// The recorder pauses the way Telegram's does: nothing new is written and
/// the clock stands where it stopped; a second tap carries on. The label
/// does not need its own bookkeeping - the recorder's duration is already
/// counted frames, not wall time.
- (void)pauseTapped {
	TGVideoNoteRecorder *recorder = [TGVideoNoteRecorder shared];
	if (recorder.paused){
		[recorder resume];
		[self.pauseButton setImage:[TGIcons pause] forState:UIControlStateNormal];
	} else {
		[recorder pause];
		[self.pauseButton setImage:[TGIcons play] forState:UIControlStateNormal];
	}
}

/// The screen as the lamp: full-white at half power, over everything but
/// never swallowing a tap. A second tap turns it off.
- (void)flashToggled {
	BOOL on = self.flashView.alpha <= 0.0f;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.flashView.alpha = on ? 0.55f : 0.0f;
	}];
	self.flashButton.backgroundColor = on ? [[TGTheme shared] accentColour]
										  : [[TGTheme shared] cardBackgroundColour];
	self.flashButton.tintColor = on ? [[TGTheme shared] onAccentColour]
									: [[TGTheme shared] primaryTextColour];
}

- (void)sendTapped {
	if (self.sending)
		return;
	self.sending = YES;
	[self.timer invalidate];
	BOOL once = self.onceOn;
	int64_t chatId = self.chatId;
	int64_t threadId = self.threadId;
	__weak typeof(self) weakSelf = self;
	[[TGVideoNoteRecorder shared] stopWithCompletion:^(NSString *path, NSTimeInterval seconds){
		if (path && seconds >= 0.5)
			[[TGClient shared] sendVideoNoteAtPath:path
										  duration:(NSInteger)seconds
											toChat:chatId
											thread:threadId
										  viewOnce:once];
		[weakSelf dismiss];
	}];
}

- (void)cancelTapped {
	[self.timer invalidate];
	[[TGVideoNoteRecorder shared] cancel];
	[self dismiss];
}

- (void)dismiss {
	[TGVideoNoteRecorder shared].onSession = nil;
	[TGVideoNoteRecorder shared].onReady = nil;
	[self willMoveToParentViewController:nil];
	[self.view removeFromSuperview];
	[self removeFromParentViewController];
	if (self.onDismiss)
		self.onDismiss();
}

@end
