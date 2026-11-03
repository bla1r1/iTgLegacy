//
// TGVideoNoteRecorder - a square round-video note recorder for iOS 6–12.
//
// AVCaptureMovieFileOutput records the camera's native frame; a video note is
// square, so the file is cropped and scaled to 480x480 with a video
// composition before it is handed to TDLib.
//
// AVCaptureFileOutput has no pause on iOS - pauseRecording is macOS-only -
// so a pause follows Telegram Android's voice recorder instead: the running
// segment is closed and stashed, and a resume starts another file on the
// still-running session. Sending joins every segment end to end before the
// export hands one note over.
//
#import "TGVideoNoteRecorder.h"
#import "TGDevice.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

/// The largest square Telegram accepts for a video note. A camera with less
/// keeps what it has: nothing is scaled up.
static const CGFloat kVideoNoteSide = 640.0f;
/// The receiver's placeholder: 240 is what the schema asks a note thumbnail to
/// be, and 0.7 keeps the JPEG small enough to upload alongside the note.
static const CGFloat kVideoNoteThumbnailSide = 240.0f;
static const CGFloat kVideoNoteThumbnailQuality = 0.7f;
/// Bits per second for each pixel of the square. The export presets offer 0.7 Mbit/s,
/// which turns a moving face into blocks, or 3.5, which makes a minute 26 MB for
/// everyone who receives it.
static const NSInteger kVideoNoteBitsPerPixel = 8;
static const NSInteger kVideoNoteBitRateMax = 2500000;
static const NSInteger kVideoNoteKeyFrameInterval = 30;
static const NSInteger kVideoNoteAudioRate = 44100;
static const NSInteger kVideoNoteAudioBitRate = 64000;
/// Long enough for the overlay's entrance to be committed before startRunning holds
/// the main thread: what is already animating keeps moving in the render server,
/// what is not yet committed would not start until the camera is up.
static const NSTimeInterval kSessionStartDelay = 0.08;
/// startRecording in the same breath as startRunning killed the note on iOS 6: the
/// output gave up before the first frame found a connection.
static const NSTimeInterval kFileOpenDelay = 0.15;
/// Five progress calls a second is as much as a small ring can show, and on the
/// A4 every main-queue wake is paid for by the transcode.
static const NSTimeInterval kExportProgressStep = 1.0 / 5.0;

@interface TGVideoNoteRecorder () <AVCaptureFileOutputRecordingDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureMovieFileOutput *output;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, copy) NSString *rawPath;
@property (nonatomic, copy) NSString *finalPath;
@property (nonatomic, copy, readwrite) NSString *thumbnailPath;
@property (nonatomic, copy) void (^completion)(NSString *, NSTimeInterval);
@property (nonatomic, assign) NSTimeInterval recordedDuration;
@property (nonatomic, assign) BOOL isRecordingFlag;
@property (nonatomic, assign) BOOL isStartingFlag;
/// The lens warm-up does not belong on the main thread; this token is the
/// guard every late callback checks after a cancel.
@property (nonatomic, assign) NSInteger warmupToken;
/// Running is the session; ready is the file that actually receives frames.
/// The clock counts only from the file, which lands half a second after the
/// lens wakes - the same two-phase warm-up the legacy recorder used.
@property (nonatomic, assign) BOOL isReadyFlag;
/// The segments closed by a pause (or a send) so far, on disk.
@property (nonatomic, strong) NSMutableArray *segmentPaths;
/// A flip waiting for the running file to close.
@property (nonatomic, copy) void (^flipCompletion)(void);
@property (nonatomic, assign, readwrite) NSInteger noteSide;
/// A cancel is closing the running file; its delegate call only cleans up.
@property (nonatomic, assign) BOOL cancelling;
/// How many files a pause_and_all_that_has_resumed promised. The delegate
/// fills segmentPaths asynchronously, so a stop right after a pause waits for
/// the count to catch up instead of exporting with a missing tail.
@property (nonatomic, assign) NSUInteger expectedSegments;
/// Set by a stop that landed while a pause was closing its segment; the
/// delegate finishes the job instead of stashing again.
@property (nonatomic, assign) BOOL pendingStop;
/// Which square the transcode is writing, out of how many. The pump reads
/// these once per sample, so the progress line counts finished segments
/// without keeping any state of its own on the export queue.
@property (nonatomic, assign) NSUInteger exportSegmentIndex;
@property (nonatomic, assign) NSUInteger exportSegmentCount;
@end

