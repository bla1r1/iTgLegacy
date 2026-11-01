//
// TGClient+Business.m - the Telegram Business requests.
//
// The shape here follows td_api.tl exactly. The account settings carry no
// connection id because TDLib applies them to the signed-in user; the
// profile and message calls do carry one because TDLib declares them for
// business bots. Sending them from a user account is still the honest
// request: Telegram answers with its own refusal, and the screen prints
// that sentence instead of hiding a row nobody can use.
//
#import "TGClient+Business.h"
#import "TGClientInternal.h"

static NSString *TGBusinessError(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] ? message : @"Telegram refused that.";
}

static BOOL TGBusinessSucceeded(NSDictionary *result) {
	return ![result[@"@type"] isEqualToString:@"error"];
}

static NSDictionary *TGBusinessFormattedText(NSString *text) {
	return @{@"@type" : @"formattedText",
			 @"text" : text ?: @"",
			 @"entities" : @[]};
}

static NSDictionary *TGBusinessTextContent(NSString *text) {
	return @{@"@type" : @"inputMessageText",
			 @"text" : TGBusinessFormattedText(text)};
}

static NSDictionary *TGBusinessPhotoContent(NSString *path, NSString *caption) {
	return @{@"@type" : @"inputMessagePhoto",
			 @"photo" : @{@"@type" : @"inputFileLocal", @"path" : path ?: @""},
			 @"caption" : TGBusinessFormattedText(caption)};
}

static NSDictionary *TGBusinessVideoContent(NSString *path, NSString *caption) {
	return @{@"@type" : @"inputMessageVideo",
			 @"video" : @{@"@type" : @"inputFileLocal", @"path" : path ?: @""},
			 @"caption" : TGBusinessFormattedText(caption)};
}

/// businessRecipients has no optional fields. A screen that only flips one
/// category still has to send the other four, so the missing ones keep the
/// "everybody" value rather than writing a chat out of the audience by
/// accident.
static NSDictionary *TGBusinessRecipients(NSDictionary *values) {
	NSDictionary *v = [values isKindOfClass:NSDictionary.class] ? values : @{};
	id existing = v[@"existing"] ?: @YES;
	id newChats = v[@"new"] ?: @YES;
	id contacts = v[@"contacts"] ?: @YES;
	id nonContacts = v[@"nonContacts"] ?: @YES;
	id exclude = v[@"excludeSelected"] ?: @NO;
	NSArray *chatIds = [v[@"chatIds"] isKindOfClass:NSArray.class]
			? v[@"chatIds"] : @[];
	NSArray *excludedIds = [v[@"excludedChatIds"] isKindOfClass:NSArray.class]
			? v[@"excludedChatIds"] : @[];
	return @{
		@"@type" : @"businessRecipients",
		@"chat_ids" : chatIds,
		@"excluded_chat_ids" : excludedIds,
		@"select_existing_chats" : existing,
		@"select_new_chats" : newChats,
		@"select_contacts" : contacts,
		@"select_non_contacts" : nonContacts,
		@"exclude_selected" : exclude,
	};
}

/// A business chat link is returned as a full t.me URL. The info request
/// names only the part after the slash.
NSString *TGBusinessLinkName(NSString *link) {
	NSString *name = link ?: @"";
	for (NSString *prefix in @[@"https://t.me/", @"http://t.me/", @"t.me/"]){
		if ([name hasPrefix:prefix]){
			name = [name substringFromIndex:prefix.length];
			break;
		}
	}
	return name;
}

@implementation TGClient (Business)

#pragma mark - features and connection

- (void)businessFeaturesForSource:(NSString *)source
					   completion:(void (^)(NSArray *, NSString *))completion {
	id sourceObject = source.length
			? @{@"@type" : source} : [NSNull null];
	[self request:@{@"@type" : @"getBusinessFeatures", @"source" : sourceObject}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		NSArray *features = [result[@"features"] isKindOfClass:NSArray.class]
				? result[@"features"] : @[];
		NSMutableArray *names = [NSMutableArray arrayWithCapacity:features.count];
		for (NSDictionary *feature in features){
			NSString *type = feature[@"@type"];
			if (type.length)
				[names addObject:type];
		}
		if (completion) completion(names, nil);
	}];
}

- (void)businessInfoWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
	int64_t userId = [[self me][@"id"] longLongValue];
	if (!userId){
		if (completion) completion(nil, @"Sign in before reading the business profile.");
		return;
	}
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		NSDictionary *info = [result[@"business_info"] isKindOfClass:NSDictionary.class]
				? result[@"business_info"] : @{};
		if (completion) completion(info, nil);
	}];
}

- (void)businessConnectionWithId:(NSString *)connectionId
					  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getBusinessConnection",
					@"connection_id" : connectionId ?: @""}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

