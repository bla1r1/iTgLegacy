#import "TGReactionPicker.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kReactionItemWidth  = 36.0f;
static const CGFloat kReactionItemHeight = 36.0f;
static const CGFloat kReactionGap        = 4.0f;
static const CGFloat kReactionMargin     = 6.0f;
static const CGFloat kReactionScale      = 1.35f;
static const NSTimeInterval kReactionAnimDuration = 0.12;

@interface TGReactionPicker () {
	UIView *_shineView;
	NSMutableArray<UIButton *> *_buttons;
	UIView *_selectionIndicator;
}
@end

@implementation TGReactionPicker

+ (NSArray<NSString *> *)defaultReactions {
	return @[
		@"\U0001F44D", // 👍
		@"\U00002764", // ❤️
		@"\U0001F525", // 🔥
		@"\U0001F389", // 🎉
		@"\U0001F602", // 😂
		@"\U0001F62E", // 😮
		@"\U0001F622", // 😢
		@"\U0001F44F"  // 👏
	];
}

- (instancetype)initWithEmojis:(NSArray<NSString *> *)emojis selectedEmoji:(NSString *)selectedEmoji {
	self = [super initWithFrame:CGRectZero];
	if (self) {
		_emojis = emojis.count ? [emojis copy] : [[self class] defaultReactions];
		_selectedEmoji = [selectedEmoji copy];
		_buttons = [NSMutableArray array];
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	return [self initWithEmojis:nil selectedEmoji:nil];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		_emojis = [[self class] defaultReactions];
		_buttons = [NSMutableArray array];
		[self commonInit];
	}
	return self;
}

- (void)commonInit {
	TGTheme *theme = [TGTheme shared];
	self.backgroundColor = [theme cardBackgroundColour];
	self.layer.cornerRadius = TGHalf(TGMetricButtonLargeH);
	self.layer.borderWidth = 1.0f;
	self.layer.borderColor = [theme separatorColour].CGColor;

	self.layer.shadowColor = [UIColor blackColor].CGColor;
	self.layer.shadowOpacity = TGMetricShadowMenuOpacity;
	self.layer.shadowRadius = TGMetricShadowMenuRadius;
	self.layer.shadowOffset = TGMetricShadowOffsetMenu;

	_shineView = [[UIView alloc] init];
	_shineView.backgroundColor = [theme skeuoShineColour];
	_shineView.userInteractionEnabled = NO;
	[self addSubview:_shineView];

	_selectionIndicator = [[UIView alloc] init];
	_selectionIndicator.backgroundColor = [theme skeuoShineColour];
	_selectionIndicator.layer.cornerRadius = TGHalf(kReactionItemHeight);
	_selectionIndicator.layer.borderWidth = 1.0f;
	_selectionIndicator.layer.borderColor = [theme accentColour].CGColor;
	_selectionIndicator.hidden = YES;
	[self addSubview:_selectionIndicator];

	[self rebuildButtons];
}

- (void)rebuildButtons {
	for (UIButton *btn in _buttons) {
		[btn removeFromSuperview];
	}
	[_buttons removeAllObjects];

	for (NSUInteger i = 0; i < _emojis.count; i++) {
		NSString *emoji = _emojis[i];
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
		btn.titleLabel.font = TGFontEmoji();
		[btn setTitle:emoji forState:UIControlStateNormal];
		btn.tag = (NSInteger)i;
		[btn addTarget:self action:@selector(emojiTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:btn];
		[_buttons addObject:btn];
	}

	[self setNeedsLayout];
}

- (void)setEmojis:(NSArray<NSString *> *)emojis {
	_emojis = [emojis copy];
	[self rebuildButtons];
}

- (void)setSelectedEmoji:(NSString *)selectedEmoji {
	_selectedEmoji = [selectedEmoji copy];
	[self setNeedsLayout];
}

- (void)emojiTapped:(UIButton *)sender {
	NSInteger idx = sender.tag;
	if (idx < 0 || idx >= (NSInteger)_emojis.count) return;

	NSString *picked = _emojis[(NSUInteger)idx];

	[UIView animateWithDuration:kReactionAnimDuration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
		sender.transform = CGAffineTransformMakeScale(kReactionScale, kReactionScale);
	} completion:^(BOOL finished){
		[UIView animateWithDuration:kReactionAnimDuration
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
			sender.transform = CGAffineTransformIdentity;
		} completion:^(BOOL fin){
			if (self.onEmojiSelected) {
				self.onEmojiSelected(picked);
			}
		}];
	}];
}

- (CGSize)sizeThatFits:(CGSize)size {
	NSUInteger count = _emojis.count;
	if (count == 0) return CGSizeZero;
	CGFloat totalW = TGDoubled(kReactionMargin) + (CGFloat)count * kReactionItemWidth + (CGFloat)(count - 1) * kReactionGap;
	return CGSizeMake(totalW, TGMetricButtonLargeH);
}

- (CGSize)intrinsicContentSize {
	return [self sizeThatFits:CGSizeZero];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.bounds;
	CGFloat w = b.size.width;
	CGFloat h = b.size.height;

	_shineView.frame = CGRectMake(kReactionMargin, 0.5f, w - TGDoubled(kReactionMargin), 1.0f);

	CGFloat curX = kReactionMargin;
	CGFloat btnY = TGCenteredOrigin(h, kReactionItemHeight);

	_selectionIndicator.hidden = YES;

	for (NSUInteger i = 0; i < _buttons.count; i++) {
		UIButton *btn = _buttons[i];
		btn.frame = CGRectMake(curX, btnY, kReactionItemWidth, kReactionItemHeight);

		if (_selectedEmoji && [_selectedEmoji isEqualToString:_emojis[i]]) {
			_selectionIndicator.hidden = NO;
			_selectionIndicator.frame = btn.frame;
			[self bringSubviewToFront:_selectionIndicator];
			[self bringSubviewToFront:btn];
		}

		curX += kReactionItemWidth + kReactionGap;
	}
}

@end
