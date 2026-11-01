//
// TGChatToolsViewController.m
//
#import "TGChatToolsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGListViewController.h"
#import "TGChatViewController.h"

/// One row: a title, the value it currently holds, and what a tap does.
static NSMutableDictionary *TGRow(NSString *title, NSString *detail,
								  void (^tap)(void)) {
	NSMutableDictionary *row = [@{@"title" : title ?: @""} mutableCopy];
	if (detail.length)
		row[@"detail"] = detail;
	if (tap)
		row[@"tap"] = [tap copy];
	return row;
}

static NSDictionary *TGSection(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

/// A colour as TDLib's RGB integer: 0xRRGGBB.
static NSInteger TGRGB(UIColor *colour) {
	CGFloat r = 0.5, g = 0.5, b = 0.5, a = 1;
	[colour getRed:&r green:&g blue:&b alpha:&a];
	return ((NSInteger)lround(r * 255) << 16) |
		   ((NSInteger)lround(g * 255) << 8) |
			(NSInteger)lround(b * 255);
}

/// A solid JPEG for the background request, which wants a file rather than a
/// colour. 64x64 is enough because the fill repeats.
static NSString *TGWriteBackground(UIColor *colour) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(TGMetricListAvatar, TGMetricListAvatar), YES, 1);
	[colour setFill];
	UIRectFill(CGRectMake(0, 0, TGMetricListAvatar, TGMetricListAvatar));
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	NSData *jpeg = UIImageJPEGRepresentation(image, 0.9);
	if (!jpeg.length)
		return nil;
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"tg-chat-background.jpg"];
	return [jpeg writeToFile:path atomically:YES] ? path : nil;
}

@interface TGChatToolsViewController ()
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSDictionary *chat;
@property (nonatomic, strong) NSDictionary *groupInfo;
@property (nonatomic, assign) BOOL protectedContent;
@property (nonatomic, assign) BOOL translatable;
@property (nonatomic, assign) BOOL defaultSilent;
@property (nonatomic, assign) BOOL reactionsAll;
@property (nonatomic, assign) NSInteger slowMode;
@property (nonatomic, assign) NSInteger accentId;
@property (nonatomic, assign) NSInteger profileAccentId;
@property (nonatomic, assign) int64_t discussionChatId;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, copy) NSString *themeName;
@end

@implementation TGChatToolsViewController

- (instancetype)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Chat Tools";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	[self rebuild];
	[self loadChat];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self.tableView reloadData];
}

