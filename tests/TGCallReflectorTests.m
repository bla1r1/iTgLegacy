// TGCallReflectorTests.m — unit tests for TGCallReflector protocol framing.
//
// Tests cover:
//   • The 40-byte ping packet format (16-byte tag, 0xFF padding, 0xFE marker,
//     zero-padding, big-endian 64-bit marker value 123).
//   • The data-packet framing: destTag(16) | senderTag(4) | size(4) | payload.
//   • localTag uniqueness across instances.
//   • The reflector refuses to start if peerTag is shorter than 16 bytes.
#import "TGTestRunner.h"
#import "TGCallReflector.h"
#import "TGCallTestHelpers.h"

@interface TGCallReflectorTests : XCTestCase
@end

@implementation TGCallReflectorTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - creation

- (void)testLocalTagIsNonZero {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:443
                                                       peerTag:tag];
    XCTAssertNotEqual(r.localTag, (uint32_t)0,
                      @"localTag must be random and not start as zero");
}

- (void)testLocalTagsDifferAcrossInstances {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *a = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:443 peerTag:tag];
    TGCallReflector *b = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:443 peerTag:tag];
    // Two random 32-bit values collide with probability 2^-32 ≈ 0, safe to assert.
    XCTAssertNotEqual(a.localTag, b.localTag,
                      @"two reflectors should have distinct local tags");
}

- (void)testStartFailsWithShortPeerTag {
    // peerTag shorter than 16 bytes → -start must return NO.
    NSData *shortTag = [NSData dataWithBytes:"\xAA\xBB" length:2];
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:443
                                                       peerTag:shortTag];
    BOOL ok = [r start];
    XCTAssertFalse(ok, @"must refuse to start with undersized peerTag");
    [r stop];
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - data framing (sendPayload:toTag:)
//
// The live loopback tests below capture the actual datagrams. The tests here
// cover the framings that must not crash: sending before start, sending with
// no known peer tag, and the port accessor.

- (void)testPortMatchesInit {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:12345 peerTag:tag];
    XCTAssertEqual(r.port, (uint16_t)12345);
}

- (void)testSendPayloadToTagDoesNotCrashBeforeStart {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:9999 peerTag:tag];
    // socketHandle is -1 before start; sending should be a no-op, not a crash.
    XCTAssertNoThrow([r sendPayload:[NSData dataWithBytes:@"\x01\x02" length:2]
                              toTag:r.localTag]);
}

- (void)testSendPayloadDoesNotCrashBeforeStart {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:9999 peerTag:tag];
    // remoteTag not set → should log and return, not crash.
    XCTAssertNoThrow([r sendPayload:[NSData dataWithBytes:"\xFF" length:1]]);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - stop idempotency

- (void)testStopBeforeStartDoesNotCrash {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:0 peerTag:tag];
    XCTAssertNoThrow([r stop]);
}

- (void)testStopTwiceDoesNotCrash {
    NSData *tag = TGTestPeerTag();
    TGCallReflector *r = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                          port:0 peerTag:tag];
    [r stop];
    XCTAssertNoThrow([r stop]);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - live loopback
//
// The reflector talks UDP only. These tests point it at a loopback socket
// standing in for the Telegram server, then assert the datagrams byte by byte
// and feed a relayed frame back to exercise readLoop and onPacket.

static uint32_t TGReflectorRead32BE(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8)  |  (uint32_t)bytes[3];
}

static uint64_t TGReflectorRead64BE(const uint8_t *bytes) {
    uint64_t value = 0;
    for (int i = 0; i < 8; i++)
        value = (value << 8) | bytes[i];
    return value;
}

/// A server socket plus a started reflector pointed at it. The ping that
/// -start sends immediately is consumed, so the test starts from a quiet queue.
- (TGCallReflector *)reflectorAgainstServer:(int)server
                                      port:(uint16_t)serverPort
                                   peerTag:(NSData *)peerTag {
    TGCallReflector *reflector = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                                  port:serverPort
                                                               peerTag:peerTag];
    XCTAssertTrue([reflector start]);
    NSData *ping = TGTestRecvFrom(server, NULL, 2.0);
    XCTAssertNotNil(ping, @"reflector must ping the server on start");
    return reflector;
}

- (void)testPingPacketFormat {
    uint16_t serverPort = 0;
    int server = TGTestUDPSocket(&serverPort);
    XCTAssertGreaterThanOrEqual(server, 0);

    NSData *peerTag = TGTestPeerTag();
    TGCallReflector *reflector = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                                  port:serverPort
                                                               peerTag:peerTag];
    XCTAssertTrue([reflector start]);

    NSData *ping = TGTestRecvFrom(server, NULL, 2.0);
    XCTAssertNotNil(ping);
    XCTAssertEqual(ping.length, (NSUInteger)40);

    const uint8_t *bytes = (const uint8_t *)ping.bytes;
    XCTAssertEqual(memcmp(bytes, peerTag.bytes, 12), 0,
                   @"the first 12 bytes name the call");

    uint32_t tag = 0;
    memcpy(&tag, bytes + 12, 4);
    XCTAssertEqual(tag, reflector.localTag, @"the next 4 bytes name our side");

    for (int i = 16; i < 28; i++)
        XCTAssertEqual(bytes[i], (uint8_t)0xFF);
    XCTAssertEqual(bytes[28], (uint8_t)0xFE, @"0xFE marks a ping");
    for (int i = 29; i < 32; i++)
        XCTAssertEqual(bytes[i], (uint8_t)0xFF);

    XCTAssertEqual(TGReflectorRead64BE(bytes + 32), (uint64_t)123);

    [reflector stop];
    close(server);
}

