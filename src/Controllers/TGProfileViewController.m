#import "TGProfileViewControllerInternal.h"
#import "TGClientInternal.h"
#import "TGStyle.h"
#import "TGAlertSheet.h"
#import "TGMemberCell.h"
#import "TGGroupMemberActions.h"
#import "TGProfileAudioViewController.h"
#import "TGProfileTrackCell.h"
#import "TGMusicPlayer.h"
#import "TGChatViewController.h"
#import "TGSimilarChannelsViewController.h"
#import "TGCommunityViewController.h"
#import "TGDMTopicsViewController.h"
#import "UIImage+WebP.h"
#import <AVFoundation/AVFoundation.h>

/// Flattened messages carry a unix date, not a formatted stamp; the shared
/// lists want a short one beside each row.
/// A file's size as the row prints it. The file info sheet has its own copy;
/// this one is only the compact line under a name here.
static NSString *TGProfileFileSize(NSNumber *bytes) {
	long long value = [bytes longLongValue];
	if (value <= 0)
		return nil;
	if (value < 1024)
		return [NSString stringWithFormat:@"%lld B", value];
	if (value < 1024 * 1024)
		return [NSString stringWithFormat:@"%.0f KB", value / 1024.0];
	return [NSString stringWithFormat:@"%.1f MB", value / (1024.0 * 1024.0)];
}

static NSString *TGProfileDurationText(NSNumber *seconds) {
	NSInteger value = [seconds integerValue];
	if (value <= 0)
		return nil;
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(value / 60), (long)(value % 60)];
}

static NSString *TGProfileShortDate(NSNumber *date) {
	if (![date isKindOfClass:NSNumber.class] || !date.doubleValue)
		return nil;
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	}
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date.doubleValue]];
}

/// The gift glyph: the sticker's own emoji drawn large. Every gift cell
/// starts here, and the sticker thumbnail replaces the image once the
/// download lands - until then the row is never blank (B5).
static UIImage *TGGiftGlyph(NSString *emoji) {
	if (!emoji.length)
		emoji = @"🎁";
	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
	NSString *key = [emoji stringByAppendingFormat:@"@40"];
	UIImage *cached = [cache objectForKey:key];
	if (cached)
		return cached;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(kGiftTile, kGiftTile), NO, 0);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	[emoji drawInRect:CGRectMake(kGiftTileInset, kGiftTileInset,
								 kGiftTile - TGDoubled(kGiftTileInset),
								 kGiftTile - TGDoubled(kGiftTileInset))
			 withFont:TGFontEmoji()
		lineBreakMode:NSLineBreakByClipping
		   alignment:NSTextAlignmentCenter];
#pragma clang diagnostic pop
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	[cache setObject:img forKey:key];
	return img;
}

/// The bar under the selected tab, and the room a text row leaves at its sides.
static const CGFloat kMediaTabLine = 2.0f;
static NSString *TGProfileUserName(NSDictionary *user) {
	if (!user) return @"";
	NSString *first = user[@"first_name"] ?: @"";
	NSString *last = user[@"last_name"] ?: @"";
	if (first.length && last.length)
		return [NSString stringWithFormat:@"%@ %@", first, last];
	return first.length ? first : last;
}

static const CGFloat kDetailInset = TGMetricPadWide;

static const CGFloat kMusicStripInset = TGMetricPadMedium;
static const CGFloat kMusicTitleTop   = TGMetricPadSmall;
static const CGFloat kMusicArtistTop  = TGMetricPadSmall + TGMetricLineMicro;
static const CGFloat kMusicChevronSide = TGMetricGiftStar;

@interface TGProfileDetailCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation TGProfileDetailCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])){
		_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
		_iconView.contentMode = UIViewContentModeScaleAspectFit;
		_iconView.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_iconView];

		_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_titleLabel.font = TGFontMeta();
		_titleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_titleLabel];

		_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_subtitleLabel.font = TGFontBody();
		_subtitleLabel.numberOfLines = 0;
		_subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
		_subtitleLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_subtitleLabel];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = self.contentView.bounds.size.width;
	CGFloat left = TGMetricPadLarge;
	if (self.iconView.image) {
		self.iconView.frame = CGRectMake(left, TGMetricPadMedium, TGMetricMenuGlyph, TGMetricMenuGlyph);
		left += TGMetricMenuGlyph + TGMetricPadMedium;
	} else {
		self.iconView.frame = CGRectZero;
	}
	CGFloat rightMargin = (self.accessoryType != UITableViewCellAccessoryNone)
			? (TGMetricMenuGlyph + TGMetricPadMedium) : TGMetricPadLarge;
	CGFloat textWidth = width - left - rightMargin;
	if (textWidth < 50.0f) textWidth = 50.0f;

	CGFloat y = TGMetricPadSmall;
	if (self.titleLabel.text.length) {
		self.titleLabel.frame = CGRectMake(left, y, textWidth, TGMetricLineCaption);
		y += TGMetricLineCaption + TGMetricPadTiny;
	} else {
		self.titleLabel.frame = CGRectZero;
	}

	CGSize valSize = [self.subtitleLabel.text sizeWithFont:self.subtitleLabel.font
										constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX)
											lineBreakMode:NSLineBreakByWordWrapping];
	self.subtitleLabel.frame = CGRectMake(left, y, textWidth, ceilf(valSize.height));
}

@end

@implementation TGProfileViewController

- (instancetype)initWithChatId:(int64_t)chatId userId:(int64_t)userId title:(NSString *)title {
	if ((self = [super initWithStyle:UITableViewStyleGrouped])){
		_chatId = chatId;
		_userId = (chatId < 0) ? 0 : userId;
		_name = title ?: @"";
		_details = @[];
		_photos = @[];
		_files = @[];
		_thumbnailsRequested = [NSMutableSet set];
		_loadedMediaKinds = [NSMutableSet set];
		_loadingMediaKinds = [NSMutableSet set];
		_mediaCounts = [NSMutableDictionary dictionary];
		_coverImages = [NSMutableDictionary dictionary];
		_memberCount = 0;
		_canManage = NO;
		_canInvite = NO;
	}
	return self;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
							  duration:(NSTimeInterval)duration {
	[super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
	// grid tiles and cached cells are laid out to the width at build time;
	// caches pinned to the old width would keep portrait frames spanning a
	// rotated screen, so drop them and let the table re-ask its metrics.
	self.storyGridCellCache = nil;
	self.mediaGridCacheContent = nil;
	[self.tableView reloadData];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Your own profile carries no title, as in Telegram: the name under the
	// picture already says whose it is.
	self.title = self.isOwnProfile ? @"" : @"Info";
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	[self applyTheme];
	[self updateNavigationItem];

	// The status line listens to the network too (B4): a profile opened
	// offline used to freeze at its captured last-seen.
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(statusLabelOwnerChanged:)
			name:TGConnectionStateChangedNotification object:nil];
	[nc addObserver:self selector:@selector(statusLabelOwnerChanged:)
			name:TGUserStatusChangedNotification object:nil];
	// A bio edited elsewhere, a member added to the group: the full record
	// arrives as its own update and this screen used to need a reopen.
	[nc addObserver:self selector:@selector(fullInfoChanged:)
			name:TGFullInfoChangedNotification object:nil];
	// Someone joined, was promoted or removed, or asked to join: the member
	// rows and the request count are both read in loadDetails.
	[nc addObserver:self selector:@selector(membersChanged:)
			name:TGChatMembersChangedNotification object:nil];

	[self buildHeader];
	[self loadDetails];
	[self loadMedia];

	// A tap opens who they are; a hold keeps the member sheet that used to
	// be the only thing a tap did. Cancelling touches on recognition stops
	// the lift after a hold from also selecting the row underneath.
	UILongPressGestureRecognizer *memberHold = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(memberRowHeld:)];
	memberHold.minimumPressDuration = 0.5;
	memberHold.cancelsTouchesInView = YES;
	[self.tableView addGestureRecognizer:memberHold];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserverForName:TGThemeChangedNotification
			object:nil queue:[NSOperationQueue mainQueue]
		 usingBlock:^(NSNotification *note) {
		[weakSelf applyTheme];
		[weakSelf buildHeader];
		[weakSelf.tableView reloadData];
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self applyTheme];
	[self updateNavigationItem];
	if (self.isOwnProfile){
		NSString *ownName = TGProfileUserName([TGClient shared].me);
		if (ownName.length)
			self.name = ownName;
		[self loadDetails];
	}
}

- (void)updateNavigationItem {
	if (self.isOwnProfile){
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithTitle:@"Edit"
						style:UIBarButtonItemStylePlain
					   target:self
					   action:@selector(editProfileTapped)];
	} else {
		self.navigationItem.rightBarButtonItem = nil;
	}
}

- (void)editProfileTapped {
	TGEditProfileViewController *edit = [[TGEditProfileViewController alloc] init];
	edit.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:edit animated:YES];
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.tableView.backgroundColor = [theme groupedBackgroundColour];
	self.tableView.separatorColor = [theme separatorColour];
	[theme styleNavigationBar:self.navigationController.navigationBar];
}

