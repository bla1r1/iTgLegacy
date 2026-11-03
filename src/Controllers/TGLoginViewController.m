#import "TGLoginViewControllerInternal.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGIcons.h"
#import "TGUIFormat.h"

/// The field is what was wrong, so it is the thing that moves: one sideways
/// nudge, no frame change, run by the render server.
static void TGShakeRejectedInput(UIView *view) {
    CAKeyframeAnimation *shake =
            [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[@0.0f, @-8.0f, @8.0f, @-5.0f, @5.0f, @0.0f];
    shake.duration = TGAnimationDurationSlow;
    shake.timingFunction = [CAMediaTimingFunction
            functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:shake forKey:@"tg.errorShake"];
}

@implementation TGLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Your Phone";

    self.nextItem = [[UIBarButtonItem alloc] initWithTitle:@"Next"
                                                     style:UIBarButtonItemStyleDone
                                                    target:self
                                                    action:@selector(actionButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.nextItem;

    [self setupUI];
    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:TGThemeChangedNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    // viewDidLayoutSubviews carries most devices through a rotation; this
    // notification catches the iOS 6 and 7 passes that once didn't call it.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layoutActiveStep)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
}

- (void)dealloc {
    [self.resendTimer invalidate];
    self.resendTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutActiveStep];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)setupUI {
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;

    self.view.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                       UIViewAutoresizingFlexibleHeight;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.alwaysBounceVertical = YES;
    if ([self.scrollView respondsToSelector:@selector(setKeyboardDismissMode:)]) {
        self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    }
    [self.view addSubview:self.scrollView];

    // The stack, added up rather than written out. Every y below is the one
    // before it plus a step, which is what makes the rhythm one value.
    CGFloat inner = width - TGDoubled(TGMetricGutter);
    CGFloat wide  = width - TGDoubled(TGMetricPadWide);
    CGFloat y = TGMetricStackTop;

    // The sign-in screen is the app's first screen, so it says whose it is:
    // the same paper plane and wordmark Telegram opens with, drawn from the
    // icon set rather than shipped as bitmap art.
    self.brandLogoView = [[UIImageView alloc] initWithFrame:
            CGRectMake(TGCenteredOrigin(width, TGMetricLoginBrandLogo), y,
                       TGMetricLoginBrandLogo, TGMetricLoginBrandLogo)];
    self.brandLogoView.contentMode = UIViewContentModeScaleAspectFit;
    self.brandLogoView.backgroundColor = [UIColor clearColor];
    [self.scrollView addSubview:self.brandLogoView];

    y += TGMetricLoginBrandLogo + TGMetricPad;
    self.brandLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(TGMetricPadWide, y, wide, TGMetricLoginBrandLabel)];
    self.brandLabel.text = @"LegacyTG";
    self.brandLabel.font = TGFontTitle();
    self.brandLabel.textAlignment = NSTextAlignmentCenter;
    self.brandLabel.backgroundColor = [UIColor clearColor];
    [self.scrollView addSubview:self.brandLabel];

    y += TGMetricLoginBrandLabel + TGMetricStackGroup;
    // Clean native iOS 7 subtitle / instructions
    self.subtitleLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(TGMetricPadWide, y, wide, TGMetricLoginSubtitleHeight)];
    self.subtitleLabel.text = @"Please confirm your country code\nand enter your phone number.";
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.font = TGFontSubhead();
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 2;
    [self.scrollView addSubview:self.subtitleLabel];

    // The country and formatting line: Telegram puts the country's name and
    // the number as it would dial it directly under the instructions.
    y += TGMetricLoginSubtitleHeight + TGMetricStackStep;
    self.countryLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(TGMetricPadWide, y, wide, TGMetricLoginCountryLine)];
    self.countryLabel.font = TGFontSubhead();
    self.countryLabel.textAlignment = NSTextAlignmentCenter;
    self.countryLabel.backgroundColor = [UIColor clearColor];
    self.countryLabel.numberOfLines = 1;
    self.countryLabel.hidden = YES;
    [self.scrollView addSubview:self.countryLabel];

    self.errorLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(TGMetricGutter, 0, inner, TGMetricLineCaption)];
    self.errorLabel.font = TGFontCaption();
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.backgroundColor = [UIColor clearColor];
    self.errorLabel.numberOfLines = 2;
    self.errorLabel.hidden = YES;
    [self.scrollView addSubview:self.errorLabel];

    // Grouped input container
    y += TGMetricLoginCountryLine + TGMetricStackStep;
    self.inputContainer = [[UIView alloc] initWithFrame:
            CGRectMake(TGMetricGutter, y, inner, TGMetricRow)];
    self.inputContainer.layer.cornerRadius = TGMetricCornerControl;
    self.inputContainer.layer.borderWidth = TGMetricHairline;
    self.inputContainer.clipsToBounds = YES;
    [self.scrollView addSubview:self.inputContainer];

    // Country code prefix
    self.phonePrefixField = [[UITextField alloc] initWithFrame:
            CGRectMake(TGMetricPadMedium, 0, TGMetricLoginPrefixWidth, TGMetricRow)];
    self.phonePrefixField.text = @"+380";
    self.phonePrefixField.font = TGFontHeader();
    self.phonePrefixField.keyboardType = UIKeyboardTypePhonePad;
    self.phonePrefixField.returnKeyType = UIReturnKeyNext;
    self.phonePrefixField.textAlignment = NSTextAlignmentCenter;
    self.phonePrefixField.delegate = self;
    [self.phonePrefixField addTarget:self action:@selector(prefixFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.phonePrefixField];

    // Hairline vertical separator between prefix and phone number
    self.prefixSeparator = [[UIView alloc] initWithFrame:CGRectMake(
            TGMetricPadMedium + TGMetricLoginPrefixWidth + TGMetricPadTiny,
            TGMetricBubblePadV, TGMetricHairline,
            TGMetricRow - TGDoubled(TGMetricBubblePadV))];
    [self.inputContainer addSubview:self.prefixSeparator];

    // Phone number input field
    CGFloat fieldX = TGMetricPadMedium + TGMetricLoginPrefixWidth + TGMetricPadMedium;
    self.inputField = [[UITextField alloc] initWithFrame:
            CGRectMake(fieldX, 0, inner - fieldX - TGMetricPadMedium, TGMetricRow)];
    self.inputField.placeholder = @"Phone number";
    self.inputField.font = TGFontInput();
    // iOS 6 sets a field's text against its top edge unless told otherwise;
    // in a 44 pt row the code and password sat a third of the way down.
    self.inputField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.phonePrefixField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.inputField.keyboardType = UIKeyboardTypePhonePad;
    self.inputField.returnKeyType = UIReturnKeyGo;
    self.inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.inputField.delegate = self;
    [self.inputField addTarget:self action:@selector(inputFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.inputField];

    // Action button ("Next")
    self.actionButton = [TGButton buttonWithTitle:@"Next" variant:TGButtonVariantPrimary size:TGButtonSizeLarge];
    y += TGMetricRow + TGMetricStackStep;
    // One control height, not 44 for the field and 42 for the button under it.
    self.actionButton.frame = CGRectMake(TGMetricGutter, y, inner, TGMetricRow);
    [self.actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.actionButton];

    // Activity spinner inside action button
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.center = CGPointMake(TGHalf(inner), TGHalf(TGMetricRow));
    self.spinner.hidesWhenStopped = YES;
    [self.actionButton addSubview:self.spinner];

    // Log in with QR Code button
    self.qrCodeButton = [TGButton buttonWithTitle:@"Log in with QR Code" variant:TGButtonVariantGhost size:TGButtonSizeMedium];
    y += TGMetricRow + TGMetricStackStep;
    self.qrCodeButton.frame = CGRectMake(TGMetricGutter, y, inner,
                                         TGMetricLoginLinkHeight);
    [self.qrCodeButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.qrCodeButton];

    y += TGMetricLoginLinkHeight + TGMetricPadLarge;
    self.scrollView.contentSize = CGSizeMake(width, y);
    self.currentStep = TGLoginStepPhone;
    [self updateActionEnabled];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.inputField becomeFirstResponder];
    });
}

