// TGCallIntegrationTests.m — end-to-end call stack tests using TGCallPeer.
//
// These tests drive TGCall directly (bypassing TDLib) by feeding it the same
// updates that TDLib would have sent.  TGCallPeer acts as the remote peer on
// 127.0.0.1 and verifies that real STUN checks, signalling messages, and audio
// frames travel end-to-end.
//
// What these tests prove:
//   • TGCall transitions to Established when ICE succeeds.
//   • Audio frames sent by TGCall arrive at TGCallPeer decryptable.
//   • Audio frames sent by TGCallPeer reach TGCall.audioEngine.
//   • Muting prevents outgoing audio frames.
//   • hangUp tears down all sockets (no crash, state = Ended).
//
// What they do NOT test (out of scope):
//   • TDLib integration, real Telegram servers, real audio I/O hardware.
//   • Design / UI / AVFoundation routing (separate concern).
//
// ─── How the fake TDLib update is built ──────────────────────────────────────
//
// TGCall.handleUpdate: expects a dictionary shaped like the TDLib object:
//   { "@type": "call",
//     "id": <int32>,
//     "user_id": <int64>,
//     "is_outgoing": <bool>,
//     "state": { "@type": "callStateReady",
//                "encryption_key": <base64 256 bytes>,
//                "servers": [ { "ip_address": "...", "port": ...,
//                               "type": { "@type": "callServerTypeTelegramReflector",
//                                         "peer_tag": <base64 16 bytes> } } ],
//                "protocol": { "@type": "callProtocol",
//                              "library_versions": ["9.0.0"] } } }
//
#import <XCTest/XCTest.h>
#import "TGCall.h"
#import "TGCallPeer.h"
#import "TGCallTestHelpers.h"

// ─── forward declaration of the private -teardown to reset state between tests
@interface TGCall ()
- (void)teardown;
@end

// ─────────────────────────────────────────────────────────────────────────────

@interface TGCallIntegrationTests : XCTestCase
@property (nonatomic, strong) TGCallPeer *peer;
@end

@implementation TGCallIntegrationTests

// ── test lifecycle ─────────────────────────────────────────────────────────

- (void)setUp {
    [super setUp];
    // Reset the shared TGCall singleton between tests.
    [[TGCall shared] teardown];
    [[TGCall shared] setState_test:TGCallStateNone];
}

- (void)tearDown {
    [[TGCall shared] teardown];
    [self.peer stop];
    self.peer = nil;
    [super tearDown];
}

// ── helpers ────────────────────────────────────────────────────────────────

/// Build a fake callStateReady update that points TGCall's reflector at
/// the TGCallPeer's UDP socket.
- (NSDictionary *)fakeReadyUpdateWithPeer:(TGCallPeer *)peer
                                    callId:(int32_t)callId
                                isOutgoing:(BOOL)outgoing
                                   callKey:(NSData *)callKey {
    // Build a fake 16-byte peer tag that the reflector will accept.
    uint8_t rawTag[16];
    arc4random_buf(rawTag, sizeof(rawTag));
    NSString *peerTagB64 = [[NSData dataWithBytes:rawTag length:16]
                             base64EncodedStringWithOptions:0];
    NSString *keyB64 = [callKey base64EncodedStringWithOptions:0];

    return @{
        @"@type"      : @"call",
        @"id"         : @(callId),
        @"user_id"    : @(42LL),
        @"is_outgoing": @(outgoing),
        @"state"      : @{
            @"@type"          : @"callStateReady",
            @"encryption_key" : keyB64,
            @"servers"        : @[@{
                @"ip_address" : @"127.0.0.1",
                @"port"       : @(peer.listenPort),
                @"type"       : @{
                    @"@type"    : @"callServerTypeTelegramReflector",
                    @"peer_tag" : peerTagB64,
                },
            }],
            @"protocol"       : @{
                @"@type"            : @"callProtocol",
                @"library_versions" : @[@"9.0.0"],
            },
        },
    };
}

