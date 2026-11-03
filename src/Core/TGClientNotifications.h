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

/// Telegram sent a service notification, which the protocol says to show as
/// a popup: it belongs to no chat. userInfo carries "text".
extern NSString *const TGServiceNotificationReceivedNotification;

/// Telegram sent terms of service that have to be accepted before the
/// account can go on. userInfo carries "id" and "text"; the screen accepting
/// them calls -acceptTermsOfService:completion:.
extern NSString *const TGTermsOfServiceReceivedNotification;

/// The account's own privacy rules changed, here or on another client. The
/// privacy page re-reads its switches while it is open.
extern NSString *const TGPrivacyRulesChangedNotification;

/// A session was added, confirmed or removed. The devices list re-reads;
/// updateUnconfirmedSession is what brings a new login to its attention.
extern NSString *const TGSessionsChangedNotification;

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

/// The local notification list changed: a group arrived, went away, or a row
/// inside it changed. TDLib sends this while the app is running; the Active
/// Notifications screen re-reads the groups it draws. userInfo carries
/// "pending" - YES while TDLib still has delayed or unreceived notifications.
extern NSString *const TGActiveNotificationsChangedNotification;

/// Telegram changed the account's autosave settings, here or on another
/// client. No payload: the Autosave page and the Data row re-read the three
/// scopes and the per-chat exceptions in one request.
extern NSString *const TGAutosaveSettingsChangedNotification;

/// A language pack's strings changed. userInfo carries "packId"; an open
/// Language page re-reads the pack record and, if it was showing a string
/// list, that list too.
extern NSString *const TGLanguagePackStringsChangedNotification;

/// Notification settings changed for a scope, or a chat's default was
/// flipped. No payload: the settings screen reads all three scopes at once.
extern NSString *const TGNotificationSettingsChangedNotification;

/// TDLib's local notification list moved - a group arrived, a notification
/// was added or one was removed here. No payload: the Active Notifications
/// page reads the client's whole list, which is short.
extern NSString *const TGActiveNotificationsChangedNotification;

/// A forum topic was created, renamed, pinned, closed or read. userInfo
/// carries "chatId" when the update names one.
extern NSString *const TGForumTopicsChangedNotification;

/// The used text composition styles changed. No payload: the manager reads
/// -textCompositionStyles, which the update replaced whole.
extern NSString *const TGTextCompositionStylesChangedNotification;

/// A channel direct messages topic arrived or moved. userInfo carries
/// "chatId"; the topic list re-reads the cache for that chat.
extern NSString *const TGDirectMessagesTopicsChangedNotification;

/// The stake dice state moved. No payload: the panel reads the cached state,
/// which is also the hash the next roll has to quote.
extern NSString *const TGStakeDiceStateChangedNotification;

/// Telegram asked this app to prove it is genuine before a request can go
/// through. userInfo carries "verificationId" and "nonce"; the settings
/// sheet hands the verification service's token back through
/// -setApplicationVerificationToken:verificationId:completion:.
extern NSString *const TGApplicationVerificationRequiredNotification;
// Fired when updateChatActionBar arrives: the bar over a chat nobody knows
// - report spam, add to contacts - follows the update, not only the fetch.
extern NSString *const TGChatActionBarChangedNotification;
/// A bot's keyboard on a chat changed; userInfo carries "chatId".
extern NSString *const TGChatReplyMarkupChangedNotification;

/// The accent colours Telegram offers changed, or the list arrived for the
/// first time. No payload: Appearance re-reads both lists and the selection.
extern NSString *const TGAccentColorsChangedNotification;

/// The contacts with a birthday nearby changed. No payload; the privacy page
/// re-reads the count and the list is on the client.
extern NSString *const TGContactCloseBirthdaysChangedNotification;

/// An account-status fact changed: a freeze started or ended, a subscription
/// moved, age verification parameters arrived, or Telegram asked for a
/// reCAPTCHA. The privacy page re-reads the rows from the client.
extern NSString *const TGAccountStatusChangedNotification;

/// Telegram's default chat background or its emoji chat themes moved. The
/// Appearance page re-reads both; there is no per-row payload.
extern NSString *const TGAppearanceDefaultsChangedNotification;

/// Telegram's list of message effects changed. The held-message effect sheet
/// reads the ids live instead of keeping the list it opened with.
extern NSString *const TGMessageEffectsChangedNotification;

/// A bot's streaming draft was stopped server-side. userInfo carries "chatId",
/// "forumTopicId", "draftId" and "draftText" (what was cached before the stop).
extern NSString *const TGChatDraftStoppedNotification;

/// A scheduled video was published and the message now carries it. userInfo
/// carries "chatId" and "messageId"; the open chat re-reads that message.
extern NSString *const TGChatVideoPublishedNotification;

/// updateCommunity or updateCommunityFullInfo arrived. No payload: the
/// community list and the open detail screen re-read the client's cache.
extern NSString *const TGCommunitiesChangedNotification;

/// updateChatActiveStories, updateStory or updateStoryDeleted: one chat's
/// strip row changed, or a story in it did. userInfo carries "chatId" and a
/// rebuilt "row", "remove", a flattened "story" or a "deletedStoryId"; the
/// strip reads the row and an open viewer reads the story.
extern NSString *const TGStoriesChangedNotification;

/// A story post finished on the server. userInfo carries "ok", "chatId",
/// "storyId", "story" on success and "error" on failure.
extern NSString *const TGStoryPostFinishedNotification;

/// One chat's revenue amount changed. userInfo carries "chatId"; the Stars
/// screen re-reads getChatRevenueStatistics for that chat.
extern NSString *const TGChatRevenueChangedNotification;

/// An owner's Star revenue status changed. userInfo carries "ownerKind" and
/// "ownerId"; the Stars screen re-reads getStarRevenueStatistics.
extern NSString *const TGStarRevenueChangedNotification;

/// A quick-reply shortcut or one of its messages changed. No payload; the
/// manager and the open shortcut re-read the cache.
extern NSString *const TGQuickRepliesChangedNotification;

/// updateSuggestedActions added or removed rows. No payload; the list that
/// draws them re-reads the client.
extern NSString *const TGSuggestedActionsChangedNotification;

/// Posted on the main queue when the running account changes: after the old
/// account's in-memory state is cleared and before the new client resumes, so
/// the app drops its old screens before the next auth state rebuilds them.
extern NSString *const TGAccountDidSwitchNotification;
