// TGCallIntegrationTests.m — end-to-end call stack tests using TGCallPeer.
//
// These tests drive TGCall directly (bypassing TDLib) by feeding it the same
// updates that TDLib would have sent.  TGCallPeer acts as the remote peer on
// 127.0.0.1 and verifies that real STUN checks and signalling messages travel
// end-to-end.
//
// What these tests prove:
//   • TGCall moves through Pending / ExchangingKeys / Connecting / Ended.
//   • callStateReady starts media and sends a real STUN check to the peer.
//   • onStateChanged fires for transitions; hangUp ends the call; duration
//     is zero before establishment; setMuted changes the flag.
//
// What they do NOT test (out of scope):
//   • TDLib integration, real Telegram servers, real audio I/O hardware.
//   • Audio encode/decode and AVAudioSession routing. TGClient and
//     TGCallAudioEngine are replaced by the (Testing) stubs in this directory;
//     the macOS AVAudioSession shim is in tests/shim.
//   • Design / UI (separate concern).
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
#import "TGTestRunner.h"
#import "TGCall.h"
#import "TGCallAudioEngine.h"
#import "TGCallMessages.h"
#import "TGCallPeer.h"
#import "TGCallTestHelpers.h"
#import "TGClient.h"

// ─── private members needed to reset the singleton between tests
@interface TGCall ()
@property (nonatomic, assign) TGCallState state;
@property (nonatomic, strong) TGCallAudioEngine *audioEngine;
@property (nonatomic, assign) uint32_t currentSenderTag;
- (void)teardown;
@end

@interface TGCall (TestSupport)
@property (nonatomic, readonly) NSString *localUfrag;
@property (nonatomic, readonly) NSString *localPwd;
@property (nonatomic, assign) BOOL audioFramingProven;
@property (nonatomic, readonly) TGCallReflector *reflector;
- (void)probeAudioFramingWith:(NSData *)audioMessage;
- (void)readPeerTagFromCandidate:(NSString *)candidate;
@end

@interface TGCall (TestSupportState)
- (void)setState_test:(TGCallState)state;
@end

// The test binary compiles TGCallAudioEngineStub.m instead of the real engine.
@interface TGCallAudioEngine (Testing)
+ (NSArray<NSData *> *)receivedFrames;
+ (void)resetReceivedFrames;
@end

// The test binary compiles TGClientStub.m instead of the TDLib client.
@interface TGClient (Testing)
+ (NSArray<NSDictionary *> *)sentRequests;
+ (void)resetSentRequests;
@end

// ─────────────────────────────────────────────────────────────────────────────

@interface TGCallIntegrationTests : XCTestCase
@property (nonatomic, strong) TGCallPeer *peer;
@end

@implementation TGCallIntegrationTests

// ── test lifecycle ─────────────────────────────────────────────────────────

- (void)setUp {
    [super setUp];
    // Reset the shared TGCall singleton between tests. Sockets from the
    // previous test deliver through dispatch_get_main_queue, so let those
    // blocks run first and tear down once more: a stale callback would
    // otherwise mark the new call established before it has a media path.
    [[TGCall shared] teardown];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    [[TGCall shared] teardown];
    [[TGCall shared] setState_test:TGCallStateNone];
    [[TGCall shared] setMuted:NO];
    [TGCallAudioEngine resetReceivedFrames];
    [TGClient resetSentRequests];
}

