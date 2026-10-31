//
// TGTheme+Drawing - the procedural skeuomorphism engine.
//
// Assembles the physical materials - satin bars, glossy buttons, linen
// patterns, recessed wells, metallic thumbs - out of gradient stops and
// hairlines at rasterization time, cached as images, with no GPU blur. It
// consumes the flat roles (TGTheme+Colours.m), the multi-stop sets
// (TGTheme+Gradients.m) and the depth materials (TGTheme+Effects.m).
// See docs/theme_system.md for the full map.
//
#import "TGTextDraw.h"
#import "TGThemeInternal.h"
#import "TGStyle.h"

#define rgb TGThemeRGB


// ── direct-blit texture tiles ────────────────────────────────────────────────
// A material tile is a per-pixel formula, and the four of them used to express
// that as 256 to 4096 separate CGContextFillRect calls on a scaled context.
// Each of those is a state read, a path, a clip test and a blend set up by
// CoreGraphics for one or four pixels, and a theme change ran all four: on a
// 4S that is a visible freeze at the moment the colours swap. The formula
// writes straight into a pixel buffer instead, and one CGImageCreate hands it
// over.
//
// 0xAARRGGBB in memory under kCGBitmapByteOrder32Little, alpha skipped: the
// tiles are opaque, so the top byte is never read.
typedef struct {
	uint32_t *pixels;
	int       w, h;      // in pixels, not points
	CGFloat   scale;
} TGTileCanvas;

static TGTileCanvas TGTileBegin(CGFloat width, CGFloat height, CGFloat scale) {
	TGTileCanvas canvas;
	canvas.scale  = scale > 0 ? scale : 1.0f;
	canvas.w      = (int)lrintf((float)(width  * canvas.scale));
	canvas.h      = (int)lrintf((float)(height * canvas.scale));
	if (canvas.w < 1) canvas.w = 1;
	if (canvas.h < 1) canvas.h = 1;
	canvas.pixels = (uint32_t *)malloc((size_t)canvas.w * canvas.h * sizeof(uint32_t));
	return canvas;
}

static inline uint32_t TGTilePack(CGFloat r, CGFloat g, CGFloat b) {
	uint32_t ri = (uint32_t)lrintf((float)(r * 255.0f));
	uint32_t gi = (uint32_t)lrintf((float)(g * 255.0f));
	uint32_t bi = (uint32_t)lrintf((float)(b * 255.0f));
	if (ri > 255) ri = 255;
	if (gi > 255) gi = 255;
	if (bi > 255) bi = 255;
	return 0xFF000000u | (ri << 16) | (gi << 8) | bi;
}

static void TGTileFillAll(TGTileCanvas *canvas, CGFloat r, CGFloat g, CGFloat b) {
	if (!canvas->pixels) return;
	uint32_t packed = TGTilePack(r, g, b);
	size_t count = (size_t)canvas->w * canvas->h;
	for (size_t i = 0; i < count; i++)
		canvas->pixels[i] = packed;
}

