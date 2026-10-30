//
// TGVoiceRecorder.mm - Streaming voice note recorder using CoreAudio AudioQueue and libopusenc.
//
#import "TGVoiceRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#ifdef __cplusplus
extern "C" {
#endif
#include "opusenc/opusenc.h"
#ifdef __cplusplus
}
#endif
#import "TGLocklessRingBuffer.hpp"

static const int kSampleRate = 48000;
static const int kChannels = 1;
static const int kBufferByteSize = 3840; // 40ms of 16-bit 48kHz mono

@interface TGVoiceRecorder () {
	AudioQueueRef _audioQueue;
	AudioQueueBufferRef _buffers[3];
	OggOpusEnc *_enc;
	OggOpusComments *_comments;
	TGLocklessRingBuffer<int16_t, 16384> _pcmRingBuffer;
	dispatch_queue_t _encodeQueue;
}

@property (nonatomic, assign) BOOL isRecordingFlag;
@property (nonatomic, strong) NSString *ogaPath;
@property (nonatomic, strong) NSDate *startedAt;

- (void)handleInputBuffer:(AudioQueueBufferRef)inBuffer queue:(AudioQueueRef)inAQ;
- (void)drainEncoder;

@end

static void TGVoiceRecorderInputCallback(void *inUserData,
										AudioQueueRef inAQ,
										AudioQueueBufferRef inBuffer,
										const AudioTimeStamp *inStartTime,
										UInt32 inNumberPacketDescriptions,
										const AudioStreamPacketDescription *inPacketDescs) {
	TGVoiceRecorder *recorder = (__bridge TGVoiceRecorder *)inUserData;
	[recorder handleInputBuffer:inBuffer queue:inAQ];
}

@implementation TGVoiceRecorder

+ (instancetype)shared {
	static TGVoiceRecorder *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGVoiceRecorder alloc] init]; });
	return s;
}

