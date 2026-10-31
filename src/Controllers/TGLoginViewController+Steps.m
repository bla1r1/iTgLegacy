#import "TGTextDraw.h"
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
    [self clearStepLinks];
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
    CGFloat y = [self placeSubtitle] + TGMetricStackGroup;
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
    self.navigationItem.rightBarButtonItem = self.nextItem;

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
    // The phone field's size. 22 pt bold was larger than the bar's own title
    // and filled the row from edge to edge.
    self.inputField.font = TGFontInput();
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
    [self clearStepLinks];
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
    // Nothing to submit here: the other device does the work.
    self.navigationItem.rightBarButtonItem = nil;

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
    // iOS 6 ships this filter unannounced and without a correction-level
    // input: setting the key raised NSUnknownKeyException and the QR login
    // took the app down. Only keys the filter lists are set.
    NSArray *keys = qrFilter.inputKeys;
    if (![keys containsObject:@"inputMessage"])
        return nil;
    [qrFilter setValue:stringData forKey:@"inputMessage"];
    if ([keys containsObject:@"inputCorrectionLevel"])
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
    [self clearStepLinks];
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
    CGFloat codeY = [self placeSubtitle] + TGMetricStackGroup;
    codeY = TGStackPlace(self.inputContainer, codeY, TGMetricRow,
                         width, TGMetricGutter);
    [self.inputField resignFirstResponder];   // or the number pad never shows
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    codeY = TGStackPlace(self.actionButton, codeY, TGMetricRow,
                         width, TGMetricGutter);
    [self.actionButton setTitle:@"Submit Code" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    self.navigationItem.rightBarButtonItem = self.nextItem;

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
    codeY = [self addStepLink:@"Didn't get the code?" action:@selector(codeMissingTapped)
                          atY:codeY + TGMetricPadSmall];
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
    [self clearStepLinks];
    [self setBusy:NO];
    self.currentStep = TGLoginStepRegister;
    self.title = @"Your Name";

    NSString *terms = [[TGClient shared] registrationTerms];
    self.subtitleLabel.text = terms.length
            ? [NSString stringWithFormat:@"This number is new to Telegram.\n\n%@", terms]
            : @"This number is new to Telegram.\nEnter your name to finish.";

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
    CGFloat y = [self placeSubtitle] + TGMetricStackGroup;
    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    self.inputField.placeholder = @"First name";
    self.inputField.secureTextEntry = NO;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);
    [self.actionButton setTitle:@"Create Account" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    self.navigationItem.rightBarButtonItem = self.nextItem;

    self.themeSectionLabel.hidden = YES;
    self.themeSegmentedControl.hidden = YES;
    self.scrollView.contentSize = CGSizeMake(width,
            y - TGMetricStackStep + TGMetricPadLarge);

    [self applyTheme];
    [self.inputField becomeFirstResponder];
}

- (void)showPasswordStep {
    NSDictionary *info = [TGClient shared].loginPasswordInfo;
    NSString *hint = info[@"password_hint"];
    NSString *subtitle = hint.length
            ? [NSString stringWithFormat:@"Your account is protected with a password.\nHint: %@", hint]
            : @"Your account is protected with a password.\nEnter your password below.";
    [self showFieldStep:TGLoginStepPassword title:@"Password" subtitle:subtitle
            placeholder:@"Password" secure:YES keyboard:UIKeyboardTypeDefault
                 button:@"Submit Password"];
    [self addStepLink:@"Forgot password?" action:@selector(forgotPasswordTapped)
                  atY:CGRectGetMaxY(self.actionButton.frame) + TGMetricPadSmall];
}

/// Asks Telegram to mail a recovery code. An account without a recovery
/// address gets Telegram's refusal, said plainly: there is nothing else this
/// app can offer it.
- (void)forgotPasswordTapped {
    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [[TGClient shared] requestPasswordRecoveryWithCompletion:^(NSString *error){
        TGLoginViewController *me = weakSelf;
        [me setBusy:NO];
        if (error) {
            [TGAlertSheet showMessage:[NSString stringWithFormat:
                    @"%@\n\nWithout a recovery email the password cannot be reset from here.", error]
                                title:@"Forgot Password" inView:me.view];
            return;
        }
        [me showRecoveryCodeStep];
    }];
}

- (void)showRecoveryCodeStep {
    NSString *pattern = [TGClient shared].loginPasswordInfo[@"recovery_email_address_pattern"];
    NSString *subtitle = pattern.length
            ? [NSString stringWithFormat:@"We've emailed a recovery code to\n%@\nEntering it removes the password.", pattern]
            : @"We've emailed a recovery code to your recovery address.\nEntering it removes the password.";
    [self showFieldStep:TGLoginStepRecoveryCode title:@"Recovery Code" subtitle:subtitle
            placeholder:@"Code" secure:NO keyboard:UIKeyboardTypeNumberPad
                 button:@"Submit Code"];
}

