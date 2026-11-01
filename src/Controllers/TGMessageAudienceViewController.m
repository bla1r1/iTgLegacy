//
// TGMessageAudienceViewController.m - the people behind a reaction or a view.
//
// TDLib gives reactions through getMessageAddedReactions and readers through
// getMessageViewers; both answer people and a time, and both are refused in
// chats where Telegram keeps that list private. The list screen therefore
// owns three states: the rows, "loading", and the sentence Telegram gave for
// why there are none - never an empty table that looks broken.
//
#import "TGMessageAudienceViewController.h"
#import "TGAlertSheet.h"
#import "TGClient.h"
#import "TGFastDate.h"
#import "TGIcons.h"
#import "TGOptions.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

/// The same three shapes the chat list and the chat sheets use for a time.
static NSString *TGAudienceDate(NSTimeInterval unix) {
	char buf[TGFastDateBufferSize + 1] = {0};
	size_t len = TGFastChatDate((time_t)unix, (time_t)TGOptionNow(), buf,
								TGFastDateBufferSize);
	return len ? [[NSString alloc] initWithBytes:buf length:len encoding:NSUTF8StringEncoding]
			   : @"";
}

/// A row with its own inset avatar. The stock subtitle cell sizes the image
/// view for the picture and puts it at x 0 on iOS 6, which is what made a
/// person row look punched against the screen edge.
@interface TGAudienceCell : UITableViewCell
- (void)applyRow:(NSDictionary *)row
		  avatar:(UIImage *)avatar
		   theme:(TGTheme *)theme;
@end

@implementation TGAudienceCell {
	UIImageView *_face;
	UILabel *_name;
	UILabel *_detail;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	_face = [[UIImageView alloc] initWithFrame:CGRectZero];
	_face.contentMode = UIViewContentModeScaleAspectFill;
	_face.layer.cornerRadius = TGHalf(TGMetricListAvatar);
	_face.clipsToBounds = YES;
	[self.contentView addSubview:_face];

	_name = [[UILabel alloc] initWithFrame:CGRectZero];
	_name.font = TGFontBody();
	_name.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:_name];

	_detail = [[UILabel alloc] initWithFrame:CGRectZero];
	_detail.font = TGFontCaption();
	_detail.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:_detail];

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat h = self.contentView.bounds.size.height;
	_face.frame = CGRectMake(TGMetricPad, TGCenteredOrigin(h, TGMetricListAvatar),
							 TGMetricListAvatar, TGMetricListAvatar);

	CGFloat x = TGMetricPad + TGMetricListAvatar + TGMetricPadMedium;
	CGFloat width = MAX(0, self.contentView.bounds.size.width - x - TGMetricPadMedium);
	_name.frame = CGRectMake(x, TGMetricPadSmall, width, TGMetricLineBody);
	_detail.frame = CGRectMake(x, TGMetricPadSmall + TGMetricLineBody,
							   width, TGMetricLineCaption);
}

- (void)applyRow:(NSDictionary *)row
		  avatar:(UIImage *)avatar
		   theme:(TGTheme *)theme {
	_face.image = avatar;
	_name.text = row[@"name"] ?: @"User";
	_name.textColor = [theme primaryTextColour];
	_detail.text = row[@"detail"] ?: @"";
	_detail.textColor = [theme secondaryTextColour];
	self.backgroundColor = [theme listBackgroundColour];
	self.contentView.backgroundColor = [theme listBackgroundColour];
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	[self setNeedsLayout];
}

@end

@interface TGMessageAudienceViewController ()
@property (nonatomic, assign) TGMessageAudienceKind kind;
@property (nonatomic, assign) int64_t chatId;
@property (nonatomic, assign) int64_t messageId;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, assign) int64_t customEmojiId;
@property (nonatomic, strong) NSArray *rows;
@property (nonatomic, copy) NSString *emptyText;
/// userId -> decoded picture. Bounded by the list's own length: this screen
/// is opened for one message and never holds more people than it lists.
@property (nonatomic, strong) NSMutableDictionary *photos;
@property (nonatomic, strong) NSMutableSet *photosRequested;
@end

@implementation TGMessageAudienceViewController

