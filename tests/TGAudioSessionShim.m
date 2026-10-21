// TGAudioSessionShim.m — macOS implementation of the AVAudioSession test shim.
//
// See tests/shim/AVFoundation/AVFoundation.h. Every call succeeds and does
// nothing: the tests care about TGCall's state machine and sockets, not about
// audio routing.
#import <AVFoundation/AVFoundation.h>

AVAudioSessionCategory const AVAudioSessionCategoryPlayAndRecord = @"AVAudioSessionCategoryPlayAndRecord";
AVAudioSessionCategoryOptions const AVAudioSessionCategoryOptionAllowBluetooth = 1 << 2;
AVAudioSessionMode const AVAudioSessionModeVoiceChat = @"AVAudioSessionModeVoiceChat";

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
