#import "TGSettingsViewControllerInternal.h"
#import "TGAlertSheet.h"
#import "TGForwardPicker.h"
#import "TGListViewController.h"
#import "TGStyle.h"
#import "TGGalleryViewController.h"
#import "AppDelegate.h"
#import "TGChatViewController.h"
#import "TGDevShowcase.h"
#import "TGStickerPacksViewController.h"
#import "TGStorySettingsViewController.h"
#import "TGStoriesMenuViewController.h"
#import "TGSettingsViewController+Tier2.h"
#import "TGSponsoredMessagesViewController.h"
#import "TGEnvironmentViewController.h"
#import "TGBotConsoleViewController.h"
#import "TGStarsGiftsViewController.h"
#import "TGTestHarnessViewController.h"
#import "TGAffiliateProgramsViewController.h"
#import "TGSupportInfoViewController.h"

/// A custom method's answer is a string the app has no schema for. When it is
/// JSON, pretty-print it so the viewer reads like a response rather than one
/// long line; otherwise show it as the lines TDLib sent.
static NSArray *TGCustomResultRows(NSString *result) {
	NSMutableArray *rows = [NSMutableArray array];
	NSString *text = result.length ? result : @"(empty result)";
	NSData *raw = [text dataUsingEncoding:NSUTF8StringEncoding];
	id parsed = raw.length
			? [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil] : nil;
	if (parsed){
		NSData *pretty = [NSJSONSerialization dataWithJSONObject:parsed
				options:NSJSONWritingPrettyPrinted error:nil];
		if (pretty.length)
			text = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding]
					?: text;
	}
	for (NSString *line in [text componentsSeparatedByString:@"\n"]){
		NSMutableDictionary *row = [@{@"title" : line ?: @""} mutableCopy];
		[rows addObject:row];
	}
	return rows;
}

@implementation TGSettingsViewController (Pages)

#pragma mark - pages

- (NSArray *)buildSections {
	switch (self.page){
		case TGSettingsPageAppearance:    return [self appearanceSections];
		case TGSettingsPageData:          return [self dataSections];
		case TGSettingsPageNotifications: return [self notificationSections];
		case TGSettingsPageNotificationSounds: return [self soundSections];
		case TGSettingsPageActiveNotifications:
			return [self activeNotificationSections];
		case TGSettingsPagePrivacy:       return [self privacySections];
		case TGSettingsPageLanguage:      return [self languageSections];
		case TGSettingsPageBlocked:       return [self blockedSections];
		case TGSettingsPagePowerSaving:   return [self powerSavingSections];
		case TGSettingsPageRecentCalls:   return [self recentCallSections];
		case TGSettingsPageFolders:       return [self folderSections];
		case TGSettingsPageProxy:         return [self proxySections];
		case TGSettingsPageDownloads:     return [self downloadSections];
		case TGSettingsPageAutosave:      return [self autosaveSections];
		case TGSettingsPageWallpaper:     return [self wallpaperSections];
		case TGSettingsPagePaymentData:   return [self paymentSections];
		case TGSettingsPageDebug:         return [self debugSections];
		default:                          return [self rootSections];
	}
}

