// TGCallCryptoTests.m — unit tests for TGCallCrypto (encrypt / decrypt).
//
// KEY DESIGN RULE for tgcalls crypto:
//   Caller (outgoing=1) WRITES with x=0, READS with x=8.
//   Callee (outgoing=0) WRITES with x=8, READS with x=0.
//   So: encrypt(outgoing=A) must be decrypted with encrypt(outgoing=!A).
//
// In other words, for a round-trip test:
//   TGCallEncryptPacket(key, outgoing=1, ...) →
//   TGCallDecryptPacket(key, outgoing=0, ...)
//   (the receiver has outgoing=0 from its own perspective)
#import "TGTestRunner.h"
#import "TGCallTestHelpers.h"
#include "TGCallCrypto.h"
#include <string.h>

@interface TGCallCryptoTests : XCTestCase
@end

@implementation TGCallCryptoTests

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - round-trip (caller → callee direction)

/// Caller (outgoing=1) encrypts; callee (outgoing=0) decrypts.
- (void)testRoundTrip_media_callerToCallee {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 0x05, 0x80, 0x01, 0x6F, 0x00, 0x00, 0x00, 0x01 };
    uint32_t seqIn = 42;

    uint8_t ciphertext[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, /*caller outgoing*/1, /*signaling*/0,
                                    payload, sizeof(payload), seqIn, ciphertext);
    XCTAssertGreaterThan(encLen, 0, @"encrypt returned no bytes");

    uint8_t plaintext[sizeof(payload) + 20];
    uint32_t seqOut = 0;
    // Callee decrypts with outgoing=0 (its own perspective)
    int decLen = TGCallDecryptPacket(key.bytes, /*callee outgoing*/0, /*signaling*/0,
                                    ciphertext, (size_t)encLen, plaintext, &seqOut);
    XCTAssertEqual(decLen, (int)sizeof(payload), @"decrypted length mismatch");
    XCTAssertEqual(seqOut, seqIn,               @"seq not preserved");
    XCTAssertEqual(memcmp(plaintext, payload, sizeof(payload)), 0,
                   @"decrypted bytes differ from original");
}

/// Callee (outgoing=0) encrypts; caller (outgoing=1) decrypts.
- (void)testRoundTrip_media_calleeToCaller {
    NSData *key = TGTestCallKey();

    uint8_t payload[20];
    for (int i = 0; i < 20; i++) payload[i] = (uint8_t)i;
    uint32_t seqIn = 7;

    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, /*callee*/0, /*signaling*/0,
                                    payload, sizeof(payload), seqIn, cipher);
    XCTAssertGreaterThan(encLen, 0);

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seqOut = 0;
    // Caller decrypts with outgoing=1
    int decLen = TGCallDecryptPacket(key.bytes, /*caller*/1, /*signaling*/0,
                                    cipher, (size_t)encLen, plain, &seqOut);
    XCTAssertEqual(decLen, (int)sizeof(payload));
    XCTAssertEqual(seqOut, seqIn);
    XCTAssertEqual(memcmp(plain, payload, sizeof(payload)), 0);
}

/// Signalling channel: caller encrypts, callee decrypts.
- (void)testRoundTrip_signalling_callerToCallee {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 0x01, 0x02, 0x03, 0x04, 0x05 };
    uint32_t seqIn = 0xDEADBEEF;

    uint8_t ciphertext[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, /*signaling*/1,
                                    payload, sizeof(payload), seqIn, ciphertext);
    XCTAssertGreaterThan(encLen, 0);

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seqOut = 0;
    int decLen = TGCallDecryptPacket(key.bytes, 0, /*signaling*/1,
                                    ciphertext, (size_t)encLen, plain, &seqOut);
    XCTAssertEqual(decLen, (int)sizeof(payload));
    XCTAssertEqual(seqOut, seqIn);
    XCTAssertEqual(memcmp(plain, payload, sizeof(payload)), 0);
}

/// Signalling channel: callee encrypts, caller decrypts.
- (void)testRoundTrip_signalling_calleeToCaller {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 0xAA, 0xBB, 0xCC };
    uint32_t seqIn = 1;

    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 0, 1,
                                    payload, sizeof(payload), seqIn, cipher);
    XCTAssertGreaterThan(encLen, 0);

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seqOut = 0;
    int decLen = TGCallDecryptPacket(key.bytes, 1, 1,
                                    cipher, (size_t)encLen, plain, &seqOut);
    XCTAssertEqual(decLen, (int)sizeof(payload));
    XCTAssertEqual(seqOut, seqIn);
    XCTAssertEqual(memcmp(plain, payload, sizeof(payload)), 0);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - direction asymmetry