- (void)applyTheme {
    TGTheme *theme = [TGTheme shared];

    // Navigation bar
    if (self.navigationController) {
        [theme styleNavigationBar:self.navigationController.navigationBar];
    }
    // iOS 7 reads an item's tint as its text colour; iOS 6 as the colour of
    // the button itself, so white there made white text on a white button.
    // On 6 the items keep the bar's own tint.
    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_6_1) {
        self.nextItem.tintColor = [theme barButtonColour];
        self.navigationItem.leftBarButtonItem.tintColor = [theme barButtonColour];
    }

    // View background
    self.view.backgroundColor = [theme groupedBackgroundColour];

    // Labels
    self.subtitleLabel.textColor = [theme secondaryTextColour];
    self.subtitleLabel.shadowColor = [theme etchedTextShadowColour];
    self.subtitleLabel.shadowOffset = TGMetricShadowOffsetEtched;

    self.brandLabel.textColor = [theme primaryTextColour];
    self.brandLogoView.image = [TGIcons telegramAirplaneOfSide:TGMetricLoginBrandLogo];
    self.countryLabel.textColor = [theme secondaryTextColour];
    self.errorLabel.textColor = [theme destructiveColour];

    // Input container & fields
    self.inputContainer.backgroundColor = [theme cardBackgroundColour];
    self.inputContainer.layer.borderColor = [theme separatorColour].CGColor;
    self.prefixSeparator.backgroundColor = [theme separatorColour];

    self.phonePrefixField.textColor = [theme primaryTextColour];
    self.phonePrefixField.keyboardAppearance = UIKeyboardAppearanceLight;

    self.inputField.textColor = [theme primaryTextColour];
    self.inputField.keyboardAppearance = UIKeyboardAppearanceLight;

    if (self.inputField.placeholder.length) {
        self.inputField.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:self.inputField.placeholder
            attributes:@{ NSForegroundColorAttributeName : [theme placeholderColour] }];
    }

    // Action button
    [self.actionButton setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleAction highlighted:NO height:TGMetricRow] forState:UIControlStateNormal];
    [self.actionButton setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleAction highlighted:YES height:TGMetricRow] forState:UIControlStateHighlighted];
    self.actionButton.backgroundColor = [UIColor clearColor];
    self.actionButton.layer.borderWidth = 0.0f;
    [self.actionButton setTitleColor:[[TGTheme shared] onAccentColour] forState:UIControlStateNormal];

    // Secondary buttons
    [self.qrCodeButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
    if (self.resendButton) {
        [self.resendButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
    }
    if (self.codeStepQrButton) {
        [self.codeStepQrButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
    }

    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
        [self setNeedsStatusBarAppearanceUpdate];
    }
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy) {
        self.errorLabel.text = nil;
        self.errorLabel.hidden = YES;
    }
    self.actionButton.enabled = !busy;
    self.nextItem.enabled = !busy;
    if (busy) {
        self.actionButton.titleLabel.alpha = TGAlphaTransparent;
        [self.spinner startAnimating];
    } else {
        self.actionButton.titleLabel.alpha = TGAlphaOpaque;
        [self.spinner stopAnimating];
    }
    [self updateActionEnabled];
}

