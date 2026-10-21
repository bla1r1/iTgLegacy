#import "TGLoginViewController.h"
#import "TGClient.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

typedef NS_ENUM(NSInteger, TGLoginStep) {
    TGLoginStepPhone,
    TGLoginStepCode,
    TGLoginStepPassword
};

@interface TGLoginViewController ()

@property (nonatomic, assign) TGLoginStep currentStep;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *inputContainer;
@property (nonatomic, strong) UITextField *phonePrefixField;
@property (nonatomic, strong) UIView *prefixSeparator;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *nextItem;
@property (nonatomic, strong) UIButton *resendButton;
@property (nonatomic, strong) UIButton *qrCodeButton;
@property (nonatomic, strong) UIButton *codeStepQrButton;
@property (nonatomic, strong) UIImageView *qrImageView;
@property (nonatomic, copy) NSString *savedPhoneNumber;
@property (nonatomic, strong) NSTimer *resendTimer;
@property (nonatomic, assign) NSInteger resendCountdown;

@end

@implementation TGLoginViewController

/* ---- skeuomorphic helpers -------------------------------------------- */

static UIColor *tgRGB(int r, int g, int b) {
    return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

/* Vertical gloss gradient, the iOS 6 era look. */
static CAGradientLayer *tgGloss(CGRect frame, UIColor *top, UIColor *bottom) {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = frame;
    g.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    return g;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Your Phone";

    self.nextItem = [[UIBarButtonItem alloc] initWithTitle:@"Next"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(actionButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.nextItem;

    /* Brushed-metal-ish bar rather than iOS 7 flat white.
     * barTintColor and NSForegroundColorAttributeName are iOS 7; on iOS 6 the
     * bar colour IS tintColor and the title key is UITextAttributeTextColor. */
    UINavigationBar *bar = self.navigationController.navigationBar;
    if ([bar respondsToSelector:@selector(setBarTintColor:)]){
        bar.tintColor = tgRGB(38, 92, 140);
        bar.barTintColor = tgRGB(64, 122, 173);
        bar.titleTextAttributes = @{ NSForegroundColorAttributeName : [UIColor whiteColor] };
    } else {
        bar.tintColor = tgRGB(64, 122, 173);
        bar.titleTextAttributes = @{ UITextAttributeTextColor : [UIColor whiteColor] };
    }

    [self setupUI];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;

    /* Paper-ish backdrop with a soft vertical shade. */
    self.view.backgroundColor = tgRGB(203, 209, 216);
    CAGradientLayer *bg = tgGloss(self.view.bounds, tgRGB(222, 226, 232), tgRGB(186, 193, 203));
    [self.view.layer insertSublayer:bg atIndex:0];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.alwaysBounceVertical = YES;
    // keyboardDismissMode is iOS 7; harmless to skip on iOS 6.
    if ([self.scrollView respondsToSelector:@selector(setKeyboardDismissMode:)])
        self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    /* Embossed title: dark text with a white highlight underneath. */
    self.headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 22, width - 40, 36)];
    self.headerLabel.text = @"Telegram";
    self.headerLabel.backgroundColor = [UIColor clearColor];
    self.headerLabel.textColor = tgRGB(52, 74, 96);
    self.headerLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.8f];
    self.headerLabel.shadowOffset = CGSizeMake(0, 1);
    self.headerLabel.font = [UIFont boldSystemFontOfSize:28];
    self.headerLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:self.headerLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 62, width - 40, 40)];
    self.subtitleLabel.text = @"Please confirm your country code\nand enter your phone number.";
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.textColor = tgRGB(90, 103, 117);
    self.subtitleLabel.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.7f];
    self.subtitleLabel.shadowOffset = CGSizeMake(0, 1);
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 2;
    [self.scrollView addSubview:self.subtitleLabel];

    /* Recessed input well: bevelled border plus an inner top shadow. */
    self.inputContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 112, width - 30, 50)];
    self.inputContainer.backgroundColor = [UIColor whiteColor];
    self.inputContainer.layer.cornerRadius = 10.0f;
    self.inputContainer.layer.borderWidth = 1.0f;
    self.inputContainer.layer.borderColor = tgRGB(140, 149, 160).CGColor;
    self.inputContainer.clipsToBounds = YES;
    [self.scrollView addSubview:self.inputContainer];

    UIView *inner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width - 30, 3)];
    inner.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.10f];
    [self.inputContainer addSubview:inner];

    /* Country code prefix - Ukraine by default. */
    self.phonePrefixField = [[UITextField alloc] initWithFrame:CGRectMake(12, 1, 62, 48)];
    self.phonePrefixField.text = @"+380";
    self.phonePrefixField.font = [UIFont boldSystemFontOfSize:17];
    self.phonePrefixField.keyboardType = UIKeyboardTypePhonePad;
    self.phonePrefixField.returnKeyType = UIReturnKeyNext;
    self.phonePrefixField.textColor = tgRGB(38, 92, 140);
    self.phonePrefixField.delegate = self;
    [self.phonePrefixField addTarget:self action:@selector(prefixFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.phonePrefixField];

    self.prefixSeparator = [[UIView alloc] initWithFrame:CGRectMake(78, 9, 1, 32)];
    self.prefixSeparator.backgroundColor = tgRGB(190, 196, 204);
    [self.inputContainer addSubview:self.prefixSeparator];

    self.inputField = [[UITextField alloc] initWithFrame:CGRectMake(90, 1, width - 132, 48)];
    self.inputField.placeholder = @"Phone number";
    self.inputField.font = [UIFont systemFontOfSize:17];
    self.inputField.textColor = tgRGB(40, 46, 54);
    self.inputField.keyboardType = UIKeyboardTypePhonePad;
    self.inputField.returnKeyType = UIReturnKeyGo;
    self.inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.inputField.delegate = self;
    [self.inputField addTarget:self action:@selector(inputFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.inputField];

    /* Glossy raised button: gradient body, dark rim, highlight on the top half. */
    self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.actionButton.frame = CGRectMake(15, 176, width - 30, 46);
    self.actionButton.layer.cornerRadius = 9.0f;
    self.actionButton.layer.borderWidth = 1.0f;
    self.actionButton.layer.borderColor = tgRGB(26, 66, 102).CGColor;
    self.actionButton.clipsToBounds = YES;
    self.actionButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.actionButton.layer.shadowOffset = CGSizeMake(0, 1);
    self.actionButton.layer.shadowOpacity = 0.35f;
    self.actionButton.layer.shadowRadius = 1.0f;

    CAGradientLayer *btn = tgGloss(CGRectMake(0, 0, width - 30, 46),
                                   tgRGB(92, 156, 210), tgRGB(38, 92, 148));
    [self.actionButton.layer insertSublayer:btn atIndex:0];

    UIView *shine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width - 30, 22)];
    shine.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
    shine.userInteractionEnabled = NO;
    [self.actionButton addSubview:shine];

    [self.actionButton setTitle:@"Next" forState:UIControlStateNormal];
    [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.actionButton setTitleColor:[UIColor colorWithWhite:1.0f alpha:0.5f] forState:UIControlStateDisabled];
    self.actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.actionButton.titleLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.4f];
    self.actionButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.actionButton];

    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.center = CGPointMake((width - 30) / 2, 23);
    self.spinner.hidesWhenStopped = YES;
    [self.actionButton addSubview:self.spinner];

    self.qrCodeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.qrCodeButton.frame = CGRectMake(15, 230, width - 30, 36);
    [self.qrCodeButton setTitle:@"Log in with QR Code" forState:UIControlStateNormal];
    [self.qrCodeButton setTitleColor:tgRGB(38, 92, 140) forState:UIControlStateNormal];
    self.qrCodeButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.qrCodeButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.qrCodeButton];

    self.scrollView.contentSize = CGSizeMake(width, 280);
    self.currentStep = TGLoginStepPhone;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.inputField becomeFirstResponder];
    });
}

