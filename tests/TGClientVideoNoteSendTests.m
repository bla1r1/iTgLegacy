// TGClientVideoNoteSendTests.m — how a round video note's send ends. The
// pending message is created by sendMessage and only updateMessageSendSucceeded
// says it is really in the chat; an error result is the other ending. Both have
// to reach the recorder overlay, and a second copy of the update must not.
//
// Requests sit in the outbox where their answer can be fed back by hand.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientVideoNoteSendTests : XCTestCase @end

static TGClient *VS(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.noteSendWaiters removeAllObjects];
	c.td_exec = NULL;
	return c;
}

static NSDictionary *decodeVS(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

/// Answers the oldest unanswered request of a type.
static void answerVS(TGClient *c, NSString *type, NSDictionary *answer) {
	for (NSData *d in c.outbox){
		NSDictionary *sent = decodeVS(d);
		if (![sent[@"@type"] isEqualToString:type])
			continue;
		NSString *extra = sent[@"@extra"];
		if (!extra || !c.pendingRequests[extra])
			continue;
		NSMutableDictionary *reply = [answer mutableCopy];
		reply[@"@extra"] = extra;
		[c handleUpdate:reply];
		return;
	}
}

/// The newest unanswered request of a type, for checking the wire shape.
static NSDictionary *VSLastRequest(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox){
		NSDictionary *sent = decodeVS(d);
		if ([sent[@"@type"] isEqualToString:type])
			found = sent;
	}
	return found;
}

static NSString *VSPath(void) {
	static NSString *path;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"send-test.mov"];
		[@"/" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	});
	return path;
}

/// The answer TDLib gives for an accepted send: the pending message, with the
/// local file id the upload will be reported against.
static NSDictionary *VSPendingMessage(int64_t messageId) {
	return @{
		@"@type"   : @"message",
		@"id"      : @(messageId),
		@"chat_id" : @(42),
		@"content" : @{
			@"@type"      : @"messageVideoNote",
			@"video_note" : @{
				@"@type"    : @"videoNote",
				@"duration" : @13,
				@"length"   : @360,
				@"video"    : @{@"@type" : @"video", @"id" : @(77)},
			},
		},
	};
}

@implementation TGClientVideoNoteSendTests

- (void)testSendVideoNote_ErrorResultCallsCompletionNO {
	TGClient *c = VS();
	__block NSInteger answers = 0;
	__block BOOL sent = YES;
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO progress:nil completion:^(BOOL ok){
		answers++;
		sent = ok;
	}];

	answerVS(c, @"sendMessage", @{@"@type"   : @"error",
								   @"code"    : @(400),
								   @"message" : @"CHAT_WRITE_FORBIDDEN"});

	XCTAssertEqual(answers, (NSInteger)1);
	XCTAssertFalse(sent);
}

- (void)testSendSucceeded_ForThePendingIdCallsCompletionYESOnce {
	TGClient *c = VS();
	__block NSInteger answers = 0;
	__block BOOL sent = NO;
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO progress:nil completion:^(BOOL ok){
		answers++;
		sent = ok;
	}];

	answerVS(c, @"sendMessage", VSPendingMessage(1048576001));

	NSDictionary *succeeded = @{
		@"@type"          : @"updateMessageSendSucceeded",
		@"message"        : @{@"@type" : @"message", @"id" : @(4000), @"chat_id" : @(42)},
		@"old_message_id" : @(1048576001),
	};
	[c handleUpdate:succeeded];
	XCTAssertEqual(answers, (NSInteger)1);
	XCTAssertTrue(sent);

	// A repeated update is not a second answer.
	[c handleUpdate:succeeded];
	XCTAssertEqual(answers, (NSInteger)1);
}

- (void)testSendFailed_ForThePendingIdCallsCompletionNO {
	TGClient *c = VS();
	__block NSInteger answers = 0;
	__block BOOL sent = YES;
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO progress:nil completion:^(BOOL ok){
		answers++;
		sent = ok;
	}];

	answerVS(c, @"sendMessage", VSPendingMessage(1048576002));

	[c handleUpdate:@{
		@"@type"          : @"updateMessageSendFailed",
		@"message"        : @{@"@type" : @"message", @"id" : @(1048576002), @"chat_id" : @(42)},
		@"old_message_id" : @(1048576002),
		@"error"          : @{@"@type" : @"error", @"code" : @(400),
							  @"message" : @"CHAT_WRITE_FORBIDDEN"},
	}];

	XCTAssertEqual(answers, (NSInteger)1);
	XCTAssertFalse(sent);
}

