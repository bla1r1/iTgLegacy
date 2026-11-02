#import "TGStoryCameraViewController.h"
#import "TGStoryComposerViewController.h"
#import "TGNavController.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import "TGAlertSheet.h"
#import "TGDevice.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>

/// The shutter: a ring around a disc, drawn once. 76 pt is the thumb-sized
/// target the official camera uses on a 320 pt screen.
static const CGFloat kShutterSide = 76.0f;
static const CGFloat kShutterRingWidth = 4.0f;
static const CGFloat kShutterDisc = 58.0f;
static const CGFloat kShutterBottom = 24.0f;
/// Every glyph button is a 44 pt target around a 26 pt picture.
static const CGFloat kEdgeButton = 44.0f;
static const CGFloat kEdgeGlyph = 26.0f;
static const CGFloat kNextWidth = 72.0f;
static const CGFloat kDurationWidth = 56.0f;
/// Telegram's caption limit for an account without Premium.
static const NSUInteger kCaptionLimit = 1024;
/// A video's first frame is often black; half a second in is not.
static const double kVideoStillSeconds = 0.5;

#pragma mark - small helpers

void TGStoryFlowSetStatusBarHidden(BOOL hidden) {
	// iOS 7 and later take it from prefersStatusBarHidden, and with that on the
	// application call is ignored with a warning.
	if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0f)
		return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	[[UIApplication sharedApplication] setStatusBarHidden:hidden
											withAnimation:UIStatusBarAnimationNone];
#pragma clang diagnostic pop
}

