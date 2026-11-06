//
// TGCallVideoRtp.m - RFC 6184 RTP H.264 packetizer and depacketizer.
//
#import "TGCallVideoRtp.h"
#include <arpa/inet.h>

@implementation TGCallVideoRtpPacketizer

- (instancetype)initWithSsrc:(uint32_t)ssrc {
    self = [super init];
    if (self) {
        _ssrc = ssrc;
        _sequenceNumber = (uint16_t)arc4random_uniform(0xFFFF);
        _payloadType = TG_CALL_RTP_VIDEO_PAYLOAD_TYPE;
    }
    return self;
}

- (instancetype)init {
    return [self initWithSsrc:arc4random()];
}

- (NSData *)buildRtpHeaderWithMarker:(BOOL)marker timestamp:(uint32_t)timestamp {
    uint8_t hdr[12];
    hdr[0] = 0x80; // V=2, P=0, X=0, CC=0
    hdr[1] = (marker ? 0x80 : 0x00) | (_payloadType & 0x7F);

    uint16_t seq = htons(_sequenceNumber++);
    memcpy(hdr + 2, &seq, 2);

    uint32_t ts = htonl(timestamp);
    memcpy(hdr + 4, &ts, 4);

    uint32_t ssrc = htonl(_ssrc);
    memcpy(hdr + 8, &ssrc, 4);

    return [NSData dataWithBytes:hdr length:12];
}

- (NSArray<NSData *> *)packetizeNalUnit:(const uint8_t *)nalBytes
                                 length:(size_t)nalLength
                              timestamp:(uint32_t)timestamp
                              isLastNal:(BOOL)isLastNal {
    if (!nalBytes || nalLength == 0) {
        return @[];
    }

    // Skip start code if caller passed one (0x000001 or 0x00000001)
    if (nalLength >= 4 && nalBytes[0] == 0 && nalBytes[1] == 0 && nalBytes[2] == 0 && nalBytes[3] == 1) {
        nalBytes += 4;
        nalLength -= 4;
    } else if (nalLength >= 3 && nalBytes[0] == 0 && nalBytes[1] == 0 && nalBytes[2] == 1) {
        nalBytes += 3;
        nalLength -= 3;
    }

    if (nalLength == 0) return @[];

    // Case 1: Single NAL unit packet
    if (nalLength <= TG_CALL_RTP_MAX_PAYLOAD_SIZE) {
        NSMutableData *packet = [NSMutableData dataWithCapacity:12 + nalLength];
        [packet appendData:[self buildRtpHeaderWithMarker:isLastNal timestamp:timestamp]];
        [packet appendBytes:nalBytes length:nalLength];
        return @[packet];
    }

    // Case 2: FU-A Fragmentation Unit
    uint8_t origHeader = nalBytes[0];
    uint8_t origType = origHeader & 0x1F;
    const uint8_t *payloadPtr = nalBytes + 1;
    size_t payloadRemaining = nalLength - 1;

    size_t maxFuPayload = TG_CALL_RTP_MAX_PAYLOAD_SIZE - 2; // reserve 2 bytes for FU indicator & FU header
    NSMutableArray<NSData *> *packets = [NSMutableArray array];

    BOOL isFirst = YES;
    while (payloadRemaining > 0) {
        size_t chunkSize = (payloadRemaining > maxFuPayload) ? maxFuPayload : payloadRemaining;
        BOOL isLast = (payloadRemaining == chunkSize);

        uint8_t fuIndicator = (origHeader & 0xE0) | TGCallNalUnitTypeFU_A; // 28
        uint8_t fuHeader = origType;
        if (isFirst) fuHeader |= 0x80; // S bit
        if (isLast)  fuHeader |= 0x40; // E bit

        BOOL marker = (isLastNal && isLast);
        NSMutableData *packet = [NSMutableData dataWithCapacity:12 + 2 + chunkSize];
        [packet appendData:[self buildRtpHeaderWithMarker:marker timestamp:timestamp]];

        uint8_t fuBytes[2] = { fuIndicator, fuHeader };
        [packet appendBytes:fuBytes length:2];
        [packet appendBytes:payloadPtr length:chunkSize];

        [packets addObject:packet];

        payloadPtr += chunkSize;
        payloadRemaining -= chunkSize;
        isFirst = NO;
    }

    return packets;
}

