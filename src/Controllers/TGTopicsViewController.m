#import "TGTopicsViewController.h"
#import "TGAlertSheet.h"
#import "TGChatViewController.h"
#import "TGClient.h"
#import "TGEmptyView.h"
#import "TGFastDate.h"
#import "TGIcons.h"
#import "TGListViewController.h"
#import "TGBadge.h"
#import "TGTheme.h"
#import "TGStyle.h"

/// A topic row is a chat row in miniature: a coloured icon made from the
/// topic's own id, the name, the last message, the time and the unread count.
/// The stock subtitle cell could not carry the icon and the badge without
/// the two fighting for the same 40 pt.
static NSString *TGTopicDateText(NSNumber *stamp) {
	if (![stamp isKindOfClass:NSNumber.class] || ![stamp longLongValue])
		return @"";
	char buf[TGFastDateBufferSize + 1] = {0};
	size_t len = TGFastChatDate((time_t)[stamp doubleValue],
			(time_t)[[NSDate date] timeIntervalSince1970], buf,
			TGFastDateBufferSize);
	return len ? [[NSString alloc] initWithBytes:buf length:len
									   encoding:NSUTF8StringEncoding] : @"";
}

@interface TGTopicCell : UITableViewCell
- (void)applyTopic:(NSDictionary *)topic;
@end

@implementation TGTopicCell {
	UIImageView *_iconView;
	UILabel *_titleLabel;
	UILabel *_previewLabel;
	UILabel *_dateLabel;
	UIImageView *_pinView;
	TGBadge *_badge;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;
	_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_iconView.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:_iconView];

	_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_titleLabel.font = TGFontRowStrong();
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:_titleLabel];

	_previewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_previewLabel.font = TGFontCaption();
	_previewLabel.backgroundColor = [UIColor clearColor];
	_previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:_previewLabel];

	_dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_dateLabel.font = TGFontCaption();
	_dateLabel.textAlignment = NSTextAlignmentRight;
	_dateLabel.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:_dateLabel];

	_pinView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_pinView.contentMode = UIViewContentModeScaleAspectFit;
	[self.contentView addSubview:_pinView];

	_badge = [TGBadge badgeWithCount:0];
	[self.contentView addSubview:_badge];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.contentView.bounds;
	CGFloat iconSide = TGMetricTopicIcon;

	_iconView.frame = CGRectMake(TGMetricPad,
			TGCenteredOrigin(b.size.height, iconSide), iconSide, iconSide);

	CGFloat dateWidth = TGMetricCallLabelWidth;
	CGFloat right = b.size.width - TGMetricGutter;
	_dateLabel.frame = CGRectMake(right - dateWidth, TGMetricPad,
			dateWidth, TGMetricLineCaption);
	CGSize badgeSize = [_badge sizeThatFits:CGSizeZero];
	_badge.frame = CGRectMake(right - badgeSize.width,
			TGMetricPad + TGMetricLineCaption + TGMetricPadTiny,
			badgeSize.width, badgeSize.height);

	CGFloat x = TGMetricPad + iconSide + TGMetricPadMedium;
	CGFloat maxX = right - dateWidth - TGMetricPad;
	CGFloat titleX = x;
	if (!_pinView.hidden) {
		_pinView.frame = CGRectMake(x, TGMetricPad + TGMetricPadTiny,
				TGMetricLineCaption, TGMetricLineCaption);
		titleX = CGRectGetMaxX(_pinView.frame) + TGMetricPadSmall;
	}
	_titleLabel.frame = CGRectMake(titleX, TGMetricPad,
			MAX(0, maxX - titleX), TGMetricLineRow);
	_previewLabel.frame = CGRectMake(x, TGMetricPad + TGMetricLineRow + TGMetricPadTiny,
			MAX(0, maxX - x), TGMetricLineCaption);
}