- (void)inputFieldChanged:(UITextField *)sender {
    if (self.currentStep != TGLoginStepPhone) return;
    NSString *text = sender.text;
    if ([text rangeOfString:@"+"].location != NSNotFound || (text.length >= 4 && [self containsKnownCountryPrefix:text])) {
        [self processPastedPhoneNumber:text];
    }
}

- (void)prefixFieldChanged:(UITextField *)sender {
    if (self.currentStep != TGLoginStepPhone) return;
    NSString *text = sender.text;
    if (![text hasPrefix:@"+"]) {
        text = [@"+" stringByAppendingString:[text stringByReplacingOccurrencesOfString:@"+" withString:@""]];
    }
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '+' && clean.length == 0) {
            [clean appendString:@"+"];
        } else if (c >= '0' && c <= '9') {
            [clean appendFormat:@"%C", c];
        }
    }
    sender.text = clean;
}

- (BOOL)containsKnownCountryPrefix:(NSString *)digits {
    static NSSet *knownPrefixes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        knownPrefixes = [NSSet setWithObjects:
            @"380", @"375", @"370", @"371", @"372", @"373", @"374", @"376", @"377", @"378",
            @"381", @"382", @"385", @"386", @"387", @"389", @"420", @"421", @"423", @"992",
            @"993", @"994", @"995", @"996", @"998", @"351", @"352", @"353", @"354", @"355",
            @"356", @"357", @"358", @"359", @"852", @"853", @"855", @"856", @"880", @"886",
            @"960", @"961", @"962", @"963", @"964", @"965", @"966", @"967", @"968", @"971",
            @"972", @"973", @"974", @"975", @"976", @"977",
            @"20", @"27", @"30", @"31", @"32", @"33", @"34", @"36", @"39", @"40",
            @"41", @"43", @"44", @"45", @"46", @"47", @"48", @"49", @"51", @"52",
            @"53", @"54", @"55", @"56", @"57", @"58", @"60", @"61", @"62", @"63",
            @"64", @"65", @"66", @"81", @"82", @"84", @"86", @"90", @"91", @"92",
            @"93", @"94", @"95", @"98", @"1", @"7", nil];
    });

    NSString *clean = [digits stringByReplacingOccurrencesOfString:@"\\D" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, digits.length)];
    if (clean.length >= 3 && [knownPrefixes containsObject:[clean substringToIndex:3]]) return YES;
    if (clean.length >= 2 && [knownPrefixes containsObject:[clean substringToIndex:2]]) return YES;
    if (clean.length >= 1 && [knownPrefixes containsObject:[clean substringToIndex:1]]) return YES;
    return NO;
}

