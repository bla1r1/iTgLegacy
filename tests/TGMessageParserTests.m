// TGMessageParserTests.m — TGFlattenMessage, which nothing covered.
//
// Every bubble in the app is drawn from the dictionary this function returns,
// and a hundred-odd TDLib content types funnel through it. It had two fields
// under test (the ones added with the reaction and retry work) and none of
// the rest, although it is where a renamed TDLib key goes unnoticed - which
// is exactly how B3 happened one level up, in the folder titles.
//
// These are the invariants a chat is unreadable without: a caption beats the
// content's own words, a reply keeps what it answers, a forward says who
// from, and content nobody wrote a branch for says what it is instead of
// drawing an empty bubble.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGMessageParserTests : XCTestCase @end

/// A message as TDLib sends one, with `content` filled in by the test.
static NSDictionary *msg(NSDictionary *content, NSDictionary *extra) {
	NSMutableDictionary *m = [@{
		@"@type"       : @"message",
		@"id"          : @(5),
		@"date"        : @(1700000000),
		@"is_outgoing" : @NO,
		@"content"     : content ?: @{},
	} mutableCopy];
	for (NSString *key in extra)
		m[key] = extra[key];
	return m;
}

static NSDictionary *textContent(NSString *text) {
	return @{@"@type" : @"messageText",
			 @"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""}};
}

@implementation TGMessageParserTests

#pragma mark - what the bubble says

- (void)testFlatten_PlainTextCarriesStraightThrough {
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"hello"), nil));
	XCTAssertEqualObjects(flat[@"text"], @"hello");
	XCTAssertEqualObjects(flat[@"kind"], @"messageText");
	XCTAssertFalse([flat[@"service"] boolValue]);
	XCTAssertEqual([flat[@"id"] longLongValue], 5LL);
}

/// A caption beats whatever the content type would have said, because the
/// caption is what the sender wrote.
- (void)testFlatten_ACaptionWinsOverTheContentsOwnWords {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type"   : @"messageDocument",
			@"caption" : @{@"text" : @"the slides"},
			@"document": @{@"file_name" : @"deck.pdf",
						   @"document" : @{@"id" : @(9), @"size" : @(2048)}}}, nil));
	XCTAssertEqualObjects(flat[@"text"], @"the slides");
	XCTAssertEqualObjects(flat[@"docName"], @"deck.pdf");
	XCTAssertEqual([flat[@"docSize"] longLongValue], 2048LL);
}

/// A picture with no caption says nothing: the image is the message, and a
/// line of text under it would be noise.
- (void)testFlatten_APhotoWithNoCaptionHasNoText {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messagePhoto",
			@"photo" : @{@"sizes" : @[@{@"type" : @"x", @"width" : @(800),
										@"height" : @(600),
										@"photo" : @{@"id" : @(11)}}]}}, nil));
	XCTAssertEqualObjects(flat[@"text"], @"");
	XCTAssertFalse([flat[@"photoId"] isEqual:[NSNull null]],
				   @"a photo must carry a file id to draw");
}

/// The one that keeps the app honest as TDLib grows: a content type nobody
/// has written a branch for reads as its own name in words, as a service
/// line, rather than as an empty bubble.
- (void)testFlatten_UnknownContentBecomesAServiceLineRatherThanNothing {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messageVideoChatStarted"}, nil));
	XCTAssertTrue([flat[@"service"] boolValue]);
	XCTAssertEqualObjects(flat[@"text"], @"Video chat started");
}

/// A self-destructing photo that has gone says so; an empty bubble would read
/// as a bug.
- (void)testFlatten_ExpiredMediaSaysSoAsAService {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messageExpiredPhoto"}, nil));
	XCTAssertTrue([flat[@"service"] boolValue]);
	XCTAssertEqualObjects(flat[@"text"], @"Expired media");
}

#pragma mark - replies

- (void)testFlatten_AReplyKeepsTheIdItAnswers {
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"yes"), @{
			@"reply_to" : @{@"@type" : @"messageReplyToMessage",
							@"message_id" : @(4)}}));
	XCTAssertEqual([flat[@"replyId"] longLongValue], 4LL);
}

/// Newer TDLib carries the quoted text inline, which saves the chat a fetch.
- (void)testFlatten_AnInlineQuoteIsKept {
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"yes"), @{
			@"reply_to" : @{@"@type" : @"messageReplyToMessage",
							@"message_id" : @(4),
							@"quote" : @{@"text" : @{@"text" : @"are you coming?"}}}}));
	XCTAssertEqualObjects(flat[@"replyText"], @"are you coming?");
}