- (NSData *)packetizeStapA:(NSArray<NSData *> *)nalUnits
                 timestamp:(uint32_t)timestamp
                 isLastNal:(BOOL)isLastNal {
    if (nalUnits.count == 0) return nil;

    uint8_t maxNri = 0;
    size_t totalPayloadSize = 1; // 1 byte STAP-A header
    for (NSData *nal in nalUnits) {
        if (nal.length == 0) continue;
        const uint8_t *b = (const uint8_t *)nal.bytes;
        uint8_t nri = b[0] & 0x60;
        if (nri > maxNri) maxNri = nri;
        totalPayloadSize += 2 + nal.length;
    }

    NSMutableData *packet = [NSMutableData dataWithCapacity:12 + totalPayloadSize];
    [packet appendData:[self buildRtpHeaderWithMarker:isLastNal timestamp:timestamp]];

    uint8_t stapAHeader = (maxNri & 0x60) | TGCallNalUnitTypeSTAP_A; // 24
    [packet appendBytes:&stapAHeader length:1];

    for (NSData *nal in nalUnits) {
        if (nal.length == 0) continue;
        uint16_t lenBE = htons((uint16_t)nal.length);
        [packet appendBytes:&lenBE length:2];
        [packet appendData:nal];
    }

    return packet;
}

- (NSArray<NSData *> *)packetizeAccessUnit:(NSArray<NSData *> *)nalUnits
                                 timestamp:(uint32_t)timestamp {
    NSMutableArray<NSData *> *allPackets = [NSMutableArray array];
    NSUInteger count = nalUnits.count;
    for (NSUInteger i = 0; i < count; i++) {
        NSData *nal = nalUnits[i];
        BOOL isLast = (i == count - 1);
        NSArray<NSData *> *pkts = [self packetizeNalUnit:(const uint8_t *)nal.bytes
                                                  length:nal.length
                                               timestamp:timestamp
                                               isLastNal:isLast];
        [allPackets addObjectsFromArray:pkts];
    }
    return allPackets;
}

@end


@interface TGCallVideoRtpDepacketizer () {
    NSMutableData *_fuBuffer;
    uint32_t _fuTimestamp;
    BOOL _fuInProgress;

    uint32_t _currentFrameTimestamp;
    NSMutableArray<NSData *> *_currentFrameNals;
    BOOL _currentFrameIsKeyframe;

    NSData *_cachedSps;
    NSData *_cachedPps;
    uint16_t _lastSeq;
    BOOL _hasLastSeq;
}
@end

@implementation TGCallVideoRtpDepacketizer

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

- (void)reset {
    _fuBuffer = [NSMutableData data];
    _fuInProgress = NO;
    _fuTimestamp = 0;
    _currentFrameTimestamp = 0;
    _currentFrameNals = [NSMutableArray array];
    _currentFrameIsKeyframe = NO;
    _cachedSps = nil;
    _cachedPps = nil;
    _hasLastSeq = NO;
}

- (void)flushFrame {
    if (_currentFrameNals.count == 0) return;

    // Build AVCC frame: 4-byte length prefix before each NAL unit
    size_t totalLen = 0;
    for (NSData *nal in _currentFrameNals) {
        totalLen += 4 + nal.length;
    }

    NSMutableData *avcc = [NSMutableData dataWithCapacity:totalLen];
    for (NSData *nal in _currentFrameNals) {
        uint32_t lenBE = htonl((uint32_t)nal.length);
        [avcc appendBytes:&lenBE length:4];
        [avcc appendData:nal];
    }

    if (self.onFrameReceived) {
        self.onFrameReceived(avcc, _currentFrameTimestamp, _currentFrameIsKeyframe, _cachedSps, _cachedPps);
    }

    [_currentFrameNals removeAllObjects];
    _currentFrameIsKeyframe = NO;
}

