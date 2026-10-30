//
// TGP1MigrationTests.mm - the Phase 3/4/5 (P1) migrations.
//
// One suite per piece of C or C++ that replaced an allocating Objective-C
// path: the chat-list date formatter, the outbox JSON writer, the flattened
// message POD, the sticker pack buffer, the bounded object cache, the VoIP
// packet slices, and the stream store's flat index.
//
#import "TGTestRunner.h"
#import "TGFastDate.h"
#import "TGJsonWriter.hpp"
#import "TGFlattenedMessage.hpp"
#import "TGStickerPack.h"
#import "TGImageLruCache.h"
#import "TGMessageStreamStore.h"
#import "TGJson.h"
#include <string>

@interface TGP1MigrationTests : XCTestCase
@end

@implementation TGP1MigrationTests

#pragma mark - TGFastChatDate

/// Midnight-safe: builds a timestamp a whole number of days back, four hours
/// into that day, so a run near midnight still grades the same bucket.
static time_t daysBack(time_t now, int days) {
	return now - (time_t)days * 86400 - 4 * 3600;
}

- (void)testFastChatDate_WithinTheDayIsAClock {
	time_t now = time(NULL);
	char buf[TGFastDateBufferSize];
	size_t len = TGFastChatDate(now - 3600, now, buf, sizeof(buf));
	XCTAssertEqual((int)len, 5, @"HH:MM is five characters");
	XCTAssertTrue(buf[2] == ':', @"the clock separator belongs in the middle");

	// It must agree with the system's own idea of the hour and minute.
	time_t when = now - 3600;
	struct tm parts;
	localtime_r(&when, &parts);
	char expected[8];
	snprintf(expected, sizeof(expected), "%02d:%02d", parts.tm_hour, parts.tm_min);
	XCTAssertTrue(strcmp(buf, expected) == 0,
		@"formatted %s, expected %s", buf, expected);
}

- (void)testFastChatDate_WithinTheWeekIsAWeekday {
	time_t now = time(NULL);
	time_t when = daysBack(now, 3);
	char buf[TGFastDateBufferSize];
	size_t len = TGFastChatDate(when, now, buf, sizeof(buf));
	XCTAssertEqual((int)len, 3, @"a weekday abbreviation is three characters");

	struct tm parts;
	localtime_r(&when, &parts);
	static const char *const names[7] = {
		"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
	};
	XCTAssertTrue(strcmp(buf, names[parts.tm_wday]) == 0,
		@"formatted %s for weekday %d", buf, parts.tm_wday);
}

- (void)testFastChatDate_BeyondTheWeekIsADate {
	time_t now = time(NULL);
	time_t when = daysBack(now, 30);
	char buf[TGFastDateBufferSize];
	size_t len = TGFastChatDate(when, now, buf, sizeof(buf));
	XCTAssertEqual((int)len, 8, @"dd.MM.yy is eight characters");

	struct tm parts;
	localtime_r(&when, &parts);
	char expected[16];
	snprintf(expected, sizeof(expected), "%02d.%02d.%02d", parts.tm_mday,
			parts.tm_mon + 1, parts.tm_year % 100);
	XCTAssertTrue(strcmp(buf, expected) == 0,
		@"formatted %s, expected %s", buf, expected);
}

- (void)testFastChatDate_NoTimestampIsEmptyAndFuturesReadAsNow {
	time_t now = time(NULL);
	char buf[TGFastDateBufferSize];
	XCTAssertEqual((int)TGFastChatDate(0, now, buf, sizeof(buf)), 0);
	XCTAssertTrue(buf[0] == '\0', @"nothing is written for no timestamp");
	XCTAssertEqual((int)TGFastChatDate(-5, now, buf, sizeof(buf)), 0);

	// A clock ahead of ours must not fall through to the date branch.
	XCTAssertEqual((int)TGFastChatDate(now + 600, now, buf, sizeof(buf)), 5);
}

#pragma mark - TGJsonWriter

- (void)testJsonWriter_ObjectArrayAndScalars {
	TGJsonWriter w;
	w.begin_object()
		.field("@type", "downloadFile")
		.field("file_id", (int64_t)4211)
		.field("synchronous", false)
		.key("limits").begin_array().num(0).num(1).end_array()
		.key("nested").begin_object().field("depth", (int64_t)2).end_object()
		.key("nothing").null_value()
	 .end_object();

	NSString *json = [NSString stringWithUTF8String:w.c_str()];
	XCTAssertEqualObjects(json,
		@"{\"@type\":\"downloadFile\",\"file_id\":4211,\"synchronous\":false,"
		 "\"limits\":[0,1],\"nested\":{\"depth\":2},\"nothing\":null}");
	XCTAssertEqual((int)w.size(), (int)json.length);
}

