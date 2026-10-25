// TGClientFilesTests.m — regression tests for the download queue (bug B2).
//
// Compiled into TGClientTests, which links the real TGClient + the +Files
// category with tdjson never loaded (requests land in the outbox). The
// watchdog tunable lets the tests fire the 45 s timer inside a test runtime.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

static TGClient *F(void) {
	TGClient *c = TGClient.shared;
	// Only the waiters and the outbox matter here; the chat tables belong
	// to the dialogs suite and a wipe here would be their loss.
	[c.fileWaiters removeAllObjects];
	[c.fileWaiterPriorities removeAllObjects];
	return c;
}

/// The watchdog arms itself on the main queue, so the run loop has to run
/// for the timer to fire inside the test's wall clock.
static void pumpFor(NSTimeInterval seconds){
	[[NSRunLoop mainRunLoop]
			runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/// Pulls the first outbox request whose JSON mentions the fragment, decoded.
static NSDictionary *requestMentioning(TGClient *c, NSString *fragment){
	for (NSData *d in c.outbox){
		NSString *json = [[NSString alloc] initWithData:d
							   encoding:NSUTF8StringEncoding];
		if (![json containsString:fragment])
			continue;
		NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
		return [NSJSONSerialization JSONObjectWithData:
				[trimmed dataUsingEncoding:NSUTF8StringEncoding]
				options:0 error:nil];
	}
	return nil;
}

@interface TGClientFilesTests : XCTestCase
@end
@implementation TGClientFilesTests

- (void)testDownloadFile_DefaultPriorityIsBackground {
	TGClient *c = F();
	[c downloadFile:871 completion:^(NSString *p){ (void)p; }];
	NSDictionary *asked = requestMentioning(c, @"\"file_id\":871");
	XCTAssertNotNil(asked, @"downloadFile must reach the outbox");
	if (!asked) return;
	XCTAssertEqual([asked[@"priority"] integerValue], TGDownloadPriorityBackground,
				   @"long-standing callers keep their rank");
}

- (void)testDownloadFile_AvatarAsksForHighestRank {
	TGClient *c = F();
	[c downloadFile:872 priority:TGDownloadPriorityAvatar
		 completion:^(NSString *p){ (void)p; }];
	NSDictionary *asked = requestMentioning(c, @"\"file_id\":872");
	XCTAssertNotNil(asked);
	if (!asked) return;
	XCTAssertEqual([asked[@"priority"] integerValue], TGDownloadPriorityAvatar,
				   @"avatars must not sit in the grid's queue at rank 1");
}

- (void)testWatchdog_ServesNilButKeepsLateCompletionWorking {
	TGClient *c = F();
	double savedTimeout = TGFileWaiterTimeoutSeconds;
	TGFileWaiterTimeoutSeconds = 0.05;

	__block NSString *served = @"unset";
	[c downloadFile:873 completion:^(NSString *path){ served = path; }];

	pumpFor(0.4);
	XCTAssertNil(served, @"the watchdog must serve nil after the timeout");

	// The whole point (B2): a file that finished downloading after the
	// timeout still reaches the callback. Before the fix the watchdog
	// destroyed the record and a late updateFile notified nobody.
	[c notifyFileWaiters:873 path:@"/var/tmp/story.webp"];
	pumpFor(0.1);   // the delivery runs on the main queue
	XCTAssertEqualObjects(served, @"/var/tmp/story.webp",
						  @"an expired record must survive late completion");

	TGFileWaiterTimeoutSeconds = savedTimeout;
}

- (void)testRetry_SecondWaiterAfterExpiryStillGetsTheFile {
	TGClient *c = F();
	double savedTimeout = TGFileWaiterTimeoutSeconds;
	TGFileWaiterTimeoutSeconds = 0.05;

	[c downloadFile:874 completion:^(NSString *p){ (void)p; }];
	pumpFor(0.3);

	// The consumer the chat list performs on its next pass: ask again.
	__block NSString *late = @"unset";
	[c downloadFile:874 completion:^(NSString *path){ late = path; }];
	[c notifyFileWaiters:874 path:@"/var/tmp/avatar.png"];
	pumpFor(0.1);   // the delivery runs on the main queue
	XCTAssertEqualObjects(late, @"/var/tmp/avatar.png");

	TGFileWaiterTimeoutSeconds = savedTimeout;
}

- (void)testSweep_KeepsARecordWithLiveWaiters {
	TGClient *c = F();
	const NSInteger id = 875;
	[c.fileWaiters setObject:[NSMutableArray
			arrayWithArray:@[ @{ @"cb" : [NSNull null], @"expired" : @NO } ]]
					 forKey:@(id)];
	[c sweepFileWaiters:id];
	@synchronized(c.fileWaiters){
		XCTAssertNotNil(c.fileWaiters[@(id)],
			@"a live waiter keeps the record - late updateFile is still owed");
	}
}

- (void)testSweep_RetiresFullyExpiredRecords {
	TGClient *c = F();
	const NSInteger id = 876;
	[c.fileWaiters setObject:[NSMutableArray
			arrayWithArray:@[ @{ @"cb" : [NSNull null], @"expired" : @YES } ]]
					 forKey:@(id)];
	[c sweepFileWaiters:id];
	@synchronized(c.fileWaiters){
		XCTAssertNil(c.fileWaiters[@(id)],
			@"a record whose waiters have all been told nil gets retired");
	}
}

@end
