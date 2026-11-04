// TGSoftVideoClockTests.m — the lag ladder that decides when the software
// decoder drops quality or a frame.
#import "TGTestRunner.h"
#import "TGSoftVideoClock.h"

@interface TGSoftVideoClockTests : XCTestCase @end

@implementation TGSoftVideoClockTests

- (void)testOnTheClockKeepsFullQuality {
	TGSoftVideoDecision d = TGSoftVideoDecide(1.0, 1.0, 1.0 / 30.0,
											  TGSoftVideoQualityFull);
	XCTAssertEqual(d.quality, TGSoftVideoQualityFull);
	XCTAssertTrue(d.display);
}

- (void)testTheLadderStepsInOrder {
	TGSoftVideoDecision d = TGSoftVideoDecide(1.070, 1.0, 1.0 / 30.0,
											  TGSoftVideoQualityFull);
	XCTAssertEqual(d.quality, TGSoftVideoQualitySkipLoopFilter);
	XCTAssertTrue(d.display);

	d = TGSoftVideoDecide(1.170, 1.0, 1.0 / 30.0, d.quality);
	XCTAssertEqual(d.quality, TGSoftVideoQualitySkipBidir);
	XCTAssertTrue(d.display);

	d = TGSoftVideoDecide(1.350, 1.0, 1.0 / 30.0, d.quality);
	XCTAssertEqual(d.quality, TGSoftVideoQualityDropFrames);
	XCTAssertFalse(d.display);
}

- (void)testAFrameIsShownAgainOnceTheDecoderHasCaughtUp {
	// Still behind enough to keep dropping, but now within one frame.
	TGSoftVideoDecision d = TGSoftVideoDecide(1.030, 1.0, 1.0 / 30.0,
											  TGSoftVideoQualityDropFrames);
	XCTAssertEqual(d.quality, TGSoftVideoQualityDropFrames);
	XCTAssertTrue(d.display);

	// Close enough to go back to full quality.
	d = TGSoftVideoDecide(1.010, 1.0, 1.0 / 30.0, TGSoftVideoQualityDropFrames);
	XCTAssertEqual(d.quality, TGSoftVideoQualityFull);
	XCTAssertTrue(d.display);
}

- (void)testASmallLagDoesNotFlapTheDecoder {
	TGSoftVideoDecision d = TGSoftVideoDecide(1.040, 1.0, 1.0 / 30.0,
											  TGSoftVideoQualitySkipLoopFilter);
	XCTAssertEqual(d.quality, TGSoftVideoQualitySkipLoopFilter);
	XCTAssertTrue(d.display);
}

@end