- (void)tearDown {
    [[TGCall shared] teardown];
    [self.peer stop];
    self.peer = nil;
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
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

/// Feed the peer's ICE credentials and candidate the way TDLib would, so
/// TGCallIce knows who to send checks to and what password signs them.
- (void)feedPeerCandidatesWithKey:(NSData *)key {
    NSData *candidatesBody = [TGCallMessages
        candidatesBody:@[[NSString stringWithFormat:
            @"candidate:1 1 udp 2130706431 reflector-1-%u.reflector %u "
            @"typ relay generation 0 ufrag %@ network-id 9 network-cost 50",
            (unsigned)arc4random(), (unsigned)self.peer.listenPort, self.peer.ufrag]]
        ufrag:self.peer.ufrag
        pwd:self.peer.pwd];

    NSData *candidatesMsg = [TGCallMessages messageWithType:TGCallMessageCandidates
                                                       body:candidatesBody];
    NSData *encrypted = [self encryptSignallingData:candidatesMsg
                                                key:key
                                       fromOutgoing:NO
                                                seq:1];
    if (encrypted)
        [[TGCall shared] handleSignalingData:encrypted];
}

/// Place a call, feed it the peer's credentials and wait for the media path
/// to come up. Returns NO if ICE never connects.
- (BOOL)startEstablishedCallWithKey:(NSData *)key callId:(int32_t)callId {
    self.peer = [self startPeerWithKey:key tgCallIsOutgoing:YES];

    NSDictionary *update = [self fakeReadyUpdateWithPeer:self.peer
                                                  callId:callId
                                              isOutgoing:YES
                                                 callKey:key];
    [[TGCall shared] handleUpdate:update];
    [self feedPeerCandidatesWithKey:key];

    // Wait for this peer specifically, not just for the singleton to say
    // "established": a late callback from a previous test's socket can set that
    // state, and then the new call's media path would not exist yet.
    return TGWaitForCondition(^{
        return (BOOL)([TGCall shared].state == TGCallStateEstablished &&
                      [TGCall shared].currentSenderTag == self.peer.localTag);
    }, 4.0);
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

    // Feed the peer's ICE credentials so TGCall knows who to ask.
    [self feedPeerCandidatesWithKey:key];

    BOOL ok = TGWaitForCondition(^{ return (BOOL)stunArrived; }, 3.0);
    XCTAssertTrue(ok, @"TGCallPeer should receive a STUN check within 3 s");
}

/// An audio frame sent by the peer through the reflector must be decrypted
/// and handed to the audio engine unchanged.
- (void)testPeerAudioFrameReachesAudioEngine {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:20],
                  @"ICE must connect before audio can flow");

    uint8_t opusBytes[] = { 0xF8, 0xFF, 0xFE };
    NSData *opusFrame = [NSData dataWithBytes:opusBytes length:sizeof(opusBytes)];

    NSData *packet = [self.peer encryptedAudioPacketWithOpusFrame:opusFrame seq:1];
    XCTAssertNotNil(packet);
    XCTAssertTrue([self.peer sendReflectorPayload:packet],
                  @"peer must know the reflector address by now");

    BOOL arrived = TGWaitForCondition(^{
        return (BOOL)([TGCallAudioEngine receivedFrames].count > 0);
    }, 2.0);
    XCTAssertTrue(arrived, @"the decrypted frame must reach the audio engine");
    XCTAssertEqualObjects([TGCallAudioEngine receivedFrames].firstObject, opusFrame);
}

/// An encoded frame from the audio engine must be encrypted, wrapped and
/// delivered to the peer, and mute must drop it on the way out.
- (void)testOutgoingAudioFrameReachesPeerAndMuteDropsIt {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:21],
                  @"ICE must connect before audio can flow");

    __block NSData *peerFrame = nil;
    self.peer.onAudioFrame = ^(NSData *frame){ if (!peerFrame) peerFrame = frame; };

    uint8_t opusBytes[] = { 0x01, 0x02, 0x03, 0x04 };
    NSData *opusFrame = [NSData dataWithBytes:opusBytes length:sizeof(opusBytes)];

    TGCall *call = [TGCall shared];
    XCTAssertNotNil(call.audioEngine, @"connecting must start the audio engine");
    XCTAssertNotNil(call.audioEngine.onOutgoingOpusFrame);

    call.audioEngine.onOutgoingOpusFrame(opusFrame);

    BOOL arrived = TGWaitForCondition(^{ return (BOOL)(peerFrame != nil); }, 2.0);
    XCTAssertTrue(arrived, @"the peer must decrypt the outgoing frame");
    XCTAssertEqualObjects(peerFrame, opusFrame);

    uint32_t framesBefore = self.peer.audioFramesReceived;
    call.muted = YES;
    call.audioEngine.onOutgoingOpusFrame(opusFrame);

    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.5]];
    XCTAssertEqual(self.peer.audioFramesReceived, framesBefore,
                   @"muted frames must not leave the device");
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
#pragma mark - TDLib-facing actions

