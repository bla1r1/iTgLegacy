// TGCallMessagesTests.m — unit tests for TGCallMessages (packet framing).
//
// Covers seq bit helpers, ACK format, candidate serialise/parse round-trip,
// single-message and multi-message media packet parsing.
#import "TGTestRunner.h"
#import "TGCallMessages.h"

// ─── helpers ─────────────────────────────────────────────────────────────────

static void appendU32BE(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = {(uint8_t)(v>>24),(uint8_t)(v>>16),(uint8_t)(v>>8),(uint8_t)v};
    [d appendBytes:b length:4];
}

/// Build a minimal "single-message" plaintext (bit31 set in seq) that
/// parseMediaPacket will accept as one message of the given type.
static NSData *makeSingleMessagePacket(uint8_t type, NSData *body,
                                       uint32_t seq, BOOL wantsAck) {
    // seq has bit31 set (single-msg), bit30 set if wantsAck
    uint32_t markedSeq = [TGCallMessages markSeq:seq requiresAck:wantsAck];
    // Without bit31 set it would be treated as multi-message and expect a length prefix.
    // Force bit31 on.
    if (!wantsAck) markedSeq |= ((uint32_t)1 << 31);

    // Framing for parseMediaPacket of a single-message audio/video packet:
    // [type byte] [body bytes…]  — body runs to end of packet (seqIsSingleMessage=YES).
    NSMutableData *packet = [NSMutableData data];
    uint8_t typeByte = type;
    [packet appendBytes:&typeByte length:1];
    [packet appendData:body];
    return packet;
}

// ─────────────────────────────────────────────────────────────────────────────

@interface TGCallMessagesTests : XCTestCase
@end

@implementation TGCallMessagesTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - seq bit helpers

- (void)testMarkSeq_RequiresAck_SetsBit30 {
    uint32_t marked = [TGCallMessages markSeq:1 requiresAck:YES];
    XCTAssertTrue((marked >> 30) & 1, @"bit30 must be set when requiresAck=YES");
}

- (void)testMarkSeq_NoAck_SetsBit31 {
    uint32_t marked = [TGCallMessages markSeq:1 requiresAck:NO];
    XCTAssertTrue((marked >> 31) & 1, @"bit31 must be set when requiresAck=NO");
}

- (void)testMarkSeq_RequiresAck_DoesNotSetBit31 {
    uint32_t marked = [TGCallMessages markSeq:5 requiresAck:YES];
    XCTAssertFalse((marked >> 31) & 1,
                   @"a retransmittable message cannot also be the only one");
}

- (void)testSeqRequiresAck_True {
    uint32_t marked = [TGCallMessages markSeq:10 requiresAck:YES];
    XCTAssertTrue([TGCallMessages seqRequiresAck:marked]);
}

- (void)testSeqRequiresAck_False {
    uint32_t marked = [TGCallMessages markSeq:10 requiresAck:NO];
    XCTAssertFalse([TGCallMessages seqRequiresAck:marked]);
}

- (void)testSeqIsSingleMessage_True {
    uint32_t marked = [TGCallMessages markSeq:3 requiresAck:NO];
    XCTAssertTrue([TGCallMessages seqIsSingleMessage:marked]);
}

