//
// TGClient+Tier2.h - communities, checklists, quick replies, suggested posts
// and the AI/rich-message tools.
//
// These are the TDLib calls behind three new screens and one message-tools
// sheet. Communities have no list request: updateCommunity is the only place
// the record arrives, so this category caches what it carries. Quick replies
// work the same way - load fills the cache through updates, and every write
// below updates that cache before Telegram's echo lands.
//
#import "TGClient+Base.h"

@interface TGClient (Tier2)

#pragma mark - communities

/// Communities Telegram has told this client about, newest update first.
/// Each row is "id", "name", "haveAccess", "date", "status", "photoFileId"
/// and "canEditChatList".
@property (nonatomic, readonly) NSArray *communities;

/// The full record this account last read: "photoFileId", "chats" (each
/// "chatId", "title", "canViewHistory", "hidden"), "administratorCount",
/// "bannedCount" and "addChatRequestCount". Nil until getCommunityFullInfo
/// answers.
- (NSDictionary *)cachedCommunityFullInfo:(int64_t)communityId;

/// Creates a community around one owned chat. `communityId` is 0 and `error`
/// carries Telegram's sentence when the request is refused.
- (void)createCommunity:(NSString *)name
                 chatId:(int64_t)chatId
                 hidden:(BOOL)hidden
             completion:(void (^)(int64_t communityId, NSString *error))completion;

- (void)communityFullInfo:(int64_t)communityId
               completion:(void (^)(NSDictionary *info, NSString *error))completion;

- (void)setCommunityName:(int64_t)communityId
                    name:(NSString *)name
              completion:(void (^)(BOOL ok, NSString *error))completion;

/// `path` is a local picture, uploaded as a static chat photo. A nil path
/// asks Telegram to remove the photo.
- (void)setCommunityPhoto:(int64_t)communityId
                     path:(NSString *)path
               completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setCommunityPermissions:(int64_t)communityId
                  canEditChatList:(BOOL)canEditChatList
                      completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteCommunity:(int64_t)communityId
             completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - quick replies

/// The shortcuts this client knows, in Telegram's order. Rows carry "id",
/// "name", "messageCount" and "preview".
@property (nonatomic, readonly) NSArray *quickReplyShortcuts;

/// Sends loadQuickReplyShortcuts, then answers the cache as the updates
/// fill it. `completion` gets the same rows as the property.
- (void)loadQuickReplyShortcutsWithCompletion:
        (void (^)(NSArray *shortcuts))completion;

/// One shortcut's messages, flattened: "id", "text", "kind" and "photoId".
/// A load request goes out first; an empty array is a real empty shortcut.
- (void)loadQuickReplyMessagesForShortcut:(NSInteger)shortcutId
                               completion:(void (^)(NSArray *messages))completion;

/// Telegram's name check. `ok` is NO and `error` holds the sentence when the
/// name is taken or malformed.
- (void)checkQuickReplyShortcutName:(NSString *)name
                         completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)setQuickReplyShortcutName:(NSInteger)shortcutId
                             name:(NSString *)name
                       completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteQuickReplyShortcut:(NSInteger)shortcutId
                      completion:(void (^)(BOOL ok, NSString *error))completion;

/// `shortcutIds` is the whole order, first row first.
- (void)reorderQuickReplyShortcuts:(NSArray *)shortcutIds
                        completion:(void (^)(BOOL ok, NSString *error))completion;

/// Adding a message is how a new shortcut is made: there is no empty
/// create request. `shortcutName` names it; Telegram creates it on success.
- (void)addQuickReplyShortcutMessage:(NSString *)shortcutName
                                text:(NSString *)text
                          completion:(void (^)(NSDictionary *message, NSString *error))completion;

/// Adds two or more text messages as one album.
- (void)addQuickReplyShortcutMessageAlbum:(NSString *)shortcutName
                                    texts:(NSArray *)texts
                               completion:(void (^)(NSArray *messages, NSString *error))completion;

- (void)editQuickReplyMessage:(int64_t)messageId
                   shortcutId:(NSInteger)shortcutId
                         text:(NSString *)text
                   completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)deleteQuickReplyShortcutMessages:(NSArray *)messageIds
                              shortcutId:(NSInteger)shortcutId
                              completion:(void (^)(BOOL ok, NSString *error))completion;

/// Puts messages TDLib still remembers back into the shortcut. The ids are
/// the ones deleteQuickReplyShortcutMessages took.
- (void)readdQuickReplyShortcutMessages:(NSArray *)messageIds
                           shortcutName:(NSString *)shortcutName
                             completion:(void (^)(NSArray *messages, NSString *error))completion;

/// Sends the shortcut into a chat. `sendingId` is the client's own marker;
/// the answer carries the messages TDLib queued.
- (void)sendQuickReplyShortcutMessages:(NSInteger)shortcutId
                                toChat:(int64_t)chatId
                             sendingId:(int32_t)sendingId
                            completion:(void (^)(NSArray *messages, NSString *error))completion;

#pragma mark - checklists

/// Reads the message and returns its checklist: "title", "tasks" (each "id",
/// "text", "done"), "canAddTasks", "canMarkTasks", "othersCanAddTasks" and
/// "othersCanMarkTasks". Nil for a message that is not a checklist.
- (void)checklistForMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                 completion:(void (^)(NSDictionary *checklist, NSString *error))completion;

