//
// TGUpdateType.h - the td_api update types this client reads, as one list.
//
// Two places need the same list and must not drift apart: the receive loop,
// which throws an update away before a Foundation tree is built for it, and
// handleUpdate's dispatch. A branch there needs a case label, a case label
// needs an enum member, and the enum comes from this list - so an update
// cannot be dispatched without also being let through the filter.
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
	X(TGUpdateUnreadChatCount,        "updateUnreadChatCount")

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
