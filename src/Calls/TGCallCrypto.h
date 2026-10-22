//
// TGCallCrypto - packet crypto for VoIP calls (AES-256-CTR + SHA256).
//
// Packet layout:
//   [0..16)   msgKey (SHA256 slice of keyPart || plaintext)
//   [16..)    AES-256-CTR ciphertext of: be32 seq, then payload
//
#ifndef TG_CALL_CRYPTO_H
#define TG_CALL_CRYPTO_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Decrypt call packet using 256-byte TDLib key. Returns decrypted length or -1.
int TGCallDecryptPacket(const uint8_t *key, int outgoing, int signaling,
                        const uint8_t *packet, size_t length,
                        uint8_t *out, uint32_t *seq);

// Encrypt call packet using 256-byte TDLib key. Returns bytes written.
int TGCallEncryptPacket(const uint8_t *key, int outgoing, int signaling,
                        const uint8_t *payload, size_t length,
                        uint32_t seq, uint8_t *out);

#ifdef __cplusplus
}
#endif

#endif
