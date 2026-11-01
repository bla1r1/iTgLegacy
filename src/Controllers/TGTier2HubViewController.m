//
// TGTier2HubViewController.m
//
#import "TGTier2HubViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGCommunitiesViewController.h"
#import "TGQuickRepliesViewController.h"
#import "TGAiComposeViewController.h"

@implementation TGTier2HubViewController

- (void)viewDidLoad {
	self.title = @"Communities and Replies";
	[super viewDidLoad];
	__weak typeof(self) weakSelf = self;
	NSArray *names = @[TGCommunitiesChangedNotification,
					   TGQuickRepliesChangedNotification,
					   TGSuggestedActionsChangedNotification];
	for (NSString *name in names){
		[[NSNotificationCenter defaultCenter] addObserverForName:name
				object:nil queue:[NSOperationQueue mainQueue]
			 usingBlock:^(NSNotification *note){
			[weakSelf rebuild];
		}];
	}
	[self rebuild];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self rebuild];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;
	TGClient *client = [TGClient shared];

	NSString *communityDetail = client.communities.count
			? [NSString stringWithFormat:@"%lu", (unsigned long)client.communities.count]
			: nil;
	NSString *replyDetail = client.quickReplyShortcuts.count
			? [NSString stringWithFormat:@"%lu", (unsigned long)client.quickReplyShortcuts.count]
			: nil;

	NSMutableArray *toolRows = [NSMutableArray array];
	[toolRows addObject:TGTier2Row(@"Communities", communityDetail, ^{
		TGCommunitiesViewController *screen = [[TGCommunitiesViewController alloc] init];
		screen.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:screen animated:YES];
	})];
	[toolRows addObject:TGTier2Row(@"Saved Replies", replyDetail, ^{
		TGQuickRepliesViewController *screen = [[TGQuickRepliesViewController alloc] init];
		screen.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:screen animated:YES];
	})];
	[toolRows addObject:TGTier2Row(@"AI Compose", nil, ^{
		TGAiComposeViewController *screen = [[TGAiComposeViewController alloc] init];
		screen.hidesBottomBarWhenPushed = YES;
		[weakSelf.navigationController pushViewController:screen animated:YES];
	})];

	NSMutableArray *sections = [NSMutableArray array];
	[sections addObject:TGTier2Section(nil,
			@"Communities group channels and groups this account owns. "
			@"Saved replies are the messages a shortcut sends.",
			toolRows)];

	NSArray *actions = client.suggestedActions;
	NSMutableArray *actionRows = [NSMutableArray array];
	for (NSDictionary *row in actions){
		NSString *title = row[@"title"] ?: @"Suggested Action";
		NSDictionary *action = row[@"action"];
		[actionRows addObject:TGTier2Row(title, @"Hide", ^{
			[weakSelf hideAction:action name:title];
		})];
	}
	NSString *footer = actions.count
			? @"These are Telegram's own suggestions. Hiding one asks Telegram to stop showing it."
			: @"Nothing suggested right now. Telegram sends suggestions when an account is missing a setting.";
	[sections addObject:TGTier2Section(@"Suggested Actions", footer, actionRows)];
	self.sections = sections;
	[self reloadRows];
}

- (void)hideAction:(NSDictionary *)action name:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] hideSuggestedAction:action completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused that."];
			return;
		}
		[weakSelf rebuild];
	}];
}

@end
