#import "TGCall.h"
#import "TGClient.h"
#import "TGCallReflector.h"
#import "TGCallMessages.h"
#import "TGCallIce.h"
#import "TGCallStun.h"
#include "TGCallCrypto.h"
#import <AVFoundation/AVFoundation.h>

#import "TGCallAudioEngine.h"

#include "libtgvoip/VoIPController.h"
#include <openssl/aes.h>
#include <openssl/modes.h>
#include <openssl/rand.h>
#include <openssl/sha.h>

#include "libtgvoip/video/VideoSource.h"
#include "libtgvoip/video/VideoRenderer.h"

using namespace tgvoip;

// With TGVOIP_USE_CUSTOM_CRYPTO the library declares this and leaves defining
// it to whoever links it.
namespace tgvoip {
	CryptoFunctions VoIPController::crypto;
}

// This build carries no video. VoIPController asks what the platform can do
// before it offers anything, and an empty answer is the honest one.
namespace tgvoip { namespace video {
	std::vector<uint32_t> VideoSource::GetAvailableEncoders() { return {}; }
	std::vector<uint32_t> VideoRenderer::GetAvailableDecoders() { return {}; }
	int VideoRenderer::GetMaximumResolution() { return 0; }
}}

#pragma mark - crypto

// libtgvoip is built with TGVOIP_USE_CUSTOM_CRYPTO, which means it ships no
// crypto of its own and expects these filled in before any controller runs.
// OpenSSL is already in the build for TDLib.

static void TGRandBytes(uint8_t *buffer, size_t length) {
	RAND_bytes(buffer, (int)length);
}

static void TGSha1(uint8_t *msg, size_t length, uint8_t *output) {
	SHA1(msg, length, output);
}

static void TGSha256(uint8_t *msg, size_t length, uint8_t *output) {
	SHA256(msg, length, output);
}

static void TGAesIgeEncrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_encrypt_key(key, 32 * 8, &akey);
	AES_ige_encrypt(in, out, length, &akey, iv, AES_ENCRYPT);
}

static void TGAesIgeDecrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_decrypt_key(key, 32 * 8, &akey);
	AES_ige_encrypt(in, out, length, &akey, iv, AES_DECRYPT);
}

static void TGAesCtrEncrypt(uint8_t *inout, size_t length, uint8_t *key,
							uint8_t *iv, uint8_t *ecount, uint32_t *num) {
	AES_KEY akey;
	AES_set_encrypt_key(key, 32 * 8, &akey);
	CRYPTO_ctr128_encrypt(inout, inout, length, &akey, iv, ecount, num,
						  (block128_f)AES_encrypt);
}

static void TGAesCbcEncrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_encrypt_key(key, 256, &akey);
	AES_cbc_encrypt(in, out, length, &akey, iv, AES_ENCRYPT);
}

static void TGAesCbcDecrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_decrypt_key(key, 256, &akey);
	AES_cbc_encrypt(in, out, length, &akey, iv, AES_DECRYPT);
}

static void TGInstallCrypto(void) {
	static BOOL installed = NO;
	if (installed)
		return;
	installed = YES;
	VoIPController::crypto.rand_bytes      = TGRandBytes;
	VoIPController::crypto.sha1            = TGSha1;
	VoIPController::crypto.sha256          = TGSha256;
	VoIPController::crypto.aes_ige_encrypt = TGAesIgeEncrypt;
	VoIPController::crypto.aes_ige_decrypt = TGAesIgeDecrypt;
	VoIPController::crypto.aes_ctr_encrypt = TGAesCtrEncrypt;
	VoIPController::crypto.aes_cbc_encrypt = TGAesCbcEncrypt;
	VoIPController::crypto.aes_cbc_decrypt = TGAesCbcDecrypt;
}

#pragma mark -

@interface TGCall ()
@property (nonatomic, assign) TGCallState state;
@property (nonatomic, assign) int32_t callId;
@property (nonatomic, assign) int64_t peerUserId;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSDate *establishedAt;
@property (nonatomic, strong) NSString *endReason;
@property (nonatomic, strong) TGCallReflector *reflector;      // the chosen one
@property (nonatomic, strong) NSMutableArray *reflectors;      // all of them
@property (nonatomic, strong) NSData *callKey;
@property (nonatomic, strong) NSString *localUfrag;
@property (nonatomic, strong) NSString *localPwd;
@property (nonatomic, strong) NSString *reflectorHost;
@property (nonatomic, assign) uint16_t reflectorPort;
@property (nonatomic, assign) int64_t reflectorId;
@property (nonatomic, assign) uint32_t signallingSeq;
@property (nonatomic, assign) BOOL sentCandidates;
@property (nonatomic, assign) BOOL loggedHeader;
@property (nonatomic, assign) BOOL sentMediaState;
@property (nonatomic, assign) uint32_t videoParametersSeq;
@property (nonatomic, assign) uint32_t mediaStateSeq;
@property (nonatomic, strong) NSTimer *mediaStateTimer;
@property (nonatomic, assign) uint32_t audioProbeSeq;
@property (nonatomic, assign) BOOL audioFramingProven;
@property (nonatomic, assign) uint32_t currentSenderTag;
@property (nonatomic, strong) TGCallReflector *currentReflector;
@property (nonatomic, strong) NSString *peerUfrag;
@property (nonatomic, strong) NSString *peerPwd;
@property (nonatomic, strong) TGCallIce *ice;
@property (nonatomic, strong) TGCallAudioEngine *audioEngine;
@property (nonatomic, assign) uint32_t mediaSeqOut;
@property (nonatomic, assign) uint16_t rtpSeqOut;
@property (nonatomic, assign) uint32_t rtpTimestampOut;
@property (nonatomic, assign) uint16_t transportSeqOut;
@end