/// The profile as the current client draws it: a large picture centred, the
/// name and status under it, and a row of tiles for the things you actually do
/// here. The coloured block this replaced is the old design; everything since
/// Downloads decode off the main thread and the circle is baked into the
/// bitmap, so the scrolling header never carries a masked layer.
- (void)applyAvatarImageAtPath:(NSString *)path {
	if (!path.length)
		return;
	CGFloat side = TGMetricProfileAvatar;
	CGFloat scale = [UIScreen mainScreen].scale;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		UIImage *image = [TGIcons decodedImageAtPath:path
										 fittingSize:CGSizeMake(side, side)
												fill:YES
											   scale:scale];
		UIImage *round = [TGIcons roundedImage:image
										 size:CGSizeMake(side, side)
									   radius:TGHalf(side)
									  corners:UIRectCornerAllCorners];
		if (!round)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			weakSelf.avatarImage = round;
			weakSelf.avatarView.image = round;
		});
	});
}

- (void)buildMusicStripIn:(UIView *)header atY:(CGFloat)y {
	NSDictionary *track = self.firstProfileAudio;
	if (!track)
		return;
	TGTheme *theme = [TGTheme shared];
	CGFloat width = header.bounds.size.width;
	UIView *band = [[UIView alloc] initWithFrame:
			CGRectMake(kMusicStripInset, y,
					width - TGDoubled(kMusicStripInset), kMusicStripHeight)];
	band.backgroundColor = [theme cardBackgroundColour];
	band.layer.cornerRadius = TGMetricCornerControl;
	[header addSubview:band];

	UIImageView *glyph = [[UIImageView alloc] initWithFrame:
			CGRectMake(TGMetricPadMedium, TGCenteredOrigin(kMusicStripHeight, kMusicStripGlyph),
					kMusicStripGlyph, kMusicStripGlyph)];
	glyph.image = [TGIcons glyphNamed:@"music" colour:[theme accentColour]
								side:kMusicStripGlyph];
	glyph.contentMode = UIViewContentModeScaleAspectFit;
	[band addSubview:glyph];

	CGFloat textX = TGMetricPadMedium + kMusicStripGlyph + TGMetricPad;
	CGFloat textW = band.bounds.size.width - textX - TGMetricPadMedium - kMusicChevronSide
			- TGMetricPad;
	UILabel *title = [[UILabel alloc] initWithFrame:
			CGRectMake(textX, kMusicTitleTop, textW, TGMetricLineCaption)];
	title.font = TGFontMetaStrong();
	title.textColor = [theme accentColour];
	title.backgroundColor = [UIColor clearColor];
	title.lineBreakMode = NSLineBreakByTruncatingTail;
	title.text = track[@"title"] ?: @"Audio";
	[band addSubview:title];

	UILabel *artist = [[UILabel alloc] initWithFrame:
			CGRectMake(textX, kMusicArtistTop, textW, TGMetricLineCaption)];
	artist.font = TGFontMeta();
	artist.textColor = [theme secondaryTextColour];
	artist.backgroundColor = [UIColor clearColor];
	artist.lineBreakMode = NSLineBreakByTruncatingTail;
	artist.text = [track[@"performer"] length] ? track[@"performer"] : @"Unknown artist";
	[band addSubview:artist];

	UIImageView *chevron = [[UIImageView alloc] initWithFrame:
			CGRectMake(band.bounds.size.width - TGMetricPadMedium - kMusicChevronSide,
					TGCenteredOrigin(kMusicStripHeight, kMusicChevronSide),
					kMusicChevronSide, kMusicChevronSide)];
	chevron.image = [TGIcons glyphNamed:@"forward" colour:[theme secondaryTextColour]
								   side:kMusicChevronSide];
	chevron.contentMode = UIViewContentModeScaleAspectFit;
	[band addSubview:chevron];

	// The whole band is the button, including the glyph and the two lines.
	UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
	tap.frame = band.bounds;
	[tap addTarget:self action:@selector(musicStripTapped)
		  forControlEvents:UIControlEventTouchUpInside];
	[band addSubview:tap];
}

- (void)musicStripTapped {
	TGProfileAudioViewController *audio = [[TGProfileAudioViewController alloc] init];
	audio.userId = self.userId;
	audio.subjectTitle = self.name.length ? self.name : @"Profile Audio";
	audio.autoplay = YES;
	audio.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:audio animated:YES];
}

- (void)buildHeader {
	CGFloat width = self.view.bounds.size.width;
	CGFloat side = TGMetricProfileAvatar;
	// Header height is the same stack the constants below lay out: picture,
	// name, status, then the action plate, then the saved-music strip when
	// the account has one.
	CGFloat height = kAvatarTop + side + kActionsTop + kActionTile + TGMetricPadMedium;
	if (self.firstProfileAudio)
		height += kMusicStripHeight + TGMetricPad;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	header.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

	self.avatarView = [[UIImageView alloc] initWithFrame:
			CGRectMake(TGCenteredOrigin(width, side), kAvatarTop, side, side)];
	self.avatarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
			UIViewAutoresizingFlexibleRightMargin;
	// The circle is in the bitmap. A corner radius plus clipsToBounds on a
	// view inside a scrolling table header is a mask the A4 repaints on every
	// scroll step; TGIcons bakes the same circle once.
	self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
	self.avatarView.opaque = NO;
	self.avatarView.backgroundColor = [UIColor clearColor];
	NSString *initials = [TGIcons initialsForTitle:self.name];
	// The header is rebuilt on every answer that changes a mark or a tile. Going
	// back to the initials each time looked like the photo never finished loading.
	self.avatarView.image = self.avatarImage ?: [TGIcons avatarWithInitials:initials
												   size:side
											   colourId:self.userId ?: self.chatId];
	[header addSubview:self.avatarView];

	// The picture is an address to what the account wears: tapping it shows
	// every photo history this profile still holds.
	UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(avatarTapped)];
	[self.avatarView addGestureRecognizer:avatarTap];
	self.avatarView.userInteractionEnabled = YES;

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(kHeaderTextInset, kAvatarTop + side + kNameTop,
					width - TGDoubled(kHeaderTextInset), TGMetricLineTitle)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = self.name;
	nameLabel.font = TGFontTitle();
	nameLabel.textAlignment = NSTextAlignmentCenter;
	nameLabel.backgroundColor = [UIColor clearColor];
	nameLabel.textColor = [[TGTheme shared] primaryTextColour];
	[header addSubview:nameLabel];
	// The marks sit after the centred name. Both are plain images, never masks.
	CGFloat markX = TGHalf(width) + TGHalf(MIN([self.name sizeWithFont:TGFontTitle()].width,
			nameLabel.bounds.size.width)) + TGMetricPadSmall;
	CGFloat markY = kAvatarTop + side + kNameTop + TGCenteredOrigin(TGMetricLineTitle, kNameBadge);
	for (UIImage *mark in @[self.isVerified ? [TGIcons verifiedBadge] : [NSNull null],
							self.emojiStatusImage ?: (id)[NSNull null]]){
		if (![mark isKindOfClass:UIImage.class])
			continue;
		UIImageView *badge = [[UIImageView alloc] initWithFrame:
				CGRectMake(markX, markY, kNameBadge, kNameBadge)];
		badge.image = mark;
		badge.contentMode = UIViewContentModeScaleAspectFit;
		[header addSubview:badge];
		markX += kNameBadge + TGMetricPadTiny;
	}

	self.statusLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(kHeaderTextInset, kAvatarTop + side + kStatusTop,
					width - TGDoubled(kHeaderTextInset), TGMetricLineBody)];
	self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.statusLabel.font = TGFontSubhead();
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.statusLabel.backgroundColor = [UIColor clearColor];
	[header addSubview:self.statusLabel];

	[self buildActionsIn:header atY:(kAvatarTop + side + kActionsTop)];

	if (self.firstProfileAudio)
		[self buildMusicStripIn:header
						  atY:(kAvatarTop + side + kActionsTop + kActionTile + TGMetricPad)];

	// The status line listens to presence too: a status arriving while the
	// profile is open refreshes the line (B4).
	if ([self showsSavedMessages]){
		self.statusLabel.text = nil;
	} else if (self.isOwnProfile){
		// You are using the app, so to yourself you are online. The server's
		// last-seen for your own account lags behind and read like a stranger's.
		self.restingStatus = @"online";
		self.statusLabel.textColor = [[TGTheme shared] accentColour];
		[self statusLabelOwnerChanged:nil];
	} else if (self.userId){
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] statusForUser:self.userId completion:^(NSString *status){
			if (!status.length)
				return;
			if (!weakSelf.isBot)
				weakSelf.restingStatus = status;
			[weakSelf statusLabelOwnerChanged:nil];
		}];
	} else {
		// The count is known from chatProfile on most opens; only fall back
		// to the member request while that answer is still on its way.
		[self updateGroupStatus];
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] memberCountForChat:self.chatId completion:^(NSInteger count){
			if (count > 0 && weakSelf.memberCount <= 0){
				weakSelf.memberCount = count;
				[weakSelf updateGroupStatus];
			}
		}];
	}

	self.tableView.tableHeaderView = header;
	self.tableView.backgroundColor = [[TGTheme shared] groupedBackgroundColour];

	NSNumber *fileId = self.userId
			? [[TGClient shared] photoFileIdForUserId:self.userId]
			: [[TGClient shared] photoFileIdForChat:self.chatId];
	if (!fileId || [fileId isEqual:self.avatarFileId])
		return;
	self.avatarFileId = fileId;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId.integerValue
						   priority:TGDownloadPriorityAvatar
						 completion:^(NSString *path){
		[weakSelf applyAvatarImageAtPath:path];
	}];
}

