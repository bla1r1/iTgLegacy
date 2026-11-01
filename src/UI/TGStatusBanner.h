//
// TGStatusBanner.h - Tactical Status & Connection Banners
// Pinned status strip for connection states, sync progress, and offline alerts.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGStatusBannerKind) {
    TGStatusBannerKindConnecting = 0,
    TGStatusBannerKindUpdating,
    TGStatusBannerKindOffline,
    TGStatusBannerKindError
};

@interface TGStatusBanner : UIView

+ (instancetype)showInView:(UIView *)host
                      kind:(TGStatusBannerKind)kind
                      text:(NSString *)text
                  animated:(BOOL)animated;

+ (void)hideFromView:(UIView *)host animated:(BOOL)animated;

@end
