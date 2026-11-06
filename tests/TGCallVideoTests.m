//
// TGCallVideoTests.m — unit tests for RTP H.264 packetizer, depacketizer, signaling & media state.
//
#import <Foundation/Foundation.h>
#import "TGTestRunner.h"
#import "TGCallVideoRtp.h"
#import "TGCallMessages.h"
#import "TGCapabilities.h"
#include <arpa/inet.h>

@interface TGCallVideoTests : XCTestCase
@end

@implementation TGCallVideoTests

- (void)testVideoFormatsSignalling_EncodeAndDecode {
    // 1. Valid H.264 video formats body with 480p
    NSData *body480 = [TGCallMessages videoFormatsBodyWithMaxResolution:TGCallVideoResolution480p];
    XCTAssertNotNil(body480);
    XCTAssertGreaterThanOrEqual((int)body480.length, 11);

    NSDictionary *parsed480 = [TGCallMessages parseVideoFormats:body480];
    XCTAssertTrue([parsed480[@"supported"] boolValue], @"H.264 should be supported");
    XCTAssertEqual([parsed480[@"maxResolution"] intValue], (int)TGCallVideoResolution480p);
    XCTAssertTrue([parsed480[@"decoders"] containsObject:@(TGCallCodecH264)]);
    XCTAssertTrue([parsed480[@"encoders"] containsObject:@(TGCallCodecH264)]);

    // 2. Empty video formats body (maxResolution == 0)
    NSData *emptyBody = [TGCallMessages videoFormatsBodyWithMaxResolution:0];
    XCTAssertEqual((int)emptyBody.length, 2);
    const uint8_t *eb = (const uint8_t *)emptyBody.bytes;
    XCTAssertEqual(eb[0], 0);
    XCTAssertEqual(eb[1], 0);

    NSDictionary *parsedEmpty = [TGCallMessages parseVideoFormats:emptyBody];
    XCTAssertFalse([parsedEmpty[@"supported"] boolValue]);
    XCTAssertEqual([parsedEmpty[@"maxResolution"] intValue], 0);

    // 3. Nil / short body handling
    NSDictionary *parsedNil = [TGCallMessages parseVideoFormats:nil];
    XCTAssertFalse([parsedNil[@"supported"] boolValue]);
}

- (void)testMediaStateVideoBit {
    // 1. Audio active, video inactive -> state byte == 1
    NSData *bundle1 = [TGCallMessages mediaStateBundleWithVideoSeq:100
                                                          stateSeq:101
                                                       audioActive:YES
                                                       videoActive:NO];
    const uint8_t *b1 = (const uint8_t *)bundle1.bytes;
    // Bundle layout:
    // 0: 0xFE (empty)
    // 1..4: videoSeq
    // 5: 8 (videoParameters)
    // 6..9: 0
    // 10..13: stateSeq
    // 14: 4 (mediaState)
    // 15: state byte
    XCTAssertGreaterThanOrEqual((int)bundle1.length, 16);
    XCTAssertEqual(b1[14], TGCallMessageMediaState);
    XCTAssertEqual(b1[15], 1, @"audio active only");

    // 2. Audio active, video active -> state byte == 5 (1 | (2 << 1) where VideoState::Active == 2)
    NSData *bundle2 = [TGCallMessages mediaStateBundleWithVideoSeq:100
                                                          stateSeq:101
                                                       audioActive:YES
                                                       videoActive:YES];
    const uint8_t *b2 = (const uint8_t *)bundle2.bytes;
    XCTAssertEqual(b2[15], 5, @"audio and video active matches tgcalls 0x05");

    // 3. Audio muted, video active -> state byte == 4 (2 << 1)
    NSData *bundle3 = [TGCallMessages mediaStateBundleWithVideoSeq:100
                                                          stateSeq:101
                                                       audioActive:NO
                                                       videoActive:YES];
    const uint8_t *b3 = (const uint8_t *)bundle3.bytes;
    XCTAssertEqual(b3[15], 4, @"video active only");

    // 4. Backward compatibility method (3 args)
    NSData *bundle4 = [TGCallMessages mediaStateBundleWithVideoSeq:100
                                                          stateSeq:101
                                                       audioActive:YES];
    const uint8_t *b4 = (const uint8_t *)bundle4.bytes;
    XCTAssertEqual(b4[15], 1, @"legacy method defaults video to inactive");

    // 5. MediaState video detection: 0x01 is audio-only, 0x05 / 0x07 has video active
    uint8_t peerDefaultAudioState = 0x01;
    BOOL peerAudioOnly = ((peerDefaultAudioState & 2) != 0) || ((peerDefaultAudioState & 4) != 0);
    XCTAssertFalse(peerAudioOnly, @"0x01 is audio-only in official Telegram");

    uint8_t peerVideoState = 0x05;
    BOOL peerVideoActive = ((peerVideoState & 2) != 0) || ((peerVideoState & 4) != 0);
    XCTAssertTrue(peerVideoActive, @"0x05 has video active");

    uint8_t peerVideoState2 = 0x07;
    BOOL peerVideoActive2 = ((peerVideoState2 & 2) != 0) || ((peerVideoState2 & 4) != 0);
    XCTAssertTrue(peerVideoActive2, @"0x07 has video active");
}

