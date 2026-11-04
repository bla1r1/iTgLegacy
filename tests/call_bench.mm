// tests/call_bench.mm - our TGCall on this Mac against the real tgcalls library, over a
// real Telegram reflector. call_sim talks to TGCallPeer, our own copy of the protocol,
// which can only agree with us. This one talks to tgcalls_cli --mode bridge, the code the
// mobile client runs, and reports what each side heard. Run through scripts/call_bench.sh.
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <opus.h>
#include <sys/socket.h>
#include <unistd.h>
#include <math.h>

#import "TGCall.h"
#import "TGCallAudioEngine.h"
#import "TGClient.h"

@interface TGCall ()
- (void)sendOutgoingAudioFrame:(NSData *)opusFrame;
- (void)handleSignalingData:(NSData *)data;
- (void)handleUpdate:(NSDictionary *)call;
@end

@interface TGCallAudioEngine (Testing)
+ (NSArray<NSData *> *)receivedFrames;
@end

@interface TGClient (Testing)
+ (NSArray<NSDictionary *> *)sentRequests;
@end

static NSData *TGHexDecode(NSString *hex) {
	NSMutableData *out = [NSMutableData data];
	for (NSUInteger i = 0; i + 1 < hex.length; i += 2){
		unsigned value = 0;
		[[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&value];
		uint8_t byte = (uint8_t)value;
		[out appendBytes:&byte length:1];
	}
	return out;
}

static NSString *TGArgument(int argc, const char **argv, const char *name) {
	for (int i = 1; i + 1 < argc; i++)
		if (!strcmp(argv[i], name))
			return @(argv[i + 1]);
	return nil;
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSString *role = TGArgument(argc, argv, "--role");
		NSString *version = TGArgument(argc, argv, "--version");
		NSArray *reflector = [TGArgument(argc, argv, "--reflector") componentsSeparatedByString:@":"];
		int signalPort = [TGArgument(argc, argv, "--signal-port") intValue];
		int duration = [TGArgument(argc, argv, "--duration") intValue];
		NSData *key = TGHexDecode(TGArgument(argc, argv, "--key-hex"));
		NSData *tag = TGHexDecode(TGArgument(argc, argv, "--tag-hex"));
		BOOL outgoing = [role isEqualToString:@"caller"];
		// The negative control: what the far meter reads when we send nothing.
		BOOL silent = [TGArgument(argc, argv, "--silent") isEqualToString:@"1"];

		int fd = -1;
		struct sockaddr_in addr = {0};
		addr.sin_family = AF_INET;
		addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		addr.sin_port = htons((uint16_t)signalPort);
		// A socket that failed to connect cannot be retried, so each attempt gets its own.
		for (int attempt = 0; ; attempt++){
			fd = socket(AF_INET, SOCK_STREAM, 0);
			if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0)
				break;
			close(fd);
			if (attempt > 50){
				perror("bench: connect");
				return 1;
			}
			usleep(100000);
		}

		__block unsigned signalingIn = 0, signalingOut = 0;
		dispatch_async(dispatch_get_global_queue(0, 0), ^{
			for (;;){
				uint32_t size = 0;
				if (recv(fd, &size, sizeof(size), MSG_WAITALL) != sizeof(size))
					return;
				NSMutableData *data = [NSMutableData dataWithLength:ntohl(size)];
				if (recv(fd, data.mutableBytes, data.length, MSG_WAITALL) != (ssize_t)data.length)
					return;
				dispatch_async(dispatch_get_main_queue(), ^{
					signalingIn++;
					[[TGCall shared] handleSignalingData:data];
				});
			}
		});

		[[TGCall shared] handleUpdate:@{
			@"@type" : @"call", @"id" : @(1), @"user_id" : @(42LL), @"is_outgoing" : @(outgoing),
			@"state" : @{
				@"@type" : @"callStateReady",
				@"encryption_key" : [key base64EncodedStringWithOptions:0],
				@"servers" : @[@{
					@"ip_address" : reflector[0], @"port" : @([reflector[1] intValue]),
					@"type" : @{@"@type" : @"callServerTypeTelegramReflector",
								@"peer_tag" : [tag base64EncodedStringWithOptions:0]},
				}],
				@"protocol" : @{@"@type" : @"callProtocol", @"library_versions" : @[version]},
			},
		}];

		int error = 0;
		OpusEncoder *encoder = opus_encoder_create(48000, 1, OPUS_APPLICATION_VOIP, &error);
		__block uint64_t phase = 0;
		__block unsigned framesOut = 0;
		__block NSUInteger forwarded = 0;
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:duration];
		// On a schedule, not a sleep after each frame: running 30% slow made the far
		// jitter buffer stretch the tone and read as a protocol fault.
		NSDate *nextFrame = [NSDate date];
		while ([deadline timeIntervalSinceNow] > 0){
			@autoreleasepool {
				NSArray *sent = [TGClient sentRequests];
				for (; forwarded < sent.count; forwarded++){
					NSDictionary *request = sent[forwarded];
					if (![request[@"@type"] isEqualToString:@"sendCallSignalingData"])
						continue;
					NSData *data = [[NSData alloc] initWithBase64EncodedString:request[@"data"] options:0];
					uint32_t size = htonl((uint32_t)data.length);
					(void)!write(fd, &size, sizeof(size));
					(void)!write(fd, data.bytes, data.length);
					signalingOut++;
				}
				// 20 ms of a 1 kHz tone, so what the far side hears cannot be its own 440 Hz.
				opus_int16 pcm[960];
				for (int i = 0; i < 960; i++, phase++)
					pcm[i] = (opus_int16)(6000.0 * sin(2.0 * M_PI * 1000.0 * phase / 48000.0));
				uint8_t packet[400];
				opus_int32 size = opus_encode(encoder, pcm, 960, packet, sizeof(packet));
				if (size > 0 && !silent){
					[[TGCall shared] sendOutgoingAudioFrame:[NSData dataWithBytes:packet length:(NSUInteger)size]];
					framesOut++;
				}
				nextFrame = [nextFrame dateByAddingTimeInterval:0.02];
				[[NSRunLoop mainRunLoop] runUntilDate:nextFrame];
			}
		}

		OpusDecoder *decoder = opus_decoder_create(48000, 1, &error);
		double energy = 0, power1000 = 0, power440 = 0;
		long long failed = 0;
		const double c1000 = 2.0 * cos(2.0 * M_PI * 1000.0 / 48000.0);
		const double c440 = 2.0 * cos(2.0 * M_PI * 440.0 / 48000.0);
		NSArray *frames = [TGCallAudioEngine receivedFrames];
		for (NSData *frame in frames){
			opus_int16 pcm[5760];
			int count = opus_decode(decoder, (const unsigned char *)frame.bytes, (opus_int32)frame.length, pcm, 5760, 0);
			if (count <= 0){
				failed++;
				continue;
			}
			// In 10 ms blocks, the same measure the far side uses: power at a frequency
			// as a share of all the energy. 1.0 is a pure tone.
			for (int start = 0; start + 480 <= count; start += 480){
				double a[2] = {0, 0}, b[2] = {0, 0};
				for (int i = start; i < start + 480; i++){
					energy += (double)pcm[i] * pcm[i];
					double next = pcm[i] + c1000 * a[0] - a[1];
					a[1] = a[0];
					a[0] = next;
					next = pcm[i] + c440 * b[0] - b[1];
					b[1] = b[0];
					b[0] = next;
				}
				power1000 += (a[0] * a[0] + a[1] * a[1] - c1000 * a[0] * a[1]) * 2.0 / 480;
				power440 += (b[0] * b[0] + b[1] * b[1] - c440 * b[0] * b[1]) * 2.0 / 480;
			}
		}
		printf("OURS_RESULT state=%ld signaling_in=%u signaling_out=%u tx_frames=%u rx_frames=%lu rx_bad=%lld rx_energy=%.0f share_1000hz=%.2f share_440hz=%.2f\n",
				(long)[TGCall shared].state, signalingIn, signalingOut, framesOut, (unsigned long)frames.count, failed,
				energy / 1e6, energy > 0 ? power1000 / energy : 0.0, energy > 0 ? power440 / energy : 0.0);
		fflush(stdout);
		_exit(0);
	}
}
