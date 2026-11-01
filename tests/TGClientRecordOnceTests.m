// TGClientRecordOnceTests.m — the record round trip: one button switches
// between voice note and round video note, the note a "1" marks goes out as
// a self destruct that fires the moment it is opened (what Telegram writes
// into voiceOnce as ttl 0x7fffffff), and a flatten of an incoming one-time
// note carries the marks the chat needs.
//
// Requests sit in the outbox where their shape can be asserted.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientRecordOnceTests : XCTestCase @end

static TGClient *RO(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	c.td_exec = NULL;
	return c;
}

static NSDictionary *decodeRO(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastRO(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeRO(d)[@"@type"] isEqualToString:type])
			found = decodeRO(d);
	return found;
}

@implementation TGClientRecordOnceTests

static NSString *ORDocPath(void) {
	static NSString *path;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"once-test.oga"];
		[@"/" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	});
	return path;
}

#pragma mark - voice note once

/// "1" on the voice note is Telegram's one-time mode: the request carries a
/// self destruct that fires on open. Not a ten second timer.
- (void)testSendVoiceOnce_GetMessageSelfDestructTypeImmediately {
	TGClient *c = RO();
	[c sendVoiceAtPath:ORDocPath() duration:7 toChat:42 thread:0 viewOnce:YES];

	NSDictionary *content = lastRO(c, @"sendMessage")
			[@"input_message_content"];
	XCTAssertEqualObjects(content[@"@type"], @"inputMessageVoiceNote");
	XCTAssertEqualObjects(content[@"self_destruct_type"][@"@type"],
			@"messageSelfDestructTypeImmediately");
}

/// A plain note carries no self destruct at all - TDLib's "absent" is a null.
- (void)testSendVoicePlain_CarriesNoSelfDestruct {
	TGClient *c = RO();
	[c sendVoiceAtPath:ORDocPath() duration:7 toChat:42 thread:0 viewOnce:NO];

	NSDictionary *content = lastRO(c, @"sendMessage")
			[@"input_message_content"];
	XCTAssertTrue(content[@"self_destruct_type"] == [NSNull null]
			|| content[@"self_destruct_type"] == nil);
}

#pragma mark - round video note once

- (void)testSendVideoNoteOnce_GetMessageSelfDestructTypeImmediately {
	TGClient *c = RO();
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			@"once-test.mov"];
	[@"/" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[c sendVideoNoteAtPath:path duration:13 toChat:42 thread:0 viewOnce:YES];

	NSDictionary *content = lastRO(c, @"sendMessage")
			[@"input_message_content"];
	XCTAssertEqualObjects(content[@"@type"], @"inputMessageVideoNote");
	XCTAssertEqualObjects(content[@"self_destruct_type"][@"@type"],
			@"messageSelfDestructTypeImmediately");
}

#pragma mark - flatten

/// A one-time voice received from the other side keeps the flag on it, so the
/// bubble can put the "1" on the clock like their chat does.
- (void)testFlatten_VoiceOnceMessage_MarksViewOnce {
	NSDictionary *m = @{@"@type" : @"message", @"id" : @(11),
			@"chat_id" : @(42), @"sender_id" : @{@"user_id" : @(2)},
			@"date" : @100,
			@"self_destruct_type" : @{@"@type" : @"messageSelfDestructTypeImmediately"},
			@"content" : @{@"@type" : @"messageVoiceNote",
					@"voice_note" : @{@"duration" : @5, @"waveform" : @""}}};

	NSDictionary *flat = TGFlattenMessage(m);
	XCTAssertEqual([flat[@"viewOnce"] boolValue], YES);
	XCTAssertEqual([flat[@"destructSeconds"] integerValue], 0);
}

/// The timer kind is the other shape the flag can take, and the flatten says
/// how long it has.
- (void)testFlatten_VoiceTimerMessage_MarksSeconds {
	NSDictionary *m = @{@"@type" : @"message", @"id" : @(12),
			@"chat_id" : @(42), @"sender_id" : @{@"user_id" : @(2)},
			@"date" : @100,
			@"self_destruct_type" : @{@"@type" : @"messageSelfDestructTypeTimer",
					@"self_destruct_time" : @12},
			@"content" : @{@"@type" : @"messageVideoNote",
					@"duration" : @5}};

	NSDictionary *flat = TGFlattenMessage(m);
	XCTAssertEqual([flat[@"viewOnce"] boolValue], NO);
	XCTAssertEqual([flat[@"destructSeconds"] integerValue], 12);
}

/// An ordinary note has neither mark; the flatten does not invent one.
- (void)testFlatten_PlainVoiceMessage_HasNoOneTimeMark {
	NSDictionary *m = @{@"@type" : @"message", @"id" : @(13),
			@"chat_id" : @(42), @"sender_id" : @{@"user_id" : @(2)},
			@"date" : @100,
			@"content" : @{@"@type" : @"messageVoiceNote",
					@"duration" : @5, @"waveform" : @""}};

	NSDictionary *flat = TGFlattenMessage(m);
	XCTAssertEqual([flat[@"viewOnce"] boolValue], NO);
	XCTAssertEqual([flat[@"destructSeconds"] integerValue], 0);
}
@end
