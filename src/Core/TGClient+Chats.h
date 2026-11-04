//
// TGClient+Chats.h - the client surface for the chat list and its folders, members, shared media, topics.
//
#import "TGClient+Base.h"

@interface TGClient (Chats)

/// The newest of your own messages in a chat the other side has read; 0 when
/// nothing is known. Anything at or below it carries two ticks.
- (int64_t)lastReadOutboxForChat:(int64_t)chatId;

/// The newest incoming message you have read in a chat; 0 when unknown.
- (int64_t)lastReadInboxForChat:(int64_t)chatId;

/// Profile photo file id of a chat we already know about, or nil. Groups and
/// channels have no user record, so this is where their picture comes from.
- (NSNumber *)photoFileIdForChat:(int64_t)chatId;

/// Chats of one folder.
- (void)chatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *chats))completion;

/// Topics of a forum supergroup - a forum holds several independent threads
/// in one chat. Each entry: "threadId", "name", "text", "unread", "date",
/// "unreadMentions", "unreadReactions", "unreadPollVotes", "pinned",
/// "general", "closed", "hidden", "created", "colour", "iconEmojiId" and the
/// raw "notificationSettings" record. Empty for a chat that is not a forum.
- (void)forumTopicsForChat:(int64_t)chatId completion:(void (^)(NSArray *topics))completion;

/// Clear the reaction marks on a topic. Called when the topic is opened:
/// reading the messages is what "read" means, and the row's badge has to go
/// with it rather than waiting for the next history read.
- (void)readAllForumTopicReactionsInChat:(int64_t)chatId
                                  topic:(int64_t)threadId
                             completion:(void (^)(BOOL ok))completion;

/// One topic read fresh: getForumTopic, the same fields the list row carries
/// plus the notification record. nil when Telegram refuses the id.
- (void)forumTopic:(int64_t)threadId
            inChat:(int64_t)chatId
        completion:(void (^)(NSDictionary *topic))completion;

/// The t.me link to one topic, which is what Copy Link puts on the clipboard.
- (void)forumTopicLinkForTopic:(int64_t)threadId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSString *link))completion;

/// The two badges that are not reactions. readAllForumTopicReactions already
/// exists; these clear mentions and poll votes when their topic is opened.
- (void)readAllForumTopicMentionsInChat:(int64_t)chatId
                                  topic:(int64_t)threadId
                             completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)readAllForumTopicPollVotesInChat:(int64_t)chatId
                                   topic:(int64_t)threadId
                              completion:(void (^)(BOOL ok, NSString *error))completion;

/// setForumTopicNotificationSettings replaces the whole chatNotificationSettings
/// object, so `settings` is the complete record the screen built from the one
/// getForumTopic returned. The answer keeps Telegram's refusal text.
- (void)setForumTopicNotificationSettings:(NSDictionary *)settings
                                    topic:(int64_t)threadId
                                   inChat:(int64_t)chatId
                               completion:(void (^)(BOOL ok, NSString *error))completion;

/// Writes the pinned order whole: the ids in `topicIds`, top first. A topic
/// left out is unpinned. Requires can_manage_topics.
- (void)setPinnedForumTopics:(NSArray *)topicIds
                      inChat:(int64_t)chatId
                  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Hides the General topic (and closes it) or brings it back. `isHidden` tells
/// the api which direction to go.
- (void)toggleGeneralForumTopicHidden:(BOOL)hidden
                               inChat:(int64_t)chatId
                           completion:(void (^)(BOOL ok, NSString *error))completion;

/// Making and minding a forum's topics. `colour` indexes the six hues TDLib
/// accepts, 0-5. `iconEmojiId` is one of the ids `forumTopicDefaultIcons`
/// answers, or 0 for a colour-only icon.
- (void)createForumTopicInChat:(int64_t)chatId
						  name:(NSString *)name
				   iconColour:(NSInteger)colour
				  iconEmojiId:(int64_t)iconEmojiId
				   completion:(void (^)(int64_t threadId, NSString *name))completion;

