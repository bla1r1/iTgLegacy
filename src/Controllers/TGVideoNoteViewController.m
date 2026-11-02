#import "TGVideoNoteViewController.h"
#import "TGVideoNoteRecorder.h"
#import "TGRecordBar.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPreviewMax   = 300.0f;
static const CGFloat kPreviewInset = 40.0f;
/// As soft as the system's own blur from iOS 7, drawn once when the screen opens.
static const CGFloat kBlurRadius = 24.0f;

@interface TGVideoNoteViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t threadId;
@property (nonatomic, strong) UIImage *background;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UIView *previewHost;
@property (nonatomic, strong) TGRecordBar *bar;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger loggedSecond;
@property (nonatomic, strong) UIButton *onceButton;
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
	self.preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
	self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	// The front camera hands its frames over sideways on this hardware: the
	// preview itself asks for portrait. The connection mirrors a front camera
	// on its own, and asking it to again throws on iOS 6.
	AVCaptureConnection *previewConnection = self.preview.connection;
	if ([previewConnection isVideoOrientationSupported])
		previewConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
	self.preview.frame = self.previewHost.bounds;
	[self.previewHost.layer addSublayer:self.preview];
}

/// The circle is a hole in a square of the backdrop laid over the square video.
/// A rounded mask on live video makes the render server draw it offscreen for
/// every frame, which the A4 cannot spare; this blends one small image instead.
- (UIImage *)circleCoverForBackdrop:(UIImage *)backdrop {
	CGRect circle = self.previewFrame;
	CGSize screen = self.view.bounds.size;
	UIGraphicsBeginImageContextWithOptions(circle.size, NO, 0);
	CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
	[backdrop drawInRect:CGRectMake(-circle.origin.x, -circle.origin.y,
			screen.width, screen.height)];
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetBlendMode(ctx, kCGBlendModeClear);
	CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, circle.size.width, circle.size.height));
	UIImage *cover = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return cover;
}

- (void)loadView {
	self.view = [[UIView alloc] initWithFrame:self.overlayFrame];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	NSLog(@"TGVideoNoteVC: viewDidLoad bounds %@", NSStringFromCGRect(self.view.bounds));
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];

	// Spread to the screen's size once, so the backdrop and the circle's cover
	// are the same pixels: scaled up separately, by the GPU and by CoreGraphics,
	// the cover showed as a faint square around the circle.
	UIImage *small = [TGTheme softenedImage:self.background radius:kBlurRadius dim:TGAlphaHighlight];
	self.background = nil;
	UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, 1);
	CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
	[small drawInRect:self.view.bounds];
	UIImage *soft = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	UIImageView *backdrop = [[UIImageView alloc] initWithFrame:self.view.bounds];
	backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	backdrop.contentMode = UIViewContentModeScaleToFill;
	backdrop.opaque = YES;
	backdrop.image = soft;
	[self.view addSubview:backdrop];

	// The circle fills in as soon as frames exist: the warm-up loop is
	// off-thread, so until then the circle is a black window the controls
	// already work around.
	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;
	CGFloat barY = height - TGMetricInputBarHeight;
	CGFloat side = MIN(kPreviewMax, MIN(width - kPreviewInset, barY - TGDoubled(TGMetricPadLarge)));
	CGFloat y = TGCenteredOrigin(barY, side);
	self.previewFrame = CGRectMake(TGCenteredOrigin(self.view.bounds.size.width, side),
			y, side, side);
	self.previewHost = [[UIView alloc] initWithFrame:self.previewFrame];
	self.previewHost.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	self.previewHost.clipsToBounds = YES;
	[self.view addSubview:self.previewHost];
	UIImageView *cover = [[UIImageView alloc] initWithFrame:self.previewFrame];
	cover.image = [self circleCoverForBackdrop:soft];
	[self.view addSubview:cover];
	// A warm camera from an earlier go attaches at once; otherwise the
	// recorder's own callback lands here when startRunning has seen the lens.
	if ([TGVideoNoteRecorder shared].session.isRunning)
		[self attachPreviewWithSession:[TGVideoNoteRecorder shared].session];
	__weak typeof(self) weakSelf = self;
	[TGVideoNoteRecorder shared].onSession = ^(AVCaptureSession *session){
		[weakSelf attachPreviewWithSession:session];
	};

	// The same strip as a locked voice note, docked where the composer was.
	self.bar = [[TGRecordBar alloc] initWithFrame:CGRectMake(0, barY, width,
			TGMetricInputBarHeight)];
	[self.bar.cancelButton addTarget:self action:@selector(cancelTapped)
					forControlEvents:UIControlEventTouchUpInside];
	[self.bar.sendButton addTarget:self action:@selector(sendTapped)
				  forControlEvents:UIControlEventTouchUpInside];
	[self.bar.pauseButton addTarget:self action:@selector(pauseTapped)
				   forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.bar];

	// The "1" sits where the voice note keeps it: right above the strip, on
	// the same edge. The screen-flash light, which has no voice counterpart,
	// stacks above it in the same disc. The wash stays touch-transparent, so
	// the controls under it keep working.
	CGFloat columnX = width - TGMetricRow - TGMetricVoiceLockMaxShift;
	self.onceButton = [TGRecordBar onceButton];
	self.onceButton.frame = CGRectMake(columnX, barY - TGMetricRow - TGMetricPadMedium,
			TGMetricRow, TGMetricRow);
	self.onceButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleTopMargin;
	[self.onceButton addTarget:self action:@selector(onceTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.onceButton];

	self.flashButton = [TGRecordBar discOfSide:TGMetricRow];
	self.flashButton.frame = CGRectMake(columnX,
			CGRectGetMinY(self.onceButton.frame) - TGMetricRow - TGMetricPadSmall,
			TGMetricRow, TGMetricRow);
	self.flashButton.autoresizingMask = self.onceButton.autoresizingMask;
	[self showFlashOn:NO];
	[self.flashButton addTarget:self action:@selector(flashToggled)
			   forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.flashButton];

	self.flashView = [[UIView alloc] initWithFrame:self.view.bounds];
	self.flashView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.flashView.backgroundColor = [UIColor whiteColor];  // the lamp: white under every theme
	self.flashView.alpha = TGAlphaTransparent;
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
	if (!self.preview && [TGVideoNoteRecorder shared].session.isRunning)
		[self attachPreviewWithSession:[TGVideoNoteRecorder shared].session];
	NSLog(@"TGVideoNoteVC: appeared, preview %@", self.preview);
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.timer invalidate];
	self.timer = nil;
}

