#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tactile skeuomorphic card container with specular highlight rim,
/// subtle ambient drop shadow, header section, and optional interactive touch handling.
@interface TGCardView : UIView

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, strong, readonly) UIView *contentContainer;
@property (nonatomic, assign, getter=isInteractive) BOOL interactive;
@property (nonatomic, copy, nullable) void (^tapHandler)(void);

- (instancetype)initWithTitle:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;

@end

NS_ASSUME_NONNULL_END
