//
// TGSoftVideoPlayer.h - software H.264/AAC playback for Vintage devices.
//
// The A4 decoder stops at H.264 Main, 720p, 30 fps. Current Telegram clips
// are High Profile at 60 fps, so AVPlayer returns -11800/-12842 and shows no
// picture. FFmpeg has the decoders; this class feeds them from a serial
// background thread and draws YUV through OpenGL ES 2.
//
// Only armv7 has an implementation. The arm64 build compiles a stub so the
// class still links; no arm64 device needs it.
//
#import <UIKit/UIKit.h>

@interface TGSoftVideoPlayer : NSObject

/// The view to put in the page. It is the player's own layer-backed view,
/// created even before playback starts. Nil on arm64.
@property (nonatomic, strong, readonly) UIView *view;

/// Seconds, 0 until the container has been read.
@property (nonatomic, readonly) NSTimeInterval duration;
/// Seconds on the audio clock, or the wall clock for a silent GIF.
@property (nonatomic, readonly) NSTimeInterval position;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;

/// A GIF loops without calling `finished`.
@property (nonatomic, assign) BOOL loops;

/// Called on the main thread at the end of a non-looping file.
@property (nonatomic, copy) void (^finished)(void);
/// Called on the main thread when the file cannot be decoded.
@property (nonatomic, copy) void (^failed)(NSError *error);

/// Nil only for an empty path. A file that cannot be opened reports through
/// `failed` on the main thread, the same path a decode error takes, so the
/// caller shows its existing AVPlayer-failure alert.
- (instancetype)initWithPath:(NSString *)path;

- (void)play;
- (void)pause;
- (void)seekToTime:(NSTimeInterval)time;
- (void)stop;

@end
