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

#pragma mark - the row model

// A row says what it is and what happens when it is touched. Everything the
// table does - height, cell, selection - reads these keys, so a new setting is
// one entry in one array rather than a new case in six switch statements.
static NSString *const TGRowTitle    = @"title";
static NSString *const TGRowDetail   = @"detail";
static NSString *const TGRowKind     = @"kind";
static NSString *const TGRowTap      = @"tap";       // void(^)(void)
static NSString *const TGRowToggle   = @"toggle";    // void(^)(BOOL)
static NSString *const TGRowOn       = @"on";
static NSString *const TGRowChecked  = @"checked";
static NSString *const TGRowIcon     = @"icon";
static NSString *const TGRowColour   = @"colour";
static NSString *const TGRowSubtitle = @"subtitle";

// Kinds
static NSString *const TGKindPlain       = @"plain";
static NSString *const TGKindDisclosure  = @"disclosure";
static NSString *const TGKindToggle      = @"switch";
static NSString *const TGKindCheck       = @"check";
static NSString *const TGKindDestructive = @"destructive";
static NSString *const TGKindProfile     = @"profile";
static NSString *const TGKindPreview     = @"preview";   // the two sample bubbles
static NSString *const TGKindAction      = @"action";    // blue text, no chevron
static NSString *const TGKindToggleInfo  = @"switchinfo";// icon, description, switch

