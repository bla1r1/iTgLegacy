//
// TGClient+Notifications.m - saved sounds and TDLib's local notification list.
//
// APNs is still the delivery path, but TDLib also keeps the groups it would
// draw. updateActiveNotifications is the only request-free way to see them,
// so the client holds that answer and lets the screen remove entries with
// removeNotification / removeNotificationGroup - the two calls that keep the
// list honest after the screen says "remove".
//
#import "TGClientInternal.h"

static NSString *TGAnswerError(NSDictionary *result) {
	if (![result[@"@type"] isEqualToString:@"error"])
		return nil;
	NSString *message = result[@"message"];
	return message.length ? message : @"Telegram refused that.";
}

/// One notificationSound without the file tree. The screen needs the id to
/// remove or select it, the title to name it, and the duration and date to
/// tell two recordings apart.
static NSDictionary *TGSoundRow(NSDictionary *sound) {
	if (![sound isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *file = [sound[@"sound"] isKindOfClass:NSDictionary.class]
			? sound[@"sound"] : nil;
	return @{
		@"id"       : sound[@"id"] ?: @(0),
		@"duration" : sound[@"duration"] ?: @(0),
		@"date"     : sound[@"date"] ?: @(0),
		@"title"    : sound[@"title"] ?: @"",
		@"data"     : sound[@"data"] ?: @"",
		@"fileId"   : file[@"id"] ?: @(0),
		@"size"     : file[@"size"] ?: file[@"expected_size"] ?: @(0),
	};
}

/// A notification is a type object; a row only needs a sentence. New messages
/// arrive whole, push messages arrive flattened by the server, and calls and
/// secret chats carry no text at all.
static NSDictionary *TGNotificationRow(NSDictionary *notification) {
	if (![notification isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *type = [notification[@"type"] isKindOfClass:NSDictionary.class]
			? notification[@"type"] : nil;
	NSString *kind = type[@"@type"] ?: @"";
	NSString *text = @"";
	if ([kind isEqualToString:@"notificationTypeNewMessage"]){
		NSDictionary *message = type[@"message"];
		text = TGMessagePreview(message) ?: @"Message";
	} else if ([kind isEqualToString:@"notificationTypeNewPushMessage"]){
		NSString *sender = type[@"sender_name"] ?: @"";
		NSString *content = type[@"content"][@"@type"] ?: @"";
		NSString *phrase = content.length ? TGPhraseFromTypeName(content) : @"Message";
		text = sender.length ? [NSString stringWithFormat:@"%@: %@", sender, phrase]
							 : phrase;
	} else if ([kind isEqualToString:@"notificationTypeNewCall"]){
		text = @"Incoming call";
	} else if ([kind isEqualToString:@"notificationTypeNewSecretChat"]){
		text = @"New secret chat";
	}
	return @{
		@"id"       : notification[@"id"] ?: @(0),
		@"date"     : notification[@"date"] ?: @(0),
		@"isSilent" : notification[@"is_silent"] ?: @NO,
		@"kind"     : kind,
		@"text"     : text,
	};
}

static NSDictionary *TGNotificationGroupRow(TGClient *client,
											NSDictionary *group) {
	if (![group isKindOfClass:NSDictionary.class])
		return nil;
	int64_t chatId = [group[@"chat_id"] longLongValue];
	NSString *title = client.chatsById[@(chatId)][@"title"] ?: @"";
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *notification in group[@"notifications"]){
		NSDictionary *row = TGNotificationRow(notification);
		if (row)
			[rows addObject:row];
	}
	NSDictionary *groupType = [group[@"type"] isKindOfClass:NSDictionary.class]
			? group[@"type"] : nil;
	return @{
		@"id"         : group[@"id"] ?: @(0),
		@"type"       : groupType[@"@type"] ?: @"",
		@"chatId"     : @(chatId),
		@"chatTitle"  : title,
		@"totalCount" : group[@"total_count"] ?: @(rows.count),
		@"notifications" : rows,
	};
}

static NSMutableArray *TGNotificationGroupsFromAnswer(TGClient *client,
													   NSArray *groups) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *group in groups){
		NSDictionary *row = TGNotificationGroupRow(client, group);
		if (row)
			[out addObject:row];
	}
	return out;
}

/// The same notification list in one group, with `notification` replacing the
/// row of the same id or joining at the end.
static NSMutableArray *TGNotificationsReplacing(NSArray *current,
												NSDictionary *notification) {
	NSDictionary *row = TGNotificationRow(notification);
	if (!row)
		return [current mutableCopy];
	NSMutableArray *next = [NSMutableArray array];
	BOOL replaced = NO;
	for (NSDictionary *existing in current){
		if ([existing[@"id"] isEqual:row[@"id"]]){
			[next addObject:row];
			replaced = YES;
		} else {
			[next addObject:existing];
		}
	}
	if (!replaced)
		[next addObject:row];
	return next;
}

@implementation TGClient (Notifications)

#pragma mark - saved sounds

- (void)savedNotificationSoundsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getSavedNotificationSounds"}
	   completion:^(NSDictionary *result){
		NSString *error = TGAnswerError(result);
		if (error){
			NSLog(@"getSavedNotificationSounds: %@", error);
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *sounds = [NSMutableArray array];
		for (NSDictionary *sound in result[@"notification_sounds"]){
			NSDictionary *row = TGSoundRow(sound);
			if (row)
				[sounds addObject:row];
		}
		NSLog(@"TGClient: %lu saved notification sounds",
			  (unsigned long)sounds.count);
		if (completion) completion(sounds);
	}];
}

