//
// TGUpdateType.h - the td_api update types this client reads, as one list.
//
// Two places need the same list and must not drift apart: the receive loop,
// which throws an update away before a Foundation tree is built for it, and
// handleUpdate's dispatch. A branch there needs a case label, a case label
// needs an enum member, and the enum comes from this list - so an update
// cannot be dispatched without also being let through the filter.
//
// The list grew a second wave: chat fields kept true in the row,
// message-level nudges, the global unread total, and the no-op markers each
// named in the dispatch below TGClient.m's handleUpdate - every one points
// at a screen the app does not draw yet.
//
#pragma once
#include <stddef.h>

#define TG_HANDLED_UPDATES(X) \
	X(TGUpdateAuthorizationState,     "updateAuthorizationState") \
	X(TGUpdateUser,                   "updateUser") \
	X(TGUpdateNewMessage,             "updateNewMessage") \
	X(TGUpdateMessageContent,         "updateMessageContent") \
	X(TGUpdateMessageSendSucceeded,   "updateMessageSendSucceeded") \
	X(TGUpdateMessageSendFailed,      "updateMessageSendFailed") \
	X(TGUpdateDeleteMessages,         "updateDeleteMessages") \
	X(TGUpdateNewChat,                "updateNewChat") \
	X(TGUpdateChatLastMessage,        "updateChatLastMessage") \
	X(TGUpdateChatPosition,           "updateChatPosition") \
	X(TGUpdateChatTitle,              "updateChatTitle") \
	X(TGUpdateChatPhoto,              "updateChatPhoto") \
	X(TGUpdateChatDraftMessage,       "updateChatDraftMessage") \
	X(TGUpdateChatIsMarkedAsUnread,   "updateChatIsMarkedAsUnread") \
	X(TGUpdateChatUnreadMentionCount, "updateChatUnreadMentionCount") \
	X(TGUpdateChatUnreadReactionCount, "updateChatUnreadReactionCount") \
	X(TGUpdateMessageMentionRead,     "updateMessageMentionRead") \
	X(TGUpdateMessageUnreadReactions, "updateMessageUnreadReactions") \
	X(TGUpdateMessageEdited,          "updateMessageEdited") \
	X(TGUpdateMessageIsPinned,        "updateMessageIsPinned") \
	X(TGUpdateMessageContentOpened,   "updateMessageContentOpened") \
	X(TGUpdateOption,                 "updateOption") \
	X(TGUpdateFileAddedToDownloads,   "updateFileAddedToDownloads") \
	X(TGUpdateFileDownload,           "updateFileDownload") \
	X(TGUpdateFileDownloads,          "updateFileDownloads") \
	X(TGUpdateFileRemovedFromDownloads, "updateFileRemovedFromDownloads") \
	X(TGUpdateUserFullInfo,           "updateUserFullInfo") \
	X(TGUpdateBasicGroup,             "updateBasicGroup") \
	X(TGUpdateBasicGroupFullInfo,     "updateBasicGroupFullInfo") \
	X(TGUpdateSupergroupFullInfo,     "updateSupergroupFullInfo") \
	X(TGUpdateMessageInteractionInfo, "updateMessageInteractionInfo") \
	X(TGUpdateInstalledStickerSets,   "updateInstalledStickerSets") \
	X(TGUpdateTrendingStickerSets,    "updateTrendingStickerSets") \
	X(TGUpdateRecentStickers,         "updateRecentStickers") \
	X(TGUpdateFavoriteStickers,       "updateFavoriteStickers") \
	X(TGUpdateSavedAnimations,        "updateSavedAnimations") \
	X(TGUpdateStickerSet,             "updateStickerSet") \
	X(TGUpdateChatMember,             "updateChatMember") \
	X(TGUpdateChatPendingJoinRequests, "updateChatPendingJoinRequests") \
	X(TGUpdateNewChatJoinRequest,     "updateNewChatJoinRequest") \
	X(TGUpdateChatPermissions,        "updateChatPermissions") \
	X(TGUpdateChatMessageAutoDeleteTime, "updateChatMessageAutoDeleteTime") \
	X(TGUpdateChatOnlineMemberCount,  "updateChatOnlineMemberCount") \
	X(TGUpdateChatUnreadPollVoteCount, "updateChatUnreadPollVoteCount") \
	X(TGUpdateMessageContainsUnreadPollVotes, "updateMessageContainsUnreadPollVotes") \
	X(TGUpdateChatAddedToList,        "updateChatAddedToList") \
	X(TGUpdateChatRemovedFromList,    "updateChatRemovedFromList") \
	X(TGUpdateScopeNotificationSettings, "updateScopeNotificationSettings") \
	X(TGUpdateChatDefaultDisableNotification, "updateChatDefaultDisableNotification") \
	X(TGUpdateForumTopic,             "updateForumTopic") \
	X(TGUpdateForumTopicInfo,         "updateForumTopicInfo") \
	X(TGUpdateTopicMessageCount,      "updateTopicMessageCount") \
	X(TGUpdateChatReadInbox,          "updateChatReadInbox") \
	X(TGUpdateChatReadOutbox,         "updateChatReadOutbox") \
	X(TGUpdateChatNotificationSettings, "updateChatNotificationSettings") \
	X(TGUpdateConnectionState,        "updateConnectionState") \
	X(TGUpdateSecretChat,             "updateSecretChat") \
	X(TGUpdateNewCallSignalingData,   "updateNewCallSignalingData") \
	X(TGUpdateCall,                   "updateCall") \
	X(TGUpdateFile,                   "updateFile") \
	X(TGUpdateChatAction,             "updateChatAction") \
	X(TGUpdateSupergroup,             "updateSupergroup") \
	X(TGUpdateUserStatus,             "updateUserStatus") \
	X(TGUpdateChatActionBar,          "updateChatActionBar") \
	X(TGUpdateChatFolders,            "updateChatFolders") \
	X(TGUpdateUnreadChatCount,        "updateUnreadChatCount") \
	X(TGUpdateChatReplyMarkup,        "updateChatReplyMarkup") \
	X(TGUpdateChatBlockList,          "updateChatBlockList") \
	X(TGUpdateChatHasProtectedContent, "updateChatHasProtectedContent") \
	X(TGUpdateChatHasScheduledMessages, "updateChatHasScheduledMessages") \
	X(TGUpdateChatViewAsTopics,       "updateChatViewAsTopics") \
	X(TGUpdateChatIsTranslatable,     "updateChatIsTranslatable") \
	X(TGUpdateChatHasWelcomeMessages, "updateChatHasWelcomeMessages") \
	X(TGUpdateChatAvailableReactions, "updateChatAvailableReactions") \
	X(TGUpdateChatTheme,              "updateChatTheme") \
	X(TGUpdateChatAccentColors,       "updateChatAccentColors") \
	X(TGUpdateChatMessageSender,      "updateChatMessageSender") \
	X(TGUpdateChatWelcomeMessages,    "updateChatWelcomeMessages") \
	X(TGUpdateChatBackground,         "updateChatBackground") \
	X(TGUpdateMessageReaction,        "updateMessageReaction") \
	X(TGUpdateMessageReactions,       "updateMessageReactions") \
	X(TGUpdateMessageLiveLocationViewed, "updateMessageLiveLocationViewed") \
	X(TGUpdateAnimatedEmojiMessageClicked, "updateAnimatedEmojiMessageClicked") \
	X(TGUpdateActiveLiveLocationMessages, "updateActiveLiveLocationMessages") \
	X(TGUpdateChatJoinResult,         "updateChatJoinResult") \
	X(TGUpdateReactionNotificationSettings, "updateReactionNotificationSettings") \
	X(TGUpdateSavedNotificationSounds, "updateSavedNotificationSounds") \
	X(TGUpdateSpeedLimitNotification, "updateSpeedLimitNotification") \
	X(TGUpdateUnreadMessageCount,     "updateUnreadMessageCount") \
	X(TGUpdateActiveNotifications,    "updateActiveNotifications") \
	X(TGUpdateNotification,           "updateNotification") \
	X(TGUpdateNotificationGroup,      "updateNotificationGroup") \
	X(TGUpdateHavePendingNotifications, "updateHavePendingNotifications") \
	X(TGUpdateServiceNotification,    "updateServiceNotification") \
	X(TGUpdateTermsOfService,         "updateTermsOfService") \
	X(TGUpdateUnconfirmedSession,     "updateUnconfirmedSession") \
	X(TGUpdateFreezeState,            "updateFreezeState") \
	X(TGUpdateUserPrivacySettingRules, "updateUserPrivacySettingRules") \
	X(TGUpdateAgeVerificationParameters, "updateAgeVerificationParameters") \
	X(TGUpdateApplicationVerificationRequired, "updateApplicationVerificationRequired") \
	X(TGUpdateApplicationRecaptchaVerificationRequired, "updateApplicationRecaptchaVerificationRequired") \
	X(TGUpdateUserSubscription,       "updateUserSubscription") \
	X(TGUpdateAutosaveSettings,       "updateAutosaveSettings") \
	X(TGUpdateLanguagePackStrings,    "updateLanguagePackStrings") \
	X(TGUpdateAccentColors,           "updateAccentColors") \
	X(TGUpdateProfileAccentColors,    "updateProfileAccentColors") \
	X(TGUpdateDefaultBackground,      "updateDefaultBackground") \
	X(TGUpdateDefaultReactionType,    "updateDefaultReactionType") \
	X(TGUpdateEmojiChatThemes,        "updateEmojiChatThemes") \
	X(TGUpdateAnimationSearchParameters, "updateAnimationSearchParameters") \
	X(TGUpdateAvailableMessageEffects, "updateAvailableMessageEffects") \
	X(TGUpdateContactCloseBirthdays,  "updateContactCloseBirthdays") \
	X(TGUpdateSavedMessagesTopic,     "updateSavedMessagesTopic") \
	X(TGUpdateSavedMessagesTopicCount, "updateSavedMessagesTopicCount") \
	X(TGUpdateSavedMessagesTags,      "updateSavedMessagesTags") \
	X(TGUpdateStopMessageDraft,       "updateStopMessageDraft") \
	X(TGUpdateVideoPublished,         "updateVideoPublished")

typedef enum {
	TGUpdateUnknown = 0,
#define TG_UPDATE_ENUM_ROW(sym, name) sym,
	TG_HANDLED_UPDATES(TG_UPDATE_ENUM_ROW)
#undef TG_UPDATE_ENUM_ROW
} TGUpdateType;

#ifdef __cplusplus
extern "C" {
#endif

/// TGUpdateUnknown for anything outside the list. `len` is the name's length
/// without the terminator - the parser knows it, so nothing calls strlen.
TGUpdateType TGUpdateTypeFor(const char *name, size_t len);

/// Whether a top-level "@type" names an update at all. Answers to requests
/// are never filtered, however rare their type: there is one per request the
/// app made, while updates are the flood.
int TGUpdateTypeIsUpdateName(const char *name, size_t len);

#ifdef __cplusplus
}
#endif
