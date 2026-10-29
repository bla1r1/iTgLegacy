#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tactile recessed well input field adhering to iOS 6 depth,
/// with leading icon support, clear button, and error state indicator.
@interface TGTextField : UITextField

@property (nonatomic, strong, nullable) UIImage *leadingIcon;
@property (nonatomic, assign) BOOL hasError;

- (instancetype)initWithFrame:(CGRect)frame;

@end

NS_ASSUME_NONNULL_END