- (void)updateGroupStatus {
	if (self.userId || self.memberCount <= 0)
		return;
	NSString *count = [NSString stringWithFormat:@"%ld %@", (long)self.memberCount,
			self.isChannel ? @"subscribers" : @"members"];
	self.restingStatus = self.onlineCount > 0 && !self.isChannel
			? [NSString stringWithFormat:@"%@, %ld online", count, (long)self.onlineCount] : count;
	[self statusLabelOwnerChanged:nil];
}

- (BOOL)isOwner {
	return [self.myStatus isEqualToString:@"owner"];
}

- (BOOL)isOwnProfile {
	return self.userId && self.userId == [[TGClient shared].me[@"id"] longLongValue];
}

/// What this account may do in a group. The profile needs the same answer
/// Group Settings asks for: a plain member must not see an Add Member tile,
/// and only the owner gets Delete Group rather than Leave Group.
- (void)loadOwnRole {
	if (self.userId || !self.chatId)
		return;
	int64_t meId = [[TGClient shared].me[@"id"] longLongValue];
	if (!meId)
		return;
	__weak typeof(self) weakSelf = self;
	// The type tells the profile whether "members" or "subscribers" is the
	// word, and a basic group's invite right lives on the chat rather than
	// on a member record. Read it before the member so both answers land in
	// the same order whichever request finishes first.
	[[TGClient shared] chatRecordForChat:self.chatId completion:^(NSDictionary *chat){
		TGProfileViewController *me = weakSelf;
		if (!me)
			return;
		NSString *kind = chat[@"type"][@"@type"];
		me.isGroup = [kind isEqualToString:@"chatTypeBasicGroup"] ||
					 [kind isEqualToString:@"chatTypeSupergroup"];
		me.isChannel = [kind isEqualToString:@"chatTypeSupergroup"] &&
					   [chat[@"type"][@"is_channel"] boolValue];
		me.chatPermissions = [chat[@"permissions"] isKindOfClass:NSDictionary.class]
				? chat[@"permissions"] : @{};
		[me updateGroupStatus];
		[me buildHeader];

		[[TGClient shared] chatMember:meId inChat:me.chatId
							completion:^(NSDictionary *member){
			TGProfileViewController *again = weakSelf;
			if (!again)
				return;
			NSDictionary *status = [member[@"status"] isKindOfClass:NSDictionary.class]
					? member[@"status"] : @{};
			NSString *role = status[@"@type"];
			again.myStatus = [role isEqualToString:@"chatMemberStatusCreator"] ? @"owner"
					: ([role isEqualToString:@"chatMemberStatusAdministrator"]
							? @"admin" : @"member");
			again.myRights = [status[@"rights"] isKindOfClass:NSDictionary.class]
					? status[@"rights"] : @{};
			BOOL owner = [again isOwner];
			BOOL hadInvite = again.canInvite;
			again.canManage = owner || [again.myStatus isEqualToString:@"admin"];
			// A basic group has no administrator rights object; its
			// permissions are the chat's, and any unrestricted member may
			// invite. A supergroup asks the member's own rights record.
			if (again.isGroup && !again.isChannel &&
					![again.myStatus isEqualToString:@"admin"] && !owner){
				id canInvite = again.chatPermissions[@"can_invite_users"];
				again.canInvite = canInvite ? [canInvite boolValue] : YES;
			} else {
				again.canInvite = owner ||
						[again.myRights[@"can_invite_users"] boolValue];
			}
			// Only the tile row changes shape with this answer; rebuilding
			// the header for every role read would re-download the avatar.
			if (hadInvite != again.canInvite)
				[again buildHeader];
			[again reloadTableDebounced];
		}];
	}];
}

/// Only this screen's own peer. A group profile has the chat id, not the
/// supergroup id, so any group's full info re-reads a group profile - one
/// request, and the alternative is caching the mapping for no gain.
- (void)fullInfoChanged:(NSNotification *)note {
	NSString *kind = note.userInfo[@"kind"];
	BOOL mine;
	if ([kind isEqualToString:@"user"])
		mine = self.userId && [note.userInfo[@"id"] longLongValue] == self.userId;
	else if ([kind isEqualToString:@"chat"])
		mine = self.chatId && [note.userInfo[@"id"] longLongValue] == self.chatId;
	else
		mine = (self.userId == 0 && self.chatId != 0);
	if (mine)
		[self loadDetails];
}

- (void)membersChanged:(NSNotification *)note {
	if (self.chatId && [note.userInfo[@"chatId"] longLongValue] == self.chatId)
		[self loadDetails];
}

