//
// TGTableViewCell.m
// TGUI Component Framework
//
#import "TGTableViewCell.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGSwitch.h"
#import "TGBadge.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kTileSide       = 28.0f;
static const CGFloat kTileIconSide   = 20.0f;
static const CGFloat kTileIconInset  = 4.0f;
static const CGFloat kSwitchWidth    = 51.0f;
static const CGFloat kSwitchHeight   = 31.0f;
static const CGFloat kDetailHeight   = 20.0f;
static const CGFloat kMaxDetailWidth = 100.0f;
static const CGFloat kMinTitleWidth  = 40.0f;
static const CGFloat kMaxBadgeWidth  = 80.0f;
static const CGFloat kMaxBadgeHeight = 24.0f;

@interface TGTableViewCell ()
@property (nonatomic, strong) UIImageView *tileIconView;
@property (nonatomic, strong) UIView *tileContainerView;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) TGSwitch *switchView;
@property (nonatomic, strong) TGBadge *badgeView;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIImageView *checkmarkView;
@end

@implementation TGTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.contentView.backgroundColor = [UIColor clearColor];
		
		_tileContainerView = [[UIView alloc] initWithFrame:CGRectMake(TGMetricPadLarge, TGCenteredOrigin(TGMetricRow, kTileSide), kTileSide, kTileSide)];
		_tileContainerView.layer.cornerRadius = TGMetricCornerSmall;
		_tileContainerView.layer.masksToBounds = YES;
		_tileContainerView.hidden = YES;
		[self.contentView addSubview:_tileContainerView];
		
		_tileIconView = [[UIImageView alloc] initWithFrame:CGRectMake(kTileIconInset, kTileIconInset, kTileIconSide, kTileIconSide)];
		_tileIconView.contentMode = UIViewContentModeScaleAspectFit;
		[_tileContainerView addSubview:_tileIconView];
		
		_detailLabel = [[UILabel alloc] init];
		_detailLabel.font = TGFontCaption();
		_detailLabel.backgroundColor = [UIColor clearColor];
		_detailLabel.textAlignment = NSTextAlignmentRight;
		_detailLabel.hidden = YES;
		[self.contentView addSubview:_detailLabel];
		
		self.textLabel.font = TGFontRow();
		self.textLabel.backgroundColor = [UIColor clearColor];
		
		[self applyTheme];
	}
	return self;
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	if (_isDestructive) {
		self.textLabel.textColor = [theme destructiveColour];
	} else {
		self.textLabel.textColor = [theme primaryTextColour];
	}
	_detailLabel.textColor = [theme secondaryTextColour];
	[self updateBackgrounds];
}

- (void)setIsDestructive:(BOOL)isDestructive {
	_isDestructive = isDestructive;
	[self applyTheme];
}

- (void)setCellPosition:(TGCellPosition)cellPosition {
	_cellPosition = cellPosition;
	[self updateBackgrounds];
}

- (void)setPositionForRow:(NSInteger)row totalRows:(NSInteger)totalRows {
	if (totalRows <= 1) {
		self.cellPosition = TGCellPositionSingle;
	} else if (row == 0) {
		self.cellPosition = TGCellPositionTop;
	} else if (row == totalRows - 1) {
		self.cellPosition = TGCellPositionBottom;
	} else {
		self.cellPosition = TGCellPositionMiddle;
	}
}

- (void)updateBackgrounds {
	if (_cellPosition == TGCellPositionPlain) {
		self.backgroundView = nil;
		self.selectedBackgroundView = nil;
		return;
	}
	
	NSInteger rowIdx = 1;
	NSInteger total = 3;
	switch (_cellPosition) {
		case TGCellPositionTop:
			rowIdx = 0; total = 2; break;
		case TGCellPositionMiddle:
			rowIdx = 1; total = 3; break;
		case TGCellPositionBottom:
			rowIdx = 1; total = 2; break;
		case TGCellPositionSingle:
			rowIdx = 0; total = 1; break;
		default:
			break;
	}
	
	UIImage *norm = [TGTheme skeuomorphicGroupedCellBackgroundForRow:rowIdx totalRows:total highlighted:NO width:0 height:0];
	UIImage *high = [TGTheme skeuomorphicGroupedCellBackgroundForRow:rowIdx totalRows:total highlighted:YES width:0 height:0];
	
	self.backgroundView = [[UIImageView alloc] initWithImage:norm];
	self.selectedBackgroundView = [[UIImageView alloc] initWithImage:high];
}

- (void)setIcon:(UIImage *)icon tileColor:(UIColor *)tileColor {
	if (icon) {
		_tileContainerView.hidden = NO;
		_tileContainerView.backgroundColor = tileColor ?: [TGTheme shared].accentColour;
		_tileIconView.image = icon;
	} else {
		[self clearIcon];
	}
	[self setNeedsLayout];
}