/// Source-over blend of one colour into the point-space rect (x, y, w, h) -
/// the same thing CGContextFillRect did over an opaque backing.
static void TGTileBlend(TGTileCanvas *canvas, CGFloat x, CGFloat y,
						CGFloat w, CGFloat h,
						CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
	if (!canvas->pixels || a <= 0.0f || w <= 0.0f || h <= 0.0f)
		return;
	int x0 = (int)lrintf((float)(x * canvas->scale));
	int y0 = (int)lrintf((float)(y * canvas->scale));
	int x1 = (int)lrintf((float)((x + w) * canvas->scale));
	int y1 = (int)lrintf((float)((y + h) * canvas->scale));
	if (x0 < 0) x0 = 0;
	if (y0 < 0) y0 = 0;
	if (x1 > canvas->w) x1 = canvas->w;
	if (y1 > canvas->h) y1 = canvas->h;

	if (a >= 1.0f){
		uint32_t packed = TGTilePack(r, g, b);
		for (int py = y0; py < y1; py++){
			uint32_t *row = canvas->pixels + (size_t)py * canvas->w;
			for (int px = x0; px < x1; px++)
				row[px] = packed;
		}
		return;
	}

	uint32_t sr = (uint32_t)lrintf((float)(r * 255.0f));
	uint32_t sg = (uint32_t)lrintf((float)(g * 255.0f));
	uint32_t sb = (uint32_t)lrintf((float)(b * 255.0f));
	uint32_t alpha = (uint32_t)lrintf((float)(a * 255.0f));
	uint32_t inverse = 255 - alpha;
	for (int py = y0; py < y1; py++){
		uint32_t *row = canvas->pixels + (size_t)py * canvas->w;
		for (int px = x0; px < x1; px++){
			uint32_t dst = row[px];
			uint32_t dr = (dst >> 16) & 0xFF;
			uint32_t dg = (dst >> 8)  & 0xFF;
			uint32_t db =  dst        & 0xFF;
			row[px] = 0xFF000000u
					| ((((sr * alpha + dr * inverse) / 255) & 0xFF) << 16)
					| ((((sg * alpha + dg * inverse) / 255) & 0xFF) << 8)
					|  (((sb * alpha + db * inverse) / 255) & 0xFF);
		}
	}
}

static void TGTileReleasePixels(void *info, const void *data, size_t size) {
	free((void *)data);
}

/// Hands the buffer to CoreGraphics, which frees it when the image goes.
static UIImage *TGTileEnd(TGTileCanvas *canvas) {
	if (!canvas->pixels)
		return nil;
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, canvas->pixels,
			(size_t)canvas->w * canvas->h * sizeof(uint32_t), TGTileReleasePixels);
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGImageRef cgImage = CGImageCreate(canvas->w, canvas->h, 8, 32,
			(size_t)canvas->w * sizeof(uint32_t), space,
			kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
			provider, NULL, false, kCGRenderingIntentDefault);
	CGColorSpaceRelease(space);
	CGDataProviderRelease(provider);
	canvas->pixels = NULL;
	if (!cgImage)
		return nil;

	UIImage *image = [UIImage imageWithCGImage:cgImage scale:canvas->scale
								   orientation:UIImageOrientationUp];
	CGImageRelease(cgImage);
	return image;
}


static const CGFloat kSkeuoCapInset    = TGMetricPadTiny;
static const CGFloat kSkeuoRimInset    = 0.75f;
static const CGFloat kSkeuoThumbPad    = TGMetricPadTiny;
static const CGFloat kSkeuoThumbLift   = 1.5f;
static const CGFloat kSwitchTextOnX    = 6.5f;
static const CGFloat kSwitchTextOffX   = 31.0f;
static const CGFloat kSwitchTextY      = 10.0f;
// drawAtPoint has no box; TGDrawText needs one, and the tag is one short word
// left-aligned, so the box only has to be wide enough not to clip it.
static const CGFloat kSwitchTagWidth   = 24.0f;
static const CGFloat kSwitchTagHeight  = 12.0f;

@implementation TGTheme (Skeuomorphism)

