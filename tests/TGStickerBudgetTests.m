//
// TGStickerBudgetTests.m — the budget is the twofold contract: a full-length
// loop fits inside the cache's totalCostLimit, and more RAM buys more loop.
// Before the fix there was no ceiling at all: one three-second .tgs loop
// rasterised at 256x256 on a 2x display held 15 MB - the whole 32-bit
// internal cache budget - which shoved the iPod touch 4 into jetsam territory
// as chats were opened and closed.
//
#import "TGTestRunner.h"
#import "TGStickerBudget.h"

@interface TGStickerBudgetTests : XCTestCase
@end
@implementation TGStickerBudgetTests

/// The invariant the constants must hold on every tier: one budget-capped
/// loop of frames at the biggest raster the tier allows costs no more than
/// the tier's cache ceiling. It failed before, when the loop ran to 60
/// frames of 256x256 with no ceiling at all.
- (void)testFullLoopFitsTheCacheCeilingOnEveryTier {
	size_t const kTiers[] = { 256, 512, 2048 };
	for (size_t i = 0; i < sizeof(kTiers) / sizeof(kTiers[0]); i++) {
		TGStickerBudget b = TGStickerBudgetForMemory(kTiers[i]);
		size_t cost = TGStickerFrameBytes((size_t)b.pixelSideCap,
										  (size_t)b.pixelSideCap,
										  b.frameCap);
		XCTAssertLessThanOrEqual(cost, b.cacheTotalBytes,
			@"tier %zu: a full loop (%zu bytes) must fit the %zu-byte ceiling",
			kTiers[i], cost, b.cacheTotalBytes);
	}
}

/// The frames cap actually bites: the vintage budget must be shorter than a
/// three-second loop rasterised at 18 fps would otherwise produce (54).
- (void)testVintageTierCapsAThreeSecondLoop {
	TGStickerBudget b = TGStickerBudgetForMemory(256);
	XCTAssertLessThanOrEqual(b.frameCap, 40);
}

/// More memory is allowed a longer loop, never a shorter one.
- (void)testBudgetGrowsWithMemory {
	TGStickerBudget small = TGStickerBudgetForMemory(256);
	TGStickerBudget big = TGStickerBudgetForMemory(2048);
	XCTAssertLessThanOrEqual(small.frameCap, big.frameCap);
	XCTAssertLessThanOrEqual(small.cacheTotalBytes, big.cacheTotalBytes);
	XCTAssertLessThanOrEqual(small.pixelSideCap, big.pixelSideCap);
}

/// Bytes are the RGBA bitmap the rasteriser actually allocates.
- (void)testFrameBytesAreRGBAWidthTimesHeight {
	XCTAssertEqual(TGStickerFrameBytes(256, 256, 1), 256u * 256u * 4u);
	XCTAssertEqual(TGStickerFrameBytes(100, 50, 2), 100u * 50u * 4u * 2u);
	XCTAssertEqual(TGStickerFrameBytes(8, 8, 0), 0u);
}

@end