- (void)clearIcon {
	_tileContainerView.hidden = YES;
	_tileIconView.image = nil;
	[self setNeedsLayout];
}

- (void)setTgAccessoryType:(TGCellAccessoryType)tgAccessoryType {
	_tgAccessoryType = tgAccessoryType;
	
	_chevronView.hidden = YES;
	_checkmarkView.hidden = YES;
	_switchView.hidden = YES;
	_badgeView.hidden = YES;
	
	switch (tgAccessoryType) {
		case TGCellAccessoryDisclosureIndicator: {
			if (!_chevronView) {
				_chevronView = [[UIImageView alloc] initWithImage:[TGIcons skeuomorphicDisclosureChevron]];
				_chevronView.highlightedImage = [TGIcons skeuomorphicDisclosureChevronHighlighted];
				[self.contentView addSubview:_chevronView];
			}
			_chevronView.hidden = NO;
			break;
		}
		case TGCellAccessoryCheckmark: {
			if (!_checkmarkView) {
				_checkmarkView = [[UIImageView alloc] initWithImage:[TGIcons selectionCheckboxSelected:YES]];
				[self.contentView addSubview:_checkmarkView];
			}
			_checkmarkView.hidden = NO;
			break;
		}
		case TGCellAccessorySwitch: {
			if (!_switchView) {
				_switchView = [[TGSwitch alloc] initWithFrame:CGRectMake(0, 0, kSwitchWidth, kSwitchHeight)];
				[self.contentView addSubview:_switchView];
			}
			_switchView.hidden = NO;
			break;
		}
		case TGCellAccessoryBadge: {
			if (!_badgeView) {
				_badgeView = [[TGBadge alloc] init];
				[self.contentView addSubview:_badgeView];
			}
			_badgeView.hidden = NO;
			break;
		}
		case TGCellAccessoryNone:
		default:
			break;
	}
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	
	CGFloat contentW = self.contentView.bounds.size.width;
	CGFloat contentH = self.contentView.bounds.size.height;
	CGFloat leftMargin = TGMetricPadLarge;
	
	if (!_tileContainerView.hidden) {
		_tileContainerView.frame = CGRectMake(leftMargin, TGCenteredOrigin(contentH, kTileSide), kTileSide, kTileSide);
		leftMargin += kTileSide + TGMetricPadMedium;
	}
	
	CGFloat rightMargin = contentW - TGMetricPadLarge;
	
	if (!_chevronView.hidden) {
		CGSize chevSize = _chevronView.image.size;
		rightMargin -= chevSize.width;
		_chevronView.frame = CGRectMake(rightMargin, TGCenteredOrigin(contentH, chevSize.height), chevSize.width, chevSize.height);
		rightMargin -= TGMetricPadSmall;
	} else if (!_checkmarkView.hidden) {
		CGSize chkSize = _checkmarkView.image.size;
		rightMargin -= chkSize.width;
		_checkmarkView.frame = CGRectMake(rightMargin, TGCenteredOrigin(contentH, chkSize.height), chkSize.width, chkSize.height);
		rightMargin -= TGMetricPadSmall;
	} else if (!_switchView.hidden) {
		CGSize swSize = _switchView.bounds.size;
		rightMargin -= swSize.width;
		_switchView.frame = CGRectMake(rightMargin, TGCenteredOrigin(contentH, swSize.height), swSize.width, swSize.height);
		rightMargin -= TGMetricPadMedium;
	} else if (!_badgeView.hidden) {
		CGSize bSize = [_badgeView sizeThatFits:CGSizeMake(kMaxBadgeWidth, kMaxBadgeHeight)];
		rightMargin -= bSize.width;
		_badgeView.frame = CGRectMake(rightMargin, TGCenteredOrigin(contentH, bSize.height), bSize.width, bSize.height);
		rightMargin -= TGMetricPadSmall;
	}
	
	if (_detailLabel.text.length > 0 && !_detailLabel.hidden) {
		CGSize detSize = [_detailLabel sizeThatFits:CGSizeMake(kMaxDetailWidth, kDetailHeight)];
		rightMargin -= detSize.width;
		_detailLabel.frame = CGRectMake(rightMargin, TGCenteredOrigin(contentH, kDetailHeight), detSize.width, kDetailHeight);
		rightMargin -= TGMetricPadMedium;
	}
	
	CGFloat titleW = rightMargin - leftMargin;
	if (titleW < kMinTitleWidth) titleW = kMinTitleWidth;
	self.textLabel.frame = CGRectMake(leftMargin, 0, titleW, contentH);
}

@end