- (void)loadDetails {
	self.muted = [[TGClient shared] isChatMuted:self.chatId];

	if (!self.userId){
		__weak typeof(self) weakSelf = self;
		[self loadOwnRole];
		[[TGClient shared] membersOfChat:self.chatId completion:^(NSArray *members){
			weakSelf.members = members;
			[weakSelf reloadTableDebounced];
		}];
		// Group details: description, member count, invite link.
		[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
			TGProfileViewController *me = weakSelf;
			if (!me)
				return;
			me.chatDescription = info[@"description"] ?: @"";
			me.memberCount = [info[@"members"] integerValue];
			me.onlineCount = [info[@"online"] integerValue];
			me.isVerified = [info[@"verified"] boolValue];
			me.inviteLink = info[@"inviteLink"] ?: @"";
			me.directMessagesChatId = [info[@"directMessagesChatId"] longLongValue];
			me.hasDirectMessages = [info[@"hasDirectMessages"] boolValue];
			me.canManageDirectMessages = [info[@"canManageDirectMessages"] boolValue];
			[me updateGroupStatus];
			NSMutableArray *rows = [NSMutableArray array];
			if ([info[@"description"] length])
				[rows addObject:@{@"kind" : @"about", @"label" : @"about",
						@"value" : info[@"description"]}];
			// No administrator count: the member rows carry an Owner or
			// Admin badge beside the people who hold that role, which says
			// who they are instead of only how many there are.
			if (me.inviteLink.length)
				[rows addObject:@{@"kind" : @"invite", @"label" : @"invite link",
						@"value" : me.inviteLink}];
			if (me.linkedChatTitle.length)
				[rows addObject:@{@"kind" : @"linkedChat",
						@"label" : (me.isChannel ? @"discussion" : @"linked channel"),
						@"value" : me.linkedChatTitle}];
			me.communityId = [info[@"communityId"] longLongValue];
			if (me.communityId != 0) {
				NSDictionary *fullComm = [[TGClient shared] cachedCommunityFullInfo:me.communityId];
				NSArray *commChats = fullComm[@"chats"];
				NSString *commTitle = nil;
				if (commChats.count > 0) {
					commTitle = [NSString stringWithFormat:@"%lu chats and groups", (unsigned long)commChats.count];
				} else {
					for (NSDictionary *comm in [TGClient shared].communities) {
						if ([comm[@"id"] longLongValue] == me.communityId) {
							commTitle = comm[@"name"];
							break;
						}
					}
					if (!commTitle.length) {
						commTitle = @"Chat pool";
					}
				}
				[rows addObject:@{@"kind" : @"community",
						@"label" : @"community",
						@"value" : commTitle}];
			}
			if (me.isChannel && me.similarChatIds.count)
				[rows addObject:@{@"kind" : @"similarChannels",
						@"label" : @"similar channels",
						@"value" : [NSString stringWithFormat:@"%lu channels", (unsigned long)me.similarChatIds.count]}];
			me.details = rows;
			[me buildHeader];
			[me reloadTableDebounced];

			if (me.communityId != 0 && ![[TGClient shared] cachedCommunityFullInfo:me.communityId]) {
				[[TGClient shared] communityFullInfo:me.communityId completion:^(NSDictionary *cinfo, NSString *err){
					TGProfileViewController *again = weakSelf;
					if (!again) return;
					[again reloadTableDebounced];
				}];
			}

			if (me.isChannel){
				[[TGClient shared] similarChatsForChat:me.chatId completion:^(NSArray *chats, NSInteger total){
					TGProfileViewController *again = weakSelf;
					if (!again || !chats.count)
						return;
					again.similarChatIds = chats;
					NSMutableArray *updated = [again.details mutableCopy];
					BOOL exists = NO;
					for (NSDictionary *r in updated){
						if ([r[@"kind"] isEqualToString:@"similarChannels"]){
							exists = YES;
							break;
						}
					}
					if (!exists){
						[updated addObject:@{@"kind" : @"similarChannels",
								@"label" : @"similar channels",
								@"value" : [NSString stringWithFormat:@"%lu channels", (unsigned long)(total > 0 ? total : chats.count)]}];
						again.details = updated;
						[again reloadTableDebounced];
					}
				}];
			}

			int64_t linkedId = [info[@"linkedChatId"] longLongValue];
			if (linkedId != 0 && linkedId != me.linkedChatId){
				me.linkedChatId = linkedId;
				[[TGClient shared] chatRecordForChat:linkedId completion:^(NSDictionary *linkedChat){
					TGProfileViewController *again = weakSelf;
					if (!again || !linkedChat)
						return;
					again.linkedChatTitle = linkedChat[@"title"] ?: @"";
					if (!again.linkedChatTitle.length)
						return;
					NSMutableArray *updated = [again.details mutableCopy];
					BOOL exists = NO;
					for (NSDictionary *r in updated){
						if ([r[@"kind"] isEqualToString:@"linkedChat"]){
							exists = YES;
							break;
						}
					}
					if (!exists){
						[updated addObject:@{@"kind" : @"linkedChat",
								@"label" : (again.isChannel ? @"discussion" : @"linked channel"),
								@"value" : again.linkedChatTitle}];
						again.details = updated;
						[again reloadTableDebounced];
					}
				}];
			}
		}];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] userInfo:self.userId completion:^(NSDictionary *user){
		if (!user) return;
		NSString *updatedName = TGProfileUserName(user);
		if (updatedName.length)
			weakSelf.name = updatedName;
		// The marks beside the name and the scam/fake warning all come off
		// the plain user record; none needs the full-info call.
		NSDictionary *verification = user[@"verification_status"];
		weakSelf.isVerified = [verification[@"is_verified"] boolValue];
		weakSelf.isScam = [verification[@"is_scam"] boolValue];
		weakSelf.isFake = [verification[@"is_fake"] boolValue];
		weakSelf.isContact = [user[@"is_contact"] boolValue];
		// A bot has no presence and cannot be a contact.
		if ([user[@"type"][@"@type"] isEqualToString:@"userTypeBot"]){
			weakSelf.isBot = YES;
			weakSelf.restingStatus = @"bot";
			[weakSelf statusLabelOwnerChanged:nil];
		}
		NSDictionary *statusType = user[@"emoji_status"][@"type"];
		int64_t statusId = [statusType[@"custom_emoji_id"] longLongValue]
				?: [statusType[@"model_custom_emoji_id"] longLongValue];
		if (statusId && statusId != weakSelf.emojiStatusId){
			weakSelf.emojiStatusId = statusId;
			[weakSelf fetchEmojiStatusImage:statusId];
		}
		weakSelf.phoneNumber = user[@"phone_number"] ?: @"";
		NSArray *activeUsernames = user[@"usernames"][@"active_usernames"];
		if ([activeUsernames isKindOfClass:NSArray.class] && activeUsernames.count) {
			weakSelf.activeUsernames = activeUsernames;
		} else if ([user[@"username"] length]) {
			weakSelf.activeUsernames = @[user[@"username"]];
		} else {
			weakSelf.activeUsernames = @[];
		}
		weakSelf.username = TGFirstUsername(user) ?: @"";
		weakSelf.details = [weakSelf basicDetailsRows];
		[weakSelf buildHeader];
		[weakSelf reloadTableDebounced];

		// The bio, the birthday and the channel live in the full record, which
		// this screen never asked for - so "about" was missing from a profile
		// that has one. The same call carries the block flag, so isUserBlocked
		// would send getUserFullInfo a second time.
		[[TGClient shared] userProfile:weakSelf.userId completion:^(NSDictionary *info){
			weakSelf.blocked = [info[@"isBlocked"] boolValue];
			weakSelf.canCall = [info[@"canCall"] boolValue];
			weakSelf.canVideoCall = [info[@"canVideoCall"] boolValue];
			weakSelf.commonGroupCount = [info[@"commonGroups"] integerValue];
			weakSelf.businessLocation = info[@"businessLocation"] ?: @"";
			NSDictionary *firstAudio = [info[@"firstProfileAudio"]
					isKindOfClass:NSDictionary.class] ? info[@"firstProfileAudio"] : nil;
			if (![firstAudio isEqual:weakSelf.firstProfileAudio]){
				weakSelf.firstProfileAudio = firstAudio;
				[weakSelf buildHeader];
			}
			weakSelf.personalNote = info[@"note"] ?: @"";
			weakSelf.bioEntities = info[@"bioEntities"] ?: @[];
			weakSelf.noteEntities = info[@"noteEntities"] ?: @[];
			weakSelf.birthdayToday = [info[@"birthdayToday"] boolValue];
			weakSelf.hasPersonalPhoto = [info[@"personalPhoto"] longLongValue] != 0;
			NSString *bio = info[@"bio"];
			if (!bio.length && [info[@"botDescription"] length])
				bio = info[@"botDescription"];
			weakSelf.details = [weakSelf fullDetailsRowsWithBio:bio
													  birthday:info[@"birthday"]];
			// The tab the person chose goes first, and the screen opens on it
			// unless a tab has already been picked.
			NSString *mainTab = info[@"mainProfileTab"];
			if (mainTab.length){
				weakSelf.mainMediaKind = mainTab;
				if (!weakSelf.storedMediaKind.length)
					weakSelf.storedMediaKind = mainTab;
			}
			int64_t personalChatId = [info[@"personalChatId"] longLongValue];
			if (personalChatId > 0)
				[weakSelf fetchPersonalChannel:personalChatId];
			[weakSelf buildHeader];
			[weakSelf reloadTableDebounced];
		}];

		// updateUser does not always carry a photo; getUser does.
		NSNumber *photoId = user[@"profile_photo"][@"small"][@"id"];
		if (photoId && ![photoId isEqual:weakSelf.avatarFileId]){
			weakSelf.avatarFileId = photoId;
			[[TGClient shared] downloadFile:photoId.integerValue
								   priority:TGDownloadPriorityAvatar
								 completion:^(NSString *path){
				[weakSelf applyAvatarImageAtPath:path];
			}];
		}
	}];
}

/// The rows the plain user record can answer before full info arrives: just
/// the phone number and username, which are the parts that never move.
- (NSArray *)basicDetailsRows {
	NSMutableArray *rows = [NSMutableArray array];
	if (self.phoneNumber.length)
		[rows addObject:@{@"kind" : @"phone", @"label" : @"mobile",
				@"value" : [@"+" stringByAppendingString:self.phoneNumber]}];
	if (self.username.length)
		[rows addObject:@{@"kind" : @"username", @"label" : @"username",
				@"value" : [@"@" stringByAppendingString:self.username]}];
	return rows;
}

/// The whole card, rebuilt once full info answers: phone, username, the bio
/// (or the scam/fake warning in its place), birthday, note, then the
/// add-to-contacts row for a stranger.
- (NSArray *)fullDetailsRowsWithBio:(NSString *)bio birthday:(NSString *)birthday {
	NSMutableArray *rows = [NSMutableArray array];
	// On your own profile the bio leads, and an empty one is an invitation to
	// write it rather than a missing row.
	BOOL own = self.isOwnProfile;
	if (own)
		[rows addObject:bio.length
				? @{@"kind" : @"bio", @"label" : @"bio", @"value" : bio}
				: @{@"kind" : @"addBio", @"label" : @"", @"value" : @"Add a bio"}];
	if (self.phoneNumber.length)
		[rows addObject:@{@"kind" : @"phone", @"label" : @"mobile",
				@"value" : [@"+" stringByAppendingString:self.phoneNumber]}];
	if (self.activeUsernames.count > 0){
		for (NSUInteger i = 0; i < self.activeUsernames.count; i++){
			NSString *u = self.activeUsernames[i];
			if (!u.length) continue;
			[rows addObject:@{@"kind" : @"username",
					@"label" : (i == 0 ? @"username" : @"link"),
					@"value" : [@"@" stringByAppendingString:u]}];
		}
	} else if (self.username.length){
		[rows addObject:@{@"kind" : @"username", @"label" : @"username",
				@"value" : [@"@" stringByAppendingString:self.username]}];
	}
	if (self.isScam || self.isFake){
		[rows addObject:@{@"kind" : @"warning", @"label" : @"",
				@"value" : (self.isScam ? @"This account is marked as a scam."
									   : @"This account is marked as fake.")}];
	} else if (bio.length && !own){
		[rows addObject:@{@"kind" : @"bio", @"label" : @"about", @"value" : bio}];
	}
	if (birthday.length)
		[rows addObject:@{@"kind" : @"birthday", @"label" : @"birthday",
				@"value" : birthday}];
	if (self.businessLocation.length)
		[rows addObject:@{@"kind" : @"businessLocation", @"label" : @"location",
				@"value" : self.businessLocation}];
	if (self.personalNote.length)
		[rows addObject:@{@"kind" : @"note", @"label" : @"note",
				@"value" : self.personalNote}];
	if (!self.isContact && !self.isOwnProfile && !self.isBot)
		[rows addObject:@{@"kind" : @"addContact", @"label" : @"",
				@"value" : @"Add to Contacts"}];
	return rows;
}

