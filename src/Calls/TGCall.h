//
// TGCall - voice call controller using TDLib for signalling and libtgvoip for audio.
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
@property (nonatomic, readonly) NSArray *emojis;

- (void)setSpeaker:(BOOL)speaker;

/// Why the last call ended, when the other side said. Nil otherwise.
@property (nonatomic, readonly) NSString *endReason;

/// Main queue, whenever the state changes.
@property (nonatomic, copy) void (^onStateChanged)(TGCallState state);
@property (nonatomic, copy) void (^onIncomingCall)(int64_t peerUserId, int32_t callId);

/// Ask TDLib to place a call. The rest arrives through -handleUpdate:.
- (void)callUser:(int64_t)userId;
- (void)accept;
- (void)hangUp;
- (void)setMuted:(BOOL)muted;

/// Sends a rating (1..5) with optional comment and problem list to TDLib for the call.
- (void)sendRating:(int)rating comment:(NSString *)comment problems:(NSArray *)problems;

/// Fed every updateNewCallSignalingData from TGClient. This is the channel
/// tgcalls negotiates over - encrypted with the call key, JSON inside.
- (void)handleSignalingData:(NSData *)data;

/// Fed every updateCall from TGClient.
- (void)handleUpdate:(NSDictionary *)call;

/// Seconds since the call was established, for the screen to show.
- (NSTimeInterval)duration;

@end
