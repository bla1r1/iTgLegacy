//
// TGLottieView - renderer for Telegram animated stickers (.tgs / Lottie) and video stickers (.webm / VP9).
//
#import <UIKit/UIKit.h>

@interface TGLottieView : UIView

/// Load an animated sticker (.tgs or .webm). Returns NO if it cannot be parsed.
- (BOOL)loadStickerFile:(NSString *)path;

/// Load a .tgs file (gzipped Lottie JSON). Returns NO if it cannot be parsed.
- (BOOL)loadTGSFile:(NSString *)path;

- (void)play;
- (void)stop;

@property (nonatomic, readonly) BOOL loaded;
@property (nonatomic, readonly) BOOL isPlaying;

@end
