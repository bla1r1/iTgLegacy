//
// TGClient+Dice - the stake dice state and the ephemeral message calls.
//
// The stake dice is the TON game in a channel direct messages chat; the
// state is what a send has to quote. Ephemeral messages are a bot-side
// surface: a user account sends the request and Telegram answers with its
// refusal, which the screen shows instead of pretending.
//
#import "TGClient+Base.h"

@interface TGClient (Dice)

/// The current stake dice state: "stateHash", "stakeGramAmount",
/// "suggestedStakeGramAmounts" (NSNumbers), "currentStreak",
/// "prizePerMille" (six NSNumbers, one per face) and "streakPrizePerMille".
- (void)stakeDiceStateWithCompletion:(void (^)(NSDictionary *state,
                                              NSString *error))completion;

/// Sends an ephemeral text into one bot chat. `receiverUserId` is the bot;
/// `ephemeralReplyId` replies to an ephemeral message when non-zero. The
/// answer is the flattened message, or the server's refusal.
- (void)sendEphemeralText:(NSString *)text
                   toChat:(int64_t)chatId
           receiverUserId:(int64_t)receiverUserId
          ephemeralReplyId:(NSInteger)ephemeralReplyId
               completion:(void (^)(NSDictionary *message,
                                    NSString *error))completion;

- (void)editEphemeralMessage:(NSInteger)ephemeralMessageId
                        text:(NSString *)text
                    receiver:(int64_t)receiverUserId
                      inChat:(int64_t)chatId
                  completion:(void (^)(BOOL ok, NSString *error))completion;

- (void)editEphemeralMessageCaption:(NSInteger)ephemeralMessageId
                            caption:(NSString *)caption
                           receiver:(int64_t)receiverUserId
                             inChat:(int64_t)chatId
                         completion:(void (^)(BOOL ok,
                                              NSString *error))completion;

- (void)deleteEphemeralMessage:(NSInteger)ephemeralMessageId
                      receiver:(int64_t)receiverUserId
                        inChat:(int64_t)chatId
                    completion:(void (^)(BOOL ok, NSString *error))completion;

/// Strips the ephemeral half off a regular message, reverting it to what it
/// was before the bot replaced its content.
- (void)deleteMessageEphemeralContent:(int64_t)messageId
                              inChat:(int64_t)chatId
                          completion:(void (^)(BOOL ok,
                                               NSString *error))completion;

@end