static const char *kBuildMarker = "BUILD_MARKER_AUDIO_FIX_V5";




@implementation TGCall {
	uint32_t _mediaPacketsIn;
	uint32_t _stunRequestsIn;
	uint32_t _stunResponsesIn;
	uint32_t _unreadablePacketsIn;
	uint32_t _audioFramesIn;
	uint32_t _audioFramesOut;
	uint32_t _highestRtpSeqIn;
	uint32_t _decryptFailuresIn;
	BOOL _loggedTheirResponse;
	BOOL _speakerEnabled;
}



+ (instancetype)shared {
	static TGCall *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSLog(@"TGCall: %s", kBuildMarker);
		s = [[TGCall alloc] init];
	});
	return s;
}


- (NSTimeInterval)duration {
	if (!self.establishedAt)
		return 0;
	return [[NSDate date] timeIntervalSinceDate:self.establishedAt];
}

- (void)setSpeaker:(BOOL)speaker {
    _speakerEnabled = speaker;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (speaker) {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    } else {
        [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    }
}

- (void)setState:(TGCallState)state {
	if (_state == state)
		return;
	_state = state;
	if (state == TGCallStateEstablished && !self.establishedAt)
		self.establishedAt = [NSDate date];
	if (self.onStateChanged)
		self.onStateChanged(state);
}

#pragma mark - signalling

/// ICE credentials are ours to choose; the peer signs its connectivity checks
/// with them, so they only have to be random and match what we announce.
- (NSString *)randomIceStringOfLength:(NSInteger)length {
	static NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	NSMutableString *out = [NSMutableString string];
	for (NSInteger i = 0; i < length; i++)
		[out appendFormat:@"%C", [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
	return out;
}

/// Our only route is the reflector, so that is the one candidate we offer -
/// a relay candidate pointing at it. The peer will send its checks there and
/// the reflector will hand them to us, because both ends share the tag.
- (void)sendOurCandidates {
	if (self.sentCandidates || !self.reflectorHost.length)
		return;
	self.sentCandidates = YES;

	self.localUfrag = [self randomIceStringOfLength:4];
	self.localPwd = [self randomIceStringOfLength:24];

	self.ice = [[TGCallIce alloc] init];
	self.ice.localUfrag = self.localUfrag;
	self.ice.localPwd = self.localPwd;
	__weak __typeof__(self) weakSelf = self;
	self.ice.transport = ^(NSData *packet){
		TGCall *me = weakSelf;
		// An answer goes to the port that asked; anything else - our own
		// checks - goes to every tag the peer has shown us.
		if (me.currentSenderTag){
			[me.currentReflector ?: me.reflector sendPayload:packet
													   toTag:me.currentSenderTag];
			return;
		}
		for (TGCallReflector *reflector in me.reflectors)
			[reflector sendPayload:packet];
	};
	self.ice.onConnected = ^(NSString *address, uint16_t port){
		NSLog(@"TGCall: media path is %@:%u", address, port);
		weakSelf.state = TGCallStateEstablished;
		[weakSelf startAudioEngine];
	};
	[self.ice start];


	// The address is a name rather than an IP: the peer reads our four-byte
	// tag out of it and uses that to address us through the reflector.
	NSMutableArray *candidates = [NSMutableArray array];
	NSInteger index = 0;
	for (TGCallReflector *reflector in self.reflectors){
		index++;
		NSString *hostname = [NSString stringWithFormat:@"reflector-%ld-%u.reflector",
				(long)index, reflector.localTag];
		// Written exactly the way the peer writes its own: component 0, no
		// raddr or rport. A line their parser rejects takes the whole message
		// with it, and then they never learn our credentials at all.
		[candidates addObject:[NSString stringWithFormat:
				@"candidate:%u 1 udp 41878272 %@ %u typ relay generation 0 "
				@"ufrag %@ network-id 9 network-cost 50",
				reflector.localTag, hostname, reflector.port, self.localUfrag]];
	}

	NSData *body = [TGCallMessages candidatesBody:candidates
											ufrag:self.localUfrag
											  pwd:self.localPwd];
	NSData *message = [TGCallMessages messageWithType:TGCallMessageCandidates body:body];
	[self sendSignalling:message
					 seq:[TGCallMessages markSeq:++self.signallingSeq requiresAck:YES]];
	NSLog(@"TGCall: sent our candidates, ufrag=%@", self.localUfrag);

	// The peer announces its video formats and waits for ours. This build has
	// no video, so the honest answer is an empty list - but an answer, because
	// silence leaves its half of the negotiation open.
	//   uint8 format count, then the formats, then uint8 encoder count
	uint8_t formats[2] = { 0, 0 };
	NSData *videoFormats = [TGCallMessages messageWithType:TGCallMessageVideoFormats
													  body:[NSData dataWithBytes:formats length:2]];
	[self sendSignalling:videoFormats
					 seq:[TGCallMessages markSeq:++self.signallingSeq requiresAck:YES]];
	NSLog(@"TGCall: sent our video formats (none)");
}

/// The peer's half of the negotiation. Decrypting it is also the check that
/// the crypto is right: the msgKey is a slice of SHA256 over the plaintext, so
/// a wrong key cannot produce a match.
- (void)handleSignalingData:(NSData *)data {
	if (!self.callKey.length || !data.length)
		return;

	NSMutableData *out = [NSMutableData dataWithLength:data.length];
	uint32_t seq = 0;
	int size = TGCallDecryptPacket((const uint8_t *)self.callKey.bytes,
								   self.outgoing, 1 /* signalling */,
								   (const uint8_t *)data.bytes, data.length,
								   (uint8_t *)out.mutableBytes, &seq);
	if (size <= 0){
		NSLog(@"TGCall: signalling %lu bytes did not decrypt", (unsigned long)data.length);
		return;
	}
	out.length = size;

	for (NSDictionary *message in [TGCallMessages parsePacket:out seq:seq]){
		uint8_t type = [message[@"type"] unsignedCharValue];
		uint32_t messageSeq = [message[@"seq"] unsignedIntValue];

		// Without an acknowledgement the peer keeps resending and never moves
		// on to the next step of the negotiation. Send ACK unconditionally for signaling.
		[self sendSignalling:[TGCallMessages ackForSeq:messageSeq]
						 seq:++self.signallingSeq];

		if (type == TGCallMessageVideoFormats) {
			NSLog(@"TGCall: peer sent VideoFormats (type 2), responding with empty video formats");
			uint8_t formats[2] = { 0, 0 };
			NSData *videoFormats = [TGCallMessages messageWithType:TGCallMessageVideoFormats
															  body:[NSData dataWithBytes:formats length:2]];
			[self sendSignalling:videoFormats
							 seq:[TGCallMessages markSeq:++self.signallingSeq requiresAck:YES]];
		}

		if (type != TGCallMessageCandidates){
			NSLog(@"TGCall: signalling message type %d, %lu bytes", type,
					(unsigned long)[message[@"body"] length]);
			if (type == 127) {
				NSData *b = message[@"body"];
				if (b.length > 4) { // skip the 4-byte size
					NSString *str = [[NSString alloc] initWithData:[b subdataWithRange:NSMakeRange(4, b.length - 4)] encoding:NSUTF8StringEncoding];
					NSLog(@"TGCall: JSON: %@", str);
				}
			}
			continue;
		}

		NSDictionary *ice = [TGCallMessages parseCandidates:message[@"body"]];
		self.peerUfrag = ice[@"ufrag"];
		self.peerPwd = ice[@"pwd"];
		self.ice.peerUfrag = self.peerUfrag;
		self.ice.peerPwd = self.peerPwd;
		NSLog(@"TGCall: peer ICE ufrag=%@ pwd=%@", self.peerUfrag, self.peerPwd);
		for (NSString *candidate in ice[@"candidates"]){
			NSLog(@"TGCall: peer candidate: %@", candidate);
			[self readPeerTagFromCandidate:candidate];
			[self.ice addPeerCandidate:candidate];
		}
	}
}

/// Their relay candidate carries their four bytes the same way ours does.
- (void)readPeerTagFromCandidate:(NSString *)candidate {
	NSRange marker = [candidate rangeOfString:@"reflector-"];
	if (marker.location == NSNotFound || self.reflector.remoteTag)
		return;

	NSString *tail = [candidate substringFromIndex:marker.location + marker.length];
	NSArray *parts = [[tail componentsSeparatedByString:@".reflector"][0]
			componentsSeparatedByString:@"-"];
	if (parts.count < 2)
		return;

	uint32_t tag = (uint32_t)[parts[1] longLongValue];
	for (TGCallReflector *reflector in self.reflectors)
		reflector.remoteTag = tag;
	NSLog(@"TGCall: peer reflector tag %u", tag);
}

- (void)sendSignalling:(NSData *)plaintext seq:(uint32_t)seq {
	if (!self.callKey.length)
		return;

	NSMutableData *encrypted = [NSMutableData dataWithLength:plaintext.length + 32];
	int size = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
								   self.outgoing, 1 /* signalling */,
								   (const uint8_t *)plaintext.bytes, plaintext.length,
								   seq,
								   (uint8_t *)encrypted.mutableBytes);
	if (size <= 0)
		return;
	encrypted.length = size;

	[[TGClient shared] send:@{
		@"@type"   : @"sendCallSignalingData",
		@"call_id" : @(self.callId),
		@"data"    : [encrypted base64EncodedStringWithOptions:0],
	}];
}

- (void)callUser:(int64_t)userId {
	self.peerUserId = userId;
	self.outgoing = YES;
	self.state = TGCallStatePending;
	[[TGClient shared] send:@{
		@"@type"     : @"createCall",
		@"user_id"   : @(userId),
		@"protocol"  : [self protocol],
		@"is_video"  : @NO,
	}];
}

- (void)accept {
	if (!self.callId)
		return;
	[[TGClient shared] send:@{
		@"@type"    : @"acceptCall",
		@"call_id"  : @(self.callId),
		@"protocol" : [self protocol],
	}];
}

- (void)hangUp {
	if (self.callId)
		[[TGClient shared] send:@{
			@"@type"           : @"discardCall",
			@"call_id"         : @(self.callId),
			@"is_disconnected" : @NO,
			@"duration"        : @((int)[self duration]),
			@"is_video"        : @NO,
			@"connection_id"   : @(0),
		}];
	[self teardown];
	self.state = TGCallStateEnded;
}

/// 65 to 92 with library version 2.4.4 is exactly what the official clients
/// advertised while libtgvoip was their call library. A peer that only speaks
/// tgcalls refuses this outright - see the note in ROADMAP.
- (NSDictionary *)protocol {
	return @{
		@"@type"            : @"callProtocol",
		// A direct path needs an address the peer can reach, and behind a
		// carrier NAT there is none: checks sent to their public address are
		// dropped by their NAT because nothing has come from us before. The
		// reflector exists for exactly this, so it is what we ask for.
		@"udp_p2p"          : @NO,
		@"udp_reflector"    : @YES,
		@"min_layer"        : @(65),
		@"max_layer"        : @(92),
		// Probing which tgcalls versions this peer still accepts. 2.4.4 alone
		// is refused outright; if 3.0.0 is taken, its media is plain RTP with
		// Opus inside an EncryptedConnection, which is implementable here.
		// Probing what the peer prefers. 9.0.0 is the current tgcalls version;
		// if it takes that, the negotiation runs v2 - JSON signalling, relay
		// candidates with a resolvable tag, and DTLS-SRTP for the media.
		@"library_versions" : @[@"9.0.0", @"3.0.0", @"2.4.4"],
	};
}

- (void)handleUpdate:(NSDictionary *)call {
	self.callId = [call[@"id"] intValue];
	self.peerUserId = [call[@"user_id"] longLongValue];
	self.outgoing = [call[@"is_outgoing"] boolValue];

	NSDictionary *state = call[@"state"];
	NSString *kind = state[@"@type"];
	NSLog(@"TGCall: %@ (call %d, outgoing %d)", kind, self.callId, self.outgoing);

	if ([kind isEqualToString:@"callStatePending"]){
		self.state = TGCallStatePending;
	} else if ([kind isEqualToString:@"callStateExchangingKeys"]){
		self.state = TGCallStateExchangingKeys;
	} else if ([kind isEqualToString:@"callStateReady"]){
		[self startMediaWithState:state];
	} else if ([kind isEqualToString:@"callStateDiscarded"] ||
			   [kind isEqualToString:@"callStateHangingUp"]){
		// The reason is the useful part: a peer that cannot speak this
		// protocol discards rather than answering, and looks like a decline.
		NSString *reason = state[@"reason"][@"@type"];
		NSLog(@"TGCall: discarded, reason %@", reason ?: @"(none)");
		self.endReason = [self humanReason:reason];
		[self teardown];
		self.state = TGCallStateEnded;
	} else if ([kind isEqualToString:@"callStateError"]){
		NSLog(@"TGCall: error %@ %@", state[@"error"][@"code"], state[@"error"][@"message"]);
		self.endReason = state[@"error"][@"message"];
		[self teardown];
		self.state = TGCallStateFailed;
	}
}

- (NSString *)humanReason:(NSString *)reason {
	if ([reason isEqualToString:@"callDiscardReasonDeclined"])       return @"Declined";
	if ([reason isEqualToString:@"callDiscardReasonMissed"])         return @"No answer";
	if ([reason isEqualToString:@"callDiscardReasonDisconnected"])   return @"Disconnected";
	if ([reason isEqualToString:@"callDiscardReasonHungUp"])         return @"Call ended";
	// This is the one that means the other side speaks only tgcalls.
	if ([reason isEqualToString:@"callDiscardReasonUpgradeToGroupCall"]) return @"Moved to a group call";
	return nil;
}

#pragma mark - media

- (void)startMediaWithState:(NSDictionary *)state {
	// callStateReady can arrive more than once; the first one owns the call.
	if (self.callKey.length)
		return;

	TGInstallCrypto();
	self.state = TGCallStateConnecting;

	// The audio session has to be a call, or iOS routes it to the speaker and
	// ignores the proximity sensor.
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:nil];
	[session setMode:AVAudioSessionModeVoiceChat error:nil];
	[session setActive:YES error:nil];


	NSData *key = [[NSData alloc] initWithBase64EncodedString:state[@"encryption_key"]
													  options:0];
	if (key.length != 256){
		NSLog(@"TGCall: encryption key is %lu bytes, expected 256",
				(unsigned long)key.length);
		self.state = TGCallStateFailed;
		return;
	}

	self.callKey = key;
	[self probeReflectorsIn:state key:key];

	if (!self.reflectors.count){
		NSLog(@"TGCall: no reflector this build can use");
		self.state = TGCallStateFailed;
		return;
	}
	NSLog(@"TGCall: negotiated %@", state[@"protocol"][@"library_versions"]);

	// libtgvoip is no longer driven here. The peer speaks tgcalls, which is what
	// the reflector, ICE and audio engine above implement; running VoIPController
	// alongside them only put a second recorder on the audio session.
}

/// Stage one of speaking tgcalls rather than libtgvoip: open the reflector
/// ourselves and see what comes back. Nothing can arrive until the peer knows
/// our four-byte tag, which travels over the signalling channel - so for now
/// this proves the socket, the tag format and the address, and logs anything
/// the reflector says on its own.
/// Both ends have to sit on the same reflector: the twelve-byte prefix of the
/// tag is per server, so packets crossing different ones never meet. TDLib
/// hands out several and the peer picks its own, so this connects to all of
/// them and lets the tags decide which one carries the call.
- (void)probeReflectorsIn:(NSDictionary *)state key:(NSData *)key {
	self.reflectors = [NSMutableArray array];
	__weak __typeof__(self) weakSelf = self;

	NSInteger index = 0;
	for (NSDictionary *server in state[@"servers"]){
		NSDictionary *type = server[@"type"];
		if (![type[@"@type"] isEqualToString:@"callServerTypeTelegramReflector"])
			continue;

		NSData *peerTag = [[NSData alloc] initWithBase64EncodedString:type[@"peer_tag"]
															 options:0];
		TGCallReflector *reflector = [[TGCallReflector alloc]
				initWithHost:server[@"ip_address"]
						port:(uint16_t)[server[@"port"] intValue]
					 peerTag:peerTag];
		__weak TGCallReflector *weakReflector = reflector;
		reflector.onPacket = ^(NSData *packet){
			weakSelf.currentReflector = weakReflector;
			[weakSelf inspectReflectorPacket:packet];
		};
		[reflector start];
		[self.reflectors addObject:reflector];

		NSLog(@"TGCall: reflector %ld at %@:%d, our tag %u", (long)++index,
				server[@"ip_address"], [server[@"port"] intValue], reflector.localTag);

		if (!self.reflector){
			self.reflector = reflector;
			self.reflectorHost = server[@"ip_address"];
			self.reflectorPort = (uint16_t)[server[@"port"] intValue];
			self.reflectorId = index;
		}
	}
	[self sendOurCandidates];
}

- (void)startAudioEngine {
	if (self.audioEngine)
		return;

	self.audioEngine = [[TGCallAudioEngine alloc] init];
	__weak __typeof__(self) weakSelf = self;
	// ponytail: both on while the call path is being proved out, two lines to
	// drop once it is. The loopback feeds our own encoded frames back into the
	// decoder so the speaker proves the encode-decode-play chain works without
	// the peer having to send anything - it has never sent us a frame, so that
	// half of the engine has never once run.
	self.audioEngine.emitMorseSignal = YES;
	self.audioEngine.loopbackToSpeaker = NO;   // proved; anything heard now is theirs
	self.audioEngine.onOutgoingOpusFrame = ^(NSData *opusFrame) {
		[weakSelf sendOutgoingAudioFrame:opusFrame];
	};
	[self.audioEngine start];
	if (self.currentSenderTag && !self.sentMediaState){
		self.sentMediaState = YES;
		[self sendMediaStateMessage];
	}
	NSLog(@"TGCall: audio engine started for call");

}

- (void)sendOutgoingAudioFrame:(NSData *)opusFrame {
	if (!self.callKey.length || opusFrame.length == 0 || self.muted)
		return;

	// Official tgcalls single-message audio packet:
	// Byte 0: 0x05 (TGCallMessageAudioData)
	// Bytes 1..12: 12-byte RTP header (V=2, PT=111, seq, ts, SSRC)
	// Bytes 13..N: Opus frame
	// Encrypted under sequence number with bit 31 set (0x80000000).

	uint8_t rtpHeader[12];
	rtpHeader[0] = 0x80; // V=2, P=0, X=0, CC=0
	rtpHeader[1] = 111;  // Payload Type 111 (Opus)

	uint16_t seq = self.rtpSeqOut++;
	rtpHeader[2] = (uint8_t)(seq >> 8);
	rtpHeader[3] = (uint8_t)(seq);

	uint32_t ts = self.rtpTimestampOut;
	self.rtpTimestampOut += 960;
	rtpHeader[4] = (uint8_t)(ts >> 24);
	rtpHeader[5] = (uint8_t)(ts >> 16);
	rtpHeader[6] = (uint8_t)(ts >> 8);
	rtpHeader[7] = (uint8_t)(ts);

	uint32_t ssrc = self.outgoing ? 2 : 1;
	rtpHeader[8]  = (uint8_t)(ssrc >> 24);
	rtpHeader[9]  = (uint8_t)(ssrc >> 16);
	rtpHeader[10] = (uint8_t)(ssrc >> 8);
	rtpHeader[11] = (uint8_t)(ssrc);

	uint8_t type = TGCallMessageAudioData;
	NSMutableData *msg = [NSMutableData dataWithCapacity:1 + 12 + opusFrame.length];
	[msg appendBytes:&type length:1];
	[msg appendBytes:rtpHeader length:12];
	[msg appendData:opusFrame];

	NSMutableData *encrypted = [NSMutableData dataWithLength:msg.length + 32];
	uint32_t mediaSeq = [TGCallMessages markSeq:++self.mediaSeqOut requiresAck:NO]; // bit 31 set!
	int encSize = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
									  self.outgoing, 0 /* media */,
									  (const uint8_t *)msg.bytes, msg.length,
									  mediaSeq,
									  (uint8_t *)encrypted.mutableBytes);
	if (encSize <= 0)
		return;
	encrypted.length = encSize;

	if (++_audioFramesOut % 50 == 0){
		NSLog(@"TGCall: sent %u audio frames (single-msg format, seq %08x)",
				_audioFramesOut, mediaSeq);
		[self sendRtcpReceiverReport];
	}


	// Send encrypted packet over reflector transport
	if (self.currentSenderTag) {
		[(self.currentReflector ?: self.reflector) sendPayload:encrypted toTag:self.currentSenderTag];
	}
	for (TGCallReflector *reflector in self.reflectors) {
		if (reflector.remoteTag && reflector.remoteTag != self.currentSenderTag) {
			[reflector sendPayload:encrypted toTag:reflector.remoteTag];
		}
	}
}