@implementation TGVideoNoteRecorder

+ (instancetype)shared {
	static TGVideoNoteRecorder *one;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ one = [[TGVideoNoteRecorder alloc] init]; });
	return one;
}

- (BOOL)recording {
	// "Starting" counts too: no second start may slip in behind the
	// warm-up, and the UI needs the busy state from the first select.
	return self.isRecordingFlag || self.isStartingFlag;
}

/// Only the frames the output wrote count. A pause stops the output, not the
/// wall clock, so the clock is the closed segments plus the running one.
- (NSTimeInterval)duration {
	return self.recordedDuration + (self.startedAt
			? -[self.startedAt timeIntervalSinceNow] : 0);
}

- (BOOL)paused {
	if (!self.isRecordingFlag || !self.isReadyFlag)
		return NO;
	return self.startedAt == nil;
}

- (BOOL)isFrontCamera {
	// A session that never came up has no side; the start path prefers the
	// front lens, so nothing set yet still reads like the one in hand.
	if (!self.session)
		return YES;
	for (AVCaptureDeviceInput *input in self.session.inputs)
		if ([input.device hasMediaType:AVMediaTypeVideo])
			return input.device.position == AVCaptureDevicePositionFront;
	return YES;
}

- (void)pause {
	if (!self.isRecordingFlag || !self.isReadyFlag || !self.startedAt)
		return;
	self.recordedDuration += -[self.startedAt timeIntervalSinceNow];
	self.startedAt = nil;
	if (self.output.isRecording){
		self.expectedSegments++;
		[self.output stopRecording];    // the delegate stashes the file
	}
}

- (void)resume {
	if (!self.isRecordingFlag || !self.isReadyFlag || self.startedAt)
		return;
	// The last segment may still be closing - isRecording lies in the window
	// after startRecording, so the only safe signal is the delegate's own
	// bookkeeping: wait until the stashed count caught up.
	if (self.segmentPaths.count < self.expectedSegments)
		return;
	[self recordSegment];
	self.startedAt = [NSDate date];
}

- (void)recordSegment {
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"video-note-raw-%lu.mov",
					(unsigned long)self.segmentPaths.count]];
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	NSLog(@"TGVideoNoteRecorder: opening segment %@", path.lastPathComponent);
	[self.output startRecordingToOutputFileURL:[NSURL fileURLWithPath:path]
							recordingDelegate:self];
	self.rawPath = path;
}

