//
// TGClient+Tier2.m - the wire for communities, checklists, quick replies,
// suggested posts and the AI/rich-message tools.
//
// Nothing here keeps a second copy of a message: a checklist request reads
// the message through getMessage and hands the editor the eight fields it
// draws. Quick-reply messages are the one exception - TDLib sends them only
// as updates, so the cache is the list, and the screens read it.
//
#import "TGClient+Tier2.h"
#import "TGClientInternal.h"

#pragma mark - small helpers

static NSDictionary *TGTierDict(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *TGTierArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *TGTierString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *TGTierErrorText(NSDictionary *result) {
	NSString *message = result[@"message"];
	return [message isKindOfClass:NSString.class] && message.length
			? message : @"Telegram refused that.";
}

static BOOL TGTierOK(NSDictionary *result) {
	return ![result[@"@type"] isEqualToString:@"error"];
}

/// A formattedText's string, or nil when the object is not one. Used for the
/// request side, where an empty string is a real answer and nil must become
/// a JSON null.
static NSString *TGTierFormattedTextValue(id value) {
	NSDictionary *text = TGTierDict(value);
	if (![text[@"@type"] isEqualToString:@"formattedText"])
		return nil;
	return TGTierString(text[@"text"]);
}

static NSNumber *TGTierPhotoFileId(id photo) {
	NSDictionary *info = TGTierDict(photo);
	NSNumber *fileId = info[@"big"][@"id"];
	if ([fileId isKindOfClass:NSNumber.class])
		return fileId;
	fileId = info[@"small"][@"id"];
	if ([fileId isKindOfClass:NSNumber.class])
		return fileId;
	// communityFullInfo carries a chatPhoto, which has sizes instead.
	NSArray *sizes = info[@"sizes"];
	if ([sizes isKindOfClass:NSArray.class] && sizes.count){
		NSDictionary *largest = nil;
		for (NSDictionary *size in sizes){
			if (![size isKindOfClass:NSDictionary.class])
				continue;
			if (!largest ||
				[size[@"width"] doubleValue] > [largest[@"width"] doubleValue])
				largest = size;
		}
		fileId = largest[@"photo"][@"id"];
		if ([fileId isKindOfClass:NSNumber.class])
			return fileId;
	}
	return nil;
}

static NSString *TGTierCommunityStatus(NSDictionary *status) {
	NSString *type = status[@"@type"];
	if ([type isEqualToString:@"communityMemberStatusCreator"])
		return @"Owner";
	if ([type isEqualToString:@"communityMemberStatusAdministrator"])
		return @"Administrator";
	if ([type isEqualToString:@"communityMemberStatusBanned"])
		return @"Banned";
	if ([type isEqualToString:@"communityMemberStatusLeft"])
		return @"Not a member";
	return @"Member";
}

/// chat_id → title, read from the chat rows the client already holds. A
/// community chat may not be in the list yet; the id stands in then.
static NSString *TGTierChatTitle(int64_t chatId) {
	return [[TGClient shared] titleForChat:chatId];
}

static NSArray *TGTierMessagesFromResult(NSDictionary *result) {
	// quickReplyMessage and quickReplyMessages answer with one or many; the
	// send path answers a Messages object.
	NSString *type = result[@"@type"];
	NSArray *raw = nil;
	if ([type isEqualToString:@"quickReplyMessage"])
		raw = @[result];
	else if ([type isEqualToString:@"quickReplyMessages"])
		raw = TGTierArray(result[@"messages"]);
	else if ([type isEqualToString:@"messages"])
		raw = TGTierArray(result[@"messages"]);
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *message in raw){
		if (![message isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *flat = TGFlattenMessage(message);
		[out addObject:@{
			@"id"      : flat[@"id"] ?: @(0),
			@"text"    : flat[@"text"] ?: @"",
			@"kind"    : flat[@"kind"] ?: @"",
			@"photoId" : flat[@"photoId"] ?: [NSNull null],
		}];
	}
	return out;
}

static NSString *TGTierSuggestedState(NSString *type) {
	if ([type isEqualToString:@"suggestedPostStatePending"])
		return @"Pending";
	if ([type isEqualToString:@"suggestedPostStateApproved"])
		return @"Approved";
	if ([type isEqualToString:@"suggestedPostStateDeclined"])
		return @"Declined";
	return @"Unknown";
}

static NSString *TGTierSuggestedPrice(NSDictionary *price) {
	NSString *type = price[@"@type"];
	if ([type isEqualToString:@"suggestedPostPriceStar"])
		return [NSString stringWithFormat:@"%lld stars",
				(long long)[price[@"star_count"] longLongValue]];
	if ([type isEqualToString:@"suggestedPostPriceGram"])
		return [NSString stringWithFormat:@"%lld Gram",
				(long long)[price[@"gram_cent_count"] longLongValue]];
	return @"Free";
}

static NSString *TGTierActionKey(NSDictionary *action) {
	NSString *type = TGTierString(action[@"@type"]);
	if ([type isEqualToString:@"suggestedActionCustom"])
		return [type stringByAppendingFormat:@":%@", TGTierString(action[@"name"])];
	if ([type isEqualToString:@"suggestedActionConvertToBroadcastGroup"])
		return [type stringByAppendingFormat:@":%@", action[@"supergroup_id"] ?: @0];
	return type;
}

static NSString *TGTierActionTitle(NSDictionary *action) {
	if ([TGTierString(action[@"@type"]) isEqualToString:@"suggestedActionCustom"]){
		NSString *name = TGTierString(action[@"name"]);
		if (name.length)
			return name;
	}
	NSString *type = TGTierString(action[@"@type"]);
	if ([type hasPrefix:@"suggestedAction"])
		type = [type substringFromIndex:@"suggestedAction".length];
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < type.length; i++){
		unichar c = [type characterAtIndex:i];
		if (i > 0 && c >= 'A' && c <= 'Z')
			[out appendString:@" "];
		[out appendFormat:@"%C", c];
	}
	return out.length ? out : @"Suggested Action";
}

@implementation TGClient (Tier2)

#pragma mark - communities

- (NSArray *)communities {
	NSMutableArray *out = [NSMutableArray array];
	for (NSNumber *ident in self.communityOrder){
		NSDictionary *row = self.communitiesById[ident];
		if (row)
			[out addObject:row];
	}
	return out;
}

- (NSDictionary *)cachedCommunityFullInfo:(int64_t)communityId {
	NSDictionary *info = self.communityFullInfoById[@(communityId)];
	return [info isKindOfClass:NSDictionary.class] ? info : nil;
}

- (void)createCommunity:(NSString *)name
                 chatId:(int64_t)chatId
                 hidden:(BOOL)hidden
             completion:(void (^)(int64_t, NSString *))completion {
	NSString *clean = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length || !chatId){
		if (completion)
			completion(0, @"A community needs a name and a chat.");
		return;
	}
	[self request:@{
		@"@type"         : @"createCommunity",
		@"name"          : clean,
		@"chat_id"       : @(chatId),
		@"is_chat_hidden": @(hidden),
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		int64_t communityId = ok ? [result[@"id"] longLongValue] : 0;
		if (completion)
			completion(communityId, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)communityFullInfo:(int64_t)communityId
               completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!communityId){
		if (completion)
			completion(nil, @"No community was chosen.");
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"        : @"getCommunityFullInfo",
		@"community_id" : @(communityId),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSMutableArray *chats = [NSMutableArray array];
		for (NSDictionary *chat in TGTierArray(result[@"chats"])){
			int64_t chatId = [chat[@"chat_id"] longLongValue];
			if (!chatId)
				continue;
			[chats addObject:@{
				@"chatId"        : @(chatId),
				@"title"         : TGTierChatTitle(chatId) ?: [NSString stringWithFormat:
										@"Chat %lld", (long long)chatId],
				@"canViewHistory": chat[@"can_view_history"] ?: @NO,
				@"hidden"        : chat[@"is_hidden"] ?: @NO,
			}];
		}
		NSDictionary *info = @{
			@"photoFileId"         : TGTierPhotoFileId(result[@"photo"]) ?: @(0),
			@"chats"               : chats,
			@"administratorCount"  : result[@"administrator_count"] ?: @(0),
			@"bannedCount"         : result[@"banned_count"] ?: @(0),
			@"addChatRequestCount" : result[@"add_chat_request_count"] ?: @(0),
		};
		weakSelf.communityFullInfoById[@(communityId)] = info;
		if (completion)
			completion(info, nil);
	}];
}

