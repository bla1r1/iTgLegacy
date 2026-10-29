#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tactile iOS 6 Reimagined emoji reaction picker bar with spring animations,
/// specular highlight rim, and selection indication.
@interface TGReactionPicker : UIView

@property (nonatomic, copy) NSArray<NSString *> *emojis;
@property (nonatomic, copy, nullable) NSString *selectedEmoji;
@property (nonatomic, copy, nullable) void (^onEmojiSelected)(NSString *emoji);

+ (NSArray<NSString *> *)defaultReactions;

- (instancetype)initWithEmojis:(nullable NSArray<NSString *> *)emojis
                 selectedEmoji:(nullable NSString *)selectedEmoji;

@end

NS_ASSUME_NONNULL_END