/// The custom emoji any account may use as a topic icon. Each entry:
/// "id" (the icon_custom_emoji_id) and "emoji" (its character).
- (void)forumTopicDefaultIconsWithCompletion:(void (^)(NSArray *icons))completion;

/// Changes only the icon; the name stays. An emoji id of 0 removes it.
/// TDLib will not edit the General topic's icon, so a failure is normal there.
- (void)setForumTopicIcon:(int64_t)iconEmojiId
				 threadId:(int64_t)threadId
				   inChat:(int64_t)chatId
			   completion:(void (^)(BOOL ok))completion;

/// Renaming only, unless `iconEmojiId` says the icon changes with it.
- (void)renameForumTopic:(int64_t)threadId
				  inChat:(int64_t)chatId
					name:(NSString *)name
			iconEmojiId:(int64_t)iconEmojiId
			 completion:(void (^)(BOOL ok))completion;

- (void)toggleForumTopic:(int64_t)threadId inChat:(int64_t)chatId closed:(BOOL)closed;

- (void)toggleForumTopic:(int64_t)threadId inChat:(int64_t)chatId pinned:(BOOL)pinned;

- (void)deleteForumTopic:(int64_t)threadId inChat:(int64_t)chatId;

/// A forum shown as one flow of messages instead of a list of topics.
- (void)chatWithViewAsTopics:(int64_t)chatId
				  completion:(void (^)(BOOL viewAsTopics))completion;

- (void)setChatViewAsTopics:(int64_t)chatId
			   viewAsTopics:(BOOL)viewAsTopics
				 completion:(void (^)(BOOL ok))completion;

/// Turns a channel's direct-messages group on or off; the group is where
/// readers' replies collect. `paidStars` is what a non-admin pays per
/// message, 0 for free. Owner only.
- (void)setDirectMessagesEnabled:(BOOL)enabled
					   paidStars:(NSInteger)paidStars
						  inChat:(int64_t)chatId
					  completion:(void (^)(BOOL ok))completion;

/// Whether the signed-in user may post in a chat. A channel you only follow
/// says NO, and the composer has to go away rather than fail on send.
- (void)canSendInChat:(int64_t)chatId completion:(void (^)(BOOL canSend, BOOL isChannel))completion;

/// Whether this chat is the Saved Messages chat, read off the row the list
/// keeps. NO when the chat is anything else or not loaded.
- (BOOL)chatIsSavedMessages:(int64_t)chatId;

/// Delete a chat's history for the current user, and leave it if it is a group.
- (void)deleteChat:(int64_t)chatId;

/// Writes the action bar over an unknown chat - its kind, a join request's
/// words, the account details to add a contact by - into a chat dict.
- (void)mergeActionBar:(NSDictionary *)bar intoChatRow:(NSMutableDictionary *)row;

/// One TDLib member record as the row a member list draws: "id", "name",
/// "status" (owner/admin/restricted/banned/left/member) and "owner"
/// (NSNumber). nil when the record names no user.
FOUNDATION_EXPORT NSDictionary *TGMemberRowForMember(NSDictionary *member,
													  NSString *name);

/// Members of a group or supergroup: "id", "name", "status" and "owner".
/// Empty for anything else. The role travels with the row so a list can draw
/// an owner or administrator badge beside the name without a second request.
- (void)membersOfChat:(int64_t)chatId completion:(void (^)(NSArray *members))completion;

/// Members in a group or supergroup; 0 for anything else.
- (void)memberCountForChat:(int64_t)chatId completion:(void (^)(NSInteger count))completion;

/// The chat's real kind, even when the chat is not in chatsById: a chat opened
/// from a profile or a link has no cached row, and guessing private put
/// presence under a channel's name. The answer carries "isGroup", "isChannel",
/// "isMember", "memberCount" and the raw "status". For a group the membership
/// comes from the supergroup or basic group record, not from the chat.
- (void)chatKindForChat:(int64_t)chatId
             completion:(void (^)(NSDictionary *kind))completion;

