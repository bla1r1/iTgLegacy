//
// TGVoiceDecoder - Opus to WAV, because iOS 7 cannot play Opus.
//
#import <Foundation/Foundation.h>

@interface TGVoiceDecoder : NSObject

/// Decode an Ogg Opus voice note into a 16-bit PCM WAV in the temp directory.
/// Returns the path, or nil. Call off the main thread: it decodes the whole
/// file in one pass.
+ (NSString *)wavFromOpusFile:(NSString *)opusPath;

@end
