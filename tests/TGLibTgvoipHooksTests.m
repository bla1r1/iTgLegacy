// TGLibTgvoipHooksTests.m — the custom crypto and video hooks TGCall.mm
// installs for libtgvoip.
//
// Starting media fills VoIPController::crypto with the OpenSSL-backed
// functions. Once installed, the same pointers libtgvoip would use are called
// here directly and checked against known answers and round-trips.
#import "TGTestRunner.h"
#import "TGCall.h"
#import "TGLibTgvoipBridge.h"

static NSData *TGHexData(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        unsigned value = 0;
        sscanf([[hex substringWithRange:NSMakeRange(i, 2)] UTF8String], "%x", &value);
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

@interface TGCall (HooksTestSupport)
- (void)teardown;
@end

@interface TGLibTgvoipHooksTests : XCTestCase
@end

@implementation TGLibTgvoipHooksTests

- (void)setUp {
    [super setUp];

    // Any callStateReady runs TGInstallCrypto() before it validates the key or
    // opens a reflector, so an empty server list is enough to install hooks.
    NSMutableData *key = [NSMutableData dataWithLength:256];
    for (NSUInteger i = 0; i < key.length; i++)
        ((uint8_t *)key.mutableBytes)[i] = (uint8_t)i;

    [[TGCall shared] handleUpdate:@{
        @"@type"       : @"call",
        @"id"          : @(1),
        @"user_id"     : @(1LL),
        @"is_outgoing" : @YES,
        @"state"       : @{
            @"@type"          : @"callStateReady",
            @"encryption_key" : [key base64EncodedStringWithOptions:0],
            @"servers"        : @[],
            @"protocol"       : @{ @"@type": @"callProtocol",
                                   @"library_versions": @[@"9.0.0"] },
        },
    }];
}

- (void)tearDown {
    [[TGCall shared] teardown];
    [super tearDown];
}

- (void)testCryptoHooksInstalled {
    XCTAssertTrue([TGLibTgvoipBridge cryptoInstalled],
                  @"TGInstallCrypto must fill every pointer");
}

- (void)testRandomBytesAreFilled {
    NSData *first = [TGLibTgvoipBridge randomBytesOfLength:32];
    NSData *second = [TGLibTgvoipBridge randomBytesOfLength:32];

    XCTAssertEqual(first.length, (NSUInteger)32);
    XCTAssertEqual(second.length, (NSUInteger)32);

    BOOL allZero = YES;
    const uint8_t *bytes = (const uint8_t *)first.bytes;
    for (NSUInteger i = 0; i < first.length; i++)
        if (bytes[i] != 0)
            allZero = NO;
    XCTAssertFalse(allZero, @"RAND_bytes must not leave the buffer empty");
    XCTAssertNotEqual(memcmp(first.bytes, second.bytes, 32), 0);
}

- (void)testSHA1KnownVector {
    NSData *digest = [TGLibTgvoipBridge sha1OfData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqualObjects(digest,
        TGHexData(@"a9993e364706816aba3e25717850c26c9cd0d89d"));
}

- (void)testSHA256KnownVector {
    NSData *digest = [TGLibTgvoipBridge sha256OfData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqualObjects(digest,
        TGHexData(@"ba7816bf8f01cfea414140de5dae2223"
                  @"b00361a396177a9cb410ff61f20015ad"));
}

- (void)testAESIGERoundTrip {
    uint8_t raw[32], key[32], iv[32];
    for (NSUInteger i = 0; i < 32; i++) {
        raw[i] = (uint8_t)(i + 1);
        key[i] = (uint8_t)(0xA0 + i);
        iv[i]  = (uint8_t)(0x10 + i);
    }

    NSData *plain = [NSData dataWithBytes:raw length:sizeof(raw)];
    NSData *result = [TGLibTgvoipBridge igeRoundTrip:plain
                                                 key:[NSData dataWithBytes:key length:sizeof(key)]
                                                  iv:[NSData dataWithBytes:iv length:sizeof(iv)]];
    XCTAssertEqualObjects(result, plain);
}

- (void)testAESCBCRoundTrip {
    uint8_t raw[32], key[32], iv[16];
    for (NSUInteger i = 0; i < 32; i++) {
        raw[i] = (uint8_t)(i + 1);
        key[i] = (uint8_t)(0x30 + i);
    }
    for (NSUInteger i = 0; i < 16; i++)
        iv[i] = (uint8_t)(0x50 + i);

    NSData *plain = [NSData dataWithBytes:raw length:sizeof(raw)];
    NSData *result = [TGLibTgvoipBridge cbcRoundTrip:plain
                                                 key:[NSData dataWithBytes:key length:sizeof(key)]
                                                  iv:[NSData dataWithBytes:iv length:sizeof(iv)]];
    XCTAssertEqualObjects(result, plain);
}

- (void)testAESCTRRoundTrip {
    uint8_t raw[32], key[32], iv[16];
    for (NSUInteger i = 0; i < 32; i++) {
        raw[i] = (uint8_t)(i + 1);
        key[i] = (uint8_t)(0x70 + i);
    }
    for (NSUInteger i = 0; i < 16; i++)
        iv[i] = (uint8_t)(0x90 + i);

    NSData *plain = [NSData dataWithBytes:raw length:sizeof(raw)];
    NSData *result = [TGLibTgvoipBridge ctrRoundTrip:plain
                                                 key:[NSData dataWithBytes:key length:sizeof(key)]
                                                  iv:[NSData dataWithBytes:iv length:sizeof(iv)]];
    XCTAssertEqualObjects(result, plain);
}

/// This build ships no video, so libtgvoip has to be told exactly that.
- (void)testVideoHooksAreEmpty {
    XCTAssertEqual([TGLibTgvoipBridge availableEncoderCount], (NSUInteger)0);
    XCTAssertEqual([TGLibTgvoipBridge availableDecoderCount], (NSUInteger)0);
    XCTAssertEqual([TGLibTgvoipBridge maximumResolution], 0);
}

@end
