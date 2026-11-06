//
// TGClient+EmojiStatus - the badge beside a name: the lists Telegram offers
// for an account and for a chat, and the two requests that wear one.
//
#import "TGClient+Base.h"

/// The custom emoji id a TDLib emojiStatus draws, or 0: a gift status
/// falls back to its model's emoji, as Telegram draws it.
FOUNDATION_EXPORT int64_t TGEmojiStatusCustomEmojiId(NSDictionary *status);

@interface TGClient (EmojiStatus)

/// Up to eight statuses Telegram places after the default Premium badge.
/// Each entry is an NSNumber custom-emoji id.
- (void)themedEmojiStatusesWithCompletion:(void (^)(NSArray *emojiIds))completion;

/// The statuses any account may wear. NSNumber custom-emoji ids.
- (void)defaultEmojiStatusesWithCompletion:(void (^)(NSArray *emojiIds))completion;

/// Recently worn statuses as dictionaries: "emojiId", "expirationDate" and
/// "kind" ("customEmoji", "upgradedGift" or "unknown").
- (void)recentEmojiStatusesWithCompletion:(void (^)(NSArray *statuses))completion;

/// The same for a chat's badge. Telegram allows a narrower set there, so the
/// picker reads the chat lists rather than the account ones.
- (void)themedChatEmojiStatusesWithCompletion:(void (^)(NSArray *emojiIds))completion;
- (void)defaultChatEmojiStatusesWithCompletion:(void (^)(NSArray *emojiIds))completion;

/// Statuses Telegram refuses as a chat badge. The picker draws them greyed
/// out instead of offering a request that is certain to fail.
- (void)disallowedChatEmojiStatusesWithCompletion:(void (^)(NSArray *emojiIds))completion;

- (void)clearRecentEmojiStatusesWithCompletion:(void (^)(BOOL ok, NSString *error))completion;

/// Wear `customEmojiId` until `expirationDate` (unix seconds, 0 for no end).
/// An id of 0 takes the badge off, which TDLib spells as a null status.
- (void)setEmojiStatus:(int64_t)customEmojiId
        expirationDate:(NSInteger)expirationDate
            completion:(void (^)(BOOL ok, NSString *error))completion;

/// A bot may change someone else's badge. The screen sends it and shows the
/// server's refusal for an ordinary account, which is the honest answer.
- (void)setUserEmojiStatus:(int64_t)customEmojiId
            expirationDate:(NSInteger)expirationDate
                   forUser:(int64_t)userId
                completion:(void (^)(BOOL ok, NSString *error))completion;

/// A group's or channel's badge. An id of 0 clears it.
- (void)setChatEmojiStatus:(int64_t)customEmojiId
            expirationDate:(NSInteger)expirationDate
                    inChat:(int64_t)chatId
                completion:(void (^)(BOOL ok, NSString *error))completion;

@end
