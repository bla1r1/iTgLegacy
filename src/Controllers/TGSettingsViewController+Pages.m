#import "TGSettingsViewControllerInternal.h"

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
		// Profile header row
		TGSection(nil, nil, @[TGRow(TGKindProfile, @"")]),

		TGSection(nil, nil, @[
			TGActionRow(hasPhoto ? @"Change Profile Photo" : @"Set Profile Photo", ^{
				[weakSelf pickProfilePhoto];
			}),
		]),

		// Their accounts card: the one you are in, and a way to add another.
		TGSection(nil, nil, @[
			TGSubtitleRow([me[@"first_name"] length] ? me[@"first_name"] : @"This account",
					[me[@"phone"] length]
							? [NSString stringWithFormat:@"+%@", me[@"phone"]] : @"signed in",
					nil),
			TGActionRow(@"Add Account", ^{ [weakSelf explainAddAccount]; }),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"My Profile", @"privacy", TGRGB(1.00, 0.23, 0.18), ^{
				[weakSelf openMyProfile];
			}),
			TGIconRow(@"Edit Profile", @"chat", TGRGB(0.35, 0.34, 0.84), ^{
				UIViewController *edit = [[TGEditProfileViewController alloc] init];
				edit.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:edit animated:YES];
			}),
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
				[weakSelf showFolders];
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
			UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:
					@"Reset All Notifications"
					message:@"Every per-chat notification exception will be forgotten."
				   delegate:weakSelf cancelButtonTitle:@"Cancel"
		  otherButtonTitles:@"Reset", nil];
			confirm.tag = 61;
			[confirm show];
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

		TGSection(@"Who can see", nil, rules),

		TGSection(@"Contacts",
				  @"Frequent contacts are ranked on Telegram's side; turning "
				  @"the suggestion off deletes that ranking.", @[
			TGSwitchRow(@"Suggest Frequent Contacts", weakSelf.suggestFrequent, ^(BOOL on){
				weakSelf.suggestFrequent = on;
				[[TGClient shared] setOption:@"disable_top_chats" boolValue:!on];
			}),
			TGRedRow(@"Delete Synced Contacts", ^{
				UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:
						@"Delete Synced Contacts"
						message:@"The phone numbers this account uploaded to Telegram "
								@"will be removed."
					   delegate:weakSelf cancelButtonTitle:@"Cancel"
			  otherButtonTitles:@"Delete", nil];
				confirm.tag = 62;
				[confirm show];
			}),
		]),

		TGSection(nil,
				  @"If you do not come online at least once within this period, "
				  @"the account is deleted along with everything in it.", @[
			TGTapRow(@"Delete My Account", weakSelf.accountTtl > 0
					? [NSString stringWithFormat:@"if away for %ld months",
							(long)(weakSelf.accountTtl / 30)]
					: @"...", ^{
				UIActionSheet *sheet = [[UIActionSheet alloc]
						initWithTitle:@"Delete my account if away for"
							 delegate:weakSelf
					cancelButtonTitle:nil
			   destructiveButtonTitle:nil
					otherButtonTitles:@"1 month", @"3 months",
									  @"6 months", @"12 months", nil];
				sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
				sheet.tag = 90;
				[sheet showInView:weakSelf.view];
			}),
		]),
	];
}

- (NSArray *)dataSections {
	__weak typeof(self) weakSelf = self;
	BOOL mobile = [[TGClient shared] autoDownloadOverMobile];
	BOOL wifi   = [[TGClient shared] autoDownloadOverWifi];

	return @[
		TGSection(@"Usage", nil, @[
			TGTapRow(@"Storage Usage", nil, ^{
				TGStorageViewController *storage = [[TGStorageViewController alloc] init];
				storage.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:storage animated:YES];
			}),
			TGTapRow(@"Network Usage",
					[NSString stringWithFormat:@"%@ in, %@ out",
							TGBytes(weakSelf.networkReceived), TGBytes(weakSelf.networkSent)],
					^{
				UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:@"Network Usage"
						message:@"Reset the counters?"
					   delegate:weakSelf cancelButtonTitle:@"Cancel"
			  otherButtonTitles:@"Reset", nil];
				confirm.tag = 63;
				[confirm show];
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

		TGSection(nil, nil, @[
			TGRedRow(@"Clear Local Database", ^{
				UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:
						@"Clear Local Database"
						message:@"Cached chats and messages are dropped and fetched "
								@"again. The session stays."
					   delegate:weakSelf cancelButtonTitle:@"Cancel"
			  otherButtonTitles:@"Clear", nil];
				confirm.tag = 64;
				[confirm show];
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
				UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Theme"
						message:@"This file could not be read as a Telegram theme."
					   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
				[alert show];
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
			: @"This device is below the tier that plays these at all, so the "
			  @"first two switches change nothing here.";

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
	UIFont *emoji = [UIFont fontWithName:@"OpenMojiColor" size:12]
			?: [UIFont fontWithName:@"OpenMoji" size:12];

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
				UIAlertView *confirm = [[UIAlertView alloc] initWithTitle:
						@"Reset Local Preferences"
						message:@"Theme, text size and every switch in Settings go "
								@"back to their defaults."
					   delegate:weakSelf cancelButtonTitle:@"Cancel"
			  otherButtonTitles:@"Reset", nil];
				confirm.tag = 65;
				[confirm show];
			}),
		]),
	];
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
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:text
			delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

@end
