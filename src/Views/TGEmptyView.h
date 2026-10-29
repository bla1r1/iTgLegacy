//
// TGEmptyView.h - Tactile Empty State Presentation
// Centered vector iconography, embossed typography, and action buttons.
//
#import <UIKit/UIKit.h>

@interface TGEmptyView : UIView

@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UIButton *actionButton;

+ (instancetype)emptyViewWithFrame:(CGRect)frame
                             image:(UIImage *)image
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle
                       buttonTitle:(NSString *)buttonTitle
                            target:(id)target
                            action:(SEL)action;

@end
