#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Classic iOS 6 skeuomorphic segmented control with metallic satin frame,
/// engraved dividers, and tactile sliding active pill indicator.
@interface TGSegmentedControl : UIControl

@property (nonatomic, copy) NSArray *items;
@property (nonatomic, assign) NSInteger selectedSegmentIndex;

- (instancetype)initWithItems:(nullable NSArray *)items;
- (void)setSelectedSegmentIndex:(NSInteger)selectedSegmentIndex animated:(BOOL)animated;
- (void)setTitle:(NSString *)title forSegmentAtIndex:(NSUInteger)segment;
- (nullable NSString *)titleForSegmentAtIndex:(NSUInteger)segment;

@end

NS_ASSUME_NONNULL_END
