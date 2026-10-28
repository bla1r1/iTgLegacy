// tests/call_sim.mm — Command-line simulation harness for VoIP call stack.
//
// Simulates an end-to-end VoIP call session between LegacyTG (Phone) and a
// WebRTC/tgcalls peer (Computer / Remote Phone) over local UDP sockets.
//
// Exercises:
//   1. Call establishment & cryptographic key exchange (AES-CTR-256 + SHA256)
//   2. ICE STUN connectivity checks & USE-CANDIDATE nomination
//   3. Reflector framing & multi-candidate tag verification
//   4. Media state handshake bundle (RemoteMediaState, VideoParameters, RemoteNetworkStatus)
//   5. Mutual ACKs
//   6. Bidirectional Opus audio streaming (Phone -> Computer and Computer -> Phone)
//
// Usage:
//   ./build/tests/call_sim [--duration <seconds>] [--fps <rate>] [--fuzz-cell] [--verbose]

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#import "TGCall.h"
#import "TGCallAudioEngine.h"
#import "TGCallCrypto.h"
#import "TGCallStun.h"
#import "TGCallMessages.h"
#import "TGCallReflector.h"
#import "TGCallPeer.h"
#import "TGCallTestHelpers.h"
#import "TGClient.h"

// Private interface access for harness instrumentation
@interface TGCall ()
@property (nonatomic, assign) TGCallState state;
@property (nonatomic, strong) TGCallAudioEngine *audioEngine;
@property (nonatomic, assign) uint32_t currentSenderTag;
@property (nonatomic, assign) uint32_t nominatedSenderTag;
@property (nonatomic, assign) uint32_t verifiedMediaTag;
- (void)teardown;
- (void)sendOutgoingAudioFrame:(NSData *)opusFrame;
@end

@interface TGCall (TestSupport)
@property (nonatomic, readonly) NSString *localUfrag;
@property (nonatomic, readonly) NSString *localPwd;
@property (nonatomic, assign) BOOL audioFramingProven;
@property (nonatomic, readonly) TGCallReflector *reflector;
@end

@interface TGCallAudioEngine (Testing)
+ (NSArray<NSData *> *)receivedFrames;
+ (void)resetReceivedFrames;
@end

