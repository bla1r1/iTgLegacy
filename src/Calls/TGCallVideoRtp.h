//
// TGCallVideoRtp.h - RFC 6184 RTP H.264 packetizer and depacketizer.
//
#import <Foundation/Foundation.h>

#define TG_CALL_RTP_VIDEO_PAYLOAD_TYPE 96
#define TG_CALL_RTP_MAX_PAYLOAD_SIZE 950

typedef NS_ENUM(uint8_t, TGCallNalUnitType) {
    TGCallNalUnitTypeUnspecified = 0,
    TGCallNalUnitTypeSliceNonIDR = 1,
    TGCallNalUnitTypeSliceDataA  = 2,
    TGCallNalUnitTypeSliceDataB  = 3,
    TGCallNalUnitTypeSliceDataC  = 4,
    TGCallNalUnitTypeSliceIDR    = 5,
    TGCallNalUnitTypeSEI         = 6,
    TGCallNalUnitTypeSPS         = 7,
    TGCallNalUnitTypePPS         = 8,
    TGCallNalUnitTypeAUD         = 9,
    TGCallNalUnitTypeSTAP_A      = 24,
    TGCallNalUnitTypeFU_A        = 28,
};

@interface TGCallVideoRtpPacketizer : NSObject

@property (nonatomic, assign) uint32_t ssrc;
@property (nonatomic, assign) uint16_t sequenceNumber;
@property (nonatomic, assign) uint8_t payloadType;

- (instancetype)initWithSsrc:(uint32_t)ssrc;

/// Packetizes a single NAL unit (with or without FU-A fragmentation).
/// If isLastNal is YES, the last generated RTP packet will have the marker bit set.
- (NSArray<NSData *> *)packetizeNalUnit:(const uint8_t *)nalBytes
                                 length:(size_t)nalLength
                              timestamp:(uint32_t)timestamp
                              isLastNal:(BOOL)isLastNal;

/// Packetizes multiple NAL units into a STAP-A aggregated packet.
- (NSData *)packetizeStapA:(NSArray<NSData *> *)nalUnits
                 timestamp:(uint32_t)timestamp
                 isLastNal:(BOOL)isLastNal;

/// Convenience method to packetize an access unit (array of NAL units).
/// SPS and PPS are sent first (or in STAP-A), slices are sent as Single/FU-A.
- (NSArray<NSData *> *)packetizeAccessUnit:(NSArray<NSData *> *)nalUnits
                                 timestamp:(uint32_t)timestamp;

@end

/// Depacketizer & jitter buffer for incoming RTP video packets.
@interface TGCallVideoRtpDepacketizer : NSObject

@property (nonatomic, copy) void (^onFrameReceived)(NSData *avccFrame, uint32_t timestamp, BOOL isKeyframe, NSData *sps, NSData *pps);

- (void)reset;

/// Feed one raw RTP packet (starting with 12-byte RTP header).
- (void)processRtpPacket:(const uint8_t *)bytes length:(size_t)length;

@end
