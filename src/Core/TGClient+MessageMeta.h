//
// TGClient+MessageMeta.h - the client surface for facts around one message: viewers, forwards, reactions, translate.
//
#import "TGClient+Base.h"

@interface TGClient (MessageMeta)

/// The reaction Telegram names as the default. nil until
/// updateDefaultReactionType has arrived; the picker keeps its own order then.
@property (nonatomic, readonly) NSString *defaultReactionEmoji;

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

/// The reactions this message offers, top row first. nil when the message
/// cannot be reacted to or has no explicit top list.
- (void)availableReactionsForMessage:(int64_t)messageId
							  inChat:(int64_t)chatId
						  completion:(void (^)(NSArray *emojis))completion;

- (void)addedReactionsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
						  emoji:(NSString *)emoji
						 offset:(NSString *)offset
					 completion:(void (^)(NSArray *rows, NSString *next))completion;

/// The same list for a reaction type that is not an emoji, chiefly a custom
/// emoji by id. `reactionType` is the TDLib ReactionType object.
- (void)addedReactionsOfMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
				   reactionType:(NSDictionary *)reactionType
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

/// The description of a message effect by id: "emoji", "premium" and the
/// effect's kind. nil when Telegram has no such effect.
- (void)messageEffectWithId:(int64_t)effectId
				 completion:(void (^)(NSDictionary *effect))completion;

/// What kind of export file a message file is, read from its first lines, so
/// the import sheet can name it before importing. nil for an unknown file.
- (void)messageFileTypeForHead:(NSString *)head
					completion:(void (^)(NSDictionary *fileType))completion;

/// The sentence Telegram wants shown before it starts importing into a chat.
- (void)importConfirmationTextForChat:(int64_t)chatId
						   completion:(void (^)(NSString *text))completion;

/// Imports an exported history file into a chat. `path` is a local file;
/// `attachedPaths` are the media files the export refers to.
- (void)importMessagesFromFile:(NSString *)path
				 attachedFiles:(NSArray *)attachedPaths
					  intoChat:(int64_t)chatId
					completion:(void (^)(BOOL ok))completion;

/// An inline message a bot prepared for this user, ready to be sent.
- (void)preparedInlineMessageFromBot:(int64_t)botUserId
				   preparedMessageId:(NSString *)preparedMessageId
						  completion:(void (^)(NSDictionary *prepared))completion;

/// Saves an inline result for another user to send; bots own the request, so
/// a user account gets nil back with the server's refusal.
- (void)savePreparedInlineMessageForUser:(int64_t)userId
									text:(NSString *)text
								   title:(NSString *)title
							  completion:(void (^)(NSString *preparedMessageId))completion;

/// A bot's streaming draft for a chat. `draftId` names the stream so stop
/// knows which one to stop; `canStop` shows the user a stop button.
- (void)sendTextDraft:(NSString *)text
			   toChat:(int64_t)chatId
				topic:(int64_t)topicId
			  draftId:(int64_t)draftId
			   canStop:(BOOL)canStop
				  keep:(BOOL)keepOnStop
		   completion:(void (^)(BOOL ok))completion;

/// Stops the draft stream `draftId` in a chat.
- (void)stopTextDraft:(int64_t)draftId
			   inChat:(int64_t)chatId
				topic:(int64_t)topicId
		   completion:(void (^)(BOOL ok))completion;

@end