- (void)setCommunityName:(int64_t)communityId
                    name:(NSString *)name
              completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion)
			completion(NO, @"A community needs a name.");
		return;
	}
	[self request:@{
		@"@type"        : @"setCommunityName",
		@"community_id" : @(communityId),
		@"name"         : clean,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok && communityId){
			NSMutableDictionary *row = self.communitiesById[@(communityId)];
			if (row)
				row[@"name"] = clean;
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)setCommunityPhoto:(int64_t)communityId
                     path:(NSString *)path
               completion:(void (^)(BOOL, NSString *))completion {
	NSDictionary *photo = path.length
			? @{@"@type" : @"inputChatPhotoStatic",
				@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path}}
			: [NSNull null];
	[self request:@{
		@"@type"        : @"setCommunityPhoto",
		@"community_id" : @(communityId),
		@"photo"        : photo,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)setCommunityPermissions:(int64_t)communityId
                  canEditChatList:(BOOL)canEditChatList
                      completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"        : @"setCommunityPermissions",
		@"community_id" : @(communityId),
		@"permissions"  : @{
			@"@type"             : @"communityPermissions",
			@"can_edit_chat_list": @(canEditChatList),
		},
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok && communityId){
			NSMutableDictionary *row = self.communitiesById[@(communityId)];
			if (row)
				row[@"canEditChatList"] = @(canEditChatList);
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)deleteCommunity:(int64_t)communityId
             completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"        : @"deleteCommunity",
		@"community_id" : @(communityId),
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok && communityId){
			[self.communitiesById removeObjectForKey:@(communityId)];
			[self.communityOrder removeObject:@(communityId)];
			[self.communityFullInfoById removeObjectForKey:@(communityId)];
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

#pragma mark - quick replies

- (NSArray *)quickReplyShortcuts {
	NSMutableArray *out = [NSMutableArray array];
	for (NSNumber *ident in self.quickReplyShortcutOrder){
		NSDictionary *row = self.quickReplyShortcutsById[ident];
		if (row)
			[out addObject:row];
	}
	return out;
}

- (void)loadQuickReplyShortcutsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"loadQuickReplyShortcuts"}
	   completion:^(NSDictionary *result){
		TGClient *strong = weakSelf;
		if (!strong){
			if (completion)
				completion(@[]);
			return;
		}
		// The answer is Ok; the shortcuts themselves arrive as updates. A
		// caller that gets here first still sees whatever the cache holds.
		if (!TGTierOK(result) && !strong.quickReplyShortcutOrder.count){
			if (completion)
				completion(@[]);
			return;
		}
		if (completion)
			completion(strong.quickReplyShortcuts);
	}];
}

- (void)loadQuickReplyMessagesForShortcut:(NSInteger)shortcutId
                               completion:(void (^)(NSArray *))completion {
	if (!shortcutId){
		if (completion)
			completion(@[]);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"loadQuickReplyShortcutMessages",
		@"shortcut_id" : @(shortcutId),
	} completion:^(NSDictionary *result){
		TGClient *strong = weakSelf;
		NSArray *messages = strong.quickReplyMessagesByShortcut[@(shortcutId)];
		if (!TGTierOK(result) && !messages){
			if (completion)
				completion(@[]);
			return;
		}
		if (completion)
			completion(messages ?: @[]);
	}];
}