- (BOOL)start {
	if (self.isRecordingFlag)
		return YES;

	// Leftovers of a previous note: each file was the answer to a send or a
	// cancel that never cleaned up behind itself.
	for (NSInteger i = 0; i < 32; i++){
		NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
				[NSString stringWithFormat:@"video-note-%lu.mov", (long)i]];
		[[NSFileManager defaultManager] removeItemAtPath:base error:nil];
		for (NSString *name in @[@"video-note-square", @"video-note-raw"]){
			NSString *path = [NSString stringWithFormat:@"%@-%ld.mov",
					name, (long)i];
			NSString *full = [NSTemporaryDirectory()
					stringByAppendingPathComponent:path];
			[[NSFileManager defaultManager] removeItemAtPath:full error:nil];
		}
	}

	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	// The hardware encoder does the work, so this costs the A4 little. The Medium
	// preset saved disk and then fed the export an already blocky picture, which
	// the second encode made worse. 720p gives the 640 square Telegram allows, on
	// the devices whose front camera has it.
	session.sessionPreset = ([TGDevice tier] >= TGDeviceTierModern &&
			[session canSetSessionPreset:AVCaptureSessionPreset1280x720])
			? AVCaptureSessionPreset1280x720 : AVCaptureSessionPreset640x480;

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
	self.segmentPaths = [[NSMutableArray alloc] init];
	self.finalPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note.mov"];
	[[NSFileManager defaultManager] removeItemAtPath:self.finalPath error:nil];
	self.thumbnailPath = nil;
	self.recordedDuration = 0;
	self.expectedSegments = 0;
	self.pendingStop = NO;
	self.completion = nil;

	// On the main thread, a turn after the overlay is up. iOS 6 will not finish
	// starting a session anywhere else: from a dispatch queue or from a thread
	// with its own run loop alike, startRunning returns with isRunning still NO,
	// no frame ever arrives and the file fails with AVErrorSessionNotRunning.
	// The price is about 1.2 s of main thread on the A4, behind a screen that
	// has already drawn itself and is not asking for input yet.
	self.cancelling = NO;
	self.warmupToken++;
	NSInteger sessionToken = self.warmupToken;
	self.isStartingFlag = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
			(int64_t)(kSessionStartDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		TGVideoNoteRecorder *me = weakSelf;
		if (!me || me.warmupToken != sessionToken)
			return;
		[session startRunning];
		[me sessionStarted:@[session, @(sessionToken)]];
	});
	return YES;
}

- (void)sessionStarted:(NSArray *)arguments {
	AVCaptureSession *session = arguments[0];
	NSInteger sessionToken = [arguments[1] integerValue];
	if (self.warmupToken != sessionToken){
		[session stopRunning];
		return;
	}
	self.isStartingFlag = NO;
	self.isRecordingFlag = YES;
	self.isReadyFlag = NO;
	self.startedAt = nil;
	NSLog(@"TGVideoNoteRecorder: session running=%d (file pending)", session.isRunning);
	if (self.onSession)
		self.onSession(session);
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
			(int64_t)(kFileOpenDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		TGVideoNoteRecorder *later = weakSelf;
		if (!later || later.warmupToken != sessionToken || later.session != session)
			return;
		[later recordSegment];
		later.startedAt = [NSDate date];
		later.isReadyFlag = YES;
		NSLog(@"TGVideoNoteRecorder: file open, recording begins");
		if (later.onReady)
			later.onReady();
	});
}

- (void)stopWithCompletion:(void (^)(NSString *, NSTimeInterval))completion {
	if (!self.isRecordingFlag){
		if (completion) completion(nil, 0);
		return;
	}
	// An export ends on a thread of its own; whoever asked is drawing a screen,
	// and UIKit off the main thread is a crash waiting for its moment.
	void (^asked)(NSString *, NSTimeInterval) = [completion copy];
	self.completion = ^(NSString *path, NSTimeInterval seconds){
		dispatch_async(dispatch_get_main_queue(), ^{
			if (asked)
				asked(path, seconds);
		});
	};
	// The running file counts: without it a note never paused measured zero,
	// and a note of zero seconds is treated as a stray tap and not sent.
	if (self.startedAt)
		self.recordedDuration += -[self.startedAt timeIntervalSinceNow];
	NSTimeInterval seconds = self.recordedDuration;
	if (self.output.isRecording){
		// A running segment is the tail of the note: the delegate closes it
		// and exports everything as one.
		self.pendingStop = YES;
		self.startedAt = nil;
		[self.output stopRecording];
	} else if (self.segmentPaths.count >= self.expectedSegments){
		// Already paused with every file closed: nothing is in flight.
		self.startedAt = nil;
		[self.session stopRunning];
		self.isRecordingFlag = NO;
		[self exportSquaresFrom:self.segmentPaths duration:seconds];
	} else {
		// Paused, but the pause's segment is still closing; the delegate
		// finds pendingStop and exports then.
		self.pendingStop = YES;
	}
}

