#import "TGCallV2Session.h"

#import "TGCallDtls.h"
#import "TGCallMessages.h"
#import "TGCallSrtp.h"
#import "TGCallV2Signaling.h"

static const NSTimeInterval kResendInterval = 3.0;
static const NSTimeInterval kGiveUpInterval = 25.0;
static const uint32_t kAudioPayloadType = 111;

@interface TGCallV2Session ()
@property (nonatomic, strong) TGCallDtls *dtls;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *pending;
@property (nonatomic, strong) NSString *peerUfrag;
@property (nonatomic, strong) NSString *peerPwd;
@property (nonatomic, strong) NSString *peerFingerprint;
@property (nonatomic, strong) NSString *offerExchangeId;
@property (nonatomic, strong) NSString *answeredExchangeId;
@property (nonatomic, assign) uint32_t peerSsrc;
@property (nonatomic, assign) BOOL sentInitialSetup;
@property (nonatomic, assign) BOOL sentOffer;
@property (nonatomic, assign) BOOL havePeerSetup;
@property (nonatomic, assign) BOOL iceIsConnected;
@property (nonatomic, assign) BOOL haveKeys;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) NSTimeInterval startedAt;
@end

@implementation TGCallV2Session {
	uint32_t _seq;
	uint16_t _rtpSeq;
	uint32_t _rtpTimestamp;
	uint32_t _srtcpIndex;
	TGSrtpContext _sendSrtp;
	TGSrtpContext _receiveSrtp;
	uint32_t _srtpPacketsIn;
	uint32_t _srtpFailuresIn;
	uint32_t _audioFramesSent;
	uint8_t _scratch[2048];
}

- (instancetype)init {
	if ((self = [super init])){
		_pending = [NSMutableArray array];
		_startedAt = [NSDate timeIntervalSinceReferenceDate];
	}
	return self;
}

- (void)start {
	self.dtls = [[TGCallDtls alloc] initWithClient:self.outgoing];
	NSString *error = nil;
	if (![self.dtls setupWithError:&error]){
		[self fail:error ?: @"DTLS setup failed"];
		return;
	}
	__weak __typeof__(self) weakSelf = self;
	self.dtls.sendRecord = ^(const uint8_t *bytes, size_t length){
		if (weakSelf.sendMedia)
			weakSelf.sendMedia(bytes, length);
	};
	self.dtls.onConnected = ^{
		[weakSelf keysReady];
	};
	self.dtls.onFailure = ^(NSString *reason){
		[weakSelf fail:reason];
	};

	if (self.outgoing){
		[self sendInitialSetup];
		[self sendOffer];
	}

	self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
	                                              target:self
	                                            selector:@selector(tick)
	                                            userInfo:nil
	                                             repeats:YES];
}

- (void)iceConnected {
	self.iceIsConnected = YES;
	if (self.havePeerSetup)
		[self.dtls beginHandshake];
}

- (void)sendWithPlaintext:(NSData *)plaintext requiresAck:(BOOL)requiresAck {
	if (!plaintext.length || !self.sendSignaling || self.failed)
		return;
	uint32_t seq = requiresAck
		? [TGCallMessages markSeq:++_seq requiresAck:YES]
		: ++_seq;
	if (requiresAck){
		[self.pending addObject:@{
			@"seq" : @(seq),
			@"data" : plaintext,
			@"time" : @([NSDate timeIntervalSinceReferenceDate]),
		}];
	}
	self.sendSignaling(plaintext, seq);
}

- (void)sendInitialSetup {
	if (self.sentInitialSetup || !self.dtls.fingerprint.length)
		return;
	self.sentInitialSetup = YES;
	NSData *message = [TGCallV2Signaling initialSetupWithUfrag:self.localUfrag
	                                                      pwd:self.localPwd
	                                              fingerprint:self.dtls.fingerprint
	                                                    setup:self.outgoing ? @"actpass" : @"passive"];
	[self sendWithPlaintext:message requiresAck:YES];
}