- (NSArray *)rootSections {
	__weak typeof(self) weakSelf = self;
	NSDictionary *me = [TGClient shared].me;
	BOOL hasPhoto = [[TGClient shared] photoFileIdForUserId:
			[me[@"id"] longLongValue]] != nil;

	// The values Telegram shows on the right of these rows. They stay nil
	// until the client answers, so a slow network leaves the row exactly as
	// it was instead of a dash that never fills in.
	NSString *username = [me[@"username"] length]
			? [NSString stringWithFormat:@"@%@", me[@"username"]] : nil;
	NSString *devicesDetail = self.rootDeviceName.length
			? (self.rootSessionCount > 0
					? [NSString stringWithFormat:@"%ld active", (long)self.rootSessionCount]
					: self.rootDeviceName)
			: nil;
	NSString *foldersDetail = [TGClient shared].folders.count
			? [NSString stringWithFormat:@"%lu",
					(unsigned long)[TGClient shared].folders.count]
			: nil;
	NSString *cacheDetail = self.rootCacheLoaded
			? TGBytes(self.rootCacheBytes) : nil;
	NSString *languageDetail = self.rootLanguageName.length
			? self.rootLanguageName : self.currentLanguage;
	NSString *proxyDetail = self.rootProxyDetail.length
			? self.rootProxyDetail : @"Off";

	return @[
		// Profile header card. The account's name and phone are the first
		// thing on the official page, and the rows under it act on that
		// account rather than on any one setting.
		TGSection(nil, nil, @[
			TGRow(TGKindProfile, @""),
		]),

		TGSection(nil, nil, @[
			// Rows like every other in Settings: a glyph on a tile, dark text,
			// a chevron. Two bare blue lines above an icon row read as a
			// different list that had lost its margin.
			([TGClient shared].authState != TGAuthStateReady) ? TGIconRow(@"Log in to Telegram", @"privacy", TGIconTileAzure(), ^{
				[[AppDelegate sharedDelegate] showLoginUI];
			}) : TGIconRow(@"Add Account", @"select", TGIconTileAzure(), ^{ [weakSelf explainAddAccount]; }),
			TGIconRow(hasPhoto ? @"Change Profile Photo" : @"Set Profile Photo", @"react", TGIconTileCoral(), ^{
				[weakSelf pickProfilePhoto];
			}),
			TGIconTapRow(@"Edit Profile", username, @"chat", TGIconTileViolet(), ^{
				UIViewController *edit = [[TGEditProfileViewController alloc] init];
				edit.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:edit animated:YES];
			}),
		]),

		// The chats and the devices they live on. Telegram keeps these above
		// the settings that change how the app looks and sounds.
		TGSection(nil, nil, @[
			TGIconRow(@"Saved Messages", @"folder", TGIconTileSky(), ^{
				[weakSelf openSavedMessages];
			}),
			TGIconRow(@"Recent Calls", @"call", TGIconTileGreen(), ^{
				[weakSelf openPage:TGSettingsPageRecentCalls];
			}),
			TGIconTapRow(@"Devices", devicesDetail, @"devices", TGIconTileAmber(), ^{
				TGSessionsViewController *sessions = [[TGSessionsViewController alloc] init];
				sessions.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:sessions animated:YES];
			}),
			TGIconTapRow(@"Chat Folders", foldersDetail, @"folder", TGIconTileCyan(), ^{
				[weakSelf openPage:TGSettingsPageFolders];
			}),
			TGIconRow(@"Stories", @"notifications", TGIconTileRed(), ^{
				// Telegram keeps the story archive, albums, live story and the
				// per-chat notification exceptions together. This row used to
				// land on the exception list alone, so archive management was
				// reachable only by holding the strip.
				TGStoriesMenuViewController *stories =
						[[TGStoriesMenuViewController alloc] initWithChatId:
								[[TGClient shared] savedMessagesChatId]
								title:@"My Story"];
				stories.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:stories animated:YES];
			}),
			[weakSelf tier2ToolsRow],
			TGIconTapRow(@"Proxy", proxyDetail, @"data", TGIconTileGrey(), ^{
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
			TGIconTapRow(@"Data and Storage", cacheDetail, @"data", TGIconTileGreen(), ^{
				[weakSelf openPage:TGSettingsPageData];
			}),
			TGIconRow(@"Appearance", @"chat", TGIconTileSky(), ^{
				[weakSelf openPage:TGSettingsPageAppearance];
			}),
			TGIconRow(@"Power Saving", @"battery", TGIconTileAmber(), ^{
				[weakSelf openPage:TGSettingsPagePowerSaving];
			}),
			TGIconTapRow(@"Language", languageDetail, @"language", TGIconTileViolet(), ^{
				[weakSelf openPage:TGSettingsPageLanguage];
			}),
			TGIconTapRow(@"This Device", [TGDevice tierName], @"devices", TGIconTileSlate(), ^{
				TGDeviceViewController *device = [[TGDeviceViewController alloc] init];
				device.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:device animated:YES];
			}),
		]),

		// Stickers and the chat look are a pair in Telegram's list, so they
		// are one card here rather than one row in a card of settings.
		TGSection(nil, nil, @[
			TGIconRow(@"Stickers and Emoji", @"star", TGIconTileViolet(), ^{
				TGStickerPacksViewController *packs =
						[[TGStickerPacksViewController alloc] init];
				packs.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:packs animated:YES];
			}),
			TGIconRow(@"Chat Themes", @"chat", TGIconTileSky(), ^{
				[weakSelf openPage:TGSettingsPageAppearance];
			}),
		]),

		TGSection(nil, nil, @[
			TGIconRow(@"Telegram Premium", @"star", TGIconTilePurple(), ^{
				[weakSelf showPremiumState];
			}),
			[weakSelf tier2BusinessRow],
			TGIconRow(@"Send a Gift", @"gift", TGIconTileCoral(), ^{
				[weakSelf pushPlaceholder:@"Send a Gift"];
			}),
		]),

		// Help last, the way the official client ends the list before Log
		// Out. Every row here existed before; they were mixed in with the
		// account rows and read as settings rather than support.
		TGSection(@"Help", nil, @[
			TGIconRow(@"Ask a Question", @"chat", TGIconTileAmber(), ^{
				[weakSelf openSupport];
			}),
			TGIconRow(@"Support Info", @"data", TGIconTileAmber(), ^{
				TGSupportInfoViewController *support =
						[[TGSupportInfoViewController alloc] init];
				support.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:support animated:YES];
			}),
			TGIconRow(@"Telegram FAQ", @"faq", TGIconTileCyan(), ^{
				[weakSelf openURL:@"https://telegram.org/faq"];
			}),
			TGIconRow(@"Telegram Features", @"star", TGIconTileGold(), ^{
				[weakSelf openURL:@"https://telegram.org/blog"];
			}),
			TGIconRow(@"Privacy Policy", @"policy", TGIconTileGold(), ^{
				[weakSelf openURL:@"https://telegram.org/privacy"];
			}),
			TGIconRow(@"Get the App", @"data", TGIconTileSky(), ^{
				[[TGClient shared] applicationDownloadLinkWithCompletion:^(NSString *url){
					if (!url.length){
						[weakSelf toast:@"Telegram did not answer with a download link."];
						return;
					}
					[weakSelf openURL:url];
				}];
			}),
		]),

		// Emoji status, profile audio, text styles and the stake dice panel:
		// the profile-extras wave answers from one category and the root list
		// only places it.
		[[self tier2Sections] firstObject] ?: TGSection(nil, nil, @[]),

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
			weakSelf.languagePackStrings = nil;
			// The record follows the choice: pack actions edit what is on.
			[[TGClient shared] languagePackInfo:packId completion:^(NSDictionary *info){
				weakSelf.languageInfo = info;
				[weakSelf rebuild];
			}];
			[weakSelf rebuild];
		})];
	}
	if (!rows.count)
		[rows addObject:TGRow(TGKindPlain, @"Loading...")];

	NSString *code = self.countryCode ?: @"US";
	NSString *countryName = self.countryInfo[@"name"] ?: code;
	NSString *flag = self.countryFlag.length ? self.countryFlag
			: (self.countryInfo[@"flag"] ?: @"");
	NSString *countryDetail = flag.length
			? [NSString stringWithFormat:@"%@  %@", flag, countryName]
			: countryName;
	NSString *preferred = self.preferredCountryLanguage ?: @"Unknown";
	NSMutableDictionary *preferredRow =
			TGRow(TGKindPlain, @"Preferred Country Language");
	preferredRow[TGRowDetail] = preferred;
	NSArray *countryRows = @[
		TGTapRow(@"Country", countryDetail, ^{ [weakSelf askCountryCode]; }),
		preferredRow,
	];

	NSString *packName = self.languageInfo[@"name"] ?: self.currentLanguage ?: @"en";
	NSString *packDetail = self.languageInfo
			? [NSString stringWithFormat:@"%@ of %@ strings",
					self.languageInfo[@"translated"] ?: @(0),
					self.languageInfo[@"total"] ?: @(0)]
			: @"Read the current pack";
	NSString *stringsDetail = weakSelf.languagePackStrings
			? [NSString stringWithFormat:@"%lu strings read",
					(unsigned long)weakSelf.languagePackStrings.count]
			: @"Read the pack's strings back";
	NSArray *packRows = @[
		TGTapRow(@"Pack Info", packDetail, ^{ [weakSelf showLanguagePackInfo]; }),
		TGTapRow(@"Strings", stringsDetail, ^{
			[weakSelf showLanguagePackStrings];
		}),
		TGTapRow(@"Read a String", @"One key from the local database", ^{
			[weakSelf readLanguagePackString];
		}),
	];

	NSArray *editRows = @[
		TGTapRow(@"New Custom Pack", @"A local pack, id starts with X", ^{
			[weakSelf createCustomLanguagePack];
		}),
		TGTapRow(@"Edit Pack Name", packName, ^{ [weakSelf editLanguagePackName]; }),
		TGTapRow(@"Set a String", @"Add or change one key", ^{
			[weakSelf setLanguagePackString];
		}),
		TGTapRow(@"Delete a String", @"Fall back to the base pack", ^{
			[weakSelf deleteLanguagePackString];
		}),
		TGTapRow(@"Install Pack from Telegram", @"Add a server pack by id", ^{
			[weakSelf installServerLanguagePack];
		}),
		TGTapRow(@"Synchronize Pack", @"Fetch the latest strings", ^{
			[weakSelf synchronizeCurrentLanguagePack];
		}),
		TGRedRow(@"Delete Pack", ^{ [weakSelf deleteCurrentLanguagePack]; }),
	];

	return @[
		TGSection(nil,
			@"This app's own text is English throughout. The language is what "
			@"Telegram itself writes in, and it follows the account onto your "
			@"other devices.", rows),
		TGSection(@"Country",
			@"Telegram answers the country's name, flag and preferred language; "
			@"the code is the two-letter ISO one.", countryRows),
		TGSection(@"Current Pack",
			@"Pack info, the strings it carries and a read-back of one key.", packRows),
		TGSection(@"Custom Packs",
			@"A local pack starts with X and overrides the base one string at a "
			@"time. Install adds a pack Telegram already serves.", editRows),
	];
}

/// The country rows are read once per open; changing the code re-reads all
/// three answers rather than leaving a flag from the previous country.
- (void)askCountryCode {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Country Code"
					message:@"Two-letter ISO 3166-1 code, for example DE."
				placeholder:@"DE"
					   text:self.countryCode ?: @""
					 action:@"Read"
					 inView:self.view
				 onSubmit:^(NSString *text){
		NSString *code = text.uppercaseString;
		weakSelf.countryCode = code;
		[[TGClient shared] countryInfoForCode:code completion:^(NSDictionary *country){
			weakSelf.countryInfo = country;
			[weakSelf rebuild];
		}];
		[[TGClient shared] preferredCountryLanguageForCode:code
												completion:^(NSString *language){
			weakSelf.preferredCountryLanguage = language;
			[weakSelf rebuild];
		}];
		[[TGClient shared] countryFlagEmojiForCode:code completion:^(NSString *emoji){
			weakSelf.countryFlag = emoji;
			[weakSelf rebuild];
		}];
	}];
}

- (void)showLanguagePackInfo {
	NSString *packId = self.currentLanguage ?: @"en";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] languagePackInfo:packId completion:^(NSDictionary *info){
		weakSelf.languageInfo = info;
		[weakSelf rebuild];
		if (!info){
			[TGAlertSheet showMessage:@"Telegram returned no record for this pack."
							   title:@"Language Pack"
							   inView:weakSelf.view];
			return;
		}
		NSMutableString *body = [NSMutableString string];
		NSString *displayName = info[@"nativeName"] ?: info[@"name"] ?: info[@"id"];
		[body appendFormat:@"%@ (%@)\n", displayName ?: @"Unknown", info[@"id"]];
		if ([info[@"name"] length] && ![info[@"name"] isEqualToString:info[@"nativeName"]])
			[body appendFormat:@"English name: %@\n", info[@"name"]];
		[body appendFormat:@"Base: %@\nStrings: %@ of %@ translated, %@ local\n",
				info[@"base"] ?: @"none", info[@"translated"] ?: @(0),
				info[@"total"] ?: @(0), info[@"local"] ?: @(0)];
		[body appendFormat:@"Official: %@ · Installed: %@ · RTL: %@",
				[info[@"official"] boolValue] ? @"yes" : @"no",
				[info[@"installed"] boolValue] ? @"yes" : @"no",
				[info[@"rtl"] boolValue] ? @"yes" : @"no"];
		[TGAlertSheet showMessage:body title:@"Language Pack" inView:weakSelf.view];
	}];
}

