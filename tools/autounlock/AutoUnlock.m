#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <notify.h>

extern UIImage *_UICreateScreenUIImage(void) __attribute__((weak_import));
#include <dlfcn.h>

static void dismiss_active_alerts(void) {
    Class alertMgrClass = objc_getClass("SBAlertItemsController");
    if (alertMgrClass) {
        id mgr = [alertMgrClass performSelector:@selector(sharedInstance)];
        if (mgr) {
            if ([mgr respondsToSelector:@selector(visibleAlertItem)]) {
                id vis = [mgr performSelector:@selector(visibleAlertItem)];
                if (vis) {
                    NSLog(@"[AutoUnlock] Found visible alert item: %@", vis);
                    if ([mgr respondsToSelector:@selector(deactivateAlertItem:)]) {
                        [mgr performSelector:@selector(deactivateAlertItem:) withObject:vis];
                        NSLog(@"[AutoUnlock] Deactivated visible alert item");
                    }
                }
            }
            if ([mgr respondsToSelector:@selector(deactivateAlertForMenuClickOrSystemGestureWithAnimation:)]) {
                typedef BOOL (*DeactFn)(id, SEL, BOOL);
                DeactFn fn = (DeactFn)[mgr methodForSelector:@selector(deactivateAlertForMenuClickOrSystemGestureWithAnimation:)];
                fn(mgr, @selector(deactivateAlertForMenuClickOrSystemGestureWithAnimation:), NO);
            }
        }
    }
}

static dispatch_source_t s_record_timer = NULL;
static int s_record_frame_index = 0;
static int s_record_max_frames = 0;

static void stop_recording(void) {
    if (s_record_timer) {
        dispatch_source_cancel(s_record_timer);
        s_record_timer = NULL;
    }
    FILE *f = fopen("/tmp/cap/done.txt", "w");
    if (f) {
        fprintf(f, "%d\n", s_record_frame_index);
        fclose(f);
    }
    NSLog(@"[AutoUnlock] Screen recording stopped. Total frames: %d", s_record_frame_index);
}

static void start_recording(int fps, int max_seconds) {
    stop_recording();
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:@"/tmp/cap" error:nil];
    [fm createDirectoryAtPath:@"/tmp/cap" withIntermediateDirectories:YES attributes:nil error:nil];
    s_record_frame_index = 0;
    if (fps <= 0) fps = 10;
    if (max_seconds <= 0) max_seconds = 5;
    s_record_max_frames = fps * max_seconds;

    NSLog(@"[AutoUnlock] Starting screen recording at %d fps for %d seconds (%d frames max)", fps, max_seconds, s_record_max_frames);

    uint64_t interval = (uint64_t)(1000000000ULL / fps);
    s_record_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(s_record_timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, 5000000ULL);

    dispatch_source_set_event_handler(s_record_timer, ^{
        if (s_record_frame_index >= s_record_max_frames) {
            stop_recording();
            return;
        }
        @autoreleasepool {
            if (_UICreateScreenUIImage != NULL) {
                UIImage *img = _UICreateScreenUIImage();
                if (img) {
                    NSData *jpeg = UIImageJPEGRepresentation(img, 0.75f);
                    if (jpeg) {
                        char path[128];
                        snprintf(path, sizeof(path), "/tmp/cap/frame_%04d.jpg", s_record_frame_index++);
                        [jpeg writeToFile:[NSString stringWithUTF8String:path] atomically:NO];
                    }
                }
            }
        }
    });
    dispatch_resume(s_record_timer);
}

static void do_screenshot(void) {
    NSLog(@"[AutoUnlock] do_screenshot triggered!");
    dismiss_active_alerts();
    
    if (_UICreateScreenUIImage != NULL) {
        UIImage *img = _UICreateScreenUIImage();
        if (img) {
            NSData *png = UIImagePNGRepresentation(img);
            if (png && png.length > 0) {
                [png writeToFile:@"/var/mobile/screenshot.png" atomically:YES];
                NSLog(@"[AutoUnlock] _UICreateScreenUIImage wrote %lu bytes to /var/mobile/screenshot.png", (unsigned long)png.length);
            }
        }
    }
}

