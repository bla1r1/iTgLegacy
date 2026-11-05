#import "TGTextDraw.h"
#import "TGChatCell.h"
#import "TGChatListRowGeometry.h"
#import "TGTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "TGStyle.h"

static const CGFloat kInset    = TGMetricPadMedium;   // picture from the left edge, text from the right
static const CGFloat kTextLeft = kInset + kAvatar + TGMetricPadMedium;
/// The row carries two lines: the name with the date and ticks beside it,
/// then the preview with the unread badge or the pin beside that.
static const CGFloat kFirstLineTop  = TGMetricPadMedium;
static const CGFloat kSecondLineTop = 32.0f;
static const CGFloat kPreviewMax    = 40.0f;
static const CGFloat kMuteGlyph     = 16.0f;
static const CGFloat kMuteRoom      = 20.0f;
static const CGFloat kPinGlyph      = 16.0f;
static const CGFloat kBadgePad      = TGMetricPadMedium + TGMetricPadTiny;
/// Three buttons fit beside a 320 pt row without clipping.
static const CGFloat kSwipeActionWidth = 76.0f;

@interface TGChatCell ()
@property (nonatomic, strong) NSMutableArray *trailingActionButtons;
@property (nonatomic, assign) CGFloat trailingActionsWidth;
@property (nonatomic, strong) NSMutableArray *leadingActionButtons;
@property (nonatomic, assign) CGFloat leadingActionsWidth;
@property (nonatomic, assign) BOOL swipeActionsOpen;
@property (nonatomic, assign) CGFloat currentSwipeOffset;
/// A close animation must not strip the buttons of a row that was swiped
/// again before the first animation finished.
@property (nonatomic, assign) NSUInteger swipeActionsGeneration;
- (void)removeSwipeActionButtons;
@end

static CGSize TGChatCellTextSize(NSString *text, UIFont *font) {
	return TGLineTextSize(text, font);
}

/// Their titles are a medium weight, not bold; Helvetica Neue has carried one
/// since iOS 5, and bold is the fallback where it does not.
static UIFont *TGChatCellTitleFont(void) {
	return TGFontListTitle();
}

