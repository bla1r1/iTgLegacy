#import "TGCallAudioEngine.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <opus/opus.h>

enum {
	kSampleRate    = 48000,
	kChannels      = 1,
	kFrameSamples  = 960, // 20 ms at 48kHz
	kPCMBufferSize = 960 * sizeof(int16_t) // 1920 bytes
};

static const char *kMorseSOS = "10101000" "11101110111000" "10101000" "0000";
static const float kToneHz        = 800.0f;
static const float kToneAmplitude = 7000.0f;
static const int   kUnitsPerSecond = 8;

static int TGFrameLevel(const int16_t *pcm, int count) {
	double sum = 0;
	for (int i = 0; i < count; i++)
		sum += (double)pcm[i] * (double)pcm[i];
	return (int)sqrt(sum / (count > 0 ? count : 1));
}

@interface TGCallAudioEngine () {
	OpusDecoder *_decoder;
	OpusEncoder *_encoder;

    AudioComponentInstance _audioUnit;
	BOOL _running;

	NSMutableData *_inputPCMBuffer;
	NSMutableData *_incomingPCMQueue;
	NSLock *_audioLock;

	uint64_t _outSamples;
	float _tonePhase;
	int _outFrames, _micLevelSum, _sentLevelSum;
	int _inFrames, _inLevelSum;
}

- (OSStatus)renderPlayback:(AudioBufferList *)ioData numFrames:(UInt32)numFrames;
- (OSStatus)renderRecord:(AudioUnitRenderActionFlags *)ioActionFlags
               timeStamp:(const AudioTimeStamp *)inTimeStamp
               busNumber:(UInt32)inBusNumber
               numFrames:(UInt32)inNumberFrames;

@end

static OSStatus TGPlaybackCallback(void *inRefCon,
                                   AudioUnitRenderActionFlags *ioActionFlags,
                                   const AudioTimeStamp *inTimeStamp,
                                   UInt32 inBusNumber,
                                   UInt32 inNumberFrames,
                                   AudioBufferList *ioData) {
    TGCallAudioEngine *engine = (__bridge TGCallAudioEngine *)inRefCon;
    return [engine renderPlayback:ioData numFrames:inNumberFrames];
}

static OSStatus TGRecordCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData) {
    TGCallAudioEngine *engine = (__bridge TGCallAudioEngine *)inRefCon;
    return [engine renderRecord:ioActionFlags timeStamp:inTimeStamp busNumber:inBusNumber numFrames:inNumberFrames];
}

@implementation TGCallAudioEngine

- (instancetype)init {
	if ((self = [super init])) {
		_inputPCMBuffer = [NSMutableData data];
		_incomingPCMQueue = [NSMutableData data];
		_audioLock = [[NSLock alloc] init];
	}
	return self;
}

- (BOOL)isRunning {
	return _running;
}

- (OSStatus)renderPlayback:(AudioBufferList *)ioData numFrames:(UInt32)numFrames {
    if (!_running) {
        memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
        return noErr;
    }

    UInt32 bytesNeeded = numFrames * sizeof(int16_t);
    [_audioLock lock];
    if (_incomingPCMQueue.length >= bytesNeeded) {
        memcpy(ioData->mBuffers[0].mData, _incomingPCMQueue.bytes, bytesNeeded);
        [_incomingPCMQueue replaceBytesInRange:NSMakeRange(0, bytesNeeded) withBytes:NULL length:0];
    } else {
        memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
    }
    [_audioLock unlock];
    return noErr;
}

- (OSStatus)renderRecord:(AudioUnitRenderActionFlags *)ioActionFlags
               timeStamp:(const AudioTimeStamp *)inTimeStamp
               busNumber:(UInt32)inBusNumber
               numFrames:(UInt32)inNumberFrames {
    
    if (!_running) return noErr;
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = kChannels;
    
    int16_t buffer[inNumberFrames * kChannels];
    bufferList.mBuffers[0].mData = buffer;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames * sizeof(int16_t);
    
    OSStatus status = AudioUnitRender(_audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList);
    if (status != noErr) {
        return status;
    }
    
    if (bufferList.mBuffers[0].mDataByteSize > 0) {
        [self processCapturedPCM:(const int16_t *)bufferList.mBuffers[0].mData length:bufferList.mBuffers[0].mDataByteSize];
    }
    return noErr;
}

