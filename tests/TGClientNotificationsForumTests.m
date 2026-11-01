// TGClientNotificationsForumTests.m - saved notification sounds, TDLib's
// local notification list, and the seven forum-topic calls the Topic Info
// and topics menu make.
//
// The screens are UIKit and are checked on a device. What is pinned here is
// that each row has a request behind it, that the answer lands in the field
// the row draws, and that a removal changes the client's copy only after
// Telegram says yes.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientNotificationsForumTests : XCTestCase @end

static TGClient *NF(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	c.activeNotificationGroupsValue = nil;
	return c;
}

static NSDictionary *decodeNF(NSData *data) {
	NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastNF(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *data in c.outbox){
		NSDictionary *request = decodeNF(data);
		if ([request[@"@type"] isEqualToString:type])
			found = request;
	}
	return found;
}

static NSDictionary *lastRequestedNF(TGClient *c) {
	NSDictionary *sent = nil;
	for (NSData *data in c.outbox)
		if (decodeNF(data)[@"@extra"])
			sent = decodeNF(data);
	return sent;
}

static void answerNF(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = lastRequestedNF(c);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainNF(NSDictionary *object) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:object options:0 error:nil]
			options:0 error:nil];
}

static NSDictionary *soundNF(int64_t soundId, NSString *title) {
	return @{@"@type" : @"notificationSound",
			 @"id" : @(soundId),
			 @"duration" : @(2),
			 @"date" : @(1700000000),
			 @"title" : title ?: @"",
			 @"data" : @"recorded",
			 @"sound" : @{@"@type" : @"file", @"id" : @(900 + soundId),
						  @"size" : @(4096),
						  @"expected_size" : @(4096)}};
}

static NSDictionary *messageNF(NSString *text) {
	return @{@"@type" : @"message", @"id" : @(1), @"date" : @(1700000000),
			 @"content" : @{@"@type" : @"messageText",
				 @"text" : @{@"@type" : @"formattedText", @"text" : text}}};
}

static NSDictionary *notificationNF(int32_t notificationId, NSString *text) {
	return @{@"@type" : @"notification",
			 @"id" : @(notificationId),
			 @"date" : @(1700000000),
			 @"is_silent" : @NO,
			 @"type" : @{@"@type" : @"notificationTypeNewMessage",
						 @"show_preview" : @YES,
						 @"message" : messageNF(text)}};
}

static NSDictionary *groupNF(int32_t groupId, int64_t chatId,
							 NSArray *notifications) {
	return @{@"@type" : @"notificationGroup",
			 @"id" : @(groupId),
			 @"type" : @{@"@type" : @"notificationGroupTypeMessages"},
			 @"chat_id" : @(chatId),
			 @"total_count" : @(notifications.count),
			 @"notifications" : notifications};
}

static NSDictionary *topicNF(int64_t chatId, int32_t topicId, NSString *name) {
	return @{@"@type" : @"forumTopic",
			 @"info" : @{@"@type" : @"forumTopicInfo",
				 @"chat_id" : @(chatId),
				 @"forum_topic_id" : @(topicId),
				 @"name" : name ?: @"",
				 @"icon" : @{@"@type" : @"forumTopicIcon",
							 @"color" : @(0x6FB9F0),
							 @"custom_emoji_id" : @(501)},
				 @"creation_date" : @(1690000000),
				 @"creator_id" : @{@"@type" : @"messageSenderUser",
								   @"user_id" : @(44)},
				 @"is_general" : @YES,
				 @"is_outgoing" : @NO,
				 @"is_closed" : @NO,
				 @"is_hidden" : @NO,
				 @"is_name_implicit" : @NO},
			 @"last_message" : messageNF(@"hello"),
			 @"order" : @(12),
			 @"is_pinned" : @YES,
			 @"unread_count" : @(4),
			 @"unread_mention_count" : @(2),
			 @"unread_reaction_count" : @(1),
			 @"unread_poll_vote_count" : @(3),
			 @"notification_settings" : @{@"@type" : @"chatNotificationSettings",
				 @"use_default_mute_for" : @NO,
				 @"mute_for" : @(3600),
				 @"use_default_sound" : @YES,
				 @"sound_id" : @(0),
				 @"use_default_show_preview" : @NO,
				 @"show_preview" : @NO}};
}