@implementation TGChatCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;
	TGTheme *theme = [TGTheme shared];

	self.backgroundColor = [theme listBackgroundColour];
	self.contentView.backgroundColor = [theme listBackgroundColour];

	self.avatar = [[UIImageView alloc] initWithFrame:CGRectMake(kInset, TGCenteredOrigin(kRowHeight, kAvatar), kAvatar, kAvatar)];
	// Pre-baked circle bitmap: no cornerRadius or shouldRasterize layer on scrolling rows.
	self.avatar.contentMode = UIViewContentModeScaleAspectFill;
	self.avatar.opaque = NO;
	self.avatar.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:self.avatar];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = TGChatCellTitleFont();
	self.titleLabel.textColor = [theme primaryTextColour];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.titleLabel];

	self.previewLabel = [[UILabel alloc] init];
	self.previewLabel.font = TGFontBody();
	self.previewLabel.textColor = [theme secondaryTextColour];
	self.previewLabel.numberOfLines = 2;
	self.previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:self.previewLabel];

	self.dateLabel = [[UILabel alloc] init];
	self.dateLabel.font = TGFontSubhead();
	self.dateLabel.textColor = [theme listDateColour];
	self.dateLabel.textAlignment = NSTextAlignmentRight;
	[self.contentView addSubview:self.dateLabel];

	self.badge = [[UILabel alloc] init];
	self.badge.font = TGFontCaptionStrong();
	self.badge.textColor = [[TGTheme shared] onAccentColour];
	self.badge.backgroundColor = [theme badgeColour];
	self.badge.textAlignment = NSTextAlignmentCenter;
	self.badge.layer.cornerRadius = TGHalf(TGMetricChatBadgeHeight);
	self.badge.clipsToBounds = YES;

	self.editCheck = [[UILabel alloc] init];
	self.editCheck.text = @"\u2713";
	self.editCheck.font = TGFontCaptionStrong();
	self.editCheck.textColor = [[TGTheme shared] onAccentColour];
	self.editCheck.backgroundColor = [theme accentColour];
	self.editCheck.textAlignment = NSTextAlignmentCenter;
	self.editCheck.layer.cornerRadius = TGHalf(TGMetricChatBadgeHeight);
	self.editCheck.clipsToBounds = YES;
	self.editCheck.hidden = YES;
	[self.contentView addSubview:self.editCheck];
	self.badge.hidden = YES;
	[self.contentView addSubview:self.badge];

	self.mentionBadge = [[UILabel alloc] init];
	self.mentionBadge.text = @"@";
	self.mentionBadge.font = TGFontCaptionStrong();
	self.mentionBadge.textColor = [[TGTheme shared] onAccentColour];
	self.mentionBadge.backgroundColor = [theme accentColour];
	self.mentionBadge.textAlignment = NSTextAlignmentCenter;
	self.mentionBadge.layer.cornerRadius = TGHalf(TGMetricChatBadgeHeight);
	self.mentionBadge.clipsToBounds = YES;
	self.mentionBadge.hidden = YES;
	[self.contentView addSubview:self.mentionBadge];

	CGFloat dot = 15;
	self.onlineDot = [[UIView alloc] initWithFrame:
			CGRectMake(kInset + kAvatar - dot, TGCenteredOrigin(kRowHeight, kAvatar) + kAvatar - dot, dot, dot)];
	self.onlineDot.backgroundColor = [theme onlineColour];
	self.onlineDot.layer.cornerRadius = TGHalf(dot);
	self.onlineDot.layer.borderWidth = TGMetricBorderThick;
	self.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;
	self.onlineDot.hidden = YES;
	[self.contentView addSubview:self.onlineDot];

	self.tick = [[UIImageView alloc] init];
	self.tick.hidden = YES;
	[self.contentView addSubview:self.tick];

	self.pin = [[UIImageView alloc] init];
	self.pin.contentMode = UIViewContentModeScaleAspectFit;
	self.pin.hidden = YES;
	[self.contentView addSubview:self.pin];

	self.muteIcon = [[UIImageView alloc] init];
	self.muteIcon.contentMode = UIViewContentModeScaleAspectFit;
	self.muteIcon.hidden = YES;
	[self.contentView addSubview:self.muteIcon];

	// The table's own separator runs under the picture and cannot be inset
	// before iOS 7, so the row draws its own.
	self.separator = [[UIView alloc] init];
	self.separator.backgroundColor = [theme separatorColour];
	[self.contentView addSubview:self.separator];

	// No disclosure arrow: a chat row is not a settings row.
	self.accessoryType = UITableViewCellAccessoryNone;
	return self;
}

- (void)setPreview:(NSString *)text author:(NSString *)author {
	TGTheme *theme = [TGTheme shared];
	text = text ?: @"";
	if (!author.length || ![self.previewLabel respondsToSelector:@selector(setAttributedText:)]) {
		self.previewLabel.text = author.length ? [NSString stringWithFormat:@"%@: %@", author, text] : text;
		return;
	}
	NSString *prefix = [author stringByAppendingString:@": "];
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc]
			initWithString:[prefix stringByAppendingString:text]
				attributes:@{NSFontAttributeName: self.previewLabel.font,
							 NSForegroundColorAttributeName: [theme secondaryTextColour]}];
	[line addAttribute:NSForegroundColorAttributeName
				 value:[theme primaryTextColour]
				 range:NSMakeRange(0, prefix.length)];
	self.previewLabel.attributedText = line;
}

- (void)setDraftPreview:(NSString *)draftText {
	TGTheme *theme = [TGTheme shared];
	draftText = draftText ?: @"";
	NSString *prefix = @"Draft: ";
	if (![self.previewLabel respondsToSelector:@selector(setAttributedText:)]) {
		self.previewLabel.text = [prefix stringByAppendingString:draftText];
		self.previewLabel.textColor = [theme destructiveColour];
		return;
	}
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc]
			initWithString:[prefix stringByAppendingString:draftText]
				attributes:@{NSFontAttributeName: self.previewLabel.font,
							 NSForegroundColorAttributeName: [theme secondaryTextColour]}];
	[line addAttribute:NSForegroundColorAttributeName
				 value:[theme destructiveColour]
				 range:NSMakeRange(0, prefix.length)];
	self.previewLabel.attributedText = line;
}

