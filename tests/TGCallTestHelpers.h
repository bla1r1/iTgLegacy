// TGCallTestHelpers.h — shared utilities for the call stack test suite.
//
// Compiled into every test binary; nothing here may reference Xcode-only
// frameworks that are not available in a plain clang invocation on macOS.
#pragma once

#import <Foundation/Foundation.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

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

// ─── loopback UDP helpers ────────────────────────────────────────────────────
// The ICE and reflector tests exercise the real socket path, not a transport
// block: open a socket on 127.0.0.1, hand its port to the object under test,
// and assert the bytes that actually arrive.

/// A UDP socket bound to 127.0.0.1:0. `port` receives the assigned port.
/// Returns -1 when the socket cannot be opened.
static inline int TGTestUDPSocket(uint16_t *port) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
        return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port        = 0;

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    socklen_t len = sizeof(addr);
    if (getsockname(fd, (struct sockaddr *)&addr, &len) < 0) {
        close(fd);
        return -1;
    }
    if (port)
        *port = ntohs(addr.sin_port);
    return fd;
}

/// Send `packet` to 127.0.0.1:`port`.
static inline BOOL TGTestSendTo(int fd, NSData *packet, uint16_t port) {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port        = htons(port);

    ssize_t sent = sendto(fd, packet.bytes, packet.length, 0,
                          (struct sockaddr *)&addr, sizeof(addr));
    return sent == (ssize_t)packet.length;
}

/// Receive one datagram, waiting up to `seconds`. `from` receives the sender
/// address. Returns nil on timeout.
///
/// The wait pumps the main run loop: TGCallIce and TGCallReflector deliver
/// packets through dispatch_get_main_queue and send checks from an NSTimer,
/// so blocking the main thread would deadlock the very code under test.
static inline NSData *TGTestRecvFrom(int fd, struct sockaddr_in *from,
                                     NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    for (;;) {
        if ([deadline timeIntervalSinceNow] <= 0)
            return nil;

        uint8_t buffer[2048];
        struct sockaddr_in addr;
        socklen_t len = sizeof(addr);
        ssize_t got = recvfrom(fd, buffer, sizeof(buffer), MSG_DONTWAIT,
                               (struct sockaddr *)&addr, &len);
        if (got > 0) {
            if (from)
                *from = addr;
            return [NSData dataWithBytes:buffer length:(NSUInteger)got];
        }

        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

/// Receive the next datagram that is not one of the reflector's 40-byte pings.
/// The pinger runs every 0.5 s, so a test that waits for a data packet can
/// otherwise pick a ping out of the queue.
static inline NSData *TGTestRecvNonPing(int fd, struct sockaddr_in *from,
                                        NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    for (;;) {
        NSTimeInterval left = [deadline timeIntervalSinceNow];
        if (left <= 0)
            return nil;
        NSData *packet = TGTestRecvFrom(fd, from, left);
        if (!packet)
            return nil;
        if (packet.length != 40)
            return packet;
    }
}
