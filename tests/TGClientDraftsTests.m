// TGClientDraftsTests.m — the requests behind the daily things that were
// missing: the draft, "typing...", taking a reaction off, marking a voice
// note played, resending what failed, pinning, and the self-set unread dot.
//
// Each of these is one request, and each was absent rather than wrong, so
// what a test can hold is the shape that goes out and the shape that comes
// back in. tdjson is never loaded on the host, so requests sit in the outbox
// where they can be read.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientDraftsTests : XCTestCase @end

static TGClient *D(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.chatsById removeAllObjects];
	return c;
}

/// The last outbox request whose JSON names this type, decoded. Last, not
/// first: a test that sends twice is asking about the second one.
static NSDictionary *lastRequestOfType(TGClient *c, NSString *type) {
	NSString *needle = [NSString stringWithFormat:@"\"%@\"", type];
	NSDictionary *found = nil;
	for (NSData *d in c.outbox){
		NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
		if (![json containsString:needle])
			continue;
		NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
		NSDictionary *request = [NSJSONSerialization JSONObjectWithData:
				[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static NSUInteger countRequestsOfType(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox){
		NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
		NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
		NSDictionary *request = [NSJSONSerialization JSONObjectWithData:
				[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
		if ([request[@"@type"] isEqualToString:type])
			n++;
	}
	return n;
}

@implementation TGClientDraftsTests

#pragma mark - drafts

/// The whole point of the draft: text typed and not sent has to leave the
/// device, or it is lost the moment the chat closes.
- (void)testDraft_CarriesTheTextAsFormattedText {
	TGClient *c = D();
	[c setDraft:@"half a thought" inChat:7 thread:0 replyTo:0];

	NSDictionary *r = lastRequestOfType(c, @"setChatDraftMessage");
	XCTAssertNotNil(r, @"setChatDraftMessage must reach the outbox");
	XCTAssertEqual([r[@"chat_id"] longLongValue], 7LL);
	XCTAssertEqualObjects(r[@"draft_message"][@"input_message_text"]
							[@"text"][@"text"], @"half a thought");
}

/// Clearing is the absence of draft_message, not an empty one: TDLib reads an
/// empty inputMessageText as an error and would leave the old draft standing.
- (void)testDraft_EmptyTextClearsRatherThanSendsAnEmptyDraft {
	TGClient *c = D();
	[c setDraft:@"" inChat:7 thread:0 replyTo:0];

	NSDictionary *r = lastRequestOfType(c, @"setChatDraftMessage");
	XCTAssertNotNil(r);
	XCTAssertNil(r[@"draft_message"], @"an empty draft must be no draft at all");
}

/// A draft written as a reply has to come back as a reply, or the thread is
/// lost between devices.
- (void)testDraft_KeepsWhatItWasReplyingTo {
	TGClient *c = D();
	[c setDraft:@"on second thought" inChat:7 thread:0 replyTo:99];

	NSDictionary *draft = lastRequestOfType(c, @"setChatDraftMessage")[@"draft_message"];
	XCTAssertEqualObjects(draft[@"reply_to"][@"@type"], @"inputMessageReplyToMessage");
	XCTAssertEqual([draft[@"reply_to"][@"message_id"] longLongValue], 99LL);
}

/// The chat list shows a draft in place of the last message, so it must be
/// readable the moment it is set and not a round trip later.
- (void)testDraft_IsReadableBackFromTheCacheAtOnce {
	TGClient *c = D();
	c.chatsById[@(7)] = [@{@"id" : @(7), @"title" : @"Someone"} mutableCopy];

	[c setDraft:@"pending" inChat:7 thread:0 replyTo:0];
	XCTAssertEqualObjects([c draftForChat:7], @"pending");

	[c setDraft:@"" inChat:7 thread:0 replyTo:0];
	XCTAssertEqualObjects([c draftForChat:7], @"");
}

/// A chat nobody has loaded has no draft rather than nil, because the caller
/// puts the answer straight into a text field.
- (void)testDraft_UnknownChatIsEmptyAndNotNil {
	XCTAssertEqualObjects([D() draftForChat:4242], @"");
}

#pragma mark - typing

- (void)testTyping_SendsTheActionAndCancelsWithTheSameShape {
	TGClient *c = D();
	[c sendTypingToChat:5 thread:3];
	NSDictionary *typing = lastRequestOfType(c, @"sendChatAction");
	XCTAssertEqualObjects(typing[@"action"][@"@type"], @"chatActionTyping");
	XCTAssertEqual([typing[@"message_thread_id"] longLongValue], 3LL);

	[c cancelTypingInChat:5 thread:3];
	XCTAssertEqualObjects(lastRequestOfType(c, @"sendChatAction")[@"action"][@"@type"],
						  @"chatActionCancel");
	XCTAssertEqual(countRequestsOfType(c, @"sendChatAction"), (NSUInteger)2);
}

#pragma mark - reactions

/// Putting one on worked; taking it off had no request at all, which is why
/// a reaction could not be undone.
- (void)testReaction_RemoveSendsTheEmojiItIsRemoving {
	TGClient *c = D();
	[c removeReaction:@"\U0001F44D" fromMessage:11 inChat:7];

	NSDictionary *r = lastRequestOfType(c, @"removeMessageReaction");
	XCTAssertNotNil(r);
	XCTAssertEqual([r[@"message_id"] longLongValue], 11LL);
	XCTAssertEqualObjects(r[@"reaction_type"][@"emoji"], @"\U0001F44D");
}

/// Nothing to remove means nothing sent: the menu offers Remove only when
/// there is one, and a stray request would clear someone else's.
- (void)testReaction_RemoveWithNoEmojiSendsNothing {
	TGClient *c = D();
	[c removeReaction:nil fromMessage:11 inChat:7];
	[c removeReaction:@"" fromMessage:11 inChat:7];
	XCTAssertEqual(countRequestsOfType(c, @"removeMessageReaction"), (NSUInteger)0);
}

/// The menu needs to know which emoji is yours to offer taking it back off,
/// and is_chosen is the only thing that says so.
- (void)testReaction_MyOwnIsTheChosenOne {
	NSDictionary *m = @{@"interaction_info" : @{@"reactions" : @{@"reactions" : @[
			@{@"type" : @{@"emoji" : @"\U0001F525"}, @"total_count" : @(3)},
			@{@"type" : @{@"emoji" : @"\U00002764"}, @"total_count" : @(1),
			  @"is_chosen" : @YES}]}}};
	XCTAssertEqualObjects(TGMyReactionEmoji(m), @"\U00002764");
}

/// A custom emoji has no character to draw or to send back, so it is not
/// something the menu can offer to remove.
- (void)testReaction_CustomEmojiIsNotOfferedAsMine {
	NSDictionary *m = @{@"interaction_info" : @{@"reactions" : @{@"reactions" : @[
			@{@"type" : @{@"@type" : @"reactionTypeCustomEmoji"},
			  @"total_count" : @(1), @"is_chosen" : @YES}]}}};
	XCTAssertNil(TGMyReactionEmoji(m));
}

- (void)testReaction_NoneChosenIsNil {
	XCTAssertNil(TGMyReactionEmoji(@{}));
	XCTAssertNil(TGMyReactionEmoji(@{@"interaction_info" : @{@"reactions" :
			@{@"reactions" : @[@{@"type" : @{@"emoji" : @"\U0001F44D"},
								 @"total_count" : @(2)}]}}}));
}

#pragma mark - played, failed, pinned, unread

- (void)testOpenContent_NamesTheMessageAndSkipsAZeroId {
	TGClient *c = D();
	[c openContentOfMessage:0 inChat:7];
	XCTAssertEqual(countRequestsOfType(c, @"openMessageContent"), (NSUInteger)0);

	[c openContentOfMessage:31 inChat:7];
	NSDictionary *r = lastRequestOfType(c, @"openMessageContent");
	XCTAssertEqual([r[@"message_id"] longLongValue], 31LL);
	XCTAssertEqual([r[@"chat_id"] longLongValue], 7LL);
}

/// A failed message is the only kind worth a Retry row, and the flattened
/// message is where the menu reads that from.
- (void)testFailed_FlagComesFromTheSendingState {
	NSDictionary *base = @{@"id" : @(5), @"date" : @(1),
			@"content" : @{@"@type" : @"messageText",
						   @"text" : @{@"text" : @"hi"}}};
	XCTAssertFalse([TGFlattenMessage(base)[@"failed"] boolValue]);

	NSMutableDictionary *failing = [base mutableCopy];
	failing[@"sending_state"] = @{@"@type" : @"messageSendingStateFailed"};
	XCTAssertTrue([TGFlattenMessage(failing)[@"failed"] boolValue]);

	NSMutableDictionary *pending = [base mutableCopy];
	pending[@"sending_state"] = @{@"@type" : @"messageSendingStatePending"};
	XCTAssertFalse([TGFlattenMessage(pending)[@"failed"] boolValue],
				   @"still on its way is not the same as failed");
}

- (void)testResend_CarriesTheIdsAndIgnoresAnEmptyList {
	TGClient *c = D();
	[c resendMessages:@[] inChat:7];
	XCTAssertEqual(countRequestsOfType(c, @"resendMessages"), (NSUInteger)0);

	[c resendMessages:@[@(5), @(6)] inChat:7];
	NSDictionary *r = lastRequestOfType(c, @"resendMessages");
	XCTAssertEqualObjects(r[@"message_ids"], (@[@(5), @(6)]));
}

- (void)testPin_PinsQuietlyAndUnpinsByItself {
	TGClient *c = D();
	[c pinMessage:12 inChat:7 notify:NO];
	NSDictionary *pin = lastRequestOfType(c, @"pinChatMessage");
	XCTAssertTrue([pin[@"disable_notification"] boolValue],
				  @"notify:NO must disable the notification, not enable it");
	XCTAssertFalse([pin[@"only_for_self"] boolValue]);

	[c unpinMessage:12 inChat:7];
	XCTAssertEqual([lastRequestOfType(c, @"unpinChatMessage")[@"message_id"]
			longLongValue], 12LL);
}

- (void)testMarkedUnread_SendsBothDirections {
	TGClient *c = D();
	[c setChat:7 markedUnread:YES];
	XCTAssertTrue([lastRequestOfType(c, @"toggleChatIsMarkedAsUnread")
			[@"is_marked_as_unread"] boolValue]);

	[c setChat:7 markedUnread:NO];
	XCTAssertFalse([lastRequestOfType(c, @"toggleChatIsMarkedAsUnread")
			[@"is_marked_as_unread"] boolValue]);
}

/// Two badges, two requests: reading the messages clears neither, and the
/// chat screen sends both on opening.
- (void)testReadAllBadges_SendsMentionsAndReactions {
	TGClient *c = D();
	[c readAllMentionsAndReactionsInChat:7];
	XCTAssertNotNil(lastRequestOfType(c, @"readAllChatMentions"));
	XCTAssertNotNil(lastRequestOfType(c, @"readAllChatReactions"));
}

/// The dot you set yourself is not the unread count, so the chat list has to
/// carry it separately or the menu offers the wrong one of the two.
- (void)testMarkedUnread_ReachesTheChatListAsItsOwnFlag {
	TGClient *c = D();
	[c handleUpdate:@{@"@type" : @"updateNewChat", @"chat" : @{
			@"@type" : @"chat", @"id" : @(7), @"title" : @"Someone",
			@"unread_count" : @(0),
			@"is_marked_as_unread" : @YES,
			@"positions" : @[@{@"@type" : @"chatPosition",
							   @"list" : @{@"@type" : @"chatListMain"},
							   @"order" : @"10"}]}}];
	XCTAssertTrue([c.chatsById[@(7)][@"markedUnread"] boolValue]);
	XCTAssertEqual([c.chatsById[@(7)][@"unread"] integerValue], (NSInteger)0);
}

@end

// vim:ft=objc