/// Read by key so it builds on an SDK older than 11 and answers zero on an OS
/// older than 11; a notch or a home bar is where the controls must not go.
static UIEdgeInsets TGStorySafeInsets(UIView *view) {
	if (![view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")])
		return UIEdgeInsetsZero;
	return [[view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue];
}

/// The picture shown on screen never needs more pixels than the screen has. An
/// 8 MP photo drawn as it is costs 32 MB of bitmap on a 512 MB phone.
static UIImage *TGStoryFitted(UIImage *image, CGSize pixels) {
	if (image.size.width <= 0 || image.size.height <= 0)
		return image;
	CGFloat ratio = MIN(pixels.width / image.size.width, pixels.height / image.size.height);
	if (ratio >= 1)
		return image;
	CGSize target = CGSizeMake(floorf(image.size.width * ratio),
							   floorf(image.size.height * ratio));
	UIGraphicsBeginImageContextWithOptions(target, YES, 1);
	[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
	UIImage *fitted = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return fitted ?: image;
}

static NSMutableDictionary *sDrawn = nil;

/// The pictures this screen draws itself, once each. Cleared when the theme
/// changes because they bake the colour in.
static UIImage *TGStoryDrawn(NSString *key, UIImage *(^make)(void)) {
	if (!sDrawn)
		sDrawn = [NSMutableDictionary dictionary];
	UIImage *image = sDrawn[key];
	if (!image){
		image = make();
		if (image)
			sDrawn[key] = image;
	}
	return image;
}

/// Two short strokes trailing back from `tip`, so a line reads as an arrow.
static void TGStoryArrowhead(CGContextRef ctx, CGPoint tip, CGFloat heading, CGFloat size) {
	CGFloat spread = 0.6f;
	CGFloat back = heading + (CGFloat)M_PI;
	CGContextMoveToPoint(ctx, tip.x + size * cosf(back - spread),
						 tip.y + size * sinf(back - spread));
	CGContextAddLineToPoint(ctx, tip.x, tip.y);
	CGContextAddLineToPoint(ctx, tip.x + size * cosf(back + spread),
							tip.y + size * sinf(back + spread));
	CGContextStrokePath(ctx);
}

static UIImage *TGStoryShutterImage(void) {
	return TGStoryDrawn(@"shutter", ^UIImage *{
		CGColorRef white = [[TGTheme shared] onMediaColour].CGColor;
		CGRect box = CGRectMake(0, 0, kShutterSide, kShutterSide);
		UIGraphicsBeginImageContextWithOptions(box.size, NO, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		CGContextSetStrokeColorWithColor(ctx, white);
		CGContextSetLineWidth(ctx, kShutterRingWidth);
		CGContextStrokeEllipseInRect(ctx,
				CGRectInset(box, TGHalf(kShutterRingWidth), TGHalf(kShutterRingWidth)));
		CGContextSetFillColorWithColor(ctx, white);
		CGFloat discOrigin = TGCenteredOrigin(kShutterSide, kShutterDisc);
		CGContextFillEllipseInRect(ctx,
				CGRectMake(discOrigin, discOrigin, kShutterDisc, kShutterDisc));
		UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		return image;
	});
}

/// Two arcs chasing each other, the usual "turn the camera round" mark.
static UIImage *TGStoryFlipGlyph(CGFloat side) {
	return TGStoryDrawn(@"flip", ^UIImage *{
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		CGContextSetStrokeColorWithColor(ctx, [[TGTheme shared] onMediaColour].CGColor);
		CGContextSetLineWidth(ctx, TGMetricStrokeIcon);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGFloat centre = TGHalf(side);
		CGFloat radius = side * 0.3f;
		CGFloat trim = 0.55f;
		NSInteger steps = 14;
		for (NSInteger arc = 0; arc < 2; arc++){
			CGFloat from = arc * (CGFloat)M_PI + trim;
			CGFloat span = (CGFloat)M_PI - TGDoubled(trim);
			CGPoint last = CGPointZero;
			CGFloat heading = 0;
			// Sampled by hand rather than CGContextAddArc: that call's sense
			// flips with the context, and the arrowhead needs the true direction.
			for (NSInteger i = 0; i <= steps; i++){
				CGFloat angle = from + span * i / steps;
				CGPoint p = CGPointMake(centre + radius * cosf(angle),
										centre + radius * sinf(angle));
				if (i == 0)
					CGContextMoveToPoint(ctx, p.x, p.y);
				else
					CGContextAddLineToPoint(ctx, p.x, p.y);
				heading = angle + (CGFloat)M_PI_2;
				last = p;
			}
			CGContextStrokePath(ctx);
			TGStoryArrowhead(ctx, last, heading, side * 0.16f);
		}
		UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		return image;
	});
}

/// A frame with a hill and a sun: the gallery.
static UIImage *TGStoryGalleryGlyph(CGFloat side) {
	return TGStoryDrawn(@"gallery", ^UIImage *{
		UIColor *colour = [[TGTheme shared] onMediaColour];
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
		CGContextSetLineWidth(ctx, TGMetricStrokeIcon);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGFloat margin = side * 0.14f;
		CGRect frame = CGRectInset(CGRectMake(0, 0, side, side), margin, margin);
		UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame
														cornerRadius:side * 0.12f];
		path.lineWidth = TGMetricStrokeIcon;
		[path stroke];
		CGContextMoveToPoint(ctx, side * 0.2f, side * 0.72f);
		CGContextAddLineToPoint(ctx, side * 0.42f, side * 0.5f);
		CGContextAddLineToPoint(ctx, side * 0.56f, side * 0.64f);
		CGContextAddLineToPoint(ctx, side * 0.66f, side * 0.54f);
		CGContextAddLineToPoint(ctx, side * 0.8f, side * 0.7f);
		CGContextStrokePath(ctx);
		CGFloat sunRadius = side * 0.06f;
		CGFloat sunX = side * 0.62f;
		CGFloat sunY = side * 0.34f;
		CGRect sun = CGRectMake(sunX - sunRadius, sunY - sunRadius,
								TGDoubled(sunRadius), TGDoubled(sunRadius));
		CGContextStrokeEllipseInRect(ctx, sun);
		UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		return image;
	});
}

/// The bolt with a stroke through it. The slash first clears a channel round
/// itself so it stays readable where it crosses the bolt.
static UIImage *TGStoryFlashOffGlyph(CGFloat side) {
	return TGStoryDrawn(@"flashOff", ^UIImage *{
		UIColor *colour = [[TGTheme shared] onMediaColour];
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		[[TGIcons glyphNamed:@"flash" colour:colour side:side]
				drawInRect:CGRectMake(0, 0, side, side)];
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetBlendMode(ctx, kCGBlendModeClear);
		CGContextSetLineWidth(ctx, TGMetricStrokeIcon * 3);
		CGContextMoveToPoint(ctx, side * 0.2f, side * 0.14f);
		CGContextAddLineToPoint(ctx, side * 0.8f, side * 0.86f);
		CGContextStrokePath(ctx);
		CGContextSetBlendMode(ctx, kCGBlendModeNormal);
		CGContextSetStrokeColorWithColor(ctx, colour.CGColor);
		CGContextSetLineWidth(ctx, TGMetricStrokeIcon);
		CGContextMoveToPoint(ctx, side * 0.2f, side * 0.14f);
		CGContextAddLineToPoint(ctx, side * 0.8f, side * 0.86f);
		CGContextStrokePath(ctx);
		UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		return image;
	});
}

static UIButton *TGStoryEdgeButton(UIImage *image, id target, SEL action) {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, kEdgeButton, kEdgeButton);
	[button setImage:image forState:UIControlStateNormal];
	[button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

#pragma mark - the flow's navigation controller

/// Asks the screen on top about the status bar (iOS 7 reads it from the nav
/// controller, which would otherwise answer for itself) and stays upright: a
/// camera that rotates under the user's thumb is not a feature.
@interface TGStoryFlowNavController : TGNavController
@end

@implementation TGStoryFlowNavController

- (UIViewController *)childViewControllerForStatusBarHidden {
	return self.topViewController;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// The edge-swipe back, on a root that has nothing under it, leaves the
	// stack stuck; the table has its own Back button.
	if ([self respondsToSelector:@selector(interactivePopGestureRecognizer)])
		self.interactivePopGestureRecognizer.enabled = NO;
}

- (BOOL)shouldAutorotate {
	return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation == UIInterfaceOrientationPortrait;
}

@end

#pragma mark - camera

@interface TGStoryCameraViewController () <UIImagePickerControllerDelegate,
		UINavigationControllerDelegate>
@property (nonatomic, strong) TGStoryComposerViewController *composer;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillOutput;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, assign) BOOL usingFront;
@property (nonatomic, assign) BOOL flashOn;
@property (nonatomic, assign) BOOL capturing;
/// No camera, or no permission for it: the gallery is all this screen offers.
@property (nonatomic, assign) BOOL noCamera;
@property (nonatomic, assign) BOOL closing;
/// Set when a picked picture is on its way to the editor, so the camera that
/// reappears for a moment under the dismissing picker does not start up.
@property (nonatomic, assign) BOOL handingOver;
@property (nonatomic, assign) NSInteger sessionToken;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIButton *shutterButton;
@property (nonatomic, strong) UIButton *galleryButton;
@property (nonatomic, strong) UIButton *flipButton;
@property (nonatomic, strong) id themeObserver;
@end

@implementation TGStoryCameraViewController

+ (UINavigationController *)flowForComposer:(TGStoryComposerViewController *)composer {
	TGStoryCameraViewController *camera = [[TGStoryCameraViewController alloc]
			initWithComposer:composer];
	TGStoryFlowNavController *nav = [[TGStoryFlowNavController alloc]
			initWithRootViewController:camera];
	nav.navigationBarHidden = YES;
	return nav;
}

- (instancetype)initWithComposer:(TGStoryComposerViewController *)composer {
	self = [super init];
	if (self)
		_composer = composer;
	return self;
}

- (void)dealloc {
	if (_themeObserver)
		[[NSNotificationCenter defaultCenter] removeObserver:_themeObserver];
}

- (BOOL)prefersStatusBarHidden {
	return YES;
}

- (BOOL)shouldAutorotate {
	return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation == UIInterfaceOrientationPortrait;
}

#pragma mark - view

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	self.view.clipsToBounds = YES;

	self.closeButton = TGStoryEdgeButton(nil, self, @selector(closeTapped));
	self.flashButton = TGStoryEdgeButton(nil, self, @selector(flashTapped));
	self.flipButton = TGStoryEdgeButton(nil, self, @selector(flipTapped));
	self.galleryButton = TGStoryEdgeButton(nil, self, @selector(galleryTapped));
	self.shutterButton = TGStoryEdgeButton(nil, self, @selector(shutterTapped));
	for (UIButton *button in @[self.closeButton, self.flashButton, self.flipButton,
							   self.galleryButton, self.shutterButton])
		[self.view addSubview:button];
	[self applyTheme];
	[self refreshControls];

	__weak typeof(self) weakSelf = self;
	self.themeObserver = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGThemeChangedNotification object:nil
			queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
		[sDrawn removeAllObjects];
		[weakSelf applyTheme];
	}];
}

- (void)applyTheme {
	UIColor *onMedia = [[TGTheme shared] onMediaColour];
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	[self.closeButton setImage:[TGIcons glyphNamed:@"close" colour:onMedia side:kEdgeGlyph]
					  forState:UIControlStateNormal];
	[self.galleryButton setImage:TGStoryGalleryGlyph(kEdgeGlyph) forState:UIControlStateNormal];
	[self.flipButton setImage:TGStoryFlipGlyph(kEdgeGlyph) forState:UIControlStateNormal];
	[self.shutterButton setImage:TGStoryShutterImage() forState:UIControlStateNormal];
	[self refreshFlashImage];
}

- (void)refreshFlashImage {
	UIImage *image = self.flashOn
			? [TGIcons glyphNamed:@"flash" colour:[[TGTheme shared] onMediaColour]
							 side:kEdgeGlyph]
			: TGStoryFlashOffGlyph(kEdgeGlyph);
	[self.flashButton setImage:image forState:UIControlStateNormal];
}

/// What can be shown depends on the hardware in hand: a flash only on a camera
/// that has one (the front camera of the iPod touch 4 does not), the flip only
/// when there is something to flip to.
- (void)refreshControls {
	BOOL cameraOn = !self.noCamera;
	self.shutterButton.hidden = !cameraOn;
	self.flashButton.hidden = !cameraOn || !self.input.device.hasFlash;
	self.flipButton.hidden = !cameraOn
			|| [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count < 2;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	UIEdgeInsets safe = TGStorySafeInsets(self.view);
	CGFloat top = safe.top + TGMetricPad;
	self.closeButton.frame = CGRectMake(TGMetricPad, top, kEdgeButton, kEdgeButton);
	self.flashButton.frame = CGRectMake(bounds.size.width - TGMetricPad - kEdgeButton,
										top, kEdgeButton, kEdgeButton);
	CGFloat shutterY = bounds.size.height - safe.bottom - kShutterBottom - kShutterSide;
	self.shutterButton.frame = CGRectMake(TGCenteredOrigin(bounds.size.width, kShutterSide),
										  shutterY, kShutterSide, kShutterSide);
	CGFloat sideY = shutterY + TGCenteredOrigin(kShutterSide, kEdgeButton);
	self.galleryButton.frame = CGRectMake(TGMetricPadWide, sideY, kEdgeButton, kEdgeButton);
	self.flipButton.frame = CGRectMake(bounds.size.width - TGMetricPadWide - kEdgeButton,
									   sideY, kEdgeButton, kEdgeButton);
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	self.previewLayer.frame = bounds;
	[CATransaction commit];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	TGStoryFlowSetStatusBarHidden(YES);
	[self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (self.handingOver || self.closing || self.presentedViewController)
		return;
	if (self.noCamera){
		[self openGallery];
		return;
	}
	[self startSession];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	self.handingOver = NO;
	[self stopSession];
}

#pragma mark - session

- (AVCaptureDevice *)cameraFront:(BOOL)front {
	AVCaptureDevicePosition wanted = front
			? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
	for (AVCaptureDevice *candidate in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
		if (candidate.position == wanted)
			return candidate;
	return nil;
}

- (void)startSession {
	if (self.session || self.noCamera || self.closing)
		return;
	// iOS 7 and later ask the user the first time; before that, a refusal
	// shows up as an error when the input is made, below.
	if ([AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)]){
		AVAuthorizationStatus status = [AVCaptureDevice
				authorizationStatusForMediaType:AVMediaTypeVideo];
		if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted){
			[self cameraFailed];
			return;
		}
		if (status == AVAuthorizationStatusNotDetermined){
			__weak typeof(self) weakSelf = self;
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
									 completionHandler:^(BOOL granted){
				dispatch_async(dispatch_get_main_queue(), ^{
					TGStoryCameraViewController *me = weakSelf;
					if (!me)
						return;
					if (granted)
						[me startSession];
					else
						[me cameraFailed];
				});
			}];
			return;
		}
	}

	// The back camera first. A phone without one falls back to the front.
	AVCaptureDevice *device = [self cameraFront:self.usingFront];
	if (!device){
		self.usingFront = !self.usingFront;
		device = [self cameraFront:self.usingFront];
	}
	NSError *error = nil;
	AVCaptureDeviceInput *input = device
			? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	if (!input || ![session canAddInput:input]){
		NSLog(@"TGStoryCamera: no camera input: %@", error);
		[self cameraFailed];
		return;
	}
	[session addInput:input];
	// Switching the preset after the session runs restarts the pipeline and
	// blanks the preview for about a second on iOS 6, so it is picked once. The
	// vintage tier (A4, 256 to 512 MB) keeps the VGA frame for preview and
	// still alike: a 5 MP photo decoded there costs 20 MB it does not have.
	session.sessionPreset = [self presetForSession:session];

	AVCaptureStillImageOutput *still = [[AVCaptureStillImageOutput alloc] init];
	still.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
	if (![session canAddOutput:still]){
		[self cameraFailed];
		return;
	}
	[session addOutput:still];
	AVCaptureConnection *connection = [still connectionWithMediaType:AVMediaTypeVideo];
	if ([connection isVideoOrientationSupported])
		connection.videoOrientation = AVCaptureVideoOrientationPortrait;

	// No videoMirrored: it raises on iOS 6 when the connection mirrors itself.
	AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
	preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	preview.frame = self.view.bounds;
	if ([preview.connection isVideoOrientationSupported])
		preview.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
	[self.view.layer insertSublayer:preview atIndex:0];

	self.session = session;
	self.input = input;
	self.stillOutput = still;
	self.previewLayer = preview;
	[self applyFlash];
	[self refreshControls];

	// On the main thread, a turn after the screen is up. iOS 6 finishes
	// starting a session through the calling thread's run loop: from a dispatch
	// queue, which has none, startRunning returns with isRunning NO and the
	// session never comes up.
	NSInteger token = ++self.sessionToken;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		TGStoryCameraViewController *me = weakSelf;
		if (!me || me.sessionToken != token || me.session != session)
			return;
		[session startRunning];
	});
}

