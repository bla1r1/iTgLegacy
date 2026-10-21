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
}
@property (nonatomic, readwrite) NSString *ufrag;
@property (nonatomic, readwrite) NSString *pwd;
@property (nonatomic, readwrite) uint16_t listenPort;
@property (nonatomic, readwrite) uint32_t stunRequestsReceived;
@property (nonatomic, readwrite) uint32_t stunResponsesReceived;
@property (nonatomic, readwrite) uint32_t audioFramesReceived;
@property (nonatomic, readwrite) uint32_t decryptFailures;
@property (nonatomic, assign) uint32_t mediaSeqOut;
@end

@implementation TGCallPeer

- (instancetype)init {
    if ((self = [super init])) {
        _socket = -1;
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
    if (s >= 0) close(s);
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

- (void)handlePacket:(NSData *)packet fromAddress:(NSData *)addrData {
    int stunType = [TGCallStun messageTypeOf:packet];

    if (stunType == 0x0001) {
        // Incoming connectivity check → respond.
        _stunRequestsReceived++;
        if (_stunRequestsReceived == 1 && self.onStunCheckReceived)
            self.onStunCheckReceived();

        NSData *response = [TGCallStun bindingResponseTo:packet
                                               password:self.pwd
                                            fromAddress:addrData];
        if (response) {
            const struct sockaddr_in *to = (const struct sockaddr_in *)addrData.bytes;
            sendto(_socket, response.bytes, response.length, 0,
                   (const struct sockaddr *)to, sizeof(*to));
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
    uint32_t markedSeq = [TGCallMessages markSeq:seq requiresAck:NO];
    for (NSDictionary *msg in [TGCallMessages parseMediaPacket:data seq:markedSeq]) {
        uint8_t type = [msg[@"type"] unsignedCharValue];
        if (type == TGCallMessageAudioData) {
            _audioFramesReceived++;
            NSData *rtpPayload = msg[@"body"];
            // Strip 12-byte RTP header → raw Opus frame.
            if (rtpPayload.length > 12) {
                NSData *opus = [rtpPayload subdataWithRange:
                                NSMakeRange(12, rtpPayload.length - 12)];
                if (self.onAudioFrame) self.onAudioFrame(opus);
            }
        }
    }
}

// ── outgoing helpers ─────────────────────────────────────────────────────

/// Build and encrypt a tgcalls-format audio packet from our perspective
/// (we are the peer, so outgoing = !TGCall.outgoing).
- (NSData *)encryptedAudioPacketWithOpusFrame:(NSData *)frame seq:(uint32_t)seq {
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
    uint32_t mediaSeq = [TGCallMessages markSeq:++_mediaSeqOut requiresAck:NO];
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

@end