- (void)testJsonWriter_EscapesWhatJsonForbidsAndPassesUtf8Through {
	TGJsonWriter w;
	w.begin_object().field("t", "a\"b\\c\nd\te\x01 \xD0\xBF").end_object();
	NSString *json = [NSString stringWithUTF8String:w.c_str()];
	XCTAssertEqualObjects(json,
		@"{\"t\":\"a\\\"b\\\\c\\nd\\te\\u0001 п\"}");

	// And it has to come back as what went in.
	NSDictionary *round = TGJsonParse(w.c_str(), w.size(), NULL);
	XCTAssertEqualObjects(round[@"t"], @"a\"b\\c\nd\te\x01 п");
}

/// The outbox path itself: TGJsonSerializeForSend now writes through
/// TGJsonWriter, and td_json_client_send takes a C string, so the trailing
/// NUL must be part of the bytes.
- (void)testSerializeForSend_IsNullTerminatedAndRoundTrips {
	NSDictionary *request = @{
		@"@type"   : @"sendMessage",
		@"chat_id" : @(-1001234567890LL),
		@"muted"   : @NO,
		@"ratio"   : @(0.5),
		@"ids"     : @[@1, @2, @3],
	};
	NSMutableData *out = TGJsonSerializeForSend(request);
	XCTAssertNotNil(out);
	const char *bytes = (const char *)out.bytes;
	XCTAssertEqual((int)bytes[out.length - 1], 0,
		@"the last byte must be the terminator td_send expects");

	NSDictionary *back = TGJsonParse(bytes, out.length - 1, NULL);
	XCTAssertEqualObjects(back[@"@type"], @"sendMessage");
	XCTAssertEqual([back[@"chat_id"] longLongValue], -1001234567890LL);
	XCTAssertEqualObjects(back[@"muted"], @NO);
	XCTAssertEqualObjects(back[@"ids"], (@[@1, @2, @3]));
	XCTAssertEqual([back[@"ratio"] doubleValue], 0.5);
}

#pragma mark - TGFlattenedMessage

- (void)testFlattenedMessage_StaysInsideItsByteBudget {
	XCTAssertLessThanOrEqual((int)sizeof(TGFlattenedMessage), 128,
		@"the POD is the whole point; %d bytes", (int)sizeof(TGFlattenedMessage));
}

- (void)testFlattenedMessage_ParsesScalarsStraightFromTdlibJson {
	const char *json =
		"{\"@type\":\"message\",\"id\":1048576,\"chat_id\":-100777,"
		 "\"date\":1700000000,\"edit_date\":1700000600,\"is_outgoing\":true,"
		 "\"sender_id\":{\"@type\":\"messageSenderUser\",\"user_id\":4242},"
		 "\"reply_to_message_id\":1048575,\"media_album_id\":\"99\","
		 "\"content\":{\"@type\":\"messagePhoto\",\"caption\":{\"text\":\"hi\"},"
		   "\"photo\":{\"sizes\":["
		     "{\"photo\":{\"id\":11},\"width\":90,\"height\":60},"
		     "{\"photo\":{\"id\":12},\"width\":1280,\"height\":720}]}}}";

	TGFlattenedMessage m;
	XCTAssertTrue(TGFlattenedMessageParseJson(json, strlen(json), m));
	XCTAssertEqual(m.messageId, (int64_t)1048576);
	XCTAssertEqual(m.chatId, (int64_t)-100777);
	XCTAssertEqual(m.date, (int32_t)1700000000);
	XCTAssertEqual(m.senderId, (int64_t)4242);
	XCTAssertEqual(m.replyToMessageId, (int64_t)1048575);
	XCTAssertEqual(m.albumId, (int64_t)99);
	XCTAssertEqual((int)m.kind, (int)TGMessageKindPhoto);
	XCTAssertTrue(m.has(TGMessageFlagOutgoing));
	XCTAssertTrue(m.has(TGMessageFlagEdited));
	XCTAssertTrue(m.has(TGMessageFlagHasCaption));
	XCTAssertFalse(m.has(TGMessageFlagService));
	// The last size is the full frame; the first is the thumbnail.
	XCTAssertEqual(m.photoFileId, (int32_t)12);
	XCTAssertEqual((int)m.mediaWidth, 1280);
	XCTAssertEqual((int)m.mediaHeight, 720);
	XCTAssertEqual(m.thumbFileId, (int32_t)11);
}