- (instancetype)init {
	if ((self = [super init])) {
		_encodeQueue = dispatch_queue_create("org.telegram.voicerecorder.encoder", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (BOOL)recording {
	return self.isRecordingFlag;
}

- (NSTimeInterval)duration {
	return self.startedAt ? -[self.startedAt timeIntervalSinceNow] : 0;
}

- (BOOL)start {
	if (self.recording)
		return YES;

	NSError *err = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryPlayAndRecord error:&err];
	[session setActive:YES error:&err];
	if (err) {
		NSLog(@"TGVoiceRecorder: audio session error: %@", err);
		return NO;
	}

	self.ogaPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"voice.oga"];
	[[NSFileManager defaultManager] removeItemAtPath:self.ogaPath error:nil];

	_pcmRingBuffer.clear();

	int opeError = 0;
	_comments = ope_comments_create();
	_enc = ope_encoder_create_file(self.ogaPath.UTF8String, _comments, kSampleRate, kChannels, 0, &opeError);
	if (!_enc) {
		NSLog(@"TGVoiceRecorder: ope_encoder_create_file failed (%d)", opeError);
		if (_comments) {
			ope_comments_destroy(_comments);
			_comments = NULL;
		}
		return NO;
	}

	AudioStreamBasicDescription format;
	memset(&format, 0, sizeof(format));
	format.mSampleRate = kSampleRate;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mBytesPerPacket = sizeof(int16_t);
	format.mFramesPerPacket = 1;
	format.mBytesPerFrame = sizeof(int16_t);
	format.mChannelsPerFrame = kChannels;
	format.mBitsPerChannel = 16;

	OSStatus status = AudioQueueNewInput(&format,
										TGVoiceRecorderInputCallback,
										(__bridge void *)self,
										NULL,
										NULL,
										0,
										&_audioQueue);
	if (status != noErr) {
		NSLog(@"TGVoiceRecorder: AudioQueueNewInput failed (%d)", (int)status);
		ope_encoder_destroy(_enc);
		ope_comments_destroy(_comments);
		_enc = NULL;
		_comments = NULL;
		return NO;
	}

	for (int i = 0; i < 3; i++) {
		status = AudioQueueAllocateBuffer(_audioQueue, kBufferByteSize, &_buffers[i]);
		if (status != noErr) {
			NSLog(@"TGVoiceRecorder: AudioQueueAllocateBuffer failed (%d)", (int)status);
			[self cancel];
			return NO;
		}
		AudioQueueEnqueueBuffer(_audioQueue, _buffers[i], 0, NULL);
	}

	status = AudioQueueStart(_audioQueue, NULL);
	if (status != noErr) {
		NSLog(@"TGVoiceRecorder: AudioQueueStart failed (%d)", (int)status);
		[self cancel];
		return NO;
	}

	self.isRecordingFlag = YES;
	self.startedAt = [NSDate date];
	return YES;
}

- (void)handleInputBuffer:(AudioQueueBufferRef)inBuffer queue:(AudioQueueRef)inAQ {
	if (!self.isRecordingFlag)
		return;

	size_t samples = inBuffer->mAudioDataByteSize / sizeof(int16_t);
	if (samples > 0) {
		_pcmRingBuffer.write((const int16_t *)inBuffer->mAudioData, samples);
		dispatch_async(_encodeQueue, ^{
			[self drainEncoder];
		});
	}

	AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
}

- (void)drainEncoder {
	if (!_enc) return;
	int16_t chunk[960]; // 20ms at 48kHz
	while (_pcmRingBuffer.available_read() >= 960) {
		size_t readCount = _pcmRingBuffer.read(chunk, 960);
		if (readCount > 0 && _enc) {
			ope_encoder_write(_enc, chunk, (int)readCount);
		}
	}
}

- (void)cancel {
	self.isRecordingFlag = NO;
	self.startedAt = nil;

	if (_audioQueue) {
		AudioQueueStop(_audioQueue, true);
		for (int i = 0; i < 3; i++) {
			if (_buffers[i]) {
				AudioQueueFreeBuffer(_audioQueue, _buffers[i]);
				_buffers[i] = NULL;
			}
		}
		AudioQueueDispose(_audioQueue, true);
		_audioQueue = NULL;
	}

	dispatch_async(_encodeQueue, ^{
		self->_pcmRingBuffer.clear();
		if (self->_enc) {
			ope_encoder_destroy(self->_enc);
			self->_enc = NULL;
		}
		if (self->_comments) {
			ope_comments_destroy(self->_comments);
			self->_comments = NULL;
		}
		[[NSFileManager defaultManager] removeItemAtPath:self.ogaPath error:nil];
	});
}

- (void)stopWithCompletion:(void (^)(NSString *, NSTimeInterval))completion {
	self.isRecordingFlag = NO;
	NSTimeInterval seconds = self.duration;
	self.startedAt = nil;

	if (_audioQueue) {
		AudioQueueStop(_audioQueue, true);
		for (int i = 0; i < 3; i++) {
			if (_buffers[i]) {
				AudioQueueFreeBuffer(_audioQueue, _buffers[i]);
				_buffers[i] = NULL;
			}
		}
		AudioQueueDispose(_audioQueue, true);
		_audioQueue = NULL;
	}

	dispatch_async(_encodeQueue, ^{
		int16_t chunk[960];
		while (self->_pcmRingBuffer.available_read() > 0) {
			size_t readCount = self->_pcmRingBuffer.read(chunk, 960);
			if (readCount > 0 && self->_enc) {
				ope_encoder_write(self->_enc, chunk, (int)readCount);
			}
		}

		if (self->_enc) {
			ope_encoder_drain(self->_enc);
			ope_encoder_destroy(self->_enc);
			self->_enc = NULL;
		}
		if (self->_comments) {
			ope_comments_destroy(self->_comments);
			self->_comments = NULL;
		}

		NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.ogaPath error:nil];
		NSString *result = [attrs fileSize] > 0 ? self.ogaPath : nil;
		NSLog(@"TGVoiceRecorder: streamed and encoded %llu bytes", [attrs fileSize]);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(result, seconds);
		});
	});
}

@end