- (void)applyTopic:(NSDictionary *)topic {
	TGTheme *theme = [TGTheme shared];
	NSString *name = topic[@"name"] ?: @"Topic";
	NSString *initials = [TGIcons initialsForTitle:name];
	if (!initials.length)
		initials = [topic[@"general"] boolValue] ? @"G" : @"?";
	_iconView.image = [TGIcons avatarWithInitials:initials
			size:TGMetricTopicIcon
			colourId:[topic[@"threadId"] longLongValue]];
	_iconView.layer.cornerRadius = TGHalf(TGMetricTopicIcon);
	_iconView.clipsToBounds = YES;

	_titleLabel.text = name;
	_titleLabel.textColor = [theme primaryTextColour];
	_dateLabel.text = TGTopicDateText(topic[@"date"]);
	_dateLabel.textColor = [theme listDateColour];

	NSMutableArray *marks = [NSMutableArray array];
	NSInteger mentions = [topic[@"unreadMentions"] integerValue];
	NSInteger polls = [topic[@"unreadPollVotes"] integerValue];
	NSInteger reactions = [topic[@"unreadReactions"] integerValue];
	if (mentions > 0)
		[marks addObject:[NSString stringWithFormat:@"@ %ld", (long)mentions]];
	if (polls > 0)
		[marks addObject:[NSString stringWithFormat:@"%ld poll vote%@",
				(long)polls, polls == 1 ? @"" : @"s"]];
	if (reactions > 0)
		[marks addObject:[NSString stringWithFormat:@"%ld reaction%@",
				(long)reactions, reactions == 1 ? @"" : @"s"]];

	NSString *preview = topic[@"text"] ?: @"";
	if ([topic[@"closed"] boolValue])
		preview = preview.length
				? [NSString stringWithFormat:@"Closed · %@", preview]
				: @"Closed";
	if (marks.count) {
		NSString *line = [marks componentsJoinedByString:@" · "];
		preview = preview.length
				? [NSString stringWithFormat:@"%@ · %@", line, preview] : line;
	}
	_previewLabel.text = preview.length ? preview : @"No messages yet";
	_previewLabel.textColor = [theme secondaryTextColour];

	_pinView.hidden = ![topic[@"pinned"] boolValue];
	_pinView.image = [TGIcons glyphNamed:@"pin"
								  colour:[theme secondaryTextColour]
									side:TGMetricLineCaption];

	NSInteger unread = [topic[@"unread"] integerValue];
	NSDictionary *settings = topic[@"notificationSettings"];
	BOOL muted = [settings isKindOfClass:NSDictionary.class] &&
			![settings[@"use_default_mute_for"] boolValue] &&
			[settings[@"mute_for"] integerValue] > 0;
	_badge.variant = muted ? TGBadgeVariantMuted : TGBadgeVariantNotification;
	_badge.count = unread;
	_badge.hidden = unread <= 0;

	self.backgroundColor = [theme listBackgroundColour];
	self.contentView.backgroundColor = [theme listBackgroundColour];
	[self setNeedsLayout];
}

@end

@interface TGTopicsViewController ()
@property (nonatomic, strong) NSArray *topics;
@property (nonatomic, strong) TGEmptyView *emptyView;
@property (nonatomic, assign) BOOL loaded;

- (void)plusTapped;
- (void)createTopicTapped;
- (void)showTopicInfoForTopic:(NSDictionary *)topic;
- (void)loadTopicInfoForList:(TGListViewController *)list thread:(int64_t)threadId;
- (void)showTopicNotificationSettingsForTopic:(NSDictionary *)info
									   reload:(void (^)(void))reload;
- (void)showPinnedTopicsManager;
- (void)loadPinnedTopicsIntoList:(TGListViewController *)list;
- (void)setGeneralTopicHidden:(BOOL)hidden;
- (NSDictionary *)generalTopic;
- (void)openTopic:(NSDictionary *)topic;
- (void)markTopicRead:(NSDictionary *)topic;
- (void)markTopicBadgeRead:(int64_t)threadId key:(NSString *)key;
- (void)changePinnedTopic:(NSDictionary *)topic
				   choice:(NSInteger)choice
				  pinnings:(NSArray *)topics
			   completion:(void (^)(void))completion;
- (void)showRefusal:(NSString *)error title:(NSString *)title;
- (void)updateEmptyView;
- (void)refreshPulled;
@end

