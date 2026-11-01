//
// TGClient+MessageMeta.h - the client surface for facts around one message: viewers, forwards, reactions, translate.
//
#import "TGClient+Base.h"

@interface TGClient (MessageMeta)

/// The chat and the exact message a "message"-kind link resolves to: a
/// t.me/name/12345 landed on. The chat id is 0 when Telegram refused.
- (void)messageLinkInfo:(NSString *)link
			 completion:(void (^)(int64_t chatId, int64_t messageId))completion;

/// Every cache's draft dropped at once, on every device.
- (void)clearAllDraftMessages;

/// The lifetime new chats carry when nobody chose one. Zero is off.
- (void)defaultMessageAutoDeleteTimeWithCompletion:
		(void (^)(NSInteger seconds))completion;

- (void)setDefaultMessageAutoDeleteTime:(NSInteger)seconds;

- (void)viewersOfMessage:(int64_t)messageId
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSArray *viewers))completion;

/// A nil date with the reason word is the honest sheet line.
- (void)readDateOfMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
			   completion:(void (^)(NSTimeInterval date, NSString *reason))completion;

- (void)authorOfMessage:(int64_t)messageId
				inChat:(int64_t)chatId
			 completion:(void (^)(NSDictionary *user))completion;

- (void)embeddingCodeOfMessage:(int64_t)messageId
						inChat:(int64_t)chatId
						 album:(BOOL)album
					completion:(void (^)(NSString *code))completion;

- (void)publicForwardsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
					 completion:(void (^)(NSArray *messages))completion;

- (void)addedReactionsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
						  emoji:(NSString *)emoji
						 offset:(NSString *)offset
					 completion:(void (^)(NSArray *rows, NSString *next))completion;

- (void)deleteReactionsOfSender:(NSDictionary *)sender
					  ofMessage:(int64_t)messageId
						 inChat:(int64_t)chatId;

- (void)deleteAllReactionsOfSender:(NSDictionary *)sender inChat:(int64_t)chatId;

- (void)messageCountInChat:(int64_t)chatId
					thread:(int64_t)threadId
				completion:(void (^)(NSInteger count))completion;

- (void)calendarJumpForChat:(int64_t)chatId
					 endDate:(NSInteger)end
				  completion:(void (^)(int64_t messageId, NSInteger total))completion;

- (void)clearAllCallMessages;

- (void)sentDocuments:(NSString *)query
			 completion:(void (^)(NSArray *messages))completion;

- (void)publicMessagesByTag:(NSString *)tag
					 offset:(NSString *)offset
				completion:(void (^)(NSArray *messages, NSString *next))completion;

- (void)recentLocationsInChat:(int64_t)chatId
				   completion:(void (^)(NSArray *messages))completion;

- (void)translateMessage:(int64_t)messageId
				  inChat:(int64_t)chatId
				 toCode:(NSString *)languageCode
			  completion:(void (^)(NSString *text))completion;

@end