- (void)handleIncomingMediaPacket:(NSData *)decryptedData seq:(uint32_t)seq {
	const uint8_t *b = (const uint8_t *)decryptedData.bytes;
	NSLog(@"TGCall: decrypted media packet seq %08x, len %lu, first byte %02x", seq, (unsigned long)decryptedData.length, b ? b[0] : 0);

	// Each message inside carries its own sequence number, and it is that one
	// the peer waits to hear back - acknowledging the packet's number instead
	// left it resending its opening pair once a second and never starting audio.
	for (NSDictionary *message in [TGCallMessages parseMediaPacket:decryptedData seq:seq]){
		uint8_t type = [message[@"type"] unsignedCharValue];
		uint32_t messageSeq = [message[@"seq"] unsignedIntValue];

		if ([TGCallMessages seqRequiresAck:messageSeq])
			[self sendAckForSeq:messageSeq signaling:NO];

		if (type == TGCallMessageAck){
			// The sequence number in front of an acknowledgement is the one it
			// confirms; the bits it was sent with are not part of the counter.
			uint32_t counter = messageSeq & ~((uint32_t)3 << 30);
			if (counter == self.mediaStateSeq)
				[self mediaStateAcknowledged];
			if (counter == self.audioProbeSeq && !self.audioFramingProven){
				self.audioFramingProven = YES;
				NSLog(@"TGCall: AUDIO FRAMING ACCEPTED - the peer parsed our "
					   "audio message and acknowledged what followed it");
			}
			continue;
		}

		if (type == TGCallMessageAudioData){
			[self handleIncomingRTP:message[@"body"]];
		} else {
			// Log ALL non-audio types (they are rare enough)
			NSLog(@"TGCall: peer media msg type %d seq %08x, %lu bytes", type,
					messageSeq, (unsigned long)[message[@"body"] length]);
			if (type == TGCallMessageMediaState) {
				const uint8_t *b = (const uint8_t *)[(NSData *)message[@"body"] bytes];
				NSLog(@"TGCall: peer MediaState byte: %02x (audio=%d video=%d)",
						b[0], b[0] & 1, (b[0] >> 1) & 1);
			}
		}
	}
}

