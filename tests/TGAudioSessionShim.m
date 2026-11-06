// TGAudioSessionShim.m — macOS implementation of the AVAudioSession test shim.
//
// See tests/shim/AVFoundation/AVFoundation.h. Every call succeeds and does
// nothing: the tests care about TGCall's state machine and sockets, not about
// audio routing.
#import <AVFoundation/AVFoundation.h>

AVAudioSessionCategory const AVAudioSessionCategoryPlayAndRecord = @"AVAudioSessionCategoryPlayAndRecord";
AVAudioSessionCategoryOptions const AVAudioSessionCategoryOptionAllowBluetooth = 1 << 2;
AVAudioSessionMode const AVAudioSessionModeVoiceChat = @"AVAudioSessionModeVoiceChat";

AVCaptureSessionPreset const AVCaptureSessionPreset640x480 = @"AVCaptureSessionPreset640x480";
AVCaptureSessionPreset const AVCaptureSessionPreset352x288 = @"AVCaptureSessionPreset352x288";
AVCaptureSessionPreset const AVCaptureSessionPresetMedium = @"AVCaptureSessionPresetMedium";

NSString * const AVMediaTypeVideo = @"vide";

@implementation AVCaptureConnection
@end

@implementation AVCaptureDevice
+ (NSArray *)devicesWithMediaType:(NSString *)mediaType { return @[]; }
+ (AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType { return nil; }
- (BOOL)lockForConfiguration:(NSError **)outError { return YES; }
- (void)unlockForConfiguration {}
@end

@implementation AVCaptureDeviceInput
+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
	return [[self alloc] init];
}
@end

@implementation AVCaptureOutput
@end

@implementation AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {}
@end

@implementation AVCaptureSession
- (BOOL)canSetSessionPreset:(id)preset { return YES; }
- (void)beginConfiguration {}
- (void)commitConfiguration {}
- (BOOL)canAddInput:(id)input { return YES; }
- (void)addInput:(id)input {}
- (void)removeInput:(id)input {}
- (BOOL)canAddOutput:(id)output { return YES; }
- (void)addOutput:(id)output {}
- (void)removeOutput:(id)output {}
- (void)startRunning {}
- (void)stopRunning {}
@end

@implementation AVCaptureVideoPreviewLayer
+ (instancetype)layerWithSession:(AVCaptureSession *)session {
	return [[self alloc] init];
}
@end

@implementation AVSampleBufferDisplayLayer
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {}
- (void)flush {}
- (void)flushAndRemoveImage {}
- (BOOL)isReadyForMoreMediaData { return YES; }
@end

@implementation AVAudioSession

+ (AVAudioSession *)sharedInstance {
	static AVAudioSession *session = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ session = [[AVAudioSession alloc] init]; });
	return session;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
		withOptions:(AVAudioSessionCategoryOptions)options
			  error:(NSError **)outError {
	if (outError) *outError = nil;
	return YES;
}

- (BOOL)setMode:(AVAudioSessionMode)mode error:(NSError **)outError {
	if (outError) *outError = nil;
	return YES;
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
	if (outError) *outError = nil;
	return YES;
}

- (BOOL)overrideOutputAudioPort:(AVAudioSessionPortOverride)portOverride
						  error:(NSError **)outError {
	if (outError) *outError = nil;
	return YES;
}

@end
