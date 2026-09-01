//
// TGCall - one voice call.
//
// TDLib does the signalling: it negotiates the call, hands over the reflector
// servers and a 256-byte encryption key, and reports the other side hanging
// up. It carries no audio. The media is libtgvoip, vendored in src/libtgvoip -
// the same library the official client used when it brought calls to an
// iPhone 4S in 2017, which is why this works on this hardware at all.
//
// Built without the WebRTC DSP, so there is no echo cancellation: on speaker
// the other side hears themselves. The earpiece is fine.
//
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TGCallState) {
    TGCallStateNone = 0,
    TGCallStatePending,        ///< ringing, either direction
    TGCallStateExchangingKeys,
    TGCallStateConnecting,
    TGCallStateEstablished,
    TGCallStateEnded,
    TGCallStateFailed
};

@interface TGCall : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) TGCallState state;
@property (nonatomic, readonly) int32_t callId;
@property (nonatomic, readonly) int64_t peerUserId;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) BOOL muted;
@property (nonatomic, readonly) NSData *callKey;

- (void)setSpeaker:(BOOL)speaker;

/// Why the last call ended, when the other side said. Nil otherwise.
@property (nonatomic, readonly) NSString *endReason;

/// Main queue, whenever the state changes.
@property (nonatomic, copy) void (^onStateChanged)(TGCallState state);

/// Ask TDLib to place a call. The rest arrives through -handleUpdate:.
- (void)callUser:(int64_t)userId;
- (void)accept;
- (void)hangUp;
- (void)setMuted:(BOOL)muted;

/// Fed every updateNewCallSignalingData from TGClient. This is the channel
/// tgcalls negotiates over - encrypted with the call key, JSON inside.
- (void)handleSignalingData:(NSData *)data;

/// Fed every updateCall from TGClient.
- (void)handleUpdate:(NSDictionary *)call;

/// Seconds since the call was established, for the screen to show.
- (NSTimeInterval)duration;

@end
