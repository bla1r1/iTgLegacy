//
// TGCallMessages - message framing and packet parsing for VoIP calls.
//
#import <Foundation/Foundation.h>

extern const uint8_t TGCallMessageCandidates;   // 1
extern const uint8_t TGCallMessageVideoFormats; // 2
extern const uint8_t TGCallMessageMediaState;   // 4
extern const uint8_t TGCallMessageAudioData;    // 5
extern const uint8_t TGCallMessageRemoteNetworkStatus; // 10
extern const uint8_t TGCallMessageAck;          // 0xFF, confirms the seq before it


@interface TGCallMessages : NSObject

// Split a decrypted packet into messages.
+ (NSArray *)parsePacket:(NSData *)plaintext seq:(uint32_t)packetSeq;

// Parse messages from media packet.
+ (NSArray *)parseMediaPacket:(NSData *)plaintext seq:(uint32_t)packetSeq;

// Build ACK for message seq.
+ (NSData *)ackForSeq:(uint32_t)seq;

// Check if sequence number requests ACK.
+ (BOOL)seqRequiresAck:(uint32_t)seq;

// Check if packet holds single message.
+ (BOOL)seqIsSingleMessage:(uint32_t)seq;

// Parse candidates and credentials.
+ (NSDictionary *)parseCandidates:(NSData *)body;

// Frame message with type.
+ (NSData *)messageWithType:(uint8_t)type body:(NSData *)body;

// Mark sequence number with flags.
+ (uint32_t)markSeq:(uint32_t)seq requiresAck:(BOOL)requiresAck;

// Opening media state bundle.
+ (NSData *)mediaStateBundleWithVideoSeq:(uint32_t)videoSeq
								stateSeq:(uint32_t)stateSeq
							 audioActive:(BOOL)audioActive;

// Candidates message body.
+ (NSData *)candidatesBody:(NSArray *)candidates ufrag:(NSString *)ufrag pwd:(NSString *)pwd;

// RTCP Receiver Report packet (PT=201).
+ (NSData *)rtcpReceiverReportWithOurSSRC:(uint32_t)ourSSRC peerSSRC:(uint32_t)peerSSRC highestSeq:(uint32_t)highestSeq;

// Remote network status body.
+ (NSData *)remoteNetworkStatusBody;

@end

