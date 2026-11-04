#include "TGCallSrtp.h"

#include <string.h>
#include <openssl/aes.h>
#include <openssl/hmac.h>

// RFC 3711 4.3: key_id is the label in byte 7 of the 112-bit value, and the
// IV is that value shifted up by 16 bits. key_derivation_rate is zero, so the
// index is zero too.
static void TGSrtpDerive(const uint8_t *masterKey, const uint8_t *masterSalt,
                         uint8_t label, uint8_t *out, size_t outLength) {
	uint8_t iv[16] = {0};
	memcpy(iv, masterSalt, TGSrtpSaltLength);
	iv[7] ^= label;

	AES_KEY aes;
	AES_set_encrypt_key(masterKey, 128, &aes);

	uint8_t zeros[32] = {0};
	uint8_t stream[32];
	size_t offset = 0;
	uint32_t block = 0;
	while (offset < outLength) {
		iv[14] = (uint8_t)(block >> 8);
		iv[15] = (uint8_t)block;
		AES_encrypt(iv, stream + offset, &aes);
		offset += 16;
		block++;
	}
	memcpy(out, stream, outLength);
}

void TGSrtpContextInit(TGSrtpContext *ctx,
                       const uint8_t masterKey[TGSrtpKeyLength],
                       const uint8_t masterSalt[TGSrtpSaltLength]) {
	memset(ctx, 0, sizeof(*ctx));
	TGSrtpDerive(masterKey, masterSalt, 0x00, ctx->encKey, sizeof(ctx->encKey));
	TGSrtpDerive(masterKey, masterSalt, 0x01, ctx->authKey, sizeof(ctx->authKey));
	TGSrtpDerive(masterKey, masterSalt, 0x02, ctx->salt, sizeof(ctx->salt));
}

void TGSrtpSplitExporter(const uint8_t exporter[60], int isClient,
                         uint8_t sendKey[TGSrtpKeyLength],
                         uint8_t sendSalt[TGSrtpSaltLength],
                         uint8_t receiveKey[TGSrtpKeyLength],
                         uint8_t receiveSalt[TGSrtpSaltLength]) {
	// WebRTC's ExtractParams: both keys first, then both salts. The spec's
	// prose said key||salt per side; pc/dtls_srtp_transport.cc:245-253 is the
	// authority and the bench only authenticates with this layout.
	const uint8_t *clientKey = exporter;
	const uint8_t *serverKey = exporter + TGSrtpKeyLength;
	const uint8_t *clientSalt = exporter + 2 * TGSrtpKeyLength;
	const uint8_t *serverSalt = exporter + 2 * TGSrtpKeyLength + TGSrtpSaltLength;
	const uint8_t *sendKeySource = isClient ? clientKey : serverKey;
	const uint8_t *sendSaltSource = isClient ? clientSalt : serverSalt;
	const uint8_t *receiveKeySource = isClient ? serverKey : clientKey;
	const uint8_t *receiveSaltSource = isClient ? serverSalt : clientSalt;
	memcpy(sendKey, sendKeySource, TGSrtpKeyLength);
	memcpy(sendSalt, sendSaltSource, TGSrtpSaltLength);
	memcpy(receiveKey, receiveKeySource, TGSrtpKeyLength);
	memcpy(receiveSalt, receiveSaltSource, TGSrtpSaltLength);
}

static void TGSrtpIv(const TGSrtpContext *ctx, uint32_t ssrc, uint64_t index,
                     uint8_t iv[16]) {
	memset(iv, 0, 16);
	memcpy(iv, ctx->salt, TGSrtpSaltLength);
	iv[4] ^= (uint8_t)(ssrc >> 24);
	iv[5] ^= (uint8_t)(ssrc >> 16);
	iv[6] ^= (uint8_t)(ssrc >> 8);
	iv[7] ^= (uint8_t)ssrc;
	iv[8]  ^= (uint8_t)(index >> 40);
	iv[9]  ^= (uint8_t)(index >> 32);
	iv[10] ^= (uint8_t)(index >> 24);
	iv[11] ^= (uint8_t)(index >> 16);
	iv[12] ^= (uint8_t)(index >> 8);
	iv[13] ^= (uint8_t)index;
}

