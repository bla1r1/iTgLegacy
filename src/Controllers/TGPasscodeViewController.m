//
// TGPasscodeViewController.m - Passcode entry and setup controller.
//
#import "TGPasscodeViewController.h"
#import "TGPasscode.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

static UIWindow *s_lockWindow = nil;

static const CGFloat kDotSide = TGMetricPollDotSide;
static const CGFloat kDotGap = 24.0f;
static const CGFloat kTopOffset = 80.0f;
static const CGFloat kTitleHeight = 28.0f;
static const CGFloat kSubtitleTop = 32.0f;
static const CGFloat kSubtitleHeight = 20.0f;
static const CGFloat kDotsTop = 74.0f;
static const CGFloat kBorderWidth = 1.5f;

@interface TGPasscodeViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *dotsContainer;
@property (nonatomic, strong) NSMutableArray *dots;
@property (nonatomic, strong) UITextField *hiddenInput;

@property (nonatomic, assign) NSInteger step; // 0, 1, 2 depending on mode
@property (nonatomic, copy) NSString *firstEntry;
@property (nonatomic, copy) NSString *pendingPasscode;

@end

@implementation TGPasscodeViewController

+ (void)presentUnlockIfLocked {
	if (![TGPasscode isLocked]) return;
	if (s_lockWindow && !s_lockWindow.hidden) return;

	UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	window.windowLevel = UIWindowLevelAlert + 1;
	TGPasscodeViewController *vc = [[TGPasscodeViewController alloc] init];
	vc.mode = TGPasscodeModeUnlock;
	vc.onSuccess = ^{
		[TGPasscode setLocked:NO];
		s_lockWindow.hidden = YES;
		s_lockWindow.rootViewController = nil;
		s_lockWindow = nil;
		[[UIApplication sharedApplication].keyWindow makeKeyAndVisible];
	};
	window.rootViewController = vc;
	[window makeKeyAndVisible];
	s_lockWindow = window;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
	self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
	if (self) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(applyTheme)
													 name:TGThemeChangedNotification
												   object:nil];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.view.backgroundColor = [theme listBackgroundColour];
	self.titleLabel.textColor = [theme primaryTextColour];
	self.subtitleLabel.textColor = [theme secondaryTextColour];
	for (UIView *dot in self.dots) {
		dot.layer.borderColor = [theme secondaryTextColour].CGColor;
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	if (self.mode != TGPasscodeModeUnlock && self.navigationController) {
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
				initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
									 target:self
									 action:@selector(cancelTapped)];
	}

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = TGFontTitle();
	self.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.titleLabel];

	self.subtitleLabel = [[UILabel alloc] init];
	self.subtitleLabel.font = TGFontCaption();
	self.subtitleLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
	self.subtitleLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.subtitleLabel];

	self.dotsContainer = [[UIView alloc] init];
	self.dotsContainer.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.dotsContainer];

	self.dots = [NSMutableArray arrayWithCapacity:4];
	for (NSUInteger i = 0; i < 4; i++) {
		UIView *dot = [[UIView alloc] init];
		dot.layer.cornerRadius = TGHalf(kDotSide);
		dot.layer.borderWidth = kBorderWidth;
		dot.layer.borderColor = [[TGTheme shared] secondaryTextColour].CGColor;
		dot.backgroundColor = [UIColor clearColor];
		[self.dotsContainer addSubview:dot];
		[self.dots addObject:dot];
	}

	self.hiddenInput = [[UITextField alloc] initWithFrame:CGRectZero];
	self.hiddenInput.keyboardType = UIKeyboardTypeNumberPad;
	self.hiddenInput.delegate = self;
	[self.hiddenInput addTarget:self action:@selector(textDidChange:) forControlEvents:UIControlEventEditingChanged];
	[self.view addSubview:self.hiddenInput];

	[self updateStepTitle];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.hiddenInput becomeFirstResponder];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat w = self.view.bounds.size.width;
	CGFloat top = kTopOffset;
	CGFloat labelWidth = w - (TGMetricPadLarge + TGMetricPadLarge);
	self.titleLabel.frame = CGRectMake(TGMetricPadLarge, top, labelWidth, kTitleHeight);
	self.subtitleLabel.frame = CGRectMake(TGMetricPadLarge, top + kSubtitleTop, labelWidth, kSubtitleHeight);

	CGFloat containerW = 4 * kDotSide + 3 * kDotGap;
	self.dotsContainer.frame = CGRectMake(TGCenteredOrigin(w, containerW), top + kDotsTop, containerW, kDotSide);

	for (NSUInteger i = 0; i < 4; i++) {
		UIView *dot = self.dots[i];
		dot.frame = CGRectMake(i * (kDotSide + kDotGap), TGMetricZero, kDotSide, kDotSide);
	}
}

