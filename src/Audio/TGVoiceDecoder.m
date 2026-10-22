//
// TGVoiceDecoder - Opus to WAV.
//
// Telegram voice notes are Opus in an Ogg container. iOS 7 cannot decode Opus
// at all, so AVAudioPlayer is given a plain 16-bit PCM WAV produced here from
// libopusfile. This is the only reason libopus and the ogg/opusfile sources
// are still in the tree.
//
#import "TGVoiceDecoder.h"
#include "opusfile/opusfile.h"
#include <stdio.h>
#include <string.h>

/// Little-endian writers - WAV headers are LE regardless of the host.
static void put32(unsigned char *p, uint32_t v) {
	p[0] = v & 0xff; p[1] = (v >> 8) & 0xff;
	p[2] = (v >> 16) & 0xff; p[3] = (v >> 24) & 0xff;
}
static void put16(unsigned char *p, uint16_t v) {
	p[0] = v & 0xff; p[1] = (v >> 8) & 0xff;
}

@implementation TGVoiceDecoder

+ (NSString *)wavFromOpusFile:(NSString *)opusPath {
	if (!opusPath.length)
		return nil;

	int err = 0;
	OggOpusFile *of = op_open_file(opusPath.UTF8String, &err);
	if (!of){
		NSLog(@"TGVoiceDecoder: op_open_file failed (%d)", err);
		return nil;
	}

	// opusfile always decodes to 48kHz; ask for stereo so the frame size is
	// fixed at 2 channels regardless of what the file carries.
	const int rate = 48000;
	const int channels = 2;

	NSMutableData *pcm = [NSMutableData data];
	opus_int16 buffer[5760 * 2];   // 120ms at 48kHz, stereo

	for (;;){
		int samples = op_read_stereo(of, buffer, (int)(sizeof(buffer) / sizeof(buffer[0])));
		if (samples < 0){
			NSLog(@"TGVoiceDecoder: op_read_stereo failed (%d)", samples);
			op_free(of);
			return nil;
		}
		if (samples == 0)
			break;
		[pcm appendBytes:buffer length:samples * channels * sizeof(opus_int16)];
	}
	op_free(of);

	if (!pcm.length){
		NSLog(@"TGVoiceDecoder: decoded nothing");
		return nil;
	}

	// 44-byte canonical WAV header
	unsigned char header[44];
	uint32_t dataSize = (uint32_t)pcm.length;
	uint32_t byteRate = rate * channels * 2;

	memcpy(header, "RIFF", 4);
	put32(header + 4, 36 + dataSize);
	memcpy(header + 8, "WAVEfmt ", 8);
	put32(header + 16, 16);          // PCM header size
	put16(header + 20, 1);           // format: PCM
	put16(header + 22, channels);
	put32(header + 24, rate);
	put32(header + 28, byteRate);
	put16(header + 32, channels * 2); // block align
	put16(header + 34, 16);           // bits per sample
	memcpy(header + 36, "data", 4);
	put32(header + 40, dataSize);

	NSMutableData *wav = [NSMutableData dataWithBytes:header length:sizeof(header)];
	[wav appendData:pcm];

	NSString *out = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"voice.wav"];
	if (![wav writeToFile:out atomically:YES]){
		NSLog(@"TGVoiceDecoder: cannot write %@", out);
		return nil;
	}
	return out;
}

@end

// vim:ft=objc
