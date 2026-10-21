// TGCallAudioEngineStub.m — test-only audio engine.
//
// The real engine opens a VoiceProcessingIO AudioUnit and needs libopus, which
// the command-line test build does not link. The call tests assert that frames
// reach the engine, not that they make sound, so this records them instead.
//
// The class name intentionally matches the production one: the test binary
// compiles this instead of src/TGCallAudioEngine.m.
#import "TGCallAudioEngine.h"

static NSMutableArray<NSData *> *TGIncomingFrames(void) {
	static NSMutableArray *frames = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ frames = [NSMutableArray array]; });
	return frames;
}

@interface TGCallAudioEngine ()
@property (nonatomic, assign) BOOL running;
@end

@implementation TGCallAudioEngine

- (BOOL)start {
	self.running = YES;
	return YES;
}

- (void)stop {
	self.running = NO;
}

- (void)handleIncomingOpusFrame:(NSData *)opusFrame {
	if (opusFrame)
		[TGIncomingFrames() addObject:opusFrame];
}

@end

@implementation TGCallAudioEngine (Testing)

+ (NSArray<NSData *> *)receivedFrames {
	return [TGIncomingFrames() copy];
}

+ (void)resetReceivedFrames {
	[TGIncomingFrames() removeAllObjects];
}

@end
