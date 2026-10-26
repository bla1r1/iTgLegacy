//
// LegacyTG - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//
#import "AppDelegate.h"
#import "AppDelegate+URL.h"
#import "RootViewController.h"
#import "TGNavController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGCall.h"
#import "TGCallViewController.h"
#import "TGLoginViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "TGAlertSheet.h"
#include <stdio.h>

@implementation AppDelegate

+ (AppDelegate *)sharedDelegate {
	return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

/// An incoming call is the one thing that takes over the screen on its own.
static void TGWatchForIncomingCalls(void) {
	[TGCall shared].onIncomingCall = ^(int64_t userId, int32_t callId){
		dispatch_async(dispatch_get_main_queue(), ^{
			[TGCallViewController presentForUserId:userId
											  name:[[TGClient shared] nameForUserId:userId]
										  outgoing:NO];
		});
	};
}

- (BOOL)application:(UIApplication *)application
		didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *cacheDir = paths.firstObject;

	// Direct diagnostics log to file so crashes persist for analysis
	NSString *logPath = [cacheDir stringByAppendingPathComponent:@"log.txt"];
	NSString *prevLogPath = [cacheDir stringByAppendingPathComponent:@"lastlog.txt"];
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:prevLogPath error:nil];
	[fm copyItemAtPath:logPath toPath:prevLogPath error:nil];
	[fm removeItemAtPath:logPath error:nil];
	self.log = freopen(logPath.UTF8String, "a+", stderr);

	NSLog(@"[LegacyTG] Starting application...");
	TGWatchForIncomingCalls();

	application.applicationIconBadgeNumber = 0;
	self.showNotifications = [[NSUserDefaults standardUserDefaults] boolForKey:@"showNotifications"];

	[fm changeCurrentDirectoryPath:[[NSBundle mainBundle] bundlePath]];

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"hasAuthorizedSession"]) {
		[self showMainUI];
	} else {
		[self showLoadingUI];
	}
	[self.window makeKeyAndVisible];

	[self startTDLib];

	return YES;
}

#pragma mark - TDLib

- (void)applicationDidBecomeActive:(UIApplication *)application {
	[[TGTheme shared] applyAutoNightIfDue];

	static NSTimer *nightTimer = nil;
	if (!nightTimer)
		nightTimer = [NSTimer scheduledTimerWithTimeInterval:3600
				target:[TGTheme shared] selector:@selector(applyAutoNightIfDue)
			  userInfo:nil repeats:YES];
}

- (void)startTDLib {
	TGClient *tg = [TGClient shared];
	__weak typeof(self) weakSelf = self;

	tg.onAuthState = ^(TGAuthState state){
		dispatch_async(dispatch_get_main_queue(), ^{
			AppDelegate *me = weakSelf;
			if (!me)
				return;

			switch (state){
				case TGAuthStateWaitPhoneNumber:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me showLoginUI];
					[me.loginVC setBusy:NO];
					[me.loginVC showPhoneStep];
					break;
				case TGAuthStateWaitCode: {
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me showLoginUI];
					NSString *phone = me.currentPhoneNumber;
					if (!phone.length) {
						phone = [[TGClient shared].codeInfo objectForKey:@"phone_number"];
					}
					if (!phone.length) {
						NSLog(@"AppDelegate: WaitCode but phone is empty! Showing phone step.");
						[me.loginVC showPhoneStep];
					} else {
						[me.loginVC showCodeStepWithPhoneNumber:phone];
					}
					break;
				}
				case TGAuthStateWaitPassword:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me showLoginUI];
					[me.loginVC showPasswordStep];
					break;
				case TGAuthStateWaitOtherDeviceConfirmation:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me showLoginUI];
					[me.loginVC showQRCodeStepWithLink:[TGClient shared].qrCodeLink];
					break;
				case TGAuthStateReady:
					[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"hasAuthorizedSession"];
					[me.loginVC setBusy:NO];
					[me showMainUI];
					break;
				case TGAuthStateClosed:
				case TGAuthStateLoggingOut:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me showLoginUI];
					break;
				default:
					break;
			}
		});
	};

	tg.onError = ^(NSString *msg){
		dispatch_async(dispatch_get_main_queue(), ^{
			AppDelegate *me = weakSelf;
			[me.loginVC setBusy:NO];
			[me showMessage:msg];
		});
	};

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (![tg start])
			NSLog(@"TDLib unavailable - libtdjson.dylib missing or unloadable");
	});
}

#pragma mark - screens

- (void)showLoadingUI {
	UIViewController *vc = [[UIViewController alloc] init];
	TGTheme *theme = [TGTheme shared];
	vc.view.backgroundColor = [theme listBackgroundColour];

	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:theme.isDark
					? UIActivityIndicatorViewStyleWhite
					: UIActivityIndicatorViewStyleGray];
	spinner.center = CGPointMake(vc.view.bounds.size.width / 2,
								 vc.view.bounds.size.height / 2);
	spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleRightMargin |
			UIViewAutoresizingFlexibleTopMargin |
			UIViewAutoresizingFlexibleBottomMargin;
	[spinner startAnimating];
	[vc.view addSubview:spinner];

	[self.window setRootViewController:vc];
}

- (void)showMainUI {
	if (!self.rootViewController)
		self.rootViewController = [[RootViewController alloc] init];
	if (self.window.rootViewController != self.rootViewController){
		self.loginVC = nil;
		[self.window setRootViewController:self.rootViewController];
	}
}

- (void)showLoginUI {
	if (self.loginVC)
		return;

	TGLoginViewController *loginVC = [[TGLoginViewController alloc] init];
	self.loginVC = loginVC;

	__weak typeof(self) weakSelf = self;
	loginVC.onPhoneSubmitted = ^(NSString *phoneNumber) {
		weakSelf.currentPhoneNumber = phoneNumber;
		[[TGClient shared] sendPhoneNumber:phoneNumber];
	};
	loginVC.onCodeSubmitted = ^(NSString *code) {
		[[TGClient shared] sendCode:code];
	};
	loginVC.onPasswordSubmitted = ^(NSString *password) {
		[[TGClient shared] sendPassword:password];
	};
	loginVC.onResendCode = ^{
		[[TGClient shared] resendAuthenticationCode];
	};
	loginVC.onRequestQRCode = ^{
		[[TGClient shared] requestQrCodeAuthentication];
	};
	loginVC.onResetSession = ^{
		weakSelf.currentPhoneNumber = nil;
		[[TGClient shared] destroySession];
	};

	UINavigationController *nav =
		[[TGNavController alloc] initWithRootViewController:loginVC];
	[[TGTheme shared] styleNavigationBar:nav.navigationBar];
	[self.window setRootViewController:nav];
	self.rootViewController = nil;
}

- (void)showMessage:(NSString *)msg {
	if (!msg.length) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[TGAlertSheet showMessage:msg title:@"LegacyTG" inView:self.window];
	});
}

@end