@implementation TGTopicsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.title = self.chatTitle ?: @"Topics";
	self.topics = @[];
	self.tableView.rowHeight = TGMetricTopicRow;
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	[self applyTheme];

	UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
	[refresh addTarget:self action:@selector(refreshPulled)
	  forControlEvents:UIControlEventValueChanged];
	self.refreshControl = refresh;

	// Making a topic is the one thing the list needs beyond its rows; the
	// plus sits where a mail folder's compose sits.
	__weak typeof(self) weakSelf = self;
	UIBarButtonItem *plus = [[UIBarButtonItem alloc] initWithTitle:@"+"
			style:UIBarButtonItemStylePlain
			target:self action:@selector(plusTapped)];
	self.navigationItem.rightBarButtonItem = plus;

	// A topic's lot holds in the row, and rows are not controls: the hold
	// reaches what a tap cannot.
	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(topicHeld:)];
	hold.minimumPressDuration = 0.55;
	[self.tableView addGestureRecognizer:hold];

	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.topics = topics;
		me.loaded = YES;
		[me.refreshControl endRefreshing];
		[me updateEmptyView];
		[me.tableView reloadData];
		NSLog(@"TDLIB TOPICS: %lu", (unsigned long)topics.count);
	}];

	// Created, renamed, pinned or read elsewhere: the list is one request and
	// this screen used to show whatever it fetched when it opened.
	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(topicsChanged:)
				name:TGForumTopicsChangedNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		weakSelf.emptyView = nil;
		weakSelf.tableView.backgroundView = nil;
		[weakSelf updateEmptyView];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

/// One update per topic touched, so a reopened forum would otherwise fetch
/// the list once per row. An update that names no chat is taken as ours.
- (void)topicsChanged:(NSNotification *)note {
	NSNumber *chatId = note.userInfo[@"chatId"];
	if (chatId && [chatId longLongValue] != self.chatId)
		return;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(reloadTopics) object:nil];
	[self performSelector:@selector(reloadTopics) withObject:nil afterDelay:0.3];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self reloadTopics];
}

- (void)refreshPulled {
	[self reloadTopics];
}

- (void)reloadTopics {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		me.topics = topics;
		me.loaded = YES;
		[me.refreshControl endRefreshing];
		[me updateEmptyView];
		[me.tableView reloadData];
	}];
}

/// A forum with no topics is a real state, not a broken list: say what to do
/// and put the same New Topic action the plus runs under it.
- (void)updateEmptyView {
	if (!self.loaded || self.topics.count) {
		self.tableView.backgroundView = nil;
		self.emptyView = nil;
		return;
	}
	if (!self.emptyView) {
		self.emptyView = [TGEmptyView emptyViewWithFrame:self.tableView.bounds
				image:[TGIcons emptyChatsIllustration]
				title:@"No topics yet"
				subtitle:@"Create a topic to keep this group's discussions apart."
				buttonTitle:@"New Topic"
				target:self
				action:@selector(createTopicTapped)];
	}
	self.tableView.backgroundView = self.emptyView;
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

/// The plus is the topics menu: a new topic, and the General topic's one
/// switch. Hiding General is server state that also closes it, so the row
/// names the direction it will take rather than a bare switch.
- (void)plusTapped {
	NSDictionary *general = [self generalTopic];
	// A hidden General topic is not in getForumTopics at all, so "no General
	// row" means the only useful direction is to bring it back.
	BOOL hidden = general ? [general[@"hidden"] boolValue] : YES;
	NSString *generalTitle = hidden
			? @"Show General Topic" : @"Hide General Topic";
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"New Topic", generalTitle]
						title:@"Topics"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index == 0)
			[weakSelf createTopicTapped];
		else
			[weakSelf setGeneralTopicHidden:!hidden];
	}];
}

- (NSDictionary *)generalTopic {
	for (NSDictionary *topic in self.topics)
		if ([topic[@"general"] boolValue])
			return topic;
	return nil;
}

- (void)setGeneralTopicHidden:(BOOL)hidden {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] toggleGeneralForumTopicHidden:hidden
											  inChat:self.chatId
										  completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf showRefusal:(error ?: @"Telegram refused that.")
							title:@"General Topic"];
			return;
		}
		[weakSelf reloadTopics];
	}];
}

- (void)showRefusal:(NSString *)error title:(NSString *)title {
	[TGAlertSheet showMessage:(error ?: @"Telegram refused that.")
						title:title inView:self.view];
}

