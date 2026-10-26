#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGForwardPicker.h"
#import "TGStyle.h"

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
		// Profile & Account card
		TGSection(nil, nil, @[
			TGRow(TGKindProfile, @""),
			TGActionRow(hasPhoto ? @"Change Profile Photo" : @"Set Profile Photo", ^{
				[weakSelf pickProfilePhoto];
			}),
			TGIconRow(@"Edit Profile", @"chat", TGRGB(0.35, 0.34, 0.84), ^{
				UIViewController *edit = [[TGEditProfileViewController alloc] init];
				edit.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:edit animated:YES];
			}),
			TGActionRow(@"Add Account", ^{ [weakSelf explainAddAccount]; }),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Saved Messages", @"folder", TGRGB(0.20, 0.60, 0.86), ^{
				[weakSelf openSavedMessages];
			}),
			TGIconRow(@"Recent Calls", @"call", TGRGB(0.29, 0.85, 0.39), ^{
				[weakSelf openPage:TGSettingsPageRecentCalls];
			}),
			TGIconRow(@"Devices", @"devices", TGRGB(1.00, 0.58, 0.00), ^{
				TGSessionsViewController *sessions = [[TGSessionsViewController alloc] init];
				sessions.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:sessions animated:YES];
			}),
			TGIconRow(@"Chat Folders", @"folder", TGRGB(0.20, 0.75, 0.86), ^{
				[weakSelf openPage:TGSettingsPageFolders];
			}),
			TGIconRow(@"Proxy", @"data", TGRGB(0.56, 0.56, 0.58), ^{
				[weakSelf openPage:TGSettingsPageProxy];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Notifications and Sounds", @"notifications", TGRGB(1.00, 0.23, 0.18), ^{
				[weakSelf openPage:TGSettingsPageNotifications];
			}),
			TGIconRow(@"Privacy and Security", @"privacy", TGRGB(0.56, 0.56, 0.58), ^{
				[weakSelf openPage:TGSettingsPagePrivacy];
			}),
			TGIconRow(@"Data and Storage", @"data", TGRGB(0.29, 0.85, 0.39), ^{
				[weakSelf openPage:TGSettingsPageData];
			}),
			TGIconRow(@"Appearance", @"chat", TGRGB(0.20, 0.60, 0.86), ^{
				[weakSelf openPage:TGSettingsPageAppearance];
			}),
			TGIconRow(@"Power Saving", @"battery", TGRGB(1.00, 0.58, 0.00), ^{
				[weakSelf openPage:TGSettingsPagePowerSaving];
			}),
			TGIconRow(@"Language", @"language", TGRGB(0.35, 0.34, 0.84), ^{
				[weakSelf openPage:TGSettingsPageLanguage];
			}),
			TGIconRow(@"Device", @"devices", TGRGB(0.45, 0.45, 0.50), ^{
				TGDeviceViewController *device = [[TGDeviceViewController alloc] init];
				device.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:device animated:YES];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Telegram Premium", @"star", TGRGB(0.53, 0.24, 0.75), ^{
				[weakSelf showPremiumState];
			}),
			TGIconRow(@"Telegram Business", @"briefcase", TGRGB(0.00, 0.48, 1.00), ^{
				[weakSelf pushPlaceholder:@"Telegram Business"];
			}),
			TGIconRow(@"Send a Gift", @"gift", TGRGB(1.00, 0.18, 0.33), ^{
				[weakSelf pushPlaceholder:@"Send a Gift"];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Ask a Question", @"chat", TGRGB(1.00, 0.58, 0.00), ^{
				[weakSelf openSupport];
			}),
			TGIconRow(@"Telegram FAQ", @"faq", TGRGB(0.20, 0.75, 0.86), ^{
				[weakSelf openURL:@"https://telegram.org/faq"];
			}),
			TGIconRow(@"Privacy Policy", @"policy", TGRGB(1.00, 0.80, 0.00), ^{
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

- (NSArray *)notificationSections {
	__weak typeof(self) weakSelf = self;
	NSArray *scopes = @[@"private", @"groups", @"channels"];
	NSArray *titles = @[@"Private Chats", @"Groups", @"Channels"];

	NSMutableArray *show = [NSMutableArray array];
	NSMutableArray *preview = [NSMutableArray array];
	for (NSUInteger i = 0; i < scopes.count; i++){
		NSString *scope = scopes[i];
		// The row says "show notifications", TDLib stores "muted": the same
		// fact the other way up.
		[show addObject:TGSwitchRow(titles[i], ![weakSelf.muted[scope] boolValue],
				^(BOOL on){
			weakSelf.muted[scope] = @(!on);
			[[TGClient shared] setScope:scope muted:!on];
		})];
		[preview addObject:TGSwitchRow(titles[i], [weakSelf.previews[scope] boolValue],
				^(BOOL on){
			weakSelf.previews[scope] = @(on);
			[[TGClient shared] setScope:scope showPreview:on];
		})];
	}

	return @[
		TGSection(@"Show notifications for", nil, show),
		TGSection(@"Message previews",
				  @"With previews off a notification says who wrote, not what "
				  @"they wrote.", preview),
		TGSection(nil,
				  @"Undoes every exception you have set on an individual chat, "
				  @"on every device.",
				  @[TGRedRow(@"Reset All Notifications", ^{
			[TGAlertSheet showConfirm:@"Every per-chat notification exception will "
									  @"be forgotten."
								title:@"Reset All Notifications"
							   action:@"Reset"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] resetAllNotificationSettings];
				[weakSelf loadForPage];
			}];
		})]),
	];
}

