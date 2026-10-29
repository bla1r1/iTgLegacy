#import "TGAvatarView.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"

static const CGFloat kOnlineDotSide = 12.0f;
static const CGFloat kDefaultAvatarSide = 40.0f;

@interface TGAvatarView () {
	UIImageView *_imageView;
	UIView *_onlineDot;
	UITapGestureRecognizer *_tapGesture;
}
@end

@implementation TGAvatarView

- (instancetype)initWithSide:(CGFloat)side {
	CGFloat resolved = side > 0 ? side : kDefaultAvatarSide;
	self = [super initWithFrame:CGRectMake(0, 0, resolved, resolved)];
	if (self) {
		_avatarSide = resolved;
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	CGFloat s = MAX(frame.size.width, frame.size.height);
	return [self initWithSide:s > 0 ? s : kDefaultAvatarSide];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		_avatarSide = kDefaultAvatarSide;
		[self commonInit];
	}
	return self;
}

- (void)commonInit {
	CGFloat scale = [UIScreen mainScreen].scale;

	_imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, _avatarSide, _avatarSide)];
	_imageView.contentMode = UIViewContentModeScaleAspectFill;
	_imageView.clipsToBounds = YES;
	_imageView.layer.cornerRadius = TGHalf(_avatarSide);
	_imageView.layer.shouldRasterize = YES;
	_imageView.layer.rasterizationScale = scale;
	_imageView.layer.borderWidth = 1.0f;
	_imageView.layer.borderColor = [TGTheme shared].separatorColour.CGColor;
	[self addSubview:_imageView];

	_onlineDot = [[UIView alloc] init];
	_onlineDot.backgroundColor = [TGTheme shared].callAcceptColour;
	_onlineDot.layer.cornerRadius = TGHalf(kOnlineDotSide);
	_onlineDot.layer.borderWidth = 1.0f;
	_onlineDot.layer.borderColor = [TGTheme shared].cardBackgroundColour.CGColor;
	_onlineDot.hidden = YES;
	[self addSubview:_onlineDot];

	_tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAvatarTap)];
	[self addGestureRecognizer:_tapGesture];
	_tapGesture.enabled = NO;
}

- (void)setAvatarSide:(CGFloat)avatarSide {
	if (fabs(_avatarSide - avatarSide) < TGMetricEpsilon) return;
	_avatarSide = avatarSide;
	_imageView.layer.cornerRadius = TGHalf(avatarSide);
	[self setNeedsLayout];
}

- (void)setImage:(UIImage *)image {
	_image = image;
	_imageView.image = image;
}

- (void)setOnline:(BOOL)online {
	_online = online;
	_onlineDot.hidden = !online;
	[self setNeedsLayout];
}

- (void)setTapHandler:(void (^)(void))tapHandler {
	_tapHandler = [tapHandler copy];
	_tapGesture.enabled = (_tapHandler != nil);
}

- (void)handleAvatarTap {
	if (self.tapHandler) {
		self.tapHandler();
	}
}

- (void)setName:(NSString *)name colourId:(int64_t)colourId {
	NSString *initials = @"?";
	if (name.length) {
		initials = [name substringToIndex:1].uppercaseString;
	}
	UIImage *photo = [TGIcons avatarWithInitials:initials size:_avatarSide colourId:colourId];
	self.image = photo;
}

- (void)setImagePath:(NSString *)path {
	if (path.length) {
		[TGIcons loadImageAtPath:path into:_imageView];
	}
}

- (CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(_avatarSide, _avatarSide);
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(_avatarSide, _avatarSide);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat side = _avatarSide;
	_imageView.frame = CGRectMake(0, 0, side, side);
	_imageView.layer.cornerRadius = TGHalf(side);

	if (_online) {
		CGFloat dotX = side - kOnlineDotSide;
		CGFloat dotY = side - kOnlineDotSide;
		_onlineDot.frame = CGRectMake(dotX, dotY, kOnlineDotSide, kOnlineDotSide);
		[self bringSubviewToFront:_onlineDot];
	}
}

@end