- (NSString *)presetForSession:(AVCaptureSession *)session {
	if ([TGDevice tier] > TGDeviceTierVintage
			&& [session canSetSessionPreset:AVCaptureSessionPresetPhoto])
		return AVCaptureSessionPresetPhoto;
	return AVCaptureSessionPreset640x480;
}

/// Stops the session and lets go of everything that holds a frame, the moment
/// this screen is covered or closed.
- (void)stopSession {
	self.sessionToken++;
	AVCaptureSession *session = self.session;
	self.session = nil;
	self.input = nil;
	self.stillOutput = nil;
	[self.previewLayer removeFromSuperlayer];
	self.previewLayer = nil;
	if (session.isRunning)
		[session stopRunning];
}

/// No camera or no access: the gallery is the only way left, so it opens
/// without waiting for a tap.
- (void)cameraFailed {
	self.noCamera = YES;
	[self stopSession];
	[self refreshControls];
	if (self.view.window && !self.presentedViewController && !self.closing)
		[self openGallery];
}

- (void)applyFlash {
	AVCaptureDevice *device = self.input.device;
	if (!device.hasFlash)
		return;
	AVCaptureFlashMode mode = self.flashOn ? AVCaptureFlashModeOn : AVCaptureFlashModeOff;
	if (![device isFlashModeSupported:mode])
		return;
	NSError *error = nil;
	if ([device lockForConfiguration:&error]){
		device.flashMode = mode;
		[device unlockForConfiguration];
	}
}

