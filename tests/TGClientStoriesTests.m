//
// TGClientStoriesTests.m - the 48 story requests, the feed row, the viewer's
// flattening and the live-story calls.
//
// Each test pins the request shape Telegram expects and the answer a screen
// reads; a request that goes out with a missing id or a wrong story list is a
// screen that lies even when the server says ok.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientStoriesTests : XCTestCase @end

static TGClient *StoriesClient(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c removeAllFileWaiters];
	c.me = @{@"id" : @(1001)};
	c.chats = @[];
	return c;
}

static NSDictionary *decodeStories(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastStoryRequest(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeStories(d)[@"@type"] isEqualToString:type])
			found = decodeStories(d);
	return found;
}

static NSUInteger countStoryRequests(TGClient *c, NSString *type) {
	NSUInteger n = 0;
	for (NSData *d in c.outbox)
		if ([decodeStories(d)[@"@type"] isEqualToString:type])
			n++;
	return n;
}

static void replyStoryRequest(TGClient *c, NSString *type, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox){
		NSDictionary *request = decodeStories(d);
		if ([request[@"@type"] isEqualToString:type] && request[@"@extra"]){
			sent = request;
			break;
		}
	}
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *storyPhotoAnswer(long long storyId, long long chatId) {
	return @{
		@"@type" : @"story",
		@"id" : @(storyId),
		@"poster_chat_id" : @(chatId),
		@"date" : @(1700000000),
		@"is_posted_to_chat_page" : @YES,
		@"can_be_deleted" : @YES,
		@"can_be_edited" : @YES,
		@"can_get_statistics" : @YES,
		@"can_get_interactions" : @YES,
		@"caption" : @{@"text" : @"A caption", @"entities" : @[]},
		@"content" : @{@"@type" : @"storyContentPhoto",
					   @"photo" : @{@"sizes" : @[
							@{@"width" : @1080, @"height" : @1920,
							  @"photo" : @{@"id" : @(555)}}]}},
		@"privacy_settings" : @{@"@type" : @"storyPrivacySettingsEveryone",
								 @"except_user_ids" : @[]},
		@"chosen_reaction_type" : @{@"@type" : @"reactionTypeEmoji",
									 @"emoji" : @"🔥"},
		@"interaction_info" : @{@"view_count" : @(12),
								 @"forward_count" : @(3),
								 @"reaction_count" : @(4)},
	};
}

static NSDictionary *liveStoryAnswer(long long storyId, long long chatId) {
	return @{
		@"@type" : @"story",
		@"id" : @(storyId),
		@"poster_chat_id" : @(chatId),
		@"date" : @(1700000000),
		@"content" : @{@"@type" : @"storyContentLive",
					   @"group_call_id" : @(77),
					   @"is_rtmp_stream" : @YES},
		@"caption" : @{@"text" : @"Live", @"entities" : @[]},
		@"privacy_settings" : @{@"@type" : @"storyPrivacySettingsEveryone",
								 @"except_user_ids" : @[]},
	};
}

static NSDictionary *albumAnswer(long long albumId) {
	return @{@"@type" : @"storyAlbum", @"id" : @(albumId),
			 @"name" : @"Trip",
			 @"photo_icon" : @{@"sizes" : @[
				 @{@"width" : @640, @"height" : @640,
				   @"photo" : @{@"id" : @(900)}}]}};
}

@implementation TGClientStoriesTests

#pragma mark - the feed

- (void)testLoadActiveStories_SendsTheMainStoryList {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c loadActiveStoriesForList:@"main" completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"loadActiveStories");
	XCTAssertEqualObjects(r[@"story_list"][@"@type"], @"storyListMain");
	replyStoryRequest(c, @"loadActiveStories", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testLoadActiveStories_ArchiveAnd404AreNotFailures {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c loadActiveStoriesForList:@"archive" completion:^(BOOL good, NSString *error){ ok = good; }];
	XCTAssertEqualObjects(lastStoryRequest(c, @"loadActiveStories")[@"story_list"][@"@type"],
			@"storyListArchive");
	replyStoryRequest(c, @"loadActiveStories",
			@{@"@type" : @"error", @"code" : @(404), @"message" : @"Not Found"});
	XCTAssertTrue(ok);
}

- (void)testActiveStoryRow_ReadsTheListAndMarksUnread {
	TGClient *c = StoriesClient();
	__block NSDictionary *row = nil;
	[c activeStoryRowForChat:-71 completion:^(NSDictionary *got){ row = got; }];
	replyStoryRequest(c, @"getChatActiveStories",
			@{@"@type" : @"chatActiveStories", @"chat_id" : @(-71),
			  @"list" : @{@"@type" : @"storyListMain"},
			  @"order" : @(50), @"can_be_archived" : @YES,
			  @"max_read_story_id" : @(3),
			  @"stories" : @[@{@"story_id" : @(5), @"date" : @(1700000000),
							   @"is_live" : @NO, @"is_for_close_friends" : @NO},
							 @{@"story_id" : @(4), @"date" : @(1699999999),
							   @"is_live" : @NO, @"is_for_close_friends" : @NO}]});
	XCTAssertEqualObjects(row[@"chatId"], @(-71));
	XCTAssertEqualObjects(row[@"list"], @"main");
	XCTAssertEqualObjects(row[@"order"], @(50));
	XCTAssertTrue([row[@"unread"] boolValue]);
	XCTAssertEqual([(NSArray *)row[@"stories"] count], (NSUInteger)2);
}

