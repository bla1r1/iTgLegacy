//
// TGChatListRowGeometryTests.m - the trailing edge of a chat row.
//
// A pinned chat with unread messages used to lose one of its two marks: the
// cell put the count where the pin went and hid the pin when a count existed.
// The official row keeps both, so this pins the arithmetic before TGChatCell
// draws it. UIKit cannot answer the cell's own frames on this host; the pure
// helper can.
//
#import "TGTestRunner.h"
#import "TGChatListRowGeometry.h"
#include <math.h>

@interface TGChatListRowGeometryTests : XCTestCase
@end

@implementation TGChatListRowGeometryTests

static const CGFloat kRight = 320.0f;
static const CGFloat kTop = 42.0f;
static const CGFloat kBadgeW = 30.0f;
static const CGFloat kBadgeH = 18.0f;
static const CGFloat kPin = 16.0f;
static const CGFloat kGap = 8.0f;

- (void)testPinnedUnreadRowKeepsBothMarksAndTheyDoNotOverlap {
	CGRect badge = CGRectZero, pin = CGRectZero;
	CGFloat previewRight = 0;
	TGChatListRowAccessories(kRight, kTop, YES, kBadgeW, kBadgeH,
			YES, kPin, kGap, &badge, &pin, &previewRight);

	XCTAssertTrue(fabs(CGRectGetMaxX(badge) - kRight) < 0.01,
			@"the unread count keeps the corner");
	XCTAssertTrue(fabs(CGRectGetMidY(pin) - CGRectGetMidY(badge)) < 0.01,
			@"the pin sits on the same line as the count");
	XCTAssertLessThanOrEqual(CGRectGetMaxX(pin), CGRectGetMinX(badge),
			@"the pin must be beside the count, not under it");
	XCTAssertLessThanOrEqual(previewRight, CGRectGetMinX(pin),
			@"the preview must stop before the first mark");
}

- (void)testPinnedRowWithoutUnreadPutsThePinAtTheEdge {
	CGRect badge = CGRectZero, pin = CGRectZero;
	CGFloat previewRight = 0;
	TGChatListRowAccessories(kRight, kTop, NO, 0, kBadgeH,
			YES, kPin, kGap, &badge, &pin, &previewRight);

	XCTAssertTrue(CGRectIsEmpty(badge), @"no count, no badge");
	XCTAssertTrue(fabs(CGRectGetMaxX(pin) - kRight) < 0.01);
	XCTAssertLessThanOrEqual(previewRight, CGRectGetMinX(pin));
}

- (void)testUnreadRowWithoutPinPutsTheBadgeAtTheEdge {
	CGRect badge = CGRectZero, pin = CGRectZero;
	CGFloat previewRight = 0;
	TGChatListRowAccessories(kRight, kTop, YES, kBadgeW, kBadgeH,
			NO, kPin, kGap, &badge, &pin, &previewRight);

	XCTAssertTrue(fabs(CGRectGetMaxX(badge) - kRight) < 0.01);
	XCTAssertTrue(CGRectIsEmpty(pin), @"no pin, no pin frame");
	XCTAssertTrue(fabs(previewRight - (CGRectGetMinX(badge) - kGap)) < 0.01);
}

- (void)testPlainRowUsesTheWholeLine {
	CGRect badge = CGRectZero, pin = CGRectZero;
	CGFloat previewRight = 0;
	TGChatListRowAccessories(kRight, kTop, NO, 0, kBadgeH,
			NO, kPin, kGap, &badge, &pin, &previewRight);

	XCTAssertTrue(CGRectIsEmpty(badge));
	XCTAssertTrue(CGRectIsEmpty(pin));
	XCTAssertTrue(fabs(previewRight - kRight) < 0.01,
			@"an unpinned, read row must not reserve room for either mark");
}

- (void)testZeroFlagsTolerateNilOutPointers {
	XCTAssertNoThrow(TGChatListRowAccessories(kRight, kTop, NO, 0, kBadgeH,
			NO, kPin, kGap, NULL, NULL, NULL),
			@"callers that only want the preview edge must not need three locals");
}

- (void)testArchiveSubtitleIsSingularForOneChat {
	XCTAssertEqualObjects(TGChatListArchiveSubtitle(1), @"1 chat");
	XCTAssertEqualObjects(TGChatListArchiveSubtitle(2), @"2 chats");
	XCTAssertEqualObjects(TGChatListArchiveSubtitle(0), @"0 chats");
}

@end