/// A reply to a story is not a reply to a message, and treating it as one
/// would have the chat fetching a message id that does not exist.
- (void)testFlatten_AReplyToSomethingOtherThanAMessageIsNotAReply {
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"nice"), @{
			@"reply_to" : @{@"@type" : @"messageReplyToStory",
							@"story_id" : @(9)}}));
	XCTAssertEqualObjects(flat[@"replyId"], [NSNull null]);
	XCTAssertEqualObjects(flat[@"replyText"], @"");
}

#pragma mark - forwards

- (void)testFlatten_AForwardFromAHiddenUserUsesTheNameTheySent {
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"look"), @{
			@"forward_info" : @{@"origin" : @{@"@type" : @"messageOriginHiddenUser",
											  @"sender_name" : @"Someone"}}}));
	XCTAssertEqualObjects(flat[@"forward"], @"Someone");
}

/// A channel forward is signed when there is a signature and named as a
/// channel when there is not - either way the line is not blank.
- (void)testFlatten_AChannelForwardIsSignedOrNamedButNeverBlank {
	NSDictionary *signed_ = TGFlattenMessage(msg(textContent(@"news"), @{
			@"forward_info" : @{@"origin" : @{@"@type" : @"messageOriginChannel",
											  @"author_signature" : @"Ed"}}}));
	XCTAssertEqualObjects(signed_[@"forward"], @"Ed");

	NSDictionary *unsigned_ = TGFlattenMessage(msg(textContent(@"news"), @{
			@"forward_info" : @{@"origin" : @{@"@type" : @"messageOriginChannel",
											  @"author_signature" : @""}}}));
	XCTAssertEqualObjects(unsigned_[@"forward"], @"a channel");
}

/// A user whose name has not arrived yet still forwards from someone.
- (void)testFlatten_AForwardFromAnUnknownUserStillNamesSomeone {
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"look"), @{
			@"forward_info" : @{@"origin" : @{@"@type" : @"messageOriginUser",
											  @"sender_user_id" : @(424242)}}}));
	XCTAssertEqualObjects(flat[@"forward"], @"a user");
}

- (void)testFlatten_NoForwardIsAnEmptyStringAndNotNil {
	// The cell reads -length on this, so nil would be a silent empty line and
	// a dictionary without the key would throw on insertion.
	NSDictionary *flat = TGFlattenMessage(msg(textContent(@"hi"), nil));
	XCTAssertEqualObjects(flat[@"forward"], @"");
}

#pragma mark - edited, albums, polls

- (void)testFlatten_EditedComesFromTheDateRatherThanAFlag {
	XCTAssertFalse([TGFlattenMessage(msg(textContent(@"hi"), nil))[@"edited"] boolValue]);
	XCTAssertTrue([TGFlattenMessage(msg(textContent(@"hi"),
			@{@"edit_date" : @(1700000001)}))[@"edited"] boolValue]);
	// Zero is not an edit; TDLib sends it for everything unedited.
	XCTAssertFalse([TGFlattenMessage(msg(textContent(@"hi"),
			@{@"edit_date" : @(0)}))[@"edited"] boolValue]);
}

/// Several pictures sent together share an album id, which is how the chat
/// knows to draw them as one block.
- (void)testFlatten_AnAlbumIdIsCarriedThrough {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messagePhoto",
			@"photo" : @{@"sizes" : @[@{@"type" : @"x", @"width" : @(100),
										@"height" : @(100),
										@"photo" : @{@"id" : @(11)}}]}},
			@{@"media_album_id" : @"7788"}));
	XCTAssertEqualObjects(flat[@"albumId"], @"7788");
}

- (void)testFlatten_APollKeepsItsQuestionOptionsAndState {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messagePoll",
			@"poll"  : @{@"question" : @{@"text" : @"Tea?"},
						 @"total_voter_count" : @(3),
						 @"is_closed" : @YES,
						 @"is_anonymous" : @NO,
						 @"options" : @[@{@"text" : @{@"text" : @"Yes"},
										  @"vote_percentage" : @(66)},
										@{@"text" : @{@"text" : @"No"},
										  @"vote_percentage" : @(34)}]}}, nil));
	XCTAssertEqualObjects(flat[@"pollQuestion"], @"Tea?");
	XCTAssertEqual([flat[@"pollOptions"] count], (NSUInteger)2);
	XCTAssertEqual([flat[@"pollTotal"] integerValue], (NSInteger)3);
	XCTAssertTrue([flat[@"pollClosed"] boolValue]);
	XCTAssertFalse([flat[@"pollAnonymous"] boolValue]);
	// A poll is not a service message, whatever its text looks like.
	XCTAssertFalse([flat[@"service"] boolValue]);
}

#pragma mark - reactions

