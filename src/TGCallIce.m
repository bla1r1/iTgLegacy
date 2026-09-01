#import "TGCallIce.h"
#import "TGCallStun.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

@interface TGCallIce ()
@property (nonatomic, strong) NSMutableArray *targets;      // NSData of sockaddr_in
@property (nonatomic, strong) NSData *chosen;               // the one that answered
@property (nonatomic, assign) int socketHandle;
@property (nonatomic, strong) NSTimer *checker;
@property (nonatomic, assign) uint64_t tieBreaker;
@property (nonatomic, assign) BOOL connectedOverRelay;
@property (nonatomic, assign) BOOL peerAddressIsPublic;
@end

@implementation TGCallIce

- (instancetype)init {
	if ((self = [super init])){
		_targets = [NSMutableArray array];
		_socketHandle = -1;
		arc4random_buf(&_tieBreaker, sizeof(_tieBreaker));
	}
	return self;
}

- (BOOL)start {
	if (self.transport){
		// Nothing to open: the reflector carries everything.
		self.checker = [NSTimer scheduledTimerWithTimeInterval:0.3
														target:self
													  selector:@selector(sendChecks)
													  userInfo:nil
													   repeats:YES];
		return YES;
	}

	self.socketHandle = socket(AF_INET, SOCK_DGRAM, 0);
	if (self.socketHandle < 0)
		return NO;

	struct sockaddr_in local;
	memset(&local, 0, sizeof(local));
	local.sin_family = AF_INET;
	local.sin_addr.s_addr = htonl(INADDR_ANY);
	local.sin_port = 0;    // any port; the peer learns it from our checks
	bind(self.socketHandle, (struct sockaddr *)&local, sizeof(local));

	[NSThread detachNewThreadSelector:@selector(readLoop) toTarget:self withObject:nil];
	self.checker = [NSTimer scheduledTimerWithTimeInterval:0.3
													target:self
												  selector:@selector(sendChecks)
												  userInfo:nil
												   repeats:YES];
	return YES;
}

/// "candidate:<foundation> <component> udp <priority> <ip> <port> typ <type> ..."
- (void)addPeerCandidate:(NSString *)candidate {
	NSArray *parts = [candidate componentsSeparatedByString:@" "];
	if (parts.count < 6)
		return;

	NSString *ip = parts[4];
	int port = [parts[5] intValue];

	struct sockaddr_in target;
	memset(&target, 0, sizeof(target));
	target.sin_family = AF_INET;
	target.sin_port = htons((uint16_t)port);
	// IPv6 candidates are skipped: this device has no route for them.
	if (inet_pton(AF_INET, ip.UTF8String, &target.sin_addr) != 1)
		return;

	NSData *address = [NSData dataWithBytes:&target length:sizeof(target)];
	// XOR-MAPPED-ADDRESS has to name an address the peer recognises as its own,
	// or WebRTC invents a peer-reflexive local candidate for whatever we put
	// there - and 0.0.0.0:0, which is what an unset one becomes, leaves it with
	// a candidate it can never send from. A public address is the honest answer;
	// any address they published is a usable one. This peer offered only host
	// candidates, so waiting for srflx meant never answering at all.
	BOOL isPublic = [candidate rangeOfString:@"typ srflx"].location != NSNotFound;
	if (!self.peerAddress || (isPublic && !self.peerAddressIsPublic)){
		self.peerAddress = address;
		self.peerAddressIsPublic = isPublic;
		NSLog(@"TGCallIce: quoting %@:%d back as their mapped address", ip, port);
	}

	for (NSData *existing in self.targets)
		if ([existing isEqualToData:address])
			return;
	[self.targets addObject:address];
	NSLog(@"TGCallIce: will check %@:%d", ip, port);
}

