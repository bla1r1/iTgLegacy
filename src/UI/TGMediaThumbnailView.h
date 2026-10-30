//
// TGMediaThumbnailView.h
// TGUI Component Framework
//
#import <UIKit/UIKit.h>

@interface TGMediaThumbnailView : UIView

@property (nonatomic, strong, readonly) UIImageView *imageView;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, copy) NSString *durationText;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) CGFloat cornerRadius;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)reset;

@end