static NSDictionary *TGSection(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

static NSMutableDictionary *TGRow(NSString *kind, NSString *title) {
	return [@{TGRowKind : kind, TGRowTitle : title ?: @""} mutableCopy];
}

static NSDictionary *TGTapRow(NSString *title, NSString *detail, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDisclosure, title);
	if (detail) row[TGRowDetail] = detail;
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static NSDictionary *TGSwitchRow(NSString *title, BOOL on, void (^changed)(BOOL)) {
	NSMutableDictionary *row = TGRow(TGKindToggle, title);
	row[TGRowOn] = @(on);
	if (changed) row[TGRowToggle] = [changed copy];
	return row;
}

/// Their Power Saving rows: a coloured glyph, the name, what it actually does
/// underneath in grey, and the switch. A bare row of switches says nothing
/// about what turning one off costs.
static NSDictionary *TGSwitchInfoRow(NSString *title, NSString *detail,
									 NSString *icon, UIColor *colour,
									 BOOL on, void (^changed)(BOOL)) {
	NSMutableDictionary *row = TGRow(TGKindToggleInfo, title);
	if (detail) row[TGRowDetail] = detail;
	if (icon)   row[TGRowIcon]   = icon;
	if (colour) row[TGRowColour] = colour;
	row[TGRowOn] = @(on);
	if (changed) row[TGRowToggle] = [changed copy];
	return row;
}

static NSDictionary *TGCheckRow(NSString *title, NSString *detail,
								BOOL checked, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindCheck, title);
	if (detail) row[TGRowDetail] = detail;
	row[TGRowChecked] = @(checked);
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

/// A name over what it is about, the way a call log and a person list read.
/// Value1 put them side by side, which truncated both.
static NSDictionary *TGSubtitleRow(NSString *title, NSString *subtitle,
								   void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDisclosure, title);
	if (subtitle) row[TGRowDetail] = subtitle;
	row[TGRowSubtitle] = @YES;
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

/// TDLib stores these lowercase; their rows show them as words.
static NSString *TGPrivacyLabel(NSString *value) {
	if ([value isEqualToString:@"everybody"]) return @"Everybody";
	if ([value isEqualToString:@"contacts"])  return @"My Contacts";
	if ([value isEqualToString:@"nobody"])    return @"Nobody";
	return @"...";
}

/// A blue line of text that does something, with no chevron: "Set Profile
/// Photo" and "Add Account" read this way in their client.
static NSDictionary *TGActionRow(NSString *title, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindAction, title);
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static NSDictionary *TGRedRow(NSString *title, void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDestructive, title);
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static NSDictionary *TGIconRow(NSString *title, NSString *icon, UIColor *colour,
							   void (^tap)(void)) {
	NSMutableDictionary *row = TGRow(TGKindDisclosure, title);
	row[TGRowIcon] = icon;
	row[TGRowColour] = colour;
	if (tap) row[TGRowTap] = [tap copy];
	return row;
}

static UIColor *TGRGB(CGFloat r, CGFloat g, CGFloat b) {
	return [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
}

static NSString *TGBytes(long long bytes) {
	if (bytes <= 0)              return @"0 KB";
	if (bytes < 1024 * 1024)     return [NSString stringWithFormat:@"%.0f KB",
											bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

#pragma mark -

@interface TGSettingsViewController () <UIActionSheetDelegate, UIAlertViewDelegate,
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSMutableDictionary *privacy;    // setting -> value
@property (nonatomic, strong) NSMutableDictionary *muted;      // scope -> NSNumber
@property (nonatomic, strong) NSMutableDictionary *previews;   // scope -> NSNumber
@property (nonatomic, strong) UITableViewCell *profileCell;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) NSArray *languages;
@property (nonatomic, strong) NSString *currentLanguage;
@property (nonatomic, strong) NSArray *blocked;
@property (nonatomic, strong) NSArray *calls;
@property (nonatomic, assign) NSInteger accountTtl;
@property (nonatomic, assign) BOOL hasPassword;
@property (nonatomic, assign) BOOL passwordKnown;
@property (nonatomic, assign) BOOL suggestFrequent;
@property (nonatomic, assign) long long networkSent;
@property (nonatomic, assign) long long networkReceived;
@property (nonatomic, assign) NSInteger versionTaps;
@property (nonatomic, strong) NSString *tdlibVersion;
@property (nonatomic, assign) BOOL pickingProfilePhoto;
@property (nonatomic, assign) BOOL searchHidden;
@property (nonatomic, assign) CGFloat lastScrollY;
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
	[self applyTheme];

	self.privacy  = [NSMutableDictionary dictionary];
	self.muted    = [NSMutableDictionary dictionary];
	self.previews = [NSMutableDictionary dictionary];
	self.suggestFrequent = YES;

	self.title = [self pageTitle];

	if (self.page == TGSettingsPageRoot)
		[self buildHeader];

	[self rebuild];
	[self loadForPage];

	// A theme change used to be handled by throwing the whole interface away.
	// Every screen repaints itself now, and this one is where the theme is
	// usually being changed from.
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf repaint];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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
		case TGSettingsPageNotifications: return @"Notifications and Sounds";
		case TGSettingsPagePrivacy:       return @"Privacy and Security";
		case TGSettingsPageLanguage:      return @"Language";
		case TGSettingsPageBlocked:       return @"Blocked Users";
		case TGSettingsPagePowerSaving:   return @"Power Saving";
		case TGSettingsPageRecentCalls:   return @"Recent Calls";
		case TGSettingsPageDebug:         return @"Debug Menu";
		default:                          return @"Settings";
	}
}

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self rebuild];
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

#pragma mark - header

/// The root page carries no title: their settings open straight into your own
/// account, and a bar spelling out "Settings" above a tab already labelled
/// Settings says it twice. The title itself stays, because the back button of
/// every page pushed from here is drawn from it.
///
/// The search bar sits above the first row and is scrolled out of sight, so it
/// arrives on a pull down the way search does everywhere else on this OS.
- (void)buildHeader {
	self.navigationItem.titleView = [[UIView alloc] initWithFrame:CGRectZero];

	CGFloat width = self.view.bounds.size.width ?: 320;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44)];
	header.backgroundColor = [UIColor clearColor];

	UISearchBar *search = [[UISearchBar alloc] initWithFrame:header.bounds];
	search.placeholder = @"Search Settings";
	search.searchBarStyle = UISearchBarStyleMinimal;
	[header addSubview:search];

	self.tableView.tableHeaderView = header;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (self.page != TGSettingsPageRoot)
		return;

	// With no navigation bar the table starts at the top of the screen, and
	// the status bar would sit on the first row.
	CGFloat statusBar = 20;
	if (self.tableView.contentInset.top != statusBar){
		self.tableView.contentInset = UIEdgeInsetsMake(statusBar, 0, 0, 0);
		self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
	}

	// Once, and only while the list is still at the top: doing it on every
	// layout would yank the table back up under the user mid-scroll.
	if (self.searchHidden)
		return;
	CGFloat height = self.tableView.tableHeaderView.frame.size.height;
	if (height <= 0)
		return;
	self.searchHidden = YES;
	self.tableView.contentOffset = CGPointMake(0, height - statusBar);
}

