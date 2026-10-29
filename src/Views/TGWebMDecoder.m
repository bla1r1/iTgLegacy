//
// TGWebMDecoder.m - Lightweight WebM VP9 video sticker decoder for iOS.
//
#import "TGWebMDecoder.h"
#include "nestegg/nestegg.h"
#define VPX_CODEC_DISABLE_COMPAT 1
#include "vpx/vpx_decoder.h"
#include "vpx/vp8dx.h"
#include <stdio.h>
#include <stdlib.h>

#pragma mark - NestEgg File I/O Callbacks

static int webm_io_read(void *buffer, size_t length, void *userdata) {
	FILE *fp = (FILE *)userdata;
	size_t r = fread(buffer, 1, length, fp);
	if (r == 0 && ferror(fp))
		return -1;
	return (int)r;
}

static int webm_io_seek(int64_t offset, int whence, void *userdata) {
	FILE *fp = (FILE *)userdata;
	return fseek(fp, (long)offset, whence);
}

static int64_t webm_io_tell(void *userdata) {
	FILE *fp = (FILE *)userdata;
	return ftell(fp);
}

#pragma mark - YUV420 to RGBA Converter

static void TGWebMReleaseDataCallback(void *info, const void *data, size_t size) {
	free((void *)data);
}

static CGImageRef CreateCGImageFromVpxImages(vpx_image_t *img, vpx_image_t *alphaImg) {
	if (!img)
		return NULL;

	unsigned int width = img->d_w;
	unsigned int height = img->d_h;
	if (width == 0 || height == 0)
		return NULL;

	size_t rgbaStride = width * 4;
	size_t dataLen = rgbaStride * height;
	uint8_t *rgba = (uint8_t *)malloc(dataLen);
	if (!rgba)
		return NULL;

	const uint8_t *yPlane = img->planes[VPX_PLANE_Y];
	const uint8_t *uPlane = img->planes[VPX_PLANE_U];
	const uint8_t *vPlane = img->planes[VPX_PLANE_V];
	int yStride = img->stride[VPX_PLANE_Y];
	int uStride = img->stride[VPX_PLANE_U];
	int vStride = img->stride[VPX_PLANE_V];

	const uint8_t *aPlane = (alphaImg ? alphaImg->planes[VPX_PLANE_Y] : NULL);
	int aStride = (alphaImg ? alphaImg->stride[VPX_PLANE_Y] : 0);

	for (unsigned int y = 0; y < height; y++) {
		const uint8_t *py = yPlane + y * yStride;
		const uint8_t *pu = uPlane + (y >> 1) * uStride;
		const uint8_t *pv = vPlane + (y >> 1) * vStride;
		const uint8_t *pa = aPlane ? (aPlane + y * aStride) : NULL;
		uint8_t *dst = rgba + y * rgbaStride;

		for (unsigned int x = 0; x < width; x++) {
			int yVal = py[x];
			int uVal = pu[x >> 1];
			int vVal = pv[x >> 1];
			int aVal = pa ? pa[x] : 255;

			int c = yVal - 16;
			if (c < 0) c = 0;
			int d = uVal - 128;
			int e = vVal - 128;
			int r = (298 * c           + 409 * e + 128) >> 8;
			int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
			int b = (298 * c + 516 * d           + 128) >> 8;

			if (r < 0) r = 0; else if (r > 255) r = 255;
			if (g < 0) g = 0; else if (g > 255) g = 255;
			if (b < 0) b = 0; else if (b > 255) b = 255;

			// Premultiply alpha for Quartz
			if (aVal < 255) {
				r = (r * aVal) / 255;
				g = (g * aVal) / 255;
				b = (b * aVal) / 255;
			}

			dst[0] = (uint8_t)r;
			dst[1] = (uint8_t)g;
			dst[2] = (uint8_t)b;
			dst[3] = (uint8_t)aVal;
			dst += 4;
		}
	}

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, rgba, dataLen, TGWebMReleaseDataCallback);
	CGImageRef cgImage = CGImageCreate(
		width, height, 8, 32, rgbaStride,
		colorSpace,
		kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
		provider, NULL, NO, kCGRenderingIntentDefault);

	CGDataProviderRelease(provider);
	CGColorSpaceRelease(colorSpace);
	return cgImage;
}

#pragma mark - Decoder Implementation

@implementation TGWebMDecoder

