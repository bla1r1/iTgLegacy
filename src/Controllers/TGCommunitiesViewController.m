//
// TGCommunitiesViewController.m
//
#import "TGCommunitiesViewController.h"
#import "TGCommunityViewController.h"
#import "TGClient.h"
#import "TGAlertSheet.h"

@implementation TGCommunitiesViewController

- (void)viewDidLoad {
	self.title = @"Communities";
	[super viewDidLoad];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGCommunitiesChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){ [self rebuild]; }];
	[self rebuild];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuild];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;
	NSMutableArray *rows = [NSMutableArray array];
	NSArray *communities = [TGClient shared].communities;
	for (NSDictionary *community in communities){
		int64_t communityId = [community[@"id"] longLongValue];
		NSString *detail = community[@"status"];
		if (![community[@"haveAccess"] boolValue])
			detail = @"No access";
		NSMutableDictionary *row = TGTier2Row(community[@"name"] ?: @"Community",
											  detail, ^{
			TGCommunityViewController *screen =
					[[TGCommunityViewController alloc] initWithCommunity:community];
			screen.hidesBottomBarWhenPushed = YES;
			[weakSelf.navigationController pushViewController:screen animated:YES];
		});
		row[@"communityId"] = @(communityId);
		[rows addObject:row];
	}
	if (!rows.count){
		NSMutableDictionary *empty = TGTier2Row(@"No communities yet", nil, nil);
		empty[TGTier2RowKind] = TGTier2KindPlain;
		[rows addObject:empty];
	}

	NSMutableArray *createRows = [NSMutableArray array];
	[createRows addObject:TGTier2Action(@"New Community", ^{ [weakSelf createCommunity]; })];

	self.sections = @[
		TGTier2Section(nil,
				@"A community is a set of channels and groups with one name, "
				@"photo and member list.", rows),
		TGTier2Section(nil,
				@"Telegram creates the community around one chat this account "
				@"owns. Basic groups are upgraded to supergroups.", createRows),
	];
	[self reloadRows];
}

- (void)createCommunity {
	TGClient *client = [TGClient shared];
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSDictionary *chat in client.chats){
		if (![chat[@"isGroup"] boolValue])
			continue;
		NSString *title = chat[@"title"];
		if (!title.length)
			continue;
		[titles addObject:title];
		[ids addObject:chat[@"id"]];
	}
	if (!titles.count){
		[self toast:@"No group or channel to build a community around."];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles
						title:@"Community Chat"
					  message:@"The community is created around this chat."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		if (index < 0 || index >= (NSInteger)ids.count)
			return;
		int64_t chatId = [ids[index] longLongValue];
		[TGAlertSheet showInput:@"New Community"
						message:@"The name every member sees."
					placeholder:@"Community name"
						   text:nil
						 action:@"Create"
						 inView:weakSelf.view
					   onSubmit:^(NSString *name){
			[TGAlertSheet showChoices:@[@"Visible to members", @"Hidden from members"]
								title:@"Chat Visibility"
							  message:@"A hidden chat is visible only to community administrators."
					 destructiveIndex:-1
							   inView:weakSelf.view
							 onChoice:^(NSInteger pick){
				BOOL hidden = (pick == 1);
				[[TGClient shared] createCommunity:name chatId:chatId hidden:hidden
										completion:^(int64_t communityId, NSString *error){
					if (!communityId){
						[weakSelf toast:error ?: @"Telegram refused that."];
						return;
					}
					NSDictionary *row = @{
						@"id"         : @(communityId),
						@"name"       : name,
						@"haveAccess" : @YES,
						@"status"     : @"Owner",
					};
					TGCommunityViewController *screen =
							[[TGCommunityViewController alloc] initWithCommunity:row];
					screen.hidesBottomBarWhenPushed = YES;
					[weakSelf.navigationController pushViewController:screen animated:YES];
				}];
			}];
		}];
	}];
}

@end