/// The person's personal channel: one getChat, then a row at the top of the
/// card that opens it like any chat the list holds.
- (void)fetchEmojiStatusImage:(int64_t)emojiId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] customEmojiStickersForIds:@[@(emojiId)] completion:^(NSArray *stickers){
		NSNumber *thumb = stickers.count ? stickers[0][@"thumbId"] : nil;
		if (![thumb isKindOfClass:NSNumber.class] || !thumb.integerValue)
			return;
		[[TGClient shared] downloadFile:thumb.integerValue
							   priority:TGDownloadPriorityAvatar
							 completion:^(NSString *path){
			if (!path.length)
				return;
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				UIImage *image = [UIImage imageWithContentsOfFile:path]
						?: [UIImage convertFromWebP:path compressedData:nil error:nil];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!image)
						return;
					weakSelf.emojiStatusImage = image;
					[weakSelf buildHeader];
				});
			});
		}];
	}];
}

- (void)fetchPersonalChannel:(int64_t)chatId {
	if (self.personalChannel)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] chatRecordForChat:chatId completion:^(NSDictionary *chat){
		TGProfileViewController *me = weakSelf;
		if (!me || !chat)
			return;
		NSString *title = chat[@"title"] ?: @"";
		NSNumber *photoId = chat[@"photo"][@"small"][@"id"];
		me.personalChannel = @{
			@"chatId" : @(chatId),
			@"title" : title,
			@"photoFileId" : [photoId isKindOfClass:NSNumber.class] ? photoId : @0,
		};
		NSMutableArray *rows = [me.details mutableCopy];
		[rows insertObject:@{@"kind" : @"channel", @"label" : @"personal channel",
				@"value" : title} atIndex:0];
		me.details = rows;
		[me reloadTableDebounced];
	}];
}

- (void)reloadTableDebounced {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(doReloadTable) object:nil];
	[self performSelector:@selector(doReloadTable) withObject:nil afterDelay:0.05];
}

- (void)doReloadTable {
	[self.tableView reloadData];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != self.tableView) return;
	[self loadVisibleMediaTabIfNeeded];
	CGFloat distanceFromBottom = scrollView.contentSize.height - (scrollView.contentOffset.y + scrollView.bounds.size.height);
	if (distanceFromBottom < 300.0f && !self.isLoadingMoreMedia) {
		[self loadMoreMediaForCurrentTab];
	}
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kSectionDetails) return self.details.count;
	if (section == kSectionDirectMessages) {
		BOOL hasDM = (self.directMessagesChatId != 0) || self.hasDirectMessages || self.canManageDirectMessages;
		return (self.isChannel && hasDM) ? 1 : 0;
	}
	// Stories and Gifts live in the bar above the shared section now, so the
	// standalone sections would show the same rows a second time.
	if (section == kSectionStories) return 0;
	if (section == kSectionGifts)   return 0;
	if (section == kSectionMembers) return self.members.count;

	if (section == kSectionMedia) {
		if (![self currentMediaTabs].count)
			return 0;
		// Media and Stories each draw into grid rows; the rest are lists.
		if ([self selectedTabIsGrid]) {
			NSArray *rows = [self selectedMediaRows];
			return (rows.count + kStoryGridCols - 1) / kStoryGridCols;
		}
		return [self selectedMediaRows].count;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == kSectionMembers){
		if (self.members.count == 0)
			return nil;
		NSInteger count = self.memberCount > 0 ? self.memberCount
											   : (NSInteger)self.members.count;
		if (count <= 0)
			return nil;
		// Telegram counts the whole group here, even when the list below is
		// only the first page it returned.
		return [NSString stringWithFormat:@"%ld %@", (long)count,
				self.isChannel ? @"subscribers" : @"members"];
	}
	return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section == kSectionMedia && [self currentMediaTabs].count) {
		return [self mediaTabBarOfWidth:tableView.bounds.size.width];
	}
	return nil;
}

/// More tabs than a phone's width holds, so they scroll. The offset is kept by
/// hand because the table builds this view again on every reload, and a tab the
/// finger just reached must not jump back to the start. The selected tab carries
/// the count of what is in it.
- (UIView *)mediaTabBarOfWidth:(CGFloat)width {
	TGTheme *theme = [TGTheme shared];
	UIScrollView *bar = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, width, kMediaTabsRow)];
	bar.backgroundColor = [theme groupedBackgroundColour];
	bar.showsHorizontalScrollIndicator = NO;
	bar.scrollsToTop = NO;
	NSArray *tabs = [self currentMediaTabs];
	NSString *selected = [self selectedMediaKind];
	CGFloat x = TGMetricPadMedium;
	for (NSUInteger i = 0; i < tabs.count; i++){
		NSString *kind = tabs[i][@"kind"];
		BOOL isSelected = [kind isEqualToString:selected];
		NSInteger count = [self.mediaCounts[kind] integerValue];
		NSString *title = count > 0
				? [NSString stringWithFormat:@"%@ %ld", tabs[i][@"title"], (long)count]
				: tabs[i][@"title"];
		UIFont *font = TGFontCaptionStrong();
		CGFloat w = ceilf([title sizeWithFont:font].width) + TGDoubled(TGMetricPadMedium);
		UIButton *tab = [UIButton buttonWithType:UIButtonTypeCustom];
		tab.frame = CGRectMake(x, 0, w, kMediaTabsRow);
		tab.titleLabel.font = font;
		tab.tag = (NSInteger)i;
		[tab setTitle:title forState:UIControlStateNormal];
		[tab setTitleColor:isSelected ? [theme accentColour] : [theme secondaryTextColour]
				  forState:UIControlStateNormal];
		[tab addTarget:self action:@selector(mediaTabTapped:) forControlEvents:UIControlEventTouchUpInside];
		[bar addSubview:tab];
		if (isSelected){
			UIView *line = [[UIView alloc] initWithFrame:CGRectMake(x + TGMetricPadSmall,
					kMediaTabsRow - kMediaTabLine, w - TGDoubled(TGMetricPadSmall), kMediaTabLine)];
			line.backgroundColor = [theme accentColour];
			[bar addSubview:line];
		}
		x += w;
	}
	bar.contentSize = CGSizeMake(x + TGMetricPadMedium, kMediaTabsRow);
	bar.contentOffset = CGPointMake(MIN(self.mediaTabsOffset, MAX(0, bar.contentSize.width - width)), 0);
	return bar;
}

- (void)mediaTabTapped:(UIButton *)tab {
	self.mediaTabsOffset = [(UIScrollView *)tab.superview contentOffset].x;
	NSArray *tabs = [self currentMediaTabs];
	if (tab.tag < (NSInteger)tabs.count)
		[self mediaTabSelected:tabs[(NSUInteger)tab.tag][@"kind"]];
}



- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.textColor = [[TGTheme shared] sectionHeaderColour];
	}
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section == kSectionMedia)
		return [self currentMediaTabs].count ? TGMetricMediaStripHeader : CGFLOAT_MIN;
	// Stories and Gifts are categories in the bar now and have no rows left.
	// A grouped table still pads an empty section at both ends, and two of
	// them in a row opened a gap the size of a screen above the bar.
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return CGFLOAT_MIN;
	// Its title is the member count; the default height cut the text in half.
	if (section == kSectionMembers){
		if (self.members.count == 0) return CGFLOAT_MIN;
		return TGMetricMediaStripHeader;
	}
	return [super tableView:tableView heightForHeaderInSection:section];
}

