#import "TGCallViewController.h"
#import "TGCall.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCapabilities.h"
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonDigest.h>
#import "TGStyle.h"

@interface TGCallViewController ()
@property (nonatomic, assign) int64_t userId;
@property (nonatomic, strong) NSString *peerName;
@property (nonatomic, assign) BOOL outgoing;

@property (nonatomic, strong) CAGradientLayer *bgLayer;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *avatarView;

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

@property (nonatomic, strong) NSTimer *ticker;
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
        UIViewController *top = window.rootViewController;
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

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Gradient Background
    self.bgLayer = [CAGradientLayer layer];
    self.bgLayer.frame = self.view.bounds;
    self.bgLayer.colors = TGCallGradient([[TGTheme shared] callGradientColours]);
    [self.view.layer addSublayer:self.bgLayer];

    CGRect b = self.view.bounds;
    
    // Down the screen once, each thing under the last, so moving the avatar
    // does not leave the name sitting where it used to be.
    CGFloat gutter = TGMetricPadMedium;
    CGFloat textWidth = b.size.width - TGDoubled(gutter);
    CGFloat y = TGMetricCallEmojiTop;

    self.emojiLabel = [[UILabel alloc] initWithFrame:CGRectMake(gutter, y, textWidth, TGMetricCallEmojiHeight)];
    self.emojiLabel.font = TGFontGlyph();
    self.emojiLabel.textAlignment = NSTextAlignmentCenter;
    self.emojiLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.emojiLabel];

    y += TGMetricCallEmojiHeight + TGMetricPadLarge;

    CGFloat side = TGMetricCallAvatarSide;
    self.avatarView = [[UIImageView alloc] initWithFrame:
            CGRectMake(TGCenteredOrigin(b.size.width, side), y, side, side)];
    self.avatarView.layer.cornerRadius = TGHalf(side);
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.shouldRasterize = YES;
    self.avatarView.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.avatarView.layer.borderColor = [[TGTheme shared] separatorColour].CGColor;
    self.avatarView.layer.borderWidth = 1.0f;
    self.avatarView.image = [TGIcons avatarWithInitials:
            (self.peerName.length ? [self.peerName substringToIndex:1].uppercaseString : @"?")
                                                   size:side colourId:self.userId];
    [self.view addSubview:self.avatarView];

    y += side + TGMetricPadLarge;

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(gutter, y, textWidth, TGMetricCallNameHeight)];
    self.nameLabel.text = self.peerName;
    self.nameLabel.font = TGFontHero();
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.nameLabel];

    y += TGMetricCallNameHeight + TGMetricPadTiny;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(gutter, y, textWidth, TGMetricCallStatusHeight)];
    self.statusLabel.font = TGFontBody();
    self.statusLabel.textColor = [[TGTheme shared] callSubtitleColour];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

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
    if (!theme.isFlat) {
        [self.endBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleDestructive highlighted:NO height:TGMetricCallButtonSide] forState:UIControlStateNormal];
        [self.endBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleDestructive highlighted:YES height:TGMetricCallButtonSide] forState:UIControlStateHighlighted];
        self.endBtn.backgroundColor = [UIColor clearColor];

        [self.acceptBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSuccess highlighted:NO height:TGMetricCallButtonSide] forState:UIControlStateNormal];
        [self.acceptBtn setBackgroundImage:[TGTheme buttonImageForStyle:TGButtonStyleSuccess highlighted:YES height:TGMetricCallButtonSide] forState:UIControlStateHighlighted];
        self.acceptBtn.backgroundColor = [UIColor clearColor];
    } else {
        self.endBtn.backgroundColor = [theme callEndColour];
        self.acceptBtn.backgroundColor = [theme callAcceptColour];
    }

    [self.speakerBtn addTarget:self action:@selector(toggleSpeaker) forControlEvents:UIControlEventTouchUpInside];
    [self.micBtn addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
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

    if (self.outgoing)
        [[TGCall shared] callUser:self.userId];
    
    [self applyState:[TGCall shared].state];

    self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   target:self
                                                 selector:@selector(tick)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (UIButton *)createButtonWithTitle:(NSString *)title icon:(NSString *)icon {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, TGMetricCallButtonSide, TGMetricCallButtonSide);
    btn.layer.cornerRadius = TGHalf(TGMetricCallButtonSide);
    btn.clipsToBounds = YES;
    btn.layer.shouldRasterize = YES;
    btn.layer.rasterizationScale = [UIScreen mainScreen].scale;
    btn.backgroundColor = [[TGTheme shared] callControlColour];
    // Drawn glyphs rather than emoji: iOS 7's font has no colour glyph for
    // some of these, and the ones it does have do not match the rest of the
    // iconography.
    UIImage *glyph = [icon isEqualToString:@"microphone"]
            ? [TGIcons microphoneOfSide:TGMetricCallGlyphSide colour:[UIColor whiteColor]]
            : [TGIcons glyphNamed:icon colour:[UIColor whiteColor] side:TGMetricCallGlyphSide];
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
    lbl.textColor = [UIColor whiteColor];
    lbl.font = TGFontMeta();
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.backgroundColor = [UIColor clearColor];
    [self.view addSubview:lbl];

    self.lastCreatedLabel = lbl;
    return btn;
}