- (void)checkQuickReplyShortcutName:(NSString *)name
                         completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion)
			completion(NO, @"A shortcut needs a name.");
		return;
	}
	[self request:@{
		@"@type" : @"checkQuickReplyShortcutName",
		@"name"  : clean,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)setQuickReplyShortcutName:(NSInteger)shortcutId
                             name:(NSString *)name
                       completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [name stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion)
			completion(NO, @"A shortcut needs a name.");
		return;
	}
	[self request:@{
		@"@type"       : @"setQuickReplyShortcutName",
		@"shortcut_id" : @(shortcutId),
		@"name"        : clean,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok && shortcutId){
			NSMutableDictionary *row = self.quickReplyShortcutsById[@(shortcutId)];
			if (row)
				row[@"name"] = clean;
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)deleteQuickReplyShortcut:(NSInteger)shortcutId
                      completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"       : @"deleteQuickReplyShortcut",
		@"shortcut_id" : @(shortcutId),
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok && shortcutId){
			[self.quickReplyShortcutsById removeObjectForKey:@(shortcutId)];
			[self.quickReplyShortcutOrder removeObject:@(shortcutId)];
			[self.quickReplyMessagesByShortcut removeObjectForKey:@(shortcutId)];
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)reorderQuickReplyShortcuts:(NSArray *)shortcutIds
                        completion:(void (^)(BOOL, NSString *))completion {
	NSArray *ids = shortcutIds ?: @[];
	[self request:@{
		@"@type"        : @"reorderQuickReplyShortcuts",
		@"shortcut_ids" : ids,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok){
			[self.quickReplyShortcutOrder removeAllObjects];
			for (NSNumber *ident in ids)
				[self.quickReplyShortcutOrder addObject:ident];
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)addQuickReplyShortcutMessage:(NSString *)shortcutName
                                text:(NSString *)text
                          completion:(void (^)(NSDictionary *, NSString *))completion {
	NSString *clean = [shortcutName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length || !text.length){
		if (completion)
			completion(nil, @"A shortcut needs a name and a message.");
		return;
	}
	[self request:@{
		@"@type"                : @"addQuickReplyShortcutMessage",
		@"shortcut_name"        : clean,
		@"reply_to_message_id"  : @(0),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : TGFormattedText(text),
		},
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSDictionary *flat = TGTierMessagesFromResult(result).firstObject;
		if (completion)
			completion(flat, nil);
	}];
}

- (void)addQuickReplyShortcutMessageAlbum:(NSString *)shortcutName
                                    texts:(NSArray *)texts
                               completion:(void (^)(NSArray *, NSString *))completion {
	NSString *clean = [shortcutName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSMutableArray *contents = [NSMutableArray array];
	for (NSString *text in texts){
		if (![text isKindOfClass:NSString.class] || !text.length)
			continue;
		[contents addObject:@{@"@type" : @"inputMessageText",
							  @"text"  : TGFormattedText(text)}];
	}
	if (!clean.length || contents.count < 2){
		if (completion)
			completion(@[], @"An album needs a name and at least two messages.");
		return;
	}
	[self request:@{
		@"@type"                 : @"addQuickReplyShortcutMessageAlbum",
		@"shortcut_name"         : clean,
		@"reply_to_message_id"   : @(0),
		@"input_message_contents": contents,
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(@[], TGTierErrorText(result));
			return;
		}
		if (completion)
			completion(TGTierMessagesFromResult(result), nil);
	}];
}

- (void)editQuickReplyMessage:(int64_t)messageId
                   shortcutId:(NSInteger)shortcutId
                         text:(NSString *)text
                   completion:(void (^)(BOOL, NSString *))completion {
	if (!messageId || !text.length){
		if (completion)
			completion(NO, @"A message needs text.");
		return;
	}
	[self request:@{
		@"@type"                : @"editQuickReplyMessage",
		@"shortcut_id"          : @(shortcutId),
		@"message_id"           : @(messageId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : TGFormattedText(text),
		},
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)deleteQuickReplyShortcutMessages:(NSArray *)messageIds
                              shortcutId:(NSInteger)shortcutId
                              completion:(void (^)(BOOL, NSString *))completion {
	NSArray *ids = messageIds ?: @[];
	if (!ids.count){
		if (completion)
			completion(NO, @"No messages were chosen.");
		return;
	}
	[self request:@{
		@"@type"       : @"deleteQuickReplyShortcutMessages",
		@"shortcut_id" : @(shortcutId),
		@"message_ids" : ids,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok){
			NSMutableArray *cached = self.quickReplyMessagesByShortcut[@(shortcutId)];
			if (cached){
				for (NSNumber *ident in ids){
					for (NSUInteger i = 0; i < cached.count; i++){
						if ([cached[i][@"id"] isEqualToNumber:ident]){
							[cached removeObjectAtIndex:i];
							break;
						}
					}
				}
			}
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)readdQuickReplyShortcutMessages:(NSArray *)messageIds
                           shortcutName:(NSString *)shortcutName
                             completion:(void (^)(NSArray *, NSString *))completion {
	NSString *clean = [shortcutName stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSArray *ids = messageIds ?: @[];
	if (!clean.length || !ids.count){
		if (completion)
			completion(@[], @"No removed messages to put back.");
		return;
	}
	[self request:@{
		@"@type"         : @"readdQuickReplyShortcutMessages",
		@"shortcut_name" : clean,
		@"message_ids"   : ids,
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(@[], TGTierErrorText(result));
			return;
		}
		if (completion)
			completion(TGTierMessagesFromResult(result), nil);
	}];
}

- (void)sendQuickReplyShortcutMessages:(NSInteger)shortcutId
                                toChat:(int64_t)chatId
                             sendingId:(int32_t)sendingId
                            completion:(void (^)(NSArray *, NSString *))completion {
	[self request:@{
		@"@type"       : @"sendQuickReplyShortcutMessages",
		@"chat_id"     : @(chatId),
		@"shortcut_id" : @(shortcutId),
		@"sending_id"  : @(sendingId),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(@[], TGTierErrorText(result));
			return;
		}
		if (completion)
			completion(TGTierMessagesFromResult(result), nil);
	}];
}

#pragma mark - checklists

- (void)checklistForMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *, NSString *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"      : @"getMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *message){
		if (!TGTierOK(message)){
			if (completion)
				completion(nil, TGTierErrorText(message));
			return;
		}
		NSDictionary *content = TGTierDict(message[@"content"]);
		if (![content[@"@type"] isEqualToString:@"messageChecklist"]){
			if (completion)
				completion(nil, @"That message has no checklist.");
			return;
		}
		NSDictionary *list = TGTierDict(content[@"checklist"]);
		NSMutableArray *tasks = [NSMutableArray array];
		for (NSDictionary *task in TGTierArray(list[@"tasks"])){
			id completedBy = task[@"completed_by"];
			BOOL done = completedBy && ![completedBy isKindOfClass:NSNull.class];
			[tasks addObject:@{
				@"id"   : task[@"id"] ?: @(0),
				@"text" : TGTierDict(task[@"text"])[@"text"] ?: @"",
				@"done" : @(done),
			}];
		}
		NSDictionary *checklist = @{
			@"title"            : TGTierDict(list[@"title"])[@"text"] ?: @"",
			@"tasks"            : tasks,
			@"canAddTasks"      : list[@"can_add_tasks"] ?: @NO,
			@"canMarkTasks"     : list[@"can_mark_tasks_as_done"] ?: @NO,
			@"othersCanAddTasks": list[@"others_can_add_tasks"] ?: @NO,
			@"othersCanMarkTasks": list[@"others_can_mark_tasks_as_done"] ?: @NO,
		};
		weakSelf.checklistCache[@(messageId)] = checklist;
		if (completion)
			completion(checklist, nil);
	}];
}

- (void)editMessageChecklist:(int64_t)messageId
                      inChat:(int64_t)chatId
                       title:(NSString *)title
                       tasks:(NSArray *)tasks
                othersCanAdd:(BOOL)othersCanAdd
              othersCanMark:(BOOL)othersCanMark
                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"      : @"editMessageChecklist",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"reply_markup": [NSNull null],
		@"checklist"  : [TGClient inputChecklistWithTitle:title
													tasks:tasks
											 othersCanAdd:othersCanAdd
											othersCanMark:othersCanMark],
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok)
			[self.checklistCache removeObjectForKey:@(messageId)];
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)addChecklistTasks:(NSArray *)tasks
                toMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
               completion:(void (^)(BOOL, NSString *))completion {
	NSMutableArray *input = [NSMutableArray array];
	for (NSDictionary *task in tasks){
		NSString *text = TGTierString(task[@"text"]);
		if (!text.length)
			continue;
		[input addObject:@{
			@"@type" : @"inputChecklistTask",
			@"id"    : @([task[@"id"] integerValue]),
			@"text"  : TGFormattedText(text),
		}];
	}
	if (!input.count){
		if (completion)
			completion(NO, @"No task to add.");
		return;
	}
	[self request:@{
		@"@type"      : @"addChecklistTasks",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"tasks"      : input,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok)
			[self.checklistCache removeObjectForKey:@(messageId)];
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)markChecklistTasksAsDone:(NSArray *)doneTaskIds
                    notDoneTaskIds:(NSArray *)notDoneTaskIds
                         onMessage:(int64_t)messageId
                            inChat:(int64_t)chatId
                        completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"                    : @"markChecklistTasksAsDone",
		@"chat_id"                  : @(chatId),
		@"message_id"               : @(messageId),
		@"marked_as_done_task_ids"  : doneTaskIds ?: @[],
		@"marked_as_not_done_task_ids": notDoneTaskIds ?: @[],
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok)
			[self.checklistCache removeObjectForKey:@(messageId)];
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)sendChecklist:(NSString *)title
                tasks:(NSArray *)tasks
               toChat:(int64_t)chatId
           completion:(void (^)(BOOL, NSString *))completion {
	NSMutableArray *input = [NSMutableArray array];
	for (NSDictionary *task in tasks){
		NSString *text = TGTierString(task[@"text"]);
		if (!text.length)
			continue;
		[input addObject:@{
			@"@type" : @"inputChecklistTask",
			@"id"    : @(0),
			@"text"  : TGFormattedText(text),
		}];
	}
	if (!title.length || !input.count){
		if (completion)
			completion(NO, @"A checklist needs a title and a task.");
		return;
	}
	[self request:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type"     : @"inputMessageChecklist",
			@"checklist" : [TGClient inputChecklistWithTitle:title
													  tasks:input
											   othersCanAdd:YES
											  othersCanMark:YES],
		},
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

#pragma mark - suggested posts and actions

- (void)suggestedPostForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type"      : @"getMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *message){
		if (!TGTierOK(message)){
			if (completion)
				completion(nil, TGTierErrorText(message));
			return;
		}
		NSDictionary *info = TGTierDict(message[@"suggested_post_info"]);
		if (![info isKindOfClass:NSDictionary.class] || !info.count ||
			[info isKindOfClass:NSNull.class]){
			if (completion)
				completion(nil, @"That message is not a suggested post.");
			return;
		}
		NSDictionary *post = @{
			@"price"        : TGTierSuggestedPrice(TGTierDict(info[@"price"])),
			@"sendDate"     : info[@"send_date"] ?: @(0),
			@"state"        : TGTierSuggestedState(TGTierString(info[@"state"][@"@type"])),
			@"canBeApproved": info[@"can_be_approved"] ?: @NO,
			@"canBeDeclined": info[@"can_be_declined"] ?: @NO,
		};
		if (completion)
			completion(post, nil);
	}];
}

