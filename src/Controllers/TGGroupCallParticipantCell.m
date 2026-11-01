#import "TGGroupCallParticipantCell.h"
#import "TGAvatarView.h"
#import "TGMemberAvatarStore.h"
#import "TGStyle.h"
#import "TGTheme.h"

/// The row is a person: picture, name, and what they are doing. The speaking
/// dot sits beside the name, where the eye lands after the picture.
static const CGFloat kGCParticipantAvatarSide = TGMetricListAvatar;
static const CGFloat kGCParticipantDotSide = 8.0f;
static const CGFloat kGCParticipantNameHeight = TGMetricLineBody;
static const CGFloat kGCParticipantDetailHeight = TGMetricLineCaption;
static const CGFloat kGCParticipantTextGap = TGMetricPadTiny;

@interface TGGroupCallParticipantCell ()
@property (nonatomic, strong) TGAvatarView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *speakingDot;
@property (nonatomic, assign) int64_t avatarUser;
@end

@implementation TGGroupCallParticipantCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])){
		self.selectionStyle = UITableViewCellSelectionStyleBlue;
		_avatar = [[TGAvatarView alloc] initWithSide:kGCParticipantAvatarSide];
		_avatar.userInteractionEnabled = NO;
		[self.contentView addSubview:_avatar];

		_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_nameLabel.font = TGFontBodyStrong();
		_nameLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_nameLabel];

		_speakingDot = [[UIView alloc] initWithFrame:CGRectZero];
		_speakingDot.backgroundColor = [TGTheme shared].onlineColour;
		_speakingDot.layer.cornerRadius = TGHalf(kGCParticipantDotSide);
		_speakingDot.hidden = YES;
		[self.contentView addSubview:_speakingDot];

		_detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_detailLabel.font = TGFontSubhead();
		_detailLabel.backgroundColor = [UIColor clearColor];
		[self.contentView addSubview:_detailLabel];
	}
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.avatarUser = 0;
	self.speakingDot.hidden = YES;
}

/// What the row says under the name. One line, in the order a person scans
/// it: mute, hand, video, screen, volume. "Muted" wins over the rest because
/// it is the state that explains why nobody hears them.
static NSString *TGGroupCallParticipantDetail(NSDictionary *participant) {
	NSMutableArray *parts = [NSMutableArray array];
	if ([participant[@"isMutedForAllUsers"] boolValue])
		[parts addObject:@"Muted"];
	else if ([participant[@"isMutedForCurrentUser"] boolValue])
		[parts addObject:@"Muted for you"];
	else if ([participant[@"isSpeaking"] boolValue])
		[parts addObject:@"Speaking"];
	if ([participant[@"isHandRaised"] boolValue])
		[parts addObject:@"Hand raised"];
	if ([participant[@"hasVideo"] boolValue]){
		[parts addObject:[participant[@"videoPaused"] boolValue]
				? @"Video paused" : @"Video"];
	}
	NSDictionary *screen = participant[@"screenInfo"];
	if ([screen[@"hasVideo"] boolValue])
		[parts addObject:[screen[@"isPaused"] boolValue]
				? @"Screen paused" : @"Sharing screen"];
	NSInteger volume = [participant[@"volumeLevel"] integerValue];
	if (volume > 0 && volume != 10000)
		[parts addObject:[NSString stringWithFormat:@"%ld%%", (long)(volume / 100)]];
	if ([participant[@"isCurrentUser"] boolValue])
		[parts insertObject:@"You" atIndex:0];
	if (!parts.count)
		[parts addObject:@"In the call"];
	return [parts componentsJoinedByString:@" · "];
}

- (void)setParticipant:(NSDictionary *)participant inTable:(UITableView *)table {
	NSString *name = participant[@"name"];
	if (!name.length)
		name = [participant[@"kind"] isEqualToString:@"chat"] ? @"Channel" : @"Participant";
	self.nameLabel.text = name;
	self.detailLabel.text = TGGroupCallParticipantDetail(participant);
	BOOL speaking = [participant[@"isSpeaking"] boolValue] &&
			![participant[@"isMutedForAllUsers"] boolValue];
	self.speakingDot.hidden = !speaking;
	self.nameLabel.textColor = [participant[@"isCurrentUser"] boolValue]
			? [TGTheme shared].accentColour : [TGTheme shared].primaryTextColour;
	self.detailLabel.textColor = speaking
			? [TGTheme shared].accentColour : [TGTheme shared].secondaryTextColour;

	int64_t userId = [participant[@"userId"] longLongValue];
	int64_t colourId = userId ?: [participant[@"chatId"] longLongValue];
	if (!userId){
		[self.avatar setName:name colourId:colourId];
		self.avatarUser = 0;
		[self setNeedsLayout];
		return;
	}

	UIImage *photo = [[TGMemberAvatarStore shared] cachedAvatarForUser:userId
																 side:kGCParticipantAvatarSide];
	if (photo){
		[self.avatar setName:name colourId:colourId];
		self.avatar.image = photo;
		self.avatarUser = userId;
		[self setNeedsLayout];
		return;
	}
	[self.avatar setName:name colourId:colourId];
	if (self.avatarUser == userId)
		return;
	self.avatarUser = userId;
	__weak TGGroupCallParticipantCell *weakCell = self;
	__weak UITableView *weakTable = table;
	[[TGMemberAvatarStore shared] loadAvatarForUser:userId side:kGCParticipantAvatarSide
										 completion:^(UIImage *image){
		if (!image)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGGroupCallParticipantCell *cell = weakCell;
			UITableView *owner = weakTable;
			if (!cell || !owner || cell.avatarUser != userId)
				return;
			cell.avatar.image = image;
			NSIndexPath *path = [owner indexPathForCell:cell];
			if (path)
				[owner reloadRowsAtIndexPaths:@[path]
							 withRowAnimation:UITableViewRowAnimationNone];
		});
	}];
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat height = self.contentView.bounds.size.height;
	CGFloat side = kGCParticipantAvatarSide;
	CGFloat x = TGMetricPadMedium;
	self.avatar.frame = CGRectMake(x, TGCenteredOrigin(height, side), side, side);
	x += side + TGMetricPadMedium;

	CGFloat right = TGMetricPadMedium;
	CGFloat dotWidth = self.speakingDot.hidden ? 0 : kGCParticipantDotSide + TGMetricPadSmall;
	CGFloat textWidth = MAX(0, self.contentView.bounds.size.width - x - right - dotWidth);
	CGFloat textHeight = kGCParticipantNameHeight + kGCParticipantTextGap +
			kGCParticipantDetailHeight;
	CGFloat top = TGCenteredOrigin(height, textHeight);
	self.nameLabel.frame = CGRectMake(x, top, textWidth, kGCParticipantNameHeight);
	self.detailLabel.frame = CGRectMake(x, top + kGCParticipantNameHeight +
			kGCParticipantTextGap, textWidth, kGCParticipantDetailHeight);
	if (!self.speakingDot.hidden){
		self.speakingDot.frame = CGRectMake(x + textWidth + TGMetricPadSmall,
				TGCenteredOrigin(height, kGCParticipantDotSide),
				kGCParticipantDotSide, kGCParticipantDotSide);
	}
}

@end

// vim:ft=objc
