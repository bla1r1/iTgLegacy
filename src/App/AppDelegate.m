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
#import "TGMemberAvatarStore.h"
#import "TGEmojiStore.h"
#import "TGCustomEmojiStore.h"
#import "TGMessageLayout.h"
#import "TGMusicPlayer.h"
#import "TGVoiceRecorder.h"
#import "TGVideoNoteRecorder.h"
#import "TGCallViewController.h"
#import "TGLoginViewController.h"
#import "TGTermsViewController.h"
#import "TGPasscode.h"
#import "TGPasscodeViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGPerf.h"
#import "TGTextDraw.h"
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

/// The per-slot "this account has signed in" flag. Slot 0 keeps the original
/// key so an existing install's YES survives the update; later slots get their
/// own so switching never reads another account's answer.
static void TGSetAuthorizedSession(BOOL authorized) {
	NSInteger slot = [TGClient activeAccountSlot];
	NSString *key = slot > 0
			? [NSString stringWithFormat:@"hasAuthorizedSession-%ld", (long)slot]
			: @"hasAuthorizedSession";
	[[NSUserDefaults standardUserDefaults] setBool:authorized forKey:key];
}

#if TG_DEV
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
#endif

/// Message text asks for custom emoji pictures through this. The store is
/// main-thread only; a measure made off it draws the same-size stand-in.
static UIImage *TGCustomEmojiFromStore(int64_t emojiId, CGFloat side) {
	if (![NSThread isMainThread])
		return nil;
	return [[TGCustomEmojiStore shared] imageForId:emojiId side:side];
}

- (BOOL)application:(UIApplication *)application
		didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	TGSetCustomEmojiProvider(TGCustomEmojiFromStore);
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
	double launchStart = TGPerfNow();
	TGWatchForIncomingCalls();

#if TG_DEV
	// Listen for developer automation commands via Darwin notification
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TGDevCommandNotifyCallback, CFSTR("org.legacy.itg.cmd"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
#endif

	application.applicationIconBadgeNumber = 0;
	self.showNotifications = [[NSUserDefaults standardUserDefaults] boolForKey:@"showNotifications"];

	// The server moves the unread total while we are backgrounded; the badge
	// follows the update instead of waiting for the next foreground list read.
	[[NSNotificationCenter defaultCenter]
			addObserverForName:TGUnreadTotalChangedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){
		int count = [n.userInfo[@"count"] intValue];
		dispatch_async(dispatch_get_main_queue(), ^{
			[UIApplication sharedApplication].applicationIconBadgeNumber = count;
		});
	}];

	// Service notifications belong to no chat: TDLib asks for a popup, and
	// the window is the only surface that is not somebody's conversation.
	__weak AppDelegate *weakSelf = self;
	[[NSNotificationCenter defaultCenter]
			addObserverForName:TGServiceNotificationReceivedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){
		NSString *text = n.userInfo[@"text"];
		if (!text.length)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf showMessage:text];
		});
	}];

	// Terms that arrive after sign-in have to be accepted before the account
	// goes on; the screen owns that and the id comes with it.
	[[NSNotificationCenter defaultCenter]
			addObserverForName:TGTermsOfServiceReceivedNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf showTermsOfService:n.userInfo];
		});
	}];

	// Switching accounts drops the old account's screens; the resumed client's
	// next auth state is what decides login versus the chat list.
	[[NSNotificationCenter defaultCenter]
			addObserverForName:TGAccountDidSwitchNotification
						object:nil queue:nil
			usingBlock:^(NSNotification *n){
		dispatch_async(dispatch_get_main_queue(), ^{
			AppDelegate *me = weakSelf;
			if (!me)
				return;
			// Keyed by this account's user ids, or playing its media.
			[[TGMemberAvatarStore shared] reset];
			[[TGEmojiStore shared] reset];
			[[TGCustomEmojiStore shared] reset];
			[[TGMusicPlayer shared] stop];
			[[TGVoiceRecorder shared] cancel];
			[[TGVideoNoteRecorder shared] cancel];
			[[TGCall shared] reset];
			me.rootViewController = nil;
			me.loginVC = nil;
			me.currentPhoneNumber = nil;
			[me showLoadingUI];
		});
	}];

	[fm changeCurrentDirectoryPath:[[NSBundle mainBundle] bundlePath]];

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	[self showMainUI];
	[self.window makeKeyAndVisible];

	if ([TGPasscode hasPasscode]) {
		[TGPasscode setLocked:YES];
		[TGPasscodeViewController presentUnlockIfLocked];
	}

	[self startTDLib];
	TGWarmFonts([TGTheme shared].messageFontSize);
	// One line if the launch itself misbehaves; silent when it is healthy.
	TGPerfReport("launch", "didFinishLaunching", launchStart, 300.0);

	return YES;
}