/// Whether the current field holds enough to be sent. Telegram keeps the
/// button inactive until it does; a disabled Next is the only error a number
/// that is still being typed needs.
- (BOOL)canSubmitCurrentStep {
    NSString *text = [self.inputField.text
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *digits = [text stringByReplacingOccurrencesOfString:@"\\D"
            withString:@"" options:NSRegularExpressionSearch
            range:NSMakeRange(0, text.length)];
    switch (self.currentStep) {
        case TGLoginStepPhone:
            return digits.length >= 4;
        case TGLoginStepCode:
        case TGLoginStepEmailCode:
        case TGLoginStepRecoveryCode:
            return digits.length >= 4;
        case TGLoginStepEmail:
            return [text rangeOfString:@"@"].location != NSNotFound &&
                   [text rangeOfString:@"."].location != NSNotFound;
        default:
            return text.length > 0;
    }
}

- (void)updateActionEnabled {
    BOOL ready = !self.busy && [self canSubmitCurrentStep];
    self.actionButton.enabled = ready;
    self.nextItem.enabled = ready;
    self.inputField.enabled = !self.busy;
    self.phonePrefixField.enabled = !self.busy;
    self.qrCodeButton.enabled = !self.busy;
    self.resendButton.enabled = !self.busy && self.resendCountdown <= 0;
    self.codeStepQrButton.enabled = !self.busy;
    for (UIView *link in self.stepLinks) {
        link.userInteractionEnabled = !self.busy;
        link.alpha = self.busy ? TGAlphaDimmed : TGAlphaOpaque;
    }
}

/// The auth requests for phone, code, password and email answer through the
/// authorization state, not a completion. A wrong code changes nothing, so
/// the spinner is released after a few seconds and the field is usable
/// again; a correct one changes step first and this does nothing.
- (void)releaseBusyIfStepIsStill:(TGLoginStep)step {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
        TGLoginViewController *me = weakSelf;
        if (!me || !me.busy || me.currentStep != step)
            return;
        [me setBusy:NO];
        NSString *sentence = nil;
        switch (step) {
            case TGLoginStepCode:
            case TGLoginStepEmailCode:
            case TGLoginStepRecoveryCode:
                sentence = @"That code was not accepted. Check it and try again.";
                break;
            case TGLoginStepPassword:
                sentence = @"That password was not accepted. Try again.";
                break;
            case TGLoginStepPhone:
                sentence = @"Telegram did not accept that number. Check the country code.";
                break;
            default:
                break;
        }
        if (sentence.length) {
            me.errorLabel.text = sentence;
            me.errorLabel.hidden = NO;
            me.errorLabel.alpha = TGAlphaTransparent;
            __weak typeof(me) weakMe = me;
            [UIView animateWithDuration:TGAnimationDurationFast animations:^{
                weakMe.errorLabel.alpha = TGAlphaOpaque;
            }];
            [me layoutActiveStep];
            TGShakeRejectedInput(me.inputContainer);
            [me.inputField becomeFirstResponder];
        }
    });
}

