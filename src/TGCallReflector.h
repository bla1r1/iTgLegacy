//
// TGCallReflector - the UDP link to a Telegram call reflector.
//
// The reflector is not a TURN server, whatever the surrounding WebRTC code in
// tgcalls suggests: ReflectorPort.cpp writes plain UDP with a small header.
// Every packet starts with a 16-byte peer tag - twelve bytes handed out by
// TDLib, then four that identify one side of the call - and the two ends find
// each other by that tag alone.
//
//   ping   tag(16) 0xFF*12 0xFE 0xFF*3 be64(123), padded to 4
//   data   destinationTag(16) ourTag4(4) be32(size) payload, padded to 4
//
#import <Foundation/Foundation.h>

@interface TGCallReflector : NSObject

/// `peerTag` is the 16 bytes TDLib gave for this server.
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port
                     peerTag:(NSData *)peerTag;

/// Our four identifying bytes, which the other side needs before it can send
/// anything back. They travel over the signalling channel.
@property (nonatomic, readonly) uint32_t localTag;
/// Set once the other side's four bytes are known.
@property (nonatomic, assign) uint32_t remoteTag;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) uint16_t port;

/// Main queue, for every datagram that arrives.
@property (nonatomic, copy) void (^onPacket)(NSData *payload);

- (BOOL)start;
- (void)stop;
- (void)sendPayload:(NSData *)payload;

/// Send to one particular tag. The peer runs a port per network interface,
/// each with its own four bytes, so an answer belongs to whichever one asked.
- (void)sendPayload:(NSData *)payload toTag:(uint32_t)tag;

@end