- (void)testActiveStoryRows_SendsLoadThenReadsEachChat {
	TGClient *c = StoriesClient();
	__block NSArray *rows = nil;
	[c activeStoryRowsForList:@"main" completion:^(NSArray *got){ rows = got; }];
	XCTAssertEqual(countStoryRequests(c, @"loadActiveStories"), (NSUInteger)1);
	replyStoryRequest(c, @"loadActiveStories", @{@"@type" : @"ok"});
	replyStoryRequest(c, @"getChatActiveStories",
			@{@"@type" : @"chatActiveStories", @"chat_id" : @(1001),
			  @"list" : @{@"@type" : @"storyListMain"}, @"order" : @(9),
			  @"max_read_story_id" : @(0),
			  @"stories" : @[@{@"story_id" : @(2), @"date" : @(1700000000),
							   @"is_live" : @NO, @"is_for_close_friends" : @NO}]});
	XCTAssertEqualObjects(rows.firstObject[@"chatId"], @(1001));
	XCTAssertTrue([rows.firstObject[@"unread"] boolValue]);
}

- (void)testSetActiveStoriesList_SendsTheChatAndTheList {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c setActiveStoriesList:@"archive" forChat:-71
				 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"setChatActiveStoriesList");
	XCTAssertEqualObjects(r[@"chat_id"], @(-71));
	XCTAssertEqualObjects(r[@"story_list"][@"@type"], @"storyListArchive");
	replyStoryRequest(c, @"setChatActiveStoriesList", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetPinnedStories_SendsEveryId {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c setPinnedStoryIds:@[@5, @4] inChat:-71
			  completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"setChatPinnedStories");
	XCTAssertEqualObjects(r[@"chat_id"], @(-71));
	XCTAssertEqualObjects(r[@"story_ids"], (@[@5, @4]));
	replyStoryRequest(c, @"setChatPinnedStories", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testArchivedStoryIds_SendsThePagingAndReturnsIds {
	TGClient *c = StoriesClient();
	__block NSArray *ids = nil;
	[c archivedStoryIdsForChat:-71 fromStoryId:42 limit:10
				   completion:^(NSArray *got, NSString *error){ ids = got; }];
	NSDictionary *r = lastStoryRequest(c, @"getChatArchivedStories");
	XCTAssertEqualObjects(r[@"from_story_id"], @(42));
	XCTAssertEqualObjects(r[@"limit"], @(10));
	replyStoryRequest(c, @"getChatArchivedStories",
			@{@"@type" : @"stories", @"stories" : @[
					@{@"id" : @(42)}, @{@"id" : @(41)}]});
	XCTAssertEqualObjects(ids, (@[@42, @41]));
}

- (void)testStoryById_FlattensTheContentAndTheFlags {
	TGClient *c = StoriesClient();
	__block NSDictionary *story = nil;
	[c story:5 fromChat:-71 completion:^(NSDictionary *got){ story = got; }];
	NSDictionary *r = lastStoryRequest(c, @"getStory");
	XCTAssertEqualObjects(r[@"story_poster_chat_id"], @(-71));
	XCTAssertEqualObjects(r[@"story_id"], @(5));
	replyStoryRequest(c, @"getStory", storyPhotoAnswer(5, -71));
	XCTAssertEqualObjects(story[@"storyId"], @(5));
	XCTAssertEqualObjects(story[@"photoId"], @(555));
	XCTAssertEqualObjects(story[@"caption"], @"A caption");
	XCTAssertEqualObjects(story[@"contentKind"], @"photo");
	XCTAssertEqualObjects(story[@"viewers"], @(12));
	XCTAssertEqualObjects(story[@"chosenReaction"], @"🔥");
	XCTAssertEqualObjects(story[@"privacy"], @"everyone");
	XCTAssertTrue([story[@"isPostedToChatPage"] boolValue]);
}

#pragma mark - viewing

- (void)testOpenStory_SendsBothIds {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c openStory:5 fromChat:-71 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"openStory");
	XCTAssertEqualObjects(r[@"story_poster_chat_id"], @(-71));
	XCTAssertEqualObjects(r[@"story_id"], @(5));
	replyStoryRequest(c, @"openStory", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testCloseStory_SendsBothIds {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c closeStory:5 fromChat:-71 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"closeStory");
	XCTAssertEqualObjects(r[@"story_id"], @(5));
	replyStoryRequest(c, @"closeStory", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testAvailableStoryReactions_SendsTheRowSizeAndReadsTheEmojis {
	TGClient *c = StoriesClient();
	__block NSDictionary *reactions = nil;
	[c storyAvailableReactionsWithCompletion:^(NSDictionary *got){ reactions = got; }];
	NSDictionary *r = lastStoryRequest(c, @"getStoryAvailableReactions");
	XCTAssertEqualObjects(r[@"row_size"], @(25));
	replyStoryRequest(c, @"getStoryAvailableReactions",
			@{@"@type" : @"availableReactions",
			  @"top_reactions" : @[@{@"type" : @{@"@type" : @"reactionTypeEmoji",
												  @"emoji" : @"❤️"}}],
			  @"recent_reactions" : @[],
			  @"popular_reactions" : @[@{@"type" : @{@"@type" : @"reactionTypeEmoji",
													 @"emoji" : @"🔥"}}],
			  @"allow_custom_emoji" : @NO});
	XCTAssertEqualObjects(reactions[@"emojis"], (@[@"❤️"]));
	XCTAssertEqualObjects(reactions[@"popular"], (@[@"🔥"]));
}

- (void)testSetStoryReaction_SendsTheEmoji {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c setStoryReaction:@"🔥" onStory:5 fromChat:-71
			 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"setStoryReaction");
	XCTAssertEqualObjects(r[@"story_id"], @(5));
	XCTAssertEqualObjects(r[@"reaction_type"][@"emoji"], @"🔥");
	replyStoryRequest(c, @"setStoryReaction", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetStoryReaction_NilRemovesItWithANull {
	TGClient *c = StoriesClient();
	[c setStoryReaction:nil onStory:5 fromChat:-71 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"setStoryReaction");
	XCTAssertEqual(r[@"reaction_type"], [NSNull null]);
}

#pragma mark - posting and editing

- (void)testCanPostStory_ReadsTheOkAndTheRefusal {
	TGClient *c = StoriesClient();
	__block NSDictionary *answer = nil;
	[c canPostStoryInChat:-71 completion:^(NSDictionary *got){ answer = got; }];
	XCTAssertEqualObjects(lastStoryRequest(c, @"canPostStory")[@"chat_id"], @(-71));
	replyStoryRequest(c, @"canPostStory",
			@{@"@type" : @"canPostStoryResultWeeklyLimitExceeded", @"retry_after" : @(99)});
	XCTAssertFalse([answer[@"ok"] boolValue]);
	XCTAssertEqualObjects(answer[@"retryAfter"], @(99));
	XCTAssertTrue([answer[@"reason"] length] > 0);
}

- (void)testChatsToPostStories_ReadsTheIdsThenEachChat {
	TGClient *c = StoriesClient();
	__block NSArray *chats = nil;
	[c chatsToPostStoriesWithCompletion:^(NSArray *got){ chats = got; }];
	replyStoryRequest(c, @"getChatsToPostStories",
			@{@"@type" : @"chats", @"total_count" : @(1), @"chat_ids" : @[@(-100)]});
	replyStoryRequest(c, @"getChat",
			@{@"@type" : @"chat", @"id" : @(-100), @"title" : @"Channel",
			  @"type" : @{@"@type" : @"chatTypeSupergroup",
						  @"supergroup_id" : @(-200), @"is_channel" : @YES}});
	XCTAssertEqualObjects(chats.firstObject[@"title"], @"Channel");
	XCTAssertTrue([chats.firstObject[@"isChannel"] boolValue]);
}

- (void)testPostStory_SendsTheContentPrivacyAndPeriod {
	TGClient *c = StoriesClient();
	__block NSDictionary *story = nil;
	[c postStoryToChat:-71 path:@"/tmp/story.jpg" isVideo:NO duration:0
			   caption:@"Hello" privacy:@"selected" userIds:@[@5]
		  activePeriod:172800 postedToChatPage:YES protectContent:YES
			  albumIds:@[@3] completion:^(NSDictionary *got, NSString *error){
		story = got;
	}];
	NSDictionary *r = lastStoryRequest(c, @"postStory");
	XCTAssertEqualObjects(r[@"chat_id"], @(-71));
	XCTAssertEqualObjects(r[@"content"][@"@type"], @"inputStoryContentPhoto");
	XCTAssertEqualObjects(r[@"content"][@"photo"][@"path"], @"/tmp/story.jpg");
	XCTAssertEqualObjects(r[@"caption"][@"text"], @"Hello");
	XCTAssertEqualObjects(r[@"privacy_settings"][@"@type"],
			@"storyPrivacySettingsSelectedUsers");
	XCTAssertEqualObjects(r[@"privacy_settings"][@"user_ids"], (@[@5]));
	XCTAssertEqualObjects(r[@"active_period"], @(172800));
	XCTAssertEqualObjects(r[@"album_ids"], (@[@3]));
	XCTAssertTrue([r[@"is_posted_to_chat_page"] boolValue]);
	replyStoryRequest(c, @"postStory", storyPhotoAnswer(5, -71));
	XCTAssertEqualObjects(story[@"storyId"], @(5));
}

- (void)testPostStory_AnEmptyPathSendsNothing {
	TGClient *c = StoriesClient();
	__block NSString *error = nil;
	[c postStoryToChat:-71 path:@"" isVideo:NO duration:0 caption:nil
			   privacy:@"everyone" userIds:@[] activePeriod:86400
	  postedToChatPage:NO protectContent:NO albumIds:@[]
			completion:^(NSDictionary *story, NSString *why){ error = why; }];
	XCTAssertEqual(countStoryRequests(c, @"postStory"), (NSUInteger)0);
	XCTAssertNotNil(error);
}

- (void)testEditStory_KeepsContentWhenOnlyTheCaptionChanges {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c editStory:5 fromChat:-71 path:nil isVideo:NO duration:0 caption:@"New"
	  completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"editStory");
	XCTAssertEqual(r[@"content"], [NSNull null]);
	XCTAssertEqualObjects(r[@"caption"][@"text"], @"New");
	replyStoryRequest(c, @"editStory", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testEditStoryCover_SendsTheTimestamp {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c editStoryCover:5 fromChat:-71 coverTimestamp:2.5
		  completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"editStoryCover");
	XCTAssertEqualObjects(r[@"cover_frame_timestamp"], @(2.5));
	replyStoryRequest(c, @"editStoryCover", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeleteStory_SendsBothIds {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c deleteStory:5 fromChat:-71 completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"deleteStory");
	XCTAssertEqualObjects(r[@"story_id"], @(5));
	replyStoryRequest(c, @"deleteStory", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testToggleStoryPostedToChatPage_SendsTheFlag {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c toggleStory:5 fromChat:-71 postedToChatPage:NO
		completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"toggleStoryIsPostedToChatPage");
	XCTAssertFalse([r[@"is_posted_to_chat_page"] boolValue]);
	replyStoryRequest(c, @"toggleStoryIsPostedToChatPage", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetStoryPrivacySettings_SendsTheSelectedUsers {
	TGClient *c = StoriesClient();
	__block BOOL ok = NO;
	[c setStoryPrivacySettings:5 privacy:@"selected" userIds:@[@7, @8]
					completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastStoryRequest(c, @"setStoryPrivacySettings");
	XCTAssertEqualObjects(r[@"story_id"], @(5));
	XCTAssertEqualObjects(r[@"privacy_settings"][@"user_ids"], (@[@7, @8]));
	replyStoryRequest(c, @"setStoryPrivacySettings", @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testDeleteBusinessStory_IsTheBusinessRequest {
	TGClient *c = StoriesClient();
	__block NSString *error = nil;
	[c deleteBusinessStory:5 fromChat:-71 completion:^(BOOL ok, NSString *why){ error = why; }];
	XCTAssertEqual(countStoryRequests(c, @"deleteBusinessStory"), (NSUInteger)1);
	replyStoryRequest(c, @"deleteBusinessStory",
			@{@"@type" : @"error", @"code" : @(400),
			  @"message" : @"This method is not available for user accounts"});
	XCTAssertEqualObjects(error, @"This method is not available for user accounts");
}

- (void)testEditBusinessStory_SendsTheBusinessRequest {
	TGClient *c = StoriesClient();
	[c editBusinessStory:5 fromChat:-71 path:nil isVideo:NO duration:0
				  caption:@"Business" completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"editBusinessStory");
	XCTAssertEqualObjects(r[@"caption"][@"text"], @"Business");
}

#pragma mark - albums

- (void)testStoryAlbums_FlattenTheIconsAndNames {
	TGClient *c = StoriesClient();
	__block NSArray *albums = nil;
	[c storyAlbumsForChat:-71 completion:^(NSArray *got){ albums = got; }];
	replyStoryRequest(c, @"getChatStoryAlbums",
			@{@"@type" : @"storyAlbums",
			  @"albums" : @[@{@"@type" : @"storyAlbum", @"id" : @(9),
							  @"name" : @"Trip",
							  @"photo_icon" : @{@"sizes" : @[
								  @{@"width" : @100, @"height" : @100,
									@"photo" : @{@"id" : @(333)}}]}}]});
	XCTAssertEqualObjects(albums.firstObject[@"name"], @"Trip");
	XCTAssertEqualObjects(albums.firstObject[@"photoFileId"], @(333));
}

- (void)testCreateStoryAlbum_SendsTheNameAndStories {
	TGClient *c = StoriesClient();
	__block NSDictionary *album = nil;
	[c createStoryAlbumNamed:@"Trip" inChat:-71 storyIds:@[@5]
				   completion:^(NSDictionary *got, NSString *error){ album = got; }];
	NSDictionary *r = lastStoryRequest(c, @"createStoryAlbum");
	XCTAssertEqualObjects(r[@"name"], @"Trip");
	XCTAssertEqualObjects(r[@"story_ids"], (@[@5]));
	replyStoryRequest(c, @"createStoryAlbum", albumAnswer(9));
	XCTAssertEqualObjects(album[@"albumId"], @(9));
}

- (void)testDeleteStoryAlbum_SendsTheAlbumAndChat {
	TGClient *c = StoriesClient();
	[c deleteStoryAlbum:9 inChat:-71 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"deleteStoryAlbum");
	XCTAssertEqualObjects(r[@"chat_id"], @(-71));
	XCTAssertEqualObjects(r[@"story_album_id"], @(9));
}

- (void)testSetStoryAlbumName_ReadsTheChangedAlbum {
	TGClient *c = StoriesClient();
	__block NSDictionary *album = nil;
	[c setStoryAlbumName:@"New" albumId:9 inChat:-71
			   completion:^(NSDictionary *got, NSString *error){ album = got; }];
	NSDictionary *r = lastStoryRequest(c, @"setStoryAlbumName");
	XCTAssertEqualObjects(r[@"name"], @"New");
	replyStoryRequest(c, @"setStoryAlbumName", albumAnswer(9));
	XCTAssertEqualObjects(album[@"name"], @"Trip");
}

- (void)testReorderStoryAlbums_SendsTheWholeOrder {
	TGClient *c = StoriesClient();
	[c reorderStoryAlbums:@[@9, @8] inChat:-71 completion:nil];
	XCTAssertEqualObjects(lastStoryRequest(c, @"reorderStoryAlbums")[@"story_album_ids"],
			(@[@9, @8]));
}

- (void)testStoriesInAlbum_FlattensTheStories {
	TGClient *c = StoriesClient();
	__block NSArray *stories = nil;
	[c storiesInAlbum:9 inChat:-71 offset:0 limit:20
			completion:^(NSArray *got, NSString *error){ stories = got; }];
	NSDictionary *r = lastStoryRequest(c, @"getStoryAlbumStories");
	XCTAssertEqualObjects(r[@"story_album_id"], @(9));
	replyStoryRequest(c, @"getStoryAlbumStories",
			@{@"@type" : @"stories", @"stories" : @[storyPhotoAnswer(5, -71)]});
	XCTAssertEqualObjects(stories.firstObject[@"storyId"], @(5));
}

- (void)testAddStoriesToAlbum_SendsTheIds {
	TGClient *c = StoriesClient();
	[c addStories:@[@5] toAlbum:9 inChat:-71 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"addStoryAlbumStories");
	XCTAssertEqualObjects(r[@"story_ids"], (@[@5]));
}

- (void)testRemoveStoriesFromAlbum_SendsTheIds {
	TGClient *c = StoriesClient();
	[c removeStories:@[@5] fromAlbum:9 inChat:-71 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"removeStoryAlbumStories");
	XCTAssertEqualObjects(r[@"story_ids"], (@[@5]));
}

- (void)testReorderStoriesInAlbum_SendsTheOrder {
	TGClient *c = StoriesClient();
	[c reorderStories:@[@5, @4] inAlbum:9 inChat:-71 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"reorderStoryAlbumStories");
	XCTAssertEqualObjects(r[@"story_ids"], (@[@5, @4]));
}

#pragma mark - interactions and statistics

- (void)testStoryInteractions_SendsTheFiltersAndRows {
	TGClient *c = StoriesClient();
	__block NSDictionary *page = nil;
	[c storyInteractionsForStory:5 query:@"ann" onlyContacts:YES
					preferForwards:YES preferWithReaction:NO offset:@"" limit:20
						 completion:^(NSDictionary *got, NSString *error){ page = got; }];
	NSDictionary *r = lastStoryRequest(c, @"getStoryInteractions");
	XCTAssertEqualObjects(r[@"query"], @"ann");
	XCTAssertTrue([r[@"only_contacts"] boolValue]);
	XCTAssertTrue([r[@"prefer_forwards"] boolValue]);
	replyStoryRequest(c, @"getStoryInteractions",
			@{@"@type" : @"storyInteractions", @"total_count" : @(1),
			  @"total_forward_count" : @(0), @"total_reaction_count" : @(1),
			  @"next_offset" : @"", @"interactions" : @[
				  @{@"actor_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(8)},
					@"interaction_date" : @(1700000000),
					@"type" : @{@"@type" : @"storyInteractionTypeView",
								@"chosen_reaction_type" : @{@"@type" : @"reactionTypeEmoji",
															@"emoji" : @"❤️"}}}]});
	XCTAssertEqualObjects(page[@"interactions"][0][@"kind"], @"view");
	XCTAssertEqualObjects(page[@"interactions"][0][@"reaction"], @"❤️");
}

- (void)testChatStoryInteractions_SendsANullReactionForAll {
	TGClient *c = StoriesClient();
	[c chatStoryInteractionsForStory:5 fromChat:-71 reactionEmoji:nil
					  preferForwards:NO offset:@"" limit:20 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"getChatStoryInteractions");
	XCTAssertEqual(r[@"reaction_type"], [NSNull null]);
	XCTAssertEqualObjects(r[@"story_poster_chat_id"], @(-71));
}

- (void)testStoryPublicForwards_ReadsMessagesAndReposts {
	TGClient *c = StoriesClient();
	__block NSDictionary *page = nil;
	[c storyPublicForwards:5 fromChat:-71 offset:@"" limit:20
				completion:^(NSDictionary *got, NSString *error){ page = got; }];
	replyStoryRequest(c, @"getStoryPublicForwards",
			@{@"@type" : @"publicForwards", @"total_count" : @(2),
			  @"next_offset" : @"", @"forwards" : @[
				  @{@"@type" : @"publicForwardMessage",
					@"message" : @{@"chat_id" : @(-72), @"id" : @(9),
								   @"date" : @(1700000000),
								   @"content" : @{@"@type" : @"messageText",
												  @"text" : @{@"text" : @"Forwarded",
															  @"entities" : @[]}}}},
				  @{@"@type" : @"publicForwardStory",
					@"story" : storyPhotoAnswer(5, -73)}]});
	XCTAssertEqual([(NSArray *)page[@"forwards"] count], (NSUInteger)2);
	XCTAssertEqualObjects(page[@"forwards"][0][@"kind"], @"message");
	XCTAssertEqualObjects(page[@"forwards"][1][@"kind"], @"story");
}

- (void)testStoryStatistics_FlattensTheGraphPoints {
	TGClient *c = StoriesClient();
	__block NSDictionary *stats = nil;
	[c storyStatistics:5 fromChat:-71 isDark:NO
			 completion:^(NSDictionary *got, NSString *error){ stats = got; }];
	replyStoryRequest(c, @"getStoryStatistics",
			@{@"@type" : @"storyStatistics",
			  @"story_interaction_graph" : @{@"@type" : @"statisticalGraphData",
				  @"json_data" : @"{\"points\":[{\"x\":1,\"y\":5},{\"x\":2,\"y\":9}]}"},
			  @"story_reaction_graph" : @{@"@type" : @"statisticalGraphAsync",
				  @"token" : @"tok"}});
	XCTAssertEqualObjects(stats[@"interaction"][@"kind"], @"data");
	XCTAssertTrue([(NSArray *)stats[@"interaction"][@"lines"] count] > 0);
	XCTAssertEqualObjects(stats[@"reaction"][@"kind"], @"async");
}

- (void)testReportStory_FirstAnswerIsTheOptionList {
	TGClient *c = StoriesClient();
	__block NSDictionary *result = nil;
	[c reportStory:5 fromChat:-71 optionId:@"" text:@""
		completion:^(NSDictionary *got, NSString *error){ result = got; }];
	NSDictionary *r = lastStoryRequest(c, @"reportStory");
	XCTAssertEqualObjects(r[@"option_id"], @"");
	replyStoryRequest(c, @"reportStory",
			@{@"@type" : @"reportStoryResultOptionRequired", @"title" : @"Report",
			  @"options" : @[@{@"id" : @"b3B0", @"text" : @"Spam"}]});
	XCTAssertEqualObjects(result[@"state"], @"options");
	XCTAssertEqualObjects(result[@"options"][0][@"text"], @"Spam");
}

- (void)testReportStory_ChosenOptionAndTextReachTheServer {
	TGClient *c = StoriesClient();
	[c reportStory:5 fromChat:-71 optionId:@"b3B0" text:@"details" completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"reportStory");
	XCTAssertEqualObjects(r[@"option_id"], @"b3B0");
	XCTAssertEqualObjects(r[@"text"], @"details");
}

#pragma mark - notifications

- (void)testStoryNotificationExceptions_ReadsEachChat {
	TGClient *c = StoriesClient();
	__block NSArray *rows = nil;
	[c storyNotificationExceptionsWithCompletion:^(NSArray *got){ rows = got; }];
	replyStoryRequest(c, @"getStoryNotificationSettingsExceptions",
			@{@"@type" : @"chats", @"total_count" : @(1), @"chat_ids" : @[@(-71)]});
	replyStoryRequest(c, @"getChat",
			@{@"@type" : @"chat", @"id" : @(-71), @"title" : @"Friend",
			  @"notification_settings" : @{@"mute_stories" : @YES,
											 @"mute_for" : @(3600)}});
	XCTAssertEqualObjects(rows.firstObject[@"title"], @"Friend");
	XCTAssertTrue([rows.firstObject[@"muteStories"] boolValue]);
}

#pragma mark - public discovery

- (void)testSearchPublicStoriesByTag_SendsTheTagOffsetAndLimit {
	TGClient *c = StoriesClient();
	__block NSDictionary *page = nil;
	[c searchPublicStoriesByTag:@"#kyiv" offset:@"" limit:20
					 completion:^(NSDictionary *got, NSString *error){ page = got; }];
	NSDictionary *r = lastStoryRequest(c, @"searchPublicStoriesByTag");
	XCTAssertEqualObjects(r[@"story_tag"], @"kyiv");
	replyStoryRequest(c, @"searchPublicStoriesByTag",
			@{@"@type" : @"foundStories", @"total_count" : @(1), @"next_offset" : @"",
			  @"stories" : @[storyPhotoAnswer(5, -71)]});
	XCTAssertEqualObjects(page[@"stories"][0][@"storyId"], @(5));
}

- (void)testSearchPublicStoriesByLocation_SendsTheAddressFields {
	TGClient *c = StoriesClient();
	[c searchPublicStoriesByLocation:@{@"countryCode" : @"UA", @"state" : @"",
									   @"city" : @"Kyiv", @"street" : @""}
							  offset:@"" limit:20 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"searchPublicStoriesByLocation");
	XCTAssertEqualObjects(r[@"address"][@"country_code"], @"UA");
	XCTAssertEqualObjects(r[@"address"][@"city"], @"Kyiv");
}

- (void)testSearchPublicStoriesByVenue_SendsProviderAndId {
	TGClient *c = StoriesClient();
	[c searchPublicStoriesByVenue:@"foursquare" venueId:@"123" offset:@"" limit:20
					   completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"searchPublicStoriesByVenue");
	XCTAssertEqualObjects(r[@"venue_provider"], @"foursquare");
	XCTAssertEqualObjects(r[@"venue_id"], @"123");
}

#pragma mark - stealth

- (void)testActivateStealthMode_SendsAndKeepsTheServerWord {
	TGClient *c = StoriesClient();
	__block NSString *error = nil;
	[c activateStoryStealthModeWithCompletion:^(BOOL ok, NSString *why){ error = why; }];
	XCTAssertEqual(countStoryRequests(c, @"activateStoryStealthMode"), (NSUInteger)1);
	replyStoryRequest(c, @"activateStoryStealthMode",
			@{@"@type" : @"error", @"code" : @(400),
			  @"message" : @"Premium is required"});
	XCTAssertEqualObjects(error, @"Premium is required");
}

#pragma mark - live stories

- (void)testStartLiveStory_SendsTheShapeAndReadsTheGroupCall {
	TGClient *c = StoriesClient();
	__block NSDictionary *answer = nil;
	[c startLiveStoryInChat:-71 privacy:@"everyone" userIds:@[]
			 protectContent:YES rtmp:YES enableMessages:YES
			  paidMessageStars:5 completion:^(NSDictionary *got){ answer = got; }];
	NSDictionary *r = lastStoryRequest(c, @"startLiveStory");
	XCTAssertTrue([r[@"is_rtmp_stream"] boolValue]);
	XCTAssertTrue([r[@"enable_messages"] boolValue]);
	XCTAssertEqualObjects(r[@"paid_message_star_count"], @(5));
	replyStoryRequest(c, @"startLiveStory",
			@{@"@type" : @"startLiveStoryResultOk",
			  @"story" : liveStoryAnswer(5, -71)});
	XCTAssertTrue([answer[@"ok"] boolValue]);
	XCTAssertEqualObjects(answer[@"groupCallId"], @(77));
	XCTAssertTrue([answer[@"story"][@"isLive"] boolValue]);
}

- (void)testJoinLiveStory_SendsTheCallAndReturnsThePayload {
	TGClient *c = StoriesClient();
	__block NSString *payload = nil;
	[c joinLiveStoryCall:77 completion:^(NSString *text, NSString *error){ payload = text; }];
	NSDictionary *r = lastStoryRequest(c, @"joinLiveStory");
	XCTAssertEqualObjects(r[@"group_call_id"], @(77));
	XCTAssertEqualObjects(r[@"join_parameters"][@"@type"],
			@"groupCallJoinParameters");
	replyStoryRequest(c, @"joinLiveStory",
			@{@"@type" : @"text", @"text" : @"join-payload"});
	XCTAssertEqualObjects(payload, @"join-payload");
}

- (void)testLiveStoryStreamer_FlattensTheParticipant {
	TGClient *c = StoriesClient();
	__block NSDictionary *streamer = nil;
	[c liveStoryStreamerForCall:77 completion:^(NSDictionary *got, NSString *error){
		streamer = got;
	}];
	replyStoryRequest(c, @"getLiveStoryStreamer",
			@{@"@type" : @"groupCallParticipant",
			  @"participant_id" : @{@"@type" : @"messageSenderUser",
									@"user_id" : @(8)},
			  @"is_speaking" : @YES, @"bio" : @"Streaming"});
	XCTAssertEqualObjects(streamer[@"id"], @(8));
	XCTAssertTrue([streamer[@"isSpeaking"] boolValue]);
	XCTAssertEqualObjects(streamer[@"bio"], @"Streaming");
}

- (void)testLiveStoryRtmpUrl_ReadsUrlAndKey {
	TGClient *c = StoriesClient();
	__block NSDictionary *url = nil;
	[c liveStoryRtmpUrlForChat:-71 completion:^(NSDictionary *got, NSString *error){
		url = got;
	}];
	XCTAssertEqualObjects(lastStoryRequest(c, @"getLiveStoryRtmpUrl")[@"chat_id"], @(-71));
	replyStoryRequest(c, @"getLiveStoryRtmpUrl",
			@{@"@type" : @"rtmpUrl", @"url" : @"rtmp://a", @"stream_key" : @"key"});
	XCTAssertEqualObjects(url[@"url"], @"rtmp://a");
	XCTAssertEqualObjects(url[@"streamKey"], @"key");
}

- (void)testReplaceLiveStoryRtmpUrl_IsItsOwnRequest {
	TGClient *c = StoriesClient();
	[c replaceLiveStoryRtmpUrlForChat:-71 completion:nil];
	XCTAssertEqual(countStoryRequests(c, @"replaceLiveStoryRtmpUrl"), (NSUInteger)1);
}

- (void)testLiveStoryMessageSenders_FlattenPremiumAndSender {
	TGClient *c = StoriesClient();
	__block NSArray *senders = nil;
	[c liveStoryAvailableMessageSendersForCall:77
									completion:^(NSArray *got, NSString *error){
		senders = got;
	}];
	replyStoryRequest(c, @"getLiveStoryAvailableMessageSenders",
			@{@"@type" : @"chatMessageSenders", @"senders" : @[
					@{@"sender" : @{@"@type" : @"messageSenderUser", @"user_id" : @(8)},
					  @"needs_premium" : @YES}]});
	XCTAssertEqualObjects(senders.firstObject[@"id"], @(8));
	XCTAssertTrue([senders.firstObject[@"needsPremium"] boolValue]);
}

- (void)testSetLiveStoryMessageSender_BuildsTheSenderObject {
	TGClient *c = StoriesClient();
	[c setLiveStoryMessageSender:@{@"kind" : @"chat", @"id" : @(-72)}
						 forCall:77 completion:nil];
	NSDictionary *r = lastStoryRequest(c, @"setLiveStoryMessageSender");
	XCTAssertEqualObjects(r[@"message_sender_id"][@"@type"], @"messageSenderChat");
	XCTAssertEqualObjects(r[@"message_sender_id"][@"chat_id"], @(-72));
}

- (void)testLiveStoryTopDonors_ReadsTheTotalAndRows {
	TGClient *c = StoriesClient();
	__block NSDictionary *donors = nil;
	[c liveStoryTopDonorsForCall:77 completion:^(NSDictionary *got, NSString *error){
		donors = got;
	}];
	replyStoryRequest(c, @"getLiveStoryTopDonors",
			@{@"@type" : @"liveStoryDonors", @"total_star_count" : @(30),
			  @"top_donors" : @[
				  @{@"sender_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(8)},
					@"star_count" : @(20), @"is_top" : @YES, @"is_me" : @NO,
					@"is_anonymous" : @NO}]});
	XCTAssertEqualObjects(donors[@"totalStarCount"], @(30));
	XCTAssertEqualObjects(donors[@"donors"][0][@"stars"], @(20));
}

- (void)testPendingLiveStoryReactions_SendAddCommitAndRemove {
	TGClient *c = StoriesClient();
	[c addPendingLiveStoryReactionInCall:77 stars:2 completion:nil];
	NSDictionary *add = lastStoryRequest(c, @"addPendingLiveStoryReaction");
	XCTAssertEqualObjects(add[@"group_call_id"], @(77));
	XCTAssertEqualObjects(add[@"star_count"], @(2));
	[c commitPendingLiveStoryReactionsInCall:77 completion:nil];
	[c removePendingLiveStoryReactionsInCall:77 completion:nil];
	XCTAssertEqual(countStoryRequests(c, @"commitPendingLiveStoryReactions"), (NSUInteger)1);
	XCTAssertEqual(countStoryRequests(c, @"removePendingLiveStoryReactions"), (NSUInteger)1);
}

- (void)testStoryRowProbes_AskAboutAScreenfulOnTheOldestPhones {
	XCTAssertEqual(TGStoryRowProbeLimit(TGDeviceTierVintage), (NSUInteger)12);
	XCTAssertEqual(TGStoryRowProbeLimit(TGDeviceTierLegacy), (NSUInteger)60);
	XCTAssertEqual(TGStoryRowProbeLimit(TGDeviceTierFull), (NSUInteger)60);
}

@end
