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
