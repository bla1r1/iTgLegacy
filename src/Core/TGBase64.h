//
// TGBase64.h - base64 across the OS line.
//
// iOS 7 gave NSConcreteData an `initWithBase64EncodedString:` selector; the
// 6.1.6 runtime answers the same call with "unrecognized selector" and the
// exception is fatal on a receive-loop thread. Callsites that must survive
// both OSes - the voice-note waveform inside a message, the call engine's
// keys and signalling - go through these two. The legacy pair named here
// (`initWithBase64Encoding:` / `base64Encoding:`) is iOS 4-era and very
// much alive where it is needed; the gate asks before calling either.
//
#import <Foundation/Foundation.h>

/// nil and empty decode as an empty answer, never a throw.
#ifdef __cplusplus
extern "C" {
#endif

NSData *TGBase64Decode(NSString *b64);

/// nil encodes as an empty string.
NSString *TGBase64Encode(NSData *data);

#ifdef __cplusplus
}
#endif