/// The version, the way their page ends with one - and, as in their client,
/// ten taps on it opens the debug menu.
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (self.page != TGSettingsPageRoot || section != (NSInteger)self.sections.count - 1)
		return [self footerLabelForSection:section];
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, 40)];
	label.text = [NSString stringWithFormat:@"iTgLegacy %@ (%@) armv7",
			info[@"CFBundleShortVersionString"] ?: @"", info[@"CFBundleVersion"] ?: @""];
	label.font = [UIFont systemFontOfSize:12];
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	label.userInteractionEnabled = YES;
	[label addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(versionTapped)]];
	return label;
}

- (UIView *)footerLabelForSection:(NSInteger)section {
	NSString *text = self.sections[section][@"footer"];
	if (!text.length)
		return nil;
	CGSize size = [self footerTextSize:text];
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(
			kFooterInset, 8, self.tableView.bounds.size.width - 2 * kFooterInset,
			size.height)];
	label.text = text;
	label.font = [UIFont systemFontOfSize:kFooterFont];
	label.numberOfLines = 0;
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];

	UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
			self.tableView.bounds.size.width, size.height + 16)];
	holder.backgroundColor = [UIColor clearColor];
	[holder addSubview:label];
	return holder;
}

- (void)versionTapped {
	self.versionTaps++;
	if (self.versionTaps < 10)
		return;
	self.versionTaps = 0;
	[self openPage:TGSettingsPageDebug];
}

#pragma mark - loading