#pragma mark - actions

- (void)closeTapped {
	self.closing = YES;
	TGStoryFlowSetStatusBarHidden(NO);
	[self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)flashTapped {
	self.flashOn = !self.flashOn;
	[self refreshFlashImage];
	[self applyFlash];
}

- (void)flipTapped {
	AVCaptureSession *session = self.session;
	if (!session)
		return;
	BOOL front = !self.usingFront;
	AVCaptureDevice *device = [self cameraFront:front];
	AVCaptureDeviceInput *next = device
			? [AVCaptureDeviceInput deviceInputWithDevice:device error:nil] : nil;
	if (!next)
		return;
	AVCaptureDeviceInput *previous = self.input;
	[session beginConfiguration];
	[session removeInput:previous];
	if ([session canAddInput:next]){
		[session addInput:next];
		self.input = next;
		self.usingFront = front;
	} else {
		[session addInput:previous];
	}
	// A camera that cannot do the photo preset (the front one on most phones)
	// has to drop to VGA or the commit throws.
	session.sessionPreset = [self presetForSession:session];
	[session commitConfiguration];
	[self applyFlash];
	[self refreshControls];
}

- (void)shutterTapped {
	AVCaptureConnection *connection = [self.stillOutput connectionWithMediaType:AVMediaTypeVideo];
	if (self.capturing || !self.session.isRunning || !connection)
		return;
	self.capturing = YES;
	__weak typeof(self) weakSelf = self;
	[self.stillOutput captureStillImageAsynchronouslyFromConnection:connection
			completionHandler:^(CMSampleBufferRef buffer, NSError *error){
		// The buffer is only valid in here, so the JPEG is cut out of it first.
		NSData *jpeg = buffer && !error
				? [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:buffer] : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGStoryCameraViewController *me = weakSelf;
			if (!me)
				return;
			me.capturing = NO;
			if (me.closing)
				return;
			UIImage *image = jpeg.length ? [UIImage imageWithData:jpeg] : nil;
			if (!image){
				[TGAlertSheet showMessage:@"The camera did not give a picture. Try again."
									title:@"New Story" inView:me.view];
				return;
			}
			[me.navigationController pushViewController:
					[[TGStoryEditorViewController alloc] initWithComposer:me.composer
																	image:image]
											   animated:YES];
		});
	}];
}

