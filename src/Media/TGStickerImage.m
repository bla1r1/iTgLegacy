//
// TGStickerImage.m - see the header.
//
#import "TGStickerImage.h"
#import "TGStyle.h"
#import "WebP.framework/Headers/encode.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

// The bundled libwebp is old enough that WebPFree is not in its headers or
// its export table, while a current one has it. Resolving it at runtime lets
// one object link against both: WebPFree when the running library exports it,
// plain free when it does not (the old encoder allocates through malloc).
typedef void (*TGWebPFreeFn)(void *);

static TGWebPFreeFn TGWebPFreeLookup(void) {
	static TGWebPFreeFn fn;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ fn = (TGWebPFreeFn)dlsym(RTLD_DEFAULT, "WebPFree"); });
	return fn;
}

static void TGWebPFreeBuffer(void *ptr) {
	TGWebPFreeFn fn = TGWebPFreeLookup();
	if (fn)
		fn(ptr);
	else
		free(ptr);
}

const size_t TGStickerImageSide = 512;

CGImageRef TGStickerImageCreatePadded(CGImageRef source, size_t side) {
	if (!source || side == 0)
		return NULL;

	size_t width = CGImageGetWidth(source);
	size_t height = CGImageGetHeight(source);
	if (!width || !height)
		return NULL;

	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	size_t stride = side * 4;
	uint8_t *pixels = calloc(side * side, 4);
	CGContextRef ctx = pixels ? CGBitmapContextCreate(pixels, side, side, 8,
			stride, space,
			kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast) : NULL;
	CGColorSpaceRelease(space);
	if (!ctx){
		free(pixels);
		return NULL;
	}

	// The canvas starts transparent; only the fitted picture is drawn.
	CGContextClearRect(ctx, CGRectMake(0, 0, (CGFloat)side, (CGFloat)side));
	CGFloat scale = MIN((CGFloat)side / (CGFloat)width,
						(CGFloat)side / (CGFloat)height);
	CGFloat drawWidth = (CGFloat)width * scale;
	CGFloat drawHeight = (CGFloat)height * scale;
	CGRect fitted = CGRectMake(TGHalf((CGFloat)side - drawWidth),
							   TGHalf((CGFloat)side - drawHeight),
							   drawWidth, drawHeight);
	CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
	CGContextDrawImage(ctx, fitted, source);

	CGImageRef out = CGBitmapContextCreateImage(ctx);
	CGContextRelease(ctx);
	free(pixels);
	return out;
}

NSData *TGStickerImageWebPData(CGImageRef source, size_t side, float quality) {
	CGImageRef padded = TGStickerImageCreatePadded(source, side);
	if (!padded)
		return nil;

	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	size_t stride = side * 4;
	uint8_t *rgba = calloc(side * side, 4);
	CGContextRef ctx = rgba ? CGBitmapContextCreate(rgba, side, side, 8,
			stride, space,
			kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast) : NULL;
	CGColorSpaceRelease(space);
	if (!ctx){
		free(rgba);
		CGImageRelease(padded);
		return nil;
	}
	// Draw the already-padded image 1:1 so the encoder sees its pixels.
	CGContextSetBlendMode(ctx, kCGBlendModeCopy);
	CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)side, (CGFloat)side), padded);
	CGContextRelease(ctx);
	CGImageRelease(padded);

	// CGBitmapContext stores premultiplied RGBA; WebP wants straight alpha.
	for (size_t i = 0; i < side * side; i++){
		uint8_t *pixel = rgba + i * 4;
		unsigned alpha = pixel[3];
		if (alpha > 0 && alpha < 255){
			pixel[0] = (uint8_t)MIN(255, (pixel[0] * 255 + alpha / 2) / alpha);
			pixel[1] = (uint8_t)MIN(255, (pixel[1] * 255 + alpha / 2) / alpha);
			pixel[2] = (uint8_t)MIN(255, (pixel[2] * 255 + alpha / 2) / alpha);
		}
	}

	uint8_t *encoded = NULL;
	size_t length = WebPEncodeRGBA(rgba, (int)side, (int)side, (int)stride,
			quality, &encoded);
	free(rgba);
	if (!encoded || length == 0){
		if (encoded)
			TGWebPFreeBuffer(encoded);
		return nil;
	}
	NSData *data = [NSData dataWithBytes:encoded length:length];
	TGWebPFreeBuffer(encoded);
	return data;
}