- (void)sendOffer {
	if (self.sentOffer)
		return;
	self.sentOffer = YES;
	if (!self.offerExchangeId)
		self.offerExchangeId = [NSString stringWithFormat:@"%u",
		                        (uint32_t)(arc4random() | 1)];
	NSData *message = [TGCallV2Signaling offerWithExchangeId:self.offerExchangeId
	                                                    ssrc:self.localSsrc];
	[self sendWithPlaintext:message requiresAck:YES];
}

- (void)sendAnswerWithExchangeId:(NSString *)exchangeId ssrc:(uint32_t)ssrc {
	NSData *message = [TGCallV2Signaling answerWithExchangeId:exchangeId ssrc:ssrc];
	[self sendWithPlaintext:message requiresAck:YES];
}

- (void)sendCandidates:(NSArray *)candidates {
	if (!candidates.count)
		return;
	NSData *message = [TGCallV2Signaling candidatesWithStrings:candidates];
	[self sendWithPlaintext:message requiresAck:YES];
}

- (void)ackSeq:(uint32_t)seq {
	NSData *ack = [TGCallV2Signaling ackForSeq:seq];
	[self sendWithPlaintext:ack requiresAck:NO];
}

- (void)handlePlaintext:(NSData *)plaintext packetSeq:(uint32_t)seq {
	TGV2Slice slices[16];
	size_t count = TGV2ParsePlaintext(plaintext.bytes, plaintext.length, seq,
	                                  slices, 16);
	for (size_t i = 0; i < count; i++){
		uint8_t type = slices[i].type;
		if (type == 0x7F){
			NSDictionary *json = [NSJSONSerialization
				JSONObjectWithData:[NSData dataWithBytes:slices[i].body
				                                 length:slices[i].bodyLength]
				           options:0 error:nil];
			if ([json isKindOfClass:[NSDictionary class]])
				[self handleJSON:json];
			if ([TGCallMessages seqRequiresAck:slices[i].seq])
				[self ackSeq:slices[i].seq];
		} else if (type == 0xFF){
			[self acknowledgeSeq:slices[i].seq];
		}
	}
}

- (void)acknowledgeSeq:(uint32_t)seq {
	for (NSUInteger i = 0; i < self.pending.count; i++){
		NSDictionary *entry = self.pending[i];
		if ([entry[@"seq"] unsignedIntValue] == seq){
			[self.pending removeObjectAtIndex:i];
			return;
		}
	}
}

- (NSString *)stringValue:(id)value {
	if ([value isKindOfClass:[NSString class]])
		return value;
	if ([value isKindOfClass:[NSNumber class]])
		return [value stringValue];
	return nil;
}

- (uint32_t)uint32Value:(id)value {
	if ([value isKindOfClass:[NSString class]])
		return (uint32_t)[value longLongValue];
	if ([value isKindOfClass:[NSNumber class]])
		return [value unsignedIntValue];
	return 0;
}