@implementation TGClientNotificationsForumTests

#pragma mark - saved sounds

- (void)testSavedNotificationSounds_ReadsTheList {
	TGClient *c = NF();
	__block NSArray *got = nil;
	[c savedNotificationSoundsWithCompletion:^(NSArray *sounds){ got = sounds; }];

	XCTAssertNotNil(lastNF(c, @"getSavedNotificationSounds"));
	answerNF(c, plainNF(@{@"@type" : @"notificationSounds",
		@"notification_sounds" : @[soundNF(11, @"Ding"), soundNF(12, @"Bell")]}));

	XCTAssertEqual(got.count, 2);
	XCTAssertEqualObjects(got[0][@"id"], @(11));
	XCTAssertEqualObjects(got[0][@"title"], @"Ding");
	XCTAssertEqualObjects(got[0][@"duration"], @(2));
	XCTAssertEqualObjects(got[0][@"fileId"], @(911));
	XCTAssertEqualObjects(got[0][@"size"], @(4096));
	XCTAssertEqualObjects(got[0][@"data"], @"recorded");
}

- (void)testSavedNotificationSounds_AnErrorReadsAsNoCustomSounds {
	TGClient *c = NF();
	__block NSArray *got = nil;
	[c savedNotificationSoundsWithCompletion:^(NSArray *sounds){ got = sounds; }];
	answerNF(c, @{@"@type" : @"error", @"code" : @(500),
				  @"message" : @"Internal Server Error"});
	XCTAssertEqual(got.count, 0);
}

- (void)testSavedNotificationSound_ReadsOneById {
	TGClient *c = NF();
	__block NSDictionary *got = nil;
	[c savedNotificationSound:12 completion:^(NSDictionary *sound){ got = sound; }];

	XCTAssertEqualObjects(lastNF(c, @"getSavedNotificationSound")[@"notification_sound_id"],
						   @(12));
	answerNF(c, plainNF(soundNF(12, @"Bell")));
	XCTAssertEqualObjects(got[@"title"], @"Bell");
}

- (void)testSavedNotificationSound_A404IsNil {
	TGClient *c = NF();
	__block NSDictionary *got = @{};
	[c savedNotificationSound:99 completion:^(NSDictionary *sound){ got = sound; }];
	answerNF(c, @{@"@type" : @"error", @"code" : @(404),
				  @"message" : @"Not Found"});
	XCTAssertNil(got);
}

- (void)testAddSavedNotificationSound_SendsTheLocalFileAndReadsTheAnswer {
	TGClient *c = NF();
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"tg-notification-test.mp3"];
	[[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data]
										 attributes:nil];
	__block NSDictionary *got = nil;
	__block NSString *gotError = nil;
	[c addSavedNotificationSoundAtPath:path
							completion:^(NSDictionary *sound, NSString *error){
		got = sound;
		gotError = error;
	}];

	NSDictionary *request = lastNF(c, @"addSavedNotificationSound");
	XCTAssertEqualObjects(request[@"sound"][@"@type"], @"inputFileLocal");
	XCTAssertEqualObjects(request[@"sound"][@"path"], path);
	answerNF(c, plainNF(soundNF(21, @"Mine")));
	XCTAssertNil(gotError);
	XCTAssertEqualObjects(got[@"id"], @(21));
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void)testAddSavedNotificationSound_MissingFileDoesNotAskTelegram {
	TGClient *c = NF();
	__block NSString *gotError = nil;
	[c addSavedNotificationSoundAtPath:@"/no/such/tg.mp3"
							completion:^(NSDictionary *sound, NSString *error){
		gotError = error;
	}];
	XCTAssertNil(lastNF(c, @"addSavedNotificationSound"));
	XCTAssertTrue(gotError.length > 0);
}