+ (UIImage *)skeuomorphicBarImageWithColor:(UIColor *)tint height:(CGFloat)height {
	CGFloat width = 8.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat r = 0, g = 0, b = 0, a = 1.0f;
	if (![tint getRed:&r green:&g blue:&b alpha:&a]) {
		r = 0.32f; g = 0.49f; b = 0.64f; a = 1.0f;
	}

	CGFloat topY = 0.0f;
	if (height >= 60.0f) {
		topY = TGMetricPadWide; // 20pt status bar area on attached bar
	}

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

	// 1. Status bar area (if attached)
	if (topY > 0.0f) {
		CGFloat statusComps[] = {
			r * 0.85f, g * 0.85f, b * 0.85f, a,
			MIN(1.0f, r * 1.42f), MIN(1.0f, g * 1.42f), MIN(1.0f, b * 1.42f), a
		};
		CGFloat statusLocs[] = { 0.0f, 1.0f };
		CGGradientRef statusGrad = CGGradientCreateWithColorComponents(cs, statusComps, statusLocs, 2);
		CGContextDrawLinearGradient(ctx, statusGrad, CGPointMake(0, 0), CGPointMake(0, topY), 0);
		CGGradientRelease(statusGrad);
	}

	// 2. Continuous smooth metallic gradient (authentic iOS 6 slate sheen - Picture 3)
	CGFloat barComps[] = {
		MIN(1.0f, r * 1.42f), MIN(1.0f, g * 1.42f), MIN(1.0f, b * 1.42f), a,
		MIN(1.0f, r * 1.08f), MIN(1.0f, g * 1.08f), MIN(1.0f, b * 1.08f), a,
		r * 0.75f, g * 0.75f, b * 0.75f, a
	};
	CGFloat barLocs[] = { 0.0f, 0.45f, 1.0f };
	CGGradientRef barGrad = CGGradientCreateWithColorComponents(cs, barComps, barLocs, 3);
	CGContextDrawLinearGradient(ctx, barGrad, CGPointMake(0, topY), CGPointMake(0, height), 0);
	CGGradientRelease(barGrad);

	CGColorSpaceRelease(cs);

	// Bottom dark hairline
	CGContextSetRGBStrokeColor(ctx, 0.11f, 0.11f, 0.11f, 0.95f);
	CGContextMoveToPoint(ctx, 0, height - 0.5f);
	CGContextAddLineToPoint(ctx, width, height - 0.5f);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(0, kSkeuoCapInset, 0, kSkeuoCapInset)];
}

+ (UIImage *)skeuomorphicButtonImageWithColor:(UIColor *)tint
                                       height:(CGFloat)height
                                  highlighted:(BOOL)highlighted
                                 cornerRadius:(CGFloat)radius {
	CGFloat width = radius * 2.0f + 12.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGFloat r = 0, g = 0, b = 0, a = 1.0f;
	if (![tint getRed:&r green:&g blue:&b alpha:&a]) {
		r = 0.5f; g = 0.5f; b = 0.5f; a = 1.0f;
	}

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.5f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
	[path addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	if (!highlighted) {
		// Normal glossy 2-stage gradient
		CGFloat comps[] = {
			MIN(r * 1.25f, 1.0f), MIN(g * 1.25f, 1.0f), MIN(b * 1.25f, 1.0f), a,
			r, g, b, a,
			r * 0.94f, g * 0.94f, b * 0.94f, a,
			r * 0.82f, g * 0.82f, b * 0.82f, a
		};
		CGFloat locs[] = { 0.0f, 0.50f, 0.51f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 4);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		// Top inner specular rim
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.38f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, kSkeuoRimInset, kSkeuoRimInset);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:MAX(radius - kSkeuoRimInset, 0.0f)];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);
	} else {
		// Highlighted / pressed recessed gradient
		CGFloat comps[] = {
			r * 0.70f, g * 0.70f, b * 0.70f, a,
			r * 0.85f, g * 0.85f, b * 0.85f, a,
			r * 0.92f, g * 0.92f, b * 0.92f, a
		};
		CGFloat locs[] = { 0.0f, 0.60f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		// Inset shadow at top
		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.35f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, kSkeuoRimInset, kSkeuoRimInset);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:MAX(radius - kSkeuoRimInset, 0.0f)];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);
	}
	CGColorSpaceRelease(cs);

	// Outer border stroke
	CGContextSetRGBStrokeColor(ctx, r * 0.65f, g * 0.65f, b * 0.65f, 0.95f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (UIImage *)buttonImageForStyle:(TGButtonStyle)style
                     highlighted:(BOOL)highlighted
                          height:(CGFloat)height {
	UIColor *tint = nil;
	switch (style) {
		case TGButtonStyleAction:
			tint = rgb(0x42, 0x82, 0xB8);
			break;
		case TGButtonStyleSilver:
			tint = rgb(0xD0, 0xD4, 0xDA);
			break;
		case TGButtonStyleDestructive:
			tint = rgb(0xC8, 0x2E, 0x2E);
			break;
		case TGButtonStyleSuccess:
			tint = rgb(0x3B, 0xA2, 0x48);
			break;
		case TGButtonStyleGhost:
			tint = [UIColor colorWithWhite:0.0f alpha:0.08f];
			break;
	}
	return [self skeuomorphicButtonImageWithColor:tint
                                          height:height
                                     highlighted:highlighted
                                    cornerRadius:TGMetricCornerControl];
}

+ (UIImage *)skeuomorphicPinstripePattern {
	CGFloat width = 2.0f, height = 2.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	TGTheme *theme = [TGTheme shared];
	// Classic iOS 6 fine woven pinstripes
	CGContextSetRGBFillColor(ctx, 0.85f, 0.86f, 0.89f, 1.0f);
	CGContextFillRect(ctx, CGRectMake(0, 0, 1.0f, height));
	CGContextSetRGBFillColor(ctx, 0.77f, 0.80f, 0.83f, 1.0f);
	CGContextFillRect(ctx, CGRectMake(1.0f, 0, 1.0f, height));


	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicPaperGrainPattern {
	CGFloat width = 16.0f, height = 16.0f;
	TGTileCanvas canvas = TGTileBegin(width, height, [UIScreen mainScreen].scale);

	TGTileFillAll(&canvas, 0.92f, 0.93f, 0.94f);

	// Fine deterministic micro-grain
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			int h = ((x * 47 + y * 31 + (x ^ y)) % 17);
			if (h == 0) {
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.85f, 0.87f, 0.89f, 0.45f);
			} else if (h == 1) {
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.98f, 0.98f, 1.00f, 0.35f);
			}
		}
	}

	return TGTileEnd(&canvas);
}

