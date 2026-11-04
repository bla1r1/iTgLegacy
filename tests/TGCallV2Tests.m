// TGCallV2Tests.m — tgcalls 9.0.0 signalling JSON, V2 framing and SRTP.
//
// The shapes here are the ones in docs/calls_v9_spec.md section 2 and 3; the
// bench is the other half of the proof.
#import "TGTestRunner.h"
#import "TGCallSrtp.h"
#import "TGCallV2Signaling.h"
#import "TGCallDtls.h"

static uint32_t readU32(const uint8_t *b) {
    return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
           ((uint32_t)b[2] << 8) | b[3];
}

/// Strip the 0x7F + 4-byte length envelope and return the JSON object.
static NSDictionary *jsonOfMessage(NSData *message) {
    if (message.length < 5)
        return nil;
    const uint8_t *bytes = message.bytes;
    if (bytes[0] != 0x7F)
        return nil;
    uint32_t length = readU32(bytes + 1);
    if (5 + length > message.length)
        return nil;
    NSData *payload = [message subdataWithRange:NSMakeRange(5, length)];
    return [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
}

static void makeRtp(uint8_t *packet, uint16_t seq, uint32_t ssrc,
                    const uint8_t *payload, size_t payloadLength) {
    packet[0] = 0x80;
    packet[1] = 111;
    packet[2] = (uint8_t)(seq >> 8);
    packet[3] = (uint8_t)seq;
    packet[4] = 0;
    packet[5] = 0;
    packet[6] = 0;
    packet[7] = 0;
    packet[8] = (uint8_t)(ssrc >> 24);
    packet[9] = (uint8_t)(ssrc >> 16);
    packet[10] = (uint8_t)(ssrc >> 8);
    packet[11] = (uint8_t)ssrc;
    memcpy(packet + 12, payload, payloadLength);
}

@interface TGCallV2Tests : XCTestCase
@end

@implementation TGCallV2Tests

#pragma mark - JSON messages

- (void)testInitialSetupShape {
    NSData *message = [TGCallV2Signaling initialSetupWithUfrag:@"UX7o"
                                                          pwd:@"Ab3dEf6hIj9lMn2pQr5sTu7v"
                                                  fingerprint:@"8D:F5:D2:CF"
                                                        setup:@"actpass"];
    NSDictionary *json = jsonOfMessage(message);
    XCTAssertNotNil(json);
    XCTAssertEqualObjects(json[@"@type"], @"InitialSetup");
    XCTAssertEqualObjects(json[@"ufrag"], @"UX7o");
    XCTAssertEqualObjects(json[@"pwd"], @"Ab3dEf6hIj9lMn2pQr5sTu7v");
    XCTAssertEqualObjects(json[@"renomination"], @YES);
    NSArray *fingerprints = json[@"fingerprints"];
    XCTAssertTrue([fingerprints isKindOfClass:[NSArray class]], @"fingerprints is an array");
    XCTAssertEqual(fingerprints.count, (NSUInteger)1);
    NSDictionary *first = fingerprints[0];
    XCTAssertEqualObjects(first[@"hash"], @"sha-256");
    XCTAssertEqualObjects(first[@"setup"], @"actpass");
    XCTAssertEqualObjects(first[@"fingerprint"], @"8D:F5:D2:CF");
}

- (void)testOfferShapeUsesStringsForSsrcAndExchangeId {
    NSData *message = [TGCallV2Signaling offerWithExchangeId:@"246813579"
                                                        ssrc:305419896];
    NSDictionary *json = jsonOfMessage(message);
    XCTAssertNotNil(json);
    XCTAssertEqualObjects(json[@"@type"], @"NegotiateChannels");
    XCTAssertEqualObjects(json[@"exchangeId"], @"246813579");
    XCTAssertTrue([json[@"exchangeId"] isKindOfClass:[NSString class]],
                  @"exchangeId is a decimal string on the wire");
    NSArray *contents = json[@"contents"];
    XCTAssertEqual(contents.count, (NSUInteger)1);
    NSDictionary *content = contents[0];
    XCTAssertEqualObjects(content[@"type"], @"audio");
    XCTAssertEqualObjects(content[@"ssrc"], @"305419896");
    XCTAssertTrue([content[@"ssrc"] isKindOfClass:[NSString class]],
                  @"ssrc is a decimal string on the wire");
    NSDictionary *payload = [content[@"payloadTypes"] firstObject];
    XCTAssertEqualObjects(payload[@"name"], @"opus");
    XCTAssertEqualObjects(payload[@"id"], @111);
    XCTAssertEqualObjects(payload[@"clockrate"], @48000);
    XCTAssertEqualObjects(payload[@"channels"], @2);
    XCTAssertNil(content[@"rtpExtensions"], @"we deliberately do not offer transport-cc");
}

- (void)testAnswerEchoesPeerSsrcAndExchangeId {
    NSData *message = [TGCallV2Signaling answerWithExchangeId:@"13579"
                                                        ssrc:120974494];
    NSDictionary *json = jsonOfMessage(message);
    XCTAssertEqualObjects(json[@"exchangeId"], @"13579");
    NSDictionary *content = [json[@"contents"] firstObject];
    XCTAssertEqualObjects(content[@"ssrc"], @"120974494");
}

- (void)testCandidatesShape {
    NSData *message = [TGCallV2Signaling candidatesWithStrings:
        @[@"candidate:3376150301 1 udp 41877760 reflector-1-231911121.reflector 598 typ relay generation 0 ufrag UX7o"]];
    NSDictionary *json = jsonOfMessage(message);
    XCTAssertEqualObjects(json[@"@type"], @"Candidates");
    NSDictionary *item = [json[@"candidates"] firstObject];
    XCTAssertTrue([item[@"sdpString"] hasPrefix:@"candidate:3376150301 1 udp 41877760"]);
}

- (void)testAckPacketIsEmptyMessageThenAck {
    NSData *ack = [TGCallV2Signaling ackForSeq:0x40000005];
    const uint8_t *bytes = ack.bytes;
    XCTAssertEqual(ack.length, (NSUInteger)6);
    XCTAssertEqual(bytes[0], 0xFE);
    XCTAssertEqual(readU32(bytes + 1), 0x40000005u);
    XCTAssertEqual(bytes[5], 0xFF);
}

- (void)testParsePlaintextReadsMessageAndTrailingAck {
    NSData *message = [TGCallV2Signaling offerWithExchangeId:@"7" ssrc:1];
    NSMutableData *plaintext = [NSMutableData dataWithData:message];
    uint8_t seq[4] = {0x40, 0x00, 0x00, 0x09};
    [plaintext appendBytes:seq length:4];
    uint8_t ack = 0xFF;
    [plaintext appendBytes:&ack length:1];

    TGV2Slice slices[4];
    size_t count = TGV2ParsePlaintext(plaintext.bytes, plaintext.length,
                                      0x40000008, slices, 4);
    XCTAssertEqual(count, (size_t)2);
    XCTAssertEqual(slices[0].type, 0x7F);
    XCTAssertEqual(slices[0].seq, 0x40000008u);
    XCTAssertEqual(slices[1].type, 0xFF);
    XCTAssertEqual(slices[1].seq, 0x40000009u);
}

#pragma mark - SRTP

- (void)testExporterSplitGivesClientFirstHalf {
    uint8_t exporter[60];
    for (int i = 0; i < 60; i++)
        exporter[i] = (uint8_t)i;
    uint8_t sendKey[16], sendSalt[14], receiveKey[16], receiveSalt[14];

    // WebRTC layout: client key, server key, client salt, server salt.
    TGSrtpSplitExporter(exporter, 1, sendKey, sendSalt, receiveKey, receiveSalt);
    for (int i = 0; i < 16; i++)
        XCTAssertEqual(sendKey[i], (uint8_t)i);
    for (int i = 0; i < 14; i++)
        XCTAssertEqual(sendSalt[i], (uint8_t)(32 + i));
    for (int i = 0; i < 16; i++)
        XCTAssertEqual(receiveKey[i], (uint8_t)(16 + i));
    for (int i = 0; i < 14; i++)
        XCTAssertEqual(receiveSalt[i], (uint8_t)(46 + i));

    // The server writes what the client reads, and the other way round.
    uint8_t serverSendKey[16], serverSendSalt[14], serverRecvKey[16], serverRecvSalt[14];
    TGSrtpSplitExporter(exporter, 0, serverSendKey, serverSendSalt,
                        serverRecvKey, serverRecvSalt);
    for (int i = 0; i < 16; i++)
        XCTAssertEqual(serverSendKey[i], receiveKey[i]);
    for (int i = 0; i < 14; i++)
        XCTAssertEqual(serverSendSalt[i], receiveSalt[i]);
    for (int i = 0; i < 16; i++)
        XCTAssertEqual(serverRecvKey[i], sendKey[i]);
    for (int i = 0; i < 14; i++)
        XCTAssertEqual(serverRecvSalt[i], sendSalt[i]);
}

- (void)testSrtpProtectThenUnprotectRoundTrips {
    uint8_t masterKey[16], masterSalt[14];
    for (int i = 0; i < 16; i++) masterKey[i] = (uint8_t)(0x10 + i);
    for (int i = 0; i < 14; i++) masterSalt[i] = (uint8_t)(0x40 + i);

    TGSrtpContext sender, receiver;
    TGSrtpContextInit(&sender, masterKey, masterSalt);
    TGSrtpContextInit(&receiver, masterKey, masterSalt);

    uint8_t packet[128];
    const uint8_t payload[20] = "an opus frame here!";
    makeRtp(packet, 100, 0x12345678, payload, sizeof(payload));

    size_t protectedLength = 0;
    XCTAssertEqual(TGSrtpProtect(&sender, packet, 12 + sizeof(payload),
                                 sizeof(packet), &protectedLength), 0);
    XCTAssertEqual(protectedLength, 12 + sizeof(payload) + TGSrtpTagLength);
    XCTAssertTrue(memcmp(packet + 12, payload, sizeof(payload)) != 0,
                  @"the payload is encrypted on the wire");

    size_t plainLength = 0;
    XCTAssertEqual(TGSrtpUnprotect(&receiver, packet, protectedLength,
                                   &plainLength), 0);
    XCTAssertEqual(plainLength, 12 + sizeof(payload));
    XCTAssertTrue(memcmp(packet + 12, payload, sizeof(payload)) == 0,
                  @"the receiver gets the original payload");

    // A single flipped byte must be rejected, not decrypted.
    makeRtp(packet, 101, 0x12345678, payload, sizeof(payload));
    TGSrtpProtect(&sender, packet, 12 + sizeof(payload), sizeof(packet),
                  &protectedLength);
    packet[protectedLength - 1] ^= 0x01;
    XCTAssertEqual(TGSrtpUnprotect(&receiver, packet, protectedLength,
                                   &plainLength), -1);
}

- (void)testKdfMatchesRfc3711AppendixB3 {
    // RFC 3711 B.3 master key/salt and the session keys they derive.
    const uint8_t masterKey[16] = {
        0xE1, 0xF9, 0x7A, 0x0D, 0x3E, 0x01, 0x8B, 0xE0,
        0xD6, 0x4F, 0xA3, 0x2C, 0x06, 0xDE, 0x41, 0x39,
    };
    const uint8_t masterSalt[14] = {
        0x0E, 0xC6, 0x75, 0xAD, 0x49, 0x8A, 0xFE, 0xEB,
        0xB6, 0x96, 0x0B, 0x3A, 0xAB, 0xE6,
    };
    const uint8_t expectedKey[16] = {
        0xC6, 0x1E, 0x7A, 0x93, 0x74, 0x4F, 0x39, 0xEE,
        0x10, 0x73, 0x4A, 0xFE, 0x3F, 0xF7, 0xA0, 0x87,
    };
    const uint8_t expectedSalt[14] = {
        0x30, 0xCB, 0xBC, 0x08, 0x86, 0x3D, 0x8C, 0x85,
        0xD4, 0x9D, 0xB3, 0x4A, 0x9A, 0xE1,
    };
    const uint8_t expectedAuth[20] = {
        0xCE, 0xBE, 0x32, 0x1F, 0x6F, 0xF7, 0x71, 0x6B, 0x6F, 0xD4,
        0xAB, 0x49, 0xAF, 0x25, 0x6A, 0x15, 0x6D, 0x38, 0xBA, 0xA4,
    };
    TGSrtpContext ctx;
    TGSrtpContextInit(&ctx, masterKey, masterSalt);
    XCTAssertTrue(memcmp(ctx.encKey, expectedKey, 16) == 0,
                  @"SRTP session encryption key (RFC 3711 B.3)");
    XCTAssertTrue(memcmp(ctx.salt, expectedSalt, 14) == 0,
                  @"SRTP session salt (RFC 3711 B.3)");
    XCTAssertTrue(memcmp(ctx.authKey, expectedAuth, 20) == 0,
                  @"SRTP session auth key (RFC 3711 B.3)");
}

- (void)testDtlsHandshakeExportsSameKeyingMaterialOnBothSides {
    TGCallDtls *client = [[TGCallDtls alloc] initWithClient:YES];
    TGCallDtls *server = [[TGCallDtls alloc] initWithClient:NO];
    XCTAssertTrue([client setupWithError:NULL]);
    XCTAssertTrue([server setupWithError:NULL]);
    client.sendRecord = ^(const uint8_t *bytes, size_t length){
        [server feed:bytes length:length];
    };
    server.sendRecord = ^(const uint8_t *bytes, size_t length){
        [client feed:bytes length:length];
    };
    [client beginHandshake];
    XCTAssertTrue(client.isConnected, @"client handshake");
    XCTAssertTrue(server.isConnected, @"server handshake");

    uint8_t clientKeys[60], serverKeys[60];
    XCTAssertTrue([client exportKeyingMaterial:clientKeys length:60]);
    XCTAssertTrue([server exportKeyingMaterial:serverKeys length:60]);
    XCTAssertTrue(memcmp(clientKeys, serverKeys, 60) == 0,
                  @"RFC 5705 exporter must agree on both sides");

    uint8_t sendKey[16], sendSalt[14], receiveKey[16], receiveSalt[14];
    TGSrtpSplitExporter(clientKeys, 1, sendKey, sendSalt, receiveKey, receiveSalt);
    TGSrtpContext sender, receiver;
    TGSrtpContextInit(&sender, sendKey, sendSalt);
    // The server receives what the client sent: its receive key is the
    // client's key, which is this side's send key.
    TGSrtpContextInit(&receiver, sendKey, sendSalt);

    uint8_t packet[128];
    const uint8_t payload[12] = "hello audio";
    makeRtp(packet, 7, 0x11223344, payload, sizeof(payload));
    size_t protectedLength = 0, plainLength = 0;
    XCTAssertEqual(TGSrtpProtect(&sender, packet, 12 + sizeof(payload),
                                 sizeof(packet), &protectedLength), 0);
    XCTAssertEqual(TGSrtpUnprotect(&receiver, packet, protectedLength,
                                   &plainLength), 0);
    XCTAssertTrue(memcmp(packet + 12, payload, sizeof(payload)) == 0);
}

- (void)testSrtpRocAdvancesAtSequenceWrap {
    uint8_t masterKey[16], masterSalt[14];
    for (int i = 0; i < 16; i++) masterKey[i] = (uint8_t)(0x20 + i);
    for (int i = 0; i < 14; i++) masterSalt[i] = (uint8_t)(0x60 + i);

    TGSrtpContext sender, receiver;
    TGSrtpContextInit(&sender, masterKey, masterSalt);
    TGSrtpContextInit(&receiver, masterKey, masterSalt);

    const uint8_t payload[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    uint8_t packet[64];
    uint16_t sequences[4] = {65534, 65535, 0, 1};
    for (int i = 0; i < 4; i++) {
        makeRtp(packet, sequences[i], 0x01020304, payload, sizeof(payload));
        size_t protectedLength = 0, plainLength = 0;
        XCTAssertEqual(TGSrtpProtect(&sender, packet, 12 + sizeof(payload),
                                     sizeof(packet), &protectedLength), 0);
        XCTAssertEqual(TGSrtpUnprotect(&receiver, packet, protectedLength,
                                       &plainLength), 0);
        XCTAssertTrue(memcmp(packet + 12, payload, sizeof(payload)) == 0,
                      @"the wrapped sequence still decrypts");
    }
    XCTAssertEqual(sender.roc, 1u);
    XCTAssertEqual(receiver.roc, 1u);
}

@end
