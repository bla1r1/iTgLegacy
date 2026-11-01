//
// TGSVGPath - the path data of an SVG icon ("d" attribute) as a CGPath.
//
// Icons are kept as the vector paths their sets publish and filled at
// whatever size a screen asks for, so every one is the original shape with
// CoreGraphics antialiasing - not a hand-drawn imitation. Plain C, no UIKit:
// the host tests run it.
//
#ifndef TG_SVG_PATH_H
#define TG_SVG_PATH_H

#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Parse `d` (M L H V C S Q T A Z, absolute and relative) drawn in a
/// `viewBox` of 0 0 w h and fit it, centred and unstretched, into `box`.
/// Y runs down as in SVG, which is also UIKit's drawing direction. NULL for
/// empty or unreadable data. The caller releases the result.
CGPathRef TGSVGPathCreate(const char *d, CGFloat viewW, CGFloat viewH, CGRect box);

#ifdef __cplusplus
}
#endif

#endif