/// An RTP packet as WebRTC wrote it: fixed header, optional CSRCs and one
/// optional extension block, then the Opus frame.
- (void)handleIncomingRTP:(NSData *)packet {
	const uint8_t *rtp = (const uint8_t *)packet.bytes;
	size_t rtpLen = packet.length;

	if (rtpLen < 12)
		return;

	uint16_t rtpSeq = ((uint16_t)rtp[2] << 8) | rtp[3];
	if (rtpSeq > _highestRtpSeqIn)
		_highestRtpSeqIn = rtpSeq;

	uint8_t cc = rtp[0] & 0x0F;
	BOOL hasExt = (rtp[0] & 0x10) != 0;
	size_t headerLen = 12 + 4 * cc;

	if (hasExt && rtpLen >= headerLen + 4) {
		uint16_t extLen = ((uint16_t)rtp[headerLen + 2] << 8) | rtp[headerLen + 3];
		headerLen += 4 + 4 * extLen;
	}

	if (rtpLen <= headerLen)
		return;

	NSData *opusFrame = [NSData dataWithBytes:rtp + headerLen length:rtpLen - headerLen];
	if (++_audioFramesIn == 1 || _audioFramesIn % 50 == 0)
		NSLog(@"TGCall: %u audio frames in, last %lu bytes", _audioFramesIn,
				(unsigned long)opusFrame.length);
	
	[self.audioEngine handleIncomingOpusFrame:opusFrame];
}