static void do_unlock(BOOL launchApp) {
    NSLog(@"[AutoUnlock] do_unlock triggered (launchApp=%d)!", launchApp);
    
    // 0. Dismiss any SIM / system alert
    dismiss_active_alerts();
    
    // 1. Wake screen via SBBacklightController
    Class backClass = objc_getClass("SBBacklightController");
    if (backClass) {
        id back = [backClass performSelector:@selector(sharedInstance)];
        if (back) {
            if ([back respondsToSelector:@selector(turnOnScreenFullyWithBacklightSource:)]) {
                typedef void (*TurnOnFn)(id, SEL, int);
                TurnOnFn fn = (TurnOnFn)[back methodForSelector:@selector(turnOnScreenFullyWithBacklightSource:)];
                fn(back, @selector(turnOnScreenFullyWithBacklightSource:), 0);
                NSLog(@"[AutoUnlock] turnOnScreenFullyWithBacklightSource:0 called");
            }
            if ([back respondsToSelector:@selector(setIdleTimerDisabled:forReason:)]) {
                typedef void (*IdleFn)(id, SEL, BOOL, id);
                IdleFn fn = (IdleFn)[back methodForSelector:@selector(setIdleTimerDisabled:forReason:)];
                fn(back, @selector(setIdleTimerDisabled:forReason:), YES, @"iTgDev");
                NSLog(@"[AutoUnlock] idleTimerDisabled:YES set");
            }
            if ([back respondsToSelector:@selector(resetIdleTimer)]) {
                [back performSelector:@selector(resetIdleTimer)];
            }
            if ([back respondsToSelector:@selector(animateBacklightToFactor:duration:source:completion:)]) {
                typedef void (*BacklightFn)(id, SEL, float, double, int, id);
                BacklightFn fn = (BacklightFn)[back methodForSelector:@selector(animateBacklightToFactor:duration:source:completion:)];
                fn(back, @selector(animateBacklightToFactor:duration:source:completion:), 1.0f, 0.2, 0, nil);
            }
        }
    }
    
    // 2. Unlock lock screen via SBLockScreenManager
    BOOL isLocked = YES;
    Class lockMgrClass = objc_getClass("SBLockScreenManager");
    if (lockMgrClass) {
        id mgr = [lockMgrClass performSelector:@selector(sharedInstance)];
        if (mgr) {
            if ([mgr respondsToSelector:@selector(isUILocked)]) {
                typedef BOOL (*LockedFn)(id, SEL);
                LockedFn lfn = (LockedFn)[mgr methodForSelector:@selector(isUILocked)];
                isLocked = lfn(mgr, @selector(isUILocked));
            }
            if (isLocked) {
                SEL selUnlock = @selector(unlockUIFromSource:withOptions:);
                if ([mgr respondsToSelector:selUnlock]) {
                    typedef void (*UnlockFn)(id, SEL, int, id);
                    UnlockFn fn = (UnlockFn)[mgr methodForSelector:selUnlock];
                    fn(mgr, selUnlock, 0, nil);
                    NSLog(@"[AutoUnlock] unlockUIFromSource:0 withOptions:nil executed!");
                }
            } else {
                NSLog(@"[AutoUnlock] Screen is already unlocked, skipping unlockUIFromSource");
            }
        }
    }
    
    // 3. Fallback for iOS 6 / legacy AwayController
    if (isLocked) {
        Class awayClass = objc_getClass("SBAwayController");
        if (awayClass) {
            id away = [awayClass performSelector:@selector(sharedAwayController)];
            if (away && [away respondsToSelector:@selector(unlockWithSound:)]) {
                typedef void (*AwayFn)(id, SEL, BOOL);
                AwayFn fn = (AwayFn)[away methodForSelector:@selector(unlockWithSound:)];
                fn(away, @selector(unlockWithSound:), NO);
                NSLog(@"[AutoUnlock] SBAwayController unlockWithSound:NO executed!");
            }
        }
    }

    // 4. If requested, launch/activate app via [UIApplication openURL:]
    if (launchApp) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            dismiss_active_alerts();
            NSString *targetUrl = @"itglegacy://";
            NSString *customUrl = [NSString stringWithContentsOfFile:@"/tmp/itg_url.txt" encoding:NSUTF8StringEncoding error:nil];
            if (customUrl.length > 0) {
                targetUrl = [customUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/itg_url.txt" error:nil];
            }
            NSLog(@"[AutoUnlock] Attempting openURL: %@", targetUrl);
            typedef int (*SBSLaunchFn)(CFStringRef, Boolean);
            SBSLaunchFn sbsLaunch = (SBSLaunchFn)dlsym(RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");
            if (sbsLaunch) {
                sbsLaunch(CFSTR("org.legacy.itg"), false);
            }
            UIApplication *app = [UIApplication sharedApplication];
            if (app) {
                BOOL ok = [app openURL:[NSURL URLWithString:targetUrl]];
                NSLog(@"[AutoUnlock] [UIApplication sharedApplication] openURL:%@ returned %d", targetUrl, ok);
                if (!ok && [targetUrl isEqualToString:@"itglegacy://"]) {
                    ok = [app openURL:[NSURL URLWithString:@"telegram://"]];
                    NSLog(@"[AutoUnlock] fallback openURL:telegram:// returned %d", ok);
                }
            } else {
                NSLog(@"[AutoUnlock] UIApplication sharedApplication is nil!");
            }
        });
    }
}