- (void)applyTheme {
	[[TGTheme shared] styleGroupedTable:self.tableView];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - state

- (void)loadChat {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
		TGChatToolsViewController *me = weakSelf;
		if (!me || !chat)
			return;
		me.chat = chat;
		me.protectedContent = [chat[@"has_protected_content"] boolValue];
		me.translatable = [chat[@"is_translatable"] boolValue];
		me.defaultSilent = [chat[@"default_disable_notification"] boolValue];
		me.note = chat[@"client_data"] ?: @"";
		NSString *theme = chat[@"theme"][@"name"];
		me.themeName = theme.length ? theme : @"Default";
		me.accentId = [chat[@"accent_color_id"] integerValue];
		me.profileAccentId = [chat[@"profile_accent_color_id"] integerValue];
		NSString *kind = chat[@"available_reactions"][@"@type"];
		me.reactionsAll = kind.length
				? [kind isEqualToString:@"chatAvailableReactionsAll"] : YES;
		[me rebuild];
	}];

	[[TGClient shared] groupFullInfoForChat:self.chatId completion:^(NSDictionary *info){
		TGChatToolsViewController *me = weakSelf;
		if (!me || !info)
			return;
		me.groupInfo = info;
		me.slowMode = [info[@"slow_mode_delay"] integerValue];
		me.discussionChatId = [info[@"linked_chat_id"] longLongValue];
		[me rebuild];
	}];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;

	NSMutableArray *insights = [NSMutableArray array];
	[insights addObject:TGRow(@"Event Log", self.isGroup ? nil : @"Groups only",
			^{ [weakSelf showEventLog]; })];
	[insights addObject:TGRow(@"Statistics", self.isGroup ? nil : @"Groups only",
			^{ [weakSelf showStatistics]; })];
	[insights addObject:TGRow(@"Similar Chats", nil, ^{ [weakSelf showSimilarChats]; })];
	[insights addObject:TGRow(@"Recommended Chats", nil,
			^{ [weakSelf showRecommendedChats]; })];

	NSMutableArray *moderation = [NSMutableArray array];
	[moderation addObject:TGRow(@"Slow Mode",
			self.slowMode ? [NSString stringWithFormat:@"%ld s", (long)self.slowMode]
						  : @"Off", ^{ [weakSelf chooseSlowMode]; })];
	[moderation addObject:TGRow(@"Available Reactions",
			self.reactionsAll ? @"All" : @"Three emoji", ^{ [weakSelf chooseReactions]; })];
	[moderation addObject:TGRow(@"Protected Content",
			self.protectedContent ? @"On" : @"Off", ^{ [weakSelf toggleProtected]; })];
	[moderation addObject:TGRow(@"Translatable",
			self.translatable ? @"On" : @"Off", ^{ [weakSelf toggleTranslatable]; })];
	[moderation addObject:TGRow(@"Send Silently By Default",
			self.defaultSilent ? @"On" : @"Off", ^{ [weakSelf toggleDefaultSilent]; })];
	[moderation addObject:TGRow(@"Answer Protected-Content Request", nil,
			^{ [weakSelf answerProtectedRequest]; })];

	NSMutableArray *appearance = [NSMutableArray array];
	[appearance addObject:TGRow(@"Accent Colour",
			[NSString stringWithFormat:@"%ld", (long)self.accentId],
			^{ [weakSelf chooseAccent:NO]; })];
	[appearance addObject:TGRow(@"Profile Accent",
			[NSString stringWithFormat:@"%ld", (long)self.profileAccentId],
			^{ [weakSelf chooseAccent:YES]; })];
	[appearance addObject:TGRow(@"Chat Theme", self.themeName ?: @"Default",
			^{ [weakSelf chooseTheme]; })];
	[appearance addObject:TGRow(@"Chat Background", @"Set", ^{ [weakSelf chooseBackground]; })];
	[appearance addObject:TGRow(@"Reset Background", nil, ^{ [weakSelf resetBackground]; })];

	NSMutableArray *group = [NSMutableArray array];
	[group addObject:TGRow(@"Discussion Group",
			self.discussionChatId ? @"Linked" : @"None",
			^{ [weakSelf chooseDiscussionGroup]; })];
	[group addObject:TGRow(@"Location", nil, ^{ [weakSelf setLocation]; })];
	[group addObject:TGRow(@"Local Note", self.note.length ? self.note : @"None",
			^{ [weakSelf editNote]; })];
	[group addObject:TGRow(@"Owner After Leaving", nil,
			^{ [weakSelf showOwnerAfterLeaving]; })];

	NSMutableArray *media = [NSMutableArray array];
	[media addObject:TGRow(@"Message Positions", @"Jump by media kind",
			^{ [weakSelf choosePositions]; })];

	NSMutableArray *photo = [NSMutableArray array];
	[photo addObject:TGRow(@"Emoji Photo", nil, ^{ [weakSelf chooseEmojiPhoto]; })];
	[photo addObject:TGRow(@"Report Photo", nil, ^{ [weakSelf reportPhoto]; })];

	NSMutableArray *admin = [NSMutableArray array];
	[admin addObject:TGRow(@"Approve All Join Requests", nil,
			^{ [weakSelf processJoinRequests:YES]; })];
	[admin addObject:TGRow(@"Decline All Join Requests", nil,
			^{ [weakSelf processJoinRequests:NO]; })];
	[admin addObject:TGRow(@"Answer Join Request Query", nil,
			^{ [weakSelf answerJoinRequestQuery]; })];

	NSMutableArray *folders = [NSMutableArray array];
	[folders addObject:TGRow(@"Add to Chat List / Folder", nil,
			^{ [weakSelf addToChatList]; })];

	self.sections = @[
		TGSection(@"Insights", @"The event log covers the last 48 hours.", insights),
		TGSection(@"Moderation", nil, moderation),
		TGSection(@"Appearance", nil, appearance),
		TGSection(@"This Chat", nil, group),
		TGSection(@"Media", nil, media),
		TGSection(@"Photo", nil, photo),
		TGSection(@"Join Requests", nil, admin),
		TGSection(@"Chat Lists", nil, folders),
	];
	[self.tableView reloadData];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.sections[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return self.sections[section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = row[@"title"];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = row[@"detail"];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
	void (^tap)(void) = row[@"tap"];
	if (tap)
		tap();
}

#pragma mark - insights

- (void)showEventLog {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] eventLogForChat:self.chatId completion:^(NSArray *events){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *event in events){
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:
					[event[@"date"] doubleValue]];
			NSString *when = [NSDateFormatter localizedStringFromDate:date
					dateStyle:NSDateFormatterShortStyle
					timeStyle:NSDateFormatterShortStyle];
			[rows addObject:@{@"title" : event[@"actor"] ?: @"Someone",
							  @"detail" : [NSString stringWithFormat:@"%@ · %@",
									  event[@"text"] ?: @"", when]}];
		}
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Event Log";
		list.rows = rows;
		list.emptyText = @"No events in the last 48 hours, or this account is "
						 @"not an administrator.";
		list.offersCopy = YES;
		list.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:list animated:YES];
	}];
}

