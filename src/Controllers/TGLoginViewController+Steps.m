#import "TGTextDraw.h"
#import "TGLoginViewControllerInternal.h"
#import "TGClient.h"
#import "TGStyle.h"
#import "TGUIFormat.h"

/// Every step is the same vertical stack: instructions, a field, a button,
/// and maybe a link or two. Each one used to carry its own column of
/// offsets - 56/108/154/190/210 here, 64/116/162/196/230/250 next door - so
/// the four steps drifted a few points apart from each other for no reason
/// anybody chose.
///
/// The show* methods only *choose* a step - titles, secrets, timers,
/// keyboards - and then land in layoutActiveStep, which writes every frame
/// from the view's present bounds and again on every rotation. These two
/// static helpers put a thing where the cursor is and answer where the next
/// thing goes, so the rhythm stays one value for every step and every
/// screen size.
static CGFloat TGStackPlace(UIView *view, CGFloat y, CGFloat height,
                            CGFloat width, CGFloat gutter) {
    if (view)
        view.frame = CGRectMake(gutter, y, width - TGDoubled(gutter), height);
    return y + height + TGMetricStackStep;
}

/// The same, for whatever starts a new group further down the form - it gets
/// the larger step above it.
static CGFloat TGStackPlaceGroup(UIView *view, CGFloat y, CGFloat height,
                                 CGFloat width, CGFloat gutter) {
    return TGStackPlace(view, y + TGMetricStackGroup - TGMetricStackStep,
                        height, width, gutter);
}

@implementation TGLoginViewController (Steps)

#pragma mark - step geometry

/// The current step's frames, written from the view's present bounds. Every
/// show* method below ends here, and so does every rotation and layout pass:
/// the phone step folds its prefix into one row on 320 pt and spreads on
/// wider screens, the QR re-centres, the links re-stack under the button.
/// This is the one place the answer to "where does a thing go" lives.
- (void)layoutActiveStep {
    if (!self.scrollView || !self.inputContainer)
        return;
    CGFloat width = self.view.bounds.size.width;

    // Only the first step is the app's front door; the code, password and
    // email steps are about the one thing they ask for and start at the top.
    BOOL showsBrand = (self.currentStep == TGLoginStepPhone) &&
            (!self.qrImageView || self.qrImageView.hidden);
    self.brandLogoView.hidden = !showsBrand;
    self.brandLabel.hidden = !showsBrand;
    if (!showsBrand || !self.countryLabel.text.length)
        self.countryLabel.hidden = YES;

    if (self.qrImageView && !self.qrImageView.hidden) {
        [self layoutQRStepInWidth:width];
        return;
    }
    switch (self.currentStep) {
        case TGLoginStepPhone:
            [self layoutPhoneStepInWidth:width];
            break;
        case TGLoginStepCode:
            [self layoutCodeStepInWidth:width];
            break;
        case TGLoginStepRegister:
        case TGLoginStepEmail:
        case TGLoginStepEmailCode:
        case TGLoginStepPassword:
        case TGLoginStepRecoveryCode:
            [self layoutFieldStepInWidth:width];
            break;
    }
}