- (NSArray *)privacySections {
	__weak typeof(self) weakSelf = self;

	NSMutableArray *rules = [NSMutableArray array];
	NSArray *settings = [TGSettingsViewController privacySettings];
	for (NSUInteger i = 0; i < settings.count; i++){
		NSString *setting = settings[i];
		NSUInteger index = i;
		[rules addObject:TGTapRow([TGSettingsViewController privacyTitles][i],
				TGPrivacyLabel(weakSelf.privacy[setting]), ^{
			[weakSelf askPrivacyRuleAtIndex:index];
		})];
	}

	NSString *passwordDetail = !weakSelf.passwordKnown ? @"..."
			: (weakSelf.hasPassword ? @"On" : @"Off");

	return @[
		TGSection(@"Security", nil, @[
			TGTapRow(@"Two-Step Verification", passwordDetail, ^{
				[weakSelf showTwoStepState];
			}),
			TGTapRow(@"Active Sessions", nil, ^{
				TGSessionsViewController *sessions = [[TGSessionsViewController alloc] init];
				sessions.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:sessions animated:YES];
			}),
			TGTapRow(@"Blocked Users", nil, ^{
				[weakSelf openPage:TGSettingsPageBlocked];
			}),
		]),

		TGSection(nil,
				  @"Your own t.me link works without a username, and can be "
				  @"given to someone who has no way to search for you.", @[
			TGTapRow(@"My Link", nil, ^{
				[[TGClient shared] myUserLink:^(NSString *link){
					if (!link.length){
						[weakSelf toast:@"Telegram did not answer with a link."];
						return;
					}
					[TGAlertSheet showChoices:@[@"Copy"]
										title:link
									  message:nil
							 destructiveIndex:-1
									   inView:weakSelf.view
									 onChoice:^(NSInteger index){
						[UIPasteboard generalPasteboard].string = link;
						[weakSelf toast:@"Copied."];
					}];
				}];
			}),
		]),

		TGSection(@"Who can see", nil, rules),

		TGSection(@"Contacts",
				  @"Frequent contacts are ranked on Telegram's side; turning "
				  @"the suggestion off deletes that ranking.", @[
			TGSwitchRow(@"Suggest Frequent Contacts", weakSelf.suggestFrequent, ^(BOOL on){
				weakSelf.suggestFrequent = on;
				[[TGClient shared] setOption:@"disable_top_chats" boolValue:!on];
			}),
			TGRedRow(@"Delete Synced Contacts", ^{
				[TGAlertSheet showConfirm:@"The phone numbers this account uploaded "
										  @"to Telegram will be removed."
									title:@"Delete Synced Contacts"
								   action:@"Delete"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearImportedContacts];
				}];
			}),
		]),

		TGSection(nil,
				  @"If you do not come online at least once within this period, "
				  @"the account is deleted along with everything in it.", @[
			TGTapRow(@"Delete My Account", weakSelf.accountTtl > 0
					? [NSString stringWithFormat:@"if away for %ld months",
							(long)(weakSelf.accountTtl / 30)]
					: @"...", ^{
				[TGAlertSheet showChoices:@[@"1 month", @"3 months",
											@"6 months", @"12 months"]
									title:@"Delete my account if away for"
						 destructiveIndex:-1
								   inView:weakSelf.view
								 onChoice:^(NSInteger index){
					static const NSInteger months[4] = {1, 3, 6, 12};
					[[TGClient shared] setAccountTtlDays:months[index] * 30];
					weakSelf.accountTtl = months[index] * 30;
					[weakSelf rebuild];
				}];
			}),
			TGRedRow(@"Delete Account Now", ^{
				[weakSelf askDeleteAccountNow];
			}),
		]),
	];
}

