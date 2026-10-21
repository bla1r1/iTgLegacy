// TGCallIceTests.m — unit tests for TGCallIce (ICE connectivity checks).
//
// Most tests use a custom `transport` block so packets can be captured and
// fed synchronously. The socket section at the bottom does the opposite: it
// opens real loopback UDP sockets and asserts what TGCallIce sends and how it
// reacts to what arrives, because that path is what a call actually uses.
#import "TGTestRunner.h"
#import "TGCallIce.h"
#import "TGCallStun.h"
#import "TGCallTestHelpers.h"

// Needed to discover the ephemeral port of the socket opened by -start.
@interface TGCallIce (TestSupport)
- (int)socketHandle;
@end

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

/// A relay candidate names the peer by reflector hostname, not by IP. It
/// cannot be turned into a sockaddr, so it must not become peerAddress.
- (void)testAddPeerCandidate_ReflectorHostnameIsIgnored {
    TGCallIce *ice = [[TGCallIce alloc] init];
    [ice addPeerCandidate:@"candidate:1 1 udp 2130706431 reflector-1-99999.reflector "
                           @"443 typ relay generation 0 ufrag ABCD network-id 9 network-cost 50"];
    XCTAssertNil(ice.peerAddress,
                 @"a hostname is not an address this agent can send to");
}

/// A host candidate with a real IPv4 address is recorded as peerAddress,
/// which is what XOR-MAPPED-ADDRESS quotes back to the peer.
- (void)testAddPeerCandidate_IPv4BecomesPeerAddress {
    TGCallIce *ice = [[TGCallIce alloc] init];
    [ice addPeerCandidate:@"candidate:1 1 udp 100 192.0.2.10 5000 typ host generation 0 ufrag AB"];

    XCTAssertNotNil(ice.peerAddress);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    [ice.peerAddress getBytes:&addr length:sizeof(addr)];
    XCTAssertEqual(addr.sin_family, AF_INET);
    XCTAssertEqual(ntohs(addr.sin_port), (uint16_t)5000);

    char text[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &addr.sin_addr, text, sizeof(text));
    XCTAssertTrue([[NSString stringWithUTF8String:text] isEqualToString:@"192.0.2.10"]);
}

/// An IPv6 candidate is silently skipped (device has no route for it).
- (void)testAddPeerCandidate_IPv6IsSkipped {
    TGCallIce *ice = [[TGCallIce alloc] init];
    [ice addPeerCandidate:@"candidate:1 1 udp 100 2001:db8::1 12345 typ host generation 0 ufrag AB"];
    XCTAssertNil(ice.peerAddress, @"IPv6 must not become a target");
}

