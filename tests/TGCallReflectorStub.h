// TGCallReflectorStub.h — an in-process reflector bridge for unit tests.
//
// Instead of real UDP sockets and a remote reflector server, this stub holds
// two TGCallReflector instances and routes packets between them synchronously
// (or asynchronously on the main queue), keeping unit tests deterministic and
// network-free.
//
// Usage:
//   TGCallReflector *sideA = ...;  // the "app" side (TGCall)
//   TGCallReflector *sideB = ...;  // the "peer" side (TGCallPeer)
//   TGCallReflectorStub *stub = [[TGCallReflectorStub alloc] init];
//   [stub connectSideA:sideA sideB:sideB];
//
// After that, any -sendPayload:toTag: on sideA triggers sideB.onPacket with
// the raw payload bytes (the reflector header is stripped), and vice-versa.
//
#import <Foundation/Foundation.h>
@class TGCallReflector;

@interface TGCallReflectorStub : NSObject

/// Connect two reflector instances through this stub.  Replaces their
/// `send` paths with in-process delivery.
- (void)connectSideA:(TGCallReflector *)a sideB:(TGCallReflector *)b;

/// Number of packets forwarded in each direction since last reset.
@property (nonatomic, readonly) uint32_t packetsAtoB;
@property (nonatomic, readonly) uint32_t packetsBtoA;

- (void)resetCounters;

@end
