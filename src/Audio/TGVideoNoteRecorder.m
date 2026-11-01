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
/// How many files a pause_and_all_that_has_resumed promised. The delegate
/// fills segmentPaths asynchronously, so a stop right after a pause waits for
/// the count to catch up instead of exporting with a missing tail.
@property (nonatomic, assign) NSUInteger expectedSegments;
/// Set by a stop that landed while a pause was closing its segment; the
/// delegate finishes the job instead of stashing again.
@property (nonatomic, assign) BOOL pendingStop;
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
	self.segmentPaths = [[NSMutableArray alloc] init];
	self.finalPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note.mov"];
	[[NSFileManager defaultManager] removeItemAtPath:self.finalPath error:nil];
	self.recordedDuration = 0;
	self.expectedSegments = 0;
	self.pendingStop = NO;
	self.completion = nil;

	// The lens takes seconds to wake on this hardware, and startRunning
	// blocks until it does - off the main thread, so the overlay and the
	// chat behind it stay alive while the camera looks for light.
	self.warmupToken++;
	NSInteger token = self.warmupToken;
	self.isStartingFlag = YES;
	NSInteger sessionToken = token;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[session startRunning];
		dispatch_async(dispatch_get_main_queue(), ^{
			TGVideoNoteRecorder *me = weakSelf;
			if (!me || me.warmupToken != sessionToken){
				[session stopRunning];
				return;
			}
			me.isStartingFlag = NO;
			me.isRecordingFlag = YES;
			me.isReadyFlag = NO;
			me.startedAt = nil;
			NSLog(@"TGVideoNoteRecorder: session running (file pending)");
			if (me.onSession)
				me.onSession(session);
		});
		// The file opens half a second after the frames exist. Starting
		// recording in the same breath as startRunning is what killed the
		// note on iOS 6: the output gave up before the first frame found
		// a connection.
		double when = 0.5;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
				(int64_t)(when * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			TGVideoNoteRecorder *me = weakSelf;
			if (!me || me.warmupToken != sessionToken || me.session != session)
				return;
			[me recordSegment];
			me.startedAt = [NSDate date];
			me.isReadyFlag = YES;
			NSLog(@"TGVideoNoteRecorder: file open, recording begins");
			if (me.onReady)
				me.onReady();
		});
	});
	return YES;
}

- (void)stopWithCompletion:(void (^)(NSString *, NSTimeInterval))completion {
	if (!self.isRecordingFlag){
		if (completion) completion(nil, 0);
		return;
	}
	self.completion = [completion copy];
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
}

- (void)cancel {
	self.completion = nil;
	self.pendingStop = NO;
	self.isRecordingFlag = NO;
	self.isStartingFlag = NO;
	self.warmupToken++;    // any warm-up callback still in flight stops now
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

	if (!finalStop)
		return;   // a pause closed this one; the session and preview stay up

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

	[[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
	AVAssetExportSession *export = [[AVAssetExportSession alloc]
			initWithAsset:asset presetName:AVAssetExportPresetMediumQuality];
	export.outputURL = [NSURL fileURLWithPath:outPath];
	export.outputFileType = AVFileTypeQuickTimeMovie;
	export.videoComposition = composition;
	export.shouldOptimizeForNetworkUse = YES;

	[export exportAsynchronouslyWithCompletionHandler:^{
		if (export.status == AVAssetExportSessionStatusCompleted)
			[squares addObject:outPath];
		[[NSFileManager defaultManager] removeItemAtPath:inPath error:nil];
		[weakSelf exportSegment:index + 1 of:paths squares:squares
					   duration:duration done:done];
	}];
}

- (NSString *)squarePathForIndex:(NSUInteger)index {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"video-note-square-%lu.mov",
					(unsigned long)index]];
}

/// One square per segment becomes one note: the tracks are laid end to end and
/// the reel is re-exported once. The pieces were cropped on their own way in,
/// so no second video composition is needed.
- (void)joinSquares:(NSArray *)squares duration:(NSTimeInterval)duration {
	void (^done)(NSString *, NSTimeInterval) = self.completion;
	self.completion = nil;
	if (!done)
		return;

	NSString *answer = nil;
	NSString *joinedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"video-note-joined.mov"];

	if (squares.count == 0){
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
						presetName:AVAssetExportPresetMediumQuality];
			export.outputURL = [NSURL fileURLWithPath:joinedPath];
			export.outputFileType = AVFileTypeQuickTimeMovie;
			export.shouldOptimizeForNetworkUse = YES;
			NSString *thisAnswer = joinedPath;
			[export exportAsynchronouslyWithCompletionHandler:^{
				NSString *finalAnswer = export.status ==
						AVAssetExportSessionStatusCompleted ? thisAnswer : nil;
				dispatch_async(dispatch_get_main_queue(), ^{
					done(finalAnswer, duration);
				});
			}];
			return;
		}
	}

	done(answer, duration);
}

@end
