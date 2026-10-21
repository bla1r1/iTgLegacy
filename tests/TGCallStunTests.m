// TGCallStunTests.m — unit tests for TGCallStun (STUN packet building / parsing).
//
// Checks that we produce RFC 5389-compliant binding requests and responses,
// including magic cookie, message integrity and fingerprint attributes.
#import "TGTestRunner.h"
#import "TGCallStun.h"
#include <netinet/in.h>
#include <arpa/inet.h>
#include <openssl/hmac.h>
#include <zlib.h>

// ── helpers ────────────────────────────────────────────────────────────────

static uint16_t readU16BE(const uint8_t *b) {
    return ((uint16_t)b[0] << 8) | b[1];
}
static uint32_t readU32BE(const uint8_t *b) {
    return ((uint32_t)b[0]<<24)|((uint32_t)b[1]<<16)|((uint32_t)b[2]<<8)|b[3];
}

/// Walk STUN attributes from offset 20, call block for each.
/// block receives (type, value_bytes_ptr, value_len); returns NO to stop.
static void walkAttributes(const uint8_t *msg, size_t len,
                           BOOL (^block)(uint16_t type, const uint8_t *val, uint16_t vlen)) {
    size_t at = 20;
    while (at + 4 <= len) {
        uint16_t type = readU16BE(msg + at);
        uint16_t vlen = readU16BE(msg + at + 2);
        at += 4;
        if (at + vlen > len) break;
        if (!block(type, msg + at, vlen)) return;
        // attributes are padded to 4 bytes
        at += (vlen + 3) & ~3u;
    }
}

/// Find an attribute by type; returns NO if absent.
static BOOL findAttr(NSData *msg, uint16_t wantType,
                     const uint8_t **outVal, uint16_t *outLen) {
    __block BOOL found = NO;
    walkAttributes(msg.bytes, msg.length, ^BOOL(uint16_t t, const uint8_t *v, uint16_t l) {
        if (t == wantType) { *outVal = v; *outLen = l; found = YES; return NO; }
        return YES;
    });
    return found;
}

// ──────────────────────────────────────────────────────────────────────────────

@interface TGCallStunTests : XCTestCase
@end

@implementation TGCallStunTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - messageTypeOf

- (void)testMessageTypeOf_BindingRequest {
    // Build a minimal 20-byte STUN binding request header manually.
    uint8_t raw[20] = {0};
    raw[0] = 0x00; raw[1] = 0x01;       // type = 0x0001
    raw[2] = 0x00; raw[3] = 0x00;       // length = 0
    raw[4] = 0x21; raw[5] = 0x12;
    raw[6] = 0xA4; raw[7] = 0x42;       // magic cookie
    // transaction id bytes 8..19 can be anything
    NSData *pkt = [NSData dataWithBytes:raw length:20];
    XCTAssertEqual([TGCallStun messageTypeOf:pkt], 0x0001);
}

- (void)testMessageTypeOf_BindingSuccessResponse {
    uint8_t raw[20] = {0};
    raw[0] = 0x01; raw[1] = 0x01;
    raw[4] = 0x21; raw[5] = 0x12; raw[6] = 0xA4; raw[7] = 0x42;
    NSData *pkt = [NSData dataWithBytes:raw length:20];
    XCTAssertEqual([TGCallStun messageTypeOf:pkt], 0x0101);
}

- (void)testMessageTypeOf_NonStunPacket {
    // First two bits non-zero → not STUN.
    uint8_t raw[20] = {0};
    raw[0] = 0xFF;
    NSData *pkt = [NSData dataWithBytes:raw length:20];
    XCTAssertEqual([TGCallStun messageTypeOf:pkt], -1);
}

- (void)testMessageTypeOf_WrongMagicCookie {
    uint8_t raw[20] = {0};
    raw[0] = 0x00; raw[1] = 0x01;
    // wrong cookie
    raw[4] = 0xDE; raw[5] = 0xAD; raw[6] = 0xBE; raw[7] = 0xEF;
    NSData *pkt = [NSData dataWithBytes:raw length:20];
    XCTAssertEqual([TGCallStun messageTypeOf:pkt], -1);
}

- (void)testMessageTypeOf_TooShort {
    uint8_t raw[10] = {0};
    NSData *pkt = [NSData dataWithBytes:raw length:10];
    XCTAssertEqual([TGCallStun messageTypeOf:pkt], -1);
}

