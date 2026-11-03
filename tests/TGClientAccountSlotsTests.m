// TGClientAccountSlotsTests.m — several accounts on one device, one TDLib
// client at a time. These pin the slot arithmetic and the reset boundary so
// an account's data cannot bleed into another's.
//
// They run in the TGClientTests binary (tests/Makefile), which compiles the
// real TGClient and its categories. Each test works the two defaults keys the
// accounts category owns — TGAccountSlots and TGActiveAccountSlot — and puts
// whatever was there back afterwards, so the host's own preferences survive.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientAccountSlotsTests : XCTestCase @end

/// A shared client with the in-memory surfaces these tests read back emptied,
/// the way the other client suites start.
static TGClient *SlotsClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	return c;
}

@implementation TGClientAccountSlotsTests {
	id _savedSlots;
	id _savedActive;
}

- (void)setUp {
	[super setUp];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	_savedSlots = [d objectForKey:@"TGAccountSlots"];
	_savedActive = [d objectForKey:@"TGActiveAccountSlot"];
	[d removeObjectForKey:@"TGAccountSlots"];
	[d removeObjectForKey:@"TGActiveAccountSlot"];
}

- (void)tearDown {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if (_savedSlots)
		[d setObject:_savedSlots forKey:@"TGAccountSlots"];
	else
		[d removeObjectForKey:@"TGAccountSlots"];
	if (_savedActive)
		[d setObject:_savedActive forKey:@"TGActiveAccountSlot"];
	else
		[d removeObjectForKey:@"TGActiveAccountSlot"];
	[super tearDown];
}

// ─── database directory ──────────────────────────────────────────────────────

- (void)testDatabaseDirectory_Slot0KeepsTdlibAndSlot2GetsSuffix {
	// Slot 0 keeps the pre-accounts path so an existing install's database
	// is still found; slot N > 0 gets its own directory.
	XCTAssertEqualObjects(TGAccountDatabaseDirectory(@"Documents", 0),
			@"Documents/tdlib");
	XCTAssertEqualObjects(TGAccountDatabaseDirectory(@"Documents", 2),
			@"Documents/tdlib-2");
}

// ─── addAccount ──────────────────────────────────────────────────────────────

- (void)testAddAccount_NeverReturnsTheActiveSlot {
	[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"TGActiveAccountSlot"];
	// An install that signed out of slot 0 leaves an empty list; the active
	// slot still counts as taken, so the new account lands in slot 1.
	NSInteger slot = [TGClient addAccount];
	XCTAssertEqual(slot, 1);

	// The active slot was not in the list, so addAccount recorded it too.
	NSArray *slots = [TGClient accountSlots];
	BOOL has0 = NO, has1 = NO;
	for (NSDictionary *entry in slots){
		NSInteger s = [entry[@"slot"] integerValue];
		if (s == 0) has0 = YES;
		if (s == 1) has1 = YES;
	}
	XCTAssertTrue(has0);
	XCTAssertTrue(has1);
}

- (void)testAddAccount_ReturnsMinusOneWhenAllThreeAreTaken {
	[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"TGActiveAccountSlot"];
	[[NSUserDefaults standardUserDefaults] setObject:@[
		@{@"slot" : @0}, @{@"slot" : @1}, @{@"slot" : @2},
	] forKey:@"TGAccountSlots"];
	XCTAssertEqual([TGClient addAccount], (NSInteger)-1);
}

// ─── recordActiveAccountFromMe ───────────────────────────────────────────────

- (void)testRecordActiveAccountFromMe_UpdatesOnlyTheActiveSlotRow {
	[[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"TGActiveAccountSlot"];
	[[NSUserDefaults standardUserDefaults] setObject:@[
		@{@"slot" : @0, @"title" : @"Old0", @"phone" : @"+0"},
		@{@"slot" : @1, @"title" : @"", @"phone" : @""},
		@{@"slot" : @2, @"title" : @"Old2", @"phone" : @"+2"},
	] forKey:@"TGAccountSlots"];

	TGClient *c = SlotsClient();
	[c recordActiveAccountFromMe:
			@{@"first_name" : @"Alice", @"username" : @"alice", @"phone" : @"+100"}];

	NSArray *slots = [TGClient accountSlots];
	for (NSDictionary *entry in slots){
		NSInteger s = [entry[@"slot"] integerValue];
		if (s == 0){
			XCTAssertEqualObjects(entry[@"title"], @"Old0");
			XCTAssertEqualObjects(entry[@"phone"], @"+0");
		} else if (s == 1){
			XCTAssertEqualObjects(entry[@"title"], @"Alice");
			XCTAssertEqualObjects(entry[@"phone"], @"+100");
		} else if (s == 2){
			XCTAssertEqualObjects(entry[@"title"], @"Old2");
			XCTAssertEqualObjects(entry[@"phone"], @"+2");
		}
	}
}

// ─── resetStateForAccountSwitch ──────────────────────────────────────────────

- (void)testResetStateForAccountSwitch_EmptiesChatsUsersAndMe {
	TGClient *c = SlotsClient();
	c.chatsById[@1] = [@{@"title" : @"one"} mutableCopy];
	c.chatsById[@2] = [@{@"title" : @"two"} mutableCopy];
	c.usersById[@1] = @"User One";
	c.usersById[@2] = @"User Two";

	[c resetStateForAccountSwitch];

	XCTAssertNil(c.me);
	XCTAssertEqual(c.chatsById.count, (NSUInteger)0);
	XCTAssertEqual(c.usersById.count, (NSUInteger)0);
}

@end
