//
// TGClient+Notifications.h - saved notification sounds and the notifications
// TDLib keeps locally while the app is running.
//
#import "TGClient+Base.h"

@interface TGClient (Notifications)

#pragma mark - saved sounds

/// Telegram's saved notification sounds, newest first as the server sends
/// them. Each row is "id", "duration" (seconds), "date", "title", "data",
/// "fileId" and "size".
- (void)savedNotificationSoundsWithCompletion:
		(void (^)(NSArray *sounds))completion;

/// One sound read fresh by its id. nil when Telegram answers 404, which is
/// what a sound removed on another client looks like here.
- (void)savedNotificationSound:(int64_t)soundId
					completion:(void (^)(NSDictionary *sound))completion;

/// Uploads a local file as a notification sound. TDLib accepts MP3; the
/// screen only offers MP3s so a refusal is the server's, not a guess.
/// `error` is Telegram's own sentence when the answer is not a sound.
- (void)addSavedNotificationSoundAtPath:(NSString *)path
							 completion:(void (^)(NSDictionary *sound,
												  NSString *error))completion;

/// Drops a saved sound. Telegram will refuse while its id is still the sound
/// of a scope or a chat, and that refusal is handed back word for word.
- (void)removeSavedNotificationSound:(int64_t)soundId
						  completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - active notifications

/// The groups updateActiveNotifications last named, newest group first as
/// TDLib sent them. Each group is "id", "type", "chatId", "chatTitle",
/// "totalCount" and "notifications"; each notification is "id", "date",
/// "isSilent", "kind" and "text". Empty while Telegram has none, which is
/// the normal state when APNs is drawing them.
@property (nonatomic, readonly) NSArray *activeNotificationGroups;

/// Removes one notification from TDLib's local list. The group id and the
/// notification id are the pair removeNotification requires; the screen
/// takes both from the row it draws.
- (void)removeNotification:(int32_t)notificationId
				   inGroup:(int32_t)groupId
				completion:(void (^)(BOOL ok, NSString *error))completion;

/// Removes every notification in a group up to and including `maxNotificationId` -
/// TDLib's whole-group removal, rather than one request per notification.
- (void)removeNotificationGroup:(int32_t)groupId
			  maxNotificationId:(int32_t)maxNotificationId
					 completion:(void (^)(BOOL ok, NSString *error))completion;

@end

// vim:ft=objc