/// Your own Stories or Archive tab once it has answered with nothing. A tab
/// that is still loading stays blank rather than claiming there is nothing.
- (BOOL)showsEmptyStories {
	NSString *kind = [self selectedMediaKind];
	if (!self.isOwnProfile ||
			!([kind isEqualToString:@"stories"] || [kind isEqualToString:@"archive"]))
		return NO;
	return [self.loadedMediaKinds containsObject:kind] && ![self selectedMediaRows].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section != kSectionMedia || ![self showsEmptyStories])
		return nil;
	TGTheme *theme = [TGTheme shared];
	CGFloat width = tableView.bounds.size.width;
	BOOL archive = [[self selectedMediaKind] isEqualToString:@"archive"];
	UIView *empty = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width,
			[self tableView:tableView heightForFooterInSection:section])];

	UILabel *line = [[UILabel alloc] initWithFrame:
			CGRectMake(0, TGMetricPadWide, width, TGMetricLineBody)];
	line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	line.text = archive ? @"No archived stories" : @"No stories yet";
	line.font = TGFontBody();
	line.textColor = [theme secondaryTextColour];
	line.textAlignment = NSTextAlignmentCenter;
	line.backgroundColor = [UIColor clearColor];
	[empty addSubview:line];

	// The archive only fills from stories that expire, so it offers nothing.
	if (!archive){
		UIButton *add = [UIButton buttonWithType:UIButtonTypeCustom];
		add.frame = CGRectMake(0, TGMetricPadWide + TGMetricLineBody, width, TGMetricLineBody);
		add.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		add.titleLabel.font = TGFontBody();
		[add setTitle:@"Add a story" forState:UIControlStateNormal];
		[add setTitleColor:[theme accentColour] forState:UIControlStateNormal];
		[add addTarget:self action:@selector(addStoryTapped)
				forControlEvents:UIControlEventTouchUpInside];
		[empty addSubview:add];
	}
	return empty;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (section == kSectionMedia && [self showsEmptyStories])
		return TGDoubled(TGMetricPadWide) + TGDoubled(TGMetricLineBody);
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return CGFLOAT_MIN;
	if (section == kSectionMedia)
		return CGFLOAT_MIN;
	return [super tableView:tableView heightForFooterInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kSectionMedia && [self selectedTabIsGrid]) {
		CGFloat side = [[self class] storySideForWidth:tableView.bounds.size.width];
		return side + kStoryGridGap;
	}
	if (indexPath.section == kSectionMedia &&
			[[self selectedMediaKind] isEqualToString:@"music"])
		return TGMetricTrackRow;
	if (indexPath.section == kSectionDirectMessages) return TGMetricPersonRow;
	if (indexPath.section == kSectionStories) return TGMetricPersonRow;
	if (indexPath.section == kSectionMembers) return TGMetricPersonRow;
	if (indexPath.section == kSectionMedia) return TGMetricPersonRow;
	if (indexPath.section == kSectionDetails && indexPath.row < (NSInteger)self.details.count){
		NSDictionary *row = self.details[indexPath.row];
		NSString *kind = row[@"kind"];
		CGFloat left = TGMetricPadLarge + TGMetricMenuGlyph + TGMetricPadMedium;
		BOOL hasAccessory = [kind isEqualToString:@"channel"] || [kind isEqualToString:@"businessLocation"] || [kind isEqualToString:@"linkedChat"] || [kind isEqualToString:@"community"];
		CGFloat rightMargin = hasAccessory ? (TGMetricMenuGlyph + TGMetricPadMedium) : TGMetricPadLarge;
		CGFloat textWidth = tableView.bounds.size.width - left - rightMargin - TGDoubled(TGMetricPad);
		if (textWidth < 50.0f) textWidth = 50.0f;
		NSString *val = row[@"value"] ?: @"";
		CGFloat textH = [val sizeWithFont:TGFontBody()
				constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX)
					lineBreakMode:NSLineBreakByWordWrapping].height;
		CGFloat labelH = [row[@"label"] length] ? (TGMetricLineCaption + TGMetricPadTiny) : 0;
		CGFloat totalH = TGMetricPadSmall + labelH + ceilf(textH) + TGMetricPadMedium;
		return MAX(TGMetricPersonRow, totalH);
	}
	return TGMetricRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kSectionMedia && [self selectedTabIsGrid])
		return [self mediaGridCellForTableView:tableView atRow:indexPath.row];

	// The member list draws a face per row; the shared cell owns the picture
	// and the one-row reload that follows its download.
	if (indexPath.section == kSectionMembers){
		static NSString *memberReuse = @"member";
		TGMemberCell *memberCell = [tableView dequeueReusableCellWithIdentifier:memberReuse];
		if (!memberCell)
			memberCell = [[TGMemberCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:memberReuse];
		[[TGTheme shared] styleCell:memberCell];
		memberCell.textLabel.font = TGFontBody();
		memberCell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		memberCell.selectionStyle = UITableViewCellSelectionStyleDefault;
		memberCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		NSDictionary *member = self.members[indexPath.row];
		int64_t userId = [member[@"id"] longLongValue];
		NSString *name = [member[@"name"] length]
				? member[@"name"] : [[TGClient shared] nameForUserId:userId];
		[memberCell setName:name userId:userId status:member[@"status"]
						tag:member[@"tag"] inTable:tableView];
		return memberCell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	cell.detailTextLabel.numberOfLines = 1;
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"row"];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = nil;
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.font = TGFontBody();
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.font = TGFontCaption();
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

	// The information card: what it is in small grey, the value itself under
	// it in the accent colour.
	if (indexPath.section == kSectionDetails){
		static NSString *detailReuse = @"profile-detail";
		TGProfileDetailCell *detailCell = [tableView dequeueReusableCellWithIdentifier:detailReuse];
		if (!detailCell)
			detailCell = [[TGProfileDetailCell alloc] initWithStyle:UITableViewCellStyleDefault
													reuseIdentifier:detailReuse];
		[[TGTheme shared] styleCell:detailCell];
		detailCell.selectionStyle = UITableViewCellSelectionStyleNone;

		NSDictionary *row = self.details[indexPath.row];
		NSString *kind = row[@"kind"];
		TGTheme *theme = [TGTheme shared];
		detailCell.accessoryType = ([kind isEqualToString:@"channel"] || [kind isEqualToString:@"businessLocation"] || [kind isEqualToString:@"linkedChat"] || [kind isEqualToString:@"community"])
				? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

		UIImage *icon = nil;
		CGFloat iconSide = TGMetricMenuGlyph;
		if ([kind isEqualToString:@"phone"]) {
			icon = [TGIcons glyphNamed:@"call" colour:[theme accentColour] side:iconSide];
		} else if ([kind isEqualToString:@"username"]) {
			icon = [TGIcons glyphNamed:@"mention" colour:[theme accentColour] side:iconSide];
		} else if ([kind isEqualToString:@"birthday"]) {
			icon = [TGIcons glyphNamed:@"star" colour:self.birthdayToday ? [theme onlineColour] : [theme accentColour] side:iconSide];
		} else if ([kind isEqualToString:@"bio"] || [kind isEqualToString:@"about"] || [kind isEqualToString:@"note"]) {
			icon = [TGIcons glyphNamed:@"edit" colour:[theme secondaryTextColour] side:iconSide];
		} else if ([kind isEqualToString:@"channel"] || [kind isEqualToString:@"linkedChat"] || [kind isEqualToString:@"community"]) {
			icon = [TGIcons glyphNamed:@"chat" colour:[theme accentColour] side:iconSide];
		} else if ([kind isEqualToString:@"businessLocation"]) {
			icon = [TGIcons glyphNamed:@"archive" colour:[theme accentColour] side:iconSide];
		}
		detailCell.iconView.image = icon;

		detailCell.titleLabel.text = row[@"label"];
		detailCell.titleLabel.textColor = [theme secondaryTextColour];
		detailCell.subtitleLabel.text = row[@"value"];
		BOOL plain = [kind isEqualToString:@"bio"] || [kind isEqualToString:@"note"] ||
				[kind isEqualToString:@"about"];
		BOOL today = [kind isEqualToString:@"birthday"] && self.birthdayToday;
		detailCell.subtitleLabel.textColor = [kind isEqualToString:@"warning"] ? [theme destructiveColour]
				: (today ? [theme onlineColour]
				: (plain ? [theme primaryTextColour] : [theme accentColour]));
		[detailCell setNeedsLayout];
		return detailCell;
	}

	if (indexPath.section == kSectionDirectMessages){
		static NSString *dmReuse = @"profile-dm";
		TGProfileDetailCell *dmCell = [tableView dequeueReusableCellWithIdentifier:dmReuse];
		if (!dmCell)
			dmCell = [[TGProfileDetailCell alloc] initWithStyle:UITableViewCellStyleDefault
												reuseIdentifier:dmReuse];
		[[TGTheme shared] styleCell:dmCell];
		dmCell.selectionStyle = UITableViewCellSelectionStyleNone;
		TGTheme *theme = [TGTheme shared];
		dmCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		dmCell.iconView.image = [TGIcons glyphNamed:@"chat" colour:[theme accentColour] side:TGMetricMenuGlyph];
		dmCell.titleLabel.text = @"direct messages";
		dmCell.titleLabel.textColor = [theme secondaryTextColour];
		dmCell.subtitleLabel.text = (self.canManageDirectMessages || self.canManage) ? @"Manage Topics" : @"Open Direct Chat";
		dmCell.subtitleLabel.textColor = [theme accentColour];
		[dmCell setNeedsLayout];
		return dmCell;
	}

	// A story reads as its picture, its caption and when it went up - the
	// same three things the story list in a current client shows.
	if (indexPath.section == kSectionStories){
		NSDictionary *story = self.stories[indexPath.row];
		NSString *caption = [story[@"caption"] length] ? story[@"caption"]
				: ([story[@"isVideo"] boolValue] ? @"Video story" : @"Photo story");
		cell.textLabel.text = caption;
		cell.textLabel.font = TGFontBody();
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];

		static NSDateFormatter *when = nil;
		if (!when){
			when = [[NSDateFormatter alloc] init];
			when.dateStyle = NSDateFormatterShortStyle;
			when.timeStyle = NSDateFormatterShortStyle;
		}
		NSString *seen = [story[@"viewers"] integerValue] > 0
				? [NSString stringWithFormat:@" - %@ views", story[@"viewers"]] : @"";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@",
				[when stringFromDate:[NSDate dateWithTimeIntervalSince1970:
						[story[@"date"] doubleValue]]], seen];
		cell.detailTextLabel.font = TGFontMeta();
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

		UIImageView *thumb = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, 0, kStoryThumb, kStoryThumb)];
		thumb.backgroundColor = [[TGTheme shared] fileTileColour];
		thumb.contentMode = UIViewContentModeScaleAspectFill;
		thumb.clipsToBounds = YES;
		thumb.layer.cornerRadius = TGMetricCornerMedium;
		cell.imageView.image = [TGIcons avatarWithInitials:@" " size:kStoryThumb
												  colourId:indexPath.row];
		NSNumber *fileId = story[@"thumbPhotoId"] ?: story[@"photoId"];
		if ([fileId isKindOfClass:NSNumber.class]){
			__weak UITableView *weakTable = tableView;
			[[TGClient shared] downloadFile:fileId.integerValue
								   priority:TGDownloadPriorityOnScreen
								 completion:^(NSString *path){
				if (!path.length) return;
				UIImage *image = [TGIcons decodedImage:[UIImage imageWithContentsOfFile:path]
										   fittingSize:CGSizeMake(kStoryThumb, kStoryThumb) fill:YES
												 scale:[UIScreen mainScreen].scale];
				if (!image) return;
				cell.imageView.image = image;
				[cell setNeedsLayout];
				(void)weakTable;
			}];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == kSectionGifts){
		NSDictionary *gift = self.gifts[indexPath.row];
		NSString *emoji = gift[@"emoji"] ?: @"";
		NSString *message = gift[@"message"];
		cell.textLabel.text = (message.length && emoji.length)
				? [NSString stringWithFormat:@"%@ %@", emoji, message]
				: (emoji.length ? emoji : @"Gift");
		cell.textLabel.font = TGFontBody();
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		NSString *stars = [NSString stringWithFormat:@"%lu stars",
				(unsigned long)[gift[@"starCount"] integerValue]];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
				TGProfileShortDate(gift[@"date"]) ?: @"", stars];
		cell.detailTextLabel.font = TGFontMeta();
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];

		cell.imageView.image = TGGiftGlyph(emoji);
		NSNumber *thumbId = gift[@"thumbFileId"];
		if ([thumbId isKindOfClass:NSNumber.class]){
			__weak UITableViewCell *weakCell = cell;
			[[TGClient shared] downloadFile:thumbId.integerValue
								   priority:TGDownloadPriorityOnScreen
								 completion:^(NSString *path){
				if (!weakCell || !path.length)
					return;
				UIImage *image = [TGIcons decodedImage:
						[UIImage imageWithContentsOfFile:path]
						fittingSize:CGSizeMake(kStoryThumb, kStoryThumb) fill:YES
						scale:[UIScreen mainScreen].scale];
				if (!image)
					return;
				weakCell.imageView.image = image;
				[weakCell setNeedsLayout];
			}];
		}
		return cell;
	}

	if (indexPath.section == kSectionMedia) {
		NSString *kind = [self selectedMediaKind];
		NSArray *rows = [self selectedMediaRows];
		if (indexPath.row < (NSInteger)rows.count) {
			NSDictionary *m = rows[indexPath.row];
			if ([kind isEqualToString:@"music"]){
				static NSString *trackReuse = @"profile-track";
				TGProfileTrackCell *trackCell =
						[tableView dequeueReusableCellWithIdentifier:trackReuse];
				if (!trackCell)
					trackCell = [[TGProfileTrackCell alloc]
							initWithStyle:UITableViewCellStyleDefault
						  reuseIdentifier:trackReuse];
				[[TGTheme shared] styleCell:trackCell];
				NSString *title = [m[@"audioTitle"] length] ? m[@"audioTitle"]
						: ([m[@"docName"] length] ? m[@"docName"] : @"Audio");
				NSString *performer = [m[@"audioPerformer"] length]
						? m[@"audioPerformer"] : @"Unknown artist";
				TGMusicPlayer *player = [TGMusicPlayer shared];
				BOOL current = player.currentMessageId == [m[@"id"] longLongValue];
				[trackCell configureTitle:title
								   artist:performer
								 duration:TGProfileDurationText(m[@"duration"])
								  current:current
								  playing:player.playing];
				[self applyArtworkToTrackCell:trackCell message:m indexPath:indexPath];
				return trackCell;
			}

			cell.textLabel.numberOfLines = 1;
			cell.accessoryType = UITableViewCellAccessoryNone;
			if ([kind isEqualToString:@"files"]) {
				cell.textLabel.text = [m[@"docName"] length] ? m[@"docName"] : @"File";
				NSString *size = TGProfileFileSize(m[@"docSize"]);
				NSString *date = TGProfileShortDate(m[@"date"]);
				cell.detailTextLabel.text = size.length
						? (date.length ? [NSString stringWithFormat:@"%@ · %@", size, date] : size)
						: date;
				cell.imageView.image = [TGIcons document];
			} else if ([kind isEqualToString:@"voice"]) {
				BOOL videoNote = [m[@"kind"] isEqualToString:@"messageVideoNote"];
				cell.textLabel.text = videoNote ? @"Video message" : @"Voice message";
				// The row plays in place, so it has to show which one is sounding.
				if (self.playingVoiceId == [m[@"id"] longLongValue])
					cell.textLabel.textColor = [[TGTheme shared] accentColour];
				NSString *length = TGProfileDurationText(m[@"duration"]);
				NSString *date = TGProfileShortDate(m[@"date"]);
				cell.detailTextLabel.text = length.length
						? (date.length ? [NSString stringWithFormat:@"%@ · %@", length, date] : length)
						: date;
				cell.imageView.image = videoNote ? [TGIcons glyphNamed:@"video"
						colour:[[TGTheme shared] accentColour] side:kLinkGlyph]
						: [TGIcons microphone];
			} else if ([kind isEqualToString:@"links"]) {
				NSString *domain = [self linkDomainForMessage:m];
				NSString *date = TGProfileShortDate(m[@"date"]);
				BOOL bare = !domain.length || [m[@"text"] hasPrefix:domain] ||
						[m[@"text"] hasPrefix:@"http"];
				cell.textLabel.text = bare ? (domain.length ? domain : @"Link") : m[@"text"];
				cell.detailTextLabel.text = bare || !date.length ? (bare ? date : domain)
						: [NSString stringWithFormat:@"%@ · %@", domain, date];
				cell.imageView.image = [TGIcons glyphNamed:@"forward"
													colour:[[TGTheme shared] secondaryTextColour]
													  side:kLinkGlyph];
				cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			} else if ([kind isEqualToString:@"groups"]) {
				cell.textLabel.text = [m[@"title"] length] ? m[@"title"] : @"Group";
				cell.detailTextLabel.text = nil;
				cell.imageView.image = nil;
				cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			} else if ([kind isEqualToString:@"gifts"]) {
				NSString *emoji = m[@"emoji"] ?: @"";
				NSString *message = m[@"message"];
				cell.textLabel.text = (message.length && emoji.length)
						? [NSString stringWithFormat:@"%@ %@", emoji, message]
						: (emoji.length ? emoji : @"Gift");
				NSString *stars = [NSString stringWithFormat:@"%lu stars",
						(unsigned long)[m[@"starCount"] integerValue]];
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
						TGProfileShortDate(m[@"date"]) ?: @"", stars];
				cell.imageView.image = TGGiftGlyph(emoji);
				NSNumber *thumbId = m[@"thumbFileId"];
				if ([thumbId isKindOfClass:NSNumber.class]){
					__weak UITableViewCell *weakCell = cell;
					[[TGClient shared] downloadFile:thumbId.integerValue
										   priority:TGDownloadPriorityOnScreen
										 completion:^(NSString *path){
						if (!weakCell || !path.length)
							return;
						UIImage *image = [TGIcons decodedImage:
								[UIImage imageWithContentsOfFile:path]
								fittingSize:CGSizeMake(kStoryThumb, kStoryThumb) fill:YES
								scale:[UIScreen mainScreen].scale];
						if (!image)
							return;
						weakCell.imageView.image = image;
						[weakCell setNeedsLayout];
					}];
				}
			}
		}
	}
	return cell;
}

