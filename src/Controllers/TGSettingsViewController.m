#import "TGSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGStorageViewController.h"
#import "TGSessionsViewController.h"
#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGCapabilities.h"
#import "TGEditProfileViewController.h"
#import "TGProfileViewController.h"
#import "TGQRViewController.h"
#import "TGPlaceholderViewController.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

#import "TGSettingsViewControllerInternal.h"
#import "TGStyle.h"

/// A settings row whose icon keeps off the card's edge. iOS 7 insets a
/// cell's image by itself; iOS 6 puts it hard against the rounded border, so
/// on the iPod the tiles touched the edge while the 4S showed a margin.
@interface TGSettingsCell : UITableViewCell
@end

@implementation TGSettingsCell
- (void)layoutSubviews {
	[super layoutSubviews];
	if (!self.imageView.image || NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_6_1)
		return;
	CGRect icon = self.imageView.frame;
	// iOS 7's own inset, so the two systems agree.
	CGFloat shift = TGMetricGutter - icon.origin.x;
	if (shift <= 0)
		return;
	CGFloat iconRight = CGRectGetMaxX(icon);
	icon.origin.x += shift;
	self.imageView.frame = icon;
	CGFloat edge = self.contentView.bounds.size.width - TGMetricPadMedium;
	for (UILabel *label in @[self.textLabel, self.detailTextLabel]) {
		CGRect f = label.frame;
		// Only labels beside the icon move; a value at the right stays put.
		if (f.origin.x > iconRight + TGMetricGutter)
			continue;
		f.origin.x += shift;
		// Value1 sizes the title to its text, so it is moved, not narrowed -
		// narrowing cut "Edit Profile" to "Edit Pro...". Only the cell's
		// edge limits it.
		f.size.width = MIN(f.size.width, MAX(0, edge - f.origin.x));
		label.frame = f;
	}
}
@end

@implementation TGSettingsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.contentInset = UIEdgeInsetsMake(0, 0, TGMetricTabBarH, 0);
	self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
	[self applyTheme];

	self.privacy  = [NSMutableDictionary dictionary];
	self.muted    = [NSMutableDictionary dictionary];
	self.previews = [NSMutableDictionary dictionary];
	self.suggestFrequent = YES;
	NSDictionary *savedDiagnostics = [NSUserDefaults.standardUserDefaults
			objectForKey:@"TGCallDiagnosticsSent"];
	self.callDiagnostics = savedDiagnostics
			? [savedDiagnostics mutableCopy] : [NSMutableDictionary dictionary];

	self.title = [self pageTitle];

	if (self.page == TGSettingsPageRecentCalls) {
		UISegmentedControl *filter = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Missed"]];
		filter.selectedSegmentIndex = self.recentCallsFilter;
		[filter addTarget:self action:@selector(recentCallsFilterChanged:) forControlEvents:UIControlEventValueChanged];
		self.navigationItem.titleView = filter;
	} else if (self.page == TGSettingsPageRoot) {
		self.navigationItem.rightBarButtonItem = nil;
	}

	[self rebuild];
	[self loadForPage];

	// Repaint on theme change notification.
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf repaint];
	}];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGPrivacyRulesChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf privacyRulesChanged];
	}];
	// The verification row has nothing to show until Telegram asks; when it
	// does, the row fills in without the page being reopened.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGApplicationVerificationRequiredNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf rebuild];
	}];
	// The privacy page's birthday row is fed by an update, and the Appearance
	// page's colour lists arrive the same way. Neither page waits for a
	// reopen when Telegram answers after it is already on screen.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGContactCloseBirthdaysChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		weakSelf.closeBirthdayRows = [[TGClient shared] contactCloseBirthdayUsers];
		if (weakSelf.page == TGSettingsPagePrivacy)
			[weakSelf rebuild];
	}];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGAccentColorsChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		if (weakSelf.page == TGSettingsPageAppearance)
			[weakSelf rebuild];
	}];
	// Account status and Telegram's appearance defaults are pushed, so the
	// page that draws them re-reads while it is open - a freeze that starts
	// during a session should not need Settings closed and reopened.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGAccountStatusChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		if (weakSelf.page == TGSettingsPagePrivacy)
			[weakSelf rebuild];
	}];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGAppearanceDefaultsChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		if (weakSelf.page == TGSettingsPageAppearance)
			[weakSelf rebuild];
	}];
	// The Active Notifications page is a view of the client's local list:
	// removing one row, or TDLib replacing the list, must reach it without a
	// reopen. The summary row on the page above reads the same count.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGActiveNotificationsChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		if (weakSelf.page == TGSettingsPageActiveNotifications ||
			weakSelf.page == TGSettingsPageNotifications)
			[weakSelf rebuild];
	}];
	// Autosave and language state can change on another client while these
	// pages are open. Both re-read their whole record rather than patching
	// one row from an update that carries only one scope or one string.
	[[NSNotificationCenter defaultCenter] addObserverForName:TGAutosaveSettingsChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf autosaveSettingsChanged];
	}];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGLanguagePackStringsChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf languagePackStringsChanged:note.userInfo[@"packId"]];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

