//
// TGMediaThumbnailView.m
// TGUI Component Framework
//
#import "TGMediaThumbnailView.h"
#import "TGStyle.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPlayIconSide     = 24.0f;
static const CGFloat kBadgeHeight      = 14.0f;
static const CGFloat kCheckIconSide    = 20.0f;
static const CGFloat kBadgePadH        = 6.0f;
static const CGFloat kMaxDurationWidth = 60.0f;

@interface TGMediaThumbnailView ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *playIconView;
@property (nonatomic, strong) UIView *badgePill;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIView *dimOverlay;
@property (nonatomic, strong) UIImageView *checkView;
@end

@implementation TGMediaThumbnailView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor blackColor];
		self.clipsToBounds = YES;
		
		_imageView = [[UIImageView alloc] initWithFrame:self.bounds];
		_imageView.contentMode = UIViewContentModeScaleAspectFill;
		_imageView.clipsToBounds = YES;
		_imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self addSubview:_imageView];
		
		_playIconView = [[UIImageView alloc] initWithImage:[TGIcons play]];
		_playIconView.contentMode = UIViewContentModeCenter;
		_playIconView.hidden = YES;
		[self addSubview:_playIconView];
		
		_badgePill = [[UIView alloc] init];
		_badgePill.backgroundColor = [[TGTheme shared] hudBackgroundColour];
		_badgePill.layer.cornerRadius = TGMetricCornerSmall;
		_badgePill.clipsToBounds = YES;
		_badgePill.hidden = YES;
		[self addSubview:_badgePill];
		
		_durationLabel = [[UILabel alloc] init];
		_durationLabel.font = TGFontMicro();
		_durationLabel.textColor = [UIColor whiteColor];
		_durationLabel.backgroundColor = [UIColor clearColor];
		[_badgePill addSubview:_durationLabel];
		
		_dimOverlay = [[UIView alloc] initWithFrame:self.bounds];
		_dimOverlay.backgroundColor = [[TGTheme shared] hudBackgroundColour];
		_dimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_dimOverlay.hidden = YES;
		[self addSubview:_dimOverlay];
		
		_checkView = [[UIImageView alloc] initWithImage:[TGIcons selectionCheckboxSelected:YES]];
		_checkView.hidden = YES;
		[self addSubview:_checkView];
	}
	return self;
}

- (void)setImage:(UIImage *)image {
	_image = image;
	_imageView.image = image;
}

- (void)setIsVideo:(BOOL)isVideo {
	_isVideo = isVideo;
	_playIconView.hidden = !isVideo;
	[self setNeedsLayout];
}

- (void)setDurationText:(NSString *)durationText {
	_durationText = [durationText copy];
	_durationLabel.text = durationText;
	_badgePill.hidden = (durationText.length == 0);
	[self setNeedsLayout];
}

- (void)setIsSelected:(BOOL)isSelected {
	_isSelected = isSelected;
	_dimOverlay.hidden = !isSelected;
	_checkView.hidden = !isSelected;
}

- (void)setCornerRadius:(CGFloat)radius {
	_cornerRadius = radius;
	self.layer.cornerRadius = radius;
}

- (void)reset {
	self.image = nil;
	self.isVideo = NO;
	self.durationText = nil;
	self.isSelected = NO;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	
	CGSize size = self.bounds.size;
	if (!_playIconView.hidden) {
		_playIconView.frame = CGRectMake(TGCenteredOrigin(size.width, kPlayIconSide),
										 TGCenteredOrigin(size.height, kPlayIconSide),
										 kPlayIconSide, kPlayIconSide);
	}
	
	if (!_badgePill.hidden && _durationLabel.text.length > 0) {
		CGSize txtSize = [_durationLabel sizeThatFits:CGSizeMake(kMaxDurationWidth, kBadgeHeight)];
		CGFloat pillW = txtSize.width + kBadgePadH;
		_badgePill.frame = CGRectMake(size.width - pillW - TGMetricPadSmall,
									  size.height - kBadgeHeight - TGMetricPadSmall,
									  pillW, kBadgeHeight);
		_durationLabel.frame = CGRectMake(TGMetricPadTiny, 0, txtSize.width, kBadgeHeight);
	}
	
	if (!_checkView.hidden) {
		_checkView.frame = CGRectMake(size.width - kCheckIconSide - TGMetricPadSmall,
									  TGMetricPadSmall,
									  kCheckIconSide, kCheckIconSide);
	}
}

@end
