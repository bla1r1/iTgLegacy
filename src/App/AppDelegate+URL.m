#import "AppDelegate+URL.h"

/// The side the debug icon dump draws a sized avatar at - a preview for the
/// gallery, not a size any screen uses.
static const CGFloat kIconDumpSide = 52.0f;
#import "RootViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGSnackbar.h"
#import "TGSearchViewController.h"
#import "TGDeviceViewController.h"
#import "TGSettingsViewController.h"
#import "TGCall.h"
#import "TGCallViewController.h"
#import "TGChatViewController.h"
#import "TGChatListViewController.h"
#import "TGChatListViewControllerInternal.h"
#import "TGChatViewControllerInternal.h"
#import "TGProfileAppearanceViewController.h"
#import "TGEditProfileViewController.h"
#import "TGProfileViewControllerInternal.h"
#import "TGDevShowcase.h"
#import "TGDevModeViewController.h"
#import "TGTopicsViewController.h"
#import "TGGalleryViewController.h"
#import "TGVideoNoteRecorder.h"
#import "TGStoryCameraViewController.h"
#import "TGStoryComposerViewController.h"
#import "TGPlayerView.h"
#import "TGVideoNoteViewController.h"
#import "TGIcons.h"
#import "TGBench.h"
#import "TGLoginViewController.h"
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>

@implementation AppDelegate (URL)

- (UITabBarController *)activeTabBarController {
	UIViewController *root = self.rootViewController ?: self.window.rootViewController;
#if TG_DEV
	// Dev mode sits over the app, so the routes act on what is on screen.
	if ([root.presentedViewController isKindOfClass:[UITabBarController class]])
		return (UITabBarController *)root.presentedViewController;
#endif
	if ([root isKindOfClass:[UITabBarController class]]) {
		return (UITabBarController *)root;
	}
	return nil;
}

#if !TG_DEV

// tg:// and telegram:// links are not followed yet, and nothing else is accepted.
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
	return NO;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
	return NO;
}

#else

#pragma mark - remote control by URL

/// The view currently taking keystrokes, wherever it is in the tree.
- (UIView *)firstResponderUnder:(UIView *)view {
	if (view.isFirstResponder)
		return view;
	for (UIView *sub in view.subviews){
		UIView *found = [self firstResponderUnder:sub];
		if (found)
			return found;
	}
	return nil;
}