#pragma mark - account profile

- (void)setBusinessAccountName:(NSString *)firstName
						  last:(NSString *)lastName
				  connectionId:(NSString *)connectionId
					completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"setBusinessAccountName",
					@"business_connection_id" : connectionId ?: @"",
					@"first_name" : firstName ?: @"",
					@"last_name" : lastName ?: @""}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessAccountBio:(NSString *)bio
				 connectionId:(NSString *)connectionId
				   completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"setBusinessAccountBio",
					@"business_connection_id" : connectionId ?: @"",
					@"bio" : bio ?: @""}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessAccountUsername:(NSString *)username
					  connectionId:(NSString *)connectionId
						completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"setBusinessAccountUsername",
					@"business_connection_id" : connectionId ?: @"",
					@"username" : username ?: @""}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessAccountProfilePhotoAtPath:(NSString *)path
									public:(BOOL)isPublic
								connectionId:(NSString *)connectionId
								  completion:(void (^)(BOOL, NSString *))completion {
	id photo = [NSNull null];
	if (path.length)
		photo = @{@"@type" : @"inputChatPhotoStatic",
				  @"photo" : @{@"@type" : @"inputFileLocal", @"path" : path}};
	[self request:@{@"@type" : @"setBusinessAccountProfilePhoto",
					@"business_connection_id" : connectionId ?: @"",
					@"photo" : photo,
					@"is_public" : @(isPublic)}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

#pragma mark - links to chat

- (void)businessChatLinksWithCompletion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{@"@type" : @"getBusinessChatLinks"}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		NSArray *links = [result[@"links"] isKindOfClass:NSArray.class]
				? result[@"links"] : @[];
		if (completion) completion(links, nil);
	}];
}

- (void)createBusinessChatLinkWithText:(NSString *)text
								 title:(NSString *)title
							completion:(void (^)(NSDictionary *, NSString *))completion {
	NSDictionary *info = @{@"@type" : @"inputBusinessChatLink",
						   @"text" : TGBusinessFormattedText(text),
						   @"title" : title ?: @""};
	[self request:@{@"@type" : @"createBusinessChatLink", @"link_info" : info}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)editBusinessChatLink:(NSString *)link
						text:(NSString *)text
					   title:(NSString *)title
				  completion:(void (^)(NSDictionary *, NSString *))completion {
	NSDictionary *info = @{@"@type" : @"inputBusinessChatLink",
						   @"text" : TGBusinessFormattedText(text),
						   @"title" : title ?: @""};
	[self request:@{@"@type" : @"editBusinessChatLink",
					@"link" : link ?: @"",
					@"link_info" : info}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)deleteBusinessChatLink:(NSString *)link
					completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"deleteBusinessChatLink", @"link" : link ?: @""}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)businessChatLinkInfoForName:(NSString *)linkName
						 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{@"@type" : @"getBusinessChatLinkInfo",
					@"link_name" : linkName ?: @""}
	   completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

#pragma mark - account settings