- (void)layoutPhoneStepInWidth:(CGFloat)width {
    CGFloat y = TGMetricStackTop;
    if (!self.brandLogoView.hidden) {
        self.brandLogoView.frame = CGRectMake(
                TGCenteredOrigin(width, TGMetricLoginBrandLogo), y,
                TGMetricLoginBrandLogo, TGMetricLoginBrandLogo);
        y += TGMetricLoginBrandLogo + TGMetricPad;
        self.brandLabel.frame = CGRectMake(TGMetricPadWide, y,
                width - TGDoubled(TGMetricPadWide), TGMetricLoginBrandLabel);
        y += TGMetricLoginBrandLabel + TGMetricStackGroup;
    }
    y = [self placeSubtitleAtY:y] + TGMetricStackGroup;

    if (!self.countryLabel.hidden) {
        self.countryLabel.frame = CGRectMake(TGMetricPadWide, y,
                width - TGDoubled(TGMetricPadWide), TGMetricLoginCountryLine);
        y += TGMetricLoginCountryLine + TGMetricStackStep;
    }

    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    y = [self placeErrorAtY:y width:width];
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);
    y = TGStackPlace(self.qrCodeButton, y, TGMetricLoginLinkHeight,
                     width, TGMetricGutter);

    CGFloat fieldX = TGMetricPadMedium + TGMetricLoginPrefixWidth + TGMetricPadMedium;
    self.inputField.frame = CGRectMake(fieldX, 0,
            width - TGDoubled(TGMetricGutter) - fieldX - TGMetricPadMedium,
            TGMetricRow);

    y = [self placeStepLinksFromY:y width:width];

    y += TGMetricStackGroup;
    self.scrollView.contentSize = CGSizeMake(width,
            y - TGMetricStackStep + TGMetricPadLarge);
}

- (void)layoutCodeStepInWidth:(CGFloat)width {
    CGFloat y = [self placeSubtitle] + TGMetricStackGroup;
    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    y = [self placeErrorAtY:y width:width];
    self.inputField.frame = CGRectMake(TGMetricPadMedium, 0,
            width - TGDoubled(TGMetricGutter) - TGDoubled(TGMetricPadMedium),
            TGMetricRow);
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);

    y = [self placeGhostRow:self.resendButton atY:y width:width];
    y = [self placeGhostRow:self.codeStepQrButton atY:y width:width];
    y = [self placeStepLinksFromY:y width:width];

    y += TGMetricStackGroup;
    self.scrollView.contentSize = CGSizeMake(width,
            y - TGMetricStackStep + TGMetricPadLarge);
}

/// The password, email, register and recovery steps are one field, one
/// button, and whatever links the caller asked for under that button.
- (void)layoutFieldStepInWidth:(CGFloat)width {
    CGFloat y = [self placeSubtitle] + TGMetricStackGroup;
    y = TGStackPlace(self.inputContainer, y, TGMetricRow, width, TGMetricGutter);
    y = [self placeErrorAtY:y width:width];
    self.inputField.frame = CGRectMake(TGMetricPadMedium, 0,
            width - TGDoubled(TGMetricGutter) - TGDoubled(TGMetricPadMedium),
            TGMetricRow);

    CGFloat buttonMaxY = y;
    y = TGStackPlace(self.actionButton, y, TGMetricRow, width, TGMetricGutter);
    CGFloat bottom = MAX(
            y - TGMetricStackStep + TGMetricPadLarge,
            [self placeStepLinksFromY:buttonMaxY + TGMetricPadSmall width:width]
                    + TGMetricPadLarge);
    self.scrollView.contentSize = CGSizeMake(width, bottom);
}

- (void)layoutQRStepInWidth:(CGFloat)width {
    [self placeSubtitle];

    CGFloat qrSize = MIN(width - 80, TGMetricLoginQRSize);
    self.qrImageView.frame = CGRectMake(
            TGCenteredOrigin(width, qrSize), TGMetricStackQRTop, qrSize, qrSize);

    CGFloat qrY = TGStackPlaceGroup(nil, TGMetricStackQRTop + qrSize,
                                    0, width, TGMetricPadWide);
    qrY = [self placeStepLinksFromY:qrY width:width];
    self.scrollView.contentSize = CGSizeMake(width,
            qrY - TGMetricStackStep + TGMetricPadLarge);
}

/// One full-width ghost row - the resend, the QR link - framed at `y`; the
/// cursor answers where the next row starts.
- (CGFloat)placeGhostRow:(UIView *)view atY:(CGFloat)y width:(CGFloat)width {
    TGStackPlace(view, y, TGMetricLoginLinkHeight, width, TGMetricGutter);
    return y + TGMetricLoginLinkHeight + TGMetricPadSmall;
}