static void printUsage(const char *prog) {
    fprintf(stdout,
            "Usage: %s [options]\n"
            "Options:\n"
            "  --duration <sec>   Call duration in seconds (default: 2.0)\n"
            "  --fps <rate>       Audio frames per second (default: 50 = 20ms)\n"
            "  --fuzz-cell        Simulate secondary cellular interface STUN race\n"
            "  --verbose          Enable verbose packet trace\n"
            "  --help             Show this help\n",
            prog);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        double duration = 2.0;
        int fps = 50;
        BOOL fuzzCell = NO;
        BOOL verbose = NO;

        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
                duration = atof(argv[++i]);
            } else if (strcmp(argv[i], "--fps") == 0 && i + 1 < argc) {
                fps = atoi(argv[++i]);
            } else if (strcmp(argv[i], "--fuzz-cell") == 0) {
                fuzzCell = YES;
            } else if (strcmp(argv[i], "--verbose") == 0) {
                verbose = YES;
            } else if (strcmp(argv[i], "--help") == 0) {
                printUsage(argv[0]);
                return 0;
            }
        }

        fprintf(stdout, "\n══════════════════════════════════════════════════════════════════\n");
        fprintf(stdout, "          iTgLegacy VoIP Call Simulator & Test Harness            \n");
        fprintf(stdout, "══════════════════════════════════════════════════════════════════\n");
        fprintf(stdout, "Config: duration=%.1fs, audio_rate=%d fps (20ms frames), fuzz_cell=%s\n\n",
                duration, fps, fuzzCell ? "YES" : "NO");

        // 1. Generate 256-byte call key
        uint8_t keyBytes[256];
        arc4random_buf(keyBytes, sizeof(keyBytes));
        NSData *callKey = [NSData dataWithBytes:keyBytes length:sizeof(keyBytes)];

        // 2. Start Party B (Peer simulator listening on local UDP port)
        TGCallPeer *peer = [[TGCallPeer alloc] init];
        peer.callKey = callKey;
        peer.isOutgoing = NO; // Peer is callee, Phone is caller
        if (![peer start]) {
            fprintf(stderr, "[-] Error: Failed to start TGCallPeer UDP socket\n");
            return 1;
        }
        fprintf(stdout, "[+] Party B (Peer / Computer) listening on 127.0.0.1:%u (tag: %08x)\n",
                peer.listenPort, peer.localTag);

        __block uint32_t peerFramesReceived = 0;
        peer.onAudioFrame = ^(NSData *frame) {
            peerFramesReceived++;
            if (verbose && (peerFramesReceived == 1 || peerFramesReceived % 25 == 0)) {
                fprintf(stdout, "    [Peer] << Audio frame #%u (%lu bytes Opus)\n",
                        peerFramesReceived, (unsigned long)frame.length);
            }
        };

        // 3. Initialize Party A (Phone / LegacyTG)
        [TGCallAudioEngine resetReceivedFrames];
        [[TGCall shared] teardown];

        uint8_t peerTagBytes[16];
        arc4random_buf(peerTagBytes, sizeof(peerTagBytes));
        NSString *peerTagB64 = [[NSData dataWithBytes:peerTagBytes length:16]
                                base64EncodedStringWithOptions:0];
        NSString *keyB64 = [callKey base64EncodedStringWithOptions:0];

        NSDictionary *readyUpdate = @{
            @"@type"      : @"call",
            @"id"         : @(101),
            @"user_id"    : @(4242LL),
            @"is_outgoing": @(YES),
            @"state"      : @{
                @"@type"          : @"callStateReady",
                @"encryption_key" : keyB64,
                @"servers"        : @[@{
                    @"ip_address" : @"127.0.0.1",
                    @"port"       : @(peer.listenPort),
                    @"type"       : @{
                        @"@type"    : @"callServerTypeTelegramReflector",
                        @"peer_tag" : peerTagB64,
                    },
                }],
                @"protocol"       : @{
                    @"@type"            : @"callProtocol",
                    @"library_versions" : @[@"3.0.0", @"9.0.0"],
                },
            },
        };

        fprintf(stdout, "[+] Party A (Phone / LegacyTG) initializing call 101...\n");
        [[TGCall shared] handleUpdate:readyUpdate];

        // 4. Feed peer candidates & credentials to Phone
        NSData *candidatesBody = [TGCallMessages
            candidatesBody:@[[NSString stringWithFormat:
                @"candidate:1 1 udp 2130706431 reflector-1-%u.reflector %u "
                @"typ relay generation 0 ufrag %@ network-id 9 network-cost 50",
                peer.localTag, peer.listenPort, peer.ufrag]]
            ufrag:peer.ufrag
            pwd:peer.pwd];

        NSData *candidatesMsg = [TGCallMessages messageWithType:TGCallMessageCandidates
                                                           body:candidatesBody];

        NSMutableData *encSignaling = [NSMutableData dataWithLength:candidatesMsg.length + 32];
        int encSize = TGCallEncryptPacket((const uint8_t *)callKey.bytes,
                                          0 /* from incoming side */,
                                          1 /* signaling */,
                                          (const uint8_t *)candidatesMsg.bytes,
                                          candidatesMsg.length,
                                          1,
                                          (uint8_t *)encSignaling.mutableBytes);
        if (encSize > 0) {
            encSignaling.length = encSize;
            [[TGCall shared] handleSignalingData:encSignaling];
        }

        // 5. Wait for ICE and call establishment
        fprintf(stdout, "[*] Negotiating ICE candidates & reflector transport...\n");
        NSDate *start = [NSDate date];
        BOOL established = NO;
        while ([[NSDate date] timeIntervalSinceDate:start] < 3.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            if ([TGCall shared].state == TGCallStateEstablished) {
                established = YES;
                break;
            }
        }

        if (!established) {
            fprintf(stderr, "[-] Error: Call failed to reach Established state within 3.0s\n");
            [peer stop];
            return 1;
        }

        fprintf(stdout, "[+] Call ESTABLISHED! Verified media tag: %08x\n",
                [TGCall shared].verifiedMediaTag ?: [TGCall shared].currentSenderTag);

        // 6. Run bidirectional audio streaming loop
        fprintf(stdout, "[*] Streaming audio bidirectionally for %.1f seconds...\n", duration);

        uint32_t phoneFramesSent = 0;
        uint32_t peerFramesSent = 0;
        NSTimeInterval interval = 1.0 / (double)fps;
        NSDate *loopStart = [NSDate date];
        NSDate *lastFrameTime = [NSDate dateWithTimeIntervalSince1970:0];

        // Synthetic 20ms Opus frame header (TOC=0xF8, configuration Opus SILK/CELT)
        uint8_t sampleOpus[] = { 0xF8, 0xFF, 0xFE, 0x01, 0x02, 0x03, 0x04, 0x05 };
        NSData *opusData = [NSData dataWithBytes:sampleOpus length:sizeof(sampleOpus)];

        while ([[NSDate date] timeIntervalSinceDate:loopStart] < duration) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];

            if ([[NSDate date] timeIntervalSinceDate:lastFrameTime] >= interval) {
                lastFrameTime = [NSDate date];

                // Phone -> Peer: Send audio frame
                phoneFramesSent++;
                [[TGCall shared] sendOutgoingAudioFrame:opusData];

                // Peer -> Phone: Send audio frame
                peerFramesSent++;
                NSData *peerAudioPkt = [peer encryptedAudioPacketWithOpusFrame:opusData
                                                                           seq:peerFramesSent
                                                                    requiresAck:NO];
                if (peerAudioPkt) {
                    [peer sendReflectorPayload:peerAudioPkt];
                }

                // Optional: fuzz cellular interface race condition
                if (fuzzCell && phoneFramesSent == 15) {
                    fprintf(stdout, "    [Fuzz] Injecting competing USE-CANDIDATE check from secondary tag...\n");
                    // Send check from different tag
                    uint32_t fakeCellTag = 0xDEADBEEF;
                    NSData *req = [TGCallStun bindingRequestWithUsername:[NSString stringWithFormat:@"%@:%@", peer.ufrag, [TGCall shared].localUfrag]
                                                                password:[TGCall shared].localPwd
                                                              tieBreaker:12345
                                                            useCandidate:YES];
                    NSMutableData *cellPacket = [NSMutableData data];
                    uint8_t zeros[12] = { 0 };
                    [cellPacket appendBytes:zeros length:12];
                    uint32_t dest = [TGCall shared].reflector.localTag;
                    [cellPacket appendBytes:&dest length:4];
                    [cellPacket appendBytes:&fakeCellTag length:4];
                    uint32_t sz = OSSwapHostToBigInt32((uint32_t)req.length);
                    [cellPacket appendBytes:&sz length:4];
                    [cellPacket appendData:req];
                    [peer sendRawToLastReflector:cellPacket];
                }
            }
        }

        // Allow final in-flight packets to settle
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

        uint32_t phoneFramesReceived = (uint32_t)[TGCallAudioEngine receivedFrames].count;

        fprintf(stdout, "\n════════════════════════ Session Summary ═════════════════════════\n");
        fprintf(stdout, "  Phone (Party A):\n");
        fprintf(stdout, "    - Sent audio frames:     %u\n", phoneFramesSent);
        fprintf(stdout, "    - Received audio frames: %u\n", phoneFramesReceived);
        fprintf(stdout, "  Peer (Party B):\n");
        fprintf(stdout, "    - Sent audio frames:     %u\n", peerFramesSent);
        fprintf(stdout, "    - Received audio frames: %u\n", peerFramesReceived);
        fprintf(stdout, "  Signaling & ICE Verification:\n");
        fprintf(stdout, "    - STUN requests parsed:  %u\n", peer.stunRequestsReceived);
        fprintf(stdout, "    - ACKs exchanged:        %u\n", peer.acksReceived);
        fprintf(stdout, "    - MediaState received:   %u\n", peer.mediaStateMessagesReceived);
        fprintf(stdout, "    - Decrypt failures:      %u\n", peer.decryptFailures);
        fprintf(stdout, "══════════════════════════════════════════════════════════════════\n");

        BOOL success = YES;
        if (peerFramesReceived < phoneFramesSent * 0.9) {
            fprintf(stderr, "[-] FAIL: Peer received too few audio frames (%u / %u)\n",
                    peerFramesReceived, phoneFramesSent);
            success = NO;
        }
        if (phoneFramesReceived < peerFramesSent * 0.9) {
            fprintf(stderr, "[-] FAIL: Phone received too few audio frames (%u / %u)\n",
                    phoneFramesReceived, peerFramesSent);
            success = NO;
        }
        if (peer.decryptFailures > 0) {
            fprintf(stderr, "[-] FAIL: Decrypt failures occurred (%u)\n", peer.decryptFailures);
            success = NO;
        }

        // Teardown
        [[TGCall shared] hangUp];
        [peer stop];

        if (success) {
            fprintf(stdout, ">>> RESULT: SUCCESS - All VoIP media paths, encryption and framing PASSED! <<<\n\n");
            return 0;
        } else {
            fprintf(stderr, ">>> RESULT: FAILED - Media delivery dropped or failed verification <<<\n\n");
            return 1;
        }
    }
}
