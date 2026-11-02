#import "TGQRViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// The four corner brackets Telegram draws around the aiming window. A full
/// border rectangle reads as a frame; the broken one reads as a target.
@interface TGQRFinderView : UIView
@end

@implementation TGQRFinderView

- (void)drawRect:(CGRect)rect {
	CGFloat arm = TGMetricPadLarge;
	CGFloat width = TGMetricBorderThick;
	CGRect b = self.bounds;
	UIBezierPath *path = [UIBezierPath bezierPath];
	[path moveToPoint:CGPointMake(0, arm)];
	[path addLineToPoint:CGPointMake(0, 0)];
	[path addLineToPoint:CGPointMake(arm, 0)];
	[path moveToPoint:CGPointMake(CGRectGetMaxX(b) - arm, 0)];
	[path addLineToPoint:CGPointMake(CGRectGetMaxX(b), 0)];
	[path addLineToPoint:CGPointMake(CGRectGetMaxX(b), arm)];
	[path moveToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b) - arm)];
	[path addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
	[path addLineToPoint:CGPointMake(CGRectGetMaxX(b) - arm, CGRectGetMaxY(b))];
	[path moveToPoint:CGPointMake(arm, CGRectGetMaxY(b))];
	[path addLineToPoint:CGPointMake(0, CGRectGetMaxY(b))];
	[path addLineToPoint:CGPointMake(0, CGRectGetMaxY(b) - arm)];
	path.lineWidth = width;
	path.lineCapStyle = kCGLineCapRound;
	[[[TGTheme shared] onMediaColour] setStroke];
	[path stroke];
}

@end

@interface TGQRViewController () <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice *camera;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, strong) UIView *wash;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) TGQRFinderView *outline;
@property (nonatomic, strong) UIButton *manualButton;
@property (nonatomic, strong) UILabel *failureLabel;
@property (nonatomic, strong) UIBarButtonItem *torchItem;
@property (nonatomic, assign) BOOL handled;
@property (nonatomic, assign) BOOL torchOn;
@end

/// The hint under the viewfinder keeps further in from the sides than the
/// table gutter, so it reads as a caption to the window above it.
static const CGFloat kQRTextInset = 24.0f;

@implementation TGQRViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Scan QR Code";
	self.view.backgroundColor = [[TGTheme shared] mediaViewerBackdropColour];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.torchItem = [[UIBarButtonItem alloc] initWithTitle:@"Light"
			style:UIBarButtonItemStylePlain target:self action:@selector(toggleTorch)];
	self.navigationItem.rightBarButtonItem = self.torchItem;

	[self startCamera];
	[self buildFrame];
}

- (void)startCamera {
	AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	self.camera = camera;
	if (!camera) {
		[self showFailure:@"This device has no camera to scan with."];
		return;
	}
	if ([AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)]) {
		AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
		if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
			[self showFailure:@"Camera access is off for LegacyTG. Allow it in Settings, or enter a link below."];
			return;
		}
	}
	NSError *error = nil;
	AVCaptureDeviceInput *input = camera
			? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
	if (!input){
		[self showFailure:@"This device has no camera to scan with."];
		return;
	}

	self.session = [[AVCaptureSession alloc] init];
	[self.session addInput:input];

	AVCaptureMetadataOutput *codes = [[AVCaptureMetadataOutput alloc] init];
	[self.session addOutput:codes];
	// The available types are only populated once the output has a session, so
	// this order matters: asking earlier says QR is not supported.
	if (![codes.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]){
		[self showFailure:@"This device cannot recognise QR codes."];
		self.session = nil;
		return;
	}
	[codes setMetadataObjectTypes:@[AVMetadataObjectTypeQRCode]];
	[codes setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];

	self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
	self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	self.preview.frame = self.view.bounds;
	[self.view.layer addSublayer:self.preview];

	[self.session startRunning];
}

