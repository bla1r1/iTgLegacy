//
// TGSimilarChannelsViewController.m - List of recommended similar channels.
//
#import "TGSimilarChannelsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGChatViewController.h"
#import "TGIcons.h"

@interface TGSimilarChannelsViewController ()
@property (nonatomic, strong) NSMutableDictionary *chatDetails;
@end

@implementation TGSimilarChannelsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"Similar Channels";
	self.chatDetails = [NSMutableDictionary dictionary];
	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(applyTheme)
				name:TGThemeChangedNotification object:nil];

	[self loadAllChannels];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self.tableView reloadData];
}

- (int64_t)chatIdAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.channelChatIds.count)
		return 0;
	id item = self.channelChatIds[(NSUInteger)index];
	if ([item isKindOfClass:[NSDictionary class]])
		return [item[@"id"] longLongValue];
	return [item longLongValue];
}

- (void)loadAllChannels {
	for (NSInteger i = 0; i < (NSInteger)self.channelChatIds.count; i++) {
		int64_t chatId = [self chatIdAtIndex:i];
		if (!chatId) continue;
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] request:@{
			@"@type"   : @"getChat",
			@"chat_id" : @(chatId),
		} completion:^(NSDictionary *chat){
			if (![chat isKindOfClass:[NSDictionary class]] || [chat[@"@type"] isEqualToString:@"error"])
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				TGSimilarChannelsViewController *me = weakSelf;
				if (!me) return;
				me.chatDetails[@(chatId)] = chat;
				[me.tableView reloadData];
			});
		}];
	}
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.channelChatIds.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.channelChatIds.count ? [NSString stringWithFormat:@"%lu channels", (unsigned long)self.channelChatIds.count] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *cellId = @"SimilarChannelCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
	}
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = TGFontSubhead();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	int64_t chatId = [self chatIdAtIndex:indexPath.row];
	id rawItem = self.channelChatIds[(NSUInteger)indexPath.row];
	NSDictionary *itemDict = [rawItem isKindOfClass:[NSDictionary class]] ? rawItem : nil;
	NSDictionary *chat = self.chatDetails[@(chatId)];

	NSString *title = chat[@"title"] ?: itemDict[@"title"];
	if (!title.length)
		title = [[TGClient shared] titleForChat:chatId];
	cell.textLabel.text = title.length ? title : [NSString stringWithFormat:@"Channel %lld", chatId];

	NSInteger members = [itemDict[@"members"] integerValue];
	if (members <= 0 && chat[@"member_count"]) {
		members = [chat[@"member_count"] integerValue];
	}
	if (members > 0) {
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld subscribers", (long)members];
	} else {
		cell.detailTextLabel.text = @"Channel";
	}

	NSNumber *photoFileId = chat[@"photo"][@"small"][@"id"];
	if ([photoFileId isKindOfClass:[NSNumber class]] && photoFileId.integerValue > 0) {
		__weak typeof(cell) weakCell = cell;
		[[TGClient shared] downloadFile:photoFileId.integerValue completion:^(NSString *path){
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!weakCell || !path.length) return;
				UIImage *raw = [UIImage imageWithContentsOfFile:path];
				if (raw) {
					[TGIcons setRoundedImage:raw inView:weakCell.imageView size:CGSizeMake(TGMetricListAvatar, TGMetricListAvatar) radius:TGHalf(TGMetricListAvatar)];
					[weakCell setNeedsLayout];
				}
			});
		}];
	} else {
		NSString *initials = [TGIcons initialsForTitle:title];
		cell.imageView.image = [TGIcons avatarWithInitials:initials size:TGMetricListAvatar colourId:chatId];
	}

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.channelChatIds.count)
		return;
	int64_t chatId = [self chatIdAtIndex:indexPath.row];
	[[TGClient shared] openSimilarChat:chatId fromChat:self.originalChatId];

	id rawItem = self.channelChatIds[(NSUInteger)indexPath.row];
	NSDictionary *itemDict = [rawItem isKindOfClass:[NSDictionary class]] ? rawItem : nil;
	NSDictionary *chat = self.chatDetails[@(chatId)];
	NSString *title = chat[@"title"] ?: (itemDict[@"title"] ?: [[TGClient shared] titleForChat:chatId]);
	TGChatViewController *chatVC = [[TGChatViewController alloc] init];
	chatVC.chatId = chatId;
	chatVC.chatTitle = title.length ? title : @"Channel";
	chatVC.isGroup = YES;
	chatVC.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chatVC animated:YES];
}

@end