/// Placing a call must ask TDLib for one with the protocol this build speaks.
- (void)testCallUserSendsCreateCall {
    [[TGCall shared] callUser:77];

    XCTAssertEqual([TGCall shared].state, TGCallStatePending);
    XCTAssertTrue([TGCall shared].outgoing);
    XCTAssertEqual([TGCall shared].peerUserId, (int64_t)77);

    NSDictionary *request = [TGClient sentRequests].firstObject;
    XCTAssertNotNil(request);
    XCTAssertTrue([request[@"@type"] isEqualToString:@"createCall"]);
    XCTAssertEqual([request[@"user_id"] longLongValue], 77LL);

    NSDictionary *protocol = request[@"protocol"];
    XCTAssertTrue([protocol[@"@type"] isEqualToString:@"callProtocol"]);
    XCTAssertTrue([protocol[@"udp_reflector"] boolValue]);
    XCTAssertTrue([protocol[@"udp_p2p"] boolValue]);
}

/// Accepting an incoming call must name the call TDLib already assigned.
- (void)testAcceptSendsAcceptCall {
    [[TGCall shared] handleUpdate:@{
        @"@type"      : @"call",
        @"id"         : @(7),
        @"user_id"    : @(42LL),
        @"is_outgoing": @NO,
        @"state"      : @{ @"@type": @"callStatePending" },
    }];
    [TGClient resetSentRequests];

    [[TGCall shared] accept];

    NSDictionary *request = [TGClient sentRequests].firstObject;
    XCTAssertNotNil(request);
    XCTAssertTrue([request[@"@type"] isEqualToString:@"acceptCall"]);
    XCTAssertEqual([request[@"call_id"] intValue], 7);
    XCTAssertNotNil(request[@"protocol"]);
}

- (void)testHangUpSendsDiscardCall {
    [[TGCall shared] handleUpdate:@{
        @"@type"      : @"call",
        @"id"         : @(12),
        @"user_id"    : @(42LL),
        @"is_outgoing": @YES,
        @"state"      : @{ @"@type": @"callStatePending" },
    }];
    [TGClient resetSentRequests];

    [[TGCall shared] hangUp];

    NSDictionary *request = [TGClient sentRequests].firstObject;
    XCTAssertNotNil(request);
    XCTAssertTrue([request[@"@type"] isEqualToString:@"discardCall"]);
    XCTAssertEqual([request[@"call_id"] intValue], 12);
}

- (void)testSendRatingSendsSendCallRating {
    [[TGCall shared] handleUpdate:@{
        @"@type"      : @"call",
        @"id"         : @(15),
        @"user_id"    : @(42LL),
        @"is_outgoing": @YES,
        @"state"      : @{ @"@type": @"callStatePending" },
    }];
    [TGClient resetSentRequests];

    [[TGCall shared] sendRating:5 comment:@"Great audio" problems:@[]];

    NSDictionary *request = [TGClient sentRequests].firstObject;
    XCTAssertNotNil(request);
    XCTAssertTrue([request[@"@type"] isEqualToString:@"sendCallRating"]);
    XCTAssertEqual([request[@"call_id"] intValue], 15);
    XCTAssertEqual([request[@"rating"] intValue], 5);
    XCTAssertTrue([request[@"comment"] isEqualToString:@"Great audio"]);
}

