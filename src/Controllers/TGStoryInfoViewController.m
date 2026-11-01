#import "TGStoryInfoViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"

static NSString *TGStoryDateText(NSNumber *unixTime) {
	static NSDateFormatter *formatter = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSDateFormatter alloc] init];
		[formatter setDateStyle:NSDateFormatterMediumStyle];
		[formatter setTimeStyle:NSDateFormatterShortStyle];
	});
	if (![unixTime isKindOfClass:NSNumber.class] || unixTime.doubleValue <= 0)
		return @"-";
	return [formatter stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:unixTime.doubleValue]];
}

@interface TGStoryInfoViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int32_t storyId;
@property (nonatomic, strong) NSDictionary *story;
@property (nonatomic, assign) TGStoryInfoMode mode;
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, assign) BOOL reportStarted;
@end

@implementation TGStoryInfoViewController

- (instancetype)initWithChatId:(int64_t)chatId
					   storyId:(int32_t)storyId
						 story:(NSDictionary *)story
						  mode:(TGStoryInfoMode)mode {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_chatId = chatId;
		_storyId = storyId;
		_story = [story copy] ?: @{};
		_mode = mode;
		_rows = [NSMutableArray array];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = self.mode == TGStoryInfoModeReport ? @"Report Story" : @"Story Info";
	[[TGTheme shared] styleGroupedTable:self.tableView];
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf.tableView reloadData];
	}];
	[self buildRows];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (self.mode == TGStoryInfoModeReport && !self.reportStarted){
		self.reportStarted = YES;
		[self startReport];
	}
}

- (void)buildRows {
	[self.rows removeAllObjects];
	NSDictionary *story = self.story;
	[self.rows addObject:@{@"title" : @"Posted",
						   @"detail" : TGStoryDateText(story[@"date"])}];
	[self.rows addObject:@{@"title" : @"Views",
						   @"detail" : [NSString stringWithFormat:@"%@",
								   story[@"viewers"] ?: @(0)]}];
	[self.rows addObject:@{@"title" : @"Forwards",
						   @"detail" : [NSString stringWithFormat:@"%@",
								   story[@"forwards"] ?: @(0)]}];
	[self.rows addObject:@{@"title" : @"Reactions",
						   @"detail" : [NSString stringWithFormat:@"%@",
								   story[@"reactions"] ?: @(0)]}];
	NSString *privacy = story[@"privacy"];
	if (![privacy isKindOfClass:NSString.class] || !privacy.length)
		privacy = @"unknown";
	[self.rows addObject:@{@"title" : @"Privacy", @"detail" : privacy}];
	[self.rows addObject:@{@"title" : @"On Chat Page",
						   @"detail" : [story[@"isPostedToChatPage"] boolValue]
								   ? @"Yes" : @"No"}];

	__weak typeof(self) weakSelf = self;
	[self.rows addObject:@{@"title" : @"Load Interactions",
						   @"detail" : @"Viewers, reactions and forwards",
						   @"tap" : ^{ [weakSelf loadInteractions]; }}];
	[self.rows addObject:@{@"title" : @"Load Public Forwards",
						   @"detail" : @"Messages and reposts",
						   @"tap" : ^{ [weakSelf loadPublicForwards]; }}];
	[self.rows addObject:@{@"title" : @"Load Statistics",
						   @"detail" : @"Interaction and reaction graphs",
						   @"tap" : ^{ [weakSelf loadStatistics]; }}];
	if (self.mode == TGStoryInfoModeInfo)
		[self.rows addObject:@{@"title" : @"Report Story",
							   @"detail" : @"Send it to Telegram's moderators",
							   @"tap" : ^{ [weakSelf startReport]; }}];
	[self.tableView reloadData];
}

