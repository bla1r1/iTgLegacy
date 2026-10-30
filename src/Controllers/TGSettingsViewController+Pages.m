#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGForwardPicker.h"
#import "TGStyle.h"
#import "TGGalleryViewController.h"
#import "AppDelegate.h"
#import "TGChatViewController.h"
#import "TGDevShowcase.h"

@implementation TGSettingsViewController (Pages)

#pragma mark - pages

- (NSArray *)buildSections {
	switch (self.page){
		case TGSettingsPageAppearance:    return [self appearanceSections];
		case TGSettingsPageData:          return [self dataSections];
		case TGSettingsPageNotifications: return [self notificationSections];
		case TGSettingsPagePrivacy:       return [self privacySections];
		case TGSettingsPageLanguage:      return [self languageSections];
		case TGSettingsPageBlocked:       return [self blockedSections];
		case TGSettingsPagePowerSaving:   return [self powerSavingSections];
		case TGSettingsPageRecentCalls:   return [self recentCallSections];
		case TGSettingsPageFolders:       return [self folderSections];
		case TGSettingsPageProxy:         return [self proxySections];
		case TGSettingsPageDownloads:     return [self downloadSections];
		case TGSettingsPageWallpaper:     return [self wallpaperSections];
		case TGSettingsPageDebug:         return [self debugSections];
		default:                          return [self rootSections];
	}
}

- (NSArray *)rootSections {
	__weak typeof(self) weakSelf = self;
	NSDictionary *me = [TGClient shared].me;
	BOOL hasPhoto = [[TGClient shared] photoFileIdForUserId:
			[me[@"id"] longLongValue]] != nil;

	return @[
		// Profile header card
		TGSection(nil, nil, @[
			TGRow(TGKindProfile, @""),
		]),

		// Account actions card
		TGSection(nil, nil, @[
			([TGClient shared].authState != TGAuthStateReady) ? TGActionRow(@"Log in to Telegram", ^{
				[[AppDelegate sharedDelegate] showLoginUI];
			}) : TGActionRow(@"Add Account", ^{ [weakSelf explainAddAccount]; }),
			TGActionRow(hasPhoto ? @"Change Profile Photo" : @"Set Profile Photo", ^{
				[weakSelf pickProfilePhoto];
			}),
			TGIconRow(@"Edit Profile", @"chat", TGIconTileViolet(), ^{
				UIViewController *edit = [[TGEditProfileViewController alloc] init];
				edit.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:edit animated:YES];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Saved Messages", @"folder", TGIconTileSky(), ^{
				[weakSelf openSavedMessages];
			}),
			TGIconRow(@"Recent Calls", @"call", TGIconTileGreen(), ^{
				[weakSelf openPage:TGSettingsPageRecentCalls];
			}),
			TGIconRow(@"Devices", @"devices", TGIconTileAmber(), ^{
				TGSessionsViewController *sessions = [[TGSessionsViewController alloc] init];
				sessions.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:sessions animated:YES];
			}),
			TGIconRow(@"Chat Folders", @"folder", TGIconTileCyan(), ^{
				[weakSelf openPage:TGSettingsPageFolders];
			}),
			TGIconRow(@"Proxy", @"data", TGIconTileGrey(), ^{
				[weakSelf openPage:TGSettingsPageProxy];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Notifications and Sounds", @"notifications", TGIconTileRed(), ^{
				[weakSelf openPage:TGSettingsPageNotifications];
			}),
			TGIconRow(@"Privacy and Security", @"privacy", TGIconTileGrey(), ^{
				[weakSelf openPage:TGSettingsPagePrivacy];
			}),
			TGIconRow(@"Data and Storage", @"data", TGIconTileGreen(), ^{
				[weakSelf openPage:TGSettingsPageData];
			}),
			TGIconRow(@"Appearance", @"chat", TGIconTileSky(), ^{
				[weakSelf openPage:TGSettingsPageAppearance];
			}),
			TGIconRow(@"Power Saving", @"battery", TGIconTileAmber(), ^{
				[weakSelf openPage:TGSettingsPagePowerSaving];
			}),
			TGIconRow(@"Language", @"language", TGIconTileViolet(), ^{
				[weakSelf openPage:TGSettingsPageLanguage];
			}),
			TGIconRow(@"Device", @"devices", TGIconTileSlate(), ^{
				TGDeviceViewController *device = [[TGDeviceViewController alloc] init];
				device.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:device animated:YES];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Telegram Premium", @"star", TGIconTilePurple(), ^{
				[weakSelf showPremiumState];
			}),
			TGIconRow(@"Telegram Business", @"briefcase", TGIconTileAzure(), ^{
				[weakSelf pushPlaceholder:@"Telegram Business"];
			}),
			TGIconRow(@"Send a Gift", @"gift", TGIconTileCoral(), ^{
				[weakSelf pushPlaceholder:@"Send a Gift"];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Ask a Question", @"chat", TGIconTileAmber(), ^{
				[weakSelf openSupport];
			}),
			TGIconRow(@"Telegram FAQ", @"faq", TGIconTileCyan(), ^{
				[weakSelf openURL:@"https://telegram.org/faq"];
			}),
			TGIconRow(@"Privacy Policy", @"policy", TGIconTileGold(), ^{
				[weakSelf openURL:@"https://telegram.org/privacy"];
			}),
		]),

		TGSection(nil, nil, @[
			TGRedRow(@"Log out", ^{
				[TGAlertSheet showConfirm:@"Are you sure you want to log out?"
									title:@"Log out"
								   action:@"Log out"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{ [[TGClient shared] logOut]; }];
			}),
		]),
	];
}