- (void)testSendPayloadToTagFraming {
    uint16_t serverPort = 0;
    int server = TGTestUDPSocket(&serverPort);
    XCTAssertGreaterThanOrEqual(server, 0);

    NSData *peerTag = TGTestPeerTag();
    TGCallReflector *reflector = [self reflectorAgainstServer:server
                                                         port:serverPort
                                                      peerTag:peerTag];

    uint32_t remoteTag = 0x11223344;
    uint8_t payloadBytes[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0x01 };
    NSData *payload = [NSData dataWithBytes:payloadBytes length:sizeof(payloadBytes)];

    [reflector sendPayload:payload toTag:remoteTag];

    NSData *packet = TGTestRecvNonPing(server, NULL, 2.0);
    XCTAssertNotNil(packet);

    // 16-byte destination tag + sender tag 4 + size 4 + 5 bytes, padded to 32.
    XCTAssertEqual(packet.length, (NSUInteger)32);
    const uint8_t *bytes = (const uint8_t *)packet.bytes;

    XCTAssertEqual(memcmp(bytes, peerTag.bytes, 12), 0,
                   @"destination tag keeps the call's 12-byte prefix");
    uint32_t destination = 0;
    memcpy(&destination, bytes + 12, 4);
    XCTAssertEqual(destination, remoteTag, @"last 4 bytes select the peer side");

    uint32_t sender = 0;
    memcpy(&sender, bytes + 16, 4);
    XCTAssertEqual(sender, reflector.localTag, @"our four bytes follow");

    XCTAssertEqual(TGReflectorRead32BE(bytes + 20), (uint32_t)payload.length,
                   @"the size field excludes padding");
    XCTAssertEqual(memcmp(bytes + 24, payload.bytes, payload.length), 0);
    for (NSUInteger i = 24 + payload.length; i < packet.length; i++)
        XCTAssertEqual(bytes[i], (uint8_t)0, @"payload is padded to four bytes");

    [reflector stop];
    close(server);
}

/// A relayed packet must reach onPacket, and the sender tag inside it must
/// become the destination of subsequent bare sendPayload: calls.
- (void)testOnPacketCalledOnLoopbackDelivery {
    uint16_t serverPort = 0;
    int server = TGTestUDPSocket(&serverPort);
    XCTAssertGreaterThanOrEqual(server, 0);

    NSData *peerTag = TGTestPeerTag();
    TGCallReflector *reflector = [[TGCallReflector alloc] initWithHost:@"127.0.0.1"
                                                                  port:serverPort
                                                               peerTag:peerTag];

    __block NSData *received = nil;
    reflector.onPacket = ^(NSData *packet){ received = packet; };

    XCTAssertTrue([reflector start]);

    // The ping's source address is the reflector's own socket.
    struct sockaddr_in reflectorAddress;
    NSData *ping = TGTestRecvFrom(server, &reflectorAddress, 2.0);
    XCTAssertNotNil(ping);

    uint32_t senderTag = 0x0BADF00D;
    uint8_t frameBytes[28] = {0};
    memset(frameBytes, 0xAA, 16);              // destination tag, not inspected
    memcpy(frameBytes + 16, &senderTag, 4);    // sender tag
    uint32_t size = 4;
    frameBytes[20] = (uint8_t)(size >> 24);
    frameBytes[21] = (uint8_t)(size >> 16);
    frameBytes[22] = (uint8_t)(size >> 8);
    frameBytes[23] = (uint8_t)size;
    uint8_t body[] = { 0x01, 0x02, 0x03, 0x04 };
    memcpy(frameBytes + 24, body, sizeof(body));
    NSData *frame = [NSData dataWithBytes:frameBytes length:sizeof(frameBytes)];

    ssize_t sent = sendto(server, frame.bytes, frame.length, 0,
                          (struct sockaddr *)&reflectorAddress, sizeof(reflectorAddress));
    XCTAssertEqual(sent, (ssize_t)frame.length);

    XCTAssertTrue(TGWaitForCondition(^{ return (BOOL)(received != nil); }, 2.0),
                  @"readLoop must deliver the datagram to onPacket");
    XCTAssertEqualObjects(received, frame, @"onPacket receives the packet whole");

    // sendPayload: (no tag) answers whoever the frame came from.
    uint8_t replyBytes[] = { 0x05, 0x06 };
    [reflector sendPayload:[NSData dataWithBytes:replyBytes length:sizeof(replyBytes)]];

    NSData *reply = TGTestRecvNonPing(server, NULL, 2.0);
    XCTAssertNotNil(reply);
    XCTAssertGreaterThanOrEqual(reply.length, (NSUInteger)24);
    const uint8_t *replyBytesPtr = (const uint8_t *)reply.bytes;
    XCTAssertEqual(memcmp(replyBytesPtr, peerTag.bytes, 12), 0);
    uint32_t destination = 0;
    memcpy(&destination, replyBytesPtr + 12, 4);
    XCTAssertEqual(destination, senderTag,
                   @"the observed sender tag is the address to answer");

    [reflector stop];
    close(server);
}

@end
