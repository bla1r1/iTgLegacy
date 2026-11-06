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
#import "TGPlayerView.h"
#import "TGChatViewController.h"
#if TG_DEV
#import "TGDevModeViewController.h"
#endif


static NSString *const TGShowsCallsTabKey = @"TGShowsCallsTab";
static NSString *const TGCallsTabChangedNotification = @"TGCallsTabChangedNotification";

@interface RootViewController () <UINavigationControllerDelegate, UITabBarControllerDelegate>
@property (nonatomic, strong) TGPlayerMiniBar *playerMiniBar;
@property (nonatomic, strong) UINavigationController *contactsNC;
@property (nonatomic, strong) UINavigationController *callsNC;
@property (nonatomic, strong) UINavigationController *chatsNC;
@property (nonatomic, strong) UINavigationController *settingsNC;
@end

@implementation RootViewController

+ (BOOL)showsCallsTab {
	return [[NSUserDefaults standardUserDefaults] boolForKey:TGShowsCallsTabKey];
}

+ (void)setShowsCallsTab:(BOOL)shows {
	[[NSUserDefaults standardUserDefaults] setBool:shows forKey:TGShowsCallsTabKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGCallsTabChangedNotification
														object:nil];
}

- (UINavigationController *)chatsNavigationController {
	return self.chatsNC;
}

- (NSUInteger)chatsTabIndex {
	NSUInteger index = [self.viewControllers indexOfObject:self.chatsNC];
	return index == NSNotFound ? 0 : index;
}

/// Calls is built the first time it is shown and kept, so switching it off
/// and on again does not drop the list it had loaded.
- (void)applyTabs {
	BOOL calls = [RootViewController showsCallsTab];
	if (calls && !self.callsNC){
		TGSettingsViewController *list = [[TGSettingsViewController alloc] init];
		list.page = TGSettingsPageRecentCalls;
		self.callsNC = [[TGNavController alloc] initWithRootViewController:list];
		self.callsNC.delegate = self;
		self.callsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Calls"
																 image:[TGIcons calls] tag:3];
	}
	UIViewController *selected = self.selectedViewController ?: self.chatsNC;
	NSArray *tabs = calls
			? @[self.contactsNC, self.callsNC, self.chatsNC, self.settingsNC]
			: @[self.contactsNC, self.chatsNC, self.settingsNC];
	[self setViewControllers:tabs animated:NO];
	// styleTabBar paints the items the bar has now; one added later keeps the
	// system's grey glyph unless the bar is painted again.
	[[TGTheme shared] styleTabBar:self.tabBar];
	// The switch lives on the Calls list itself, so turning it off from there
	// lands on Settings, where the Recent Calls row still leads back.
	self.selectedViewController = [tabs containsObject:selected] ? selected : self.settingsNC;
}

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
	self.chatsNC = chatsNC;
	chatsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Chats"
														image:[TGIcons chats] tag:0];

	TGContactsViewController *contacts = [[TGContactsViewController alloc] init];
	UINavigationController *contactsNC =
		[[TGNavController alloc] initWithRootViewController:contacts];
	contactsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Contacts"
														   image:[TGIcons contacts] tag:1];

	// The standard 44 pt bar, like the other two tabs. A 32 pt one here, to win
	// a line on a 3.5" screen, made Settings the only tab whose bar jumped in
	// height and squeezed a Back button drawn for 44.
	UINavigationController *settingsNC =
		[[TGNavController alloc] initWithRootViewController:[[TGSettingsViewController alloc] init]];
	settingsNC.delegate = self;
	chatsNC.delegate = self;
	contactsNC.delegate = self;
	self.delegate = self;
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

	self.contactsNC = contactsNC;
	self.settingsNC = settingsNC;
	[self applyTabs];
	self.selectedViewController = chatsNC;

	[[TGTheme shared] styleTabBar:self.tabBar];

	CGFloat barH = TGMetricPlayerBarHeight;
	CGFloat barY = self.view.bounds.size.height - self.tabBar.bounds.size.height - barH;
	self.playerMiniBar = [TGPlayerMiniBar miniBarWithFrame:CGRectMake(0, barY, self.view.bounds.size.width, barH)];
	self.playerMiniBar.hidden = YES;
	[self.view addSubview:self.playerMiniBar];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGCallsTabChangedNotification
													  object:nil
													   queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *note) {
		[weakSelf applyTabs];
	}];

	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
													  object:nil
													   queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *note) {
		[[TGTheme shared] styleTabBar:weakSelf.tabBar];
	}];

	[[NSNotificationCenter defaultCenter] addObserverForName:TGMusicPlayerChangedNotification
													  object:nil
													   queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *note) {
		[weakSelf updateMiniPlayerLayoutAnimated:YES];
	}];

	[self updateMiniPlayerLayoutAnimated:NO];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (self.playerMiniBar)
		[self placeMiniPlayerOn:[self visibleScreen]];
}

