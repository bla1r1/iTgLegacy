#import "TGCallViewController.h"
#import "TGCall.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCapabilities.h"
#import "TGUIFormat.h"
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonDigest.h>
#import "TGStyle.h"
#import "TGAlertSheet.h"

/// The bar a minimised call leaves at the top of the app. A call does not
/// stop when its screen is put away, and Telegram keeps a way back to it; the
/// bar is that way. It is a separate window because the call screen is gone
/// by then and the chat list must still take touches underneath.
@interface TGCallMiniBar : NSObject
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, copy) NSString *peerName;
+ (instancetype)shared;
- (void)showForUserId:(int64_t)userId name:(NSString *)name;
- (void)hide;
@end

@interface TGCallMiniBar ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation TGCallMiniBar

+ (instancetype)shared {
	static TGCallMiniBar *bar = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ bar = [[TGCallMiniBar alloc] init]; });
	return bar;
}

- (void)showForUserId:(int64_t)userId name:(NSString *)name {
	self.userId = userId;
	self.peerName = name ?: @"";
	if (!self.window)
		[self buildWindow];
	[self updateTitle];
	self.window.hidden = NO;
	[self.timer invalidate];
	self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
			selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (CGRect)barFrame {
	CGRect screen = [UIScreen mainScreen].bounds;
	UIInterfaceOrientation orientation =
			[UIApplication sharedApplication].statusBarOrientation;
	if (UIInterfaceOrientationIsLandscape(orientation))
		return CGRectMake(0, 0, screen.size.height, TGMetricCallBarHeight);
	return CGRectMake(0, 0, screen.size.width, TGMetricCallBarHeight);
}

- (void)buildWindow {
	UIWindow *window = [[UIWindow alloc] initWithFrame:[self barFrame]];
	window.windowLevel = UIWindowLevelStatusBar + 1;
	window.backgroundColor = [UIColor clearColor];

	UIViewController *root = [[UIViewController alloc] init];
	root.view.backgroundColor = [[TGTheme shared] barColour];
	root.view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;

	self.button = [UIButton buttonWithType:UIButtonTypeCustom];
	self.button.frame = root.view.bounds;
	self.button.autoresizingMask = UIViewAutoresizingFlexibleWidth |
			UIViewAutoresizingFlexibleHeight;
	self.button.titleLabel.font = TGFontBodyStrong();
	[self.button setTitleColor:[[TGTheme shared] barTitleColour]
					  forState:UIControlStateNormal];
	[self.button addTarget:self action:@selector(returnToCall)
		  forControlEvents:UIControlEventTouchUpInside];
	[root.view addSubview:self.button];

	window.rootViewController = root;
	self.window = window;

	[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(orientationChanged:)
				name:UIApplicationDidChangeStatusBarOrientationNotification
			  object:nil];
}

- (void)orientationChanged:(NSNotification *)note {
	self.window.frame = [self barFrame];
	self.button.frame = self.window.rootViewController.view.bounds;
}

- (void)updateTitle {
	NSString *name = self.peerName.length ? self.peerName : @"Call";
	TGCallState state = [TGCall shared].state;
	if (state == TGCallStatePending) {
		[self.button setTitle:[NSString stringWithFormat:@"%@  ·  Ringing", name]
					 forState:UIControlStateNormal];
		return;
	}
	if (state == TGCallStateEstablished) {
		[self.button setTitle:[NSString stringWithFormat:@"%@  ·  %@", name,
				TGUIFormatCallDuration([[TGCall shared] duration])]
					 forState:UIControlStateNormal];
		return;
	}
	[self.button setTitle:[NSString stringWithFormat:@"%@  ·  Connecting", name]
				 forState:UIControlStateNormal];
}

- (void)tick:(NSTimer *)timer {
	TGCallState state = [TGCall shared].state;
	if (state == TGCallStateNone || state == TGCallStateEnded ||
			state == TGCallStateFailed) {
		[self hide];
		return;
	}
	[self updateTitle];
}

- (void)returnToCall {
	int64_t userId = self.userId;
	NSString *name = self.peerName;
	[self hide];
	[TGCallViewController presentForUserId:userId name:name outgoing:NO];
}

- (void)hide {
	[self.timer invalidate];
	self.timer = nil;
	self.window.hidden = YES;
	self.window.rootViewController = nil;
	self.window = nil;
	self.button = nil;
	self.peerName = nil;
	self.userId = 0;
}

@end

@interface TGCallViewController ()
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *peerName;
@property (nonatomic, assign) BOOL outgoing;

@property (nonatomic, strong) CAGradientLayer *bgLayer;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UIImageView *fallbackAvatar;
@property (nonatomic, strong) UIView *shadeView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *keyButton;
@property (nonatomic, copy) NSString *keyEmojiText;

@property (nonatomic, strong) UIView *keyCard;
@property (nonatomic, strong) UILabel *keyCardEmoji;
@property (nonatomic, strong) UILabel *keyCardTitle;
@property (nonatomic, strong) UILabel *keyCardBody;

@property (nonatomic, strong) UIButton *speakerBtn;
@property (nonatomic, strong) UIButton *videoBtn;
@property (nonatomic, strong) UIButton *micBtn;
@property (nonatomic, strong) UIButton *endBtn;
@property (nonatomic, strong) UIButton *acceptBtn;

@property (nonatomic, strong) UILabel *speakerLbl;
@property (nonatomic, strong) UILabel *videoLbl;
@property (nonatomic, strong) UILabel *micLbl;
@property (nonatomic, strong) UILabel *endLbl;
@property (nonatomic, strong) UILabel *acceptLbl;

@property (nonatomic, assign) BOOL speakerOn;
@property (nonatomic, strong) UILabel *lastCreatedLabel;
@property (nonatomic, assign) BOOL photoRequested;
@property (nonatomic, assign) BOOL photoUserEnsured;

/// Which variant of the control row `updateLayoutForCallActive:` last built,
/// so a rotation rebuilds the same one instead of guessing from the state.
@property (nonatomic, assign) BOOL callRowActive;

@property (nonatomic, strong) NSTimer *ticker;
/// When the call was answered, for the rating prompt after it; TGCall's own
/// duration is gone by then, teardown having cleared its start time.
@property (nonatomic, strong) NSDate *connectedAt;
@property (nonatomic, assign) BOOL ratedCall;
@end

// A gradient layer wants CGColorRefs; the palette hands out UIColors.
static NSArray *TGCallGradient(NSArray *colours) {
    NSMutableArray *refs = [NSMutableArray arrayWithCapacity:colours.count];
    for (UIColor *colour in colours)
        [refs addObject:(id)colour.CGColor];
    return refs;
}

@implementation TGCallViewController

+ (void)presentForUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window.rootViewController) {
            for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
                if (candidate.rootViewController && !candidate.hidden) {
                    window = candidate;
                    break;
                }
            }
        }
        UIViewController *top = window.rootViewController;
        if (!top)
            return;
        while (top.presentedViewController)
            top = top.presentedViewController;

        if ([top isKindOfClass:[TGCallViewController class]])
            return;

        TGCallViewController *screen = [[TGCallViewController alloc]
                initWithUserId:userId name:name outgoing:outgoing];
        [top presentViewController:screen animated:YES completion:nil];
    });
}