- (void)testRtpSingleNalPacketizationAndDepacketization {
    uint32_t ssrc = 0x11223344;
    uint32_t ts = 90000;
    TGCallVideoRtpPacketizer *packetizer = [[TGCallVideoRtpPacketizer alloc] initWithSsrc:ssrc];
    packetizer.sequenceNumber = 1000;

    // Create a 200-byte NAL unit (type 1 non-IDR slice)
    NSMutableData *nal = [NSMutableData dataWithLength:200];
    uint8_t *bytes = (uint8_t *)nal.mutableBytes;
    bytes[0] = 0x21; // NRI=01, Type=1
    for (int i = 1; i < 200; i++) {
        bytes[i] = (uint8_t)(i & 0xFF);
    }

    NSArray<NSData *> *packets = [packetizer packetizeNalUnit:(const uint8_t *)nal.bytes
                                                       length:nal.length
                                                    timestamp:ts
                                                    isLastNal:YES];
    XCTAssertEqual((int)packets.count, 1, @"Single NAL <= MTU should produce exactly 1 packet");

    NSData *rtpPkt = packets[0];
    XCTAssertEqual((int)rtpPkt.length, 12 + 200);

    const uint8_t *rtpHdr = (const uint8_t *)rtpPkt.bytes;
    XCTAssertEqual(rtpHdr[0], 0x80); // V=2
    XCTAssertEqual(rtpHdr[1], (0x80 | 96)); // Marker=1, PT=96
    uint16_t seq = ((uint16_t)rtpHdr[2] << 8) | rtpHdr[3];
    XCTAssertEqual(seq, 1000);
    uint32_t readTs = ((uint32_t)rtpHdr[4] << 24) | ((uint32_t)rtpHdr[5] << 16) |
                      ((uint32_t)rtpHdr[6] << 8)  | rtpHdr[7];
    XCTAssertEqual(readTs, ts);
    uint32_t readSsrc = ((uint32_t)rtpHdr[8] << 24) | ((uint32_t)rtpHdr[9] << 16) |
                        ((uint32_t)rtpHdr[10] << 8) | rtpHdr[11];
    XCTAssertEqual(readSsrc, ssrc);

    // Depacketize and verify round-trip
    TGCallVideoRtpDepacketizer *depacketizer = [[TGCallVideoRtpDepacketizer alloc] init];
    __block BOOL received = NO;
    __block NSData *receivedFrame = nil;
    __block uint32_t receivedTs = 0;
    __block BOOL receivedKeyframe = YES;

    depacketizer.onFrameReceived = ^(NSData *avccFrame, uint32_t timestamp, BOOL isKeyframe, NSData *sps, NSData *pps) {
        received = YES;
        receivedFrame = avccFrame;
        receivedTs = timestamp;
        receivedKeyframe = isKeyframe;
    };

    [depacketizer processRtpPacket:(const uint8_t *)rtpPkt.bytes length:rtpPkt.length];

    XCTAssertTrue(received, @"depacketizer should emit frame on marker bit");
    XCTAssertEqual(receivedTs, ts);
    XCTAssertFalse(receivedKeyframe, @"NAL type 1 is not keyframe");

    // AVCC format: 4-byte length + payload
    XCTAssertEqual((int)receivedFrame.length, 4 + 200);
    const uint8_t *fb = (const uint8_t *)receivedFrame.bytes;
    uint32_t nalLen = ((uint32_t)fb[0] << 24) | ((uint32_t)fb[1] << 16) |
                      ((uint32_t)fb[2] << 8)  | fb[3];
    XCTAssertEqual(nalLen, 200);
    XCTAssertEqual(memcmp(fb + 4, nal.bytes, 200), 0, @"payload bytes must match exactly");
}