#pragma mark - TDLib

- (void)applicationDidEnterBackground:(UIApplication *)application {
	[TGPasscode noteAppBackgrounded];

	// B13: the close has to finish before iOS suspends us.
	__block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
	void (^finish)(void) = ^{
		if (task == UIBackgroundTaskInvalid)
			return;
		[application endBackgroundTask:task];
		task = UIBackgroundTaskInvalid;
	};
	task = [application beginBackgroundTaskWithExpirationHandler:finish];
	[[TGClient shared] pauseForBackground:finish];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	if ([TGPasscode shouldLockOnForeground]) {
		[TGPasscodeViewController presentUnlockIfLocked];
	}
	[[TGClient shared] resumeFromBackground];
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
					TGSetAuthorizedSession(NO);
					[me.loginVC setBusy:NO];
					[me.loginVC showPhoneStep];
					// In dev builds, keep Main UI active so showcase chats are instantly accessible
					[me showMainUI];
					break;
				case TGAuthStateWaitCode: {
					TGSetAuthorizedSession(NO);
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
					TGSetAuthorizedSession(NO);
					[me.loginVC showPasswordStep];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateWaitEmailAddress:
					TGSetAuthorizedSession(NO);
					[me.loginVC showEmailStep];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateWaitEmailCode:
					TGSetAuthorizedSession(NO);
					[me.loginVC showEmailCodeStep];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateWaitRegistration:
					TGSetAuthorizedSession(NO);
					[me.loginVC showRegisterStep];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateWaitOtherDeviceConfirmation:
					TGSetAuthorizedSession(NO);
					[me.loginVC showQRCodeStepWithLink:[TGClient shared].qrCodeLink];
					if (me.loginVC) [me showLoginUI]; else [me showMainUI];
					break;
				case TGAuthStateReady:
					// Telegram only takes a token for a signed-in account, so
					// the ask waits until there is one.
					[me askForPushToken];
					TGSetAuthorizedSession(YES);
					[me.loginVC setBusy:NO];
					[me showMainUI];
					break;
				case TGAuthStateClosed:
				case TGAuthStateLoggingOut:
					TGSetAuthorizedSession(NO);
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
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
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
		// Already waiting on a scan: TDLib refuses a second request with
		// "unexpected", so the code it gave is shown again instead.
		TGClient *tg = [TGClient shared];
		if (tg.authState == TGAuthStateWaitOtherDeviceConfirmation && tg.qrCodeLink.length) {
			[weakSelf.loginVC showQRCodeStepWithLink:tg.qrCodeLink];
			return;
		}
		[tg requestQrCodeAuthentication];
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
	// The blob names the account it was addressed to. One signed in on this
	// phone handles the notification; a payload for another account is not
	// this client's to process, and the id says so before the updates land.
	[[TGClient shared] pushReceiverOfPayload:userInfo
								  completion:^(BOOL ok, int64_t receiverId){
		int64_t mine = [TGClient shared].pushReceiverId;
		// Only a definite answer for a different account skips the payload;
		// an id TDLib could not read is still worth handing over.
		if (ok && mine && receiverId && mine != receiverId)
			return;
		[[TGClient shared] processPushPayload:userInfo];
	}];
}

- (void)showMessage:(NSString *)msg {
	if (!msg.length) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[TGAlertSheet showMessage:msg title:@"LegacyTG" inView:self.window];
	});
}

/// The terms popup: one screen, one Accept, and the id Telegram sent goes
/// back so the restriction lifts.
- (void)showTermsOfService:(NSDictionary *)info {
	NSString *termsId = info[@"id"];
	if (![termsId isKindOfClass:NSString.class] || !termsId.length)
		return;
	// The update can beat the window by a moment at launch; one retry is
	// enough, and dropping the terms would leave the account restricted.
	if (!self.window){
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC),
				dispatch_get_main_queue(), ^{
			[[AppDelegate sharedDelegate] showTermsOfService:info];
		});
		return;
	}
	UIViewController *top = self.window.rootViewController;
	while (top.presentedViewController)
		top = top.presentedViewController;
	if (!top)
		return;
	// A second update while the sheet is up must not stack another one.
	if ([top isKindOfClass:[UINavigationController class]] &&
		[((UINavigationController *)top).topViewController
				isKindOfClass:[TGTermsViewController class]])
		return;

	TGTermsViewController *terms = [[TGTermsViewController alloc] init];
	terms.termsText = info[@"text"] ?: @"";
	terms.onAccept = ^{
		[[TGClient shared] acceptTermsOfService:termsId completion:nil];
	};
	UINavigationController *nav = [[UINavigationController alloc]
			initWithRootViewController:terms];
	[top presentViewController:nav animated:YES completion:nil];
}

@end
