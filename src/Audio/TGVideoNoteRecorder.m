#import "TGVideoNoteRecorder.h"
#import <AVFoundation/AVFoundation.h>

static const CGFloat kVideoNoteSide = 480.0f;

@interface TGVideoNoteRecorder () <AVCaptureFileOutputRecordingDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureMovieFileOutput *output;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, copy) NSString *rawPath;
@property (nonatomic, copy) NSString *finalPath;
@property (nonatomic, copy) void (^completion)(NSString *, NSTimeInterval);
@property (nonatomic, assign) NSTimeInterval recordedDuration;
@property (nonatomic, assign) BOOL isRecordingFlag;
@end

@implementation TGVideoNoteRecorder

+ (instancetype)shared {
	static TGVideoNoteRecorder *one;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ one = [[TGVideoNoteRecorder alloc] init]; });
	return one;
}

- (BOOL)recording {
	return self.isRecordingFlag;
}

- (NSTimeInterval)duration {
	return self.startedAt ? -[self.startedAt timeIntervalSinceNow] : 0;
}

- (BOOL)start {
	if (self.isRecordingFlag)
		return YES;

	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	session.sessionPreset = AVCaptureSessionPreset640x480;

	AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *candidate in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
		if (candidate.position == AVCaptureDevicePositionFront){
			camera = candidate;
			break;
		}
	if (!camera)
		return NO;
	NSError *error = nil;
	AVCaptureDeviceInput *video = [AVCaptureDeviceInput deviceInputWithDevice:camera
																		error:&error];
	if (!video){
		NSLog(@"TGVideoNoteRecorder: camera input: %@", error);
		return NO;
	}
	if ([session canAddInput:video])
		[session addInput:video];

	AVCaptureDevice *microphone = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	if (microphone){
		AVCaptureDeviceInput *audio = [AVCaptureDeviceInput deviceInputWithDevice:microphone
																			 error:&error];
		if (audio && [session canAddInput:audio])
			[session addInput:audio];
	}

	AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
	if (![session canAddOutput:output])
		return NO;
	[session addOutput:output];
	AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
	if ([connection isVideoOrientationSupported])
		connection.videoOrientation = AVCaptureVideoOrientationPortrait;

	self.session = session;
	self.output = output;
	self.rawPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note-raw.mov"];
	[[NSFileManager defaultManager] removeItemAtPath:self.rawPath error:nil];
	self.finalPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note.mov"];
	[[NSFileManager defaultManager] removeItemAtPath:self.finalPath error:nil];
	self.recordedDuration = 0;
	self.completion = nil;

	[session startRunning];
	[output startRecordingToOutputFileURL:[NSURL fileURLWithPath:self.rawPath]
						recordingDelegate:self];
	self.startedAt = [NSDate date];
	self.isRecordingFlag = YES;
	return YES;
}

- (void)stopWithCompletion:(void (^)(NSString *, NSTimeInterval))completion {
	if (!self.isRecordingFlag){
		if (completion) completion(nil, 0);
		return;
	}
	self.recordedDuration = self.duration;
	self.completion = [completion copy];
	[self.output stopRecording];
}

- (void)cancel {
	self.completion = nil;
	self.isRecordingFlag = NO;
	if (self.output.isRecording)
		[self.output stopRecording];
	[self.session stopRunning];
	self.session = nil;
	self.output = nil;
	self.startedAt = nil;
	[[NSFileManager defaultManager] removeItemAtPath:self.rawPath error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:self.finalPath error:nil];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
		didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
		fromConnections:(NSArray *)connections
		error:(NSError *)error {
	[self.session stopRunning];
	self.session = nil;
	self.output = nil;
	self.startedAt = nil;
	self.isRecordingFlag = NO;

	if (error || ![[NSFileManager defaultManager] fileExistsAtPath:self.rawPath]){
		void (^done)(NSString *, NSTimeInterval) = self.completion;
		self.completion = nil;
		if (done)
			done(nil, 0);
		return;
	}
	[self exportSquareFrom:self.rawPath duration:self.recordedDuration];
}

- (void)exportSquareFrom:(NSString *)path duration:(NSTimeInterval)duration {
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path]
											options:nil];
	AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
	if (!track){
		if (self.completion) self.completion(nil, 0);
		self.completion = nil;
		return;
	}
	CGSize natural = track.naturalSize;
	CGFloat side = MIN(natural.width, natural.height);
	if (side <= 0)
		side = 480;
	CGFloat scale = kVideoNoteSide / side;

	AVMutableVideoCompositionLayerInstruction *layer =
			[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
	CGAffineTransform transform = CGAffineTransformMakeTranslation(
			-(natural.width - side) / 2.0f, -(natural.height - side) / 2.0f);
	transform = CGAffineTransformConcat(transform,
			CGAffineTransformMakeScale(scale, scale));
	[layer setTransform:transform atTime:kCMTimeZero];

	AVMutableVideoCompositionInstruction *instruction =
			[AVMutableVideoCompositionInstruction videoCompositionInstruction];
	instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
	instruction.layerInstructions = @[layer];

	AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
	composition.renderSize = CGSizeMake(kVideoNoteSide, kVideoNoteSide);
	composition.frameDuration = CMTimeMake(1, 30);
	composition.instructions = @[instruction];

	[[NSFileManager defaultManager] removeItemAtPath:self.finalPath error:nil];
	AVAssetExportSession *export = [[AVAssetExportSession alloc]
			initWithAsset:asset presetName:AVAssetExportPresetMediumQuality];
	export.outputURL = [NSURL fileURLWithPath:self.finalPath];
	export.outputFileType = AVFileTypeQuickTimeMovie;
	export.videoComposition = composition;
	export.shouldOptimizeForNetworkUse = YES;

	__weak typeof(self) weakSelf = self;
	[export exportAsynchronouslyWithCompletionHandler:^{
		TGVideoNoteRecorder *me = weakSelf;
		void (^done)(NSString *, NSTimeInterval) = me.completion;
		me.completion = nil;
		NSString *answer = export.status == AVAssetExportSessionStatusCompleted
				? me.finalPath : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (done)
				done(answer, duration);
		});
	}];
}

@end
