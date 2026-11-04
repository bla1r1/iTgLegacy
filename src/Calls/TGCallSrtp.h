//
// TGCallSrtp - SRTP/SRTCP for the 9.0.0 media path.
//
// Pure C on purpose: one of these runs per direction for the length of a call
// and nothing here may allocate per packet. Profile is SRTP_AES128_CM_SHA1_80,
// RFC 3711.
//
#ifndef TG_CALL_SRTP_H
#define TG_CALL_SRTP_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TGSrtpKeyLength   16
#define TGSrtpSaltLength  14
#define TGSrtpAuthLength  20
#define TGSrtpTagLength   10

typedef struct {
	uint8_t  encKey[TGSrtpKeyLength];
	uint8_t  authKey[TGSrtpAuthLength];
	uint8_t  salt[TGSrtpSaltLength];
	uint32_t roc;          // rollover counter for the SSRC in this direction
	uint16_t highestSeq;
	int      haveHighest;
} TGSrtpContext;

/// Derive the session keys from the 16-byte master key and 14-byte salt.
/// Each direction has its own context; a context only ever sees one SSRC.
void TGSrtpContextInit(TGSrtpContext *ctx,
                       const uint8_t masterKey[TGSrtpKeyLength],
                       const uint8_t masterSalt[TGSrtpSaltLength]);

/// Split the 60-byte DTLS exporter block into the two directions. The DTLS
/// client writes the first half, the server the second; reading is the other.
void TGSrtpSplitExporter(const uint8_t exporter[60], int isClient,
                         uint8_t sendKey[TGSrtpKeyLength],
                         uint8_t sendSalt[TGSrtpSaltLength],
                         uint8_t receiveKey[TGSrtpKeyLength],
                         uint8_t receiveSalt[TGSrtpSaltLength]);

/// Protect one RTP packet in place. `capacity` is the size of `packet` and
/// must be at least `length + TGSrtpTagLength`. Returns 0 on success.
int TGSrtpProtect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                  size_t capacity, size_t *outLength);

/// Verify and decrypt one RTP packet in place. Returns 0 on success, -1 when
/// the packet is too short or the tag does not match.
int TGSrtpUnprotect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                    size_t *outLength);

/// The same for a compound RTCP packet. The 31-bit SRTCP index lives in the
/// four bytes before the tag.
int TGSrtcpProtect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                   size_t capacity, uint32_t index, size_t *outLength);
int TGSrtcpUnprotect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                     size_t *outLength);

#ifdef __cplusplus
}
#endif

#endif