- (NSArray *)languageSections {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *language in self.languages){
		NSString *packId = language[@"id"];
		[rows addObject:TGCheckRow(language[@"name"], nil,
				[packId isEqualToString:self.currentLanguage], ^{
			[[TGClient shared] setLanguage:packId];
			weakSelf.currentLanguage = packId;
			[weakSelf rebuild];
		})];
	}
	if (!rows.count)
		[rows addObject:TGRow(TGKindPlain, @"Loading...")];

	return @[TGSection(nil,
			@"This app's own text is English throughout. The language is what "
			@"Telegram itself writes in, and it follows the account onto your "
			@"other devices.", rows)];
}

- (NSArray *)recentCallSections {
	__weak typeof(self) weakSelf = self;
	if (!self.calls.count)
		return @[TGSection(nil, nil, @[TGRow(TGKindPlain, @"No recent calls")])];

	static NSDateFormatter *when = nil;
	if (!when){
		when = [[NSDateFormatter alloc] init];
		when.dateStyle = NSDateFormatterShortStyle;
		when.timeStyle = NSDateFormatterShortStyle;
	}

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *call in self.calls){
		BOOL missed = [call[@"missed"] boolValue];
		BOOL outgoing = [call[@"outgoing"] boolValue];
		NSInteger duration = [call[@"duration"] integerValue];
		NSString *detail = [NSString stringWithFormat:@"%@ %@%@",
				(outgoing ? @"Outgoing" : @"Incoming"),
				[when stringFromDate:[NSDate dateWithTimeIntervalSince1970:
						[call[@"date"] doubleValue]]],
				(!missed && duration > 0)
						? [NSString stringWithFormat:@" - %ld:%02ld",
								(long)(duration / 60), (long)(duration % 60)]
						: @""];

		NSMutableDictionary *row = [TGSubtitleRow(call[@"name"], detail, ^{
			[weakSelf pushPlaceholder:@"Call back"];
		}) mutableCopy];
		if (missed)
			row[TGRowKind] = TGKindDestructive;
		[rows addObject:row];
	}
	return @[TGSection(nil, nil, rows)];
}

