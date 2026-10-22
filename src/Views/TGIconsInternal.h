#import "TGIcons.h"
#import "TGTheme.h"

UIImage *TGIconsGetCached(NSString *key);
void TGIconsSetCached(NSString *key, UIImage *img);
void TGIconsClearSettingsIconCache(void);

@interface TGIcons ()
+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw;
@end
