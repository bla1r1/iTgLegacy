//
// TGAffiliateProgramsViewController.m
//
// Every row names the affiliate it acts for. The connection records are
// real TDLib reads and writes; the payout itself happens on Fragment, which
// this build does not carry. That is why the screen shows a connection URL
// instead of promising money.
//
#import "TGAffiliateProgramsViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"

@interface TGAffiliateProgramsViewController ()
@property (nonatomic, copy) NSString *offset;
@property (nonatomic, copy) NSString *sort;
@property (nonatomic, copy) NSString *connectionURL;
@property (nonatomic, assign) int64_t programBotId;
@property (nonatomic, assign) int32_t limit;
@property (nonatomic, assign) int32_t commission;
@property (nonatomic, assign) int32_t months;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGAffiliateProgramsViewController

- (instancetype)init {
	if ((self = [super init])){
		_kind = @"user";
		_sort = @"profitability";
		_limit = 20;
		_commission = 50;
		_months = 12;
		_answerLines = @[@"Choose a kind and load the catalogue or a connection."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Affiliate Programs";
	[self rebuildSections];
}

- (NSString *)kindTitle {
	if ([self.kind isEqualToString:@"bot"]) return @"Bot";
	if ([self.kind isEqualToString:@"channel"]) return @"Channel";
	return @"This Account";
}

- (void)rebuildSections {
	NSMutableArray *identity = [NSMutableArray array];
	[identity addObject:TGBAction(@"Affiliate", self.kindTitle, @"kind")];
	[identity addObject:TGBAction(@"Bot User ID", self.botUserId
			? [NSString stringWithFormat:@"%lld", self.botUserId] : @"Set", @"botId")];
	[identity addObject:TGBAction(@"Channel Chat ID", self.chatId
			? [NSString stringWithFormat:@"%lld", self.chatId] : @"Set", @"chatId")];
	[identity addObject:TGBAction(@"Program Bot ID", self.programBotId
			? [NSString stringWithFormat:@"%lld", self.programBotId] : @"Set",
			@"programBotId")];
	[identity addObject:TGBAction(@"Sort", self.sort, @"sort")];
	[identity addObject:TGBAction(@"Offset",
			self.offset.length ? self.offset : @"(first page)", @"offset")];
	[identity addObject:TGBAction(@"Limit", [NSString stringWithFormat:@"%d",
			(int)self.limit], @"limit")];

	NSMutableArray *catalogue = [NSMutableArray array];
	[catalogue addObject:TGBAction(@"Search Programs", nil, @"search")];
	[catalogue addObject:TGBAction(@"Connected Programs", nil, @"connected")];
	[catalogue addObject:TGBAction(@"Get One Connection", nil, @"one")];
	[catalogue addObject:TGBAction(@"Connect Program", nil, @"connect")];
	[catalogue addObject:TGBAction(@"Disconnect URL",
			self.connectionURL.length ? self.connectionURL : @"Set", @"url")];
	[catalogue addObject:TGBDestructive(@"Disconnect Program", @"disconnect")];

	NSMutableArray *channel = [NSMutableArray array];
	[channel addObject:TGBAction(@"Channel Program Page", nil, @"channelPage")];
	[channel addObject:TGBAction(@"Commission Per Mille", [NSString stringWithFormat:
			@"%d", (int)self.commission], @"commission")];
	[channel addObject:TGBAction(@"Month Count", [NSString stringWithFormat:
			@"%d", (int)self.months], @"months")];
	[channel addObject:TGBAction(@"Search Channel Program", nil, @"searchChannel")];
	[channel addObject:TGBAction(@"Set Channel Program", nil, @"setChannel")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"AFFILIATE", @"A bot or channel affiliate uses that record's "
				@"own id. This Account is the signed-in user.", identity),
		TGBSection(@"PROGRAMS", @"The catalogue is a search; connections carry "
				@"the URL Fragment pays through, not a wallet this build holds.",
				catalogue),
		TGBSection(@"CHANNEL", @"The channel page opens Telegram's parameters "
				@"and lets the owner set the commission and duration.",
				channel),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (void)finish:(BOOL)ok error:(NSString *)error title:(NSString *)title {
	self.answerLines = @[ok ? @"Telegram accepted the request."
			: (error.length ? error : @"Telegram refused that.")];
	[self rebuildSections];
	if (!ok)
		[self showMessage:self.answerLines.firstObject title:title];
}

- (void)showPage:(NSDictionary *)page title:(NSString *)title {
	NSMutableArray *lines = [NSMutableArray array];
	[lines addObject:[NSString stringWithFormat:@"Total: %@  Next: %@",
			page[@"totalCount"] ?: @0,
			[(page[@"nextOffset"] ?: @"") length]
					? page[@"nextOffset"] : @"(none)"]];
	for (NSDictionary *program in page[@"programs"] ?: @[]){
		if ([page[@"found"] boolValue]){
			[lines addObject:[NSString stringWithFormat:
					@"Bot #%@  commission %@‰  %@ month(s)",
					program[@"botUserId"] ?: @"?",
					program[@"info"][@"commissionPerMille"] ?: @0,
					program[@"info"][@"monthCount"] ?: @0]];
		} else {
			[lines addObject:[NSString stringWithFormat:
					@"Bot #%@  users %@  stars %@  %@",
					program[@"botUserId"] ?: @"?",
					program[@"userCount"] ?: @0,
					program[@"revenueStarCount"] ?: @0,
					program[@"url"] ?: @""]];
		}
	}
	NSString *body = [lines componentsJoinedByString:@"\n"];
	self.answerLines = @[body];
	[self rebuildSections];
	[self showMessage:body title:title];
}

- (void)showProgram:(NSDictionary *)program title:(NSString *)title {
	if (!program){
		[self finish:NO error:@"Telegram has no such connection." title:title];
		return;
	}
	NSString *body = [NSString stringWithFormat:
			@"%@\nBot #%@\nCommission: %@‰ for %@ month(s)\nDisconnected: %@\n"
			 @"Users: %@\nEarned: %@ stars",
			program[@"url"] ?: @"", program[@"botUserId"] ?: @"?",
			program[@"commissionPerMille"] ?: @0, program[@"monthCount"] ?: @0,
			[program[@"disconnected"] boolValue] ? @"yes" : @"no",
			program[@"userCount"] ?: @0, program[@"revenueStarCount"] ?: @0];
	self.answerLines = @[body];
	[self rebuildSections];
	[self showMessage:body title:title];
}

- (void)askField:(NSString *)action title:(NSString *)title current:(NSString *)current {
	__weak typeof(self) weakSelf = self;
	[self askText:title message:nil placeholder:current text:current
		   action:@"Save" completion:^(NSString *text){
		if ([action isEqualToString:@"kind"]){
			weakSelf.kind = text;
		} else if ([action isEqualToString:@"botId"]){
			weakSelf.botUserId = text.longLongValue;
		} else if ([action isEqualToString:@"chatId"]){
			weakSelf.chatId = text.longLongValue;
		} else if ([action isEqualToString:@"programBotId"]){
			weakSelf.programBotId = text.longLongValue;
		} else if ([action isEqualToString:@"sort"]){
			weakSelf.sort = text;
		} else if ([action isEqualToString:@"offset"]){
			weakSelf.offset = text;
		} else if ([action isEqualToString:@"limit"]){
			weakSelf.limit = text.intValue;
		} else if ([action isEqualToString:@"url"]){
			weakSelf.connectionURL = text;
		} else if ([action isEqualToString:@"commission"]){
			weakSelf.commission = text.intValue;
		} else if ([action isEqualToString:@"months"]){
			weakSelf.months = text.intValue;
		}
		[weakSelf rebuildSections];
	}];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"kind"]){
		[TGAlertSheet showChoices:@[@"This Account", @"Bot", @"Channel"]
						   title:@"Affiliate" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			weakSelf.kind = @[@"user", @"bot", @"channel"][(NSUInteger)index];
			[weakSelf rebuildSections];
		}];
		return;
	}
	if ([action isEqualToString:@"sort"]){
		[TGAlertSheet showChoices:@[@"Profitability", @"Creation Date", @"Revenue"]
						   title:@"Sort" destructiveIndex:-1 inView:self.view
						 onChoice:^(NSInteger index){
			weakSelf.sort = @[@"profitability", @"creationDate", @"revenue"][
					(NSUInteger)index];
			[weakSelf rebuildSections];
		}];
		return;
	}
	if ([action isEqualToString:@"botId"] || [action isEqualToString:@"chatId"] ||
			[action isEqualToString:@"programBotId"] ||
			[action isEqualToString:@"offset"] || [action isEqualToString:@"limit"] ||
			[action isEqualToString:@"url"] ||
			[action isEqualToString:@"commission"] ||
			[action isEqualToString:@"months"]){
		NSString *current = @"";
		NSString *title = action;
		if ([action isEqualToString:@"botId"]){ current = [NSString stringWithFormat:@"%lld", self.botUserId]; title = @"Bot User ID"; }
		if ([action isEqualToString:@"chatId"]){ current = [NSString stringWithFormat:@"%lld", self.chatId]; title = @"Channel Chat ID"; }
		if ([action isEqualToString:@"programBotId"]){ current = [NSString stringWithFormat:@"%lld", self.programBotId]; title = @"Program Bot ID"; }
		if ([action isEqualToString:@"offset"]){ current = self.offset; title = @"Offset"; }
		if ([action isEqualToString:@"limit"]){ current = [NSString stringWithFormat:@"%d", (int)self.limit]; title = @"Limit"; }
		if ([action isEqualToString:@"url"]){ current = self.connectionURL; title = @"Disconnect URL"; }
		if ([action isEqualToString:@"commission"]){ current = [NSString stringWithFormat:@"%d", (int)self.commission]; title = @"Commission Per Mille"; }
		if ([action isEqualToString:@"months"]){ current = [NSString stringWithFormat:@"%d", (int)self.months]; title = @"Month Count"; }
		[self askField:action title:title current:current];
		return;
	}

	if ([action isEqualToString:@"search"]){
		[[TGClient shared] searchAffiliateProgramsForKind:self.kind
											   botUserId:self.botUserId
												  chatId:self.chatId
												sortOrder:self.sort
												   offset:self.offset
													limit:self.limit
											   completion:^(NSDictionary *page,
															 NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Affiliate Catalogue"];
				return;
			}
			[weakSelf showPage:page title:@"Affiliate Catalogue"];
		}];
	} else if ([action isEqualToString:@"connected"]){
		[[TGClient shared] connectedAffiliateProgramsForKind:self.kind
												   botUserId:self.botUserId
													  chatId:self.chatId
													  offset:self.offset
													   limit:self.limit
												  completion:^(NSDictionary *page,
																NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Connected Programs"];
				return;
			}
			[weakSelf showPage:page title:@"Connected Programs"];
		}];
	} else if ([action isEqualToString:@"one"]){
		[[TGClient shared] connectedAffiliateProgramForKind:self.kind
												  botUserId:self.botUserId
													 chatId:self.chatId
										   programBotUserId:self.programBotId
												 completion:^(NSDictionary *program,
															  NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Connection"];
				return;
			}
			[weakSelf showProgram:program title:@"Connection"];
		}];
	} else if ([action isEqualToString:@"connect"]){
		[[TGClient shared] connectAffiliateProgramForKind:self.kind
												botUserId:self.botUserId
												   chatId:self.chatId
										 programBotUserId:self.programBotId
											   completion:^(NSDictionary *program,
															 NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Connect Program"];
				return;
			}
			[weakSelf showProgram:program title:@"Connect Program"];
		}];
	} else if ([action isEqualToString:@"disconnect"]){
		if (!self.connectionURL.length){
			[self showMessage:@"Set the connection URL first."
						title:@"Disconnect Program"];
			return;
		}
		[[TGClient shared] disconnectAffiliateProgramForKind:self.kind
												   botUserId:self.botUserId
													  chatId:self.chatId
														 url:self.connectionURL
												  completion:^(NSDictionary *program,
																NSString *error){
			if (error){
				[weakSelf finish:NO error:error title:@"Disconnect Program"];
				return;
			}
			[weakSelf showProgram:program title:@"Disconnect Program"];
		}];
	} else if ([action isEqualToString:@"channelPage"]){
		TGChannelAffiliateViewController *screen =
				[[TGChannelAffiliateViewController alloc] init];
		screen.chatId = self.chatId;
		screen.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:screen animated:YES];
	} else if ([action isEqualToString:@"searchChannel"]){
		TGChannelAffiliateViewController *screen =
				[[TGChannelAffiliateViewController alloc] init];
		screen.chatId = self.chatId;
		screen.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:screen animated:YES];
	} else if ([action isEqualToString:@"setChannel"]){
		[[TGClient shared] setChatAffiliateProgram:self.chatId
							   commissionPerMille:self.commission
									   monthCount:self.months
									   completion:^(BOOL ok, NSString *error){
			[weakSelf finish:ok error:error title:@"Channel Program"];
		}];
	}
}

