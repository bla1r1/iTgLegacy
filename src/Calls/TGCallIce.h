//
// TGCallIce - one UDP socket, and the connectivity checks over it.
//
// A full ICE agent gathers candidates, forms pairs, and nominates one. This
// needs less: the peer sends its addresses over the signalling channel, we
// send a check to each and keep the one that answers. Our own address is never
// advertised usefully - behind a carrier NAT it would be wrong - but that does
// not matter, because a check arriving from an unknown address is exactly what
// the other agent turns into a peer-reflexive candidate and replies to.
//
#import <Foundation/Foundation.h>

@interface TGCallIce : NSObject

/// Credentials from the signalling exchange. Ours sign what we receive,
/// theirs sign what we send.
@property (nonatomic, strong) NSString *localUfrag;
@property (nonatomic, strong) NSString *localPwd;
@property (nonatomic, strong) NSString *peerUfrag;
@property (nonatomic, strong) NSString *peerPwd;

/// Fired on the main queue the first time a check is answered.
@property (nonatomic, copy) void (^onConnected)(NSString *address, uint16_t port);
/// Everything that is not STUN: the media stream.
@property (nonatomic, copy) void (^onMedia)(NSData *packet);

/// Where checks go. Left nil, the class uses its own socket and talks to peer
/// addresses directly; set, everything rides that instead - which is what a
/// client with no reachable address of its own has to do.
@property (nonatomic, copy) void (^transport)(NSData *packet);

- (BOOL)start;
- (void)stop;

/// An address to name in the response to a check. WebRTC discards a binding
/// response with no XOR-MAPPED-ADDRESS, so one is always sent - their own
/// server-reflexive address when it is known.
@property (nonatomic, strong) NSData *peerAddress;

/// Add a candidate line as it came over signalling.
- (void)addPeerCandidate:(NSString *)candidate;

/// Send media to whichever address answered.
- (void)sendMedia:(NSData *)payload;

/// A packet that came in over the reflector.
- (void)handleRelayedPacket:(NSData *)packet;

@end