/// Every step link the step carries, stacked from `y`; returns the cursor
/// past the last one.
- (CGFloat)placeStepLinksFromY:(CGFloat)y width:(CGFloat)width {
    for (UIView *link in self.stepLinks) {
        link.frame = CGRectMake(TGMetricGutter, y,
                width - TGDoubled(TGMetricGutter), TGMetricLoginLinkHeight);
        y += TGMetricLoginLinkHeight + TGMetricPadSmall;
    }
    return y;
}

- (void)showPhoneStep {
    [self clearStepLinks];
    [self.resendTimer invalidate];
    self.resendTimer = nil;
    [self setBusy:NO];
    self.errorLabel.text = nil;
    self.errorLabel.hidden = YES;
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

    self.inputContainer.hidden = NO;
    self.actionButton.hidden = NO;
    self.inputField.hidden = NO;
    self.qrCodeButton.hidden = NO;
    if (self.qrImageView) {
        self.qrImageView.hidden = YES;
    }
    // A field that is already first responder ignores a new secure flag and
    // keyboard type; the password screen's Cancel used to return to a phone
    // field still wearing its dots.
    [self.inputField resignFirstResponder];
    self.phonePrefixField.hidden = NO;
    self.prefixSeparator.hidden = NO;
    self.countryLabel.text = nil;
    self.countryLabel.hidden = YES;
    self.expectedCodeLength = 0;
    self.inputField.textAlignment = NSTextAlignmentLeft;
    self.inputField.font = TGFontInput();
    self.inputField.placeholder = @"Phone number";
    self.inputField.text = self.savedNationalNumber ?: @"";
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

    // A pasted number answers its own prefix; a typed one needs the country
    // this phone is in, which Telegram guesses from the network. The picker
    // is there for when the guess is wrong or the number is not local.
    if (!self.prefixEdited) {
        __weak typeof(self) weakSelf = self;
        [[TGClient shared] countryCodeWithCompletion:^(NSString *code){
            TGLoginViewController *me = weakSelf;
            if (!me || me.currentStep != TGLoginStepPhone || !code.length)
                return;
            if (me.prefixEdited)
                return;
            me.phonePrefixField.text = [@"+" stringByAppendingString:code];
        }];
    }
    [self addStepLink:@"Choose a Country" action:@selector(countryPickerTapped) atY:0];
    // A web login hands over a token instead of a code; the phone step is
    // where the official client offers that choice too.
    [self addStepLink:@"Web Login Token" action:@selector(webTokenTapped) atY:0];

    [self layoutActiveStep];
    [self applyTheme];
    [self updateActionEnabled];
    [self.inputField becomeFirstResponder];
}