- (void)layoutSubviews {
	// UIKit sets the content view's frame in here, and a frame set under a
	// transform lands somewhere else: the swiped row ended up 228 pt to the right
	// of where it was slid to, covering the buttons it had just uncovered.
	CGAffineTransform slid = self.contentView.transform;
	BOOL isSlid = !CGAffineTransformIsIdentity(slid);
	if (isSlid)
		self.contentView.transform = CGAffineTransformIdentity;
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width;
	CGFloat h = self.contentView.bounds.size.height;
	CGFloat right = w - kInset;

	// The first line: the date pinned to the right edge, the ticks before it,
	// and the title taking whatever is left.
	CGSize date = TGChatCellTextSize(self.dateLabel.text, self.dateLabel.font);
	self.dateLabel.frame = CGRectMake(right - ceilf(date.width), kFirstLineTop + TGMetricBorderWidth,
			ceilf(date.width), TGMetricLineBody);
	CGFloat titleRight = CGRectGetMinX(self.dateLabel.frame) - TGMetricChatCellDateGap;
	if (!self.tick.hidden) {
		self.tick.frame = CGRectMake(titleRight - TGMetricTicksWidth,
				kFirstLineTop + TGMetricPadSmall, TGMetricTicksWidth,
				TGMetricTicksHeight);
		titleRight -= (TGMetricTicksWidth + TGMetricPadSmall);
	}

	CGFloat muteW = self.muteIcon.hidden ? 0 : kMuteRoom;
	CGFloat titleRoom = MAX(0, titleRight - kTextLeft - muteW);
	CGFloat titleW = MIN(ceilf(TGChatCellTextSize(self.titleLabel.text, self.titleLabel.font).width), titleRoom);
	self.titleLabel.frame = CGRectMake(kTextLeft, kFirstLineTop, titleW, TGMetricLineRow);
	if (!self.muteIcon.hidden)
		self.muteIcon.frame = CGRectMake(kTextLeft + titleW + TGMetricBubbleRowInset,
				kFirstLineTop + TGMetricPadTiny, kMuteGlyph, kMuteGlyph);

	// The second line: the unread count at the right edge, the pin beside it,
	// and the preview wrapping onto a second line up to whichever is leftmost.
	// The two are not alternatives - a pinned chat with unread messages keeps
	// both, which is what the official row shows.
	CGFloat badgeW = 0;
	if (!self.badge.hidden) {
		CGSize s = TGChatCellTextSize(self.badge.text, self.badge.font);
		badgeW = MAX(TGMetricChatBadgeHeight, ceilf(s.width) + kBadgePad);
	}
	CGRect badgeFrame = CGRectZero, pinFrame = CGRectZero;
	CGFloat previewRight = right;
	TGChatListRowAccessories(right, TGMetricChatBadgeTop,
			!self.badge.hidden, badgeW, TGMetricChatBadgeHeight,
			!self.pin.hidden, kPinGlyph, TGMetricPad,
			&badgeFrame, &pinFrame, &previewRight);
	self.badge.frame = badgeFrame;
	self.pin.frame = pinFrame;

	if (!self.mentionBadge.hidden) {
		CGFloat mentionSide = TGMetricChatBadgeHeight;
		CGFloat mentionX = previewRight - mentionSide;
		self.mentionBadge.frame = CGRectMake(mentionX, TGMetricChatBadgeTop, mentionSide, mentionSide);
		previewRight = mentionX - TGMetricPadSmall;
	}

	CGFloat previewW = MAX(0, previewRight - kTextLeft);
	CGSize fit = [self.previewLabel sizeThatFits:CGSizeMake(previewW, kPreviewMax)];
	self.previewLabel.frame = CGRectMake(kTextLeft, kSecondLineTop, previewW,
			MIN(ceilf(fit.height), kPreviewMax - TGMetricPadTiny));

	CGFloat checkSide = TGMetricChatBadgeHeight;
	self.editCheck.frame = CGRectMake(w - checkSide - TGMetricPad,
			TGCenteredOrigin(h, checkSide), checkSide, checkSide);

	CGFloat hair = TGMetricHairline;
	self.separator.frame = CGRectMake(kTextLeft, h - hair, w - kTextLeft, hair);

	// Layout trailing buttons along the right edge
	if (self.trailingActionButtons.count){
		CGFloat x = self.bounds.size.width - self.trailingActionsWidth;
		for (UIButton *button in self.trailingActionButtons){
			button.frame = CGRectMake(x, 0, kSwipeActionWidth, self.bounds.size.height);
			x += kSwipeActionWidth;
		}
	}
	// Layout leading buttons along the left edge
	if (self.leadingActionButtons.count){
		CGFloat x = 0;
		for (UIButton *button in self.leadingActionButtons){
			button.frame = CGRectMake(x, 0, kSwipeActionWidth, self.bounds.size.height);
			x += kSwipeActionWidth;
		}
	}
	if (isSlid)
		self.contentView.transform = slid;
}

