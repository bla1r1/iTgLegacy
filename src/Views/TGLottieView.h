//
// TGLottieView - plays Telegram animated stickers (.tgs).
//
// A .tgs is gzipped Lottie JSON. Telegram restricts what it allows to a small
// subset - shape layers only, no images, no expressions, no text - which is
// what makes writing a player for it feasible at all. This one covers:
//
//   * shape layers: groups, paths, ellipses, rectangles, fills, strokes
//   * transforms: anchor, position, scale, rotation, opacity
//   * animated properties with keyframe interpolation
//   * layer parenting and in/out points
//
// Not covered: masks, mattes, trim paths, gradients, repeaters, merge paths.
// Stickers that lean on those will draw approximately or drop the layer.
//
#import <UIKit/UIKit.h>

@interface TGLottieView : UIView

/// Load a .tgs file (gzipped Lottie JSON). Returns NO if it cannot be parsed.
- (BOOL)loadTGSFile:(NSString *)path;

- (void)play;
- (void)stop;

@property (nonatomic, readonly) BOOL loaded;

@end