// One row of round buttons, spread evenly across the width with the same air
// at both ends, each caption centred on the button above it. Every offset the
// three old branches wrote out by hand - gap*4 + 180, x - 10, +35, -95 - was
// this arithmetic done again, differently, and drifting.
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

- (void)applyState:(TGCallState)state {
    BOOL isRinging = (!self.outgoing && state == TGCallStatePending);
    [self updateLayoutForCallActive:!isRinging];

    switch (state){
        case TGCallStatePending:
            self.statusLabel.text = self.outgoing ? @"Calling..." : @"Incoming...";
            [self setStatusPulsing:YES];
            break;
        case TGCallStateExchangingKeys:
        case TGCallStateConnecting:
            self.statusLabel.text = @"Connecting...";
            [self setupEmojis];
            break;
        case TGCallStateEstablished:
            [self setStatusPulsing:NO];
            self.bgLayer.colors = TGCallGradient([[TGTheme shared] callGradientColoursConnected]);
            [self setupEmojis];
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

- (void)setupEmojis {
    NSArray *emojis = [TGCall shared].emojis;
    if (emojis.count >= 4) {
        self.emojiLabel.text = [NSString stringWithFormat:@"%@  %@  %@  %@", emojis[0], emojis[1], emojis[2], emojis[3]];
        return;
    }
    NSData *key = [TGCall shared].callKey;
    if (key.length >= 32) {
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(key.bytes, (CC_LONG)key.length, hash);
        
        NSArray *emojisList = @[@"🐶", @"🐱", @"🐭", @"🐹", @"🐰", @"🦊", @"🐻", @"🐼", @"🐨", @"🐯", @"🦁", @"🐮", @"🐷", @"🐸", @"🐵"];
        NSString *e1 = emojisList[hash[0] % emojisList.count];
        NSString *e2 = emojisList[hash[1] % emojisList.count];
        NSString *e3 = emojisList[hash[2] % emojisList.count];
        NSString *e4 = emojisList[hash[3] % emojisList.count];
        self.emojiLabel.text = [NSString stringWithFormat:@"%@  %@  %@  %@", e1, e2, e3, e4];
    }
}

- (void)tick {
    if ([TGCall shared].state != TGCallStateEstablished)
        return;
    NSInteger seconds = (NSInteger)[[TGCall shared] duration];
    self.statusLabel.text = [NSString stringWithFormat:@"ılı %ld:%02ld",
            (long)(seconds / 60), (long)(seconds % 60)];
}

- (void)toggleSpeaker {
    self.speakerOn = !self.speakerOn;
    [[TGCall shared] setSpeaker:self.speakerOn];
    [self refreshControls];
}

- (void)toggleMute {
    [[TGCall shared] setMuted:![TGCall shared].muted];
    [self refreshControls];
}

// One place decides what the two toggles look like, so the drawing can never
// disagree with the call. Both used to change colour only, which on a dark
// screen read as nothing at all.
- (void)refreshControls {
    BOOL muted = [TGCall shared].muted;
    TGTheme *theme = [TGTheme shared];

    UIImage *mic = muted
            ? [TGIcons microphoneOffOfSide:TGMetricCallGlyphSide colour:[UIColor whiteColor]]
            : [TGIcons microphoneOfSide:TGMetricCallGlyphSide colour:[UIColor whiteColor]];
    UIImage *spk = [TGIcons glyphNamed:(self.speakerOn ? @"speakerOn" : @"unmute")
                                colour:[UIColor whiteColor] side:TGMetricCallGlyphSide];

    [self setGlyph:mic on:self.micBtn active:muted];
    [self setGlyph:spk on:self.speakerBtn active:self.speakerOn];

    self.micLbl.text = muted ? @"Unmute" : @"Mute";
    self.speakerLbl.text = @"Speaker";
    self.micLbl.textColor = muted ? [theme callControlActiveColour] : [UIColor whiteColor];
    self.speakerLbl.textColor = self.speakerOn ? [theme callControlActiveColour] : [UIColor whiteColor];
}

// Telegram crosses a control over to white-on-light when it is on; the swap
// is worth a frame of animation so the eye follows which button moved.
- (void)setGlyph:(UIImage *)glyph on:(UIButton *)button active:(BOOL)active {
    TGTheme *theme = [TGTheme shared];
    [UIView transitionWithView:button duration:TGAnimationDurationFast
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [button setImage:glyph forState:UIControlStateNormal];
        button.backgroundColor = active ? [theme callControlActiveColour]
                                        : [theme callControlColour];
        button.tintColor = active ? [theme callControlActiveColour] : [UIColor whiteColor];
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
    ring.layer.borderColor = [[UIColor whiteColor]
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

/// The call is over: the controls fade out and the backdrop goes red, so the
/// second before the screen closes shows what happened.
- (void)windDown {
    [self setStatusPulsing:NO];
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
    fade.duration = 0.9;
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
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
