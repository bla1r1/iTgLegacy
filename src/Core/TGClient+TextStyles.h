//
// TGClient+TextStyles - custom text composition styles: the list Telegram
// streams through updateTextCompositionStyles, and the seven calls that
// create, edit, find, preview, add and remove one.
//
#import "TGClient+Base.h"

@interface TGClient (TextStyles)

/// The styles this account may use, kept live by updateTextCompositionStyles.
/// Each entry: "name", "title", "emojiId", "isCustom", "isCreator",
/// "installCount", "prompt", "creatorUserId".
@property (nonatomic, readonly) NSArray *textCompositionStyles;

/// Creates a style. TDLib answers the whole object, so the screen does not
/// wait for the update to draw it.
- (void)createTextCompositionStyle:(NSString *)title
                           emojiId:(int64_t)customEmojiId
                            prompt:(NSString *)prompt
                       showCreator:(BOOL)showCreator
                        completion:(void (^)(NSDictionary *style,
                                             NSString *error))completion;

- (void)editTextCompositionStyleNamed:(NSString *)name
                                title:(NSString *)title
                              emojiId:(int64_t)customEmojiId
                               prompt:(NSString *)prompt
                          showCreator:(BOOL)showCreator
                           completion:(void (^)(NSDictionary *style,
                                                NSString *error))completion;

- (void)deleteTextCompositionStyleNamed:(NSString *)name
                             completion:(void (^)(BOOL ok,
                                                  NSString *error))completion;

/// Telegram's 404 means there is no style by that name. It is returned as an
/// error sentence so the manager can show it rather than an empty row.
- (void)searchTextCompositionStyleNamed:(NSString *)name
                             completion:(void (^)(NSDictionary *style,
                                                  NSString *error))completion;

/// An example of the style in use. `number` is 0-based; the screen walks it
/// until Telegram answers 404. Keys: "sourceText", "resultText" and the two
/// entity arrays under "sourceEntities" / "resultEntities".
- (void)textCompositionStyleExampleNamed:(NSString *)name
                                  number:(NSInteger)number
                              completion:(void (^)(NSDictionary *example,
                                                   NSString *error))completion;

/// Puts the style into the used list the composer's style picker reads.
- (void)addTextCompositionStyleNamed:(NSString *)name
                          completion:(void (^)(BOOL ok,
                                               NSString *error))completion;

/// Takes it out again. A style this account created is deleted, not removed.
- (void)removeTextCompositionStyleNamed:(NSString *)name
                             completion:(void (^)(BOOL ok,
                                                  NSString *error))completion;

@end
