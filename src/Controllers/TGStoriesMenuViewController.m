#import "TGStoriesMenuViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGStoryComposerViewController.h"
#import "TGStoryAlbumsViewController.h"
#import "TGStoryArchiveViewController.h"
#import "TGStorySettingsViewController.h"
#import "TGStoryViewerViewController.h"
#import "TGPublicStoriesViewController.h"
#import "TGLiveStoryViewController.h"

@interface TGStoriesMenuViewController ()
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *chatTitle;
@end

@implementation TGStoriesMenuViewController

- (instancetype)initWithChatId:(int64_t)chatId title:(NSString *)title {
	self = [super init];
	if (self){
		_chatId = chatId;
		_chatTitle = [title copy] ?: @"Your Story";
		self.listTitle = @"Stories";
		self.emptyText = @"Nothing to show.";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.listFooter = @"Stealth mode hides your views for the past and next "
			@"window Telegram names; it is a Premium feature and a refusal "
			@"is shown as Telegram sends it.";
	[self rebuildRows];
}

- (void)rebuildRows {
	NSMutableArray *rows = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	[rows addObject:@{@"title" : @"Add Story",
					  @"detail" : @"Photo or video, caption and privacy",
					  @"tap" : ^{ [weakSelf addStory]; }}];
	[rows addObject:@{@"title" : @"My Story",
					  @"detail" : @"Open your active stories",
					  @"tap" : ^{ [weakSelf openMyStory]; }}];
	[rows addObject:@{@"title" : @"Story Albums",
					  @"detail" : @"Create, rename, order and fill",
					  @"tap" : ^{ [weakSelf openAlbums]; }}];
	[rows addObject:@{@"title" : @"Story Archive",
					  @"detail" : @"Every story you have posted",
					  @"tap" : ^{ [weakSelf openArchive]; }}];
	[rows addObject:@{@"title" : @"Story Notifications",
					  @"detail" : @"Chats with their own story settings",
					  @"tap" : ^{ [weakSelf openNotifications]; }}];
	[rows addObject:@{@"title" : @"Public Stories",
					  @"detail" : @"Search by tag, location or venue",
					  @"tap" : ^{ [weakSelf openPublic]; }}];
	[rows addObject:@{@"title" : @"Start Live Story",
					  @"detail" : @"RTMP stream or group call",
					  @"tap" : ^{ [weakSelf openLive]; }}];
	[rows addObject:@{@"title" : @"Activate Stealth Mode",
					  @"detail" : @"Hide your views from story posters",
					  @"tap" : ^{ [weakSelf activateStealth]; }}];
	self.rows = rows;
	[self.tableView reloadData];
}

- (void)addStory {
	__weak typeof(self) weakSelf = self;
	[TGStoryComposerViewController openFromController:self chatId:self.chatId
												title:self.chatTitle onPosted:^{
		TGStoriesMenuViewController *me = weakSelf;
		if (me.onStoriesChanged)
			me.onStoriesChanged();
	}];
}

- (void)openMyStory {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] activeStoryRowForChat:self.chatId completion:^(NSDictionary *row){
		TGStoriesMenuViewController *me = weakSelf;
		if (!me)
			return;
		NSArray *infos = row[@"stories"];
		if (!infos.count){
			[TGAlertSheet showMessage:@"You have no active stories right now."
								title:@"My Story" inView:me.view];
			return;
		}
		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *info in infos)
			if ([info[@"storyId"] isKindOfClass:NSNumber.class])
				[ids addObject:info[@"storyId"]];
		TGStoryViewerViewController *viewer = [[TGStoryViewerViewController alloc]
				initWithChatId:me.chatId
						 title:me.chatTitle
					   stories:ids
					startIndex:0
					 canManage:YES];
		viewer.hidesBottomBarWhenPushed = YES;
		viewer.onStoriesChanged = ^{
			if (me.onStoriesChanged)
				me.onStoriesChanged();
		};
		[me.navigationController pushViewController:viewer animated:YES];
	}];
}

- (void)openAlbums {
	TGStoryAlbumsViewController *albums = [[TGStoryAlbumsViewController alloc]
			initWithChatId:self.chatId storyToAdd:0];
	albums.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:albums animated:YES];
}

- (void)openArchive {
	TGStoryArchiveViewController *archive = [[TGStoryArchiveViewController alloc]
			initWithChatId:self.chatId title:self.chatTitle];
	archive.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:archive animated:YES];
}

- (void)openNotifications {
	TGStorySettingsViewController *settings = [[TGStorySettingsViewController alloc] init];
	settings.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:settings animated:YES];
}

- (void)openPublic {
	TGPublicStoriesViewController *public = [[TGPublicStoriesViewController alloc]
			initWithTag:@""];
	public.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:public animated:YES];
}

- (void)openLive {
	TGLiveStoryViewController *live = [[TGLiveStoryViewController alloc]
			initWithChatId:self.chatId groupCallId:0];
	live.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:live animated:YES];
}

- (void)activateStealth {
	// Stealth mode is a Premium feature; asking first would end in a refusal.
	if (![[TGClient shared].me[@"is_premium"] boolValue]){
		[TGAlertSheet showMessage:@"Stealth mode needs Telegram Premium."
							title:@"Stealth Mode" inView:self.view];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"Activate stealth mode? Your views of stories "
			@"will be hidden from their posters for the next window."
						title:@"Stealth Mode"
					   action:@"Activate"
				  destructive:NO
					   inView:self.view
					onConfirm:^{
		TGStoriesMenuViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] activateStoryStealthModeWithCompletion:^(BOOL ok, NSString *error){
			[TGAlertSheet showMessage:ok
					? @"Stealth mode is active. Telegram is hiding your views."
					: (error ?: @"Telegram refused stealth mode.")
								title:@"Stealth Mode" inView:me.view];
		}];
	}];
}

@end