/// Joins a public group or channel. `ok` only when TDLib says the account is now a
/// member; `requestSent` when an admin has to approve it first.
- (void)joinChat:(int64_t)chatId completion:(void (^)(BOOL ok, BOOL requestSent))completion;

/// Ask TDLib to populate the main chat list. Only meaningful once authorized.
- (void)loadChats;

/// The pinned message of a chat, flattened, or nil if there is none.
- (void)pinnedMessageForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *message))completion;

/// Deletes a group or channel for every member. Owner only; `error` says
/// why not otherwise.
- (void)deleteChatForEveryone:(int64_t)chatId completion:(void (^)(NSString *error))completion;

/// The pinned chats in this order, top first; one left out is unpinned.
- (void)setPinnedChatIds:(NSArray *)chatIds;

/// The same for a group or channel: "description", "members" (NSNumber) and
/// "inviteLink". There is deliberately no administrator count: the member
/// list carries each person's role instead.
- (void)chatProfile:(int64_t)chatId completion:(void (^)(NSDictionary *info))completion;

/// Muted state of one chat, as the list already knows it.
- (BOOL)isChatMuted:(int64_t)chatId;

/// Erase the messages of a chat without leaving it.
- (void)clearHistoryInChat:(int64_t)chatId;

/// Reporting is a conversation: the first call answers with the reasons to
/// choose from, and the chosen option id goes in the second. The completion
/// gets either a title and a list of options - each with "id" and "text" -
/// to put to the user, or an empty list and `done` once it is accepted.
- (void)reportChat:(int64_t)chatId
		  optionId:(NSString *)optionId
			  text:(NSString *)text
		completion:(void (^)(NSString *title, NSArray *options, BOOL done))completion;

/// Dismisses the "Report spam / Add to contacts" bar above a chat from
/// someone this account does not know.
- (void)removeActionBarInChat:(int64_t)chatId;

/// Who this account talks to most, as Telegram ranks it - the people row in
/// search. Entries are the same chat dictionaries the chat list holds.
- (void)topChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// Everything the search field can find by name, from the three places a
/// chat can be: loaded here, on the server but not loaded, and public and
/// belonging to nobody yet. Deduplicated in that order, so a chat you are in
/// never ranks below a stranger with a similar name. A public chat the list
/// has never seen arrives as an "id"/"title" pair, which is enough to open.
- (void)searchChatsForQuery:(NSString *)query
				 completion:(void (^)(NSArray *chats))completion;

/// Contacts matched by Telegram - on the username and the phone number as
/// well as the name, which comparing strings here does not do. Entries carry
/// "id" and "name".
- (void)searchContactsForQuery:(NSString *)query
					completion:(void (^)(NSArray *users))completion;

/// The chats opened most recently - the other half of an empty search.
- (void)recentlyOpenedChatsWithCompletion:(void (^)(NSArray *chats))completion;

/// Opening a chat from search puts it in the recently-found list.
- (void)rememberFoundChat:(int64_t)chatId;

/// Takes someone out of the frequent-contacts ranking.
- (void)forgetTopChat:(int64_t)chatId;

/// Look up a public chat by its @username, creating it locally if needed.
/// Answers 0 when there is no such account.
- (void)chatWithUsername:(NSString *)username
              completion:(void (^)(int64_t chatId, NSString *title))completion;

- (void)joinChatByInviteLink:(NSString *)inviteLink
                  completion:(void (^)(int64_t chatId, NSString *title))completion;

/// The unsent message in the composer, kept on Telegram's side so it is
/// there on the next launch and on every other device. Empty text clears it.
- (void)setDraft:(NSString *)text
		  inChat:(int64_t)chatId
		  thread:(int64_t)threadId
		 replyTo:(int64_t)replyToId;

/// What was last typed into this chat and not sent, by any client of this
/// account. Empty when there is none.
- (NSString *)draftForChat:(int64_t)chatId;

