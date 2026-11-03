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
/// A note may run a minute, and Telegram's recorder stops a beat short of it and
/// still calls it a minute.
static const NSTimeInterval kNoteLimitSeconds = 59.0;
static const NSInteger kNoteLimitShown = 60;
/// The progress line sits just outside the circle.
static const CGFloat kRingOutset = 3.0f;
static const CGFloat kRingWidth  = 3.0f;
/// Where the circle grows from and shrinks to, as a share of its size.
static const CGFloat kStageScaleHidden = 0.7f;
/// How far past its size the circle goes before settling.
static const CGFloat kStageScaleOver = 1.03f;
static const CGFloat kPendingWidth = 196.0f;
static const CGFloat kPendingHeight = 30.0f;
static const CGFloat kPendingTop = 72.0f;

@interface TGVideoNoteViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t threadId;
@property (nonatomic, strong) UIImage *background;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UIView *stage;
@property (nonatomic, strong) UIView *previewHost;
@property (nonatomic, strong) UIImageView *circleCover;
@property (nonatomic, strong) CAShapeLayer *ring;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) TGRecordBar *bar;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger loggedSecond;
@property (nonatomic, strong) UIButton *onceButton;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIButton *flipButton;
@property (nonatomic, strong) UIView *lampBackdrop;
@property (nonatomic, strong) UIImageView *lampCover;
@property (nonatomic, assign) BOOL lampOn;
@property (nonatomic, assign) CGFloat brightnessBefore;
@property (nonatomic, assign) CGRect previewFrame;
@property (nonatomic, assign) BOOL onceOn;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL atLimit;
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

#pragma mark - camera

- (void)attachPreviewWithSession:(AVCaptureSession *)session {
	if (self.preview || !session)
		return;
	// From here the picture is live, and rounding it would cost a frame's worth
	// of offscreen drawing every frame. See the note on the cover.
	self.previewHost.clipsToBounds = NO;
	self.circleCover.hidden = NO;
	self.preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
	self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	self.preview.frame = self.previewHost.bounds;
	[self applyPreviewOrientation];
	[self.previewHost.layer addSublayer:self.preview];
}

/// The front camera hands its frames over sideways on this hardware: the preview
/// asks for portrait, again after a flip. The connection mirrors a front camera
/// on its own, and asking it to as well throws on iOS 6.
- (void)applyPreviewOrientation {
	AVCaptureConnection *connection = self.preview.connection;
	if ([connection isVideoOrientationSupported])
		connection.videoOrientation = AVCaptureVideoOrientationPortrait;
}

- (void)recordingBecameReady {
	self.ready = YES;
	[self.spinner stopAnimating];
	[self.bar setActionsEnabled:YES animated:YES];
	[self startRingFrom:0];
}

#pragma mark - building

