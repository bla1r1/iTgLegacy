//
// iTgLegacy - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//

#import <UIKit/UIKit.h>

@interface RootViewController : UITabBarController

+ (instancetype)standardTabBarController;
- (void)switchToTab:(NSUInteger)tabIndex popToRoot:(BOOL)popToRoot;

@end