- (void)useSingleFieldLayout {
    self.inputContainer.hidden = NO;
    self.actionButton.hidden = NO;
    self.inputField.hidden = NO;
    self.phonePrefixField.hidden = YES;
    self.prefixSeparator.hidden = YES;
    self.qrCodeButton.hidden = YES;
    if (self.qrImageView) {
        self.qrImageView.hidden = YES;
    }
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
    self.errorLabel.text = nil;
    self.errorLabel.hidden = YES;
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
    }
    self.qrImageView.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
    self.qrImageView.hidden = NO;
    self.qrImageView.image = [self generateQRCodeForString:link size:qrSize];

    // The other direction: the other device shows the code and this one
    // confirms the link, which is what their "scan a QR" does with a camera
    // this OS may not have.
    [self addStepLink:@"Enter a QR Link" action:@selector(qrLinkTapped) atY:0];

    [self layoutActiveStep];
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
    self.errorLabel.text = nil;
    self.errorLabel.hidden = YES;
    self.currentStep = TGLoginStepCode;
    self.title = @"Enter Code";
    if (phoneNumber.length > 0) {
        self.savedPhoneNumber = phoneNumber;
    }
    NSString *displayNumber = self.savedPhoneNumber ?: phoneNumber ?: @"";

    NSDictionary *info = [TGClient shared].codeInfo;
    NSString *codeType = info[@"type"][@"@type"];
    if ([codeType isEqualToString:@"authenticationCodeTypeTelegramMessage"]) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent the code to your Telegram app\non another device for\n%@", displayNumber];
    } else if ([codeType isEqualToString:@"authenticationCodeTypeSms"]) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent an SMS with the code to\n%@", displayNumber];
    } else if ([codeType isEqualToString:@"authenticationCodeTypeCall"]) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"Telegram is calling %@\nwith the code.", displayNumber];
    } else {
        self.subtitleLabel.text = [NSString stringWithFormat:@"We've sent a code to your other Telegram device or by SMS to\n%@", displayNumber];
    }

    self.countryLabel.hidden = YES;
    self.expectedCodeLength = [info[@"length"] integerValue];
    [self useSingleFieldLayout];
    [self.inputField resignFirstResponder];   // or the number pad never shows
    self.inputField.placeholder = @"Code";
    self.inputField.keyboardType = UIKeyboardTypeNumberPad;
    [self.actionButton setTitle:@"Submit Code" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    self.navigationItem.rightBarButtonItem = self.nextItem;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Edit"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(showPhoneStep)];

    // The frames land in layoutActiveStep: resend under the button, the QR
    // link under it, this link under both.
    if (!self.resendButton) {
        self.resendButton = [TGButton buttonWithTitle:@"Send code via SMS / Resend" variant:TGButtonVariantGhost size:TGButtonSizeSmall];
        [self.resendButton addTarget:self action:@selector(resendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.resendButton];
    }
    if (!self.codeStepQrButton) {
        self.codeStepQrButton = [TGButton buttonWithTitle:@"Log in with QR Code instead" variant:TGButtonVariantGhost size:TGButtonSizeSmall];
        [self.codeStepQrButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:self.codeStepQrButton];
    }
    [self addStepLink:@"Didn't get the code?" action:@selector(codeMissingTapped) atY:0];
    // The Firebase code is not an SMS: it is a secret handed to the app by a
    // push, and the server only accepts it through its own request. Offered
    // only when Telegram actually sent that kind of code.
    if ([codeType hasPrefix:@"authenticationCodeTypeFirebase"])
        [self addStepLink:@"Code Came By Push?" action:@selector(firebaseCodeTapped) atY:0];

    [self layoutActiveStep];

    [self.resendTimer invalidate];
    self.resendTimer = nil;

    int timeout = [info[@"timeout"] intValue];
    if (timeout > 0) {
        self.resendCountdown = timeout;
        [self.resendButton setTitle:[self resendTitleForCountdown:self.resendCountdown]
                          forState:UIControlStateDisabled];
        self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(resendTick:) userInfo:nil repeats:YES];
    } else {
        self.resendCountdown = 0;
        [self.resendButton setTitle:@"Resend code" forState:UIControlStateNormal];
    }

    [self applyTheme];
    [self updateActionEnabled];
    [self.inputField becomeFirstResponder];
}

- (NSString *)resendTitleForCountdown:(NSInteger)seconds {
    NSString *clock = TGUIFormatCallDuration(MAX(0, seconds));
    return [NSString stringWithFormat:@"Resend code in %@", clock];
}

- (void)resendTick:(NSTimer *)timer {
    self.resendCountdown--;
    if (self.resendCountdown <= 0) {
        [self.resendTimer invalidate];
        self.resendTimer = nil;
        self.resendCountdown = 0;
        [self.resendButton setTitle:@"Resend code" forState:UIControlStateNormal];
    } else {
        [self.resendButton setTitle:[self resendTitleForCountdown:self.resendCountdown]
                          forState:UIControlStateDisabled];
    }
    [self updateActionEnabled];
}