/// A topic made: the name asked for, one of TDLib's six forum hues, then an
/// optional emoji from the set any account may use. The general topic TDLib
/// makes itself; this only makes named ones.
- (void)createTopicTapped {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"New Topic"
					message:nil
				placeholder:@"Topic name"
					   text:nil
					 action:@"Next"
					 inView:self.view
				   onSubmit:^(NSString *name){
		NSString *what = [name stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!what.length)
			return;
		// The order matches TGForumTopicColour in the client; the server
		// accepts these six values and nothing else.
		[TGAlertSheet showChoices:@[@"Blue", @"Orange", @"Violet", @"Green",
									@"Pink", @"Red"]
							title:@"Icon colour"
				  destructiveIndex:-1
						   inView:weakSelf.view
						 onChoice:^(NSInteger colour){
			[weakSelf chooseTopicIconWithCompletion:^(int64_t emojiId){
				[[TGClient shared] createForumTopicInChat:weakSelf.chatId
													 name:what
											   iconColour:colour
											  iconEmojiId:emojiId
											   completion:^(int64_t threadId, NSString *made){
					if (!threadId){
						[TGAlertSheet showMessage:@"Only a forum supergroup holds "
												  @"topics, and only an "
												  @"administrator makes one."
											title:@"New Topic" inView:weakSelf.view];
						return;
					}
					[weakSelf reloadTopics];
				}];
			}];
		}];
	}];
}

/// The default set is everything TDLib lets a non-Premium account use, so a
/// picker built from it cannot ask for an icon the server will refuse. The
/// first row is a real answer: 0 keeps the colour and drops the emoji.
- (void)chooseTopicIconWithCompletion:(void (^)(int64_t emojiId))completion {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] forumTopicDefaultIconsWithCompletion:^(NSArray *icons){
		TGTopicsViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *titles = [NSMutableArray arrayWithObject:@"No icon"];
		for (NSDictionary *icon in icons)
			[titles addObject:icon[@"emoji"] ?: @"?"];
		[TGAlertSheet showChoices:titles
							title:@"Topic icon"
				  destructiveIndex:-1
						   inView:me.view
						 onChoice:^(NSInteger index){
			int64_t emojiId = index > 0
				? [icons[index - 1][@"id"] longLongValue] : 0;
			if (completion)
				completion(emojiId);
		}];
	}];
}

/// The hold lands wherever the finger is, so the row is found from the
/// point; a miss does nothing rather than guessing the last row.
- (void)topicHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	CGPoint where = [hold locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:where];
	if (!path || path.row >= (NSInteger)self.topics.count)
		return;

	NSDictionary *t = self.topics[path.row];
	int64_t threadId = [t[@"threadId"] longLongValue];
	NSString *name = t[@"name"] ?: @"";
	if (!threadId)
		return;

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Topic Info", @"Rename", @"Icon", @"Pin", @"Close",
								@"Manage Pinned Topics", @"Delete"]
						title:name
			  destructiveIndex:6
					   inView:self.view
					 onChoice:^(NSInteger index){
		void (^refresh)(void) = ^{
			[weakSelf reloadTopics];
		};
		if (index == 0)
			[weakSelf showTopicInfoForTopic:t];
		else if (index == 1)
			[weakSelf renameTopic:threadId name:name];
		else if (index == 2)
			[weakSelf changeIconOfTopic:threadId];
		else if (index == 3){
			[[TGClient shared] toggleForumTopic:threadId
										 inChat:weakSelf.chatId
										 pinned:![t[@"pinned"] boolValue]];
			refresh();
		}
		else if (index == 4){
			[[TGClient shared] toggleForumTopic:threadId
										 inChat:weakSelf.chatId
										 closed:![t[@"closed"] boolValue]];
			refresh();
		}
		else if (index == 5)
			[weakSelf showPinnedTopicsManager];
		else
			[TGAlertSheet showConfirm:@"The topic and every message in it is "
									  @"removed, for everyone."
								title:name
							   action:@"Delete"
						  destructive:YES
							   inView:self.view
							onConfirm:^{
				[[TGClient shared] deleteForumTopic:threadId inChat:weakSelf.chatId];
				refresh();
			}];
	}];
}

/// Changing only the icon; the rename sheet owns the name. TDLib keeps the
/// General topic's icon to itself, so the refusal message says so.
- (void)changeIconOfTopic:(int64_t)threadId {
	__weak typeof(self) weakSelf = self;
	[self chooseTopicIconWithCompletion:^(int64_t emojiId){
		[[TGClient shared] setForumTopicIcon:emojiId
								   threadId:threadId
									 inChat:weakSelf.chatId
								 completion:^(BOOL ok){
			TGTopicsViewController *me = weakSelf;
			if (!me)
				return;
			if (ok)
				[me reloadTopics];
			else
				[TGAlertSheet showMessage:@"Telegram refused the icon. Only "
										  @"an administrator or the topic's "
										  @"maker changes one, and the "
										  @"General topic keeps its own."
									title:@"Topic icon" inView:me.view];
		}];
	}];
}