- (void)sendChecks {
	if (!self.peerPwd.length || (!self.transport && self.socketHandle < 0))
		return;


	// The username is the peer's fragment first: it names who is being asked.
	NSString *username = [NSString stringWithFormat:@"%@:%@",
			self.peerUfrag ?: @"", self.localUfrag ?: @""];
	NSData *request = [TGCallStun bindingRequestWithUsername:username
													password:self.peerPwd
												  tieBreaker:self.tieBreaker
												useCandidate:YES];

	if (self.transport){
		self.transport(request);
		return;
	}

	NSArray *targets = self.chosen ? @[self.chosen] : self.targets;
	for (NSData *address in targets)
		sendto(self.socketHandle, request.bytes, request.length, 0,
			   (const struct sockaddr *)address.bytes, (socklen_t)address.length);
}

- (void)readLoop {
	uint8_t buffer[2048];
	while (self.socketHandle >= 0){
		struct sockaddr_in from;
		socklen_t fromLength = sizeof(from);
		ssize_t got = recvfrom(self.socketHandle, buffer, sizeof(buffer), 0,
							   (struct sockaddr *)&from, &fromLength);
		if (got <= 0)
			break;

		NSData *packet = [NSData dataWithBytes:buffer length:got];
		NSData *address = [NSData dataWithBytes:&from length:sizeof(from)];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self handlePacket:packet from:address];
		});
	}
}

/// For packets that arrived over the reflector, where there is no sender
/// address to speak of.
- (void)handleRelayedPacket:(NSData *)packet {
	int type = [TGCallStun messageTypeOf:packet];

	if (type == 0x0001){
		NSData *response = [TGCallStun bindingResponseTo:packet
												password:self.localPwd
											 fromAddress:self.peerAddress];
		NSLog(@"TGCallIce: their check, our pwd %@, response %lu bytes, transport %@",
				self.localPwd.length ? @"set" : @"MISSING",
				(unsigned long)response.length, self.transport ? @"set" : @"MISSING");
		if (response && self.transport)
			self.transport(response);
		[self markConnected:nil];
		return;
	}
	if (type == 0x0101){
		[self markConnected:nil];
		return;
	}
	if (type < 0 && self.onMedia)
		self.onMedia(packet);
}

- (void)handlePacket:(NSData *)packet from:(NSData *)address {
	int type = [TGCallStun messageTypeOf:packet];

	if (type == 0x0001){
		// A check from the peer. Answering it is what makes the pair usable
		// in their direction.
		NSData *response = [TGCallStun bindingResponseTo:packet
												password:self.localPwd
											 fromAddress:address];
		if (response)
			sendto(self.socketHandle, response.bytes, response.length, 0,
				   (const struct sockaddr *)address.bytes, (socklen_t)address.length);
		[self markConnected:address];
		return;
	}

	if (type == 0x0101){
		[self markConnected:address];
		return;
	}

	if (type < 0 && self.onMedia)
		self.onMedia(packet);
}

- (void)markConnected:(NSData *)address {
	NSLog(@"TGCallIce: markConnected, chosen %@, relay %d",
			self.chosen ? @"set" : @"nil", (int)self.connectedOverRelay);
	if (self.chosen || (!address && self.connectedOverRelay))
		return;

	if (!address){
		self.connectedOverRelay = YES;
		NSLog(@"TGCallIce: connected over the reflector");
		if (self.onConnected)
			self.onConnected(@"reflector", 0);
		return;
	}
	self.chosen = address;

	const struct sockaddr_in *from = (const struct sockaddr_in *)address.bytes;
	char text[INET_ADDRSTRLEN] = {0};
	inet_ntop(AF_INET, &from->sin_addr, text, sizeof(text));
	NSLog(@"TGCallIce: connected to %s:%u", text, ntohs(from->sin_port));
	if (self.onConnected)
		self.onConnected([NSString stringWithUTF8String:text], ntohs(from->sin_port));
}

- (void)sendMedia:(NSData *)payload {
	if (self.transport){
		self.transport(payload);
		return;
	}
	if (!self.chosen || self.socketHandle < 0)
		return;
	sendto(self.socketHandle, payload.bytes, payload.length, 0,
		   (const struct sockaddr *)self.chosen.bytes, (socklen_t)self.chosen.length);
}

- (void)stop {
	[self.checker invalidate];
	self.checker = nil;
	int handle = self.socketHandle;
	self.socketHandle = -1;
	if (handle >= 0)
		close(handle);
}

@end

// vim:ft=objc
