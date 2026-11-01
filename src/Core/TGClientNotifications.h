//
// TGClientNotifications - the names the client posts, and what each carries.
// Every one is posted on the main queue.
//
#import <Foundation/Foundation.h>

/// Posted on the main queue when the other side reads your messages in a
/// chat; userInfo carries "chatId".
extern NSString *const TGChatReadOutboxChangedNotification;
// Fired when updateConnectionState arrives, so screens that need not own the
// single onConnectionState slot can still see the network change (B4).
extern NSString *const TGConnectionStateChangedNotification;
// Fired when updateUserStatus arrives: chat headers and profile status
// labels re-render their line instead of freezing at the fetched one.
extern NSString *const TGUserStatusChangedNotification;

/// The main chat list's unread total moved server-side. userInfo carries
/// "count" - the unmuted unread count the app-icon badge shows. A folder's
/// own count is not sent here: shrinking the badge for it would be a lie.
extern NSString *const TGUnreadTotalChangedNotification;

/// A Saved Messages topic arrived, moved or got a label. The topics screen
/// re-reads; loadSavedMessagesTopics starts the stream.
extern NSString *const TGSavedTopicsChangedNotification;

/// The download list changed: a file was added, finished, paused or removed.
/// Carries no payload - the list is short and is re-read whole.
extern NSString *const TGDownloadsChangedNotification;

/// A sender's full record changed (bio, member count, admin rights). userInfo
/// carries "kind" ("user", "basicGroup" or "supergroup") and "id".
extern NSString *const TGFullInfoChangedNotification;

/// An installed set, the recent or favourite stickers or the saved GIFs
/// changed - here or on another client. The panel re-reads what it shows.
extern NSString *const TGStickerListsChangedNotification;

/// A chat's membership changed: a member joined, was promoted or removed, or
/// a join request arrived. userInfo carries "chatId".
extern NSString *const TGChatMembersChangedNotification;

/// Notification settings changed for a scope, or a chat's default was
/// flipped. No payload: the settings screen reads all three scopes at once.
extern NSString *const TGNotificationSettingsChangedNotification;

/// A forum topic was created, renamed, pinned, closed or read. userInfo
/// carries "chatId" when the update names one.
extern NSString *const TGForumTopicsChangedNotification;
// Fired when updateChatActionBar arrives: the bar over a chat nobody knows
// - report spam, add to contacts - follows the update, not only the fetch.
extern NSString *const TGChatActionBarChangedNotification;
/// A bot's keyboard on a chat changed; userInfo carries "chatId".
extern NSString *const TGChatReplyMarkupChangedNotification;