- (void)applyTheme {
	TGTheme *theme = [TGTheme shared];
	self.backgroundColor = [theme listBackgroundColour];
	self.contentView.backgroundColor = [theme listBackgroundColour];
	self.titleLabel.textColor = [theme primaryTextColour];
	self.previewLabel.textColor = [theme secondaryTextColour];
	self.dateLabel.textColor = [theme listDateColour];
	self.badge.backgroundColor = [theme badgeColour];
	self.mentionBadge.backgroundColor = [theme accentColour];
	self.onlineDot.backgroundColor = [theme onlineColour];
	self.onlineDot.layer.borderColor = [theme listBackgroundColour].CGColor;
	self.separator.backgroundColor = [theme separatorColour];
}

- (CGFloat)swipeActionsWidth {
	return self.trailingActionsWidth + self.leadingActionsWidth;
}

- (void)revealSwipeActionsWithTrailingTitles:(NSArray *)trailingTitles
                             trailingColours:(NSArray *)trailingColours
                               leadingTitles:(NSArray *)leadingTitles
                              leadingColours:(NSArray *)leadingColours
                                      target:(id)target
                                      action:(SEL)action {
	self.swipeActionsGeneration++;
	[self removeSwipeActionButtons];

	// Trailing buttons (shown when dragging left, offset < 0)
	if (trailingTitles.count){
		self.trailingActionButtons = [NSMutableArray arrayWithCapacity:trailingTitles.count];
		for (NSUInteger i = 0; i < trailingTitles.count; i++){
			UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
			button.titleLabel.font = TGFontCaptionStrong();
			[button setTitleColor:[[TGTheme shared] onAccentColour]
						 forState:UIControlStateNormal];
			[button addTarget:target action:action
			 forControlEvents:UIControlEventTouchUpInside];
			[button setTitle:i < trailingTitles.count ? trailingTitles[i] : @""
					forState:UIControlStateNormal];
			if (i < trailingColours.count)
				button.backgroundColor = trailingColours[i];
			[self.contentView.superview insertSubview:button belowSubview:self.contentView];
			[self.trailingActionButtons addObject:button];
		}
		self.trailingActionsWidth = (CGFloat)trailingTitles.count * kSwipeActionWidth;
	}

	// Leading buttons (shown when dragging right, offset > 0)
	if (leadingTitles.count){
		self.leadingActionButtons = [NSMutableArray arrayWithCapacity:leadingTitles.count];
		for (NSUInteger i = 0; i < leadingTitles.count; i++){
			UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
			button.titleLabel.font = TGFontCaptionStrong();
			[button setTitleColor:[[TGTheme shared] onAccentColour]
						 forState:UIControlStateNormal];
			[button addTarget:target action:action
			 forControlEvents:UIControlEventTouchUpInside];
			[button setTitle:i < leadingTitles.count ? leadingTitles[i] : @""
					forState:UIControlStateNormal];
			if (i < leadingColours.count)
				button.backgroundColor = leadingColours[i];
			[self.contentView.superview insertSubview:button belowSubview:self.contentView];
			[self.leadingActionButtons addObject:button];
		}
		self.leadingActionsWidth = (CGFloat)leadingTitles.count * kSwipeActionWidth;
	}

	self.clipsToBounds = YES;
	self.swipeActionsOpen = NO;
	self.currentSwipeOffset = 0;
	self.contentView.transform = CGAffineTransformIdentity;
	[self setNeedsLayout];
}

- (void)revealSwipeActionsWithTitles:(NSArray *)titles
                             colours:(NSArray *)colours
                              target:(id)target
                              action:(SEL)action {
	[self revealSwipeActionsWithTrailingTitles:titles
	                           trailingColours:colours
	                             leadingTitles:nil
	                            leadingColours:nil
	                                    target:target
	                                    action:action];
}

