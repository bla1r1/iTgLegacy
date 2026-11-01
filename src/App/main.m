//
// LegacyTG - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

static void TGLegacyExceptionHandler(NSException *exception) {
	NSLog(@"UNCAUGHT %@: %@\n%@", exception.name, exception.reason,
		  [exception.callStackSymbols componentsJoinedByString:@"\n"]);
}

int main(int argc, char *argv[]) {
	NSSetUncaughtExceptionHandler(&TGLegacyExceptionHandler);
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
	}
}