- (void)galleryTapped {
	[self openGallery];
}

- (void)openGallery {
	if (self.presentedViewController)
		return;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.delegate = self;
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.mediaTypes = [UIImagePickerController
			availableMediaTypesForSourceType:picker.sourceType] ?: @[];
	picker.allowsEditing = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - the picker

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	NSString *type = info[UIImagePickerControllerMediaType];
	UIViewController *editor = nil;
	if ([type isEqualToString:(NSString *)kUTTypeMovie]){
		NSURL *url = info[UIImagePickerControllerMediaURL];
		if (url){
			double duration = 0;
			AVURLAsset *asset = [AVURLAsset assetWithURL:url];
			if (asset.duration.value > 0)
				duration = CMTimeGetSeconds(asset.duration);
			editor = [[TGStoryEditorViewController alloc] initWithComposer:self.composer
																 videoPath:url.path
																  duration:duration];
		}
	} else {
		UIImage *image = info[UIImagePickerControllerOriginalImage];
		if (image)
			editor = [[TGStoryEditorViewController alloc] initWithComposer:self.composer
																	 image:image];
	}
	if (!editor){
		[self imagePickerControllerDidCancel:picker];
		return;
	}
	self.handingOver = YES;
	__weak typeof(self) weakSelf = self;
	[picker dismissViewControllerAnimated:YES completion:^{
		[weakSelf.navigationController pushViewController:editor animated:YES];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	if (self.noCamera){
		// Nothing is left behind the picker to come back to.
		self.closing = YES;
		TGStoryFlowSetStatusBarHidden(NO);
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	[picker dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - editor

@interface TGStoryEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong) TGStoryComposerViewController *composer;
/// Held until the photo has been written for Telegram, then let go.
@property (nonatomic, strong) UIImage *original;
@property (nonatomic, copy) NSString *photoPath;
@property (nonatomic, copy) NSString *videoPath;
@property (nonatomic, assign) double duration;
@property (nonatomic, assign) BOOL preparing;
@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, strong) AVAssetImageGenerator *generator;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UITextField *captionField;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) id themeObserver;
@end

@implementation TGStoryEditorViewController

- (instancetype)initWithComposer:(TGStoryComposerViewController *)composer
						   image:(UIImage *)image {
	self = [super init];
	if (self){
		_composer = composer;
		_original = image;
	}
	return self;
}

- (instancetype)initWithComposer:(TGStoryComposerViewController *)composer
					   videoPath:(NSString *)path
						duration:(double)duration {
	self = [super init];
	if (self){
		_composer = composer;
		_videoPath = [path copy];
		_duration = duration;
	}
	return self;
}

- (void)dealloc {
	if (_themeObserver)
		[[NSNotificationCenter defaultCenter] removeObserver:_themeObserver];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)prefersStatusBarHidden {
	return YES;
}

- (BOOL)shouldAutorotate {
	return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation == UIInterfaceOrientationPortrait;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	self.view.clipsToBounds = YES;

	self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
	self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	self.imageView.contentMode = UIViewContentModeScaleAspectFit;
	[self.view addSubview:self.imageView];

	self.durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.durationLabel.font = TGFontCaption();
	self.durationLabel.textAlignment = NSTextAlignmentCenter;
	self.durationLabel.hidden = !self.videoPath || self.duration <= 0;
	int seconds = (int)(self.duration + 0.5);
	self.durationLabel.text = [NSString stringWithFormat:@"%d:%02d", seconds / 60, seconds % 60];
	[self.view addSubview:self.durationLabel];

	self.bar = [[UIView alloc] initWithFrame:CGRectZero];
	[self.view addSubview:self.bar];

	self.captionField = [[UITextField alloc] initWithFrame:CGRectZero];
	self.captionField.font = TGFontBody();
	self.captionField.borderStyle = UITextBorderStyleNone;
	self.captionField.returnKeyType = UIReturnKeyDone;
	self.captionField.clearButtonMode = UITextFieldViewModeWhileEditing;
	self.captionField.delegate = self;
	[self.bar addSubview:self.captionField];

	self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.nextButton.titleLabel.font = TGFontBodyStrong();
	self.nextButton.layer.cornerRadius = TGHalf(TGMetricButtonHeightSmall);
	[self.nextButton setTitle:@"Next" forState:UIControlStateNormal];
	[self.nextButton addTarget:self action:@selector(nextTapped)
			  forControlEvents:UIControlEventTouchUpInside];
	[self.bar addSubview:self.nextButton];

	self.backButton = TGStoryEdgeButton(nil, self, @selector(backTapped));
	[self.view addSubview:self.backButton];

	[self.view addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(backgroundTapped)]];
	[self applyTheme];

	__weak typeof(self) weakSelf = self;
	self.themeObserver = [[NSNotificationCenter defaultCenter]
			addObserverForName:TGThemeChangedNotification object:nil
			queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
		[weakSelf applyTheme];
	}];

	if (self.videoPath)
		[self loadVideoStill];
	else
		[self loadPhoto];
}

