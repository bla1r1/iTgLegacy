#import "TGLoginViewControllerInternal.h"
#import "TGClient.h"
#import "TGStyle.h"

@implementation TGLoginViewController (Steps)

- (void)showPhoneStep {
    [self.resendTimer invalidate];
    self.resendTimer = nil;
    [self setBusy:NO];
    self.currentStep = TGLoginStepPhone;
    self.title = @"Your Phone";
    self.subtitleLabel.text = @"Please confirm your country code\nand enter your phone number.";

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
    self.inputContainer.frame = CGRectMake(15, 56, width - 30, 44);
    self.actionButton.hidden = NO;
    self.actionButton.frame = CGRectMake(15, 108, width - 30, 42);
    self.inputField.hidden = NO;
    self.qrCodeButton.hidden = NO;
    self.qrCodeButton.frame = CGRectMake(15, 154, width - 30, 30);
    if (self.qrImageView) {
        self.qrImageView.hidden = YES;
    }
    self.phonePrefixField.hidden = NO;
    self.prefixSeparator.hidden = NO;
    self.inputField.frame = CGRectMake(78, 0, width - 108, 44);
    self.inputField.textAlignment = NSTextAlignmentLeft;
    self.inputField.font = TGFontInput();
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

    self.themeSectionLabel.frame = CGRectMake(20, 190, width - 40, 16);
    self.themeSegmentedControl.frame = CGRectMake(15, 210, width - 30, 30);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width, 256);
    [self applyTheme];
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
    self.inputField.frame = CGRectMake(10, 0, width - 50, 44);
    self.inputField.textAlignment = NSTextAlignmentCenter;
    self.inputField.font = TGFontTitle();
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
    self.subtitleLabel.text = @"Open Telegram on another device:\nSettings > Devices > Link Desktop Device";

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

    CGFloat width = self.view.bounds.size.width;
    CGFloat qrSize = MIN(width - 80, 180.0f);
    if (!self.qrImageView) {
        self.qrImageView = [[UIImageView alloc] initWithFrame:CGRectMake((width - qrSize) / 2.0f, 64, qrSize, qrSize)];
        self.qrImageView.backgroundColor = [UIColor whiteColor];
        self.qrImageView.layer.cornerRadius = 8.0f;
        self.qrImageView.layer.borderWidth = 0.5f;
        self.qrImageView.clipsToBounds = YES;
        [self.scrollView addSubview:self.qrImageView];
    } else {
        self.qrImageView.frame = CGRectMake((width - qrSize) / 2.0f, 64, qrSize, qrSize);
    }
    self.qrImageView.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
    self.qrImageView.hidden = NO;
    self.qrImageView.image = [self generateQRCodeForString:link size:qrSize];

    self.themeSectionLabel.frame = CGRectMake(20, 64 + qrSize + 16, width - 40, 16);
    self.themeSegmentedControl.frame = CGRectMake(15, 64 + qrSize + 36, width - 30, 30);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width, 64 + qrSize + 80);
    [self applyTheme];
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

- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber {
    [self setBusy:NO];
    self.currentStep = TGLoginStepCode;
    self.title = @"Enter Code";
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

    CGFloat width = self.view.bounds.size.width;
    [self useSingleFieldLayout];
    self.inputContainer.frame = CGRectMake(15, 64, width - 30, 44);
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    self.actionButton.frame = CGRectMake(15, 116, width - 30, 42);
    [self.actionButton setTitle:@"Submit Code" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Edit"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

    if (!self.resendButton) {
        self.resendButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.resendButton.frame = CGRectMake(15, 162, width - 30, 30);
        [self.resendButton setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
        [self.resendButton setTitleColor:[[TGTheme shared] secondaryTextColour] forState:UIControlStateDisabled];
        self.resendButton.titleLabel.font = TGFontSubhead();
        [self.resendButton addTarget:self action:@selector(resendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.resendButton];
    } else {
        self.resendButton.frame = CGRectMake(15, 162, width - 30, 30);
    }

    if (!self.codeStepQrButton) {
        self.codeStepQrButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.codeStepQrButton.frame = CGRectMake(15, 196, width - 30, 28);
        [self.codeStepQrButton setTitle:@"Log in with QR Code instead" forState:UIControlStateNormal];
        [self.codeStepQrButton setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
        self.codeStepQrButton.titleLabel.font = TGFontSubheadStrong();
        [self.codeStepQrButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.codeStepQrButton];
    } else {
        self.codeStepQrButton.frame = CGRectMake(15, 196, width - 30, 28);
    }

    self.themeSectionLabel.frame = CGRectMake(20, 230, width - 40, 16);
    self.themeSegmentedControl.frame = CGRectMake(15, 250, width - 30, 30);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width, 296);

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

    [self applyTheme];
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

/// Their sign-up screen, as far as this app needs it: a first name, and the
/// terms Telegram sent with the state. A last name is optional and Telegram
/// does not require one, so the single field this screen has asks for the
/// first and the rest is left for Edit Profile.
- (void)showRegisterStep {
    [self setBusy:NO];
    self.currentStep = TGLoginStepRegister;
    self.title = @"Your Name";

    NSString *terms = [[TGClient shared] registrationTerms];
    self.subtitleLabel.text = terms.length
            ? [NSString stringWithFormat:@"This number is new to Telegram.\n\n%@", terms]
            : @"This number is new to Telegram.\nEnter your name to finish.";
    self.subtitleLabel.numberOfLines = 0;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Cancel"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

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

    CGFloat width = self.view.bounds.size.width;
    [self useSingleFieldLayout];
    // The terms can run long, so the field sits under whatever they took.
    CGSize room = CGSizeMake(width - 40, 10000);
    CGFloat subtitleH = 40;
    if ([self.subtitleLabel.text respondsToSelector:
            @selector(boundingRectWithSize:options:attributes:context:)]){
        subtitleH = ceilf([self.subtitleLabel.text boundingRectWithSize:room
                options:NSStringDrawingUsesLineFragmentOrigin
             attributes:@{NSFontAttributeName : self.subtitleLabel.font}
                context:nil].size.height);
    }
    self.subtitleLabel.frame = CGRectMake(20, 8, width - 40, subtitleH);

    CGFloat y = 16 + subtitleH;
    self.inputContainer.frame = CGRectMake(15, y, width - 30, 44);
    self.inputField.placeholder = @"First name";
    self.inputField.secureTextEntry = NO;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.actionButton.frame = CGRectMake(15, y + 52, width - 30, 42);
    [self.actionButton setTitle:@"Create Account" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    self.themeSectionLabel.hidden = YES;
    self.themeSegmentedControl.hidden = YES;
    self.scrollView.contentSize = CGSizeMake(width, y + 110);

    [self applyTheme];
    [self.inputField becomeFirstResponder];
}

- (void)showPasswordStep {
    [self setBusy:NO];
    self.currentStep = TGLoginStepPassword;
    self.title = @"Password";
    self.subtitleLabel.text = @"Your account is protected with a password.\nEnter your password below.";

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Cancel"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

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

    CGFloat width = self.view.bounds.size.width;
    [self useSingleFieldLayout];
    self.inputContainer.frame = CGRectMake(15, 56, width - 30, 44);
    self.inputField.placeholder = @"Password";
    self.inputField.secureTextEntry = YES;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.actionButton.frame = CGRectMake(15, 108, width - 30, 42);
    [self.actionButton setTitle:@"Submit Password" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    self.themeSectionLabel.frame = CGRectMake(20, 160, width - 40, 16);
    self.themeSegmentedControl.frame = CGRectMake(15, 180, width - 30, 30);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width, 226);

    [self applyTheme];
    [self.inputField becomeFirstResponder];
}

@end
