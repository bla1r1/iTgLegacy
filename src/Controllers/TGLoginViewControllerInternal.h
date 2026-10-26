#ifndef TGLOGINVIEWCONTROLLERINTERNAL_H
#define TGLOGINVIEWCONTROLLERINTERNAL_H

#import "TGLoginViewController.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

typedef NS_ENUM(NSInteger, TGLoginStep) {
    TGLoginStepPhone,
    TGLoginStepCode,
    TGLoginStepPassword,
    /// A phone number Telegram has never seen: the account is made here, and
    /// before this step existed the code screen simply never moved on.
    TGLoginStepRegister
};

@interface TGLoginViewController ()

@property (nonatomic, assign) TGLoginStep currentStep;
/// The last name typed on the registration step, which is optional and so
/// cannot live in the one input field the step shares with every other.
@property (nonatomic, copy) NSString *registrationLastName;
@property (nonatomic, strong) UIScrollView *scrollView;
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

@property (nonatomic, strong) UILabel *themeSectionLabel;
@property (nonatomic, strong) UISegmentedControl *themeSegmentedControl;
@property (nonatomic, strong) CAGradientLayer *skeuoBgLayer;
@property (nonatomic, strong) CAGradientLayer *skeuoBtnLayer;
@property (nonatomic, strong) UIView *skeuoShineView;

- (void)setupUI;
- (void)applyTheme;
- (void)themeSegmentChanged:(UISegmentedControl *)sender;
- (void)actionButtonTapped;

@end

@interface TGLoginViewController (Phone)

- (BOOL)containsKnownCountryPrefix:(NSString *)digits;
- (void)processPastedPhoneNumber:(NSString *)raw;
- (void)inputFieldChanged:(UITextField *)sender;
- (void)prefixFieldChanged:(UITextField *)sender;

@end

@interface TGLoginViewController (StepsInternal)

- (void)qrCodeButtonTapped;
- (void)useSingleFieldLayout;
- (void)resendTick:(NSTimer *)timer;
- (void)resendButtonTapped;
- (void)resetSessionTapped;
- (UIImage *)generateQRCodeForString:(NSString *)string size:(CGFloat)size;

@end

static inline UIColor *tgRGB(int r, int g, int b) {
    return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

static inline CAGradientLayer *tgGloss(CGRect frame, UIColor *top, UIColor *bottom) {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = frame;
    g.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    return g;
}

#endif // TGLOGINVIEWCONTROLLERINTERNAL_H