/// Anything that arrives gets held against the call key both ways round: if it
/// decrypts, the crypto port is right and the packet is real call traffic.
- (void)inspectReflectorPacket:(NSData *)packet {
	const uint8_t *bytes = (const uint8_t *)packet.bytes;
	if (packet.length <= 24)
		return;

	// Update sender tag from reflector header (ignoring 0xFFFFFFFF service tags)
	uint32_t senderTag = 0;
	memcpy(&senderTag, bytes + 16, 4);
	if (senderTag && senderTag != 0xFFFFFFFF && senderTag != self.reflector.localTag)
		self.currentSenderTag = senderTag;

	// The media state is what tells the peer our microphone is live, and it
	// cannot go anywhere until a tag to address it to has shown up. Whichever
	// happens last - the tag or the audio engine - sends it.
	if (self.currentSenderTag && self.audioEngine && !self.sentMediaState){
		self.sentMediaState = YES;
		[self sendMediaStateMessage];
	}


	// The reflector pads the payload out to a multiple of four and states the
	// real length at offset 20. Handing the padding to the decryptor as if it
	// were part of the message makes the hash over the plaintext disagree, and
	// every packet whose length is not already a multiple of four is thrown
	// away - which is most of them, and all the interesting ones.
	size_t declared = ((size_t)bytes[20] << 24) | ((size_t)bytes[21] << 16) |
					  ((size_t)bytes[22] << 8)  |  (size_t)bytes[23];

	static const size_t offsets[] = { 24, 16, 20, 0 };
	for (unsigned i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
		size_t offset = offsets[i];
		if (packet.length <= offset + 20)
			continue;

		size_t available = packet.length - offset;
		if (offset == 24 && declared > 0 && declared <= available)
			available = declared;

		NSData *payload = [packet subdataWithRange:NSMakeRange(offset, available)];
		int stunType = [TGCallStun messageTypeOf:payload];

		if (stunType >= 0) {
			// 0001 is a check from them, 0101 their answer to ours. Seeing only
			// one of the two is the difference between a path that works and a
			// path that looks like it does.
			if (stunType == 0x0001) _stunRequestsIn++; else _stunResponsesIn++;
			// Their answer to our check, once: a known-good response from a
			// real WebRTC agent to compare ours against.
			if (stunType == 0x0101 && !_loggedTheirResponse){
				_loggedTheirResponse = YES;
				NSLog(@"TGCallStun: their response %@", [TGCallStun hexOf:payload]);
			}
			if ((_stunRequestsIn + _stunResponsesIn) % 10 == 0)
				NSLog(@"TGCall: STUN in: %u checks, %u answers",
						_stunRequestsIn, _stunResponsesIn);
			[self.ice handleRelayedPacket:payload];
			return;
		}

		if (self.callKey.length && payload.length >= 21) {
			NSMutableData *decrypted = [NSMutableData dataWithLength:payload.length];
			uint32_t mediaSeq = 0;
			int decSize = TGCallDecryptPacket((const uint8_t *)self.callKey.bytes,
											  self.outgoing, 0 /* media */,
											  (const uint8_t *)payload.bytes, payload.length,
											  (uint8_t *)decrypted.mutableBytes, &mediaSeq);
			if (decSize > 0) {
				decrypted.length = decSize;
				if (++_mediaPacketsIn == 1 || _mediaPacketsIn % 50 == 0)
					NSLog(@"TGCall: %u incoming media packets, last %d bytes (seq %08x, offset %zu)",
							_mediaPacketsIn, decSize, mediaSeq, offset);
				if ([TGCallMessages seqRequiresAck:mediaSeq]) {
					[self sendAckForSeq:mediaSeq signaling:NO];
				}
				[self handleIncomingMediaPacket:decrypted seq:mediaSeq];
				return;
			} else if (payload.length >= 4) {
				// Log decrypt failure for diagnosis (once per 20 failures)
				if (++_decryptFailuresIn % 20 == 1) {
					const uint8_t *pb = (const uint8_t *)payload.bytes;
					NSLog(@"TGCall: decrypt fail #%u offset=%zu pklen=%lu paylen=%lu first=%02x%02x%02x%02x",
							_decryptFailuresIn, offset,
							(unsigned long)packet.length,
							(unsigned long)payload.length,
							pb[0], pb[1], pb[2], pb[3]);
				}
			}
		}
	}

	// Neither STUN nor anything the call key opens. Worth counting: it is the
	// difference between the peer sending us nothing and sending us something
	// we cannot read.
	if (++_unreadablePacketsIn % 10 == 1)
		NSLog(@"TGCall: %u unreadable packets, last %lu bytes starting %02x %02x",
				_unreadablePacketsIn, (unsigned long)packet.length,
				bytes[24], packet.length > 25 ? bytes[25] : 0);
}

