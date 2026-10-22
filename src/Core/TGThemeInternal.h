#import "TGTheme.h"

static inline UIColor *TGThemeRGB(int r, int g, int b) {
	return [UIColor colorWithRed:r/255.0f green:g/255.0f blue:b/255.0f alpha:1.0f];
}

@interface TGTheme ()
- (UIColor *)importedColour:(NSString *)key;
- (BOOL)hasCustomPalette;
@end