- (instancetype)initWithUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
    if ((self = [super init])){
        _userId = userId;
        _peerName = name ?: @"";
        _outgoing = outgoing;
    }
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];

    // The peer's own picture fills the screen, the way Telegram's call screen
    // is the person rather than a card of controls. It starts hidden: until
    // the picture arrives the gradient behind it is the backdrop.
    self.photoView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.photoView.contentMode = UIViewContentModeScaleAspectFill;
    self.photoView.clipsToBounds = YES;
    self.photoView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.photoView];

    self.shadeView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.shadeView.backgroundColor = [[TGTheme shared] scrimColour];
    self.shadeView.userInteractionEnabled = NO;
    self.shadeView.hidden = YES;
    [self.view addSubview:self.shadeView];

    // No profile picture still gets a face: the same initial disc the chat
    // list draws, so the screen is a person rather than an empty gradient.
    self.fallbackAvatar = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.fallbackAvatar.contentMode = UIViewContentModeScaleAspectFill;
    self.fallbackAvatar.layer.cornerRadius = TGHalf(TGMetricCallAvatarSide);
    self.fallbackAvatar.clipsToBounds = YES;
    NSString *initials = [TGIcons initialsForTitle:
            self.peerName.length ? self.peerName : @"?"];
    self.fallbackAvatar.image = [TGIcons avatarWithInitials:
            initials.length ? initials : @"?"
            size:TGMetricCallAvatarSide colourId:self.userId];
    [self.view addSubview:self.fallbackAvatar];

    self.bgLayer = [CAGradientLayer layer];
    self.bgLayer.frame = self.view.bounds;
    self.bgLayer.colors = TGCallGradient([[TGTheme shared] callGradientColours]);
    [self.view.layer insertSublayer:self.bgLayer above:self.photoView.layer];

    // Back to the chat without ending the call. Telegram's call screen keeps
    // a chevron in the corner for exactly this.
    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backButton.frame = CGRectMake(TGMetricPadSmall, TGMetricPadWide,
            TGMetricCallLabelWidth, TGMetricRow);
    self.backButton.titleLabel.font = TGFontBody();
    [self.backButton setTitle:@"Back" forState:UIControlStateNormal];
    [self.backButton setTitleColor:[[TGTheme shared] onAccentColour]
                          forState:UIControlStateNormal];
    [self.backButton setImage:[TGIcons backChevronWithColour:
            [[TGTheme shared] onAccentColour]] forState:UIControlStateNormal];
    self.backButton.imageEdgeInsets = UIEdgeInsetsMake(0, -TGMetricPadSmall, 0, 0);
    self.backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.backButton addTarget:self action:@selector(minimise)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.text = self.peerName.length ? self.peerName
            : ([[TGClient shared] nameForUserId:self.userId] ?: @"Call");
    self.nameLabel.font = TGFontHero();
    self.nameLabel.textColor = [[TGTheme shared] onAccentColour];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:self.nameLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = TGFontBody();
    self.statusLabel.textColor = [[TGTheme shared] callSubtitleColour];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    // The four emoji out of the call key sit in the top-right, and a tap
    // opens the full card; the words are the shortcut, the card the proof.
    self.keyButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.keyButton.titleLabel.font = TGFontEmojiSmall();
    [self.keyButton setTitleColor:[[TGTheme shared] onAccentColour]
                         forState:UIControlStateNormal];
    self.keyButton.hidden = YES;
    [self.keyButton addTarget:self action:@selector(showKeyCard)
             forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.keyButton];

    BOOL canVideo = [TGCapabilities canEncodeVideoCall];

    self.speakerBtn = [self createButtonWithTitle:@"Speaker" icon:@"unmute"];
    self.speakerLbl = self.lastCreatedLabel;
    self.videoBtn = [self createButtonWithTitle:@"Video" icon:@"video"];
    self.videoLbl = self.lastCreatedLabel;
    if (!canVideo) {
        self.videoBtn.hidden = YES;
        self.videoLbl.hidden = YES;
    }
    self.micBtn = [self createButtonWithTitle:@"Mute" icon:@"microphone"];
    self.micLbl = self.lastCreatedLabel;
    self.endBtn = [self createButtonWithTitle:@"End" icon:@"endcall"];
    self.endLbl = self.lastCreatedLabel;

    self.acceptBtn = [self createButtonWithTitle:@"Accept" icon:@"call"];
    self.acceptLbl = self.lastCreatedLabel;
    [self.acceptBtn addTarget:self action:@selector(acceptCall) forControlEvents:UIControlEventTouchUpInside];

    TGTheme *theme = [TGTheme shared];
    [self.endBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleDestructive highlighted:NO height:TGMetricCallButtonSide] forState:UIControlStateNormal];
    [self.endBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleDestructive highlighted:YES height:TGMetricCallButtonSide] forState:UIControlStateHighlighted];
    self.endBtn.backgroundColor = [UIColor clearColor];

    [self.acceptBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSuccess highlighted:NO height:TGMetricCallButtonSide] forState:UIControlStateNormal];
    [self.acceptBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSuccess highlighted:YES height:TGMetricCallButtonSide] forState:UIControlStateHighlighted];
    self.acceptBtn.backgroundColor = [UIColor clearColor];
    // The plates are saturated, so the end/accept glyphs stay light whatever
    // the controls around them carry.
    [self.endBtn setImage:[TGIcons glyphNamed:@"endcall" colour:[theme onAccentColour]
                                         side:TGMetricCallGlyphSide]
                 forState:UIControlStateNormal];
    [self.acceptBtn setImage:[TGIcons glyphNamed:@"call" colour:[theme onAccentColour]
                                           side:TGMetricCallGlyphSide]
                    forState:UIControlStateNormal];

    [self.speakerBtn addTarget:self action:@selector(toggleSpeaker) forControlEvents:UIControlEventTouchUpInside];
    [self.micBtn addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [self.videoBtn addTarget:self action:@selector(toggleVideo) forControlEvents:UIControlEventTouchUpInside];
    [self.endBtn addTarget:self action:@selector(end) forControlEvents:UIControlEventTouchUpInside];

    for (UIButton *control in @[self.speakerBtn, self.videoBtn, self.micBtn,
                                self.endBtn, self.acceptBtn]){
        [control addTarget:self action:@selector(controlHeld:)
          forControlEvents:UIControlEventTouchDown];
        [control addTarget:self action:@selector(controlReleased:)
          forControlEvents:UIControlEventTouchUpInside |
                           UIControlEventTouchUpOutside |
                           UIControlEventTouchCancel];
    }
    [self refreshControls];

    __weak typeof(self) weakSelf = self;
    [TGCall shared].onStateChanged = ^(TGCallState state){
        [weakSelf applyState:state];
    };

    // A screen presented again from the minimised bar must not place a second
    // call: TGCall already has one.
    if (self.outgoing && [TGCall shared].state == TGCallStateNone)
        [[TGCall shared] callUser:self.userId];

    [self loadPeerPhoto];
    [self applyState:[TGCall shared].state];

    self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   target:self
                                                 selector:@selector(tick)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.nameLabel)
        return;
    [self applyChromeLayout];
    // The same row variant the call state chose, at the new width.
    [self updateLayoutForCallActive:self.callRowActive];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController ||
            self.isBeingDismissed) {
        [self.ticker invalidate];
        self.ticker = nil;
    }
}

