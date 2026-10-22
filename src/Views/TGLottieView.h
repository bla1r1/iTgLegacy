//
// TGLottieView - renderer for Telegram animated stickers (.tgs / Lottie).
//
#import <UIKit/UIKit.h>

@interface TGLottieView : UIView

/// Load a .tgs file (gzipped Lottie JSON). Returns NO if it cannot be parsed.
- (BOOL)loadTGSFile:(NSString *)path;

- (void)play;
- (void)stop;

@property (nonatomic, readonly) BOOL loaded;

@end
