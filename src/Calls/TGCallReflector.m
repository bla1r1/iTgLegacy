#import "TGCallReflector.h"

#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

@interface TGCallReflector ()
@property (nonatomic, strong) NSString *host;

@property (nonatomic, strong) NSData *peerTag;
@property (nonatomic, assign) int socketHandle;
@property (nonatomic, strong) NSThread *reader;
@property (nonatomic, assign) uint32_t observedTag;
@property (nonatomic, assign) uint32_t lastDestination;
@property (nonatomic, strong) NSTimer *pinger;
@end

@implementation TGCallReflector {
	struct sockaddr_in _server;

	// Guards _stopping and _readerFinished. stop has to know that the reader
	// is gone before it closes the descriptor and returns: otherwise the thread
	// can still be inside onPacket, or blocked in recv on a descriptor number
	// the next call will reuse.
	NSCondition *_lifecycle;
	BOOL _stopping;
	BOOL _readerFinished;
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port peerTag:(NSData *)peerTag {
	if ((self = [super init])){
		_host = host;
		_port = port;
		_peerTag = peerTag;
		_socketHandle = -1;
		_lifecycle = [[NSCondition alloc] init];
		// Four random bytes name this side of the call. The reflector uses
		// them to decide which way a packet goes.
		arc4random_buf(&_localTag, sizeof(_localTag));
	}
	return self;
}

- (uint32_t)fallbackTag {
	if (self.peerTag.length >= 16) {
		uint32_t tag = 0;
		memcpy(&tag, (const uint8_t *)self.peerTag.bytes + 12, 4);
		return tag;
	}
	return 0;
}

// Tag for addressing peer on reflector
- (NSData *)tagFor:(uint32_t)tag {
	if (self.peerTag.length < 16)
		return nil;
	NSMutableData *out = [NSMutableData dataWithBytes:self.peerTag.bytes length:12];
	[out appendBytes:&tag length:4];
	return out;
}

- (BOOL)start {
	if (self.peerTag.length < 16){
		NSLog(@"TGCallReflector: peer tag is %lu bytes", (unsigned long)self.peerTag.length);
		return NO;
	}

	memset(&_server, 0, sizeof(_server));
	_server.sin_family = AF_INET;
	_server.sin_port = htons(self.port);
	if (inet_pton(AF_INET, self.host.UTF8String, &_server.sin_addr) != 1){
		NSLog(@"TGCallReflector: cannot parse %@", self.host);
		return NO;
	}

	self.socketHandle = socket(AF_INET, SOCK_DGRAM, 0);
	if (self.socketHandle < 0){
		NSLog(@"TGCallReflector: no socket");
		return NO;
	}

	// shutdown() does not wake recv on an unconnected UDP socket, and close()
	// from another thread does not either. A short receive timeout is what
	// lets readLoop notice -stop and exit; without it the thread outlives the
	// call, keeps the descriptor, and after the number is reused it reads the
	// next call's datagrams.
	struct timeval timeout = { 0, 100000 };   // 100 ms
	setsockopt(self.socketHandle, SOL_SOCKET, SO_RCVTIMEO,
			   &timeout, sizeof(timeout));

	NSLog(@"TGCallReflector: %@:%u, our tag %08x", self.host, self.port, self.localTag);

	[_lifecycle lock];
	_stopping = NO;
	_readerFinished = NO;
	[_lifecycle unlock];

	self.reader = [[NSThread alloc] initWithTarget:self selector:@selector(readLoop) object:nil];
	[self.reader start];

	// The reflector drops a route it has not heard from; the official client
	// pings on the same cadence.
	self.pinger = [NSTimer scheduledTimerWithTimeInterval:0.5
												   target:self
												 selector:@selector(ping)
												 userInfo:nil
												  repeats:YES];
	[self ping];
	return YES;
}

- (void)ping {
	NSData *tag = [self tagFor:self.localTag];
	if (!tag)
		return;

	NSMutableData *packet = [NSMutableData dataWithData:tag];
	uint8_t filler[16];
	memset(filler, 0xFF, sizeof(filler));
	filler[12] = 0xFE;
	[packet appendBytes:filler length:16];

	uint64_t marker = CFSwapInt64HostToBig(123);
	[packet appendBytes:&marker length:8];

	[self send:packet];
}

- (void)sendPayload:(NSData *)payload toTag:(uint32_t)tag {
	NSData *destination = [self tagFor:tag];
	if (!destination)
		return;

	// Audio comes through here fifty times a second and syslog drops lines when
	// it is flooded - which costs exactly the lines worth reading.
	if (tag != self.lastDestination){
		self.lastDestination = tag;
		NSLog(@"TGCallReflector: addressing tag %u on %@", tag, self.host);
	}

	NSMutableData *packet = [NSMutableData dataWithData:destination];
	[packet appendBytes:&_localTag length:4];

	uint32_t size = CFSwapInt32HostToBig((uint32_t)payload.length);
	[packet appendBytes:&size length:4];
	[packet appendData:payload];

	while (packet.length % 4)
		[packet appendBytes:"\0" length:1];

	[self send:packet];
}


- (void)sendPayload:(NSData *)payload {
	// Answer whoever actually wrote to us: the tag in the header of the last
	// packet is the truth, and a tag read out of a candidate can be stale or
	// belong to a different reflector.
	uint32_t destination = self.observedTag ?: (self.remoteTag ?: [self fallbackTag]);
	if (!destination){
		NSLog(@"TGCallReflector: nothing has come from the peer yet");
		return;
	}
	if (destination != self.lastDestination){
		self.lastDestination = destination;
		NSLog(@"TGCallReflector: addressing tag %u", destination);
	}

	NSData *tag = [self tagFor:destination];
	if (!tag){
		NSLog(@"TGCallReflector: no usable tag, peer tag is %lu bytes",
				(unsigned long)self.peerTag.length);
		return;
	}
	NSMutableData *packet = [NSMutableData dataWithData:tag];
	[packet appendBytes:&_localTag length:4];

	uint32_t size = CFSwapInt32HostToBig((uint32_t)payload.length);
	[packet appendBytes:&size length:4];
	[packet appendData:payload];

	while (packet.length % 4)
		[packet appendBytes:"\0" length:1];

	[self send:packet];
}

- (void)send:(NSData *)packet {
	// Hold the lifecycle lock across the send: stop closes the descriptor only
	// after the reader is gone, but a main-thread send must not race that close
	// and land on a descriptor number that now belongs to someone else.
	[_lifecycle lock];
	if (self.socketHandle >= 0)
		sendto(self.socketHandle, packet.bytes, packet.length, 0,
			   (struct sockaddr *)&_server, sizeof(_server));
	[_lifecycle unlock];
}

/// The reader thread. Its own thread rather than the main queue, for the whole
/// life of the socket: a call delivers fifty to a hundred datagrams a second,
/// each of which has to be parsed, decrypted and decoded, and doing any of
/// that between runloop turns is what froze the interface during a call.
/// Everything downstream of onPacket - TGCall's slice parsing, the Opus
/// decode, the ring buffer the audio unit reads - runs here too, so the main
/// thread does no per-packet work at all.
- (void)readLoop {
	// One buffer for the life of the thread. The packet handed to onPacket is
	// a view over it and is only read inside the call, so nothing is copied.
	uint8_t buffer[2048];
	uint32_t received = 0;
	for (;;) {
		[_lifecycle lock];
		BOOL stopping = _stopping;
		int handle = self.socketHandle;
		[_lifecycle unlock];
		if (stopping || handle < 0)
			break;

		ssize_t got = recv(handle, buffer, sizeof(buffer), 0);
		if (got < 0) {
			// The receive timeout is how this thread notices -stop when
			// shutdown cannot wake an unconnected UDP socket.
			if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
				continue;
			break;
		}
		if (got == 0)
			continue;   // an empty datagram, not end of stream

		// A relayed packet carries the sender's four bytes right after the
		// sixteen-byte tag; that is the address to answer.
		if (got > 20){
			uint32_t sender = 0;
			memcpy(&sender, buffer + 16, 4);
			if (sender && sender != 0xFFFFFFFF && sender != self.localTag && !self.observedTag)
				self.observedTag = sender;
		}

		// A line per packet floods syslog at this rate, and syslog answers by
		// dropping lines - which costs exactly the ones worth reading.
		if (++received == 1 || received % 250 == 0)
			NSLog(@"TGCallReflector: %u packets in, last %ld bytes",
					received, (long)got);

		[_lifecycle lock];
		BOOL stoppingNow = _stopping;
		[_lifecycle unlock];
		if (stoppingNow)
			break;

		if (self.onPacket){
			NSData *packet = [NSData dataWithBytesNoCopy:buffer
												  length:got
											freeWhenDone:NO];
			self.onPacket(packet);
		}
	}

	[_lifecycle lock];
	_readerFinished = YES;
	[_lifecycle broadcast];
	[_lifecycle unlock];
}

- (void)stop {
	[_lifecycle lock];
	_stopping = YES;
	int handle = self.socketHandle;
	NSThread *reader = self.reader;
	[_lifecycle unlock];

	[self.pinger invalidate];
	self.pinger = nil;

	// Best effort: on an unconnected UDP socket this fails with ENOTCONN. The
	// receive timeout is what actually makes the reader return.
	if (handle >= 0)
		shutdown(handle, SHUT_RDWR);

	// Wait for the reader before closing: until it has returned it may be
	// inside onPacket, or about to recv on this descriptor number.
	if (reader && reader != [NSThread currentThread]) {
		[_lifecycle lock];
		while (!_readerFinished)
			[_lifecycle wait];
		[_lifecycle unlock];
	}

	[_lifecycle lock];
	handle = self.socketHandle;
	self.socketHandle = -1;
	self.reader = nil;
	[_lifecycle unlock];

	if (handle >= 0)
		close(handle);
}

@end

// vim:ft=objc