/// The circle is a hole in a square of the backdrop laid over the square video.
/// A rounded mask on live video makes the render server draw it offscreen for
/// every frame, which the A4 cannot spare; this blends one small image instead.
- (UIImage *)circleCoverForBackdrop:(UIImage *)backdrop {
	CGRect circle = self.previewFrame;
	CGSize screen = self.view.bounds.size;
	UIGraphicsBeginImageContextWithOptions(circle.size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
	if (backdrop){
		[backdrop drawInRect:CGRectMake(-circle.origin.x, -circle.origin.y,
				screen.width, screen.height)];
	} else {
		[[UIColor whiteColor] setFill];  // the lamp: white under every theme
		CGContextFillRect(ctx, CGRectMake(0, 0, circle.size.width, circle.size.height));
	}
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
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];

	// The chat itself, the same pixels at the same place and only darker, so
	// nothing moves or changes when this opens: recording is a state of the chat
	// the way a voice note is, not a screen of its own. One flat image, because
	// the circle's cover has to match it and a translucent layer over the live
	// chat would be blended again for every video frame. Messages that arrive
	// meanwhile show when the recording ends.
	UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, 0.0f);
	[self.background drawInRect:self.view.bounds];
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, [[[TGTheme shared] mediaViewerBackdropColour]
			colorWithAlphaComponent:TGAlphaHighlight].CGColor);
	CGContextFillRect(ctx, self.view.bounds);
	UIImage *dimmed = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	self.background = nil;
	UIImageView *backdrop = [[UIImageView alloc] initWithFrame:self.view.bounds];
	backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	backdrop.opaque = YES;
	backdrop.image = dimmed;
	[self.view addSubview:backdrop];

	self.lampBackdrop = [[UIView alloc] initWithFrame:self.view.bounds];
	self.lampBackdrop.autoresizingMask = backdrop.autoresizingMask;
	self.lampBackdrop.backgroundColor = [UIColor whiteColor];  // the lamp: white under every theme
	self.lampBackdrop.alpha = TGAlphaTransparent;
	self.lampBackdrop.userInteractionEnabled = NO;
	[self.view addSubview:self.lampBackdrop];

	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;
	CGFloat barY = height - TGMetricInputBarHeight;
	CGFloat side = MIN(kPreviewMax, MIN(width - kPreviewInset, barY - TGDoubled(TGMetricPadLarge)));
	self.previewFrame = CGRectMake(TGCenteredOrigin(width, side), TGCenteredOrigin(barY, side),
			side, side);
	CGRect local = CGRectMake(0, 0, side, side);

	self.stage = [[UIView alloc] initWithFrame:self.previewFrame];
	self.previewHost = [[UIView alloc] initWithFrame:local];
	self.previewHost.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	self.previewHost.clipsToBounds = YES;
	[self.stage addSubview:self.previewHost];
	// The cover only lines up with the backdrop at full size: scaled with the
	// stage, its square of chat would slide over the chat behind it. So while the
	// circle grows and shrinks the host rounds itself, which is cheap on a plain
	// black layer and only for a moment on the video.
	self.previewHost.layer.cornerRadius = TGHalf(side);
	self.circleCover = [[UIImageView alloc] initWithFrame:local];
	self.circleCover.image = [self circleCoverForBackdrop:dimmed];
	self.circleCover.hidden = YES;
	[self.stage addSubview:self.circleCover];
	self.lampCover = [[UIImageView alloc] initWithFrame:local];
	self.lampCover.alpha = TGAlphaTransparent;
	[self.stage addSubview:self.lampCover];
	[self buildRingOfSide:side];

	// The camera takes more than a second to wake and the main thread is held
	// while it does. This turns in the render server all the same, so the screen
	// says it is working instead of looking frozen.
	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
			UIActivityIndicatorViewStyleWhiteLarge];
	self.spinner.center = CGPointMake(TGHalf(side), TGHalf(side));
	self.spinner.hidesWhenStopped = YES;
	[self.spinner startAnimating];
	[self.stage addSubview:self.spinner];
	[self.view addSubview:self.stage];

	__weak typeof(self) weakSelf = self;
	TGVideoNoteRecorder *recorder = [TGVideoNoteRecorder shared];
	if (recorder.session.isRunning)
		[self attachPreviewWithSession:recorder.session];
	recorder.onSession = ^(AVCaptureSession *session){
		[weakSelf attachPreviewWithSession:session];
	};
	recorder.onReady = ^{
		[weakSelf recordingBecameReady];
	};
	recorder.onCameraSwitched = ^{
		[weakSelf applyPreviewOrientation];
	};

	// The same strip as a locked voice note, docked where the composer was. It
	// fades over the hold's strip in the same place, so it never travels.
	self.bar = [[TGRecordBar alloc] initWithFrame:CGRectMake(0, barY, width,
			TGMetricInputBarHeight)];
	[self.bar.cancelButton addTarget:self action:@selector(cancelTapped)
					forControlEvents:UIControlEventTouchUpInside];
	[self.bar.sendButton addTarget:self action:@selector(sendTapped)
				  forControlEvents:UIControlEventTouchUpInside];
	[self.bar.pauseButton addTarget:self action:@selector(pauseTapped)
				   forControlEvents:UIControlEventTouchUpInside];
	[self.bar setActionsEnabled:NO animated:NO];
	[self.view addSubview:self.bar];

	// The "1" sits where the voice note keeps it: right above the strip, on the
	// same edge. The lamp, which has no voice counterpart, stacks above it, and
	// the flip faces them from the other side.
	CGFloat columnX = width - TGMetricRow - TGMetricVoiceLockMaxShift;
	CGFloat columnY = barY - TGMetricRow - TGMetricPadMedium;
	self.onceButton = [TGRecordBar onceButton];
	self.onceButton.frame = CGRectMake(columnX, columnY, TGMetricRow, TGMetricRow);
	self.onceButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleTopMargin;
	[self.onceButton addTarget:self action:@selector(onceTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.onceButton];

	self.flashButton = [TGRecordBar discOfSide:TGMetricRow];
	self.flashButton.frame = CGRectMake(columnX, columnY - TGMetricRow - TGMetricPadSmall,
			TGMetricRow, TGMetricRow);
	self.flashButton.autoresizingMask = self.onceButton.autoresizingMask;
	[self showLampButtonOn:NO];
	[self.flashButton addTarget:self action:@selector(flashToggled)
			   forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.flashButton];

	if ([AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1){
		self.flipButton = [TGRecordBar discOfSide:TGMetricRow];
		self.flipButton.frame = CGRectMake(TGMetricVoiceLockMaxShift, columnY,
				TGMetricRow, TGMetricRow);
		self.flipButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
		[self.flipButton setImage:[TGRecordBar flipGlyphOfSide:TGMetricMenuGlyph
														colour:[[TGTheme shared] primaryTextColour]]
						 forState:UIControlStateNormal];
		self.flipButton.accessibilityLabel = @"Switch camera";
		[self.flipButton addTarget:self action:@selector(flipTapped)
				  forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:self.flipButton];
	}

	self.timer = [NSTimer timerWithTimeInterval:0.1 target:self
									   selector:@selector(tick) userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

	[self prepareEntrance];
	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf playEntrance];
	});
}