- (void)testFlattenedMessage_VoiceNoteCarriesUnplayedAndDuration {
	const char *json =
		"{\"id\":7,\"content\":{\"@type\":\"messageVoiceNote\",\"is_listened\":false,"
		 "\"voice_note\":{\"duration\":14,\"voice\":{\"id\":501}}}}";
	TGFlattenedMessage m;
	XCTAssertTrue(TGFlattenedMessageParseJson(json, strlen(json), m));
	XCTAssertEqual((int)m.kind, (int)TGMessageKindVoiceNote);
	XCTAssertEqual(m.duration, (int32_t)14);
	XCTAssertEqual(m.docFileId, (int32_t)501);
	XCTAssertTrue(m.has(TGMessageFlagUnplayed));
}

- (void)testFlattenedMessage_UnknownContentIsAServiceNoticeAndGarbageIsRefused {
	const char *json =
		"{\"id\":8,\"content\":{\"@type\":\"messageChatJoinByLink\"}}";
	TGFlattenedMessage m;
	XCTAssertTrue(TGFlattenedMessageParseJson(json, strlen(json), m));
	XCTAssertEqual((int)m.kind, (int)TGMessageKindService);
	XCTAssertTrue(m.has(TGMessageFlagService));

	XCTAssertFalse(TGFlattenedMessageParseJson("not json", 8, m));
	XCTAssertEqual(m.messageId, (int64_t)0, @"a refused parse leaves it zeroed");
}

#pragma mark - TGStickerPack

static NSDictionary *tdSticker(int fileId, int thumbId, NSString *emoji, BOOL webp) {
	return @{
		@"sticker" : @{@"id" : @(fileId)},
		@"format"  : @{@"@type" : webp ? @"stickerFormatWebp" : @"stickerFormatTgs"},
		@"emoji"   : emoji,
		@"width"   : @(512),
		@"height"  : @(400),
		@"thumbnail" : @{@"format" : @{@"@type" : @"thumbnailFormatWebp"},
						 @"file"   : @{@"id" : @(thumbId)}},
	};
}

- (void)testStickerPack_IsAnNSArrayOverAFlatBuffer {
	NSArray *raw = @[ tdSticker(10, 20, @"\U0001F600", YES),
					  tdSticker(11, 21, @"\U0001F601", NO),
					  @{ @"format" : @{@"@type" : @"stickerFormatWebp"} } ];
	TGStickerPack *pack = [TGStickerPack packWithTDLibStickers:raw];

	XCTAssertTrue([pack isKindOfClass:NSArray.class],
		@"every caller treats a sticker list as an NSArray");
	XCTAssertEqual((int)pack.count, 2, @"a sticker with no file is dropped");

	NSDictionary *first = pack[0];
	XCTAssertEqualObjects(first[@"fileId"], @(10));
	XCTAssertEqualObjects(first[@"thumbId"], @(20));
	XCTAssertEqualObjects(first[@"emoji"], @"\U0001F600");
	XCTAssertEqualObjects(first[@"isAnimated"], @NO);
	XCTAssertEqualObjects(first[@"width"], @(512));
	XCTAssertEqualObjects(first[@"height"], @(400));
	XCTAssertEqualObjects(pack[1][@"isAnimated"], @YES, @"a .tgs is animated");

	// Enumeration and firstObject go through objectAtIndex:, so they work too.
	int seen = 0;
	for (NSDictionary *item in pack){
		XCTAssertNotNil(item[@"fileId"]);
		seen++;
	}
	XCTAssertEqual(seen, 2);
	XCTAssertEqualObjects([pack.firstObject objectForKey:@"fileId"], @(10));
}

- (void)testStickerPack_FiftyStickersFitInTheFlatBudget {
	NSMutableArray *raw = [NSMutableArray array];
	for (int i = 0; i < 50; i++)
		[raw addObject:tdSticker(100 + i, 200 + i, @"\U0001F60A", YES)];
	TGStickerPack *pack = [TGStickerPack packWithTDLibStickers:raw];
	XCTAssertEqual((int)pack.count, 50);
	XCTAssertLessThanOrEqual((int)pack.byteSize, 2560,
		@"a 50-sticker pack must stay around 2.4 KB, got %d bytes",
		(int)pack.byteSize);
}