- (void)showLanguagePackStrings {
	NSString *packId = self.currentLanguage ?: @"en";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] languagePackStrings:packId keys:@[] completion:^(NSArray *strings){
		if (!weakSelf)
			return;
		weakSelf.languagePackStrings = strings;
		[weakSelf rebuild];
		if (!strings.count){
			[TGAlertSheet showMessage:@"This pack has no strings on the device yet."
							   title:@"Strings"
							   inView:weakSelf.view];
			return;
		}
		NSMutableString *body = [NSMutableString string];
		NSUInteger shown = MIN(strings.count, (NSUInteger)20);
		for (NSUInteger i = 0; i < shown; i++){
			NSDictionary *string = strings[i];
			[body appendFormat:@"%@ = %@\n", string[@"key"], string[@"value"]];
		}
		if (strings.count > shown)
			[body appendFormat:@"…and %lu more.", (unsigned long)(strings.count - shown)];
		[TGAlertSheet showMessage:body
						   title:[NSString stringWithFormat:@"%@ Strings", packId]
						   inView:weakSelf.view];
	}];
}

- (void)readLanguagePackString {
	NSString *packId = self.currentLanguage ?: @"en";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Read a String"
					message:@"The key as the pack stores it, for example Continue."
				placeholder:@"Continue"
					   text:@""
					 action:@"Read"
					 inView:self.view
				 onSubmit:^(NSString *key){
		[[TGClient shared] languagePackString:key pack:packId
								   completion:^(NSString *value, NSString *kind){
			if (!weakSelf)
				return;
			NSString *body = value == nil
					? @"That key is not in this pack."
					: [NSString stringWithFormat:@"%@ = %@ (%@)", key, value, kind ?: @"value"];
			[TGAlertSheet showMessage:body title:@"Language String" inView:weakSelf.view];
		}];
	}];
}

- (void)createCustomLanguagePack {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"New Custom Pack"
					message:@"An id for the local pack. X is added when missing."
				placeholder:@"Xmytest"
					   text:@"X"
					 action:@"Next"
					 inView:self.view
				 onSubmit:^(NSString *packId){
		[TGAlertSheet showInput:@"Pack Name"
						message:@"What the language list calls this pack."
					placeholder:@"My Test Pack"
						   text:@""
						 action:@"Create"
						 inView:weakSelf.view
					 onSubmit:^(NSString *name){
			[[TGClient shared] setCustomLanguagePack:packId name:name
										  nativeName:name strings:@[]
										  completion:^(BOOL ok){
				if (!weakSelf)
					return;
				if (ok){
					NSString *customId = [packId hasPrefix:@"X"] ? packId
							: [@"X" stringByAppendingString:packId];
					weakSelf.currentLanguage = customId;
					[[TGClient shared] setLanguage:customId];
					[[TGClient shared] languagePackInfo:customId
											completion:^(NSDictionary *info){
						weakSelf.languageInfo = info;
						[weakSelf rebuild];
					}];
				}
				[weakSelf toast:ok ? @"Custom pack created" : @"Telegram refused the pack"];
				[weakSelf refreshLanguagePage];
			}];
		}];
	}];
}

- (void)editLanguagePackName {
	NSString *packId = self.currentLanguage ?: @"en";
	__weak typeof(self) weakSelf = self;
	void (^ask)(NSDictionary *) = ^(NSDictionary *info){
		if (!weakSelf)
			return;
		if (!info){
			[TGAlertSheet showMessage:@"Read Pack Info first."
							   title:@"Edit Pack"
							   inView:weakSelf.view];
			return;
		}
		[TGAlertSheet showInput:@"Edit Pack Name"
						message:@"Only a custom local pack can be changed."
					placeholder:@"Name"
						   text:info[@"name"] ?: @""
						 action:@"Save"
						 inView:weakSelf.view
					 onSubmit:^(NSString *name){
			NSMutableDictionary *changed = [info mutableCopy];
			changed[@"name"] = name;
			changed[@"nativeName"] = name;
			[[TGClient shared] editCustomLanguagePackInfo:changed completion:^(BOOL ok){
				if (!weakSelf)
					return;
				[weakSelf toast:ok ? @"Pack renamed" : @"Telegram refused the edit"];
				[weakSelf refreshLanguagePage];
			}];
		}];
	};
	if (self.languageInfo)
		ask(self.languageInfo);
	else
		[[TGClient shared] languagePackInfo:packId completion:^(NSDictionary *info){
			ask(info);
		}];
}

- (void)setLanguagePackString {
	NSString *packId = self.currentLanguage ?: @"Xcustom";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Set a String"
					message:@"The key to add or change in this local pack."
				placeholder:@"Continue"
					   text:@""
					 action:@"Next"
					 inView:self.view
				 onSubmit:^(NSString *key){
		[TGAlertSheet showInput:@"String Value"
						message:[NSString stringWithFormat:@"Value for %@.", key]
					placeholder:@"Continue"
						   text:@""
						 action:@"Save"
						 inView:weakSelf.view
					 onSubmit:^(NSString *value){
			[[TGClient shared] setCustomLanguagePackString:key value:value
													 pack:packId
											   completion:^(BOOL ok){
				if (!weakSelf)
					return;
				[weakSelf toast:ok ? @"String saved" : @"Telegram refused the string"];
				[weakSelf refreshLanguagePage];
			}];
		}];
	}];
}

- (void)deleteLanguagePackString {
	NSString *packId = self.currentLanguage ?: @"Xcustom";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Delete a String"
					message:@"The key falls back to the base pack."
				placeholder:@"Continue"
					   text:@""
					 action:@"Delete"
					 inView:self.view
				 onSubmit:^(NSString *key){
		[[TGClient shared] setCustomLanguagePackString:key value:nil
												 pack:packId
										   completion:^(BOOL ok){
			if (!weakSelf)
				return;
			[weakSelf toast:ok ? @"String deleted" : @"Telegram refused the delete"];
			[weakSelf refreshLanguagePage];
		}];
	}];
}

- (void)installServerLanguagePack {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Install Language Pack"
					message:@"The id Telegram serves, for example de."
				placeholder:@"de"
					   text:@""
					 action:@"Install"
					 inView:self.view
				 onSubmit:^(NSString *packId){
		[[TGClient shared] addCustomServerLanguagePack:packId completion:^(BOOL ok){
			if (!weakSelf)
				return;
			[weakSelf toast:ok ? @"Pack installed" : @"Telegram refused the pack"];
			[weakSelf refreshLanguagePage];
		}];
	}];
}

- (void)synchronizeCurrentLanguagePack {
	NSString *packId = self.currentLanguage ?: @"en";
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] synchronizeLanguagePack:packId completion:^(BOOL ok){
		if (!weakSelf)
			return;
		[weakSelf toast:ok ? @"Strings synchronized" : @"Telegram refused the sync"];
		[weakSelf refreshLanguagePage];
	}];
}

- (void)deleteCurrentLanguagePack {
	NSString *packId = self.currentLanguage ?: @"en";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:[NSString stringWithFormat:@"%@ is removed from this device. The pack Telegram serves is untouched.", packId]
						title:@"Delete Pack"
					   action:@"Delete"
				  destructive:YES
					   inView:self.view
					onConfirm:^{
		[[TGClient shared] deleteLanguagePack:packId completion:^(BOOL ok){
			if (!weakSelf)
				return;
			[weakSelf toast:ok ? @"Pack deleted" : @"Telegram refused: a pack in use cannot be deleted"];
			weakSelf.languageInfo = nil;
			[weakSelf refreshLanguagePage];
		}];
	}];
}