- (void)testSetSpeakerDoesNotCrash {
    XCTAssertNoThrow([[TGCall shared] setSpeaker:YES]);
    XCTAssertNoThrow([[TGCall shared] setSpeaker:NO]);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - call endings

/// A rejected call carries TDLib's reason through to the screen.
- (void)testHandleUpdate_EndReasons {
    NSArray *cases = @[
        @[@"callDiscardReasonDeclined",     @"Declined"],
        @[@"callDiscardReasonMissed",       @"No answer"],
        @[@"callDiscardReasonDisconnected", @"Disconnected"],
        @[@"callDiscardReasonHungUp",       @"Call ended"],
        @[@"callDiscardReasonUpgradeToGroupCall", @"Moved to a group call"],
    ];

    for (NSArray *pair in cases) {
        [[TGCall shared] handleUpdate:@{
            @"@type"      : @"call",
            @"id"         : @(1),
            @"user_id"    : @(42LL),
            @"is_outgoing": @NO,
            @"state"      : @{
                @"@type"  : @"callStateDiscarded",
                @"reason" : @{ @"@type": pair[0] },
            },
        }];
        XCTAssertEqual([TGCall shared].state, TGCallStateEnded);
        XCTAssertTrue([[TGCall shared].endReason isEqualToString:pair[1]],
                      @"reason %@ must read as %@", pair[0], pair[1]);
    }
}

/// callStateError keeps TDLib's message and ends in Failed, not Ended.
- (void)testHandleUpdate_ErrorState {
    [[TGCall shared] handleUpdate:@{
        @"@type"      : @"call",
        @"id"         : @(3),
        @"user_id"    : @(42LL),
        @"is_outgoing": @YES,
        @"state"      : @{
            @"@type" : @"callStateError",
            @"error" : @{ @"code": @(400), @"message": @"Nope" },
        },
    }];

    XCTAssertEqual([TGCall shared].state, TGCallStateFailed);
    XCTAssertTrue([[TGCall shared].endReason isEqualToString:@"Nope"]);
}

/// A ready update whose encryption key is not 256 bytes cannot start media.
- (void)testReadyWithBadKeyFails {
    NSData *shortKey = [NSData dataWithBytes:"too short" length:9];
    [[TGCall shared] handleUpdate:@{
        @"@type"      : @"call",
        @"id"         : @(33),
        @"user_id"    : @(42LL),
        @"is_outgoing": @YES,
        @"state"      : @{
            @"@type"          : @"callStateReady",
            @"encryption_key" : [shortKey base64EncodedStringWithOptions:0],
            @"servers"        : @[],
            @"protocol"       : @{ @"@type": @"callProtocol",
                                   @"library_versions": @[@"9.0.0"] },
        },
    }];

    XCTAssertEqual([TGCall shared].state, TGCallStateFailed);
    XCTAssertNil([TGCall shared].callKey);
}

/// callStateReady can arrive twice; the first one owns the call.
- (void)testReadyAgainIsIgnored {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:30]);

    NSMutableData *otherKey = [key mutableCopy];
    ((uint8_t *)otherKey.mutableBytes)[0] ^= 0xFF;
    NSDictionary *update = [self fakeReadyUpdateWithPeer:self.peer
                                                  callId:31
                                              isOutgoing:YES
                                                 callKey:otherKey];
    [[TGCall shared] handleUpdate:update];

    XCTAssertEqual([TGCall shared].state, TGCallStateEstablished);
    XCTAssertEqualObjects([TGCall shared].callKey, key,
                          @"the second ready must not replace the key");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - signalling

/// Decrypt what TGCall asked TGClient to send, from the peer's perspective.
- (NSArray *)decryptedSentSignallingWithKey:(NSData *)key {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSDictionary *request in [TGClient sentRequests]) {
        if (![request[@"@type"] isEqualToString:@"sendCallSignalingData"])
            continue;

        NSData *data = [[NSData alloc] initWithBase64EncodedString:request[@"data"]
                                                           options:0];
        if (!data.length)
            continue;

        NSMutableData *plain = [NSMutableData dataWithLength:data.length];
        uint32_t seq = 0;
        int size = TGCallDecryptPacket(key.bytes, 0 /* peer's view */,
                                       1 /* signalling */,
                                       data.bytes, data.length,
                                       plain.mutableBytes, &seq);
        if (size <= 0)
            continue;
        plain.length = (NSUInteger)size;

        // An acknowledgement is an empty message plus the acknowledged
        // sequence number and the 0xFF marker; parsePacket skips both bytes,
        // so surface it explicitly for tests that look for it.
        const uint8_t *bytes = (const uint8_t *)plain.bytes;
        if (plain.length == 6 && bytes[0] == 0xFE && bytes[5] == 0xFF) {
            [messages addObject:@{ @"type": @(TGCallMessageAck),
                                   @"seq": @(seq),
                                   @"body": [NSData data] }];
            continue;
        }

        [messages addObjectsFromArray:[TGCallMessages parsePacket:plain seq:seq]];
    }
    return messages;
}

