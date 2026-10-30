#import "TGLoginViewControllerInternal.h"
#import "TGClient.h"
#import "TGStyle.h"

/// Every step is the same vertical stack: instructions, a field, a button,
/// maybe a link or two, then the theme picker. Each one used to carry its own
/// column of offsets - 56/108/154/190/210 here, 64/116/162/196/230/250 next
/// door - so the four steps drifted a few points apart from each other for
/// no reason anybody chose.
///
/// These two put a thing where the cursor is and answer where the next thing
/// goes, so the rhythm is one piece of code rather than four columns.
static CGFloat TGStackPlace(UIView *view, CGFloat y, CGFloat height,
                            CGFloat width, CGFloat gutter) {
    if (view)
        view.frame = CGRectMake(gutter, y, width - TGDoubled(gutter), height);
    return y + height + TGMetricStackStep;
}

/// The same, for the thing that starts a new group - the theme picker under
/// everything else - which gets the larger step above it.
static CGFloat TGStackPlaceGroup(UIView *view, CGFloat y, CGFloat height,
                                 CGFloat width, CGFloat gutter) {
    return TGStackPlace(view, y + TGMetricStackGroup - TGMetricStackStep,
                        height, width, gutter);
}

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
    CGFloat y = TGMetricStackTop + TGMetricLoginSubtitleHeight + TGMetricStackStep;
    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    self.actionButton.hidden = NO;
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);
    self.inputField.hidden = NO;
    self.qrCodeButton.hidden = NO;
    y = TGStackPlace(self.qrCodeButton, y, TGMetricLoginLinkHeight,
                     width, TGMetricGutter);
    if (self.qrImageView) {
        self.qrImageView.hidden = YES;
    }
    self.phonePrefixField.hidden = NO;
    self.prefixSeparator.hidden = NO;
    CGFloat fieldX = TGMetricPadMedium + TGMetricLoginPrefixWidth + TGMetricPadMedium;
    self.inputField.frame = CGRectMake(fieldX, 0,
            width - TGDoubled(TGMetricGutter) - fieldX - TGMetricPadMedium,
            TGMetricRow);
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

    y = TGStackPlaceGroup(self.themeSectionLabel, y, TGMetricPadLarge,
                          width, TGMetricPadWide);
    y = TGStackPlace(self.themeSegmentedControl, y - TGMetricStackStep +
                     TGMetricPadSmall, TGMetricLoginLinkHeight,
                     width, TGMetricGutter);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width,
            y - TGMetricStackStep + TGMetricPadLarge);
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
    self.inputField.frame = CGRectMake(TGMetricPadMedium, 0,
            width - TGDoubled(TGMetricGutter) - TGDoubled(TGMetricPadMedium),
            TGMetricRow);
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
    CGFloat qrSize = MIN(width - 80, TGMetricLoginQRSize);
    CGFloat qrX = TGCenteredOrigin(width, qrSize);
    if (!self.qrImageView) {
        self.qrImageView = [[UIImageView alloc] initWithFrame:
                CGRectMake(qrX, TGMetricStackQRTop, qrSize, qrSize)];
        self.qrImageView.backgroundColor = [UIColor whiteColor];
        self.qrImageView.layer.cornerRadius = TGMetricCornerControl;
        self.qrImageView.layer.borderWidth = TGMetricHairline;
        self.qrImageView.clipsToBounds = YES;
        [self.scrollView addSubview:self.qrImageView];
    } else {
        self.qrImageView.frame = CGRectMake(qrX, TGMetricStackQRTop, qrSize, qrSize);
    }
    self.qrImageView.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
    self.qrImageView.hidden = NO;
    self.qrImageView.image = [self generateQRCodeForString:link size:qrSize];

    CGFloat qrY = TGStackPlaceGroup(nil, TGMetricStackQRTop + qrSize,
                                    0, width, TGMetricPadWide);
    qrY = TGStackPlace(self.themeSectionLabel, qrY - TGMetricStackStep,
                       TGMetricPadLarge, width, TGMetricPadWide);
    qrY = TGStackPlace(self.themeSegmentedControl,
                       qrY - TGMetricStackStep + TGMetricPadSmall,
                       TGMetricLoginLinkHeight, width, TGMetricGutter);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width,
            qrY - TGMetricStackStep + TGMetricPadLarge);
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
    CGFloat codeY = TGMetricStackTop + TGMetricLoginSubtitleHeight +
                    TGMetricStackGroup;
    codeY = TGStackPlace(self.inputContainer, codeY, TGMetricRow,
                         width, TGMetricGutter);
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    codeY = TGStackPlace(self.actionButton, codeY, TGMetricRow,
                         width, TGMetricGutter);
    [self.actionButton setTitle:@"Submit Code" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Edit"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

    if (!self.resendButton) {
        self.resendButton = [TGButton buttonWithTitle:@"Send code via SMS / Resend" variant:TGButtonVariantGhost size:TGButtonSizeSmall];
        self.resendButton.frame = CGRectMake(TGMetricGutter, codeY,
                width - TGDoubled(TGMetricGutter), TGMetricLoginLinkHeight);
        [self.resendButton addTarget:self action:@selector(resendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.resendButton];
    } else {
        self.resendButton.frame = CGRectMake(TGMetricGutter, codeY,
                width - TGDoubled(TGMetricGutter), TGMetricLoginLinkHeight);
    }

    if (!self.codeStepQrButton) {
        self.codeStepQrButton = [TGButton buttonWithTitle:@"Log in with QR Code instead" variant:TGButtonVariantGhost size:TGButtonSizeSmall];
        self.codeStepQrButton.frame = CGRectMake(TGMetricGutter,
                codeY + TGMetricLoginLinkHeight + TGMetricPadSmall,
                width - TGDoubled(TGMetricGutter), TGMetricLoginLinkHeight);
        [self.codeStepQrButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.codeStepQrButton];
    } else {
        self.codeStepQrButton.frame = CGRectMake(TGMetricGutter,
                codeY + TGMetricLoginLinkHeight + TGMetricPadSmall,
                width - TGDoubled(TGMetricGutter), TGMetricLoginLinkHeight);
    }

    // Past the two links, whichever of them is showing.
    codeY += TGDoubled(TGMetricLoginLinkHeight) + TGMetricPadSmall;
    codeY = TGStackPlaceGroup(self.themeSectionLabel, codeY,
                              TGMetricPadLarge, width, TGMetricPadWide);
    codeY = TGStackPlace(self.themeSegmentedControl,
                         codeY - TGMetricStackStep + TGMetricPadSmall,
                         TGMetricLoginLinkHeight, width, TGMetricGutter);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width,
            codeY - TGMetricStackStep + TGMetricPadLarge);

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
    CGSize room = CGSizeMake(width - TGDoubled(TGMetricPadWide),
                             TGMetricTextMeasureHeight);
    CGFloat subtitleH = 40;
    if ([self.subtitleLabel.text respondsToSelector:
            @selector(boundingRectWithSize:options:attributes:context:)]){
        subtitleH = ceilf([self.subtitleLabel.text boundingRectWithSize:room
                options:NSStringDrawingUsesLineFragmentOrigin
             attributes:@{NSFontAttributeName : self.subtitleLabel.font}
                context:nil].size.height);
    }
    self.subtitleLabel.frame = CGRectMake(TGMetricPadWide, TGMetricPad,
            width - TGDoubled(TGMetricPadWide), subtitleH);

    CGFloat y = 16 + subtitleH;
    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    self.inputField.placeholder = @"First name";
    self.inputField.secureTextEntry = NO;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);
    [self.actionButton setTitle:@"Create Account" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    self.themeSectionLabel.hidden = YES;
    self.themeSegmentedControl.hidden = YES;
    self.scrollView.contentSize = CGSizeMake(width,
            y - TGMetricStackStep + TGMetricPadLarge);

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
    CGFloat passY = TGMetricStackTop + TGMetricLoginSubtitleHeight +
                    TGMetricStackStep;
    passY = TGStackPlace(self.inputContainer, passY, TGMetricRow,
                         width, TGMetricGutter);
    self.inputField.placeholder = @"Password";
    self.inputField.secureTextEntry = YES;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    passY = TGStackPlace(self.actionButton, passY, TGMetricRow,
                         width, TGMetricGutter);
    [self.actionButton setTitle:@"Submit Password" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";

    passY = TGStackPlaceGroup(self.themeSectionLabel, passY,
                              TGMetricPadLarge, width, TGMetricPadWide);
    passY = TGStackPlace(self.themeSegmentedControl,
                         passY - TGMetricStackStep + TGMetricPadSmall,
                         TGMetricLoginLinkHeight, width, TGMetricGutter);
    self.themeSectionLabel.hidden = NO;
    self.themeSegmentedControl.hidden = NO;

    self.scrollView.contentSize = CGSizeMake(width,
            passY - TGMetricStackStep + TGMetricPadLarge);

    [self applyTheme];
    [self.inputField becomeFirstResponder];
}

@end