- (void)savedNotificationSound:(int64_t)soundId
					completion:(void (^)(NSDictionary *))completion {
	if (!soundId){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getSavedNotificationSound",
					@"notification_sound_id" : @(soundId)}
	   completion:^(NSDictionary *result){
		NSString *error = TGAnswerError(result);
		if (error){
			NSLog(@"getSavedNotificationSound %lld: %@",
				  (long long)soundId, error);
			if (completion) completion(nil);
			return;
		}
		if (completion) completion(TGSoundRow(result));
	}];
}

- (void)addSavedNotificationSoundAtPath:(NSString *)path
							 completion:(void (^)(NSDictionary *, NSString *))completion {
	if (!path.length ||
		![[NSFileManager defaultManager] fileExistsAtPath:path]){
		if (completion)
			completion(nil, @"The sound file is not there any more.");
		return;
	}
	[self request:@{
		@"@type" : @"addSavedNotificationSound",
		@"sound" : @{@"@type" : @"inputFileLocal", @"path" : path},
	} completion:^(NSDictionary *result){
		NSString *error = TGAnswerError(result);
		if (error){
			NSLog(@"addSavedNotificationSound: %@", error);
			if (completion) completion(nil, error);
			return;
		}
		NSDictionary *row = TGSoundRow(result);
		if (!row){
			if (completion)
				completion(nil, @"Telegram did not return the saved sound.");
			return;
		}
		if (completion) completion(row, nil);
	}];
}

- (void)removeSavedNotificationSound:(int64_t)soundId
						  completion:(void (^)(BOOL, NSString *))completion {
	if (!soundId){
		if (completion) completion(NO, @"That sound has no id.");
		return;
	}
	[self request:@{@"@type" : @"removeSavedNotificationSound",
					@"notification_sound_id" : @(soundId)}
	   completion:^(NSDictionary *result){
		NSString *error = TGAnswerError(result);
		if (error)
			NSLog(@"removeSavedNotificationSound %lld: %@",
				  (long long)soundId, error);
		if (completion) completion(error == nil, error);
	}];
}

#pragma mark - active notifications

- (NSArray *)activeNotificationGroups {
	return self.activeNotificationGroupsValue ?: @[];
}

/// TDLib is still fetching or delaying notifications; the screen keeps its
/// spinner up until both flags are off.
- (BOOL)havePendingNotifications {
	return self.haveDelayedNotifications || self.haveUnreceivedNotifications;
}

- (void)removeNotification:(int32_t)notificationId
				   inGroup:(int32_t)groupId
				completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"removeNotification",
					@"notification_group_id" : @(groupId),
					@"notification_id" : @(notificationId)}
	   completion:^(NSDictionary *result){
		NSString *error = TGAnswerError(result);
		if (error){
			NSLog(@"removeNotification %d/%d: %@", groupId, notificationId, error);
			if (completion) completion(NO, error);
			return;
		}
		NSMutableArray *groups = [NSMutableArray array];
		for (NSDictionary *group in self.activeNotificationGroupsValue ?: @[]){
			if ([group[@"id"] intValue] != groupId){
				[groups addObject:group];
				continue;
			}
			NSMutableArray *left = [NSMutableArray array];
			for (NSDictionary *row in group[@"notifications"])
				if ([row[@"id"] intValue] != notificationId)
					[left addObject:row];
			NSMutableDictionary *next = [group mutableCopy];
			next[@"notifications"] = left;
			NSInteger total = MAX((NSInteger)0,
					[group[@"totalCount"] integerValue] - 1);
			next[@"totalCount"] = @(total);
			[groups addObject:next];
		}
		self.activeNotificationGroupsValue = groups;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGActiveNotificationsChangedNotification
							  object:self];
		if (completion) completion(YES, nil);
	}];
}