- (void)approveSuggestedPost:(int64_t)messageId
                      inChat:(int64_t)chatId
                    sendDate:(NSInteger)sendDate
                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"      : @"approveSuggestedPost",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"send_date"  : @(sendDate),
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)declineSuggestedPost:(int64_t)messageId
                      inChat:(int64_t)chatId
                     comment:(NSString *)comment
                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"      : @"declineSuggestedPost",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"comment"    : comment ?: @"",
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (NSArray *)suggestedActions {
	return self.suggestedActionsValue ?: @[];
}

- (void)hideSuggestedAction:(NSDictionary *)action
                 completion:(void (^)(BOOL, NSString *))completion {
	NSDictionary *object = TGTierDict(action[@"action"]);
	if (!object.count){
		if (completion)
			completion(NO, @"No suggested action was chosen.");
		return;
	}
	[self request:@{
		@"@type"  : @"hideSuggestedAction",
		@"action" : object,
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (ok){
			NSString *key = TGTierActionKey(object);
			NSMutableArray *kept = [NSMutableArray array];
			for (NSDictionary *row in self.suggestedActionsValue){
				if (![TGTierActionKey(TGTierDict(row[@"action"])) isEqualToString:key])
					[kept addObject:row];
			}
			self.suggestedActionsValue = kept;
		}
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

#pragma mark - AI text and rich messages

- (void)composeTextWithAi:(NSString *)text
         translateTo:(NSString *)languageCode
               style:(NSString *)styleName
           addEmojis:(BOOL)addEmojis
          completion:(void (^)(NSString *, NSString *))completion {
	NSString *clean = text ?: @"";
	if (!clean.length){
		if (completion)
			completion(nil, @"There is no text to compose.");
		return;
	}
	[self request:@{
		@"@type"                   : @"composeTextWithAi",
		@"text"                    : TGFormattedText(clean),
		@"translate_to_language_code": languageCode ?: @"",
		@"style_name"              : styleName ?: @"",
		@"add_emojis"              : @(addEmojis),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = TGTierFormattedTextValue(result);
		if (completion)
			completion(answer, answer ? nil : TGTierErrorText(result));
	}];
}

- (void)composeRichMessageWithAi:(NSString *)text
                     translateTo:(NSString *)languageCode
                           style:(NSString *)styleName
                    customPrompt:(NSString *)customPrompt
                       addEmojis:(BOOL)addEmojis
                      completion:(void (^)(NSString *, NSString *))completion {
	NSString *clean = text ?: @"";
	if (!clean.length){
		if (completion)
			completion(nil, @"There is no text to compose.");
		return;
	}
	[self request:@{
		@"@type"                     : @"composeRichMessageWithAi",
		@"message"                   : [TGClient inputRichMessageWithText:clean],
		@"translate_to_language_code": languageCode ?: @"",
		@"style_name"                : styleName ?: @"",
		@"custom_prompt"             : customPrompt ?: @"",
		@"add_emojis"                : @(addEmojis),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = [TGClient plainTextFromRichMessage:result];
		if (completion)
			completion(answer, answer.length ? nil : TGTierErrorText(result));
	}];
}

- (void)createRichMessageWithAi:(NSString *)prompt
                   languageCode:(NSString *)languageCode
                      addEmojis:(BOOL)addEmojis
                     completion:(void (^)(NSString *, NSString *))completion {
	NSString *clean = [prompt stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length){
		if (completion)
			completion(nil, @"A prompt is needed.");
		return;
	}
	[self request:@{
		@"@type"        : @"createRichMessageWithAi",
		@"prompt"       : clean,
		@"language_code": languageCode ?: @"",
		@"add_emojis"   : @(addEmojis),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = [TGClient plainTextFromRichMessage:result];
		if (completion)
			completion(answer, answer.length ? nil : TGTierErrorText(result));
	}];
}

- (void)fixTextWithAi:(NSString *)text
           completion:(void (^)(NSString *, NSString *, NSString *))completion {
	NSString *clean = text ?: @"";
	if (!clean.length){
		if (completion)
			completion(nil, nil, @"There is no text to fix.");
		return;
	}
	[self request:@{
		@"@type" : @"fixTextWithAi",
		@"text"  : TGFormattedText(clean),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, nil, TGTierErrorText(result));
			return;
		}
		NSString *fixed = TGTierFormattedTextValue(result[@"text"]);
		NSString *diff = TGTierString(TGTierDict(result[@"diff_text"])[@"text"]);
		if (completion)
			completion(fixed, diff, fixed ? nil : TGTierErrorText(result));
	}];
}

- (void)fixRichMessageWithAi:(NSString *)text
                  completion:(void (^)(NSString *, NSString *))completion {
	NSString *clean = text ?: @"";
	if (!clean.length){
		if (completion)
			completion(nil, @"There is no text to fix.");
		return;
	}
	[self request:@{
		@"@type"   : @"fixRichMessageWithAi",
		@"message" : [TGClient inputRichMessageWithText:clean],
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = [TGClient plainTextFromRichMessage:result];
		if (completion)
			completion(answer, answer.length ? nil : TGTierErrorText(result));
	}];
}

- (void)summarizeMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
             translateTo:(NSString *)languageCode
                    tone:(NSString *)tone
              completion:(void (^)(NSString *, NSString *))completion {
	[self request:@{
		@"@type"                     : @"summarizeMessage",
		@"chat_id"                   : @(chatId),
		@"message_id"                : @(messageId),
		@"translate_to_language_code": languageCode ?: @"",
		@"tone"                      : tone ?: @"",
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = TGTierFormattedTextValue(result);
		if (completion)
			completion(answer, answer ? nil : TGTierErrorText(result));
	}];
}

- (void)translateMessageRichMessage:(int64_t)messageId
                             inChat:(int64_t)chatId
                             toCode:(NSString *)languageCode
                               tone:(NSString *)tone
                         completion:(void (^)(NSString *, NSString *))completion {
	[self request:@{
		@"@type"          : @"translateMessageRichMessage",
		@"chat_id"        : @(chatId),
		@"message_id"     : @(messageId),
		@"to_language_code": languageCode ?: @"en",
		@"tone"           : tone ?: @"",
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = [TGClient plainTextFromRichMessage:result];
		if (completion)
			completion(answer, answer.length ? nil : TGTierErrorText(result));
	}];
}

- (void)translateRichMessage:(NSString *)text
                      toCode:(NSString *)languageCode
                        tone:(NSString *)tone
                  completion:(void (^)(NSString *, NSString *))completion {
	NSString *clean = text ?: @"";
	if (!clean.length){
		if (completion)
			completion(nil, @"There is no text to translate.");
		return;
	}
	[self request:@{
		@"@type"           : @"translateRichMessage",
		@"message"         : [TGClient inputRichMessageWithText:clean],
		@"to_language_code": languageCode ?: @"en",
		@"tone"            : tone ?: @"",
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, TGTierErrorText(result));
			return;
		}
		NSString *answer = [TGClient plainTextFromRichMessage:result];
		if (completion)
			completion(answer, answer.length ? nil : TGTierErrorText(result));
	}];
}

