#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Authentic iOS 6 tactile skeuomorphic switch control with recessed
/// track well, metallic knurled thumb, smooth sliding and physical snap.
@interface TGSwitch : UIControl

@property (nonatomic, assign, getter=isOn) BOOL on;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setOn:(BOOL)on animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
