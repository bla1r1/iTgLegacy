//
// TGIconPaths - the SVG path of every icon taken from a published set
// (scripts/icon_picks.txt), looked up by its TGIcons name.
//
#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
	const char *name;
	int viewW, viewH;
	/// Margin on each side in 24ths of the box: MDI keeps 2 of its 24 units
	/// empty, Font Awesome fills its box, so it gets the same 2 to match.
	int pad;
	const char *d;
} TGIconPath;

/// NULL for a name that keeps its hand-drawn TGIcons version.
const TGIconPath *TGIconPathNamed(const char *name);
/// The whole table, for the test that parses every entry.
size_t TGIconPathCount(void);
const TGIconPath *TGIconPathAt(size_t index);

#ifdef __cplusplus
}
#endif
