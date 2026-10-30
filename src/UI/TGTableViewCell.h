//
// TGTableViewCell.h
// TGUI Component Framework
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGCellPosition) {
	TGCellPositionPlain = 0,
	TGCellPositionTop,
	TGCellPositionMiddle,
	TGCellPositionBottom,
	TGCellPositionSingle
};

typedef NS_ENUM(NSInteger, TGCellAccessoryType) {
	TGCellAccessoryNone = 0,
	TGCellAccessoryDisclosureIndicator,
	TGCellAccessoryCheckmark,
	TGCellAccessorySwitch,
	TGCellAccessoryBadge
};

@class TGSwitch;
@class TGBadge;

@interface TGTableViewCell : UITableViewCell

@property (nonatomic, assign) TGCellPosition cellPosition;
@property (nonatomic, assign) TGCellAccessoryType tgAccessoryType;

/// Left icon tile container
@property (nonatomic, strong, readonly) UIImageView *tileIconView;
@property (nonatomic, strong, readonly) UIView *tileContainerView;

/// Right detail label
@property (nonatomic, strong, readonly) UILabel *detailLabel;

/// Right switch (when tgAccessoryType == TGCellAccessorySwitch)
@property (nonatomic, strong, readonly) TGSwitch *switchView;

/// Right badge (when tgAccessoryType == TGCellAccessoryBadge)
@property (nonatomic, strong, readonly) TGBadge *badgeView;

/// Destructive style (red title)
@property (nonatomic, assign) BOOL isDestructive;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier;

/// Helper to configure grouped card position from row and total rows count
- (void)setPositionForRow:(NSInteger)row totalRows:(NSInteger)totalRows;

/// Configure left icon with icon image and tile background color
- (void)setIcon:(UIImage *)icon tileColor:(UIColor *)tileColor;

/// Clear icon tile
- (void)clearIcon;

@end