- (void)showEmailStep {
    [self showFieldStep:TGLoginStepEmail title:@"Your Email"
               subtitle:@"Telegram needs an email address for this account\nbefore it sends a login code."
            placeholder:@"Email address" secure:NO keyboard:UIKeyboardTypeEmailAddress
                 button:@"Continue"];
}

- (void)showEmailCodeStep {
    NSDictionary *info = [TGClient shared].emailCodeInfo;
    NSString *pattern = info[@"code_info"][@"email_address_pattern"];
    NSString *subtitle = pattern.length
            ? [NSString stringWithFormat:@"We've sent a code to\n%@", pattern]
            : @"We've sent a code to your email.";
    [self showFieldStep:TGLoginStepEmailCode title:@"Check Your Email" subtitle:subtitle
            placeholder:@"Code" secure:NO keyboard:UIKeyboardTypeNumberPad
                 button:@"Submit Code"];
    if ([info[@"can_reset_email_address"] boolValue])
        [self addStepLink:@"Can't access this email?" action:@selector(resetEmailTapped)
                      atY:CGRectGetMaxY(self.actionButton.frame) + TGMetricPadSmall];
}

- (void)resetEmailTapped {
    [self setBusy:YES];
    [[TGClient shared] resetAuthenticationEmailAddress];
}

- (void)codeMissingTapped {
    [[TGClient shared] reportAuthenticationCodeMissing];
    [TGAlertSheet showMessage:@"Telegram has been told the code did not arrive.\n\nTry \"Send code via SMS\" once the timer runs out, or log in with a QR code from another device."
                        title:@"No Code" inView:self.view];
}

/// Sizes the subtitle to its text and returns where it ends. It was two
/// lines high whatever it said, so "...via SMS to" lost the phone number on
/// the code step, the one line that says where the code went.
- (CGFloat)placeSubtitle {
    CGFloat width = self.view.bounds.size.width - TGDoubled(TGMetricPadWide);
    self.subtitleLabel.numberOfLines = 0;
    CGFloat height = MAX(TGTextHeight(self.subtitleLabel.text, self.subtitleLabel.font, width),
                         TGMetricLoginSubtitleHeight);
    self.subtitleLabel.frame = CGRectMake(TGMetricPadWide, TGMetricStackTop, width, height);
    return TGMetricStackTop + height;
}

- (void)clearStepLinks {
    for (UIView *link in self.stepLinks)
        [link removeFromSuperview];
    [self.stepLinks removeAllObjects];
}

/// One ghost link at `y`; returns where the next one goes.
- (CGFloat)addStepLink:(NSString *)title action:(SEL)action atY:(CGFloat)y {
    if (!self.stepLinks)
        self.stepLinks = [NSMutableArray array];
    CGFloat width = self.view.bounds.size.width;
    TGButton *link = [TGButton buttonWithTitle:title variant:TGButtonVariantGhost size:TGButtonSizeSmall];
    link.frame = CGRectMake(TGMetricGutter, y, width - TGDoubled(TGMetricGutter), TGMetricLoginLinkHeight);
    [link addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:link];
    [self.stepLinks addObject:link];
    CGFloat next = y + TGMetricLoginLinkHeight + TGMetricPadSmall;
    self.scrollView.contentSize = CGSizeMake(width, MAX(self.scrollView.contentSize.height, next + TGMetricPadLarge));
    return next;
}

/// The steps that are one field and one button: the password and the
/// email ones. Links are added by the caller under the button.
- (void)showFieldStep:(TGLoginStep)step title:(NSString *)title subtitle:(NSString *)subtitle
          placeholder:(NSString *)placeholder secure:(BOOL)secure
             keyboard:(UIKeyboardType)keyboard button:(NSString *)button {
    [self setBusy:NO];
    [self clearStepLinks];
    self.currentStep = step;
    self.title = title;
    self.subtitleLabel.text = subtitle;

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
    CGFloat y = [self placeSubtitle] + TGMetricStackGroup;
    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    // A keyboard type set on a field that already has focus is ignored until
    // it loses it: the code steps used to open on letters.
    [self.inputField resignFirstResponder];
    self.inputField.text = @"";
    self.inputField.placeholder = placeholder;
    self.inputField.secureTextEntry = secure;
    self.inputField.keyboardType = keyboard;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);
    [self.actionButton setTitle:button forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    self.navigationItem.rightBarButtonItem = self.nextItem;

    self.themeSectionLabel.hidden = YES;
    self.themeSegmentedControl.hidden = YES;
    self.scrollView.contentSize = CGSizeMake(width, y - TGMetricStackStep + TGMetricPadLarge);

    [self applyTheme];
    [self.inputField becomeFirstResponder];
}

@end