/// A hold on a member row is the old tap: the sheet of member actions. It
/// is the only way to reach Promote, Ban or Hand Over now that a tap opens
/// the person's profile, and it never turns into a chat on its own.
- (void)memberRowHeld:(UILongPressGestureRecognizer *)hold {
	if (hold.state != UIGestureRecognizerStateBegan)
		return;
	NSIndexPath *path = [self.tableView indexPathForRowAtPoint:
			[hold locationInView:self.tableView]];
	// One recogniser for both, since two on one table would race for the press.
	// A detail row copies whatever a tap on it would have done.
	if (path && path.section == kSectionDetails && path.row < (NSInteger)self.details.count){
		if ([self.details[path.row][@"value"] length])
			[self copyDetailValue:self.details[path.row][@"value"]];
		return;
	}
	if (!path || path.section != kSectionMembers ||
			path.row >= (NSInteger)self.members.count)
		return;
	[self showMemberActionsFor:self.members[(NSUInteger)path.row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == kSectionMembers &&
		indexPath.row < (NSInteger)self.members.count){
		// A member row is a person, not a chat: open their profile. The
		// sheet with Send Message and the administrator actions stays on a
		// hold, which is where this screen kept it.
		[TGGroupMemberActions openProfileForMember:self.members[indexPath.row]
											  from:self];
		return;
	}

	if (indexPath.section == kSectionMedia){
		[self openMediaRow:indexPath.row];
		return;
	}

	if (indexPath.section == kSectionDirectMessages){
		[self openDirectMessages];
		return;
	}

	if (indexPath.section != kSectionDetails ||
		indexPath.row >= (NSInteger)self.details.count)
		return;
	NSDictionary *row = self.details[indexPath.row];
	NSString *kind = row[@"kind"];
	// Each row does what it says. Copying everything was the only thing a tap
	// did before, so tapping a bio put the bio on the clipboard.
	if ([kind isEqualToString:@"channel"]){
		[self openChat:[self.personalChannel[@"chatId"] longLongValue]
				 title:self.personalChannel[@"title"] message:0];
	} else if ([kind isEqualToString:@"linkedChat"]){
		[self openChat:self.linkedChatId title:self.linkedChatTitle message:0];
	} else if ([kind isEqualToString:@"community"]){
		NSDictionary *targetComm = nil;
		for (NSDictionary *comm in [TGClient shared].communities) {
			if ([comm[@"id"] longLongValue] == self.communityId) {
				targetComm = comm;
				break;
			}
		}
		if (!targetComm) {
			targetComm = @{@"id": @(self.communityId), @"name": @"Community"};
		}
		TGCommunityViewController *commVC = [[TGCommunityViewController alloc] initWithCommunity:targetComm];
		commVC.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:commVC animated:YES];
	} else if ([kind isEqualToString:@"directMessages"]){
		[self openDirectMessages];
	} else if ([kind isEqualToString:@"similarChannels"]){
		TGSimilarChannelsViewController *similarVC = [[TGSimilarChannelsViewController alloc] init];
		similarVC.originalChatId = self.chatId;
		similarVC.channelChatIds = self.similarChatIds;
		similarVC.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:similarVC animated:YES];
	} else if ([kind isEqualToString:@"businessLocation"]){
		NSString *encoded = [row[@"value"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		NSString *mapsUrl = [NSString stringWithFormat:@"http://maps.apple.com/?q=%@", encoded ?: @""];
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:mapsUrl]];
	} else if ([kind isEqualToString:@"addContact"]){
		[self addToContactsTapped];
	} else if ([kind isEqualToString:@"addBio"]){
		[self editProfileTapped];
	} else if ([kind isEqualToString:@"bio"]){
		NSURL *url = TGProfileFirstURL(row[@"value"], self.bioEntities);
		if (url)
			[[UIApplication sharedApplication] openURL:url];
	} else if ([kind isEqualToString:@"phone"] || [kind isEqualToString:@"username"] ||
			   [kind isEqualToString:@"invite"] || [kind isEqualToString:@"birthday"]){
		[self copyDetailValue:row[@"value"]];
	}
}