- (void)switchCamera {
	if (!self.session)
		return;
	AVCaptureDeviceInput *current = nil;
	for (AVCaptureDeviceInput *input in self.session.inputs)
		if ([input.device hasMediaType:AVMediaTypeVideo]){
			current = input;
			break;
		}
	if (!current)
		return;
	AVCaptureDevicePosition wanted = current.device.position == AVCaptureDevicePositionFront
			? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
	AVCaptureDevice *device = nil;
	for (AVCaptureDevice *candidate in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
		if (candidate.position == wanted){
			device = candidate;
			break;
		}
	if (!device)
		return;
	NSError *error = nil;
	AVCaptureDeviceInput *next = [AVCaptureDeviceInput deviceInputWithDevice:device
																	   error:&error];
	if (!next)
		return;
	[self.session beginConfiguration];
	[self.session removeInput:current];
	if ([self.session canAddInput:next])
		[self.session addInput:next];
	[self.session commitConfiguration];
	AVCaptureConnection *connection = [self.output connectionWithMediaType:AVMediaTypeVideo];
	if ([connection isVideoOrientationSupported])
		connection.videoOrientation = AVCaptureVideoOrientationPortrait;
	if (self.onCameraSwitched)
		self.onCameraSwitched();
}

- (void)flipCameraWithCompletion:(void (^)(void))completion {
	void (^finished)(void) = completion ? [completion copy] : [^{} copy];
	if (!self.startedAt){
		[self switchCamera];
		finished();
		return;
	}
	self.flipCompletion = finished;
	[self pause];
}

- (void)cancel {
	self.completion = nil;
	self.flipCompletion = nil;
	self.onExportProgress = nil;
	self.thumbnailPath = nil;
	self.pendingStop = NO;
	self.isRecordingFlag = NO;
	self.isStartingFlag = NO;
	self.exportSegmentIndex = 0;
	self.exportSegmentCount = 0;
	self.warmupToken++;    // any warm-up callback still in flight stops now
	// The delegate can answer inside stopRecording, before anything below has
	// run, and would export a note nobody wants on the way out.
	self.cancelling = YES;
	if (self.output.isRecording)
		[self.output stopRecording];
	[self.session stopRunning];
	self.session = nil;
	self.output = nil;
	self.startedAt = nil;
	self.recordedDuration = 0;
	self.expectedSegments = 0;
	for (NSString *path in self.segmentPaths)
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	self.segmentPaths = nil;
	[[NSFileManager defaultManager] removeItemAtPath:self.rawPath error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:self.finalPath error:nil];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
		didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
		fromConnections:(NSArray *)connections
		error:(NSError *)error {
	NSString *closed = outputFileURL.path;
	if (self.cancelling){
		self.cancelling = NO;
		[[NSFileManager defaultManager] removeItemAtPath:closed error:nil];
		return;
	}
	BOOL finalStop = (self.startedAt != nil) || self.pendingStop;
	NSLog(@"TGVideoNoteRecorder: segment closed (%d, error=%@)",
			finalStop, error.localizedDescription ?: @"none");

	if (error){
		// A half-written segment is worth as much as none: leave it out and
		// keep counting from the ones that made it.
		NSLog(@"TGVideoNoteRecorder: segment failed: %@", error);
	} else {
		[self.segmentPaths addObject:closed];
	}

	if (!finalStop){
		// A pause closed this one; the session and preview stay up. A flip is a
		// pause with the lens changed in the gap.
		if (self.flipCompletion){
			void (^flipped)(void) = self.flipCompletion;
			self.flipCompletion = nil;
			[self switchCamera];
			[self resume];
			dispatch_async(dispatch_get_main_queue(), flipped);
		}
		return;
	}

	if (self.startedAt == nil && self.segmentPaths.count < self.expectedSegments)
		return;   // the tail behind pendingStop; the next file closes it

	self.pendingStop = NO;
	[self.session stopRunning];
	self.session = nil;
	self.output = nil;
	self.startedAt = nil;
	self.isRecordingFlag = NO;

	if (self.segmentPaths.count == 0){
		void (^done)(NSString *, NSTimeInterval) = self.completion;
		self.completion = nil;
		if (done)
			done(nil, 0);
		return;
	}
	[self exportSquaresFrom:self.segmentPaths duration:self.recordedDuration];
}

- (void)exportSquaresFrom:(NSArray *)paths duration:(NSTimeInterval)duration {
	NSMutableArray *squares = [[NSMutableArray alloc] init];
	self.exportSegmentCount = paths.count;
	self.exportSegmentIndex = 0;
	__weak typeof(self) weakSelf = self;
	[self exportSegment:0 of:paths squares:squares duration:duration done:^{
		[weakSelf joinSquares:squares duration:duration];
	}];
}

/// Crops and scales one raw segment into a square file, then moves to the
/// next. One export at a time: iOS 6's AVAssetExportSession is too small to
/// run two, and the chain keeps that promise without holding itself.
- (void)exportSegment:(NSUInteger)index
				   of:(NSArray *)paths
			  squares:(NSMutableArray *)squares
			 duration:(NSTimeInterval)duration
				 done:(void (^)(void))done {
	if (index >= paths.count){
		done();
		return;
	}
	NSString *inPath = paths[index];
	NSString *outPath = [self squarePathForIndex:index];
	__weak typeof(self) weakSelf = self;

	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:inPath]
											options:nil];
	AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
	if (!track){
		// A segment with no video drags the whole note nowhere.
		[[NSFileManager defaultManager] removeItemAtPath:inPath error:nil];
		[weakSelf exportSegment:index + 1 of:paths squares:squares
					   duration:duration done:done];
		return;
	}

	// The camera writes sideways and says so in the track's transform, which a
	// composition does not apply by itself: without it a portrait note comes
	// out on its side.
	CGSize natural = track.naturalSize;
	CGAffineTransform upright = track.preferredTransform;
	CGRect shown = CGRectApplyAffineTransform(
			CGRectMake(0, 0, natural.width, natural.height), upright);
	CGFloat side = MIN(shown.size.width, shown.size.height);
	if (side <= 0)
		side = 480;
	CGFloat renderSide = MIN(kVideoNoteSide, side);
	self.noteSide = (NSInteger)renderSide;
	CGFloat scale = renderSide / side;
	NSLog(@"TGVideoNoteRecorder: segment %.0fx%.0f shown %.0fx%.0f, square %.0f",
			natural.width, natural.height, shown.size.width, shown.size.height, renderSide);

	AVMutableVideoCompositionLayerInstruction *layer =
			[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
	CGAffineTransform transform = CGAffineTransformConcat(upright,
			CGAffineTransformMakeTranslation(
					-shown.origin.x - (shown.size.width - side) / 2.0f,
					-shown.origin.y - (shown.size.height - side) / 2.0f));
	transform = CGAffineTransformConcat(transform,
			CGAffineTransformMakeScale(scale, scale));
	[layer setTransform:transform atTime:kCMTimeZero];

	AVMutableVideoCompositionInstruction *instruction =
			[AVMutableVideoCompositionInstruction videoCompositionInstruction];
	instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
	instruction.layerInstructions = @[layer];

	AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
	composition.renderSize = CGSizeMake(renderSide, renderSide);
	composition.frameDuration = CMTimeMake(1, 30);
	composition.instructions = @[instruction];

	void (^finished)(BOOL) = ^(BOOL written){
		if (written)
			[squares addObject:outPath];
		[[NSFileManager defaultManager] removeItemAtPath:inPath error:nil];
		[weakSelf exportSegment:index + 1 of:paths squares:squares
					   duration:duration done:done];
	};
	[[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
	NSDate *began = [NSDate date];
	// The pump reads these while this segment is being written; nothing else
	// touches them until it has finished.
	self.exportSegmentIndex = index;
	self.exportSegmentCount = paths.count;
	[self transcodeAsset:asset videoTrack:track composition:composition side:renderSide
				  toPath:outPath completion:^(BOOL written){
		NSLog(@"TGVideoNoteRecorder: transcode %@ in %.1f s", written ? @"done" : @"failed",
				-[began timeIntervalSinceNow]);
		if (written){
			finished(YES);
			return;
		}
		// A note at the preset's rate beats no note at all.
		[[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
		AVAssetExportSession *export = [[AVAssetExportSession alloc]
				initWithAsset:asset presetName:AVAssetExportPresetMediumQuality];
		export.outputURL = [NSURL fileURLWithPath:outPath];
		export.outputFileType = AVFileTypeQuickTimeMovie;
		export.videoComposition = composition;
		export.shouldOptimizeForNetworkUse = YES;
		[export exportAsynchronouslyWithCompletionHandler:^{
			finished(export.status == AVAssetExportSessionStatusCompleted);
		}];
	}];
}

/// AVAssetReader into AVAssetWriter, because only a writer can name the bit rate.
/// Each track feeds its input from its own queue until the reader runs dry.
- (void)transcodeAsset:(AVAsset *)asset
			videoTrack:(AVAssetTrack *)track
		   composition:(AVVideoComposition *)composition
				  side:(CGFloat)side
				toPath:(NSString *)path
			completion:(void (^)(BOOL))completion {
	NSError *error = nil;
	AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
	AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:path]
													 fileType:AVFileTypeQuickTimeMovie error:&error];
	if (!reader || !writer){
		NSLog(@"TGVideoNoteRecorder: transcode setup: %@", error);
		completion(NO);
		return;
	}
	writer.shouldOptimizeForNetworkUse = YES;

	AVAssetReaderVideoCompositionOutput *videoOut = [AVAssetReaderVideoCompositionOutput
			assetReaderVideoCompositionOutputWithVideoTracks:@[track]
											   videoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey :
													   @(kCVPixelFormatType_32BGRA)}];
	videoOut.videoComposition = composition;
	AVAssetWriterInput *videoIn = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
			outputSettings:@{
		AVVideoCodecKey : AVVideoCodecH264,
		AVVideoWidthKey : @(side),
		AVVideoHeightKey : @(side),
		AVVideoCompressionPropertiesKey : @{
			AVVideoAverageBitRateKey : @(MIN((NSInteger)(side * side) * kVideoNoteBitsPerPixel,
					kVideoNoteBitRateMax)),
			AVVideoMaxKeyFrameIntervalKey : @(kVideoNoteKeyFrameInterval),
			AVVideoProfileLevelKey : AVVideoProfileLevelH264Baseline31,
		},
	}];
	if (![reader canAddOutput:videoOut] || ![writer canAddInput:videoIn]){
		completion(NO);
		return;
	}
	[reader addOutput:videoOut];
	[writer addInput:videoIn];

	AVAssetReaderTrackOutput *audioOut = nil;
	AVAssetWriterInput *audioIn = nil;
	AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
	if (audioTrack){
		AudioChannelLayout layout = {0};
		layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
		audioOut = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack
				outputSettings:@{AVFormatIDKey : @(kAudioFormatLinearPCM)}];
		audioIn = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:@{
			AVFormatIDKey : @(kAudioFormatMPEG4AAC),
			AVNumberOfChannelsKey : @1,
			AVSampleRateKey : @(kVideoNoteAudioRate),
			AVEncoderBitRateKey : @(kVideoNoteAudioBitRate),
			AVChannelLayoutKey : [NSData dataWithBytes:&layout length:sizeof(layout)],
		}];
		if ([reader canAddOutput:audioOut] && [writer canAddInput:audioIn]){
			[reader addOutput:audioOut];
			[writer addInput:audioIn];
		} else {
			audioOut = nil;
			audioIn = nil;
		}
	}

	if (![reader startReading] || ![writer startWriting]){
		NSLog(@"TGVideoNoteRecorder: transcode start: %@ %@", reader.error, writer.error);
		completion(NO);
		return;
	}
	[writer startSessionAtSourceTime:kCMTimeZero];

	dispatch_group_t tracks = dispatch_group_create();
	// The pump is shared with audio, and only the video samples say where the
	// note has got to. Reports are throttled to five a second so a thirty-frame
	// second costs five main-queue wakes, not thirty; nothing is allocated for
	// the frames between them.
	NSUInteger segmentIndex = self.exportSegmentIndex;
	NSUInteger segmentCount = self.exportSegmentCount;
	NSTimeInterval segmentSeconds = CMTimeGetSeconds(asset.duration);
	__weak typeof(self) weakSelf = self;
	void (^pump)(AVAssetWriterInput *, AVAssetReaderOutput *, const char *, BOOL) =
			^(AVAssetWriterInput *input, AVAssetReaderOutput *output, const char *name,
					BOOL reportsProgress){
		dispatch_group_enter(tracks);
		__block BOOL over = NO;
		__block CFAbsoluteTime nextReport = 0;
		[input requestMediaDataWhenReadyOnQueue:dispatch_queue_create(name, NULL) usingBlock:^{
			while (!over && input.readyForMoreMediaData){
				CMSampleBufferRef sample = [output copyNextSampleBuffer];
				if (sample && reportsProgress && segmentCount > 0 && segmentSeconds > 0){
					// Wall clock, not the sample's own time: the callback budget
					// is calls per second of the A4's work, wherever the encode
					// happens to be relative to real time.
					CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
					if (now >= nextReport){
						nextReport = now + kExportProgressStep;
						NSTimeInterval at = CMTimeGetSeconds(
								CMSampleBufferGetPresentationTimeStamp(sample));
						CGFloat into = (CGFloat)(MIN(MAX(at, 0), segmentSeconds) /
								segmentSeconds);
						CGFloat fraction = ((CGFloat)segmentIndex + into) /
								(CGFloat)segmentCount;
						dispatch_async(dispatch_get_main_queue(), ^{
							TGVideoNoteRecorder *me = weakSelf;
							if (me.onExportProgress)
								me.onExportProgress(fraction);
						});
					}
				}
				BOOL appended = sample && [input appendSampleBuffer:sample];
				if (sample)
					CFRelease(sample);
				if (!appended){
					over = YES;
					[input markAsFinished];
					dispatch_group_leave(tracks);
				}
			}
		}];
	};
	pump(videoIn, videoOut, "org.legacy.itg.note.video", YES);
	if (audioIn)
		pump(audioIn, audioOut, "org.legacy.itg.note.audio", NO);

	dispatch_group_notify(tracks, dispatch_get_main_queue(), ^{
		BOOL readAll = reader.status == AVAssetReaderStatusCompleted;
		[writer finishWritingWithCompletionHandler:^{
			BOOL written = readAll && writer.status == AVAssetWriterStatusCompleted;
			if (!written)
				NSLog(@"TGVideoNoteRecorder: transcode ended: %@ %@", reader.error, writer.error);
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(written);
			});
		}];
	});
}