- (void)processPastedPhoneNumber:(NSString *)raw {
    if (!raw.length) return;

    NSMutableString *cleaned = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == '+' && cleaned.length == 0) {
            [cleaned appendString:@"+"];
        } else if (c >= '0' && c <= '9') {
            [cleaned appendFormat:@"%C", c];
        }
    }

    if ([cleaned hasPrefix:@"00"]) {
        [cleaned replaceCharactersInRange:NSMakeRange(0, 2) withString:@"+"];
    }

    if ([cleaned hasPrefix:@"0"] && ![cleaned hasPrefix:@"00"] && cleaned.length == 10) {
        // Local 10-digit number e.g. 0671234567, strip leading 0, keep country prefix
        self.inputField.text = [cleaned substringFromIndex:1];
        [self.inputField becomeFirstResponder];
        return;
    }

    NSString *digits = cleaned;
    BOOL hadPlus = [digits hasPrefix:@"+"];
    if (hadPlus) {
        digits = [digits substringFromIndex:1];
    }
    if (!digits.length) return;

    static NSSet *threeDigitCodes = nil;
    static NSSet *twoDigitCodes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        threeDigitCodes = [NSSet setWithObjects:
            @"380", @"375", @"370", @"371", @"372", @"373", @"374", @"376", @"377", @"378",
            @"381", @"382", @"385", @"386", @"387", @"389", @"420", @"421", @"423", @"992",
            @"993", @"994", @"995", @"996", @"998", @"351", @"352", @"353", @"354", @"355",
            @"356", @"357", @"358", @"359", @"852", @"853", @"855", @"856", @"880", @"886",
            @"960", @"961", @"962", @"963", @"964", @"965", @"966", @"967", @"968", @"971",
            @"972", @"973", @"974", @"975", @"976", @"977", nil];

        twoDigitCodes = [NSSet setWithObjects:
            @"20", @"27", @"30", @"31", @"32", @"33", @"34", @"36", @"39", @"40",
            @"41", @"43", @"44", @"45", @"46", @"47", @"48", @"49", @"51", @"52",
            @"53", @"54", @"55", @"56", @"57", @"58", @"60", @"61", @"62", @"63",
            @"64", @"65", @"66", @"81", @"82", @"84", @"86", @"90", @"91", @"92",
            @"93", @"94", @"95", @"98", nil];
    });

    NSString *prefix = nil;
    NSString *rest = nil;

    if (digits.length >= 3 && [threeDigitCodes containsObject:[digits substringToIndex:3]]) {
        prefix = [digits substringToIndex:3];
        rest = [digits substringFromIndex:3];
    } else if (digits.length >= 2 && [twoDigitCodes containsObject:[digits substringToIndex:2]]) {
        prefix = [digits substringToIndex:2];
        rest = [digits substringFromIndex:2];
    } else if ([digits hasPrefix:@"1"] || [digits hasPrefix:@"7"]) {
        prefix = [digits substringToIndex:1];
        rest = [digits substringFromIndex:1];
    } else if (hadPlus) {
        NSUInteger pLen = MIN((NSUInteger)3, digits.length);
        prefix = [digits substringToIndex:pLen];
        rest = [digits substringFromIndex:pLen];
    } else {
        self.inputField.text = digits;
        return;
    }

    self.phonePrefixField.text = [NSString stringWithFormat:@"+%@", prefix];
    self.inputField.text = rest;
    [self.inputField becomeFirstResponder];
}

