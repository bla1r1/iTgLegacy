// TGStatusTextTests.m — the phrase table every subtitle carries (bug B4).
//
// Pure functions: no UIKit, no tdjson. Compiled into TGClientTests, so the
// phrasings the chat header, the profile status and the list title show are
// pinned before they ever reach a device.
#import "TGTestRunner.h"
#import "TGStatusText.h"
#import "TGClient.h"

@interface TGStatusTextTests : XCTestCase
@end
@implementation TGStatusTextTests

// A userStatusOffline whole N days back (4 hours into that day, so a test
// run that lands within ±4 h of midnight keeps grading the same day).
static NSDictionary *offlineDays(NSInteger days){
	NSDate *now = [NSDate date];
	NSTimeInterval was = now.timeIntervalSince1970
			- days * 86400.0 - 4 * 3600.0;
	return @{@"@type" : @"userStatusOffline", @"was_online" : @(was)};
}

- (void)testOnline {
	XCTAssertEqualObjects(TGStatusTextFromTDStatus(
			@{@"@type" : @"userStatusOnline"}), @"online");
}

- (void)testRecently {
	XCTAssertEqualObjects(TGStatusTextFromTDStatus(
			@{@"@type" : @"userStatusRecently"}), @"last seen recently");
}

- (void)testAnnouncedWeekAndMonth {
	XCTAssertEqualObjects(TGStatusTextFromTDStatus(
			@{@"@type" : @"userStatusLastWeek"}), @"last seen within a week");
	XCTAssertEqualObjects(TGStatusTextFromTDStatus(
			@{@"@type" : @"userStatusLastMonth"}), @"last seen within a month");
}

- (void)testOfflineTodayNamesTheClock {
	NSString *text = TGStatusTextFromTDStatus(offlineDays(0));
	NSString *prefix = @"last seen at ";
	XCTAssertTrue([text hasPrefix:prefix], "%@", text);
	XCTAssertTrue(text.length > prefix.length, "the clock must follow: %@", text);
}

- (void)testOfflineYesterdaySaysYesterday {
	NSString *text = TGStatusTextFromTDStatus(offlineDays(1));
	XCTAssertTrue([text containsString:@"yesterday"], "%@", text);
	// The bug B4 was about: without the second line this graded into
	// "a long time ago", like a contact seen weeks earlier.
	XCTAssertFalse([text hasSuffix:@"a long time ago"], "%@", text);
}

- (void)testWeekAndMonthGrades {
	NSString *week = TGStatusTextFromTDStatus(offlineDays(3));
	NSString *month = TGStatusTextFromTDStatus(offlineDays(10));
	XCTAssertEqualObjects(week, @"last seen within a week");
	XCTAssertEqualObjects(month, @"last seen within a month");
	XCTAssertFalse([month containsString:@"yesterday"]);
}

- (void)testAncientReadsLongTimeAgo {
	NSString *text = TGStatusTextFromTDStatus(offlineDays(60));
	XCTAssertEqualObjects(text, @"last seen a long time ago");
}

- (void)testZeroTimestampNeverPosesAsToday {
	NSString *text = TGStatusTextFromTDStatus(
			@{@"@type" : @"userStatusOffline", @"was_online" : @(0)});
	XCTAssertEqualObjects(text, @"last seen a long time ago",
			@"a 1970 fallback reads like the phrase every client shows (B4)");
}

- (void)testEmptyStatusReadsRecently {
	NSString *text = TGStatusTextFromTDStatus(@{@"@type" : @"userStatusEmpty"});
	XCTAssertEqualObjects(text, @"last seen recently",
			@"the no-last-seen case every client phrases");
}

- (void)testNetworkPhrases {
	NSString *waiting = TGNetworkSubtitleForState(
			(NSInteger)TGConnectionStateWaitingForNetwork, nil);
	NSString *connecting = TGNetworkSubtitleForState(
			(NSInteger)TGConnectionStateConnecting, @"");
	NSString *updating = TGNetworkSubtitleForState(
			(NSInteger)TGConnectionStateUpdating, @"");
	NSString *ready = TGNetworkSubtitleForState(
			(NSInteger)TGConnectionStateReady, @"anything");
	NSString *unknown = TGNetworkSubtitleForState(999, @"Something unusual");

	XCTAssertEqualObjects(waiting, @"Waiting for network");
	XCTAssertEqualObjects(connecting, @"Connecting...");
	XCTAssertEqualObjects(updating, @"Updating...");
	XCTAssertNil(ready, @"'ready' hands ownership back - it names nothing");
	XCTAssertEqualObjects(unknown, @"Something unusual",
			@"a future state name passes through verbatim");
}

@end
