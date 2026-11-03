//
// TGDevModeViewController.m
//
#import "TGDevModeViewController.h"
#import "TGChatViewController.h"
#import "TGDevShowcase.h"
#import "TGNavController.h"
#import "TGSettingsViewController.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"

/// The fixture chats. They live here and not in the chat list, so a real account's
/// list is only that account's.
@interface TGDevChatsViewController : UITableViewController
@property (nonatomic, strong) NSArray *chats;
@end

@implementation TGDevChatsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Dev Chats";
	self.chats = [TGDevShowcase allShowcaseChats];
	[self applyTheme];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme)
												 name:TGThemeChangedNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chat"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:@"chat"];
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.text = self.chats[indexPath.row][@"title"];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *row = self.chats[indexPath.row];
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = [row[@"id"] longLongValue];
	chat.chatTitle = row[@"title"];
	chat.isGroup = [row[@"isGroup"] boolValue];
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

@end

@implementation TGDevModeViewController

+ (void)presentFrom:(UIViewController *)host {
	if (host.presentedViewController)
		return;
	[host presentViewController:[[self alloc] init] animated:YES completion:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	TGDevChatsViewController *chats = [[TGDevChatsViewController alloc]
			initWithStyle:UITableViewStyleGrouped];
	TGSettingsViewController *settings = [[TGSettingsViewController alloc] init];
	settings.page = TGSettingsPageDebug;

	UINavigationController *chatsNC = [[TGNavController alloc] initWithRootViewController:chats];
	chatsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Dev Chats"
													   image:[TGIcons chats] tag:0];
	UINavigationController *settingsNC = [[TGNavController alloc] initWithRootViewController:settings];
	settingsNC.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Dev Settings"
														  image:[TGIcons settings] tag:1];
	for (UIViewController *root in @[chats, settings])
		root.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Close" style:UIBarButtonItemStylePlain
					   target:self action:@selector(closeTapped)];
	self.viewControllers = @[chatsNC, settingsNC];
	[self applyTheme];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme)
												 name:TGThemeChangedNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	[[TGTheme shared] styleTabBar:self.tabBar];
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
