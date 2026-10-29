#import "TGGalleryViewController.h"
#import "TGUI.h"
#import "TGTheme.h"
#import "TGStyle.h"
#import "TGIcons.h"
#import "TGAlertSheet.h"
#import "TGSnackbar.h"

static const CGFloat kSectionGap = 20.0f;
static const CGFloat kRowHeight = 44.0f;
static const CGFloat kControlGap = 10.0f;
static const CGFloat kLabelHeight = 22.0f;
static const CGFloat kCardHeight = 130.0f;
static const CGFloat kSmallCardHeight = 90.0f;
static const CGFloat kGalleryBubbleW = 230.0f;
static const CGFloat kIncomingBubbleH = 58.0f;
static const CGFloat kOutgoingBubbleH = 68.0f;
static const CGFloat kTimeWidth = 54.0f;
static const CGFloat kAvatarSmallSide = 32.0f;
static const CGFloat kAvatarMediumSide = 44.0f;
static const CGFloat kAvatarLargeSide = 60.0f;

@interface TGGalleryViewController () <UIScrollViewDelegate> {
	UIScrollView *_scrollView;
	UIView *_contentView;

	// Buttons
	TGButton *_primaryBtn;
	TGButton *_secondaryBtn;
	TGButton *_destructiveBtn;
	TGButton *_successBtn;
	TGButton *_ghostBtn;
	TGButton *_busyToggleBtn;

	// Switches
	TGSwitch *_pushSwitch;
	UILabel *_pushLabel;
	TGSwitch *_soundSwitch;
	UILabel *_soundLabel;

	// Sliders
	TGSlider *_volumeSlider;
	UILabel *_volumeLabel;

	// Segmented Control
	TGSegmentedControl *_segmentedControl;
	TGCardView *_previewCard;
	UILabel *_previewCardLabel;

	// Text Fields
	TGTextField *_searchField;
	TGTextField *_inputField;
	TGButton *_errorToggleBtn;

	// Badges
	TGBadge *_notifBadge;
	TGBadge *_accentBadge;
	TGBadge *_mutedBadge;
	TGBadge *_successBadge;

	// Chat Message Bubbles Preview
	UIView *_incomingBubble;
	UIView *_incomingShine;
	UILabel *_incomingBody;
	UILabel *_incomingTime;

	UIView *_outgoingBubble;
	UIView *_outgoingShine;
	UILabel *_outgoingBody;
	UILabel *_outgoingTime;
	UIImageView *_outgoingTicks;
	TGBadge *_outgoingReaction;

	// Reaction Picker & Popup Menu Demo
	TGReactionPicker *_galleryReactionPicker;
	TGButton *_showMenuBtn;

	// Avatars & Search Bar Demo
	TGAvatarView *_smallAvatar;
	TGAvatarView *_onlineAvatar;
	TGAvatarView *_largeAvatar;
	TGSearchBar *_searchHeaderBar;
}
@end

@implementation TGGalleryViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"iOS 6 Design Lab";

	TGTheme *theme = [TGTheme shared];
	[theme styleNavigationBar:self.navigationController.navigationBar];

	if (self.navigationController.viewControllers.firstObject == self) {
		UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                     style:UIBarButtonItemStyleDone
                                                                    target:self
                                                                    action:@selector(dismissSelf)];
		self.navigationItem.rightBarButtonItem = doneItem;
	}

	self.view.backgroundColor = [theme groupedBackgroundColour];

	_scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	_scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_scrollView.alwaysBounceVertical = YES;
	[self.view addSubview:_scrollView];

	_contentView = [[UIView alloc] init];
	[_scrollView addSubview:_contentView];

	[self buildSections];
}

