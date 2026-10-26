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

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [TGTheme shared].isDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

- (void)setupUI {
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;

    // Classic skeuomorphic background gradient layer
    self.skeuoBgLayer = tgGloss(self.view.bounds, tgRGB(222, 226, 232), tgRGB(186, 193, 203));
    [self.view.layer insertSublayer:self.skeuoBgLayer atIndex:0];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
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
    self.inputField.keyboardType = UIKeyboardTypePhonePad;
    self.inputField.returnKeyType = UIReturnKeyGo;
    self.inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.inputField.delegate = self;
    [self.inputField addTarget:self action:@selector(inputFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.inputField];

    // Action button ("Next")
    self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    y += TGMetricRow + TGMetricStackStep;
    // One control height, not 44 for the field and 42 for the button under it.
    self.actionButton.frame = CGRectMake(TGMetricGutter, y, inner, TGMetricRow);
    self.actionButton.layer.cornerRadius = TGMetricCornerControl;
    self.actionButton.clipsToBounds = YES;
    [self.actionButton setTitle:@"Next" forState:UIControlStateNormal];
    self.actionButton.titleLabel.font = TGFontRowStrong();
    [self.actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    // Skeuomorphic button gloss layer
    self.skeuoBtnLayer = tgGloss(CGRectMake(0, 0, inner, TGMetricRow),
            tgRGB(92, 156, 210), tgRGB(38, 92, 148));
    [self.actionButton.layer insertSublayer:self.skeuoBtnLayer atIndex:0];

    self.skeuoShineView = [[UIView alloc] initWithFrame:
            CGRectMake(0, 0, inner, TGHalf(TGMetricRow))];
    self.skeuoShineView.backgroundColor = [[TGTheme shared] skeuoShineColour];
    self.skeuoShineView.userInteractionEnabled = NO;
    [self.actionButton addSubview:self.skeuoShineView];

    [self.scrollView addSubview:self.actionButton];

    // Activity spinner inside action button
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.center = CGPointMake(TGHalf(inner), TGHalf(TGMetricRow));
    self.spinner.hidesWhenStopped = YES;
    [self.actionButton addSubview:self.spinner];

    // Log in with QR Code button
    self.qrCodeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    y += TGMetricRow + TGMetricStackStep;
    self.qrCodeButton.frame = CGRectMake(TGMetricGutter, y, inner,
                                         TGMetricLoginLinkHeight);
    [self.qrCodeButton setTitle:@"Log in with QR Code" forState:UIControlStateNormal];
    self.qrCodeButton.titleLabel.font = TGFontBody();
    [self.qrCodeButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.qrCodeButton];

    // Theme Switcher Section
    // A new group, so the larger step.
    y += TGMetricLoginLinkHeight + TGMetricStackGroup;
    self.themeSectionLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(TGMetricPadWide, y, wide, TGMetricPadLarge)];
    self.themeSectionLabel.text = @"THEME";
    self.themeSectionLabel.font = TGFontMicroStrong();
    self.themeSectionLabel.textAlignment = NSTextAlignmentCenter;
    self.themeSectionLabel.backgroundColor = [UIColor clearColor];
    [self.scrollView addSubview:self.themeSectionLabel];

    self.themeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Classic", @"Day", @"Night", @"Night Blue"]];
    y += TGMetricPadLarge + TGMetricPadSmall;
    self.themeSegmentedControl.frame = CGRectMake(TGMetricGutter, y, inner,
                                                  TGMetricLoginLinkHeight);
    [self.themeSegmentedControl addTarget:self action:@selector(themeSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:self.themeSegmentedControl];

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
    self.nextItem.tintColor = [theme barButtonColour];
    if (self.navigationItem.leftBarButtonItem) {
        self.navigationItem.leftBarButtonItem.tintColor = [theme barButtonColour];
    }

    // View background
    if (!theme.isFlat) {
        self.skeuoBgLayer.hidden = NO;
        self.view.backgroundColor = tgRGB(203, 209, 216);
    } else {
        self.skeuoBgLayer.hidden = YES;
        self.view.backgroundColor = [theme groupedBackgroundColour];
    }

    // Labels
    self.subtitleLabel.textColor = [theme secondaryTextColour];
    self.subtitleLabel.shadowColor = [theme etchedTextShadowColour];
    self.subtitleLabel.shadowOffset = TGMetricShadowOffsetEtched;
    self.themeSectionLabel.textColor = [theme secondaryTextColour];

    // Input container & fields
    self.inputContainer.backgroundColor = [theme cardBackgroundColour];
    self.inputContainer.layer.borderColor = [theme separatorColour].CGColor;
    self.prefixSeparator.backgroundColor = [theme separatorColour];

    self.phonePrefixField.textColor = [theme primaryTextColour];
    self.phonePrefixField.keyboardAppearance = theme.isDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;

    self.inputField.textColor = [theme primaryTextColour];
    self.inputField.keyboardAppearance = theme.isDark ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;

    if (self.inputField.placeholder.length) {
        self.inputField.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:self.inputField.placeholder
            attributes:@{ NSForegroundColorAttributeName : [theme placeholderColour] }];
    }

    // Action button
    if (!theme.isFlat) {
        self.skeuoBtnLayer.hidden = NO;
        self.skeuoShineView.hidden = NO;
        self.actionButton.backgroundColor = [UIColor clearColor];
        self.actionButton.layer.borderWidth = TGMetricBorderWidth;
        self.actionButton.layer.borderColor = tgRGB(26, 66, 102).CGColor;
    } else {
        self.skeuoBtnLayer.hidden = YES;
        self.skeuoShineView.hidden = YES;
        self.actionButton.backgroundColor = [theme accentColour];
        self.actionButton.layer.borderWidth = TGMetricBorderNone;
    }
    [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    // Secondary buttons
    [self.qrCodeButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
    if (self.resendButton) {
        [self.resendButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
    }
    if (self.codeStepQrButton) {
        [self.codeStepQrButton setTitleColor:[theme accentColour] forState:UIControlStateNormal];
    }

    // Theme Segmented Control
    self.themeSegmentedControl.tintColor = [theme accentColour];
    NSString *currentTheme = [theme currentThemeId];
    if ([currentTheme isEqualToString:@"classic"]) {
        self.themeSegmentedControl.selectedSegmentIndex = 0;
    } else if ([currentTheme isEqualToString:@"day"]) {
        self.themeSegmentedControl.selectedSegmentIndex = 1;
    } else if ([currentTheme isEqualToString:@"night"]) {
        self.themeSegmentedControl.selectedSegmentIndex = 2;
    } else if ([currentTheme isEqualToString:@"nightblue"]) {
        self.themeSegmentedControl.selectedSegmentIndex = 3;
    } else {
        self.themeSegmentedControl.selectedSegmentIndex = 1;
    }

    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
        [self setNeedsStatusBarAppearanceUpdate];
    }
}

- (void)themeSegmentChanged:(UISegmentedControl *)sender {
    NSString *themeId = @"day";
    switch (sender.selectedSegmentIndex) {
        case 0: themeId = @"classic"; break;
        case 1: themeId = @"day"; break;
        case 2: themeId = @"night"; break;
        case 3: themeId = @"nightblue"; break;
        default: break;
    }
    [[TGTheme shared] selectThemeId:themeId];
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
