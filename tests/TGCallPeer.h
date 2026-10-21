// TGCallPeer.h — a loopback peer simulator for call stack testing.
//
// TGCallPeer impersonates the other end of a voice call without any real
// Telegram account, server, or network path beyond 127.0.0.1.
//
// Usage pattern:
//   1. Create TGCallPeer with the same 256-byte call key as TGCall, but with
//      outgoing reversed (if TGCall.outgoing==YES, set peer.isOutgoing=NO).
//   2. Call -start to open a UDP listener on 127.0.0.1.
//   3. Point TGCall's reflector at 127.0.0.1:peer.listenPort — or use
//      TGCallReflectorStub for in-process tests with no real sockets.
//   4. The peer automatically responds to STUN checks and decrypts audio frames.
//
#import <Foundation/Foundation.h>

@interface TGCallPeer : NSObject

/// The same 256-byte key as TGCall.shared.callKey, with the direction
/// reversed for proper keyspace selection.
@property (nonatomic, strong) NSData *callKey;

/// Opposite of TGCall.outgoing so the key halves line up correctly.
@property (nonatomic, assign) BOOL isOutgoing;

/// ICE credentials we generate; hand these to TGCallIce as peerUfrag/peerPwd.
@property (nonatomic, readonly) NSString *ufrag;
@property (nonatomic, readonly) NSString *pwd;

/// Port we listen on (assigned after -start).
@property (nonatomic, readonly) uint16_t listenPort;

/// The four bytes this peer puts in the reflector header as the sender tag.
@property (nonatomic, readonly) uint32_t localTag;

// ── statistics ──────────────────────────────────────────────────────────────
@property (nonatomic, readonly) uint32_t stunRequestsReceived;
@property (nonatomic, readonly) uint32_t stunResponsesReceived;
@property (nonatomic, readonly) uint32_t audioFramesReceived;
@property (nonatomic, readonly) uint32_t decryptFailures;
@property (nonatomic, readonly) uint32_t acksReceived;
@property (nonatomic, readonly) uint32_t mediaStateMessagesReceived;
@property (nonatomic, readonly) uint32_t remoteStatusMessagesReceived;
@property (nonatomic, readonly) uint32_t rtcpReportsReceived;

/// Called on main queue whenever a decrypted Opus frame arrives.
@property (nonatomic, copy) void (^onAudioFrame)(NSData *opusFrame);

/// Called on main queue the first time a STUN check is received.
@property (nonatomic, copy) void (^onStunCheckReceived)(void);

// ── lifecycle ───────────────────────────────────────────────────────────────

/// Open the UDP socket and begin processing packets.  Returns YES on success.
- (BOOL)start;

/// Close the socket and stop processing.
- (void)stop;

// ── peer actions ────────────────────────────────────────────────────────────

/// Build a real tgcalls-format single-message audio packet and encrypt it with
/// the call key (from our side's perspective).
- (NSData *)encryptedAudioPacketWithOpusFrame:(NSData *)frame seq:(uint32_t)seq;

/// Same, with control over the acknowledgement bit. A packet that asks to be
/// acknowledged makes TGCall send an ACK back.
- (NSData *)encryptedAudioPacketWithOpusFrame:(NSData *)frame
                                          seq:(uint32_t)seq
                                   requiresAck:(BOOL)requiresAck;

/// Build an audio message around an arbitrary RTP payload (header, CSRC list,
/// extension block and Opus frame). Encrypts and returns it for sending.
- (NSData *)encryptedAudioPacketWithRTPPayload:(NSData *)rtpPayload;

/// Send bytes as-is to the reflector socket learned from the last packet.
/// Used to exercise the packet layouts TGCall's inspector falls back to.
- (BOOL)sendRawToLastReflector:(NSData *)bytes;

/// Wrap `payload` in the reflector header learned from the last packet that
/// arrived, and send it back to that socket. Returns NO until TGCall has sent
/// something through its reflector, because there is no address to answer yet.
- (BOOL)sendReflectorPayload:(NSData *)payload;

@end
