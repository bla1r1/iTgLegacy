//
// TGMemberCell.m - the picture inset and the name beside it.
//
#import "TGMemberCell.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import "TGMemberAvatarStore.h"
#import "TGBadge.h"

/// The gap between a name and the role pill, and the pill's own right inset.
/// Both are spacing-scale values, named here because only this row uses them.
static const CGFloat kMemberBadgeGap = TGMetricPadSmall;

@interface TGMemberCell ()
/// The user whose picture this cell already asked for. A reload while the
/// download is still running would otherwise queue the same row again.
@property (nonatomic, assign) int64_t avatarUser;
/// "Owner" or "Admin" beside the name; hidden for everybody else. A pill,
/// not a count: the list never says how many administrators there are.
@property (nonatomic, strong) TGBadge *roleBadge;
@end

@implementation TGMemberCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault
					 reuseIdentifier:reuseIdentifier])){
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		_roleBadge = [TGBadge badgeWithText:@"" variant:TGBadgeVariantMuted];
		_roleBadge.userInteractionEnabled = NO;
		_roleBadge.hidden = YES;
		[self.contentView addSubview:_roleBadge];
	}
	return self;
}

- (void)setName:(NSString *)name userId:(int64_t)userId inTable:(UITableView *)tableView {
	[self setName:name userId:userId status:nil inTable:tableView];
}

- (void)setName:(NSString *)name
		 userId:(int64_t)userId
		 status:(NSString *)status
		inTable:(UITableView *)tableView {
	[self setName:name userId:userId status:status tag:nil inTable:tableView];
}

- (void)setName:(NSString *)name
		 userId:(int64_t)userId
		 status:(NSString *)status
			tag:(NSString *)tag
		inTable:(UITableView *)tableView {
	self.textLabel.text = name ?: @"";
	[self setRole:status tag:tag];

	CGSize side = CGSizeMake(TGMetricListAvatar, TGMetricListAvatar);

	UIImage *photo = [[TGMemberAvatarStore shared] cachedAvatarForUser:userId
																 side:TGMetricListAvatar];
	if (photo){
		self.avatarUser = userId;
		self.imageView.image = [TGIcons roundedImage:photo size:side
											  radius:TGHalf(TGMetricListAvatar)
											 corners:UIRectCornerAllCorners];
		return;
	}
	// Initials first, always. A member with no photo, a lookup still running
	// and a failed download all keep this face; the row never goes blank.
	self.imageView.image = [TGIcons avatarWithInitials:[TGIcons initialsForTitle:name]
												 size:TGMetricListAvatar
											 colourId:userId];
	if (self.avatarUser == userId)
		return;
	self.avatarUser = userId;

	__weak TGMemberCell *weakCell = self;
	__weak UITableView *weakTable = tableView;
	[[TGMemberAvatarStore shared] loadAvatarForUser:userId side:TGMetricListAvatar
										 completion:^(UIImage *image){
		if (!image)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGMemberCell *cell = weakCell;
			UITableView *table = weakTable;
			if (!cell || !table || cell.avatarUser != userId)
				return;
			NSIndexPath *path = [table indexPathForCell:cell];
			if (path)
				[table reloadRowsAtIndexPaths:@[path]
							 withRowAnimation:UITableViewRowAnimationNone];
		});
	}];
}

/// The badge is the member's real custom title when Telegram sent one, and
/// the role word only as the fallback. "Admin" alone loses the thing the
/// group actually calls that person.
- (void)setRole:(NSString *)status tag:(NSString *)tag {
	NSString *label = [tag isKindOfClass:NSString.class]
			? [tag stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
	if ([status isEqualToString:@"owner"]){
		self.roleBadge.variant = TGBadgeVariantAccent;
		self.roleBadge.text = label.length ? label : @"Owner";
	} else if ([status isEqualToString:@"admin"]){
		self.roleBadge.variant = TGBadgeVariantMuted;
		self.roleBadge.text = label.length ? label : @"Admin";
	} else {
		self.roleBadge.text = nil;
	}
	self.roleBadge.hidden = (self.roleBadge.text.length == 0);
	[self setNeedsLayout];
}

- (void)setRole:(NSString *)status {
	[self setRole:status tag:nil];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat side = TGMetricListAvatar;
	CGFloat height = self.contentView.bounds.size.height;
	self.imageView.frame = CGRectMake(TGMetricPad, TGCenteredOrigin(height, side),
									  side, side);
	CGFloat x = TGMetricPad + side + TGMetricPadMedium;
	// To the content view's edge: UIKit sized the label for the picture as
	// it was before the inset, and long names came out cut short.
	CGFloat contentWidth = self.contentView.bounds.size.width;
	CGFloat badgeWidth = 0;
	if (!self.roleBadge.hidden){
		badgeWidth = [self.roleBadge sizeThatFits:CGSizeZero].width;
		badgeWidth += kMemberBadgeGap;
	}
	CGFloat width = MAX(0, contentWidth - x - TGMetricPadMedium - badgeWidth);
	CGRect frame = self.textLabel.frame;
	frame.origin.x = x;
	frame.size.width = width;
	self.textLabel.frame = frame;

	if (self.roleBadge.hidden)
		return;
	// Sit at the end of the name, not at the end of the row, so the pill
	// reads as part of the name. A long name is clipped by `width` above,
	// which keeps the pill on screen.
	CGSize nameSize = [self.textLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)];
	CGFloat shown = MIN(ceil(nameSize.width), width);
	CGSize badgeSize = [self.roleBadge sizeThatFits:CGSizeZero];
	self.roleBadge.frame = CGRectMake(x + shown + kMemberBadgeGap,
									  TGCenteredOrigin(height, badgeSize.height),
									  badgeSize.width, badgeSize.height);
}

@end
