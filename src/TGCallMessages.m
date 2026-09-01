#import "TGCallMessages.h"

const uint8_t TGCallMessageCandidates = 1;
const uint8_t TGCallMessageVideoFormats = 2;
const uint8_t TGCallMessageMediaState = 4;
const uint8_t TGCallMessageAudioData  = 5;
const uint8_t TGCallMessageRemoteNetworkStatus = 10;

const uint8_t TGCallMessageAck = 0xFF;


static const uint8_t kEmptyId = 0xFE;
static const uint8_t kAckId   = 0xFF;

/// Everything here is big-endian, as rtc::ByteBufferWriter writes it.
static uint32_t TGReadU32(const uint8_t *bytes) {
	return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
		   ((uint32_t)bytes[2] << 8)  |  (uint32_t)bytes[3];
}

static void TGAppendU32(NSMutableData *data, uint32_t value) {
	uint8_t bytes[4] = {
		(uint8_t)(value >> 24), (uint8_t)(value >> 16),
		(uint8_t)(value >> 8),  (uint8_t)value
	};
	[data appendBytes:bytes length:4];
}

static void TGAppendString(NSMutableData *data, NSString *string) {
	NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
	TGAppendU32(data, (uint32_t)utf8.length);
	[data appendData:utf8];
}

@implementation TGCallMessages

+ (NSArray *)parsePacket:(NSData *)plaintext seq:(uint32_t)packetSeq {
	const uint8_t *bytes = (const uint8_t *)plaintext.bytes;
	NSUInteger length = plaintext.length;
	NSUInteger at = 0;
	NSMutableArray *messages = [NSMutableArray array];
	uint32_t currentSeq = packetSeq;

	while (at < length){
		uint8_t type = bytes[at];

		if (type == kEmptyId || type == kAckId){
			at += 1;
		} else {
			// A message body runs to the end of the packet unless another
			// sequence number follows, which only the message itself knows how
			// to find - so the tail is handed over whole and the caller reads
			// what it understands.
			[messages addObject:@{
				@"type" : @(type),
				@"seq"  : @(currentSeq),
				@"body" : [plaintext subdataWithRange:
						NSMakeRange(at + 1, length - at - 1)],
			}];
			return messages;
		}

		// Between messages comes the next sequence number.
		if (at + 4 > length)
			break;
		currentSeq = TGReadU32(bytes + at);
		at += 4;
	}
	return messages;
}

/// The transport channel really does carry several messages in one packet, each
/// under its own sequence number, and each of those - not the packet's - is what
/// an acknowledgement refers to. Walking the list needs every message's length,
/// so the fixed sizes are from tgcalls/Message.cpp; the three that carry a raw
/// buffer are length-prefixed unless the packet holds nothing else.
+ (NSArray *)parseMediaPacket:(NSData *)plaintext seq:(uint32_t)packetSeq {
	const uint8_t *bytes = (const uint8_t *)plaintext.bytes;
	NSUInteger length = plaintext.length;
	NSUInteger at = 0;
	uint32_t currentSeq = packetSeq;
	NSMutableArray *messages = [NSMutableArray array];

	while (at < length){
		uint8_t type = bytes[at++];
		NSUInteger bodySize = 0;

		switch (type){
			case kEmptyId:                    // nothing but a sequence number
			case kAckId:      bodySize = 0; break;
			case 4:                            // remote media state
			case 9:           bodySize = 1; break;   // remote battery is low
			case 10:          bodySize = 2; break;   // remote network status
			case 8:           bodySize = 4; break;   // video parameters
			case 5:                            // audio data
			case 6:                            // video data
			case 7: {                          // unstructured data
				if ([self seqIsSingleMessage:currentSeq]){
					bodySize = length - at;
				} else {
					if (at + 2 > length)
						return messages;
					bodySize = ((NSUInteger)bytes[at] << 8) | bytes[at + 1];
					at += 2;
				}
				break;
			}
			// An unknown type has an unknown length, so the rest of the packet
			// cannot be walked. What was already read still stands.
			default: return messages;
		}

		if (at + bodySize > length)
			return messages;

		// An acknowledgement is worth reporting: the sequence number in front of
		// it is the one being confirmed, and that is how we learn our own
		// messages arrived.
		if (type != kEmptyId)
			[messages addObject:@{
				@"type" : @(type),
				@"seq"  : @(currentSeq),
				@"body" : [plaintext subdataWithRange:NSMakeRange(at, bodySize)],
			}];
		at += bodySize;

		if (at + 4 > length)
			break;
		currentSeq = TGReadU32(bytes + at);
		at += 4;
	}
	return messages;
}

+ (NSData *)messageWithType:(uint8_t)type body:(NSData *)body {
	NSMutableData *packet = [NSMutableData data];
	[packet appendBytes:&type length:1];
	[packet appendData:body];
	return packet;
}

+ (BOOL)seqRequiresAck:(uint32_t)seq {
	return (seq & ((uint32_t)1 << 30)) != 0;
}

+ (BOOL)seqIsSingleMessage:(uint32_t)seq {
	return (seq & ((uint32_t)1 << 31)) != 0;
}

/// Two messages in one packet, so neither the single-message bit nor the
/// ack-request bit belongs on the sequence number carrying it.
+ (NSData *)ackForSeq:(uint32_t)seq {
	NSMutableData *packet = [NSMutableData data];
	uint8_t empty = kEmptyId, ack = kAckId;
	[packet appendBytes:&empty length:1];
	TGAppendU32(packet, seq);
	[packet appendBytes:&ack length:1];
	return packet;
}

