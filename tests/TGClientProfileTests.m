// TGClientProfileTests.m — the profile surface between two accounts: the
// private note, close friends, the read-date switch, suggested photos and
// birthdays, the sharing theme, and the account's own accent colours.
//
// These are the requests a screen now reaches. The shape matters because
// TDLib answers a wrong one with a plain "ok" that changes nothing, and the
// refusals are the part the screens show verbatim.
#import "TGTestRunner.h"
#import "TGClient.h"
#import "TGClientInternal.h"

@interface TGClientProfileTests : XCTestCase @end

static TGClient *P(void) {
	TGClient *c = TGClient.shared;
	[c.outbox removeAllObjects];
	[c.pendingRequests removeAllObjects];
	[c.chatsById removeAllObjects];
	c.me = @{@"id" : @(1001)};
	c.accentColorIds = nil;
	c.profileAccentColorIds = nil;
	c.contactCloseBirthdays = nil;
	return c;
}

static NSDictionary *decodeP(NSData *d) {
	NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	NSString *trimmed = [json componentsSeparatedByString:@"\0"][0];
	return [NSJSONSerialization JSONObjectWithData:
			[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSDictionary *lastP(TGClient *c, NSString *type) {
	NSDictionary *found = nil;
	for (NSData *d in c.outbox)
		if ([decodeP(d)[@"@type"] isEqualToString:type])
			found = decodeP(d);
	return found;
}

static void answerP(TGClient *c, NSDictionary *answer) {
	NSDictionary *sent = nil;
	for (NSData *d in c.outbox)
		if (decodeP(d)[@"@extra"])
			sent = decodeP(d);
	if (!sent)
		return;
	NSMutableDictionary *reply = [answer mutableCopy];
	reply[@"@extra"] = sent[@"@extra"];
	[c handleUpdate:reply];
}

static NSDictionary *plainP(NSDictionary *d) {
	return [NSJSONSerialization JSONObjectWithData:
			[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]
			options:0 error:nil];
}

@implementation TGClientProfileTests

#pragma mark - the private note

- (void)testUserNote_SendsTheTextAndTheContact {
	TGClient *c = P();
	__block BOOL ok = NO;
	[c setUserNote:@"met at the conference" forUser:42
		completion:^(BOOL good, NSString *error){ ok = good; }];
	NSDictionary *r = lastP(c, @"setUserNote");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"note"][@"text"], @"met at the conference");
	XCTAssertEqualObjects(r[@"note"][@"@type"], @"formattedText");
	answerP(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testUserNote_AnEmptyNoteIsHowItIsRemoved {
	TGClient *c = P();
	[c setUserNote:@"" forUser:42 completion:nil];
	NSDictionary *r = lastP(c, @"setUserNote");
	XCTAssertEqualObjects(r[@"note"][@"text"], @"");
	XCTAssertEqualObjects(r[@"note"][@"entities"], @[]);
}

- (void)testUserNote_ARefusalCarriesTheServerSentence {
	TGClient *c = P();
	__block NSString *said = nil;
	__block BOOL ok = YES;
	[c setUserNote:@"hello" forUser:42 completion:^(BOOL good, NSString *error){
		ok = good; said = error;
	}];
	answerP(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"USER_NOT_FOUND"});
	XCTAssertFalse(ok);
	XCTAssertEqualObjects(said, @"USER_NOT_FOUND");
}

#pragma mark - close friends

- (void)testCloseFriends_AnswersWithTheIdsTelegramHolds {
	TGClient *c = P();
	__block NSArray *ids = nil;
	[c closeFriendsWithCompletion:^(NSArray *users){ ids = users; }];
	answerP(c, @{@"@type" : @"users", @"total_count" : @(2),
				  @"user_ids" : @[@11, @12]});
	XCTAssertEqualObjects(ids, (@[@11, @12]));
}

- (void)testSetCloseFriends_WritesTheWholeList {
	TGClient *c = P();
	__block BOOL ok = NO;
	[c setCloseFriends:@[@11, @12] completion:^(BOOL good, NSString *error){
		ok = good;
	}];
	NSDictionary *r = lastP(c, @"setCloseFriends");
	XCTAssertEqualObjects(r[@"user_ids"], (@[@11, @12]));
	answerP(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
}

- (void)testSetCloseFriends_ANonContactIsRefusedWithTheReason {
	TGClient *c = P();
	__block NSString *said = nil;
	[c setCloseFriends:@[@11] completion:^(BOOL ok, NSString *error){ said = error; }];
	answerP(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"USERS_TOO_FEW"});
	XCTAssertEqualObjects(said, @"USERS_TOO_FEW");
}

#pragma mark - read-date privacy

- (void)testReadDateSettings_ReadsTheFlag {
	TGClient *c = P();
	__block BOOL show = NO;
	[c readDatePrivacySettingsWithCompletion:^(BOOL value){ show = value; }];
	answerP(c, plainP(@{@"@type" : @"readDatePrivacySettings",
						@"show_read_date" : @YES}));
	XCTAssertTrue(show);
}

- (void)testReadDateSettings_WritesTheWholeRecord {
	TGClient *c = P();
	[c setReadDateShown:NO completion:nil];
	NSDictionary *r = lastP(c, @"setReadDatePrivacySettings");
	XCTAssertEqualObjects(r[@"settings"][@"@type"], @"readDatePrivacySettings");
	XCTAssertEqualObjects(r[@"settings"][@"show_read_date"], @NO);
}

#pragma mark - suggestions

- (void)testSuggestBirthdate_SendsDayMonthAndOptionalYear {
	TGClient *c = P();
	[c suggestBirthdateDay:12 month:5 year:1990 forUser:42 completion:nil];
	NSDictionary *r = lastP(c, @"suggestUserBirthdate");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"birthdate"][@"day"], @(12));
	XCTAssertEqualObjects(r[@"birthdate"][@"month"], @(5));
	XCTAssertEqualObjects(r[@"birthdate"][@"year"], @(1990));
}

