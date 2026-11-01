//
// TGWebMDecoder.h - Lightweight WebM VP9 video sticker decoder for iOS.
//
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface TGWebMDecoder : NSObject

/// Decodes a WebM video sticker (VP9 with optional alpha stream) into an array of CGImageRef frames.
/// Returns an NSArray of id (where each element is a (__bridge id)CGImageRef).
/// Returns nil if decoding fails.
+ (NSArray *)decodeFramesFromFile:(NSString *)path
                              fps:(double *)outFps
                         duration:(NSTimeInterval *)outDuration;

/// Returns the first frame of a WebM file as a UIImage using early-exit keyframe decoding.
+ (UIImage *)firstFrameFromFile:(NSString *)path;

@end

/// Streaming WebM player that maintains an open demuxer and decoder state,
/// decoding on-demand on CADisplayLink ticks into a pre-allocated 3-frame cyclic ring buffer.
@interface TGWebMStreamPlayer : NSObject

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) double fps;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) CGSize pixelSize;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, weak) CALayer *targetLayer;
@property (nonatomic, copy) void (^onFrame)(CGImageRef frame);

- (instancetype)initWithPath:(NSString *)path;
- (void)play;
- (void)stop;
- (void)pause;
- (CGImageRef)currentFrameImage;
- (CGImageRef)decodeNextFrame;

@end
