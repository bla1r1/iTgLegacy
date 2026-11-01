#import "TGStoryComposerViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGIcons.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <MobileCoreServices/MobileCoreServices.h>

/// Telegram accepts a 1080x1920 photo and a 720x1280 video. This client only
/// re-sizes the photo; a picked video is sent as recorded and the sheet says
/// when it is not the size Telegram prefers.
static const CGFloat kStoryPhotoWidth = 1080.0f;
static const CGFloat kStoryPhotoHeight = 1920.0f;
static const CGFloat kStoryCaptionRow = 132.0f;
static const CGFloat kStoryPreviewRow = TGMetricStoryInputHeight;
static const NSInteger kStorySectionChoices = 0;
static const NSInteger kStorySectionOptions = 1;
static const NSInteger kStorySectionPublish = 2;

@interface TGStoryComposerViewController () <UIImagePickerControllerDelegate,
		UINavigationControllerDelegate, UITextViewDelegate>
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, copy) NSString *posterTitle;
@property (nonatomic, assign) int64_t targetChatId;
@property (nonatomic, copy) NSString *targetTitle;
@property (nonatomic, strong) NSArray *postChats;
@property (nonatomic, copy) NSString *mediaPath;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, assign) double videoDuration;
@property (nonatomic, strong) UIImage *previewImage;
@property (nonatomic, strong) UIImageView *previewView;
@property (nonatomic, strong) UITextView *captionView;
@property (nonatomic, assign) BOOL captionShowsPlaceholder;
@property (nonatomic, copy) NSString *privacy;
@property (nonatomic, strong) NSArray *privacyUserIds;
@property (nonatomic, assign) NSInteger activePeriod;
@property (nonatomic, assign) BOOL postedToChatPage;
@property (nonatomic, assign) BOOL protectContent;
@property (nonatomic, strong) NSArray *albumIds;
@property (nonatomic, assign) BOOL posting;
@end

@implementation TGStoryComposerViewController

- (instancetype)initWithChatId:(int64_t)chatId title:(NSString *)title {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_chatId = chatId;
		_posterTitle = [title copy] ?: @"Your Story";
		_targetChatId = chatId;
		_targetTitle = [_posterTitle copy];
		_privacy = @"everyone";
		_privacyUserIds = @[];
		_activePeriod = 86400;
		_albumIds = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.title = @"New Story";
	[[TGTheme shared] styleGroupedTable:self.tableView];
	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note){
		[weakSelf.tableView reloadData];
	}];
	[self loadPostChats];
}

