//
// TGCallDtls - the DTLS 1.2 handshake for tgcalls 9.0.0, over memory BIOs.
//
// The transport is the reflector, not a socket, so records go in and out as
// buffers. One instance per call. All methods except -setupWithError: are safe
// to call from the reflector reader thread; the owner serialises them.
//
#ifndef TG_CALL_DTLS_H
#define TG_CALL_DTLS_H

#import <Foundation/Foundation.h>

@class TGCallDtls;

@interface TGCallDtls : NSObject

/// YES for the caller (DTLS client), NO for the callee (server).
- (instancetype)initWithClient:(BOOL)client;

/// Generate the ECDSA P-256 certificate and create the SSL. A few milliseconds
/// of key generation, so callers keep it off the main thread.
- (BOOL)setupWithError:(NSString **)error;

/// SHA-256 of the DER certificate, colon-separated uppercase hex.
@property (nonatomic, readonly) NSString *fingerprint;

@property (nonatomic, readonly, getter=isConnected) BOOL connected;

/// A complete DTLS record (or several) from the peer.
- (void)feed:(const uint8_t *)bytes length:(size_t)length;

/// Sends the first flight once both sides have announced their setup.
- (void)beginHandshake;

/// DTLS retransmission timer. Call about every 500 ms.
- (void)handleTimeout;

/// RFC 5705 exporter with the SRTP label. 60 bytes for AES128_CM_SHA1_80.
- (BOOL)exportKeyingMaterial:(uint8_t *)out length:(size_t)length;

/// Where records to the peer go. Called with one datagram per invocation.
@property (nonatomic, copy) void (^sendRecord)(const uint8_t *bytes, size_t length);
@property (nonatomic, copy) void (^onConnected)(void);
@property (nonatomic, copy) void (^onFailure)(NSString *reason);

- (void)stop;

@end

#endif