- (void)handleReceivedNal:(const uint8_t *)nalBytes length:(size_t)nalLength timestamp:(uint32_t)timestamp marker:(BOOL)marker {
    if (!nalBytes || nalLength == 0) return;

    if (_currentFrameNals.count > 0 && timestamp != _currentFrameTimestamp) {
        [self flushFrame];
    }
    _currentFrameTimestamp = timestamp;

    uint8_t nalType = nalBytes[0] & 0x1F;
    NSData *nalData = [NSData dataWithBytes:nalBytes length:nalLength];

    if (nalType == TGCallNalUnitTypeSPS) {
        _cachedSps = nalData;
    } else if (nalType == TGCallNalUnitTypePPS) {
        _cachedPps = nalData;
    } else if (nalType == TGCallNalUnitTypeSliceIDR) {
        _currentFrameIsKeyframe = YES;
    }

    [_currentFrameNals addObject:nalData];

    if (marker) {
        [self flushFrame];
    }
}

- (void)processRtpPacket:(const uint8_t *)bytes length:(size_t)length {
    if (!bytes || length < 12) return;

    // Check version == 2
    if ((bytes[0] >> 6) != 2) return;

    BOOL marker = (bytes[1] & 0x80) != 0;
    uint16_t seq = ((uint16_t)bytes[2] << 8) | bytes[3];
    uint32_t timestamp = ((uint32_t)bytes[4] << 24) | ((uint32_t)bytes[5] << 16) |
                         ((uint32_t)bytes[6] << 8)  | (uint32_t)bytes[7];

    uint8_t cc = bytes[0] & 0x0F;
    size_t headerLen = 12 + 4 * cc;
    if ((bytes[0] & 0x10) != 0 && length >= headerLen + 4) { // Extension header
        uint16_t extLen = ((uint16_t)bytes[headerLen + 2] << 8) | bytes[headerLen + 3];
        headerLen += 4 + 4 * extLen;
    }

    if (length <= headerLen) return;

    const uint8_t *payload = bytes + headerLen;
    size_t payloadLen = length - headerLen;

    _lastSeq = seq;
    _hasLastSeq = YES;

    uint8_t nalHeader = payload[0];
    uint8_t nalType = nalHeader & 0x1F;

    // 1. Single NAL unit packet (1..23)
    if (nalType >= 1 && nalType <= 23) {
        [self handleReceivedNal:payload length:payloadLen timestamp:timestamp marker:marker];
        return;
    }

    // 2. STAP-A aggregation packet (24)
    if (nalType == TGCallNalUnitTypeSTAP_A) {
        size_t offset = 1;
        while (offset + 2 <= payloadLen) {
            uint16_t nalSize = ((uint16_t)payload[offset] << 8) | payload[offset + 1];
            offset += 2;
            if (offset + nalSize > payloadLen) break;

            BOOL isLast = (offset + nalSize == payloadLen) && marker;
            [self handleReceivedNal:payload + offset length:nalSize timestamp:timestamp marker:isLast];
            offset += nalSize;
        }
        return;
    }

    // 3. FU-A fragmentation packet (28)
    if (nalType == TGCallNalUnitTypeFU_A) {
        if (payloadLen < 2) return;

        uint8_t fuIndicator = payload[0];
        uint8_t fuHeader = payload[1];
        BOOL isStart = (fuHeader & 0x80) != 0;
        BOOL isEnd   = (fuHeader & 0x40) != 0;
        uint8_t origType = fuHeader & 0x1F;
        uint8_t reconstructedHeader = (fuIndicator & 0xE0) | origType;

        const uint8_t *fuData = payload + 2;
        size_t fuDataLen = payloadLen - 2;

        if (isStart) {
            [_fuBuffer setLength:0];
            [_fuBuffer appendBytes:&reconstructedHeader length:1];
            [_fuBuffer appendBytes:fuData length:fuDataLen];
            _fuTimestamp = timestamp;
            _fuInProgress = YES;
        } else if (_fuInProgress && timestamp == _fuTimestamp) {
            [_fuBuffer appendBytes:fuData length:fuDataLen];
        }

        if (isEnd && _fuInProgress) {
            [self handleReceivedNal:(const uint8_t *)_fuBuffer.bytes
                             length:_fuBuffer.length
                          timestamp:_fuTimestamp
                             marker:marker];
            [_fuBuffer setLength:0];
            _fuInProgress = NO;
        }
    }
}

@end