- (void)applyTheme {
	UIColor *onMedia = [[TGTheme shared] onMediaColour];
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	self.durationLabel.textColor = onMedia;
	self.durationLabel.backgroundColor = [[TGTheme shared] mediaOverlayColour];
	self.bar.backgroundColor = [[TGTheme shared] mediaOverlayColour];
	self.captionField.textColor = onMedia;
	NSDictionary *hint = @{NSForegroundColorAttributeName :
			[onMedia colorWithAlphaComponent:TGAlphaSecondary]};
	self.captionField.attributedPlaceholder = [[NSAttributedString alloc]
			initWithString:@"Add a caption..." attributes:hint];
	self.nextButton.backgroundColor = [[TGTheme shared] accentColour];
	[self.nextButton setTitleColor:[[TGTheme shared] onAccentColour]
						  forState:UIControlStateNormal];
	[self.backButton setImage:[TGIcons backChevronWithColour:onMedia]
					 forState:UIControlStateNormal];
}

/// The screen-sized copy is made off the main thread: scaling an 8 MP photo on
/// a single-core phone takes long enough to freeze the push animation.
- (void)loadPhoto {
	UIImage *original = self.original;
	CGFloat scale = [UIScreen mainScreen].scale;
	CGSize screen = [UIScreen mainScreen].bounds.size;
	CGSize pixels = CGSizeMake(screen.width * scale, screen.height * scale);
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		UIImage *fitted = TGStoryFitted(original, pixels);
		dispatch_async(dispatch_get_main_queue(), ^{
			weakSelf.imageView.image = fitted;
		});
	});
}