#pragma mark - TGObjectLruCache

- (void)testObjectLruCache_EvictsTheLeastRecentlyUsedAndNothingElse {
	TGObjectLruCache *cache = [[TGObjectLruCache alloc] initWithCapacity:3];
	XCTAssertEqual((int)cache.capacity, 3);

	cache[@(1)] = @{@"name" : @"one"};
	cache[@(2)] = @{@"name" : @"two"};
	cache[@(3)] = @{@"name" : @"three"};
	XCTAssertEqual((int)cache.count, 3);

	// Touching 1 makes 2 the oldest, so 2 is what the fourth entry displaces.
	XCTAssertNotNil(cache[@(1)]);
	cache[@(4)] = @{@"name" : @"four"};
	XCTAssertEqual((int)cache.count, 3, @"the bound is a bound");
	XCTAssertNil(cache[@(2)]);
	XCTAssertNotNil(cache[@(1)]);
	XCTAssertNotNil(cache[@(3)]);
	XCTAssertEqualObjects(cache[@(4)][@"name"], @"four");

	cache[@(4)] = nil;
	XCTAssertNil(cache[@(4)], @"assigning nil removes the entry");
	[cache removeAllObjects];
	XCTAssertEqual((int)cache.count, 0);
}

#pragma mark - TGMessageStreamStore flat index

static NSDictionary *streamMessage(int64_t msgId, int32_t date, BOOL outgoing) {
	return @{ @"id" : @(msgId), @"date" : @(date), @"outgoing" : @(outgoing),
			  @"kind" : @"messageText", @"text" : @"hello" };
}

- (void)testStreamStoreIndex_AnswersBoundsAndPositionsFromTheFlatBuffer {
	TGMessageStreamStore *store = [[TGMessageStreamStore alloc] init];
	[store resetWithMessages:@[ streamMessage(100, 1000, NO),
								streamMessage(200, 2000, YES),
								streamMessage(300, 3000, NO) ]];

	XCTAssertEqual(store.oldestMessageId, (int64_t)100);
	XCTAssertEqual(store.newestMessageId, (int64_t)300);
	XCTAssertEqual([store messageIdAtIndex:1], (int64_t)200);
	XCTAssertEqual([store dateAtIndex:1], (int32_t)2000);
	XCTAssertTrue([store isOutgoingAtIndex:1]);
	XCTAssertFalse([store isOutgoingAtIndex:0]);
	XCTAssertEqual((int)[store indexOfMessageId:300], 2);
	XCTAssertEqual((int)[store indexOfMessageId:999], (int)NSNotFound);

	// Past the end answers zero rather than reading off the buffer.
	XCTAssertEqual([store messageIdAtIndex:99], (int64_t)0);
	XCTAssertEqual([store dateAtIndex:99], (int32_t)0);
	XCTAssertFalse([store isOutgoingAtIndex:99]);
}

- (void)testStreamStoreIndex_StaysInStepWithTheMessagesThroughEveryMutation {
	TGMessageStreamStore *store = [[TGMessageStreamStore alloc] init];
	[store resetWithMessages:@[ streamMessage(200, 2000, NO) ]];
	[store prependOlderMessages:@[ streamMessage(100, 1000, NO) ]];
	[store appendNewerMessages:@[ streamMessage(300, 3000, NO) ]];

	XCTAssertEqual((int)store.count, 3);
	XCTAssertEqual([store messageIdAtIndex:0], (int64_t)100);
	XCTAssertEqual([store messageIdAtIndex:2], (int64_t)300);
	XCTAssertEqual((int)store.indexByteSize, 3 * (int)sizeof(TGFlattenedMessage));

	XCTAssertTrue([store removeMessageId:200]);
	XCTAssertEqual((int)store.count, 2);
	XCTAssertEqual([store messageIdAtIndex:1], (int64_t)300,
		@"removing a message must close the gap in the index too");
	XCTAssertEqualObjects(store.messages[1][@"id"], @(300));
	XCTAssertEqual((int)store.indexByteSize, 2 * (int)sizeof(TGFlattenedMessage));

	[store clear];
	XCTAssertEqual((int)store.indexByteSize, 0);
	XCTAssertEqual(store.oldestMessageId, (int64_t)0);
}

@end
