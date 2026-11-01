//
// TGClient+BotTools.h - a bot's prepared keyboard button, read and written.
//
// A prepared button is the half of a keyboard a bot builds ahead of time: it
// is stored against a user and named by an opaque id, and a later message
// points at it. A user account may send the two requests; the server decides
// whether it will keep a button for a user, and the screen shows the answer.
//
#import "TGClient+Base.h"

@interface TGClient (BotTools)

/// One prepared button: "text", "type" (the keyboardButtonType without its
/// prefix, "text" for a plain button), "customEmojiId" and "style". Nil with
/// `error` when Telegram has no such button or refuses the read.
- (void)preparedKeyboardButtonFromBot:(int64_t)botUserId
					preparedButtonId:(NSString *)preparedButtonId
						   completion:(void (^)(NSDictionary *button,
												NSString *error))completion;

/// Stores a plain text button for `userId` and answers its prepared id. The
/// id is what a later message's keyboard names; an empty answer with no
/// error would be a bug, so the client treats a non-text reply as a refusal.
- (void)savePreparedKeyboardButtonText:(NSString *)text
							   forUser:(int64_t)userId
							completion:(void (^)(NSString *preparedButtonId,
												NSString *error))completion;

@end