- (NSString *)squarePathForIndex:(NSUInteger)index {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"video-note-square-%lu.mov",
					(unsigned long)index]];
}

/// Reads the note's first frame into a JPEG. The export has finished by then;
/// this runs on a low-priority queue because decoding one frame and encoding
/// it is tens of milliseconds on an A4, which the main thread cannot spare
/// while the chat is already showing the new row.
- (NSString *)writeThumbnailAtPath:(NSString *)path {
	if (!path.length)
		return nil;
	NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note-thumb.jpg"];
	[[NSFileManager defaultManager] removeItemAtPath:out error:nil];

	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path]
											options:nil];
	AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
	generator.appliesPreferredTrackTransform = YES;
	generator.maximumSize = CGSizeMake(kVideoNoteThumbnailSide,
			kVideoNoteThumbnailSide);
	NSError *error = nil;
	CGImageRef frame = [generator copyCGImageAtTime:kCMTimeZero
										 actualTime:NULL error:&error];
	if (!frame){
		NSLog(@"TGVideoNoteRecorder: thumbnail failed: %@", error);
		return nil;
	}
	UIImage *image = [UIImage imageWithCGImage:frame];
	CGImageRelease(frame);
	NSData *jpeg = UIImageJPEGRepresentation(image, kVideoNoteThumbnailQuality);
	if (!jpeg || ![jpeg writeToFile:out atomically:YES])
		return nil;
	return out;
}

