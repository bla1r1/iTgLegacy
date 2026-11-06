// tests/shim/AVFoundation/AVFoundation.h — macOS test shim.
//
// TGCall.mm is an iOS translation unit: it configures AVAudioSession, which
// does not exist on macOS. The call-stack tests run on a plain macOS
// command-line binary, so this header stands in for the one framework symbol
// the tests need. It must stay first on the include path so that
// <AVFoundation/AVFoundation.h> resolves here rather than to the SDK.
//
// Nothing in here makes sound; it only lets TGCall's session calls run as
// no-ops while the rest of the test exercises signalling and sockets.
#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMedia/CoreMedia.h>

typedef NSString *AVAudioSessionCategory;
typedef NSString *AVAudioSessionMode;
typedef NSUInteger AVAudioSessionCategoryOptions;

extern AVAudioSessionCategory const AVAudioSessionCategoryPlayAndRecord;
extern AVAudioSessionCategoryOptions const AVAudioSessionCategoryOptionAllowBluetooth;
extern AVAudioSessionMode const AVAudioSessionModeVoiceChat;

typedef NS_ENUM(NSUInteger, AVAudioSessionPortOverride) {
	AVAudioSessionPortOverrideNone = 0,
	AVAudioSessionPortOverrideSpeaker = 1936748594,
};

typedef NS_ENUM(NSInteger, AVCaptureDevicePosition) {
	AVCaptureDevicePositionUnspecified = 0,
	AVCaptureDevicePositionBack = 1,
	AVCaptureDevicePositionFront = 2,
};

typedef NSString *AVCaptureSessionPreset;
extern AVCaptureSessionPreset const AVCaptureSessionPreset640x480;
extern AVCaptureSessionPreset const AVCaptureSessionPreset352x288;
extern AVCaptureSessionPreset const AVCaptureSessionPresetMedium;

extern NSString * const AVMediaTypeVideo;

typedef NS_ENUM(NSInteger, AVCaptureVideoOrientation) {
	AVCaptureVideoOrientationPortrait = 1,
	AVCaptureVideoOrientationPortraitUpsideDown = 2,
	AVCaptureVideoOrientationLandscapeRight = 3,
	AVCaptureVideoOrientationLandscapeLeft = 4,
};

@interface AVCaptureConnection : NSObject
@property (nonatomic, assign) AVCaptureVideoOrientation videoOrientation;
@property (nonatomic, readonly) BOOL isVideoOrientationSupported;
@end

@interface AVCaptureDevice : NSObject
@property (nonatomic, readonly) AVCaptureDevicePosition position;
@property (nonatomic, assign) CMTime activeVideoMinFrameDuration;
@property (nonatomic, assign) CMTime activeVideoMaxFrameDuration;
+ (NSArray *)devicesWithMediaType:(NSString *)mediaType;
+ (AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType;
- (BOOL)lockForConfiguration:(NSError **)outError;
- (void)unlockForConfiguration;
@end

@interface AVCaptureDeviceInput : NSObject
+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError;
@end

@protocol AVCaptureVideoDataOutputSampleBufferDelegate <NSObject>
@end

@interface AVCaptureOutput : NSObject
- (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType;
@end

@interface AVCaptureVideoDataOutput : AVCaptureOutput
@property (nonatomic, copy) NSDictionary *videoSettings;
@property (nonatomic, assign) BOOL alwaysDiscardsLateVideoFrames;
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)queue;
@end

@interface AVCaptureSession : NSObject
@property (nonatomic, copy) AVCaptureSessionPreset sessionPreset;
@property (nonatomic, readonly) BOOL isRunning;
- (BOOL)canSetSessionPreset:(AVCaptureSessionPreset)preset;
- (void)beginConfiguration;
- (void)commitConfiguration;
- (BOOL)canAddInput:(id)input;
- (void)addInput:(id)input;
- (void)removeInput:(id)input;
- (BOOL)canAddOutput:(id)output;
- (void)addOutput:(id)output;
- (void)removeOutput:(id)output;
- (void)startRunning;
- (void)stopRunning;
@end

@interface AVCaptureVideoPreviewLayer : CALayer
+ (instancetype)layerWithSession:(AVCaptureSession *)session;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, copy) NSString *videoGravity;
@end

@interface AVSampleBufferDisplayLayer : CALayer
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)flush;
- (void)flushAndRemoveImage;
@property (nonatomic, readonly) BOOL isReadyForMoreMediaData;
@end

@interface AVAudioSession : NSObject

+ (AVAudioSession *)sharedInstance;

- (BOOL)setCategory:(AVAudioSessionCategory)category
		withOptions:(AVAudioSessionCategoryOptions)options
			  error:(NSError **)outError;
- (BOOL)setMode:(AVAudioSessionMode)mode error:(NSError **)outError;
- (BOOL)setActive:(BOOL)active error:(NSError **)outError;
- (BOOL)overrideOutputAudioPort:(AVAudioSessionPortOverride)portOverride
						  error:(NSError **)outError;

@end