- (void)testSuggestBirthdate_AYearOfZeroIsLeftOut {
	TGClient *c = P();
	[c suggestBirthdateDay:12 month:5 year:0 forUser:42 completion:nil];
	NSDictionary *r = lastP(c, @"suggestUserBirthdate");
	XCTAssertNil(r[@"birthdate"][@"year"]);
}

- (void)testSuggestProfilePhoto_SendsALocalPicture {
	TGClient *c = P();
	[c suggestProfilePhotoAtPath:@"/tmp/face.jpg" forUser:42 completion:nil];
	NSDictionary *r = lastP(c, @"suggestUserProfilePhoto");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"photo"][@"@type"], @"inputChatPhotoStatic");
	XCTAssertEqualObjects(r[@"photo"][@"photo"][@"path"], @"/tmp/face.jpg");
}

- (void)testPersonalProfilePhoto_SetsThePictureOnlyThisAccountSees {
	TGClient *c = P();
	[c setPersonalProfilePhotoAtPath:@"/tmp/face.jpg" forUser:42 completion:nil];
	NSDictionary *r = lastP(c, @"setUserPersonalProfilePhoto");
	XCTAssertEqualObjects(r[@"user_id"], @(42));
	XCTAssertEqualObjects(r[@"photo"][@"photo"][@"path"], @"/tmp/face.jpg");
}

- (void)testPersonalProfilePhoto_ANilPathIsHowItIsRemoved {
	TGClient *c = P();
	[c setPersonalProfilePhotoAtPath:nil forUser:42 completion:nil];
	NSDictionary *r = lastP(c, @"setUserPersonalProfilePhoto");
	XCTAssertEqualObjects(r[@"photo"], [NSNull null]);
}

#pragma mark - the main tab

- (void)testMainProfileTab_ReadsTheTabNameTheScreenUses {
	TGClient *c = P();
	__block NSString *tab = nil;
	[c myMainProfileTabWithCompletion:^(NSString *name){ tab = name; }];
	answerP(c, plainP(@{@"@type" : @"userFullInfo",
						@"main_profile_tab" : @{@"@type" : @"profileTabMedia"}}));
	XCTAssertEqualObjects(tab, @"media");
}

- (void)testMainProfileTab_WritesTheSchemaType {
	TGClient *c = P();
	[c setMainProfileTab:@"voice" completion:nil];
	NSDictionary *r = lastP(c, @"setMainProfileTab");
	XCTAssertEqualObjects(r[@"main_profile_tab"][@"@type"], @"profileTabVoice");
}