- (void)testRtpFuAPacketizationAndDepacketization {
    uint32_t ssrc = 0x55667788;
    uint32_t ts = 180000;
    TGCallVideoRtpPacketizer *packetizer = [[TGCallVideoRtpPacketizer alloc] initWithSsrc:ssrc];
    packetizer.sequenceNumber = 2000;

    // Create a 2500-byte NAL unit (type 5 IDR slice)
    // MAX_PAYLOAD is 950, so 2500 - 1 = 2499 bytes of payload will be split into:
    // chunk 1: 948 bytes (FU-A S=1)
    // chunk 2: 948 bytes (FU-A S=0, E=0)
    // chunk 3: 603 bytes (FU-A E=1, marker=1)
    NSMutableData *nal = [NSMutableData dataWithLength:2500];
    uint8_t *bytes = (uint8_t *)nal.mutableBytes;
    bytes[0] = 0x65; // NRI=11, Type=5 (IDR)
    for (int i = 1; i < 2500; i++) {
        bytes[i] = (uint8_t)((i * 37) & 0xFF);
    }

    NSArray<NSData *> *packets = [packetizer packetizeNalUnit:(const uint8_t *)nal.bytes
                                                       length:nal.length
                                                    timestamp:ts
                                                    isLastNal:YES];
    XCTAssertEqual((int)packets.count, 3, @"2500-byte NAL should be fragmented into 3 FU-A packets");

    // Inspect first packet
    const uint8_t *p1 = (const uint8_t *)packets[0].bytes;
    XCTAssertEqual(p1[1] & 0x80, 0, @"First FU-A packet must NOT have RTP marker");
    XCTAssertEqual(p1[12] & 0x1F, 28, @"Indicator type must be FU-A (28)");
    XCTAssertEqual(p1[13] & 0x80, 0x80, @"First FU-A must have Start bit (S=1)");
    XCTAssertEqual(p1[13] & 0x40, 0, @"First FU-A must not have End bit (E=0)");
    XCTAssertEqual(p1[13] & 0x1F, 5, @"Reconstructed type must be 5 (IDR)");

    // Inspect intermediate packet
    const uint8_t *p2 = (const uint8_t *)packets[1].bytes;
    XCTAssertEqual(p2[13] & 0xC0, 0, @"Middle FU-A must have S=0 and E=0");

    // Inspect last packet
    const uint8_t *p3 = (const uint8_t *)packets[2].bytes;
    XCTAssertEqual(p3[1] & 0x80, 0x80, @"Last packet of frame must have RTP marker");
    XCTAssertEqual(p3[13] & 0x80, 0, @"Last FU-A must have S=0");
    XCTAssertEqual(p3[13] & 0x40, 0x40, @"Last FU-A must have End bit (E=1)");

    // Feed to depacketizer
    TGCallVideoRtpDepacketizer *depacketizer = [[TGCallVideoRtpDepacketizer alloc] init];
    __block BOOL received = NO;
    __block NSData *receivedFrame = nil;
    __block BOOL receivedKeyframe = NO;

    depacketizer.onFrameReceived = ^(NSData *avccFrame, uint32_t timestamp, BOOL isKeyframe, NSData *sps, NSData *pps) {
        received = YES;
        receivedFrame = avccFrame;
        receivedKeyframe = isKeyframe;
    };

    for (NSData *pkt in packets) {
        [depacketizer processRtpPacket:(const uint8_t *)pkt.bytes length:pkt.length];
    }

    XCTAssertTrue(received, @"depacketizer should emit reassembled frame");
    XCTAssertTrue(receivedKeyframe, @"NAL type 5 must be marked as keyframe");
    XCTAssertEqual((int)receivedFrame.length, 4 + 2500);

    const uint8_t *fb = (const uint8_t *)receivedFrame.bytes;
    XCTAssertEqual(memcmp(fb + 4, nal.bytes, 2500), 0, @"reassembled FU-A payload must match original 2500 bytes");
}

- (void)testRtpStapAPacketizationAndDepacketization {
    uint32_t ssrc = 0xAABBCCDD;
    uint32_t ts = 270000;
    TGCallVideoRtpPacketizer *packetizer = [[TGCallVideoRtpPacketizer alloc] initWithSsrc:ssrc];

    // SPS (type 7)
    uint8_t spsBytes[] = { 0x67, 0x42, 0x00, 0x1E, 0x96, 0x54, 0x05, 0x01, 0xE9, 0x7B };
    NSData *sps = [NSData dataWithBytes:spsBytes length:sizeof(spsBytes)];

    // PPS (type 8)
    uint8_t ppsBytes[] = { 0x68, 0xCE, 0x38, 0x80 };
    NSData *pps = [NSData dataWithBytes:ppsBytes length:sizeof(ppsBytes)];

    NSData *stapPkt = [packetizer packetizeStapA:@[sps, pps] timestamp:ts isLastNal:YES];
    XCTAssertNotNil(stapPkt);
    XCTAssertEqual((int)stapPkt.length, 12 + 1 + (2 + (int)sizeof(spsBytes)) + (2 + (int)sizeof(ppsBytes)));

    const uint8_t *b = (const uint8_t *)stapPkt.bytes;
    XCTAssertEqual(b[12] & 0x1F, TGCallNalUnitTypeSTAP_A);

    TGCallVideoRtpDepacketizer *depacketizer = [[TGCallVideoRtpDepacketizer alloc] init];
    __block BOOL received = NO;
    __block NSData *receivedSps = nil;
    __block NSData *receivedPps = nil;

    depacketizer.onFrameReceived = ^(NSData *avccFrame, uint32_t timestamp, BOOL isKeyframe, NSData *spsOut, NSData *ppsOut) {
        received = YES;
        receivedSps = spsOut;
        receivedPps = ppsOut;
    };

    [depacketizer processRtpPacket:(const uint8_t *)stapPkt.bytes length:stapPkt.length];

    XCTAssertTrue(received);
    XCTAssertNotNil(receivedSps);
    XCTAssertNotNil(receivedPps);
    XCTAssertEqualObjects(receivedSps, sps);
    XCTAssertEqualObjects(receivedPps, pps);
}