/// Restyle everything this screen owns and redraw it. The profile cell is held
/// across reloads, so it has to be dropped or it keeps the old theme's colours.
- (void)repaint {
	[TGIcons flush];
	self.profileCell = nil;
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[[TGTheme shared] styleTabBar:self.tabBarController.tabBar];
	[self applyTheme];
	[self rebuild];
}

- (NSString *)pageTitle {
	switch (self.page){
		case TGSettingsPageAppearance:    return @"Appearance";
		case TGSettingsPageData:          return @"Data and Storage";
		case TGSettingsPageFolders:       return @"Chat Folders";
		case TGSettingsPageProxy:         return @"Proxy";
		case TGSettingsPageDownloads:     return @"Downloads";
		case TGSettingsPageAutosave:      return @"Autosave";
		case TGSettingsPageNotifications: return @"Notifications and Sounds";
		case TGSettingsPageNotificationSounds: return @"Custom Sounds";
		case TGSettingsPageActiveNotifications: return @"Active Notifications";
		case TGSettingsPagePrivacy:       return @"Privacy and Security";
		case TGSettingsPagePasscode:      return @"Passcode Lock";
		case TGSettingsPageLanguage:      return @"Language";
		case TGSettingsPageBlocked:       return @"Blocked Users";
		case TGSettingsPagePowerSaving:   return @"Power Saving";
		case TGSettingsPageRecentCalls:   return @"Recent Calls";
		case TGSettingsPageWallpaper:     return @"Chat Wallpaper";
		case TGSettingsPagePaymentData:   return @"Orders and Payment Data";
#if TG_DEV
		case TGSettingsPageDebug:         return @"Dev Settings";
		case TGSettingsPageLanguageDev:   return @"Language Packs";
		case TGSettingsPagePaymentDev:    return @"Invoice Tools";
#endif
		default:                          return @"Settings";
	}
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
}



- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	// The header is held across reloads. An edit changes the name and picture,
	// so returning to Settings must build it again rather than show the old one.
	if (self.page == TGSettingsPageRoot)
		self.profileCell = nil;
	[self rebuild];
	// The Archive switches are the one page that reads copy TDLib holds:
	// the cached copy answers the first draw, the network refresh redraws.
	if (self.page == TGSettingsPageData)
		[[TGClient shared] refreshArchiveChatListSettings:^{ [self rebuild]; }];
}

#pragma mark - reordering, where a page has an order

/// Only the folders page has one, and the order belongs to the pill strip
/// above the chat list. A table already knows how to drag rows, so this is
/// the Edit button and the two delegate methods rather than a gesture.
- (BOOL)tableView:(UITableView *)tableView
		canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return self.page == TGSettingsPageFolders &&
		   indexPath.section == 0 &&
		   indexPath.row < (NSInteger)[TGClient shared].folders.count;
}

- (void)tableView:(UITableView *)tableView
		moveRowAtIndexPath:(NSIndexPath *)from
			   toIndexPath:(NSIndexPath *)to {
	NSMutableArray *order = [NSMutableArray array];
	for (NSDictionary *folder in [TGClient shared].folders)
		if ([folder[@"id"] integerValue])
			[order addObject:folder[@"id"]];
	if (from.row >= (NSInteger)order.count || to.row >= (NSInteger)order.count)
		return;

	NSNumber *moved = order[(NSUInteger)from.row];
	[order removeObjectAtIndex:(NSUInteger)from.row];
	[order insertObject:moved atIndex:(NSUInteger)to.row];

	// All Chats stays first: this app's strip draws it as the leading pill and
	// has nowhere to put it in the middle.
	[[TGClient shared] reorderFolderIds:order mainListAt:0];
}

/// Dragging needs no delete control beside it; the folder's own sheet deletes.
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
		   editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewCellEditingStyleNone;
}

- (void)openPage:(TGSettingsPage)page {
	TGSettingsViewController *next = [[TGSettingsViewController alloc] init];
	next.page = page;
	next.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:next animated:YES];
}

/// Rebuild the rows from whatever the client has answered so far, and redraw.
/// Everything that arrives asynchronously calls this rather than reaching into
/// a cell by index.
- (void)rebuild {
	self.sections = [self buildSections];
	[self.tableView reloadData];
}

/// The version, the way their page ends with one.
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	// Every other footer is the system's (titleForFooterInSection:).
	if (self.page != TGSettingsPageRoot || section != (NSInteger)self.sections.count - 1)
		return nil;
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, kVersionRow)];
	label.text = [NSString stringWithFormat:@"LegacyTG %@ (%@) armv7",
			info[@"CFBundleShortVersionString"] ?: @"", info[@"CFBundleVersion"] ?: @""];
	label.font = TGFontMeta();
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	return label;
}