#pragma mark - entrance and exit

- (NSArray *)sideControls {
	NSMutableArray *controls = [NSMutableArray arrayWithObjects:self.onceButton, self.flashButton, nil];
	if (self.flipButton)
		[controls addObject:self.flipButton];
	return controls;
}

- (void)prepareEntrance {
	self.view.alpha = TGAlphaTransparent;
	self.stage.transform = CGAffineTransformMakeScale(kStageScaleHidden, kStageScaleHidden);
	for (UIView *control in [self sideControls])
		control.alpha = TGAlphaTransparent;
}

/// One keyframe animation rather than two steps chained by a completion block:
/// the render server runs it to the end by itself, and a completion would wait
/// on a main thread that startRunning is holding, leaving the circle stuck past
/// its size with the cover's square edge showing.
- (void)playEntrance {
	CAKeyframeAnimation *grow = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
	grow.values = @[@(kStageScaleHidden), @(kStageScaleOver), @(1.0f)];
	grow.keyTimes = @[@0.0f, @0.66f, @1.0f];
	grow.duration = TGAnimationDurationSlow;
	grow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
	self.stage.transform = CGAffineTransformIdentity;
	[self.stage.layer addAnimation:grow forKey:@"entrance"];

	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.view.alpha = TGAlphaOpaque;
	}];
	[UIView animateWithDuration:TGAnimationDurationNormal delay:TGAnimationDurationFast
						options:UIViewAnimationOptionCurveEaseOut animations:^{
		for (UIView *control in [self sideControls])
			control.alpha = TGAlphaOpaque;
	} completion:nil];
}

- (void)dismiss {
	TGVideoNoteRecorder *recorder = [TGVideoNoteRecorder shared];
	recorder.onSession = nil;
	recorder.onReady = nil;
	recorder.onCameraSwitched = nil;
	[self.timer invalidate];
	self.timer = nil;
	[self restoreBrightness];
	[self.spinner stopAnimating];
	self.previewHost.clipsToBounds = YES;
	self.circleCover.hidden = YES;
	self.lampCover.hidden = YES;
	// The chat behind has its composer back before the screen has finished
	// leaving, so the two do not trade places with a gap.
	if (self.onDismiss)
		self.onDismiss();
	self.onDismiss = nil;
	[UIView animateWithDuration:TGAnimationDurationNormal delay:0
						options:UIViewAnimationOptionCurveEaseIn animations:^{
		self.view.alpha = TGAlphaTransparent;
		self.stage.transform = CGAffineTransformMakeScale(kStageScaleHidden, kStageScaleHidden);
	} completion:^(BOOL finished){
		[self.view removeFromSuperview];
	}];
}

