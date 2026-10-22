#import "TGVoiceRecorder.h"
#import <AVFoundation/AVFoundation.h>
#include "opusenc/opusenc.h"

@interface TGVoiceRecorder ()
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) NSString *pcmPath;
@property (nonatomic, strong) NSDate *startedAt;
@end

@implementation TGVoiceRecorder

+ (instancetype)shared {
	static TGVoiceRecorder *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGVoiceRecorder alloc] init]; });
	return s;
}

- (BOOL)recording {
	return self.recorder.isRecording;
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
	if (err){
		NSLog(@"TGVoiceRecorder: audio session: %@", err);
		return NO;
	}

	self.pcmPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"voice.caf"];
	[[NSFileManager defaultManager] removeItemAtPath:self.pcmPath error:nil];

	// 48kHz mono 16-bit: what libopusenc wants, so nothing has to be resampled.
	NSDictionary *settings = @{
		AVFormatIDKey            : @(kAudioFormatLinearPCM),
		AVSampleRateKey          : @(48000.0),
		AVNumberOfChannelsKey    : @(1),
		AVLinearPCMBitDepthKey   : @(16),
		AVLinearPCMIsFloatKey    : @NO,
		AVLinearPCMIsBigEndianKey: @NO,
	};

	self.recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:self.pcmPath]
												settings:settings
												   error:&err];
	if (!self.recorder || err){
		NSLog(@"TGVoiceRecorder: %@", err);
		return NO;
	}

	self.startedAt = [NSDate date];
	return [self.recorder record];
}

- (void)cancel {
	[self.recorder stop];
	self.recorder = nil;
	self.startedAt = nil;
	[[NSFileManager defaultManager] removeItemAtPath:self.pcmPath error:nil];
}

- (void)stopWithCompletion:(void (^)(NSString *, NSTimeInterval))completion {
	NSTimeInterval seconds = self.duration;
	[self.recorder stop];
	self.recorder = nil;
	self.startedAt = nil;

	NSString *pcmPath = self.pcmPath;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *oga = [self encodePCMAtPath:pcmPath];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(oga, seconds);
		});
	});
}

/// CAF from AVAudioRecorder is a header followed by raw samples; find the data
/// chunk, then feed it to libopusenc.
- (NSString *)encodePCMAtPath:(NSString *)path {
	NSData *caf = [NSData dataWithContentsOfFile:path];
	if (caf.length < 64){
		NSLog(@"TGVoiceRecorder: nothing recorded");
		return nil;
	}

	const uint8_t *bytes = caf.bytes;
	NSUInteger offset = 0, dataLength = 0;

	// Walk CAF chunks looking for "data"; its payload starts 4 bytes in, after
	// the edit-count field.
	NSUInteger p = 8;
	while (p + 12 <= caf.length){
		char type[5] = {0};
		memcpy(type, bytes + p, 4);
		uint64_t size = 0;
		for (int i = 0; i < 8; i++)
			size = (size << 8) | bytes[p + 4 + i];   // CAF sizes are big-endian

		if (!strcmp(type, "data")){
			offset = p + 12 + 4;
			dataLength = (size == (uint64_t)-1 || p + 12 + size > caf.length)
					? caf.length - offset : (NSUInteger)size - 4;
			break;
		}
		p += 12 + (NSUInteger)size;
	}

	if (!offset || dataLength < 2){
		NSLog(@"TGVoiceRecorder: no data chunk");
		return nil;
	}

	NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:@"voice.oga"];
	[[NSFileManager defaultManager] removeItemAtPath:out error:nil];

	int error = 0;
	OggOpusComments *comments = ope_comments_create();
	OggOpusEnc *enc = ope_encoder_create_file(out.UTF8String, comments, 48000, 1, 0, &error);
	if (!enc){
		NSLog(@"TGVoiceRecorder: encoder create failed (%d)", error);
		ope_comments_destroy(comments);
		return nil;
	}

	const short *samples = (const short *)(bytes + offset);
	NSUInteger total = dataLength / sizeof(short);
	NSUInteger chunk = 960;   // 20ms at 48kHz

	for (NSUInteger i = 0; i < total; i += chunk){
		int count = (int)MIN(chunk, total - i);
		if (ope_encoder_write(enc, samples + i, count) != 0){
			NSLog(@"TGVoiceRecorder: write failed at %lu", (unsigned long)i);
			break;
		}
	}

	ope_encoder_drain(enc);
	ope_encoder_destroy(enc);
	ope_comments_destroy(comments);

	NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:out error:nil];
	NSLog(@"TGVoiceRecorder: encoded %llu bytes", [attrs fileSize]);
	return [attrs fileSize] > 0 ? out : nil;
}

@end

// vim:ft=objc