- (void)refreshLanguagePage {
	[self rebuild];
	[self loadForPage];
}

static NSString *TGCallRecordWhen(NSNumber *stamp) {
	NSTimeInterval seconds = stamp.doubleValue;
	if (seconds <= 0)
		return @"unknown time";
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	}
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

/// The record this client writes for sendCallLog. TDLib's own log is not a
/// file this app can read - setLogStream is a stream the client would have to
/// own - so the log it sends is the call's facts and the device it ran on.
static NSString *TGCallLogText(NSDictionary *call) {
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;
	return [NSString stringWithFormat:
			@"LegacyTG call log\n"
			@"Client: LegacyTG %@ (%@)\n"
			@"System: iOS %@\n"
			@"Device: %@\n"
			@"Call: %@\n"
			@"Direction: %@\n"
			@"Time: %@\n"
			@"Duration: %ld s\n"
			@"Missed: %@\n"
			@"Chat: %lld\n"
			@"Message: %lld\n",
			info[@"CFBundleShortVersionString"] ?: @"?",
			info[@"CFBundleVersion"] ?: @"?",
			[UIDevice currentDevice].systemVersion ?: @"?",
			[TGDevice modelName] ?: @"?",
			call[@"name"] ?: @"?",
			[call[@"outgoing"] boolValue] ? @"outgoing" : @"incoming",
			TGCallRecordWhen(call[@"date"]),
			(long)[call[@"duration"] integerValue],
			[call[@"missed"] boolValue] ? @"yes" : @"no",
			(long long)[call[@"chatId"] longLongValue],
			(long long)[call[@"messageId"] longLongValue]];
}

/// The debug record: the same facts as JSON, because that is what TDLib
/// forwards and what Telegram's call team reads.
static NSString *TGCallDebugText(NSDictionary *call) {
	NSDictionary *record = @{
		@"client"    : @"LegacyTG",
		@"system"    : [NSString stringWithFormat:@"iOS %@",
						[UIDevice currentDevice].systemVersion ?: @"?"],
		@"device"    : [TGDevice modelName] ?: @"?",
		@"peer"      : call[@"name"] ?: @"?",
		@"outgoing"  : [call[@"outgoing"] boolValue] ? @"yes" : @"no",
		@"missed"    : [call[@"missed"] boolValue] ? @"yes" : @"no",
		@"date"      : call[@"date"] ?: @0,
		@"duration"  : call[@"duration"] ?: @0,
		@"chat_id"   : call[@"chatId"] ?: @0,
		@"message_id": call[@"messageId"] ?: @0,
	};
	NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:NULL];
	if (!json)
		return nil;
	return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
}

/// Telegram changed a pack. The page re-reads its record so the translated
/// count moves, and a string list it had already read is read again: the
/// update carries only what changed, not a complete pack to draw.
- (void)languagePackStringsChanged:(NSString *)packId {
	if (self.page != TGSettingsPageLanguage)
		return;
	if (!packId.length || ![packId isEqualToString:self.currentLanguage ?: @""])
		return;
	[self loadForPage];
	if (!self.languagePackStrings.count)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] languagePackStrings:packId keys:@[]
								completion:^(NSArray *strings){
		weakSelf.languagePackStrings = strings;
		[weakSelf rebuild];
	}];
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
		NSString *key = [NSString stringWithFormat:@"%lld:%lld",
				(long long)[call[@"chatId"] longLongValue],
				(long long)[call[@"messageId"] longLongValue]];
		NSArray *already = weakSelf.callDiagnostics[key];
		if (already.count){
			NSMutableArray *done = [NSMutableArray array];
			if ([already containsObject:@"log"])
				[done addObject:@"log sent"];
			if ([already containsObject:@"debug"])
				[done addObject:@"debug sent"];
			if (done.count)
				detail = [NSString stringWithFormat:@"%@ · %@", detail,
						[done componentsJoinedByString:@", "]];
		}

		NSMutableDictionary *row = [TGSubtitleRow(call[@"name"], detail, ^{
			[weakSelf runRecentCallActionFor:call];
		}) mutableCopy];
		if (missed)
			row[TGRowKind] = TGKindDestructive;
		[rows addObject:row];
	}
	return @[TGSection(nil, nil, rows)];
}

/// A finished call leaves a message, and that message is an InputCall. The
/// action sheet offers the two diagnostics TDLib accepts for one, and shows
/// Telegram's own sentence when it refuses - a user account usually is.
- (void)runRecentCallActionFor:(NSDictionary *)call {
	NSString *name = call[@"name"] ?: @"Call";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Send Call Log", @"Send Debug Information"]
						title:name
					  message:[NSString stringWithFormat:@"%@ · %@",
							  [call[@"outgoing"] boolValue] ? @"Outgoing" : @"Incoming",
							  TGCallRecordWhen(call[@"date"])]
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		int64_t chatId = [call[@"chatId"] longLongValue];
		int64_t messageId = [call[@"messageId"] longLongValue];
		if (!chatId || !messageId){
			[TGAlertSheet showMessage:@"This call record has no message to report."
								title:name inView:weakSelf.view];
			return;
		}
		if (index == 0){
			NSString *log = TGCallLogText(call);
			[[TGClient shared] sendCallLog:log forMessage:messageId inChat:chatId
								completion:^(BOOL ok, NSString *error){
				if (ok)
					[weakSelf noteCallDiagnostic:@"log" forCall:call];
				[TGAlertSheet showMessage:(ok ? @"Telegram accepted the call log."
						: (error ?: @"Telegram refused the call log."))
									title:@"Send Call Log" inView:weakSelf.view];
			}];
			return;
		}
		NSString *debug = TGCallDebugText(call);
		if (!debug.length){
			[TGAlertSheet showMessage:@"The debug record could not be encoded."
								title:name inView:weakSelf.view];
			return;
		}
		[[TGClient shared] sendCallDebugInformation:debug
										forMessage:messageId
											inChat:chatId
										completion:^(BOOL ok, NSString *error){
			if (ok)
				[weakSelf noteCallDiagnostic:@"debug" forCall:call];
			[TGAlertSheet showMessage:(ok ? @"Telegram accepted the debug information."
					: (error ?: @"Telegram refused the debug information."))
								title:@"Send Debug Information" inView:weakSelf.view];
		}];
	}];
}

#pragma mark - orders and payment data

