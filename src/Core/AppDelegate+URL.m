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
#import "TGTopicsViewController.h"
#import "TGGalleryViewController.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

static NSString *TGBase64FromImage(UIImage *img) {
	if (!img) return @"";
	NSData *data = UIImagePNGRepresentation(img);
	if (!data) return @"";
	if ([data respondsToSelector:@selector(base64EncodedStringWithOptions:)]) {
		return [data base64EncodedStringWithOptions:0] ?: @"";
	}
	return @"";
}

@implementation AppDelegate (URL)

- (UITabBarController *)activeTabBarController {
	UIViewController *root = self.rootViewController ?: self.window.rootViewController;
	if ([root isKindOfClass:[UITabBarController class]]) {
		return (UITabBarController *)root;
	}
	return nil;
}

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

	if ([host isEqualToString:@"phone"] && arg.length){
		self.currentPhoneNumber = arg;
		[[TGClient shared] sendPhoneNumber:arg];
		return YES;
	}

	if ([host isEqualToString:@"code"] && arg.length){
		NSLog(@"code received (%lu chars)", (unsigned long)arg.length);
		[[TGClient shared] sendCode:arg];
		return YES;
	}

	if ([host isEqualToString:@"password"] && arg.length){
		NSLog(@"password received (%lu chars)", (unsigned long)arg.length);
		[[TGClient shared] sendPassword:arg];
		return YES;
	}

	if ([host isEqualToString:@"tab"]){
		dispatch_async(dispatch_get_main_queue(), ^{
			UITabBarController *tabs = [self activeTabBarController];
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
			NSArray *chats = [TGClient shared].chats;
			NSInteger idx = [arg integerValue];
			if (idx < 0 || idx >= (NSInteger)chats.count){
				NSLog(@"chatindex %ld out of range (%lu)",
						(long)idx, (unsigned long)chats.count);
				return;
			}
			NSDictionary *c = chats[idx];

			UITabBarController *tabs = (UITabBarController *)(self.rootViewController ?: self.window.rootViewController);
			if (![tabs isKindOfClass:UITabBarController.class])
				return;
			if ([tabs isKindOfClass:[RootViewController class]]) {
				[(RootViewController *)tabs switchToTab:0 popToRoot:YES];
			} else {
				tabs.selectedIndex = 0;
			}
			UINavigationController *nc = tabs.viewControllers[0];
			[nc popToRootViewControllerAnimated:NO];

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

	// itglegacy://gallery - open the UI Component Gallery Design Lab
	if ([host isEqualToString:@"gallery"]){
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
			TGGalleryViewController *gallery = [[TGGalleryViewController alloc] init];
			gallery.hidesBottomBarWhenPushed = YES;
			[nc pushViewController:gallery animated:NO];
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
			void (^addIcon)(NSString *, NSString *, NSString *, UIImage *) = ^(NSString *name, NSString *cat, NSString *desc, UIImage *img){
				if (!img) return;
				[items addObject:@{
					@"name" : name,
					@"category" : cat,
					@"description" : desc,
					@"b64" : TGBase64FromImage(img),
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
			addIcon(@"searchLens", @"Actions & Inputs", @"Magnifying search lens", [TGIcons searchLensOfSize:22 colour:[UIColor colorWithWhite:0.25 alpha:1]]);
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
			[json writeToFile:@"/tmp/icons_dump.json" atomically:YES];
			NSLog(@"[TGIcons] Dumped %lu icons to /tmp/icons_dump.json", (unsigned long)items.count);
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
			if ([themeId isEqualToString:@"skeuomorphic"]) themeId = @"classic";
			else if ([themeId isEqualToString:@"flat"])    themeId = @"day";
			else if ([themeId isEqualToString:@"dark"])    themeId = @"night";
			else if ([themeId isEqualToString:@"none"])    themeId = @"day";
			else if (![@[@"classic", @"day", @"night", @"nightblue"] containsObject:themeId])
				themeId = [@"file:" stringByAppendingString:arg];

			NSLog(@"theme: %@ -> %@", arg,
					[[TGTheme shared] selectThemeId:themeId] ? @"applied" : @"rejected");
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

	if ([host isEqualToString:@"screenshot"]){
		dispatch_async(dispatch_get_main_queue(), ^{
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

@end
