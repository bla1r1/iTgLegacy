#import "TGReactionPicker.h"
#import "TGTheme.h"
#import "TGStyle.h"

static const CGFloat kReactionItemWidth   = 26.0f;
static const CGFloat kReactionItemHeight  = 26.0f;
static const CGFloat kReactionGap         = TGMetricPadTiny;
static const CGFloat kReactionMargin      = TGMetricPadTiny;
static const CGFloat kReactionTrayInsetY  = 2.0f;
static const CGFloat kReactionTrayDiffY   = 4.0f;
static const CGFloat kReactionScale       = 1.35f;
static const NSTimeInterval kReactionAnimDuration = TGAnimationDurationFast;

@interface TGReactionPicker () {
	UIView *_trayView;
	NSMutableArray<UIButton *> *_buttons;
	UIView *_selectionIndicator;
}
@end

@implementation TGReactionPicker

+ (NSArray<NSString *> *)defaultReactions {
	return @[
		@"\U00002764", // ❤️
		@"\U0001F44D", // 👍
		@"\U0001F44E", // 👎
		@"\U0001F525", // 🔥
		@"\U0001F602", // 😂
		@"\U0001F44F", // 👏
		@"\U0001F62E"  // 😮
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
	self.backgroundColor = [UIColor clearColor];
	self.clipsToBounds = YES;

	_trayView = [[UIView alloc] init];
	_trayView.backgroundColor = [theme calloutTrayColour];
	_trayView.layer.borderColor = [theme calloutBorderColour].CGColor;
	_trayView.layer.borderWidth = 1.0f;
	[self addSubview:_trayView];

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
	return CGSizeMake(totalW, kReactionItemHeight + kReactionTrayDiffY);
}

- (CGSize)intrinsicContentSize {
	return [self sizeThatFits:CGSizeZero];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.bounds;
	CGFloat w = b.size.width;
	CGFloat h = b.size.height;

	_trayView.frame = CGRectMake(kReactionMargin, kReactionTrayInsetY, w - TGDoubled(kReactionMargin), h - kReactionTrayDiffY);
	_trayView.layer.cornerRadius = TGHalf(h - kReactionTrayDiffY);

	CGFloat totalButtonsW = (CGFloat)_buttons.count * kReactionItemWidth + (CGFloat)(_buttons.count > 0 ? (_buttons.count - 1) : 0) * kReactionGap;
	CGFloat curX = TGHalf(w - totalButtonsW);
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