#pragma mark - birthdays and support

- (void)testHideCloseBirthdays_SendsTheRequestAndClearsTheCachedList {
	TGClient *c = P();
	c.contactCloseBirthdays = @[@{@"userId" : @7}];
	__block BOOL ok = NO;
	[c hideContactCloseBirthdaysWithCompletion:^(BOOL good, NSString *error){
		ok = good;
	}];
	XCTAssertNotNil(lastP(c, @"hideContactCloseBirthdays"));
	answerP(c, @{@"@type" : @"ok"});
	XCTAssertTrue(ok);
	XCTAssertEqualObjects(c.contactCloseBirthdayUsers, @[]);
}

- (void)testSupportUser_AnswersWithTheAccountTelegramNames {
	TGClient *c = P();
	__block NSDictionary *user = nil;
	[c supportUserWithCompletion:^(NSDictionary *u, NSString *error){ user = u; }];
	answerP(c, plainP(@{@"@type" : @"user",
						@"id" : @(777000),
						@"first_name" : @"Telegram",
						@"last_name" : @"Support",
						@"usernames" : @{@"active_usernames" : @[@"TelegramSupport"]}}));
	XCTAssertEqualObjects(user[@"id"], @(777000));
	XCTAssertEqualObjects(user[@"name"], @"Telegram Support");
}

- (void)testSupportUser_ARefusalIsNotAnAccount {
	TGClient *c = P();
	__block NSString *error = nil;
	__block NSDictionary *user = @{};
	[c supportUserWithCompletion:^(NSDictionary *u, NSString *e){ user = u; error = e; }];
	answerP(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"SUPPORT_UNAVAILABLE"});
	XCTAssertNil(user);
	XCTAssertEqualObjects(error, @"SUPPORT_UNAVAILABLE");
}

#pragma mark - accent colours

- (void)testAccentColors_TheSchemaPromisesZeroThroughSixBeforeAnyUpdate {
	TGClient *c = P();
	XCTAssertEqualObjects([c availableAccentColorIds], (@[@0, @1, @2, @3, @4, @5, @6]));
}

- (void)testAccentColors_AnUpdateReplacesTheOffer {
	TGClient *c = P();
	[c handleUpdate:@{@"@type" : @"updateAccentColors",
					  @"colors" : @[],
					  @"available_accent_color_ids" : @[@0, @7]}];
	XCTAssertEqualObjects([c availableAccentColorIds], (@[@0, @7]));
}

- (void)testAccountAccentColor_WritesTheIdAndNoEmoji {
	TGClient *c = P();
	[c setAccountAccentColor:5 backgroundEmojiId:0 completion:nil];
	NSDictionary *r = lastP(c, @"setAccentColor");
	XCTAssertEqualObjects(r[@"accent_color_id"], @(5));
	XCTAssertEqualObjects(r[@"background_custom_emoji_id"], @(0));
}

- (void)testProfileAccentColor_WritesTheProfileIdAndCanTurnItOff {
	TGClient *c = P();
	[c setAccountProfileAccentColor:-1 backgroundEmojiId:0 completion:nil];
	NSDictionary *r = lastP(c, @"setProfileAccentColor");
	XCTAssertEqualObjects(r[@"profile_accent_color_id"], @(-1));
	XCTAssertEqualObjects(r[@"profile_background_custom_emoji_id"], @(0));
}

- (void)testMyAccentColors_ReadsBothIdsFromGetMe {
	TGClient *c = P();
	__block NSInteger accent = -99, profile = -99;
	[c myAccentColorsWithCompletion:^(NSInteger a, NSInteger p){
		accent = a; profile = p;
	}];
	answerP(c, plainP(@{@"@type" : @"user", @"id" : @(1001),
						@"accent_color_id" : @(3),
						@"profile_accent_color_id" : @(4)}));
	XCTAssertEqual(accent, 3);
	XCTAssertEqual(profile, 4);
}

