//
// TGCommunityViewController.m
//
#import "TGCommunityViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGIcons.h"
#import "TGChatViewController.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kCommunityPhotoSide = 72.0f;
static const CGFloat kCommunityPhotoBar  = 92.0f;

@interface TGCommunityViewController () <
		UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) int64_t communityId;
@property (nonatomic, strong) NSMutableDictionary *community;
@property (nonatomic, strong) NSDictionary *fullInfo;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UIImage *pickedPhoto;
@end

@implementation TGCommunityViewController

- (instancetype)initWithCommunity:(NSDictionary *)community {
	self = [super init];
	if (!self)
		return nil;
	_community = [community mutableCopy] ?: [NSMutableDictionary dictionary];
	_communityId = [community[@"id"] longLongValue];
	_community[@"id"] = @(_communityId);
	return self;
}

- (void)viewDidLoad {
	self.title = self.community[@"name"] ?: @"Community";
	[super viewDidLoad];
	[self buildPhotoHeader];
	[[NSNotificationCenter defaultCenter] addObserverForName:TGCommunitiesChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){ [self loadFullInfo]; }];
	[self loadFullInfo];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self rebuild];
}

- (void)applyTheme {
	[super applyTheme];
	self.photoView.backgroundColor = [[TGTheme shared] cardBackgroundColour];
}

#pragma mark - data

- (void)buildPhotoHeader {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
			self.tableView.bounds.size.width, kCommunityPhotoBar)];
	header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.photoView = [[UIImageView alloc] initWithFrame:CGRectMake(
			TGCenteredOrigin(header.bounds.size.width, kCommunityPhotoSide),
			TGMetricPadMedium, kCommunityPhotoSide, kCommunityPhotoSide)];
	self.photoView.contentMode = UIViewContentModeScaleAspectFill;
	self.photoView.clipsToBounds = YES;
	self.photoView.layer.cornerRadius = TGMetricCornerMedium;
	self.photoView.backgroundColor = [[TGTheme shared] cardBackgroundColour];
	[header addSubview:self.photoView];
	self.tableView.tableHeaderView = header;
	[self loadPhoto];
}

- (void)loadPhoto {
	if (self.pickedPhoto){
		self.photoView.image = self.pickedPhoto;
		return;
	}
	NSNumber *fileId = self.community[@"photoFileId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0)
		fileId = self.fullInfo[@"photoFileId"];
	if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0){
		NSString *name = self.community[@"name"] ?: @"C";
		NSString *initial = [TGIcons initialsForTitle:name];
		self.photoView.image = [TGIcons avatarWithInitials:initial
													 size:kCommunityPhotoSide
												 colourId:0];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
		TGCommunityViewController *me = weakSelf;
		if (!me || !path.length)
			return;
		UIImage *image = [UIImage imageWithContentsOfFile:path];
		if (image)
			me.photoView.image = image;
	}];
}

- (void)loadFullInfo {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] communityFullInfo:self.communityId
							  completion:^(NSDictionary *info, NSString *error){
		TGCommunityViewController *me = weakSelf;
		if (!me)
			return;
		if (!info){
			if (error.length)
				[me toast:error];
			return;
		}
		me.fullInfo = info;
		[me loadPhoto];
		[me rebuild];
	}];
}

