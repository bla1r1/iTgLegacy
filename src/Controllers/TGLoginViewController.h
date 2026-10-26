#import <UIKit/UIKit.h>

@interface TGLoginViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, copy) void (^onPhoneSubmitted)(NSString *phoneNumber);
@property (nonatomic, copy) void (^onCodeSubmitted)(NSString *code);
@property (nonatomic, copy) void (^onPasswordSubmitted)(NSString *password);
@property (nonatomic, copy) void (^onResendCode)(void);
@property (nonatomic, copy) void (^onRequestQRCode)(void);
@property (nonatomic, copy) void (^onResetSession)(void);

- (void)setBusy:(BOOL)busy;

@end

@interface TGLoginViewController (Steps)

- (void)showPhoneStep;
- (void)showCodeStepWithPhoneNumber:(NSString *)phoneNumber;
- (void)showQRCodeStepWithLink:(NSString *)link;
- (void)showPasswordStep;
/// A number Telegram has never seen stops here until an account is made.
- (void)showRegisterStep;

@end