/// Chats this account may post on behalf of. The own story is always first:
/// a channel that is not in the answer yet must not hide it.
- (void)loadPostChats {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatsToPostStoriesWithCompletion:^(NSArray *chats){
		TGStoryComposerViewController *me = weakSelf;
		if (!me)
			return;
		me.postChats = chats ?: @[];
		[me.tableView reloadData];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kStorySectionChoices)
		return 6;
	if (section == kStorySectionOptions)
		return 2;
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == kStorySectionChoices)
		return @"Story";
	if (section == kStorySectionOptions)
		return @"Options";
	return @"Publish";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kStorySectionChoices && indexPath.row == 0)
		return kStoryPreviewRow;
	if (indexPath.section == kStorySectionChoices && indexPath.row == 1)
		return kStoryCaptionRow;
	return TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *identifier = [NSString stringWithFormat:@"story-%ld-%ld",
			(long)indexPath.section, (long)indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:identifier];
	[[TGTheme shared] styleCell:cell];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.textLabel.font = TGFontBody();
	cell.detailTextLabel.font = TGFontSubhead();

	if (indexPath.section == kStorySectionPublish){
		if (indexPath.row == 0){
			cell.textLabel.text = self.posting ? @"Posting…" : @"Post Story";
			cell.textLabel.textColor = [[TGTheme shared] accentColour];
			cell.detailTextLabel.text = self.mediaPath ? @"" : @"Pick media first";
			cell.selectionStyle = self.mediaPath && !self.posting
					? UITableViewCellSelectionStyleBlue
					: UITableViewCellSelectionStyleNone;
		} else {
			cell.textLabel.text = @"Cancel";
			cell.textLabel.textColor = [[TGTheme shared] destructiveColour];
		}
		return cell;
	}

	if (indexPath.section == kStorySectionOptions){
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = indexPath.row == 0 ? self.postedToChatPage : self.protectContent;
		toggle.tag = indexPath.row;
		[toggle addTarget:self action:@selector(toggleChanged:)
		 forControlEvents:UIControlEventValueChanged];
		cell.textLabel.text = indexPath.row == 0
				? @"Keep on Profile" : @"Protect Content";
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	if (indexPath.row == 0){
		cell.textLabel.text = self.mediaPath ? @"Change Media" : @"Choose Photo or Video";
		cell.detailTextLabel.text = self.mediaPath
				? (self.isVideo ? @"Video" : @"Photo") : @"Required";
		if (!self.previewView){
			self.previewView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0,
					TGMetricStoryThumb, TGMetricStoryThumb)];
			self.previewView.contentMode = UIViewContentModeScaleAspectFill;
			self.previewView.clipsToBounds = YES;
			self.previewView.layer.cornerRadius = TGMetricCornerSmall;
			self.previewView.backgroundColor = [[TGTheme shared] fileTileColour];
		}
		self.previewView.image = self.previewImage;
		cell.accessoryView = self.previewView;
		return cell;
	}
	if (indexPath.row == 1){
		cell.textLabel.text = @"";
		if (!self.captionView){
			self.captionView = [[UITextView alloc] initWithFrame:CGRectZero];
			self.captionView.font = TGFontBody();
			self.captionView.backgroundColor = [UIColor clearColor];
			self.captionView.textColor = [[TGTheme shared] primaryTextColour];
			self.captionView.delegate = self;
			[self.captionView setText:@"Add a caption"];
			self.captionView.textColor = [[TGTheme shared] secondaryTextColour];
			self.captionShowsPlaceholder = YES;
		}
		// The caption is one view the controller owns; a reload may hand the
		// row a different cell, so it is moved rather than added once.
		if (self.captionView.superview != cell.contentView){
			[self.captionView removeFromSuperview];
			[cell.contentView addSubview:self.captionView];
		}
		self.captionView.frame = CGRectMake(
				TGMetricPadLarge, TGMetricPadSmall,
				tableView.bounds.size.width - TGDoubled(TGMetricPadLarge) -
				TGMetricGutter,
				kStoryCaptionRow - TGDoubled(TGMetricPadSmall));
		return cell;
	}
	if (indexPath.row == 2){
		cell.textLabel.text = @"Privacy";
		cell.detailTextLabel.text = [self privacyTitle];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	if (indexPath.row == 3){
		cell.textLabel.text = @"Active For";
		cell.detailTextLabel.text = [self activePeriodTitle];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	if (indexPath.row == 4){
		cell.textLabel.text = @"Post As";
		cell.detailTextLabel.text = self.targetTitle ?: @"My Story";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	cell.textLabel.text = @"Album IDs";
	cell.detailTextLabel.text = self.albumIds.count
			? [self.albumIds componentsJoinedByString:@", "] : @"None";
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == kStorySectionOptions)
		return;
	if (indexPath.section == kStorySectionPublish){
		if (indexPath.row == 0)
			[self postStory];
		else
			[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	if (indexPath.row == 0){
		[self pickMedia];
		return;
	}
	if (indexPath.row == 2){
		[self choosePrivacy];
		return;
	}
	if (indexPath.row == 3){
		[self chooseActivePeriod];
		return;
	}
	if (indexPath.row == 4){
		[self chooseTargetChat];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showInput:@"Album IDs"
					message:@"Comma-separated album ids, or empty for none."
				placeholder:@"12, 15"
					   text:[self.albumIds componentsJoinedByString:@", "]
					 action:@"Save"
					 inView:self.view
				   onSubmit:^(NSString *text){
		TGStoryComposerViewController *me = weakSelf;
		if (!me)
			return;
		NSMutableArray *ids = [NSMutableArray array];
		for (NSString *part in [text componentsSeparatedByString:@","]){
			NSString *trimmed = [part stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceCharacterSet]];
			if (trimmed.integerValue > 0)
				[ids addObject:@(trimmed.integerValue)];
		}
		me.albumIds = ids;
		[me.tableView reloadData];
	}];
}

#pragma mark - choices

- (void)pickMedia {
	NSArray *choices = @[@"Photo Library", @"Camera"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:@"Add to Story" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger choice){
		TGStoryComposerViewController *me = weakSelf;
		if (!me)
			return;
		UIImagePickerController *picker = [[UIImagePickerController alloc] init];
		picker.delegate = me;
		picker.sourceType = choice == 1 && [UIImagePickerController
				isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]
				? UIImagePickerControllerSourceTypeCamera
				: UIImagePickerControllerSourceTypePhotoLibrary;
		picker.mediaTypes = [UIImagePickerController
				availableMediaTypesForSourceType:picker.sourceType] ?: @[];
		picker.allowsEditing = NO;
		[me presentViewController:picker animated:YES completion:nil];
	}];
}

- (void)choosePrivacy {
	NSArray *choices = @[@"Everybody", @"My Contacts", @"Close Friends", @"Selected Users"];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:@"Who Can See This Story"
				destructiveIndex:-1 inView:self.view onChoice:^(NSInteger choice){
		TGStoryComposerViewController *me = weakSelf;
		if (!me)
			return;
		if (choice == 0){
			me.privacy = @"everyone";
			me.privacyUserIds = @[];
		} else if (choice == 1){
			me.privacy = @"contacts";
			me.privacyUserIds = @[];
		} else if (choice == 2){
			me.privacy = @"closeFriends";
			me.privacyUserIds = @[];
		} else {
			[TGAlertSheet showInput:@"Selected Users"
							message:@"Comma-separated user ids."
						placeholder:@"123, 456"
							   text:nil
							 action:@"Save"
							 inView:me.view
						 onSubmit:^(NSString *text){
				NSMutableArray *ids = [NSMutableArray array];
				for (NSString *part in [text componentsSeparatedByString:@","]){
					NSString *trimmed = [part stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceCharacterSet]];
					if (trimmed.longLongValue > 0)
						[ids addObject:@(trimmed.longLongValue)];
				}
				me.privacy = @"selected";
				me.privacyUserIds = ids;
				[me.tableView reloadData];
			}];
			return;
		}
		[me.tableView reloadData];
	}];
}

