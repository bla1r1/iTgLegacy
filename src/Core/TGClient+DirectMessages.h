//
// TGClient+DirectMessages - the topics of a channel direct messages chat.
//
// A channel that turns on direct messages gets one topic per person who
// writes to it. loadDirectMessagesChatTopics starts the stream and
// updateDirectMessagesChatTopic keeps it; every other call acts on one topic.
//
#import "TGClient+Base.h"

@interface TGClient (DirectMessages)

/// The topics already streamed for `chatId`, newest order first. Each entry:
/// "topicId", "chatId", "senderKind" ("user" or "chat"), "senderId",
/// "senderName", "order", "unread", "unreadReactions", "isMarkedUnread",
/// "canSendUnpaid", "lastReadInbox", "lastReadOutbox", "lastMessage" (flattened
/// or NSNull) and "draftText".
- (NSArray *)directMessagesChatTopicsForChat:(int64_t)chatId;

/// Asks Telegram for more topics. Answers OK and streams the rows through
/// updateDirectMessagesChatTopic; a 404 means the list is complete.
- (void)loadDirectMessagesChatTopicsInChat:(int64_t)chatId
                                     limit:(NSInteger)limit
                                completion:(void (^)(BOOL ok,
                                                     NSString *error))completion;

/// One topic read fresh: the same shape as a list row.
- (void)directMessagesChatTopic:(int64_t)topicId
                         inChat:(int64_t)chatId
                     completion:(void (^)(NSDictionary *topic,
                                          NSString *error))completion;

/// Newest `limit` messages, oldest first, flattened the way the chat screen
/// flattens history.
- (void)directMessagesChatTopicHistory:(int64_t)topicId
                                inChat:(int64_t)chatId
                         fromMessageId:(int64_t)fromMessageId
                                offset:(NSInteger)offset
                                 limit:(NSInteger)limit
                            completion:(void (^)(NSArray *messages,
                                                 NSString *error))completion;

/// The last message in the topic on or before `date` (unix seconds).
- (void)directMessagesChatTopicMessageByDate:(int64_t)topicId
                                      inChat:(int64_t)chatId
                                        date:(NSInteger)date
                                  completion:(void (^)(NSDictionary *message,
                                                       NSString *error))completion;

- (void)deleteDirectMessagesChatTopicHistory:(int64_t)topicId
                                      inChat:(int64_t)chatId
                                  completion:(void (^)(BOOL ok,
                                                       NSString *error))completion;

- (void)deleteDirectMessagesChatTopicMessages:(int64_t)topicId
                                       inChat:(int64_t)chatId
                                     minDate:(NSInteger)minDate
                                     maxDate:(NSInteger)maxDate
                                  completion:(void (^)(BOOL ok,
                                                       NSString *error))completion;

- (void)setDirectMessagesChatTopic:(int64_t)topicId
                            inChat:(int64_t)chatId
                  markedAsUnread:(BOOL)markedAsUnread
                        completion:(void (^)(BOOL ok,
                                             NSString *error))completion;

- (void)readAllDirectMessagesChatTopicReactions:(int64_t)topicId
                                         inChat:(int64_t)chatId
                                     completion:(void (^)(BOOL ok,
                                                          NSString *error))completion;

- (void)unpinAllDirectMessagesChatTopicMessages:(int64_t)topicId
                                         inChat:(int64_t)chatId
                                     completion:(void (^)(BOOL ok,
                                                          NSString *error))completion;

@end
