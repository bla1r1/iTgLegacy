//
// TGStreamingVoicePlayer.m - Low-footprint streaming audio player for Ogg Opus voice notes.
//
#import "TGStreamingVoicePlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#include "opusfile/opusfile.h"

static const int kNumBuffers = 3;
static const int kBufferSamples = 4096; // 4096 frames = ~85.3ms at 48kHz stereo

@interface TGStreamingVoicePlayer () {
	OggOpusFile *_opusFile;
	AudioQueueRef _audioQueue;
	AudioQueueBufferRef _buffers[kNumBuffers];
	AudioStreamBasicDescription _format;
	BOOL _playing;
	BOOL _paused;
	BOOL _eof;
	float _rate;
	BOOL _enableRate;
	NSTimeInterval _duration;
	NSRecursiveLock *_lock;
	int _buffersInFlight;
}

- (void)fillBuffer:(AudioQueueBufferRef)buffer;
- (void)handleBufferComplete:(AudioQueueBufferRef)buffer;

@end

static void TGStreamingAudioQueueOutputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
	TGStreamingVoicePlayer *player = (__bridge TGStreamingVoicePlayer *)inUserData;
	[player handleBufferComplete:inBuffer];
}

@implementation TGStreamingVoicePlayer

- (instancetype)initWithPath:(NSString *)path error:(NSError **)outError {
	if (!path.length){
		if (outError)
			*outError = [NSError errorWithDomain:@"TGStreamingVoicePlayer" code:-1
										 userInfo:@{NSLocalizedDescriptionKey : @"Empty file path"}];
		return nil;
	}

	if ((self = [super init])){
		_lock = [[NSRecursiveLock alloc] init];
		_rate = 1.0f;
		_enableRate = YES;

		int err = 0;
		_opusFile = op_open_file(path.UTF8String, &err);
		if (!_opusFile){
			if (outError)
				*outError = [NSError errorWithDomain:@"TGStreamingVoicePlayer" code:err
											 userInfo:@{NSLocalizedDescriptionKey :
													[NSString stringWithFormat:@"op_open_file failed: %d", err]}];
			return nil;
		}

		ogg_int64_t totalSamples = op_pcm_total(_opusFile, -1);
		_duration = (totalSamples > 0) ? ((NSTimeInterval)totalSamples / 48000.0) : 0.0;

		memset(&_format, 0, sizeof(_format));
		_format.mSampleRate = 48000.0;
		_format.mFormatID = kAudioFormatLinearPCM;
		_format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
		_format.mBytesPerPacket = 4;
		_format.mFramesPerPacket = 1;
		_format.mBytesPerFrame = 4;
		_format.mChannelsPerFrame = 2;
		_format.mBitsPerChannel = 16;

		OSStatus status = AudioQueueNewOutput(&_format,
											  TGStreamingAudioQueueOutputCallback,
											  (__bridge void *)self,
											  CFRunLoopGetMain(),
											  kCFRunLoopCommonModes,
											  0,
											  &_audioQueue);
		if (status != noErr){
			op_free(_opusFile);
			_opusFile = NULL;
			if (outError)
				*outError = [NSError errorWithDomain:@"TGStreamingVoicePlayer" code:status
											 userInfo:@{NSLocalizedDescriptionKey : @"AudioQueueNewOutput failed"}];
			return nil;
		}

		UInt32 propValue = 1;
		AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableTimePitch, &propValue, sizeof(propValue));

		UInt32 bufferByteSize = kBufferSamples * _format.mBytesPerFrame;
		for (int i = 0; i < kNumBuffers; i++){
			status = AudioQueueAllocateBuffer(_audioQueue, bufferByteSize, &_buffers[i]);
			if (status != noErr){
				NSLog(@"TGStreamingVoicePlayer: AudioQueueAllocateBuffer failed %d", (int)status);
			}
		}
	}
	return self;
}

- (void)dealloc {
	[self stop];
}