- (void)testAddSavedNotificationSound_ServerRefusalKeepsItsSentence {
	TGClient *c = NF();
	NSString *path = [NSTemporaryDirectory()
			stringByAppendingPathComponent:@"tg-notification-refused.mp3"];
	[[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data]
										 attributes:nil];
	__block NSString *gotError = nil;
	[c addSavedNotificationSoundAtPath:path
							completion:^(NSDictionary *sound, NSString *error){
		gotError = error;
	}];
	answerNF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Sound is too long"});
	XCTAssertEqualObjects(gotError, @"Sound is too long");
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void)testRemoveSavedNotificationSound_SendsTheId {
	TGClient *c = NF();
	__block BOOL ok = NO;
	__block NSString *gotError = nil;
	[c removeSavedNotificationSound:11 completion:^(BOOL done, NSString *error){
		ok = done;
		gotError = error;
	}];
	XCTAssertEqualObjects(lastNF(c, @"removeSavedNotificationSound")[@"notification_sound_id"],
						   @(11));
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertNil(gotError);
}

- (void)testRemoveSavedNotificationSound_RefusalIsReported {
	TGClient *c = NF();
	__block BOOL ok = YES;
	__block NSString *gotError = nil;
	[c removeSavedNotificationSound:11 completion:^(BOOL done, NSString *error){
		ok = done;
		gotError = error;
	}];
	answerNF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Sound is in use"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(gotError, @"Sound is in use");
}

#pragma mark - active notifications

- (void)testActiveNotifications_FlattenGroupsAndNameTheChat {
	TGClient *c = NF();
	c.chatsById[@(77)] = [@{@"title" : @"Design"} mutableCopy];
	[c handleUpdate:plainNF(@{@"@type" : @"updateActiveNotifications",
		@"groups" : @[groupNF(7, 77, @[notificationNF(9, @"half a sentence")])]})];

	NSArray *groups = c.activeNotificationGroups;
	XCTAssertEqual(groups.count, 1);
	XCTAssertEqualObjects(groups[0][@"id"], @(7));
	XCTAssertEqualObjects(groups[0][@"chatTitle"], @"Design");
	XCTAssertEqualObjects(groups[0][@"type"], @"notificationGroupTypeMessages");
	XCTAssertEqualObjects(groups[0][@"totalCount"], @(1));
	NSArray *rows = groups[0][@"notifications"];
	XCTAssertEqual(rows.count, 1);
	XCTAssertEqualObjects(rows[0][@"text"], @"half a sentence");
	XCTAssertEqualObjects(rows[0][@"kind"], @"notificationTypeNewMessage");
}

- (void)testNotificationGroup_IncrementalAddAndRemoveKeepsTheListStraight {
	TGClient *c = NF();
	[c handleUpdate:plainNF(@{@"@type" : @"updateActiveNotifications",
		@"groups" : @[groupNF(7, 77, @[notificationNF(9, @"old")])]})];
	[c handleUpdate:plainNF(@{@"@type" : @"updateNotificationGroup",
		@"id" : @(7),
		@"type" : @{@"@type" : @"notificationGroupTypeMessages"},
		@"chat_id" : @(77),
		@"total_count" : @(1),
		@"added_notifications" : @[notificationNF(10, @"new")],
		@"removed_notification_ids" : @[@(9)]})];

	NSArray *rows = c.activeNotificationGroups[0][@"notifications"];
	XCTAssertEqual(rows.count, 1);
	XCTAssertEqualObjects(rows[0][@"id"], @(10));
	XCTAssertEqualObjects(rows[0][@"text"], @"new");
}

- (void)testNotificationUpdate_JoinsItsGroupAndDoesNotDuplicate {
	TGClient *c = NF();
	[c handleUpdate:plainNF(@{@"@type" : @"updateActiveNotifications",
		@"groups" : @[groupNF(7, 77, @[notificationNF(9, @"old")])]})];
	[c handleUpdate:plainNF(@{@"@type" : @"updateNotification",
		@"notification_group_id" : @(7),
		@"notification" : notificationNF(10, @"new")})];
	[c handleUpdate:plainNF(@{@"@type" : @"updateNotification",
		@"notification_group_id" : @(7),
		@"notification" : notificationNF(10, @"edited")})];

	NSArray *rows = c.activeNotificationGroups[0][@"notifications"];
	XCTAssertEqual(rows.count, 2);
	XCTAssertEqualObjects(rows[1][@"id"], @(10));
	XCTAssertEqualObjects(rows[1][@"text"], @"edited");
}