#pragma mark - the peer's picture

/// The call screen shows the person, so the profile picture is fetched the
/// same way the profile screen fetches it: the small file id from the client,
/// decoded off the main thread, then set. No picture leaves the gradient.
- (void)loadPeerPhoto {
    if (self.photoRequested || self.userId == 0)
        return;
    NSNumber *fileId = [[TGClient shared] photoFileIdForUserId:self.userId];
    if (![fileId isKindOfClass:NSNumber.class] || fileId.integerValue <= 0) {
        if (self.photoUserEnsured)
            return;
        self.photoUserEnsured = YES;
        __weak typeof(self) weakSelf = self;
        [[TGClient shared] ensureUserName:self.userId completion:^{
            TGCallViewController *me = weakSelf;
            if (!me)
                return;
            NSNumber *now = [[TGClient shared] photoFileIdForUserId:me.userId];
            if ([now isKindOfClass:NSNumber.class] && now.integerValue > 0)
                [me loadPeerPhoto];
        }];
        return;
    }
    self.photoRequested = YES;
    __weak typeof(self) weakSelf = self;
    [[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
        if (!path.length)
            return;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            UIImage *photo = [TGIcons decodedImageAtPath:path
                    fittingSize:[UIScreen mainScreen].bounds.size
                           fill:YES
                          scale:[UIScreen mainScreen].scale];
            if (!photo)
                return;
            dispatch_async(dispatch_get_main_queue(), ^{
                TGCallViewController *me = weakSelf;
                if (!me)
                    return;
                TGCallState state = [TGCall shared].state;
                if (state == TGCallStateEnded || state == TGCallStateFailed ||
                        state == TGCallStateNone)
                    return;
                me.photoView.image = photo;
                me.bgLayer.hidden = YES;
                me.shadeView.hidden = NO;
                me.fallbackAvatar.hidden = YES;
            });
        });
    }];
}