/// Every non-empty line of an orderInfo, so the sheet reads like the form it
/// came from instead of a raw object.
static NSString *TGOrderLines(NSDictionary *order) {
	if (![order isKindOfClass:NSDictionary.class])
		return @"";
	NSMutableArray *lines = [NSMutableArray array];
	NSArray *keys = @[@"name", @"phone_number", @"email_address"];
	NSArray *titles = @[@"Name", @"Phone", @"Email"];
	for (NSUInteger i = 0; i < keys.count; i++){
		NSString *value = order[keys[i]];
		if ([value isKindOfClass:NSString.class] && value.length)
			[lines addObject:[NSString stringWithFormat:@"%@: %@", titles[i], value]];
	}
	NSDictionary *address = order[@"shipping_address"];
	if ([address isKindOfClass:NSDictionary.class]){
		NSArray *parts = @[@"street_line1", @"street_line2", @"city", @"state",
						   @"postal_code", @"country_code"];
		NSMutableArray *where = [NSMutableArray array];
		for (NSString *key in parts){
			NSString *value = address[key];
			if ([value isKindOfClass:NSString.class] && value.length)
				[where addObject:value];
		}
		if (where.count)
			[lines addObject:[NSString stringWithFormat:@"Address: %@",
					[where componentsJoinedByString:@", "]]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

- (NSArray *)paymentSections {
	__weak typeof(self) weakSelf = self;
	NSString *orderDetail;
	if (!self.savedOrderLoaded)
		orderDetail = @"Reading...";
	else if (self.savedOrder)
		orderDetail = self.savedOrder[@"name"] ?: @"Saved";
	else
		orderDetail = @"None saved";

	NSMutableArray *orderRows = [NSMutableArray array];
	[orderRows addObject:TGTapRow(@"Saved Order Info", orderDetail, ^{
		NSString *body = weakSelf.savedOrder
				? TGOrderLines(weakSelf.savedOrder)
				: (weakSelf.savedOrderError ?: @"Telegram has no order saved.");
		[TGAlertSheet showMessage:body.length ? body : @"The saved order is empty."
							title:@"Saved Order Info"
						   inView:weakSelf.view];
	})];
	if (self.savedOrder){
		[orderRows addObject:TGRedRow(@"Delete Saved Order Info", ^{
			[TGAlertSheet showConfirm:@"The address and phone Telegram kept "
									  @"from the last checkout are forgotten. "
									  @"The next checkout asks for them again."
								title:@"Delete Saved Order Info"
							   action:@"Delete"
						  destructive:YES
							   inView:weakSelf.view
							onConfirm:^{
				[[TGClient shared] deleteSavedOrderInfoWithCompletion:^(BOOL ok,
																		NSString *error){
					if (!ok){
						[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
											title:@"Delete Saved Order Info"
										   inView:weakSelf.view];
						return;
					}
					weakSelf.savedOrder = nil;
					weakSelf.savedOrderError = nil;
					weakSelf.savedOrderLoaded = YES;
					[weakSelf rebuild];
				}];
			}];
		})];
	}

	return @[
		TGSection(@"Saved order",
				  @"The checkout Telegram remembers: name, phone, email and "
				  @"shipping address from the last payment.", orderRows),

		TGSection(@"Bank card",
				  @"The number is looked up, not stored. Telegram's provider "
				  @"answers with the card's title and the links its own page "
				  @"opens.", @[
			TGActionRow(@"Look Up a Card", ^{ [weakSelf showBankCardLookup]; }),
		]),

		TGSection(@"Suggested post offer",
				  @"An offer puts a Stars price on a suggested post in a channel "
				  @"direct-messages chat. The message has to allow it; otherwise "
				  @"Telegram's refusal is shown.", @[
			TGActionRow(@"Add an Offer", ^{ [weakSelf addOfferFlow]; }),
		]),

		TGSection(@"Order validation",
				  @"Checks an order against a named invoice and reads back the "
				  @"shipping options Telegram offers. Nothing is charged.", @[
			TGActionRow(@"Validate an Order", ^{ [weakSelf validateOrderFlow]; }),
		]),
	];
}

- (void)showBankCardLookup {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Look Up a Card"
					message:@"The card number. It is sent to Telegram's provider "
							@"for this lookup only."
				placeholder:@"4111 1111 1111 1111"
					 text:nil action:@"Look Up" inView:self.view
				 onSubmit:^(NSString *number){
		[[TGClient shared] bankCardInfoForNumber:number
									  completion:^(NSDictionary *info, NSString *error){
			if (!info){
				[TGAlertSheet showMessage:(error ?: @"The provider did not answer.")
									title:@"Bank Card"
								   inView:weakSelf.view];
				return;
			}
			NSString *title = info[@"title"] ?: @"Card";
			NSArray *actions = [info[@"actions"] isKindOfClass:NSArray.class]
					? info[@"actions"] : @[];
			NSMutableArray *titles = [NSMutableArray array];
			for (NSDictionary *action in actions){
				NSString *text = action[@"text"];
				if ([text isKindOfClass:NSString.class] && text.length)
					[titles addObject:text];
			}
			if (!titles.count){
				[TGAlertSheet showMessage:title title:@"Bank Card" inView:weakSelf.view];
				return;
			}
			[TGAlertSheet showChoices:titles
								title:title
							  message:@"The provider's own page."
					   destructiveIndex:-1
							   inView:weakSelf.view
							 onChoice:^(NSInteger index){
				NSString *url = actions[(NSUInteger)index][@"url"];
				if ([url isKindOfClass:NSString.class] && url.length)
					[weakSelf openURL:url];
			}];
		}];
	}];
}

- (void)addOfferFlow {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Add an Offer"
					message:@"The channel direct-messages chat id."
				placeholder:@"-100..."
					 text:nil action:@"Next" inView:self.view
				 onSubmit:^(NSString *chat){
		int64_t chatId = chat.longLongValue;
		[TGAlertSheet showInput:@"Add an Offer"
						message:@"The suggested post's message id."
					placeholder:@"123"
						 text:nil action:@"Next" inView:weakSelf.view
					 onSubmit:^(NSString *message){
			int64_t messageId = message.longLongValue;
			[TGAlertSheet showInput:@"Add an Offer"
							message:@"The price in Telegram Stars."
						placeholder:@"100"
							 text:nil action:@"Send" inView:weakSelf.view
						 onSubmit:^(NSString *stars){
				[[TGClient shared] addOfferToMessage:messageId
											  inChat:chatId
										   starCount:stars.longLongValue
											sendDate:0
										  completion:^(NSDictionary *sent,
													   NSString *error){
					if (error){
						[TGAlertSheet showMessage:error
											title:@"Add an Offer"
										   inView:weakSelf.view];
						return;
					}
					NSString *body = sent[@"id"]
							? [NSString stringWithFormat:@"Offer sent. Message id %@.",
									sent[@"id"]]
							: @"Telegram accepted the offer.";
					[TGAlertSheet showMessage:body
										title:@"Add an Offer"
									   inView:weakSelf.view];
				}];
			}];
		}];
	}];
}

- (void)validateOrderFlow {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Validate an Order"
					message:@"The invoice name the order is checked against."
				placeholder:@"invoice-name"
					 text:nil action:@"Next" inView:self.view
				 onSubmit:^(NSString *invoice){
		NSMutableDictionary *values = [NSMutableDictionary dictionary];
		values[@"invoice"] = invoice;
		[TGAlertSheet showChoices:@[@"Check Only", @"Check and Save"]
							title:@"Validate an Order"
						  message:@"Saving keeps the fields for the invoice's next "
								  @"checkout."
				 destructiveIndex:-1
						   inView:weakSelf.view
						 onChoice:^(NSInteger index){
			BOOL save = index == 1;
			NSArray *keys = @[@"name", @"phone_number", @"email_address",
							  @"street_line1", @"city", @"postal_code",
							  @"country_code"];
			NSArray *prompts = @[@"Full name", @"Phone number", @"Email",
								 @"Street address", @"City", @"Postal code",
								 @"Country code"];
			[weakSelf askOrderFieldAtIndex:0 keys:keys prompts:prompts
									values:values allowSave:save];
		}];
	}];
}

/// The order form is seven fields and no more: state and the second street
/// line are the two an invoice rarely asks for, and orderInfo sends them as
/// empty strings rather than leaving a required key out.
- (void)askOrderFieldAtIndex:(NSUInteger)index
						keys:(NSArray *)keys
					 prompts:(NSArray *)prompts
					  values:(NSMutableDictionary *)values
				   allowSave:(BOOL)allowSave {
	if (index >= keys.count){
		[self runOrderValidation:values allowSave:allowSave];
		return;
	}
	__weak typeof(self) weakSelf = self;
	NSString *key = keys[index];
	[TGAlertSheet showInput:@"Validate an Order"
					message:(index == 0
							? @"Fill what the invoice asks for; the rest is sent empty."
							: nil)
				placeholder:prompts[index]
					 text:nil
				   action:(index + 1 == keys.count ? @"Validate" : @"Next")
				   inView:self.view
				 onSubmit:^(NSString *text){
		values[key] = text;
		[weakSelf askOrderFieldAtIndex:index + 1 keys:keys prompts:prompts
								values:values allowSave:allowSave];
	}];
}

