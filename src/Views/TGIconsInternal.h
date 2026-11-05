#import "TGIcons.h"
#import "TGTheme.h"
#import "TGStyle.h"

UIImage *TGIconsGetCached(NSString *key);
void TGIconsSetCached(NSString *key, UIImage *img);
void TGIconsClearSettingsIconCache(void);
CGFloat TGMainScreenScale(void);

/// One weight for the whole line-art family. The set was drawn at ten
/// different widths - 1.3 through 5.0 - and send sat next to attach in the
/// same bar at 2.4 and 2.0, which is what makes a set of icons read as a
/// pile of icons. Anything that scales with its box (a waveform, the mark on
/// an avatar) sets its own and is not part of this.
static const CGFloat TGIconStroke = TGMetricStrokeIcon;
/// The same family drawn small. A delivery tick is twelve points across and
/// a checkbox not much more; the ordinary weight on a mark that size closes
/// up its own corners. Only for glyphs under about sixteen points.
static const CGFloat TGIconStrokeFine = TGMetricStrokeFine;

/// Add a published icon's path (TGIconPaths) fitted into `box` to the
/// current path. NO for a name that keeps its hand-drawn version.
BOOL TGIconAddPath(CGContextRef ctx, const char *name, CGRect box);

@interface TGIcons ()
/// The published icon in the usual 28-point template box, or nil.
+ (UIImage *)pathIconNamed:(NSString *)name;
/// The same with `margin` of the box left empty on each side; tab bar
/// glyphs use 0 to stand as tall as their neighbours.
+ (UIImage *)pathIconNamed:(NSString *)name margin:(CGFloat)margin;
+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw;
@end
