// TGStickerImageTests.m - the bytes Telegram receives for a static sticker.
//
// A PNG declared as WebP is refused by TDLib's server check, so the encoder
// is not a convenience: it is the difference between a working upload and a
// silent failure. These tests hold the two hard facts - it is really WebP,
// and it is really 512x512 - without a device.
#import "TGTestRunner.h"
#import "TGStickerImage.h"
#import "WebP.framework/Headers/decode.h"

#include <string.h>

@interface TGStickerImageTests : XCTestCase @end

/// A red CGImage of any size. CGBitmapContextCreateImage copies or shares
/// the buffer, so the buffer is deliberately left for the process to reclaim
/// rather than freed under a still-living image in a test.
static CGImageRef TGStickerTestImage(size_t width, size_t height) {
	size_t stride = width * 4;
	uint8_t *pixels = (uint8_t *)calloc(width * height, 4);
	if (!pixels)
		return NULL;
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(pixels, width, height, 8, stride,
			space, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(space);
	if (!ctx){
		free(pixels);
		return NULL;
	}
	CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
	CGContextFillRect(ctx, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height));
	CGImageRef image = CGBitmapContextCreateImage(ctx);
	CGContextRelease(ctx);
	return image;
}

@implementation TGStickerImageTests

- (void)testStickerSideIsTheTelegramSquare {
	XCTAssertEqual(TGStickerImageSide, (size_t)512);
}

- (void)testPaddedImageIsExactlyTheSquareEvenWhenTheSourceIsNot {
	CGImageRef source = TGStickerTestImage(300, 120);
	XCTAssertTrue(source != NULL);
	CGImageRef padded = TGStickerImageCreatePadded(source, TGStickerImageSide);
	CGImageRelease(source);
	XCTAssertTrue(padded != NULL);
	if (!padded)
		return;
	XCTAssertEqual(CGImageGetWidth(padded), (size_t)512);
	XCTAssertEqual(CGImageGetHeight(padded), (size_t)512);
	CGImageRelease(padded);
}

- (void)testPaddedImageHasTransparentBars {
	CGImageRef source = TGStickerTestImage(256, 64);
	CGImageRef padded = TGStickerImageCreatePadded(source, TGStickerImageSide);
	CGImageRelease(source);
	XCTAssertTrue(padded != NULL);
	if (!padded)
		return;

	uint8_t *pixels = (uint8_t *)calloc(512 * 512, 4);
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(pixels, 512, 512, 8, 512 * 4,
			space, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(space);
	CGContextDrawImage(ctx, CGRectMake(0, 0, 512, 512), padded);
	CGImageRelease(padded);
	// The top-left pixel is outside the 256x64 picture, so it is padding.
	XCTAssertEqual(pixels[3], (uint8_t)0);
	CGContextRelease(ctx);
	free(pixels);
}

- (void)testEncodedBytesStartWithRiffWebpAndDecodeToTheSquare {
	CGImageRef source = TGStickerTestImage(640, 480);
	NSData *data = TGStickerImageWebPData(source, TGStickerImageSide, 0.9f);
	CGImageRelease(source);
	XCTAssertNotNil(data);
	XCTAssertTrue(data.length > 12);
	if (data.length < 12)
		return;

	const uint8_t *bytes = (const uint8_t *)data.bytes;
	XCTAssertEqual(memcmp(bytes, "RIFF", 4), 0);
	XCTAssertEqual(memcmp(bytes + 8, "WEBP", 4), 0);

	int width = 0, height = 0;
	XCTAssertTrue(WebPGetInfo(bytes, data.length, &width, &height));
	XCTAssertEqual(width, 512);
	XCTAssertEqual(height, 512);
}

- (void)testNoImageMeansNoBytes {
	XCTAssertNil(TGStickerImageWebPData(NULL, TGStickerImageSide, 0.9f));
	XCTAssertTrue(TGStickerImageCreatePadded(NULL, TGStickerImageSide) == NULL);
}

@end
