//
// TGVideoNoteRecorder - a square round-video note recorder for iOS 6–12.
//
// AVCaptureMovieFileOutput records the camera's native frame; a video note is
// square, so the file is cropped and scaled to 480x480 with a video
// composition before it is handed to TDLib.
//
#import <Foundation/Foundation.h>

@interface TGVideoNoteRecorder : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, readonly) NSTimeInterval duration;

- (BOOL)start;
- (void)stopWithCompletion:(void (^)(NSString *path, NSTimeInterval duration))completion;
- (void)cancel;

@end
