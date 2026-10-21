// TGCallIceTests.m — unit tests for TGCallIce (ICE connectivity checks).
//
// All tests use a custom `transport` block so no real UDP socket is opened.
// This lets us capture outgoing STUN packets and feed incoming ones
// synchronously inside the test process.
#import "TGTestRunner.h"
#import "TGCallIce.h"
#import "TGCallStun.h"
#import "TGCallTestHelpers.h"

@interface TGCallIceTests : XCTestCase
@end

@implementation TGCallIceTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - transport block

/// When a custom `transport` block is set, start does NOT open a socket
/// but still schedules the check timer.  Verifying via sendChecks output.
- (void)testTransportBlockCalledForChecks {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"AAAA";
    ice.localPwd   = @"localpwd123456789012345";
    ice.peerUfrag  = @"BBBB";
    ice.peerPwd    = @"peerpwd123456789012345";

    __block NSData *sent = nil;
    ice.transport = ^(NSData *pkt){ sent = pkt; };

    [ice start];

    // Pump run loop briefly so the repeating timer fires once.
    BOOL fired = TGWaitForCondition(^{ return (BOOL)(sent != nil); }, 1.0);
    [ice stop];

    XCTAssertTrue(fired, @"transport block must be called within 1 s");
    XCTAssertNotNil(sent, @"a packet must have been sent");
}

/// The sent packet must be a valid STUN binding request.
- (void)testSentCheckIsStunBindingRequest {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"CCCC";
    ice.localPwd   = @"localpwd123456789012345";
    ice.peerUfrag  = @"DDDD";
    ice.peerPwd    = @"peerpwd123456789012345";

    __block NSData *sent = nil;
    ice.transport = ^(NSData *pkt){ if (!sent) sent = pkt; };
    [ice start];
    TGWaitForCondition(^{ return (BOOL)(sent != nil); }, 1.0);
    [ice stop];

    XCTAssertEqual([TGCallStun messageTypeOf:sent], 0x0001,
                   @"sent packet must be STUN binding request (0x0001)");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - handleRelayedPacket — incoming request

/// When an incoming STUN binding request arrives over the relay,
/// the ICE agent must immediately call the transport block with a
/// binding success response (0x0101).
- (void)testHandleRelayedPacket_RequestTriggersResponse {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"EEEE";
    ice.localPwd   = @"localpwd123456789012345";
    ice.peerUfrag  = @"FFFF";
    ice.peerPwd    = @"peerpwd123456789012345";

    NSMutableArray *sent = [NSMutableArray array];
    ice.transport = ^(NSData *pkt){ [sent addObject:pkt]; };
    [ice start];

    // Build a synthetic STUN binding request from the "peer".
    NSData *req = [TGCallStun bindingRequestWithUsername:@"EEEE:FFFF"
                                               password:ice.peerPwd
                                            tieBreaker:42
                                           useCandidate:YES];
    [ice handleRelayedPacket:req];
    [ice stop];

    // One of the sent packets must be a binding response.
    BOOL foundResponse = NO;
    for (NSData *pkt in sent)
        if ([TGCallStun messageTypeOf:pkt] == 0x0101) { foundResponse = YES; break; }
    XCTAssertTrue(foundResponse,
                  @"must send a binding success response to an incoming check");
}

/// The same relayed request must also trigger onConnected (connected over relay).
- (void)testHandleRelayedPacket_RequestFiresOnConnected {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"GGGG";
    ice.localPwd   = @"localpwd123456789012345";
    ice.peerUfrag  = @"HHHH";
    ice.peerPwd    = @"peerpwd123456789012345";

    __block BOOL connected = NO;
    ice.onConnected = ^(NSString *addr, uint16_t port){ connected = YES; };
    ice.transport   = ^(NSData *pkt){};
    [ice start];

    NSData *req = [TGCallStun bindingRequestWithUsername:@"GGGG:HHHH"
                                               password:ice.peerPwd
                                            tieBreaker:1
                                           useCandidate:YES];
    [ice handleRelayedPacket:req];
    [ice stop];

    XCTAssertTrue(connected, @"onConnected must fire on incoming relayed request");
}

/// A binding SUCCESS response (0x0101) over the relay also triggers onConnected.
- (void)testHandleRelayedPacket_SuccessResponseFiresOnConnected {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"IIII";
    ice.localPwd   = @"localpwd123456789012345";
    ice.peerUfrag  = @"JJJJ";
    ice.peerPwd    = @"peerpwd123456789012345";

    __block BOOL connected = NO;
    ice.onConnected = ^(NSString *addr, uint16_t port){ connected = YES; };
    ice.transport   = ^(NSData *pkt){};
    [ice start];

    // Build a fake request just to have a valid transaction ID.
    NSData *fakeReq = [TGCallStun bindingRequestWithUsername:@"IIII:JJJJ"
                                                   password:ice.peerPwd
                                                tieBreaker:0
                                               useCandidate:NO];
    // Build a success response from that request.
    NSData *resp = [TGCallStun bindingResponseTo:fakeReq
                                       password:ice.localPwd
                                    fromAddress:[NSData data]];
    [ice handleRelayedPacket:resp];
    [ice stop];

    XCTAssertTrue(connected,
                  @"onConnected must fire on receiving a STUN success response");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - handleRelayedPacket — non-STUN data

/// A non-STUN packet (media) must be forwarded to onMedia.
- (void)testHandleRelayedPacket_MediaForwardedToCallback {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"KKKK";
    ice.localPwd   = @"localpwd123456789012345";
    ice.transport  = ^(NSData *pkt){};

    __block NSData *receivedMedia = nil;
    ice.onMedia = ^(NSData *pkt){ receivedMedia = pkt; };
    [ice start];

    // A non-STUN packet: first two bits non-zero → messageTypeOf returns -1.
    uint8_t raw[] = { 0xFF, 0xAA, 0xBB, 0xCC, 0xDD };
    NSData *media = [NSData dataWithBytes:raw length:sizeof(raw)];
    [ice handleRelayedPacket:media];
    [ice stop];

    XCTAssertNotNil(receivedMedia, @"non-STUN packet must reach onMedia callback");
    XCTAssertEqualObjects(receivedMedia, media);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - addPeerCandidate

/// A well-formed relay candidate is parsed and queued without crashing.
- (void)testAddPeerCandidate_ValidRelayCandidate {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.transport = ^(NSData *pkt){};
    [ice start];
    // Should not crash; actual routing happens via transport or direct socket.
    [ice addPeerCandidate:@"candidate:1 1 udp 2130706431 reflector-1-99999.reflector "
                           @"443 typ relay generation 0 ufrag ABCD network-id 9 network-cost 50"];
    [ice stop];
}

/// An IPv6 candidate is silently skipped (device has no route for it).
- (void)testAddPeerCandidate_IPv6IsSkipped {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.transport = ^(NSData *pkt){};
    [ice start];
    // Must not crash and must not add any target.
    [ice addPeerCandidate:@"candidate:1 1 udp 100 2001:db8::1 12345 typ host generation 0 ufrag AB"];
    [ice stop];
}

/// A candidate with fewer than 6 space-separated parts is silently skipped.
- (void)testAddPeerCandidate_TooFewPartsSilentlyIgnored {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.transport = ^(NSData *pkt){};
    [ice start];
    [ice addPeerCandidate:@"bad data"];
    [ice stop];
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - stop / cleanup

/// Calling stop twice must not crash.
- (void)testStopIdempotent {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.transport = ^(NSData *pkt){};
    [ice start];
    [ice stop];
    XCTAssertNoThrow([ice stop]);
}

@end