- (void)showPhoneStep {
    [self.resendTimer invalidate];
    self.resendTimer = nil;
    [self setBusy:NO];
    self.currentStep = TGLoginStepPhone;
    self.title = @"Your Phone";
    self.headerLabel.text = @"Telegram";
    self.subtitleLabel.text = @"Please confirm your country code and enter your phone number.";

    if (self.onResetSession) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:@"Reset"
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(resetSessionTapped)];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }

    CGFloat width = self.view.bounds.size.width;
    self.inputContainer.hidden = NO;
    self.actionButton.hidden = NO;
    self.inputField.hidden = NO;
    self.qrCodeButton.hidden = NO;
    if (self.qrImageView) {
        self.qrImageView.hidden = YES;
    }
    self.phonePrefixField.hidden = NO;
    self.prefixSeparator.hidden = NO;
    self.inputField.frame = CGRectMake(90, 1, width - 132, 48);
    self.inputField.textAlignment = NSTextAlignmentLeft;
    self.inputField.font = [UIFont systemFontOfSize:17];
    self.inputField.placeholder = @"Phone number";
    self.inputField.secureTextEntry = NO;
    self.inputField.keyboardType = UIKeyboardTypePhonePad;
    self.inputField.returnKeyType = UIReturnKeyGo;
    [self.actionButton setTitle:@"Next" forState:UIControlStateNormal];
    self.nextItem.title = @"Next";

    if (self.resendButton) {
        [self.resendButton removeFromSuperview];
        self.resendButton = nil;
    }
    if (self.codeStepQrButton) {
        [self.codeStepQrButton removeFromSuperview];
        self.codeStepQrButton = nil;
    }
    self.scrollView.contentSize = CGSizeMake(width, 280);
    [self.inputField becomeFirstResponder];
}

