// TGSVGPathTests - the SVG path parser behind every icon.
#import "TGSVGPath.h"
#import "TGIconPaths.h"

@interface TGSVGPathTests : XCTestCase @end

static CGRect TGBoundsOf(const char *d, CGFloat view, CGFloat side) {
	CGPathRef path = TGSVGPathCreate(d, view, view, CGRectMake(0, 0, side, side));
	if (!path)
		return CGRectNull;
	CGRect r = CGPathGetPathBoundingBox(path);
	CGPathRelease(path);
	return r;
}

static BOOL TGNear(CGFloat a, CGFloat b) {
	return fabs(a - b) < 0.05;
}

@implementation TGSVGPathTests

- (void)testAbsoluteLinesScaleIntoTheBox {
	CGRect r = TGBoundsOf("M2 2H22V22H2Z", 24, 48);
	XCTAssertTrue(TGNear(r.origin.x, 4) && TGNear(r.origin.y, 4), "%@", NSStringFromRect(r));
	XCTAssertTrue(TGNear(r.size.width, 40) && TGNear(r.size.height, 40), "%@", NSStringFromRect(r));
}

/// MDI and Font Awesome pack numbers with no separators: "1.5.5" is two
/// numbers, "-1-2" is two, and arc flags run into the next number.
- (void)testCompactNumbersAndPackedArcFlags {
	CGRect r = TGBoundsOf("M1.5.5l10-0h-0.5v10.5", 24, 24);
	XCTAssertTrue(TGNear(r.origin.x, 1.5) && TGNear(r.origin.y, 0.5), "%@", NSStringFromRect(r));
	XCTAssertTrue(TGNear(r.size.width, 10) && TGNear(r.size.height, 10.5), "%@", NSStringFromRect(r));

	// a full circle of radius 10 about (12,12) as two packed-flag arcs
	r = TGBoundsOf("M2 12a10 10 0 0120 0a10 10 0 01-20 0z", 24, 24);
	XCTAssertTrue(TGNear(r.origin.x, 2) && TGNear(r.origin.y, 2), "%@", NSStringFromRect(r));
	XCTAssertTrue(TGNear(r.size.width, 20) && TGNear(r.size.height, 20), "%@", NSStringFromRect(r));
}

/// A wide Font Awesome viewBox fits by its long side and is centred.
- (void)testNonSquareViewBoxIsCentredNotStretched {
	CGPathRef path = TGSVGPathCreate("M0 0H448V512H0Z", 448, 512, CGRectMake(0, 0, 32, 32));
	CGRect r = CGPathGetPathBoundingBox(path);
	CGPathRelease(path);
	XCTAssertTrue(TGNear(r.size.height, 32) && TGNear(r.size.width, 28), "%@", NSStringFromRect(r));
	XCTAssertTrue(TGNear(r.origin.x, 2) && TGNear(r.origin.y, 0), "%@", NSStringFromRect(r));
}

- (void)testSmoothCurvesReflectTheLastControlPoint {
	// s after c mirrors the control point; the curve must stay inside 0..20
	CGRect r = TGBoundsOf("M0 10C0 0 10 0 10 10S20 20 20 10", 20, 20);
	XCTAssertTrue(r.origin.y > 2 && r.origin.y + r.size.height < 18, "%@", NSStringFromRect(r));
	XCTAssertTrue(TGNear(r.size.width, 20), "%@", NSStringFromRect(r));
}

- (void)testGarbageGivesNull {
	XCTAssertTrue(TGSVGPathCreate("", 24, 24, CGRectMake(0, 0, 24, 24)) == NULL);
	XCTAssertTrue(TGSVGPathCreate("hello", 24, 24, CGRectMake(0, 0, 24, 24)) == NULL);
	XCTAssertTrue(TGSVGPathCreate(NULL, 24, 24, CGRectMake(0, 0, 24, 24)) == NULL);
}

/// Every icon shipped must come out of the parser as a shape that fills a
/// fair part of its box - a path cut short draws a sliver or nothing.
- (void)testEveryShippedIconParses {
	XCTAssertTrue(TGIconPathCount() > 40);
	for (size_t i = 0; i < TGIconPathCount(); i++) {
		const TGIconPath *icon = TGIconPathAt(i);
		CGPathRef path = TGSVGPathCreate(icon->d, icon->viewW, icon->viewH, CGRectMake(0, 0, 24, 24));
		XCTAssertTrue(path != NULL, "%s", icon->name);
		if (!path)
			continue;
		CGRect r = CGPathGetPathBoundingBox(path);
		XCTAssertTrue(MAX(r.size.width, r.size.height) > 12, "%s %@", icon->name, NSStringFromRect(r));
		CGPathRelease(path);
	}
	XCTAssertTrue(TGIconPathNamed("reply") != NULL);
	XCTAssertTrue(TGIconPathNamed("contacts") != NULL);
	XCTAssertTrue(TGIconPathNamed("nonexistent") == NULL);
	// Asked for by name with no hand-drawn fallback: the story camera and the
	// round video recorder (flash), the profile's music strip (music). A
	// regeneration from icon_picks.txt once dropped both and left the buttons
	// empty.
	XCTAssertTrue(TGIconPathNamed("flash") != NULL);
	XCTAssertTrue(TGIconPathNamed("music") != NULL);
}

@end
