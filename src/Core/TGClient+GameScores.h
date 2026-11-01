//
// TGClient+GameScores.h - the score table of a game message and the inline
// equivalent. Telegram reserves setGameScore and setInlineGameScore for the
// bot that serves the game, so a user session gets a refusal; the screen
// shows it. The two getters are reads the same bot can make.
//
#import "TGClient+Base.h"

@interface TGClient (GameScores)

/// Rows of "position", "userId" and "score".
- (void)gameHighScoresForChat:(int64_t)chatId
					  message:(int64_t)messageId
						 user:(int64_t)userId
				   completion:(void (^)(NSArray *scores,
										NSString *error))completion;

- (void)inlineGameHighScores:(NSString *)inlineMessageId
						 user:(int64_t)userId
				   completion:(void (^)(NSArray *scores,
										NSString *error))completion;

/// The edited message, flattened to the fields a row draws.
- (void)setGameScoreForChat:(int64_t)chatId
					message:(int64_t)messageId
					 user:(int64_t)userId
					  score:(int32_t)score
					  force:(BOOL)force
			 editMessage:(BOOL)editMessage
				 completion:(void (^)(NSDictionary *message,
									  NSString *error))completion;

- (void)setInlineGameScore:(NSString *)inlineMessageId
					  user:(int64_t)userId
					 score:(int32_t)score
					 force:(BOOL)force
			   editMessage:(BOOL)editMessage
				completion:(void (^)(BOOL ok, NSString *error))completion;

@end

// vim:ft=objc
