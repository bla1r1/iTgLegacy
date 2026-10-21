// TGLibTgvoipBridge.h — Objective-C face for libtgvoip's C++ hooks.
//
// TGCall.mm installs OpenSSL-backed functions into VoIPController::crypto and
// provides the empty video capability hooks. Those symbols live in C++, so this
// small bridge lets the Objective-C tests call them without making the whole
// test suite Objective-C++.
#import <Foundation/Foundation.h>

@interface TGLibTgvoipBridge : NSObject

/// YES when every crypto pointer was filled in by TGCall.
+ (BOOL)cryptoInstalled;

+ (NSData *)randomBytesOfLength:(NSUInteger)length;
+ (NSData *)sha1OfData:(NSData *)data;
+ (NSData *)sha256OfData:(NSData *)data;

+ (NSData *)igeRoundTrip:(NSData *)data key:(NSData *)key iv:(NSData *)iv;
+ (NSData *)cbcRoundTrip:(NSData *)data key:(NSData *)key iv:(NSData *)iv;
+ (NSData *)ctrRoundTrip:(NSData *)data key:(NSData *)key iv:(NSData *)iv;

+ (NSUInteger)availableEncoderCount;
+ (NSUInteger)availableDecoderCount;
+ (int)maximumResolution;

@end