- (void)testSeqIsSingleMessage_False {
    uint32_t marked = [TGCallMessages markSeq:3 requiresAck:YES];
    XCTAssertFalse([TGCallMessages seqIsSingleMessage:marked]);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - ackForSeq

/// ackForSeq produces: 0xFE (empty) | seq32BE | 0xFF (ack).
- (void)testAckForSeq_Format {
    uint32_t seq = 0xDEADBEEF;
    NSData *ack = [TGCallMessages ackForSeq:seq];
    XCTAssertEqual(ack.length, 6u, @"ack packet must be exactly 6 bytes");

    const uint8_t *b = ack.bytes;
    XCTAssertEqual(b[0], (uint8_t)0xFE, @"first byte must be empty-marker 0xFE");
    uint32_t encoded = ((uint32_t)b[1]<<24)|((uint32_t)b[2]<<16)|
                       ((uint32_t)b[3]<<8)|(uint32_t)b[4];
    XCTAssertEqual(encoded, seq,         @"seq must be encoded big-endian");
    XCTAssertEqual(b[5], (uint8_t)0xFF, @"last byte must be ack-marker 0xFF");
}

- (void)testAckForSeq_ZeroSeq {
    NSData *ack = [TGCallMessages ackForSeq:0];
    XCTAssertEqual(ack.length, 6u);
    const uint8_t *b = ack.bytes;
    XCTAssertEqual(b[0], (uint8_t)0xFE);
    for (int i = 1; i < 5; i++) XCTAssertEqual(b[i], (uint8_t)0x00);
    XCTAssertEqual(b[5], (uint8_t)0xFF);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - messageWithType

- (void)testMessageWithType_FirstByteIsType {
    uint8_t body[] = { 0x01, 0x02, 0x03 };
    NSData *msg = [TGCallMessages messageWithType:0x05
                                            body:[NSData dataWithBytes:body length:3]];
    XCTAssertEqual(msg.length, 4u);
    const uint8_t *b = msg.bytes;
    XCTAssertEqual(b[0], (uint8_t)0x05);
    XCTAssertEqual(memcmp(b + 1, body, 3), 0);
}

- (void)testMessageWithType_EmptyBody {
    NSData *msg = [TGCallMessages messageWithType:0x04 body:[NSData data]];
    XCTAssertEqual(msg.length, 1u);
    XCTAssertEqual(((const uint8_t *)msg.bytes)[0], (uint8_t)0x04);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - candidates round-trip

- (void)testCandidatesBody_RoundTrip_Single {
    NSString *cand = @"candidate:1 1 udp 2130706431 reflector-1-12345.reflector 443 typ relay "
                      @"generation 0 ufrag abcd network-id 9 network-cost 50";
    NSString *ufrag = @"abcd";
    NSString *pwd   = @"verylongpassword1234567890";

    NSData *body = [TGCallMessages candidatesBody:@[cand] ufrag:ufrag pwd:pwd];
    XCTAssertNotNil(body);

    NSDictionary *parsed = [TGCallMessages parseCandidates:body];
    XCTAssertNotNil(parsed);
    XCTAssertEqualObjects(parsed[@"ufrag"], ufrag);
    XCTAssertEqualObjects(parsed[@"pwd"],   pwd);
    NSArray *parsedCandidates = parsed[@"candidates"];
    XCTAssertEqual(parsedCandidates.count, 1u);
    XCTAssertEqualObjects(parsedCandidates[0], cand);
}

- (void)testCandidatesBody_RoundTrip_Multiple {
    NSArray *cands = @[
        @"candidate:1 1 udp 100 reflector-1-111.reflector 443 typ relay generation 0 ufrag A",
        @"candidate:2 1 udp 200 reflector-2-222.reflector 443 typ relay generation 0 ufrag A",
    ];
    NSData *body = [TGCallMessages candidatesBody:cands ufrag:@"ABCD" pwd:@"pw123456789012345678901234"];
    NSDictionary *parsed = [TGCallMessages parseCandidates:body];
    XCTAssertEqual([parsed[@"candidates"] count], 2u);
}

- (void)testCandidatesBody_EmptyCandidates {
    NSData *body = [TGCallMessages candidatesBody:@[] ufrag:@"ufrg" pwd:@"pwd1234567890123456789012"];
    NSDictionary *parsed = [TGCallMessages parseCandidates:body];
    XCTAssertNotNil(parsed);
    XCTAssertEqual([parsed[@"candidates"] count], 0u);
    XCTAssertEqualObjects(parsed[@"ufrag"], @"ufrg");
}

- (void)testParseCandidates_NilOnEmpty {
    NSDictionary *parsed = [TGCallMessages parseCandidates:[NSData data]];
    XCTAssertNil(parsed);
}

- (void)testParseCandidates_NilOnTooShort {
    uint8_t byte = 5; // claims 5 candidates but body is empty
    NSDictionary *parsed = [TGCallMessages parseCandidates:
                             [NSData dataWithBytes:&byte length:1]];
    XCTAssertNil(parsed);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - parsePacket (signalling)

/// A bare candidates message: type byte + body, seq handed in from outside.
- (void)testParsePacket_SingleMessage {
    uint8_t body[] = { 0x05, 0xAA, 0xBB };   // candidates type + 2 payload bytes
    NSData *packet = [NSData dataWithBytes:body length:sizeof(body)];
    NSArray *msgs = [TGCallMessages parsePacket:packet seq:99];
    XCTAssertEqual(msgs.count, 1u);
    NSDictionary *m = msgs[0];
    XCTAssertEqual([m[@"type"] unsignedCharValue], (uint8_t)0x05);
    XCTAssertEqual([m[@"seq"] unsignedIntValue], (uint32_t)99);
    XCTAssertEqual([m[@"body"] length], 2u);
}

/// Two messages: empty (0xFE) + seq32 + real message.
- (void)testParsePacket_EmptyThenMessage {
    NSMutableData *packet = [NSMutableData data];
    uint8_t empty = 0xFE;
    [packet appendBytes:&empty length:1];
    appendU32BE(packet, 42); // next seq
    uint8_t type = 0x01;
    [packet appendBytes:&type length:1];
    uint8_t payload[] = { 0xCC, 0xDD };
    [packet appendBytes:payload length:2];

    NSArray *msgs = [TGCallMessages parsePacket:packet seq:1];
    XCTAssertEqual(msgs.count, 1u);
    XCTAssertEqual([msgs[0][@"seq"] unsignedIntValue], (uint32_t)42);
    XCTAssertEqual([msgs[0][@"type"] unsignedCharValue], (uint8_t)0x01);
}

/// An all-empty packet (no messages) returns an empty array.
- (void)testParsePacket_AllEmpty {
    NSMutableData *packet = [NSMutableData data];
    uint8_t empty = 0xFE;
    [packet appendBytes:&empty length:1];
    NSArray *msgs = [TGCallMessages parsePacket:packet seq:1];
    XCTAssertEqual(msgs.count, 0u);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - parseMediaPacket

/// MediaState (type 4) is a fixed-size 1-byte body.
- (void)testParseMediaPacket_MediaState {
    NSMutableData *packet = [NSMutableData data];
    uint8_t type = 4;
    [packet appendBytes:&type length:1];
    uint8_t state = 0x01; // audio active
    [packet appendBytes:&state length:1];

    uint32_t seq = [TGCallMessages markSeq:1 requiresAck:YES];
    NSArray *msgs = [TGCallMessages parseMediaPacket:packet seq:seq];
    XCTAssertEqual(msgs.count, 1u);
    XCTAssertEqual([msgs[0][@"type"] unsignedCharValue], (uint8_t)4);
    XCTAssertEqual([msgs[0][@"body"] length], 1u);
}

/// Audio data (type 5) in a single-message packet: body runs to end.
- (void)testParseMediaPacket_AudioData_SingleMessage {
    // An Opus frame placeholder
    uint8_t opusBytes[] = { 0xFC, 0x01, 0x02, 0x03, 0x04, 0x05 };
    NSData *body = [NSData dataWithBytes:opusBytes length:sizeof(opusBytes)];

    uint32_t seq = [TGCallMessages markSeq:2 requiresAck:NO]; // bit31 = single-msg
    NSData *packet = makeSingleMessagePacket(TGCallMessageAudioData, body, 2, NO);
    NSArray *msgs = [TGCallMessages parseMediaPacket:packet seq:seq];
    XCTAssertEqual(msgs.count, 1u);
    XCTAssertEqual([msgs[0][@"type"] unsignedCharValue], TGCallMessageAudioData);
    XCTAssertEqual([msgs[0][@"body"] length], body.length);
}

/// Multi-message packet: empty + videoParam(type 8) + mediaState(type 4).
/// This is exactly the shape of the opening media-state bundle.
- (void)testParseMediaPacket_MediaStateBundle {
    NSData *bundle = [TGCallMessages
        mediaStateBundleWithVideoSeq:[TGCallMessages markSeq:1 requiresAck:YES]
                            stateSeq:[TGCallMessages markSeq:2 requiresAck:YES]
                         audioActive:YES];
    uint32_t packetSeq = 0;  // bare counter, no flags
    NSArray *msgs = [TGCallMessages parseMediaPacket:bundle seq:packetSeq];

    // Expect type-8 (video parameters) and type-4 (media state).
    NSMutableSet *types = [NSMutableSet set];
    for (NSDictionary *m in msgs) [types addObject:m[@"type"]];
    XCTAssertTrue([types containsObject:@(8)],  @"video parameters missing");
    XCTAssertTrue([types containsObject:@(4)],  @"media state missing");
}

/// ACK (0xFF) inside a media packet is reported (the seq in front of it is what
/// was confirmed).
- (void)testParseMediaPacket_AckIsReported {
    NSMutableData *packet = [NSMutableData data];
    // empty marker
    uint8_t empty = 0xFE;
    [packet appendBytes:&empty length:1];
    appendU32BE(packet, 0x40000007);  // seq with bit30 set
    // ack marker
    uint8_t ack = 0xFF;
    [packet appendBytes:&ack length:1];

    NSArray *msgs = [TGCallMessages parseMediaPacket:packet seq:0];
    BOOL foundAck = NO;
    for (NSDictionary *m in msgs)
        if ([m[@"type"] unsignedCharValue] == 0xFF) { foundAck = YES; break; }
    XCTAssertTrue(foundAck, @"ACK message must be reported");
}

/// RemoteNetworkStatus (type 10) has a fixed 2-byte body.
- (void)testParseMediaPacket_RemoteNetworkStatus {
    NSMutableData *packet = [NSMutableData data];
    uint8_t type = 10;
    [packet appendBytes:&type length:1];
    uint8_t body[2] = {0, 0};
    [packet appendBytes:body length:2];

    uint32_t seq = [TGCallMessages markSeq:1 requiresAck:YES];
    NSArray *msgs = [TGCallMessages parseMediaPacket:packet seq:seq];
    XCTAssertEqual(msgs.count, 1u);
    XCTAssertEqual([msgs[0][@"type"] unsignedCharValue], (uint8_t)10);
    XCTAssertEqual([msgs[0][@"body"] length], 2u);
}

/// Unknown type terminates parsing cleanly without crashing.
- (void)testParseMediaPacket_UnknownTypeTerminates {
    NSMutableData *packet = [NSMutableData data];
    // First a known message (media state).
    uint8_t known = 4;
    [packet appendBytes:&known length:1];
    uint8_t state = 1;
    [packet appendBytes:&state length:1];
    // Next seq
    appendU32BE(packet, 2);
    // Unknown type (e.g. 0x7F)
    uint8_t unknown = 0x7F;
    [packet appendBytes:&unknown length:1];

    NSArray *msgs = [TGCallMessages parseMediaPacket:packet seq:1];
    // At least the first (media state) must be returned.
    XCTAssertGreaterThanOrEqual(msgs.count, 1u);
    XCTAssertEqual([msgs[0][@"type"] unsignedCharValue], (uint8_t)4);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - RTCP receiver report

- (void)testRTCPReceiverReport_Length {
    NSData *rr = [TGCallMessages rtcpReceiverReportWithOurSSRC:2
                                                      peerSSRC:1
                                                   highestSeq:100];
    XCTAssertEqual(rr.length, 32u, @"RTCP RR must be 32 bytes");
}

- (void)testRTCPReceiverReport_Header {
    NSData *rr = [TGCallMessages rtcpReceiverReportWithOurSSRC:2 peerSSRC:1 highestSeq:0];
    const uint8_t *b = rr.bytes;
    // V=2,P=0,RC=1 → 0x81; PT=201
    XCTAssertEqual(b[0], (uint8_t)0x81);
    XCTAssertEqual(b[1], (uint8_t)201);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - remoteNetworkStatusBody

- (void)testRemoteNetworkStatusBody_TwoBytes {
    NSData *body = [TGCallMessages remoteNetworkStatusBody];
    XCTAssertEqual(body.length, 2u);
}

@end