#pragma mark - chrome

- (UIButton *)createButtonWithTitle:(NSString *)title icon:(NSString *)icon {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, TGMetricCallButtonSide, TGMetricCallButtonSide);
    btn.layer.cornerRadius = TGHalf(TGMetricCallButtonSide);
    btn.clipsToBounds = YES;
    btn.layer.shouldRasterize = YES;
    btn.layer.rasterizationScale = [UIScreen mainScreen].scale;
    // An embossed metal plate, not a flat wash: the procedural engine carves
    // the gloss, bevel and shadow out of the token colour (§2). The two
    // states share the same geometry, only the light differs.
    TGTheme *theme = [TGTheme shared];
    [btn setBackgroundImage:
            [TGTheme skeuomorphicButtonImageWithColor:[theme callControlBaseColour]
                                               height:TGMetricCallButtonSide
                                          highlighted:NO
                                         cornerRadius:TGHalf(TGMetricCallButtonSide)]
              forState:UIControlStateNormal];
    [btn setBackgroundImage:
            [TGTheme skeuomorphicButtonImageWithColor:[theme callControlBaseColour]
                                               height:TGMetricCallButtonSide
                                          highlighted:YES
                                         cornerRadius:TGHalf(TGMetricCallButtonSide)]
              forState:UIControlStateHighlighted];
    btn.backgroundColor = [UIColor clearColor];
    UIImage *glyph = [icon isEqualToString:@"microphone"]
            ? [TGIcons microphoneOfSide:TGMetricCallGlyphSide colour:[theme primaryTextColour]]
            : [TGIcons glyphNamed:icon colour:[theme primaryTextColour] side:TGMetricCallGlyphSide];
    if (glyph){
        [btn setImage:glyph forState:UIControlStateNormal];
    } else {
        [btn setTitle:icon forState:UIControlStateNormal];
        btn.titleLabel.font = TGFontGlyph();
    }
    [self.view addSubview:btn];

    UILabel *lbl = [[UILabel alloc] initWithFrame:
            CGRectMake(0, 0, TGMetricCallLabelWidth, TGMetricCallLabelHeight)];
    lbl.text = title;
    lbl.textColor = [[TGTheme shared] onAccentColour];
    lbl.font = TGFontMeta();
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.backgroundColor = [UIColor clearColor];
    [self.view addSubview:lbl];

    self.lastCreatedLabel = lbl;
    return btn;
}

- (BOOL)usesTallStatusOffset {
    return self.view.bounds.size.height > 700;
}

- (CGFloat)statusTop {
    CGFloat height = self.view.bounds.size.height;
    if (height < 500)
        return TGMetricCallStatusTopSmall;
    if (height > 700)
        return TGMetricCallStatusTopTall;
    return TGMetricCallStatusTop;
}

- (void)applyChromeLayout {
    CGRect b = self.view.bounds;
    self.bgLayer.frame = b;
    self.photoView.frame = b;
    self.shadeView.frame = b;

    CGFloat top = [self statusTop];
    CGFloat width = b.size.width;
    self.backButton.frame = CGRectMake(TGMetricPadSmall, TGMetricPadWide,
            TGMetricCallLabelWidth, TGMetricRow);
    self.keyButton.frame = CGRectMake(width - TGMetricCallKeyWidth - TGMetricPadSmall,
            TGMetricPadWide, TGMetricCallKeyWidth, TGMetricCallKeyHeight);

    self.nameLabel.frame = CGRectMake(TGMetricPadMedium, top,
            width - TGDoubled(TGMetricPadMedium), TGMetricLineHero);
    self.statusLabel.frame = CGRectMake(TGMetricPadMedium,
            top + TGMetricLineHero + TGMetricPadTiny,
            width - TGDoubled(TGMetricPadMedium), TGMetricCallStatusHeight);

    CGFloat avatarSide = TGMetricCallAvatarSide;
    CGFloat controlsTop = b.size.height - TGMetricCallTogglesBottom;
    CGFloat avatarCentre = (top + TGMetricLineHero + TGMetricCallStatusHeight +
            controlsTop) / 2;
    self.fallbackAvatar.frame = CGRectMake(TGCenteredOrigin(width, avatarSide),
            avatarCentre - TGHalf(avatarSide), avatarSide, avatarSide);

    if (self.keyCard)
        [self layoutKeyCardInBounds:b];
}