- (void)getFullRichMessage:(int64_t)messageId
                    inChat:(int64_t)chatId
                completion:(void (^)(NSString *, NSDictionary *, NSString *))completion {
	[self request:@{
		@"@type"      : @"getFullRichMessage",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
	} completion:^(NSDictionary *result){
		if (!TGTierOK(result)){
			if (completion)
				completion(nil, nil, TGTierErrorText(result));
			return;
		}
		NSString *text = [TGClient plainTextFromRichMessage:result];
		if (completion)
			completion(text, result, text.length ? nil : TGTierErrorText(result));
	}];
}

- (void)sendRichMessageDraft:(NSString *)text
                      toChat:(int64_t)chatId
                     topicId:(int32_t)topicId
                     draftId:(int64_t)draftId
                     canStop:(BOOL)canStop
                  keepOnStop:(BOOL)keepOnStop
                  completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{
		@"@type"         : @"sendRichMessageDraft",
		@"chat_id"       : @(chatId),
		@"forum_topic_id": @(topicId),
		@"draft_id"      : @(draftId),
		@"can_stop"      : @(canStop),
		@"keep_on_stop"  : @(keepOnStop),
		@"message"       : [TGClient inputRichMessageWithText:text],
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

- (void)setMessageFactCheck:(int64_t)messageId
                     inChat:(int64_t)chatId
                       text:(NSString *)text
                 completion:(void (^)(BOOL, NSString *))completion {
	NSString *clean = [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[self request:@{
		@"@type"      : @"setMessageFactCheck",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"text"       : clean.length ? TGFormattedText(clean) : [NSNull null],
	} completion:^(NSDictionary *result){
		BOOL ok = TGTierOK(result);
		if (completion)
			completion(ok, ok ? nil : TGTierErrorText(result));
	}];
}

#pragma mark - shared shapes

/// richText is a tree; headings, links and bold wrap one more level, so the
/// leaf's text is what every caller wants.
static NSString *TGTierRichTextPlain(id value) {
	NSDictionary *text = TGTierDict(value);
	NSString *type = TGTierString(text[@"@type"]);
	if ([type isEqualToString:@"richTextPlain"])
		return TGTierString(text[@"text"]);
	if ([type isEqualToString:@"richTextCustomEmoji"]){
		NSString *alternative = TGTierString(text[@"alternative_text"]);
		return alternative.length ? alternative : @"";
	}
	if ([type isEqualToString:@"richTextUrl"]){
		NSString *label = TGTierRichTextPlain(text[@"text"]);
		return label.length ? label : TGTierString(text[@"url"]);
	}
	if ([type isEqualToString:@"richTextEmailAddress"]){
		NSString *label = TGTierRichTextPlain(text[@"text"]);
		return label.length ? label : TGTierString(text[@"email_address"]);
	}
	if ([type isEqualToString:@"richTextPhoneNumber"]){
		NSString *label = TGTierRichTextPlain(text[@"text"]);
		return label.length ? label : TGTierString(text[@"phone_number"]);
	}
	if ([type isEqualToString:@"richTextAnchor"] || [type isEqualToString:@"richTextAnchorLink"] ||
		[type isEqualToString:@"richTextReference"] || [type isEqualToString:@"richTextReferenceLink"] ||
		[type isEqualToString:@"richTextMention"] || [type isEqualToString:@"richTextHashtag"] ||
		[type isEqualToString:@"richTextCashtag"] || [type isEqualToString:@"richTextBotCommand"] ||
		[type isEqualToString:@"richTextBankCardNumber"] || [type isEqualToString:@"richTextTonAddress"] ||
		[type isEqualToString:@"richTextFixed"] || [type isEqualToString:@"richTextBold"] ||
		[type isEqualToString:@"richTextItalic"] || [type isEqualToString:@"richTextUnderline"] ||
		[type isEqualToString:@"richTextStrikethrough"] || [type isEqualToString:@"richTextSpoiler"] ||
		[type isEqualToString:@"richTextSubscript"] || [type isEqualToString:@"richTextSuperscript"] ||
		[type isEqualToString:@"richTextMarked"] ||
		[type isEqualToString:@"richTextDateTime"]){
		return TGTierRichTextPlain(text[@"text"]);
	}
	if ([type isEqualToString:@"richTextMathematicalExpression"])
		return TGTierString(text[@"expression"]);
	// A shape this client cannot read still often has a label somewhere.
	NSString *leaf = TGTierRichTextPlain(text[@"text"]);
	return leaf;
}

static void TGTierFlattenBlocks(NSArray *blocks, NSMutableArray *lines);

static NSString *TGTierPageBlockText(NSDictionary *block) {
	NSString *type = TGTierString(block[@"@type"]);
	if ([type isEqualToString:@"pageBlockParagraph"] ||
		[type isEqualToString:@"pageBlockSectionHeading"] ||
		[type isEqualToString:@"pageBlockPreformatted"] ||
		[type isEqualToString:@"pageBlockFooter"] ||
		[type isEqualToString:@"pageBlockThinking"]){
		return TGTierRichTextPlain(block[@"text"]);
	}
	if ([type isEqualToString:@"pageBlockMathematicalExpression"])
		return TGTierString(block[@"expression"]);
	if ([type isEqualToString:@"pageBlockDivider"])
		return @"—";
	if ([type isEqualToString:@"pageBlockAnchor"])
		return @"";
	if ([type isEqualToString:@"pageBlockPhoto"] || [type isEqualToString:@"pageBlockVideo"] ||
		[type isEqualToString:@"pageBlockAnimation"] || [type isEqualToString:@"pageBlockAudio"] ||
		[type isEqualToString:@"pageBlockVoiceNote"] || [type isEqualToString:@"pageBlockDocument"] ||
		[type isEqualToString:@"pageBlockMap"]){
		return TGTierRichTextPlain(TGTierDict(block[@"caption"])[@"text"]);
	}
	return @"";
}

static void TGTierFlattenBlocks(NSArray *blocks, NSMutableArray *lines) {
	for (NSDictionary *block in blocks){
		if (![block isKindOfClass:NSDictionary.class])
			continue;
		NSString *type = TGTierString(block[@"@type"]);
		if ([type isEqualToString:@"pageBlockList"]){
			for (NSDictionary *item in TGTierArray(block[@"items"])){
				NSMutableArray *itemLines = [NSMutableArray array];
				TGTierFlattenBlocks(TGTierArray(item[@"blocks"]), itemLines);
				BOOL checked = [item[@"is_checked"] boolValue];
				NSString *marker = [item[@"has_checkbox"] boolValue] ? (checked ? @"☑ " : @"☐ ") : @"• ";
				NSString *body = [itemLines componentsJoinedByString:@"\n"];
				[lines addObject:[marker stringByAppendingString:body]];
			}
			continue;
		}
		if ([type isEqualToString:@"pageBlockBlockQuote"] ||
			[type isEqualToString:@"pageBlockExpandableBlockQuote"] ||
			[type isEqualToString:@"pageBlockCollage"] ||
			[type isEqualToString:@"pageBlockSlideshow"] ||
			[type isEqualToString:@"pageBlockDetails"]){
			NSMutableArray *inner = [NSMutableArray array];
			TGTierFlattenBlocks(TGTierArray(block[@"blocks"]), inner);
			if ([type isEqualToString:@"pageBlockBlockQuote"] ||
				[type isEqualToString:@"pageBlockExpandableBlockQuote"] ||
				[type isEqualToString:@"pageBlockDetails"]){
				NSString *credit = TGTierRichTextPlain(block[@"credit"]);
				if (!credit.length)
					credit = TGTierRichTextPlain(block[@"header"]);
				if (credit.length)
					[inner addObject:credit];
			}
			if (inner.count)
				[lines addObject:[inner componentsJoinedByString:@"\n"]];
			continue;
		}
		if ([type isEqualToString:@"pageBlockPullQuote"]){
			NSString *quote = TGTierRichTextPlain(block[@"text"]);
			NSString *credit = TGTierRichTextPlain(block[@"credit"]);
			if (credit.length)
				quote = [quote stringByAppendingFormat:@"\n%@", credit];
			if (quote.length)
				[lines addObject:quote];
			continue;
		}
		if ([type isEqualToString:@"pageBlockTable"]){
			for (NSArray *row in TGTierArray(block[@"cells"])){
				NSMutableArray *cells = [NSMutableArray array];
				for (NSDictionary *cell in TGTierArray(row)){
					NSString *text = TGTierRichTextPlain(cell[@"text"]);
					if (text.length)
						[cells addObject:text];
				}
				if (cells.count)
					[lines addObject:[cells componentsJoinedByString:@" | "]];
			}
			continue;
		}
		NSString *text = TGTierPageBlockText(block);
		if (text.length)
			[lines addObject:text];
	}
}

+ (NSDictionary *)inputRichMessageWithText:(NSString *)text {
	NSString *body = text ?: @"";
	NSMutableArray *blocks = [NSMutableArray array];
	// One paragraph per line: a rich editor is not what this is, and folding
	// a newline into a paragraph would lose the line break Telegram draws.
	NSArray *lines = [body componentsSeparatedByString:@"\n"];
	for (NSString *line in lines){
		[blocks addObject:@{
			@"@type" : @"inputPageBlockParagraph",
			@"text"  : @{@"@type" : @"richTextPlain",
						 @"text"  : line ?: @""},
		}];
	}
	if (!blocks.count){
		[blocks addObject:@{
			@"@type" : @"inputPageBlockParagraph",
			@"text"  : @{@"@type" : @"richTextPlain", @"text" : @""},
		}];
	}
	return @{
		@"@type" : @"inputRichMessage",
		@"source": @{
			@"@type" : @"richMessageSourceBlocks",
			@"blocks": blocks,
		},
		@"is_rtl"                : @NO,
		@"detect_automatic_blocks": @YES,
	};
}

+ (NSString *)plainTextFromRichMessage:(NSDictionary *)richMessage {
	NSMutableArray *lines = [NSMutableArray array];
	TGTierFlattenBlocks(TGTierArray(TGTierDict(richMessage)[@"blocks"]), lines);
	return [lines componentsJoinedByString:@"\n"];
}

+ (NSDictionary *)inputChecklistWithTitle:(NSString *)title
                                    tasks:(NSArray *)tasks
                              othersCanAdd:(BOOL)othersCanAdd
                             othersCanMark:(BOOL)othersCanMark {
	NSMutableArray *input = [NSMutableArray array];
	for (NSDictionary *task in tasks){
		if ([task isKindOfClass:NSDictionary.class] &&
			[task[@"@type"] isEqualToString:@"inputChecklistTask"]){
			[input addObject:task];
			continue;
		}
		NSString *text = TGTierString(task[@"text"]);
		if (!text.length)
			continue;
		[input addObject:@{
			@"@type" : @"inputChecklistTask",
			@"id"    : @([task[@"id"] integerValue]),
			@"text"  : TGFormattedText(text),
		}];
	}
	return @{
		@"@type"                   : @"inputChecklist",
		@"title"                   : TGFormattedText(title ?: @""),
		@"tasks"                   : input,
		@"others_can_add_tasks"    : @(othersCanAdd),
		@"others_can_mark_tasks_as_done": @(othersCanMark),
	};
}

#pragma mark - update cache

- (void)applyCommunityUpdate:(NSDictionary *)update {
	NSDictionary *community = TGTierDict(update[@"community"]);
	NSNumber *ident = community[@"id"];
	if (![ident isKindOfClass:NSNumber.class])
		return;
	if (!self.communitiesById)
		self.communitiesById = [NSMutableDictionary dictionary];
	if (!self.communityOrder)
		self.communityOrder = [NSMutableArray array];
	NSDictionary *row = @{
		@"id"             : ident,
		@"name"           : community[@"name"] ?: @"",
		@"haveAccess"     : community[@"have_access"] ?: @NO,
		@"date"           : community[@"date"] ?: @(0),
		@"status"         : TGTierCommunityStatus(TGTierDict(community[@"status"])),
		@"photoFileId"    : TGTierPhotoFileId(community[@"photo"]) ?: @(0),
		@"canEditChatList": TGTierDict(community[@"permissions"])[@"can_edit_chat_list"] ?: @NO,
	};
	self.communitiesById[ident] = [row mutableCopy];
	if (![self.communityOrder containsObject:ident])
		[self.communityOrder insertObject:ident atIndex:0];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGCommunitiesChangedNotification object:nil];
}

- (void)applyCommunityFullInfoUpdate:(NSDictionary *)update {
	NSNumber *ident = update[@"community_id"];
	NSDictionary *info = TGTierDict(update[@"community_full_info"]);
	if (![ident isKindOfClass:NSNumber.class] || !info.count)
		return;
	if (!self.communityFullInfoById)
		self.communityFullInfoById = [NSMutableDictionary dictionary];
	NSMutableArray *chats = [NSMutableArray array];
	for (NSDictionary *chat in TGTierArray(info[@"chats"])){
		int64_t chatId = [chat[@"chat_id"] longLongValue];
		if (!chatId)
			continue;
		[chats addObject:@{
			@"chatId"        : @(chatId),
			@"title"         : TGTierChatTitle(chatId) ?: [NSString stringWithFormat:
									@"Chat %lld", (long long)chatId],
			@"canViewHistory": chat[@"can_view_history"] ?: @NO,
			@"hidden"        : chat[@"is_hidden"] ?: @NO,
		}];
	}
	self.communityFullInfoById[ident] = @{
		@"photoFileId"         : TGTierPhotoFileId(info[@"photo"]) ?: @(0),
		@"chats"               : chats,
		@"administratorCount"  : info[@"administrator_count"] ?: @(0),
		@"bannedCount"         : info[@"banned_count"] ?: @(0),
		@"addChatRequestCount" : info[@"add_chat_request_count"] ?: @(0),
	};
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGCommunitiesChangedNotification object:nil];
}

