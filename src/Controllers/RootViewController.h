//
// LegacyTG - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//

#import <UIKit/UIKit.h>

@interface RootViewController : UITabBarController

+ (instancetype)standardTabBarController;
- (void)switchToTab:(NSUInteger)tabIndex popToRoot:(BOOL)popToRoot;

/// Tabs run Contacts, Calls, Chats, Settings as in Telegram; Calls is there
/// only when this is on (off by default). Setting it rebuilds the tab bar.
+ (BOOL)showsCallsTab;
+ (void)setShowsCallsTab:(BOOL)shows;

/// Chats moves when Calls comes and goes, so nothing may hard-code its index.
- (UINavigationController *)chatsNavigationController;
- (NSUInteger)chatsTabIndex;

@end
