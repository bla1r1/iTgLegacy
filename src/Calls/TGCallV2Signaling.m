#import "TGCallV2Signaling.h"

#include <string.h>

static uint32_t TGReadU32(const uint8_t *bytes) {
	return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
	       ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
}

size_t TGV2ParsePlaintext(const uint8_t *bytes, size_t length,
                          uint32_t packetSeq, TGV2Slice *out, size_t maxSlices) {
	size_t at = 0, count = 0;
	uint32_t currentSeq = packetSeq;
	while (at < length && count < maxSlices){
		uint8_t type = bytes[at++];
		const uint8_t *body = NULL;
		size_t bodyLength = 0;
		if (type == 0x7F){
			if (at + 4 > length)
				break;
			bodyLength = TGReadU32(bytes + at);
			at += 4;
			if (at + bodyLength > length)
				break;
			body = bytes + at;
			at += bodyLength;
		} else if (type == 0xFE || type == 0xFF){
			// An empty message carries nothing; an ack names its target in the
			// sequence number in front of it.
		} else {
			break;
		}
		out[count].type = type;
		out[count].seq = currentSeq;
		out[count].body = body;
		out[count].bodyLength = bodyLength;
		count++;
		if (at + 4 > length)
			break;
		currentSeq = TGReadU32(bytes + at);
		at += 4;
	}
	return count;
}

@implementation TGCallV2Signaling

+ (NSData *)messageWithJSONObject:(NSDictionary *)json {
	NSData *payload = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
	if (!payload)
		return nil;
	NSMutableData *out = [NSMutableData dataWithCapacity:payload.length + 5];
	uint8_t header[5];
	header[0] = 0x7F;
	uint32_t length = (uint32_t)payload.length;
	header[1] = (uint8_t)(length >> 24);
	header[2] = (uint8_t)(length >> 16);
	header[3] = (uint8_t)(length >> 8);
	header[4] = (uint8_t)length;
	[out appendBytes:header length:5];
	[out appendData:payload];
	return out;
}

+ (NSData *)ackForSeq:(uint32_t)seq {
	uint8_t bytes[6] = {
		0xFE,
		(uint8_t)(seq >> 24), (uint8_t)(seq >> 16),
		(uint8_t)(seq >> 8), (uint8_t)seq,
		0xFF,
	};
	return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

+ (NSData *)initialSetupWithUfrag:(NSString *)ufrag
                              pwd:(NSString *)pwd
                      fingerprint:(NSString *)fingerprint
                            setup:(NSString *)setup {
	NSDictionary *json = @{
		@"@type" : @"InitialSetup",
		@"fingerprints" : @[@{
			@"fingerprint" : fingerprint ?: @"",
			@"hash" : @"sha-256",
			@"setup" : setup ?: @"actpass",
		}],
		@"pwd" : pwd ?: @"",
		@"renomination" : @YES,
		@"ufrag" : ufrag ?: @"",
	};
	return [self messageWithJSONObject:json];
}

/// Audio only. Omitting rtpExtensions is deliberate: the peer then sends bare
/// RTP and does not expect transport-cc feedback from us.
+ (NSDictionary *)audioContentWithSsrc:(uint32_t)ssrc {
	return @{
		@"type" : @"audio",
		@"ssrc" : [NSString stringWithFormat:@"%u", ssrc],
		@"payloadTypes" : @[@{
			@"id" : @111,
			@"name" : @"opus",
			@"clockrate" : @48000,
			@"channels" : @2,
		}],
	};
}

+ (NSData *)offerWithExchangeId:(NSString *)exchangeId ssrc:(uint32_t)ssrc {
	return [self messageWithJSONObject:@{
		@"@type" : @"NegotiateChannels",
		@"contents" : @[[self audioContentWithSsrc:ssrc]],
		@"exchangeId" : exchangeId ?: @"",
	}];
}

+ (NSData *)answerWithExchangeId:(NSString *)exchangeId ssrc:(uint32_t)ssrc {
	return [self messageWithJSONObject:@{
		@"@type" : @"NegotiateChannels",
		@"contents" : @[[self audioContentWithSsrc:ssrc]],
		@"exchangeId" : exchangeId ?: @"",
	}];
}

+ (NSData *)candidatesWithStrings:(NSArray *)candidates {
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:candidates.count];
	for (NSString *candidate in candidates)
		[items addObject:@{ @"sdpString" : candidate }];
	return [self messageWithJSONObject:@{
		@"@type" : @"Candidates",
		@"candidates" : items,
	}];
}

@end