- (NSArray *)dataSections {
	__weak typeof(self) weakSelf = self;
	BOOL mobile = [[TGClient shared] autoDownloadOverMobile];
	BOOL wifi   = [[TGClient shared] autoDownloadOverWifi];
	NSDictionary *archiveSettings = [TGClient shared].archiveSettings ?: @{};

	return @[
		TGSection(@"Usage", nil, @[
			TGTapRow(@"Downloads", nil, ^{
				[weakSelf openPage:TGSettingsPageDownloads];
			}),
			TGTapRow(@"Storage Usage", nil, ^{
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				storage.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:storage animated:YES];
			}),
			TGTapRow(@"Network Usage",
					[NSString stringWithFormat:@"%@ in, %@ out",
							TGBytes(weakSelf.networkReceived), TGBytes(weakSelf.networkSent)],
					^{
				[TGAlertSheet showConfirm:@"Reset the counters?"
									title:@"Network Usage"
								   action:@"Reset"
							  destructive:NO
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] resetNetworkStats];
					weakSelf.networkSent = 0;
					weakSelf.networkReceived = 0;
					[weakSelf rebuild];
				}];
			}),
		]),

		TGSection(@"Automatic media download",
				  @"Off over mobile by default: this radio is slow and the "
				  @"cache lives on a small disk.", @[
			TGSwitchRow(@"Over Mobile Data", mobile, ^(BOOL on){
				[[TGClient shared] setAutoDownloadOverMobile:on
														wifi:[[TGClient shared] autoDownloadOverWifi]];
				[weakSelf rebuild];
			}),
			TGSwitchRow(@"Over Wi-Fi", wifi, ^(BOOL on){
				[[TGClient shared] setAutoDownloadOverMobile:[[TGClient shared] autoDownloadOverMobile]
														wifi:on];
				[weakSelf rebuild];
			}),
		]),

		TGSection(@"Archive", @"New chats from non-contacts can be archived "
				  @"and muted instead of ringing in. A new message can drag "
				  @"an archived chat back to the main list - the last two "
				  @"switches decide whether it does.", @[
			TGSwitchRow(@"Archive New Chats From Non-Contacts",
					[archiveSettings[@"archive_and_mute_new_chats_from_unknown_users"] boolValue],
					^(BOOL on){
				NSDictionary *old = [TGClient shared].archiveSettings ?: @{};
				[[TGClient shared] setArchiveSettingsArchiveAndMute:on
											keepUnmutedArchived:[old[@"keep_unmuted_chats_archived"] boolValue]
									  keepFolderChatsArchived:[old[@"keep_chats_from_folders_archived"] boolValue]];
				[weakSelf rebuild];
			}),
			TGSwitchRow(@"Keep Unmuted Chats Archived",
					[archiveSettings[@"keep_unmuted_chats_archived"] boolValue],
					^(BOOL on){
				NSDictionary *old = [TGClient shared].archiveSettings ?: @{};
				[[TGClient shared] setArchiveSettingsArchiveAndMute:[old[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]
											keepUnmutedArchived:on
									  keepFolderChatsArchived:[old[@"keep_chats_from_folders_archived"] boolValue]];
				[weakSelf rebuild];
			}),
			// Ignored while "Keep Unmuted Chats Archived" is on, which is
			// how TDLib reads the same object; the row stays for the day
			// that switch goes back off.
			TGSwitchRow(@"Keep Folder Chats Archived",
					[archiveSettings[@"keep_chats_from_folders_archived"] boolValue],
					^(BOOL on){
				NSDictionary *old = [TGClient shared].archiveSettings ?: @{};
				[[TGClient shared] setArchiveSettingsArchiveAndMute:[old[@"archive_and_mute_new_chats_from_unknown_users"] boolValue]
											keepUnmutedArchived:[old[@"keep_unmuted_chats_archived"] boolValue]
									  keepFolderChatsArchived:on];
				[weakSelf rebuild];
			}),
		]),

		TGSection(nil, nil, @[
			TGRedRow(@"Clear Local Database", ^{
				[TGAlertSheet showConfirm:@"Cached chats and messages are dropped "
										  @"and fetched again. The session stays."
									title:@"Clear Local Database"
								   action:@"Clear"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearLocalDatabase];
				}];
			}),
		]),
	];
}