+ (UIImage *)skeuomorphicLinenPattern {
	CGFloat width = 16.0f, height = 16.0f;
	TGTileCanvas canvas = TGTileBegin(width, height, [UIScreen mainScreen].scale);

	// Base tone: authentic Apple charcoal linen or slate
	TGTileFillAll(&canvas, 0.22f, 0.23f, 0.26f);

	// Cross-hatch threads with highlights and depth shadows
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			BOOL vertRib = (x % 4 == 0);
			BOOL vertShadow = (x % 4 == 1);
			BOOL horizRib = (y % 4 == 0);
			BOOL horizShadow = (y % 4 == 1);
			int noise = ((x * 37 + y * 19 + ((x * 7) ^ (y * 11))) % 11);

			if (vertRib && horizRib) {
				// Interlaced thread crest: subtle highlight
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 0.12f);
			} else if (vertShadow || horizShadow) {
				// Thread recess: depth shadow
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.22f);
			} else if (noise == 0) {
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 0.06f);
			} else if (noise == 1) {
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.10f);
			}
		}
	}

	return TGTileEnd(&canvas);
}

+ (UIImage *)skeuomorphicParchmentPattern {
	CGFloat width = 32.0f, height = 32.0f;
	TGTileCanvas canvas = TGTileBegin(width, height, [UIScreen mainScreen].scale);

	// Classic Notes app warm cream parchment
	TGTileFillAll(&canvas, 0.96f, 0.94f, 0.88f);

	// Laid paper horizontal watermark line (spaced every 16pt)
	for (int y = 0; y < (int)height; y += 16) {
		TGTileBlend(&canvas, 0, y, width, 1.0f, 0.88f, 0.84f, 0.74f, 0.35f);
	}

	// Natural organic paper fibers and warm flecks
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			int h = ((x * 53 + y * 29 + (x ^ (y * 3))) % 19);
			if (h == 0) {
				// Fiber fleck
				TGTileBlend(&canvas, x, y, 1.5f, 1.0f, 0.85f, 0.79f, 0.65f, 0.40f);
			} else if (h == 1) {
				// Fine light tooth
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.99f, 0.98f, 0.94f, 0.30f);
			}
		}
	}

	return TGTileEnd(&canvas);
}