/// The rename asked for; the sheet is where a topic gets the words.
- (void)renameTopic:(int64_t)threadId name:(NSString *)old {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Rename Topic"
					message:nil
				placeholder:old ?: @"Topic name"
					   text:old
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *name){
		NSString *what = [name stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!what.length)
			return;
		[[TGClient shared] renameForumTopic:threadId
									 inChat:weakSelf.chatId
									   name:what
							   iconEmojiId:0
								completion:^(BOOL ok){
			TGTopicsViewController *me = weakSelf;
			if (ok)
				[me reloadTopics];
			else
				[TGAlertSheet showMessage:@"Telegram refused the rename. Only "
										  @"an administrator or the topic's "
										  @"maker renames one."
									title:@"Rename" inView:me.view];
		}];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGTopicCell";
	TGTopicCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGTopicCell alloc] initWithStyle:UITableViewCellStyleDefault
								  reuseIdentifier:reuse];
	[cell applyTopic:self.topics[indexPath.row]];
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.topics.count)
		return;
	[self openTopic:self.topics[indexPath.row]];
}

/// Opening a topic is reading it. The message list makes the unread count
/// fall on the server; mentions, poll votes and reactions are three separate
/// badges, so each has its own read call and its own local clear.
- (void)markTopicRead:(NSDictionary *)topic {
	int64_t threadId = [topic[@"threadId"] longLongValue];
	if (!threadId)
		return;
	BOOL hadBadge = [topic[@"unreadMentions"] integerValue] > 0 ||
					[topic[@"unreadPollVotes"] integerValue] > 0 ||
					[topic[@"unreadReactions"] integerValue] > 0;
	if (hadBadge){
		NSMutableArray *rows = [NSMutableArray arrayWithArray:self.topics];
		for (NSUInteger i = 0; i < rows.count; i++){
			NSDictionary *row = rows[i];
			if ([row[@"threadId"] longLongValue] != threadId)
				continue;
			NSMutableDictionary *next = [row mutableCopy];
			next[@"unreadMentions"] = @(0);
			next[@"unreadPollVotes"] = @(0);
			next[@"unreadReactions"] = @(0);
			rows[i] = next;
			break;
		}
		self.topics = rows;
		[self.tableView reloadData];
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] readAllForumTopicMentionsInChat:self.chatId
												 topic:threadId
											completion:^(BOOL ok, NSString *error){
		if (!ok)
			[weakSelf showRefusal:(error ?: @"Telegram refused to clear mentions.")
							title:@"Mentions"];
	}];
	[[TGClient shared] readAllForumTopicPollVotesInChat:self.chatId
												  topic:threadId
											 completion:^(BOOL ok, NSString *error){
		if (!ok)
			[weakSelf showRefusal:(error ?: @"Telegram refused to clear poll votes.")
							title:@"Poll Votes"];
	}];
	[[TGClient shared] readAllForumTopicReactionsInChat:self.chatId
												  topic:threadId
											 completion:^(BOOL ok){
		if (!ok)
			NSLog(@"readAllForumTopicReactions refused for %lld", (long long)threadId);
	}];
}

- (void)openTopic:(NSDictionary *)topic {
	int64_t threadId = [topic[@"threadId"] longLongValue];
	if (!threadId)
		return;
	[self markTopicRead:topic];

	TGChatViewController *vc = [[TGChatViewController alloc] init];
	vc.chatId = self.chatId;
	vc.threadId = threadId;
	vc.chatTitle = topic[@"name"];
	vc.isGroup = YES;
	[self.navigationController pushViewController:vc animated:YES];
}

static NSString *TGTopicWhen(NSNumber *stamp) {
	if (![stamp isKindOfClass:NSNumber.class] || ![stamp longLongValue])
		return @"";
	return [NSDateFormatter localizedStringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]]
			dateStyle:NSDateFormatterMediumStyle
			timeStyle:NSDateFormatterShortStyle];
}

static NSString *TGTopicIconLine(NSDictionary *info) {
	NSInteger colour = [info[@"colour"] integerValue];
	BOOL emoji = [info[@"iconEmojiId"] longLongValue] != 0;
	if (emoji)
		return [NSString stringWithFormat:@"Custom emoji · colour %06lX",
				(long)colour];
	return [NSString stringWithFormat:@"Colour %06lX", (long)colour];
}

