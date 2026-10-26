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

	[self rebuild];
	[self loadForPage];

	// Repaint on theme change notification.
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
		case TGSettingsPageFolders:       return @"Chat Folders";
		case TGSettingsPageProxy:         return @"Proxy";
		case TGSettingsPageDownloads:     return @"Downloads";
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
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view
	   forSection:(NSInteger)section {
	[[TGTheme shared] styleSectionHeader:view];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
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

/// The version, the way their page ends with one - and, as in their client,
/// ten taps on it opens the debug menu.
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (self.page != TGSettingsPageRoot || section != (NSInteger)self.sections.count - 1)
		return [self footerLabelForSection:section];
	NSDictionary *info = [NSBundle mainBundle].infoDictionary;
	UILabel *label = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, kVersionRow)];
	label.text = [NSString stringWithFormat:@"LegacyTG %@ (%@) armv7",
			info[@"CFBundleShortVersionString"] ?: @"", info[@"CFBundleVersion"] ?: @""];
	label.font = TGFontMeta();
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
			kFooterInset, 8, self.tableView.bounds.size.width - TGDoubled(kFooterInset),
			size.height)];
	label.text = text;
	label.font = TGFontMeta();
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

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *text = self.sections[section][@"header"];
	if (text.length)
		return TGMetricSectionHeaderHeight;
	return TGMetricSectionHeaderEmpty;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	NSString *text = self.sections[section][@"header"];
	if (!text.length)
		return [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, TGMetricSectionHeaderEmpty)];
	UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, TGMetricSectionHeaderHeight)];
	holder.backgroundColor = [UIColor clearColor];
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kFooterInset,
			TGMetricPadMedium, tableView.bounds.size.width - TGDoubled(kFooterInset),
			TGMetricLineBody)];
	label.text = text.uppercaseString;
	label.font = TGFontMeta();
	label.textColor = [[TGTheme shared] sectionHeaderColour];
	label.backgroundColor = [UIColor clearColor];
	[holder addSubview:label];
	return holder;
}

/// The footers explain things, so there are a lot of words in them; at UIKit's
/// default size they were louder than the settings they describe. Drawn here
/// rather than handed over as a title so the size is ours.
static const CGFloat kFooterInset  = TGMetricGutter;
/// The version line that ends the root page.
static const CGFloat kVersionRow   = 40.0f;
/// Measuring a footer: the narrowest column worth wrapping into, and a height
/// no footer will reach, which is how sizeWithFont: is told "as tall as it
/// needs".
static const CGFloat kFooterMinW   = 100.0f;
static const CGFloat kFooterMaxH   = 400.0f;
/// The theme preview: a strip of wallpaper with two bubbles on it.
static const CGFloat kPreviewRow      = TGMetricSettingsPreviewRow;
static const CGFloat kPreviewBubbleW  = 176.0f;
static const CGFloat kPreviewBubbleH  = 34.0f;
static const CGFloat kPreviewInset    = TGMetricPadMedium + TGMetricPadTiny;
static const CGFloat kPreviewTop      = TGMetricPadLarge - TGMetricPadTiny;
static const CGFloat kPreviewGap      = TGMetricPad;
static const CGFloat kPreviewTextLeft = 9.0f;
static const CGFloat kPreviewStampRoom = 46.0f;
static const CGFloat kPreviewStampW   = 30.0f;
/// The account header: the picture, the name under it, the phone under that.
static const CGFloat kMeAvatarTop  = TGMetricPadLarge + TGMetricPadTiny;
static const CGFloat kMeNameTop    = TGMetricPadMedium;
static const CGFloat kMeNameLine   = TGMetricLineTitle + TGMetricPadTiny;
static const CGFloat kMeTextInset  = TGMetricPadMedium;

- (CGSize)footerTextSize:(NSString *)text {
	CGFloat width = self.tableView.bounds.size.width - TGDoubled(kFooterInset);
	return [text sizeWithFont:TGFontMeta()
			constrainedToSize:CGSizeMake(MAX(width, kFooterMinW), kFooterMaxH)
				lineBreakMode:NSLineBreakByWordWrapping];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (self.page == TGSettingsPageRoot && section == (NSInteger)self.sections.count - 1)
		return TGMetricSectionFooterRoot;
	NSString *text = self.sections[section][@"footer"];
	if (!text.length)
		return TGMetricSectionHeaderHidden;
	return [self footerTextSize:text].height + TGMetricSectionFooterGap;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
	NSDictionary *row = [self rowAt:path];
	NSString *kind = row[TGRowKind];
	if ([kind isEqualToString:TGKindProfile]) return TGMetricSettingsProfileRow;
	if ([kind isEqualToString:TGKindPreview]) return TGMetricSettingsPreviewRow;
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

	UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kPreviewRow)];
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
		CGFloat bubbleW = kPreviewBubbleW, bubbleH = kPreviewBubbleH;
		UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(
				mine ? width - bubbleW - kPreviewInset : kPreviewInset,
				kPreviewTop + i * (bubbleH + kPreviewGap),
				bubbleW, bubbleH)];
		bubble.backgroundColor = mine ? [theme bubbleMineColour]
									  : [theme bubbleTheirsColour];
		bubble.layer.cornerRadius = [theme bubbleCornerRadius];
		bubble.layer.borderWidth = [theme bubbleBorderWidth];
		bubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
		[canvas addSubview:bubble];

		UILabel *text = [[UILabel alloc] initWithFrame:
				CGRectMake(kPreviewTextLeft, 0, bubbleW - kPreviewStampRoom, bubbleH)];
		text.text = lines[i];
		text.font = TGFontAtSize(MIN(theme.messageFontSize, TGFontMessageBaseCap));
		text.textColor = [theme primaryTextColour];
		text.backgroundColor = [UIColor clearColor];
		text.adjustsFontSizeToFitWidth = YES;
		[bubble addSubview:text];

		UILabel *stamp = [[UILabel alloc] initWithFrame:
				CGRectMake(bubbleW - kPreviewStampW - TGMetricPad,
						bubbleH - TGMetricLineCaption, kPreviewStampW, TGMetricStampHeight)];
		stamp.text = @"9:41";
		stamp.font = TGFontMicro();
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
	cell.textLabel.font = TGFontRow();
	cell.textLabel.textAlignment = NSTextAlignmentLeft;
	cell.textLabel.textColor = [kind isEqualToString:TGKindDestructive]
			? [theme destructiveColour] : [theme primaryTextColour];
	cell.detailTextLabel.text = row[TGRowDetail];
	cell.detailTextLabel.font = subtitle ? TGFontCaption() : TGFontBody();
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
		UIViewController *profile = [[TGEditProfileViewController alloc] init];
		profile.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:profile animated:YES];
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
			CGRectMake(TGCenteredOrigin(width, side), kMeAvatarTop, side, side)];
	self.avatarView.layer.cornerRadius = TGHalf(side);
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