/// Video formats from the peer get an acknowledgement and an empty answer,
/// otherwise their half of the negotiation never closes.
- (void)testVideoFormatsSignallingGetsAnswer {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:32]);

    [TGClient resetSentRequests];

    uint8_t formats[2] = { 0, 0 };
    NSData *message = [TGCallMessages messageWithType:TGCallMessageVideoFormats
                                                 body:[NSData dataWithBytes:formats
                                                                    length:sizeof(formats)]];
    NSData *encrypted = [self encryptSignallingData:message
                                                key:key
                                       fromOutgoing:NO
                                                seq:2];
    [[TGCall shared] handleSignalingData:encrypted];

    NSArray *sent = [self decryptedSentSignallingWithKey:key];
    BOOL sawAck = NO, sawVideoFormats = NO;
    for (NSDictionary *entry in sent) {
        uint8_t type = [entry[@"type"] unsignedCharValue];
        if (type == TGCallMessageAck) sawAck = YES;
        if (type == TGCallMessageVideoFormats) sawVideoFormats = YES;
    }
    XCTAssertTrue(sawAck, @"every signalling message must be acknowledged");
    XCTAssertTrue(sawVideoFormats, @"an empty video format list must be sent");
}

/// Undecryptable garbage must be dropped without changing the call.
- (void)testGarbageSignallingIsIgnored {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:34]);

    uint8_t garbage[64];
    arc4random_buf(garbage, sizeof(garbage));
    [[TGCall shared] handleSignalingData:
        [NSData dataWithBytes:garbage length:sizeof(garbage)]];

    XCTAssertEqual([TGCall shared].state, TGCallStateEstablished);
}

/// A media packet that asks to be acknowledged must be answered.
- (void)testIncomingPacketAskingForAckGetsAck {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:35]);

    uint8_t opusBytes[] = { 0x11, 0x22, 0x33 };
    NSData *packet = [self.peer encryptedAudioPacketWithOpusFrame:
        [NSData dataWithBytes:opusBytes length:sizeof(opusBytes)]
                                                             seq:1
                                                      requiresAck:YES];
    XCTAssertNotNil(packet);
    XCTAssertTrue([self.peer sendReflectorPayload:packet]);

    XCTAssertTrue(TGWaitForCondition(^{
        return (BOOL)(self.peer.acksReceived > 0);
    }, 2.0), @"TGCall must acknowledge a packet that asks for it");
}

/// The media-state bundle is acknowledged by the peer, after which TGCall
/// sends its remote network status. This is the opening handshake of a call.
- (void)testMediaStateAckSendsRemoteNetworkStatus {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:36]);

    XCTAssertTrue(TGWaitForCondition(^{
        return (BOOL)(self.peer.remoteStatusMessagesReceived > 0);
    }, 3.0), @"acknowledging media state must trigger the network status message");
    XCTAssertGreaterThan(self.peer.mediaStateMessagesReceived, (uint32_t)0);
}