static NSString *TGTopicStateLine(NSDictionary *info) {
	NSMutableArray *parts = [NSMutableArray array];
	if ([info[@"general"] boolValue]) [parts addObject:@"General"];
	if ([info[@"pinned"] boolValue])  [parts addObject:@"Pinned"];
	if ([info[@"closed"] boolValue])  [parts addObject:@"Closed"];
	if ([info[@"hidden"] boolValue])  [parts addObject:@"Hidden"];
	if (!parts.count)                 [parts addObject:@"Open"];
	return [parts componentsJoinedByString:@" · "];
}

/// Topic Info is where the fields no row has space for live, and where the
/// four one-topic calls are reached: the link, the notification record and
/// the two read marks that are not reactions.
- (void)showTopicInfoForTopic:(NSDictionary *)topic {
	int64_t threadId = [topic[@"threadId"] longLongValue];
	if (!threadId)
		return;

	TGListViewController *list = [[TGListViewController alloc] init];
	list.listTitle = [topic[@"name"] length] ? topic[@"name"] : @"Topic Info";
	list.emptyText = @"Telegram did not return this topic.";
	list.hidesBottomBarWhenPushed = YES;
	[self loadTopicInfoForList:list thread:threadId];
	[self.navigationController pushViewController:list animated:YES];
}

/// One getForumTopic per open and per action that changes the record. The
/// list is updated in place, so a mute or a read mark lands on the row the
/// user is looking at without pushing a second screen.
- (void)loadTopicInfoForList:(TGListViewController *)list thread:(int64_t)threadId {
	__weak typeof(self) weakSelf = self;
	__weak typeof(list) weakList = list;
	[[TGClient shared] forumTopic:threadId
						   inChat:self.chatId
					   completion:^(NSDictionary *info){
		TGTopicsViewController *me = weakSelf;
		TGListViewController *screen = weakList;
		if (!me || !screen)
			return;
		if (!info){
			screen.rows = @[];
			screen.emptyText = @"Telegram refused that topic.";
			return;
		}
		NSDictionary *settings = info[@"notificationSettings"];
		BOOL followMute = [settings[@"use_default_mute_for"] boolValue];
		NSInteger muteFor = [settings[@"mute_for"] integerValue];
		NSString *muteText = followMute ? @"Chat default"
				: (muteFor > 0
					? [NSString stringWithFormat:@"Muted %ld h", (long)(muteFor / 3600)]
					: @"Off");
		BOOL followPreview = [settings[@"use_default_show_preview"] boolValue];
		BOOL preview = [settings[@"show_preview"] boolValue];
		NSString *previewText = followPreview ? @"Chat default"
				: (preview ? @"On" : @"Off");
		NSString *unread = [NSString stringWithFormat:
				@"%ld messages · %ld mentions · %ld poll votes · %ld reactions",
				(long)[info[@"unread"] integerValue],
				(long)[info[@"unreadMentions"] integerValue],
				(long)[info[@"unreadPollVotes"] integerValue],
				(long)[info[@"unreadReactions"] integerValue]];
		void (^reload)(void) = ^{
			[me loadTopicInfoForList:screen thread:threadId];
		};

		screen.rows = @[
			@{@"title" : @"Name", @"detail" : info[@"name"] ?: @""},
			@{@"title" : @"Icon", @"detail" : TGTopicIconLine(info)},
			@{@"title" : @"State", @"detail" : TGTopicStateLine(info)},
			@{@"title" : @"Unread", @"detail" : unread},
			@{@"title" : @"Created",
			  @"detail" : TGTopicWhen(info[@"created"]) ?: @""},
			@{@"title" : @"Open Topic", @"detail" : @"Read and reply",
			  @"tap" : ^{ [me openTopic:info]; }},
			@{@"title" : @"Copy Link", @"detail" : @"t.me",
			  @"tap" : ^{
				[[TGClient shared] forumTopicLinkForTopic:threadId
												   inChat:me.chatId
											   completion:^(NSString *link){
					if (!link.length){
						[me showRefusal:@"Telegram did not return a link."
								  title:@"Copy Link"];
						return;
					}
					[UIPasteboard generalPasteboard].string = link;
					[TGAlertSheet showMessage:link title:@"Link Copied"
									   inView:me.view];
				}];
			}},
			@{@"title" : @"Notifications", @"detail" :
					[NSString stringWithFormat:@"%@ · previews %@",
							muteText, previewText],
			  @"tap" : ^{
				[me showTopicNotificationSettingsForTopic:info reload:reload];
			}},
			@{@"title" : @"Mark Mentions Read", @"detail" :
					[NSString stringWithFormat:@"%ld unread",
							(long)[info[@"unreadMentions"] integerValue]],
			  @"tap" : ^{
				[[TGClient shared] readAllForumTopicMentionsInChat:me.chatId
															 topic:threadId
														completion:^(BOOL ok, NSString *error){
					if (!ok){
						[me showRefusal:(error ?: @"Telegram refused.")
								  title:@"Mentions"];
						return;
					}
					[me markTopicBadgeRead:threadId key:@"unreadMentions"];
					[me loadTopicInfoForList:screen thread:threadId];
				}];
			}},
			@{@"title" : @"Mark Poll Votes Read", @"detail" :
					[NSString stringWithFormat:@"%ld unread",
							(long)[info[@"unreadPollVotes"] integerValue]],
			  @"tap" : ^{
				[[TGClient shared] readAllForumTopicPollVotesInChat:me.chatId
															  topic:threadId
														 completion:^(BOOL ok, NSString *error){
					if (!ok){
						[me showRefusal:(error ?: @"Telegram refused.")
								  title:@"Poll Votes"];
						return;
					}
					[me markTopicBadgeRead:threadId key:@"unreadPollVotes"];
					[me loadTopicInfoForList:screen thread:threadId];
				}];
			}},
		];
	}];
}

