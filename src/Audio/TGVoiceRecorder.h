//
// TGVoiceRecorder - record a voice note.
//
// Records linear PCM with AVAudioRecorder, then encodes it to Ogg Opus with
// libopusenc, which is the format Telegram expects. iOS has no Opus encoder of
// its own, which is why libopus and the opusenc sources are in the tree - the
// mirror image of TGVoiceDecoder.
//
#import <Foundation/Foundation.h>

@interface TGVoiceRecorder : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL recording;
/// Seconds captured so far, for the UI to show.
@property (nonatomic, readonly) NSTimeInterval duration;

- (BOOL)start;
/// Stops and encodes. `completion` gets the .oga path and its duration, or nil.
- (void)stopWithCompletion:(void (^)(NSString *path, NSTimeInterval duration))completion;
- (void)cancel;

@end
