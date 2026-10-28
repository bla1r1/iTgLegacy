//
// TGStreamingVoicePlayer.h - Low-footprint streaming audio player for Ogg Opus voice notes.
// Streams PCM directly into CoreAudio AudioQueue without disk-based WAV decompression.
//
#import <Foundation/Foundation.h>

@protocol TGStreamingVoicePlayerDelegate <NSObject>
@optional
- (void)audioPlayerDidFinishPlaying:(id)player successfully:(BOOL)flag;
@end

@interface TGStreamingVoicePlayer : NSObject

- (instancetype)initWithPath:(NSString *)path error:(NSError **)outError;

- (BOOL)play;
- (void)pause;
- (void)stop;

@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, assign) float rate;
@property (nonatomic, assign) BOOL enableRate;
@property (nonatomic, weak) id<TGStreamingVoicePlayerDelegate> delegate;

@end