static void on_unlock_notify(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notif = (__bridge NSString *)name;
    NSLog(@"[AutoUnlock] Darwin notification received: %@", notif);
    if ([notif isEqualToString:@"org.legacy.itg.screenshot"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            do_screenshot();
        });
        return;
    }
    if ([notif isEqualToString:@"org.legacy.itg.record_start"]) {
        int fps = 10;
        int duration = 5;
        FILE *f = fopen("/tmp/cap_cfg.txt", "r");
        if (f) {
            if (fscanf(f, "%d %d", &fps, &duration) != 2) {
                fps = 10; duration = 5;
            }
            fclose(f);
            unlink("/tmp/cap_cfg.txt");
        }
        start_recording(fps, duration);
        return;
    }
    if ([notif isEqualToString:@"org.legacy.itg.record_stop"]) {
        stop_recording();
        return;
    }
    BOOL launch = [notif isEqualToString:@"org.legacy.itg.launch"];
    dispatch_async(dispatch_get_main_queue(), ^{
        do_unlock(launch);
    });
}

// Swizzle SBAlertItemsController activateAlertItem: to block SIM and Carrier alerts
static void (*orig_activateAlertItem)(id, SEL, id) = NULL;
static void my_activateAlertItem(id self, SEL _cmd, id item) {
    if (item) {
        NSString *cls = NSStringFromClass([item class]);
        if ([cls rangeOfString:@"SIM" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [cls rangeOfString:@"Carrier" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSLog(@"[AutoUnlock] Suppressed SIM/Carrier alert item: %@", cls);
            return;
        }
    }
    if (orig_activateAlertItem) {
        orig_activateAlertItem(self, _cmd, item);
    }
}

__attribute__((constructor))
static void auto_unlock_init(void) {
    NSString *proc = [[NSProcessInfo processInfo] processName];
    NSLog(@"[AutoUnlock] Injected into process: %@", proc);
    if (![proc isEqualToString:@"SpringBoard"]) {
        return;
    }
    
    // Swizzle activateAlertItem: to permanently block SIM popups
    Class alertMgrClass = objc_getClass("SBAlertItemsController");
    if (alertMgrClass) {
        Method m = class_getInstanceMethod(alertMgrClass, @selector(activateAlertItem:));
        if (m) {
            orig_activateAlertItem = (void (*)(id, SEL, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)my_activateAlertItem);
            NSLog(@"[AutoUnlock] Successfully swizzled SBAlertItemsController activateAlertItem:");
        }
    }
    
    // Listen for custom triggers from SSH
    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin, NULL, on_unlock_notify, CFSTR("org.legacy.itg.unlock"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin, NULL, on_unlock_notify, CFSTR("org.legacy.itg.launch"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin, NULL, on_unlock_notify, CFSTR("org.legacy.itg.screenshot"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin, NULL, on_unlock_notify, CFSTR("org.legacy.itg.record_start"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin, NULL, on_unlock_notify, CFSTR("org.legacy.itg.record_stop"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Automatically unlock after SpringBoard finishes bootstrap
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        do_unlock(NO);
    });
}