- (void)showStatistics {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatStatisticsForChat:self.chatId completion:^(NSArray *rows, NSString *kind){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Statistics";
		list.rows = rows;
		list.emptyText = kind.length
				? @"Telegram did not return a statistic for this chat."
				: @"Statistics are available only to administrators of a "
				  @"supergroup or channel.";
		list.listFooter = @"Figures are Telegram's; growth is measured against "
						  @"the previous day.";
		list.offersCopy = YES;
		list.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:list animated:YES];
	}];
}

- (void)showSimilarChats {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] similarChatsForChat:self.chatId completion:^(NSArray *chats, NSInteger total){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		if (!chats.count){
			[TGAlertSheet showMessage:@"Telegram knows no similar channels."
								title:@"Similar Chats" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *chat in chats){
			[rows addObject:@{@"title" : chat[@"title"] ?: @"Channel",
							  @"detail" : @"Open",
							  @"tap" : ^{
				[me openChat:chat];
			}}];
		}
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Similar Chats";
		list.rows = rows;
		list.listFooter = [NSString stringWithFormat:@"About %ld similar channels.",
						   (long)total];
		list.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:list animated:YES];
	}];
}

- (void)showRecommendedChats {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] recommendedChatsWithCompletion:^(NSArray *chats){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		if (!chats.count){
			[TGAlertSheet showMessage:@"Telegram has no recommendations right now."
								title:@"Recommended Chats" inView:me.view];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *chat in chats){
			[rows addObject:@{@"title" : chat[@"title"] ?: @"Channel",
							  @"detail" : @"Open",
							  @"tap" : ^{
				TGChatViewController *vc = [[TGChatViewController alloc] init];
				vc.chatId = [chat[@"id"] longLongValue];
				vc.chatTitle = chat[@"title"];
				vc.isGroup = YES;
				vc.hidesBottomBarWhenPushed = YES;
				[me.navigationController pushViewController:vc animated:YES];
			}}];
		}
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Recommended Chats";
		list.rows = rows;
		list.listFooter = @"Channels Telegram suggests to this account.";
		list.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:list animated:YES];
	}];
}