#pragma mark - the clock and the ring

- (void)buildRingOfSide:(CGFloat)side {
	CGFloat radius = TGHalf(side) + kRingOutset;
	UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(TGHalf(side), TGHalf(side))
														radius:radius
													startAngle:(CGFloat)-M_PI_2
													  endAngle:(CGFloat)(M_PI + M_PI_2)
													 clockwise:YES];
	self.ring = [CAShapeLayer layer];
	self.ring.frame = CGRectMake(0, 0, side, side);
	self.ring.path = path.CGPath;
	self.ring.fillColor = [UIColor clearColor].CGColor;
	self.ring.strokeColor = [[TGTheme shared] accentColour].CGColor;
	self.ring.lineWidth = kRingWidth;
	self.ring.lineCap = kCALineCapRound;
	self.ring.strokeEnd = 0;
	[self.stage.layer addSublayer:self.ring];
}

/// One animation over what is left of the minute, not a redraw per tick: the
/// render server carries it and the main thread pays nothing while recording.
- (void)startRingFrom:(NSTimeInterval)seconds {
	CGFloat done = MIN(1.0f, (CGFloat)(seconds / kNoteLimitSeconds));
	CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
	grow.fromValue = @(done);
	grow.toValue = @(1.0f);
	grow.duration = MAX(0.0, kNoteLimitSeconds - seconds);
	grow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
	self.ring.speed = 1;
	self.ring.timeOffset = 0;
	self.ring.beginTime = 0;
	self.ring.strokeEnd = 1;
	[self.ring addAnimation:grow forKey:@"grow"];
}

- (void)freezeRingAt:(NSTimeInterval)seconds {
	[self.ring removeAnimationForKey:@"grow"];
	self.ring.strokeEnd = MIN(1.0f, (CGFloat)(seconds / kNoteLimitSeconds));
}

- (void)tick {
	TGVideoNoteRecorder *recorder = [TGVideoNoteRecorder shared];
	NSTimeInterval seconds = recorder.duration;
	if (!self.atLimit && seconds >= kNoteLimitSeconds)
		[self reachLimit];
	[self.bar showSeconds:self.atLimit ? kNoteLimitShown : seconds
				   paused:recorder.paused || !self.ready];
	// Once per second of recording is enough for the log: when the clock
	// refuses to walk on the device, this is where the line stops.
	if (!self.loggedSecond || (NSInteger)seconds != self.loggedSecond - 1){
		self.loggedSecond = (NSInteger)seconds + 1;
		NSLog(@"TGVideoNote: clock %.1f s (recording=%d paused=%d)",
				seconds, recorder.recording, recorder.paused);
	}
}

/// The note is as long as it may be. It stays on screen, stopped, for the person
/// to send or throw away, and pause has nothing left to resume.
- (void)reachLimit {
	self.atLimit = YES;
	[[TGVideoNoteRecorder shared] pause];
	[self freezeRingAt:kNoteLimitSeconds];
	self.bar.pauseButton.enabled = NO;
	self.bar.pauseButton.alpha = TGAlphaDisabled;
	self.flipButton.enabled = NO;
	self.flipButton.alpha = TGAlphaDisabled;
}

#pragma mark - controls

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
	if (!self.ready || self.atLimit)
		return;
	if (recorder.paused){
		[recorder resume];
		if (recorder.paused)
			return;   // the last segment is still closing; the tap did nothing
		[self.bar.pauseButton setImage:[TGIcons pause] forState:UIControlStateNormal];
		[self startRingFrom:recorder.duration];
	} else {
		[recorder pause];
		[self.bar.pauseButton setImage:[TGIcons play] forState:UIControlStateNormal];
		[self freezeRingAt:recorder.duration];
	}
}