+ (UIImage *)skeuomorphicFeltPattern {
	CGFloat width = 24.0f, height = 24.0f;
	TGTileCanvas canvas = TGTileBegin(width, height, [UIScreen mainScreen].scale);

	// Authentic Apple Game Center billiard felt
	TGTileFillAll(&canvas, 0.11f, 0.31f, 0.16f);

	// Soft stippled wool fibers
	for (int y = 0; y < (int)height; y++) {
		for (int x = 0; x < (int)width; x++) {
			int h = ((x * 41 + y * 23 + (x ^ (y * 5))) % 13);
			if (h == 0) {
				// Light fiber highlight
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.17f, 0.44f, 0.23f, 0.45f);
			} else if (h == 1) {
				// Shadow fiber depth
				TGTileBlend(&canvas, x, y, 1.0f, 1.0f, 0.06f, 0.18f, 0.09f, 0.50f);
			}
		}
	}

	return TGTileEnd(&canvas);
}

+ (UIImage *)textureImageForType:(TGWallpaperType)type {
	UIImage *tile = nil;
	switch (type) {
		case TGWallpaperTypePaperGrain:
			tile = [self skeuomorphicPaperGrainPattern];
			break;
		case TGWallpaperTypePinstripes:
			tile = [self skeuomorphicPinstripePattern];
			break;
		case TGWallpaperTypeLinen:
			tile = [self skeuomorphicLinenPattern];
			break;
		case TGWallpaperTypeParchment:
			tile = [self skeuomorphicParchmentPattern];
			break;
		case TGWallpaperTypeFelt:
			tile = [self skeuomorphicFeltPattern];
			break;
		default:
			return nil;
	}
	if (!tile) return nil;

	CGSize canvasSize = [UIScreen mainScreen].bounds.size;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(canvasSize, YES, scale);
	[[UIColor colorWithPatternImage:tile] setFill];
	UIRectFill(CGRectMake(0.0f, 0.0f, canvasSize.width, canvasSize.height));
	UIImage *canvas = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return canvas;
}

