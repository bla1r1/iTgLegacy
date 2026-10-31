//
// TGLottieView - renderer for Telegram animated stickers (.tgs / Lottie) and video stickers (.webm / VP9).
//
#import <UIKit/UIKit.h>

@interface TGLottieView : UIView

/// Load an animated sticker (.tgs or .webm). Returns NO if it cannot be
/// parsed yet. A sticker whose model is still building off the main thread
/// answers NO - the scroll is never held - and calls onStickerReady on the
/// main queue once it can be shown; the row reloads itself then.
- (BOOL)loadStickerFile:(NSString *)path;

/// Load a .tgs file (gzipped Lottie JSON). Returns NO if it cannot be parsed.
- (BOOL)loadTGSFile:(NSString *)path;

- (void)play;
- (void)stop;

/// Called on the main thread when a .webm that answered NO at load time has
/// been decoded and is ready. Never called for a file that failed to decode.
@property (nonatomic, copy) void (^onStickerReady)(void);

@property (nonatomic, readonly) BOOL loaded;
@property (nonatomic, readonly) BOOL isPlaying;

@end
