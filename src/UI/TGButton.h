#import <UIKit/UIKit.h>
#import "TGTheme.h"
#import "TGStyle.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TGButtonVariant) {
    TGButtonVariantPrimary = 0,    ///< iOS 6 glossy blue action button
    TGButtonVariantSecondary,      ///< Brushed metallic silver button with dark etched text
    TGButtonVariantDestructive,    ///< Glossy crimson red destructive action button
    TGButtonVariantSuccess,        ///< Glossy emerald green accept/confirm button
    TGButtonVariantGhost           ///< Subtle translucent / etched ghost button
};

typedef NS_ENUM(NSInteger, TGButtonSize) {
    TGButtonSizeSmall = 0,         ///< 28 pt compact button
    TGButtonSizeMedium,            ///< 36 pt standard button
    TGButtonSizeLarge              ///< 44 pt prominent action button
};

/// Tactile, skeuomorphic button component delivering iOS 6 physical depth,
/// specular edge highlights, pressed displacement, and built-in activity states.
@interface TGButton : UIButton

@property (nonatomic, assign) TGButtonVariant variant;
@property (nonatomic, assign) TGButtonSize buttonSize;
@property (nonatomic, assign, getter=isBusy) BOOL busy;
@property (nonatomic, strong, nullable) UIImage *leftIcon;
@property (nonatomic, strong, nullable) UIImage *rightIcon;

+ (instancetype)buttonWithTitle:(NSString *)title
                        variant:(TGButtonVariant)variant
                           size:(TGButtonSize)size;

+ (instancetype)buttonWithTitle:(NSString *)title
                        variant:(TGButtonVariant)variant;

- (void)setVariant:(TGButtonVariant)variant size:(TGButtonSize)size;

@end

NS_ASSUME_NONNULL_END