- (void)testMessageTypeOf_EmptyData {
    XCTAssertEqual([TGCallStun messageTypeOf:[NSData data]], -1);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - bindingRequest structure

- (void)testBindingRequest_Type {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"peer:self"
                                               password:@"secret"
                                            tieBreaker:0x0102030405060708ULL
                                           useCandidate:NO];
    XCTAssertNotNil(req);
    XCTAssertGreaterThanOrEqual(req.length, 20u);
    // bytes [0..1] == 0x0001
    const uint8_t *b = req.bytes;
    XCTAssertEqual(readU16BE(b), (uint16_t)0x0001);
}

- (void)testBindingRequest_MagicCookie {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"ab:cd"
                                               password:@"pw"
                                            tieBreaker:1
                                           useCandidate:NO];
    const uint8_t *b = req.bytes;
    XCTAssertEqual(readU32BE(b + 4), (uint32_t)0x2112A442,
                   @"magic cookie must be 0x2112A442");
}

- (void)testBindingRequest_ContainsUsernameAttribute {
    NSString *username = @"peerUfrag:ourUfrag";
    NSData *req = [TGCallStun bindingRequestWithUsername:username
                                               password:@"testpwd"
                                            tieBreaker:42
                                           useCandidate:NO];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x0006, &val, &vlen);
    XCTAssertTrue(found, @"USERNAME attribute (0x0006) not found");

    NSString *parsed = [[NSString alloc] initWithBytes:val length:vlen
                                             encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(parsed, username, @"USERNAME value mismatch");
}

- (void)testBindingRequest_ContainsMessageIntegrity {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"a:b"
                                               password:@"mypassword"
                                            tieBreaker:7
                                           useCandidate:NO];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x0008, &val, &vlen);
    XCTAssertTrue(found,          @"MESSAGE-INTEGRITY attribute (0x0008) not found");
    XCTAssertEqual(vlen, (uint16_t)20, @"HMAC-SHA1 must be 20 bytes");
}

- (void)testBindingRequest_ContainsFingerprint {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"a:b"
                                               password:@"mypassword"
                                            tieBreaker:7
                                           useCandidate:NO];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x8028, &val, &vlen);
    XCTAssertTrue(found,        @"FINGERPRINT attribute (0x8028) not found");
    XCTAssertEqual(vlen, (uint16_t)4);
}

- (void)testBindingRequest_UseCandidateAttribute_Present {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"a:b"
                                               password:@"pw"
                                            tieBreaker:0
                                           useCandidate:YES];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x0025, &val, &vlen);
    XCTAssertTrue(found, @"USE-CANDIDATE attribute should be present");
}

- (void)testBindingRequest_UseCandidateAttribute_Absent {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"a:b"
                                               password:@"pw"
                                            tieBreaker:0
                                           useCandidate:NO];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x0025, &val, &vlen);
    XCTAssertFalse(found, @"USE-CANDIDATE should be absent");
}

- (void)testBindingRequest_ContainsPriority {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"x:y"
                                               password:@"p"
                                            tieBreaker:1
                                           useCandidate:NO];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x0024, &val, &vlen);
    XCTAssertTrue(found, @"PRIORITY attribute (0x0024) not found");
    XCTAssertEqual(vlen, (uint16_t)4);
}

- (void)testBindingRequest_ICEControllingAttribute {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"x:y"
                                               password:@"p"
                                            tieBreaker:0xABCDEF0102030405ULL
                                           useCandidate:NO];
    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(req, 0x802A, &val, &vlen);
    XCTAssertTrue(found, @"ICE-CONTROLLING attribute (0x802A) not found");
    XCTAssertEqual(vlen, (uint16_t)8, @"tie-breaker must be 8 bytes");
}