static void TGSrtpCtr(const TGSrtpContext *ctx, const uint8_t ivIn[16],
                      uint8_t *data, size_t length) {
	AES_KEY aes;
	AES_set_encrypt_key(ctx->encKey, 128, &aes);
	uint8_t iv[16];
	memcpy(iv, ivIn, 16);
	uint8_t stream[16];
	size_t offset = 0;
	uint32_t block = 0;
	while (offset < length) {
		iv[14] = (uint8_t)(block >> 8);
		iv[15] = (uint8_t)block;
		AES_encrypt(iv, stream, &aes);
		size_t chunk = length - offset;
		if (chunk > 16)
			chunk = 16;
		for (size_t i = 0; i < chunk; i++)
			data[offset + i] ^= stream[i];
		offset += chunk;
		block++;
	}
}

static void TGSrtpTag(const TGSrtpContext *ctx, const uint8_t *data,
                      size_t length, const uint8_t roc[4], uint8_t tag[10]) {
	uint8_t digest[EVP_MAX_MD_SIZE];
	unsigned int digestLength = 0;
	HMAC_CTX *hmac = HMAC_CTX_new();
	HMAC_Init_ex(hmac, ctx->authKey, sizeof(ctx->authKey), EVP_sha1(), NULL);
	HMAC_Update(hmac, data, length);
	HMAC_Update(hmac, roc, 4);
	HMAC_Final(hmac, digest, &digestLength);
	HMAC_CTX_free(hmac);
	memcpy(tag, digest, 10);
}

static int TGSrtpTagMatches(const TGSrtpContext *ctx, const uint8_t *data,
                            size_t length, const uint8_t roc[4],
                            const uint8_t *tag) {
	uint8_t expected[10];
	TGSrtpTag(ctx, data, length, roc, expected);
	uint8_t differs = 0;
	for (int i = 0; i < 10; i++)
		differs |= (uint8_t)(expected[i] ^ tag[i]);
	return differs == 0 ? 0 : -1;
}

/// RFC 3711 3.3.1: a sequence number far below the highest one belongs to the
/// next ROC. 32768 is the window that separates reordering from a wrap.
static uint32_t TGSrtpRocForSequence(const TGSrtpContext *ctx, uint16_t seq) {
	if (!ctx->haveHighest)
		return 0;
	if (seq < ctx->highestSeq && (uint16_t)(ctx->highestSeq - seq) > 32768)
		return ctx->roc + 1;
	return ctx->roc;
}

int TGSrtpProtect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                  size_t capacity, size_t *outLength) {
	if (!ctx || !packet || length < 12 || capacity < length + TGSrtpTagLength)
		return -1;

	uint16_t seq = ((uint16_t)packet[2] << 8) | packet[3];
	uint32_t ssrc = ((uint32_t)packet[8] << 24) | ((uint32_t)packet[9] << 16) |
	                ((uint32_t)packet[10] << 8) | packet[11];

	uint32_t roc = TGSrtpRocForSequence(ctx, seq);
	uint64_t index = ((uint64_t)roc << 16) | seq;

	uint8_t iv[16];
	TGSrtpIv(ctx, ssrc, index, iv);
	TGSrtpCtr(ctx, iv, packet + 12, length - 12);

	uint8_t rocBytes[4] = {
		(uint8_t)(roc >> 24), (uint8_t)(roc >> 16),
		(uint8_t)(roc >> 8), (uint8_t)roc,
	};
	uint8_t tag[10];
	TGSrtpTag(ctx, packet, length, rocBytes, tag);
	memcpy(packet + length, tag, 10);

	ctx->roc = roc;
	ctx->highestSeq = seq;
	ctx->haveHighest = 1;
	if (outLength)
		*outLength = length + TGSrtpTagLength;
	return 0;
}