- (void)setSwipeActionsOffset:(CGFloat)offset {
	if (offset < 0){
		// Dragging left: show trailing, hide leading
		for (UIButton *b in self.leadingActionButtons) b.hidden = YES;
		for (UIButton *b in self.trailingActionButtons) b.hidden = NO;
		CGFloat maxOffset = self.trailingActionsWidth;
		if (maxOffset > 0 && offset < -maxOffset)
			offset = -maxOffset;
	} else if (offset > 0){
		// Dragging right: show leading, hide trailing
		for (UIButton *b in self.leadingActionButtons) b.hidden = NO;
		for (UIButton *b in self.trailingActionButtons) b.hidden = YES;
		CGFloat maxOffset = self.leadingActionsWidth;
		if (maxOffset > 0 && offset > maxOffset)
			offset = maxOffset;
	}
	self.currentSwipeOffset = offset;
	self.contentView.transform = CGAffineTransformMakeTranslation(offset, 0);
}

- (void)openTrailingSwipeActionsAnimated:(BOOL)animated {
	CGFloat width = self.trailingActionsWidth;
	if (width <= 0)
		return;
	for (UIButton *b in self.leadingActionButtons) b.hidden = YES;
	for (UIButton *b in self.trailingActionButtons) b.hidden = NO;
	self.swipeActionsOpen = YES;
	self.currentSwipeOffset = -width;
	if (!animated){
		self.contentView.transform = CGAffineTransformMakeTranslation(-width, 0);
		return;
	}
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.contentView.transform = CGAffineTransformMakeTranslation(-width, 0);
	}];
}

- (void)openLeadingSwipeActionsAnimated:(BOOL)animated {
	CGFloat width = self.leadingActionsWidth;
	if (width <= 0)
		return;
	for (UIButton *b in self.leadingActionButtons) b.hidden = NO;
	for (UIButton *b in self.trailingActionButtons) b.hidden = YES;
	self.swipeActionsOpen = YES;
	self.currentSwipeOffset = width;
	if (!animated){
		self.contentView.transform = CGAffineTransformMakeTranslation(width, 0);
		return;
	}
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.contentView.transform = CGAffineTransformMakeTranslation(width, 0);
	}];
}

- (void)openSwipeActionsAnimated:(BOOL)animated {
	[self openTrailingSwipeActionsAnimated:animated];
}

- (void)closeSwipeActionsAnimated:(BOOL)animated {
	self.swipeActionsOpen = NO;
	self.currentSwipeOffset = 0;
	NSUInteger generation = ++self.swipeActionsGeneration;
	void (^finish)(void) = ^{
		if (self.swipeActionsGeneration != generation)
			return;
		[self removeSwipeActionButtons];
	};
	if (!animated || (!self.trailingActionButtons.count && !self.leadingActionButtons.count)){
		self.contentView.transform = CGAffineTransformIdentity;
		finish();
		return;
	}
	[UIView animateWithDuration:TGAnimationDurationFast animations:^{
		self.contentView.transform = CGAffineTransformIdentity;
	} completion:^(BOOL finished){
		finish();
	}];
}

- (void)removeSwipeActionButtons {
	for (UIButton *button in self.trailingActionButtons)
		[button removeFromSuperview];
	self.trailingActionButtons = nil;
	self.trailingActionsWidth = 0;

	for (UIButton *button in self.leadingActionButtons)
		[button removeFromSuperview];
	self.leadingActionButtons = nil;
	self.leadingActionsWidth = 0;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	[super setEditing:editing animated:animated];
	if (editing)
		[self closeSwipeActionsAnimated:NO];
	[self updateEditCheck];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
	[super setSelected:selected animated:animated];
	if (selected)
		[self closeSwipeActionsAnimated:NO];
	[self updateEditCheck];
}

- (void)updateEditCheck {
	self.editCheck.hidden = !(self.editing && self.selected);
	self.dateLabel.hidden = self.editing;
	[self setNeedsLayout];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self closeSwipeActionsAnimated:NO];
	self.editCheck.hidden = YES;
	self.dateLabel.hidden = NO;
}

@end