/// Their Appearance page: a live preview of two bubbles at the top, then the
/// text size and the wallpaper, then Auto-Night, then one list of themes.
- (NSArray *)appearanceSections {
	__weak typeof(self) weakSelf = self;
	TGTheme *theme = [TGTheme shared];

	// One list. The split between "Style" and "Telegram themes" was how this
	// file stored them, not a distinction anyone picking a look cares about.
	NSString *current = [theme currentThemeId];
	NSMutableArray *themes = [NSMutableArray array];
	for (NSDictionary *entry in [TGTheme availableThemes]){
		NSString *themeId = entry[@"id"];
		BOOL fromFile = entry[@"path"] != nil;
		[themes addObject:TGCheckRow(entry[@"name"],
				fromFile ? [(NSString *)entry[@"path"] pathExtension] : nil,
				[current isEqualToString:themeId], ^{
			if (![[TGTheme shared] selectThemeId:themeId]){
				[TGAlertSheet showMessage:@"This file could not be read as a "
										  @"Telegram theme."
									title:@"Theme" inView:weakSelf.view];
			}
			[weakSelf repaint];
		})];
	}

	NSString *autoNightDetail = (theme.autoNight == TGAutoNightScheduled)
			? [NSString stringWithFormat:@"%02ld:00 - %02ld:00",
					(long)theme.autoNightFromHour, (long)theme.autoNightToHour]
			: @"Disabled";

	return @[
		TGSection(nil, nil, @[TGRow(TGKindPreview, @"")]),

		TGSection(@"Chat", nil, @[
			TGTapRow(@"Message Text Size",
					[NSString stringWithFormat:@"%.0f pt", theme.messageFontSize],
					^{ [weakSelf chooseTextSize]; }),
			TGTapRow(@"Chat Wallpaper", theme.wallpaper ? @"Set" : @"None", ^{
				[weakSelf chooseWallpaper];
			}),
		]),

		TGSection(@"Auto-Night Mode",
				  @"There is no system dark mode on this OS to follow, so the "
				  @"schedule is the automatic. Picking a theme by hand at night "
				  @"turns the schedule off until morning.", @[
			TGTapRow(@"Auto-Night Mode", autoNightDetail, ^{
				[weakSelf chooseAutoNight];
			}),
		]),

		TGSection(@"Color Theme",
				  @"Theme files made for the official clients - .tgios-theme and "
				  @".attheme - appear here once they are in the app's Documents "
				  @"folder, or once one is opened from a chat.", themes),
	];
}