- (void)dismissSelf {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (UILabel *)createSectionHeaderWithTitle:(NSString *)title {
	UILabel *label = [[UILabel alloc] init];
	label.font = TGFontMicroStrong();
	label.textColor = [TGTheme shared].secondaryTextColour;
	label.shadowColor = [TGTheme shared].etchedTextShadowColour;
	label.shadowOffset = CGSizeMake(0, 1.0f);
	label.text = [title uppercaseString];
	return label;
}

- (void)buildSections {
	TGTheme *theme = [TGTheme shared];

	// ── 1. Buttons ──────────────────────────────────────────
	_primaryBtn = [TGButton buttonWithTitle:@"Action" variant:TGButtonVariantPrimary size:TGButtonSizeMedium];
	[_primaryBtn addTarget:self action:@selector(handleActionTap) forControlEvents:UIControlEventTouchUpInside];
	[_contentView addSubview:_primaryBtn];

	_secondaryBtn = [TGButton buttonWithTitle:@"Silver" variant:TGButtonVariantSecondary size:TGButtonSizeMedium];
	[_contentView addSubview:_secondaryBtn];

	_destructiveBtn = [TGButton buttonWithTitle:@"Delete" variant:TGButtonVariantDestructive size:TGButtonSizeSmall];
	[_contentView addSubview:_destructiveBtn];

	_successBtn = [TGButton buttonWithTitle:@"Accept" variant:TGButtonVariantSuccess size:TGButtonSizeSmall];
	[_contentView addSubview:_successBtn];

	_ghostBtn = [TGButton buttonWithTitle:@"Ghost" variant:TGButtonVariantGhost size:TGButtonSizeSmall];
	[_contentView addSubview:_ghostBtn];

	_busyToggleBtn = [TGButton buttonWithTitle:@"Toggle Busy Spinner" variant:TGButtonVariantPrimary size:TGButtonSizeLarge];
	[_busyToggleBtn addTarget:self action:@selector(toggleBusy) forControlEvents:UIControlEventTouchUpInside];
	[_contentView addSubview:_busyToggleBtn];

	// ── 2. Switches ─────────────────────────────────────────
	_pushSwitch = [[TGSwitch alloc] initWithFrame:CGRectZero];
	_pushSwitch.on = YES;
	[_pushSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
	[_contentView addSubview:_pushSwitch];

	_pushLabel = [[UILabel alloc] init];
	_pushLabel.font = TGFontRow();
	_pushLabel.textColor = theme.primaryTextColour;
	_pushLabel.text = @"Push Notifications: ON";
	[_contentView addSubview:_pushLabel];

	_soundSwitch = [[TGSwitch alloc] initWithFrame:CGRectZero];
	_soundSwitch.on = NO;
	[_soundSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
	[_contentView addSubview:_soundSwitch];

	_soundLabel = [[UILabel alloc] init];
	_soundLabel.font = TGFontRow();
	_soundLabel.textColor = theme.primaryTextColour;
	_soundLabel.text = @"Sound Effects: OFF";
	[_contentView addSubview:_soundLabel];

	// ── 3. Sliders ──────────────────────────────────────────
	_volumeSlider = [[TGSlider alloc] initWithFrame:CGRectZero];
	_volumeSlider.minimumValue = 0.0f;
	_volumeSlider.maximumValue = 100.0f;
	_volumeSlider.value = 68.0f;
	_volumeSlider.continuous = YES;
	[_volumeSlider addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
	[_contentView addSubview:_volumeSlider];

	_volumeLabel = [[UILabel alloc] init];
	_volumeLabel.font = TGFontCaptionStrong();
	_volumeLabel.textColor = theme.secondaryTextColour;
	_volumeLabel.text = @"Volume: 68%";
	_volumeLabel.textAlignment = NSTextAlignmentRight;
	[_contentView addSubview:_volumeLabel];

	// ── 4. Segmented Control & Preview Card ──────────────────
	_segmentedControl = [[TGSegmentedControl alloc] initWithItems:@[@"Overview", @"Activity", @"Settings"]];
	[_segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
	[_contentView addSubview:_segmentedControl];

	_previewCard = [[TGCardView alloc] initWithTitle:@"Active Tab" subtitle:@"Live reactive container"];
	_previewCard.interactive = YES;
	__weak typeof(self) weakSelf = self;
	_previewCard.tapHandler = ^{
		[TGAlertSheet showMessage:@"Tactile card received physical tap feedback." title:@"Interactive Card" inView:weakSelf.view];
	};
	[_contentView addSubview:_previewCard];

	_previewCardLabel = [[UILabel alloc] init];
	_previewCardLabel.font = TGFontBody();
	_previewCardLabel.textColor = theme.primaryTextColour;
	_previewCardLabel.text = @"Viewing Overview panel. Select a segment above to animate.";
	[_previewCard.contentContainer addSubview:_previewCardLabel];

	// ── 5. Text Inputs ──────────────────────────────────────
	_searchField = [[TGTextField alloc] initWithFrame:CGRectZero];
	_searchField.placeholder = @"Tactile Search...";
	_searchField.leadingIcon = [TGIcons glyphNamed:@"search" colour:theme.secondaryTextColour side:TGMetricSearchIconSize];
	[_contentView addSubview:_searchField];

	_inputField = [[TGTextField alloc] initWithFrame:CGRectZero];
	_inputField.placeholder = @"Recessed Input Field...";
	[_contentView addSubview:_inputField];

	_errorToggleBtn = [TGButton buttonWithTitle:@"Toggle Error Outline" variant:TGButtonVariantSecondary size:TGButtonSizeSmall];
	[_errorToggleBtn addTarget:self action:@selector(toggleError) forControlEvents:UIControlEventTouchUpInside];
	[_contentView addSubview:_errorToggleBtn];

	// ── 6. Badges ───────────────────────────────────────────
	_notifBadge = [TGBadge badgeWithCount:7];
	[_contentView addSubview:_notifBadge];

	_accentBadge = [TGBadge badgeWithCount:42];
	_accentBadge.variant = TGBadgeVariantAccent;
	[_contentView addSubview:_accentBadge];

	_mutedBadge = [TGBadge badgeWithText:@"SYNC" variant:TGBadgeVariantMuted];
	[_contentView addSubview:_mutedBadge];

	_successBadge = [TGBadge badgeWithText:@"LIVE" variant:TGBadgeVariantSuccess];
	[_contentView addSubview:_successBadge];

	// ── 7. Chat Message Bubbles Preview ──────────────────────
	_incomingBubble = [[UIView alloc] init];
	_incomingBubble.backgroundColor = [theme bubbleTheirsColour];
	_incomingBubble.layer.cornerRadius = TGMetricCornerBubbleSkeuo;
	_incomingBubble.layer.borderWidth = 1.0f;
	_incomingBubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	_incomingBubble.clipsToBounds = YES;
	[_contentView addSubview:_incomingBubble];

	_incomingShine = [[UIView alloc] init];
	_incomingShine.backgroundColor = [theme skeuoShineColour];
	[_incomingBubble addSubview:_incomingShine];

	_incomingBody = [[UILabel alloc] init];
	_incomingBody.font = TGFontRow();
	_incomingBody.textColor = [theme primaryTextColour];
	_incomingBody.shadowColor = [theme etchedTextShadowColour];
	_incomingBody.shadowOffset = CGSizeMake(0, 1.0f);
	_incomingBody.text = @"Did you see the new iOS 6 tactile design system?";
	_incomingBody.numberOfLines = 0;
	[_incomingBubble addSubview:_incomingBody];

	_incomingTime = [[UILabel alloc] init];
	_incomingTime.font = TGFontMicro();
	_incomingTime.textColor = [theme timeColour];
	_incomingTime.shadowColor = [theme etchedTextShadowColour];
	_incomingTime.shadowOffset = CGSizeMake(0, 1.0f);
	_incomingTime.text = @"10:42 AM";
	_incomingTime.textAlignment = NSTextAlignmentRight;
	[_incomingBubble addSubview:_incomingTime];

	_outgoingBubble = [[UIView alloc] init];
	_outgoingBubble.backgroundColor = [theme bubbleMineColour];
	_outgoingBubble.layer.cornerRadius = TGMetricCornerBubbleSkeuo;
	_outgoingBubble.layer.borderWidth = 1.0f;
	_outgoingBubble.layer.borderColor = [theme bubbleBorderColour].CGColor;
	_outgoingBubble.clipsToBounds = YES;
	[_contentView addSubview:_outgoingBubble];

	_outgoingShine = [[UIView alloc] init];
	_outgoingShine.backgroundColor = [theme skeuoShineColour];
	[_outgoingBubble addSubview:_outgoingShine];

	_outgoingBody = [[UILabel alloc] init];
	_outgoingBody.font = TGFontRow();
	_outgoingBody.textColor = [theme onAccentColour];
	_outgoingBody.shadowColor = [theme navBarTextShadowColour];
	_outgoingBody.shadowOffset = CGSizeMake(0, -1.0f);
	_outgoingBody.text = @"Yes! The specular shine and etched letters feel so tangible!";
	_outgoingBody.numberOfLines = 0;
	[_outgoingBubble addSubview:_outgoingBody];

	_outgoingTime = [[UILabel alloc] init];
	_outgoingTime.font = TGFontMicro();
	_outgoingTime.textColor = [theme timeMineColour];
	_outgoingTime.shadowColor = [theme navBarTextShadowColour];
	_outgoingTime.shadowOffset = CGSizeMake(0, -1.0f);
	_outgoingTime.text = @"10:43 AM";
	_outgoingTime.textAlignment = NSTextAlignmentRight;
	[_outgoingBubble addSubview:_outgoingTime];

	_outgoingTicks = [[UIImageView alloc] init];
	_outgoingTicks.image = [TGIcons ticksColour:[theme timeMineColour] read:YES];
	[_outgoingBubble addSubview:_outgoingTicks];

	_outgoingReaction = [TGBadge badgeWithText:@"❤️ 5" variant:TGBadgeVariantAccent];
	[_contentView addSubview:_outgoingReaction];

	// ── 8. Tactile Reaction Bar & Popup Menu ────────────────
	_galleryReactionPicker = [[TGReactionPicker alloc] initWithEmojis:nil selectedEmoji:@"🔥"];
	_galleryReactionPicker.onEmojiSelected = ^(NSString *emoji){
		[TGSnackbar showInView:weakSelf.view text:[NSString stringWithFormat:@"Reacted: %@", emoji] seconds:2 onCommit:nil];
	};
	[_contentView addSubview:_galleryReactionPicker];

	_showMenuBtn = [TGButton buttonWithTitle:@"Open Tactile Menu with Reactions" variant:TGButtonVariantSecondary size:TGButtonSizeLarge];
	[_showMenuBtn addTarget:self action:@selector(openGalleryMenu:) forControlEvents:UIControlEventTouchUpInside];
	[_contentView addSubview:_showMenuBtn];

	// ── 9. Avatars & Search Bar ──────────────────────────────
	_smallAvatar = [[TGAvatarView alloc] initWithSide:kAvatarSmallSide];
	[_smallAvatar setName:@"Alice" colourId:1];
	[_contentView addSubview:_smallAvatar];

	_onlineAvatar = [[TGAvatarView alloc] initWithSide:kAvatarMediumSide];
	[_onlineAvatar setName:@"Bob" colourId:2];
	_onlineAvatar.online = YES;
	[_contentView addSubview:_onlineAvatar];

	_largeAvatar = [[TGAvatarView alloc] initWithSide:kAvatarLargeSide];
	[_largeAvatar setName:@"Telegram" colourId:3];
	[_contentView addSubview:_largeAvatar];

	_searchHeaderBar = [[TGSearchBar alloc] initWithFrame:CGRectZero];
	_searchHeaderBar.placeholder = @"Search chats and contacts...";
	[_contentView addSubview:_searchHeaderBar];
}

- (void)handleActionTap {
	[TGAlertSheet showMessage:@"Skeuomorphic action button tapped!" title:@"TGUI" inView:self.view];
}

- (void)toggleBusy {
	BOOL willBeBusy = !_primaryBtn.isBusy;
	_primaryBtn.busy = willBeBusy;
	_secondaryBtn.busy = willBeBusy;
	[_busyToggleBtn setTitle:willBeBusy ? @"Restore Normal State" : @"Toggle Busy Spinner" forState:UIControlStateNormal];
}

- (void)switchChanged:(TGSwitch *)sender {
	if (sender == _pushSwitch) {
		_pushLabel.text = [NSString stringWithFormat:@"Push Notifications: %@", sender.isOn ? @"ON" : @"OFF"];
	} else if (sender == _soundSwitch) {
		_soundLabel.text = [NSString stringWithFormat:@"Sound Effects: %@", sender.isOn ? @"ON" : @"OFF"];
	}
}

- (void)sliderMoved:(TGSlider *)slider {
	_volumeLabel.text = [NSString stringWithFormat:@"Volume: %.0f%%", slider.value];
}

- (void)segmentChanged:(TGSegmentedControl *)sender {
	NSString *title = [sender titleForSegmentAtIndex:(NSUInteger)sender.selectedSegmentIndex];
	_previewCard.title = [NSString stringWithFormat:@"Tab: %@", title];
	_previewCardLabel.text = [NSString stringWithFormat:@"Switched to '%@' with physical sliding animation.", title];
}

- (void)toggleError {
	_inputField.hasError = !_inputField.hasError;
}

- (void)openGalleryMenu:(UIButton *)sender {
	CGPoint pt = CGPointMake(TGHalf(self.view.bounds.size.width), sender.frame.origin.y);
	NSArray *items = @[
		@{ @"title": @"Reply", @"icon": @"reply" },
		@{ @"title": @"Forward", @"icon": @"forward" },
		@{ @"title": @"Copy Text", @"icon": @"copy" },
		@{ @"title": @"Delete Message", @"icon": @"delete", @"destructive": @YES }
	];
	__weak typeof(self) weakSelf = self;
	[TGPopupMenu showItems:items
				   atPoint:pt
					inView:self.view
				 reactions:[TGReactionPicker defaultReactions]
		  selectedReaction:@"🔥"
				onReaction:^(NSString *emoji) {
		[TGSnackbar showInView:weakSelf.view text:[NSString stringWithFormat:@"Reaction selected: %@", emoji] seconds:2 onCommit:nil];
	} onChoice:^(NSInteger index, NSString *title) {
		[TGSnackbar showInView:weakSelf.view text:[NSString stringWithFormat:@"Action selected: %@", title] seconds:2 onCommit:nil];
	}];
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	[self layoutGallery];
}

- (void)layoutGallery {
	CGFloat w = self.view.bounds.size.width;
	CGFloat inset = TGMetricPadMedium;
	CGFloat contentW = w - inset * 2.0f;
	CGFloat y = TGMetricPadLarge;

	// ── Buttons ──
	CGFloat btnW = TGHalf(contentW - kControlGap);
	_primaryBtn.frame = CGRectMake(inset, y, btnW, TGMetricButtonMediumH);
	_secondaryBtn.frame = CGRectMake(inset + btnW + kControlGap, y, btnW, TGMetricButtonMediumH);
	y += TGMetricButtonMediumH + kControlGap;

	CGFloat smallBtnW = (contentW - TGDoubled(kControlGap)) / 3.0f;
	CGFloat smallBtnStep = smallBtnW + kControlGap;
	_destructiveBtn.frame = CGRectMake(inset, y, smallBtnW, TGMetricButtonSmallH);
	_successBtn.frame = CGRectMake(inset + smallBtnStep, y, smallBtnW, TGMetricButtonSmallH);
	_ghostBtn.frame = CGRectMake(inset + TGDoubled(smallBtnStep), y, smallBtnW, TGMetricButtonSmallH);
	y += TGMetricButtonSmallH + kControlGap;

	_busyToggleBtn.frame = CGRectMake(inset, y, contentW, TGMetricButtonLargeH);
	y += TGMetricButtonLargeH + kSectionGap;

	// ── Switches ──
	_pushSwitch.frame = CGRectMake(inset, y, TGMetricSwitchW, TGMetricSwitchH);
	_pushLabel.frame = CGRectMake(inset + TGMetricSwitchW + TGMetricPadMedium, y, contentW - TGMetricSwitchW - TGMetricPadMedium, TGMetricSwitchH);
	y += TGMetricSwitchH + kControlGap;

	_soundSwitch.frame = CGRectMake(inset, y, TGMetricSwitchW, TGMetricSwitchH);
	_soundLabel.frame = CGRectMake(inset + TGMetricSwitchW + TGMetricPadMedium, y, contentW - TGMetricSwitchW - TGMetricPadMedium, TGMetricSwitchH);
	y += TGMetricSwitchH + kSectionGap;

	// ── Slider ──
	_volumeLabel.frame = CGRectMake(inset, y, contentW, kLabelHeight);
	y += kLabelHeight;
	_volumeSlider.frame = CGRectMake(inset, y, contentW, TGMetricSliderH);
	y += TGMetricSliderH + kSectionGap;

	// ── Segmented Control & Preview Card ──
	_segmentedControl.frame = CGRectMake(inset, y, contentW, TGMetricSegmentedHeight);
	y += TGMetricSegmentedHeight + kControlGap;

	_previewCard.frame = CGRectMake(inset, y, contentW, kCardHeight);
	CGFloat cardInnerW = contentW - TGDoubled(TGMetricPadMedium);
	CGFloat labelTotalH = TGDoubled(kLabelHeight);
	_previewCardLabel.frame = CGRectMake(0, TGMetricPadSmall, cardInnerW, labelTotalH);
	y += kCardHeight + kSectionGap;

	// ── Text Inputs ──
	_searchField.frame = CGRectMake(inset, y, contentW, TGMetricTextFieldH);
	y += TGMetricTextFieldH + kControlGap;

	_inputField.frame = CGRectMake(inset, y, contentW, TGMetricTextFieldH);
	y += TGMetricTextFieldH + kControlGap;

	_errorToggleBtn.frame = CGRectMake(inset, y, contentW, TGMetricButtonSmallH);
	y += TGMetricButtonSmallH + kSectionGap;

	// ── Badges ──
	CGFloat curX = inset;
	CGSize b1Size = [_notifBadge sizeThatFits:CGSizeZero];
	_notifBadge.frame = CGRectMake(curX, y, b1Size.width, TGMetricBadgeH);
	curX += b1Size.width + TGMetricPadMedium;

	CGSize b2Size = [_accentBadge sizeThatFits:CGSizeZero];
	_accentBadge.frame = CGRectMake(curX, y, b2Size.width, TGMetricBadgeH);
	curX += b2Size.width + TGMetricPadMedium;

	CGSize b3Size = [_mutedBadge sizeThatFits:CGSizeZero];
	_mutedBadge.frame = CGRectMake(curX, y, b3Size.width, TGMetricBadgeH);
	curX += b3Size.width + TGMetricPadMedium;

	CGSize b4Size = [_successBadge sizeThatFits:CGSizeZero];
	_successBadge.frame = CGRectMake(curX, y, b4Size.width, TGMetricBadgeH);
	y += TGMetricBadgeH + kSectionGap;

	// ── Chat Message Bubbles Preview ──
	_incomingBubble.frame = CGRectMake(inset, y, kGalleryBubbleW, kIncomingBubbleH);
	_incomingShine.frame = CGRectMake(TGMetricPadSmall, 0.5f, kGalleryBubbleW - TGDoubled(TGMetricPadSmall), 1.0f);
	_incomingBody.frame = CGRectMake(TGMetricPadMedium, TGMetricPadSmall, kGalleryBubbleW - TGDoubled(TGMetricPadMedium), kIncomingBubbleH - TGMetricLineMicro - TGMetricPadSmall);
	_incomingTime.frame = CGRectMake(kGalleryBubbleW - kTimeWidth - TGMetricPadMedium, kIncomingBubbleH - TGMetricLineMicro - TGMetricPadTiny, kTimeWidth, TGMetricLineMicro);
	y += kIncomingBubbleH + kControlGap;

	CGFloat outX = inset + contentW - kGalleryBubbleW;
	_outgoingBubble.frame = CGRectMake(outX, y, kGalleryBubbleW, kOutgoingBubbleH);
	_outgoingShine.frame = CGRectMake(TGMetricPadSmall, 0.5f, kGalleryBubbleW - TGDoubled(TGMetricPadSmall), 1.0f);
	_outgoingBody.frame = CGRectMake(TGMetricPadMedium, TGMetricPadSmall, kGalleryBubbleW - TGDoubled(TGMetricPadMedium), kOutgoingBubbleH - TGMetricLineMicro - TGMetricPadSmall);
	_outgoingTime.frame = CGRectMake(kGalleryBubbleW - kTimeWidth - TGMetricTicksWidth - TGMetricPadMedium, kOutgoingBubbleH - TGMetricLineMicro - TGMetricPadTiny, kTimeWidth, TGMetricLineMicro);
	_outgoingTicks.frame = CGRectMake(kGalleryBubbleW - TGMetricTicksWidth - TGMetricPadMedium, kOutgoingBubbleH - TGMetricLineMicro - TGMetricPadTiny, TGMetricTicksWidth, TGMetricTicksHeight);

	CGSize reactionSize = [_outgoingReaction sizeThatFits:CGSizeZero];
	_outgoingReaction.frame = CGRectMake(outX + TGMetricPadMedium, y + kOutgoingBubbleH - TGMetricPadSmall, reactionSize.width, TGMetricBadgeH);
	y += kOutgoingBubbleH + kSectionGap;

	// ── Reaction Bar & Menu Demo ──
	CGSize rpSize = [_galleryReactionPicker sizeThatFits:CGSizeZero];
	CGFloat rpX = TGCenteredOrigin(contentW, rpSize.width) + inset;
	_galleryReactionPicker.frame = CGRectMake(rpX, y, rpSize.width, TGMetricButtonLargeH);
	y += TGMetricButtonLargeH + kControlGap;

	_showMenuBtn.frame = CGRectMake(inset, y, contentW, TGMetricButtonLargeH);
	y += TGMetricButtonLargeH + kSectionGap;

	// ── Avatars & Search Bar ──
	CGFloat avY = y;
	_smallAvatar.frame = CGRectMake(inset, avY + TGCenteredOrigin(kAvatarLargeSide, kAvatarSmallSide), kAvatarSmallSide, kAvatarSmallSide);
	_onlineAvatar.frame = CGRectMake(inset + kAvatarSmallSide + TGMetricPadLarge, avY + TGCenteredOrigin(kAvatarLargeSide, kAvatarMediumSide), kAvatarMediumSide, kAvatarMediumSide);
	_largeAvatar.frame = CGRectMake(inset + kAvatarSmallSide + TGMetricPadLarge + kAvatarMediumSide + TGMetricPadLarge, avY, kAvatarLargeSide, kAvatarLargeSide);
	y += kAvatarLargeSide + kControlGap;

	_searchHeaderBar.frame = CGRectMake(inset, y, contentW, TGMetricRow);
	y += TGMetricRow + kSectionGap + TGMetricPadLarge;

	_contentView.frame = CGRectMake(0, 0, w, y);
	_scrollView.contentSize = CGSizeMake(w, y);
}

@end
