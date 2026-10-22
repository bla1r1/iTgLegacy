//
// UIImage+WebP - decode WebP with libwebp.
//
// Telegram stickers are WebP and iOS 7 has no idea what that is. The file that
// used to sit here contained only the @interface - a copy of the header, no
// implementation - so every call was an unrecognized selector. WebP.framework
// ships the libwebp C API, so the category is written against that.
//
#import "UIImage+WebP.h"
#import "WebP.framework/Headers/decode.h"

/// CGDataProvider owns the buffer once created and frees it through this.
static void tgFreePixels(void *info, const void *data, size_t size) {
	free((void *)data);
}

@implementation UIImage (WebP)

+ (UIImage *)convertFromWebP:(NSString *)filePath
			  compressedData:(__autoreleasing NSData **)compressedData
					   error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (!data.length)
		return nil;
	if (compressedData)
		*compressedData = data;

	int width = 0, height = 0;
	if (!WebPGetInfo(data.bytes, data.length, &width, &height) ||
		width <= 0 || height <= 0)
		return nil;

	// RGBA, 4 bytes per pixel, straight into a buffer CGImage can own.
	size_t stride = (size_t)width * 4;
	size_t size = stride * (size_t)height;
	uint8_t *pixels = malloc(size);
	if (!pixels)
		return nil;

	if (!WebPDecodeRGBAInto(data.bytes, data.length, pixels, size, (int)stride)){
		free(pixels);
		return nil;
	}

	CGDataProviderRef provider =
		CGDataProviderCreateWithData(NULL, pixels, size, tgFreePixels);
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGImageRef cgImage = CGImageCreate(width, height, 8, 32, stride, space,
			kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast,
			provider, NULL, NO, kCGRenderingIntentDefault);

	UIImage *image = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;

	if (cgImage) CGImageRelease(cgImage);
	CGColorSpaceRelease(space);
	CGDataProviderRelease(provider);

	return image;
}

+ (UIImage *)convertFromGZippedData:(NSString *)filePath size:(CGSize)size {
	// .tgs stickers are gzipped Lottie JSON - vector animation. Rendering that
	// needs a Lottie player, which this app does not have, so the caller falls
	// back to the sticker's emoji.
	return nil;
}

@end

// vim:ft=objc