+ (UIImage *)skeuomorphicWellImageWithHeight:(CGFloat)height cornerRadius:(CGFloat)radius {
	CGFloat width = radius * 2.0f + 16.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.0f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

	// Background fill
	CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);

	CGContextAddPath(ctx, path.CGPath);
	CGContextFillPath(ctx);

	// Inner shadow at top
	CGContextSaveGState(ctx);
	[path addClip];
	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.20f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);
	CGContextRestoreGState(ctx);

	// Outer border stroke
	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.25f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (UIImage *)skeuomorphicSliderTrackImageFilled:(BOOL)filled {
	CGFloat width = 18.0f;
	CGFloat height = TGMetricSliderTrackH;
	CGFloat radius = TGHalf(height);
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.0f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
	[path addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	if (filled) {
		CGFloat comps[] = {
			0.14f, 0.45f, 0.88f, 1.0f,
			0.09f, 0.32f, 0.68f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.45f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, radius, 1.0f);
		CGContextAddLineToPoint(ctx, width - radius, 1.0f);
		CGContextStrokePath(ctx);
	} else {
		CGFloat comps[] = {
			0.70f, 0.72f, 0.75f, 1.0f,
			0.88f, 0.90f, 0.92f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.35f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGContextMoveToPoint(ctx, radius, 1.0f);
		CGContextAddLineToPoint(ctx, width - radius, 1.0f);
		CGContextStrokePath(ctx);
	}
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.30f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (UIImage *)skeuomorphicSliderThumbWithRadius:(CGFloat)radius {
	CGFloat side = radius * 2.0f + 4.0f;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect circle = CGRectMake(kSkeuoThumbPad, kSkeuoThumbLift, TGDoubled(radius), TGDoubled(radius));
	UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:circle];
	[p addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGFloat comps[] = {
		0.98f, 0.98f, 0.99f, 1.0f,
		0.86f, 0.88f, 0.90f, 1.0f,
		0.74f, 0.76f, 0.78f, 1.0f
	};
	CGFloat locs[] = { 0.0f, 0.55f, 1.0f };
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, kSkeuoThumbLift), CGPointMake(0, kSkeuoThumbLift + radius * 2.0f), 0);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	// Inner rim
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.70f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circle, kSkeuoRimInset, kSkeuoRimInset)].CGPath);
	CGContextStrokePath(ctx);

	// Outer border
	CGContextSetRGBStrokeColor(ctx, 0.50f, 0.52f, 0.55f, 0.95f);
	CGContextAddPath(ctx, p.CGPath);
	CGContextStrokePath(ctx);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)skeuomorphicSwitchTrackImageOn:(BOOL)isOn {
	CGFloat width = TGMetricSwitchW;
	CGFloat height = TGMetricSwitchH;
	CGFloat radius = TGHalf(height);
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect rect = CGRectMake(0.5f, 0.5f, width - 1.0f, height - 1.0f);
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
	[path addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	if (isOn) {
		CGFloat comps[] = {
			0.14f, 0.45f, 0.88f, 1.0f,
			0.10f, 0.36f, 0.74f, 1.0f,
			0.08f, 0.28f, 0.62f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 0.55f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.40f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, 1.0f, 1.0f);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:radius - 1.0f];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);

		NSShadow *shadow = [[NSShadow alloc] init];
		shadow.shadowOffset = CGSizeMake(0, -1.0f);
		shadow.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.35f];
		TGDrawText(@"ON", CGRectMake(kSwitchTextOnX, kSwitchTextY,
						kSwitchTagWidth, kSwitchTagHeight), TGFontSwitchTag(),
				[UIColor whiteColor], NSTextAlignmentLeft, shadow);
	} else {
		CGFloat comps[] = {
			0.82f, 0.84f, 0.87f, 1.0f,
			0.90f, 0.92f, 0.94f, 1.0f,
			0.95f, 0.96f, 0.97f, 1.0f
		};
		CGFloat locs[] = { 0.0f, 0.40f, 1.0f };
		CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, height), 0);
		CGGradientRelease(grad);

		CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.30f);
		CGContextSetLineWidth(ctx, 1.0f);
		CGRect innerRect = CGRectInset(rect, 1.0f, 1.0f);
		UIBezierPath *innerPath = [UIBezierPath bezierPathWithRoundedRect:innerRect cornerRadius:radius - 1.0f];
		CGContextAddPath(ctx, innerPath.CGPath);
		CGContextStrokePath(ctx);

		NSShadow *shadow = [[NSShadow alloc] init];
		shadow.shadowOffset = CGSizeMake(0, 1.0f);
		shadow.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.75f];
		TGDrawText(@"OFF", CGRectMake(kSwitchTextOffX, kSwitchTextY,
						kSwitchTagWidth, kSwitchTagHeight), TGFontSwitchTag(),
				[UIColor colorWithWhite:0.48f alpha:1.0f], NSTextAlignmentLeft, shadow);
	}
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.35f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, path.CGPath);
	CGContextStrokePath(ctx);

	UIImage *trackImg = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return trackImg;
}

