#import "TGAttachSheet.h"
#import "TGTheme.h"
#import "TGCapabilities.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMargin    = 8.0f;
static const CGFloat kRow       = 52.0f;
static const CGFloat kStrip     = 100.0f;
static const CGFloat kThumb     = 86.0f;
static const NSUInteger kRecentPhotos = 24;

@interface TGAttachSheet ()
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIView *cancelCard;
@property (nonatomic, strong) UIScrollView *strip;
/// Holds the assets alive: an ALAsset is only valid while its library is.
@property (nonatomic, strong) ALAssetsLibrary *library;
@property (nonatomic, strong) NSMutableArray *assets;
@end

@implementation TGAttachSheet

+ (TGAttachSheet *)showInView:(UIView *)view {
	TGAttachSheet *sheet = [[TGAttachSheet alloc] initWithFrame:view.bounds];
	[view addSubview:sheet];
	[sheet present];
	return sheet;
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	TGTheme *theme = [TGTheme shared];

	self.backdrop = [[UIView alloc] initWithFrame:self.bounds];
	self.backdrop.autoresizingMask = self.autoresizingMask;
	self.backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4f];
	self.backdrop.alpha = 0;
	[self.backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(dismiss)]];
	[self addSubview:self.backdrop];

	BOOL strip = [TGCapabilities canShowRecentPhotos];
	CGFloat w = frame.size.width - 2 * kMargin;
	NSArray *titles = @[@"Photo or Video", @"Location", @"Contact"];
	CGFloat cardH = (strip ? kStrip : 0) + kRow * titles.count;

	self.card = [[UIView alloc] initWithFrame:CGRectMake(kMargin, 0, w, cardH)];
	self.card.backgroundColor = [theme cardBackgroundColour];
	self.card.layer.cornerRadius = 12;
	self.card.clipsToBounds = YES;
	[self addSubview:self.card];

	CGFloat y = 0;
	if (strip){
		self.strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, kStrip)];
		self.strip.showsHorizontalScrollIndicator = NO;
		self.strip.alwaysBounceHorizontal = YES;
		self.strip.scrollsToTop = NO;
		[self.card addSubview:self.strip];
		y = kStrip;
		[self loadRecentPhotos];
	}

	for (NSUInteger i = 0; i < titles.count; i++){
		if (y > 0){
			UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 0.5f)];
			hair.backgroundColor = [theme separatorColour];
			[self.card addSubview:hair];
		}
		UIButton *button = [self rowButtonTitled:titles[i] bold:NO frame:CGRectMake(0, y, w, kRow)];
		button.tag = (NSInteger)i;
		[button addTarget:self action:@selector(choiceTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.card addSubview:button];
		y += kRow;
	}

	self.cancelCard = [[UIView alloc] initWithFrame:CGRectMake(kMargin, 0, w, kRow)];
	self.cancelCard.backgroundColor = [theme cardBackgroundColour];
	self.cancelCard.layer.cornerRadius = 12;
	self.cancelCard.clipsToBounds = YES;
	UIButton *cancel = [self rowButtonTitled:@"Cancel" bold:YES frame:self.cancelCard.bounds];
	[cancel addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
	[self.cancelCard addSubview:cancel];
	[self addSubview:self.cancelCard];

	[self placeCardsShown:NO];
	return self;
}

- (UIButton *)rowButtonTitled:(NSString *)title bold:(BOOL)bold frame:(CGRect)frame {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = frame;
	button.titleLabel.font = bold ? [UIFont boldSystemFontOfSize:19] : [UIFont systemFontOfSize:19];
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:[[TGTheme shared] accentColour] forState:UIControlStateNormal];
	[button setTitleColor:[[TGTheme shared] secondaryTextColour] forState:UIControlStateHighlighted];
	return button;
}

