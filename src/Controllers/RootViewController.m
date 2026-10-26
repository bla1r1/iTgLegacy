//
// LegacyTG - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//
#import "RootViewController.h"
#import "TGChatListViewController.h"
#import "TGContactsViewController.h"
#import "TGSettingsViewController.h"
#import "TGNavController.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGMusicPlayer.h"
#import "TGStyle.h"

/// Compact navigation bar to maximize vertical space on 3.5" displays.
static const CGFloat kCompactBarHeight = TGMetricCompactBarHeight;

@interface TGCompactNavigationBar : UINavigationBar
@end

@implementation TGCompactNavigationBar
- (CGSize)sizeThatFits:(CGSize)size {
	CGSize fitted = [super sizeThatFits:size];
	fitted.height = kCompactBarHeight;
	return fitted;
}
@end

@interface RootViewController () <UINavigationControllerDelegate>
@end

@implementation RootViewController

+ (instancetype)standardTabBarController {
	return [[self alloc] init];
}

- (void)switchToTab:(NSUInteger)tabIndex popToRoot:(BOOL)popToRoot {
	if (tabIndex >= self.viewControllers.count) return;
	self.selectedIndex = tabIndex;
	if (popToRoot) {
		UIViewController *vc = self.viewControllers[tabIndex];
		if ([vc isKindOfClass:[UINavigationController class]]) {
			[(UINavigationController *)vc popToRootViewControllerAnimated:NO];
		}
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];

	TGChatListViewController *chats = [[TGChatListViewController alloc] init];
	UINavigationController *chatsNC =
		[[TGNavController alloc] initWithRootViewController:chats];
	chatsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Chats"
														image:[TGIcons chats] tag:0];

	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	UINavigationController *contactsNC =
		[[TGNavController alloc] initWithRootViewController:contacts];
	contactsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Contacts"
														   image:[TGIcons contacts] tag:1];

	UINavigationController *settingsNC =
		[[TGNavController alloc] initWithNavigationBarClass:[TGCompactNavigationBar class]
													  toolbarClass:nil];
	[settingsNC setViewControllers:@[[[TGSettingsViewController alloc] init]]];
	settingsNC.delegate = self;
	settingsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
														   image:[TGIcons settings] tag:2];

	// From iOS 7 their tab bar draws the other tabs as outlines and only the
	// selected one filled; before that the bar's own glow marks the selection.
	if ([chatsNC.tabBarItem respondsToSelector:@selector(setSelectedImage:)]){
		chatsNC.tabBarItem.image = [TGIcons chatsOutline];
		chatsNC.tabBarItem.selectedImage = [TGIcons chats];
		contactsNC.tabBarItem.image = [TGIcons contactsOutline];
		contactsNC.tabBarItem.selectedImage = [TGIcons contacts];
		settingsNC.tabBarItem.image = [TGIcons settingsOutline];
		settingsNC.tabBarItem.selectedImage = [TGIcons settings];
	}

	[self setViewControllers:@[chatsNC, contactsNC, settingsNC] animated:NO];
	[self setSelectedIndex:0];

	[[TGTheme shared] styleTabBar:self.tabBar];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
													  object:nil
													   queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *note) {
		[[TGTheme shared] styleTabBar:weakSelf.tabBar];
	}];
}

#pragma mark - lock screen

- (BOOL)canBecomeFirstResponder { return YES; }

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self becomeFirstResponder];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
	if (event.type != UIEventTypeRemoteControl)
		return;
	TGMusicPlayer *music = [TGMusicPlayer shared];
	switch (event.subtype){
		case UIEventSubtypeRemoteControlPlay:
		case UIEventSubtypeRemoteControlPause:
		case UIEventSubtypeRemoteControlTogglePlayPause:
			[music togglePlayPause];
			break;
		case UIEventSubtypeRemoteControlNextTrack:
			[music next];
			break;
		case UIEventSubtypeRemoteControlPreviousTrack:
			[music previous];
			break;
		case UIEventSubtypeRemoteControlStop:
			[music stop];
			break;
		default:
			break;
	}
}

@end

// vim:ft=objc
