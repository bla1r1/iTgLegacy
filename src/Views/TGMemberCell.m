//
// TGMemberCell.m - the picture inset and the name beside it.
//
#import "TGMemberCell.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import "TGMemberAvatarStore.h"

@interface TGMemberCell ()
/// The user whose picture this cell already asked for. A reload while the
/// download is still running would otherwise queue the same row again.
@property (nonatomic, assign) int64_t avatarUser;
@end

@implementation TGMemberCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			   reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault
					 reuseIdentifier:reuseIdentifier])){
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
	}
	return self;
}

- (void)setName:(NSString *)name userId:(int64_t)userId inTable:(UITableView *)tableView {
	self.textLabel.text = name ?: @"";
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

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat side = TGMetricListAvatar;
	CGFloat height = self.contentView.bounds.size.height;
	self.imageView.frame = CGRectMake(TGMetricPad, TGCenteredOrigin(height, side),
									  side, side);
	CGFloat x = TGMetricPad + side + TGMetricPadMedium;
	// To the content view's edge: UIKit sized the label for the picture as
	// it was before the inset, and long names came out cut short.
	CGFloat width = MAX(0, self.contentView.bounds.size.width - x - TGMetricPadMedium);
	CGRect frame = self.textLabel.frame;
	frame.origin.x = x;
	frame.size.width = width;
	self.textLabel.frame = frame;
}

@end
