#import "TGLoginViewControllerInternal.h"

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

    // Clean native iOS 7 subtitle / instructions
    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, width - 40, 34)];
    self.subtitleLabel.text = @"Please confirm your country code\nand enter your phone number.";
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 2;
    [self.scrollView addSubview:self.subtitleLabel];

    // Grouped input container
    self.inputContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 56, width - 30, 44)];
    self.inputContainer.layer.cornerRadius = 8.0f;
    self.inputContainer.layer.borderWidth = 0.5f;
    self.inputContainer.clipsToBounds = YES;
    [self.scrollView addSubview:self.inputContainer];

    // Country code prefix
    self.phonePrefixField = [[UITextField alloc] initWithFrame:CGRectMake(10, 0, 56, 44)];
    self.phonePrefixField.text = @"+380";
    self.phonePrefixField.font = [UIFont boldSystemFontOfSize:17];
    self.phonePrefixField.keyboardType = UIKeyboardTypePhonePad;
    self.phonePrefixField.returnKeyType = UIReturnKeyNext;
    self.phonePrefixField.textAlignment = NSTextAlignmentCenter;
    self.phonePrefixField.delegate = self;
    [self.phonePrefixField addTarget:self action:@selector(prefixFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.phonePrefixField];

    // Hairline vertical separator between prefix and phone number
    self.prefixSeparator = [[UIView alloc] initWithFrame:CGRectMake(68, 7, 0.5f, 30)];
    [self.inputContainer addSubview:self.prefixSeparator];

    // Phone number input field
    self.inputField = [[UITextField alloc] initWithFrame:CGRectMake(78, 0, width - 108, 44)];
    self.inputField.placeholder = @"Phone number";
    self.inputField.font = [UIFont systemFontOfSize:17];
    self.inputField.keyboardType = UIKeyboardTypePhonePad;
    self.inputField.returnKeyType = UIReturnKeyGo;
    self.inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.inputField.delegate = self;
    [self.inputField addTarget:self action:@selector(inputFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainer addSubview:self.inputField];

    // Action button ("Next")
    self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.actionButton.frame = CGRectMake(15, 108, width - 30, 42);
    self.actionButton.layer.cornerRadius = 8.0f;
    self.actionButton.clipsToBounds = YES;
    [self.actionButton setTitle:@"Next" forState:UIControlStateNormal];
    self.actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    // Skeuomorphic button gloss layer
    self.skeuoBtnLayer = tgGloss(CGRectMake(0, 0, width - 30, 42), tgRGB(92, 156, 210), tgRGB(38, 92, 148));
    [self.actionButton.layer insertSublayer:self.skeuoBtnLayer atIndex:0];

    self.skeuoShineView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width - 30, 21)];
    self.skeuoShineView.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
    self.skeuoShineView.userInteractionEnabled = NO;
    [self.actionButton addSubview:self.skeuoShineView];

    [self.scrollView addSubview:self.actionButton];

    // Activity spinner inside action button
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.center = CGPointMake((width - 30) / 2.0f, 21.0f);
    self.spinner.hidesWhenStopped = YES;
    [self.actionButton addSubview:self.spinner];

    // Log in with QR Code button
    self.qrCodeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.qrCodeButton.frame = CGRectMake(15, 154, width - 30, 30);
    [self.qrCodeButton setTitle:@"Log in with QR Code" forState:UIControlStateNormal];
    self.qrCodeButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [self.qrCodeButton addTarget:self action:@selector(qrCodeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.qrCodeButton];

    // Theme Switcher Section
    self.themeSectionLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 190, width - 40, 16)];
    self.themeSectionLabel.text = @"THEME";
    self.themeSectionLabel.font = [UIFont boldSystemFontOfSize:11];
    self.themeSectionLabel.textAlignment = NSTextAlignmentCenter;
    self.themeSectionLabel.backgroundColor = [UIColor clearColor];
    [self.scrollView addSubview:self.themeSectionLabel];

    self.themeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Classic", @"Day", @"Night", @"Night Blue"]];
    self.themeSegmentedControl.frame = CGRectMake(15, 210, width - 30, 30);
    [self.themeSegmentedControl addTarget:self action:@selector(themeSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:self.themeSegmentedControl];

    self.scrollView.contentSize = CGSizeMake(width, 256);
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
    self.subtitleLabel.shadowColor = !theme.isFlat ? [UIColor colorWithWhite:1.0f alpha:0.7f] : [UIColor clearColor];
    self.subtitleLabel.shadowOffset = CGSizeMake(0, 1);
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
        self.actionButton.layer.borderWidth = 1.0f;
        self.actionButton.layer.borderColor = tgRGB(26, 66, 102).CGColor;
    } else {
        self.skeuoBtnLayer.hidden = YES;
        self.skeuoShineView.hidden = YES;
        self.actionButton.backgroundColor = [theme accentColour];
        self.actionButton.layer.borderWidth = 0.0f;
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

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    CGRect kbFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbFrame.size.height;

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, kbHeight + 10, 0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

@end