- (void)chooseActivePeriod {
	NSArray *choices = @[@"6 hours", @"12 hours", @"24 hours", @"48 hours"];
	NSArray *values = @[@21600, @43200, @86400, @172800];
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:choices title:@"Active Period" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger choice){
		TGStoryComposerViewController *me = weakSelf;
		if (!me || choice < 0 || choice >= (NSInteger)values.count)
			return;
		me.activePeriod = [values[choice] integerValue];
		[me.tableView reloadData];
	}];
}

- (void)chooseTargetChat {
	NSMutableArray *titles = [NSMutableArray arrayWithObject:@"My Story"];
	NSMutableArray *ids = [NSMutableArray arrayWithObject:@(self.chatId)];
	for (NSDictionary *chat in self.postChats){
		NSNumber *chatId = chat[@"id"];
		if (![chatId isKindOfClass:NSNumber.class] || [chatId isEqualToNumber:@(self.chatId)])
			continue;
		[titles addObject:chat[@"title"] ?: @"Chat"];
		[ids addObject:chatId];
	}
	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showChoices:titles title:@"Post Story As" destructiveIndex:-1
					   inView:self.view onChoice:^(NSInteger choice){
		TGStoryComposerViewController *me = weakSelf;
		if (!me || choice < 0 || choice >= (NSInteger)ids.count)
			return;
		me.targetChatId = [ids[choice] longLongValue];
		me.targetTitle = titles[choice];
		[me.tableView reloadData];
	}];
}

- (NSString *)privacyTitle {
	if ([self.privacy isEqualToString:@"contacts"]) return @"My Contacts";
	if ([self.privacy isEqualToString:@"closeFriends"]) return @"Close Friends";
	if ([self.privacy isEqualToString:@"selected"])
		return [NSString stringWithFormat:@"Selected (%lu)",
				(unsigned long)self.privacyUserIds.count];
	return @"Everybody";
}

- (NSString *)activePeriodTitle {
	if (self.activePeriod == 21600) return @"6 hours";
	if (self.activePeriod == 43200) return @"12 hours";
	if (self.activePeriod == 172800) return @"48 hours";
	return @"24 hours";
}

