//
// TGCallV2Session - the tgcalls 9.0.0 audio session: V2 signalling, DTLS,
// SRTP keys and RTP. TGCall owns one of these only when callStateReady names
// 9.0.0; the 5.0.0 path is untouched.
//
#ifndef TG_CALL_V2_SESSION_H
#define TG_CALL_V2_SESSION_H

#import <Foundation/Foundation.h>

@interface TGCallV2Session : NSObject

/// Caller = YES. Chooses the DTLS client role, the ICE role and actpass.
@property (nonatomic, assign) BOOL outgoing;

/// Must be the same ufrag the candidate line names.
@property (nonatomic, copy) NSString *localUfrag;
@property (nonatomic, copy) NSString *localPwd;
@property (nonatomic, assign) uint32_t localSsrc;

/// Encrypts and sends one signalling plaintext with this packet sequence.
@property (nonatomic, copy) void (^sendSignaling)(NSData *plaintext, uint32_t seq);
/// Sends one DTLS record or SRTP datagram to the peer's reflector tag.
@property (nonatomic, copy) void (^sendMedia)(const uint8_t *bytes, size_t length);
/// Candidate strings from the peer, for the ICE layer.
@property (nonatomic, copy) void (^onRemoteCandidates)(NSArray *candidates);
/// ICE credentials from InitialSetup. Candidates in 9.0.0 do not carry them.
@property (nonatomic, copy) void (^onPeerCredentials)(NSString *ufrag, NSString *pwd);
@property (nonatomic, copy) void (^onEstablished)(void);
@property (nonatomic, copy) void (^onAudio)(const uint8_t *rtp, size_t length);
@property (nonatomic, copy) void (^onFailure)(NSString *reason);

- (void)start;
/// The reflector path is usable. DTLS starts here, not before: a ClientHello
/// sent into an unwritable path only buys a retransmission timer.
- (void)iceConnected;
- (void)handlePlaintext:(NSData *)plaintext packetSeq:(uint32_t)seq;
- (void)handlePacket:(const uint8_t *)bytes length:(size_t)length;
- (void)sendCandidates:(NSArray *)candidates;
- (void)sendOpusFrame:(NSData *)frame;
- (void)tick;
- (void)stop;

@end

#endif
