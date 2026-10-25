#import "TGCallViewController.h"
#import "TGCall.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
#import "TGCapabilities.h"
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonDigest.h>

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
@property (nonatomic, strong) UILabel *lastCreatedLabel;

@property (nonatomic, strong) NSTimer *ticker;
@end

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
    self.bgLayer.colors = @[(id)[UIColor colorWithRed:0.43f green:0.38f blue:0.87f alpha:1].CGColor,
                            (id)[UIColor colorWithRed:0.35f green:0.60f blue:0.95f alpha:1].CGColor];
    [self.view.layer addSublayer:self.bgLayer];

    CGRect b = self.view.bounds;
    
    self.emojiLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 30, b.size.width - 20, 30)];
    self.emojiLabel.font = [UIFont systemFontOfSize:22];
    self.emojiLabel.textAlignment = NSTextAlignmentCenter;
    self.emojiLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.emojiLabel];

    CGFloat side = 120;
    self.avatarView = [[UIImageView alloc] initWithFrame:
            CGRectMake((b.size.width - side) / 2, 100, side, side)];
    self.avatarView.layer.cornerRadius = side / 2;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.shouldRasterize = YES;
    self.avatarView.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.avatarView.image = [TGIcons avatarWithInitials:
            (self.peerName.length ? [self.peerName substringToIndex:1].uppercaseString : @"?")
                                                   size:side colourId:self.userId];
    [self.view addSubview:self.avatarView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 240, b.size.width - 20, 30)];
    self.nameLabel.text = self.peerName;
    self.nameLabel.font = [UIFont systemFontOfSize:28];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.nameLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 275, b.size.width - 20, 20)];
    self.statusLabel.font = [UIFont systemFontOfSize:15];
    self.statusLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.7f];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];

    CGFloat btnY = b.size.height - 130;
    BOOL canVideo = [TGCapabilities canEncodeVideoCall];
    CGFloat btnCount = canVideo ? 4 : 3;
    CGFloat gap = (b.size.width - (60 * btnCount)) / (btnCount + 1);
    
    self.speakerBtn = [self createButtonAtX:gap y:btnY title:@"Speaker" icon:@"unmute"];
    self.speakerLbl = self.lastCreatedLabel;
    self.videoBtn = [self createButtonAtX:canVideo ? (gap*2 + 60) : -100 y:btnY title:@"Video" icon:@"video"];
    self.videoLbl = self.lastCreatedLabel;
    if (!canVideo) {
        self.videoBtn.hidden = YES;
        self.videoLbl.hidden = YES;
    }
    self.micBtn = [self createButtonAtX:canVideo ? (gap*3 + 120) : (gap*2 + 60) y:btnY title:@"Mute" icon:@"microphone"];
    self.micLbl = self.lastCreatedLabel;
    self.endBtn = [self createButtonAtX:canVideo ? (gap*4 + 180) : (gap*3 + 120) y:btnY title:@"End" icon:@"endcall"];
    self.endLbl = self.lastCreatedLabel;
    self.endBtn.backgroundColor = [UIColor colorWithRed:0.9f green:0.2f blue:0.2f alpha:1];

    self.acceptBtn = [self createButtonAtX:(b.size.width / 2) + 35 y:btnY title:@"Accept" icon:@"call"];
    self.acceptLbl = self.lastCreatedLabel;
    self.acceptBtn.backgroundColor = [UIColor colorWithRed:0.2f green:0.8f blue:0.3f alpha:1];
    [self.acceptBtn addTarget:self action:@selector(acceptCall) forControlEvents:UIControlEventTouchUpInside];
    
    [self.speakerBtn addTarget:self action:@selector(toggleSpeaker) forControlEvents:UIControlEventTouchUpInside];
    [self.micBtn addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [self.endBtn addTarget:self action:@selector(end) forControlEvents:UIControlEventTouchUpInside];

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

- (UIButton *)createButtonAtX:(CGFloat)x y:(CGFloat)y title:(NSString *)title icon:(NSString *)icon {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(x, y, 60, 60);
    btn.layer.cornerRadius = 30;
    btn.clipsToBounds = YES;
    btn.layer.shouldRasterize = YES;
    btn.layer.rasterizationScale = [UIScreen mainScreen].scale;
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    // Drawn glyphs rather than emoji: iOS 7's font has no colour glyph for
    // some of these, and the ones it does have do not match the rest of the
    // iconography.
    UIImage *glyph = [icon isEqualToString:@"microphone"]
            ? [TGIcons microphoneOfSide:28 colour:[UIColor whiteColor]]
            : [TGIcons glyphNamed:icon colour:[UIColor whiteColor] side:28];
    if (glyph){
        [btn setImage:glyph forState:UIControlStateNormal];
    } else {
        [btn setTitle:icon forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:24];
    }
    [self.view addSubview:btn];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(x - 10, y + 65, 80, 15)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.backgroundColor = [UIColor clearColor];
    [self.view addSubview:lbl];

    self.lastCreatedLabel = lbl;
    return btn;
}

- (void)acceptCall {
    [[TGCall shared] accept];
    self.statusLabel.text = @"Connecting...";
    [self updateLayoutForCallActive:YES];
}

- (void)updateLayoutForCallActive:(BOOL)active {
    CGRect b = self.view.bounds;
    CGFloat btnY = b.size.height - 130;
    if (!self.outgoing && !active && [TGCall shared].state == TGCallStatePending) {
        self.speakerBtn.hidden = YES;
        self.speakerLbl.hidden = YES;
        self.videoBtn.hidden = YES;
        self.videoLbl.hidden = YES;
        self.micBtn.hidden = YES;
        self.micLbl.hidden = YES;
        
        self.acceptBtn.hidden = NO;
        self.acceptLbl.hidden = NO;
        self.acceptBtn.frame = CGRectMake((b.size.width / 2) + 35, btnY, 60, 60);
        self.acceptLbl.frame = CGRectMake((b.size.width / 2) + 25, btnY + 65, 80, 15);
        
        self.endBtn.hidden = NO;
        self.endLbl.hidden = NO;
        self.endBtn.frame = CGRectMake((b.size.width / 2) - 95, btnY, 60, 60);
        self.endLbl.frame = CGRectMake((b.size.width / 2) - 105, btnY + 65, 80, 15);
        self.endLbl.text = @"Decline";
    } else {
        BOOL canVideo = [TGCapabilities canEncodeVideoCall];
        self.acceptBtn.hidden = YES;
        self.acceptLbl.hidden = YES;
        
        if (canVideo) {
            CGFloat gap = (b.size.width - (60 * 4)) / 5;
            self.speakerBtn.hidden = NO;
            self.speakerLbl.hidden = NO;
            self.speakerBtn.frame = CGRectMake(gap, btnY, 60, 60);
            self.speakerLbl.frame = CGRectMake(gap - 10, btnY + 65, 80, 15);
            
            self.videoBtn.hidden = NO;
            self.videoLbl.hidden = NO;
            self.videoBtn.frame = CGRectMake(gap*2 + 60, btnY, 60, 60);
            self.videoLbl.frame = CGRectMake(gap*2 + 50, btnY + 65, 80, 15);
            
            self.micBtn.hidden = NO;
            self.micLbl.hidden = NO;
            self.micBtn.frame = CGRectMake(gap*3 + 120, btnY, 60, 60);
            self.micLbl.frame = CGRectMake(gap*3 + 110, btnY + 65, 80, 15);
            
            self.endBtn.hidden = NO;
            self.endLbl.hidden = NO;
            self.endBtn.frame = CGRectMake(gap*4 + 180, btnY, 60, 60);
            self.endLbl.frame = CGRectMake(gap*4 + 170, btnY + 65, 80, 15);
        } else {
            CGFloat gap = (b.size.width - (60 * 3)) / 4;
            self.videoBtn.hidden = YES;
            self.videoLbl.hidden = YES;
            
            self.speakerBtn.hidden = NO;
            self.speakerLbl.hidden = NO;
            self.speakerBtn.frame = CGRectMake(gap, btnY, 60, 60);
            self.speakerLbl.frame = CGRectMake(gap - 10, btnY + 65, 80, 15);
            
            self.micBtn.hidden = NO;
            self.micLbl.hidden = NO;
            self.micBtn.frame = CGRectMake(gap*2 + 60, btnY, 60, 60);
            self.micLbl.frame = CGRectMake(gap*2 + 50, btnY + 65, 80, 15);
            
            self.endBtn.hidden = NO;
            self.endLbl.hidden = NO;
            self.endBtn.frame = CGRectMake(gap*3 + 120, btnY, 60, 60);
            self.endLbl.frame = CGRectMake(gap*3 + 110, btnY + 65, 80, 15);
        }
        self.endLbl.text = @"End";
    }
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
            self.bgLayer.colors = @[(id)[UIColor colorWithRed:0.27f green:0.69f blue:0.55f alpha:1].CGColor,
                                    (id)[UIColor colorWithRed:0.45f green:0.77f blue:0.43f alpha:1].CGColor];
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
    static BOOL speakerOn = NO;
    speakerOn = !speakerOn;
    [[TGCall shared] setSpeaker:speakerOn];
    self.speakerBtn.backgroundColor = speakerOn ? [UIColor colorWithWhite:1.0 alpha:0.4] : [UIColor colorWithWhite:1.0 alpha:0.2];
}

- (void)toggleMute {
    BOOL muted = ![TGCall shared].muted;
    [[TGCall shared] setMuted:muted];
    self.micBtn.backgroundColor = muted ? [UIColor colorWithWhite:1.0 alpha:0.4] : [UIColor colorWithWhite:1.0 alpha:0.2];
}

- (void)end {
    // Hanging up takes a moment to come back from the network; without this
    // the screen just sits there and the tap looks like it was missed.
    self.statusLabel.text = @"Ending...";
    [self setStatusPulsing:NO];
    [UIView animateWithDuration:0.12 animations:^{
        self.endBtn.transform = CGAffineTransformMakeScale(0.86f, 0.86f);
    } completion:^(BOOL done){
        [UIView animateWithDuration:0.12 animations:^{
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
    self.bgLayer.colors = @[(id)[UIColor colorWithRed:0.45f green:0.16f blue:0.16f alpha:1].CGColor,
                            (id)[UIColor colorWithRed:0.30f green:0.10f blue:0.12f alpha:1].CGColor];
    [UIView animateWithDuration:0.25 animations:^{
        for (UIView *view in @[self.speakerBtn, self.videoBtn, self.micBtn,
                               self.acceptBtn, self.speakerLbl, self.videoLbl,
                               self.micLbl, self.acceptLbl])
            view.alpha = 0;
        self.endBtn.alpha = 0.5f;
    }];
}

/// A slow breath on the status while it is still ringing - the one hint that
/// the call is live and not stuck.
- (void)setStatusPulsing:(BOOL)pulsing {
    if (!pulsing){
        [self.statusLabel.layer removeAnimationForKey:@"pulse"];
        self.statusLabel.alpha = 1;
        return;
    }
    if ([self.statusLabel.layer animationForKey:@"pulse"])
        return;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1.0f;
    fade.toValue = @0.45f;
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