- (void)testRemoveNotification_SendsBothIdsAndDropsTheRow {
	TGClient *c = NF();
	[c handleUpdate:plainNF(@{@"@type" : @"updateActiveNotifications",
		@"groups" : @[groupNF(7, 77, @[notificationNF(9, @"one"),
									   notificationNF(10, @"two")])]})];
	__block BOOL ok = NO;
	[c removeNotification:9 inGroup:7 completion:^(BOOL done, NSString *error){
		ok = done;
	}];
	NSDictionary *request = lastNF(c, @"removeNotification");
	XCTAssertEqualObjects(request[@"notification_group_id"], @(7));
	XCTAssertEqualObjects(request[@"notification_id"], @(9));
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	NSArray *rows = c.activeNotificationGroups[0][@"notifications"];
	XCTAssertEqual(rows.count, 1);
	XCTAssertEqualObjects(rows[0][@"id"], @(10));
	XCTAssertEqualObjects(c.activeNotificationGroups[0][@"totalCount"], @(1));
}

- (void)testRemoveNotification_RefusalKeepsTheRow {
	TGClient *c = NF();
	[c handleUpdate:plainNF(@{@"@type" : @"updateActiveNotifications",
		@"groups" : @[groupNF(7, 77, @[notificationNF(9, @"one")])]})];
	__block NSString *gotError = nil;
	[c removeNotification:9 inGroup:7 completion:^(BOOL done, NSString *error){
		gotError = error;
	}];
	answerNF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Notification not found"});
	XCTAssertEqualObjects(gotError, @"Notification not found");
	XCTAssertEqual([c.activeNotificationGroups[0][@"notifications"] count], 1);
}

- (void)testRemoveNotificationGroup_SendsTheHighestIdAndDropsTheGroup {
	TGClient *c = NF();
	[c handleUpdate:plainNF(@{@"@type" : @"updateActiveNotifications",
		@"groups" : @[groupNF(7, 77, @[notificationNF(9, @"one"),
									   notificationNF(12, @"two")]),
					 groupNF(8, 78, @[notificationNF(13, @"other")])]})];
	__block BOOL ok = NO;
	[c removeNotificationGroup:7 maxNotificationId:12
					completion:^(BOOL done, NSString *error){ ok = done; }];
	NSDictionary *request = lastNF(c, @"removeNotificationGroup");
	XCTAssertEqualObjects(request[@"notification_group_id"], @(7));
	XCTAssertEqualObjects(request[@"max_notification_id"], @(12));
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertEqual(c.activeNotificationGroups.count, 1);
	XCTAssertEqualObjects(c.activeNotificationGroups[0][@"id"], @(8));
}

#pragma mark - forum topic read and write

- (void)testForumTopic_ReadsTheCountsAndNotificationRecord {
	TGClient *c = NF();
	__block NSDictionary *got = nil;
	[c forumTopic:12 inChat:77 completion:^(NSDictionary *topic){ got = topic; }];
	NSDictionary *request = lastNF(c, @"getForumTopic");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"forum_topic_id"], @(12));

	answerNF(c, plainNF(topicNF(77, 12, @"News")));
	XCTAssertEqualObjects(got[@"name"], @"News");
	XCTAssertEqualObjects(got[@"threadId"], @(12));
	XCTAssertEqualObjects(got[@"unread"], @(4));
	XCTAssertEqualObjects(got[@"unreadMentions"], @(2));
	XCTAssertEqualObjects(got[@"unreadPollVotes"], @(3));
	XCTAssertEqualObjects(got[@"general"], @YES);
	XCTAssertEqualObjects(got[@"pinned"], @YES);
	XCTAssertEqualObjects(got[@"colour"], @(0x6FB9F0));
	XCTAssertEqualObjects(got[@"iconEmojiId"], @(501));
	XCTAssertEqualObjects(got[@"notificationSettings"][@"mute_for"], @(3600));
}

- (void)testForumTopic_RefusalIsNil {
	TGClient *c = NF();
	__block NSDictionary *got = @{};
	[c forumTopic:12 inChat:77 completion:^(NSDictionary *topic){ got = topic; }];
	answerNF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Topic not found"});
	XCTAssertNil(got);
}

- (void)testForumTopicLink_CopiesTheAnswer {
	TGClient *c = NF();
	__block NSString *got = nil;
	[c forumTopicLinkForTopic:12 inChat:77 completion:^(NSString *link){ got = link; }];
	XCTAssertEqualObjects(lastNF(c, @"getForumTopicLink")[@"forum_topic_id"], @(12));
	answerNF(c, plainNF(@{@"@type" : @"messageLink",
						  @"link" : @"https://t.me/c/77/12",
						  @"is_public" : @NO}));
	XCTAssertEqualObjects(got, @"https://t.me/c/77/12");
}