- (void)handleJSON:(NSDictionary *)json {
	NSString *type = json[@"@type"];
	if ([type isEqualToString:@"InitialSetup"]){
		NSArray *fingerprints = json[@"fingerprints"];
		NSDictionary *first = [fingerprints isKindOfClass:[NSArray class]] &&
		                      [fingerprints count] ? fingerprints[0] : nil;
		NSString *fingerprint = first[@"fingerprint"];
		self.peerUfrag = json[@"ufrag"];
		self.peerPwd = json[@"pwd"];
		self.peerFingerprint = fingerprint;
		NSLog(@"TGCallV2: peer InitialSetup ufrag=%@ pwd=%d setup=%@ fingerprint=%d",
		      self.peerUfrag, self.peerPwd.length > 0,
		      first[@"setup"], fingerprint.length > 0);
		if (!self.havePeerSetup){
			self.havePeerSetup = YES;
			if (self.onPeerCredentials)
				self.onPeerCredentials(self.peerUfrag, self.peerPwd);
			// The callee stays silent until the caller's InitialSetup arrives,
			// then answers with its own.
			[self sendInitialSetup];
			if (self.iceIsConnected)
				[self.dtls beginHandshake];
		}
	} else if ([type isEqualToString:@"NegotiateChannels"]){
		NSString *exchangeId = [self stringValue:json[@"exchangeId"]];
		NSArray *contents = json[@"contents"];
		NSDictionary *content = [contents isKindOfClass:[NSArray class]] &&
		                        contents.count ? contents[0] : nil;
		uint32_t ssrc = [self uint32Value:content[@"ssrc"]];
		NSLog(@"TGCallV2: peer NegotiateChannels exchange=%@ ssrc=%u type=%@",
		      exchangeId, ssrc, content[@"type"]);
		if (!ssrc || !exchangeId)
			return;
		if (ssrc == self.localSsrc){
			// Their answer to our offer.
			return;
		}
		// Their offer. Answer it once per exchange; the callee also sends its
		// own offer at this point, which is what starts the other direction.
		if (![self.answeredExchangeId isEqualToString:exchangeId]){
			self.answeredExchangeId = exchangeId;
			self.peerSsrc = ssrc;
			[self sendAnswerWithExchangeId:exchangeId ssrc:ssrc];
			if (!self.outgoing)
				[self sendOffer];
		}
	} else if ([type isEqualToString:@"Candidates"]){
		NSArray *items = json[@"candidates"];
		NSMutableArray *candidates = [NSMutableArray array];
		for (NSDictionary *item in items){
			NSString *sdp = item[@"sdpString"];
			if (sdp.length)
				[candidates addObject:sdp];
		}
		if (candidates.count && self.onRemoteCandidates)
			self.onRemoteCandidates(candidates);
	} else if ([type isEqualToString:@"MediaState"]){
		// The library only sends this over SCTP, which this client skips.
	} else {
		NSLog(@"TGCallV2: ignoring signalling type %@", type);
	}
}

- (void)keysReady {
	if (self.haveKeys)
		return;
	uint8_t exporter[60];
	if (![self.dtls exportKeyingMaterial:exporter length:sizeof(exporter)]){
		[self fail:@"SRTP key export failed"];
		return;
	}
	uint8_t sendKey[TGSrtpKeyLength], sendSalt[TGSrtpSaltLength];
	uint8_t receiveKey[TGSrtpKeyLength], receiveSalt[TGSrtpSaltLength];
	TGSrtpSplitExporter(exporter, self.outgoing ? 1 : 0,
	                    sendKey, sendSalt, receiveKey, receiveSalt);
	TGSrtpContextInit(&_sendSrtp, sendKey, sendSalt);
	TGSrtpContextInit(&_receiveSrtp, receiveKey, receiveSalt);
	self.haveKeys = YES;
	NSLog(@"TGCallV2: DTLS done, SRTP keys installed (client %d)", self.outgoing);
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.onEstablished)
			self.onEstablished();
	});
}

- (void)sendOpusFrame:(NSData *)frame {
	if (!self.haveKeys || !frame.length || self.failed)
		return;
	size_t length = 12 + frame.length;
	if (length + TGSrtpTagLength > sizeof(_scratch))
		return;
	_scratch[0] = 0x80;
	_scratch[1] = kAudioPayloadType;
	_scratch[2] = (uint8_t)(_rtpSeq >> 8);
	_scratch[3] = (uint8_t)_rtpSeq;
	_scratch[4] = (uint8_t)(_rtpTimestamp >> 24);
	_scratch[5] = (uint8_t)(_rtpTimestamp >> 16);
	_scratch[6] = (uint8_t)(_rtpTimestamp >> 8);
	_scratch[7] = (uint8_t)_rtpTimestamp;
	_scratch[8]  = (uint8_t)(self.localSsrc >> 24);
	_scratch[9]  = (uint8_t)(self.localSsrc >> 16);
	_scratch[10] = (uint8_t)(self.localSsrc >> 8);
	_scratch[11] = (uint8_t)self.localSsrc;
	memcpy(_scratch + 12, frame.bytes, frame.length);
	_rtpSeq++;
	_rtpTimestamp += 960;

	size_t protectedLength = 0;
	if (TGSrtpProtect(&_sendSrtp, _scratch, length, sizeof(_scratch),
	                  &protectedLength) != 0)
		return;
	if (self.sendMedia)
		self.sendMedia(_scratch, protectedLength);
	if (++_audioFramesSent % 100 == 0)
		NSLog(@"TGCallV2: %u audio frames sent (seq %u ts %u ssrc %u)",
		      _audioFramesSent, (uint16_t)(_rtpSeq - 1), _rtpTimestamp - 960,
		      self.localSsrc);
}

