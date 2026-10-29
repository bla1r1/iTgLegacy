#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TGBadgeVariant) {
    TGBadgeVariantNotification = 0, ///< Glossy crimson red notification badge
    TGBadgeVariantAccent,          ///< Glossy blue accent badge
    TGBadgeVariantMuted,           ///< Metallic gray muted badge
    TGBadgeVariantSuccess          ///< Glossy emerald green badge
};

/// Tactile iOS 6 notification badge pill with top glass sheen highlight,
/// 1px specular border, and embossed white etched typography.
@interface TGBadge : UIView

@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) TGBadgeVariant variant;

+ (instancetype)badgeWithCount:(NSInteger)count;
+ (instancetype)badgeWithText:(NSString *)text variant:(TGBadgeVariant)variant;

@end

NS_ASSUME_NONNULL_END