/**
 * Automation URL scheme handler for remote UI driving and testing.
 * Supported schemes: legacytg:// and itglegacy://
 */
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
	return [self application:application handleOpenURL:url];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
	NSString *host = url.host;
	NSString *arg = [url.path stringByReplacingOccurrencesOfString:@"/" withString:@""];
	NSLog(@"handleOpenURL: %@", host ?: @"(launch)");

	// itglegacy://devmode[/close] - what three taps on Chats opens.
	if ([host isEqualToString:@"devmode"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *root = self.rootViewController ?: self.window.rootViewController;
			if ([arg isEqualToString:@"close"])
				[root dismissViewControllerAnimated:NO completion:nil];
			else
				[TGDevModeViewController presentFrom:root];
		});
		return YES;
	}

	// itglegacy://tabtaps/<count> - that many taps on the Chats tab, through the
	// tab bar's delegate. An ssh round trip is too slow to make them one by one.
	if ([host isEqualToString:@"tabtaps"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			for (NSInteger i = 0; i < [arg integerValue]; i++)
				[tabs.delegate tabBarController:tabs
					 shouldSelectViewController:tabs.viewControllers.firstObject];
		});
		return YES;
	}

	if ([host isEqualToString:@"phone"] && arg.length){
		self.currentPhoneNumber = arg;
		[[TGClient shared] sendPhoneNumber:arg];
		return YES;
	}

	// itglegacy://loginstep/<password|recovery|email|emailcode|code|qr> - a sign-in
	// step on screen without an account that needs it, for checking layout.
	if ([host isEqualToString:@"loginstep"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[self showLoginUI];
			if ([arg isEqualToString:@"password"]) [self.loginVC showPasswordStep];
			else if ([arg isEqualToString:@"recovery"]) [self.loginVC performSelector:@selector(showRecoveryCodeStep)];
			else if ([arg isEqualToString:@"email"]) [self.loginVC showEmailStep];
			else if ([arg isEqualToString:@"emailcode"]) [self.loginVC showEmailCodeStep];
			else if ([arg isEqualToString:@"qr"]) {
				// The button itself, so the whole path runs: TDLib's request
				// and the state that answers it.
				[self.loginVC showPhoneStep];
				[self.loginVC performSelector:@selector(qrCodeButtonTapped)];
			}
			else [self.loginVC showCodeStepWithPhoneNumber:@"+1 555 0100"];
		});
		return YES;
	}

	// itglegacy://noteplay/<row> - the last recorded note plays at that row of the
	// open chat; noteplay/state logs what the player is doing. A note in a fixture
	// chat has no file to download.
	if ([host isEqualToString:@"noteplay"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			UINavigationController *nc = (UINavigationController *)tabs.selectedViewController;
			TGChatViewController *chat = (TGChatViewController *)nc.topViewController;
			if (![chat isKindOfClass:[TGChatViewController class]])
				return;
			if ([arg isEqualToString:@"state"]){
				NSLog(@"noteplay: state=%ld rate=%.2f at %.1f", (long)chat.videoNotePlayer.playbackState,
						chat.videoNotePlayer.currentPlaybackRate, chat.videoNotePlayer.currentPlaybackTime);
				return;
			}
			if ([arg isEqualToString:@"speed"]){
				[chat cyclePlaybackSpeed];
				return;
			}
			if ([arg isEqualToString:@"toggle"]){
				[chat togglePlayback];
				return;
			}
			[chat playVideoNoteAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
					@"video-note-square-0.mov"] row:[arg integerValue]];
		});
		return YES;
	}

	// itglegacy://ownscreen/<colours|edit> - a screen of your own profile, which
	// changes nothing until something on it is tapped.
	if ([host isEqualToString:@"ownscreen"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			tabs.selectedIndex = tabs.viewControllers.count - 1;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			[nc popToRootViewControllerAnimated:NO];
			UIViewController *screen = [arg isEqualToString:@"colours"]
					? [[TGProfileAppearanceViewController alloc] init]
					: [[TGEditProfileViewController alloc] init];
			screen.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:screen animated:NO];
		});
		return YES;
	}

	// itglegacy://profile/<username|me>[:<tab>] - a public profile, so a check on the
	// device never has to go through somebody's private chat.
	if ([host isEqualToString:@"profile"] && arg.length){
		NSArray *parts = [arg componentsSeparatedByString:@":"];
		void (^open)(int64_t, NSString *) = ^(int64_t chatId, NSString *title){
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!chatId)
					return;
				UITabBarController *tabs = [self activeTabBarController];
				UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
				[nc popToRootViewControllerAnimated:NO];
				TGProfileViewController *profile = [[TGProfileViewController alloc]
						initWithChatId:chatId userId:chatId > 0 ? chatId : 0 title:title];
				profile.hidesBottomBarWhenPushed = YES;
				[nc pushViewController:profile animated:NO];
				if (parts.count > 1)
					[profile mediaTabSelected:parts[1]];
			});
		};
		if ([parts[0] isEqualToString:@"me"])
			open([[TGClient shared].me[@"id"] longLongValue], [TGClient shared].me[@"first_name"]);
		else
			[[TGClient shared] chatWithUsername:parts[0] completion:open];
		return YES;
	}

	// itglegacy://swiperow/<row> - a chat row open on its swipe actions.
	if ([host isEqualToString:@"swiperow"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			UINavigationController *nc = tabs.viewControllers[0];
			if ([nc.topViewController isKindOfClass:[TGChatListViewController class]])
				[(id)nc.topViewController openSwipeActionsAtRow:[arg integerValue]];
		});
		return YES;
	}

	// itglegacy://account/<slot> - switch account without the sheet, for checking
	// that a client closes and reopens on another database.
	if ([host isEqualToString:@"account"] && arg.length){
		dispatch_async(dispatch_get_main_queue(), ^{
			[[TGClient shared] switchToAccountSlot:[arg integerValue]];
		});
		return YES;
	}

	if ([host isEqualToString:@"debug_auth"]){
		NSString *info = [NSString stringWithFormat:@"authState=%ld, chats=%lu, loginVC=%@, rootVC=%@, winRoot=%@",
			(long)[TGClient shared].authState,
			(unsigned long)[TGClient shared].chats.count,
			self.loginVC,
			self.rootViewController,
			self.window.rootViewController];
		[info writeToFile:@"/tmp/auth_debug.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
		return YES;
	}

	if ([host isEqualToString:@"code"] && arg.length){
		NSLog(@"code received (%lu chars)", (unsigned long)arg.length);
		[[TGClient shared] sendCode:arg];
		return YES;
	}

	if ([host isEqualToString:@"dev"] || [host isEqualToString:@"showcase"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[self showMainUI];
			UITabBarController *tabs = [self activeTabBarController];
			if (!tabs) {
				[self showMainUI];
				tabs = [self activeTabBarController];
			}
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = 0;
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];

			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = -7777777LL;
			vc.chatTitle = @"Dev Showcase";
			vc.isGroup = YES;
			vc.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:vc animated:NO];
			NSLog(@"open dev showcase chat directly");
		});
		return YES;
	}

	if ([host isEqualToString:@"password"] && arg.length){
		NSLog(@"password received (%lu chars)", (unsigned long)arg.length);
		[[TGClient shared] sendPassword:arg];
		return YES;
	}

	if ([host isEqualToString:@"dev"] || [host isEqualToString:@"showcase"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = 0;
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];

			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = -7777777LL;
			vc.chatTitle = @"Dev Showcase";
			vc.isGroup = YES;
			vc.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:vc animated:NO];
			NSLog(@"open dev showcase chat directly");
		});
		return YES;
	}

	if ([host isEqualToString:@"tab"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (!tabs) {
				[self showMainUI];
				tabs = [self activeTabBarController];
			}
			NSInteger idx = [arg integerValue];
			if ([tabs isKindOfClass:[RootViewController class]]) {
				[(RootViewController *)tabs switchToTab:(NSUInteger)idx popToRoot:YES];
			} else if (tabs) {
				tabs.selectedIndex = idx;
			}
		});
		return YES;
	}

	if ([host isEqualToString:@"chatindex"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = (UITabBarController *)(self.rootViewController ?: self.window.rootViewController);
			if (![tabs isKindOfClass:UITabBarController.class]) {
				[self showMainUI];
				tabs = (UITabBarController *)(self.rootViewController ?: self.window.rootViewController);
			}
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			if ([tabs isKindOfClass:[RootViewController class]]) {
				[(RootViewController *)tabs switchToTab:0 popToRoot:YES];
			} else {
				tabs.selectedIndex = 0;
			}
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];

			TGChatListViewController *chatList = (TGChatListViewController *)[nc.viewControllers firstObject];
			NSArray *chats = [chatList isKindOfClass:[TGChatListViewController class]] ? [chatList visibleChats] : [TGClient shared].chats;
			NSInteger idx = [arg integerValue];
			if (idx < 0 || idx >= (NSInteger)chats.count){
				NSLog(@"chatindex %ld out of range (%lu)",
						(long)idx, (unsigned long)chats.count);
				return;
			}
			NSDictionary *c = chats[idx];

			if ([c[@"isForum"] boolValue]){
				TGTopicsViewController *topics = [[TGTopicsViewController alloc] init];
				topics.chatId = [c[@"id"] longLongValue];
				topics.chatTitle = c[@"title"];
				topics.hidesBottomBarWhenPushed = YES;
				[nc pushViewController:topics animated:NO];
				NSLog(@"open forum index %ld", (long)idx);
				return;
			}

			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = [c[@"id"] longLongValue];
			vc.chatTitle = c[@"title"];
			vc.isGroup = [c[@"isGroup"] boolValue];   // same as the list does
			vc.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:vc animated:NO];
			NSLog(@"open chat index %ld", (long)idx);
		});
		return YES;
	}

	// itglegacy://touch/X/Y and itglegacy://hold/X/Y/MS - a finger, for the
	// things a URL cannot express: holding the microphone, tapping a sticker,
	// answering a call. Only reaches this app, which is all that is needed.
	if ([host isEqualToString:@"touch"] || [host isEqualToString:@"hold"]){
		BOOL holding = [host isEqualToString:@"hold"];
		// `arg` has had every slash stripped out of it, so the path is read
		// straight from the URL here.
		NSMutableArray *parts = [NSMutableArray array];
		for (NSString *component in url.pathComponents)
			if (![component isEqualToString:@"/"] && component.length)
				[parts addObject:component];
		if (parts.count < 2){
			NSLog(@"touch: expected x and y, got %@", url.path);
			return YES;
		}

		CGPoint point = CGPointMake([parts[0] floatValue], [parts[1] floatValue]);
		NSTimeInterval seconds = (holding && parts.count > 2)
				? [parts[2] doubleValue] / 1000.0 : 0;

		dispatch_async(dispatch_get_main_queue(), ^{
			UIWindow *window = [UIApplication sharedApplication].keyWindow;
			UIView *hit = [window hitTest:point withEvent:nil];
			// An action sheet lives in its own window, and the key window is
			// not it - hit-testing only the key window makes every sheet look
			// untouchable to this helper. Walk the windows from the top.
			for (UIWindow *candidate in [[[UIApplication sharedApplication].windows
					reverseObjectEnumerator] allObjects]){
				if (candidate.hidden || candidate.alpha <= 0.01f)
					continue;
				UIView *found = [candidate hitTest:point withEvent:nil];
				if (found && found != candidate.window){
					hit = found;
					window = candidate;
					break;
				}
			}
			NSLog(@"touch at %.0f,%.0f hit %@", point.x, point.y, [hit class]);

			// A control is driven through its actions; a plain view gets its
			// gesture recognisers fired instead.
			UIControl *control = nil;
			for (UIView *view = hit; view; view = view.superview)
				if ([view isKindOfClass:UIControl.class]){
					control = (UIControl *)view;
					break;
				}

			// A switch changes its value from its own gesture handling, not
			// from TouchUpInside, so sending that alone leaves it where it was
			// and the screen looks like it ignored the tap.
			if ([control isKindOfClass:UISwitch.class]){
				UISwitch *toggle = (UISwitch *)control;
				[toggle setOn:!toggle.on animated:YES];
				[toggle sendActionsForControlEvents:UIControlEventValueChanged];
				NSLog(@"touch: switch -> %@", toggle.on ? @"on" : @"off");
				return;
			}

			if (control){
				[control sendActionsForControlEvents:UIControlEventTouchDown];
				if (seconds > 0){
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
							(int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
						[control sendActionsForControlEvents:UIControlEventTouchUpInside];
						NSLog(@"released after %.0f ms", seconds * 1000);
					});
				} else {
					[control sendActionsForControlEvents:UIControlEventTouchUpInside];
				}
				return;
			}

			// Rows are reachable through itglegacy://tap/N and settings pages
			// through itglegacy://settings/N, so anything that is not a control
			// is left alone rather than guessed at.
			NSLog(@"touch: nothing actionable at that point");
		});
		return YES;
	}

	// itglegacy://answer - the 4S is not in reach of a finger during a test.
	if ([host isEqualToString:@"answer"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"answering call %d", [TGCall shared].callId);
			[[TGCall shared] accept];
		});
		return YES;
	}

	// itglegacy://hangup - end whatever call is up.
	if ([host isEqualToString:@"hangup"]){
		dispatch_async(dispatch_get_main_queue(), ^{ [[TGCall shared] hangUp]; });
		return YES;
	}

	// itglegacy://callindex/N - the private chat id is the user id, and this
	// saves having to find one by hand.
	if ([host isEqualToString:@"callindex"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSArray *chats = [TGClient shared].chats;
			NSInteger idx = [arg integerValue];
			if (idx < 0 || idx >= (NSInteger)chats.count){
				NSLog(@"callindex %ld out of range", (long)idx);
				return;
			}
			NSDictionary *c = chats[idx];
			if ([c[@"isGroup"] boolValue]){
				NSLog(@"callindex %ld is a group", (long)idx);
				return;
			}
			int64_t userId = [c[@"id"] longLongValue];
			NSLog(@"calling %@ (%lld)", c[@"title"], userId);
			[TGCallViewController presentForUserId:userId name:c[@"title"] outgoing:YES];
		});
		return YES;
	}

	// itglegacy://call/<user id> - placing a call needs a tap otherwise.
	if ([host isEqualToString:@"call"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			int64_t userId = [arg longLongValue];
			[TGCallViewController presentForUserId:userId
											  name:[[TGClient shared] nameForUserId:userId]
										  outgoing:YES];
		});
		return YES;
	}

	// itglegacy://type/TEXT - put text into whatever is being typed into, and
	// tell its delegate, which is what a keyboard would have done. Keyboard
	// keys are not controls, so touch/ cannot reach them.
	if ([host isEqualToString:@"type"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *text = [arg stringByReplacingPercentEscapesUsingEncoding:
					NSUTF8StringEncoding] ?: arg;
			UIView *responder = [self firstResponderUnder:self.window];
			if ([responder isKindOfClass:UITextField.class]){
				UITextField *field = (UITextField *)responder;
				field.text = text;
				[field sendActionsForControlEvents:UIControlEventEditingChanged];
			}

			// A search bar owns a text field but may be the responder itself,
			// and either way its delegate is what wants to hear about this.
			UIView *bar = responder;
			while (bar && ![bar isKindOfClass:UISearchBar.class])
				bar = bar.superview;
			if (bar){
				[(UISearchBar *)bar setText:text];
				id<UISearchBarDelegate> delegate = [(UISearchBar *)bar delegate];
				if ([delegate respondsToSelector:@selector(searchBar:textDidChange:)])
					[delegate searchBar:(UISearchBar *)bar textDidChange:text];
			}
			NSLog(@"type: %@ into %@", text, responder ? [responder class] : (id)@"nothing");
		});
		return YES;
	}

	// itglegacy://search - open the search page. Tapping the bar in the header
	// cannot be delivered through touch/, which drives controls rather than
	// first responders.
	if ([host isEqualToString:@"search"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			[nc pushViewController:[[TGSearchViewController alloc] init] animated:YES];
		});
		return YES;
	}

	// itglegacy://snackbar - show the undo plate over whatever is on screen,
	// committing nothing. The real one sits behind a delete, and checking how
	// it looks is not worth destroying a chat to find out.
	if ([host isEqualToString:@"snackbar"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[TGSnackbar showInView:self.window.rootViewController.view
							  text:@"Chat deleted"
						   seconds:5
						  onCommit:^{ NSLog(@"snackbar: committed (test, no-op)"); }];
		});
		return YES;
	}

	// itglegacy://holdrow/N - hold the Nth row. A long press cannot be sent
	// through touch/, which only drives controls, and the menus behind it are
	// the ones most worth looking at.
	if ([host isEqualToString:@"holdrow"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UIViewController *selected = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = [selected isKindOfClass:[UINavigationController class]] ? [(UINavigationController *)selected topViewController] : selected;
			if (![top respondsToSelector:@selector(showActionsForRow:)]){
				NSLog(@"holdrow: %@ has no row menu", [top class]);
				return;
			}
			NSInteger row = [arg isEqualToString:@"last"] ? -1 : [arg integerValue];
			NSLog(@"holdrow: %ld on %@", (long)row, [top class]);
			NSMethodSignature *sig = [top methodSignatureForSelector:
					@selector(showActionsForRow:)];
			NSInvocation *call = [NSInvocation invocationWithMethodSignature:sig];
			call.selector = @selector(showActionsForRow:);
			call.target = top;
			[call setArgument:&row atIndex:2];
			[call invoke];
		});
		return YES;
	}

	if ([host isEqualToString:@"row"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSInteger row = [arg integerValue];
			UITabBarController *tabs = (UITabBarController *)self.rootViewController;
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = (UINavigationController *)tabs.selectedViewController;
			UIViewController *top = [nc isKindOfClass:[UINavigationController class]] ? nc.topViewController : (UIViewController *)nc;
			UITableView *table = nil;
			if ([top respondsToSelector:@selector(table)])
				table = [top performSelector:@selector(table)];
			else if ([top respondsToSelector:@selector(tableView)])
				table = [top performSelector:@selector(tableView)];
			if (!table) {
				for (UIView *v in top.view.subviews) {
					if ([v isKindOfClass:[UITableView class]]) { table = (UITableView *)v; break; }
				}
			}
			if (table) {
				NSInteger total = [table numberOfRowsInSection:0];
				if (row >= 0 && row < total) {
					[table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
								 atScrollPosition:UITableViewScrollPositionTop
										 animated:NO];
					NSLog(@"scrolled to row %ld / %ld", (long)row, (long)total);
				}
			}
		});
		return YES;
	}

	// itglegacy://scroll/N - a screenshot only shows the top of a screen.
	if ([host isEqualToString:@"scroll"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UIViewController *top = [tabs.viewControllers[tabs.selectedIndex] topViewController];
			UIView *view = top.view;
			UIScrollView *scroll = [view isKindOfClass:UIScrollView.class]
					? (UIScrollView *)view : nil;
			for (UIView *sub in view.subviews)
				if (!scroll && [sub isKindOfClass:UIScrollView.class])
					scroll = (UIScrollView *)sub;
			[scroll setContentOffset:CGPointMake(0, [arg floatValue]) animated:NO];
		});
		return YES;
	}

	// itglegacy://device - the Device screen, which is three taps in otherwise.
	if ([host isEqualToString:@"device"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = tabs.viewControllers.count - 1;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			[nc popToRootViewControllerAnimated:NO];
			[nc pushViewController:[[TGDeviceViewController alloc] init] animated:NO];
		});
		return YES;
	}

	// itglegacy://saved - Saved Messages, the one real chat a script may open:
	// nobody is waiting on its read state, and it has a composer to test.
	if ([host isEqualToString:@"saved"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			int64_t savedId = [[TGClient shared] savedMessagesChatId];
			if (!tabs || !savedId)
				return;
			tabs.selectedIndex = 0;
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];
			TGChatViewController *vc = [[TGChatViewController alloc] init];
			vc.chatId = savedId;
			vc.chatTitle = @"Saved Messages";
			vc.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:vc animated:NO];
		});
		return YES;
	}

	// itglegacy://storypost - what the + on the chat list does, whose touch is a
	// gesture and out of reach of touch/.
	if ([host isEqualToString:@"storypost"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[TGStoryComposerViewController openFromController:[self activeTabBarController]
					chatId:[[TGClient shared] savedMessagesChatId] title:@"Your Story" onPosted:nil];
		});
		return YES;
	}

	// itglegacy://storycam - the story camera without the Premium check in front
	// of it, so its layout can be checked from any account. Nothing posts unless
	// its last screen's button is pressed.
	if ([host isEqualToString:@"storycam"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			TGStoryComposerViewController *composer = [[TGStoryComposerViewController alloc]
					initWithChatId:[[TGClient shared] savedMessagesChatId] title:@"Your Story"];
			[[self activeTabBarController] presentViewController:
					[TGStoryCameraViewController flowForComposer:composer]
					animated:NO completion:nil];
		});
		return YES;
	}

	// itglegacy://callbar/Name - the minimised call bar's look; callbar alone
	// takes it away.
	if ([host isEqualToString:@"callbar"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[TGCallViewController previewMiniBarNamed:arg.length ? arg : nil];
		});
		return YES;
	}

	// itglegacy://videonote - the round video recorder over whatever is showing,
	// bound to a chat that does not exist: its look and its clock can be checked
	// without opening a real conversation, which would mark it read.
	if ([host isEqualToString:@"videonote"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			// In a chat this is the chat's own start, so what comes after a
			// cancel or a send can be checked as well. The mode is only set on
			// this controller, not written down as the user's choice.
			UINavigationController *shown = (UINavigationController *)tabs.selectedViewController;
			UIViewController *top = [shown isKindOfClass:UINavigationController.class]
					? shown.topViewController : nil;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[top setValue:@YES forKey:@"videoNoteMode"];
				[top performSelector:NSSelectorFromString(@"recordStart")];
				return;
			}
			if (!tabs || ![[TGVideoNoteRecorder shared] start])
				return;
			UIView *hostView = tabs.view;
			CGRect covered = [hostView convertRect:[UIScreen mainScreen].applicationFrame fromView:nil];
			UIGraphicsBeginImageContextWithOptions(covered.size, YES, 0.0f);
			CGContextTranslateCTM(UIGraphicsGetCurrentContext(), -covered.origin.x, -covered.origin.y);
			[hostView.layer renderInContext:UIGraphicsGetCurrentContext()];
			UIImage *background = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			static TGVideoNoteViewController *recorder;
			recorder = [[TGVideoNoteViewController alloc]
					initWithChatId:-7777777LL threadId:0 background:background];
			recorder.overlayFrame = [hostView convertRect:[UIScreen mainScreen].applicationFrame
												 fromView:nil];
			[hostView addSubview:recorder.view];
		});
		return YES;
	}

	// itglegacy://gallery - open the UI Component Gallery Design Lab
	if ([host isEqualToString:@"gallery"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[self showMainUI];
			UITabBarController *tabs = [self activeTabBarController];
			if (!tabs) {
				[self showMainUI];
				tabs = [self activeTabBarController];
			}
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			tabs.selectedIndex = 0;
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];

			TGGalleryViewController *gallery = [[TGGalleryViewController alloc] init];
			gallery.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:gallery animated:NO];
			NSLog(@"open gallery directly on main nc");
		});
		return YES;
	}

	// itglegacy://settings/<page> - open one settings page directly, by the
	// number in TGSettingsPage. Row indexes move whenever a setting is added,
	// which makes a script built out of tap/S/R go stale silently; and the
	// debug menu is reachable only through ten taps on a label, which no URL
	// can do at all.
	if ([host isEqualToString:@"settings"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			if ([tabs isKindOfClass:[RootViewController class]]) {
				[(RootViewController *)tabs switchToTab:tabs.viewControllers.count - 1 popToRoot:YES];
			} else {
				tabs.selectedIndex = tabs.viewControllers.count - 1;
			}
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			[nc popToRootViewControllerAnimated:NO];
			if (!arg.length)
				return;                     // the root is where we already are
			TGSettingsViewController *page = [[TGSettingsViewController alloc] init];
			if ([arg isEqualToString:@"wallpaper"]) {
				page.page = TGSettingsPageWallpaper;
			} else {
				page.page = (TGSettingsPage)[arg integerValue];
			}
			// As the rows push it, so a screenshot shows the page the way a
			// finger would reach it rather than under the tab bar.
			page.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:page animated:NO];
		});
		return YES;
	}

	// itglegacy://wallpaper/<name or id> - switch chat canvas texture
	if ([host isEqualToString:@"wallpaper"] && arg.length){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSInteger type = [arg integerValue];
			if ([arg isEqualToString:@"none"]) type = TGWallpaperTypeNone;
			else if ([arg isEqualToString:@"grain"]) type = TGWallpaperTypePaperGrain;
			else if ([arg isEqualToString:@"pinstripes"]) type = TGWallpaperTypePinstripes;
			else if ([arg isEqualToString:@"linen"]) type = TGWallpaperTypeLinen;
			else if ([arg isEqualToString:@"parchment"]) type = TGWallpaperTypeParchment;
			else if ([arg isEqualToString:@"felt"]) type = TGWallpaperTypeFelt;
			[[TGTheme shared] setWallpaperType:(TGWallpaperType)type];
			NSLog(@"set wallpaper type: %ld (%@)", (long)type, arg);
		});
		return YES;
	}

	// itglegacy://tab/N - switch tabs, so screens behind them can be checked.
	if ([host isEqualToString:@"tab"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if ([tabs isKindOfClass:UITabBarController.class])
				tabs.selectedIndex = MIN((NSUInteger)[arg integerValue],
										 tabs.viewControllers.count - 1);
		});
		return YES;
	}

	// itglegacy://dump - dump chat messages summary to /tmp/chat_messages.json.
	if ([host isEqualToString:@"dump"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class]) return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]]){
				TGChatViewController *chatVC = (TGChatViewController *)top;
				NSArray *msgs = [chatVC valueForKey:@"messages"];
				NSMutableArray *summary = [NSMutableArray array];
				for (NSDictionary *m in msgs) {
					[summary addObject:@{
						@"id" : m[@"id"] ?: @0,
						@"kind" : m[@"kind"] ?: @"",
						@"text" : m[@"text"] ?: @"",
						@"outgoing" : m[@"outgoing"] ?: @NO,
						@"photoId" : m[@"photoId"] ?: @0,
						@"isAlbum" : m[@"isAlbum"] ?: @NO,
					}];
				}
				NSData *json = [NSJSONSerialization dataWithJSONObject:summary options:NSJSONWritingPrettyPrinted error:nil];
				[json writeToFile:@"/tmp/chat_messages.json" atomically:YES];
			}

			NSArray *chats = [TGClient shared].chats;
			NSMutableArray *chatsSummary = [NSMutableArray array];
			for (NSDictionary *c in chats) {
				[chatsSummary addObject:@{
					@"id" : c[@"id"] ?: @0,
					@"title" : c[@"title"] ?: @"",
					@"unread" : c[@"unreadCount"] ?: @0,
					@"lastMessage" : c[@"lastMessage"] ?: @"",
				}];
			}
			NSData *cjson = [NSJSONSerialization dataWithJSONObject:chatsSummary options:NSJSONWritingPrettyPrinted error:nil];
			[cjson writeToFile:@"/tmp/all_chats.json" atomically:YES];
		});
		return YES;
	}

	// itglegacy://dump_icons - render and dump all vector glyphs to /tmp/icons_dump.json
	if ([host isEqualToString:@"dump_icons"]){
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			NSMutableArray *items = [NSMutableArray array];
			// One PNG per icon beside the list: the base64 the list used to
			// carry is an iOS 7 call, and on 6 it wrote empty strings.
			NSString *dir = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
					NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"icons"];
			[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
													   attributes:nil error:nil];
			void (^addIcon)(NSString *, NSString *, NSString *, UIImage *) = ^(NSString *name, NSString *cat, NSString *desc, UIImage *img){
				if (!img) return;
				NSString *file = [NSString stringWithFormat:@"%@-%@.png",
						[[cat componentsSeparatedByString:@" "] objectAtIndex:0], name];
				[UIImagePNGRepresentation(img) writeToFile:[dir stringByAppendingPathComponent:file]
												atomically:YES];
				[items addObject:@{
					@"name" : name,
					@"category" : cat,
					@"description" : desc,
					@"file" : file,
					@"width" : @(img.size.width),
					@"height" : @(img.size.height)
				}];
			};

			// Tab bar
			addIcon(@"chats", @"Tab Bar", @"Main chats tab glyph", [TGIcons chats]);
			addIcon(@"contacts", @"Tab Bar", @"Contacts tab glyph", [TGIcons contacts]);
			addIcon(@"settings", @"Tab Bar", @"Settings sliders glyph", [TGIcons settings]);

			// Actions & Inputs
			addIcon(@"compose", @"Actions & Inputs", @"New message pencil on sheet", [TGIcons compose]);
			addIcon(@"send", @"Actions & Inputs", @"Send message paper plane / arrow", [TGIcons send]);
			addIcon(@"attach", @"Actions & Inputs", @"Paperclip attachment glyph", [TGIcons attach]);
			addIcon(@"microphone", @"Actions & Inputs", @"Audio note microphone glyph", [TGIcons microphone]);
			addIcon(@"sticker", @"Actions & Inputs", @"Sticker outline glyph", [TGIcons sticker]);
			addIcon(@"document", @"Actions & Inputs", @"Document folded sheet", [TGIcons document]);
			addIcon(@"pin", @"Actions & Inputs", @"Pushpin marker", [TGIcons pin]);
			addIcon(@"play", @"Actions & Inputs", @"Media video play arrow", [TGIcons play]);
			addIcon(@"pause", @"Actions & Inputs", @"Media video pause glyph", [TGIcons pause]);
			addIcon(@"phoneCall", @"Actions & Inputs", @"Phone handset call icon", [TGIcons phoneCall]);
			addIcon(@"searchLens", @"Actions & Inputs", @"Magnifying search lens", [TGIcons searchLensOfSize:22 colour:[[TGTheme shared] iconCatalogGlyphColour]]);
			addIcon(@"backChevron", @"Actions & Inputs", @"Navigation back chevron", [TGIcons backChevronWithColour:[[TGTheme shared] accentColour]]);
			addIcon(@"checkboxSelected", @"Actions & Inputs", @"Multi-select checked box", [TGIcons selectionCheckboxSelected:YES]);
			addIcon(@"checkboxUnselected", @"Actions & Inputs", @"Multi-select unchecked circle", [TGIcons selectionCheckboxSelected:NO]);

			// Delivery & Badges
			addIcon(@"ticksOutgoing", @"Delivery & Status", @"Delivery checkmarks (bubble text)", [TGIcons ticksWhite:NO]);
			addIcon(@"ticksMedia", @"Delivery & Status", @"Delivery checkmarks (media plate)", [TGIcons ticksWhite:YES]);
			addIcon(@"callIncoming", @"Delivery & Status", @"Incoming call arrow (green)", [TGIcons callArrowOutgoing:NO missed:NO]);
			addIcon(@"callOutgoing", @"Delivery & Status", @"Outgoing call arrow", [TGIcons callArrowOutgoing:YES missed:NO]);
			addIcon(@"callMissed", @"Delivery & Status", @"Missed call arrow (red)", [TGIcons callArrowOutgoing:NO missed:YES]);
			addIcon(@"telegramAirplane", @"Delivery & Status", @"Telegram paper airplane disc", [TGIcons telegramAirplaneOfSide:44]);
			addIcon(@"verifiedBadge", @"Delivery & Status", @"Verified starburst checkmark badge", [TGIcons verifiedBadge]);

			// Media discs
			addIcon(@"mediaDiscPlay", @"Media & Files", @"Audio play circular button", [TGIcons mediaDiscOfSide:42 playing:NO]);
			addIcon(@"mediaDiscPause", @"Media & Files", @"Audio pause circular button", [TGIcons mediaDiscOfSide:42 playing:YES]);
			addIcon(@"fileDisc", @"Media & Files", @"File attachment circular plate", [TGIcons fileDiscOfSide:42]);
			addIcon(@"recordMicDisc", @"Media & Files", @"Recording microphone disc", [TGIcons microphoneOfSide:42 colour:[[TGTheme shared] accentColour]]);

			// Context Menu
			NSArray *menuNames = @[@"reply", @"forward", @"copy", @"edit", @"delete", @"pin", @"unpin", @"mute", @"unmute", @"archive", @"unarchive", @"react", @"select", @"undo"];
			for (NSString *mn in menuNames) {
				addIcon(mn, @"Context Menu (27x27)", [NSString stringWithFormat:@"Menu action: %@", mn], [TGIcons menuGlyphNamed:mn]);
			}

			// Settings
			NSArray *settingsNames = @[@"notifications", @"privacy", @"data", @"chat", @"folder", @"devices", @"language", @"faq", @"policy"];
			for (NSString *sn in settingsNames) {
				addIcon(sn, @"Settings Rows", [NSString stringWithFormat:@"Settings page icon: %@", sn], [TGIcons settingsIconNamed:sn color:[[TGTheme shared] accentColour]]);
			}

			// Profile Tiles
			NSArray *tileNames = @[@"call", @"video", @"search", @"more"];
			for (NSString *tn in tileNames) {
				addIcon(tn, @"Profile Action Tiles", [NSString stringWithFormat:@"Action tile: %@", tn], [TGIcons menuGlyphNamed:tn]);
			}

			// Avatars & Maps
			addIcon(@"archiveAvatar", @"Avatars & Badges", @"Archived chats row disc avatar", [TGIcons archiveAvatarOfSide:kIconDumpSide]);
			addIcon(@"savedMessagesAvatar", @"Avatars & Badges", @"Saved Messages ribbon disc avatar", [TGIcons savedMessagesAvatarOfSide:kIconDumpSide]);
			addIcon(@"avatarWithInitials", @"Avatars & Badges", @"Initials placeholder avatar", [TGIcons avatarWithInitials:@"TG" size:kIconDumpSide colourId:1]);
			addIcon(@"mapPinBadge", @"Avatars & Badges", @"Location map pin marker badge", [TGIcons mapPinBadge]);

			NSData *json = [NSJSONSerialization dataWithJSONObject:items options:NSJSONWritingPrettyPrinted error:nil];
			[json writeToFile:[dir stringByAppendingPathComponent:@"icons.json"] atomically:YES];
			NSLog(@"[TGIcons] Dumped %lu icons to %@", (unsigned long)items.count, dir);
		});
		return YES;
	}

	// itglegacy://stickers - open the sticker strip, which needs a real tap.
	if ([host isEqualToString:@"stickers"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UIViewController *top = [tabs.viewControllers[tabs.selectedIndex] topViewController];
			// With a tab name it opens on that tab, which is what a test
			// needs; bare, it toggles the way the button does.
			if (arg.length && [top respondsToSelector:@selector(openStickerPanelTab:)])
				[top performSelector:@selector(openStickerPanelTab:) withObject:arg];
			else if ([top respondsToSelector:@selector(toggleStickerPanel)])
				[top performSelector:@selector(toggleStickerPanel)];
		});
		return YES;
	}

	// itglegacy://edit - enter message multi-select edit mode.
	if ([host isEqualToString:@"edit"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class]) return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[(TGChatViewController *)top enterEditMode];
			}
		});
		return YES;
	}

	// itglegacy://select/N - toggle selection of Nth message.
	if ([host isEqualToString:@"select"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class]) return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[(TGChatViewController *)top selectMessageAtIndex:[arg integerValue]];
			}
		});
		return YES;
	}

	// itglegacy://cancel - exit message edit mode.
	if ([host isEqualToString:@"cancel"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class]) return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[(TGChatViewController *)top exitEditMode];
			}
		});
		return YES;
	}

	// itglegacy://delete_selected - delete selected messages.
	if ([host isEqualToString:@"delete_selected"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class]) return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]]){
				TGChatViewController *chatVC = (TGChatViewController *)top;
				if ([arg isEqualToString:@"me"]){
					[chatVC executeDeleteMessages:[chatVC.selectedMessageIds allObjects] revoke:NO];
				} else if ([arg isEqualToString:@"both"] || [arg isEqualToString:@"everyone"]){
					[chatVC executeDeleteMessages:[chatVC.selectedMessageIds allObjects] revoke:YES];
				} else {
					[chatVC deleteSelectedMessages];
				}
			}
		});
		return YES;
	}

	// itglegacy://forward_selected - forward selected messages.
	if ([host isEqualToString:@"forward_selected"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class]) return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[(TGChatViewController *)top forwardSelectedMessages];
			}
		});
		return YES;
	}

	// itglegacy://theme/<id> - switch theme without a finger on the device.
	// Built-in and imported answer the same way now that they are one list:
	// "classic", "day", "night", "nightblue", or a file name in Documents.
	if ([host isEqualToString:@"theme"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *themeId = arg.lowercaseString;
			// The old names still work; scripts on the device use them.
			// Every built-in name is Classic now.
			if ([@[@"skeuomorphic", @"flat", @"dark", @"none", @"day", @"night", @"nightblue"] containsObject:themeId])
				themeId = @"classic";
			else if (![themeId isEqualToString:@"classic"])
				themeId = [@"file:" stringByAppendingString:arg];

			NSLog(@"theme: %@ -> %@", arg,
					[[TGTheme shared] selectThemeId:themeId] ? @"applied" : @"rejected");
		});
		return YES;
	}

	// itglegacy://fontsize/<pt> - set message font size and refresh UI.
	if ([host isEqualToString:@"fontsize"]) {
		CGFloat pt = [arg floatValue];
		if (pt >= 10.0f && pt <= 30.0f) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[TGTheme shared].messageFontSize = pt;
				NSLog(@"fontsize: set to %.1f pt", pt);
			});
			return YES;
		}
	}

	// itglegacy://groupsettings[ /chatId] - open the group settings screen for
	// the chat on screen, or for a named chat. It exists because the screen is
	// reached through an action sheet, which the touch helper cannot drive on
	// iOS 6; the user path is the group profile's More menu.
	if ([host isEqualToString:@"groupsettings"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			int64_t chatId = 0;
			NSString *chatTitle = nil;
			if ([top isKindOfClass:[TGChatViewController class]]){
				chatId = [(TGChatViewController *)top chatId];
				chatTitle = [(TGChatViewController *)top chatTitle];
			}
			if (arg.length)
				chatId = [arg longLongValue];
			Class settingsClass = NSClassFromString(@"TGGroupSettingsViewController");
			UIViewController *settings = settingsClass
					? [[settingsClass alloc] init] : nil;
			if (!settings || !chatId){
				NSLog(@"groupsettings: no screen (class %@, chat %lld)",
						settingsClass ? @"present" : @"missing", chatId);
				return;
			}
			[settings setValue:@(chatId) forKey:@"chatId"];
			if (chatTitle.length)
				[settings setValue:chatTitle forKey:@"chatTitle"];
			settings.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:settings animated:NO];
			NSLog(@"groupsettings: opened chat %lld", chatId);
		});
		return YES;
	}

	// itglegacy://profile - open the profile of the chat already on screen.
	if ([host isEqualToString:@"profile"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if ([top respondsToSelector:@selector(openProfile)])
				[top performSelector:@selector(openProfile)];
			else
				NSLog(@"profile: no chat on screen");
		});
		return YES;
	}

	// itglegacy://tap/N - run the tap handler for a row of the open chat.
	// itglegacy://send/<text> - send into the open chat, for testing the path
	// end to end without a keyboard.
	if ([host isEqualToString:@"send"] && arg.length){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			if (![top isKindOfClass:[TGChatViewController class]]){
				NSLog(@"send: no chat open");
				return;
			}
			int64_t chatId = [(TGChatViewController *)top chatId];
			NSString *text = [arg stringByReplacingPercentEscapesUsingEncoding:
					NSUTF8StringEncoding] ?: arg;
			NSLog(@"send: %lu chars to chat %lld", (unsigned long)text.length, chatId);
			[[TGClient shared] sendText:text toChat:chatId];
		});
		return YES;
	}

	if ([host isEqualToString:@"tap"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			UINavigationController *nc = tabs.viewControllers[tabs.selectedIndex];
			UIViewController *top = nc.topViewController;
			// Any table screen can answer this, not only a chat: rows are not
			// controls, so touch/ cannot reach them and every list would
			// otherwise be unreachable without a finger.
			UITableView *table = [top isKindOfClass:UITableViewController.class]
					? [(UITableViewController *)top tableView] : nil;
			if ([top isKindOfClass:[TGChatViewController class]]){
				[(TGChatViewController *)top simulateTapOnRow:[arg integerValue]];
			} else if (table){
				// tap/N is row N of section 0; tap/S/R reaches a grouped table,
				// where everything past the first group is otherwise unreachable.
				NSMutableArray *parts = [NSMutableArray array];
				for (NSString *component in url.pathComponents)
					if (![component isEqualToString:@"/"] && component.length)
						[parts addObject:component];
				NSIndexPath *path = (parts.count > 1)
						? [NSIndexPath indexPathForRow:[parts[1] integerValue]
											 inSection:[parts[0] integerValue]]
						: [NSIndexPath indexPathForRow:[arg integerValue] inSection:0];
				// A row that is not there must not take the app down with it:
				// this is driven from a script, and a stale index is normal.
				NSInteger rows = [table numberOfRowsInSection:path.section];
				if (path.section >= [table numberOfSections] || path.row >= rows){
					NSLog(@"tap: %ld.%ld is out of range (%ld rows)",
							(long)path.section, (long)path.row, (long)rows);
					return;
				}
				NSLog(@"tap: %ld.%ld on %@", (long)path.section, (long)path.row, [top class]);
				[table.delegate tableView:table didSelectRowAtIndexPath:path];
			} else {
				NSLog(@"tap: %@ has no rows", [top class]);
			}
		});
		return YES;
	}

	// itglegacy://bench/... - see TGBench.h.
	if ([host isEqualToString:@"bench"]){
		NSMutableArray *args = [url.pathComponents mutableCopy];
		[args removeObject:@"/"];
		dispatch_async(dispatch_get_main_queue(), ^{
			[TGBench runWithArguments:args window:self.window];
		});
		return YES;
	}

	if ([host isEqualToString:@"screenshot"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			// The framebuffer itself where UIKit still offers it (iOS 6 and
			// earlier): renderInContext redraws layers and misses what the
			// system draws, like the tab bar's glow and the status bar.
			CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
			CGImageRef screen = grab ? grab() : NULL;
			if (screen) {
				NSString *dir = [NSSearchPathForDirectoriesInDomains(
						NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
				BOOL ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:screen])
						writeToFile:[dir stringByAppendingPathComponent:@"screen.png"] atomically:YES];
				CGImageRelease(screen);
				NSLog(@"screenshot (framebuffer) %@", ok ? @"saved" : @"FAILED");
				return;
			}
			// Opaque: with an alpha channel, white text over a solid bubble
			// composited wrongly and came out orange in the capture - a
			// screenshot artifact that looked exactly like a colour bug.
			UIGraphicsBeginImageContextWithOptions(self.window.bounds.size, YES, 0.0f);
			CGContextRef ctx = UIGraphicsGetCurrentContext();
			// An action sheet, an alert and the keyboard each live in a window
			// of their own, so rendering only ours photographed the screen
			// underneath them and made a menu that was open look like one that
			// had never opened.
			for (UIWindow *w in [UIApplication sharedApplication].windows){
				if (w.hidden || w.alpha <= 0.01f)
					continue;
				CGContextSaveGState(ctx);
				CGContextTranslateCTM(ctx, w.frame.origin.x, w.frame.origin.y);
				[w.layer renderInContext:ctx];
				CGContextRestoreGState(ctx);
			}
			UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();

			NSString *dir = [NSSearchPathForDirectoriesInDomains(
					NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
			NSString *path = [dir stringByAppendingPathComponent:@"screen.png"];
			BOOL ok = [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
			NSLog(@"screenshot %@", ok ? @"saved" : @"FAILED");
		});
		return YES;
	}

	return YES;
}

#endif

@end