- (NSArray *)powerSavingSections {
	__weak typeof(self) weakSelf = self;
	TGClient *client = [TGClient shared];
	BOOL possible = [TGDevice tier] >= TGDeviceTierLegacy;

	NSString *footer = possible
			? @"Each of these redraws the screen while nothing is being touched, "
			  @"which is where an A5 spends its battery. Turning one off leaves "
			  @"the still picture."
			: @"This device is below the tier that plays these at all, so these "
			  @"switches change nothing here.";

	return @[
		TGSection(@"Resource-intensive processes", footer, @[
			TGSwitchInfoRow(@"Sticker Animation",
					@"Loop animated stickers in chats instead of showing the "
					@"first frame.",
					@"sticker", TGRGB(0.29, 0.85, 0.39),
					[TGCapabilities animatedStickersWanted] && possible, ^(BOOL on){
				[TGCapabilities setAnimatedStickersWanted:on];
				[weakSelf rebuild];
			}),
			TGSwitchInfoRow(@"Chat Wallpaper",
					@"Draw the wallpaper behind messages. A plain background "
					@"scrolls faster.",
					@"chat", TGRGB(0.20, 0.60, 0.86),
					[TGCapabilities wallpaperWanted] && possible, ^(BOOL on){
				[TGCapabilities setWallpaperWanted:on];
				[weakSelf rebuild];
			}),
			TGSwitchInfoRow(@"Autoplay GIFs",
					@"Loop GIFs silently in the chat. Off, a GIF plays when "
					@"tapped.",
					@"video", TGRGB(0.69, 0.32, 0.87),
					[TGCapabilities gifAutoplayWanted] && possible, ^(BOOL on){
				[TGCapabilities setGifAutoplayWanted:on];
				[weakSelf rebuild];
			}),
		]),

		TGSection(@"Media preloading",
				  @"Downloading nothing until it is asked for is the largest "
				  @"saving of the three - it costs radio time as well as CPU.", @[
			TGSwitchInfoRow(@"Over Mobile Data",
					@"Start downloading photos and files before you open them, "
					@"on the cellular radio.",
					@"data", TGRGB(1.00, 0.58, 0.00),
					[client autoDownloadOverMobile], ^(BOOL on){
				[client setAutoDownloadOverMobile:on wifi:[client autoDownloadOverWifi]];
				[weakSelf rebuild];
			}),
			TGSwitchInfoRow(@"Over Wi-Fi",
					@"The same, on Wi-Fi.",
					@"data", TGRGB(0.20, 0.75, 0.86),
					[client autoDownloadOverWifi], ^(BOOL on){
				[client setAutoDownloadOverMobile:[client autoDownloadOverMobile] wifi:on];
				[weakSelf rebuild];
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

- (NSArray *)blockedSections {
	__weak typeof(self) weakSelf = self;
	if (!self.blocked.count)
		return @[TGSection(nil, nil, @[TGRow(TGKindPlain, @"Nobody is blocked")])];

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *user in self.blocked){
		int64_t userId = [user[@"id"] longLongValue];
		[rows addObject:TGSubtitleRow(user[@"name"], @"Tap to unblock", ^{
			[[TGClient shared] setUser:userId blocked:NO];
			NSMutableArray *rest = [weakSelf.blocked mutableCopy];
			[rest removeObject:user];
			weakSelf.blocked = rest;
			[weakSelf rebuild];
		})];
	}
	return @[TGSection(nil, nil, rows)];
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

#pragma mark - chat folders

/// The name the chat list knows a chat under. A folder's own answer carries
/// ids and nothing else, and an id is no use on a row.
static NSString *TGChatNameForId(NSNumber *chatId) {
	for (NSArray *list in @[[TGClient shared].chats ?: @[],
							[TGClient shared].archivedChats ?: @[]])
		for (NSDictionary *chat in list)
			if ([chat[@"id"] longLongValue] == chatId.longLongValue){
				NSString *title = chat[@"title"];
				if (title.length)
					return title;
			}
	return [NSString stringWithFormat:@"Chat %@", chatId];
}

/// Their Folders page: what this account has, then what Telegram suggests.
/// A folder's own settings - which chats, which kinds - are a sheet on the
/// row rather than a screen of their own: on a 3.5-inch display a second
/// list of checkboxes reads worse than four plain choices.
- (NSArray *)folderSections {
	__weak typeof(self) weakSelf = self;
	NSArray *folders = [TGClient shared].folders;

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *folder in folders){
		NSString *title = folder[@"title"];
		if (!title.length)
			continue;
		[rows addObject:TGTapRow(title, nil, ^{
			[weakSelf runFolderActionFor:folder];
		})];
	}
	[rows addObject:TGActionRow(@"Create New Folder", ^{
		[TGAlertSheet showInput:@"New Folder"
						message:@"Folders appear as a strip above the chat list."
					placeholder:@"Name"
						   text:nil
						 action:@"Create"
						 inView:weakSelf.view
					   onSubmit:^(NSString *name){
			[[TGClient shared] createFolderNamed:name icon:nil withChats:@[]
									  completion:^(NSInteger folderId){
				if (!folderId){
					[weakSelf toast:@"Telegram refused that name."];
					return;
				}
				// updateChatFolders brings the new one back; the strip and
				// this page both read from it.
				[weakSelf toast:[NSString stringWithFormat:
						@"%@ created. Tap it to choose its chats.", name]];
			}];
		}];
	})];

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGSection(folders.count ? @"Folders" : nil,
			folders.count
					? @"Tap a folder to rename it, choose its chats, or delete it."
					: @"This account has no folders yet. A folder is a filter "
					  @"over the chat list, not a copy of it: a chat in a "
					  @"folder is still in All Chats.",
			rows)];

	NSMutableArray *suggested = [NSMutableArray array];
	for (NSDictionary *entry in self.recommendedFolders){
		NSString *title = entry[@"title"];
		if (!title.length)
			continue;
		[suggested addObject:TGTapRow(title, entry[@"description"], ^{
			[[TGClient shared] createRecommendedFolder:entry[@"folder"]
											completion:^(NSInteger folderId){
				[weakSelf toast:folderId ? [NSString stringWithFormat:@"%@ added.", title]
										 : @"Telegram refused that folder."];
			}];
		})];
	}
	if (suggested.count)
		[sections addObject:TGSection(@"Recommended",
				@"Telegram's own, ready made. Adding one does not move any chat.",
				suggested)];

	return sections;
}

/// Four things can be done to a folder, and this is all four. Reordering is
/// not among them: the strip's order needs dragging, which this list has no
/// room for - see docs/feature_backlog.md.
- (void)runFolderActionFor:(NSDictionary *)folder {
	NSInteger folderId = [folder[@"id"] integerValue];
	NSString *title = folder[@"title"] ?: @"Folder";
	if (!folderId)
		return;

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Rename", @"Add a Chat", @"Remove a Chat",
								@"Delete Folder"]
						title:title
			 destructiveIndex:3
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 0){
			[TGAlertSheet showInput:@"Rename Folder" message:nil
						placeholder:@"Name" text:title action:@"Save"
							 inView:me.view onSubmit:^(NSString *name){
				[[TGClient shared] editFolder:folderId name:name chats:nil
								   completion:^(BOOL ok){
					if (!ok)
						[me toast:@"Telegram refused that name."];
				}];
			}];
		} else if (index == 1){
			[me addChatToFolder:folderId named:title];
		} else if (index == 2){
			[me removeChatFromFolder:folderId named:title];
		} else {
			[TGAlertSheet showConfirm:[NSString stringWithFormat:
							@"%@ goes away. The chats in it stay where they are.",
							title]
								title:@"Delete Folder"
							   action:@"Delete"
						  destructive:YES
							   inView:me.view
							onConfirm:^{
				[[TGClient shared] deleteFolder:folderId leavingChats:@[]];
				[me toast:[NSString stringWithFormat:@"%@ deleted.", title]];
			}];
		}
	}];
}