#pragma mark - loading

/// Three scopes arrive as three updates when they are reset at once.
- (void)notificationSettingsChanged {
	if (self.page != TGSettingsPageNotifications &&
		self.page != TGSettingsPageNotificationSounds)
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(loadForPage) object:nil];
	[self performSelector:@selector(loadForPage) withObject:nil afterDelay:0.3];
}

/// updateAutosaveSettings moves one scope at a time and a client change can
/// be a short run of them. The Autosave page and the Data row read the whole
/// record, so one re-read a third of a second later covers the burst.
- (void)autosaveSettingsChanged {
	if (self.page != TGSettingsPageAutosave && self.page != TGSettingsPageData)
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(loadForPage) object:nil];
	[self performSelector:@selector(loadForPage) withObject:nil afterDelay:0.3];
}

/// A privacy rule flipped here or on another client; a reset moves several
/// at once, so the re-read waits out the burst like the one above.
- (void)privacyRulesChanged {
	if (self.page != TGSettingsPagePrivacy)
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(loadForPage) object:nil];
	[self performSelector:@selector(loadForPage) withObject:nil afterDelay:0.3];
}

- (void)recentCallsFilterChanged:(UISegmentedControl *)sender {
	self.recentCallsFilter = sender.selectedSegmentIndex;
	[self rebuild];
}

/// Four updates land on this screen - added, finished, paused, removed - and
/// a sweep of the list fires one per file. One re-read a third of a second
/// later covers the burst; the list is a single request.
- (void)downloadsChanged {
	if (self.page != TGSettingsPageDownloads)
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(loadForPage) object:nil];
	[self performSelector:@selector(loadForPage) withObject:nil afterDelay:0.3];
}

