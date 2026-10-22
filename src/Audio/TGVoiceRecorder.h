//
// TGVoiceRecorder - records linear PCM and encodes to Ogg Opus with libopusenc.
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
