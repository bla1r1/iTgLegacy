#import "TGCallViewController.h"
#import "TGCall.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGIcons.h"
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

@property (nonatomic, strong) NSTimer *ticker;
@end

@implementation TGCallViewController

+ (void)presentForUserId:(int64_t)userId name:(NSString *)name outgoing:(BOOL)outgoing {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController)
        top = top.presentedViewController;

    TGCallViewController *screen = [[TGCallViewController alloc]
            initWithUserId:userId name:name outgoing:outgoing];
    [top presentViewController:screen animated:YES completion:nil];
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
    CGFloat gap = (b.size.width - (60 * 4)) / 5;
    
    self.speakerBtn = [self createButtonAtX:gap y:btnY title:@"Speaker" icon:@"🔊"];
    self.videoBtn = [self createButtonAtX:gap*2 + 60 y:btnY title:@"Video" icon:@"📹"];
    self.micBtn = [self createButtonAtX:gap*3 + 120 y:btnY title:@"Mute" icon:@"🎤"];
    self.endBtn = [self createButtonAtX:gap*4 + 180 y:btnY title:@"End" icon:@"✖️"];
    
    self.endBtn.backgroundColor = [UIColor colorWithRed:0.9f green:0.2f blue:0.2f alpha:1];
    
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
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    [btn setTitle:icon forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:24];
    [self.view addSubview:btn];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(x - 10, y + 65, 80, 15)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:12];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.backgroundColor = [UIColor clearColor];
    [self.view addSubview:lbl];
    
    return btn;
}

- (void)applyState:(TGCallState)state {
    switch (state){
        case TGCallStatePending:
            self.statusLabel.text = self.outgoing ? @"Запит..." : @"Incoming...";
            break;
        case TGCallStateExchangingKeys:
        case TGCallStateConnecting:
            self.statusLabel.text = @"Connecting...";
            break;
        case TGCallStateEstablished:
            self.bgLayer.colors = @[(id)[UIColor colorWithRed:0.27f green:0.69f blue:0.55f alpha:1].CGColor,
                                    (id)[UIColor colorWithRed:0.45f green:0.77f blue:0.43f alpha:1].CGColor];
            [self setupEmojis];
            break;
        case TGCallStateFailed:
            self.statusLabel.text = [TGCall shared].endReason ?: @"Call failed";
            [self dismissShortly];
            break;
        case TGCallStateEnded:
            self.statusLabel.text = [TGCall shared].endReason ?: @"Call ended";
            [self dismissShortly];
            break;
        default:
            break;
    }
}

- (void)setupEmojis {
    NSData *key = [TGCall shared].callKey;
    if (key.length >= 32) {
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(key.bytes, (CC_LONG)key.length, hash);
        
        NSArray *emojis = @[@"🐶", @"🐱", @"🐭", @"🐹", @"🐰", @"🦊", @"🐻", @"🐼", @"🐨", @"🐯", @"🦁", @"🐮", @"🐷", @"🐸", @"🐵"];
        NSString *e1 = emojis[hash[0] % emojis.count];
        NSString *e2 = emojis[hash[1] % emojis.count];
        NSString *e3 = emojis[hash[2] % emojis.count];
        NSString *e4 = emojis[hash[3] % emojis.count];
        self.emojiLabel.text = [NSString stringWithFormat:@"%@ %@ %@ %@", e1, e2, e3, e4];
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
    [[TGCall shared] hangUp];
    [self dismissShortly];
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