- (void)openChat:(NSDictionary *)chat {
	int64_t chatId = [chat[@"id"] longLongValue];
	if (!chatId)
		return;
	[[TGClient shared] openSimilarChat:chatId fromChat:self.chatId];
	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = chatId;
	vc.chatTitle = chat[@"title"];
	vc.isGroup = YES;
	vc.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)choosePositions {
	__weak typeof(self) weakSelf = self;
	NSArray *kinds = @[@"Photos", @"Videos", @"Files", @"Links"];
	[TGAlertSheet showChoices:kinds title:@"Message Positions"
			destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		static NSString *filters[] = {@"photo", @"video", @"file", @"link"};
		[weakSelf loadPositions: filters[index]];
	}];
}

- (void)loadPositions:(NSString *)filter {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] sparsePositionsInChat:self.chatId filter:filter fromMessage:0
			completion:^(NSInteger total, NSArray *positions){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *entry in positions){
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:
					[entry[@"date"] doubleValue]];
			NSString *when = [NSDateFormatter localizedStringFromDate:date
					dateStyle:NSDateFormatterShortStyle
					timeStyle:NSDateFormatterShortStyle];
			[rows addObject:@{
				@"title" : [NSString stringWithFormat:@"Position %@",
						entry[@"position"] ?: @(0)],
				@"detail" : when,
				@"tap" : ^{ [me openPosition:entry filter:filter]; },
			}];
		}
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Message Positions";
		list.rows = rows;
		list.emptyText = @"There is nothing of that kind in this chat yet.";
		list.listFooter = [NSString stringWithFormat:@"%ld messages of this kind.",
						   (long)total];
		list.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:list animated:YES];
	}];
}

- (void)openPosition:(NSDictionary *)entry filter:(NSString *)filter {
	int64_t messageId = [entry[@"messageId"] longLongValue];
	if (!messageId)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] messagePosition:messageId inChat:self.chatId filter:filter
			completion:^(NSInteger position, NSInteger total){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		(void)total;
		NSString *say = [NSString stringWithFormat:@"Position %ld in this "
				@"chat. Opening it now.", (long)position];
		[TGAlertSheet showMessage:say title:@"Message Position" inView:me.view];
		TGChatViewController *vc = [[TGChatViewController alloc] init];
		vc.chatId = me.chatId;
		vc.chatTitle = me.chatTitle;
		vc.isGroup = me.isGroup;
		vc.initialMessageId = messageId;
		vc.hidesBottomBarWhenPushed = YES;
		[me.navigationController pushViewController:vc animated:YES];
	}];
}

#pragma mark - moderation

- (void)chooseSlowMode {
	NSArray *titles = @[@"Off", @"5 seconds", @"10 seconds", @"30 seconds",
						@"1 minute", @"5 minutes", @"15 minutes", @"1 hour"];
	static const NSInteger seconds[] = {0, 5, 10, 30, 60, 300, 900, 3600};
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Slow Mode" destructiveIndex:-1
			inView:self.view onChoice:^(NSInteger index){
		[[TGClient shared] setSlowModeDelayForChat:weakSelf.chatId
				seconds:seconds[index] completion:^(BOOL ok){
			TGChatToolsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Telegram refused that delay."
									title:@"Slow Mode" inView:me.view];
				return;
			}
			me.slowMode = seconds[index];
			[me rebuild];
		}];
	}];
}

- (void)chooseReactions {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"All reactions", @"Only 👍 ❤️ 🔥"]
						title:@"Available Reactions"
			 destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		NSString *mode = index == 0 ? @"all" : @"some";
		[[TGClient shared] setAvailableReactionsForChat:weakSelf.chatId
				mode:mode completion:^(BOOL ok){
			TGChatToolsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Telegram refused that reaction set."
									title:@"Reactions" inView:me.view];
				return;
			}
			me.reactionsAll = (index == 0);
			[me rebuild];
		}];
	}];
}

- (void)toggleProtected {
	__weak typeof(self) weakSelf = self;
	BOOL next = !self.protectedContent;
	[[TGClient shared] toggleProtectedContentForChat:self.chatId on:next
			completion:^(BOOL ok){
		TGChatToolsViewController *me = weakSelf;
		if (!ok){
			[TGAlertSheet showMessage:@"Only the owner can change this, and "
									  @"Telegram Premium is needed in a private chat."
								title:@"Protected Content" inView:me.view];
			return;
		}
		me.protectedContent = next;
		[me rebuild];
	}];
}

