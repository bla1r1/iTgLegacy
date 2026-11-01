#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tactile iOS 6 Reimagined emoji reaction picker bar with spring animations,
/// specular highlight rim, and selection indication.
@interface TGReactionPicker : UIView

@property (nonatomic, copy) NSArray<NSString *> *emojis;
@property (nonatomic, copy, nullable) NSString *selectedEmoji;
@property (nonatomic, copy, nullable) void (^onEmojiSelected)(NSString *emoji);
/// Holding a reaction asks for it to become the default. nil leaves the bar
/// as it is, which is what a picker shown outside the chat wants.
@property (nonatomic, copy, nullable) void (^onDefaultRequested)(NSString *emoji);

+ (NSArray<NSString *> *)defaultReactions;

- (instancetype)initWithEmojis:(nullable NSArray<NSString *> *)emojis
                 selectedEmoji:(nullable NSString *)selectedEmoji;

/// Move one emoji to the front and select it. The popup calls this after the
/// default was accepted so the bar it left open already leads with it.
- (void)promoteEmoji:(NSString *)emoji;

@end

NS_ASSUME_NONNULL_END