- (void)runOrderValidation:(NSMutableDictionary *)values allowSave:(BOOL)allowSave {
	NSString *invoice = values[@"invoice"];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] validateOrderInfoForInvoice:invoice order:values
										 allowSave:allowSave
										completion:^(NSDictionary *validated,
													 NSString *error){
		if (error){
			[TGAlertSheet showMessage:error title:@"Validate an Order"
							   inView:weakSelf.view];
			return;
		}
		NSMutableArray *lines = [NSMutableArray array];
		NSString *orderId = validated[@"order_info_id"];
		if ([orderId isKindOfClass:NSString.class] && orderId.length)
			[lines addObject:[NSString stringWithFormat:@"Order info id: %@", orderId]];
		NSArray *options = [validated[@"shipping_options"] isKindOfClass:NSArray.class]
				? validated[@"shipping_options"] : @[];
		if (options.count){
			[lines addObject:@"Shipping options:"];
			for (NSDictionary *option in options){
				NSMutableArray *prices = [NSMutableArray array];
				NSArray *parts = [option[@"price_parts"] isKindOfClass:NSArray.class]
						? option[@"price_parts"] : @[];
				for (NSDictionary *part in parts){
					NSString *label = part[@"label"];
					NSNumber *amount = part[@"amount"];
					if ([label isKindOfClass:NSString.class] && label.length)
						[prices addObject:[NSString stringWithFormat:@"%@ %@",
								label, amount ?: @0]];
				}
				[lines addObject:[NSString stringWithFormat:@"· %@%@",
						option[@"title"] ?: @"Option",
						prices.count ? [NSString stringWithFormat:@" - %@",
								[prices componentsJoinedByString:@", "]] : @""]];
			}
		} else {
			[lines addObject:@"Telegram accepted the order and offered no "
							  @"shipping options."];
		}
		[TGAlertSheet showMessage:([lines componentsJoinedByString:@"\n"])
							title:@"Validate an Order"
						   inView:weakSelf.view];
	}];
}