- (void)cancelTapped {
	[self.hiddenInput resignFirstResponder];
	if (self.onCancel) self.onCancel();
	if (self.navigationController) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

- (void)updateStepTitle {
	self.subtitleLabel.text = @"";
	switch (self.mode) {
		case TGPasscodeModeUnlock:
			self.titleLabel.text = @"Enter Passcode";
			break;
		case TGPasscodeModeTurnOff:
			self.titleLabel.text = @"Enter Passcode";
			break;
		case TGPasscodeModeSetup:
			if (self.step == 0) {
				self.titleLabel.text = @"Enter a Passcode";
			} else {
				self.titleLabel.text = @"Re-enter your Passcode";
			}
			break;
		case TGPasscodeModeChange:
			if (self.step == 0) {
				self.titleLabel.text = @"Enter Old Passcode";
			} else if (self.step == 1) {
				self.titleLabel.text = @"Enter New Passcode";
			} else {
				self.titleLabel.text = @"Re-enter New Passcode";
			}
			break;
	}
}

- (void)updateDots:(NSUInteger)count {
	TGTheme *theme = [TGTheme shared];
	for (NSUInteger i = 0; i < 4; i++) {
		UIView *dot = self.dots[i];
		if (i < count) {
			dot.backgroundColor = [theme accentColour];
			dot.layer.borderColor = [theme accentColour].CGColor;
		} else {
			dot.backgroundColor = [UIColor clearColor];
			dot.layer.borderColor = [theme secondaryTextColour].CGColor;
		}
	}
}

- (void)shakeDots {
	AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
	CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
	shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
	shake.duration = 0.4;
	shake.values = @[@(-16), @(16), @(-12), @(12), @(-6), @(6), @(0)];
	[self.dotsContainer.layer addAnimation:shake forKey:@"shake"];
	self.hiddenInput.text = @"";
	[self updateDots:0];
}

- (void)textDidChange:(UITextField *)field {
	NSString *text = field.text ?: @"";
	if (text.length > 4) {
		text = [text substringToIndex:4];
		field.text = text;
	}
	[self updateDots:text.length];
	if (text.length == 4) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self processPin:text];
		});
	}
}

- (void)processPin:(NSString *)pin {
	switch (self.mode) {
		case TGPasscodeModeUnlock: {
			if ([TGPasscode verifyPasscode:pin]) {
				[self.hiddenInput resignFirstResponder];
				if (self.onSuccess) self.onSuccess();
			} else {
				[self shakeDots];
				self.subtitleLabel.textColor = [[TGTheme shared] destructiveColour];
				self.subtitleLabel.text = @"Incorrect passcode";
			}
			break;
		}
		case TGPasscodeModeTurnOff: {
			if ([TGPasscode verifyPasscode:pin]) {
				[TGPasscode clearPasscode];
				[self.hiddenInput resignFirstResponder];
				if (self.onSuccess) self.onSuccess();
				if (self.navigationController) [self.navigationController popViewControllerAnimated:YES];
			} else {
				[self shakeDots];
				self.subtitleLabel.textColor = [[TGTheme shared] destructiveColour];
				self.subtitleLabel.text = @"Incorrect passcode";
			}
			break;
		}
		case TGPasscodeModeSetup: {
			if (self.step == 0) {
				self.firstEntry = pin;
				self.step = 1;
				self.hiddenInput.text = @"";
				[self updateDots:0];
				[self updateStepTitle];
			} else {
				if ([pin isEqualToString:self.firstEntry]) {
					[TGPasscode setPasscode:pin];
					[self.hiddenInput resignFirstResponder];
					if (self.onSuccess) self.onSuccess();
					if (self.navigationController) [self.navigationController popViewControllerAnimated:YES];
				} else {
					[self shakeDots];
					self.subtitleLabel.textColor = [[TGTheme shared] destructiveColour];
					self.subtitleLabel.text = @"Passcodes didn't match. Try again.";
					self.step = 0;
					self.firstEntry = nil;
					[self updateStepTitle];
				}
			}
			break;
		}
		case TGPasscodeModeChange: {
			if (self.step == 0) {
				if ([TGPasscode verifyPasscode:pin]) {
					self.step = 1;
					self.hiddenInput.text = @"";
					[self updateDots:0];
					[self updateStepTitle];
				} else {
					[self shakeDots];
					self.subtitleLabel.textColor = [[TGTheme shared] destructiveColour];
					self.subtitleLabel.text = @"Incorrect old passcode";
				}
			} else if (self.step == 1) {
				self.pendingPasscode = pin;
				self.step = 2;
				self.hiddenInput.text = @"";
				[self updateDots:0];
				[self updateStepTitle];
			} else {
				if ([pin isEqualToString:self.pendingPasscode]) {
					[TGPasscode setPasscode:pin];
					[self.hiddenInput resignFirstResponder];
					if (self.onSuccess) self.onSuccess();
					if (self.navigationController) [self.navigationController popViewControllerAnimated:YES];
				} else {
					[self shakeDots];
					self.subtitleLabel.textColor = [[TGTheme shared] destructiveColour];
					self.subtitleLabel.text = @"Passcodes didn't match. Try again.";
					self.step = 1;
					self.pendingPasscode = nil;
					[self updateStepTitle];
				}
			}
			break;
		}
	}
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	NSString *newStr = [textField.text stringByReplacingCharactersInRange:range withString:string];
	return newStr.length <= 4;
}

@end