- (void)toggleTranslatable {
	self.translatable = !self.translatable;
	[[TGClient shared] toggleTranslatableForChat:self.chatId on:self.translatable];
	[self rebuild];
}

- (void)toggleDefaultSilent {
	self.defaultSilent = !self.defaultSilent;
	[[TGClient shared] toggleDefaultSilentForChat:self.chatId on:self.defaultSilent];
	[self rebuild];
}

- (void)answerProtectedRequest {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Protected-Content Request"
					message:@"The message id is on the request in the chat."
				placeholder:@"Request message id" text:nil action:@"Next"
					 inView:self.view onSubmit:^(NSString *text){
		int64_t messageId = text.longLongValue;
		if (!messageId)
			return;
		[TGAlertSheet showChoices:@[@"Approve", @"Reject"]
							title:@"Protected-Content Request"
				 destructiveIndex:1 inView:weakSelf.view onChoice:^(NSInteger index){
			[[TGClient shared] processProtectedContentDisableRequestInChat:weakSelf.chatId
					messageId:messageId approve:(index == 0) completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"The request was answered."
											   : @"Telegram refused that request.")
									title:@"Protected Content" inView:weakSelf.view];
			}];
		}];
	}];
}

#pragma mark - appearance

- (void)chooseAccent:(BOOL)profile {
	NSArray *titles = @[@"0", @"1", @"2", @"3", @"4", @"5", @"6"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles
						title:(profile ? @"Profile Accent" : @"Accent Colour")
			 destructiveIndex:-1 inView:self.view onChoice:^(NSInteger index){
		if (profile){
			[[TGClient shared] setChatProfileAccentColour:weakSelf.chatId colourId:index];
			weakSelf.profileAccentId = index;
		} else {
			[[TGClient shared] setChatAccentColour:weakSelf.chatId colourId:index];
			weakSelf.accentId = index;
		}
		[weakSelf rebuild];
	}];
}

- (void)chooseTheme {
	NSArray *themes = @[@"Default", @"❤️", @"🔥", @"🎉", @"🌊", @"🍀", @"🌙"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:themes title:@"Chat Theme" destructiveIndex:-1
			inView:self.view onChoice:^(NSInteger index){
		NSString *name = index == 0 ? @"" : themes[index];
		[[TGClient shared] setChatTheme:weakSelf.chatId name:name completion:^(BOOL ok){
			TGChatToolsViewController *me = weakSelf;
			if (!ok){
				[TGAlertSheet showMessage:@"Telegram does not know that theme."
									title:@"Chat Theme" inView:me.view];
				return;
			}
			me.themeName = index == 0 ? @"Default" : themes[index];
			[me rebuild];
		}];
	}];
}

- (void)chooseBackground {
	NSArray *titles = @[@"Accent", @"Secondary", @"Destructive", @"Grouped"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Chat Background" destructiveIndex:-1
			inView:self.view onChoice:^(NSInteger index){
		UIColor *colour = [[TGTheme shared] accentColour];
		if (index == 1)
			colour = [[TGTheme shared] secondaryTextColour];
		else if (index == 2)
			colour = [[TGTheme shared] destructiveColour];
		else if (index == 3)
			colour = [[TGTheme shared] groupedBackgroundColour];
		NSString *path = TGWriteBackground(colour);
		if (!path){
			[TGAlertSheet showMessage:@"The background image could not be written."
								title:@"Chat Background" inView:weakSelf.view];
			return;
		}
		[[TGClient shared] setChatBackground:weakSelf.chatId imagePath:path
				colour:TGRGB(colour) onlyForSelf:!weakSelf.isGroup
				completion:^(BOOL ok){
			[TGAlertSheet showMessage:(ok ? @"Background set for this chat."
										   : @"Telegram refused the background.")
								title:@"Chat Background" inView:weakSelf.view];
		}];
	}];
}