- (void)useSingleFieldLayout {
    CGFloat width = self.view.bounds.size.width;
    self.inputContainer.hidden = NO;
    self.actionButton.hidden = NO;
    self.inputField.hidden = NO;
    self.phonePrefixField.hidden = YES;
    self.prefixSeparator.hidden = YES;
    self.qrCodeButton.hidden = YES;
    if (self.qrImageView) {
        self.qrImageView.hidden = YES;
    }
    self.inputField.frame = CGRectMake(14, 1, width - 58, 48);
    self.inputField.textAlignment = NSTextAlignmentCenter;
    self.inputField.font = [UIFont boldSystemFontOfSize:20];
    self.inputField.text = @"";
    self.inputField.returnKeyType = UIReturnKeyGo;
}

- (void)qrCodeButtonTapped {
    [self setBusy:YES];
    if (self.onRequestQRCode) {
        self.onRequestQRCode();
    }
}

- (void)showQRCodeStepWithLink:(NSString *)link {
    [self setBusy:NO];
    self.title = @"Scan QR Code";
    self.headerLabel.text = @"Scan QR Code";
    self.subtitleLabel.text = @"Open Telegram on your other device:\nSettings > Devices > Link Desktop Device";

    self.inputContainer.hidden = YES;
    self.actionButton.hidden = YES;
    self.phonePrefixField.hidden = YES;
    self.prefixSeparator.hidden = YES;
    self.inputField.hidden = YES;
    self.qrCodeButton.hidden = YES;
    if (self.resendButton) {
        [self.resendButton removeFromSuperview];
        self.resendButton = nil;
    }
    if (self.codeStepQrButton) {
        [self.codeStepQrButton removeFromSuperview];
        self.codeStepQrButton = nil;
    }
    [self.resendTimer invalidate];
    self.resendTimer = nil;
    [self.view endEditing:YES];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Cancel"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

    if (!self.qrImageView) {
        CGFloat width = self.view.bounds.size.width;
        CGFloat qrSize = MIN(width - 80, 200.0f);
        self.qrImageView = [[UIImageView alloc] initWithFrame:CGRectMake((width - qrSize) / 2, 115, qrSize, qrSize)];
        self.qrImageView.backgroundColor = [UIColor whiteColor];
        self.qrImageView.layer.cornerRadius = 8.0f;
        self.qrImageView.layer.borderWidth = 1.0f;
        self.qrImageView.layer.borderColor = tgRGB(190, 196, 204).CGColor;
        self.qrImageView.clipsToBounds = YES;
        [self.scrollView addSubview:self.qrImageView];
    }
    self.qrImageView.hidden = NO;
    self.qrImageView.image = [self generateQRCodeForString:link size:self.qrImageView.bounds.size.width];
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, 350);
}