+ (NSArray *)decodeFramesFromFile:(NSString *)path
                              fps:(double *)outFps
                         duration:(NSTimeInterval *)outDuration {
	if (!path.length)
		return nil;

	FILE *fp = fopen(path.UTF8String, "rb");
	if (!fp) {
		NSLog(@"TGWebMDecoder: failed to open %@", path);
		return nil;
	}

	nestegg_io io = { webm_io_read, webm_io_seek, webm_io_tell, fp };
	nestegg *demux = NULL;
	if (nestegg_init(&demux, io, NULL, -1) != 0) {
		fclose(fp);
		NSLog(@"TGWebMDecoder: nestegg_init failed for %@", path);
		return nil;
	}

	unsigned int trackCount = 0;
	nestegg_track_count(demux, &trackCount);
	int videoTrack = -1;
	for (unsigned int i = 0; i < trackCount; i++) {
		if (nestegg_track_type(demux, i) == NESTEGG_TRACK_VIDEO) {
			videoTrack = (int)i;
			break;
		}
	}

	if (videoTrack < 0) {
		nestegg_destroy(demux);
		fclose(fp);
		NSLog(@"TGWebMDecoder: no video track found in %@", path);
		return nil;
	}

	uint64_t durNs = 0;
	nestegg_duration(demux, &durNs);
	NSTimeInterval durSec = (durNs > 0) ? ((double)durNs / 1000000000.0) : 2.0;

	vpx_codec_ctx_t codec;
	vpx_codec_dec_cfg_t cfg = {0};
	cfg.threads = 1;
	vpx_codec_iface_t *iface = vpx_codec_vp9_dx();
	if (vpx_codec_dec_init(&codec, iface, &cfg, 0) != VPX_CODEC_OK) {
		nestegg_destroy(demux);
		fclose(fp);
		NSLog(@"TGWebMDecoder: vpx_codec_dec_init failed: %s", vpx_codec_error(&codec));
		return nil;
	}

	vpx_codec_ctx_t alphaCodec;
	BOOL hasAlphaCodec = NO;

	NSMutableArray *frames = [NSMutableArray array];
	nestegg_packet *pkt = NULL;

	while (nestegg_read_packet(demux, &pkt) > 0) {
		unsigned int track = 0;
		nestegg_packet_track(pkt, &track);
		if ((int)track == videoTrack) {
			unsigned int count = 0;
			nestegg_packet_count(pkt, &count);

			// Check for BlockAdditional alpha data
			unsigned char *alphaData = NULL;
			size_t alphaLen = 0;
			nestegg_packet_additional_data(pkt, 1, &alphaData, &alphaLen);

			for (unsigned int c = 0; c < count; c++) {
				unsigned char *data = NULL;
				size_t len = 0;
				if (nestegg_packet_data(pkt, c, &data, &len) == 0 && data && len > 0) {
					vpx_codec_decode(&codec, data, (unsigned int)len, NULL, 0);

					vpx_image_t *alphaImg = NULL;
					if (alphaData && alphaLen > 0) {
						if (!hasAlphaCodec) {
							if (vpx_codec_dec_init(&alphaCodec, iface, &cfg, 0) == VPX_CODEC_OK) {
								hasAlphaCodec = YES;
							}
						}
						if (hasAlphaCodec) {
							vpx_codec_decode(&alphaCodec, alphaData, (unsigned int)alphaLen, NULL, 0);
							vpx_codec_iter_t aIter = NULL;
							alphaImg = vpx_codec_get_frame(&alphaCodec, &aIter);
						}
					}

					vpx_codec_iter_t iter = NULL;
					vpx_image_t *img = NULL;
					while ((img = vpx_codec_get_frame(&codec, &iter)) != NULL) {
						CGImageRef cg = CreateCGImageFromVpxImages(img, alphaImg);
						if (cg) {
							[frames addObject:CFBridgingRelease(cg)];
						}
					}
				}
			}
		}
		nestegg_free_packet(pkt);
		pkt = NULL;
	}

	if (hasAlphaCodec) {
		vpx_codec_destroy(&alphaCodec);
	}
	vpx_codec_destroy(&codec);
	nestegg_destroy(demux);
	fclose(fp);

	if (frames.count == 0) {
		NSLog(@"TGWebMDecoder: decoded 0 frames for %@", path);
		return nil;
	}

	double fps = 30.0;
	if (durSec > 0.05 && frames.count > 1) {
		fps = (double)frames.count / durSec;
		if (fps < 1.0) fps = 30.0;
		if (fps > 60.0) fps = 60.0;
	}

	if (outFps) *outFps = fps;
	if (outDuration) *outDuration = durSec;

	return frames;
}

+ (UIImage *)firstFrameFromFile:(NSString *)path {
	double fps = 30;
	NSTimeInterval dur = 0;
	NSArray *frames = [self decodeFramesFromFile:path fps:&fps duration:&dur];
	if (frames.count > 0) {
		CGImageRef cg = (__bridge CGImageRef)frames[0];
		return [UIImage imageWithCGImage:cg];
	}
	return nil;
}

@end
