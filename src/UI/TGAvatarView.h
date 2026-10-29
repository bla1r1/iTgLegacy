#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tactile skeuomorphic avatar component with automatic initials rendering,
/// async photo loading, 1px specular rim border, and online presence badge indicator.
@interface TGAvatarView : UIView

@property (nonatomic, assign) CGFloat avatarSide;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, assign, getter=isOnline) BOOL online;
@property (nonatomic, copy, nullable) void (^tapHandler)(void);

- (instancetype)initWithSide:(CGFloat)side;

- (void)setName:(nullable NSString *)name colourId:(int64_t)colourId;
- (void)setImagePath:(nullable NSString *)path;

@end

NS_ASSUME_NONNULL_END