/// A window in a dark wash, which is what tells you where to aim. Called
/// again on every layout pass: the wash, its cutout, the outline and the
/// hint all follow the present bounds, so a rotated camera keeps aiming at
/// a centred window.
- (void)buildFrame {
	CGRect b = self.view.bounds;
	CGFloat side = MIN(b.size.width, b.size.height) * TGMetricQRViewfinderRatio;
	CGRect window = CGRectMake(TGCenteredOrigin(b.size.width, side),
							   TGCenteredOrigin(b.size.height, side) - TGMetricPadWide,
							   side, side);

	if (!self.wash) {
		self.wash = [[UIView alloc] initWithFrame:b];
		self.wash.backgroundColor = [[TGTheme shared] scrimColour];
		self.wash.userInteractionEnabled = NO;

		// The hole is cut with an even-odd mask rather than four strips, so
		// the edges stay exact when the frame moves.
		self.maskLayer = [CAShapeLayer layer];
		self.maskLayer.fillRule = kCAFillRuleEvenOdd;
		self.wash.layer.mask = self.maskLayer;
		[self.view addSubview:self.wash];

		self.outline = [[TGQRFinderView alloc] initWithFrame:window];
		self.outline.backgroundColor = [UIColor clearColor];
		self.outline.userInteractionEnabled = NO;
		[self.view addSubview:self.outline];

		self.hint = [[UILabel alloc] initWithFrame:CGRectMake(
				TGMetricPadWide, CGRectGetMaxY(window) + TGMetricPadWide, b.size.width - TGDoubled(TGMetricPadWide), TGDoubled(TGMetricPadWide))];
		self.hint.text = @"Point the camera at a QR code";
		self.hint.numberOfLines = 2;
		self.hint.textAlignment = NSTextAlignmentCenter;
		self.hint.font = TGFontBody();
		self.hint.textColor = [[TGTheme shared] onMediaColour];
		self.hint.backgroundColor = [UIColor clearColor];
		[self.view addSubview:self.hint];

		self.manualButton = [UIButton buttonWithType:UIButtonTypeCustom];
		self.manualButton.frame = CGRectMake(
				TGCenteredOrigin(b.size.width, TGMetricQRManualWidth),
				CGRectGetMaxY(self.hint.frame) + TGMetricPad,
				TGMetricQRManualWidth, TGMetricRow);
		[self.manualButton setTitle:@"Enter a Link" forState:UIControlStateNormal];
		[self.manualButton setTitleColor:[[TGTheme shared] onMediaColour] forState:UIControlStateNormal];
		self.manualButton.titleLabel.font = TGFontBody();
		self.manualButton.layer.borderColor = [[TGTheme shared] onMediaColour].CGColor;
		self.manualButton.layer.borderWidth = TGMetricHairline;
		self.manualButton.layer.cornerRadius = TGMetricCornerControl;
		[self.manualButton addTarget:self action:@selector(manualLinkTapped)
					forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:self.manualButton];
	}

	self.wash.frame = b;
	UIBezierPath *path = [UIBezierPath bezierPathWithRect:b];
	[path appendPath:[UIBezierPath bezierPathWithRoundedRect:window cornerRadius:TGMetricCornerControl]];
	self.maskLayer.path = path.CGPath;
	self.outline.frame = window;
	self.hint.frame = CGRectMake(
			TGMetricPadWide, CGRectGetMaxY(window) + TGMetricPadWide,
			b.size.width - TGDoubled(TGMetricPadWide), TGDoubled(TGMetricPadWide));
	self.manualButton.frame = CGRectMake(
			TGCenteredOrigin(b.size.width, TGMetricQRManualWidth),
			CGRectGetMaxY(self.hint.frame) + TGMetricPad,
			TGMetricQRManualWidth, TGMetricRow);
	if (self.failureLabel)
		[self.view bringSubviewToFront:self.failureLabel];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (self.preview)
		self.preview.frame = self.view.bounds;
	[self buildFrame];
}

