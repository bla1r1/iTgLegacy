//
// TGCallV2Signaling - the tgcalls 9.0.0 (SignalingProtocolVersion::V2)
// signalling envelope and JSON messages.
//
// A decrypted packet is [seq][element] repeated. One element is either a raw
// message (0x7F, 4-byte length, JSON), an empty message (0xFE) or an ack
// (0xFF, whose preceding seq is the one being acknowledged).
//
#ifndef TG_CALL_V2_SIGNALING_H
#define TG_CALL_V2_SIGNALING_H

#import <Foundation/Foundation.h>

typedef struct {
	uint8_t type;
	uint32_t seq;
	const uint8_t *body;
	size_t bodyLength;
} TGV2Slice;

#ifdef __cplusplus
extern "C" {
#endif
/// Parses every element, not just the first. Returns the number written.
size_t TGV2ParsePlaintext(const uint8_t *bytes, size_t length,
                          uint32_t packetSeq, TGV2Slice *out, size_t maxSlices);
#ifdef __cplusplus
}
#endif

@interface TGCallV2Signaling : NSObject

/// 0x7F + length + compact JSON.
+ (NSData *)messageWithJSONObject:(NSDictionary *)json;

/// An ack-only packet body: [0xFE][acked seq][0xFF]. The caller gives the
/// packet its own bare sequence number.
+ (NSData *)ackForSeq:(uint32_t)seq;

+ (NSData *)initialSetupWithUfrag:(NSString *)ufrag
                              pwd:(NSString *)pwd
                      fingerprint:(NSString *)fingerprint
                            setup:(NSString *)setup;

/// Our own send-only audio offer.
+ (NSData *)offerWithExchangeId:(NSString *)exchangeId ssrc:(uint32_t)ssrc;

/// The answer to their offer. It must echo their ssrc and exchangeId, or the
/// peer builds no outgoing audio channel and stays silent.
+ (NSData *)answerWithExchangeId:(NSString *)exchangeId ssrc:(uint32_t)ssrc;

+ (NSData *)candidatesWithStrings:(NSArray *)candidates;

@end

#endif