/// Caller encrypts; trying to decrypt as caller (same direction) must fail.
/// The key slices differ by direction, so auth hash will not match.
- (void)testDecryptFails_sameDirection_callerCaller {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 0xAA, 0xBB, 0xCC };
    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, 0,
                                    payload, sizeof(payload), 1, cipher);
    XCTAssertGreaterThan(encLen, 0);

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seq = 0;
    // Both outgoing=1 — wrong direction, should fail
    int result = TGCallDecryptPacket(key.bytes, 1, 0,
                                    cipher, (size_t)encLen, plain, &seq);
    XCTAssertLessThanOrEqual(result, 0, @"same-direction decrypt must be rejected");
}

/// Media-channel packet must not be readable on the signalling channel.
- (void)testDecryptFails_wrongChannel {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 0x05, 0x80, 0x00, 0x01 };
    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, /*signaling*/0,
                                    payload, sizeof(payload), 1, cipher);
    XCTAssertGreaterThan(encLen, 0);

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seq = 0;
    int result = TGCallDecryptPacket(key.bytes, 0, /*signaling*/1,
                                    cipher, (size_t)encLen, plain, &seq);
    XCTAssertLessThanOrEqual(result, 0, @"wrong channel must be rejected");
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - authentication

/// A packet with a flipped ciphertext byte must be rejected.
- (void)testDecryptRejectsModifiedCiphertext {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 1, 2, 3, 4, 5 };
    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, 0,
                                    payload, sizeof(payload), 99, cipher);
    XCTAssertGreaterThan(encLen, 0);
    cipher[17] ^= 0xFF;

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seq = 0;
    int result = TGCallDecryptPacket(key.bytes, 0, 0,
                                    cipher, (size_t)encLen, plain, &seq);
    XCTAssertLessThanOrEqual(result, 0, @"tampered packet should be rejected");
}

/// Flipping a byte in the msgKey (first 16 bytes) must also be rejected.
- (void)testDecryptRejectsModifiedMsgKey {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 9, 8, 7 };
    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, 0,
                                    payload, sizeof(payload), 5, cipher);
    XCTAssertGreaterThan(encLen, 0);
    cipher[3] ^= 0x01;

    uint8_t plain[sizeof(payload) + 20];
    uint32_t seq = 0;
    int result = TGCallDecryptPacket(key.bytes, 0, 0,
                                    cipher, (size_t)encLen, plain, &seq);
    XCTAssertLessThanOrEqual(result, 0);
}

// ──────────────────────────────────────────────────────────────────────────────
#pragma mark - edge cases

/// Packets shorter than 21 bytes must be rejected without crashing.
- (void)testDecryptRejectsTooShortPacket {
    NSData *key = TGTestCallKey();
    uint8_t junk[20] = {0};
    uint8_t plain[20];
    uint32_t seq = 0;
    int r = TGCallDecryptPacket(key.bytes, 1, 0, junk, 20, plain, &seq);
    XCTAssertLessThanOrEqual(r, 0, @"20-byte packet is under the minimum");
}

/// seq output pointer may be NULL without crashing.
- (void)testDecryptNullSeqPointer {
    NSData *key = TGTestCallKey();

    uint8_t payload[] = { 0x01 };
    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, 0,
                                    payload, sizeof(payload), 11, cipher);
    XCTAssertGreaterThan(encLen, 0);

    uint8_t plain[sizeof(payload) + 20];
    // Callee decrypts (outgoing=0), NULL seq pointer
    int r = TGCallDecryptPacket(key.bytes, 0, 0,
                                cipher, (size_t)encLen, plain, NULL);
    XCTAssertGreaterThan(r, 0);
}

/// Different seq values produce different ciphertexts.
- (void)testDifferentSeqsDifferentCiphertexts {
    NSData *key = TGTestCallKey();
    uint8_t payload[] = { 0x05, 0x80, 0x00, 0x01 };

    uint8_t cipher1[sizeof(payload) + 20];
    uint8_t cipher2[sizeof(payload) + 20];
    TGCallEncryptPacket(key.bytes, 1, 0, payload, sizeof(payload), 1, cipher1);
    TGCallEncryptPacket(key.bytes, 1, 0, payload, sizeof(payload), 2, cipher2);

    XCTAssertNotEqual(memcmp(cipher1, cipher2, sizeof(payload) + 20), 0,
                      @"different seq must yield different ciphertext");
}

/// EncryptPacket returns the expected number of bytes (payload + seq(4) + msgKey(16)).
- (void)testEncryptReturnsCorrectLength {
    NSData *key = TGTestCallKey();
    uint8_t payload[] = { 1, 2, 3, 4, 5 };
    uint8_t cipher[sizeof(payload) + 20];
    int encLen = TGCallEncryptPacket(key.bytes, 1, 0,
                                    payload, sizeof(payload), 1, cipher);
    // Expected: 16 (msgKey) + 4 (seq) + sizeof(payload)
    XCTAssertEqual(encLen, (int)(16 + 4 + sizeof(payload)));
}

@end