- (void)testAccessUnitPacketizationAndDepacketization {
    uint32_t ssrc = 0x1234;
    uint32_t ts = 360000;
    TGCallVideoRtpPacketizer *packetizer = [[TGCallVideoRtpPacketizer alloc] initWithSsrc:ssrc];

    uint8_t spsBytes[] = { 0x67, 0x42, 0x00, 0x1E };
    NSData *sps = [NSData dataWithBytes:spsBytes length:sizeof(spsBytes)];

    uint8_t ppsBytes[] = { 0x68, 0xCE, 0x38 };
    NSData *pps = [NSData dataWithBytes:ppsBytes length:sizeof(ppsBytes)];

    NSMutableData *idrSlice = [NSMutableData dataWithLength:1500];
    uint8_t *idrPtr = (uint8_t *)idrSlice.mutableBytes;
    idrPtr[0] = 0x65;
    for (int i = 1; i < 1500; i++) idrPtr[i] = (uint8_t)(i ^ 0xAA);

    NSArray<NSData *> *packets = [packetizer packetizeAccessUnit:@[sps, pps, idrSlice] timestamp:ts];
    XCTAssertGreaterThan((int)packets.count, 2);

    TGCallVideoRtpDepacketizer *depacketizer = [[TGCallVideoRtpDepacketizer alloc] init];
    __block BOOL received = NO;
    __block NSData *outSps = nil, *outPps = nil;
    __block BOOL outKeyframe = NO;
    __block NSData *outFrame = nil;

    depacketizer.onFrameReceived = ^(NSData *avccFrame, uint32_t timestamp, BOOL isKeyframe, NSData *spsO, NSData *ppsO) {
        received = YES;
        outSps = spsO;
        outPps = ppsO;
        outKeyframe = isKeyframe;
        outFrame = avccFrame;
    };

    for (NSData *pkt in packets) {
        [depacketizer processRtpPacket:(const uint8_t *)pkt.bytes length:pkt.length];
    }

    XCTAssertTrue(received);
    XCTAssertTrue(outKeyframe);
    XCTAssertEqualObjects(outSps, sps);
    XCTAssertEqualObjects(outPps, pps);
    XCTAssertEqual((int)outFrame.length, (4 + 4) + (4 + 3) + (4 + 1500));
}

- (void)testDepacketizerRejectsGarbage {
    TGCallVideoRtpDepacketizer *depacketizer = [[TGCallVideoRtpDepacketizer alloc] init];
    __block BOOL received = NO;
    depacketizer.onFrameReceived = ^(NSData *avccFrame, uint32_t timestamp, BOOL isKeyframe, NSData *sps, NSData *pps) {
        received = YES;
    };

    // 1. Packet too short (< 12 bytes)
    uint8_t shortPkt[8] = { 0 };
    [depacketizer processRtpPacket:shortPkt length:sizeof(shortPkt)];
    XCTAssertFalse(received);

    // 2. Wrong RTP version (V=1 instead of 2)
    uint8_t wrongVerPkt[20] = { 0x40, 0x60, 0 };
    [depacketizer processRtpPacket:wrongVerPkt length:sizeof(wrongVerPkt)];
    XCTAssertFalse(received);
}

// Video calls are dev-only while they are unfinished: the dev build (the one
// the host suite compiles, TG_DEV=1) follows the hardware, and the "This
// device" row says so. scripts/check_release.sh checks the release side.
- (void)testVideoCallsFollowHardwareInDevBuilds {
    XCTAssertEqual([TGCapabilities canEncodeVideoCall], [TGCapabilities hasVideoCallHardware]);
    BOOL listed = NO;
    for (TGCapability *row in [TGCapabilities all]) {
        if (![row.name isEqualToString:@"Video calls"]) continue;
        listed = YES;
        XCTAssertEqual(row.available, [TGCapabilities hasVideoCallHardware]);
        XCTAssertTrue([row.requirement rangeOfString:@"dev builds only"].location != NSNotFound);
    }
    XCTAssertTrue(listed);
}

@end