- (BOOL)start {
	if (_running) return YES;

	int err = 0;
	_decoder = opus_decoder_create(kSampleRate, kChannels, &err);
	if (err != OPUS_OK || !_decoder) return NO;

	_encoder = opus_encoder_create(kSampleRate, kChannels, OPUS_APPLICATION_VOIP, &err);
	if (err != OPUS_OK || !_encoder) {
		opus_decoder_destroy(_decoder);
		return NO;
	}
	opus_encoder_ctl(_encoder, OPUS_SET_BITRATE(24000));
	opus_encoder_ctl(_encoder, OPUS_SET_COMPLEXITY(5));
	opus_encoder_ctl(_encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));

    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        NSLog(@"TGCallAudioEngine: failed to find VoiceProcessingIO");
        return NO;
    }

    OSStatus status = AudioComponentInstanceNew(comp, &_audioUnit);
    if (status != noErr) {
        NSLog(@"TGCallAudioEngine: failed to create VoiceProcessingIO instance");
        return NO;
    }

    UInt32 enableIO = 1;
    AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, sizeof(enableIO));
    AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableIO, sizeof(enableIO));

    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate       = kSampleRate;
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket   = sizeof(int16_t);
    format.mFramesPerPacket  = 1;
    format.mBytesPerFrame    = sizeof(int16_t);
    format.mChannelsPerFrame = kChannels;
    format.mBitsPerChannel   = 16;

    AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
    AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format));

    AURenderCallbackStruct renderCb;
    renderCb.inputProc = TGPlaybackCallback;
    renderCb.inputProcRefCon = (__bridge void *)self;
    AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCb, sizeof(renderCb));

    AURenderCallbackStruct recordCb;
    recordCb.inputProc = TGRecordCallback;
    recordCb.inputProcRefCon = (__bridge void *)self;
    AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &recordCb, sizeof(recordCb));

    status = AudioUnitInitialize(_audioUnit);
    if (status != noErr) {
        NSLog(@"TGCallAudioEngine: AudioUnitInitialize failed");
        return NO;
    }

    status = AudioOutputUnitStart(_audioUnit);
    if (status != noErr) {
        NSLog(@"TGCallAudioEngine: AudioOutputUnitStart failed");
        return NO;
    }

	_running = YES;
	NSLog(@"TGCallAudioEngine: started VoiceProcessingIO");
	return YES;
}

- (void)handleIncomingOpusFrame:(NSData *)opusFrame {
	if (!_running || !_decoder || opusFrame.length == 0)
		return;

	int16_t pcmBuffer[5760];
	int decodedSamples = opus_decode(_decoder, (const unsigned char *)opusFrame.bytes,
									 (opus_int32)opusFrame.length, pcmBuffer,
									 5760, 0);
	if (decodedSamples <= 0)
		return;

	_inLevelSum += TGFrameLevel(pcmBuffer, decodedSamples);
	if (++_inFrames >= 50) {
		NSLog(@"TGCallAudioEngine: incoming level %d over %d frames", _inLevelSum / _inFrames, _inFrames);
		_inFrames = _inLevelSum = 0;
	}

	NSUInteger bytesSize = decodedSamples * sizeof(int16_t);
	[_audioLock lock];
	[_incomingPCMQueue appendBytes:pcmBuffer length:bytesSize];
	if (_incomingPCMQueue.length > kPCMBufferSize * 10) {
		NSUInteger excess = _incomingPCMQueue.length - kPCMBufferSize * 10;
		[_incomingPCMQueue replaceBytesInRange:NSMakeRange(0, excess) withBytes:NULL length:0];
	}
	[_audioLock unlock];
}

- (void)processCapturedPCM:(const int16_t *)pcm length:(UInt32)bytesLength {
	if (!_running || !_encoder)
		return;

	[_inputPCMBuffer appendBytes:pcm length:bytesLength];

	while (_inputPCMBuffer.length >= kPCMBufferSize) {
		int16_t framePCM[kFrameSamples];
		memcpy(framePCM, _inputPCMBuffer.bytes, kPCMBufferSize);

		int micLevel = TGFrameLevel(framePCM, kFrameSamples);

		if (self.emitMorseSignal) {
			const uint32_t samplesPerUnit = kSampleRate / kUnitsPerSecond;
			const size_t units = strlen(kMorseSOS);
			const float phaseInc = 2.0f * M_PI * kToneHz / (float)kSampleRate;

			for (int i = 0; i < kFrameSamples; i++) {
				BOOL on = kMorseSOS[((_outSamples + i) / samplesPerUnit) % units] == '1';
				_tonePhase += phaseInc;
				if (_tonePhase >= 2.0f * M_PI)
					_tonePhase -= 2.0f * M_PI;
				if (!on)
					continue;
				int32_t mixed = (int32_t)framePCM[i] + (int32_t)(sinf(_tonePhase) * kToneAmplitude);
				if (mixed > 32767)  mixed = 32767;
				if (mixed < -32768) mixed = -32768;
				framePCM[i] = (int16_t)mixed;
			}
		}
		_outSamples += kFrameSamples;

		_micLevelSum += micLevel;
		_sentLevelSum += TGFrameLevel(framePCM, kFrameSamples);
		if (++_outFrames >= 50) {
			NSLog(@"TGCallAudioEngine: mic level %d, sending level %d", _micLevelSum / _outFrames, _sentLevelSum / _outFrames);
			_outFrames = _micLevelSum = _sentLevelSum = 0;
		}

		uint8_t opusOut[512];
		int encodedBytes = opus_encode(_encoder, framePCM, kFrameSamples, opusOut, sizeof(opusOut));
		if (encodedBytes > 0) {
			NSData *opusFrame = [NSData dataWithBytes:opusOut length:encodedBytes];
			if (self.onOutgoingOpusFrame) {
				self.onOutgoingOpusFrame(opusFrame);
			}
			if (self.loopbackToSpeaker) {
				[self handleIncomingOpusFrame:opusFrame];
			}
		}
		[_inputPCMBuffer replaceBytesInRange:NSMakeRange(0, kPCMBufferSize) withBytes:NULL length:0];
	}
}

- (void)stop {
	_running = NO;

    if (_audioUnit) {
        AudioOutputUnitStop(_audioUnit);
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
    }

	if (_decoder) {
		opus_decoder_destroy(_decoder);
		_decoder = NULL;
	}

	if (_encoder) {
		opus_encoder_destroy(_encoder);
		_encoder = NULL;
	}

	[_inputPCMBuffer setLength:0];
	[_incomingPCMQueue setLength:0];
	NSLog(@"TGCallAudioEngine: stopped");
}

@end
