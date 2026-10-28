// TGClientComposeTests.m — the tier-0 holes in composing and finding: markup
// that could not be sent, a caption that could not be edited, pictures that
// could not go as one album, and a search that only ever found what was
// already loaded.
//
// The shapes here are the ones TDLib refuses outright (an album where two
// pictures carry a caption) or accepts and does the wrong thing with (a
// caption edited as text, which is a different request and leaves the
// caption alone).
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientComposeTests : XCTestCase @end

static TGClient *C(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	[c.usersById removeAllObjects];
	c.onChatsChanged = nil;
	return c;
}

static NSDictionary *decodeC(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastC(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeC(d)[@"@type"] isEqualToString:type])
			found = decodeC(d);
	return found;
}

static NSUInteger countC(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeC(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

/// Answers the oldest unanswered request of a type, so a method that sends
/// three at once can be answered one at a time in a known order.
static void answerTyped(TGClient *c, NSString *type, NSDictionary *answer) {
	for (NSData *d in c.outbox){
		NSDictionary *sent = decodeC(d);
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

@implementation TGClientComposeTests

#pragma mark - markup

/// Without the execute symbol - which is how the host sees it, and how a
/// device with a dylib missing it would - the text goes as written rather
/// than not at all.
- (void)testFormattedText_FallsBackToTheTextAsWritten {
	TGClient *c = C();
	c.td_exec = NULL;

	NSDictionary *formatted = TGFormattedText(@"*bold* and plain");
	XCTAssertEqualObjects(formatted[@"@type"], @"formattedText");
	XCTAssertEqualObjects(formatted[@"text"], @"*bold* and plain");
	XCTAssertEqual([formatted[@"entities"] count], (NSUInteger)0);
}

- (void)testFormattedText_EmptyAndNilAreStillAFormattedText {
	TGClient *c = C();
	c.td_exec = NULL;
	XCTAssertEqualObjects(TGFormattedText(nil)[@"text"], @"");
	XCTAssertEqualObjects(TGFormattedText(@"")[@"text"], @"");
}

/// A message now carries a formattedText rather than a bare string, which is
/// what lets bold and italic leave this device at all.
- (void)testSendText_CarriesAFormattedTextRatherThanAPlainString {
	TGClient *c = C();
	c.td_exec = NULL;
	[c sendText:@"hello" toChat:7 thread:0 replyTo:0];

	NSDictionary *content = lastC(c, @"sendMessage")[@"input_message_content"];
	XCTAssertEqualObjects(content[@"@type"], @"inputMessageText");
	XCTAssertEqualObjects(content[@"text"][@"@type"], @"formattedText");
	XCTAssertEqualObjects(content[@"text"][@"text"], @"hello");
}

#pragma mark - captions

/// Editing a caption as text leaves the caption alone: it is its own
/// request, and that is why media with a caption had no Edit at all.
- (void)testEditCaption_IsItsOwnRequestAndNotEditMessageText {
	TGClient *c = C();
	c.td_exec = NULL;
	[c editCaption:@"the slides" ofMessage:5 inChat:7 completion:nil];

	NSDictionary *r = lastC(c, @"editMessageCaption");
	XCTAssertNotNil(r);
	XCTAssertEqual(countC(c, @"editMessageText"), (NSUInteger)0);
	XCTAssertEqual([r[@"message_id"] longLongValue], 5LL);
	XCTAssertEqualObjects(r[@"caption"][@"text"], @"the slides");
}

- (void)testEditCaption_AnErrorIsNotSuccess {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL ok = YES;
	[c editCaption:@"x" ofMessage:5 inChat:7 completion:^(BOOL good){ ok = good; }];
	answerTyped(c, @"editMessageCaption",
			@{@"@type" : @"error", @"message" : @"MESSAGE_NOT_MODIFIED"});
	XCTAssertFalse(ok);
}

/// Replacing the picture takes the whole content, so the caption has to
/// travel with it or editing the picture wipes the words under it.
- (void)testEditPhoto_CarriesTheCaptionAlongWithTheNewPicture {
	TGClient *c = C();
	c.td_exec = NULL;
	[c editPhotoAtPath:@"/tmp/new.jpg" caption:@"still the slides"
			 ofMessage:5 inChat:7 completion:nil];

	NSDictionary *content = lastC(c, @"editMessageMedia")[@"input_message_content"];
	XCTAssertEqualObjects(content[@"@type"], @"inputMessagePhoto");
	XCTAssertEqualObjects(content[@"photo"][@"path"], @"/tmp/new.jpg");
	XCTAssertEqualObjects(content[@"caption"][@"text"], @"still the slides");
}

- (void)testEditPhoto_RefusesAnEmptyPathRatherThanSendingOne {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL ok = YES;
	[c editPhotoAtPath:@"" caption:nil ofMessage:5 inChat:7
			completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countC(c, @"editMessageMedia"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

#pragma mark - albums

/// One request, not several: that is the difference between an album and a
/// run of pictures that happen to be next to each other.
- (void)testAlbum_IsOneRequestWithEveryPictureInIt {
	TGClient *c = C();
	c.td_exec = NULL;
	[c sendPhotoAlbumAtPaths:@[@"/tmp/a.jpg", @"/tmp/b.jpg", @"/tmp/c.jpg"]
					 caption:@"three of them" toChat:7 thread:0];

	XCTAssertEqual(countC(c, @"sendMessageAlbum"), (NSUInteger)1);
	XCTAssertEqual(countC(c, @"sendMessage"), (NSUInteger)0);
	NSArray *contents = lastC(c, @"sendMessageAlbum")[@"input_message_contents"];
	XCTAssertEqual(contents.count, (NSUInteger)3);
	XCTAssertEqualObjects(contents[0][@"photo"][@"path"], @"/tmp/a.jpg");
}

/// TDLib refuses an album where more than one picture carries a caption, so
/// only the first may.
- (void)testAlbum_OnlyTheFirstPictureCarriesTheCaption {
	TGClient *c = C();
	c.td_exec = NULL;
	[c sendPhotoAlbumAtPaths:@[@"/tmp/a.jpg", @"/tmp/b.jpg"]
					 caption:@"the caption" toChat:7 thread:0];

	NSArray *contents = lastC(c, @"sendMessageAlbum")[@"input_message_contents"];
	XCTAssertEqualObjects(contents[0][@"caption"][@"text"], @"the caption");
	XCTAssertEqualObjects(contents[1][@"caption"][@"text"], @"");
}

/// Their own ceiling is ten. An eleventh would have the whole album refused
/// rather than trimmed.
- (void)testAlbum_StopsAtTen {
	TGClient *c = C();
	c.td_exec = NULL;
	NSMutableArray *paths = [NSMutableArray array];
	for (NSUInteger i = 0; i < 14; i++)
		[paths addObject:[NSString stringWithFormat:@"/tmp/%lu.jpg", (unsigned long)i]];
	[c sendPhotoAlbumAtPaths:paths caption:nil toChat:7 thread:0];

	NSArray *contents = lastC(c, @"sendMessageAlbum")[@"input_message_contents"];
	XCTAssertEqual(contents.count, (NSUInteger)10);
}

- (void)testAlbum_NothingToSendIsNoRequest {
	TGClient *c = C();
	c.td_exec = NULL;
	[c sendPhotoAlbumAtPaths:@[] caption:@"x" toChat:7 thread:0];
	[c sendPhotoAlbumAtPaths:@[@"", [NSNull null]] caption:nil toChat:7 thread:0];
	XCTAssertEqual(countC(c, @"sendMessageAlbum"), (NSUInteger)0);
}

#pragma mark - finding a chat by name

/// Three requests, one answer. Matching titles in the loaded list only ever
/// found chats already here, so a chat this account has and has not opened -
/// and every public chat - was unfindable by name.
- (void)testSearchChats_AsksAllThreePlacesAChatCanBe {
	TGClient *c = C();
	[c searchChatsForQuery:@"walk" completion:nil];
	XCTAssertEqual(countC(c, @"searchChats"), (NSUInteger)1);
	XCTAssertEqual(countC(c, @"searchChatsOnServer"), (NSUInteger)1);
	XCTAssertEqual(countC(c, @"searchPublicChats"), (NSUInteger)1);
}

/// Local first, and each chat once: a chat you are in must never rank below
/// a stranger with a similar name.
- (void)testSearchChats_LocalComesFirstAndNothingAppearsTwice {
	TGClient *c = C();
	c.chatsById[@(7)] = [@{@"id" : @(7), @"title" : @"Walkers"} mutableCopy];
	c.chatsById[@(8)] = [@{@"id" : @(8), @"title" : @"Walking group"} mutableCopy];

	__block NSArray *found = nil;
	[c searchChatsForQuery:@"walk" completion:^(NSArray *chats){ found = chats; }];

	// The public answer arrives first and still ends up last.
	answerTyped(c, @"searchPublicChats", @{@"@type" : @"chats",
										   @"chat_ids" : @[@(9), @(7)]});
	answerTyped(c, @"searchChatsOnServer", @{@"@type" : @"chats",
											 @"chat_ids" : @[@(8)]});
	answerTyped(c, @"searchChats", @{@"@type" : @"chats", @"chat_ids" : @[@(7)]});

	XCTAssertEqual(found.count, (NSUInteger)3);
	XCTAssertEqual([found[0][@"id"] longLongValue], 7LL);
	XCTAssertEqual([found[1][@"id"] longLongValue], 8LL);
	XCTAssertEqual([found[2][@"id"] longLongValue], 9LL);
}

/// The answer waits for all three rather than arriving three times, or the
/// table would reorder itself under the finger.
- (void)testSearchChats_AnswersOnceAllThreeHaveLanded {
	TGClient *c = C();
	__block NSUInteger calls = 0;
	[c searchChatsForQuery:@"walk" completion:^(NSArray *chats){ calls++; }];

	answerTyped(c, @"searchChats", @{@"@type" : @"chats", @"chat_ids" : @[]});
	XCTAssertEqual(calls, (NSUInteger)0);
	answerTyped(c, @"searchChatsOnServer", @{@"@type" : @"chats", @"chat_ids" : @[]});
	XCTAssertEqual(calls, (NSUInteger)0);
	answerTyped(c, @"searchPublicChats", @{@"@type" : @"chats", @"chat_ids" : @[]});
	XCTAssertEqual(calls, (NSUInteger)1);
}

/// A public chat nobody here has opened has no title to draw, so it is asked
/// for - and the row carries its id meanwhile, which is enough to open it.
- (void)testSearchChats_AnUnknownPublicChatIsAskedForById {
	TGClient *c = C();
	__block NSArray *found = nil;
	[c searchChatsForQuery:@"walk" completion:^(NSArray *chats){ found = chats; }];
	answerTyped(c, @"searchChats", @{@"@type" : @"chats", @"chat_ids" : @[]});
	answerTyped(c, @"searchChatsOnServer", @{@"@type" : @"chats", @"chat_ids" : @[]});
	answerTyped(c, @"searchPublicChats", @{@"@type" : @"chats", @"chat_ids" : @[@(99)]});

	XCTAssertEqual(found.count, (NSUInteger)1);
	XCTAssertEqual([found[0][@"id"] longLongValue], 99LL);
	XCTAssertEqualObjects(found[0][@"title"], @"");
	XCTAssertNotNil(lastC(c, @"getChat"), @"its title has to be asked for");
}

- (void)testSearchChats_AnEmptyQueryIsNoRequest {
	TGClient *c = C();
	__block BOOL called = NO;
	[c searchChatsForQuery:@"" completion:^(NSArray *chats){ called = YES; }];
	XCTAssertEqual(countC(c, @"searchChats"), (NSUInteger)0);
	XCTAssertTrue(called, @"the caller still has to be told there is nothing");
}

/// Telegram matches a contact on the username and the phone number too,
/// which comparing names here never did.
- (void)testSearchContacts_NamedOffWhatTheListKnows {
	TGClient *c = C();
	c.usersById[@(6)] = @"Pat";
	__block NSArray *found = nil;
	[c searchContactsForQuery:@"pat" completion:^(NSArray *users){ found = users; }];
	XCTAssertEqualObjects(lastC(c, @"searchContacts")[@"query"], @"pat");

	answerTyped(c, @"searchContacts", @{@"@type" : @"users",
										@"user_ids" : @[@(6), @(7)]});
	XCTAssertEqual(found.count, (NSUInteger)2);
	XCTAssertEqualObjects(found[0][@"name"], @"Pat");
	// A contact whose name has not arrived is still a row; the screen fills
	// it in from nameForUserId when it does.
	XCTAssertEqualObjects(found[1][@"name"], @"");
}

#pragma mark - links

/// A card under a message is Telegram's answer, not a guess here, and most
/// links have none - so nil has to be the ordinary case rather than an
/// error.
- (void)testLinkPreview_FlattensWhatACardDraws {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSDictionary *preview = nil;
	[c linkPreviewForText:@"look at https://example.com"
			   completion:^(NSDictionary *found){ preview = found; }];
	XCTAssertEqualObjects(lastC(c, @"getLinkPreview")[@"text"][@"text"],
						  @"look at https://example.com");

	answerTyped(c, @"getLinkPreview", @{@"@type" : @"linkPreview",
			@"url" : @"https://example.com",
			@"site_name" : @"Example",
			@"title" : @"An example",
			@"description" : @{@"text" : @"what it is"},
			@"instant_view_version" : @(2),
			@"type" : @{@"photo" : @{@"sizes" : @[
					@{@"photo" : @{@"id" : @(41)}},
					@{@"photo" : @{@"id" : @(42)}}]}}});

	XCTAssertEqualObjects(preview[@"site"], @"Example");
	XCTAssertEqualObjects(preview[@"title"], @"An example");
	XCTAssertEqualObjects(preview[@"description"], @"what it is");
	// The biggest size, which is the one a card draws.
	XCTAssertEqual([preview[@"photoId"] integerValue], (NSInteger)42);
	XCTAssertTrue([preview[@"instantView"] boolValue]);
}

- (void)testLinkPreview_NoPreviewIsNilAndNotAnEmptyCard {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSDictionary *preview = @{};
	[c linkPreviewForText:@"nothing here"
			   completion:^(NSDictionary *found){ preview = found; }];
	answerTyped(c, @"getLinkPreview",
			@{@"@type" : @"error", @"message" : @"WEBPAGE_NOT_FOUND"});
	XCTAssertNil(preview);
}

- (void)testLinkPreview_EmptyTextIsNoRequest {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL called = NO;
	[c linkPreviewForText:@"" completion:^(NSDictionary *found){ called = YES; }];
	XCTAssertEqual(countC(c, @"getLinkPreview"), (NSUInteger)0);
	XCTAssertTrue(called);
}

/// The chat used to read a t.me path by hand, which made
/// t.me/addstickers/foo a chat called "addstickers". Telegram says what its
/// own links mean.
- (void)testInternalLink_KindsAreReadRatherThanGuessed {
	TGClient *c = C();
	c.td_exec = NULL;

	__block NSString *kind = nil;
	__block NSString *value = nil;
	void (^answer)(NSDictionary *) = ^(NSDictionary *reply){
		answerTyped(c, @"getInternalLinkType", reply);
	};

	[c internalLinkKind:@"https://t.me/addstickers/foo"
			 completion:^(NSString *k, NSString *v){ kind = k; value = v; }];
	answer(@{@"@type" : @"internalLinkTypeStickerSet", @"sticker_set_name" : @"foo"});
	XCTAssertEqualObjects(kind, @"stickerSet");
	XCTAssertEqualObjects(value, @"foo");

	[c internalLinkKind:@"https://t.me/durov"
			 completion:^(NSString *k, NSString *v){ kind = k; value = v; }];
	answer(@{@"@type" : @"internalLinkTypePublicChat", @"chat_username" : @"durov"});
	XCTAssertEqualObjects(kind, @"publicChat");
	XCTAssertEqualObjects(value, @"durov");

	[c internalLinkKind:@"https://t.me/+abc"
			 completion:^(NSString *k, NSString *v){ kind = k; value = v; }];
	answer(@{@"@type" : @"internalLinkTypeChatInvite",
			 @"invite_link" : @"https://t.me/+abc"});
	XCTAssertEqualObjects(kind, @"inviteLink");
}

/// A kind this app has no step for must say so, so the caller falls back to
/// the paths it matches by hand rather than doing nothing.
- (void)testInternalLink_AnUnhandledKindAsksTelegramWhatTheLinkMeans {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSString *kind = nil;
	[c internalLinkKind:@"https://t.me/proxy?server=x"
			 completion:^(NSString *k, NSString *v){ kind = k; }];
	answerTyped(c, @"getInternalLinkType", @{@"@type" : @"internalLinkTypeProxy"});
	XCTAssertNil(kind);
	answerTyped(c, @"getDeepLinkInfo",
			@{@"@type" : @"error", @"message" : @"refused"});
	XCTAssertEqualObjects(kind, @"unknown");
}

/// a link with no schema still has a meaning, stated in prose on Telegram's
/// side - which is what the tap answers with rather than guessing from the
/// path.
- (void)testInternalLink_ADeepLinkNoteIsTheMeaning {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSString *kind = nil;
	__block NSString *note = nil;
	[c internalLinkKind:@"https://t.me/something"
			 completion:^(NSString *k, NSString *v){ kind = k; note = v; }];
	answerTyped(c, @"getInternalLinkType",
			@{@"@type" : @"internalLinkTypeUnsupported"});
	answerTyped(c, @"getDeepLinkInfo",
			@{@"@type" : @"deepLinkInfo",
			  @"message" : @{@"text" : @"This link carries a private secret."},
			  @"update_app" : @NO});
	XCTAssertEqualObjects(kind, @"deepLink");
	XCTAssertEqualObjects(note, @"This link carries a private secret.");
}

/// A prompt to update the app is not the payload's meaning: TDLib said so
/// because its copy is stale. None the wiser, the tap falls back.
- (void)testInternalLink_ADeepLinkAndUpdatePromptIsNotAMeaning {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSString *kind = nil;
	[c internalLinkKind:@"https://t.me/something"
			 completion:^(NSString *k, NSString *v){ kind = k; }];
	answerTyped(c, @"getInternalLinkType",
			@{@"@type" : @"internalLinkTypeUnsupported"});
	answerTyped(c, @"getDeepLinkInfo",
			@{@"@type" : @"deepLinkInfo",
			  @"message" : @{@"text" : @"Update Telegram"},
			  @"update_app" : @YES});
	XCTAssertEqualObjects(kind, @"unknown");
}

#pragma mark - markdown of a received message

/// A message whose sender composed it on a modern client stores entities -
/// which is what Edit should put back into the composer, the markdown out
/// of it, rather than the render.
- (void)testMarkdownOfMessage_AFormattedTextComesBackAsItsMarkdown {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSString *md = nil;
	[c markdownOfMessage:9 inChat:7 completion:^(NSString *m){ md = m; }];
	XCTAssertNil(md);
	answerTyped(c, @"getMessage",
			@{@"@type" : @"message",
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"@type" : @"formattedText",
										 @"text" : @"bold and plain",
										 @"entities" : @[@{@"@type" : @"textEntity",
														  @"offset" : @0,
														  @"length" : @4,
														  @"entity" : @{@"@type" : @"entityBold"}}]}}});
	answerTyped(c, @"getMarkdownText",
			@{@"@type" : @"formattedText", @"text" : @"*bold* and plain"});
	XCTAssertEqualObjects(md, @"*bold* and plain");
}

/// No entities, no round trip: a plain message is already the origin, and
/// a getMarkdownText asked about it would be a question with one answer.
- (void)testMarkdownOfMessage_APlainMessageIsNotWorthARoundTrip {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSString *md = nil;
	[c markdownOfMessage:9 inChat:7 completion:^(NSString *m){ md = m; }];
	answerTyped(c, @"getMessage",
			@{@"@type" : @"message",
			  @"content" : @{@"@type" : @"messageText",
							 @"text" : @{@"@type" : @"formattedText",
										 @"text" : @"plain",
										 @"entities" : @[]}}});
	[c.outbox removeAllObjects];
	answerTyped(c, @"getMarkdownText", @{@"@type" : @"ok"});
	XCTAssertEqualObjects(md, @"plain");
	XCTAssertEqual(countC(c, @"getMarkdownText"), (NSUInteger)0);
}

#pragma mark - signing up

/// A number Telegram has never seen waits in a state that had no case at
/// all, so a code entered on a new number left the code screen up forever.
- (void)testRegisterUser_CarriesTheNameAndRefusesAnEmptyOne {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL ok = YES;
	[c registerWithFirstName:@"" lastName:nil
				  completion:^(BOOL good, NSString *error){ ok = good; }];
	XCTAssertEqual(countC(c, @"registerUser"), (NSUInteger)0);
	XCTAssertFalse(ok);

	[c registerWithFirstName:@"Pat" lastName:@"Walker" completion:nil];
	NSDictionary *r = lastC(c, @"registerUser");
	XCTAssertEqualObjects(r[@"first_name"], @"Pat");
	XCTAssertEqualObjects(r[@"last_name"], @"Walker");
}

/// The terms arrive with the authorization state and nowhere else; the
/// screen that shows them cannot ask for them later.
- (void)testRegistrationTerms_AreKeptFromTheState {
	TGClient *c = C();
	[c handleUpdate:@{@"@type" : @"updateAuthorizationState",
			@"authorization_state" : @{
					@"@type" : @"authorizationStateWaitRegistration",
					@"terms_of_service" : @{
							@"text" : @{@"text" : @"Be nice to each other."}}}}];
	XCTAssertEqualObjects([c registrationTerms], @"Be nice to each other.");
	XCTAssertEqual(c.authState, TGAuthStateWaitRegistration);
}

/// Hidden countries are left out, and one with no calling code is not a row
/// the picker can use.
- (void)testCountries_FlattenToWhatThePickerNeeds {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSArray *countries = nil;
	[c countriesWithCompletion:^(NSArray *found){ countries = found; }];
	answerTyped(c, @"getCountries", @{@"@type" : @"countries", @"countries" : @[
			@{@"country_code" : @"UA", @"name" : @"Ukraine",
			  @"flag_emoji" : @"🇺🇦", @"calling_codes" : @[@"380"]},
			@{@"country_code" : @"XX", @"name" : @"Hidden",
			  @"is_hidden" : @YES, @"calling_codes" : @[@"1"]},
			@{@"country_code" : @"ZZ", @"name" : @"No code",
			  @"calling_codes" : @[]}]});

	XCTAssertEqual(countries.count, (NSUInteger)1);
	XCTAssertEqualObjects(countries[0][@"code"], @"UA");
	XCTAssertEqualObjects(countries[0][@"prefix"], @"+380");
}

#pragma mark - push

/// A production token registered as sandbox is silently never delivered to,
/// so the flag has to travel exactly as given.
- (void)testPushToken_CarriesTheTokenAndTheSandboxFlag {
	TGClient *c = C();
	c.td_exec = NULL;
	[c registerPushToken:@"deadbeef" sandbox:YES completion:nil];
	NSDictionary *token = lastC(c, @"registerDevice")[@"device_token"];
	XCTAssertEqualObjects(token[@"@type"], @"deviceTokenApplePush");
	XCTAssertEqualObjects(token[@"device_token"], @"deadbeef");
	XCTAssertTrue([token[@"is_app_sandbox"] boolValue]);

	[c registerPushToken:@"deadbeef" sandbox:NO completion:nil];
	XCTAssertFalse([lastC(c, @"registerDevice")[@"device_token"]
			[@"is_app_sandbox"] boolValue]);
}

- (void)testPushToken_NoTokenIsNoRequest {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL ok = YES;
	[c registerPushToken:@"" sandbox:NO completion:^(BOOL good){ ok = good; }];
	XCTAssertEqual(countC(c, @"registerDevice"), (NSUInteger)0);
	XCTAssertFalse(ok);
}

/// Only a pushReceiverId means Telegram took it; an error means notifications
/// will not arrive and the log should say so.
- (void)testPushToken_OnlyAReceiverIdCounts {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL ok = NO;
	[c registerPushToken:@"deadbeef" sandbox:NO completion:^(BOOL good){ ok = good; }];
	answerTyped(c, @"registerDevice", @{@"@type" : @"pushReceiverId", @"id" : @"7"});
	XCTAssertTrue(ok);

	[c registerPushToken:@"deadbeef" sandbox:NO completion:^(BOOL good){ ok = good; }];
	answerTyped(c, @"registerDevice",
			@{@"@type" : @"error", @"message" : @"Invalid token"});
	XCTAssertFalse(ok);
}

/// A notification that arrives while the app runs goes to TDLib as the JSON
/// it came as, so the chat list moves without waiting for a poll.
- (void)testPushPayload_GoesThroughAsJson {
	TGClient *c = C();
	c.td_exec = NULL;
	[c processPushPayload:@{@"p" : @"payload"}];
	NSDictionary *r = lastC(c, @"processPushNotification");
	XCTAssertNotNil(r);
	XCTAssertTrue([r[@"payload"] rangeOfString:@"payload"].location != NSNotFound);

	[c processPushPayload:nil];
	XCTAssertEqual(countC(c, @"processPushNotification"), (NSUInteger)1);
}

#pragma mark - contacts

- (void)testImportContact_SendsImportContactsWithFormattedFields {
	TGClient *c = C();
	c.td_exec = NULL;
	__block int64_t gotUserId = 0;
	[c importContactNamed:@"Alice" lastName:@"Smith" phone:@"+1 234 567" completion:^(int64_t uid){
		gotUserId = uid;
	}];
	NSDictionary *sent = lastC(c, @"importContacts");
	XCTAssertNotNil(sent);
	NSArray *contacts = sent[@"contacts"];
	XCTAssertEqual(contacts.count, (NSUInteger)1);
	XCTAssertEqualObjects(contacts[0][@"first_name"], @"Alice");
	XCTAssertEqualObjects(contacts[0][@"last_name"], @"Smith");
	XCTAssertEqualObjects(contacts[0][@"phone_number"], @"+1234567");
	answerTyped(c, @"importContacts", @{@"@type" : @"importedContacts", @"user_ids" : @[@(4242)]});
	XCTAssertEqual(gotUserId, (int64_t)4242);
}

- (void)testAddContact_SendsAddContactWithUserIdAndContact {
	TGClient *c = C();
	c.td_exec = NULL;
	__block BOOL finished = NO;
	[c addContactWithUserId:4242 firstName:@"Alice" lastName:@"Smith" phone:@"+1234567" completion:^(BOOL ok){
		finished = ok;
	}];
	NSDictionary *sent = lastC(c, @"addContact");
	XCTAssertNotNil(sent);
	XCTAssertEqualObjects(sent[@"user_id"], @(4242));
	XCTAssertEqualObjects(sent[@"contact"][@"first_name"], @"Alice");
	XCTAssertEqualObjects(sent[@"contact"][@"last_name"], @"Smith");
	XCTAssertEqualObjects(sent[@"contact"][@"phone_number"], @"+1234567");
	answerTyped(c, @"addContact", @{@"@type" : @"ok"});
	XCTAssertTrue(finished);
}

- (void)testBlockUser_SendsSetMessageSenderBlockList {
	TGClient *c = C();
	[c blockUserWithUserId:777];
	NSDictionary *sent = lastC(c, @"setMessageSenderBlockList");
	XCTAssertNotNil(sent);
	XCTAssertEqualObjects(sent[@"sender_id"][@"user_id"], @(777));
	XCTAssertEqualObjects(sent[@"block_list"][@"@type"], @"blockListMain");
}

- (void)testSharePhoneNumber_SendsSharePhoneNumber {
	TGClient *c = C();
	[c sharePhoneNumberWithUser:888];
	NSDictionary *sent = lastC(c, @"sharePhoneNumber");
	XCTAssertNotNil(sent);
	XCTAssertEqualObjects(sent[@"user_id"], @(888));
}

- (void)testChatActionBar_MergesKindAndAccount {
	TGClient *c = C();
	NSMutableDictionary *row = [@{@"id" : @(123)} mutableCopy];
	[c mergeActionBar:@{
		@"@type" : @"chatActionBarReportAddBlock",
		@"account_info" : @{
			@"first_name" : @"Jane",
			@"last_name" : @"Doe",
			@"phone_number" : @"+999",
		},
	} intoChatRow:row];
	XCTAssertEqualObjects(row[@"actionBarKind"], @"chatActionBarReportAddBlock");
	XCTAssertEqualObjects(row[@"actionBarAccount"][@"name"], @"Jane Doe");
	XCTAssertEqualObjects(row[@"actionBarAccount"][@"phone"], @"+999");
}

#pragma mark - replies and messages

- (void)testRepliedMessage_FetchesAndIncludesChatId {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSDictionary *gotMsg = nil;
	[c repliedMessageTo:100 inChat:200 completion:^(NSDictionary *m){
		gotMsg = m;
	}];
	NSDictionary *sent = lastC(c, @"getRepliedMessage");
	XCTAssertNotNil(sent);
	XCTAssertEqualObjects(sent[@"chat_id"], @(200));
	XCTAssertEqualObjects(sent[@"message_id"], @(100));
	answerTyped(c, @"getRepliedMessage", @{
		@"@type" : @"message",
		@"id" : @(99),
		@"chat_id" : @(200),
		@"content" : @{
			@"@type" : @"messageText",
			@"text" : @{@"text" : @"quoted text"},
		},
	});
	XCTAssertNotNil(gotMsg);
	XCTAssertEqual([gotMsg[@"id"] longLongValue], 99LL);
	XCTAssertEqualObjects(gotMsg[@"chatId"], @(200));
	XCTAssertEqualObjects(gotMsg[@"text"], @"quoted text");
}

- (void)testGetMessages_FetchesMultipleAndFlattens {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSArray *got = nil;
	[c messagesInChat:50 messageIds:@[@(1), @(2)] completion:^(NSArray *msgs){
		got = msgs;
	}];
	NSDictionary *sent = lastC(c, @"getMessages");
	XCTAssertNotNil(sent);
	XCTAssertEqualObjects(sent[@"chat_id"], @(50));
	XCTAssertEqualObjects(sent[@"message_ids"], (@[@(1), @(2)]));
	answerTyped(c, @"getMessages", @{
		@"@type" : @"messages",
		@"messages" : @[
			@{
				@"@type" : @"message",
				@"id" : @(1),
				@"content" : @{@"@type" : @"messageText", @"text" : @{@"text" : @"one"}},
			},
			[NSNull null],
		],
	});
	XCTAssertEqual(got.count, (NSUInteger)2);
	XCTAssertEqualObjects(got[0][@"text"], @"one");
	XCTAssertTrue([got[1] isEqual:[NSNull null]]);
}

- (void)testGetMessageProperties_PassesThroughResponse {
	TGClient *c = C();
	c.td_exec = NULL;
	__block NSDictionary *props = nil;
	[c messagePropertiesForChat:50 messageId:1 completion:^(NSDictionary *p){
		props = p;
	}];
	NSDictionary *sent = lastC(c, @"getMessageProperties");
	XCTAssertNotNil(sent);
	XCTAssertEqualObjects(sent[@"chat_id"], @(50));
	XCTAssertEqualObjects(sent[@"message_id"], @(1));
	answerTyped(c, @"getMessageProperties", @{
		@"@type" : @"messageProperties",
		@"can_be_replied" : @YES,
	});
	XCTAssertNotNil(props);
	XCTAssertTrue([props[@"can_be_replied"] boolValue]);
}

@end

// vim:ft=objc
