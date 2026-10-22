#import "TGChatCell.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>

@implementation TGChatCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;

	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(10, (kRowHeight - kAvatar) / 2, kAvatar, kAvatar)];
	self.avatar.layer.cornerRadius = kAvatar / 2;
	self.avatar.clipsToBounds = YES;
	self.avatar.layer.shouldRasterize = YES;
	self.avatar.layer.rasterizationScale = scale;
	self.avatar.backgroundColor = [[TGTheme shared] fileTileColour];
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.titleLabel.textColor = [[TGTheme shared] primaryTextColour];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = [UIFont systemFontOfSize:14];
	self.previewLabel.textColor = [[TGTheme shared] secondaryTextColour];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = [UIFont systemFontOfSize:12];
	self.dateLabel.textColor = [[TGTheme shared] timeColour];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.dateLabel];

	self.badge = [[UILabel alloc] init];
	self.badge.font = [UIFont boldSystemFontOfSize:13];
	self.badge.textColor = [UIColor whiteColor];
	self.badge.backgroundColor = [[TGTheme shared] badgeColour];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.layer.cornerRadius = 10;
	self.badge.clipsToBounds = YES;
	self.badge.layer.shouldRasterize = YES;
	self.badge.layer.rasterizationScale = scale;
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(10 + kAvatar - 14, (kRowHeight - kAvatar) / 2 + kAvatar - 14, 14, 14)];
	self.onlineDot.backgroundColor = [[TGTheme shared] onlineColour];
	self.onlineDot.layer.cornerRadius = 7;
	self.onlineDot.layer.borderWidth = 2;
	self.onlineDot.layer.shouldRasterize = YES;
	self.onlineDot.layer.rasterizationScale = scale;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	self.pin = [[UIImageView alloc] init];
	self.pin.contentMode = UIViewContentModeScaleAspectFit;
	self.pin.hidden = YES;
	[self.contentView addSubview:self.pin];

	self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat left = kAvatar + 20;
	CGFloat right = 78;   // room for date and the disclosure arrow

	self.dateLabel.frame  = CGRectMake(w - right, 10, right - 8, 16);
	self.titleLabel.frame = CGRectMake(left, 9, w - left - right, 20);
	self.previewLabel.frame = CGRectMake(left, 30, w - left - right + 40, 32);

	// Your own last message is marked, the way it is in their chat item.
	if (!self.tick.hidden){
		CGSize s = [self.dateLabel.text sizeWithFont:self.dateLabel.font];
		self.tick.frame = CGRectMake(w - 8 - s.width - 19, 13, 15, 9);
	}

	if (!self.badge.hidden){
		CGSize s = [self.badge.text sizeWithFont:self.badge.font];
		CGFloat bw = MAX(20, s.width + 12);
		self.badge.frame = CGRectMake(w - right + 30, 36, bw, 20);
	}
	if (!self.pin.hidden)
		self.pin.frame = CGRectMake(w - right + 34, 38, 16, 16);
}

@end