- (void)actionButtonTapped {
    if (![self canSubmitCurrentStep])
        return;
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    [self setBusy:YES];

    if (self.currentStep == TGLoginStepPhone) {
        NSString *fullPhone = TGUIFormatFullPhone(self.phonePrefixField.text, text);
        self.savedPhoneNumber = fullPhone;
        self.savedNationalNumber = text;
        if (self.onPhoneSubmitted) {
            self.onPhoneSubmitted(fullPhone);
        }
        [self releaseBusyIfStepIsStill:TGLoginStepPhone];
    } else if (self.currentStep == TGLoginStepCode) {
        NSString *cleanCode = [text stringByReplacingOccurrencesOfString:@"\\D" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
        if (self.onCodeSubmitted) {
            self.onCodeSubmitted(cleanCode.length ? cleanCode : text);
        }
        [self releaseBusyIfStepIsStill:TGLoginStepCode];
    } else if (self.currentStep == TGLoginStepPassword) {
        if (self.onPasswordSubmitted) {
            self.onPasswordSubmitted(text);
        }
        [self releaseBusyIfStepIsStill:TGLoginStepPassword];
    } else if (self.currentStep == TGLoginStepEmail) {
        [[TGClient shared] sendEmailAddress:text];
        [self releaseBusyIfStepIsStill:TGLoginStepEmail];
    } else if (self.currentStep == TGLoginStepEmailCode) {
        [[TGClient shared] sendEmailCode:text];
        [self releaseBusyIfStepIsStill:TGLoginStepEmailCode];
    } else if (self.currentStep == TGLoginStepRecoveryCode) {
        __weak typeof(self) weakSelf = self;
        [[TGClient shared] recoverPasswordWithCode:text completion:^(NSString *error){
            TGLoginViewController *me = weakSelf;
            [me setBusy:NO];
            if (error)    // success moves on by the authorization state
                [TGAlertSheet showMessage:error title:@"Recovery Code" inView:me.view];
        }];
    } else if (self.currentStep == TGLoginStepRegister) {
        __weak typeof(self) weakSelf = self;
        [[TGClient shared] registerWithFirstName:text
                                        lastName:self.registrationLastName
                                      completion:^(BOOL ok, NSString *error){
            TGLoginViewController *me = weakSelf;
            [me setBusy:NO];
            if (ok)
                return;   // the authorization state carries the screen on
            [TGAlertSheet showMessage:(error ?: @"Telegram refused that name.")
                                title:@"Your Name" inView:me.view];
        }];
    }
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    CGRect kbFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbFrame.size.height;

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, kbHeight + TGMetricPadMedium, 0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;

    // The keyboard covers the button on a 3.5" screen once the brand block is
    // above the field. Keep the field, not the top of the form, on screen.
    CGRect field = [self.inputField convertRect:self.inputField.bounds
                                         toView:self.scrollView];
    [self.scrollView scrollRectToVisible:CGRectInset(field, 0, -TGMetricPad)
                                animated:YES];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

@end
