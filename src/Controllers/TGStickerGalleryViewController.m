//
// TGStickerGalleryViewController.m - see the header.
//
#import "TGStickerGalleryViewController.h"
#import "TGAlertSheet.h"
#import "TGStyle.h"
#import "TGTheme.h"

@implementation TGStickerGalleryViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.stickers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *cellId = @"sticker";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:cellId];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	NSDictionary *sticker = self.stickers[(NSUInteger)indexPath.row];
	NSString *emoji = [sticker[@"emoji"] length] ? sticker[@"emoji"] : @"Sticker";
	cell.textLabel.text = emoji;
	cell.textLabel.font = TGFontRow();

	NSMutableArray *parts = [NSMutableArray array];
	if (sticker[@"fileId"])
		[parts addObject:[NSString stringWithFormat:@"file %@", sticker[@"fileId"]]];
	if ([sticker[@"setId"] longLongValue])
		[parts addObject:[NSString stringWithFormat:@"set %@", sticker[@"setId"]]];
	if ([sticker[@"customEmojiId"] longLongValue])
		[parts addObject:[NSString stringWithFormat:@"emoji id %@",
				sticker[@"customEmojiId"]]];
	cell.detailTextLabel.text = [parts componentsJoinedByString:@"  ·  "];
	cell.detailTextLabel.font = TGFontCaption();
	TGTheme *theme = [TGTheme shared];
	cell.backgroundColor = [theme listBackgroundColour];
	cell.textLabel.textColor = [theme primaryTextColour];
	cell.detailTextLabel.textColor = [theme secondaryTextColour];
	return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.stickers.count ? self.title : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.stickers.count)
		return;
	NSDictionary *sticker = self.stickers[(NSUInteger)indexPath.row];
	NSString *emoji = [sticker[@"emoji"] length] ? sticker[@"emoji"] : @"Sticker";
	NSString *message = [NSString stringWithFormat:
			@"Emoji: %@\nFile: %@\nSet: %@\nCustom emoji id: %@",
			emoji, sticker[@"fileId"] ?: @"-", sticker[@"setId"] ?: @"-",
			sticker[@"customEmojiId"] ?: @"-"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:@[@"Copy File ID", @"Done"]
						title:emoji
						message:message
			 destructiveIndex:-1
					   inView:weakSelf.view
					 onChoice:^(NSInteger index){
		if (index == 0 && sticker[@"fileId"])
			[UIPasteboard generalPasteboard].string =
					[sticker[@"fileId"] stringValue];
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	if (!self.stickers.count && self.emptyText.length)
		self.tableView.backgroundView = ({
			UILabel *label = [[UILabel alloc] init];
			label.text = self.emptyText;
			label.font = TGFontBody();
			label.textAlignment = NSTextAlignmentCenter;
			label.numberOfLines = 2;
			label.textColor = [TGTheme shared].secondaryTextColour;
			label;
		});
	else
		self.tableView.backgroundView = nil;
	[self.tableView reloadData];
}

@end