/// One row of round buttons, spread evenly across the width with the same air
/// at both ends, each caption centred on the button above it.
- (void)placeRow:(NSArray *)buttons captions:(NSArray *)captions atY:(CGFloat)rowY {
    CGFloat width = self.view.bounds.size.width;
    CGFloat side = TGMetricCallButtonSide;
    CGFloat count = (CGFloat)buttons.count;
    CGFloat gap = (width - side * count) / (count + 1);

    for (NSUInteger i = 0; i < buttons.count; i++){
        UIButton *button = buttons[i];
        UILabel *caption = captions[i];
        CGFloat x = gap + i * (side + gap);

        button.hidden = NO;
        caption.hidden = NO;
        button.frame = CGRectMake(x, rowY, side, side);
        caption.frame = CGRectMake(
                x + TGCenteredOrigin(side, TGMetricCallLabelWidth),
                rowY + TGMetricCallLabelGap,
                TGMetricCallLabelWidth, TGMetricCallLabelHeight);
    }
}

- (void)hideRow:(NSArray *)buttons captions:(NSArray *)captions {
    for (UIView *view in buttons) view.hidden = YES;
    for (UIView *view in captions) view.hidden = YES;
}

- (void)acceptCall {
    [[TGCall shared] accept];
    self.statusLabel.text = @"Connecting...";
    [self updateLayoutForCallActive:YES];
}

- (void)updateLayoutForCallActive:(BOOL)active {
    self.callRowActive = active;
    CGRect b = self.view.bounds;
    CGFloat rowY = b.size.height - TGMetricCallTogglesBottom;
    BOOL ringing = (!self.outgoing && !active &&
                    [TGCall shared].state == TGCallStatePending);

    if (ringing){
        // Nothing to toggle until the call is yours: decline and accept, side
        // by side, the way the phone app does it.
        [self hideRow:@[self.speakerBtn, self.videoBtn, self.micBtn]
             captions:@[self.speakerLbl, self.videoLbl, self.micLbl]];
        self.endLbl.text = @"Decline";
        [self placeRow:@[self.endBtn, self.acceptBtn]
              captions:@[self.endLbl, self.acceptLbl]
                   atY:rowY];
        return;
    }

    self.acceptBtn.hidden = YES;
    self.acceptLbl.hidden = YES;
    self.endLbl.text = @"End";

    // One row, End among the others and on their line: it is the button the
    // thumb goes for, and it should not be somewhere else on the screen.
    NSMutableArray *row = [NSMutableArray arrayWithObject:self.speakerBtn];
    NSMutableArray *captions = [NSMutableArray arrayWithObject:self.speakerLbl];
    if ([TGCapabilities canEncodeVideoCall]){
        [row addObject:self.videoBtn];
        [captions addObject:self.videoLbl];
    } else {
        self.videoBtn.hidden = YES;
        self.videoLbl.hidden = YES;
    }
    [row addObjectsFromArray:@[self.micBtn, self.endBtn]];
    [captions addObjectsFromArray:@[self.micLbl, self.endLbl]];

    [self placeRow:row captions:captions atY:rowY];
}

#pragma mark - state

- (void)applyState:(TGCallState)state {
    BOOL isRinging = (!self.outgoing && state == TGCallStatePending);
    [self updateLayoutForCallActive:!isRinging];
    switch (state){
        case TGCallStatePending:
            self.statusLabel.text = self.outgoing ? @"Ringing..." : @"Incoming call";
            [self setStatusPulsing:YES];
            break;
        case TGCallStateExchangingKeys:
        case TGCallStateConnecting:
            self.statusLabel.text = @"Connecting...";
            [self setStatusPulsing:NO];
            [self setupEmojis];
            break;
        case TGCallStateEstablished:
            [self setStatusPulsing:NO];
            if (!self.connectedAt)
                self.connectedAt = [NSDate dateWithTimeIntervalSinceNow:
                        -[[TGCall shared] duration]];
            self.bgLayer.colors = TGCallGradient([[TGTheme shared] callGradientColoursConnected]);
            [self setupEmojis];
            [self tick];
            break;
        case TGCallStateFailed:
            self.statusLabel.text = [TGCall shared].endReason ?: @"Call failed";
            [self windDown];
            [self dismissShortly];
            break;
        case TGCallStateEnded:
            self.statusLabel.text = [TGCall shared].endReason ?: @"Call ended";
            [self windDown];
            [self dismissShortly];
            break;
        default:
            break;
    }
}

- (NSString *)emojiKeyText {
    NSArray *emojis = [TGCall shared].emojis;
    if (emojis.count >= 4)
        return [NSString stringWithFormat:@"%@ %@ %@ %@",
                emojis[0], emojis[1], emojis[2], emojis[3]];
    NSData *key = [TGCall shared].callKey;
    if (key.length >= 32) {
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(key.bytes, (CC_LONG)key.length, hash);
        NSArray *list = @[@"🐶", @"🐱", @"🐭", @"🐹", @"🐰", @"🦊", @"🐻", @"🐼",
                          @"🐨", @"🐯", @"🦁", @"🐮", @"🐷", @"🐸", @"🐵"];
        return [NSString stringWithFormat:@"%@ %@ %@ %@",
                list[hash[0] % list.count], list[hash[1] % list.count],
                list[hash[2] % list.count], list[hash[3] % list.count]];
    }
    return nil;
}