- (void)loadForPage {
	__weak typeof(self) weakSelf = self;

	if (self.page == TGSettingsPageNotifications){
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
		[[TGClient shared] hasPasswordWithCompletion:^(BOOL has, NSString *email){
			weakSelf.hasPassword = has;
			weakSelf.passwordKnown = YES;
			[weakSelf rebuild];
		}];
		// TDLib stores the negative, so the row and the option are opposites.
		[[TGClient shared] optionValue:@"disable_top_chats" completion:^(id value){
			weakSelf.suggestFrequent = ![value boolValue];
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageData){
		[[TGClient shared] networkStatsWithCompletion:^(long long sent, long long got){
			weakSelf.networkSent = sent;
			weakSelf.networkReceived = got;
			[weakSelf rebuild];
		}];
		return;
	}

	if (self.page == TGSettingsPageLanguage){
		[[TGClient shared] languagesWithCompletion:^(NSArray *languages,
													NSString *current){
			weakSelf.languages = languages;
			weakSelf.currentLanguage = current;
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
		// Their page opens with the picture centred, the name under it and the
		// number under that - not a row with the picture off to one side.
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

#pragma mark - table

- (NSDictionary *)rowAt:(NSIndexPath *)path {
	if (path.section >= (NSInteger)self.sections.count)
		return nil;
	NSArray *rows = self.sections[path.section][@"rows"];
	return path.row < (NSInteger)rows.count ? rows[path.row] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.sections[section][@"header"];
}

/// The footers explain things, so there are a lot of words in them; at UIKit's
/// default size they were louder than the settings they describe. Drawn here
/// rather than handed over as a title so the size is ours.
static const CGFloat kFooterFont   = 12.0f;
static const CGFloat kFooterInset  = 15.0f;

- (CGSize)footerTextSize:(NSString *)text {
	CGFloat width = self.tableView.bounds.size.width - 2 * kFooterInset;
	return [text sizeWithFont:[UIFont systemFontOfSize:kFooterFont]
			constrainedToSize:CGSizeMake(MAX(width, 100), 400)
				lineBreakMode:NSLineBreakByWordWrapping];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (self.page == TGSettingsPageRoot && section == (NSInteger)self.sections.count - 1)
		return 44;
	NSString *text = self.sections[section][@"footer"];
	if (!text.length)
		return 14;
	return [self footerTextSize:text].height + 16;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAt:path];
	NSString *kind = row[TGRowKind];
	if ([kind isEqualToString:TGKindProfile]) return 168.0f;
	if ([kind isEqualToString:TGKindPreview]) return 108.0f;
	if ([kind isEqualToString:TGKindToggleInfo]){
		// Glyph, name, and the description wrapped in what is left once the
		// switch has taken its side.
		CGFloat width = self.tableView.bounds.size.width - 44 - 62;
		CGSize size = [(row[TGRowDetail] ?: @"") sizeWithFont:[UIFont systemFontOfSize:13]
										   constrainedToSize:CGSizeMake(width, 200)
											   lineBreakMode:NSLineBreakByWordWrapping];
		return MAX(52.0f, 30.0f + size.height);
	}
	return 44.0f;
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

	UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 108)];
	canvas.backgroundColor = [theme chatBackgroundColour];
	canvas.clipsToBounds = YES;
	if (theme.wallpaper){
		UIImageView *paper = [[UIImageView alloc] initWithFrame:canvas.bounds];
		paper.image = theme.wallpaper;
		paper.contentMode = UIViewContentModeScaleAspectFill;
		[canvas addSubview:paper];
	}
	[cell.contentView addSubview:canvas];

	NSArray *lines = @[@"How does this one look?", @"Like Telegram, only older."];
	for (NSUInteger i = 0; i < 2; i++){
		BOOL mine = (i == 1);
		CGFloat bubbleW = 176, bubbleH = 34;
		UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(
				mine ? width - bubbleW - 12 : 12, 14 + i * (bubbleH + 8),
				bubbleW, bubbleH)];
		bubble.backgroundColor = mine ? [theme bubbleMineColour]
									  : [theme bubbleTheirsColour];
		bubble.layer.cornerRadius = [theme bubbleCornerRadius];
		bubble.layer.borderWidth = [theme bubbleBorderWidth];
		bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
		[canvas addSubview:bubble];

		UILabel *text = [[UILabel alloc] initWithFrame:
				CGRectMake(9, 0, bubbleW - 46, bubbleH)];
		text.text = lines[i];
		text.font = [UIFont systemFontOfSize:MIN(theme.messageFontSize, 14.0f)];
		text.textColor = [theme primaryTextColour];
		text.backgroundColor = [UIColor clearColor];
		text.adjustsFontSizeToFitWidth = YES;
		[bubble addSubview:text];

		UILabel *stamp = [[UILabel alloc] initWithFrame:
				CGRectMake(bubbleW - 38, bubbleH - 16, 30, 12)];
		stamp.text = @"9:41";
		stamp.font = [UIFont systemFontOfSize:10];
		stamp.textColor = [theme timeColour];
		stamp.backgroundColor = [UIColor clearColor];
		stamp.textAlignment = NSTextAlignmentRight;
		[bubble addSubview:stamp];
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
		cell = [[UITableViewCell alloc] initWithStyle:(subtitle
						? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1)
									  reuseIdentifier:reuse];

	TGTheme *theme = [TGTheme shared];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.imageView.image = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	[theme styleCell:cell];

	cell.textLabel.text = row[TGRowTitle];
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = [kind isEqualToString:TGKindDestructive]
			? TGRGB(0.8f, 0.1f, 0.1f) : [theme primaryTextColour];
	cell.detailTextLabel.text = row[TGRowDetail];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:subtitle ? 13 : 15];
	cell.detailTextLabel.textColor = subtitle
			? [theme secondaryTextColour] : [theme cellDetailColour];

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
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	[theme styleCell:cell];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;

	cell.textLabel.text = row[TGRowTitle];
	cell.textLabel.font = [UIFont systemFontOfSize:16];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = [theme primaryTextColour];

	cell.detailTextLabel.text = row[TGRowDetail];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
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

/// iOS 8 has hidesBarsOnSwipe; this OS does not, and thirty-two points is a
/// tenth of the list on a 3.5-inch screen. Going down the list takes the bar
/// away, coming back up brings it back - the deadband keeps a rubber-band
/// bounce at the ends from flickering it.
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.tableView || self.page == TGSettingsPageRoot)
		return;

	CGFloat y = scrollView.contentOffset.y;
	CGFloat delta = y - self.lastScrollY;
	if (fabsf((float)delta) < 14.0f)
		return;
	self.lastScrollY = y;

	// Never hide it while the top of the list is showing: there would be
	// nothing on screen to bring it back with.
	BOOL hide = (delta > 0) && (y > 44);
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
		UIViewController *profile = [[TGEditProfileViewController alloc] init];
		profile.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:profile animated:YES];
		return;
	}

	void (^tap)(void) = row[TGRowTap];
	if (tap)
		tap();
}

