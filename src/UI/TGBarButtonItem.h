//
// TGBarButtonItem.h
// TGUI Component Framework
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGBarButtonItemStyle) {
	TGBarButtonItemStyleBordered = 0,
	TGBarButtonItemStyleDone,
	TGBarButtonItemStyleBack,
	TGBarButtonItemStylePlain
};

@interface TGBarButtonItem : UIBarButtonItem

@property (nonatomic, assign) TGBarButtonItemStyle itemStyle;
@property (nonatomic, strong, readonly) UIButton *customButton;

- (instancetype)initWithTitle:(NSString *)title style:(TGBarButtonItemStyle)style target:(id)target action:(SEL)action;
- (instancetype)initWithImage:(UIImage *)image style:(TGBarButtonItemStyle)style target:(id)target action:(SEL)action;
- (instancetype)initBackButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;

@end