- (void)testReactionSummary_IsEmojiAndCountMostUsedFirst {
	NSString *summary = TGReactionSummary(@{@"interaction_info" :
			@{@"reactions" : @{@"reactions" : @[
					@{@"type" : @{@"emoji" : @"\U0001F44D"}, @"total_count" : @(3)},
					@{@"type" : @{@"emoji" : @"\U00002764"}, @"total_count" : @(1)}]}}});
	XCTAssertEqualObjects(summary, @"\U0001F44D 3  \U00002764 1");
}

/// A custom emoji has no character to draw, so it is counted under a star
/// rather than leaving a gap in the line.
- (void)testReactionSummary_CustomEmojiIsCountedUnderAStar {
	NSString *summary = TGReactionSummary(@{@"interaction_info" :
			@{@"reactions" : @{@"reactions" : @[
					@{@"type" : @{@"@type" : @"reactionTypeCustomEmoji"},
					  @"total_count" : @(2)}]}}});
	XCTAssertEqualObjects(summary, @"\U00002B50 2");
}

- (void)testReactionSummary_NoReactionsIsNilRatherThanAnEmptyLine {
	XCTAssertNil(TGReactionSummary(@{}));
	XCTAssertNil(TGReactionSummary(@{@"interaction_info" :
			@{@"reactions" : @{@"reactions" : @[]}}}));
	// A shape that is not a list at all must not throw.
	XCTAssertNil(TGReactionSummary(@{@"interaction_info" :
			@{@"reactions" : @{@"reactions" : @"nonsense"}}}));
}

#pragma mark - the type-name fallback

/// The fallback that keeps unknown content readable. It is the reason a new
/// TDLib release does not leave blank bubbles behind.
- (void)testPhraseFromTypeName_SplitsCamelCaseAndDropsThePrefix {
	XCTAssertEqualObjects(TGPhraseFromTypeName(@"messageVideoChatStarted"),
						  @"Video chat started");
	XCTAssertEqualObjects(TGPhraseFromTypeName(@"messagePinMessage"),
						  @"Pin message");
	// Not a message type at all, and still readable.
	XCTAssertEqualObjects(TGPhraseFromTypeName(@"somethingElse"),
						  @"Something else");
	XCTAssertEqualObjects(TGPhraseFromTypeName(@"message"), @"Message");
}

#pragma mark - a track

/// Everything the track bubble draws comes from here, and until the bubble
/// existed none of it was read: a song drew as the document it also is, and
/// the cover TDLib sends was never put on screen.
- (void)testFlatten_ATrackCarriesItsTitlePerformerCoverAndLength {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messageAudio",
			@"audio" : @{@"file_name" : @"track01.mp3",
						 @"title"     : @"Teardrop",
						 @"performer" : @"Massive Attack",
						 @"duration"  : @(330),
						 @"audio"     : @{@"id" : @(21)},
						 @"album_cover_thumbnail" : @{@"file" : @{@"id" : @(22)}}}}, nil));

	XCTAssertEqualObjects(flat[@"kind"], @"messageAudio");
	XCTAssertEqualObjects(flat[@"audioTitle"], @"Teardrop");
	XCTAssertEqualObjects(flat[@"audioPerformer"], @"Massive Attack");
	XCTAssertEqual([flat[@"duration"] integerValue], (NSInteger)330);
	XCTAssertEqual([flat[@"albumCoverId"] integerValue], (NSInteger)22);
	// It is still a file, because that is what gets downloaded to play it.
	XCTAssertEqual([flat[@"docId"] integerValue], (NSInteger)21);
}

/// A track with no tags falls back to the file name, which is what the bubble
/// puts on its first line rather than leaving it blank.
- (void)testFlatten_ATrackWithNoTagsStillHasAName {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messageAudio",
			@"audio" : @{@"file_name" : @"track01.mp3",
						 @"duration"  : @(12),
						 @"audio"     : @{@"id" : @(21)}}}, nil));
	XCTAssertEqualObjects(flat[@"text"], @"track01.mp3");
	XCTAssertEqualObjects(flat[@"audioTitle"], @"");
	XCTAssertEqualObjects(flat[@"audioPerformer"], @"");
	// Nothing to draw rather than a zero that would look like a real cover.
	XCTAssertEqualObjects(flat[@"albumCoverId"], [NSNull null]);
}

/// A track is not a service message, however little it carries.
- (void)testFlatten_ATrackIsNotAServiceLine {
	NSDictionary *flat = TGFlattenMessage(msg(@{
			@"@type" : @"messageAudio",
			@"audio" : @{@"audio" : @{@"id" : @(21)}}}, nil));
	XCTAssertFalse([flat[@"service"] boolValue]);
}

@end

// vim:ft=objc