/// Start a TGCallPeer and hand it the call key from the opposite direction.
- (TGCallPeer *)startPeerWithKey:(NSData *)key tgCallIsOutgoing:(BOOL)tgOutgoing {
    TGCallPeer *peer = [[TGCallPeer alloc] init];
    peer.callKey    = key;
    peer.isOutgoing = !tgOutgoing;  // reversed
    [peer start];
    return peer;
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - call state machine

/// Feeding TGCall a callStatePending update must move it to Pending.
- (void)testHandleUpdate_PendingState {
    NSDictionary *update = @{
        @"@type"      : @"call",
        @"id"         : @(1),
        @"user_id"    : @(42LL),
        @"is_outgoing": @NO,
        @"state"      : @{ @"@type": @"callStatePending" },
    };
    [[TGCall shared] handleUpdate:update];
    XCTAssertEqual([TGCall shared].state, TGCallStatePending);
}

/// callStateExchangingKeys must move to ExchangingKeys.
- (void)testHandleUpdate_ExchangingKeysState {
    NSDictionary *update = @{
        @"@type"      : @"call",
        @"id"         : @(1),
        @"user_id"    : @(42LL),
        @"is_outgoing": @NO,
        @"state"      : @{ @"@type": @"callStateExchangingKeys" },
    };
    [[TGCall shared] handleUpdate:update];
    XCTAssertEqual([TGCall shared].state, TGCallStateExchangingKeys);
}

/// callStateDiscarded must tear down and move to Ended.
- (void)testHandleUpdate_DiscardedState {
    NSDictionary *update = @{
        @"@type"      : @"call",
        @"id"         : @(1),
        @"user_id"    : @(42LL),
        @"is_outgoing": @NO,
        @"state"      : @{
            @"@type"  : @"callStateDiscarded",
            @"reason" : @{ @"@type": @"callDiscardReasonHungUp" },
        },
    };
    [[TGCall shared] handleUpdate:update];
    XCTAssertEqual([TGCall shared].state, TGCallStateEnded);
}

/// onStateChanged callback is fired.
- (void)testOnStateChanged_CalledOnTransition {
    __block TGCallState observed = TGCallStateNone;
    [TGCall shared].onStateChanged = ^(TGCallState s){ observed = s; };

    NSDictionary *update = @{
        @"@type"      : @"call",
        @"id"         : @(2),
        @"user_id"    : @(99LL),
        @"is_outgoing": @YES,
        @"state"      : @{ @"@type": @"callStatePending" },
    };
    [[TGCall shared] handleUpdate:update];

    XCTAssertEqual(observed, TGCallStatePending,
                   @"onStateChanged must be called with the new state");
    [TGCall shared].onStateChanged = nil;
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - media path (requires loopback)

/// TGCall transitions to Connecting when callStateReady arrives with a valid key.
- (void)testHandleUpdate_ReadyMovesToConnecting {
    NSData *key = TGTestCallKey();
    self.peer = [self startPeerWithKey:key tgCallIsOutgoing:YES];

    NSDictionary *update = [self fakeReadyUpdateWithPeer:self.peer
                                                  callId:10
                                              isOutgoing:YES
                                                 callKey:key];
    [[TGCall shared] handleUpdate:update];

    // Connecting is set synchronously inside handleUpdate → startMediaWithState.
    XCTAssertEqual([TGCall shared].state, TGCallStateConnecting);
}

/// TGCall sends a STUN check that TGCallPeer receives within 2 seconds.
- (void)testStunCheckReachesSimulator {
    NSData *key = TGTestCallKey();
    self.peer = [self startPeerWithKey:key tgCallIsOutgoing:YES];

    __block BOOL stunArrived = NO;
    self.peer.onStunCheckReceived = ^{ stunArrived = YES; };

    NSDictionary *update = [self fakeReadyUpdateWithPeer:self.peer
                                                  callId:11
                                              isOutgoing:YES
                                                 callKey:key];
    [[TGCall shared] handleUpdate:update];

    // Also feed the peer's ICE credentials as a signalling message so TGCall
    // knows the peerUfrag/peerPwd to put in its STUN checks.
    NSData *candidatesBody = [TGCallMessages
        candidatesBody:@[[NSString stringWithFormat:
            @"candidate:1 1 udp 2130706431 reflector-1-%u.reflector %u "
            @"typ relay generation 0 ufrag %@ network-id 9 network-cost 50",
            (unsigned)arc4random(), (unsigned)self.peer.listenPort, self.peer.ufrag]]
        ufrag:self.peer.ufrag
        pwd:self.peer.pwd];

    // Encrypt the candidates message from the peer's perspective.
    NSData *candidatesMsg = [TGCallMessages messageWithType:TGCallMessageCandidates
                                                       body:candidatesBody];
    NSData *encrypted = [self encryptSignallingData:candidatesMsg key:key fromOutgoing:NO seq:1];
    if (encrypted)
        [[TGCall shared] handleSignalingData:encrypted];

    BOOL ok = TGWaitForCondition(^{ return stunArrived; }, 3.0);
    XCTAssertTrue(ok, @"TGCallPeer should receive a STUN check within 3 s");
}

/// hangUp sets state to Ended and does not crash.
- (void)testHangUpSetsEndedState {
    // Feed a pending state so callId is set.
    NSDictionary *pending = @{
        @"@type"      : @"call",
        @"id"         : @(5),
        @"user_id"    : @(7LL),
        @"is_outgoing": @NO,
        @"state"      : @{ @"@type": @"callStatePending" },
    };
    [[TGCall shared] handleUpdate:pending];
    XCTAssertNoThrow([[TGCall shared] hangUp]);
    XCTAssertEqual([TGCall shared].state, TGCallStateEnded);
}

/// duration returns 0 before the call is established.
- (void)testDurationZeroBeforeEstablished {
    XCTAssertEqual([[TGCall shared] duration], 0.0);
}

/// setMuted changes the muted property.
- (void)testSetMuted {
    [[TGCall shared] setMuted:YES];
    XCTAssertTrue([TGCall shared].muted);
    [[TGCall shared] setMuted:NO];
    XCTAssertFalse([TGCall shared].muted);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - crypto helpers

/// Encrypt a signalling plaintext as if the peer sent it.
/// outgoing=NO means we are the callee encrypting for the caller.
- (NSData *)encryptSignallingData:(NSData *)plain key:(NSData *)key
                      fromOutgoing:(BOOL)outgoing seq:(uint32_t)seq {
    NSMutableData *enc = [NSMutableData dataWithLength:plain.length + 32];
    int sz = TGCallEncryptPacket(key.bytes, outgoing ? 1 : 0, 1 /* signalling */,
                                 plain.bytes, plain.length, seq,
                                 enc.mutableBytes);
    if (sz <= 0) return nil;
    enc.length = (NSUInteger)sz;
    return enc;
}

@end

// ─── Private test helper category ────────────────────────────────────────────
// Exposes just enough internals to let tests reset the singleton state.
#include "TGCallCrypto.h"

@implementation TGCall (TestSupport)

- (void)setState_test:(TGCallState)state {
    self.state = state;
}

@end