- (void)loadVideoStill {
	AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:self.videoPath]];
	AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
	generator.appliesPreferredTrackTransform = YES;
	CGFloat scale = [UIScreen mainScreen].scale;
	CGSize screen = [UIScreen mainScreen].bounds.size;
	generator.maximumSize = CGSizeMake(screen.width * scale, screen.height * scale);
	self.generator = generator;
	double at = self.duration > TGDoubled(kVideoStillSeconds) ? kVideoStillSeconds : 0;
	NSValue *time = [NSValue valueWithCMTime:CMTimeMakeWithSeconds(at, 600)];
	__weak typeof(self) weakSelf = self;
	[generator generateCGImagesAsynchronouslyForTimes:@[time]
			completionHandler:^(CMTime requested, CGImageRef cg, CMTime actual,
								AVAssetImageGeneratorResult result, NSError *error){
		UIImage *still = result == AVAssetImageGeneratorSucceeded && cg
				? [UIImage imageWithCGImage:cg] : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			weakSelf.imageView.image = still;
			weakSelf.generator = nil;
		});
	}];
}

#pragma mark - layout

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutBar];
	UIEdgeInsets safe = TGStorySafeInsets(self.view);
	self.backButton.frame = CGRectMake(TGMetricPad, safe.top + TGMetricPad,
									   kEdgeButton, kEdgeButton);
}

