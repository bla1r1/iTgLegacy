// TGCallPeer.m — implementation of the loopback call peer simulator.
#import "TGCallPeer.h"
#import "TGCallStun.h"
#import "TGCallMessages.h"
#include "TGCallCrypto.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

// ── tiny helper ──────────────────────────────────────────────────────────────

static NSString *randomIceString(NSUInteger length) {
    static NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < length; i++)
        [out appendFormat:@"%C", [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────

@interface TGCallPeer () {
    int _socket;
    struct sockaddr_in _lastSender;   // address of the last STUN check sender
    BOOL _hasSender;

    // Reflector reply context, learned from the last wrapped packet. A reply
    // swaps the header around: the destination becomes TGCall's four bytes,
    // and our own four bytes take their place.
    uint8_t _replyPrefix[12];
    uint32_t _replyDestination;
    uint32_t _localTag;
    struct sockaddr_in _replyAddress;
    BOOL _hasReplyContext;
}
@property (nonatomic, readwrite) NSString *ufrag;
@property (nonatomic, readwrite) NSString *pwd;
@property (nonatomic, readwrite) uint16_t listenPort;
@property (nonatomic, readwrite) uint32_t stunRequestsReceived;
@property (nonatomic, readwrite) uint32_t stunResponsesReceived;
@property (nonatomic, readwrite) uint32_t audioFramesReceived;
@property (nonatomic, readwrite) uint32_t decryptFailures;
@property (nonatomic, readwrite) uint32_t acksReceived;
@property (nonatomic, readwrite) uint32_t mediaStateMessagesReceived;
@property (nonatomic, readwrite) uint32_t remoteStatusMessagesReceived;
@property (nonatomic, readwrite) uint32_t rtcpReportsReceived;
@property (nonatomic, assign) uint32_t mediaSeqOut;
@end

@implementation TGCallPeer

- (uint32_t)localTag {
    return _localTag;
}

- (instancetype)init {
    if ((self = [super init])) {
        _socket = -1;
        _localTag = arc4random();
        if (_localTag == 0) _localTag = 1;
        _ufrag  = randomIceString(4);
        _pwd    = randomIceString(24);
    }
    return self;
}

// ── lifecycle ─────────────────────────────────────────────────────────────

- (BOOL)start {
    _socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (_socket < 0) return NO;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port        = 0;  // OS picks a free port.

    if (bind(_socket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_socket); _socket = -1; return NO;
    }

    // Read back the assigned port.
    socklen_t len = sizeof(addr);
    getsockname(_socket, (struct sockaddr *)&addr, &len);
    _listenPort = ntohs(addr.sin_port);

    [NSThread detachNewThreadSelector:@selector(readLoop) toTarget:self withObject:nil];
    return YES;
}

- (void)stop {
    int s = _socket;
    _socket = -1;
    if (s >= 0) {
        // recvfrom() is blocking. close() alone does not reliably wake it, and
        // the descriptor number can be reused by the next test's peer before
        // this thread notices - which then steals that peer's packets.
        // shutdown() wakes the blocked call while the descriptor is still ours.
        shutdown(s, SHUT_RDWR);
        close(s);
    }
}

// ── read loop (background thread) ────────────────────────────────────────

- (void)readLoop {
    uint8_t buf[4096];
    while (_socket >= 0) {
        struct sockaddr_in from;
        socklen_t fromLen = sizeof(from);
        ssize_t got = recvfrom(_socket, buf, sizeof(buf), 0,
                               (struct sockaddr *)&from, &fromLen);
        if (got <= 0) break;

        NSData *packet = [NSData dataWithBytes:buf length:(NSUInteger)got];
        NSData *sender = [NSData dataWithBytes:&from length:sizeof(from)];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handlePacket:packet fromAddress:sender];
        });
    }
}

// ── packet dispatch ──────────────────────────────────────────────────────

/// TGCall no longer talks to the peer directly: its ICE transport wraps every
/// packet in the reflector header (destTag 16 | senderTag 4 | be32 size |
/// payload, padded to four). The peer stands in for a reflector endpoint, so
/// it has to unwrap before looking for STUN or media. Packets that already
/// parse as STUN are passed through for backwards compatibility.
- (NSData *)payloadFromReflectorPacket:(NSData *)packet {
    if ([TGCallStun messageTypeOf:packet] >= 0)
        return packet;
    if (packet.length <= 24)
        return packet;

    const uint8_t *bytes = (const uint8_t *)packet.bytes;
    size_t declared = ((size_t)bytes[20] << 24) | ((size_t)bytes[21] << 16) |
                      ((size_t)bytes[22] << 8)  |  (size_t)bytes[23];
    size_t available = packet.length - 24;
    if (declared == 0 || declared > available)
        declared = available;
    return [packet subdataWithRange:NSMakeRange(24, declared)];
}