- (void)testAcceptedGetsThePendingIdBeforeTheWaiterIsUsable {
	TGClient *c = VS();
	__block int64_t acceptedId = 0;
	__block CGFloat progressAtAccept = -1;
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO thumbnail:nil progress:nil
				  accepted:^(int64_t messageId){
		acceptedId = messageId;
		progressAtAccept = [c sendProgressForMessage:messageId];
	} completion:^(BOOL ok){}];

	answerVS(c, @"sendMessage", VSPendingMessage(1048576005));

	XCTAssertEqual(acceptedId, (int64_t)1048576005);
	XCTAssertTrue(progressAtAccept == 0);
	XCTAssertNotNil(c.noteSendWaiters[@(1048576005)]);
	[c noteSendFinished:1048576005 sent:YES];
}

- (void)testThumbnailIsInThePayloadWhenGiven {
	TGClient *c = VS();
	NSString *thumb = @"/tmp/video-note-thumb.jpg";
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO thumbnail:thumb progress:nil accepted:nil completion:nil];

	NSDictionary *sent = VSLastRequest(c, @"sendMessage");
	NSDictionary *note = sent[@"input_message_content"][@"video_note"];
	NSDictionary *thumbnail = note[@"thumbnail"];
	XCTAssertEqualObjects(thumbnail[@"@type"], @"inputThumbnail");
	XCTAssertEqualObjects(thumbnail[@"thumbnail"][@"@type"], @"inputFileLocal");
	XCTAssertEqualObjects(thumbnail[@"thumbnail"][@"path"], thumb);
	XCTAssertEqualObjects(thumbnail[@"width"], @240);
	XCTAssertEqualObjects(thumbnail[@"height"], @240);
}

- (void)testSendProgressReturnsTheLastFraction {
	TGClient *c = VS();
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO progress:^(CGFloat progress){} completion:^(BOOL ok){}];
	answerVS(c, @"sendMessage", VSPendingMessage(1048576006));

	XCTAssertTrue(fabs((double)([c sendProgressForMessage:1048576006]) - (0.0)) < 0.0001);
	[c noteUploadProgress:77 fraction:0.25f];
	XCTAssertTrue(fabs((double)([c sendProgressForMessage:1048576006]) - (0.25)) < 0.0001);
	[c noteUploadProgress:77 fraction:0.75f];
	XCTAssertTrue(fabs((double)([c sendProgressForMessage:1048576006]) - (0.75)) < 0.0001);
	[c noteSendFinished:1048576006 sent:YES];
}

- (void)testCancelSendingMessageDeletesRevokedAndAnswersOnce {
	TGClient *c = VS();
	__block NSInteger answers = 0;
	__block BOOL sent = NO;
	[c sendVideoNoteAtPath:VSPath() duration:13 length:360 toChat:42 thread:0
				  viewOnce:NO progress:nil completion:^(BOOL ok){
		answers++;
		sent = ok;
	}];
	answerVS(c, @"sendMessage", VSPendingMessage(1048576007));

	[c cancelSendingMessage:1048576007 inChat:42];

	NSDictionary *request = VSLastRequest(c, @"deleteMessages");
	XCTAssertEqualObjects(request[@"chat_id"], @42);
	XCTAssertEqualObjects(request[@"revoke"], @YES);
	XCTAssertTrue([request[@"message_ids"] containsObject:@(1048576007)]);
	XCTAssertEqual(answers, (NSInteger)1);
	XCTAssertTrue(sent);

	// The update that follows is not a second answer.
	[c noteSendFinished:1048576007 sent:YES];
	XCTAssertEqual(answers, (NSInteger)1);
}

- (void)testFlattenMarksAPendingStateAsSending {
	NSDictionary *base = @{
		@"id"          : @1,
		@"chat_id"     : @42,
		@"date"        : @1,
		@"is_outgoing" : @YES,
		@"content"     : @{@"@type" : @"messageText",
						   @"text"  : @{@"text" : @"hi"}},
	};
	NSMutableDictionary *pending = [base mutableCopy];
	pending[@"sending_state"] = @{@"@type" : @"messageSendingStatePending"};
	XCTAssertTrue([TGFlattenMessage(pending)[@"sending"] boolValue]);

	NSMutableDictionary *failed = [base mutableCopy];
	failed[@"sending_state"] = @{@"@type" : @"messageSendingStateFailed"};
	XCTAssertNil(TGFlattenMessage(failed)[@"sending"]);
	XCTAssertNil(TGFlattenMessage(base)[@"sending"]);
}

@end