/// Their Debug Menu, with what is actually inspectable on this build. Reached
/// by ten taps on the version, and linked from nowhere - the same bargain
/// their client makes.
- (NSArray *)debugSections {
	__weak typeof(self) weakSelf = self;
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;

	// Whether the bundled emoji font actually registered - the one thing that
	// cannot be told apart from "no emoji in this message" by looking.
	UIFont *emoji = TGFontEmojiMeta();

	NSMutableArray *facts = [NSMutableArray array];
	[facts addObject:TGTapRow(@"App Version", [NSString stringWithFormat:@"%@ (%@)",
			info[@"CFBundleShortVersionString"] ?: @"?",
			info[@"CFBundleVersion"] ?: @"?"], nil)];
	[facts addObject:TGTapRow(@"TDLib", self.tdlibVersion ?: @"...", nil)];
	[facts addObject:TGTapRow(@"System", [UIDevice currentDevice].systemVersion, nil)];
	[facts addObject:TGTapRow(@"Device", [TGDevice modelName] ?: @"?", nil)];
	[facts addObject:TGTapRow(@"Machine", [TGDevice machine] ?: @"?", nil)];
	[facts addObject:TGTapRow(@"Tier", [TGDevice tierName] ?: @"?", nil)];
	[facts addObject:TGTapRow(@"Chip", [TGDevice chip] ?: @"unknown", nil)];
	[facts addObject:TGTapRow(@"Memory", [NSString stringWithFormat:@"%lu MB",
			(unsigned long)[TGCapabilities memoryMB]], nil)];
	[facts addObject:TGTapRow(@"Architecture",
			[TGCapabilities is64Bit] ? @"arm64" : @"armv7", nil)];
	[facts addObject:TGTapRow(@"Emoji Font",
			emoji ? emoji.fontName : @"NOT REGISTERED", nil)];
	[facts addObject:TGTapRow(@"Theme", [[TGTheme shared] currentThemeId], nil)];

	return @[
		TGSection(@"Dev & Showcase",
				  @"Interactive showcase for all 30 TDLib message types, vector Lottie (.tgs), and VP9 video (.webm) stickers.", @[
			TGTapRow(@"Open Message Types Showcase Chat", nil, ^{
				TGChatViewController *chat = [[TGChatViewController alloc] init];
				chat.chatId = kDevChatId;
				chat.chatTitle = @"Dev Showcase";
				chat.isGroup = YES;
				chat.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:chat animated:YES];
			}),
		]),

		TGSection(@"Build", nil, facts),

		TGSection(@"Capabilities",
				  @"What this device is allowed to do, and what it is waiting "
				  @"for when it is not.", @[
			TGTapRow(@"Device Capabilities", nil, ^{
				TGDeviceViewController *device = [[TGDeviceViewController alloc] init];
				device.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:device animated:YES];
			}),
		]),

		TGSection(@"Dev Harness",
				  @"Preview rich media, interactive polls, audio tracks, and custom stickers.", @[
			TGTapRow(@"Open Dev Showcase Chat", @"30 message types", ^{
				TGChatViewController *vc = [[TGChatViewController alloc] init];
				vc.chatId = kDevChatId;
				vc.chatTitle = @"Dev Showcase";
				vc.isGroup = YES;
				vc.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:vc animated:YES];
			}),
		]),

		TGSection(@"Logging",
				  @"Verbose puts TDLib's own chatter into the system log, which "
				  @"is where a connection problem shows up. It is noisy and it "
				  @"costs speed, so it does not survive a restart.", @[
			TGTapRow(@"TDLib Log Verbosity: Errors", nil, ^{
				[[TGClient shared] send:@{@"@type" : @"setLogVerbosityLevel",
										  @"new_verbosity_level" : @(1)}];
				[weakSelf toast:@"Verbosity set to 1"];
			}),
			TGTapRow(@"TDLib Log Verbosity: Verbose", nil, ^{
				[[TGClient shared] send:@{@"@type" : @"setLogVerbosityLevel",
										  @"new_verbosity_level" : @(5)}];
				[weakSelf toast:@"Verbosity set to 5"];
			}),
		]),

		TGSection(@"Storage",
				  @"Documents is shared over iTunes file sharing, so anything "
				  @"written there can be pulled off the device.", @[
			TGTapRow(@"Clear Temporary Files", nil, ^{
				[weakSelf clearTemporaryFiles];
			}),
			TGTapRow(@"Storage Usage", nil, ^{
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				storage.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:storage animated:YES];
			}),
		]),

		TGSection(nil,
				  @"Resets this app's own preferences - theme, text size, power "
				  @"saving, auto-download. The session and the messages stay.", @[
			TGRedRow(@"Reset Local Preferences", ^{
				[TGAlertSheet showConfirm:@"Theme, text size and every switch in "
										  @"Settings go back to their defaults."
									title:@"Reset Local Preferences"
								   action:@"Reset"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					NSString *domain = [NSBundle mainBundle].bundleIdentifier;
					[NSUserDefaults.standardUserDefaults
							removePersistentDomainForName:domain];
					[NSUserDefaults.standardUserDefaults synchronize];
					[weakSelf repaint];
					[weakSelf toast:@"Preferences reset."];
				}];
			}),
		]),
	];
}

- (void)toast:(NSString *)text {
	[TGAlertSheet showMessage:text title:nil inView:self.view];
}

@end
