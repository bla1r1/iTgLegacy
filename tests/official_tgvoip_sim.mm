// tests/official_tgvoip_sim.mm — VoIP call simulation using Telegram's official libtgvoip.
//
// Demonstrates and tests how the official Telegram VoIP library (VoIPController)
// operates end-to-end:
//   1. Crypto hooks initialization (OpenSSL AES-IGE + AES-CTR + SHA1 + SHA256)
//   2. MockReflector relaying packets based on 16-byte peer tags
//   3. Endpoint negotiation (UDP_RELAY over 127.0.0.1)
//   4. Full call lifecycle: STATE_WAIT_INIT -> STATE_WAIT_INIT_ACK -> STATE_ESTABLISHED
//   5. Continuous audio streaming via audio callbacks (generating test tone and measuring RMS)
//   6. Querying VoIPController::GetDebugString() for bitrate, loss, ping and jitter

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <chrono>
#include <thread>
#include <atomic>

#include <openssl/rand.h>
#include <openssl/sha.h>
#include <openssl/aes.h>
#include <openssl/modes.h>

#include "libtgvoip/VoIPController.h"
#include "libtgvoip/tests/MockReflector.h"

using namespace tgvoip;

// Static definition of VoIPController crypto hooks
CryptoFunctions VoIPController::crypto;

namespace tgvoip {
namespace audio {
    AudioUnitIO::AudioUnitIO(std::string in, std::string out) {}
    AudioUnitIO::~AudioUnitIO() {}
    void AudioUnitIO::EnableInput(bool) {}
    void AudioUnitIO::EnableOutput(bool) {}
    AudioInput* AudioUnitIO::GetInput() { return nullptr; }
    AudioOutput* AudioUnitIO::GetOutput() { return nullptr; }
    void AudioUnitIO::SetDuckingEnabled(bool) {}
}
namespace video {
    std::vector<uint32_t> VideoSource::GetAvailableEncoders() { return {}; }
    std::vector<uint32_t> VideoRenderer::GetAvailableDecoders() { return {}; }
    int VideoRenderer::GetMaximumResolution() { return 0; }
}
}

// Crypto hooks implemented with OpenSSL
static void TGRandBytes(uint8_t *buffer, size_t length) {
    RAND_bytes(buffer, (int)length);
}

static void TGSha1(uint8_t *msg, size_t length, uint8_t *output) {
    SHA1(msg, length, output);
}

static void TGSha256(uint8_t *msg, size_t length, uint8_t *output) {
    SHA256(msg, length, output);
}

static void TGAesIgeEncrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY akey;
    AES_set_encrypt_key(key, 32 * 8, &akey);
    AES_ige_encrypt(in, out, length, &akey, iv, AES_ENCRYPT);
}

static void TGAesIgeDecrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY akey;
    AES_set_decrypt_key(key, 32 * 8, &akey);
    AES_ige_encrypt(in, out, length, &akey, iv, AES_DECRYPT);
}

static void TGAesCtrEncrypt(uint8_t *inout, size_t length, uint8_t *key, uint8_t *iv, uint8_t *ecount, uint32_t *num) {
    AES_KEY akey;
    AES_set_encrypt_key(key, 32 * 8, &akey);
    CRYPTO_ctr128_encrypt(inout, inout, length, &akey, iv, ecount, num, (block128_f)AES_encrypt);
}

static void TGAesCbcEncrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY akey;
    AES_set_encrypt_key(key, 256, &akey);
    AES_cbc_encrypt(in, out, length, &akey, iv, AES_ENCRYPT);
}

static void TGAesCbcDecrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY akey;
    AES_set_decrypt_key(key, 256, &akey);
    AES_cbc_encrypt(in, out, length, &akey, iv, AES_DECRYPT);
}

static void initCryptoHooks() {
    VoIPController::crypto.rand_bytes      = TGRandBytes;
    VoIPController::crypto.sha1            = TGSha1;
    VoIPController::crypto.sha256          = TGSha256;
    VoIPController::crypto.aes_ige_encrypt = TGAesIgeEncrypt;
    VoIPController::crypto.aes_ige_decrypt = TGAesIgeDecrypt;
    VoIPController::crypto.aes_ctr_encrypt = TGAesCtrEncrypt;
    VoIPController::crypto.aes_cbc_encrypt = TGAesCbcEncrypt;
    VoIPController::crypto.aes_cbc_decrypt = TGAesCbcDecrypt;
}

