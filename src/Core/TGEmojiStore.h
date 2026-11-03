//
// TGEmojiStore - the emoji panel's view of the client: categories, search,
// keyword suggestions and the one-off metadata cards. The panel is a view and
// asks this store rather than TGClient, the same way the sticker tab asks
// TGStickerStore.
//
#import <Foundation/Foundation.h>

@interface TGEmojiStore : NSObject

+ (instancetype)shared;

/// Drops the cached category list, so the next account asks TDLib afresh
/// instead of showing the previous account's emoji categories.
- (void)reset;

/// Telegram's categories, cached after the first non-empty answer so reopening
/// the panel draws the strip before the round trip. The entries are the shape
/// TGClient's -emojiCategoriesWithCompletion: documents.
- (void)categoriesWithCompletion:(void (^)(NSArray *categories))completion;

/// Emoji matching a word, with the device's preferred languages sent along so
/// TDLib can break ties the way the user's keyboard would.
- (void)searchEmojis:(NSString *)text
          completion:(void (^)(NSArray *emojis))completion;

/// The emoji filed under one keyword, shown as the search's suggestion row.
- (void)keywordEmojis:(NSString *)text
           completion:(void (^)(NSArray *emojis))completion;

/// The translation platform's short-lived suggestion link.
- (void)suggestionsUrlForLanguage:(NSString *)languageCode
                       completion:(void (^)(NSString *url))completion;

/// One reaction's title and animation, or nil when it is not a reaction.
- (void)reactionForEmoji:(NSString *)emoji
              completion:(void (^)(NSDictionary *reaction))completion;

/// The animated sticker for a plain emoji, or nil.
- (void)animatedEmojiForEmoji:(NSString *)emoji
                   completion:(void (^)(NSDictionary *animated))completion;

/// The generic TGS animations for custom-emoji reactions.
- (void)customEmojiReactionAnimationsWithCompletion:
		(void (^)(NSArray *stickers))completion;

@end