- (void)resetBackground {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The chat goes back to the default background."
						title:@"Reset Background" action:@"Reset"
				  destructive:YES inView:self.view onConfirm:^{
		[[TGClient shared] deleteChatBackground:weakSelf.chatId restorePrevious:YES];
	}];
}

#pragma mark - this chat

- (void)chooseDiscussionGroup {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] suitableDiscussionChatsWithCompletion:^(NSArray *chats){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *titles = [NSMutableArray arrayWithObject:@"None"];
		NSMutableArray *all = [NSMutableArray arrayWithObject:@{}];
		for (NSDictionary *chat in chats){
			[titles addObject:chat[@"title"] ?: @"Group"];
			[all addObject:chat];
		}
		[TGAlertSheet showChoices:titles title:@"Discussion Group"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			NSDictionary *chat = all[index];
			int64_t discussionId = [chat[@"id"] longLongValue];
			[[TGClient shared] setDiscussionGroup:discussionId forChat:weakSelf.chatId
					completion:^(BOOL ok){
				if (ok){
					weakSelf.discussionChatId = discussionId;
					[weakSelf rebuild];
				}
				[TGAlertSheet showMessage:(ok ? @"Discussion group updated."
											   : @"Telegram refused that group.")
									title:@"Discussion Group" inView:weakSelf.view];
			}];
		}];
	}];
}

- (void)setLocation {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Location" message:nil placeholder:@"Address"
					   text:nil action:@"Save" inView:self.view
				   onSubmit:^(NSString *address){
		[[TGClient shared] setLocationAddress:address forChat:weakSelf.chatId
				completion:^(BOOL ok){
			[TGAlertSheet showMessage:(ok ? @"Location saved."
										   : @"Only a location-based supergroup "
											 @"takes one, and only an administrator.")
								title:@"Location" inView:weakSelf.view];
		}];
	}];
}

- (void)editNote {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Local Note"
					message:@"Kept in this chat's application data, on Telegram's side."
				placeholder:@"A note only this app sees"
					   text:self.note action:@"Save" inView:self.view
				 onSubmit:^(NSString *note){
		[[TGClient shared] setClientNote:note forChat:weakSelf.chatId
				completion:^(BOOL ok){
			if (!ok)
				return;
			weakSelf.note = note;
			[weakSelf rebuild];
		}];
	}];
}

- (void)showOwnerAfterLeaving {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] ownerAfterLeavingChat:self.chatId completion:^(NSDictionary *user){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		NSString *say = user[@"name"]
				? [NSString stringWithFormat:@"%@ becomes owner if this account "
						@"stays away for seven days.", user[@"name"]]
				: @"Only the owner can see who takes over after they leave.";
		[TGAlertSheet showMessage:say title:@"Owner After Leaving" inView:me.view];
	}];
}

#pragma mark - photo

- (void)chooseEmojiPhoto {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] defaultChatPhotoEmojiStickersWithCompletion:^(NSArray *stickers){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		if (!stickers.count){
			[TGAlertSheet showMessage:@"Telegram returned no emoji photos."
								title:@"Emoji Photo" inView:me.view];
			return;
		}
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *sticker in stickers)
			[titles addObject:sticker[@"emoji"] ?: @"🙂"];
		[TGAlertSheet showChoices:titles title:@"Emoji Photo"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			NSDictionary *sticker = stickers[index];
			UIColor *colour = [[TGTheme shared] accentColour];
			[[TGClient shared] setEmojiPhotoForChat:weakSelf.chatId
					customEmojiId:[sticker[@"customEmojiId"] longLongValue]
					colour:TGRGB(colour) completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"The emoji photo is set."
											   : @"Telegram refused that photo.")
									title:@"Emoji Photo" inView:weakSelf.view];
			}];
		}];
	}];
}