- (void)resendButtonTapped {
    if (self.onResendCode) {
        self.onResendCode();
    }
    self.resendCountdown = 60;
    [self.resendButton setTitle:[self resendTitleForCountdown:self.resendCountdown]
                      forState:UIControlStateDisabled];
    [self.resendTimer invalidate];
    self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(resendTick:) userInfo:nil repeats:YES];
    [self updateActionEnabled];
}

- (void)resetSessionTapped {
    if (self.onResetSession) {
        self.onResetSession();
    }
    self.savedNationalNumber = nil;
    self.savedPhoneNumber = nil;
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

    // The terms can run long, so the field sits under whatever they took.
    [self useSingleFieldLayout];
    self.inputField.placeholder = @"First name";
    self.inputField.secureTextEntry = NO;
    self.inputField.keyboardType = UIKeyboardTypeDefault;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    [self.actionButton setTitle:@"Create Account" forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    self.navigationItem.rightBarButtonItem = self.nextItem;

    [self layoutActiveStep];

    [self applyTheme];
    [self updateActionEnabled];
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
    self.expectedCodeLength = [info[@"code_info"][@"length"] integerValue];
    [self updateActionEnabled];
    if ([info[@"can_reset_email_address"] boolValue])
        [self addStepLink:@"Can't access this email?" action:@selector(resetEmailTapped)
                      atY:CGRectGetMaxY(self.actionButton.frame) + TGMetricPadSmall];
}

- (void)resetEmailTapped {
    [self setBusy:YES];
    [[TGClient shared] resetAuthenticationEmailAddress];
    [self releaseBusyIfStepIsStill:self.currentStep];
}

- (void)codeMissingTapped {
    [[TGClient shared] reportAuthenticationCodeMissing];
    [TGAlertSheet showMessage:@"Telegram has been told the code did not arrive.\n\nTry \"Send code via SMS\" once the timer runs out, or log in with a QR code from another device."
                        title:@"No Code" inView:self.view];
}

/// A token from a web login: the desktop page shows one when it waits for a
/// phone to approve it. Either it signs in, or it is dropped so it stops
/// waiting - both answers come from Telegram and are shown.
- (void)webTokenTapped {
    __weak typeof(self) weakSelf = self;
    [TGAlertSheet showInput:@"Web Login Token"
                    message:@"Paste the token from the web login, then choose what to do with it."
                placeholder:@"Token"
                       text:nil
                     action:@"Continue"
                     inView:self.view
                   onSubmit:^(NSString *token){
        TGLoginViewController *me = weakSelf;
        [TGAlertSheet showChoices:@[@"Log In", @"Dismiss It"]
                            title:@"Web Login Token"
                     destructiveIndex:1
                           inView:me.view
                         onChoice:^(NSInteger index){
            if (index == 1){
                [[TGClient shared] dismissWebToken:token completion:^(NSString *error){
                    [TGAlertSheet showMessage:(error
                            ?: @"The token was dropped. The web login stops waiting.")
                                        title:@"Web Login Token" inView:me.view];
                }];
                return;
            }
            [TGAlertSheet showInput:@"Datacenter"
                            message:@"The dc_id the web login names, usually 2."
                        placeholder:@"dc_id"
                               text:@"2"
                             action:@"Log In"
                             inView:me.view
                           onSubmit:^(NSString *dc){
                NSInteger dcId = [dc integerValue];
                if (dcId <= 0)
                    dcId = 2;
                [[TGClient shared] checkAuthenticationWebToken:token dcId:dcId
                                                    completion:^(NSString *error){
                    [TGAlertSheet showMessage:(error
                            ?: @"Signed in. Telegram is opening the account.")
                                        title:@"Web Login Token" inView:me.view];
                }];
            }];
        }];
    }];
}

/// The other half of QR login: a link from a QR another device shows. The
/// server creates the session, so success is the authorization state that
/// follows; a refusal is said here instead.
- (void)qrLinkTapped {
    __weak typeof(self) weakSelf = self;
    [TGAlertSheet showInput:@"QR Link"
                    message:@"Paste the tg:// link the other screen's QR code stands for."
                placeholder:@"tg://login?token=..."
                       text:nil
                     action:@"Confirm"
                     inView:self.view
                   onSubmit:^(NSString *link){
        TGLoginViewController *me = weakSelf;
        [[TGClient shared] confirmQrCodeAuthenticationLink:link completion:^(NSString *error){
            [TGAlertSheet showMessage:(error
                    ?: @"Confirmed. Telegram is signing this device in.")
                                title:@"QR Link" inView:me.view];
        }];
    }];
}

/// The Firebase code arrives as a secret in a push, not as an SMS. There is
/// no verification SDK on this OS, so the sheet asks for the secret; the
/// answer still comes from the server.
- (void)firebaseCodeTapped {
    __weak typeof(self) weakSelf = self;
    [TGAlertSheet showInput:@"Push Verification"
                    message:@"Paste the secret from the verification push notification."
                placeholder:@"Secret"
                       text:nil
                     action:@"Send"
                     inView:self.view
                   onSubmit:^(NSString *token){
        TGLoginViewController *me = weakSelf;
        [[TGClient shared] sendAuthenticationFirebaseSms:token completion:^(NSString *error){
            [TGAlertSheet showMessage:(error
                    ?: @"Telegram accepted the verification. The code is on its way.")
                                title:@"Push Verification" inView:me.view];
        }];
    }];
}

/// Sizes the subtitle to its text and returns where it ends. It was two
/// lines high whatever it said, so "...via SMS to" lost the phone number on
/// the code step, the one line that says where the code went.
- (CGFloat)placeSubtitle {
    return [self placeSubtitleAtY:TGMetricStackTop];
}

- (CGFloat)placeSubtitleAtY:(CGFloat)y {
    CGFloat width = self.view.bounds.size.width - TGDoubled(TGMetricPadWide);
    self.subtitleLabel.numberOfLines = 0;
    CGFloat height = MAX(TGTextHeight(self.subtitleLabel.text, self.subtitleLabel.font, width),
                         TGMetricLoginSubtitleHeight);
    self.subtitleLabel.frame = CGRectMake(TGMetricPadWide, y, width, height);
    return y + height;
}

- (CGFloat)placeErrorAtY:(CGFloat)y width:(CGFloat)width {
    if (self.errorLabel.hidden)
        return y;
    CGFloat height = TGDoubled(TGMetricLineCaption);
    self.errorLabel.frame = CGRectMake(TGMetricGutter, y,
            width - TGDoubled(TGMetricGutter), height);
    return y + height + TGMetricStackStep;
}

- (void)clearError {
    if (self.errorLabel.hidden && !self.errorLabel.text.length)
        return;
    self.errorLabel.text = nil;
    self.errorLabel.hidden = YES;
    [self layoutActiveStep];
}

- (void)clearStepLinks {
    for (UIView *link in self.stepLinks)
        [link removeFromSuperview];
    [self.stepLinks removeAllObjects];
}

/// One ghost link at `y`; returns where the next one goes. A step added after
/// layoutActiveStep ran lands its own frame here; the same geometry pass
/// places every link again from the step's anchor.
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
    self.errorLabel.text = nil;
    self.errorLabel.hidden = YES;
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

    [self useSingleFieldLayout];
    // A keyboard type set on a field that already has focus is ignored until
    // it loses it: the code steps used to open on letters.
    [self.inputField resignFirstResponder];
    self.inputField.text = @"";
    self.inputField.placeholder = placeholder;
    self.inputField.secureTextEntry = secure;
    self.inputField.keyboardType = keyboard;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.actionButton setTitle:button forState:UIControlStateNormal];
    self.nextItem.title = @"Done";
    self.navigationItem.rightBarButtonItem = self.nextItem;
    self.countryLabel.hidden = YES;
    self.expectedCodeLength = 0;

    [self layoutActiveStep];

    [self applyTheme];
    [self updateActionEnabled];
    [self.inputField becomeFirstResponder];
}

@end
