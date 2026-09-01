//
// TGCallAudioEngine - Opus audio playback and microphone capture using AudioQueue.
//
#ifndef TG_CALL_AUDIO_ENGINE_H
#define TG_CALL_AUDIO_ENGINE_H

#import <Foundation/Foundation.h>

@interface TGCallAudioEngine : NSObject

/// Mixes SOS in Morse into the outgoing stream. The phone under test sits in an
/// empty room, so silence on the far end proves nothing; this makes a working
/// path audible without anyone having to speak into it.
@property (nonatomic, assign) BOOL emitMorseSignal;

/// Feeds every encoded frame straight back into the decoder. Proves capture,
/// encoding, decoding and playback in one go, without the network.
@property (nonatomic, assign) BOOL loopbackToSpeaker;

@property (nonatomic, copy) void (^onOutgoingOpusFrame)(NSData *opusFrame);

- (BOOL)start;
- (void)stop;

/// Pass an incoming Opus audio frame to be decoded and played through the speaker/earpiece.
- (void)handleIncomingOpusFrame:(NSData *)opusFrame;

@end

#endif