- (instancetype)initWithKind:(TGMessageAudienceKind)kind
						chat:(int64_t)chatId
					 message:(int64_t)messageId
					   emoji:(NSString *)emoji
			   customEmojiId:(int64_t)customEmojiId {
	self = [super initWithStyle:UITableViewStylePlain];
	if (!self)
		return nil;
	_kind = kind;
	_chatId = chatId;
	_messageId = messageId;
	_emoji = [emoji copy];
	_customEmojiId = customEmojiId;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.photos = [NSMutableDictionary dictionary];
	self.photosRequested = [NSMutableSet set];
	self.rows = @[];
	self.emptyText = @"Loading…";

	if (self.kind == TGMessageAudienceKindReactions){
		NSString *glyph = self.emoji.length ? self.emoji : @"★";
		self.title = [NSString stringWithFormat:@"%@ Reactions", glyph];
	} else {
		self.title = @"Viewed by";
	}

	// An explicit back item, not only the system chevron: the list is also
	// opened from a URL-driven chat, where the stack is not always what the
	// bar assumes. It pops when it can and dismisses when it cannot.
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Back" style:UIBarButtonItemStylePlain
				   target:self action:@selector(closeScreen)];

	self.tableView.rowHeight = TGMetricPersonRow;
	[self applyTheme];

	// Reaction rows keep the administrator's removal that used to live in a
	// tiny action sheet: a hold asks before taking one person's reactions
	// off this message and across the chat.
	if (self.kind == TGMessageAudienceKindReactions){
		UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
				initWithTarget:self action:@selector(rowHeld:)];
		hold.minimumPressDuration = 0.55;
		[self.tableView addGestureRecognizer:hold];
	}

	[self loadPeople];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme listBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

- (void)closeScreen {
	if (self.navigationController.viewControllers.count > 1)
		[self.navigationController popViewControllerAnimated:YES];
	else
		[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - loading

- (void)loadPeople {
	if (self.kind == TGMessageAudienceKindReactions){
		NSDictionary *type = self.customEmojiId > 0
				? @{@"@type" : @"reactionTypeCustomEmoji",
					@"custom_emoji_id" : @(self.customEmojiId)}
				: @{@"@type" : @"reactionTypeEmoji", @"emoji" : self.emoji ?: @""};
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] addedReactionsOfMessage:self.messageId
											inChat:self.chatId
									  reactionType:type
											offset:nil
										completion:^(NSArray *rows, NSString *next){
			TGMessageAudienceViewController *me = weakSelf;
			if (!me)
				return;
			if (!rows.count){
				me.emptyText = @"Telegram keeps that list closed here.";
				[me.tableView reloadData];
				return;
			}
			[me showReactionRows:rows];
		}];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] viewersOfMessage:self.messageId inChat:self.chatId
							completion:^(NSArray *viewers){
		TGMessageAudienceViewController *me = weakSelf;
		if (!me)
			return;
		if (viewers.count){
			[me showViewerRows:viewers];
			return;
		}
		// No viewer list is what a private chat answers. The read date is
		// still Telegram's answer, and its reason is the honest sentence
		// when there is no date either.
		[[TGClient shared] readDateOfMessage:me.messageId inChat:me.chatId
								  completion:^(NSTimeInterval date, NSString *reason){
			TGMessageAudienceViewController *again = weakSelf;
			if (!again)
				return;
			again.emptyText = date > 0
					? [NSString stringWithFormat:@"Read %@.", TGAudienceDate(date)]
					: (reason ?: @"Telegram cannot say.");
			[again.tableView reloadData];
		}];
	}];
}

- (void)showReactionRows:(NSArray *)reactions {
	NSString *glyph = self.emoji.length ? self.emoji : @"★";
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:reactions.count];
	for (NSDictionary *r in reactions){
		NSDictionary *sender = r[@"sender"];
		int64_t userId = [sender[@"user_id"] longLongValue];
		int64_t chatId = [sender[@"chat_id"] longLongValue];
		NSString *name = userId
				? ([[TGClient shared] nameForUserId:userId] ?: @"User")
				: (chatId ? @"Another chat" : @"User");
		if ([r[@"mine"] boolValue])
			name = [NSString stringWithFormat:@"%@ (you)", name];
		NSString *when = TGAudienceDate([r[@"date"] doubleValue]);
		NSString *detail = when.length
				? [NSString stringWithFormat:@"%@  ·  %@", glyph, when]
				: glyph;
		[rows addObject:@{
			@"name"   : name ?: @"User",
			@"detail" : detail,
			@"userId" : @(userId),
			@"chatId" : @(chatId),
			@"date"   : r[@"date"] ?: @(0),
			@"sender" : sender ?: @{},
		}];
	}
	self.rows = rows;
	[self loadAvatars];
	[self.tableView reloadData];
	[self resolveMissingNames];
}

- (void)showViewerRows:(NSArray *)viewers {
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:viewers.count];
	for (NSDictionary *v in viewers){
		int64_t userId = [v[@"user_id"] longLongValue];
		NSString *name = [[TGClient shared] nameForUserId:userId] ?: @"User";
		NSString *when = TGAudienceDate([v[@"view_date"] doubleValue]);
		[rows addObject:@{
			@"name"   : name,
			@"detail" : when,
			@"userId" : @(userId),
			@"chatId" : @(0),
			@"date"   : v[@"view_date"] ?: @(0),
		}];
	}
	self.rows = rows;
	self.emptyText = nil;
	self.title = viewers.count == 1 ? @"Viewed by 1" :
			[NSString stringWithFormat:@"Viewed by %lu", (unsigned long)viewers.count];
	[self loadAvatars];
	[self.tableView reloadData];
	[self resolveMissingNames];
}

