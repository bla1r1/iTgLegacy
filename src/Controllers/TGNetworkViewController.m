//
// TGNetworkViewController.m - the network and diagnostics panel.
//
// TDLib already knows the connection it is on, the state it was in when asked,
// what its configuration says and how many bytes went over the radio. This
// page asks it, and every row either shows the answer or spells out the
// refusal; none of it is a local guess.
//
#import "TGNetworkViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"
#import "TGStorageViewController.h"
#import "TGStyle.h"
#import "TGTheme.h"

static NSMutableDictionary *TGNetRow(NSString *title, NSString *detail,
									 void (^tap)(void)) {
	NSMutableDictionary *row = [@{@"title" : title ?: @""} mutableCopy];
	if (detail.length)
		row[@"detail"] = detail;
	if (tap)
		row[@"tap"] = [tap copy];
	return row;
}

static NSString *TGNetworkTypeTitle(NSString *type) {
	if ([type isEqualToString:@"none"])    return @"None";
	if ([type isEqualToString:@"mobile"])  return @"Mobile";
	if ([type isEqualToString:@"roaming"] || [type isEqualToString:@"mobileRoaming"])
		return @"Mobile Roaming";
	if ([type isEqualToString:@"wifi"] || [type isEqualToString:@"wiFi"])
		return @"Wi-Fi";
	return @"Other";
}

static NSString *TGNetBytes(long long bytes) {
	if (bytes <= 0)
		return @"0 KB";
	if (bytes < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
	if (bytes < 1024LL * 1024 * 1024)
		return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
	return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

static NSString *TGConfigValueText(id value) {	if ([value isKindOfClass:NSString.class])
		return value;
	if ([value isKindOfClass:NSNumber.class])
		return [value stringValue];
	if (value == [NSNull null])
		return @"null";
	NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
	if (!data)
		return [value description];
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSDictionary *TGNetSection(NSString *header, NSString *footer, NSArray *rows) {
	NSMutableDictionary *section = [NSMutableDictionary dictionary];
	if (header) section[@"header"] = header;
	if (footer) section[@"footer"] = footer;
	section[@"rows"] = rows ?: @[];
	return section;
}

@interface TGNetworkViewController ()
@property (nonatomic, copy) NSString *networkType;
@property (nonatomic, assign) long long sent;
@property (nonatomic, assign) long long received;
@property (nonatomic, strong) NSArray *stateRows;
@property (nonatomic, copy) NSString *stateError;
@property (nonatomic, assign) BOOL stateLoaded;
@property (nonatomic, copy) NSString *status;
/// Grouped the way Telegram's Data and Storage pages are: the connection,
/// the diagnostics, what the radio carried, and the graph. The flat `rows`
/// the base list keeps is filled from these so Copy still prints everything.
@property (nonatomic, strong) NSArray *sections;
@end

@implementation TGNetworkViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Network";
	// TDLib does not remember the last setNetworkType across launches, so the
	// page does. "Other" is what TDLib itself uses until it is told.
	NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"TGNetworkType"];
	self.networkType = saved.length ? saved : @"other";
	[self loadTotals];
	[self loadState];
	[self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuild];
}

- (void)rebuild {
	self.sections = [self buildSections];
	NSMutableArray *flat = [NSMutableArray array];
	for (NSDictionary *section in self.sections)
		[flat addObjectsFromArray:section[@"rows"]];
	self.rows = flat;
	self.listFooter = self.status.length ? self.status
			: @"TDLib reopens every connection when the network type changes. "
			  @"The counters are reset by TDLib itself and cover this launch only "
			  @"until reset.";
	[self.tableView reloadData];
}

- (NSArray *)buildSections {
	__weak typeof(self) weakSelf = self;

	NSString *stateDetail = self.stateError.length ? self.stateError
			: (self.stateLoaded
				? [NSString stringWithFormat:@"%lu updates",
						(unsigned long)self.stateRows.count]
				: @"Reading...");

	NSArray *connection = @[
		TGNetRow(@"Network Type", TGNetworkTypeTitle(self.networkType), ^{
			[weakSelf chooseNetworkType];
		}),
	];

	NSArray *diagnostics = @[
		TGNetRow(@"TDLib State", stateDetail, ^{
			[weakSelf showCurrentState];
		}),
		TGNetRow(@"Application Config", @"Tap to read", ^{
			[weakSelf showApplicationConfig];
		}),
		TGNetRow(@"Database Statistics", @"Tap to read", ^{
			[weakSelf showDatabaseStatistics];
		}),
	];

	NSArray *usage = @[
		TGNetRow(@"Data Usage",
				[NSString stringWithFormat:@"%@ in, %@ out",
						TGNetBytes(weakSelf.received), TGNetBytes(weakSelf.sent)],
				^{ [weakSelf loadTotals]; }),
		TGNetRow(@"Add Usage Entry",
				@"A call's bytes and duration", ^{ [weakSelf addUsageEntry]; }),
	];

	NSArray *graph = @[
		TGNetRow(@"Statistical Graph",
				@"Render a chat statistics token", ^{ [weakSelf askStatisticalGraph]; }),
	];

	return @[
		TGNetSection(@"CONNECTION",
				@"TDLib reports the network it is on; changing it here reopens "
				@"every connection.", connection),
		TGNetSection(@"DIAGNOSTICS",
				@"The state, configuration and database report TDLib answers "
				@"when this page asks.", diagnostics),
		TGNetSection(@"DATA USAGE",
				@"The counters cover this launch. Reset adds a call's bytes "
				@"back into TDLib's own totals.", usage),
		TGNetSection(@"STATISTICS",
				@"A statistics token from a chat's admin panel draws its graph "
				@"here as a list of points.", graph),
	];
}

/// The base list has one section and one flat row list; this page draws its
/// four groups itself and hands the shared cell styling the flat index.
- (NSInteger)flatRowForIndexPath:(NSIndexPath *)path {
	NSInteger flat = 0;
	for (NSInteger i = 0; i < (NSInteger)self.sections.count && i < path.section; i++)
		flat += (NSInteger)[self.sections[(NSUInteger)i][@"rows"] count];
	return flat + path.row;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return 0;
	return (NSInteger)[self.sections[(NSUInteger)section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return nil;
	NSString *text = self.sections[(NSUInteger)section][@"header"];
	return text.length ? text : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section >= (NSInteger)self.sections.count)
		return nil;
	if (section == (NSInteger)self.sections.count - 1 && self.status.length)
		return self.status;
	NSString *text = self.sections[(NSUInteger)section][@"footer"];
	return text.length ? text : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSIndexPath *flat = [NSIndexPath indexPathForRow:[self flatRowForIndexPath:indexPath]
										  inSection:0];
	return [super tableView:tableView cellForRowAtIndexPath:flat];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSInteger flat = [self flatRowForIndexPath:indexPath];
	if (flat < 0 || flat >= (NSInteger)self.rows.count)
		return;
	void (^tap)(void) = self.rows[(NSUInteger)flat][@"tap"];
	if (tap)
		tap();
}

#pragma mark - network type

- (void)chooseNetworkType {
	static NSArray *names = nil;
	static NSArray *titles = nil;
	if (!names){
		names = @[@"none", @"mobile", @"roaming", @"wifi", @"other"];
		titles = @[@"None", @"Mobile", @"Mobile Roaming", @"Wi-Fi", @"Other"];
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles
						title:@"Network Type"
					  message:@"Telegram reopens its connections when this changes."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index >= (NSInteger)names.count)
			return;
		NSString *type = names[(NSUInteger)index];
		[[TGClient shared] setNetworkType:type completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf showError:error title:@"Network Type"];
				return;
			}
			weakSelf.networkType = type;
			[NSUserDefaults.standardUserDefaults setObject:type forKey:@"TGNetworkType"];
			[NSUserDefaults.standardUserDefaults synchronize];
			weakSelf.status = [NSString stringWithFormat:
					@"Telegram accepted the network type: %@.", TGNetworkTypeTitle(type)];
			[weakSelf rebuild];
		}];
	}];
}

