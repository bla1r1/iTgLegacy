#import "TGIcons.h"
#import "TGTheme.h"
#import "TGStyle.h"

UIImage *TGIconsGetCached(NSString *key);
void TGIconsSetCached(NSString *key, UIImage *img);
void TGIconsClearSettingsIconCache(void);

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

@interface TGIcons ()
+ (UIImage *)iconNamed:(NSString *)name draw:(void (^)(CGContextRef ctx, CGFloat s))draw;
@end
