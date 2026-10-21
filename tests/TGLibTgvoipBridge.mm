// TGLibTgvoipBridge.mm — calls the C++ hooks that TGCall.mm defines.
#import "TGLibTgvoipBridge.h"

#include "libtgvoip/VoIPController.h"
#include "libtgvoip/video/VideoSource.h"
#include "libtgvoip/video/VideoRenderer.h"

#include <stdlib.h>
#include <string.h>

using namespace tgvoip;

@implementation TGLibTgvoipBridge

+ (BOOL)cryptoInstalled {
    CryptoFunctions &crypto = VoIPController::crypto;
    return crypto.rand_bytes && crypto.sha1 && crypto.sha256 &&
           crypto.aes_ige_encrypt && crypto.aes_ige_decrypt &&
           crypto.aes_ctr_encrypt &&
           crypto.aes_cbc_encrypt && crypto.aes_cbc_decrypt;
}

+ (NSData *)randomBytesOfLength:(NSUInteger)length {
    if (!VoIPController::crypto.rand_bytes || length == 0)
        return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    VoIPController::crypto.rand_bytes((uint8_t *)data.mutableBytes, length);
    return data;
}

+ (NSData *)sha1OfData:(NSData *)data {
    if (!VoIPController::crypto.sha1)
        return nil;
    uint8_t digest[20];
    VoIPController::crypto.sha1((uint8_t *)data.bytes, data.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

+ (NSData *)sha256OfData:(NSData *)data {
    if (!VoIPController::crypto.sha256)
        return nil;
    uint8_t digest[32];
    VoIPController::crypto.sha256((uint8_t *)data.bytes, data.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

+ (NSData *)igeRoundTrip:(NSData *)data key:(NSData *)key iv:(NSData *)iv {
    if (!VoIPController::crypto.aes_ige_encrypt ||
        !VoIPController::crypto.aes_ige_decrypt ||
        data.length == 0 || data.length % 16 != 0 ||
        key.length < 32 || iv.length < 32)
        return nil;

    size_t length = data.length;
    uint8_t *encrypted = (uint8_t *)malloc(length);
    uint8_t *plain = (uint8_t *)malloc(length);
    uint8_t encryptIV[32], decryptIV[32];
    memcpy(encryptIV, iv.bytes, sizeof(encryptIV));
    memcpy(decryptIV, iv.bytes, sizeof(decryptIV));

    VoIPController::crypto.aes_ige_encrypt((uint8_t *)data.bytes, encrypted,
                                           length, (uint8_t *)key.bytes, encryptIV);
    VoIPController::crypto.aes_ige_decrypt(encrypted, plain, length,
                                           (uint8_t *)key.bytes, decryptIV);

    NSData *result = [NSData dataWithBytes:plain length:length];
    free(encrypted);
    free(plain);
    return result;
}

+ (NSData *)cbcRoundTrip:(NSData *)data key:(NSData *)key iv:(NSData *)iv {
    if (!VoIPController::crypto.aes_cbc_encrypt ||
        !VoIPController::crypto.aes_cbc_decrypt ||
        data.length == 0 || data.length % 16 != 0 ||
        key.length < 32 || iv.length < 16)
        return nil;

    size_t length = data.length;
    uint8_t *encrypted = (uint8_t *)malloc(length);
    uint8_t *plain = (uint8_t *)malloc(length);
    uint8_t encryptIV[16], decryptIV[16];
    memcpy(encryptIV, iv.bytes, sizeof(encryptIV));
    memcpy(decryptIV, iv.bytes, sizeof(decryptIV));

    VoIPController::crypto.aes_cbc_encrypt((uint8_t *)data.bytes, encrypted,
                                           length, (uint8_t *)key.bytes, encryptIV);
    VoIPController::crypto.aes_cbc_decrypt(encrypted, plain, length,
                                           (uint8_t *)key.bytes, decryptIV);

    NSData *result = [NSData dataWithBytes:plain length:length];
    free(encrypted);
    free(plain);
    return result;
}

+ (NSData *)ctrRoundTrip:(NSData *)data key:(NSData *)key iv:(NSData *)iv {
    if (!VoIPController::crypto.aes_ctr_encrypt ||
        data.length == 0 || key.length < 32 || iv.length < 16)
        return nil;

    size_t length = data.length;
    uint8_t *buffer = (uint8_t *)malloc(length);
    memcpy(buffer, data.bytes, length);

    uint8_t encryptIV[16], decryptIV[16];
    uint8_t encryptCount[16] = {0}, decryptCount[16] = {0};
    uint32_t encryptNum = 0, decryptNum = 0;
    memcpy(encryptIV, iv.bytes, sizeof(encryptIV));
    memcpy(decryptIV, iv.bytes, sizeof(decryptIV));

    VoIPController::crypto.aes_ctr_encrypt(buffer, length, (uint8_t *)key.bytes,
                                           encryptIV, encryptCount, &encryptNum);
    VoIPController::crypto.aes_ctr_encrypt(buffer, length, (uint8_t *)key.bytes,
                                           decryptIV, decryptCount, &decryptNum);

    NSData *result = [NSData dataWithBytes:buffer length:length];
    free(buffer);
    return result;
}

+ (NSUInteger)availableEncoderCount {
    return video::VideoSource::GetAvailableEncoders().size();
}

+ (NSUInteger)availableDecoderCount {
    return video::VideoRenderer::GetAvailableDecoders().size();
}

+ (int)maximumResolution {
    return video::VideoRenderer::GetMaximumResolution();
}

@end
