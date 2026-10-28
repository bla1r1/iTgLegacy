//
// TGMessageStreamStoreTests.m - Unit tests for TGMessageStreamStore C++ manager
//
#import <Foundation/Foundation.h>
#import "TGTestRunner.h"
#import "TGMessageStreamStore.h"

@interface TGMessageStreamStoreTests : XCTestCase
@end

@implementation TGMessageStreamStoreTests

- (void)testInitialResetAndBoundaries {
	TGMessageStreamStore *store = [[TGMessageStreamStore alloc] init];
	XCTAssertEqual((NSUInteger)0, store.count);
	XCTAssertEqual((int64_t)0, store.oldestMessageId);
	XCTAssertEqual((int64_t)0, store.newestMessageId);

	NSArray *initial = @[
		@{@"id": @(10), @"text": @"hello"},
		@{@"id": @(20), @"text": @"world"},
		@{@"id": @(30), @"text": @"foo"}
	];
	[store resetWithMessages:initial];

	XCTAssertEqual((NSUInteger)3, store.count);
	XCTAssertEqual((int64_t)10, store.oldestMessageId);
	XCTAssertEqual((int64_t)30, store.newestMessageId);
	XCTAssertTrue([store containsMessageId:20]);
	XCTAssertFalse([store containsMessageId:99]);
}

- (void)testPrependOlderDeduplication {
	TGMessageStreamStore *store = [[TGMessageStreamStore alloc] init];
	[store resetWithMessages:@[
		@{@"id": @(20), @"text": @"middle"},
		@{@"id": @(30), @"text": @"newest"}
	]];

	NSArray *older = @[
		@{@"id": @(5),  @"text": @"first"},
		@{@"id": @(10), @"text": @"second"},
		@{@"id": @(20), @"text": @"duplicate"}
	];
	NSUInteger added = [store prependOlderMessages:older];
	XCTAssertEqual((NSUInteger)2, added);
	XCTAssertEqual((NSUInteger)4, store.count);
	XCTAssertEqual((int64_t)5, store.oldestMessageId);
	XCTAssertEqual((int64_t)30, store.newestMessageId);

	NSArray *all = [store messages];
	XCTAssertEqual((int64_t)5,  [all[0][@"id"] longLongValue]);
	XCTAssertEqual((int64_t)10, [all[1][@"id"] longLongValue]);
	XCTAssertEqual((int64_t)20, [all[2][@"id"] longLongValue]);
	XCTAssertEqual((int64_t)30, [all[3][@"id"] longLongValue]);
}

- (void)testAppendNewerDeduplication {
	TGMessageStreamStore *store = [[TGMessageStreamStore alloc] init];
	[store resetWithMessages:@[
		@{@"id": @(10), @"text": @"oldest"},
		@{@"id": @(20), @"text": @"middle"}
	]];

	NSArray *newer = @[
		@{@"id": @(20), @"text": @"duplicate"},
		@{@"id": @(30), @"text": @"newer"},
		@{@"id": @(40), @"text": @"newest"}
	];
	NSUInteger added = [store appendNewerMessages:newer];
	XCTAssertEqual((NSUInteger)2, added);
	XCTAssertEqual((NSUInteger)4, store.count);
	XCTAssertEqual((int64_t)10, store.oldestMessageId);
	XCTAssertEqual((int64_t)40, store.newestMessageId);
}

- (void)testRemoveMessage {
	TGMessageStreamStore *store = [[TGMessageStreamStore alloc] init];
	[store resetWithMessages:@[
		@{@"id": @(10), @"text": @"one"},
		@{@"id": @(20), @"text": @"two"},
		@{@"id": @(30), @"text": @"three"}
	]];

	BOOL removed = [store removeMessageId:20];
	XCTAssertTrue(removed);
	XCTAssertEqual((NSUInteger)2, store.count);
	XCTAssertFalse([store containsMessageId:20]);

	BOOL removedNonExistent = [store removeMessageId:999];
	XCTAssertFalse(removedNonExistent);
}

@end