- (void)setupEmojis {
    NSString *text = [self emojiKeyText];
    if (!text.length)
        return;
    self.keyEmojiText = text;
    [self.keyButton setTitle:text forState:UIControlStateNormal];
    self.keyButton.hidden = NO;
    if (self.keyCard)
        self.keyCardEmoji.text = text;
}

- (void)showKeyCard {
    if (!self.keyEmojiText.length)
        return;
    if (!self.keyCard){
        self.keyCard = [[UIView alloc] initWithFrame:self.view.bounds];
        self.keyCard.backgroundColor = [[TGTheme shared] scrimColour];
        self.keyCard.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                UIViewAutoresizingFlexibleHeight;
        [self.keyCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                initWithTarget:self action:@selector(hideKeyCard)]];

        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.tag = 0xCA2D;
        card.backgroundColor = [[TGTheme shared] cardBackgroundColour];
        card.layer.cornerRadius = TGMetricCornerCard;
        [self.keyCard addSubview:card];

        self.keyCardEmoji = [[UILabel alloc] initWithFrame:CGRectZero];
        self.keyCardEmoji.text = self.keyEmojiText;
        self.keyCardEmoji.font = TGFontEmojiLarge();
        self.keyCardEmoji.textAlignment = NSTextAlignmentCenter;
        self.keyCardEmoji.backgroundColor = [UIColor clearColor];
        [card addSubview:self.keyCardEmoji];

        self.keyCardTitle = [[UILabel alloc] initWithFrame:CGRectZero];
        self.keyCardTitle.text = @"Encryption Key";
        self.keyCardTitle.font = TGFontHeader();
        self.keyCardTitle.textColor = [[TGTheme shared] primaryTextColour];
        self.keyCardTitle.textAlignment = NSTextAlignmentCenter;
        self.keyCardTitle.backgroundColor = [UIColor clearColor];
        [card addSubview:self.keyCardTitle];

        self.keyCardBody = [[UILabel alloc] initWithFrame:CGRectZero];
        self.keyCardBody.text = @"Compare these four emoji with your friend. "
                "If they match, the call is end-to-end encrypted.";
        self.keyCardBody.font = TGFontCaption();
        self.keyCardBody.textColor = [[TGTheme shared] secondaryTextColour];
        self.keyCardBody.textAlignment = NSTextAlignmentCenter;
        self.keyCardBody.numberOfLines = 3;
        self.keyCardBody.backgroundColor = [UIColor clearColor];
        [card addSubview:self.keyCardBody];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        close.frame = CGRectZero;
        close.tag = 0xCA2E;
        [close setTitle:@"Close" forState:UIControlStateNormal];
        [close setTitleColor:[[TGTheme shared] accentColour]
                    forState:UIControlStateNormal];
        close.titleLabel.font = TGFontRow();
        [close addTarget:self action:@selector(hideKeyCard)
                forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:close];

        self.keyCard.alpha = 0;
        [self.view addSubview:self.keyCard];
        [self layoutKeyCardInBounds:self.view.bounds];
    }
    self.keyCard.hidden = NO;
    [UIView animateWithDuration:TGAnimationDurationFast animations:^{
        self.keyCard.alpha = TGAlphaOpaque;
    }];
}

- (void)layoutKeyCardInBounds:(CGRect)b {
    CGFloat cardWidth = MIN(TGMetricCallKeyCardWidth,
            b.size.width - TGDoubled(TGMetricPadWide));
    CGFloat cardHeight = TGMetricCallKeyCardHeight;
    UIView *card = [self.keyCard viewWithTag:0xCA2D];
    card.frame = CGRectMake(TGCenteredOrigin(b.size.width, cardWidth),
            TGCenteredOrigin(b.size.height, cardHeight), cardWidth, cardHeight);
    CGFloat inner = cardWidth - TGDoubled(TGMetricPadLarge);
    self.keyCardEmoji.frame = CGRectMake(TGMetricPadLarge, TGMetricPadLarge,
            inner, TGMetricCallKeyGlyphSize + TGMetricPadLarge);
    self.keyCardTitle.frame = CGRectMake(TGMetricPadLarge,
            TGMetricPadLarge + TGMetricCallKeyGlyphSize + TGMetricPadLarge,
            inner, TGMetricLineHeader);
    self.keyCardBody.frame = CGRectMake(TGMetricPadLarge,
            TGMetricPadLarge + TGMetricCallKeyGlyphSize + TGMetricPadLarge +
                    TGMetricLineHeader + TGMetricPadSmall,
            inner, TGMetricCallKeyCardBody);
    UIButton *close = [card viewWithTag:0xCA2E];
    close.frame = CGRectMake(TGMetricPadLarge,
            cardHeight - TGMetricRow - TGMetricPadSmall,
            inner, TGMetricRow);
}

- (void)hideKeyCard {
    if (!self.keyCard)
        return;
    [UIView animateWithDuration:TGAnimationDurationFast animations:^{
        self.keyCard.alpha = TGAlphaTransparent;
    } completion:^(BOOL done){
        self.keyCard.hidden = YES;
        self.keyCard.alpha = TGAlphaOpaque;
    }];
}

- (void)tick {
    if ([TGCall shared].state != TGCallStateEstablished)
        return;
    self.statusLabel.text = TGUIFormatCallDuration([[TGCall shared] duration]);
}

#pragma mark - controls