- (void)loadInteractions {
	int64_t ownChat = [[TGClient shared] savedMessagesChatId];
	__weak typeof(self) weakSelf = self;
	void (^done)(NSDictionary *, NSString *) = ^(NSDictionary *page, NSString *error){
		TGStoryInfoViewController *me = weakSelf;
		if (!me)
			return;
		if (!page){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Interactions" inView:me.view];
			return;
		}
		[me appendPage:page];
	};
	if (self.chatId == ownChat)
		[[TGClient shared] storyInteractionsForStory:self.storyId
											   query:@""
										onlyContacts:NO
									   preferForwards:NO
								   preferWithReaction:NO
											   offset:@""
												limit:20
										  completion:done];
	else
		[[TGClient shared] chatStoryInteractionsForStory:self.storyId
												fromChat:self.chatId
										   reactionEmoji:nil
										  preferForwards:NO
												  offset:@""
												   limit:20
											  completion:done];
}

- (void)appendPage:(NSDictionary *)page {
	NSArray *interactions = page[@"interactions"];
	NSMutableArray *added = [NSMutableArray array];
	[added addObject:@{@"title" : @"Interactions",
					   @"detail" : [NSString stringWithFormat:@"%@ total, %@ forwards, %@ reactions",
							   page[@"totalCount"] ?: @(0),
							   page[@"totalForwardCount"] ?: @(0),
							   page[@"totalReactionCount"] ?: @(0)]}];
	for (NSDictionary *row in interactions){
		NSString *kind = row[@"kind"] ?: @"view";
		NSString *reaction = row[@"reaction"] ?: @"";
		NSString *detail = [NSString stringWithFormat:@"%@ · %@%@",
				TGStoryDateText(row[@"date"]), kind,
				reaction.length ? [@" · " stringByAppendingString:reaction] : @""];
		[added addObject:@{@"title" : row[@"name"] ?: @"Someone",
						   @"detail" : detail}];
	}
	[self.rows addObjectsFromArray:added];
	[self.tableView reloadData];
	if (!interactions.count)
		[TGAlertSheet showMessage:@"Telegram returned no interactions."
							title:@"Interactions" inView:self.view];
}

- (void)loadPublicForwards {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storyPublicForwards:self.storyId
								  fromChat:self.chatId
									offset:@""
									 limit:20
								completion:^(NSDictionary *page, NSString *error){
		TGStoryInfoViewController *me = weakSelf;
		if (!me)
			return;
		if (!page){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Public Forwards" inView:me.view];
			return;
		}
		NSMutableArray *added = [NSMutableArray array];
		[added addObject:@{@"title" : @"Public Forwards",
						   @"detail" : [NSString stringWithFormat:@"%@ total",
								   page[@"totalCount"] ?: @(0)]}];
		for (NSDictionary *row in page[@"forwards"]){
			NSString *title = row[@"title"];
			if (!title.length)
				title = [row[@"kind"] isEqualToString:@"story"]
						? @"Reposted story" : @"Forwarded message";
			NSString *detail = row[@"text"];
			if (!detail.length)
				detail = TGStoryDateText(row[@"date"]);
			[added addObject:@{@"title" : title, @"detail" : detail}];
		}
		[me.rows addObjectsFromArray:added];
		[me.tableView reloadData];
	}];
}

- (void)loadStatistics {
	__weak typeof(self) weakSelf = self;
	CGFloat white = 0;
	[[[TGTheme shared] listBackgroundColour] getWhite:&white alpha:NULL];
	[[TGClient shared] storyStatistics:self.storyId
							  fromChat:self.chatId
								isDark:white < 0.5
							completion:^(NSDictionary *statistics, NSString *error){
		TGStoryInfoViewController *me = weakSelf;
		if (!me)
			return;
		if (!statistics){
			[TGAlertSheet showMessage:error ?: @"Telegram refused that."
								title:@"Story Statistics" inView:me.view];
			return;
		}
		NSMutableArray *added = [NSMutableArray array];
		NSDictionary *interaction = statistics[@"interaction"] ?: @{};
		NSDictionary *reaction = statistics[@"reaction"] ?: @{};
		[added addObject:@{@"title" : @"Interaction Graph",
						   @"detail" : interaction[@"kind"] ?: @"none"}];
		for (NSString *line in interaction[@"lines"] ?: @[])
			[added addObject:@{@"title" : line}];
		[added addObject:@{@"title" : @"Reaction Graph",
						   @"detail" : reaction[@"kind"] ?: @"none"}];
		for (NSString *line in reaction[@"lines"] ?: @[])
			[added addObject:@{@"title" : line}];
		[me.rows addObjectsFromArray:added];
		[me.tableView reloadData];
	}];
}

