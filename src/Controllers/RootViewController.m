//
// iTgLegacy - Telegram client for legacy iOS
// Copyright (C) 2026 Blair <dimazzzzz342@gmail.com>
// Licensed under GNU General Public License v3.0
//
#import "RootViewController.h"
#import "TGChatListViewController.h"
#import "TGContactsViewController.h"
#import "TGSettingsViewController.h"
#import "TGIcons.h"
#import "TGTheme.h"
#import "TGMusicPlayer.h"

/// A 3.5-inch screen is 480pt tall and the bars take 108 of it. The settings
/// pages carry a short title and a back button and nothing else, so the bar
/// gives back twelve of those points and hides itself on the way down the
/// list; the root page, which has neither, drops it entirely.
static const CGFloat kCompactBarHeight = 32.0f;

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
		[[UINavigationController alloc] initWithRootViewController:chats];
	chatsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Chats"
														image:[TGIcons chats] tag:0];

	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	UINavigationController *contactsNC =
		[[UINavigationController alloc] initWithRootViewController:contacts];
	contactsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Contacts"
														   image:[TGIcons contacts] tag:1];

	UINavigationController *settingsNC =
		[[UINavigationController alloc] initWithNavigationBarClass:[TGCompactNavigationBar class]
													  toolbarClass:nil];
	[settingsNC setViewControllers:@[[[TGSettingsViewController alloc] init]]];
	settingsNC.delegate = self;
	settingsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
														   image:[TGIcons settings] tag:2];

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

/// The root settings page has no title and no back button - it is a tab root -
/// so the bar there is forty-four points of nothing. Deciding it here rather
/// than in each screen's viewWillAppear means a page pushed from settings does
/// not have to remember to put the bar back.
- (void)navigationController:(UINavigationController *)nc
	  willShowViewController:(UIViewController *)controller
					animated:(BOOL)animated
{
	BOOL isSettingsRoot = [controller isKindOfClass:[TGSettingsViewController class]] &&
			((TGSettingsViewController *)controller).page == TGSettingsPageRoot;
	if (nc.navigationBarHidden != isSettingsRoot)
		[nc setNavigationBarHidden:isSettingsRoot animated:animated];
}

@end

// vim:ft=objc