+ (UIImage *)skeuomorphicSwitchThumbImage {
	CGFloat side = TGMetricSwitchThumbD;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGRect circle = CGRectMake(0.5f, 0.5f, side - 1.0f, side - 1.0f);
	UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:circle];
	[p addClip];

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGFloat comps[] = {
		0.99f, 0.99f, 1.00f, 1.0f,
		0.92f, 0.93f, 0.95f, 1.0f,
		0.80f, 0.82f, 0.85f, 1.0f
	};
	CGFloat locs[] = { 0.0f, 0.60f, 1.0f };
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
	CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, side), 0);
	CGGradientRelease(grad);
	CGColorSpaceRelease(cs);

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.80f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circle, 1.0f, 1.0f)].CGPath);
	CGContextStrokePath(ctx);

	CGContextSetLineWidth(ctx, 1.0f);
	CGFloat midX = TGHalf(side);
	CGFloat ridgeH = 10.0f;
	CGFloat ridgeY = TGCenteredOrigin(side, ridgeH);
	CGFloat offsets[] = { -3.0f, 0.0f, 3.0f };
	for (int i = 0; i < 3; i++) {
		CGFloat rx = midX + offsets[i];
		CGContextSetRGBStrokeColor(ctx, 0.55f, 0.58f, 0.62f, 0.80f);
		CGContextMoveToPoint(ctx, rx, ridgeY);
		CGContextAddLineToPoint(ctx, rx, ridgeY + ridgeH);
		CGContextStrokePath(ctx);
		CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.90f);
		CGContextMoveToPoint(ctx, rx + 0.5f, ridgeY);
		CGContextAddLineToPoint(ctx, rx + 0.5f, ridgeY + ridgeH);
		CGContextStrokePath(ctx);
	}

	CGContextSetRGBStrokeColor(ctx, 0.45f, 0.48f, 0.52f, 0.95f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextAddPath(ctx, p.CGPath);
	CGContextStrokePath(ctx);

	UIImage *thumbImg = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return thumbImg;
}

+ (void)applySkeuomorphicStyleToButton:(UIButton *)button style:(TGButtonStyle)style {
	if (!button)
		return;
	CGFloat h = button.bounds.size.height > 0 ? button.bounds.size.height : TGMetricButtonHeight;
	UIImage *norm = [self buttonImageForStyle:style highlighted:NO height:h];
	UIImage *high = [self buttonImageForStyle:style highlighted:YES height:h];
	[button setBackgroundImage:norm forState:UIControlStateNormal];
	[button setBackgroundImage:high forState:UIControlStateHighlighted];
	button.titleLabel.font = TGFontRowStrong();

	if (style == TGButtonStyleSilver || style == TGButtonStyleGhost) {
		[button setTitleColor:TG_TEXT_PRIMARY forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.80f] forState:UIControlStateNormal];
		button.titleLabel.shadowOffset = CGSizeMake(0, 1.0f);
	} else {
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.45f] forState:UIControlStateNormal];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1.0f);
	}
}

+ (void)applySkeuomorphicInputStyle:(UITextField *)field {
	if (!field)
		return;
	CGFloat h = field.bounds.size.height > 0 ? field.bounds.size.height : TGMetricRow;
	field.background = [self skeuomorphicWellImageWithHeight:h cornerRadius:TGMetricCornerControl];
	field.font = TGFontInput();
	field.textColor = [[TGTheme shared] primaryTextColour];
}

+ (UIImage *)skeuomorphicInputBarImageWithHeight:(CGFloat)height {
	CGFloat width = TGMetricPadSmall;
	CGFloat scale = [UIScreen mainScreen].scale;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), YES, scale);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	TGTheme *theme = [TGTheme shared];
	// Classic iOS 6 brushed aluminum satin gradient
	CGFloat comps[] = {
		0.92f, 0.93f, 0.95f, 1.0f,
		0.82f, 0.84f, 0.86f, 1.0f,
		0.72f, 0.74f, 0.77f, 1.0f
	};
	CGFloat locs[] = { 0.0f, 0.5f, 1.0f };
	CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
	CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(0, height), 0);
	CGGradientRelease(grad);

	// Top 1px crisp specular highlight line
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.90f);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextMoveToPoint(ctx, 0, 0.5f);
	CGContextAddLineToPoint(ctx, width, 0.5f);
	CGContextStrokePath(ctx);

	CGColorSpaceRelease(cs);

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	CGFloat cap = TGMetricPadTiny;
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap)];
}

/// The system's rounded grouped cell, coloured by the theme: UIKit draws the
/// card, its corners and its selection. The drawn card images it replaced
/// imitated exactly that, and only iOS 6's version of it.
- (void)styleGroupedCell:(UITableViewCell *)cell forRow:(NSInteger)row totalRows:(NSInteger)total {
	if (!cell) return;
	// The cell's own background view is left alone: on iOS 6 it is the
	// rounded card, and taking it away left bare labels on the table.
	[self styleCell:cell];
}


@end

// vim:ft=objc