- (void)setBusinessLocationLatitude:(NSNumber *)latitude
						  longitude:(NSNumber *)longitude
							address:(NSString *)address
						 completion:(void (^)(BOOL, NSString *))completion {
	id location = [NSNull null];
	if (latitude && longitude)
		location = @{
			@"@type" : @"businessLocation",
			@"location" : @{
				@"@type" : @"location",
				@"latitude" : @(latitude.doubleValue),
				@"longitude" : @(longitude.doubleValue),
				@"horizontal_accuracy" : @(0),
			},
			@"address" : address ?: @"",
		};
	[self request:@{@"@type" : @"setBusinessLocation", @"location" : location}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessOpeningHoursTimeZone:(NSString *)timeZone
							  intervals:(NSArray *)intervals
							 completion:(void (^)(BOOL, NSString *))completion {
	id hours = [NSNull null];
	if (intervals.count){
		hours = @{@"@type" : @"businessOpeningHours",
				  @"time_zone_id" : timeZone ?: @"UTC",
				  @"opening_hours" : intervals};
	}
	[self request:@{@"@type" : @"setBusinessOpeningHours", @"opening_hours" : hours}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessGreetingMessageEnabled:(BOOL)enabled
							   shortcutId:(NSInteger)shortcutId
						   inactivityDays:(NSInteger)inactivityDays
							   recipients:(NSDictionary *)recipients
							   completion:(void (^)(BOOL, NSString *))completion {
	id settings = [NSNull null];
	if (enabled)
		settings = @{
			@"@type" : @"businessGreetingMessageSettings",
			@"shortcut_id" : @(shortcutId),
			@"recipients" : TGBusinessRecipients(recipients),
			@"inactivity_days" : @(inactivityDays),
		};
	[self request:@{@"@type" : @"setBusinessGreetingMessageSettings",
					@"greeting_message_settings" : settings}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessAwayMessageEnabled:(BOOL)enabled
						   shortcutId:(NSInteger)shortcutId
							 schedule:(NSString *)schedule
							startDate:(int32_t)startDate
							  endDate:(int32_t)endDate
						  offlineOnly:(BOOL)offlineOnly
						   recipients:(NSDictionary *)recipients
						   completion:(void (^)(BOOL, NSString *))completion {
	id settings = [NSNull null];
	if (enabled){
		NSDictionary *scheduleObject = nil;
		if ([schedule isEqualToString:@"outside"])
			scheduleObject = @{@"@type" : @"businessAwayMessageScheduleOutsideOfOpeningHours"};
		else if ([schedule isEqualToString:@"custom"])
			scheduleObject = @{@"@type" : @"businessAwayMessageScheduleCustom",
							   @"start_date" : @(startDate),
							   @"end_date" : @(endDate)};
		else
			scheduleObject = @{@"@type" : @"businessAwayMessageScheduleAlways"};
		settings = @{
			@"@type" : @"businessAwayMessageSettings",
			@"shortcut_id" : @(shortcutId),
			@"recipients" : TGBusinessRecipients(recipients),
			@"schedule" : scheduleObject,
			@"offline_only" : @(offlineOnly),
		};
	}
	[self request:@{@"@type" : @"setBusinessAwayMessageSettings",
					@"away_message_settings" : settings}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessStartPageTitle:(NSString *)title
						  message:(NSString *)message
					  stickerPath:(NSString *)stickerPath
					   completion:(void (^)(BOOL, NSString *))completion {
	id startPage = [NSNull null];
	if (title.length || message.length){
		id sticker = [NSNull null];
		if (stickerPath.length)
			sticker = @{@"@type" : @"inputFileLocal", @"path" : stickerPath};
		else
			sticker = @{@"@type" : @"inputFileId", @"id" : @(0)};
		startPage = @{@"@type" : @"inputBusinessStartPage",
					  @"title" : title ?: @"",
					  @"message" : message ?: @"",
					  @"sticker" : sticker};
	}
	[self request:@{@"@type" : @"setBusinessStartPage", @"start_page" : startPage}
	   completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

#pragma mark - business messages

- (void)sendBusinessMessageWithConnectionId:(NSString *)connectionId
									 chatId:(int64_t)chatId
									   text:(NSString *)text
						   disableNotification:(BOOL)disableNotification
							  protectContent:(BOOL)protectContent
								 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"sendBusinessMessage",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"reply_to" : [NSNull null],
		@"disable_notification" : @(disableNotification),
		@"protect_content" : @(protectContent),
		@"effect_id" : @(0),
		@"reply_markup" : [NSNull null],
		@"input_message_content" : TGBusinessTextContent(text),
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)sendBusinessMessageAlbumWithConnectionId:(NSString *)connectionId
										  chatId:(int64_t)chatId
										   paths:(NSArray *)paths
										  caption:(NSString *)caption
							  disableNotification:(BOOL)disableNotification
								 protectContent:(BOOL)protectContent
									  completion:(void (^)(NSArray *, NSString *))completion {
	NSMutableArray *contents = [NSMutableArray array];
	NSUInteger index = 0;
	for (id value in paths){
		if (index >= 10)
			break;
		if (![value isKindOfClass:NSString.class] || ![value length])
			continue;
		[contents addObject:TGBusinessPhotoContent(value, index == 0 ? caption : @"")];
		index++;
	}
	if (!contents.count){
		if (completion) completion(nil, @"An album needs at least two local photos.");
		return;
	}
	[self request:@{
		@"@type" : @"sendBusinessMessageAlbum",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"reply_to" : [NSNull null],
		@"disable_notification" : @(disableNotification),
		@"protect_content" : @(protectContent),
		@"effect_id" : @(0),
		@"input_message_contents" : contents,
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		NSArray *messages = [result[@"messages"] isKindOfClass:NSArray.class]
				? result[@"messages"] : @[];
		if (completion) completion(messages, nil);
	}];
}

- (void)editBusinessMessageTextWithConnectionId:(NSString *)connectionId
										 chatId:(int64_t)chatId
									  messageId:(int64_t)messageId
										   text:(NSString *)text
									 completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"editBusinessMessageText",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
		@"input_message_content" : TGBusinessTextContent(text),
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)editBusinessMessageCaptionWithConnectionId:(NSString *)connectionId
											chatId:(int64_t)chatId
										 messageId:(int64_t)messageId
										   caption:(NSString *)caption
										completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"editBusinessMessageCaption",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
		@"caption" : TGBusinessFormattedText(caption),
		@"show_caption_above_media" : @NO,
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)editBusinessMessageMediaWithConnectionId:(NSString *)connectionId
										  chatId:(int64_t)chatId
									   messageId:(int64_t)messageId
											path:(NSString *)path
										 isVideo:(BOOL)isVideo
										 caption:(NSString *)caption
									  completion:(void (^)(NSDictionary *, NSString *))completion {
	id content = isVideo
			? TGBusinessVideoContent(path, caption)
			: TGBusinessPhotoContent(path, caption);
	[self request:@{
		@"@type" : @"editBusinessMessageMedia",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
		@"input_message_content" : content,
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)editBusinessMessageLiveLocationWithConnectionId:(NSString *)connectionId
												 chatId:(int64_t)chatId
											  messageId:(int64_t)messageId
											   latitude:(double)latitude
											  longitude:(double)longitude
											 livePeriod:(NSInteger)livePeriod
											 completion:(void (^)(NSDictionary *, NSString *))completion {
	id location = [NSNull null];
	if (livePeriod > 0)
		location = @{
			@"@type" : @"liveLocation",
			@"location" : @{
				@"@type" : @"location",
				@"latitude" : @(latitude),
				@"longitude" : @(longitude),
				@"horizontal_accuracy" : @(0),
			},
			@"live_period" : @(livePeriod),
			@"heading" : @(0),
			@"proximity_alert_radius" : @(0),
		};
	[self request:@{
		@"@type" : @"editBusinessMessageLiveLocation",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
		@"location" : location,
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)editBusinessMessageChecklistWithConnectionId:(NSString *)connectionId
											  chatId:(int64_t)chatId
										   messageId:(int64_t)messageId
											   title:(NSString *)title
											   tasks:(NSArray *)tasks
											completion:(void (^)(NSDictionary *, NSString *))completion {
	NSMutableArray *taskObjects = [NSMutableArray array];
	NSInteger taskId = 1;
	for (id value in tasks){
		if (![value isKindOfClass:NSString.class] || ![value length])
			continue;
		[taskObjects addObject:@{
			@"@type" : @"inputChecklistTask",
			@"id" : @(taskId++),
			@"text" : TGBusinessFormattedText(value),
		}];
	}
	NSDictionary *checklist = @{
		@"@type" : @"inputChecklist",
		@"title" : TGBusinessFormattedText(title),
		@"tasks" : taskObjects,
		@"others_can_add_tasks" : @NO,
		@"others_can_mark_tasks_as_done" : @NO,
	};
	[self request:@{
		@"@type" : @"editBusinessMessageChecklist",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
		@"checklist" : checklist,
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)editBusinessMessageReplyMarkupWithConnectionId:(NSString *)connectionId
												chatId:(int64_t)chatId
											 messageId:(int64_t)messageId
											completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"editBusinessMessageReplyMarkup",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)stopBusinessPollWithConnectionId:(NSString *)connectionId
								  chatId:(int64_t)chatId
							   messageId:(int64_t)messageId
							  completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type" : @"stopBusinessPoll",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup" : [NSNull null],
	} completion:^(NSDictionary *result){
		if (!TGBusinessSucceeded(result)){
			if (completion) completion(nil, TGBusinessError(result));
			return;
		}
		if (completion) completion(result, nil);
	}];
}

- (void)readBusinessMessageWithConnectionId:(NSString *)connectionId
									 chatId:(int64_t)chatId
								  messageId:(int64_t)messageId
								 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"readBusinessMessage",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)setBusinessMessagePinnedWithConnectionId:(NSString *)connectionId
										  chatId:(int64_t)chatId
									   messageId:(int64_t)messageId
										  pinned:(BOOL)pinned
									  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type" : @"setBusinessMessageIsPinned",
		@"business_connection_id" : connectionId ?: @"",
		@"chat_id" : @(chatId),
		@"message_id" : @(messageId),
		@"is_pinned" : @(pinned),
	} completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

- (void)deleteBusinessMessagesWithConnectionId:(NSString *)connectionId
									 messageIds:(NSArray *)messageIds
									 completion:(void (^)(BOOL, NSString *))completion {
	if (!messageIds.count){
		if (completion) completion(NO, @"Name at least one message to delete.");
		return;
	}
	[self request:@{
		@"@type" : @"deleteBusinessMessages",
		@"business_connection_id" : connectionId ?: @"",
		@"message_ids" : messageIds,
	} completion:^(NSDictionary *result){
		BOOL ok = TGBusinessSucceeded(result);
		if (completion)
			completion(ok, ok ? nil : TGBusinessError(result));
	}];
}

@end

// vim:ft=objc
