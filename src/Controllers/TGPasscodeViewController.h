//
// TGPasscodeViewController.h - Passcode entry and setup controller.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGPasscodeMode) {
	TGPasscodeModeUnlock = 0,
	TGPasscodeModeSetup,
	TGPasscodeModeChange,
	TGPasscodeModeTurnOff
};

@interface TGPasscodeViewController : UIViewController

@property (nonatomic, assign) TGPasscodeMode mode;
@property (nonatomic, copy) void (^onSuccess)(void);
@property (nonatomic, copy) void (^onCancel)(void);

+ (void)presentUnlockIfLocked;

@end