- (UIImage *)generateQRCodeForString:(NSString *)string size:(CGFloat)size {
    if (!string.length) return nil;
    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *qrFilter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [qrFilter setValue:stringData forKey:@"inputMessage"];
    [qrFilter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *ciImage = qrFilter.outputImage;
    if (!ciImage) return nil;

    CGRect extent = CGRectIntegral(ciImage.extent);
    CGFloat scale = MIN(size / CGRectGetWidth(extent), size / CGRectGetHeight(extent));
    size_t width = (size_t)(CGRectGetWidth(extent) * scale);
    size_t height = (size_t)(CGRectGetHeight(extent) * scale);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmapRef = CGBitmapContextCreate(nil, width, height, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaNone);
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef bitmapImage = [context createCGImage:ciImage fromRect:extent];
    CGContextSetInterpolationQuality(bitmapRef, kCGInterpolationNone);
    CGContextScaleCTM(bitmapRef, scale, scale);
    CGContextDrawImage(bitmapRef, extent, bitmapImage);
    CGImageRef scaledImage = CGBitmapContextCreateImage(bitmapRef);
    CGContextRelease(bitmapRef);
    CGImageRelease(bitmapImage);
    CGColorSpaceRelease(cs);
    UIImage *img = [UIImage imageWithCGImage:scaledImage];
    CGImageRelease(scaledImage);
    return img;
}

- (void)setBusy:(BOOL)busy {
    self.actionButton.enabled = !busy;
    self.nextItem.enabled = !busy;
    if (busy) {
        self.actionButton.titleLabel.alpha = 0.0f;
        [self.spinner startAnimating];
    } else {
        self.actionButton.titleLabel.alpha = 1.0f;
        [self.spinner stopAnimating];
    }
}

- (void)actionButtonTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return;
    }

    [self setBusy:YES];

    if (self.currentStep == TGLoginStepPhone) {
        NSString *prefix = [self.phonePrefixField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![prefix hasPrefix:@"+"]) {
            prefix = [@"+" stringByAppendingString:prefix];
        }
        NSString *prefixDigits = [prefix stringByReplacingOccurrencesOfString:@"\\D" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, prefix.length)];
        NSString *numberDigits = [text stringByReplacingOccurrencesOfString:@"\\D" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];

        if (prefixDigits.length > 0 && [numberDigits hasPrefix:prefixDigits]) {
            numberDigits = [numberDigits substringFromIndex:prefixDigits.length];
        }

        NSString *fullPhone = [NSString stringWithFormat:@"+%@%@", prefixDigits, numberDigits];
        self.savedPhoneNumber = fullPhone;
        if (self.onPhoneSubmitted) {
            self.onPhoneSubmitted(fullPhone);
        }
    } else if (self.currentStep == TGLoginStepCode) {
        NSString *cleanCode = [text stringByReplacingOccurrencesOfString:@"\\D" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
        if (self.onCodeSubmitted) {
            self.onCodeSubmitted(cleanCode.length ? cleanCode : text);
        }
    } else if (self.currentStep == TGLoginStepPassword) {
        if (self.onPasswordSubmitted) {
            self.onPasswordSubmitted(text);
        }
    }
}

- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber {
    [self setBusy:NO];
    self.currentStep = TGLoginStepCode;
    self.title = @"Enter Code";
    self.headerLabel.text = @"Enter Code";
    if (phoneNumber.length > 0) {
        self.savedPhoneNumber = phoneNumber;
    }
    NSString *displayNumber = self.savedPhoneNumber ?: phoneNumber ?: @"";

    NSDictionary *info = [TGClient shared].codeInfo;
    NSString *codeType = info[@"type"][@"@type"];
    if ([codeType isEqualToString:@"authenticationCodeTypeTelegramMessage"]) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent a code to the Telegram app on your other device for\n%@\nPlease check your other Telegram client.", displayNumber];
    } else if ([codeType isEqualToString:@"authenticationCodeTypeSms"]) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent an SMS with a confirmation code to\n%@", displayNumber];
    } else {
        self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent a code to your other Telegram device or via SMS to\n%@", displayNumber];
    }

    [self useSingleFieldLayout];
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    [self.actionButton setTitle:@"Submit Code" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Edit"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

    CGFloat width = self.view.bounds.size.width;

    if (!self.resendButton) {
        self.resendButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.resendButton.frame = CGRectMake(15, 230, width - 30, 36);
        [self.resendButton setTitleColor:tgRGB(38, 92, 140) forState:UIControlStateNormal];
        [self.resendButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
        self.resendButton.titleLabel.font = [UIFont systemFontOfSize:14];
        [self.resendButton addTarget:self action:@selector(resendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.resendButton];
    }

    if (!self.codeStepQrButton) {
        self.codeStepQrButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.codeStepQrButton.frame = CGRectMake(15, 268, width - 30, 32);
        [self.codeStepQrButton setTitle:@"Log in with QR Code instead" forState:UIControlStateNormal];
        [self.codeStepQrButton setTitleColor:tgRGB(38, 92, 140) forState:UIControlStateNormal];
        self.codeStepQrButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [self.codeStepQrButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.codeStepQrButton];
    }

    self.scrollView.contentSize = CGSizeMake(width, 320);

    [self.resendTimer invalidate];
    self.resendTimer = nil;

    int timeout = [info[@"timeout"] intValue];
    if (timeout > 0) {
        self.resendCountdown = timeout;
        self.resendButton.enabled = NO;
        [self.resendButton setTitle:[NSString stringWithFormat:@"Send code via SMS in %lds", (long)self.resendCountdown] forState:UIControlStateDisabled];
        self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(resendTick:) userInfo:nil repeats:YES];
    } else {
        self.resendButton.enabled = YES;
        [self.resendButton setTitle:@"Send code via SMS / Resend" forState:UIControlStateNormal];
    }

    [self.inputField becomeFirstResponder];
}

- (void)resendTick:(NSTimer *)timer {
    self.resendCountdown--;
    if (self.resendCountdown <= 0) {
        [self.resendTimer invalidate];
        self.resendTimer = nil;
        self.resendButton.enabled = YES;
        [self.resendButton setTitle:@"Send code via SMS / Resend" forState:UIControlStateNormal];
    } else {
        [self.resendButton setTitle:[NSString stringWithFormat:@"Send code via SMS in %lds", (long)self.resendCountdown] forState:UIControlStateDisabled];
    }
}

- (void)resendButtonTapped {
    if (self.onResendCode) {
        self.onResendCode();
    }
    self.resendButton.enabled = NO;
    self.resendCountdown = 60;
    [self.resendButton setTitle:[NSString stringWithFormat:@"Send code via SMS in %lds", (long)self.resendCountdown] forState:UIControlStateDisabled];
    [self.resendTimer invalidate];
    self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(resendTick:) userInfo:nil repeats:YES];
}

- (void)resetSessionTapped {
    if (self.onResetSession) {
        self.onResetSession();
    }
    self.inputField.text = @"";
    [self showPhoneStep];
}

- (void)showPasswordStep {
    [self setBusy:NO];
    self.currentStep = TGLoginStepPassword;
    self.title = @"Password";
    self.headerLabel.text = @"Two-Step Verification";
    self.subtitleLabel.text = @"Your account is protected with a password.\nEnter your password below.";
    self.navigationItem.leftBarButtonItem = nil;

    if (self.resendButton) {
        [self.resendButton removeFromSuperview];
        self.resendButton = nil;
    }
    if (self.codeStepQrButton) {
        [self.codeStepQrButton removeFromSuperview];
        self.codeStepQrButton = nil;
    }
    [self.resendTimer invalidate];
    self.resendTimer = nil;

    [self useSingleFieldLayout];
    self.inputField.placeholder = @"Password";
    self.inputField.secureTextEntry = YES;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    [self.actionButton setTitle:@"Submit Password" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    [self.inputField becomeFirstResponder];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (self.currentStep == TGLoginStepPhone && string.length > 1) {
        NSString *existing = textField.text ?: @"";
        NSString *newText = [existing stringByReplacingCharactersInRange:range withString:string];
        [self processPastedPhoneNumber:newText];
        return NO;
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.phonePrefixField) {
        [self.inputField becomeFirstResponder];
        return YES;
    }
    [self actionButtonTapped];
    return YES;
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    CGRect kbFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbFrame.size.height;

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, kbHeight + 20, 0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

@end