/// Names arrive with the same updateUser that carries the photo, so a row
/// whose name is not cached is asked for once; TDLib answers, the chip and
/// the row then read the same person.
- (void)resolveMissingNames {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *row in self.rows){
		int64_t userId = [row[@"userId"] longLongValue];
		if (!userId || [[TGClient shared] nameForUserId:userId].length)
			continue;
		[[TGClient shared] ensureUserName:userId completion:^{
			TGMessageAudienceViewController *me = weakSelf;
			if (me)
				[me.tableView reloadData];
		}];
	}
}

#pragma mark - avatars

- (void)loadAvatars {
	for (NSDictionary *row in self.rows)
		[self requestAvatarForUserId:[row[@"userId"] longLongValue]];
}

- (void)requestAvatarForUserId:(int64_t)userId {
	if (!userId)
		return;
	NSNumber *key = @(userId);
	if (self.photos[key] || [self.photosRequested containsObject:key])
		return;
	[self.photosRequested addObject:key];

	__weak typeof(self) weakSelf = self;
	void (^fetch)(NSNumber *) = ^(NSNumber *fileId){
		if (!fileId || fileId.integerValue <= 0)
			return;
		[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
				// The same pooled decode gate the chat's avatars use: a busy
				// list must not start one decode per row at once.
				dispatch_semaphore_wait(TGIconsDecodeGate(), DISPATCH_TIME_FOREVER);
				UIImage *photo = nil;
				@autoreleasepool {
					photo = [TGIcons decodedImageAtPath:path
										   fittingSize:CGSizeMake(TGMetricListAvatar,
																  TGMetricListAvatar)
												  fill:YES
												 scale:[UIScreen mainScreen].scale];
					if (photo)
						photo = [TGIcons roundedImage:photo
												size:CGSizeMake(TGMetricListAvatar,
																TGMetricListAvatar)
											  radius:TGHalf(TGMetricListAvatar)
											 corners:UIRectCornerAllCorners];
				}
				dispatch_semaphore_signal(TGIconsDecodeGate());
				if (!photo)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					TGMessageAudienceViewController *me = weakSelf;
					if (!me)
						return;
					me.photos[key] = photo;
					[me.tableView reloadData];
				});
			});
		}];
	};

	NSNumber *cached = [[TGClient shared] photoFileIdForUserId:userId];
	if (cached){
		fetch(cached);
		return;
	}
	[[TGClient shared] ensureUserName:userId completion:^{
		fetch([[TGClient shared] photoFileIdForUserId:userId]);
	}];
}

#pragma mark - table

/// A hold on a reactor, not a tap: removing somebody's reactions is an
/// administrator's correction, not what the list is for on a normal read.
- (void)rowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	CGPoint where = [hold locationInView:self.tableView];
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:where];
	if (!path || path.row >= (NSInteger)self.rows.count)
		return;
	NSDictionary *row = self.rows[(NSUInteger)path.row];
	NSDictionary *sender = row[@"sender"];
	if (![sender isKindOfClass:NSDictionary.class] || !sender.count)
		return;

	__weak typeof(self) weakSelf = self;
	[TGAlertSheet showConfirm:
			@"This removes everything that account reacted with on this "
			@"message and, in a group, across the chat."
							title:@"Clear Reactions"
						   action:@"Remove"
					  destructive:YES
						   inView:self.view
						onConfirm:^{
		TGMessageAudienceViewController *me = weakSelf;
		if (!me)
			return;
		[[TGClient shared] deleteReactionsOfSender:sender
										ofMessage:me.messageId
										   inChat:me.chatId];
		[[TGClient shared] deleteAllReactionsOfSender:sender
											   inChat:me.chatId];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.rows.count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.rows.count){
		static NSString *empty = @"TGAudienceEmpty";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:empty];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:empty];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.textLabel.font = TGFontBody();
			cell.textLabel.numberOfLines = 0;
		}
		TGTheme *theme = [TGTheme shared];
		cell.backgroundColor = [theme listBackgroundColour];
		cell.contentView.backgroundColor = [theme listBackgroundColour];
		cell.textLabel.text = self.emptyText ?: @"Nobody here yet.";
		cell.textLabel.textColor = [theme secondaryTextColour];
		return cell;
	}

	static NSString *reuse = @"TGAudienceCell";
	TGAudienceCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGAudienceCell alloc] initWithStyle:UITableViewCellStyleDefault
									 reuseIdentifier:reuse];

	NSDictionary *row = self.rows[indexPath.row];
	int64_t userId = [row[@"userId"] longLongValue];
	UIImage *photo = userId ? self.photos[@(userId)] : nil;
	if (!photo){
		NSString *name = row[@"name"] ?: @"?";
		NSString *initials = [TGIcons initialsForTitle:name];
		photo = [TGIcons avatarWithInitials:initials.length ? initials : @"?"
										size:TGMetricListAvatar
									colourId:userId];
	}
	[cell applyRow:row avatar:photo theme:[TGTheme shared]];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