- (void)applyQuickReplyShortcutUpdate:(NSDictionary *)update {
	NSDictionary *shortcut = TGTierDict(update[@"shortcut"]);
	NSNumber *ident = shortcut[@"id"];
	if (![ident isKindOfClass:NSNumber.class])
		return;
	if (!self.quickReplyShortcutsById)
		self.quickReplyShortcutsById = [NSMutableDictionary dictionary];
	if (!self.quickReplyShortcutOrder)
		self.quickReplyShortcutOrder = [NSMutableArray array];
	NSDictionary *first = TGTierDict(shortcut[@"first_message"]);
	NSString *preview = first.count ? (TGFlattenMessage(first)[@"text"] ?: @"") : @"";
	self.quickReplyShortcutsById[ident] = [@{
		@"id"          : ident,
		@"name"        : shortcut[@"name"] ?: @"",
		@"messageCount": shortcut[@"message_count"] ?: @(0),
		@"preview"     : preview,
	} mutableCopy];
	if (![self.quickReplyShortcutOrder containsObject:ident])
		[self.quickReplyShortcutOrder addObject:ident];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGQuickRepliesChangedNotification object:nil];
}

- (void)applyQuickReplyShortcutDeleted:(NSDictionary *)update {
	NSNumber *ident = update[@"shortcut_id"];
	if (![ident isKindOfClass:NSNumber.class])
		return;
	[self.quickReplyShortcutsById removeObjectForKey:ident];
	[self.quickReplyShortcutOrder removeObject:ident];
	[self.quickReplyMessagesByShortcut removeObjectForKey:ident];
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGQuickRepliesChangedNotification object:nil];
}