- (void)openDirectMessages {
	int64_t targetId = self.directMessagesChatId;
	if (targetId == 0) {
		__weak typeof(self) weakSelf = self;
		[[TGClient shared] chatProfile:self.chatId completion:^(NSDictionary *info){
			TGProfileViewController *me = weakSelf;
			if (!me) return;
			int64_t dmId = [info[@"directMessagesChatId"] longLongValue];
			me.hasDirectMessages = [info[@"hasDirectMessages"] boolValue];
			me.canManageDirectMessages = [info[@"canManageDirectMessages"] boolValue];
			if (dmId != 0) {
				me.directMessagesChatId = dmId;
				[me openDirectMessages];
			} else if (me.hasDirectMessages || me.canManageDirectMessages) {
				me.directMessagesChatId = me.chatId;
				[me openDirectMessages];
			} else {
				[TGAlertSheet showMessage:@"Direct messages are not available for this channel."
									title:@"Direct Messages"
								   inView:me.view];
			}
		}];
		return;
	}

	if (self.canManage || self.canManageDirectMessages) {
		TGDMTopicsViewController *topics = [[TGDMTopicsViewController alloc] init];
		topics.chatId = targetId;
		topics.chatTitle = self.name;
		topics.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:topics animated:YES];
	} else {
		[self openChat:targetId
				 title:[NSString stringWithFormat:@"%@ · Direct", self.name.length ? self.name : @"Channel"]
			   message:0];
	}
}

- (void)openChat:(int64_t)chatId title:(NSString *)title message:(int64_t)messageId {
	if (!chatId)
		return;
	TGChatViewController *chat = [[TGChatViewController alloc] init];
	chat.chatId = chatId;
	chat.chatTitle = title ?: @"";
	chat.initialMessageId = messageId;
	chat.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:chat animated:YES];
}

/// A row in the shared lists. Grids have their own tiles; these are the lists,
/// which used to ignore the tap altogether.
- (void)openMediaRow:(NSInteger)index {
	NSArray *rows = [self selectedMediaRows];
	if (index >= (NSInteger)rows.count)
		return;
	NSDictionary *m = rows[(NSUInteger)index];
	NSString *kind = [self selectedMediaKind];
	int64_t messageId = [m[@"id"] longLongValue];
	if ([kind isEqualToString:@"music"]){
		[[TGMusicPlayer shared] playTracks:rows atIndex:index inChat:self.chatId];
		[self.tableView reloadData];
	} else if ([kind isEqualToString:@"links"]){
		NSURL *url = TGProfileFirstURL(m[@"text"], m[@"entities"]);
		if (url)
			[[UIApplication sharedApplication] openURL:url];
	} else if ([kind isEqualToString:@"groups"]){
		[self openChat:[m[@"chatId"] longLongValue] title:m[@"title"] message:0];
	} else if ([kind isEqualToString:@"voice"] &&
			   ![m[@"kind"] isEqualToString:@"messageVideoNote"]){
		[self toggleVoiceRow:m];
	} else if ([kind isEqualToString:@"files"] || [kind isEqualToString:@"voice"]){
		// The chat already knows how to open every kind of file and play a round
		// note, so the row goes to the message rather than growing a second way.
		[self openChat:self.chatId title:self.name message:messageId];
	}
}

- (void)toggleVoiceRow:(NSDictionary *)m {
	int64_t messageId = [m[@"id"] longLongValue];
	BOOL same = self.voicePlayer && self.playingVoiceId == messageId;
	[self.voicePlayer stop];
	self.voicePlayer = nil;
	self.playingVoiceId = 0;
	[self.tableView reloadData];
	NSNumber *docId = m[@"docId"];
	if (same || ![docId isKindOfClass:NSNumber.class])
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:docId.integerValue completion:^(NSString *path){
		dispatch_async(dispatch_get_main_queue(), ^{
			TGProfileViewController *me = weakSelf;
			if (!me || !path)
				return;
			[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
			[[AVAudioSession sharedInstance] setActive:YES error:nil];
			NSError *err = nil;
			me.voicePlayer = [[TGStreamingVoicePlayer alloc] initWithPath:path error:&err];
			if (!me.voicePlayer){
				NSLog(@"voice playback: %@", err);
				[TGAlertSheet showMessage:@"This voice message cannot be played on this device."
									title:@"Voice Message" inView:me.view];
				return;
			}
			me.voicePlayer.delegate = me;
			me.playingVoiceId = messageId;
			[me.voicePlayer play];
			[me.tableView reloadData];
		});
	}];
}

- (void)audioPlayerDidFinishPlaying:(id)player successfully:(BOOL)flag {
	self.voicePlayer = nil;
	self.playingVoiceId = 0;
	[self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self loadVisibleMediaTabIfNeeded];
	// Back from the viewer, which can move or delete a story.
	[self reloadOwnStories];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.voicePlayer stop];
	self.voicePlayer = nil;
	self.playingVoiceId = 0;
}

- (void)copyDetailValue:(NSString *)value {
	[UIPasteboard generalPasteboard].string = value;

	UILabel *toast = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, kToastWidth, kToastHeight)];
	toast.center = CGPointMake(TGHalf(self.view.bounds.size.width),
							   self.view.bounds.size.height - TGMetricToastBottomOffset);
	toast.text = @"Copied";
	toast.textAlignment = NSTextAlignmentCenter;
	toast.font = TGFontSubhead();
	toast.textColor = [[TGTheme shared] hudTextColour];
	toast.backgroundColor = [[TGTheme shared] hudBackgroundColour];
	toast.layer.cornerRadius = TGMetricCornerMedium;
	toast.clipsToBounds = YES;
	[self.view addSubview:toast];
	[UIView animateWithDuration:TGAnimationDurationSlow delay:1.0 options:0
					 animations:^{ toast.alpha = 0; }
					 completion:^(BOOL done){ [toast removeFromSuperview]; }];
}

@end