- (void)handlePacket:(const uint8_t *)bytes length:(size_t)length {
	if (!bytes || length < 1 || self.failed)
		return;
	uint8_t first = bytes[0];
	if (first >= 20 && first <= 25){
		// A DTLS record. The handshake itself runs on this thread, which is
		// the reflector reader, never the main thread.
		@synchronized (self){
			[self.dtls feed:bytes length:length];
		}
		return;
	}
	if ((first & 0xC0) != 0x80 || !self.haveKeys)
		return;

	uint8_t payloadType = bytes[1] & 0x7F;
	if (payloadType >= 192 && payloadType <= 223){
		// SRTCP. Nothing here depends on their receiver reports, but the
		// record still has to be consumed.
		if (length <= sizeof(_scratch)){
			memcpy(_scratch, bytes, length);
			size_t plainLength = 0;
			TGSrtcpUnprotect(&_receiveSrtp, _scratch, length, &plainLength);
		}
		return;
	}

	if (length <= sizeof(_scratch)){
		memcpy(_scratch, bytes, length);
		size_t plainLength = 0;
		if (TGSrtpUnprotect(&_receiveSrtp, _scratch, length, &plainLength) == 0){
			if (++_srtpPacketsIn == 1 || _srtpPacketsIn % 50 == 0)
				NSLog(@"TGCallV2: %u SRTP packets in", _srtpPacketsIn);
			if (self.onAudio)
				self.onAudio(_scratch, plainLength);
		} else if (++_srtpFailuresIn == 1 || _srtpFailuresIn % 50 == 0){
			if (_srtpFailuresIn == 1){
				uint16_t seq = ((uint16_t)bytes[2] << 8) | bytes[3];
				uint32_t ssrc = ((uint32_t)bytes[8] << 24) | ((uint32_t)bytes[9] << 16) |
				                ((uint32_t)bytes[10] << 8) | bytes[11];
				NSLog(@"TGCallV2: first SRTP failure seq=%u ssrc=%u roc=%u len=%lu",
				      seq, ssrc, _receiveSrtp.roc, (unsigned long)length);
			}
			NSLog(@"TGCallV2: %u SRTP packets did not authenticate (len %lu pt %u)",
			      _srtpFailuresIn, (unsigned long)length, payloadType);
		}
	}
}

- (void)tick {
	if (self.failed)
		return;
	if (!self.haveKeys){
		@synchronized (self){
			[self.dtls handleTimeout];
		}
	}
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	for (NSUInteger i = 0; i < self.pending.count; ){
		NSDictionary *entry = self.pending[i];
		NSTimeInterval sent = [entry[@"time"] doubleValue];
		if (now - sent < kResendInterval){
			i++;
			continue;
		}
		uint32_t seq = [entry[@"seq"] unsignedIntValue];
		NSData *data = entry[@"data"];
		if (self.sendSignaling)
			self.sendSignaling(data, seq);
		[self.pending replaceObjectAtIndex:i withObject:@{
			@"seq" : @(seq),
			@"data" : data,
			@"time" : @(now),
		}];
		i++;
	}
	if (!self.haveKeys && now - self.startedAt > kGiveUpInterval)
		[self fail:@"no DTLS after 25 s"];
}

- (void)fail:(NSString *)reason {
	if (self.failed)
		return;
	self.failed = YES;
	NSLog(@"TGCallV2: failed: %@", reason);
	[self.timer invalidate];
	self.timer = nil;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.onFailure)
			self.onFailure(reason);
	});
}

- (void)stop {
	self.failed = YES;
	[self.timer invalidate];
	self.timer = nil;
	[self.pending removeAllObjects];
	[self.dtls stop];
	self.dtls = nil;
	self.haveKeys = NO;
	self.onEstablished = nil;
	self.onFailure = nil;
	self.onAudio = nil;
	self.sendSignaling = nil;
	self.sendMedia = nil;
	self.onRemoteCandidates = nil;
	self.onPeerCredentials = nil;
}

@end