- (UIViewController *)visibleScreen {
	UIViewController *tab = self.selectedViewController;
	return [tab isKindOfClass:UINavigationController.class]
			? [(UINavigationController *)tab topViewController] : tab;
}

/// At the foot of the screen, above the tab bar when there is one. A chat keeps
/// the old height, which clears its composer. It overlays the screen, so a list
/// under it gets the room back or its last row could never be reached.
- (void)placeMiniPlayerOn:(UIViewController *)screen {
	BOOL noTabBar = screen.hidesBottomBarWhenPushed &&
			![screen isKindOfClass:TGChatViewController.class];
	CGFloat barH = TGMetricPlayerBarHeight;
	CGFloat barY = self.view.bounds.size.height - barH -
			(noTabBar ? 0 : self.tabBar.bounds.size.height);
	self.playerMiniBar.frame = CGRectMake(0, barY, self.view.bounds.size.width, barH);

	if ([screen isKindOfClass:UITableViewController.class]){
		UITableView *table = [(UITableViewController *)screen tableView];
		UIEdgeInsets insets = table.contentInset;
		// A list with a bottom inset of its own knows better.
		if (insets.bottom == 0 || insets.bottom == barH){
			insets.bottom = [TGMusicPlayer shared].current ? barH : 0;
			table.contentInset = insets;
			table.scrollIndicatorInsets = insets;
		}
	}
}

- (void)navigationController:(UINavigationController *)nc
	  willShowViewController:(UIViewController *)screen animated:(BOOL)animated {
	[UIView animateWithDuration:animated ? TGAnimationDurationFast : 0 animations:^{
		[self placeMiniPlayerOn:screen];
	}];
}

- (void)navigationController:(UINavigationController *)nc
	   didShowViewController:(UIViewController *)screen animated:(BOOL)animated {
	// A cancelled swipe back ends on a different screen from the one announced.
	[self placeMiniPlayerOn:[self visibleScreen]];
}

- (void)tabBarController:(UITabBarController *)tabs didSelectViewController:(UIViewController *)tab {
	[self placeMiniPlayerOn:[self visibleScreen]];
}

#if TG_DEV
/// Three taps on Chats within 0.5 s of each other. This is the delegate call a tap
/// on the tab already selected still reaches.
- (BOOL)tabBarController:(UITabBarController *)tabs shouldSelectViewController:(UIViewController *)tab {
	static NSInteger taps;
	static CFAbsoluteTime last;
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	BOOL onChats = tab == self.chatsNC;
	taps = onChats && now - last < 0.5 ? taps + 1 : (onChats ? 1 : 0);
	last = now;
	if (taps == 3){
		taps = 0;
		[TGDevModeViewController presentFrom:self];
	}
	return YES;
}
#endif

- (void)updateMiniPlayerLayoutAnimated:(BOOL)animated {
	TGMusicPlayer *player = [TGMusicPlayer shared];
	BOOL shouldShow = (player.current != nil);

	CGFloat barH = TGMetricPlayerBarHeight;
	[self placeMiniPlayerOn:[self visibleScreen]];

	if (shouldShow && self.playerMiniBar.hidden) {
		self.playerMiniBar.hidden = NO;
		[self.playerMiniBar updateState];
		if (animated) {
			self.playerMiniBar.transform = CGAffineTransformMakeTranslation(0, barH);
			[UIView animateWithDuration:TGAnimationDurationFast animations:^{
				self.playerMiniBar.transform = CGAffineTransformIdentity;
			}];
		}
	} else if (!shouldShow && !self.playerMiniBar.hidden) {
		if (animated) {
			[UIView animateWithDuration:TGAnimationDurationFast animations:^{
				self.playerMiniBar.transform = CGAffineTransformMakeTranslation(0, barH);
			} completion:^(BOOL finished) {
				self.playerMiniBar.hidden = YES;
				self.playerMiniBar.transform = CGAffineTransformIdentity;
			}];
		} else {
			self.playerMiniBar.hidden = YES;
		}
	} else if (shouldShow) {
		[self.playerMiniBar updateState];
	}
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