/// A candidate with fewer than 6 space-separated parts is silently skipped.
- (void)testAddPeerCandidate_TooFewPartsSilentlyIgnored {
    TGCallIce *ice = [[TGCallIce alloc] init];
    [ice addPeerCandidate:@"bad data"];
    XCTAssertNil(ice.peerAddress);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - real socket path
//
// These tests do not set `transport`, so TGCallIce opens its own UDP socket
// and uses readLoop. They cover the path a real call takes: sendto of checks,
// recvfrom of checks and responses, and media delivery.

- (void)testStartWithoutTransportOpensSocket {
    TGCallIce *ice = [[TGCallIce alloc] init];

    XCTAssertTrue([ice start]);
    int handle = [ice socketHandle];
    XCTAssertGreaterThanOrEqual(handle, 0);

    struct sockaddr_in bound;
    socklen_t len = sizeof(bound);
    XCTAssertEqual(getsockname(handle, (struct sockaddr *)&bound, &len), 0);
    XCTAssertEqual(bound.sin_family, AF_INET);
    XCTAssertGreaterThan(ntohs(bound.sin_port), 0);

    [ice stop];
    XCTAssertEqual([ice socketHandle], -1, @"stop must close the socket");
}

/// A peer's binding request arriving on the socket must be answered with a
/// binding success response and must mark the connection as usable.
- (void)testSocketAnswersBindingRequest {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"LOCAL";
    ice.localPwd   = @"localpwd123456789012345";
    XCTAssertTrue([ice start]);

    __block NSString *connected = nil;
    ice.onConnected = ^(NSString *address, uint16_t port){
        connected = address ?: @"relay";
    };

    struct sockaddr_in bound;
    socklen_t len = sizeof(bound);
    XCTAssertEqual(getsockname([ice socketHandle], (struct sockaddr *)&bound, &len), 0);

    int peer = TGTestUDPSocket(NULL);
    XCTAssertGreaterThanOrEqual(peer, 0);

    NSData *request = [TGCallStun bindingRequestWithUsername:@"LOCAL:PEER"
                                                    password:ice.localPwd
                                                   tieBreaker:0x1234567890ULL
                                                  useCandidate:YES];
    XCTAssertTrue(TGTestSendTo(peer, request, ntohs(bound.sin_port)));

    NSData *response = TGTestRecvFrom(peer, NULL, 2.0);
    XCTAssertNotNil(response, @"the socket must answer a binding request");
    XCTAssertEqual([TGCallStun messageTypeOf:response], 0x0101);

    XCTAssertTrue(TGWaitForCondition(^{ return (BOOL)(connected != nil); }, 2.0),
                  @"answering a check must call onConnected");

    [ice stop];
    close(peer);
}

/// With no transport block, the periodic check must be written to the socket
/// and addressed to the candidate added over signalling.
- (void)testSocketSendsCheckToPeerCandidate {
    TGCallIce *ice = [[TGCallIce alloc] init];
    ice.localUfrag = @"LOCAL";
    ice.localPwd   = @"localpwd123456789012345";
    ice.peerUfrag  = @"PEER";
    ice.peerPwd    = @"peerpwd123456789012345";

    uint16_t peerPort = 0;
    int peer = TGTestUDPSocket(&peerPort);
    XCTAssertGreaterThanOrEqual(peer, 0);

    NSString *candidate = [NSString stringWithFormat:
        @"candidate:1 1 udp 100 127.0.0.1 %u typ host generation 0 ufrag PEER",
        (unsigned)peerPort];
    [ice addPeerCandidate:candidate];
    XCTAssertNotNil(ice.peerAddress, @"the IPv4 candidate must be recorded");

    __block BOOL connected = NO;
    ice.onConnected = ^(NSString *address, uint16_t port){ connected = YES; };

    XCTAssertTrue([ice start]);

    struct sockaddr_in sender;
    NSData *check = TGTestRecvFrom(peer, &sender, 2.0);
    XCTAssertNotNil(check, @"the check must arrive on the peer socket");
    XCTAssertEqual([TGCallStun messageTypeOf:check], 0x0001);

    // Answer the check from the peer's socket. The response goes back to the
    // address the check came from, which is TGCallIce's own socket.
    NSData *iceAddress = [NSData dataWithBytes:&sender length:sizeof(sender)];
    NSData *response = [TGCallStun bindingResponseTo:check
                                            password:ice.localPwd
                                         fromAddress:iceAddress];
    XCTAssertNotNil(response);
    XCTAssertTrue(TGTestSendTo(peer, response, ntohs(sender.sin_port)));

    XCTAssertTrue(TGWaitForCondition(^{ return connected; }, 2.0),
                  @"a success response must mark the pair connected");

    [ice stop];
    close(peer);
}

/// Non-STUN traffic on the socket is media and must reach onMedia unchanged.
- (void)testSocketDeliversMediaToOnMedia {
    TGCallIce *ice = [[TGCallIce alloc] init];
    XCTAssertTrue([ice start]);

    __block NSData *media = nil;
    ice.onMedia = ^(NSData *packet){ media = packet; };

    struct sockaddr_in bound;
    socklen_t len = sizeof(bound);
    XCTAssertEqual(getsockname([ice socketHandle], (struct sockaddr *)&bound, &len), 0);

    int peer = TGTestUDPSocket(NULL);
    XCTAssertGreaterThanOrEqual(peer, 0);

    uint8_t bytes[] = { 0xDE, 0xAD, 0xBE, 0xEF };
    NSData *payload = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    XCTAssertTrue(TGTestSendTo(peer, payload, ntohs(bound.sin_port)));

    XCTAssertTrue(TGWaitForCondition(^{ return (BOOL)(media != nil); }, 2.0));
    XCTAssertEqualObjects(media, payload);

    [ice stop];
    close(peer);
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