- (void)tick {
	TGVideoNoteRecorder *recorder = [TGVideoNoteRecorder shared];
	NSTimeInterval d = recorder.duration;
	[self.bar showSeconds:d paused:recorder.paused];
	// Once per second of recording is enough for the log: when the clock
	// refuses to walk on the device, this is where the line stops.
	if (!self.loggedSecond || (NSInteger)d != self.loggedSecond - 1){
		self.loggedSecond = (NSInteger)d + 1;
		NSLog(@"TGVideoNote: clock %.1f s (recording=%d paused=%d)",
				d, recorder.recording, recorder.paused);
	}
}

- (void)onceTapped {
	self.onceOn = !self.onceOn;
	[TGRecordBar setOnce:self.onceOn onButton:self.onceButton];
}

/// The recorder pauses the way Telegram's does: nothing new is written and
/// the clock stands where it stopped; a second tap carries on. The label
/// does not need its own bookkeeping - the recorder's duration is already
/// counted frames, not wall time.
- (void)pauseTapped {
	TGVideoNoteRecorder *recorder = [TGVideoNoteRecorder shared];
	if (recorder.paused){
		[recorder resume];
		[self.bar.pauseButton setImage:[TGIcons pause] forState:UIControlStateNormal];
	} else {
		[recorder pause];
		[self.bar.pauseButton setImage:[TGIcons play] forState:UIControlStateNormal];
	}
}

/// The screen as the lamp: full-white at half power, over everything but
/// never swallowing a tap. A second tap turns it off.
- (void)flashToggled {
	BOOL on = self.flashView.alpha <= TGAlphaTransparent;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.flashView.alpha = on ? TGAlphaDimmed : TGAlphaTransparent;
	}];
	[self showFlashOn:on];
}

/// Drawn in its colour rather than tinted: iOS 6 ignores a tint on a custom
/// button's image.
- (void)showFlashOn:(BOOL)on {
	TGTheme *theme = [TGTheme shared];
	self.flashButton.backgroundColor = on ? [theme accentColour] : [theme inputBarColour];
	[self.flashButton setImage:[TGIcons glyphNamed:@"flash"
											colour:on ? [theme onAccentColour] : [theme primaryTextColour]
											  side:TGMetricMenuGlyph]
					  forState:UIControlStateNormal];
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
	[self.view removeFromSuperview];
	if (self.onDismiss)
		self.onDismiss();
}

@end