@end

#pragma mark - one channel's program

@interface TGChannelAffiliateViewController ()
@property (nonatomic, copy) NSString *referrer;
@property (nonatomic, assign) int32_t commission;
@property (nonatomic, assign) int32_t months;
@property (nonatomic, strong) NSArray *answerLines;
@end

@implementation TGChannelAffiliateViewController

- (instancetype)init {
	if ((self = [super init])){
		_commission = 50;
		_months = 12;
		_answerLines = @[@"Look up a channel's affiliate link or set its parameters."];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Channel Affiliate";
	[self rebuildSections];
}

- (void)rebuildSections {
	NSMutableArray *identity = [NSMutableArray array];
	[identity addObject:TGBAction(@"Chat ID", self.chatId
			? [NSString stringWithFormat:@"%lld", self.chatId] : @"Set", @"chatId")];
	[identity addObject:TGBAction(@"Channel Username",
			self.username.length ? self.username : @"Set", @"username")];
	[identity addObject:TGBAction(@"Referrer",
			self.referrer.length ? self.referrer : @"(none)", @"referrer")];
	[identity addObject:TGBAction(@"Commission Per Mille",
			[NSString stringWithFormat:@"%d", (int)self.commission], @"commission")];
	[identity addObject:TGBAction(@"Month Count",
			[NSString stringWithFormat:@"%d", (int)self.months], @"months")];

	NSMutableArray *actions = [NSMutableArray array];
	[actions addObject:TGBAction(@"Search Channel Program", nil, @"search")];
	[actions addObject:TGBAction(@"Set Channel Program", nil, @"set")];

	NSMutableArray *answers = [NSMutableArray array];
	for (NSString *line in self.answerLines)
		[answers addObject:TGBInfo(line, nil)];

	self.sections = @[
		TGBSection(@"CHANNEL", @"The username is the one t.me resolves. The chat "
				@"id is what setChatAffiliateProgram writes.", identity),
		TGBSection(@"PROGRAM", nil, actions),
		TGBSection(@"ANSWER", nil, answers),
	];
	[self rebuild];
}

- (void)didChooseAction:(NSString *)action row:(NSDictionary *)row {
	__weak typeof(self) weakSelf = self;
	if ([action isEqualToString:@"chatId"] || [action isEqualToString:@"username"] ||
			[action isEqualToString:@"referrer"] ||
			[action isEqualToString:@"commission"] ||
			[action isEqualToString:@"months"]){
		NSString *current = @"";
		NSString *title = action;
		if ([action isEqualToString:@"chatId"]){ current = [NSString stringWithFormat:@"%lld", self.chatId]; title = @"Chat ID"; }
		if ([action isEqualToString:@"username"]){ current = self.username; title = @"Channel Username"; }
		if ([action isEqualToString:@"referrer"]){ current = self.referrer; title = @"Referrer"; }
		if ([action isEqualToString:@"commission"]){ current = [NSString stringWithFormat:@"%d", (int)self.commission]; title = @"Commission Per Mille"; }
		if ([action isEqualToString:@"months"]){ current = [NSString stringWithFormat:@"%d", (int)self.months]; title = @"Month Count"; }
		[self askText:title message:nil placeholder:current text:current
			   action:@"Save" completion:^(NSString *text){
			if ([action isEqualToString:@"chatId"]) weakSelf.chatId = text.longLongValue;
			if ([action isEqualToString:@"username"]) weakSelf.username = text;
			if ([action isEqualToString:@"referrer"]) weakSelf.referrer = text;
			if ([action isEqualToString:@"commission"]) weakSelf.commission = text.intValue;
			if ([action isEqualToString:@"months"]) weakSelf.months = text.intValue;
			[weakSelf rebuildSections];
		}];
		return;
	}
	if ([action isEqualToString:@"search"]){
		[[TGClient shared] searchChatAffiliateProgram:self.username
											referrer:self.referrer
										  completion:^(NSDictionary *chat,
													   NSString *error){
			if (error){
				weakSelf.answerLines = @[error];
				[weakSelf rebuildSections];
				[weakSelf showMessage:error title:@"Search Channel Program"];
				return;
			}
			NSString *line = [NSString stringWithFormat:@"%@  #%@",
					chat[@"title"] ?: @"?", chat[@"id"] ?: @0];
			weakSelf.answerLines = @[line];
			[weakSelf rebuildSections];
			[weakSelf showMessage:line title:@"Search Channel Program"];
		}];
	} else if ([action isEqualToString:@"set"]){
		[[TGClient shared] setChatAffiliateProgram:self.chatId
							   commissionPerMille:self.commission
									   monthCount:self.months
									   completion:^(BOOL ok, NSString *error){
			weakSelf.answerLines = @[ok ? @"Telegram accepted the request."
					: (error.length ? error : @"Telegram refused that.")];
			[weakSelf rebuildSections];
			if (!ok)
				[weakSelf showMessage:weakSelf.answerLines.firstObject
								title:@"Set Channel Program"];
		}];
	}
}

@end

// vim:ft=objc