- (void)sendAckForSeq:(uint32_t)seq signaling:(BOOL)signaling {
	if (!self.callKey.length || !self.currentSenderTag)
		return;

	NSData *ack = [TGCallMessages ackForSeq:seq];
	NSMutableData *encrypted = [NSMutableData dataWithLength:ack.length + 32];
	// An ack packet is an empty message followed by the ack, so it is neither a
	// single-message packet nor one asking to be acknowledged: bare counter.
	uint32_t outSeq = signaling ? ++self.signallingSeq : ++self.mediaSeqOut;

	int encSize = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
									  self.outgoing, signaling,
									  (const uint8_t *)ack.bytes, ack.length,
									  outSeq,
									  (uint8_t *)encrypted.mutableBytes);
	if (encSize > 0) {
		encrypted.length = encSize;
		[(self.currentReflector ?: self.reflector) sendPayload:encrypted toTag:self.currentSenderTag];
	}
}

/// Our opening pair on the media channel. The peer sends its own once a second
/// until it is acknowledged and only then moves on, so this does the same: the
/// sequence numbers are allocated once and the same packet goes out until an
/// acknowledgement for the media state comes back.
- (void)sendMediaStateMessage {
	if (!self.callKey.length || !self.currentSenderTag){
		NSLog(@"TGCall: media state not sent, no sender tag yet");
		return;
	}

	if (!self.mediaStateSeq){
		self.videoParametersSeq = ++self.mediaSeqOut;
		self.mediaStateSeq = ++self.mediaSeqOut;
	}

	NSData *body = [TGCallMessages
			mediaStateBundleWithVideoSeq:[TGCallMessages markSeq:self.videoParametersSeq
													 requiresAck:YES]
								stateSeq:[TGCallMessages markSeq:self.mediaStateSeq
													 requiresAck:YES]
							 audioActive:!self.muted];

	// The packet carries an empty message first, so its own sequence number is a
	// bare counter - no single-message bit, nothing asking to be acknowledged.
	NSMutableData *encrypted = [NSMutableData dataWithLength:body.length + 32];
	int encSize = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
									  self.outgoing, 0 /* media */,
									  (const uint8_t *)body.bytes, body.length,
									  ++self.mediaSeqOut,
									  (uint8_t *)encrypted.mutableBytes);
	if (encSize <= 0)
		return;
	encrypted.length = encSize;
	[(self.currentReflector ?: self.reflector) sendPayload:encrypted
													 toTag:self.currentSenderTag];
	NSLog(@"TGCall: media state sent to tag %u (video seq %u, state seq %u)",
			self.currentSenderTag, self.videoParametersSeq, self.mediaStateSeq);

	if (!self.mediaStateTimer)
		self.mediaStateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
																target:self
															  selector:@selector(sendMediaStateMessage)
															  userInfo:nil
															   repeats:YES];
}

