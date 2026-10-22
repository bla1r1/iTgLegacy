//
// LegacyTG - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//

#import <UIKit/UIKit.h>

@class TGLoginViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIViewController *rootViewController;
@property (nonatomic, strong) TGLoginViewController *loginVC;

@property (nonatomic, copy) NSString *currentPhoneNumber;
@property (nonatomic, assign) BOOL showNotifications;
@property (nonatomic, assign) FILE *log;

+ (AppDelegate *)sharedDelegate;

- (void)showMainUI;
- (void)showLoginUI;
- (void)showMessage:(NSString *)message;

@end
