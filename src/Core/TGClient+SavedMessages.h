//
// TGClient+SavedMessages.h - the client surface for welcome messages and the Saved Messages topics.
//
#import "TGClient+Base.h"

@interface TGClient (SavedMessages)

/// Whether a compose with this user can go through at all: "ok",
/// "paidMessages", "userDeleted" or "userRestrictsNewChats".
- (void)canSendMessageToUser:(int64_t)userId
				  completion:(void (^)(NSString *result))completion;

- (void)loadSavedMessagesTopics;

- (void)welcomeMessagesOfChat:(int64_t)chatId
				   completion:(void (^)(NSArray *welcomes))completion;

- (void)addWelcomeMessageToChat:(int64_t)chatId
						   text:(NSString *)text
					 completion:(void (^)(BOOL ok))completion;

- (void)setWelcomeMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
					 text:(NSString *)text
			   completion:(void (^)(BOOL ok))completion;

- (void)deleteWelcomeMessage:(int64_t)messageId inChat:(int64_t)chatId;

- (void)clearAllWelcomeMessagesInChat:(int64_t)chatId;

- (void)availableMessageSendersInChat:(int64_t)chatId
						   completion:(void (^)(NSArray *senders))completion;

- (void)setMessageSender:(NSDictionary *)sender
				  inChat:(int64_t)chatId
			  completion:(void (^)(BOOL ok))completion;

- (void)deleteChatMessagesByDate:(int64_t)chatId
						  minDate:(NSInteger)minDate
						  maxDate:(NSInteger)maxDate
						   revoke:(BOOL)revoke;

- (void)deleteChatMessagesBySender:(NSDictionary *)sender
							inChat:(int64_t)chatId
							revoke:(BOOL)revoke;

- (void)labelSavedTag:(NSDictionary *)tag label:(NSString *)label;

- (void)toggleSavedTopicPinned:(int64_t)topicId pinned:(BOOL)pinned;

- (void)setPinnedSavedTopics:(NSArray *)topicIds;

- (void)savedTopicsTags:(int64_t)topicId
			 completion:(void (^)(NSArray *tags))completion;

- (void)searchSavedMessagesInTopic:(int64_t)topicId
							 query:(NSString *)query
							 tag:(NSDictionary *)tag
							  from:(int64_t)fromMessageId
					completion:(void (^)(NSArray *found, int64_t next))completion;

- (void)clearSavedTopicMessagesBefore:(int64_t)topicId
							 minDate:(NSInteger)minDate
							 maxDate:(NSInteger)maxDate;

- (void)savedTopicMessageAtDate:(int64_t)topicId
						 date:(NSInteger)date
					completion:(void (^)(NSDictionary *message))completion;

@end