- (void)testMyAccentColours_ReadsTheBackgroundEmojiIdsToo {
	TGClient *c = P();
	__block NSInteger accent = -99, profile = -99;
	__block int64_t emoji = -1, profileEmoji = -1;
	[c myAccentColoursWithCompletion:^(NSInteger a, NSInteger p,
									   int64_t e, int64_t pe){
		accent = a; profile = p; emoji = e; profileEmoji = pe;
	}];
	// int64 ids arrive as strings over JSON; the read has to survive both.
	answerP(c, plainP(@{@"@type" : @"user", @"id" : @(1001),
						@"accent_color_id" : @(3),
						@"profile_accent_color_id" : @(4),
						@"background_custom_emoji_id" : @"521234567890",
						@"profile_background_custom_emoji_id" : @"531234567890"}));
	XCTAssertEqual(accent, 3);
	XCTAssertEqual(profile, 4);
	XCTAssertEqual(emoji, 521234567890LL);
	XCTAssertEqual(profileEmoji, 531234567890LL);
}

- (void)testAccountAccentColor_ForwardsTheBackgroundEmojiId {
	TGClient *c = P();
	[c setAccountAccentColor:5 backgroundEmojiId:521234567890 completion:nil];
	NSDictionary *r = lastP(c, @"setAccentColor");
	XCTAssertEqualObjects(r[@"accent_color_id"], @(5));
	XCTAssertEqualObjects(r[@"background_custom_emoji_id"], @(521234567890));
}

static void P_assertColour(UIColor *colour, int rgb) {
	XCTAssertNotNil(colour);
	CGFloat r = -1, g = -1, b = -1, a = -1;
	[colour getRed:&r green:&g blue:&b alpha:&a];
	XCTAssertTrue(fabs(r - ((rgb >> 16) & 0xFF) / 255.0) < 0.001);
	XCTAssertTrue(fabs(g - ((rgb >> 8) & 0xFF) / 255.0) < 0.001);
	XCTAssertTrue(fabs(b - (rgb & 0xFF) / 255.0) < 0.001);
}

- (void)testAccentColourForId_ReadsOneIntPerColour {
	TGClient *c = P();
	c.accentColors = @[@{@"id" : @(9), @"light_theme_colors" : @[@(0x1A2B3C), @(0x445566)]}];
	P_assertColour([c accentColourForId:9 profile:NO], 0x1A2B3C);
	XCTAssertNil([c accentColourForId:99 profile:NO]);
}

- (void)testAccentColourForId_TheFirstSevenAreNotInTheList {
	TGClient *c = P();
	c.accentColors = @[];
	P_assertColour([c accentColourForId:3 profile:NO], 0x7BC862);
}

- (void)testAccentColourForId_ProfileColoursAreNested {
	TGClient *c = P();
	c.profileAccentColors = @[@{@"id" : @(2), @"light_theme_colors" :
			@{@"palette_colors" : @[@(0x102030)], @"background_colors" : @[@(0xFFFFFF)]}}];
	P_assertColour([c accentColourForId:2 profile:YES], 0x102030);
	XCTAssertNil([c accentColourForId:3 profile:YES]);
}

- (void)testAccentChoiceKeepingEmoji_ReadsThenWritesTheSameId {
	TGClient *c = P();
	[c setAccountAccentColorPreservingBackgroundEmoji:5 completion:nil];
	XCTAssertNotNil(lastP(c, @"getMe"));
	answerP(c, plainP(@{@"@type" : @"user", @"id" : @(1001),
						@"background_custom_emoji_id" : @(77),
						@"profile_background_custom_emoji_id" : @(88)}));
	NSDictionary *r = lastP(c, @"setAccentColor");
	XCTAssertEqualObjects(r[@"accent_color_id"], @(5));
	XCTAssertEqualObjects(r[@"background_custom_emoji_id"], @(77));
}

- (void)testProfileAccentChoiceKeepingEmoji_UsesTheProfileEmojiId {
	TGClient *c = P();
	[c setAccountProfileAccentColorPreservingBackgroundEmoji:5 completion:nil];
	XCTAssertNotNil(lastP(c, @"getMe"));
	answerP(c, plainP(@{@"@type" : @"user", @"id" : @(1001),
						@"background_custom_emoji_id" : @(77),
						@"profile_background_custom_emoji_id" : @(88)}));
	NSDictionary *r = lastP(c, @"setProfileAccentColor");
	XCTAssertEqualObjects(r[@"profile_accent_color_id"], @(5));
	XCTAssertEqualObjects(r[@"profile_background_custom_emoji_id"], @(88));
}