/// Every fiftieth outgoing frame is followed by an RTCP receiver report, which
/// is how the far end learns about loss and jitter.
- (void)testOutgoingAudioSendsRtcpAfterFiftyFrames {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:37]);

    uint8_t opusBytes[] = { 0x01, 0x02 };
    NSData *opusFrame = [NSData dataWithBytes:opusBytes length:sizeof(opusBytes)];

    TGCall *call = [TGCall shared];
    for (int i = 0; i < 60; i++)
        call.audioEngine.onOutgoingOpusFrame(opusFrame);

    XCTAssertTrue(TGWaitForCondition(^{
        return (BOOL)(self.peer.rtcpReportsReceived > 0);
    }, 3.0), @"a receiver report must follow the fiftieth frame");
    XCTAssertGreaterThanOrEqual(self.peer.audioFramesReceived, (uint32_t)50);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - RTP framing

/// RTP may carry CSRCs and one extension block before the Opus payload; both
/// have to be skipped or the decoder receives header bytes as audio.
- (void)testIncomingRTPWithCSRCAndExtension {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:40]);

    uint8_t opusBytes[] = { 0xAB, 0xCD, 0xEF };
    uint8_t rtp[31] = {0};
    rtp[0] = 0x92;             // V=2, X=1, CC=2
    rtp[1] = 111;              // Opus
    rtp[2] = 0; rtp[3] = 7;    // sequence number
    memcpy(rtp + 12, "CSRC1234", 8);
    rtp[20] = 0xBE; rtp[21] = 0xDE;   // extension profile
    rtp[22] = 0;    rtp[23] = 1;      // one 32-bit extension word
    memcpy(rtp + 24, "EXTR", 4);
    memcpy(rtp + 28, opusBytes, sizeof(opusBytes));

    NSData *packet = [self.peer encryptedAudioPacketWithRTPPayload:
        [NSData dataWithBytes:rtp length:sizeof(rtp)]];
    XCTAssertNotNil(packet);
    XCTAssertTrue([self.peer sendReflectorPayload:packet]);

    XCTAssertTrue(TGWaitForCondition(^{
        return (BOOL)([TGCallAudioEngine receivedFrames].count > 0);
    }, 2.0));
    XCTAssertEqualObjects([TGCallAudioEngine receivedFrames].firstObject,
                          [NSData dataWithBytes:opusBytes length:sizeof(opusBytes)]);
}

/// An RTP header with no payload is silently dropped.
- (void)testIncomingRTPWithoutPayloadIsIgnored {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:41]);

    // Shorter than a fixed RTP header.
    uint8_t runt[11] = {0};
    runt[0] = 0x80;
    runt[1] = 111;
    NSData *runtPacket = [self.peer encryptedAudioPacketWithRTPPayload:
        [NSData dataWithBytes:runt length:sizeof(runt)]];
    XCTAssertNotNil(runtPacket);
    XCTAssertTrue([self.peer sendReflectorPayload:runtPacket]);

    // Header with the extension bit set but no extension block, and no payload.
    uint8_t headerOnly[12] = {0};
    headerOnly[0] = 0x90;
    headerOnly[1] = 111;
    NSData *headerPacket = [self.peer encryptedAudioPacketWithRTPPayload:
        [NSData dataWithBytes:headerOnly length:sizeof(headerOnly)]];
    XCTAssertNotNil(headerPacket);
    XCTAssertTrue([self.peer sendReflectorPayload:headerPacket]);

    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.3]];
    XCTAssertEqual([TGCallAudioEngine receivedFrames].count, (NSUInteger)0,
                   @"RTP without a payload must not reach the decoder");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - reflector packet layouts

/// The inspector tries the normal 24-byte envelope first, then 16, 20 and 0.
/// Older or malformed relays have to keep working through those fallbacks.
- (void)testInspectorFallsBackToOtherOffsets {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:42]);

    TGCall *call = [TGCall shared];
    NSData *request = [TGCallStun
        bindingRequestWithUsername:[NSString stringWithFormat:@"%@:%@",
                                    call.localUfrag, self.peer.ufrag]
                          password:call.localPwd
                        tieBreaker:0xABCDEF01ULL
                       useCandidate:YES];
    XCTAssertNotNil(request);

    NSMutableData *at16 = [NSMutableData dataWithLength:16];
    [at16 appendData:request];

    NSMutableData *at20 = [NSMutableData dataWithLength:16];
    uint8_t sender[4] = { 0x01, 0x02, 0x03, 0x04 };
    [at20 appendBytes:sender length:sizeof(sender)];
    [at20 appendData:request];

    NSArray<NSData *> *layouts = @[ request, at16, at20 ];
    for (NSData *layout in layouts) {
        uint32_t before = self.peer.stunResponsesReceived;
        XCTAssertTrue([self.peer sendRawToLastReflector:layout]);
        XCTAssertTrue(TGWaitForCondition(^{
            return (BOOL)(self.peer.stunResponsesReceived > before);
        }, 2.0), @"a check in a %lu-byte layout must still be answered",
            (unsigned long)layout.length);
    }
}