/// The screen as the lamp: everything around the circle turns white and the
/// backlight goes to full, which is what lights a face on a phone with no light
/// on its front. The circle itself stays clear, the bar stays readable.
- (void)flashToggled {
	self.lampOn = !self.lampOn;
	UIScreen *screen = [UIScreen mainScreen];
	if (self.lampOn){
		if (!self.lampCover.image)
			self.lampCover.image = [self circleCoverForBackdrop:nil];
		self.brightnessBefore = screen.brightness;
		screen.brightness = 1;
	} else {
		[self restoreBrightness];
	}
	CGFloat alpha = self.lampOn ? TGAlphaOpaque : TGAlphaTransparent;
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.lampBackdrop.alpha = alpha;
		self.lampCover.alpha = alpha;
	}];
	[self showLampButtonOn:self.lampOn];
}

- (void)restoreBrightness {
	if (self.brightnessBefore > 0)
		[UIScreen mainScreen].brightness = self.brightnessBefore;
	self.brightnessBefore = 0;
}

/// Drawn in its colour rather than tinted: iOS 6 ignores a tint on a custom
/// button's image.
- (void)showLampButtonOn:(BOOL)on {
	TGTheme *theme = [TGTheme shared];
	[TGRecordBar paintDisc:self.flashButton colour:on ? [theme accentColour] : [theme inputBarColour]];
	[self.flashButton setImage:[TGIcons glyphNamed:@"flash"
											colour:on ? [theme onAccentColour] : [theme primaryTextColour]
											  side:TGMetricMenuGlyph]
					  forState:UIControlStateNormal];
}

- (void)flipTapped {
	if (!self.ready || self.atLimit)
		return;
	// The picture dips to black while the lens changes, so the jump does not
	// read as a glitch, and the spinner covers the half second it takes.
	[self.spinner startAnimating];
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.previewHost.alpha = TGAlphaTransparent;
	}];
	__weak typeof(self) weakSelf = self;
	[[TGVideoNoteRecorder shared] flipCameraWithCompletion:^{
		TGVideoNoteViewController *me = weakSelf;
		[me.spinner stopAnimating];
		[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
			me.previewHost.alpha = TGAlphaOpaque;
		}];
	}];
}

- (void)sendTapped {
	if (self.sending || !self.ready)
		return;
	self.sending = YES;
	BOOL once = self.onceOn;
	int64_t chatId = self.chatId;
	int64_t threadId = self.threadId;
	// The export takes most of the note's length on the A4. The chat comes back
	// at once with a line saying what is happening; nothing waits on the camera.
	UIView *pending = [self pendingPlateOn:self.view.superview];
	[[TGVideoNoteRecorder shared] stopWithCompletion:^(NSString *path, NSTimeInterval seconds){
		[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
			pending.alpha = TGAlphaTransparent;
		} completion:^(BOOL finished){
			[pending removeFromSuperview];
		}];
		if (path && seconds >= 0.5)
			[[TGClient shared] sendVideoNoteAtPath:path
										  duration:MIN(kNoteLimitShown, (NSInteger)ceil(seconds))
											length:[TGVideoNoteRecorder shared].noteSide
											toChat:chatId
											thread:threadId
										  viewOnce:once];
	}];
	[self dismiss];
}

- (UIView *)pendingPlateOn:(UIView *)host {
	UIView *plate = [[UIView alloc] initWithFrame:CGRectMake(
			TGCenteredOrigin(host.bounds.size.width, kPendingWidth), kPendingTop,
			kPendingWidth, kPendingHeight)];
	plate.backgroundColor = [[TGTheme shared] mediaOverlayColour];
	plate.layer.cornerRadius = TGHalf(kPendingHeight);
	plate.userInteractionEnabled = NO;
	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	spinner.center = CGPointMake(TGHalf(kPendingHeight), TGHalf(kPendingHeight));
	[spinner startAnimating];
	[plate addSubview:spinner];
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kPendingHeight, 0,
			kPendingWidth - kPendingHeight, kPendingHeight)];
	label.text = @"Preparing video note…";
	label.font = TGFontCaption();
	label.textColor = [[TGTheme shared] onMediaColour];
	label.backgroundColor = [UIColor clearColor];
	[plate addSubview:label];
	plate.alpha = TGAlphaTransparent;
	[host addSubview:plate];
	[UIView animateWithDuration:TGAnimationDurationNormal animations:^{
		plate.alpha = TGAlphaOpaque;
	}];
	return plate;
}

- (void)cancelTapped {
	[[TGVideoNoteRecorder shared] cancel];
	[self dismiss];
}

@end
