//
// TGClient+Messages.h - the client surface for the message wire: history, sending, editing, deleting, searching.
//
#import "TGClient+Base.h"

@interface TGClient (Messages)

/// Title for a chat TDLib has told us about, or nil.
- (NSString *)titleForChat:(int64_t)chatId;

/// Newest `limit` messages of a chat, oldest first. Each entry has "id",
/// "text", "date", "outgoing" (NSNumber BOOL), "senderId", "photoId"
/// (NSNumber file id or nil).
- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

- (void)historyForChat:(int64_t)chatId
         fromMessageId:(int64_t)fromMessageId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

- (void)historyForChat:(int64_t)chatId
         fromMessageId:(int64_t)fromMessageId
                offset:(NSInteger)offset
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

- (void)newerHistoryForChat:(int64_t)chatId
              fromMessageId:(int64_t)fromMessageId
                      limit:(NSInteger)limit
                 completion:(void (^)(NSArray *messages))completion;

/// History of one forum topic. `threadId` is the topic's message_thread_id.
- (void)historyForChat:(int64_t)chatId
                thread:(int64_t)threadId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *messages))completion;

/// Pin a message to the top of the chat, or take it down again. `notify`
/// posts the "pinned a message" service message the way their clients do.
- (void)pinMessage:(int64_t)messageId inChat:(int64_t)chatId notify:(BOOL)notify;

- (void)unpinMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// Every pinned message down at once; `threadId` limits it to a forum topic.
- (void)unpinAllMessagesInChat:(int64_t)chatId thread:(int64_t)threadId;

/// The last message on or before `date` (unix seconds), or nil.
- (void)messageAtDate:(NSTimeInterval)date inChat:(int64_t)chatId
		   completion:(void (^)(NSDictionary *message))completion;

- (void)sendText:(NSString *)text toChat:(int64_t)chatId;

/// Send into a forum topic.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send as a reply to a message.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId;

/// The two scheduling states a send can carry; nil fields are refused by
/// TDLib, so the request without one is the send-now call in the header.
+ (NSDictionary *)scheduledAtDate:(NSTimeInterval)date;

+ (NSDictionary *)scheduledWhenOnline;

/// The reply send with one of those states attached.
- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId
        scheduled:(NSDictionary *)schedulingState;

/// What a chat has waiting. Flattened like the history is.
- (void)scheduledMessagesInChat:(int64_t)chatId
                     completion:(void (^)(NSArray *messages))completion;

/// Move a scheduled message: nil for `state` sends it now, which is TDLib's
/// meaning of an absent scheduling state.
- (void)setSchedulingState:(NSDictionary *)state
                forMessage:(int64_t)messageId
                    inChat:(int64_t)chatId
                completion:(void (^)(BOOL ok))completion;

/// Forward messages into another chat.
- (void)forwardMessages:(NSArray *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId;

/// Replace the text of a message already sent.
- (void)editMessage:(int64_t)messageId inChat:(int64_t)chatId text:(NSString *)text;

/// The caption under a picture, a video or a file - a different request from
/// editing text, which is why only text could be edited before.
- (void)editCaption:(NSString *)caption
		  ofMessage:(int64_t)messageId
			 inChat:(int64_t)chatId
		 completion:(void (^)(BOOL ok))completion;

/// Replaces the picture itself, keeping the message where it is. The caption
/// travels with it, because the request takes the whole content.
- (void)editPhotoAtPath:(NSString *)path
				caption:(NSString *)caption
			  ofMessage:(int64_t)messageId
				 inChat:(int64_t)chatId
			 completion:(void (^)(BOOL ok))completion;

/// Up to ten pictures as one message rather than as a run of separate ones.
/// Only the first carries the caption; TDLib refuses an album where more
/// than one does.
- (void)sendPhotoAlbumAtPaths:(NSArray *)paths
					  caption:(NSString *)caption
					   toChat:(int64_t)chatId
					   thread:(int64_t)threadId;

/// One message by id, flattened. Used to show what a reply is answering.
- (void)messageWithId:(int64_t)messageId
               inChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *message))completion;

/// Stickers the user reached for lately: "fileId", "emoji", "isAnimated".
- (void)recentStickersWithCompletion:(void (^)(NSArray *stickers))completion;

/// Send a sticker TDLib already knows, by file id.
- (void)sendStickerWithFileId:(NSInteger)fileId toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send a recorded voice note (.oga), with its duration in seconds.
- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
                 toChat:(int64_t)chatId thread:(int64_t)threadId;

/// Send a video file from the library.
- (void)sendVideoAtPath:(NSString *)path toChat:(int64_t)chatId;