- (void)layoutBar {
	CGRect bounds = self.view.bounds;
	// The keyboard covers the home bar's inset, so it only counts without one.
	CGFloat bottom = self.keyboardHeight > 0 ? 0 : TGStorySafeInsets(self.view).bottom;
	CGFloat height = TGMetricInputBarHeight + bottom;
	CGFloat barY = bounds.size.height - self.keyboardHeight - height;
	self.bar.frame = CGRectMake(0, barY, bounds.size.width, height);
	CGFloat rowY = TGCenteredOrigin(TGMetricInputBarHeight, TGMetricButtonHeightSmall);
	self.nextButton.frame = CGRectMake(bounds.size.width - TGMetricPad - kNextWidth, rowY,
									   kNextWidth, TGMetricButtonHeightSmall);
	self.captionField.frame = CGRectMake(TGMetricPadLarge, rowY,
			bounds.size.width - TGMetricPadLarge - TGDoubled(TGMetricPad) - kNextWidth,
			TGMetricButtonHeightSmall);
	self.durationLabel.frame = CGRectMake(TGMetricPadLarge,
			barY - TGMetricPad - TGMetricLineCaption, kDurationWidth, TGMetricLineCaption);
}

#pragma mark - lifecycle

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	TGStoryFlowSetStatusBarHidden(YES);
	[self.navigationController setNavigationBarHidden:YES animated:animated];
	[self layoutBar];
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(keyboardWillChange:)
			name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[[NSNotificationCenter defaultCenter] removeObserver:self
			name:UIKeyboardWillChangeFrameNotification object:nil];
	[self.captionField resignFirstResponder];
	self.keyboardHeight = 0;
}

- (void)keyboardWillChange:(NSNotification *)note {
	CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect local = [self.view convertRect:end fromView:nil];
	self.keyboardHeight = MAX(0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(local));
	NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	NSInteger curve = [note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
	// The keyboard's own curve is what keeps the bar glued to its top edge.
	[UIView animateWithDuration:duration delay:0
						options:(UIViewAnimationOptions)(curve << 16)
							| UIViewAnimationOptionBeginFromCurrentState
					 animations:^{
		[self layoutBar];
	} completion:nil];
}

#pragma mark - actions

- (void)backTapped {
	[self.captionField resignFirstResponder];
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)backgroundTapped {
	[self.captionField resignFirstResponder];
}

- (void)nextTapped {
	if (self.preparing)
		return;
	[self.captionField resignFirstResponder];
	NSString *caption = [self.captionField.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if (self.videoPath){
		[self.composer useMediaAtPath:self.videoPath isVideo:YES
							 duration:self.duration caption:caption];
		[self.navigationController pushViewController:self.composer animated:YES];
		return;
	}
	if (self.photoPath){
		[self.composer useMediaAtPath:self.photoPath isVideo:NO duration:0 caption:caption];
		[self.navigationController pushViewController:self.composer animated:YES];
		return;
	}
	// First time on: scale and write the photo off the main thread, then let
	// the original go; coming back and pressing Next again reuses the file.
	self.preparing = YES;
	self.nextButton.enabled = NO;
	self.nextButton.alpha = TGAlphaDisabled;
	UIImage *original = self.original;
	TGStoryComposerViewController *composer = self.composer;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *path = [composer writeStoryPhoto:original];
		dispatch_async(dispatch_get_main_queue(), ^{
			TGStoryEditorViewController *me = weakSelf;
			if (!me)
				return;
			me.preparing = NO;
			me.nextButton.enabled = YES;
			me.nextButton.alpha = TGAlphaOpaque;
			if (!path){
				[TGAlertSheet showMessage:@"The picture could not be prepared. Try another."
									title:@"New Story" inView:me.view];
				return;
			}
			me.photoPath = path;
			me.original = nil;
			[composer useMediaAtPath:path isVideo:NO duration:0 caption:caption];
			[me.navigationController pushViewController:composer animated:YES];
		});
	});
}

#pragma mark - text field

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
	NSUInteger length = textField.text.length - range.length + string.length;
	return length <= kCaptionLimit;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return NO;
}

@end
