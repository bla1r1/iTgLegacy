//
// TGVideoNoteRecorder - a square round-video note recorder for iOS 6–12.
//
// AVCaptureMovieFileOutput records the camera's native frame; a video note is
// square, so the file is cropped and scaled to at most 480x480 with a video
// composition before it is handed to TDLib.
//
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface TGVideoNoteRecorder : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) BOOL isFrontCamera;   ///< which side the lens looks
@property (nonatomic, readonly) AVCaptureSession *session;

/// Fires once once the lens is up and running (main queue). The overlay adds
/// the preview layer here instead of waiting for `start` to return - warm-up
/// is off-thread, so the overlay is already on screen by then.
@property (nonatomic, copy) void (^onSession)(AVCaptureSession *session);
/// Fires once the file open lands and the clock may count (main queue).
@property (nonatomic, copy) void (^onReady)(void);
/// The lens changed; a preview must ask for portrait again (main queue).
@property (nonatomic, copy) void (^onCameraSwitched)(void);
/// The side of the square a finished note was exported at.
@property (nonatomic, readonly) NSInteger noteSide;

- (BOOL)start;
- (void)pause;
- (void)resume;
/// `completion` runs on the main queue, after the export.
- (void)stopWithCompletion:(void (^)(NSString *path, NSTimeInterval duration))completion;
- (void)switchCamera;
/// Changes lens without losing the note: the running file closes, the lens
/// changes, a new file opens. `completion` runs on the main queue.
- (void)flipCameraWithCompletion:(void (^)(void))completion;
- (void)cancel;

@end