/// Clears the @ and the reaction badge. Reading the messages does not: those
/// two counts are kept apart from unread.
- (void)readAllMentionsAndReactionsInChat:(int64_t)chatId;

/// Informs TDLib that chat is opened or closed, freeing background resources.
- (void)openChat:(int64_t)chatId;

- (void)closeChat:(int64_t)chatId;

/// A contact nobody here has met: the import makes the user, and the id it
/// hands back is what `addContactWithUserId:` is finished with.
- (void)importContactNamed:(NSString *)firstName
				  lastName:(NSString *)lastName
					 phone:(NSString *)phone
				completion:(void (^)(int64_t userId))completion;

/// A number back in the block list, spelled as a message sender.
- (void)blockUserWithUserId:(int64_t)userId;

/// Your phone number to a mutual contact, on their offer to share it.
- (void)sharePhoneNumberWithUser:(int64_t)userId;

/// Adds someone to your Telegram contacts. The phone number is what the
/// server matches on.
- (void)addContactWithUserId:(int64_t)userId
				   firstName:(NSString *)firstName
					lastName:(NSString *)lastName
					   phone:(NSString *)phone
				  completion:(void (^)(BOOL ok))completion;

/// Takes someone out of your contacts; the chat with them stays.
- (void)removeContactWithUserId:(int64_t)userId completion:(void (^)(BOOL ok))completion;

/// Makes a folder holding `chatIds`. `icon` is one of Telegram's own icon
/// names and may be nil. The completion gets the new folder's id, or 0.
- (void)createFolderNamed:(NSString *)name
					 icon:(NSString *)icon
				withChats:(NSArray *)chatIds
			   completion:(void (^)(NSInteger folderId))completion;

/// The folder as it stands - its chats, its flags - or nil if it is gone.
- (void)folderDetails:(NSInteger)folderId
		   completion:(void (^)(NSDictionary *folder))completion;

/// Renames a folder, or changes which chats it holds, or both: a nil leaves
/// that part as it was. An edit replaces the whole folder on Telegram's side,
/// so this reads it first.
- (void)editFolder:(NSInteger)folderId
			  name:(NSString *)name
			 chats:(NSArray *)chatIds
		completion:(void (^)(BOOL ok))completion;

/// Drops the folder. The chats in it stay; `leaveChatIds` is for the ones
/// you also want out of, and is usually empty.
- (void)deleteFolder:(NSInteger)folderId leavingChats:(NSArray *)leaveChatIds;

/// The order of the pill strip. "All chats" is a position in that order
/// rather than a folder of its own.
- (void)reorderFolderIds:(NSArray *)folderIds mainListAt:(NSInteger)position;

/// The pill strip's drag result: the local order is written first so the
/// strip holds it while the wire request is still in flight, then the same
/// order is sent.
- (void)reorderFoldersToLocalIds:(NSArray *)folderIds
					 mainListAt:(NSInteger)position;

/// Telegram's own suggestions, each with the sentence their client shows
/// under it: "title", "description", and "folder" ready to be created.
- (void)recommendedFoldersWithCompletion:(void (^)(NSArray *folders))completion;

- (void)createRecommendedFolder:(NSDictionary *)folder
					 completion:(void (^)(NSInteger folderId))completion;

/// Marks every chat of one chat list read: the folder's badge clears because
/// the list was read as a whole, not chat by chat. folderId 0 = "All chats".
- (void)readChatListOfFolder:(NSInteger)folderId archived:(BOOL)archived;

/// Asks TDLib for the archive settings again and swaps the local copy under
/// the completion; the block runs whether the answer is good or bad, because
/// a page built on the old copy must not wait for one.
- (void)refreshArchiveChatListSettings:(void (^)(void))completion;

/// Sets all three at once - the archive settings are one object in TDLib,
/// not three unrelated switches.
- (void)setArchiveSettingsArchiveAndMute:(BOOL)archiveAndMute
					 keepUnmutedArchived:(BOOL)keepUnmuted
				   keepFolderChatsArchived:(BOOL)keepFolders;

@end