/// The one question that cannot be answered by listening: does the peer parse
/// our audio message at all? Put a message it must acknowledge directly behind
/// one, in the same packet. Their parser reaches the second only by having read
/// the first correctly - a malformed message aborts the whole packet - so an
/// acknowledgement is proof the audio framing is right, and its absence is
/// proof it is wrong.
- (void)probeAudioFramingWith:(NSData *)audioMessage {
	if (self.audioFramingProven || !self.currentSenderTag)
		return;

	self.audioProbeSeq = ++self.mediaSeqOut;

	NSMutableData *body = [NSMutableData dataWithData:audioMessage];
	uint32_t marked = [TGCallMessages markSeq:self.audioProbeSeq requiresAck:YES];
	uint8_t seqBytes[4] = {
		(uint8_t)(marked >> 24), (uint8_t)(marked >> 16),
		(uint8_t)(marked >> 8),  (uint8_t)marked,
	};
	[body appendBytes:seqBytes length:4];
	uint8_t trailer[2] = { TGCallMessageMediaState, 1 };
	[body appendBytes:trailer length:2];

	NSMutableData *encrypted = [NSMutableData dataWithLength:body.length + 32];
	int encSize = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
									  self.outgoing, 0 /* media */,
									  (const uint8_t *)body.bytes, body.length,
									  ++self.mediaSeqOut,
									  (uint8_t *)encrypted.mutableBytes);
	if (encSize <= 0)
		return;
	encrypted.length = encSize;
	[(self.currentReflector ?: self.reflector) sendPayload:encrypted
													 toTag:self.currentSenderTag];
	NSLog(@"TGCall: audio framing probe sent, waiting on seq %u", self.audioProbeSeq);
}