- (void)placeCardsShown:(BOOL)shown {
	CGFloat h = self.bounds.size.height;
	CGFloat total = self.card.bounds.size.height + kMargin + kRow + kMargin;
	CGFloat top = shown ? h - total : h;
	CGRect card = self.card.frame;
	card.origin.y = top;
	self.card.frame = card;
	CGRect cancel = self.cancelCard.frame;
	cancel.origin.y = top + card.size.height + kMargin;
	self.cancelCard.frame = cancel;
}

- (void)present {
	[UIView animateWithDuration:0.25 animations:^{
		self.backdrop.alpha = 1;
		[self placeCardsShown:YES];
	}];
}

- (void)dismiss {
	[UIView animateWithDuration:0.2 animations:^{
		self.backdrop.alpha = 0;
		[self placeCardsShown:NO];
	} completion:^(BOOL finished){
		[self removeFromSuperview];
	}];
}

- (void)choiceTapped:(UIButton *)button {
	void (^onChoice)(TGAttachChoice) = self.onChoice;
	[self dismiss];
	if (onChoice)
		onChoice((TGAttachChoice)button.tag);
}

#pragma mark - recent photos

- (void)loadRecentPhotos {
	self.library = [[ALAssetsLibrary alloc] init];
	self.assets = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	[self.library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop){
		if (!group){
			[weakSelf fillStrip];
			return;
		}
		[group setAssetsFilter:[ALAssetsFilter allPhotos]];
		[group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *asset, NSUInteger index, BOOL *stopAssets){
			TGAttachSheet *me = weakSelf;
			if (!me || !asset)
				return;
			[me.assets addObject:asset];
			if (me.assets.count >= kRecentPhotos)
				*stopAssets = YES;
		}];
		*stop = YES;
		[weakSelf fillStrip];
	} failureBlock:^(NSError *error){
		// No access to the library: the strip says so instead of sitting empty.
		[weakSelf showStripMessage:@"Allow access to Photos in Settings to send them from here"];
	}];
}

- (void)showStripMessage:(NSString *)text {
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.strip.bounds, 16, 0)];
	label.text = text;
	label.numberOfLines = 2;
	label.textAlignment = NSTextAlignmentCenter;
	label.font = [UIFont systemFontOfSize:14];
	label.textColor = [[TGTheme shared] secondaryTextColour];
	label.backgroundColor = [UIColor clearColor];
	[self.strip addSubview:label];
}

- (void)fillStrip {
	if (self.strip.subviews.count)
		return;   // the group block can finish twice
	if (!self.assets.count){
		[self showStripMessage:@"No photos yet"];
		return;
	}
	CGFloat x = 7;
	CGFloat y = (kStrip - kThumb) / 2;
	for (NSUInteger i = 0; i < self.assets.count; i++){
		ALAsset *asset = self.assets[i];
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.frame = CGRectMake(x, y, kThumb, kThumb);
		button.tag = (NSInteger)i;
		button.layer.cornerRadius = 6;
		button.clipsToBounds = YES;
		button.imageView.contentMode = UIViewContentModeScaleAspectFill;
		CGImageRef thumb = asset.thumbnail;
		if (thumb)
			[button setImage:[UIImage imageWithCGImage:thumb] forState:UIControlStateNormal];
		[button addTarget:self action:@selector(photoTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.strip addSubview:button];
		x += kThumb + 5;
	}
	self.strip.contentSize = CGSizeMake(x + 2, kStrip);
}

- (void)photoTapped:(UIButton *)button {
	if (button.tag >= (NSInteger)self.assets.count)
		return;
	ALAsset *asset = self.assets[button.tag];
	// The screen-sized rendition is already rotated upright and is what
	// Telegram compresses a photo down to anyway.
	CGImageRef full = asset.defaultRepresentation.fullScreenImage;
	UIImage *image = full ? [UIImage imageWithCGImage:full] : nil;
	void (^onPhoto)(UIImage *) = self.onPhoto;
	[self dismiss];
	if (image && onPhoto)
		onPhoto(image);
}

@end