- (void)removeNotificationGroup:(int32_t)groupId
			  maxNotificationId:(int32_t)maxNotificationId
					 completion:(void (^)(BOOL, NSString *))completion {
	[self request:@{@"@type" : @"removeNotificationGroup",
					@"notification_group_id" : @(groupId),
					@"max_notification_id" : @(maxNotificationId)}
	   completion:^(NSDictionary *result){
		NSString *error = TGAnswerError(result);
		if (error){
			NSLog(@"removeNotificationGroup %d up to %d: %@",
				  groupId, maxNotificationId, error);
			if (completion) completion(NO, error);
			return;
		}
		NSMutableArray *groups = [NSMutableArray array];
		for (NSDictionary *group in self.activeNotificationGroupsValue ?: @[]){
			if ([group[@"id"] intValue] != groupId)
				[groups addObject:group];
		}
		self.activeNotificationGroupsValue = groups;
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGActiveNotificationsChangedNotification
							  object:self];
		if (completion) completion(YES, nil);
	}];
}

#pragma mark - update handling, called from TGClient.m

/// An update the receive loop used to mark ignored. Kept in one method so
/// the three shapes share the same list instead of three copies of it.
- (void)applyActiveNotificationUpdate:(NSDictionary *)update {
	NSString *type = update[@"@type"];
	if ([type isEqualToString:@"updateActiveNotifications"]){
		self.activeNotificationGroupsValue =
				TGNotificationGroupsFromAnswer(self, update[@"groups"]);
	} else if ([type isEqualToString:@"updateNotificationGroup"]){
		int32_t groupId = [update[@"id"] intValue];
		NSString *groupType = [update[@"type"] isKindOfClass:NSDictionary.class]
				? update[@"type"][@"@type"] : nil;
		NSMutableArray *groups = [NSMutableArray array];
		BOOL found = NO;
		for (NSDictionary *group in self.activeNotificationGroupsValue ?: @[]){
			if ([group[@"id"] intValue] != groupId){
				[groups addObject:group];
				continue;
			}
			found = YES;
			NSMutableArray *rows = [group[@"notifications"] mutableCopy];
			NSSet *removed = [NSSet setWithArray:update[@"removed_notification_ids"] ?: @[]];
			if (removed.count){
				NSMutableArray *left = [NSMutableArray array];
				for (NSDictionary *row in rows)
					if (![removed containsObject:row[@"id"]])
						[left addObject:row];
				rows = left;
			}
			for (NSDictionary *added in update[@"added_notifications"] ?: @[])
				rows = TGNotificationsReplacing(rows, added);
			NSMutableDictionary *next = [group mutableCopy];
			next[@"type"] = groupType ?: group[@"type"];
			next[@"chatId"] = update[@"chat_id"] ?: group[@"chatId"];
			next[@"totalCount"] = update[@"total_count"] ?: @(rows.count);
			next[@"notifications"] = rows;
			int64_t chatId = [next[@"chatId"] longLongValue];
			NSString *title = self.chatsById[@(chatId)][@"title"];
			if (title.length)
				next[@"chatTitle"] = title;
			[groups addObject:next];
		}
		if (!found){
			NSMutableDictionary *next = [@{
				@"id"         : @(groupId),
				@"type"       : groupType ?: @"",
				@"chatId"     : update[@"chat_id"] ?: @(0),
				@"totalCount" : update[@"total_count"] ?: @(0),
			} mutableCopy];
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *added in update[@"added_notifications"] ?: @[]){
				NSDictionary *row = TGNotificationRow(added);
				if (row)
					[rows addObject:row];
			}
			next[@"notifications"] = rows;
			int64_t chatId = [next[@"chatId"] longLongValue];
			next[@"chatTitle"] = self.chatsById[@(chatId)][@"title"] ?: @"";
			[groups addObject:next];
		}
		self.activeNotificationGroupsValue = groups;
	} else if ([type isEqualToString:@"updateNotification"]){
		int32_t groupId = [update[@"notification_group_id"] intValue];
		NSMutableArray *groups = [NSMutableArray array];
		BOOL found = NO;
		for (NSDictionary *group in self.activeNotificationGroupsValue ?: @[]){
			if ([group[@"id"] intValue] != groupId){
				[groups addObject:group];
				continue;
			}
			found = YES;
			NSMutableDictionary *next = [group mutableCopy];
			next[@"notifications"] =
					TGNotificationsReplacing(group[@"notifications"],
											 update[@"notification"]);
			NSInteger total = MAX([next[@"totalCount"] integerValue],
								  (NSInteger)[next[@"notifications"] count]);
			next[@"totalCount"] = @(total);
			[groups addObject:next];
		}
		if (!found){
			NSMutableDictionary *next = [@{
				@"id"         : @(groupId),
				@"type"       : @"",
				@"chatId"     : @(0),
				@"chatTitle"  : @"",
				@"totalCount" : @(1),
			} mutableCopy];
			next[@"notifications"] =
					TGNotificationsReplacing(@[], update[@"notification"]);
			[groups addObject:next];
		}
		self.activeNotificationGroupsValue = groups;
	} else {
		return;
	}
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGActiveNotificationsChangedNotification
						  object:self];
}

@end

// vim:ft=objc