int TGSrtpUnprotect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                    size_t *outLength) {
	if (!ctx || !packet || length < 12 + TGSrtpTagLength)
		return -1;

	uint16_t seq = ((uint16_t)packet[2] << 8) | packet[3];
	uint32_t ssrc = ((uint32_t)packet[8] << 24) | ((uint32_t)packet[9] << 16) |
	                ((uint32_t)packet[10] << 8) | packet[11];

	uint32_t roc = TGSrtpRocForSequence(ctx, seq);
	size_t plainLength = length - TGSrtpTagLength;

	// The tag is checked before anything is decrypted: a forged packet must
	// not be allowed to move the rollover counter.
	uint8_t rocBytes[4] = {
		(uint8_t)(roc >> 24), (uint8_t)(roc >> 16),
		(uint8_t)(roc >> 8), (uint8_t)roc,
	};
	if (TGSrtpTagMatches(ctx, packet, plainLength, rocBytes,
	                     packet + plainLength) != 0)
		return -1;

	uint64_t index = ((uint64_t)roc << 16) | seq;
	uint8_t iv[16];
	TGSrtpIv(ctx, ssrc, index, iv);
	TGSrtpCtr(ctx, iv, packet + 12, plainLength - 12);

	ctx->roc = roc;
	ctx->highestSeq = seq;
	ctx->haveHighest = 1;
	if (outLength)
		*outLength = plainLength;
	return 0;
}

int TGSrtcpProtect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                   size_t capacity, uint32_t index, size_t *outLength) {
	if (!ctx || !packet || length < 8 || capacity < length + 4 + TGSrtpTagLength)
		return -1;

	uint32_t ssrc = ((uint32_t)packet[4] << 24) | ((uint32_t)packet[5] << 16) |
	                ((uint32_t)packet[6] << 8) | packet[7];
	uint8_t iv[16];
	TGSrtpIv(ctx, ssrc, index, iv);
	TGSrtpCtr(ctx, iv, packet + 8, length - 8);

	uint32_t word = 0x80000000u | (index & 0x7FFFFFFFu);
	packet[length]     = (uint8_t)(word >> 24);
	packet[length + 1] = (uint8_t)(word >> 16);
	packet[length + 2] = (uint8_t)(word >> 8);
	packet[length + 3] = (uint8_t)word;

	uint8_t zero[4] = {0, 0, 0, 0};
	uint8_t tag[10];
	TGSrtpTag(ctx, packet, length + 4, zero, tag);
	memcpy(packet + length + 4, tag, 10);

	if (outLength)
		*outLength = length + 4 + TGSrtpTagLength;
	return 0;
}

int TGSrtcpUnprotect(TGSrtpContext *ctx, uint8_t *packet, size_t length,
                     size_t *outLength) {
	if (!ctx || !packet || length < 8 + 4 + TGSrtpTagLength)
		return -1;

	size_t plainLength = length - 4 - TGSrtpTagLength;
	const uint8_t *wordBytes = packet + plainLength;
	uint32_t word = ((uint32_t)wordBytes[0] << 24) | ((uint32_t)wordBytes[1] << 16) |
	                ((uint32_t)wordBytes[2] << 8) | wordBytes[3];
	if ((word & 0x80000000u) == 0)
		return -1;
	uint32_t index = word & 0x7FFFFFFFu;

	uint8_t zero[4] = {0, 0, 0, 0};
	if (TGSrtpTagMatches(ctx, packet, plainLength + 4, zero,
	                     packet + plainLength + 4) != 0)
		return -1;

	uint32_t ssrc = ((uint32_t)packet[4] << 24) | ((uint32_t)packet[5] << 16) |
	                ((uint32_t)packet[6] << 8) | packet[7];
	uint8_t iv[16];
	TGSrtpIv(ctx, ssrc, index, iv);
	TGSrtpCtr(ctx, iv, packet + 8, plainLength - 8);

	if (outLength)
		*outLength = plainLength;
	return 0;
}