#pragma mark - birthdays and fields

- (void)testOwnBirthday_AYearOfZeroIsLeftOutOfSetBirthdate {
	TGClient *c = P();
	[c setBirthdayDay:12 month:5 year:0 completion:nil];
	NSDictionary *r = lastP(c, @"setBirthdate");
	XCTAssertEqualObjects(r[@"birthdate"][@"day"], @(12));
	XCTAssertEqualObjects(r[@"birthdate"][@"month"], @(5));
	XCTAssertNil(r[@"birthdate"][@"year"]);
}

- (void)testOwnBioLength_ReadsTheServerOption {
	TGClient *c = P();
	__block NSInteger max = 0;
	[c bioLengthMaxWithCompletion:^(NSInteger value){ max = value; }];
	NSDictionary *r = lastP(c, @"getOption");
	XCTAssertEqualObjects(r[@"name"], @"bio_length_max");
	answerP(c, plainP(@{@"@type" : @"optionValueInteger", @"value" : @"70"}));
	XCTAssertEqual(max, 70);
}

- (void)testBirthdayPrivacy_ReadsAndWritesShowBirthdate {
	TGClient *c = P();
	__block NSString *rule = nil;
	[c privacyRule:@"ShowBirthdate" completion:^(NSString *value){ rule = value; }];
	NSDictionary *asked = lastP(c, @"getUserPrivacySettingRules");
	XCTAssertEqualObjects(asked[@"setting"][@"@type"],
						  @"userPrivacySettingShowBirthdate");
	answerP(c, plainP(@{@"@type" : @"userPrivacySettingRules",
						@"rules" : @[@{@"@type" : @"userPrivacySettingRuleAllowContacts"}]}));
	XCTAssertEqualObjects(rule, @"contacts");

	[c setPrivacyRule:@"ShowBirthdate" to:@"everybody"];
	NSDictionary *written = lastP(c, @"setUserPrivacySettingRules");
	XCTAssertEqualObjects(written[@"setting"][@"@type"],
						  @"userPrivacySettingShowBirthdate");
	XCTAssertEqualObjects(written[@"rules"][@"rules"][0][@"@type"],
						  @"userPrivacySettingRuleAllowAll");
}

#pragma mark - the sharing theme

- (void)testShareThemeBackdrops_ListsTheIdsAndNames {
	TGClient *c = P();
	__block NSArray *backdrops = nil;
	[c profileShareThemeBackdropsWithCompletion:^(NSArray *rows, NSString *error){
		backdrops = rows;
	}];
	answerP(c, plainP(@{@"@type" : @"profileShareThemeBackdrops",
						@"backdrops" : @[
							@{@"@type" : @"profileShareThemeBackdrop",
							  @"id" : @(9), @"name" : @"Night",
							  @"colors" : @{@"@type" : @"upgradedGiftBackdropColors"}},
							@{@"@type" : @"profileShareThemeBackdrop",
							  @"id" : @(10), @"name" : @"Dawn",
							  @"colors" : @{@"@type" : @"upgradedGiftBackdropColors"}}]}));
	XCTAssertEqual(backdrops.count, 2);
	XCTAssertEqualObjects(backdrops[1][@"name"], @"Dawn");
	XCTAssertEqualObjects(backdrops[0][@"id"], @(9));
}

- (void)testShareThemeBackdrops_ARefusalCarriesTheSentence {
	TGClient *c = P();
	__block NSString *said = nil;
	[c profileShareThemeBackdropsWithCompletion:^(NSArray *rows, NSString *error){
		said = error;
	}];
	answerP(c, @{@"@type" : @"error", @"code" : @(400),
				  @"message" : @"BACKDROPS_UNAVAILABLE"});
	XCTAssertEqualObjects(said, @"BACKDROPS_UNAVAILABLE");
}

