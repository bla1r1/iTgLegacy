//
// TGCustomEmojiStore - still pictures of custom emoji for the screens that
// draw them: an emoji status beside a name, a custom emoji inside a message.
// Views ask this store, never TGClient.
//
#import <UIKit/UIKit.h>

/// Posted on the main thread when a picture asked for earlier is ready.
/// userInfo "id" is the custom emoji id as an NSNumber.
extern NSString *const TGCustomEmojiLoadedNotification;

@interface TGCustomEmojiStore : NSObject

+ (instancetype)shared;

/// The picture at `side` points, or nil while it loads. A nil starts the load
/// once; TGCustomEmojiLoadedNotification follows when it is ready. Ids asked
/// for within 50 ms go to TDLib as one getCustomEmojiStickers call.
- (UIImage *)imageForId:(int64_t)emojiId side:(CGFloat)side;

/// Forgets every picture and pending request, for an account switch.
- (void)reset;

@end