- (void)showFailure:(NSString *)message {
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectInset(self.view.bounds, kQRTextInset, 0)];
	label.text = message;
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] onMediaColour];
	label.backgroundColor = [UIColor clearColor];
	self.failureLabel = label;
	[self.view addSubview:label];
	[self.view bringSubviewToFront:label];
	if (self.manualButton)
		[self.view bringSubviewToFront:self.manualButton];
	self.torchItem.enabled = NO;
}

- (void)toggleTorch {
	if (!self.camera || ![self.camera hasTorch])
		return;
	NSError *error = nil;
	if (![self.camera lockForConfiguration:&error]) {
		[TGAlertSheet showMessage:@"This camera will not change its light."
							  title:@"Light" inView:self.view];
		return;
	}
	self.torchOn = !self.torchOn;
	[self.camera setTorchMode:self.torchOn ? AVCaptureTorchModeOn : AVCaptureTorchModeOff];
	[self.camera unlockForConfiguration];
	self.torchItem.title = self.torchOn ? @"Light On" : @"Light";
}

/// A QR the camera cannot see, or a phone whose camera is broken, still has
/// the link the code stands for: the other direction Telegram offers.
- (void)manualLinkTapped {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Enter a Link"
					message:@"Paste a t.me address or the link a QR code stands for."
				placeholder:@"t.me/name"
					   text:nil
					 action:@"Open"
					 inView:self.view
				   onSubmit:^(NSString *link){
		TGQRViewController *me = weakSelf;
		if (!me)
			return;
		NSString *trimmed = [link stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!trimmed.length)
			return;
		[me actOn:trimmed];
	}];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.session stopRunning];
	if (self.torchOn && self.camera) {
		NSError *error = nil;
		if ([self.camera lockForConfiguration:&error]) {
			[self.camera setTorchMode:AVCaptureTorchModeOff];
			[self.camera unlockForConfiguration];
		}
		self.torchOn = NO;
	}
}

#pragma mark - reading

- (void)captureOutput:(AVCaptureOutput *)output
		didOutputMetadataObjects:(NSArray *)objects
				  fromConnection:(AVCaptureConnection *)connection
{
	if (self.handled)
		return;
	for (AVMetadataMachineReadableCodeObject *code in objects){
		if (![code.type isEqualToString:AVMetadataObjectTypeQRCode] || !code.stringValue.length)
			continue;
		self.handled = YES;
		[self.session stopRunning];
		NSLog(@"qr: %@", code.stringValue);
		[self actOn:code.stringValue];
		return;
	}
}

/// t.me/name and tg://resolve?domain=name both mean "open this chat".
- (NSString *)usernameIn:(NSString *)text {
	NSRange marker = [text rangeOfString:@"t.me/"];
	if (marker.location != NSNotFound){
		NSString *rest = [text substringFromIndex:NSMaxRange(marker)];
		NSRange stop = [rest rangeOfCharacterFromSet:
				[NSCharacterSet characterSetWithCharactersInString:@"/?#"]];
		return stop.location == NSNotFound ? rest : [rest substringToIndex:stop.location];
	}
	marker = [text rangeOfString:@"domain="];
	if (marker.location != NSNotFound)
		return [text substringFromIndex:NSMaxRange(marker)];
	return nil;
}

- (void)actOn:(NSString *)text {
	NSString *username = [self usernameIn:text];
	if (!username.length){
		self.hint.text = text;
		[TGAlertSheet showMessage:text title:@"QR code" inView:self.view];
		self.handled = NO;
		[self.session startRunning];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatWithUsername:username completion:^(int64_t chatId,
															 NSString *title){
		TGQRViewController *me = weakSelf;
		if (!me)
			return;
		if (!chatId){
			me.hint.text = [NSString stringWithFormat:@"No such account: @%@", username];
			me.handled = NO;
			[me.session startRunning];
			return;
		}
		TGChatViewController *chat = [[TGChatViewController alloc] init];
		chat.chatId = chatId;
		chat.chatTitle = title ?: username;
		chat.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:chat animated:YES];
	}];
}

@end

// vim:ft=objc