/// Record that a diagnostic went for this call, so the row says so on the
/// next open. The default is the only place it belongs: TDLib keeps no flag
/// for "this user already sent the log".
- (void)noteCallDiagnostic:(NSString *)kind forCall:(NSDictionary *)call {
	NSString *key = [NSString stringWithFormat:@"%lld:%lld",
			(long long)[call[@"chatId"] longLongValue],
			(long long)[call[@"messageId"] longLongValue]];
	if ([key isEqualToString:@"0:0"])
		return;
	if (!self.callDiagnostics)
		self.callDiagnostics = [NSMutableDictionary dictionary];
	NSMutableArray *kinds = [self.callDiagnostics[key] mutableCopy]
			?: [NSMutableArray array];
	if (![kinds containsObject:kind])
		[kinds addObject:kind];
	self.callDiagnostics[key] = kinds;
	[NSUserDefaults.standardUserDefaults setObject:self.callDiagnostics
											forKey:@"TGCallDiagnosticsSent"];
	[self rebuild];
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
			// The component gallery is a development surface, not a setting.
			// It sat in Appearance next to the theme picker, where a user had
			// no reason to open it.
			TGTapRow(@"UI Component Gallery", @"Every control and state", ^{
				TGGalleryViewController *gallery = [[TGGalleryViewController alloc] init];
				gallery.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:gallery animated:YES];
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

		// The calls the old tier list called "never" but a user account can
		// still send. Each screen names its request and shows Telegram's
		// answer; the ones that stay impossible are documented in
		// docs/feature_backlog.md.
		TGSection(@"Tier 3 Audit",
				  @"Surfaces for the calls a user account really can make: "
				  @"advertisements, TDLib's environment, owned bots and the "
				  @"read-only Premium and gift records.", @[
			TGTapRow(@"Sponsored Messages", @"Channel, search and video ads", ^{
				TGSponsoredMessagesViewController *ads =
						[[TGSponsoredMessagesViewController alloc] init];
				ads.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:ads animated:YES];
			}),
			TGTapRow(@"TDLib Environment", @"JSON, log, weather and time zones", ^{
				TGEnvironmentViewController *environment =
						[[TGEnvironmentViewController alloc] init];
				environment.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:environment animated:YES];
			}),
			TGTapRow(@"Bot Console", @"Bots this account owns and its inline bots", ^{
				TGBotConsoleViewController *bots = [[TGBotConsoleViewController alloc] init];
				bots.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:bots animated:YES];
			}),
			TGTapRow(@"TDLib Test Harness", @"The twelve td_api test calls", ^{
				TGTestHarnessViewController *harness =
						[[TGTestHarnessViewController alloc] init];
				harness.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:harness animated:YES];
			}),
			TGTapRow(@"Affiliate Programs", @"Catalogue, connections and channel links", ^{
				TGAffiliateProgramsViewController *affiliate =
						[[TGAffiliateProgramsViewController alloc] init];
				affiliate.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:affiliate animated:YES];
			}),
			TGTapRow(@"Premium, Stars and Gifts", @"Read-only", ^{
				TGStarsGiftsViewController *stars = [[TGStarsGiftsViewController alloc] init];
				stars.hidesBottomBarWhenPushed = YES;
				[weakSelf.navigationController pushViewController:stars animated:YES];
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

		// The calls TDLib reserves for bot accounts. A user account still
		// sends them; the server's refusal is the honest answer, and the row
		// exists so the request and its result have a real surface.
		TGSection(@"Bot Tools",
				  @"Requests a bot account owns. A user account will usually get "
				  @"Telegram's refusal back, shown as the answer.", @[
			TGTapRow(@"Prepared Keyboard Button", nil, ^{
				[TGAlertSheet showInput:@"Prepared Keyboard Button"
								message:@"Bot user id" placeholder:@"123"
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *bot){
					int64_t botId = bot.longLongValue;
					[TGAlertSheet showInput:@"Prepared Keyboard Button"
									message:@"Prepared button id"
								placeholder:@"prepared"
									 text:nil action:@"Fetch" inView:weakSelf.view
							   onSubmit:^(NSString *prepared){
						[[TGClient shared] preparedKeyboardButtonFromBot:botId
													   preparedButtonId:prepared
															completion:^(NSDictionary *button,
																		 NSString *error){
							if (!button){
								[TGAlertSheet showMessage:(error ?: @"Telegram has no such button.")
													title:@"Prepared Keyboard Button"
												   inView:weakSelf.view];
								return;
							}
							NSString *body = [NSString stringWithFormat:
									@"Text: %@\nType: %@\nStyle: %@\nIcon: %@",
									button[@"text"] ?: @"",
									button[@"type"] ?: @"",
									button[@"style"] ?: @"",
									button[@"customEmojiId"] ?: @0];
							[TGAlertSheet showMessage:body
												title:@"Prepared Keyboard Button"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Save Prepared Keyboard Button", nil, ^{
				[TGAlertSheet showInput:@"Save Prepared Keyboard Button"
								message:@"User id the button is prepared for"
							placeholder:@"123"
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *user){
					int64_t userId = user.longLongValue;
					[TGAlertSheet showInput:@"Save Prepared Keyboard Button"
									message:@"Button text"
								placeholder:@"Send me the file"
									 text:nil action:@"Save" inView:weakSelf.view
							   onSubmit:^(NSString *text){
						[[TGClient shared] savePreparedKeyboardButtonText:text
																  forUser:userId
															   completion:^(NSString *preparedId,
																			NSString *error){
							if (!preparedId.length){
								[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
													title:@"Save Prepared Keyboard Button"
												   inView:weakSelf.view];
								return;
							}
							[TGAlertSheet showChoices:@[@"Fetch It Back"]
												title:@"Prepared Button Saved"
											  message:[NSString stringWithFormat:
													  @"Prepared id: %@", preparedId]
									   destructiveIndex:-1
											   inView:weakSelf.view
											 onChoice:^(NSInteger index){
								[[TGClient shared] preparedKeyboardButtonFromBot:userId
															   preparedButtonId:preparedId
																		completion:^(NSDictionary *button,
																					 NSString *fetchError){
									if (!button){
										[TGAlertSheet showMessage:(fetchError
												?: @"Telegram did not return it.")
															title:@"Prepared Keyboard Button"
														   inView:weakSelf.view];
										return;
									}
									[TGAlertSheet showMessage:[NSString stringWithFormat:
											@"Text: %@\nType: %@",
											button[@"text"] ?: @"",
											button[@"type"] ?: @""]
														title:@"Prepared Keyboard Button"
													   inView:weakSelf.view];
								}];
							}];
						}];
					}];
				}];
			}),
			TGTapRow(@"Callback Query Message", nil, ^{
				[TGAlertSheet showInput:@"Callback Query Message"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Callback Query Message"
									message:@"Message id" placeholder:@"123"
										 text:nil action:@"Next" inView:weakSelf.view
								   onSubmit:^(NSString *message){
						int64_t messageId = [message longLongValue];
						[TGAlertSheet showInput:@"Callback Query Message"
										message:@"Callback query id"
									placeholder:@"0"
										 text:nil action:@"Fetch"
									   inView:weakSelf.view
								   onSubmit:^(NSString *query){
							[[TGClient shared] callbackQueryMessage:messageId
															 inChat:chatId
													callbackQueryId:[query longLongValue]
														 completion:^(NSDictionary *found){
								[TGAlertSheet showMessage:(found[@"text"] ?: @"Telegram refused or has no such callback.")
													title:@"Callback Query Message"
												   inView:weakSelf.view];
							}];
						}];
					}];
				}];
			}),
			TGTapRow(@"Personal Chat History", nil, ^{
				[TGAlertSheet showInput:@"Personal Chat History"
								message:@"User id" placeholder:@"123"
									 text:nil action:@"Fetch" inView:weakSelf.view
							   onSubmit:^(NSString *user){
					[[TGClient shared] personalChatHistoryForUser:[user longLongValue]
														   limit:20
													  completion:^(NSArray *messages){
						NSMutableString *body = [NSMutableString string];
						for (NSDictionary *message in messages)
							[body appendFormat:@"%@\n",
									message[@"text"] ?: @"(no text)"];
						if (!body.length)
							body = [@"Telegram refused or the chat is empty."
									mutableCopy];
						[TGAlertSheet showMessage:body
											title:@"Personal Chat History"
										   inView:weakSelf.view];
					}];
				}];
			}),
			TGTapRow(@"Set Reactions", nil, ^{
				[TGAlertSheet showInput:@"Set Reactions"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Set Reactions"
									message:@"Message id" placeholder:@"123"
										 text:nil action:@"Next" inView:weakSelf.view
								   onSubmit:^(NSString *message){
						int64_t messageId = [message longLongValue];
						[TGAlertSheet showInput:@"Set Reactions"
										message:@"Emoji (empty clears)"
									placeholder:@"👍"
										 text:nil action:@"Set"
									   inView:weakSelf.view
								   onSubmit:^(NSString *emoji){
							[[TGClient shared] setReactions:(emoji.length ? @[emoji] : @[])
												  onMessage:messageId
													 inChat:chatId
												 completion:^(BOOL ok){
								[TGAlertSheet showMessage:(ok ? @"Reactions set."
															: @"Telegram refused that.")
													title:@"Set Reactions"
												   inView:weakSelf.view];
							}];
						}];
					}];
				}];
			}),
			TGTapRow(@"Send Text Draft", nil, ^{
				[TGAlertSheet showInput:@"Send Text Draft"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Send Text Draft"
									message:@"Draft text" placeholder:@"Thinking..."
										 text:nil action:@"Send" inView:weakSelf.view
								   onSubmit:^(NSString *text){
						int64_t draftId = (int64_t)([[NSDate date]
								timeIntervalSince1970] * 1000);
						[[TGClient shared] sendTextDraft:text
												 toChat:chatId
												  topic:0
												draftId:draftId
												 canStop:YES
													keep:NO
											 completion:^(BOOL ok){
							NSString *body = ok
									? [NSString stringWithFormat:
											@"Draft sent. Its id is %lld.",
											(long long)draftId]
									: @"Telegram refused that.";
							[TGAlertSheet showMessage:body
												title:@"Send Text Draft"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Stop Text Draft", nil, ^{
				[TGAlertSheet showInput:@"Stop Text Draft"
								message:@"Chat id" placeholder:@"-100..."
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *chat){
					int64_t chatId = [chat longLongValue];
					[TGAlertSheet showInput:@"Stop Text Draft"
									message:@"Draft id" placeholder:@"0"
										 text:nil action:@"Stop" inView:weakSelf.view
								   onSubmit:^(NSString *draft){
						[[TGClient shared] stopTextDraft:[draft longLongValue]
												  inChat:chatId
												   topic:0
											  completion:^(BOOL ok){
							[TGAlertSheet showMessage:(ok ? @"Draft stopped."
														: @"Telegram refused that.")
												title:@"Stop Text Draft"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Prepared Inline Message", nil, ^{
				[TGAlertSheet showInput:@"Prepared Inline Message"
								message:@"Bot user id" placeholder:@"123"
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *bot){
					int64_t botId = [bot longLongValue];
					[TGAlertSheet showInput:@"Prepared Inline Message"
									message:@"Prepared message id"
								placeholder:@"prepared"
									 text:nil action:@"Fetch"
								   inView:weakSelf.view
							   onSubmit:^(NSString *prepared){
						[[TGClient shared] preparedInlineMessageFromBot:botId
													  preparedMessageId:prepared
														   completion:^(NSDictionary *found){
							NSString *body = found
									? [NSString stringWithFormat:@"Id: %@\nResult: %@",
											found[@"id"] ?: @"",
											found[@"result"] ?: @{}]
									: @"Telegram refused or has no such message.";
							[TGAlertSheet showMessage:body
												title:@"Prepared Inline Message"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Save Inline Message", nil, ^{
				[TGAlertSheet showInput:@"Save Inline Message"
								message:@"User id to prepare it for" placeholder:@"123"
									 text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *user){
					int64_t userId = [user longLongValue];
					[TGAlertSheet showInput:@"Save Inline Message"
									message:@"Message text"
								placeholder:@"Hello"
									 text:nil action:@"Save"
								   inView:weakSelf.view
							   onSubmit:^(NSString *text){
						[[TGClient shared] savePreparedInlineMessageForUser:userId
																	 text:text
																	title:text
															   completion:^(NSString *preparedId){
							[TGAlertSheet showMessage:(preparedId.length
									? [NSString stringWithFormat:@"Saved as %@", preparedId]
									: @"Telegram refused that.")
												title:@"Save Inline Message"
											   inView:weakSelf.view];
						}];
					}];
				}];
			}),
			TGTapRow(@"Edit Inline Message", nil, ^{
				[TGAlertSheet showInput:@"Edit Inline Message"
								message:@"Inline message id"
							placeholder:@"AAH..."
									 text:nil action:@"Next"
								   inView:weakSelf.view
							   onSubmit:^(NSString *inlineId){
					[TGAlertSheet showChoices:@[@"Text", @"Caption",
												@"Remove Buttons", @"Photo",
												@"Live Location"]
										title:@"Edit Inline Message"
							  destructiveIndex:-1
									   inView:weakSelf.view
									 onChoice:^(NSInteger index){
						if (index == 0){
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"New text" placeholder:@"Hello"
												 text:nil action:@"Save"
											   inView:weakSelf.view
										   onSubmit:^(NSString *text){
								[[TGClient shared] editInlineMessageText:inlineId
																	text:text
															  completion:^(BOOL ok){
									[TGAlertSheet showMessage:(ok ? @"Edited."
																: @"Telegram refused that.")
														title:@"Edit Inline Message"
													   inView:weakSelf.view];
								}];
							}];
						} else if (index == 1){
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"New caption" placeholder:@"Caption"
												 text:nil action:@"Save"
											   inView:weakSelf.view
										   onSubmit:^(NSString *caption){
								[[TGClient shared] editInlineMessageCaption:inlineId
																   caption:caption
																completion:^(BOOL ok){
									[TGAlertSheet showMessage:(ok ? @"Caption saved."
																: @"Telegram refused that.")
														title:@"Edit Inline Message"
													   inView:weakSelf.view];
								}];
							}];
						} else if (index == 2){
							[[TGClient shared] clearInlineMessageReplyMarkup:inlineId
																 completion:^(BOOL ok){
								[TGAlertSheet showMessage:(ok ? @"Buttons removed."
															: @"Telegram refused that.")
													title:@"Edit Inline Message"
												   inView:weakSelf.view];
							}];
						} else if (index == 3){
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"Photo id" placeholder:@"123"
												 text:nil action:@"Next"
											   inView:weakSelf.view
										   onSubmit:^(NSString *photo){
								int64_t photoId = [photo longLongValue];
								[TGAlertSheet showInput:@"Edit Inline Message"
												message:@"Caption" placeholder:@"Photo"
													 text:nil action:@"Save"
												   inView:weakSelf.view
											   onSubmit:^(NSString *caption){
									[[TGClient shared] editInlineMessagePhoto:inlineId
																	photoId:photoId
																	caption:caption
																 completion:^(BOOL ok){
										[TGAlertSheet showMessage:(ok ? @"Photo saved."
																	: @"Telegram refused that.")
															title:@"Edit Inline Message"
														   inView:weakSelf.view];
									}];
								}];
							}];
						} else {
							[TGAlertSheet showInput:@"Edit Inline Message"
											message:@"Latitude" placeholder:@"0.0"
												 text:nil action:@"Next"
											   inView:weakSelf.view
										   onSubmit:^(NSString *lat){
								double latitude = [lat doubleValue];
								[TGAlertSheet showInput:@"Edit Inline Message"
												message:@"Longitude" placeholder:@"0.0"
													 text:nil action:@"Save"
												   inView:weakSelf.view
											   onSubmit:^(NSString *lon){
									[[TGClient shared] editInlineMessageLiveLocation:inlineId
																			latitude:latitude
																		   longitude:[lon doubleValue]
																		  completion:^(BOOL ok){
										[TGAlertSheet showMessage:(ok ? @"Location moved."
																	: @"Telegram refused that.")
															title:@"Edit Inline Message"
														   inView:weakSelf.view];
									}];
								}];
							}];
						}
					}];
				}];
			}),
		]),

		TGSection(@"Chat Resolvers",
				  @"A chat id is what every screen carries. These turn the "
				  @"internal basic-group, supergroup or secret-chat id back "
				  @"into one, which is the compatibility path TDLib keeps for "
				  @"an account that only ever saw the inner id.", @[
			TGTapRow(@"Open Basic Group by ID", nil, ^{
				[TGAlertSheet showInput:@"Basic Group ID" message:nil
							placeholder:@"Group id" text:nil action:@"Read"
								 inView:weakSelf.view onSubmit:^(NSString *text){
					int64_t basicGroupId = text.longLongValue;
					// The record first, so the resolver shows what Telegram
					// holds for the id - name, members and status - not only
					// an attempt to open a chat from it.
					[[TGClient shared] basicGroupInfo:basicGroupId
							completion:^(NSDictionary *info){
						if (!info){
							[TGAlertSheet showMessage:@"TDLib has no basic group "
													  @"with that id."
												title:@"Basic Group"
											   inView:weakSelf.view];
							return;
						}
						NSString *status = [info[@"status"] capitalizedString];
						NSString *upgraded = [info[@"upgradedTo"] longLongValue]
								? @"\nIt has been upgraded to a supergroup."
								: @"";
						NSString *message = [NSString stringWithFormat:
								@"%@\n%ld members · %@%@%@",
								info[@"title"],
								(long)[info[@"members"] integerValue],
								status,
								[info[@"active"] boolValue] ? @"" : @" · inactive",
								upgraded];
						[TGAlertSheet showChoices:@[@"Open Chat"]
											title:@"Basic Group"
										  message:message
								 destructiveIndex:-1
										   inView:weakSelf.view
										 onChoice:^(NSInteger index){
							[[TGClient shared] chatForBasicGroup:basicGroupId
													completion:^(int64_t chatId){
								[weakSelf openResolvedChat:chatId
													 title:info[@"title"]];
							}];
						}];
					}];
				}];
			}),
			TGTapRow(@"Open Supergroup by ID", nil, ^{
				[TGAlertSheet showInput:@"Supergroup ID" message:nil
							placeholder:@"Supergroup id" text:nil action:@"Open"
								 inView:weakSelf.view onSubmit:^(NSString *text){
					[[TGClient shared] chatForSupergroup:text.longLongValue
											completion:^(int64_t chatId){
						[weakSelf openResolvedChat:chatId title:@"Supergroup"];
					}];
				}];
			}),
			TGTapRow(@"Open Secret Chat by ID", nil, ^{
				[TGAlertSheet showInput:@"Secret Chat ID" message:nil
							placeholder:@"Secret chat id" text:nil action:@"Open"
								 inView:weakSelf.view onSubmit:^(NSString *text){
					[[TGClient shared] chatForSecretChat:(int32_t)text.intValue
											completion:^(int64_t chatId){
						[weakSelf openResolvedChat:chatId title:@"Secret Chat"];
					}];
				}];
			}),
		]),

		TGSection(@"Diagnostics",
				  @"Raw access to TDLib for a support session. A custom method "
				  @"answers with its own result string; the database key is the "
				  @"one setting that can make this device's chats unreadable.",
				  @[
			TGTapRow(@"Send Custom Request", @"Method and JSON parameters", ^{
				[TGAlertSheet showInput:@"Send Custom Request"
								message:@"TDLib method"
							placeholder:@"getOption"
								   text:nil action:@"Next" inView:weakSelf.view
							   onSubmit:^(NSString *method){
					[TGAlertSheet showInput:@"Send Custom Request"
									message:@"Parameters as JSON"
								placeholder:@"{}"
									   text:@"{}" action:@"Send"
								   inView:weakSelf.view
								   onSubmit:^(NSString *parameters){
						[[TGClient shared] sendCustomRequestMethod:method
													   parameters:parameters
													   completion:^(NSString *result,
																	NSString *error){
							if (error){
								[TGAlertSheet showMessage:error
													title:@"Custom Request"
												   inView:weakSelf.view];
								return;
							}
							TGListViewController *viewer = [[TGListViewController alloc] init];
							viewer.listTitle = method;
							viewer.rows = TGCustomResultRows(result);
							viewer.listFooter = @"sendCustomRequest result";
							viewer.offersCopy = YES;
							viewer.hidesBottomBarWhenPushed = YES;
							[weakSelf.navigationController pushViewController:viewer
																 animated:YES];
						}];
					}];
				}];
			}),
			TGTapRow(@"Database Encryption Key",
					[[TGClient shared] databaseEncryptionKeyIsKnown]
							? ([[TGClient shared] databaseEncryptionKeyIsSet]
								? @"Set" : @"Not set")
							: @"Unknown",
					^{
				if (![[TGClient shared] databaseEncryptionKeyIsKnown]){
					[TGAlertSheet showMessage:@"The current database key could not "
											  @"be read from the keychain. Changing "
											  @"it now could lock the database."
										title:@"Database Encryption Key"
									   inView:weakSelf.view];
					return;
				}
				[TGAlertSheet showConfirm:@"Changing the key re-encrypts the local "
										  @"database. If the new key is lost, the "
										  @"chats cached on this device cannot be "
										  @"opened again. The key is saved in the "
										  @"keychain and used on the next launch. "
										  @"Continue?"
									title:@"Database Encryption Key"
								   action:@"Continue"
							  destructive:YES
								   inView:weakSelf.view
								onConfirm:^{
					[TGAlertSheet showSecureInput:@"Database Encryption Key"
										  message:@"New key"
									  placeholder:@"at least 8 characters"
										   action:@"Set"
										   inView:weakSelf.view
									   onSubmit:^(NSString *key){
						NSData *bytes = [key dataUsingEncoding:NSUTF8StringEncoding];
						[[TGClient shared] setDatabaseEncryptionKey:bytes
								completion:^(BOOL ok, NSString *error){
							if (!ok){
								[TGAlertSheet showMessage:(error ?: @"Telegram refused that key.")
													title:@"Database Encryption Key"
												   inView:weakSelf.view];
								return;
							}
							[TGAlertSheet showMessage:@"The key is set and saved. "
													  @"TDLib will open the database "
													  @"with it from the next launch."
												title:@"Database Encryption Key"
											   inView:weakSelf.view];
							[weakSelf rebuild];
						}];
					}];
				}];
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

- (void)openResolvedChat:(int64_t)chatId title:(NSString *)title {
	if (!chatId){
		[TGAlertSheet showMessage:@"TDLib did not resolve that id to a chat."
							title:title inView:self.view];
		return;
	}
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = title;
	chat.isGroup = YES;
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

- (void)toast:(NSString *)text {
	[TGAlertSheet showMessage:text title:nil inView:self.view];
}

@end
