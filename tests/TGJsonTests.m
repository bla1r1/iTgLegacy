//
// TGJsonTests.m - Verification for yyjson parser & serializer.
//
#import "TGTestRunner.h"
#import "TGJson.h"
#include "TGJsonReader.hpp"

@interface TGJsonTests : XCTestCase
@end

@implementation TGJsonTests

- (void)testParsePrimitives {
	const char *json = "{\"str\":\"hello\",\"num\":12345,\"negative\":-42,\"real\":3.1415,\"truth\":true,\"lie\":false,\"empty\":null}";
	NSError *err = nil;
	NSDictionary *d = TGJsonParse(json, strlen(json), &err);

	XCTAssertNil(err);
	XCTAssertTrue([d isKindOfClass:NSDictionary.class]);
	XCTAssertEqualObjects(d[@"str"], @"hello");
	XCTAssertEqual([d[@"num"] longLongValue], 12345LL);
	XCTAssertEqual([d[@"negative"] longLongValue], -42LL);
	XCTAssertTrue(fabs([d[@"real"] doubleValue] - 3.1415) < 0.0001);
	XCTAssertEqualObjects(d[@"truth"], @YES);
	XCTAssertEqualObjects(d[@"lie"], @NO);
	XCTAssertEqualObjects(d[@"empty"], [NSNull null]);
}

- (void)testParseNestedStructure {
	const char *json = "{\"user\":{\"id\":999,\"names\":[\"Alice\",\"Bob\"],\"meta\":{\"online\":true}}}";
	NSDictionary *d = TGJsonParse(json, strlen(json), nil);

	XCTAssertNotNil(d[@"user"]);
	XCTAssertEqual([d[@"user"][@"id"] longLongValue], 999LL);
	NSArray *names = d[@"user"][@"names"];
	XCTAssertEqual((NSInteger)names.count, 2);
	XCTAssertEqualObjects(names[0], @"Alice");
	XCTAssertEqualObjects(names[1], @"Bob");
	XCTAssertEqualObjects(d[@"user"][@"meta"][@"online"], @YES);
}

- (void)testSerializeAndDeserializeParity {
	NSDictionary *orig = @{
		@"@type"   : @"sendMessage",
		@"chat_id" : @(123456789LL),
		@"options" : @{@"silent" : @NO, @"from_background" : @YES},
		@"tags"    : @[@"urgent", @"important"],
	};

	NSMutableData *data = TGJsonSerializeForSend(orig);
	XCTAssertNotNil(data);
	XCTAssertGreaterThan(data.length, (NSUInteger)10);

	// Check null-terminator
	const char *bytes = (const char *)data.bytes;
	XCTAssertEqual(bytes[data.length - 1], '\0', "must be null-terminated for td_send");

	// Parse back
	NSDictionary *parsed = TGJsonParse(bytes, data.length - 1, nil);
	XCTAssertEqualObjects(parsed[@"@type"], @"sendMessage");
	XCTAssertEqual([parsed[@"chat_id"] longLongValue], 123456789LL);
	XCTAssertEqualObjects(parsed[@"options"][@"from_background"], @YES);
	XCTAssertEqualObjects(parsed[@"options"][@"silent"], @NO);
	XCTAssertEqual((NSInteger)[parsed[@"tags"] count], 2);
	XCTAssertEqualObjects(parsed[@"tags"][0], @"urgent");
}

- (void)testMalformedJsonReturnsError {
	const char *bad = "{\"incomplete\":";
	NSError *err = nil;
	id result = TGJsonParse(bad, strlen(bad), &err);

	XCTAssertNil(result);
	XCTAssertNotNil(err);
	XCTAssertEqualObjects(err.domain, @"TGJsonErrorDomain");
}

- (void)testCppJsonReader_PrimitivesAndDefaults {
	const char *json = "{\"str\":\"hello\",\"num\":9876543210,\"small\":42,\"pi\":3.14159,\"flag\":true,\"f_flag\":false,\"nothing\":null}";
	TGJsonDoc doc(json);
	XCTAssertTrue(doc.is_valid());
	TGJsonVal root = doc.root();
	XCTAssertTrue(root.is_valid());

	XCTAssertEqual(root.get_int64("num"), 9876543210LL);
	XCTAssertEqual(root.get_int32("small"), 42);
	XCTAssertTrue(root.get_bool("flag"));
	XCTAssertFalse(root.get_bool("f_flag"));
	XCTAssertEqual(strcmp(root.get_str("str"), "hello"), 0);

	// Defaults on missing keys
	XCTAssertEqual(root.get_int64("missing", 99), 99LL);
	XCTAssertEqual(root.get_int32("missing", -1), -1);
	XCTAssertTrue(root.get_bool("missing", true));
	XCTAssertEqual(strcmp(root.get_str("missing", "def"), "def"), 0);
}

- (void)testCppJsonReader_NestedAndArrays {
	const char *json = "{\"items\":[10, 20, 30], \"user\":{\"id\":555, \"name\":\"John\"}}";
	TGJsonDoc doc(json);
	XCTAssertTrue(doc.is_valid());
	TGJsonVal root = doc.root();

	TGJsonVal items = root.get("items");
	XCTAssertTrue(items.is_arr());
	XCTAssertEqual((NSUInteger)items.arr_size(), (NSUInteger)3);
	XCTAssertEqual(items.arr_at(0).as_int32(), 10);
	XCTAssertEqual(items.arr_at(1).as_int32(), 20);
	XCTAssertEqual(items.arr_at(2).as_int32(), 30);

	TGJsonVal user = root.get("user");
	XCTAssertTrue(user.is_obj());
	XCTAssertEqual(user.get_int64("id"), 555LL);
	XCTAssertEqual(strcmp(user.get_str("name"), "John"), 0);
}

- (void)testCppJsonReader_InvalidJson {
	const char *bad = "{not_json";
	TGJsonDoc doc(bad);
	XCTAssertFalse(doc.is_valid());
	XCTAssertFalse(doc.root().is_valid());
}

@end