- (void)toggleSpeaker {
    self.speakerOn = !self.speakerOn;
    [[TGCall shared] setSpeaker:self.speakerOn];
    [self refreshControls];
}

- (void)toggleMute {
    [[TGCall shared] setMuted:![TGCall shared].muted];
    [self refreshControls];
}

/// The 1:1 engine in this build carries audio. The control is kept where
/// Telegram puts it, and its answer is the truth rather than a camera that
/// would never produce a frame.
- (void)toggleVideo {
    [TGAlertSheet showMessage:@"Video calls need a camera engine this build "
            "does not carry. The call continues with audio."
                        title:@"Video" inView:self.view];
}

// One place decides what the toggles look like, so the drawing can never
// disagree with the call. Both used to change colour only, which on a dark
// screen read as nothing at all. Each toggle carries two glyphs: a dark one
// for the steel plate, a light one for the lit accent plate.
- (void)refreshControls {
    BOOL muted = [TGCall shared].muted;
    TGTheme *theme = [TGTheme shared];

    UIImage *mic = muted
            ? [TGIcons microphoneOffOfSide:TGMetricCallGlyphSide colour:[theme primaryTextColour]]
            : [TGIcons microphoneOfSide:TGMetricCallGlyphSide colour:[theme primaryTextColour]];
    // the lit state always shows the crossed-out mic, in the light colour
    UIImage *micActive = [TGIcons microphoneOffOfSide:TGMetricCallGlyphSide
                                               colour:[theme onAccentColour]];
    UIImage *spk = [TGIcons glyphNamed:(self.speakerOn ? @"speakerOn" : @"unmute")
                                colour:[theme primaryTextColour] side:TGMetricCallGlyphSide];
    UIImage *spkActive = [TGIcons glyphNamed:(self.speakerOn ? @"speakerOn" : @"unmute")
                                      colour:[theme onAccentColour] side:TGMetricCallGlyphSide];

    [self setGlyph:mic activeGlyph:micActive on:self.micBtn active:muted];
    [self setGlyph:spk activeGlyph:spkActive on:self.speakerBtn active:self.speakerOn];

    self.micLbl.text = muted ? @"Unmute" : @"Mute";
    self.speakerLbl.text = @"Speaker";
    self.micLbl.textColor = muted ? [theme callControlActiveColour] : [theme onAccentColour];
    self.speakerLbl.textColor = self.speakerOn ? [theme callControlActiveColour] : [theme onAccentColour];
}

// Telegram crosses a control over to white-on-light when it is on; the swap
// is worth a frame of animation so the eye follows which button moved. The
// plate changes with it: steel when idle, accent when lit.
- (void)setGlyph:(UIImage *)glyph activeGlyph:(UIImage *)activeGlyph
              on:(UIButton *)button active:(BOOL)active {
    TGTheme *theme = [TGTheme shared];
    [UIView transitionWithView:button duration:TGAnimationDurationFast
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        UIImage *plate = [TGTheme skeuomorphicButtonImageWithColor:
                (active ? [theme accentColour] : [theme callControlBaseColour])
                                   height:TGMetricCallButtonSide
                              highlighted:NO
                             cornerRadius:TGHalf(TGMetricCallButtonSide)];
        [button setBackgroundImage:plate forState:UIControlStateNormal];
        [button setBackgroundImage:
                [TGTheme skeuomorphicButtonImageWithColor:
                 (active ? [theme accentColour] : [theme callControlBaseColour])
                                    height:TGMetricCallButtonSide
                               highlighted:YES
                              cornerRadius:TGHalf(TGMetricCallButtonSide)]
              forState:UIControlStateHighlighted];
        [button setImage:active ? activeGlyph : glyph forState:UIControlStateNormal];
    } completion:nil];
}

// Holding a control draws a ring around it that grows in under the finger and
// fades out on release, so a press you are still making is visible.
- (void)controlHeld:(UIButton *)button {
    CGFloat side = TGMetricCallButtonSide;
    UIView *ring = [[UIView alloc] initWithFrame:button.frame];
    ring.backgroundColor = [UIColor clearColor];
    ring.userInteractionEnabled = NO;
    ring.layer.cornerRadius = TGHalf(side);
    ring.layer.borderWidth = TGMetricBorderThick;
    ring.layer.borderColor = [[[TGTheme shared] onAccentColour]
            colorWithAlphaComponent:TGAlphaRingTrack].CGColor;
    ring.transform = CGAffineTransformMakeScale(TGTransformScaleButtonActive,
                                                TGTransformScaleButtonActive);
    ring.alpha = 0;
    ring.tag = 0xCA11;
    [self.view insertSubview:ring belowSubview:button];

    [UIView animateWithDuration:TGAnimationDurationFast animations:^{
        ring.alpha = TGAlphaOpaque;
        ring.transform = CGAffineTransformMakeScale(TGTransformScaleRingHeld,
                                                    TGTransformScaleRingHeld);
        button.transform = CGAffineTransformMakeScale(TGTransformScaleButtonActive,
                                                      TGTransformScaleButtonActive);
    }];
}

