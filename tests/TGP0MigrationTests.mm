//
// TGP0MigrationTests.mm - Unit tests for Phase 2 / P0 critical migrations
//
#import "TGTestRunner.h"
#import "TGLocklessRingBuffer.hpp"
#import "TGImageLruCache.h"
#include <vector>
#include <cmath>

@interface TGP0MigrationTests : XCTestCase
@end

@implementation TGP0MigrationTests

- (void)testLocklessRingBuffer_BasicReadWrite {
	TGLocklessRingBuffer<int16_t, 16> rb;
	XCTAssertEqual((int)rb.capacity(), 16);
	XCTAssertEqual((int)rb.available_read(), 0);
	XCTAssertEqual((int)rb.available_write(), 16);

	int16_t inData[8] = {1, 2, 3, 4, 5, 6, 7, 8};
	size_t written = rb.write(inData, 8);
	XCTAssertEqual((int)written, 8);
	XCTAssertEqual((int)rb.available_read(), 8);
	XCTAssertEqual((int)rb.available_write(), 8);

	int16_t outData[8] = {0};
	size_t readCount = rb.read(outData, 8);
	XCTAssertEqual((int)readCount, 8);
	XCTAssertEqual((int)rb.available_read(), 0);
	for (int i = 0; i < 8; i++) {
		XCTAssertEqual((int)outData[i], i + 1);
	}
}

- (void)testLocklessRingBuffer_CircularWrap {
	TGLocklessRingBuffer<int16_t, 16> rb;
	// Write 12
	int16_t d1[12];
	for (int i = 0; i < 12; i++) d1[i] = (int16_t)(i + 1);
	rb.write(d1, 12);

	// Read 10 (read index is now 10)
	int16_t out1[10];
	rb.read(out1, 10);
	XCTAssertEqual((int)rb.available_read(), 2);

	// Write 10 more (this wraps around 16)
	int16_t d2[10];
	for (int i = 0; i < 10; i++) d2[i] = (int16_t)(100 + i);
	size_t w2 = rb.write(d2, 10);
	XCTAssertEqual((int)w2, 10);
	XCTAssertEqual((int)rb.available_read(), 12);

	// Read all 12
	int16_t out2[12];
	size_t r2 = rb.read(out2, 12);
	XCTAssertEqual((int)r2, 12);
	// First 2 elements should be 11, 12
	XCTAssertEqual((int)out2[0], 11);
	XCTAssertEqual((int)out2[1], 12);
	// Next 10 elements should be 100..109
	for (int i = 0; i < 10; i++) {
		XCTAssertEqual((int)out2[2 + i], 100 + i);
	}
}

- (void)testImageLruCache_EvictionAndOrdering {
	TGImageLruCache *cache = [[TGImageLruCache alloc] initWithCapacity:3];
	XCTAssertEqual((int)cache.capacity, 3);
	XCTAssertEqual((int)cache.count, 0);

	UIImage *img1 = [[UIImage alloc] init];
	UIImage *img2 = [[UIImage alloc] init];
	UIImage *img3 = [[UIImage alloc] init];
	UIImage *img4 = [[UIImage alloc] init];

	cache[@(101)] = img1;
	cache[@(102)] = img2;
	cache[@(103)] = img3;
	XCTAssertEqual((int)cache.count, 3);

	// Touch 101 to make it most recently used
	UIImage *got101 = cache[@(101)];
	XCTAssertTrue(got101 != nil);

	// Insert 104 -> should evict 102 (since 101 was refreshed and 103 was inserted after 102)
	cache[@(104)] = img4;
	XCTAssertEqual((int)cache.count, 3);

	XCTAssertTrue(cache[@(101)] != nil);
	XCTAssertTrue(cache[@(102)] == nil); // evicted!
	XCTAssertTrue(cache[@(103)] != nil);
	XCTAssertTrue(cache[@(104)] != nil);

	[cache removeAllObjects];
	XCTAssertEqual((int)cache.count, 0);
	XCTAssertTrue(cache[@(101)] == nil);
}

@end