/// A count cleared from one action: the list row and Topic Info must agree
/// before the server's update lands.
- (void)markTopicBadgeRead:(int64_t)threadId key:(NSString *)key {
	NSMutableArray *rows = [NSMutableArray arrayWithArray:self.topics];
	for (NSUInteger i = 0; i < rows.count; i++){
		if ([rows[i][@"threadId"] longLongValue] != threadId)
			continue;
		NSMutableDictionary *next = [rows[i] mutableCopy];
		next[key] = @(0);
		rows[i] = next;
		break;
	}
	self.topics = rows;
	[self.tableView reloadData];
}

/// Mute and preview are two fields of one chatNotificationSettings object;
/// setForumTopicNotificationSettings writes the whole object, so every other
/// field comes from the record getForumTopic just returned.
- (void)showTopicNotificationSettingsForTopic:(NSDictionary *)info
									   reload:(void (^)(void))reload {
	NSDictionary *current = info[@"notificationSettings"];
	if (![current isKindOfClass:NSDictionary.class])
		current = @{};
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Mute for 1 hour", @"Mute for 8 hours",
								@"Mute for 2 days", @"Unmute",
								@"Show Previews", @"Hide Previews"]
						title:@"Topic Notifications"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		NSMutableDictionary *next = [@{
			@"@type" : @"chatNotificationSettings",
			@"use_default_mute_for" : current[@"use_default_mute_for"] ?: @YES,
			@"mute_for" : current[@"mute_for"] ?: @(0),
			@"use_default_sound" : current[@"use_default_sound"] ?: @YES,
			@"sound_id" : current[@"sound_id"] ?: @(0),
			@"use_default_show_preview" : current[@"use_default_show_preview"] ?: @YES,
			@"show_preview" : current[@"show_preview"] ?: @YES,
			@"use_default_mute_stories" : current[@"use_default_mute_stories"] ?: @YES,
			@"mute_stories" : current[@"mute_stories"] ?: @NO,
			@"use_default_story_sound" : current[@"use_default_story_sound"] ?: @YES,
			@"story_sound_id" : current[@"story_sound_id"] ?: @(0),
			@"use_default_show_story_poster" :
					current[@"use_default_show_story_poster"] ?: @YES,
			@"show_story_poster" : current[@"show_story_poster"] ?: @YES,
			@"use_default_disable_pinned_message_notifications" :
					current[@"use_default_disable_pinned_message_notifications"] ?: @YES,
			@"disable_pinned_message_notifications" :
					current[@"disable_pinned_message_notifications"] ?: @NO,
			@"use_default_disable_mention_notifications" :
					current[@"use_default_disable_mention_notifications"] ?: @YES,
			@"disable_mention_notifications" :
					current[@"disable_mention_notifications"] ?: @NO,
		} mutableCopy];
		if (index <= 3){
			NSInteger seconds = index == 0 ? 3600
					: index == 1 ? 8 * 3600
					: index == 2 ? 2 * 24 * 3600 : 0;
			next[@"use_default_mute_for"] = @NO;
			next[@"mute_for"] = @(seconds);
		} else {
			next[@"use_default_show_preview"] = @NO;
			next[@"show_preview"] = @(index == 4);
		}
		[[TGClient shared] setForumTopicNotificationSettings:next
													   topic:[info[@"threadId"] longLongValue]
													  inChat:weakSelf.chatId
												  completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showRefusal:(error ?: @"Telegram refused that setting.")
								title:@"Topic Notifications"];
				return;
			}
			if (reload)
				reload();
		}];
	}];
}

