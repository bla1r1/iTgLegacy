// TGPlaybackQueueTests.m — a round note between two voice notes used to be
// skipped, because the queue only looked for voice notes.
#import "TGTestRunner.h"
#import "TGPlaybackQueue.h"

@interface TGPlaybackQueueTests : XCTestCase @end

@implementation TGPlaybackQueueTests

- (void)testPrefetch_TakesTheNextTrackAndStopsAtTheEnd {
	NSArray *list = @[@{@"docId" : @1}, @{@"docId" : @2}, @{@"docId" : @3}];
	XCTAssertEqualObjects(TGTrackToPrefetch(list, 0, NO, NO), @2);
	XCTAssertNil(TGTrackToPrefetch(list, 2, NO, NO));
	XCTAssertEqualObjects(TGTrackToPrefetch(list, 2, NO, YES), @1);
}

- (void)testPrefetch_ShuffleAndHugeFilesAreLeftAlone {
	NSArray *list = @[@{@"docId" : @1}, @{@"docId" : @2, @"docSize" : @(40LL * 1024 * 1024)}];
	XCTAssertNil(TGTrackToPrefetch(list, 0, YES, NO));
	XCTAssertNil(TGTrackToPrefetch(list, 0, NO, NO));
	NSArray *missing = @[@{@"docId" : @1}, @{@"docId" : [NSNull null]}];
	XCTAssertNil(TGTrackToPrefetch(missing, 0, NO, NO));
}

- (void)testRoundNoteAfterVoiceIsNotSkipped {
	NSArray *chat = @[
		@{@"id" : @1, @"kind" : @"messageVoiceNote", @"type" : @"voice", @"docId" : @10},
		@{@"id" : @2, @"kind" : @"messageText"},
		@{@"id" : @3, @"kind" : @"messageVideoNote", @"docId" : @30},
		@{@"id" : @4, @"kind" : @"messageVoiceNote", @"type" : @"voice", @"docId" : @40},
	];
	XCTAssertEqual(TGNextPlayableRow(chat, 1), (NSInteger)2);
	XCTAssertEqual(TGNextPlayableRow(chat, 3), (NSInteger)3);
}

- (void)testOwnNoteShowsItsDotUntilOpened {
	NSDictionary *sent = @{@"outgoing" : @YES, @"unplayed" : @YES};
	XCTAssertTrue(TGShowsUnplayedMark(sent, NO));
	XCTAssertFalse(TGShowsUnplayedMark((@{@"outgoing" : @YES, @"unplayed" : @NO}), NO));
	XCTAssertTrue(TGShowsUnplayedMark((@{@"outgoing" : @NO, @"unplayed" : @YES}), NO));
}

- (void)testNobodyReportsBackInSavedMessagesOrOnAChannel {
	XCTAssertFalse(TGShowsUnplayedMark((@{@"outgoing" : @YES, @"unplayed" : @YES}), YES));
	XCTAssertFalse(TGShowsUnplayedMark((@{@"outgoing" : @YES, @"unplayed" : @YES, @"channelPost" : @YES}), NO));
}

- (void)testSendingRowIsNotPlayable {
	NSArray *chat = @[
		@{@"id" : @1, @"kind" : @"messageVoiceNote", @"docId" : @10},
		@{@"id" : @2, @"kind" : @"messageVideoNote", @"docId" : @20,
		  @"sending" : @YES},
		@{@"id" : @3, @"kind" : @"messageVoiceNote", @"docId" : @30},
	];
	XCTAssertEqual(TGNextPlayableRow(chat, 1), (NSInteger)2);
	XCTAssertEqual(TGNextPlayableRow(chat, 3), (NSInteger)NSNotFound);
}

- (void)testEndOfChatAndUnknownMessageHaveNoNext {
	NSArray *chat = @[@{@"id" : @1, @"kind" : @"messageVideoNote", @"docId" : @10}];
	XCTAssertEqual(TGNextPlayableRow(chat, 1), (NSInteger)NSNotFound);
	XCTAssertEqual(TGNextPlayableRow(chat, 99), (NSInteger)NSNotFound);
}

- (void)testNoteWithoutAFileIsPassedOver {
	NSArray *chat = @[
		@{@"id" : @1, @"kind" : @"messageVoiceNote", @"docId" : @10},
		@{@"id" : @2, @"kind" : @"messageVideoNote"},
		@{@"id" : @3, @"kind" : @"messageVoiceNote", @"docId" : @30},
	];
	XCTAssertEqual(TGNextPlayableRow(chat, 1), (NSInteger)2);
}

@end