- (void)applyQuickReplyShortcutsUpdate:(NSDictionary *)update {
	NSArray *ids = TGTierArray(update[@"shortcut_ids"]);
	if (!self.quickReplyShortcutOrder)
		self.quickReplyShortcutOrder = [NSMutableArray array];
	[self.quickReplyShortcutOrder removeAllObjects];
	for (NSNumber *ident in ids){
		if ([ident isKindOfClass:NSNumber.class])
			[self.quickReplyShortcutOrder addObject:ident];
	}
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGQuickRepliesChangedNotification object:nil];
}

- (void)applyQuickReplyShortcutMessagesUpdate:(NSDictionary *)update {
	NSNumber *ident = update[@"shortcut_id"];
	if (![ident isKindOfClass:NSNumber.class])
		return;
	if (!self.quickReplyMessagesByShortcut)
		self.quickReplyMessagesByShortcut = [NSMutableDictionary dictionary];
	NSMutableArray *messages = [NSMutableArray array];
	for (NSDictionary *message in TGTierArray(update[@"messages"])){
		if (![message isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *flat = TGFlattenMessage(message);
		[messages addObject:@{
			@"id"      : flat[@"id"] ?: @(0),
			@"text"    : flat[@"text"] ?: @"",
			@"kind"    : flat[@"kind"] ?: @"",
			@"photoId" : flat[@"photoId"] ?: [NSNull null],
		}];
	}
	self.quickReplyMessagesByShortcut[ident] = messages;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGQuickRepliesChangedNotification object:nil];
}

- (void)applySuggestedActionsUpdate:(NSDictionary *)update {
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableSet *removed = [NSMutableSet set];
	for (NSDictionary *action in TGTierArray(update[@"removed_actions"])){
		if ([action isKindOfClass:NSDictionary.class])
			[removed addObject:TGTierActionKey(action)];
	}
	for (NSDictionary *row in self.suggestedActionsValue){
		NSDictionary *action = TGTierDict(row[@"action"]);
		if (![removed containsObject:TGTierActionKey(action)])
			[rows addObject:row];
	}
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *row in rows)
		[seen addObject:TGTierActionKey(TGTierDict(row[@"action"]))];
	for (NSDictionary *action in TGTierArray(update[@"added_actions"])){
		if (![action isKindOfClass:NSDictionary.class])
			continue;
		NSString *key = TGTierActionKey(action);
		if ([seen containsObject:key])
			continue;
		[seen addObject:key];
		[rows addObject:@{
			@"title" : TGTierActionTitle(action),
			@"action": action,
		}];
	}
	self.suggestedActionsValue = rows;
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGSuggestedActionsChangedNotification object:nil];
}

@end
