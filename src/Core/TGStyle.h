//
// TGStyle.h - Unified Design Tokens umbrella header
//
// Refactored from monolithic 833-line file into domain categories:
// - TGStyle+Typography.h: Type scale, line heights, font roles
// - TGStyle+Metrics.h: Spacing scale, component dimensions, corner radii
// - TGStyle+Decorations.h: Shadows, borders, layer helpers, math inlines
// - TGStyle+Palette.h: Non-theme palette roles and tile hues
//
#import <UIKit/UIKit.h>

#import "TGStyle+Typography.h"
#import "TGStyle+Palette.h"
#import "TGStyle+Decorations.h"
#import "TGStyle+Metrics.h"