/// Replaces the whole checklist. `tasks` are dictionaries with "id" (0 for
/// a new task) and "text".
- (void)editMessageChecklist:(int64_t)messageId
                      inChat:(int64_t)chatId
                       title:(NSString *)title
                       tasks:(NSArray *)tasks
                othersCanAdd:(BOOL)othersCanAdd
              othersCanMark:(BOOL)othersCanMark
                  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)addChecklistTasks:(NSArray *)tasks
                toMessage:(int64_t)messageId
                   inChat:(int64_t)chatId
               completion:(void (^)(BOOL ok, NSString *error))completion;

/// `doneTaskIds` and `notDoneTaskIds` are the tasks to flip, by their int32
/// ids. Sending the same list on both sides is refused by the server.
- (void)markChecklistTasksAsDone:(NSArray *)doneTaskIds
                    notDoneTaskIds:(NSArray *)notDoneTaskIds
                         onMessage:(int64_t)messageId
                            inChat:(int64_t)chatId
                        completion:(void (^)(BOOL ok, NSString *error))completion;

/// Sends a new checklist into a chat. The same inputChecklist object the
/// editor builds, wrapped in a regular sendMessage.
- (void)sendChecklist:(NSString *)title
                tasks:(NSArray *)tasks
               toChat:(int64_t)chatId
           completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - suggested posts and actions

/// The message's suggested-post record: "price", "sendDate", "state",
/// "canBeApproved" and "canBeDeclined". Nil when the message is not one.
- (void)suggestedPostForMessage:(int64_t)messageId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSDictionary *post, NSString *error))completion;

- (void)approveSuggestedPost:(int64_t)messageId
                      inChat:(int64_t)chatId
                    sendDate:(NSInteger)sendDate
                  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)declineSuggestedPost:(int64_t)messageId
                      inChat:(int64_t)chatId
                     comment:(NSString *)comment
                  completion:(void (^)(BOOL ok, NSString *error))completion;

/// SuggestedAction objects from updateSuggestedActions. Rows keep Telegram's
/// object under "action" and add a readable "title".
@property (nonatomic, readonly) NSArray *suggestedActions;

- (void)hideSuggestedAction:(NSDictionary *)action
                 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - AI text and rich messages

- (void)composeTextWithAi:(NSString *)text
         translateTo:(NSString *)languageCode
               style:(NSString *)styleName
           addEmojis:(BOOL)addEmojis
          completion:(void (^)(NSString *text, NSString *error))completion;

- (void)composeRichMessageWithAi:(NSString *)text
                     translateTo:(NSString *)languageCode
                           style:(NSString *)styleName
                    customPrompt:(NSString *)customPrompt
                       addEmojis:(BOOL)addEmojis
                      completion:(void (^)(NSString *text, NSString *error))completion;

- (void)createRichMessageWithAi:(NSString *)prompt
                   languageCode:(NSString *)languageCode
                      addEmojis:(BOOL)addEmojis
                     completion:(void (^)(NSString *text, NSString *error))completion;

- (void)fixTextWithAi:(NSString *)text
           completion:(void (^)(NSString *text, NSString *diff, NSString *error))completion;

- (void)fixRichMessageWithAi:(NSString *)text
                  completion:(void (^)(NSString *text, NSString *error))completion;

- (void)summarizeMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
             translateTo:(NSString *)languageCode
                    tone:(NSString *)tone
              completion:(void (^)(NSString *text, NSString *error))completion;

- (void)translateMessageRichMessage:(int64_t)messageId
                             inChat:(int64_t)chatId
                             toCode:(NSString *)languageCode
                               tone:(NSString *)tone
                         completion:(void (^)(NSString *text, NSString *error))completion;

- (void)translateRichMessage:(NSString *)text
                      toCode:(NSString *)languageCode
                        tone:(NSString *)tone
                  completion:(void (^)(NSString *text, NSString *error))completion;

/// The whole rich message. Telegram truncates the block list on a normal
/// message read; this asks for the full one.
- (void)getFullRichMessage:(int64_t)messageId
                    inChat:(int64_t)chatId
                completion:(void (^)(NSString *text, NSDictionary *message, NSString *error))completion;

/// Sends a rich-message draft. Bots own this request, so a user account
/// gets Telegram's refusal in `error` - which is the honest answer.
- (void)sendRichMessageDraft:(NSString *)text
                      toChat:(int64_t)chatId
                     topicId:(int32_t)topicId
                     draftId:(int64_t)draftId
                     canStop:(BOOL)canStop
                  keepOnStop:(BOOL)keepOnStop
                  completion:(void (^)(BOOL ok, NSString *error))completion;

/// Sets or clears the fact-check line under a channel post. A nil or empty
/// `text` removes it, which TDLib spells as a null formattedText.
- (void)setMessageFactCheck:(int64_t)messageId
                     inChat:(int64_t)chatId
                       text:(NSString *)text
                 completion:(void (^)(BOOL ok, NSString *error))completion;

#pragma mark - shared shapes

/// An inputRichMessage with one paragraph per line, so a plain string can
/// reach every rich-message request.
+ (NSDictionary *)inputRichMessageWithText:(NSString *)text;

/// The readable text of a RichMessage: paragraphs, headings, lists, quotes
/// and captions, joined by newlines. Empty for a message this client cannot
/// read.
+ (NSString *)plainTextFromRichMessage:(NSDictionary *)richMessage;

/// inputChecklist with `tasks` (each "id" and "text") and the two
/// "others can" flags. Shared by the editor and the send path.
+ (NSDictionary *)inputChecklistWithTitle:(NSString *)title
                                    tasks:(NSArray *)tasks
                              othersCanAdd:(BOOL)othersCanAdd
                             othersCanMark:(BOOL)othersCanMark;

@end
