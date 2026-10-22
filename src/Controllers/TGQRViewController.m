#import "TGQRViewController.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface TGQRViewController () <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UILabel *hint;
@property (nonatomic, assign) BOOL handled;
@end

@implementation TGQRViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Scan QR Code";
	self.view.backgroundColor = [UIColor blackColor];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[self startCamera];
	[self buildFrame];
}

- (void)startCamera {
	AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
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

/// A window in a dark wash, which is what tells you where to aim.
- (void)buildFrame {
	CGRect b = self.view.bounds;
	CGFloat side = MIN(b.size.width, b.size.height) * 0.66f;
	CGRect window = CGRectMake((b.size.width - side) / 2,
							   (b.size.height - side) / 2 - 20, side, side);

	UIView *wash = [[UIView alloc] initWithFrame:b];
	wash.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
	wash.userInteractionEnabled = NO;

	// The hole is cut with an even-odd mask rather than four strips, so the
	// edges stay exact when the frame moves.
	CAShapeLayer *mask = [CAShapeLayer layer];
	UIBezierPath *path = [UIBezierPath bezierPathWithRect:b];
	[path appendPath:[UIBezierPath bezierPathWithRoundedRect:window cornerRadius:8]];
	mask.path = path.CGPath;
	mask.fillRule = kCAFillRuleEvenOdd;
	wash.layer.mask = mask;
	[self.view addSubview:wash];

	UIView *outline = [[UIView alloc] initWithFrame:window];
	outline.layer.borderColor = [UIColor whiteColor].CGColor;
	outline.layer.borderWidth = 2;
	outline.layer.cornerRadius = 8;
	outline.userInteractionEnabled = NO;
	[self.view addSubview:outline];

	self.hint = [[UILabel alloc] initWithFrame:CGRectMake(
			20, CGRectGetMaxY(window) + 20, b.size.width - 40, 40)];
	self.hint.text = @"Point the camera at a QR code";
	self.hint.numberOfLines = 2;
	self.hint.textAlignment = NSTextAlignmentCenter;
	self.hint.font = [UIFont systemFontOfSize:15];
	self.hint.textColor = [UIColor whiteColor];
	self.hint.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.hint];
}

- (void)showFailure:(NSString *)message {
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectInset(self.view.bounds, 24, 0)];
	label.text = message;
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [UIColor whiteColor];
	label.backgroundColor = [UIColor clearColor];
	[self.view addSubview:label];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.session stopRunning];
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
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"QR code"
				message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
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