#pragma mark - state

- (void)loadState {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] currentStateWithCompletion:^(NSArray *updates, NSString *error){
		weakSelf.stateRows = updates ?: @[];
		weakSelf.stateError = error;
		weakSelf.stateLoaded = YES;
		if (error.length)
			weakSelf.status = error;
		[weakSelf rebuild];
	}];
}

- (void)showCurrentState {
	__weak typeof(self) weakSelf = self;
	void (^show)(NSArray *, NSString *) = ^(NSArray *updates, NSString *error){
		NSMutableArray *rows = [NSMutableArray array];
		for (NSDictionary *update in updates){
			NSMutableDictionary *row = TGNetRow(update[@"type"], update[@"summary"], nil);
			[rows addObject:row];
		}
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"TDLib State";
		list.rows = rows;
		list.emptyText = error.length ? error : @"TDLib is in no state yet.";
		list.offersCopy = YES;
		list.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:list animated:YES];
	};
	if (self.stateLoaded)
		show(self.stateRows, self.stateError);
	else
		[[TGClient shared] currentStateWithCompletion:^(NSArray *updates, NSString *error){
			weakSelf.stateRows = updates ?: @[];
			weakSelf.stateError = error;
			weakSelf.stateLoaded = YES;
			[weakSelf rebuild];
			show(updates, error);
		}];
}

#pragma mark - configuration and database

- (void)showApplicationConfig {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] applicationConfigWithCompletion:^(NSDictionary *config,
														  NSString *error){
		if (!config){
			[weakSelf showError:error title:@"Application Config"];
			return;
		}
		NSArray *keys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
		NSMutableArray *rows = [NSMutableArray arrayWithCapacity:keys.count];
		for (NSString *key in keys)
			[rows addObject:TGNetRow(key, TGConfigValueText(config[key]), nil)];
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Application Config";
		list.rows = rows;
		list.emptyText = @"Telegram sent an empty configuration.";
		list.listFooter = [NSString stringWithFormat:
				@"getApplicationConfig answered %lu values.", (unsigned long)keys.count];
		list.offersCopy = YES;
		list.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:list animated:YES];
	}];
}