/// messageTypeOf must recognise the request we build.
- (void)testBindingRequest_RecognisedByMessageTypeOf {
    NSData *req = [TGCallStun bindingRequestWithUsername:@"x:y"
                                               password:@"p"
                                            tieBreaker:0
                                           useCandidate:NO];
    XCTAssertEqual([TGCallStun messageTypeOf:req], 0x0001);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - bindingResponse structure

- (NSData *)makeFakeRequest {
    return [TGCallStun bindingRequestWithUsername:@"their:our"
                                        password:@"theirpwd"
                                     tieBreaker:0
                                    useCandidate:YES];
}

- (NSData *)fakeSockaddrWithIP:(const char *)ip port:(uint16_t)port {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(port);
    inet_pton(AF_INET, ip, &addr.sin_addr);
    return [NSData dataWithBytes:&addr length:sizeof(addr)];
}

- (void)testBindingResponse_TypeIs0101 {
    NSData *req  = [self makeFakeRequest];
    NSData *addr = [self fakeSockaddrWithIP:@"1.2.3.4" port:54321];
    NSData *resp = [TGCallStun bindingResponseTo:req password:@"ourpwd" fromAddress:addr];
    XCTAssertNotNil(resp);
    XCTAssertGreaterThanOrEqual(resp.length, 20u);
    const uint8_t *b = resp.bytes;
    XCTAssertEqual(readU16BE(b), (uint16_t)0x0101);
}

- (void)testBindingResponse_MagicCookie {
    NSData *req  = [self makeFakeRequest];
    NSData *addr = [self fakeSockaddrWithIP:@"127.0.0.1" port:9999];
    NSData *resp = [TGCallStun bindingResponseTo:req password:@"pw" fromAddress:addr];
    XCTAssertEqual(readU32BE((const uint8_t *)resp.bytes + 4), (uint32_t)0x2112A442);
}

- (void)testBindingResponse_SameTransactionId {
    NSData *req  = [self makeFakeRequest];
    NSData *addr = [self fakeSockaddrWithIP:@"10.0.0.1" port:1234];
    NSData *resp = [TGCallStun bindingResponseTo:req password:@"pw" fromAddress:addr];
    // Transaction ID is bytes [8..19] of the STUN header.
    XCTAssertEqual(memcmp((const uint8_t *)req.bytes + 8,
                          (const uint8_t *)resp.bytes + 8, 12), 0,
                   @"transaction ID must be echoed back");
}

- (void)testBindingResponse_ContainsXorMappedAddress {
    NSData *req  = [self makeFakeRequest];
    NSData *addr = [self fakeSockaddrWithIP:@"192.168.1.2" port:5000];
    NSData *resp = [TGCallStun bindingResponseTo:req password:@"pw" fromAddress:addr];

    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(resp, 0x0020, &val, &vlen);
    XCTAssertTrue(found, @"XOR-MAPPED-ADDRESS attribute (0x0020) not found");
    XCTAssertGreaterThanOrEqual(vlen, (uint16_t)8);
}

- (void)testBindingResponse_ContainsMessageIntegrity {
    NSData *req  = [self makeFakeRequest];
    NSData *addr = [self fakeSockaddrWithIP:@"1.1.1.1" port:80];
    NSData *resp = [TGCallStun bindingResponseTo:req password:@"mypwd" fromAddress:addr];

    const uint8_t *val; uint16_t vlen;
    BOOL found = findAttr(resp, 0x0008, &val, &vlen);
    XCTAssertTrue(found,           @"MESSAGE-INTEGRITY not found in response");
    XCTAssertEqual(vlen, (uint16_t)20);
}

- (void)testBindingResponse_RecognisedByMessageTypeOf {
    NSData *req  = [self makeFakeRequest];
    NSData *addr = [self fakeSockaddrWithIP:@"10.0.0.1" port:4444];
    NSData *resp = [TGCallStun bindingResponseTo:req password:@"pw" fromAddress:addr];
    XCTAssertEqual([TGCallStun messageTypeOf:resp], 0x0101);
}

- (void)testBindingResponse_NilForTooShortRequest {
    NSData *tooShort = [NSData dataWithBytes:@"\x00\x01\x00\x00" length:4];
    NSData *addr = [self fakeSockaddrWithIP:@"1.1.1.1" port:80];
    NSData *resp = [TGCallStun bindingResponseTo:tooShort password:@"pw" fromAddress:addr];
    XCTAssertNil(resp, @"must return nil for undersized request");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - hexOf

- (void)testHexOf_KnownBytes {
    uint8_t bytes[] = { 0xDE, 0xAD, 0xBE, 0xEF };
    NSData *data = [NSData dataWithBytes:bytes length:4];
    NSString *hex = [TGCallStun hexOf:data];
    XCTAssertEqualObjects(hex, @"deadbeef");
}

- (void)testHexOf_EmptyData {
    NSString *hex = [TGCallStun hexOf:[NSData data]];
    XCTAssertEqualObjects(hex, @"");
}

@end