- (void)controlReleased:(UIButton *)button {
    [UIView animateWithDuration:TGAnimationDurationFast animations:^{
        button.transform = CGAffineTransformIdentity;
        for (UIView *ring in self.view.subviews)
            if (ring.tag == 0xCA11){
                ring.alpha = 0;
                ring.transform = CGAffineTransformMakeScale(TGTransformScaleRingHeld,
                                                            TGTransformScaleRingHeld);
            }
    } completion:^(BOOL done){
        for (UIView *ring in [self.view.subviews copy])
            if (ring.tag == 0xCA11)
                [ring removeFromSuperview];
    }];
}

- (void)end {
    // Hanging up takes a moment to come back from the network; without this
    // the screen just sits there and the tap looks like it was missed.
    self.statusLabel.text = @"Ending...";
    [self setStatusPulsing:NO];
    [UIView animateWithDuration:TGAnimationDurationFast animations:^{
        self.endBtn.transform = CGAffineTransformMakeScale(TGTransformScaleButtonActive, TGTransformScaleButtonActive);
    } completion:^(BOOL done){
        [UIView animateWithDuration:TGAnimationDurationFast animations:^{
            self.endBtn.transform = CGAffineTransformIdentity;
        }];
    }];
    [self windDown];
    [[TGCall shared] hangUp];
    [self dismissShortly];
}

#pragma mark - leaving the screen without ending the call

- (void)minimise {
    [[TGCallMiniBar shared] showForUserId:self.userId
                                     name:self.nameLabel.text ?: self.peerName];
    [self.ticker invalidate];
    self.ticker = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

/// The call is over: the controls fade out and the backdrop goes red, so the
/// second before the screen closes shows what happened.
- (void)windDown {
    [self setStatusPulsing:NO];
    self.bgLayer.hidden = NO;
    self.photoView.hidden = YES;
    self.fallbackAvatar.hidden = YES;
    self.shadeView.hidden = YES;
    self.bgLayer.colors = TGCallGradient([[TGTheme shared] callGradientColoursFailed]);
    [UIView animateWithDuration:TGAnimationDurationMedium animations:^{
        for (UIView *view in @[self.speakerBtn, self.videoBtn, self.micBtn,
                               self.acceptBtn, self.speakerLbl, self.videoLbl,
                               self.micLbl, self.acceptLbl])
            view.alpha = TGAlphaTransparent;
        self.endBtn.alpha = TGAlphaDimmed;
    }];
}

/// A slow breath on the status while it is still ringing - the one hint that
/// the call is live and not stuck.
- (void)setStatusPulsing:(BOOL)pulsing {
    if (!pulsing){
        [self.statusLabel.layer removeAnimationForKey:@"pulse"];
        self.statusLabel.alpha = TGAlphaOpaque;
        return;
    }
    if ([self.statusLabel.layer animationForKey:@"pulse"])
        return;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(TGAlphaOpaque);
    fade.toValue = @(TGAlphaDisabled);
    fade.duration = TGAnimationDurationSlow;
    fade.autoreverses = YES;
    fade.repeatCount = HUGE_VALF;
    [self.statusLabel.layer addAnimation:fade forKey:@"pulse"];
}

- (void)dismissShortly {
    [self.ticker invalidate];
    self.ticker = nil;
    [self performSelector:@selector(dismissNow) withObject:nil afterDelay:1.0];
}

- (void)dismissNow {
    [TGCall shared].onStateChanged = nil;
    [[TGCallMiniBar shared] hide];
    // A call that lasted a moment is not worth asking about, and asking
    // about a call nobody answered is worse than not asking. The controller
    // is kept alive by this block only until the prompt is on screen.
    NSTimeInterval talked = self.connectedAt ? -[self.connectedAt timeIntervalSinceNow] : 0;
    TGCallViewController *me = self;
    [self dismissViewControllerAnimated:YES completion:^{
        if (talked >= 10)
            [me askForCallRatingAfter:talked];
    }];
}

/// Telegram asks five stars and, for a poor score, what went wrong; that is
/// the whole shape of sendCallRating. The sheet belongs to the window, since
/// this screen is already gone when it appears.
- (void)askForCallRatingAfter:(NSTimeInterval)seconds {
    if (self.ratedCall || ![TGCall shared].lastCallId)
        return;
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window)
        return;
    NSArray *stars = @[@"★★★★★", @"★★★★", @"★★★", @"★★", @"★"];
    NSString *name = self.peerName.length ? self.peerName : @"this call";
    __weak typeof(self) weakSelf = self;
    [TGAlertSheet showChoices:stars
                        title:@"Rate the call"
                      message:[NSString stringWithFormat:
                              @"How did %@ go? Your score goes to Telegram, not "
                              @"to the other side.", name]
             destructiveIndex:-1
                       inView:window
                     onChoice:^(NSInteger index){
        TGCallViewController *me = weakSelf;
        if (!me)
            return;
        int rating = (int)(5 - index);
        me.ratedCall = YES;
        if (rating <= 3){
            [TGAlertSheet showInput:@"What went wrong?"
                            message:@"Optional - it is read by Telegram."
                        placeholder:@"Sound, connection, ..."
                               text:nil
                             action:@"Send"
                             inView:window
                         onSubmit:^(NSString *comment){
                [[TGCall shared] sendRating:rating comment:comment problems:@[]];
            }];
            return;
        }
        [[TGCall shared] sendRating:rating comment:@"" problems:@[]];
    }];
}

@end