/// Share a point on the map.
- (void)sendLocation:(double)latitude longitude:(double)longitude toChat:(int64_t)chatId;

/// A place that keeps changing, for `seconds` more. The send is answered
/// with the message itself - its id is what every later edit answers
/// through.
- (void)sendLiveLocation:(NSInteger)seconds
				latitude:(double)latitude
			   longitude:(double)longitude
				  toChat:(int64_t)chatId
			  completion:(void (^)(int64_t messageId))completion;

/// The moving pin, moved again, for `seconds` more of its period. 0 stops
/// it. nil id is refused, because a pin nobody can move is a lie on the map.
- (void)editLiveLocationOfMessage:(int64_t)messageId
						   inChat:(int64_t)chatId
						 latitude:(double)latitude
						longitude:(double)longitude
					   livePeriod:(NSInteger)seconds
					   completion:(void (^)(BOOL ok))completion;

/// Share someone from the address book.
- (void)sendContactNamed:(NSString *)name phone:(NSString *)phone toChat:(int64_t)chatId;

/// Send a local image file. TDLib uploads it and echoes the message back.
- (void)sendPhotoAtPath:(NSString *)path toChat:(int64_t)chatId;

/// Vote in a poll. `optionIds` are indexes into the poll's options.
- (void)votePoll:(int64_t)messageId inChat:(int64_t)chatId options:(NSArray *)optionIds;

/// What Telegram makes of a link: "url", "site", "title", "description",
/// "photoId" and "instantView". nil when the link has no preview, which is
/// most links.
- (void)linkPreviewForText:(NSString *)text
				completion:(void (^)(NSDictionary *preview))completion;

/// What a t.me or tg:// link points at, decided by Telegram rather than by
/// pattern-matching the path. The kind is one word - "publicChat",
/// "message", "stickerSet", "inviteLink", "phoneNumber" or "unknown" - with
/// the piece of it worth acting on.
- (void)internalLinkKind:(NSString *)link
			  completion:(void (^)(NSString *kind, NSString *value))completion;

/// A received formatted message handed back as the markdown its sender
/// typed: *bold*, `_italic_`, `code` - so Edit edits the origin, not the
/// render. A message with no markup comes back as its plain text.
- (void)markdownOfMessage:(int64_t)messageId
				   inChat:(int64_t)chatId
				completion:(void (^)(NSString *markdown))completion;

/// Telegram's own static map of a place, as a PNG, answered as a local path
/// once it is down - or nil, which on this device is ordinary. The drawn card
/// is what a caller falls back to.
- (void)mapThumbnailForLatitude:(double)latitude
					  longitude:(double)longitude
						  width:(NSInteger)width
						 height:(NSInteger)height
						 inChat:(int64_t)chatId
					 completion:(void (^)(NSString *path))completion;

/// Reports messages in a supergroup as spam. Reads the chat first: the
/// request wants the supergroup's own id, which a chat id is not.
- (void)reportSpamMessages:(NSArray *)messageIds
				    inChat:(int64_t)chatId
				completion:(void (^)(BOOL ok))completion;

/// Blocks whoever sent a message from replying again, optionally deleting
/// what they wrote and reporting it.
- (void)blockSenderOfMessage:(int64_t)messageId
			  deleteMessages:(BOOL)deleteMessages
				  reportSpam:(BOOL)reportSpam;

/// Closes a poll you sent; nobody can vote after that.
- (void)stopPoll:(int64_t)messageId inChat:(int64_t)chatId;

/// Who voted for one answer. `optionIndex` is the 0-based one; entries
/// carry "id", "name", "date".
- (void)pollVotersOfOption:(NSInteger)optionIndex
                ofMessage:(int64_t)messageId
                     inChat:(int64_t)chatId
                completion:(void (^)(NSArray *voters, BOOL end))completion;

/// The poll's vote statistics as one graph: the entries carry "json" (the
/// chart data as a JSON string) and "zoom". nil when the answer is an
/// error, which is how a poll without statistics everywhere says so.
- (void)pollVoteStatisticsOfMessage:(int64_t)messageId
							 inChat:(int64_t)chatId
						 completion:(void (^)(NSDictionary *graph))completion;

/// An option added after the poll went out, for polls that allow it.
- (void)addPollOption:(NSString *)text
            toMessage:(int64_t)messageId
                 inChat:(int64_t)chatId
            completion:(void (^)(BOOL ok))completion;