- (void)testShareTheme_WritesTheBackdropAndAnEmoji {
	TGClient *c = P();
	[c setProfileShareThemeForChat:77 backdropId:9 useDefault:NO completion:nil];
	NSDictionary *r = lastP(c, @"setProfileShareTheme");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"theme"][@"@type"], @"inputProfileShareThemeEmoji");
	XCTAssertEqualObjects(r[@"theme"][@"background_backdrop_id"], @(9));
	XCTAssertEqualObjects(r[@"theme"][@"use_default_background"], @NO);
	XCTAssertEqual([r[@"theme"][@"emojis"] count], 1);
}

- (void)testShareTheme_DefaultIsANullTheme {
	TGClient *c = P();
	[c clearProfileShareThemeForChat:77 completion:nil];
	NSDictionary *r = lastP(c, @"setProfileShareTheme");
	XCTAssertEqualObjects(r[@"chat_id"], @(77));
	XCTAssertEqualObjects(r[@"theme"], [NSNull null]);
}

- (void)testCloseBirthdayUpdate_KeepsTheRowsThePrivacyPageCounts {
	TGClient *c = P();
	[c handleUpdate:plainP(@{@"@type" : @"updateContactCloseBirthdays",
							 @"close_birthday_users" : @[
								 @{@"@type" : @"closeBirthdayUser",
								   @"user_id" : @(7),
								   @"birthdate" : @{@"@type" : @"birthdate",
													@"day" : @(3),
													@"month" : @(4),
													@"year" : @(0)}}]})];
	XCTAssertEqual(c.contactCloseBirthdayUsers.count, 1);
	XCTAssertEqualObjects(c.contactCloseBirthdayUsers[0][@"userId"], @(7));
}

#pragma mark - profile full info (wave 1)

static NSDate *PGDate(NSInteger year, NSInteger month, NSInteger day) {
	NSCalendar *cal = [NSCalendar currentCalendar];
	NSDateComponents *c = [[NSDateComponents alloc] init];
	c.year = year; c.month = month; c.day = day;
	return [cal dateFromComponents:c];
}

- (void)testBirthdayText_IncludesTheYearAndAge {
	NSString *text = TGProfileBirthdayText(5, 3, 1990, PGDate(2026, 7, 1));
	XCTAssertEqualObjects(text, @"March 5, 1990 (36 years old)");
}

- (void)testBirthdayText_AYearOfZeroDropsTheAge {
	NSString *text = TGProfileBirthdayText(5, 3, 0, PGDate(2026, 7, 1));
	XCTAssertEqualObjects(text, @"March 5");
}

- (void)testBirthdayText_TodayIsItsOwnLine {
	NSString *text = TGProfileBirthdayText(1, 7, 1990, PGDate(2026, 7, 1));
	XCTAssertEqualObjects(text, @"Birthday today");
	XCTAssertTrue(TGProfileBirthdayIsToday(1, 7, PGDate(2026, 7, 1)));
	XCTAssertFalse(TGProfileBirthdayIsToday(2, 7, PGDate(2026, 7, 1)));
}

- (void)testBirthdayText_NoDayMeansNoRow {
	XCTAssertNil(TGProfileBirthdayText(0, 3, 1990, PGDate(2026, 7, 1)));
}

- (void)testFirstUsername_AnEmptyArrayIsNilNotACrash {
	XCTAssertNil(TGFirstUsername(plainP(@{@"usernames" : @{@"active_usernames" : @[]}})));
	XCTAssertEqualObjects(TGFirstUsername(plainP(@{@"usernames" : @{@"active_usernames" : @[@"alice"]}})), @"alice");
	XCTAssertNil(TGFirstUsername(@{}));
}

- (void)testUserProfile_CarriesTheBlockFlagSoOneRequestServesBoth {
	TGClient *c = P();
	__block NSDictionary *info = nil;
	[c userProfile:42 completion:^(NSDictionary *i){ info = i; }];
	answerP(c, plainP(@{@"@type" : @"userFullInfo",
						@"block_list" : @{@"@type" : @"blockListMain"},
						@"bio" : @{@"@type" : @"formattedText", @"text" : @"hi"}}));
	XCTAssertEqualObjects(info[@"isBlocked"], @YES);
	XCTAssertEqualObjects(info[@"bio"], @"hi");
}