- (void)mediaStateAcknowledged {
	if (!self.mediaStateTimer)
		return;
	NSLog(@"TGCall: peer acknowledged our media state");
	[self.mediaStateTimer invalidate];
	self.mediaStateTimer = nil;
	[self sendRemoteNetworkStatusMessage];
}

- (void)sendRtcpReceiverReport {
	if (!self.callKey.length || !self.currentSenderTag)
		return;

	uint32_t ourSSRC = self.outgoing ? 2 : 1;
	uint32_t peerSSRC = self.outgoing ? 1 : 2;

	NSData *rrPayload = [TGCallMessages rtcpReceiverReportWithOurSSRC:ourSSRC
															 peerSSRC:peerSSRC
														   highestSeq:_highestRtpSeqIn];

	uint16_t rtpLength = (uint16_t)rrPayload.length;
	uint8_t header[3] = {
		TGCallMessageAudioData,
		(uint8_t)(rtpLength >> 8),
		(uint8_t)rtpLength,
	};
	NSMutableData *msg = [NSMutableData dataWithCapacity:3 + rtpLength];
	[msg appendBytes:header length:3];
	[msg appendData:rrPayload];

	NSMutableData *encrypted = [NSMutableData dataWithLength:msg.length + 32];
	uint32_t mediaSeq = ++self.mediaSeqOut;
	int encSize = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
									  self.outgoing, 0 /* media */,
									  (const uint8_t *)msg.bytes, msg.length,
									  mediaSeq,
									  (uint8_t *)encrypted.mutableBytes);
	if (encSize <= 0)
		return;
	encrypted.length = encSize;

	[(self.currentReflector ?: self.reflector) sendPayload:encrypted toTag:self.currentSenderTag];
	for (TGCallReflector *reflector in self.reflectors) {
		if (reflector.remoteTag && reflector.remoteTag != self.currentSenderTag) {
			[reflector sendPayload:encrypted toTag:reflector.remoteTag];
		}
	}
	NSLog(@"TGCall: sent RTCP Receiver Report (our SSRC %u, peer SSRC %u, highest rtp seq %u)",
			ourSSRC, peerSSRC, _highestRtpSeqIn);
}

- (void)sendRemoteNetworkStatusMessage {
	if (!self.callKey.length || !self.currentSenderTag)
		return;

	NSData *body = [TGCallMessages messageWithType:TGCallMessageRemoteNetworkStatus
											  body:[TGCallMessages remoteNetworkStatusBody]];
	NSMutableData *encrypted = [NSMutableData dataWithLength:body.length + 32];
	uint32_t mediaSeq = [TGCallMessages markSeq:++self.mediaSeqOut requiresAck:YES];
	int encSize = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
									  self.outgoing, 0 /* media */,
									  (const uint8_t *)body.bytes, body.length,
									  mediaSeq,
									  (uint8_t *)encrypted.mutableBytes);
	if (encSize <= 0)
		return;
	encrypted.length = encSize;
	[(self.currentReflector ?: self.reflector) sendPayload:encrypted toTag:self.currentSenderTag];
	NSLog(@"TGCall: sent RemoteNetworkStatusMessage (type 10)");
}


- (void)setMuted:(BOOL)muted {
	// ponytail: the mic keeps running and the frames are dropped on the way out.
	// Stopping the input queue would mean restarting it, for no audible gain.
	_muted = muted;
}

- (void)teardown {
	if (self.audioEngine) {
		[self.audioEngine stop];
		self.audioEngine = nil;
	}
	[self.ice stop];
	self.ice = nil;
	for (TGCallReflector *reflector in self.reflectors)
		[reflector stop];
	self.reflectors = nil;
	self.reflector = nil;
	self.currentReflector = nil;
	self.currentSenderTag = 0;
	self.callKey = nil;
	self.sentCandidates = NO;
	[self.mediaStateTimer invalidate];
	self.mediaStateTimer = nil;
	self.sentMediaState = NO;
	self.mediaStateSeq = 0;
	self.videoParametersSeq = 0;
	self.mediaSeqOut = 0;
	self.signallingSeq = 0;
	_mediaPacketsIn = 0;
	self.establishedAt = nil;
	self.callId = 0;
	[[AVAudioSession sharedInstance] setActive:NO error:nil];
}


@end

// vim:ft=objcpp