/// An option taken out again; `optionId` is the string id pollOption
/// carries, not an index.
- (void)deletePollOption:(NSString *)optionId
               ofMessage:(int64_t)messageId
                  inChat:(int64_t)chatId
              completion:(void (^)(BOOL ok))completion;

/// Every poll in the chat read up on, so the fresh-vote badge is gone.
- (void)readAllChatPollVotes:(int64_t)chatId;

/// Reports a reaction the flattening named - `sender` is the MessageSender
/// dict it carried, and TDLib files the report against whoever added it.
- (void)reportReactionBySender:(NSDictionary *)sender
					 ofMessage:(int64_t)messageId
						 inChat:(int64_t)chatId
					 completion:(void (^)(BOOL ok))completion;

/// React to a message with an emoji, as the current user.
- (void)reactTo:(int64_t)messageId inChat:(int64_t)chatId emoji:(NSString *)emoji;

/// Takes your own reaction back off. Nothing happens if it was not there.
- (void)removeReaction:(NSString *)emoji
		   fromMessage:(int64_t)messageId
				inChat:(int64_t)chatId;

/// it expires a few seconds after the last one. Cancel sends the stop.
- (void)sendTypingToChat:(int64_t)chatId thread:(int64_t)threadId;

- (void)cancelTypingInChat:(int64_t)chatId thread:(int64_t)threadId;

/// Marks a voice note, a video note or a one-time picture as opened, so the
/// sender's ticks say it was played.
- (void)openContentOfMessage:(int64_t)messageId inChat:(int64_t)chatId;

/// Sends failed messages again, by the ids they kept while failing.
- (void)resendMessages:(NSArray *)messageIds inChat:(int64_t)chatId;

/// The message a reply points at, fetched from the server - the history on
/// screen may not reach back far enough to hold it. nil when it is gone.
- (void)repliedMessageTo:(int64_t)messageId
				  inChat:(int64_t)chatId
			  completion:(void (^)(NSDictionary *message))completion;

/// Returns messages by their ids in a chat. Missing messages are returned as NSNull.
- (void)messagesInChat:(int64_t)chatId
			messageIds:(NSArray *)messageIds
			completion:(void (^)(NSArray *messages))completion;

/// Returns properties of a message (e.g. can_be_replied, can_get_message_thread).
- (void)messagePropertiesForChat:(int64_t)chatId
					   messageId:(int64_t)messageId
					  completion:(void (^)(NSDictionary *properties))completion;

/// A t.me link to one message, or nil for a chat that has no public link.
- (void)linkToMessage:(int64_t)messageId
			   inChat:(int64_t)chatId
		   completion:(void (^)(NSString *link))completion;

- (void)deleteMessage:(int64_t)messageId inChat:(int64_t)chatId;

- (void)deleteMessages:(NSArray *)messageIds inChat:(int64_t)chatId;

- (void)deleteMessages:(NSArray *)messageIds inChat:(int64_t)chatId revoke:(BOOL)revoke;

- (void)markRead:(NSArray *)messageIds inChat:(int64_t)chatId;

/// Search messages across every chat. Each result is a flattened message with
/// an extra "chatId" and "chatTitle" so it can be shown out of context.
- (void)searchMessages:(NSString *)query completion:(void (^)(NSArray *messages))completion;

/// Search inside one chat, newest first. Flattened messages.
- (void)searchInChat:(int64_t)chatId query:(NSString *)query
          completion:(void (^)(NSArray *messages))completion;

/// Bot buttons. See TGFlattenReplyMarkup for the button dictionaries.
- (void)pressCallbackButton:(NSDictionary *)button
					 inChat:(int64_t)chatId
				  messageId:(int64_t)messageId
				 completion:(void (^)(NSString *text, BOOL alert, NSString *url,
									  NSString *error))completion;

- (void)loginURLForButton:(NSDictionary *)button
				   inChat:(int64_t)chatId
				messageId:(int64_t)messageId
			   completion:(void (^)(NSString *url, NSString *confirmDomain,
									NSString *error))completion;

- (void)confirmLoginButton:(NSDictionary *)button
					inChat:(int64_t)chatId
				 messageId:(int64_t)messageId
				completion:(void (^)(NSString *url, NSString *error))completion;

/// The reply keyboard a bot left on the chat, or nil.
- (void)replyKeyboardForChat:(int64_t)chatId completion:(void (^)(NSDictionary *keyboard))completion;

/// A channel post's comments: its discussion group and the thread in it.
- (void)commentThreadForChat:(int64_t)chatId
				   messageId:(int64_t)messageId
				  completion:(void (^)(int64_t discussionChatId, int64_t threadId,
									   NSString *error))completion;

@end