/// Their page opens with a large picture centred, the name in bold under it
/// and "+number • @username" under that. This used to be a row with the
/// picture off to the left, which is not how any current client shows your
/// own account.
- (UITableViewCell *)profileCellFor:(UITableView *)tableView {
	if (self.profileCell)
		return self.profileCell;

	TGTheme *theme = [TGTheme shared];
	CGFloat width = tableView.bounds.size.width;
	CGFloat side = 80;

	UITableViewCell *profile = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[theme styleCell:profile];
	profile.selectionStyle = UITableViewCellSelectionStyleNone;

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
			CGRectMake((width - side) / 2, 18, side, side)];
	self.avatarView.layer.cornerRadius = side / 2;
	self.avatarView.clipsToBounds = YES;
	self.avatarView.layer.shouldRasterize = YES;
	self.avatarView.layer.rasterizationScale = [UIScreen mainScreen].scale;
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.image = [TGIcons avatarWithInitials:
			[name substringToIndex:1].uppercaseString
												   size:side
											   colourId:[me[@"id"] longLongValue]];
	[profile.contentView addSubview:self.avatarView];

	NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:[me[@"id"] longLongValue]];
	if (fileId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			[TGIcons loadImageAtPath:path into:weakSelf.avatarView];
		}];
	}

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 18 + side + 10, width - 20, 28)];
	nameLabel.text = name;
	nameLabel.font = [UIFont boldSystemFontOfSize:22];
	nameLabel.textAlignment = NSTextAlignmentCenter;
	nameLabel.textColor = [theme primaryTextColour];
	nameLabel.backgroundColor = [UIColor clearColor];
	[profile.contentView addSubview:nameLabel];

	UILabel *phoneLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(10, 18 + side + 38, width - 20, 20)];
	phoneLabel.text = (phone.length && username.length)
			? [NSString stringWithFormat:@"%@ • %@", phone, username]
			: (phone.length ? phone : username);
	phoneLabel.font = [UIFont systemFontOfSize:15];
	phoneLabel.textAlignment = NSTextAlignmentCenter;
	phoneLabel.adjustsFontSizeToFitWidth = YES;
	phoneLabel.textColor = [theme secondaryTextColour];
	phoneLabel.backgroundColor = [UIColor clearColor];
	[profile.contentView addSubview:phoneLabel];

	self.profileCell = profile;
	return profile;
}

/// Your own profile, as everyone else sees it - their "My Profile" row.
- (void)openMyProfile {
	int64_t userId = [[TGClient shared].me[@"id"] longLongValue];
	if (!userId)
		return;
	Class profileClass = NSClassFromString(@"TGProfileViewController");
	UIViewController *profile = [[profileClass alloc]
			initWithChatId:userId userId:userId
					 title:[TGClient shared].me[@"first_name"] ?: @"Profile"];
	profile.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:profile animated:YES];
}

