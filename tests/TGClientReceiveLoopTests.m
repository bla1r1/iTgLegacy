// TGClientReceiveLoopTests.m — the receive thread has to rest when TDLib is idle.
//
// The single-threaded ClientManager ignores td_json_client_receive's timeout, so
// a loop that only retries burns the one core of an A4 whenever nothing happens.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"
#include <libkern/OSAtomic.h>

@interface TGClient (ReceiveLoopTests)
- (void)receiveLoop;
@end

@interface TGClientReceiveLoopTests : XCTestCase @end

static volatile int32_t recvCalls;

static const char *countingRecv(void *client, double timeout) {
	OSAtomicIncrement32(&recvCalls);
	return NULL;
}

@implementation TGClientReceiveLoopTests

- (void)testIdleLoopDoesNotSpin {
	TGClient *c = TGClient.shared;
	td_recv_fn savedRecv = c.td_recv;
	BOOL savedAvailable = c.available;

	recvCalls = 0;
	c.td_recv = countingRecv;
	c.available = NO;
	c.running = YES;
	[NSThread detachNewThreadSelector:@selector(receiveLoop) toTarget:c withObject:nil];
	[NSThread sleepForTimeInterval:0.2];
	c.running = NO;
	[NSThread sleepForTimeInterval:0.05];

	// 0.2 s at 20 ms is 10 rounds; a spinning loop makes millions.
	XCTAssertTrue(recvCalls < 30, "the idle loop polled too often");

	c.td_recv = savedRecv;
	c.available = savedAvailable;
}

@end
