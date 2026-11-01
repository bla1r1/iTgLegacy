//
// UIImage+WebP - decode WebP images with libwebp.
//
#import "UIImage+WebP.h"
#import "TGStickerImage.h"
#import "TGStyle.h"
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

/// Drawing through UIKit first, rather than handing `CGImage` straight to
/// the encoder, applies the EXIF orientation a camera roll picture carries:
/// `CGImage` has no such field, and a sideways sticker is the bug that
/// follows from ignoring it. The bitmap is already the square Telegram
/// wants, so the encoder only has to compress it.
+ (NSData *)webPDataFromImage:(UIImage *)image quality:(CGFloat)quality {
	if (!image)
		return nil;
	CGSize size = image.size;
	if (size.width <= 0 || size.height <= 0)
		return nil;

	CGFloat side = TGMetricStickerSide;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 1.0f);
	if (!UIGraphicsGetCurrentContext())
		return nil;
	CGFloat scale = MIN(side / size.width, side / size.height);
	CGFloat drawWidth = size.width * scale;
	CGFloat drawHeight = size.height * scale;
	[image drawInRect:CGRectMake((side - drawWidth) / 2.0f,
								 (side - drawHeight) / 2.0f,
								 drawWidth, drawHeight)];
	UIImage *padded = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (!padded)
		return nil;
	return TGStickerImageWebPData(padded.CGImage, (size_t)side, (float)quality);
}

@end

// vim:ft=objc