/// A second account is a second TDLib client: another database, another
/// connection, and the whole message cache twice over. On 504MB that is not a
/// switch to flip, so the row says what it is waiting for rather than failing
/// after the user has typed a phone number into it.
- (void)explainAddAccount {
	if ([TGCapabilities canHoldMultipleAccounts]){
		[self toast:@"Multiple accounts are not wired up yet on this build."];
		return;
	}
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Add Account"
			message:[NSString stringWithFormat:
					@"A second account needs a second TDLib client and a second "
					@"copy of the cache. This is a %@ device with %lu MB, and "
					@"that needs the Full tier - 2 GB or more.",
					[TGDevice tierName] ?: @"Legacy", (unsigned long)[TGCapabilities memoryMB]]
		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)pickProfilePhoto {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	self.pickingProfilePhoto = YES;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - actions

- (void)pushPlaceholder:(NSString *)featureName {
	TGPlaceholderViewController *placeholder = [[TGPlaceholderViewController alloc] init];
	placeholder.featureName = featureName;
	placeholder.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:placeholder animated:YES];
}

- (void)openURL:(NSString *)url {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

/// Saved Messages is a real chat - your own - so it opens as one rather than
/// as a page saying the feature is missing.
- (void)openSavedMessages {
	int64_t chatId = [[TGClient shared] savedMessagesChatId];
	if (!chatId){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Saved Messages"
				message:@"This account is still loading."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
		return;
	}
	[self openChat:chatId title:@"Saved Messages"];
}

- (void)openChat:(int64_t)chatId title:(NSString *)title {
	// Loaded by name to keep the settings screen from knowing about chats in
	// general; it only ever opens one at a time.
	Class chatClass = NSClassFromString(@"TGChatViewController");
	UIViewController *chat = [[chatClass alloc] init];
	[chat setValue:@(chatId) forKey:@"chatId"];
	[chat setValue:(title ?: @"") forKey:@"chatTitle"];
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

/// Folders are a filter over the chat list, so this says where they are rather
/// than building a second copy of the same sheet.
- (void)showFolders {
	NSArray *folders = [TGClient shared].folders;
	NSString *message = folders.count
			? [NSString stringWithFormat:@"%lu folders. Pick one from Folders "
					@"above the chat list.", (unsigned long)folders.count]
			: @"This account has no chat folders. They are set up in Telegram "
			  @"on a desktop or a newer phone, and appear here.";
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Folders"
			message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

- (void)showPremiumState {
	[[TGClient shared] premiumStateWithCompletion:^(NSString *summary){
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Telegram Premium"
				message:summary.length ? summary
						: @"This account does not have Premium. It is bought in "
						  @"an official client; what it unlocks works here."
			   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

/// Setting a password is a multi-step flow with a recovery address; this screen
/// reports the state and says where to change it rather than pretending to.
- (void)showTwoStepState {
	[[TGClient shared] hasPasswordWithCompletion:^(BOOL has, NSString *email){
		NSString *message = has
				? [NSString stringWithFormat:@"Two-step verification is on.%@",
						email.length ? [NSString stringWithFormat:
								@"\nRecovery address: %@", email] : @""]
				: @"Two-step verification is off. It is set up in an official "
				  @"client; once it is on, this app asks for the password when "
				  @"signing in.";
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Two-Step Verification"
				message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	}];
}

- (void)openSupport {
	// Their support is a chat, not a web page.
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatWithUsername:@"BotSupport"
							 completion:^(int64_t chatId, NSString *title){
		if (!chatId){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Support"
					message:@"Support is not reachable from this account right now."
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
			return;
		}
		[weakSelf openChat:chatId title:(title ?: @"Telegram Support")];
	}];
}

- (void)askPrivacyRuleAtIndex:(NSUInteger)index {
	UIActionSheet *sheet = [[UIActionSheet alloc]
			initWithTitle:[TGSettingsViewController privacyTitles][index]
				 delegate:self
		cancelButtonTitle:nil
   destructiveButtonTitle:nil
		otherButtonTitles:@"Everybody", @"My Contacts", @"Nobody", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 91 + index;
	[sheet showInView:self.view];
}

- (void)chooseAutoNight {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Auto-Night Mode"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"Disabled",
														   @"22:00 - 07:00",
														   @"21:00 - 08:00",
														   @"23:00 - 06:00", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 87;
	[sheet showInView:self.view];
}

/// Four sizes is enough on a 3.5-inch screen; a slider would be finer than
/// the difference it makes.
- (void)chooseTextSize {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Message text size"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"13 pt", @"15 pt",
														   @"17 pt", @"19 pt", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 88;
	[sheet showInView:self.view];
}

#pragma mark - wallpaper

- (void)chooseWallpaper {
	if ([TGTheme shared].wallpaper){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chat wallpaper"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:@"Remove"
												 otherButtonTitles:@"Choose another", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		sheet.tag = 89;
		[sheet showInView:self.view];
		return;
	}
	[self presentWallpaperPicker];
}

- (void)presentWallpaperPicker {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image){
		self.pickingProfilePhoto = NO;
		return;
	}

	// One picker serves the wallpaper and the profile picture, so it has to
	// know which row opened it.
	if (self.pickingProfilePhoto){
		self.pickingProfilePhoto = NO;
		[self uploadProfilePhoto:image];
		return;
	}
	[[TGTheme shared] setWallpaperImage:image];
	[self rebuild];
}

/// TDLib uploads from a file, and a camera frame is far larger than a picture
/// anyone will ever see as an avatar - so it is scaled before it is written.
- (void)uploadProfilePhoto:(UIImage *)image {
	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(640, 640)
									   fill:NO scale:1.0f];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"profile-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, 0.9f) writeToFile:path atomically:YES]){
		[self toast:@"Could not prepare the picture."];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setProfilePhotoAtPath:path completion:^(BOOL ok){
		if (!ok){
			[weakSelf toast:@"Telegram refused the picture."];
			return;
		}
		// The new file id arrives with the updateUser that follows.
		weakSelf.profileCell = nil;
		[weakSelf rebuild];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	self.pickingProfilePhoto = NO;
	[picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - sheets and alerts

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 87){
		TGTheme *theme = [TGTheme shared];
		if (index == 0){
			theme.autoNight = TGAutoNightOff;
		} else {
			static const NSInteger from[3] = {22, 21, 23};
			static const NSInteger to[3]   = { 7,  8,  6};
			theme.autoNightFromHour = from[index - 1];
			theme.autoNightToHour   = to[index - 1];
			theme.autoNight = TGAutoNightScheduled;
		}
		[self rebuild];
		return;
	}

	if (sheet.tag == 88){
		[TGTheme shared].messageFontSize = 13.0f + index * 2.0f;
		[self rebuild];
		return;
	}

	if (sheet.tag == 89){
		if (index == sheet.destructiveButtonIndex)
			[[TGTheme shared] setWallpaperImage:nil];
		else
			[self presentWallpaperPicker];
		[self rebuild];
		return;
	}

	if (sheet.tag == 90){
		static const NSInteger months[4] = {1, 3, 6, 12};
		[[TGClient shared] setAccountTtlDays:months[index] * 30];
		self.accountTtl = months[index] * 30;
		[self rebuild];
		return;
	}

	if (sheet.tag >= 91){
		NSInteger row = sheet.tag - 91;
		NSString *setting = [TGSettingsViewController privacySettings][row];
		NSString *value = @[@"everybody", @"contacts", @"nobody"][index];
		[[TGClient shared] setPrivacyRule:setting to:value];
		self.privacy[setting] = value;
		[self rebuild];
	}
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index {
	if (index == alert.cancelButtonIndex)
		return;

	switch (alert.tag){
		case 61:
			[[TGClient shared] resetAllNotificationSettings];
			[self loadForPage];
			break;
		case 62:
			[[TGClient shared] clearImportedContacts];
			break;
		case 63:
			[[TGClient shared] resetNetworkStats];
			self.networkSent = 0;
			self.networkReceived = 0;
			[self rebuild];
			break;
		case 64:
			[[TGClient shared] clearLocalDatabase];
			break;
		case 65: {
			NSString *domain = [NSBundle mainBundle].bundleIdentifier;
			[NSUserDefaults.standardUserDefaults removePersistentDomainForName:domain];
			[NSUserDefaults.standardUserDefaults synchronize];
			[self repaint];
			[self toast:@"Preferences reset."];
			break;
		}
		default:
			if ([alert.title isEqualToString:@"Log out"])
				[[TGClient shared] logOut];
			break;
	}
}

@end

// vim:ft=objc