static const char *stateToString(int state) {
    switch (state) {
        case STATE_WAIT_INIT:     return "WAIT_INIT";
        case STATE_WAIT_INIT_ACK: return "WAIT_INIT_ACK";
        case STATE_ESTABLISHED:   return "ESTABLISHED";
        case STATE_FAILED:        return "FAILED";
        case STATE_RECONNECTING:  return "RECONNECTING";
        default:                  return "UNKNOWN";
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        double duration = 3.0;
        uint16_t port = 10330;

        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
                duration = atof(argv[++i]);
            } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
                port = (uint16_t)atoi(argv[++i]);
            }
        }

        fprintf(stdout, "\n══════════════════════════════════════════════════════════════════\n");
        fprintf(stdout, "     Telegram Official libtgvoip VoIPController Simulation       \n");
        fprintf(stdout, "══════════════════════════════════════════════════════════════════\n");
        fprintf(stdout, "Using libtgvoip version: %s\n", VoIPController::GetVersion());
        fprintf(stdout, "Config: duration=%.1fs, reflector_port=%u\n\n", duration, port);

        // 1. Initialize crypto hooks
        initCryptoHooks();

        // 2. Start mock reflector on 127.0.0.1
        test::MockReflector reflector("127.0.0.1", port);
        reflector.Start();
        fprintf(stdout, "[+] Official MockReflector running on 127.0.0.1:%u\n", port);

        // 3. Generate peer tags (16 bytes each, matching Telegram's reflector tag protocol)
        std::array<std::array<uint8_t, 16>, 2> peerTags = test::MockReflector::GeneratePeerTags();

        // 4. Instantiate two VoIPControllers
        VoIPController *caller = new VoIPController();
        VoIPController *callee = new VoIPController();

        // Setup endpoints
        IPv4Address localhost("127.0.0.1");
        IPv6Address emptyV6;
        std::vector<Endpoint> callerEndpoints;
        callerEndpoints.push_back(Endpoint(1, port, localhost, emptyV6, Endpoint::Type::UDP_RELAY, peerTags[0].data()));
        caller->SetRemoteEndpoints(callerEndpoints, false /* allowP2P */, 76 /* maxLayer */);

        std::vector<Endpoint> calleeEndpoints;
        calleeEndpoints.push_back(Endpoint(1, port, localhost, emptyV6, Endpoint::Type::UDP_RELAY, peerTags[1].data()));
        callee->SetRemoteEndpoints(calleeEndpoints, false /* allowP2P */, 76 /* maxLayer */);

        // 5. Generate and set 256-byte call encryption key
        char encryptionKey[256];
        arc4random_buf(encryptionKey, sizeof(encryptionKey));
        caller->SetEncryptionKey(encryptionKey, true  /* isOutgoing */);
        callee->SetEncryptionKey(encryptionKey, false /* isOutgoing */);

        // 6. Configure controllers
        VoIPController::Config config;
        config.enableNS = false;
        config.enableAEC = false;
        config.enableAGC = false;
        config.enableCallUpgrade = false;
        config.initTimeout = 4.0;
        config.recvTimeout = 4.0;
        caller->SetConfig(config);
        callee->SetConfig(config);

        // 7. Audio callbacks: caller produces 1kHz sine wave, callee measures received audio
        std::atomic<uint64_t> samplesGenerated{0};
        std::atomic<uint64_t> samplesReceived{0};
        std::atomic<double> audioEnergySum{0.0};

        caller->SetAudioDataCallbacks([&](int16_t *data, size_t len) {
            float freq = 1000.0f;
            float sampleRate = 48000.0f;
            uint64_t offset = samplesGenerated.fetch_add(len);
            for (size_t i = 0; i < len; i++) {
                float t = (float)(offset + i) / sampleRate;
                data[i] = (int16_t)(sinf(2.0f * M_PI * freq * t) * 10000.0f);
            }
        }, [](int16_t *data, size_t len) {},
        [](int16_t *data, size_t len) {});

        callee->SetAudioDataCallbacks([](int16_t *data, size_t len) {
            // callee mic silence
            memset(data, 0, len * sizeof(int16_t));
        }, [&](int16_t *data, size_t len) {
            samplesReceived.fetch_add(len);
            double sumSq = 0;
            for (size_t i = 0; i < len; i++) {
                sumSq += (double)data[i] * (double)data[i];
            }
            audioEnergySum.store(audioEnergySum.load() + sumSq);
        }, [](int16_t *data, size_t len) {});

        // 8. Start & Connect both sides
        fprintf(stdout, "[*] Starting Caller & Callee VoIPControllers...\n");
        caller->Start();
        callee->Start();
        caller->Connect();
        callee->Connect();

        // 9. Wait for STATE_ESTABLISHED
        auto startTime = std::chrono::steady_clock::now();
        bool established = false;
        while (std::chrono::duration<double>(std::chrono::steady_clock::now() - startTime).count() < 3.0) {
            int s1 = caller->GetConnectionState();
            int s2 = callee->GetConnectionState();
            if (s1 == STATE_ESTABLISHED && s2 == STATE_ESTABLISHED) {
                established = true;
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        fprintf(stdout, "[*] Caller state: %s, Callee state: %s\n",
                stateToString(caller->GetConnectionState()),
                stateToString(callee->GetConnectionState()));

        if (!established) {
            fprintf(stderr, "[-] Error: Failed to reach STATE_ESTABLISHED within 3 seconds\n");
            caller->Stop();
            callee->Stop();
            delete caller;
            delete callee;
            reflector.Stop();
            return 1;
        }

        fprintf(stdout, "[+] Official VoIPController ESTABLISHED over MockReflector!\n");

        // 10. Run audio streaming loop for specified duration
        fprintf(stdout, "[*] Streaming audio through official Opus encoder & MTProto reflector for %.1fs...\n", duration);
        auto streamStart = std::chrono::steady_clock::now();
        while (std::chrono::duration<double>(std::chrono::steady_clock::now() - streamStart).count() < duration) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            std::string debugStr = caller->GetDebugString();
            if (!debugStr.empty()) {
                fprintf(stdout, "    [Live Stats] %s\n", debugStr.c_str());
            }
        }

        uint64_t gen = samplesGenerated.load();
        uint64_t rec = samplesReceived.load();
        double rms = rec > 0 ? sqrt(audioEnergySum.load() / (double)rec) : 0.0;

        fprintf(stdout, "\n════════════════════════ Session Summary ═════════════════════════\n");
        fprintf(stdout, "  Official libtgvoip Call:\n");
        fprintf(stdout, "    - Caller Connection State: %s\n", stateToString(caller->GetConnectionState()));
        fprintf(stdout, "    - Callee Connection State: %s\n", stateToString(callee->GetConnectionState()));
        fprintf(stdout, "    - Audio Samples Sent:      %llu (%.2f seconds at 48kHz)\n",
                gen, (double)gen / 48000.0);
        fprintf(stdout, "    - Audio Samples Received:  %llu (%.2f seconds at 48kHz)\n",
                rec, (double)rec / 48000.0);
        fprintf(stdout, "    - Decoded Audio RMS Level: %.1f\n", rms);
        fprintf(stdout, "══════════════════════════════════════════════════════════════════\n");

        BOOL success = YES;
        if (caller->GetConnectionState() != STATE_ESTABLISHED ||
            callee->GetConnectionState() != STATE_ESTABLISHED) {
            fprintf(stderr, "[-] FAIL: Final state is not ESTABLISHED\n");
            success = NO;
        }
        if (rec < 48000) {
            fprintf(stderr, "[-] FAIL: Too few audio samples received (%llu)\n", rec);
            success = NO;
        }
        if (rms < 100.0) {
            fprintf(stderr, "[-] FAIL: Decoded audio energy is too low (silence)\n");
            success = NO;
        }

        // Teardown
        caller->Stop();
        callee->Stop();
        delete caller;
        delete callee;
        reflector.Stop();

        if (success) {
            fprintf(stdout, ">>> RESULT: SUCCESS - Official Telegram VoIPController PASSED! <<<\n\n");
            return 0;
        } else {
            fprintf(stderr, ">>> RESULT: FAILED - Official VoIPController verification failed <<<\n\n");
            return 1;
        }
    }
}