- (void)testReadAllForumTopicMentions_SendsThePair {
	TGClient *c = NF();
	__block BOOL ok = NO;
	[c readAllForumTopicMentionsInChat:77 topic:12
							completion:^(BOOL done, NSString *error){ ok = done; }];
	NSDictionary *request = lastNF(c, @"readAllForumTopicMentions");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"forum_topic_id"], @(12));
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testReadAllForumTopicPollVotes_SendsThePairAndReportsRefusal {
	TGClient *c = NF();
	__block BOOL ok = YES;
	__block NSString *gotError = nil;
	[c readAllForumTopicPollVotesInChat:77 topic:12
							 completion:^(BOOL done, NSString *error){
		ok = done;
		gotError = error;
	}];
	XCTAssertEqualObjects(lastNF(c, @"readAllForumTopicPollVotes")[@"forum_topic_id"],
						   @(12));
	answerNF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Topic is not a poll"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(gotError, @"Topic is not a poll");
}

- (void)testSetForumTopicNotificationSettings_WritesTheWholeRecord {
	TGClient *c = NF();
	__block BOOL ok = NO;
	NSDictionary *settings = @{@"use_default_mute_for" : @NO,
							   @"mute_for" : @(7200),
							   @"use_default_sound" : @YES,
							   @"sound_id" : @(0),
							   @"use_default_show_preview" : @NO,
							   @"show_preview" : @NO,
							   @"use_default_mute_stories" : @YES,
							   @"mute_stories" : @NO,
							   @"use_default_story_sound" : @YES,
							   @"story_sound_id" : @(0),
							   @"use_default_show_story_poster" : @YES,
							   @"show_story_poster" : @YES,
							   @"use_default_disable_pinned_message_notifications" : @YES,
							   @"disable_pinned_message_notifications" : @NO,
							   @"use_default_disable_mention_notifications" : @YES,
							   @"disable_mention_notifications" : @NO};
	[c setForumTopicNotificationSettings:settings topic:12 inChat:77
							  completion:^(BOOL done, NSString *error){ ok = done; }];
	NSDictionary *request = lastNF(c, @"setForumTopicNotificationSettings");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"forum_topic_id"], @(12));
	XCTAssertEqualObjects(request[@"notification_settings"][@"@type"],
						   @"chatNotificationSettings");
	XCTAssertEqualObjects(request[@"notification_settings"][@"mute_for"], @(7200));
	XCTAssertEqualObjects(request[@"notification_settings"][@"show_preview"], @NO);
	XCTAssertEqualObjects(
			request[@"notification_settings"][@"disable_mention_notifications"], @NO);
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetPinnedForumTopics_SendsTheOrder {
	TGClient *c = NF();
	__block BOOL ok = NO;
	[c setPinnedForumTopics:@[@(12), @(5), @(9)] inChat:77
				 completion:^(BOOL done, NSString *error){ ok = done; }];
	NSDictionary *request = lastNF(c, @"setPinnedForumTopics");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"forum_topic_ids"], (@[@(12), @(5), @(9)]));
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetPinnedForumTopics_RefusalKeepsItsSentence {
	TGClient *c = NF();
	__block NSString *gotError = nil;
	[c setPinnedForumTopics:@[@(12)] inChat:77
				 completion:^(BOOL done, NSString *error){ gotError = error; }];
	answerNF(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"Too many pinned topics"});
	XCTAssertEqualObjects(gotError, @"Too many pinned topics");
}

- (void)testToggleGeneralForumTopicHidden_SendsTheFlag {
	TGClient *c = NF();
	__block BOOL ok = NO;
	[c toggleGeneralForumTopicHidden:YES inChat:77
						  completion:^(BOOL done, NSString *error){ ok = done; }];
	NSDictionary *request = lastNF(c, @"toggleGeneralForumTopicIsHidden");
	XCTAssertEqualObjects(request[@"chat_id"], @(77));
	XCTAssertEqualObjects(request[@"is_hidden"], @YES);
	answerNF(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

@end

// vim:ft=objc
