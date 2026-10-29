#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tactile, skeuomorphic slider with recessed well track, glossy fill
/// and metallic knurled thumb adhering to iOS 6 physics.
@interface TGSlider : UISlider

@property (nonatomic, strong, nullable) UIImage *leadingIcon;
@property (nonatomic, strong, nullable) UIImage *trailingIcon;

@end

NS_ASSUME_NONNULL_END
