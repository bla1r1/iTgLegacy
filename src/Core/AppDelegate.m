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
#import "TGStyle.h"
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

static void TGDevCommandNotifyCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	NSString *cmd = [NSString stringWithContentsOfFile:@"/tmp/itg_cmd.txt" encoding:NSUTF8StringEncoding error:nil];
	if (!cmd.length) return;
	cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSURL *url = [NSURL URLWithString:([cmd hasPrefix:@"itglegacy://"] ? cmd : [NSString stringWithFormat:@"itglegacy://%@", cmd])];
	if (url) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AppDelegate *app = (AppDelegate *)[UIApplication sharedApplication].delegate;
			[app application:[UIApplication sharedApplication] handleOpenURL:url];
		});
	}
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

	// Listen for developer automation commands via Darwin notification
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TGDevCommandNotifyCallback, CFSTR("org.legacy.itg.cmd"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	application.applicationIconBadgeNumber = 0;
	self.showNotifications = [[NSUserDefaults standardUserDefaults] boolForKey:@"showNotifications"];

	[fm changeCurrentDirectoryPath:[[NSBundle mainBundle] bundlePath]];

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	[self showMainUI];
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
					[me.loginVC setBusy:NO];
					[me.loginVC showPhoneStep];
					// In dev builds, keep Main UI active so showcase chats are instantly accessible
					[me showMainUI];
					break;
				case TGAuthStateWaitCode: {
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
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
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				}
				case TGAuthStateWaitPassword:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me.loginVC showPasswordStep];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateWaitRegistration:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me.loginVC showRegisterStep];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateWaitOtherDeviceConfirmation:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me.loginVC showQRCodeStepWithLink:[TGClient shared].qrCodeLink];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateReady:
					// Telegram only takes a token for a signed-in account, so
					// the ask waits until there is one.
					[me askForPushToken];
					[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"hasAuthorizedSession"];
					[me.loginVC setBusy:NO];
					[me showMainUI];
					break;
				case TGAuthStateClosed:
				case TGAuthStateLoggingOut:
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"hasAuthorizedSession"];
					[me showMainUI];
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
			if ([msg isEqualToString:@"Unauthorized"] || [msg hasPrefix:@"Unauthorized"]) {
				return;
			}
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
	spinner.center = CGPointMake(TGHalf(vc.view.bounds.size.width),
								 TGHalf(vc.view.bounds.size.height));
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

#pragma mark - push

/// Notifications were never set up at all: the app asked iOS for nothing and
/// handed Telegram nothing, so a closed app was silent however the
/// certificate was configured.
- (void)askForPushToken {
	UIApplication *app = [UIApplication sharedApplication];
	// iOS 8 moved this; on 6 and 7 the types are registered directly.
	if ([app respondsToSelector:@selector(registerForRemoteNotifications)]){
		[app performSelector:@selector(registerForRemoteNotifications)];
		return;
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	[app registerForRemoteNotificationTypes:
			(UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeBadge |
			 UIRemoteNotificationTypeSound)];
#pragma clang diagnostic pop
}

- (void)application:(UIApplication *)application
		didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
	// TDLib wants the token as hex, which is what their own clients send.
	const unsigned char *bytes = deviceToken.bytes;
	NSMutableString *hex = [NSMutableString stringWithCapacity:deviceToken.length * 2];
	for (NSUInteger i = 0; i < deviceToken.length; i++)
		[hex appendFormat:@"%02x", bytes[i]];

	// A production token registered as sandbox is silently never delivered
	// to, so the flag follows the build rather than being guessed.
#ifdef DEBUG
	BOOL sandbox = YES;
#else
	BOOL sandbox = NO;
#endif
	NSLog(@"[LegacyTG] push token %lu bytes, sandbox=%d",
			(unsigned long)deviceToken.length, sandbox);
	[[TGClient shared] registerPushToken:hex sandbox:sandbox completion:^(BOOL ok){
		NSLog(@"[LegacyTG] registerDevice %@", ok ? @"accepted" : @"refused");
	}];
}

- (void)application:(UIApplication *)application
		didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
	// No certificate, no entitlement, or no network: the app works without
	// notifications and says so in the log rather than to the user.
	NSLog(@"[LegacyTG] no push token: %@", error.localizedDescription);
}

/// A notification that arrives while the app is running goes to TDLib, which
/// turns it into the ordinary updates - so the chat list moves at once
/// instead of waiting for the next poll.
- (void)application:(UIApplication *)application
		didReceiveRemoteNotification:(NSDictionary *)userInfo {
	[[TGClient shared] processPushPayload:userInfo];
}

- (void)showMessage:(NSString *)msg {
	if (!msg.length) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[TGAlertSheet showMessage:msg title:@"LegacyTG" inView:self.window];
	});
}

@end