/// The note is finished; the thumbnail is the last thing before its completion
/// so the caller never sends a note whose preview is still being written.
- (void)finishNoteAtPath:(NSString *)path duration:(NSTimeInterval)duration
					done:(void (^)(NSString *, NSTimeInterval))done {
	if (!done)
		return;
	if (!path){
		self.thumbnailPath = nil;
		done(nil, duration);
		return;
	}
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		TGVideoNoteRecorder *me = weakSelf;
		NSString *thumbnail = [me writeThumbnailAtPath:path];
		dispatch_async(dispatch_get_main_queue(), ^{
			TGVideoNoteRecorder *strong = weakSelf;
			if (strong)
				strong.thumbnailPath = thumbnail;
			done(path, duration);
		});
	});
}

/// One square per segment becomes one note: the tracks are laid end to end and
/// the reel is written out once, untouched. The pieces were cropped and encoded on
/// their own way in, and a third encode is where a paused note would lose detail.
- (void)joinSquares:(NSArray *)squares duration:(NSTimeInterval)duration {
	void (^done)(NSString *, NSTimeInterval) = self.completion;
	self.completion = nil;
	if (!done)
		return;

	NSString *answer = nil;
	NSString *joinedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note-joined.mov"];

	if (squares.count == 0){
		self.thumbnailPath = nil;
		done(nil, 0);
		return;
	}

	if (squares.count == 1){
		answer = squares[0];    // nothing to join, no extra export
	} else {
		AVMutableComposition *composition = [AVMutableComposition composition];
		AVMutableCompositionTrack *video = [composition
				addMutableTrackWithMediaType:AVMediaTypeVideo
							   preferredTrackID:kCMPersistentTrackID_Invalid];
		AVMutableCompositionTrack *audio = [composition
				addMutableTrackWithMediaType:AVMediaTypeAudio
							   preferredTrackID:kCMPersistentTrackID_Invalid];
		CMTime cursor = kCMTimeZero;
		BOOL placed = YES;
		for (NSString *path in squares){
			AVURLAsset *asset = [AVURLAsset URLAssetWithURL:
					[NSURL fileURLWithPath:path] options:nil];
			AVAssetTrack *videoTrack = [[asset tracksWithMediaType:
					AVMediaTypeVideo] firstObject];
			AVAssetTrack *audioTrack = [[asset tracksWithMediaType:
					AVMediaTypeAudio] firstObject];
			CMTimeRange range = CMTimeRangeMake(kCMTimeZero, asset.duration);
			if (videoTrack)
				placed &= [video insertTimeRange:range ofTrack:videoTrack
										  atTime:cursor error:nil];
			if (audioTrack && audio && placed)
				[audio insertTimeRange:range ofTrack:audioTrack
								atTime:cursor error:nil];
			cursor = CMTimeAdd(cursor, asset.duration);
		}

		if (placed && CMTimeGetSeconds(cursor) > 0.1){
			[[NSFileManager defaultManager] removeItemAtPath:joinedPath error:nil];
			AVAssetExportSession *export = [[AVAssetExportSession alloc]
					initWithAsset:composition
						presetName:AVAssetExportPresetPassthrough];
			export.outputURL = [NSURL fileURLWithPath:joinedPath];
			export.outputFileType = AVFileTypeQuickTimeMovie;
			export.shouldOptimizeForNetworkUse = YES;
			NSString *thisAnswer = joinedPath;
			[export exportAsynchronouslyWithCompletionHandler:^{
				NSString *finalAnswer = export.status ==
						AVAssetExportSessionStatusCompleted ? thisAnswer : nil;
				[self finishNoteAtPath:finalAnswer duration:duration done:done];
			}];
			return;
		}
	}

	[self finishNoteAtPath:answer duration:duration done:done];
}

@end
