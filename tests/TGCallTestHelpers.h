// TGCallTestHelpers.h — shared utilities for the call stack test suite.
//
// Compiled into every test binary; nothing here may reference Xcode-only
// frameworks that are not available in a plain clang invocation on macOS.
#pragma once

#import <Foundation/Foundation.h>

/// A deterministic 256-byte key for tests.  All-zeros is a valid key for the
/// crypto algorithm (the hash still differs per direction / channel), and it
/// makes expected values reproducible across machines.
static inline NSData *TGTestCallKey(void) {
    static uint8_t key[256];
    // Use a simple pattern so failures print something recognisable.
    for (int i = 0; i < 256; i++) key[i] = (uint8_t)(i & 0xFF);
    return [NSData dataWithBytes:key length:256];
}

/// A 12-byte fake peer tag (TDLib supplies 16 bytes, last 4 are the side tag;
/// we test the reflector with only the 12-byte prefix filled in).
static inline NSData *TGTestPeerTag(void) {
    static uint8_t tag[16] = {
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66,
        0x00, 0x00, 0x00, 0x01   // last 4 = localTag placeholder
    };
    return [NSData dataWithBytes:tag length:16];
}

/// Spin the run loop for up to `seconds`, returning early when `condition`
/// becomes true.  Use for async callbacks in unit tests.
static inline BOOL TGWaitForCondition(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition()) {
        if ([NSDate date].timeIntervalSinceReferenceDate >
            deadline.timeIntervalSinceReferenceDate)
            return NO;
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return YES;
}