- (void)loadForPage {
	__weak typeof(self) weakSelf = self;

	if (self.page == TGSettingsPageRoot){
		// The root rows name their values, as the official client's do. All
		// four answers are cached by the client or cheap to ask for; none of
		// them blocks the first draw, and a failed answer leaves the row as
		// it was rather than inventing a value.
		[[TGClient shared] storageStatsWithCompletion:^(long long bytes, NSInteger files){
			(void)files;
			weakSelf.rootCacheBytes = bytes;
			weakSelf.rootCacheLoaded = YES;
			[weakSelf rebuild];
		}];
		[[TGClient shared] sessionsWithInactiveTtlCompletion:^(NSArray *sessions,
															  NSInteger ttlDays){
			(void)ttlDays;
			NSInteger others = 0;
			NSString *device = nil;
			for (NSDictionary *session in sessions){
				if ([session[@"isCurrent"] boolValue])
					device = session[@"name"];
				else
					others++;
			}
			weakSelf.rootDeviceName = device;
			weakSelf.rootSessionCount = others;
			[weakSelf rebuild];
		}];
		[[TGClient shared] languagesWithCompletion:^(NSArray *languages,
													 NSString *current){
			NSString *name = current;
			for (NSDictionary *language in languages)
				if ([language[@"id"] isEqualToString:current ?: @""]){
					name = language[@"name"] ?: current;
					break;
				}
			weakSelf.rootLanguageName = name;
			[weakSelf rebuild];
		}];
		[[TGClient shared] proxiesWithCompletion:^(NSArray *proxies){
			NSString *detail = @"Off";
			for (NSDictionary *proxy in proxies)
				if ([proxy[@"enabled"] boolValue]){
					detail = [proxy[@"server"] length]
							? proxy[@"server"] : @"On";
					break;
				}
			weakSelf.rootProxyDetail = detail;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageAppearance){
		// The colour list comes from updateAccentColors and is cached on the
		// client; the selection is a field of the account record, so it takes
		// one getMe. A page opened before the update still draws 0-6, which
		// the schema promises are valid.
		[[TGClient shared] myAccentColorsWithCompletion:^(NSInteger accent,
														  NSInteger profile){
			weakSelf.accentColorId = accent;
			weakSelf.profileAccentColorId = profile;
			weakSelf.accentColorsLoaded = YES;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageFolders){
		// Nothing to reorder until there are two.
		if ([TGClient shared].folders.count > 1)
			self.navigationItem.rightBarButtonItem = self.editButtonItem;
		// The folders themselves arrive through updateChatFolders, which the
		// client already keeps; only the suggestions have to be asked for.
		[[TGClient shared] recommendedFoldersWithCompletion:^(NSArray *folders){
			weakSelf.recommendedFolders = folders;
			[weakSelf rebuild];
		}];
		[TGClient shared].onChatsChanged = ^{ [weakSelf rebuild]; };
		return;
	}

	if (self.page == TGSettingsPageDownloads){
		[[NSNotificationCenter defaultCenter] removeObserver:self
				name:TGDownloadsChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(downloadsChanged)
					name:TGDownloadsChangedNotification object:nil];
		[[TGClient shared] fileDownloadsMatching:nil activeOnly:NO
									  completion:^(NSArray *downloads, NSInteger active){
			weakSelf.downloads = downloads;
			weakSelf.activeDownloads = active;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageProxy){
		[[TGClient shared] proxiesWithCompletion:^(NSArray *proxies){
			weakSelf.proxies = proxies;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageNotifications){
		[[NSNotificationCenter defaultCenter] removeObserver:self
				name:TGNotificationSettingsChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(notificationSettingsChanged)
					name:TGNotificationSettingsChangedNotification object:nil];
		for (NSString *scope in @[@"private", @"groups", @"channels"]){
			[[TGClient shared] notificationsMutedForScope:scope
											   completion:^(BOOL muted){
				weakSelf.muted[scope] = @(muted);
				[weakSelf rebuild];
			}];
			[[TGClient shared] notificationPreviewForScope:scope
												completion:^(BOOL show){
				weakSelf.previews[scope] = @(show);
				[weakSelf rebuild];
			}];
		}
		return;
	}

	if (self.page == TGSettingsPageNotificationSounds){
		// A sound added or removed here, or on another client, arrives as
		// updateSavedNotificationSounds and the same settings notification.
		[[NSNotificationCenter defaultCenter] removeObserver:self
				name:TGNotificationSettingsChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
				selector:@selector(notificationSettingsChanged)
					name:TGNotificationSettingsChangedNotification object:nil];
		[[TGClient shared] savedNotificationSoundsWithCompletion:^(NSArray *sounds){
			weakSelf.savedSounds = sounds;
			weakSelf.savedSoundsLoaded = YES;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageActiveNotifications){
		// No request exists for this list: updateActiveNotifications is the
		// only copy, and it is already on the client.
		[self rebuild];
		return;
	}

	if (self.page == TGSettingsPagePrivacy){
		for (NSString *setting in [TGSettingsViewController privacySettings])
			[[TGClient shared] privacyRule:setting completion:^(NSString *value){
				weakSelf.privacy[setting] = value;
				[weakSelf rebuild];
			}];
		[[TGClient shared] accountTtlWithCompletion:^(NSInteger days){
			weakSelf.accountTtl = days;
			[weakSelf rebuild];
		}];
		[[TGClient shared] defaultMessageAutoDeleteTimeWithCompletion:^(NSInteger seconds){
			weakSelf.autoDeleteDefault = seconds;
			[weakSelf rebuild];
		}];
		[[TGClient shared] hasPasswordWithCompletion:^(BOOL has, NSString *email){
			weakSelf.hasPassword = has;
			weakSelf.passwordKnown = YES;
			[weakSelf rebuild];
		}];
		[[TGClient shared] newChatPrivacySettingsWithCompletion:^(NSDictionary *settings){
			weakSelf.newChatAllowUnknown =
					[settings[@"allow_new_chats_from_unknown_users"] boolValue];
			weakSelf.newChatPrivacyLoaded = YES;
			[weakSelf rebuild];
		}];
		NSNumber *savedPersonal =
				[NSUserDefaults.standardUserDefaults objectForKey:
						TGAccountDefaultsKey(@"TGPersonalChatId")];
		if (savedPersonal)
			weakSelf.personalChatId = savedPersonal.longLongValue;
		// TDLib stores the negative, so the row and the option are opposites.
		[[TGClient shared] optionValue:@"disable_top_chats" completion:^(id value){
			weakSelf.suggestFrequent = ![value boolValue];
			[weakSelf rebuild];
		}];
		[[TGClient shared] readDatePrivacySettingsWithCompletion:^(BOOL show){
			weakSelf.readDateLoaded = YES;
			weakSelf.showReadDate = show;
			[weakSelf rebuild];
		}];
		[[TGClient shared] closeFriendsWithCompletion:^(NSArray *ids){
			weakSelf.closeFriendsLoaded = YES;
			weakSelf.closeFriendsCount = ids.count;
			[weakSelf rebuild];
		}];
		weakSelf.closeBirthdayRows = [[TGClient shared] contactCloseBirthdayUsers];
		return;
	}

	if (self.page == TGSettingsPageData){
		[[TGClient shared] networkStatsWithCompletion:^(long long sent, long long got){
			weakSelf.networkSent = sent;
			weakSelf.networkReceived = got;
			[weakSelf rebuild];
		}];
		[[TGClient shared] autoDownloadSettingsPresetsWithCompletion:^(NSDictionary *presets){
			weakSelf.autoDownloadPresets = presets;
			[weakSelf rebuild];
		}];
		// The Autosave row's detail is the exception count; reading the
		// settings once here also satisfies TDLib's rule that set/clear work
		// only after getAutosaveSettings has answered.
		[[TGClient shared] autosaveSettingsWithCompletion:^(NSDictionary *settings){
			weakSelf.autosaveSettings = settings;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageAutosave){
		[[TGClient shared] autosaveSettingsWithCompletion:^(NSDictionary *settings){
			weakSelf.autosaveSettings = settings;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageLanguage || self.page == TGSettingsPageLanguageDev){
		[[TGClient shared] languagesWithCompletion:^(NSArray *languages,
													NSString *current){
			weakSelf.languages = languages;
			weakSelf.currentLanguage = current;
			[weakSelf rebuild];
			if (current.length)
				[[TGClient shared] languagePackInfo:current
										 completion:^(NSDictionary *info){
					weakSelf.languageInfo = info;
					[weakSelf rebuild];
				}];
		}];
		NSString *code = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode]
				?: weakSelf.countryCode ?: @"US";
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
		return;
	}

	if (self.page == TGSettingsPageBlocked){
		[[TGClient shared] blockedUsersWithCompletion:^(NSArray *users){
			weakSelf.blocked = users;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageRecentCalls){
		[[TGClient shared] recentCallsWithCompletion:^(NSArray *calls){
			weakSelf.calls = calls;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPagePaymentData){
		[[TGClient shared] savedOrderInfoWithCompletion:^(NSDictionary *order,
														  NSString *error){
			weakSelf.savedOrder = order;
			weakSelf.savedOrderError = error;
			weakSelf.savedOrderLoaded = YES;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageDebug){
		// optionValue: hands back the value itself, not the option object.
		// Subscripting it again asked an NSString for objectForKeyedSubscript:,
		// which took the app down every time this page opened.
		[[TGClient shared] optionValue:@"version" completion:^(id value){
			weakSelf.tdlibVersion = [value isKindOfClass:NSString.class]
					? value : @"unavailable";
			[weakSelf rebuild];
		}];
	}
}

/// TDLib's names without the prefix, in the order every client lists them.
+ (NSArray *)privacySettings {
	static NSArray *settings = nil;
	if (!settings)
		settings = @[@"ShowStatus", @"ShowProfilePhoto", @"ShowPhoneNumber",
					 @"AllowCalls", @"AllowChatInvites",
					 @"ShowLinkInForwardedMessages"];
	return settings;
}

+ (NSArray *)privacyTitles {
	static NSArray *titles = nil;
	if (!titles)
		titles = @[@"Last Seen", @"Profile Photo", @"Phone Number",
				   @"Calls", @"Group Invites", @"Forwarded Messages"];
	return titles;
}


#pragma mark - table

- (NSDictionary *)rowAt:(NSIndexPath *)path {
	if (path.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = self.sections[path.section][@"rows"];
	return path.row < (NSInteger)rows.count ? rows[path.row] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	NSString *text = self.sections[section][@"header"];
	return text.length ? text : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	NSString *text = self.sections[section][@"footer"];
	return text.length ? text : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self.sections[section][@"rows"] count];
}


/// The version line that ends the root page.
static const CGFloat kVersionRow   = 40.0f;
/// The theme preview: a strip of wallpaper with two bubbles on it.
static const CGFloat kPreviewInset    = TGMetricPadMedium + TGMetricPadTiny;
static const CGFloat kPreviewTop      = TGMetricPadLarge - TGMetricPadTiny;
static const CGFloat kPreviewGap      = TGMetricPad;
static const CGFloat kPreviewTextLeft = TGMetricBubblePadH;
static const CGFloat kPreviewStampRoom = 46.0f;
static const CGFloat kPreviewStampW   = 30.0f;
static const CGFloat kPreviewStampMineRoom = 22.0f;
static const CGFloat kPreviewTicksLeft = 18.0f;
static const CGFloat kPreviewTextMaxW = 230.0f;
static const CGFloat kPreviewTextMaxH = 80.0f;
static const CGFloat kPreviewBubbleMinH = 34.0f;
static const CGFloat kPreviewBubblePadV = TGMetricPadMedium + TGMetricPadTiny;

static NSArray *TGPreviewLines(void) {
	return @[@"How does this one look?", @"Like Telegram, only older."];
}

static CGSize TGPreviewSizeForLine(NSString *line, CGFloat fontSize) {
	UIFont *font = TGFontAtSize(fontSize);
	CGSize textSize = [line sizeWithFont:font constrainedToSize:CGSizeMake(kPreviewTextMaxW, kPreviewTextMaxH)];
	CGFloat bubbleW = ceilf(textSize.width + kPreviewStampRoom + TGMetricPadMedium);
	CGFloat bubbleH = ceilf(MAX(kPreviewBubbleMinH, textSize.height + kPreviewBubblePadV));
	return CGSizeMake(bubbleW, bubbleH);
}
/// The account header: the picture, the name under it, the phone under that.
static const CGFloat kMeAvatarTop  = TGMetricPadLarge + TGMetricPadTiny;
static const CGFloat kMeNameTop    = TGMetricPadMedium;
static const CGFloat kMeNameLine   = TGMetricLineTitle + TGMetricPadTiny;
static const CGFloat kMeTextInset  = TGMetricPadMedium;


- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (self.page == TGSettingsPageRoot && section == (NSInteger)self.sections.count - 1)
		return TGMetricSectionFooterRoot;
	return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAt:path];
	NSString *kind = row[TGRowKind];
	if ([kind isEqualToString:TGKindProfile]) return TGMetricSettingsProfileRow;
	if ([kind isEqualToString:TGKindPreview]) {
		CGFloat fontSize = [TGTheme shared].messageFontSize;
		NSArray *lines = TGPreviewLines();
		CGSize s0 = TGPreviewSizeForLine(lines[0], fontSize);
		CGSize s1 = TGPreviewSizeForLine(lines[1], fontSize);
		return kPreviewTop + s0.height + kPreviewGap + s1.height + kPreviewTop;
	}
	if ([kind isEqualToString:TGKindToggleInfo]){
		// Glyph, name, and the description wrapped in what is left once the
		// switch has taken its side.
		CGFloat width = self.tableView.bounds.size.width - TGMetricRow - TGMetricViewerBottomBar;
		CGSize size = [(row[TGRowDetail] ?: @"") sizeWithFont:TGFontCaption()
										   constrainedToSize:CGSizeMake(width, TGMetricImageMax)
											   lineBreakMode:NSLineBreakByWordWrapping];
		return MAX(TGMetricActionTile, TGMetricPollRow + size.height);
	}
	return TGMetricRow;
}

/// Two bubbles over the wallpaper, drawn from the palette that is in force.
/// Their Appearance page puts one at the top so a theme can be judged without
/// leaving the screen, which is the only way to judge one.
- (UITableViewCell *)previewCellFor:(UITableView *)tableView {
	TGTheme *theme = [TGTheme shared];
	CGFloat width = tableView.bounds.size.width;

	UITableViewCell *cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	CGFloat fontSize = theme.messageFontSize;
	NSArray *lines = TGPreviewLines();
	CGSize s0 = TGPreviewSizeForLine(lines[0], fontSize);
	CGSize s1 = TGPreviewSizeForLine(lines[1], fontSize);
	CGFloat totalH = kPreviewTop + s0.height + kPreviewGap + s1.height + kPreviewTop;

	UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, totalH)];
	canvas.backgroundColor = [theme chatBackgroundColour];
	canvas.clipsToBounds = YES;
	if (theme.wallpaper){
		UIImageView *paper = [[UIImageView alloc] initWithFrame:canvas.bounds];
		paper.image = theme.wallpaper;
		paper.contentMode = UIViewContentModeScaleAspectFill;
		[canvas addSubview:paper];
	}
	[cell.contentView addSubview:canvas];

	CGFloat yOffset = kPreviewTop;
	for (NSUInteger i = 0; i < 2; i++){
		BOOL mine = (i == 1);
		CGSize bSize = (i == 0) ? s0 : s1;
		CGFloat bubbleW = bSize.width;
		CGFloat bubbleH = bSize.height;
		CGFloat bubbleX = mine ? (width - bubbleW - kPreviewInset) : kPreviewInset;
		CGFloat bubbleY = yOffset;
		yOffset += bubbleH + kPreviewGap;

		UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(bubbleX, bubbleY, bubbleW, bubbleH)];

		CAGradientLayer *grad = [CAGradientLayer layer];
		grad.frame = bubble.bounds;
		grad.colors = mine ? [theme skeuoBubbleMineGradientColours] : [theme skeuoBubbleTheirsGradientColours];
		grad.cornerRadius = [theme bubbleCornerRadius];
		[bubble.layer insertSublayer:grad atIndex:0];

		bubble.backgroundColor = [UIColor clearColor];
		bubble.layer.cornerRadius = [theme bubbleCornerRadius];
		bubble.layer.borderWidth = 1.0f;
		bubble.layer.borderColor = (mine ? [theme skeuoBubbleMineBorderColour] : [theme skeuoBubbleTheirsBorderColour]).CGColor;
		bubble.clipsToBounds = YES;
		[canvas addSubview:bubble];

		UIFont *font = TGFontAtSize(fontSize);
		CGSize tFit = [lines[i] sizeWithFont:font constrainedToSize:CGSizeMake(bubbleW - kPreviewStampRoom, bubbleH)];
		CGFloat textTop = ceilf(TGCenteredOrigin(bubbleH, tFit.height));
		UILabel *text = [[UILabel alloc] initWithFrame:
				CGRectMake(kPreviewTextLeft, textTop, bubbleW - kPreviewStampRoom, tFit.height)];
		text.text = lines[i];
		text.font = font;
		text.textColor = [theme primaryTextColour];
		text.backgroundColor = [UIColor clearColor];
		text.adjustsFontSizeToFitWidth = NO;
		text.numberOfLines = 0;
		text.shadowColor = [theme etchedTextShadowColour];
		text.shadowOffset = TGMetricShadowOffsetEtched;
		[bubble addSubview:text];

		UILabel *stamp = [[UILabel alloc] initWithFrame:
				CGRectMake(bubbleW - kPreviewStampW - (mine ? kPreviewStampMineRoom : TGMetricPad),
						bubbleH - TGMetricLineCaption, kPreviewStampW, TGMetricStampHeight)];
		stamp.text = @"9:41";
		stamp.font = TGFontMicro();
		stamp.textColor = mine ? [theme timeMineColour] : [theme timeColour];
		stamp.backgroundColor = [UIColor clearColor];
		stamp.textAlignment = NSTextAlignmentRight;
		[bubble addSubview:stamp];

		if (mine) {
			UIImageView *ticks = [[UIImageView alloc] initWithFrame:
					CGRectMake(bubbleW - kPreviewTicksLeft, bubbleH - TGMetricLineCaption + 1.0f, TGMetricTicksWidth, TGMetricTicksHeight)];
			ticks.image = [TGIcons ticksColour:[theme timeMineColour] read:YES];
			[bubble addSubview:ticks];
		}
	}
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)path
{
	NSDictionary *row = [self rowAt:path];
	NSString *kind = row[TGRowKind];

	if ([kind isEqualToString:TGKindProfile])
		return [self profileCellFor:tableView];
	if ([kind isEqualToString:TGKindPreview])
		return [self previewCellFor:tableView];

	// Value1 puts the detail on the right, which is where every settings row
	// in the current client shows what it is set to. A row naming a person or
	// a call wants the other arrangement, and a cell's style is fixed at
	// creation - so they come from different queues.
	if ([kind isEqualToString:TGKindToggleInfo])
		return [self switchInfoCell:tableView row:row at:path];

	BOOL subtitle = [row[TGRowSubtitle] boolValue];
	NSString *reuse = subtitle ? @"TGSettingsSubtitleCell" : @"TGSettingsCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGSettingsCell alloc] initWithStyle:(subtitle
						? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1)
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.imageView.image = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	[theme styleGroupedCell:cell forRow:path.row totalRows:[self.sections[path.section][@"rows"] count]];

	cell.textLabel.text = row[TGRowTitle];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.detailTextLabel.text = row[TGRowDetail];
	// The system's own type, as on every other settings page of the OS.
	UITableViewCell *system = [TGTheme systemCellOfStyle:(subtitle
			? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1)];
	cell.textLabel.font = system.textLabel.font;
	cell.textLabel.textColor = system.textLabel.textColor;
	cell.detailTextLabel.font = system.detailTextLabel.font;
	cell.detailTextLabel.textColor = system.detailTextLabel.textColor;
	if ([kind isEqualToString:TGKindDestructive])
		cell.textLabel.textColor = [theme destructiveColour];

	if (row[TGRowIcon])
		cell.imageView.image = [TGIcons settingsIconNamed:row[TGRowIcon]
													color:row[TGRowColour]];

	if ([kind isEqualToString:TGKindToggle]){
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = [row[TGRowOn] boolValue];
		toggle.tag = path.section * 100 + path.row;
		[toggle addTarget:self action:@selector(toggleChanged:)
		 forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else if ([kind isEqualToString:TGKindCheck]){
		cell.accessoryType = [row[TGRowChecked] boolValue]
				? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if ([kind isEqualToString:TGKindDisclosure]){
		cell.accessoryView = [[UIImageView alloc] initWithImage:[TGIcons skeuomorphicDisclosureChevron]];
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else if ([kind isEqualToString:TGKindAction]){
		cell.textLabel.textColor = [theme accentColour];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
	} else if ([kind isEqualToString:TGKindPlain]){
		cell.textLabel.textColor = [theme secondaryTextColour];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}

	return cell;
}

- (UITableViewCell *)switchInfoCell:(UITableView *)tableView
							   row:(NSDictionary *)row
								at:(NSIndexPath *)path
{
	TGTheme *theme = [TGTheme shared];
	static NSString *reuse = @"TGSettingsSwitchInfoCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGSettingsCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	[theme styleGroupedCell:cell forRow:path.row totalRows:[self.sections[path.section][@"rows"] count]];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;

	cell.textLabel.text = row[TGRowTitle];
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = [theme primaryTextColour];

	cell.detailTextLabel.text = row[TGRowDetail];
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	cell.detailTextLabel.numberOfLines = 0;      // it is a sentence, not a value

	cell.imageView.image = row[TGRowIcon]
			? [TGIcons settingsIconNamed:row[TGRowIcon] color:row[TGRowColour]] : nil;

	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = [row[TGRowOn] boolValue];
	toggle.tag = path.section * 100 + path.row;
	[toggle addTarget:self action:@selector(toggleChanged:)
	 forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

/// Toggles navigation bar visibility on scroll down/up.
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.tableView || self.page == TGSettingsPageRoot)
		return;

	CGFloat y = scrollView.contentOffset.y;
	CGFloat delta = y - self.lastScrollY;
	if (fabsf((float)delta) < TGMetricFontSizeDeltaThreshold)
		return;
	self.lastScrollY = y;

	// Never hide it while the top of the list is showing: there would be
	// nothing on screen to bring it back with.
	BOOL hide = (delta > 0) && (y > TGMetricRow);
	if (self.navigationController.navigationBarHidden != hide)
		[self.navigationController setNavigationBarHidden:hide animated:YES];
}

- (void)toggleChanged:(UISwitch *)toggle {
	NSIndexPath *path = [NSIndexPath indexPathForRow:(toggle.tag % 100)
										   inSection:(toggle.tag / 100)];
	void (^changed)(BOOL) = [self rowAt:path][TGRowToggle];
	if (changed)
		changed(toggle.on);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
	[tableView deselectRowAtIndexPath:path animated:YES];

	NSDictionary *row = [self rowAt:path];
	if ([row[TGRowKind] isEqualToString:TGKindProfile]){
		[self openMyProfile];
		return;
	}

	void (^tap)(void) = row[TGRowTap];
	if (tap)
		tap();
}

/// Profile header cell with avatar, user display name, phone, and username.
- (UITableViewCell *)profileCellFor:(UITableView *)tableView {
	if (self.profileCell)
		return self.profileCell;

	TGTheme *theme = [TGTheme shared];
	CGFloat width = tableView.bounds.size.width;
	CGFloat side = 80;

	UITableViewCell *profile = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleGroupedCell:profile forRow:0 totalRows:1];
	profile.selectionStyle = UITableViewCellSelectionStyleBlue;

	NSDictionary *me = [TGClient shared].me;
	NSString *name = [me[@"first_name"] length] ? me[@"first_name"]
			: ([me[@"username"] length] ? me[@"username"] : @"Telegram");
	if ([me[@"last_name"] length])
		name = [NSString stringWithFormat:@"%@ %@", name, me[@"last_name"]];
	NSString *phone = [me[@"phone"] length]
			? [NSString stringWithFormat:@"+%@", me[@"phone"]] : @"";
	NSString *username = [me[@"username"] length]
			? [NSString stringWithFormat:@"@%@", me[@"username"]] : @"";

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(TGCenteredOrigin(width, side), kMeAvatarTop, side, side)];
	// Pre-baked circle bitmap: no CALayer cornerRadius or rasterizing mask on scrolling headers.
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.opaque = NO;
	self.avatarView.backgroundColor = [UIColor clearColor];
	self.avatarView.image = [TGIcons avatarWithInitials:
			[TGIcons initialsForTitle:name]
												   size:side
											   colourId:[me[@"id"] longLongValue]];
	[profile.contentView addSubview:self.avatarView];

	NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:[me[@"id"] longLongValue]];
	if (fileId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path.length)
				return;
			CGSize target = CGSizeMake(side, side);
			CGFloat screenScale = TGMainScreenScale();
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				UIImage *decoded = [TGIcons decodedImageAtPath:path fittingSize:target fill:YES scale:screenScale];
				UIImage *round = [TGIcons roundedImage:decoded size:target radius:TGHalf(side) corners:UIRectCornerAllCorners];
				if (!round)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					weakSelf.avatarView.image = round;
				});
			});
		}];
	}

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(kMeTextInset, kMeAvatarTop + side + kMeNameTop,
					width - TGDoubled(kMeTextInset), kMeNameLine)];
	nameLabel.text = name;
	nameLabel.font = TGFontTitle();
	nameLabel.textAlignment = NSTextAlignmentCenter;
	nameLabel.textColor = [theme primaryTextColour];
	nameLabel.backgroundColor = [UIColor clearColor];
	[profile.contentView addSubview:nameLabel];

	UILabel *phoneLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(kMeTextInset, kMeAvatarTop + side + kMeNameTop + kMeNameLine,
					width - TGDoubled(kMeTextInset), TGMetricLineRow)];
	phoneLabel.text = (phone.length && username.length)
			? [NSString stringWithFormat:@"%@ • %@", phone, username]
			: (phone.length ? phone : username);
	phoneLabel.font = TGFontBody();
	phoneLabel.textAlignment = NSTextAlignmentCenter;
	phoneLabel.adjustsFontSizeToFitWidth = YES;
	phoneLabel.textColor = [theme secondaryTextColour];
	phoneLabel.backgroundColor = [UIColor clearColor];
	[profile.contentView addSubview:phoneLabel];

	self.profileCell = profile;
	return profile;
}

@end

// vim:ft=objc