#pragma mark - the picker

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	NSString *type = info[UIImagePickerControllerMediaType];
	[picker dismissViewControllerAnimated:YES completion:nil];
	if ([type isEqualToString:(NSString *)kUTTypeMovie]){
		NSURL *url = info[UIImagePickerControllerMediaURL];
		if (!url)
			return;
		self.isVideo = YES;
		self.mediaPath = url.path;
		self.previewImage = nil;
		self.videoDuration = 0;
		AVURLAsset *asset = [AVURLAsset assetWithURL:url];
		if (asset.duration.value > 0)
			self.videoDuration = CMTimeGetSeconds(asset.duration);
		[self.tableView reloadData];
		return;
	}
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (!image)
		return;
	self.isVideo = NO;
	self.videoDuration = 0;
	self.previewImage = image;
	self.mediaPath = [self writeStoryPhoto:image];
	[self.tableView reloadData];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleChanged:(UISwitch *)toggle {
	if (toggle.tag == 0)
		self.postedToChatPage = toggle.on;
	else
		self.protectContent = toggle.on;
}

/// Telegram wants a 1080x1920 JPEG. Scaling here, not on the server, keeps a
/// 4S from uploading a 5 MP picture Telegram would reject or crop.
- (NSString *)writeStoryPhoto:(UIImage *)image {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(kStoryPhotoWidth,
			kStoryPhotoHeight), YES, 1);
	[[UIColor blackColor] setFill];
	UIRectFill(CGRectMake(0, 0, kStoryPhotoWidth, kStoryPhotoHeight));
	CGFloat scale = MIN(kStoryPhotoWidth / image.size.width,
						kStoryPhotoHeight / image.size.height);
	CGFloat width = image.size.width * scale;
	CGFloat height = image.size.height * scale;
	CGRect target = CGRectMake(TGHalf(kStoryPhotoWidth - width),
							   TGHalf(kStoryPhotoHeight - height),
							   width, height);
	[image drawInRect:target];
	UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	NSData *jpeg = UIImageJPEGRepresentation(scaled, 0.9);
	if (!jpeg.length)
		return nil;
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"tg-story.jpg"];
	return [jpeg writeToFile:path atomically:YES] ? path : nil;
}

#pragma mark - posting

- (void)postStory {
	if (self.posting)
		return;
	if (!self.mediaPath.length){
		[TGAlertSheet showMessage:@"Choose a photo or a video first."
							title:@"New Story" inView:self.view];
		return;
	}
	self.posting = YES;
	[self.tableView reloadData];
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] canPostStoryInChat:self.targetChatId
							   completion:^(NSDictionary *answer){
		TGStoryComposerViewController *me = weakSelf;
		if (!me)
			return;
		if (![answer[@"ok"] boolValue]){
			me.posting = NO;
			[me.tableView reloadData];
			[TGAlertSheet showMessage:answer[@"reason"] ?: @"Telegram refused that."
								title:@"New Story" inView:me.view];
			return;
		}
		NSString *caption = me.captionView.text ?: @"";
		if (me.captionShowsPlaceholder)
			caption = @"";
		[[TGClient shared] postStoryToChat:me.targetChatId
									  path:me.mediaPath
								   isVideo:me.isVideo
								  duration:me.videoDuration
								   caption:caption
								   privacy:me.privacy
								   userIds:me.privacyUserIds
							 activePeriod:me.activePeriod
						  postedToChatPage:me.postedToChatPage
							protectContent:me.protectContent
								  albumIds:me.albumIds
								completion:^(NSDictionary *story, NSString *error){
			me.posting = NO;
			[me.tableView reloadData];
			if (!story){
				[TGAlertSheet showMessage:error ?: @"Telegram refused the story."
									title:@"New Story" inView:me.view];
				return;
			}
			if (me.onPosted)
				me.onPosted();
			[me.navigationController popViewControllerAnimated:YES];
		}];
	}];
}

#pragma mark - caption placeholder

- (void)textViewDidBeginEditing:(UITextView *)textView {
	if (self.captionShowsPlaceholder){
		textView.text = @"";
		textView.textColor = [[TGTheme shared] primaryTextColour];
		self.captionShowsPlaceholder = NO;
	}
}

- (void)textViewDidEndEditing:(UITextView *)textView {
	if (!textView.text.length){
		textView.text = @"Add a caption";
		textView.textColor = [[TGTheme shared] secondaryTextColour];
		self.captionShowsPlaceholder = YES;
	}
}

@end