- (void)fillBuffer:(AudioQueueBufferRef)buffer {
	if (!_opusFile || !_audioQueue || _eof)
		return;

	int maxSamples = buffer->mAudioDataBytesCapacity / (sizeof(opus_int16) * 2);
	int samplesRead = op_read_stereo(_opusFile, (opus_int16 *)buffer->mAudioData, maxSamples);

	if (samplesRead > 0){
		buffer->mAudioDataByteSize = samplesRead * sizeof(opus_int16) * 2;
		OSStatus status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
		if (status == noErr){
			_buffersInFlight++;
		}
	} else {
		_eof = YES;
		buffer->mAudioDataByteSize = 0;
	}
}

- (void)handleBufferComplete:(AudioQueueBufferRef)buffer {
	[_lock lock];
	if (!_audioQueue || !_playing){
		[_lock unlock];
		return;
	}

	_buffersInFlight--;
	if (_buffersInFlight < 0)
		_buffersInFlight = 0;

	if (!_eof){
		[self fillBuffer:buffer];
	} else if (_buffersInFlight == 0){
		// All queued buffers finished playing
		_playing = NO;
		_paused = NO;
		AudioQueueStop(_audioQueue, false);

		id<TGStreamingVoicePlayerDelegate> del = self.delegate;
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([del respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)]){
				[del audioPlayerDidFinishPlaying:(id)self successfully:YES];
			}
		});
	}
	[_lock unlock];
}

- (BOOL)play {
	[_lock lock];
	if (!_audioQueue || !_opusFile){
		[_lock unlock];
		return NO;
	}

	if (_playing){
		[_lock unlock];
		return YES;
	}

	if (!_paused){
		_buffersInFlight = 0;
		for (int i = 0; i < kNumBuffers; i++){
			if (!_eof){
				[self fillBuffer:_buffers[i]];
			}
		}
	}

	_playing = YES;
	_paused = NO;
	[self applyRate];
	OSStatus status = AudioQueueStart(_audioQueue, NULL);
	[_lock unlock];
	return status == noErr;
}

- (void)pause {
	[_lock lock];
	if (_audioQueue && _playing){
		AudioQueuePause(_audioQueue);
		_playing = NO;
		_paused = YES;
	}
	[_lock unlock];
}

- (void)stop {
	[_lock lock];
	_playing = NO;
	_paused = NO;
	_eof = NO;
	_buffersInFlight = 0;
	self.delegate = nil;

	AudioQueueRef aq = _audioQueue;
	_audioQueue = NULL;
	OggOpusFile *of = _opusFile;
	_opusFile = NULL;
	[_lock unlock];

	if (aq){
		AudioQueueStop(aq, true);
		AudioQueueDispose(aq, true);
	}
	if (of){
		op_free(of);
	}
}

- (BOOL)isPlaying {
	return _playing;
}

- (BOOL)playing {
	return _playing;
}

- (NSTimeInterval)duration {
	return _duration;
}

- (NSTimeInterval)currentTime {
	[_lock lock];
	if (!_opusFile){
		[_lock unlock];
		return 0.0;
	}
	ogg_int64_t pcm = op_pcm_tell(_opusFile);
	[_lock unlock];
	return (pcm > 0) ? ((NSTimeInterval)pcm / 48000.0) : 0.0;
}

- (void)setCurrentTime:(NSTimeInterval)currentTime {
	[_lock lock];
	if (!_opusFile || !_audioQueue){
		[_lock unlock];
		return;
	}

	currentTime = MIN(MAX(currentTime, 0.0), _duration);
	ogg_int64_t targetPcm = (ogg_int64_t)(currentTime * 48000.0);
	op_pcm_seek(_opusFile, targetPcm);

	_eof = NO;
	_buffersInFlight = 0;
	AudioQueueReset(_audioQueue);

	for (int i = 0; i < kNumBuffers; i++){
		if (!_eof){
			[self fillBuffer:_buffers[i]];
		}
	}

	if (_playing){
		[self applyRate];
		AudioQueueStart(_audioQueue, NULL);
	}
	[_lock unlock];
}

- (float)rate {
	return _rate;
}

- (void)setRate:(float)rate {
	_rate = rate;
	[self applyRate];
}

- (void)applyRate {
	if (_audioQueue && _enableRate){
		AudioQueueSetParameter(_audioQueue, kAudioQueueParam_PlayRate, _rate);
	}
}

@end