- (void)showDatabaseStatistics {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] databaseStatisticsWithCompletion:^(NSString *statistics,
														   NSString *error){
		if (!statistics.length){
			[weakSelf showError:(error ?: @"Telegram sent no database statistics.")
						  title:@"Database Statistics"];
			return;
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (NSString *line in [statistics componentsSeparatedByString:@"\n"])
			if (line.length)
				[rows addObject:TGNetRow(line, nil, nil)];
		TGListViewController *list = [[TGListViewController alloc] init];
		list.listTitle = @"Database Statistics";
		list.rows = rows;
		list.emptyText = statistics;
		list.offersCopy = YES;
		list.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:list animated:YES];
	}];
}

#pragma mark - data usage

- (void)loadTotals {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] networkStatsWithCompletion:^(long long sent, long long received){
		weakSelf.sent = sent;
		weakSelf.received = received;
		[weakSelf rebuild];
	}];
}

- (void)addUsageEntry {
	static NSArray *names = nil;
	static NSArray *titles = nil;
	if (!names){
		names = @[@"none", @"mobile", @"roaming", @"wifi", @"other"];
		titles = @[@"None", @"Mobile", @"Mobile Roaming", @"Wi-Fi", @"Other"];
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles
						title:@"Add Usage Entry"
					  message:@"Which network did the call use?"
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index >= (NSInteger)names.count)
			return;
		NSString *type = names[(NSUInteger)index];
		[TGAlertSheet showInput:@"Add Usage Entry"
						message:@"Bytes sent"
					placeholder:@"0"
						   text:@"0" action:@"Next" inView:weakSelf.view
					   onSubmit:^(NSString *sentText){
			[TGAlertSheet showInput:@"Add Usage Entry"
							message:@"Bytes received"
						placeholder:@"0"
							   text:@"0" action:@"Next" inView:weakSelf.view
						   onSubmit:^(NSString *receivedText){
				[TGAlertSheet showInput:@"Add Usage Entry"
								message:@"Call duration, seconds"
							placeholder:@"0"
								   text:@"0" action:@"Add" inView:weakSelf.view
							   onSubmit:^(NSString *durationText){
					[[TGClient shared] addNetworkStatisticsForNetworkType:type
							sentBytes:[sentText longLongValue]
							receivedBytes:[receivedText longLongValue]
								 duration:[durationText doubleValue]
							   completion:^(BOOL ok, NSString *error){
						if (!ok){
							[weakSelf showError:error title:@"Add Usage Entry"];
							return;
						}
						weakSelf.status = [NSString stringWithFormat:
								@"Telegram added the entry: %@ in, %@ out.",
								TGNetBytes([receivedText longLongValue]),
								TGNetBytes([sentText longLongValue])];
						[weakSelf loadTotals];
						[TGAlertSheet showMessage:weakSelf.status
											title:@"Add Usage Entry"
										   inView:weakSelf.view];
					}];
				}];
			}];
		}];
	}];
}

#pragma mark - statistical graph

- (void)askStatisticalGraph {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Statistical Graph"
					message:@"Chat id"
				placeholder:@"-100..."
					   text:nil action:@"Next" inView:self.view
				   onSubmit:^(NSString *chatText){
		int64_t chatId = chatText.longLongValue;
		[TGAlertSheet showInput:@"Statistical Graph"
						message:@"Statistics token"
					placeholder:@"token"
						   text:nil action:@"Next" inView:weakSelf.view
					   onSubmit:^(NSString *token){
			[TGAlertSheet showInput:@"Statistical Graph"
							message:@"X value (0 for the whole graph)"
						placeholder:@"0"
							   text:@"0" action:@"Render" inView:weakSelf.view
						   onSubmit:^(NSString *xText){
				[[TGClient shared] statisticalGraphForChat:chatId
													token:token
														x:(NSInteger)xText.longLongValue
											   completion:^(NSDictionary *graph, NSString *error){
					if (!graph){
						[weakSelf showError:error title:@"Statistical Graph"];
						return;
					}
					NSMutableArray *rows = [NSMutableArray array];
					for (NSString *line in graph[@"lines"])
						[rows addObject:TGNetRow(line, nil, nil)];
					TGListViewController *list = [[TGListViewController alloc] init];
					list.listTitle = @"Statistical Graph";
					list.rows = rows;
					list.emptyText = @"Telegram sent an empty graph.";
					list.listFooter = [graph[@"kind"] isEqualToString:@"async"]
							? @"The graph is still being prepared. Open the page "
							  @"again with the token above."
							: [NSString stringWithFormat:@"getStatisticalGraph answered %lu lines.",
									(unsigned long)rows.count];
					list.offersCopy = YES;
					list.hidesBottomBarWhenPushed = YES;
					[weakSelf.navigationController pushViewController:list animated:YES];
				}];
			}];
		}];
	}];
}

#pragma mark - answer

- (void)showError:(NSString *)message title:(NSString *)title {
	if (!message.length)
		message = @"Telegram refused that.";
	self.status = message;
	[TGAlertSheet showMessage:message title:title inView:self.view];
	[self rebuild];
}

@end