/// setPinnedForumTopics writes the whole order, not one flag: pin, unpin and
/// move are all the same request with a different id list.
- (void)showPinnedTopicsManager {
	TGListViewController *list = [[TGListViewController alloc] init];
	list.listTitle = @"Pinned Topics";
	list.emptyText = @"Telegram returned no topics.";
	list.listFooter = @"Pinned topics are written in this order. Moving one "
					  @"rewrites the list for everyone.";
	list.hidesBottomBarWhenPushed = YES;
	[self loadPinnedTopicsIntoList:list];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)loadPinnedTopicsIntoList:(TGListViewController *)list {
	__weak typeof(self) weakSelf = self;
	__weak typeof(list) weakList = list;
	[[TGClient shared] forumTopicsForChat:self.chatId completion:^(NSArray *topics){
		TGTopicsViewController *me = weakSelf;
		TGListViewController *screen = weakList;
		if (!me || !screen)
			return;
		me.topics = topics;
		[me.tableView reloadData];
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *topic in topics){
			BOOL pinned = [topic[@"pinned"] boolValue];
			NSString *title = topic[@"name"] ?: @"Topic";
			[rows addObject:@{
				@"title" : title,
				@"detail" : pinned ? @"Pinned" : @"Not pinned",
				@"tap" : ^{
					NSMutableArray *choices = [NSMutableArray arrayWithObject:
							pinned ? @"Unpin" : @"Pin to Top"];
					if (pinned){
						[choices addObject:@"Move Up"];
						[choices addObject:@"Move Down"];
					}
					[TGAlertSheet showChoices:choices
										title:title
							 destructiveIndex:-1
									   inView:me.view
									 onChoice:^(NSInteger choice){
						[me changePinnedTopic:topic
									  choice:choice
									 pinnings:topics
								  completion:^{
							[me loadPinnedTopicsIntoList:screen];
						}];
					}];
				},
			}];
		}
		screen.rows = rows;
	}];
}

- (void)changePinnedTopic:(NSDictionary *)topic
				   choice:(NSInteger)choice
				  pinnings:(NSArray *)topics
			   completion:(void (^)(void))completion {
	int64_t threadId = [topic[@"threadId"] longLongValue];
	BOOL pinned = [topic[@"pinned"] boolValue];
	NSMutableArray *pinnedIds = [NSMutableArray array];
	for (NSDictionary *row in topics)
		if ([row[@"pinned"] boolValue])
			[pinnedIds addObject:@([row[@"threadId"] longLongValue])];
	NSNumber *idNumber = @(threadId);

	if (choice == 0){
		if (pinned){
			[pinnedIds removeObject:idNumber];
		} else {
			[pinnedIds insertObject:idNumber atIndex:0];
		}
	} else {
		NSUInteger at = [pinnedIds indexOfObject:idNumber];
		if (at == NSNotFound){
			[TGAlertSheet showMessage:@"That topic is not pinned any more."
								title:@"Pinned Topics" inView:self.view];
			return;
		}
		if (choice == 1 && at > 0){
			[pinnedIds exchangeObjectAtIndex:at withObjectAtIndex:at - 1];
		} else if (choice == 2 && at + 1 < pinnedIds.count){
			[pinnedIds exchangeObjectAtIndex:at withObjectAtIndex:at + 1];
		} else {
			[TGAlertSheet showMessage:@"That topic is already at the edge of "
									  @"the pinned list."
								title:@"Pinned Topics" inView:self.view];
			return;
		}
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setPinnedForumTopics:pinnedIds
									 inChat:self.chatId
								 completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf showRefusal:(error ?: @"Telegram refused that order.")
							title:@"Pinned Topics"];
			return;
		}
		[weakSelf reloadTopics];
		if (completion)
			completion();
	}];
}

/// The system's caption is grey on grey over a dark list, which is what
/// this screen had: every other list styles its own.

@end

// vim:ft=objc