/// Garbage that is neither STUN nor decryptable must be dropped quietly.
- (void)testUnreadablePacketLeavesCallEstablished {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:43]);

    // Too short to inspect at all.
    uint8_t runt[24] = {0};
    XCTAssertTrue([self.peer sendRawToLastReflector:
        [NSData dataWithBytes:runt length:sizeof(runt)]]);

    // Long enough to try the 24-byte envelope, but not long enough for any of
    // the fallbacks to have a full header.
    uint8_t shortEnvelope[40];
    arc4random_buf(shortEnvelope, sizeof(shortEnvelope));
    XCTAssertTrue([self.peer sendRawToLastReflector:
        [NSData dataWithBytes:shortEnvelope length:sizeof(shortEnvelope)]]);

    // Plain garbage that no decryptor will accept.
    uint8_t garbage[64];
    arc4random_buf(garbage, sizeof(garbage));
    XCTAssertTrue([self.peer sendRawToLastReflector:
        [NSData dataWithBytes:garbage length:sizeof(garbage)]]);

    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:0.3]];
    XCTAssertEqual([TGCall shared].state, TGCallStateEstablished);
}

/// probeAudioFramingWith: puts an audio message in front of a message that must
/// be acknowledged. The ACK proves the peer parsed the audio framing.
- (void)testProbeAudioFramingMarksProof {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:44]);

    uint8_t opusBytes[] = { 0x01, 0x02 };
    uint16_t rtpLength = (uint16_t)(12 + sizeof(opusBytes));

    NSMutableData *audio = [NSMutableData data];
    uint8_t type = TGCallMessageAudioData;
    uint8_t length[2] = { (uint8_t)(rtpLength >> 8), (uint8_t)rtpLength };
    [audio appendBytes:&type length:1];
    [audio appendBytes:length length:2];

    uint8_t rtp[12] = {0};
    rtp[0] = 0x80;
    rtp[1] = 111;
    [audio appendBytes:rtp length:sizeof(rtp)];
    [audio appendData:[NSData dataWithBytes:opusBytes length:sizeof(opusBytes)]];

    [[TGCall shared] probeAudioFramingWith:audio];

    XCTAssertTrue(TGWaitForCondition(^{
        return (BOOL)([TGCall shared].audioFramingProven);
    }, 2.0), @"the peer must acknowledge the probe");

    // A second probe is a no-op once the path is proven.
    [[TGCall shared] probeAudioFramingWith:audio];
    XCTAssertTrue([TGCall shared].audioFramingProven);
}

- (void)testReadPeerTagFromCandidateSetsTagAndRemoteTag {
    NSData *key = TGTestCallKey();
    XCTAssertTrue([self startEstablishedCallWithKey:key callId:45]);

    [TGCall shared].currentSenderTag = 0;
    NSString *candidate = @"candidate:1 1 udp 2130706431 reflector-1-88888.reflector 54321 typ relay";
    [[TGCall shared] readPeerTagFromCandidate:candidate];

    XCTAssertEqual([TGCall shared].currentSenderTag, (uint32_t)88888);
    XCTAssertEqual([TGCall shared].reflector.remoteTag, (uint32_t)88888);
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

@implementation TGCall (TestSupportState)

- (void)setState_test:(TGCallState)state {
    self.state = state;
}

@end
