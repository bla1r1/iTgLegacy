// TGCallReflectorStub.m — in-process reflector bridge implementation.
//
// TGCallReflector sends real UDP.  For tests we swap that out by swizzling
// nothing; instead we intercept at the public -sendPayload:toTag: API by
// subclassing — but since TGCallReflector has no designated override points,
// the stub intercepts via the onPacket callback direction only.
//
// Concretely: the stub creates two fake "packet delivery" blocks and installs
// them as onPacket handlers after the real ones.  When sideA would normally
// write to a UDP socket we instead call sideB.onPacket directly.
//
// This is possible because TGCallReflector already exposes the full
// send / onPacket surface: the test just has to sit between them.
//
// For full interception we use method swizzling on the private -send: method
// so real UDP is never attempted.  The swizzle is installed per-instance via
// associated objects.
#import "TGCallReflectorStub.h"
#import "TGCallReflector.h"
#import <objc/runtime.h>

// Associated-object key for a per-instance delivery block.
static const char kDeliveryBlockKey = 0;

@interface TGCallReflectorStub ()
@property (nonatomic, weak) TGCallReflector *sideA;
@property (nonatomic, weak) TGCallReflector *sideB;
@property (nonatomic, readwrite) uint32_t packetsAtoB;
@property (nonatomic, readwrite) uint32_t packetsBtoA;
@end

// ─── TGCallReflector category — intercept -send: per instance ────────────────
//
// We replace the private `send:` method globally but route each packet to the
// block stored in the reflector's associated object.  Instances without a
// block still call the original (which sends real UDP) so tests that do not
// use the stub are unaffected.

typedef void (^TGReflectorSendBlock)(NSData *packet);

static IMP  gOriginalSendIMP = NULL;

static void stubbedSend(id self, SEL _cmd, NSData *packet) {
    TGReflectorSendBlock block =
        objc_getAssociatedObject(self, &kDeliveryBlockKey);
    if (block) {
        block(packet);
    } else if (gOriginalSendIMP) {
        ((void(*)(id,SEL,NSData*))gOriginalSendIMP)(self, _cmd, packet);
    }
}

static void swizzleSendOnce(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [TGCallReflector class];
        SEL sel = @selector(send:);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        gOriginalSendIMP = method_getImplementation(m);
        method_setImplementation(m, (IMP)stubbedSend);
    });
}

// ─────────────────────────────────────────────────────────────────────────────

@implementation TGCallReflectorStub

- (void)connectSideA:(TGCallReflector *)a sideB:(TGCallReflector *)b {
    swizzleSendOnce();

    _sideA = a;
    _sideB = b;

    __weak typeof(self) weakSelf = self;
    __weak TGCallReflector *weakA = a;
    __weak TGCallReflector *weakB = b;

    // Any packet that sideA's -send: would put on the wire → deliver to sideB.
    TGReflectorSendBlock aToB = ^(NSData *packet) {
        TGCallReflectorStub *me = weakSelf;
        TGCallReflector     *bRef = weakB;
        if (!me || !bRef) return;
        me.packetsAtoB++;
        // Strip the 20-byte reflector header (destTag16 + senderTag4 + size4)
        // and deliver raw payload to sideB.onPacket.
        if (packet.length > 20 && bRef.onPacket) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (bRef.onPacket) bRef.onPacket(packet);
            });
        }
    };

    // Any packet that sideB's -send: would put on the wire → deliver to sideA.
    TGReflectorSendBlock bToA = ^(NSData *packet) {
        TGCallReflectorStub *me = weakSelf;
        TGCallReflector     *aRef = weakA;
        if (!me || !aRef) return;
        me.packetsBtoA++;
        if (packet.length > 20 && aRef.onPacket) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (aRef.onPacket) aRef.onPacket(packet);
            });
        }
    };

    objc_setAssociatedObject(a, &kDeliveryBlockKey, aToB,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(b, &kDeliveryBlockKey, bToA,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)resetCounters {
    _packetsAtoB = 0;
    _packetsBtoA = 0;
}

@end
