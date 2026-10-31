//
// TGUpdateFilterTests.m - the receive loop must not build a Foundation tree
// for an update nothing reads.
//
// Before the filter existed every object off td_json_client_receive became a
// full NSDictionary / NSNumber / NSString tree, including the update types
// the client has no branch for at all. updateActiveEmojiReactions is the
// worst of them: one array, two thousand NSStrings, read by nobody. The
// first test keeps both halves of that in view - what the unfiltered parse
// still costs, and that the filtered one costs nothing.
//
#import <Foundation/Foundation.h>
#import "TGTestRunner.h"
#import "TGJson.h"
#import "TGUpdateType.h"

@interface TGUpdateFilterTests : XCTestCase
@end

@implementation TGUpdateFilterTests

static NSString *TGBigEmojiUpdate(NSUInteger count) {
	NSMutableString *json = [NSMutableString stringWithString:
			@"{\"@type\":\"updateActiveEmojiReactions\",\"emojis\":["];
	for (NSUInteger i = 0; i < count; i++)
		[json appendFormat:@"%@\"e%lu\"", i ? @"," : @"", (unsigned long)i];
	[json appendString:@"]}"];
	return json;
}

- (void)testUnhandledUpdateIsDroppedBeforeTheTreeIsBuilt {
	const char *utf8 = TGBigEmojiUpdate(2000).UTF8String;
	size_t len = strlen(utf8);

	// What the loop used to do, and what it cost.
	NSDictionary *unfiltered = TGJsonParse(utf8, len, NULL);
	XCTAssertEqual([unfiltered[@"emojis"] count], (NSUInteger)2000);

	XCTAssertNil(TGJsonParseUpdate(utf8, len, NULL));
}

- (void)testHandledUpdateSurvivesTheFilter {
	const char *utf8 = "{\"@type\":\"updateFile\",\"file\":{\"id\":7}}";
	NSDictionary *parsed = TGJsonParseUpdate(utf8, strlen(utf8), NULL);
	XCTAssertEqualObjects(parsed[@"@type"], @"updateFile");
	XCTAssertEqualObjects(parsed[@"file"][@"id"], @(7));
}

- (void)testAnswerWithExtraIsNeverDropped {
	// Owed to a waiting completion block, whatever its type.
	const char *utf8 = "{\"@type\":\"updateFooBar\",\"@extra\":\"r12\"}";
	NSDictionary *parsed = TGJsonParseUpdate(utf8, strlen(utf8), NULL);
	XCTAssertEqualObjects(parsed[@"@extra"], @"r12");
}

- (void)testNonUpdateAnswerIsNeverDropped {
	// getAuthorizationState and getMe answer without @extra; only update*
	// types are candidates for the bin.
	const char *utf8 = "{\"@type\":\"authorizationStateWaitPhoneNumber\"}";
	XCTAssertNotNil(TGJsonParseUpdate(utf8, strlen(utf8), NULL));

	const char *me = "{\"@type\":\"user\",\"phone_number\":\"123\"}";
	XCTAssertNotNil(TGJsonParseUpdate(me, strlen(me), NULL));
}

- (void)testMalformedInputIsDistinguishableFromADrop {
	NSError *err = nil;
	XCTAssertNil(TGJsonParseUpdate("{\"@type\":", 9, &err));
	XCTAssertNotNil(err);

	err = nil;
	const char *dropped = "{\"@type\":\"updateDiceEmojis\"}";
	XCTAssertNil(TGJsonParseUpdate(dropped, strlen(dropped), &err));
	XCTAssertNil(err);
}

- (void)testEveryDispatchedTypeIsInTheTable {
	// handleUpdate dispatches on this enum, so a case label that the lookup
	// cannot produce would be a branch the filter silently starves.
#define TG_CHECK_ROW(sym, name) \
	XCTAssertEqual(TGUpdateTypeFor(name, strlen(name)), sym, @"%s", name); \
	XCTAssertTrue(TGUpdateTypeIsUpdateName(name, strlen(name)) != 0, @"%s", name);
	TG_HANDLED_UPDATES(TG_CHECK_ROW)
#undef TG_CHECK_ROW

	XCTAssertEqual(TGUpdateTypeFor("updateDiceEmojis", 16), TGUpdateUnknown);
	XCTAssertEqual(TGUpdateTypeFor("updateFil", 9), TGUpdateUnknown);
	XCTAssertEqual(TGUpdateTypeFor(NULL, 0), TGUpdateUnknown);
	XCTAssertEqual(TGUpdateTypeIsUpdateName("user", 4), 0);
}

@end