/// One chat at a time, through the picker the forward flow already uses -
/// a multiple-selection list of every chat is its own screen, and this works
/// today.
- (void)addChatToFolder:(NSInteger)folderId named:(NSString *)title {
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	__weak typeof(self) weakSelf = self;
	picker.onPicked = ^(int64_t chatId){
		[[TGClient shared] folderDetails:folderId completion:^(NSDictionary *current){
			TGSettingsViewController *me = weakSelf;
			if (!current){
				[me toast:@"That folder is gone."];
				return;
			}
			NSArray *included = current[@"included_chat_ids"] ?: @[];
			if ([included containsObject:@(chatId)]){
				[me toast:[NSString stringWithFormat:@"Already in %@.", title]];
				return;
			}
			[[TGClient shared] editFolder:folderId
									 name:nil
									chats:[included arrayByAddingObject:@(chatId)]
							   completion:^(BOOL ok){
				[me toast:ok ? [NSString stringWithFormat:@"Added to %@.", title]
							 : @"Telegram refused that change."];
			}];
		}];
	};
	picker.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:picker animated:YES];
}

/// The folder's own chats, by the names the chat list knows them under.
- (void)removeChatFromFolder:(NSInteger)folderId named:(NSString *)title {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] folderDetails:folderId completion:^(NSDictionary *current){
		TGSettingsViewController *me = weakSelf;
		NSArray *included = current[@"included_chat_ids"] ?: @[];
		if (!included.count){
			[me toast:[NSString stringWithFormat:@"%@ holds no chats yet.", title]];
			return;
		}

		NSMutableArray *names = [NSMutableArray array];
		for (NSNumber *chatId in included)
			[names addObject:TGChatNameForId(chatId)];
		[TGAlertSheet showChoices:names
							title:[NSString stringWithFormat:@"Remove from %@", title]
				 destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			NSMutableArray *left = [included mutableCopy];
			[left removeObjectAtIndex:(NSUInteger)index];
			[[TGClient shared] editFolder:folderId name:nil chats:left
							   completion:^(BOOL ok){
				[me toast:ok ? [NSString stringWithFormat:@"Removed from %@.", title]
							 : @"Telegram refused that change."];
			}];
		}];
	}];
}

#pragma mark - downloads