- (void)handlePacket:(NSData *)packet fromAddress:(NSData *)addrData {
    // A wrapped packet tells us how to answer: keep its 12-byte call prefix,
    // the sender tag (TGCall's four bytes) and the socket it came from.
    if (packet.length > 24 && [TGCallStun messageTypeOf:packet] < 0) {
        const uint8_t *bytes = (const uint8_t *)packet.bytes;
        memcpy(_replyPrefix, bytes, 12);
        memcpy(&_replyDestination, bytes + 16, 4);
        memcpy(&_replyAddress, addrData.bytes, sizeof(_replyAddress));
        _hasReplyContext = YES;
    }

    packet = [self payloadFromReflectorPacket:packet];
    int stunType = [TGCallStun messageTypeOf:packet];

    if (stunType == 0x0001) {
        // Incoming connectivity check → respond. The answer has to go back
        // through the same relay, or TGCall's reflector never sees it.
        _stunRequestsReceived++;
        if (_stunRequestsReceived == 1 && self.onStunCheckReceived)
            self.onStunCheckReceived();

        NSData *response = [TGCallStun bindingResponseTo:packet
                                               password:self.pwd
                                            fromAddress:addrData];
        if (response) {
            if (![self sendReflectorPayload:response]) {
                const struct sockaddr_in *to = (const struct sockaddr_in *)addrData.bytes;
                sendto(_socket, response.bytes, response.length, 0,
                       (const struct sockaddr *)to, sizeof(*to));
            }
        }
        // Remember sender so we can send audio later.
        memcpy(&_lastSender, addrData.bytes, sizeof(_lastSender));
        _hasSender = YES;
        return;
    }

    if (stunType == 0x0101) {
        _stunResponsesReceived++;
        return;
    }

    // Try to decrypt as a media packet.
    if (!self.callKey.length || packet.length < 21) return;

    uint8_t *plain = malloc(packet.length);
    if (!plain) return;
    uint32_t seq = 0;
    int decLen = TGCallDecryptPacket(self.callKey.bytes,
                                    self.isOutgoing ? 1 : 0,  // reading from TGCall's outgoing stream
                                    0 /* media */,
                                    packet.bytes, packet.length,
                                    plain, &seq);
    if (decLen <= 0) {
        _decryptFailures++;
        free(plain);
        return;
    }

    NSData *plainData = [NSData dataWithBytesNoCopy:plain length:(NSUInteger)decLen freeWhenDone:YES];
    [self handleDecryptedMediaPacket:plainData seq:seq];
}

- (void)handleDecryptedMediaPacket:(NSData *)data seq:(uint32_t)seq {
    // Keep the sequence exactly as sent: bit 31 says the packet holds a
    // single message, and a bare counter means the packet carries length
    // prefixes. Re-marking it would misparse RTCP reports and media bundles.
    for (NSDictionary *msg in [TGCallMessages parseMediaPacket:data seq:seq]) {
        uint8_t type = [msg[@"type"] unsignedCharValue];
        uint32_t messageSeq = [msg[@"seq"] unsignedIntValue];

        if (type == TGCallMessageAudioData) {
            _audioFramesReceived++;
            NSData *rtpPayload = msg[@"body"];

            // Receiver Reports use the audio message type but start with an
            // RTCP header (version 2, packet type 201) instead of RTP.
            if (rtpPayload.length >= 2) {
                const uint8_t *rtcp = (const uint8_t *)rtpPayload.bytes;
                if ((rtcp[0] & 0xE0) == 0x80 && rtcp[1] == 0xC9)
                    _rtcpReportsReceived++;
            }

            // Strip 12-byte RTP header → raw Opus frame.
            if (rtpPayload.length > 12) {
                NSData *opus = [rtpPayload subdataWithRange:
                                NSMakeRange(12, rtpPayload.length - 12)];
                if (self.onAudioFrame) self.onAudioFrame(opus);
            }
        } else if (type == TGCallMessageAck) {
            _acksReceived++;
        } else if (type == TGCallMessageMediaState) {
            _mediaStateMessagesReceived++;
        } else if (type == TGCallMessageRemoteNetworkStatus) {
            _remoteStatusMessagesReceived++;
        }

        // A real peer acknowledges anything that asks for it, which is how
        // TGCall learns that its opening media-state bundle was understood.
        if (type != TGCallMessageAck && [TGCallMessages seqRequiresAck:messageSeq])
            [self sendAckForSeq:messageSeq];
    }
}

- (void)sendAckForSeq:(uint32_t)seq {
    if (!self.callKey.length)
        return;

    NSData *ack = [TGCallMessages ackForSeq:seq];
    NSMutableData *encrypted = [NSMutableData dataWithLength:ack.length + 32];
    uint32_t outSeq = ++_mediaSeqOut;
    int encSize = TGCallEncryptPacket(self.callKey.bytes,
                                      self.isOutgoing ? 1 : 0,
                                      0 /* media */,
                                      ack.bytes, ack.length,
                                      outSeq,
                                      encrypted.mutableBytes);
    if (encSize <= 0)
        return;
    encrypted.length = (NSUInteger)encSize;
    [self sendReflectorPayload:encrypted];
}