+ (uint32_t)markSeq:(uint32_t)seq requiresAck:(BOOL)requiresAck {
	// A message that wants an acknowledgement cannot also claim to be the only
	// one in its packet, because it may be resent alongside others later.
	return requiresAck ? (seq | ((uint32_t)1 << 30))
					   : (seq | ((uint32_t)1 << 31));
}

/// Their own opening packet, byte for byte:
///   fe | 40000001 | 08 00000000 | 40000002 | 04 01
/// an empty message under the packet's sequence number, video parameters with
/// an aspect ratio of zero, then the media state - one byte, (video << 1) | audio.
+ (NSData *)mediaStateBundleWithVideoSeq:(uint32_t)videoSeq
								stateSeq:(uint32_t)stateSeq
							 audioActive:(BOOL)audioActive {
	NSMutableData *body = [NSMutableData data];
	[body appendBytes:&kEmptyId length:1];

	TGAppendU32(body, videoSeq);
	uint8_t videoParameters = 8;
	[body appendBytes:&videoParameters length:1];
	TGAppendU32(body, 0);            // aspect ratio, unknown and unused here

	TGAppendU32(body, stateSeq);
	uint8_t mediaState = 4;
	[body appendBytes:&mediaState length:1];
	uint8_t state = audioActive ? 1 : 0;
	[body appendBytes:&state length:1];

	return body;
}

+ (NSData *)candidatesBody:(NSArray *)candidates ufrag:(NSString *)ufrag pwd:(NSString *)pwd {
	NSMutableData *body = [NSMutableData data];
	uint8_t count = (uint8_t)candidates.count;
	[body appendBytes:&count length:1];
	for (NSString *candidate in candidates)
		TGAppendString(body, candidate);
	TGAppendString(body, ufrag);
	TGAppendString(body, pwd);
	return body;
}

+ (NSDictionary *)parseCandidates:(NSData *)body {
	const uint8_t *bytes = (const uint8_t *)body.bytes;
	NSUInteger length = body.length;
	NSUInteger at = 0;

	if (length < 1)
		return nil;
	uint8_t count = bytes[at++];

	NSMutableArray *candidates = [NSMutableArray array];
	for (uint8_t i = 0; i < count; i++){
		if (at + 4 > length)
			return nil;
		uint32_t size = TGReadU32(bytes + at);
		at += 4;
		if (at + size > length)
			return nil;
		NSString *candidate = [[NSString alloc]
				initWithBytes:bytes + at length:size encoding:NSUTF8StringEncoding];
		if (candidate)
			[candidates addObject:candidate];
		at += size;
	}

	// The ICE credentials follow the list, and they are what a connectivity
	// check has to be signed with.
	NSString *ufrag = nil, *pwd = nil;
	for (int i = 0; i < 2; i++){
		if (at + 4 > length)
			break;
		uint32_t size = TGReadU32(bytes + at);
		at += 4;
		if (at + size > length)
			break;
		NSString *value = [[NSString alloc]
				initWithBytes:bytes + at length:size encoding:NSUTF8StringEncoding];
		at += size;
		if (i == 0) ufrag = value; else pwd = value;
	}

	return @{
		@"candidates" : candidates,
		@"ufrag"      : ufrag ?: @"",
		@"pwd"        : pwd ?: @"",
	};
}

+ (NSData *)rtcpReceiverReportWithOurSSRC:(uint32_t)ourSSRC peerSSRC:(uint32_t)peerSSRC highestSeq:(uint32_t)highestSeq {
	uint8_t rtcp[32];
	memset(rtcp, 0, sizeof(rtcp));

	// Header: V=2, P=0, RC=1 (1 report block), PT=201 (Receiver Report), Length=7 (32 bytes total)
	rtcp[0] = 0x81;
	rtcp[1] = 201;
	rtcp[2] = 0x00;
	rtcp[3] = 0x07;

	// Our SSRC (sender of RTCP report)
	rtcp[4] = (uint8_t)(ourSSRC >> 24);
	rtcp[5] = (uint8_t)(ourSSRC >> 16);
	rtcp[6] = (uint8_t)(ourSSRC >> 8);
	rtcp[7] = (uint8_t)(ourSSRC);

	// Report Block 1: Peer SSRC
	rtcp[8]  = (uint8_t)(peerSSRC >> 24);
	rtcp[9]  = (uint8_t)(peerSSRC >> 16);
	rtcp[10] = (uint8_t)(peerSSRC >> 8);
	rtcp[11] = (uint8_t)(peerSSRC);

	// Fraction lost (0) & Cumulative lost (0)
	rtcp[12] = 0; rtcp[13] = 0; rtcp[14] = 0; rtcp[15] = 0;

	// Extended highest sequence number received
	rtcp[16] = (uint8_t)(highestSeq >> 24);
	rtcp[17] = (uint8_t)(highestSeq >> 16);
	rtcp[18] = (uint8_t)(highestSeq >> 8);
	rtcp[19] = (uint8_t)(highestSeq);

	// Jitter (0) at bytes 20-23
	// LSR (0) at bytes 24-27
	// DLSR (0) at bytes 28-31

	return [NSData dataWithBytes:rtcp length:sizeof(rtcp)];
}

+ (NSData *)remoteNetworkStatusBody {
	uint8_t bytes[2] = { 0, 0 };
	return [NSData dataWithBytes:bytes length:2];
}

@end


// vim:ft=objc