/// Their Download Manager: everything this account has pulled down, running
/// or finished, with the two things worth doing to one - stopping it, and
/// getting the disk back.
- (NSArray *)downloadSections {
	__weak typeof(self) weakSelf = self;

	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *download in self.downloads){
		long long size = [download[@"size"] longLongValue];
		NSString *state = [download[@"done"] boolValue] ? @"done"
				: ([download[@"paused"] boolValue] ? @"paused" : @"downloading");
		[rows addObject:TGTapRow(download[@"name"],
				[NSString stringWithFormat:@"%@ - %@", TGBytes(size), state], ^{
			[weakSelf runDownloadActionFor:download];
		})];
	}

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGSection(self.downloads.count ? @"Files" : nil,
			self.downloads.count
					? @"Tap one to pause it, take it out of the list, or free "
					  @"the disk it is using."
					: @"Nothing has been downloaded yet. A picture or a file "
					  @"opened in a chat appears here.",
			rows)];

	if (self.downloads.count)
		[sections addObject:TGSection(nil, nil, @[
			TGActionRow(self.activeDownloads > 0 ? @"Pause All" : @"Resume All", ^{
				[[TGClient shared] setAllDownloadsPaused:
						weakSelf.activeDownloads > 0];
				[weakSelf loadForPage];
			}),
			TGRedRow(@"Clear List and Free Disk", ^{
				[TGAlertSheet showConfirm:@"Every downloaded file is removed "
										  @"from this device. They can be "
										  @"fetched again from the chat."
									title:@"Clear Downloads"
								   action:@"Clear"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[[TGClient shared] clearDownloadsDeletingFromCache:YES];
					[weakSelf loadForPage];
				}];
			}),
		])];

	return sections;
}

- (void)runDownloadActionFor:(NSDictionary *)download {
	NSInteger fileId = [download[@"fileId"] integerValue];
	BOOL done = [download[@"done"] boolValue];
	BOOL paused = [download[@"paused"] boolValue];
	__weak typeof(self) weakSelf = self;

	NSMutableArray *choices = [NSMutableArray array];
	if (!done)
		[choices addObject:paused ? @"Resume" : @"Pause"];
	[choices addObject:@"Take Out of the List"];
	[choices addObject:@"Delete the File"];

	[TGAlertSheet showChoices:choices
						title:download[@"name"]
			 destructiveIndex:(NSInteger)choices.count - 1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSString *choice = choices[(NSUInteger)index];
		if ([choice isEqualToString:@"Pause"] || [choice isEqualToString:@"Resume"])
			[[TGClient shared] setDownloadOfFile:fileId
										  paused:[choice isEqualToString:@"Pause"]];
		else if ([choice isEqualToString:@"Take Out of the List"])
			[[TGClient shared] removeFileFromDownloads:fileId deleteFromCache:NO];
		else
			[[TGClient shared] removeFileFromDownloads:fileId deleteFromCache:YES];
		[weakSelf loadForPage];
	}];
}

#pragma mark - proxy

/// Their Proxy Settings page: a direct row at the top, then one row per
/// proxy, the one in use checked.
- (NSArray *)proxySections {
	__weak typeof(self) weakSelf = self;
	BOOL anyEnabled = NO;
	for (NSDictionary *proxy in self.proxies)
		anyEnabled = anyEnabled || [proxy[@"enabled"] boolValue];

	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:TGCheckRow(@"No proxy", nil, !anyEnabled, ^{
		[[TGClient shared] disableProxy];
		[weakSelf loadForPage];
	})];
	for (NSDictionary *proxy in self.proxies){
		NSString *name = [NSString stringWithFormat:@"%@:%@",
				proxy[@"server"] ?: @"?", proxy[@"port"] ?: @0];
		[rows addObject:TGCheckRow(name, proxy[@"kind"],
				[proxy[@"enabled"] boolValue], ^{
			[weakSelf runProxyActionFor:proxy];
		})];
	}

	return @[
		TGSection(@"Connection",
				  @"A proxy is TDLib's own, not the system's: it applies to "
				  @"this app and to nothing else on the phone.", rows),
		TGSection(nil, nil, @[
			TGActionRow(@"Add Proxy", ^{ [weakSelf addProxyByAsking]; }),
		]),
	];
}

/// One field takes both forms a proxy arrives in - the t.me link someone
/// sent, or a bare host and port - because asking which it is first would be
/// a screen of its own.
- (void)addProxyByAsking {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Add Proxy"
					message:@"A t.me/proxy or tg://proxy link, or host:port "
							@"for a SOCKS5 server."
				placeholder:@"t.me/proxy?... or 1.2.3.4:1080"
					   text:nil
					 action:@"Add"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGSettingsViewController *me = weakSelf;
		void (^added)(NSInteger) = ^(NSInteger proxyId){
			if (!proxyId){
				[me toast:@"Telegram could not read that as a proxy."];
				return;
			}
			[me loadForPage];
		};

		if ([text rangeOfString:@"proxy"].location != NSNotFound &&
			[text rangeOfString:@"?"].location != NSNotFound){
			if (![[TGClient shared] addProxyFromLink:text completion:added])
				[me toast:@"That link carries no server and port."];
			return;
		}

		NSArray *parts = [text componentsSeparatedByString:@":"];
		NSInteger port = parts.count > 1 ? [parts[1] integerValue] : 0;
		if (parts.count < 2 || port <= 0){
			[me toast:@"A proxy needs a host and a port."];
			return;
		}
		[[TGClient shared] addProxyAtServer:parts[0] port:port kind:@"socks5"
								   username:nil password:nil secret:nil
									 enable:YES completion:added];
	}];
}