// ── outgoing helpers ─────────────────────────────────────────────────────

- (BOOL)sendReflectorPayload:(NSData *)payload {
    if (!_hasReplyContext || _socket < 0)
        return NO;

    NSMutableData *packet = [NSMutableData data];
    [packet appendBytes:_replyPrefix length:12];
    [packet appendBytes:&_replyDestination length:4];
    [packet appendBytes:&_localTag length:4];

    uint32_t size = CFSwapInt32HostToBig((uint32_t)payload.length);
    [packet appendBytes:&size length:4];
    [packet appendData:payload];
    while (packet.length % 4)
        [packet appendBytes:"\0" length:1];

    ssize_t sent = sendto(_socket, packet.bytes, packet.length, 0,
                          (struct sockaddr *)&_replyAddress, sizeof(_replyAddress));
    return sent == (ssize_t)packet.length;
}

/// Build and encrypt a tgcalls-format audio packet from our perspective
/// (we are the peer, so outgoing = !TGCall.outgoing).
- (NSData *)encryptedAudioPacketWithOpusFrame:(NSData *)frame seq:(uint32_t)seq {
    return [self encryptedAudioPacketWithOpusFrame:frame seq:seq requiresAck:NO];
}

- (NSData *)encryptedAudioPacketWithOpusFrame:(NSData *)frame
                                          seq:(uint32_t)seq
                                   requiresAck:(BOOL)requiresAck {
    if (!self.callKey.length || frame.length == 0) return nil;

    // Build a minimal 12-byte RTP header.
    uint8_t rtpHeader[12];
    rtpHeader[0] = 0x80;           // V=2
    rtpHeader[1] = 111;            // PT=Opus
    rtpHeader[2] = (uint8_t)(seq >> 8);
    rtpHeader[3] = (uint8_t)seq;
    uint32_t ts = seq * 960;
    rtpHeader[4] = (uint8_t)(ts >> 24); rtpHeader[5] = (uint8_t)(ts >> 16);
    rtpHeader[6] = (uint8_t)(ts >> 8);  rtpHeader[7] = (uint8_t)ts;
    // SSRC: peer is "1" when caller is outgoing==YES, "2" otherwise.
    uint32_t ssrc = self.isOutgoing ? 2 : 1;
    rtpHeader[8]  = (uint8_t)(ssrc >> 24); rtpHeader[9]  = (uint8_t)(ssrc >> 16);
    rtpHeader[10] = (uint8_t)(ssrc >> 8);  rtpHeader[11] = (uint8_t)ssrc;

    uint8_t type = TGCallMessageAudioData;
    NSMutableData *msg = [NSMutableData dataWithCapacity:1 + 12 + frame.length];
    [msg appendBytes:&type length:1];
    [msg appendBytes:rtpHeader length:12];
    [msg appendData:frame];

    NSMutableData *encrypted = [NSMutableData dataWithLength:msg.length + 32];
    // We are the incoming side relative to TGCall, so we use outgoing=0.
    uint32_t mediaSeq = [TGCallMessages markSeq:++_mediaSeqOut requiresAck:requiresAck];
    int encLen = TGCallEncryptPacket(self.callKey.bytes,
                                    self.isOutgoing ? 1 : 0,
                                    0 /* media */,
                                    msg.bytes, msg.length,
                                    mediaSeq,
                                    encrypted.mutableBytes);
    if (encLen <= 0) return nil;
    encrypted.length = (NSUInteger)encLen;
    return encrypted;
}

- (NSData *)encryptedAudioPacketWithRTPPayload:(NSData *)rtpPayload {
    if (!self.callKey.length || rtpPayload.length == 0)
        return nil;

    uint8_t type = TGCallMessageAudioData;
    NSMutableData *msg = [NSMutableData dataWithCapacity:1 + rtpPayload.length];
    [msg appendBytes:&type length:1];
    [msg appendData:rtpPayload];

    NSMutableData *encrypted = [NSMutableData dataWithLength:msg.length + 32];
    uint32_t mediaSeq = [TGCallMessages markSeq:++_mediaSeqOut requiresAck:NO];
    int encLen = TGCallEncryptPacket(self.callKey.bytes,
                                     self.isOutgoing ? 1 : 0,
                                     0 /* media */,
                                     msg.bytes, msg.length,
                                     mediaSeq,
                                     encrypted.mutableBytes);
    if (encLen <= 0)
        return nil;
    encrypted.length = (NSUInteger)encLen;
    return encrypted;
}

- (BOOL)sendRawToLastReflector:(NSData *)bytes {
    if (!_hasReplyContext || _socket < 0 || bytes.length == 0)
        return NO;
    ssize_t sent = sendto(_socket, bytes.bytes, bytes.length, 0,
                          (struct sockaddr *)&_replyAddress, sizeof(_replyAddress));
    return sent == (ssize_t)bytes.length;
}

@end
