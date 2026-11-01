// TGUIFormatTests.m - the shared strings the auth, call, scheduled and
// forward screens print. Every one is a pure function, so the format is
// pinned here instead of being checked by eye on four screens.
#import "TGTestRunner.h"
#import "TGUIFormat.h"

@interface TGUIFormatTests : XCTestCase
@end
@implementation TGUIFormatTests

- (void)testCallDuration {
	XCTAssertEqualObjects(TGUIFormatCallDuration(0), @"0:00");
	XCTAssertEqualObjects(TGUIFormatCallDuration(7), @"0:07");
	XCTAssertEqualObjects(TGUIFormatCallDuration(65), @"1:05");
	XCTAssertEqualObjects(TGUIFormatCallDuration(3729), @"1:02:09");
	XCTAssertEqualObjects(TGUIFormatCallDuration(-4), @"0:00");
}

- (void)testFullPhoneKeepsOnePrefix {
	XCTAssertEqualObjects(TGUIFormatFullPhone(@"+380", @"0671234567"),
			@"+380671234567");
	XCTAssertEqualObjects(TGUIFormatFullPhone(@"+380", @"380671234567"),
			@"+380671234567");
	XCTAssertEqualObjects(TGUIFormatFullPhone(@"380", @"67 123 4567"),
			@"+380671234567");
	XCTAssertEqualObjects(TGUIFormatFullPhone(@"+1", @"(555) 010-9999"),
			@"+15550109999");
	XCTAssertEqualObjects(TGUIFormatFullPhone(@"", @"5550109999"),
			@"+5550109999");
	XCTAssertEqualObjects(TGUIFormatFullPhone(@"+39", @"06 1234 5678"),
			@"+390612345678");
}

- (void)testForwardSearchIgnoresCaseAndAccents {
	XCTAssertTrue(TGUIFormatChatMatches(@"Zürich", @"zurich"));
	XCTAssertTrue(TGUIFormatChatMatches(@"Saved Messages", @""));
	XCTAssertTrue(TGUIFormatChatMatches(@"Team Kyiv", @"kyiv"));
	XCTAssertFalse(TGUIFormatChatMatches(@"Team Kyiv", @"lviv"));
	XCTAssertFalse(TGUIFormatChatMatches(nil, @"x"));
}

- (void)testScheduledRelative {
	XCTAssertEqualObjects(TGUIFormatScheduledRelative(1000, 1000), @"in less than a minute");
	XCTAssertEqualObjects(TGUIFormatScheduledRelative(1000 + 1800, 1000), @"in 30 min");
	XCTAssertEqualObjects(TGUIFormatScheduledRelative(1000 + 2 * 3600 + 15 * 60, 1000),
			@"in 2 h 15 min");
	XCTAssertEqualObjects(TGUIFormatScheduledRelative(1000 + 3 * 86400, 1000), @"in 3 d");
	XCTAssertEqualObjects(TGUIFormatScheduledRelative(0, 1000), @"");
}

- (void)testScheduledWhenNamesTodayAndTomorrow {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *nowDate = [NSDate date];
	NSDate *today = [calendar dateFromComponents:
			[calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit |
								   NSDayCalendarUnit) fromDate:nowDate]];
	NSTimeInterval base = [today timeIntervalSince1970] + 12 * 3600;
	NSString *todayText = TGUIFormatScheduledWhen(base, base);
	NSString *tomorrowText = TGUIFormatScheduledWhen(base + 86400, base);
	XCTAssertTrue([todayText hasPrefix:@"Today at "]);
	XCTAssertTrue([tomorrowText hasPrefix:@"Tomorrow at "]);
	XCTAssertEqualObjects(TGUIFormatScheduledWhen(0, base), @"");
}

@end