- (void)runProxyActionFor:(NSDictionary *)proxy {
	NSInteger proxyId = [proxy[@"id"] integerValue];
	NSString *name = [NSString stringWithFormat:@"%@:%@",
			proxy[@"server"] ?: @"?", proxy[@"port"] ?: @0];
	__weak typeof(self) weakSelf = self;

	[TGAlertSheet showChoices:@[@"Use This Proxy", @"Check It Works",
								@"Change Address", @"Remove"]
						title:name
			 destructiveIndex:3
					   inView:self.view
					 onChoice:^(NSInteger index){
		TGSettingsViewController *me = weakSelf;
		if (index == 0){
			[[TGClient shared] enableProxy:proxyId];
			[me loadForPage];
		} else if (index == 1){
			[me checkProxy:proxy named:name];
		} else if (index == 2){
			[me editProxyAddress:proxy named:name];
		} else {
			[[TGClient shared] removeProxy:proxyId];
			[me loadForPage];
		}
	}];
}

/// Two questions, not one: whether it answers at all, and whether it will
/// carry Telegram. A proxy that completes a handshake and then refuses the
/// data centre is the failure a ping alone calls success.
- (void)checkProxy:(NSDictionary *)proxy named:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	NSString *server = proxy[@"server"];
	NSInteger port = [proxy[@"port"] integerValue];
	NSString *kind = proxy[@"kind"];

	[[TGClient shared] testProxyAtServer:server port:port kind:kind
								username:nil password:nil secret:nil
							  completion:^(BOOL works){
		TGSettingsViewController *me = weakSelf;
		if (!works){
			[me toast:[NSString stringWithFormat:
					@"%@ will not carry Telegram.", name]];
			return;
		}
		[[TGClient shared] pingProxyAtServer:server port:port kind:kind
									username:nil password:nil secret:nil
								  completion:^(double seconds){
			[me toast:seconds >= 0
					? [NSString stringWithFormat:@"%@ works - %.0f ms",
							name, seconds * 1000.0]
					: [NSString stringWithFormat:@"%@ works", name]];
		}];
	}];
}

/// Editing in place rather than removing and adding again, which lost the
/// proxy's position in the list and whether it was the one in use.
- (void)editProxyAddress:(NSDictionary *)proxy named:(NSString *)name {
	NSInteger proxyId = [proxy[@"id"] integerValue];
	BOOL wasEnabled = [proxy[@"enabled"] boolValue];
	NSString *kind = proxy[@"kind"];
	__weak typeof(self) weakSelf = self;

	[TGAlertSheet showInput:@"Change Address"
					message:@"host:port. The kind of proxy stays as it is."
				placeholder:@"1.2.3.4:1080"
					   text:name
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGSettingsViewController *me = weakSelf;
		NSArray *parts = [text componentsSeparatedByString:@":"];
		NSInteger port = parts.count > 1 ? [parts[1] integerValue] : 0;
		if (parts.count < 2 || port <= 0){
			[me toast:@"A proxy needs a host and a port."];
			return;
		}
		[[TGClient shared] editProxy:proxyId
							  server:parts[0]
								port:port
								kind:kind
							username:nil password:nil secret:nil
							  enable:wasEnabled
						  completion:^(BOOL ok){
			if (!ok){
				[me toast:@"Telegram refused that address."];
				return;
			}
			[me loadForPage];
		}];
	}];
}

- (void)clearTemporaryFiles {
	NSFileManager *files = [NSFileManager defaultManager];
	NSString *tmp = NSTemporaryDirectory();
	long long freed = 0;
	for (NSString *entry in [files contentsOfDirectoryAtPath:tmp error:nil]){
		NSString *path = [tmp stringByAppendingPathComponent:entry];
		freed += [[files attributesOfItemAtPath:path error:nil] fileSize];
		[files removeItemAtPath:path error:nil];
	}
	[self toast:[NSString stringWithFormat:@"Freed %@", TGBytes(freed)]];
}

- (void)toast:(NSString *)text {
	[TGAlertSheet showMessage:text title:nil inView:self.view];
}

@end
