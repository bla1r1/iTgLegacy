#import "TGLoginViewControllerInternal.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGClient.h"

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

    // Clean native iOS 7 subtitle / instructions
    self.subtitleLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(TGMetricPadWide, y, wide, TGMetricLoginSubtitleHeight)];
    self.subtitleLabel.text = @"Please confirm your country code\nand enter your phone number.";
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.font = TGFontSubhead();
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 2;
    [self.scrollView addSubview:self.subtitleLabel];

    // Grouped input container
    y += TGMetricLoginSubtitleHeight + TGMetricStackStep;
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
    [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

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
    self.actionButton.enabled = !busy;
    self.nextItem.enabled = !busy;
    if (busy) {
        self.actionButton.titleLabel.alpha = TGAlphaTransparent;
        [self.spinner startAnimating];
    } else {
        self.actionButton.titleLabel.alpha = TGAlphaOpaque;
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
    } else if (self.currentStep == TGLoginStepEmail) {
        [[TGClient shared] sendEmailAddress:text];
    } else if (self.currentStep == TGLoginStepEmailCode) {
        [[TGClient shared] sendEmailCode:text];
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
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

@end