#pragma mark - reporting

- (void)startReport {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] reportStory:self.storyId
						  fromChat:self.chatId
						  optionId:@""
							  text:@""
						completion:^(NSDictionary *result, NSString *error){
		[weakSelf handleReport:result error:error];
	}];
}

- (void)handleReport:(NSDictionary *)result error:(NSString *)error {
	if (!result){
		[TGAlertSheet showMessage:error ?: @"Telegram refused the report."
							title:@"Report Story" inView:self.view];
		return;
	}
	NSString *state = result[@"state"];
	if ([state isEqualToString:@"ok"]){
		[TGAlertSheet showMessage:@"The story was reported to Telegram."
							title:@"Report Story" inView:self.view];
		return;
	}
	if ([state isEqualToString:@"options"]){
		NSArray *options = result[@"options"] ?: @[];
		NSMutableArray *titles = [NSMutableArray array];
		for (NSDictionary *option in options)
			[titles addObject:option[@"text"] ?: @"Report"];
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showChoices:titles title:result[@"title"] ?: @"Report Story"
					destructiveIndex:-1 inView:self.view onChoice:^(NSInteger choice){
			TGStoryInfoViewController *me = weakSelf;
			if (!me || choice < 0 || choice >= (NSInteger)options.count)
				return;
			NSDictionary *option = options[choice];
			[[TGClient shared] reportStory:me.storyId
								  fromChat:me.chatId
								  optionId:option[@"id"] ?: @""
									  text:@""
								completion:^(NSDictionary *next, NSString *why){
				[me handleReport:next error:why];
			}];
		}];
		return;
	}
	if ([state isEqualToString:@"text"]){
		NSString *optionId = result[@"optionId"] ?: @"";
		BOOL optional = [result[@"optional"] boolValue];
		__weak typeof(self) weakSelf = self;
		[TGAlertSheet showInput:@"Report Story"
						message:optional ? @"Add a note, or leave it empty." : @"Add a note."
					placeholder:@"Details"
						   text:nil
						 action:@"Send"
						 inView:self.view
					   onSubmit:^(NSString *text){
			TGStoryInfoViewController *me = weakSelf;
			if (!me)
				return;
			[[TGClient shared] reportStory:me.storyId
								  fromChat:me.chatId
								  optionId:optionId
									  text:text
								completion:^(NSDictionary *next, NSString *why){
				[me handleReport:next error:why];
			}];
		}];
		return;
	}
	[TGAlertSheet showMessage:@"Telegram answered the report in a way this app "
			@"does not understand." title:@"Report Story" inView:self.view];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.mode == TGStoryInfoModeReport ? @"Report" : @"Story";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *row = self.rows[indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"storyInfo"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"storyInfo"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = row[@"title"] ?: @"";
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.text = row[@"detail"];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.detailTextLabel.numberOfLines = 4;
	cell.accessoryType = row[@"tap"] ? UITableViewCellAccessoryDisclosureIndicator
									 : UITableViewCellAccessoryNone;
	cell.selectionStyle = row[@"tap"] ? UITableViewCellSelectionStyleBlue
									  : UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.rows.count)
		return;
	void (^tap)(void) = self.rows[indexPath.row][@"tap"];
	if (tap)
		tap();
}

@end