- (void)testUserProfile_FlattensTheFirstProfileAudio {
	TGClient *c = P();
	__block NSDictionary *info = nil;
	[c userProfile:42 completion:^(NSDictionary *i){ info = i; }];
	answerP(c, plainP(@{@"@type" : @"userFullInfo",
						// td_api.tl: first_profile_audio:audio, with the file under "audio".
						@"first_profile_audio" : @{
							@"@type" : @"audio", @"title" : @"Track", @"performer" : @"Artist",
							@"duration" : @(125),
							@"audio" : @{@"@type" : @"file", @"id" : @(99)},
							@"album_cover_thumbnail" : @{
								@"@type" : @"thumbnail", @"file" : @{@"@type" : @"file", @"id" : @(7)}}}}));
	XCTAssertEqualObjects(info[@"firstProfileAudio"][@"fileId"], @(99));
	XCTAssertEqualObjects(info[@"firstProfileAudio"][@"title"], @"Track");
	XCTAssertEqualObjects(info[@"firstProfileAudio"][@"performer"], @"Artist");
	XCTAssertEqualObjects(info[@"firstProfileAudio"][@"albumCoverId"], @(7));
}

- (void)testUserProfile_ReadsThePersonalChannelId {
	TGClient *c = P();
	__block NSDictionary *info = nil;
	[c userProfile:42 completion:^(NSDictionary *i){ info = i; }];
	answerP(c, plainP(@{@"@type" : @"userFullInfo", @"personal_chat_id" : @(88)}));
	XCTAssertEqualObjects(info[@"personalChatId"], @(88));
}

- (void)testUserProfile_NoPersonalChannelIsZero {
	TGClient *c = P();
	__block NSDictionary *info = nil;
	[c userProfile:42 completion:^(NSDictionary *i){ info = i; }];
	answerP(c, plainP(@{@"@type" : @"userFullInfo"}));
	XCTAssertEqualObjects(info[@"personalChatId"], @(0));
}

- (void)testMediaPageAppending_DropsTheRowThePreviousPageEndedWith {
	NSArray *first = @[@{@"id" : @(9)}, @{@"id" : @(8)}];
	NSArray *second = @[@{@"id" : @(8)}, @{@"id" : @(7)}];
	NSArray *joined = TGMediaPageAppending(first, second);
	XCTAssertEqual(joined.count, (NSUInteger)3);
	XCTAssertEqualObjects([joined valueForKey:@"id"], (@[@9, @8, @7]));
}

- (void)testChatProfile_ReadsTheOnlineCountFromTheCachedRow {
	TGClient *c = P();
	c.chatsById[@(77)] = [@{@"onlineMembers" : @(5)} mutableCopy];
	__block NSDictionary *got = nil;
	[c chatProfile:77 completion:^(NSDictionary *info){ got = info; }];
	answerP(c, plainP(@{@"@type" : @"chat",
						@"id" : @(77),
						@"type" : @{@"@type" : @"chatTypeSupergroup", @"supergroup_id" : @(9)}}));
	answerP(c, plainP(@{@"@type" : @"supergroup",
						@"verification_status" : @{@"@type" : @"verificationStatus",
												   @"is_verified" : @YES}}));
	answerP(c, plainP(@{@"@type" : @"supergroupFullInfo",
						@"member_count" : @(12),
						@"description" : @"about",
						@"invite_link" : @{@"@type" : @"chatInviteLink",
										   @"invite_link" : @"t.me/x"}}));
	XCTAssertEqualObjects(got[@"online"], @(5));
	XCTAssertEqualObjects(got[@"members"], @(12));
	XCTAssertEqualObjects(got[@"verified"], @YES);
}

- (void)testMessageCountForFilter_SendsTheTabFilter {
	TGClient *c = P();
	__block NSInteger count = -1;
	[c messageCountInChat:77 filter:@"searchMessagesFilterAudio"
			   completion:^(NSInteger n){ count = n; }];
	NSDictionary *r = lastP(c, @"getChatMessageCount");
	XCTAssertEqualObjects(r[@"filter"][@"@type"], @"searchMessagesFilterAudio");
	XCTAssertNil(r[@"topic_id"]);
	answerP(c, plainP(@{@"@type" : @"count", @"count" : @(9)}));
	XCTAssertEqual(count, 9);
}

@end