- (void)rebuild {
	__weak typeof(self) weakSelf = self;
	NSDictionary *info = self.fullInfo ?: [[TGClient shared] cachedCommunityFullInfo:self.communityId];
	NSArray *chats = info[@"chats"] ?: @[];

	NSMutableArray *infoRows = [NSMutableArray array];
	[infoRows addObject:TGTier2Row(@"Name", self.community[@"name"], ^{
		[weakSelf renameCommunity];
	})];
	[infoRows addObject:TGTier2Row(@"Photo", self.pickedPhoto ? @"New photo" : nil, ^{
		[weakSelf pickPhoto];
	})];
	NSString *status = self.community[@"status"] ?: @"Member";
	[infoRows addObject:TGTier2Row(@"Your Role", status, nil)];
	NSNumber *date = self.community[@"date"];
	if ([date longLongValue] > 0){
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
		[infoRows addObject:TGTier2Row(@"Since",
				[formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:
						[date doubleValue]]], nil)];
	}
	[infoRows addObject:TGTier2Row(@"Members Can Edit Chats",
			[self.community[@"canEditChatList"] boolValue] ? @"On" : @"Off", ^{
		[weakSelf choosePermissions];
	})];

	NSMutableArray *countRows = [NSMutableArray array];
	[countRows addObject:TGTier2Row(@"Chats",
			[NSString stringWithFormat:@"%lu", (unsigned long)chats.count], nil)];
	if (info){
		[countRows addObject:TGTier2Row(@"Administrators",
				[NSString stringWithFormat:@"%ld", (long)[info[@"administratorCount"] integerValue]],
				nil)];
		[countRows addObject:TGTier2Row(@"Banned",
				[NSString stringWithFormat:@"%ld", (long)[info[@"bannedCount"] integerValue]],
				nil)];
		[countRows addObject:TGTier2Row(@"Chat Requests",
				[NSString stringWithFormat:@"%ld", (long)[info[@"addChatRequestCount"] integerValue]],
				nil)];
	}

	NSMutableArray *chatRows = [NSMutableArray array];
	for (NSDictionary *chat in chats){
		NSString *detail = [chat[@"hidden"] boolValue] ? @"Hidden" :
				([chat[@"canViewHistory"] boolValue] ? nil : @"No history");
		[chatRows addObject:TGTier2Row(chat[@"title"] ?: @"Chat", detail, ^{
			if (weakSelf.navigationController)
				[weakSelf openChat:[chat[@"chatId"] longLongValue]
							 title:chat[@"title"] ?: @""];
		})];
	}
	if (!chatRows.count){
		NSMutableDictionary *empty = TGTier2Row(@"No chats in this community", nil, nil);
		empty[TGTier2RowKind] = TGTier2KindPlain;
		[chatRows addObject:empty];
	}

	NSMutableArray *dangerRows = [NSMutableArray array];
	NSMutableDictionary *deleteRow = TGTier2Row(@"Delete Community", nil, ^{
		[weakSelf confirmDelete];
	});
	deleteRow[TGTier2RowKind] = TGTier2KindDestructive;
	[dangerRows addObject:deleteRow];

	self.sections = @[
		TGTier2Section(nil, nil, infoRows),
		TGTier2Section(@"Community", nil, countRows),
		TGTier2Section(@"Chats", nil, chatRows),
		TGTier2Section(nil, @"Deleting the community does not delete its chats.", dangerRows),
	];
	[self reloadRows];
}

#pragma mark - actions

- (void)renameCommunity {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Community Name"
					message:nil
				placeholder:@"Name"
					   text:self.community[@"name"]
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *name){
		[[TGClient shared] setCommunityName:weakSelf.communityId name:name
								 completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf toast:error ?: @"Telegram refused that name."];
				return;
			}
			weakSelf.community[@"name"] = name;
			weakSelf.title = name;
			[weakSelf rebuild];
		}];
	}];
}

- (void)choosePermissions {
	__weak typeof(self) weakSelf = self;
	BOOL current = [self.community[@"canEditChatList"] boolValue];
	NSArray *titles = @[@"Members can edit the chat list",
						@"Only administrators edit the chat list"];
	[TGAlertSheet showChoices:titles
						title:@"Community Permissions"
					  message:@"This is the only permission Telegram exposes for "
							  @"regular members of a community."
			 destructiveIndex:-1
					   inView:self.view
					 onChoice:^(NSInteger index){
		BOOL allowed = (index == 0);
		if (allowed == current)
			return;
		[[TGClient shared] setCommunityPermissions:weakSelf.communityId
									 canEditChatList:allowed
										 completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf toast:error ?: @"Telegram refused that."];
				return;
			}
			weakSelf.community[@"canEditChatList"] = @(allowed);
			[weakSelf rebuild];
		}];
	}];
}

- (void)pickPhoto {
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	UIImage *image = info[UIImagePickerControllerEditedImage] ?:
			info[UIImagePickerControllerOriginalImage];
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (!image)
		return;
	UIImage *scaled = [TGIcons decodedImage:image
								fittingSize:CGSizeMake(TGMetricUploadPhotoSide,
													   TGMetricUploadPhotoSide)
									   fill:NO scale:TGMetricScaleFull];
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"community-photo.jpg"];
	if (![UIImageJPEGRepresentation(scaled, TGCompressionQualityStandard)
			writeToFile:path atomically:YES]){
		[self toast:@"Could not prepare the picture."];
		return;
	}
	self.pickedPhoto = scaled;
	[self loadPhoto];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] setCommunityPhoto:self.communityId path:path
							  completion:^(BOOL ok, NSString *error){
		if (!ok){
			[weakSelf toast:error ?: @"Telegram refused the picture."];
			return;
		}
		[weakSelf loadFullInfo];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)confirmDelete {
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:@"The community and its member list are removed. "
							  @"Its chats stay where they are."
						 title:@"Delete Community"
						action:@"Delete"
				   destructive:YES
						inView:self.view
					 onConfirm:^{
		[[TGClient shared] deleteCommunity:weakSelf.communityId
								completion:^(BOOL ok, NSString *error){
			if (!ok){
				[weakSelf toast:error ?: @"Telegram refused that."];
				return;
			}
			[weakSelf.navigationController popViewControllerAnimated:YES];
		}];
	}];
}

- (void)openChat:(int64_t)chatId title:(NSString *)title {
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = title;
	chat.isGroup = YES;
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

@end