- (void)reportPhoto {
	NSArray *titles = @[@"Spam", @"Violence", @"Pornography", @"Child abuse",
						@"Copyright", @"Wrong location", @"Fake", @"Other"];
	NSArray *reasons = @[@"spam", @"violence", @"pornography", @"childAbuse",
						 @"copyright", @"location", @"fake", @"custom"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Report Photo" destructiveIndex:0
			inView:self.view onChoice:^(NSInteger index){
		[TGAlertSheet showConfirm:[NSString stringWithFormat:
						@"Report this chat's photo as %@?", titles[index]]
							title:@"Report Photo" action:@"Report"
					  destructive:YES inView:weakSelf.view onConfirm:^{
			[[TGClient shared] reportChatPhotoInChat:weakSelf.chatId
					reason:reasons[index] detail:@""
					completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"Reported. Thank you."
											   : @"Telegram refused the report, "
												 @"or this chat has no photo.")
									title:@"Report Photo" inView:weakSelf.view];
			}];
		}];
	}];
}

#pragma mark - join requests and folders

- (void)processJoinRequests:(BOOL)approve {
	__weak typeof(self) weakSelf = self;
	NSString *action = approve ? @"Approve All" : @"Decline All";
	[TGAlertSheet showConfirm:[NSString stringWithFormat:
					@"%@ pending requests at every link of this chat.", action]
						title:@"Join Requests" action:action
				  destructive:!approve inView:self.view onConfirm:^{
		[[TGClient shared] processAllJoinRequests:weakSelf.chatId link:@""
				approve:approve completion:^(BOOL ok){
			[TGAlertSheet showMessage:(ok ? @"The requests were answered."
										   : @"Telegram refused the batch.")
								title:@"Join Requests" inView:weakSelf.view];
		}];
	}];
}

- (void)answerJoinRequestQuery {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Join Request Query"
					message:@"Query ids arrive with a guard bot's request."
				placeholder:@"Query id" text:nil action:@"Next"
					 inView:self.view onSubmit:^(NSString *text){
		int64_t queryId = text.longLongValue;
		if (!queryId)
			return;
		[TGAlertSheet showChoices:@[@"Approve", @"Decline", @"Queue"]
							title:@"Answer Query" destructiveIndex:1
						   inView:weakSelf.view onChoice:^(NSInteger index){
			if (index == 2){
				[TGAlertSheet showMessage:@"A queue answer is sent by the guard "
										  @"bot, not by this client."
									title:@"Join Request" inView:weakSelf.view];
				return;
			}
			[[TGClient shared] answerJoinRequestQuery:queryId approve:(index == 0)
					completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"The query was answered."
											   : @"Telegram refused the answer.")
									title:@"Join Request" inView:weakSelf.view];
			}];
		}];
	}];
}

- (void)addToChatList {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatListsForChat:self.chatId completion:^(NSArray *lists){
		TGChatToolsViewController *me = weakSelf;
		if (!me)
			return;
		if (!lists.count){
			[TGAlertSheet showMessage:@"Telegram named no lists for this chat."
								title:@"Add to Folder" inView:me.view];
			return;
		}
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *list in lists){
			NSString *kind = list[@"@type"] ?: @"";
			if ([kind isEqualToString:@"chatListMain"])
				[titles addObject:@"All Chats"];
			else if ([kind isEqualToString:@"chatListArchive"])
				[titles addObject:@"Archive"];
			else if ([kind isEqualToString:@"chatListFolder"]){
				NSInteger folderId = [list[@"chat_folder_id"] integerValue];
				NSString *name = nil;
				for (NSDictionary *folder in [TGClient shared].folders)
					if ([folder[@"id"] integerValue] == folderId)
						name = folder[@"title"];
				[titles addObject:name.length ? name
						: [NSString stringWithFormat:@"Folder %ld", (long)folderId]];
			} else {
				[titles addObject:@"List"];
			}
		}
		[TGAlertSheet showChoices:titles title:@"Add to Chat List"
				destructiveIndex:-1 inView:me.view onChoice:^(NSInteger index){
			[[TGClient shared] addChat:weakSelf.chatId toList:lists[index]
					completion:^(BOOL ok){
				[TGAlertSheet showMessage:(ok ? @"Added."
											   : @"Telegram refused that list.")
									title:@"Add to Folder" inView:weakSelf.view];
			}];
		}];
	}];
}

@end
