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
#include <math.h>

#if defined(__ARM_NEON__) || defined(__ARM_NEON)
#include <arm_neon.h>
#endif

#pragma mark - NestEgg File I/O Callbacks

static const CGFloat kTGWebMDefaultSide = 256.0f;

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

#pragma mark - YUV420 to RGBA Converter with ARM NEON SIMD Intrinsics

static void ConvertYUV420ToRGBA(vpx_image_t *img, vpx_image_t *alphaImg, uint8_t *dstRgba,
								unsigned int width, unsigned int height, size_t rgbaStride) {
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
		uint8_t *dst = dstRgba + y * rgbaStride;

		unsigned int x = 0;

#if defined(__ARM_NEON__) || defined(__ARM_NEON)
		for (; x + 8 <= width; x += 8) {
			uint8x8_t y_raw = vld1_u8(py + x);

			uint8x8_t u_4 = vld1_u8(pu + (x >> 1));
			uint8x8x2_t u_zip = vzip_u8(u_4, u_4);
			uint8x8_t u_raw = u_zip.val[0];

			uint8x8_t v_4 = vld1_u8(pv + (x >> 1));
			uint8x8x2_t v_zip = vzip_u8(v_4, v_4);
			uint8x8_t v_raw = v_zip.val[0];

			uint8x8_t a_raw = pa ? vld1_u8(pa + x) : vdup_n_u8(255);

			uint8x8_t y_clamped = vqsub_u8(y_raw, vdup_n_u8(16));
			int16x8_t c_16 = vreinterpretq_s16_u16(vmovl_u8(y_clamped));
			int16x8_t d_16 = vsubq_s16(vreinterpretq_s16_u16(vmovl_u8(u_raw)), vdupq_n_s16(128));
			int16x8_t e_16 = vsubq_s16(vreinterpretq_s16_u16(vmovl_u8(v_raw)), vdupq_n_s16(128));

			int16x4_t c_low = vget_low_s16(c_16);
			int16x4_t d_low = vget_low_s16(d_16);
			int16x4_t e_low = vget_low_s16(e_16);

			int16x4_t c_high = vget_high_s16(c_16);
			int16x4_t d_high = vget_high_s16(d_16);
			int16x4_t e_high = vget_high_s16(e_16);

			int32x4_t y_low = vmlal_n_s16(vdupq_n_s32(128), c_low, 298);
			int32x4_t r_low = vmlal_n_s16(y_low, e_low, 409);
			int32x4_t g_low = vmlsl_n_s16(vmlsl_n_s16(y_low, d_low, 100), e_low, 208);
			int32x4_t b_low = vmlal_n_s16(y_low, d_low, 516);

			int32x4_t y_high = vmlal_n_s16(vdupq_n_s32(128), c_high, 298);
			int32x4_t r_high = vmlal_n_s16(y_high, e_high, 409);
			int32x4_t g_high = vmlsl_n_s16(vmlsl_n_s16(y_high, d_high, 100), e_high, 208);
			int32x4_t b_high = vmlal_n_s16(y_high, d_high, 516);

			uint16x4_t r_u16_low = vqmovun_s32(vshrq_n_s32(r_low, 8));
			uint16x4_t r_u16_high = vqmovun_s32(vshrq_n_s32(r_high, 8));
			uint8x8_t r_u8 = vqmovn_u16(vcombine_u16(r_u16_low, r_u16_high));

			uint16x4_t g_u16_low = vqmovun_s32(vshrq_n_s32(g_low, 8));
			uint16x4_t g_u16_high = vqmovun_s32(vshrq_n_s32(g_high, 8));
			uint8x8_t g_u8 = vqmovn_u16(vcombine_u16(g_u16_low, g_u16_high));

			uint16x4_t b_u16_low = vqmovun_s32(vshrq_n_s32(b_low, 8));
			uint16x4_t b_u16_high = vqmovun_s32(vshrq_n_s32(b_high, 8));
			uint8x8_t b_u8 = vqmovn_u16(vcombine_u16(b_u16_low, b_u16_high));

			if (pa) {
				r_u8 = vqmovn_u16(vshrq_n_u16(vmlal_u8(vdupq_n_u16(128), r_u8, a_raw), 8));
				g_u8 = vqmovn_u16(vshrq_n_u16(vmlal_u8(vdupq_n_u16(128), g_u8, a_raw), 8));
				b_u8 = vqmovn_u16(vshrq_n_u16(vmlal_u8(vdupq_n_u16(128), b_u8, a_raw), 8));
			}

			uint8x8x4_t rgba;
			rgba.val[0] = r_u8;
			rgba.val[1] = g_u8;
			rgba.val[2] = b_u8;
			rgba.val[3] = a_raw;
			vst4_u8(dst, rgba);
			dst += 32;
		}
#endif

		for (; x < width; x++) {
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
}

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

	ConvertYUV420ToRGBA(img, alphaImg, rgba, width, height, rgbaStride);

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
	if (!path.length)
		return nil;

	FILE *fp = fopen(path.UTF8String, "rb");
	if (!fp) return nil;

	nestegg_io io = { webm_io_read, webm_io_seek, webm_io_tell, fp };
	nestegg *demux = NULL;
	if (nestegg_init(&demux, io, NULL, -1) != 0) {
		fclose(fp);
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
		return nil;
	}

	vpx_codec_ctx_t codec;
	vpx_codec_dec_cfg_t cfg = {0};
	cfg.threads = 1;
	vpx_codec_iface_t *iface = vpx_codec_vp9_dx();
	if (vpx_codec_dec_init(&codec, iface, &cfg, 0) != VPX_CODEC_OK) {
		nestegg_destroy(demux);
		fclose(fp);
		return nil;
	}

	vpx_codec_ctx_t alphaCodec;
	BOOL hasAlphaCodec = NO;
	nestegg_packet *pkt = NULL;
	CGImageRef firstCG = NULL;

	while (nestegg_read_packet(demux, &pkt) > 0) {
		unsigned int track = 0;
		nestegg_packet_track(pkt, &track);
		if ((int)track == videoTrack) {
			unsigned int count = 0;
			nestegg_packet_count(pkt, &count);

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
					vpx_image_t *img = vpx_codec_get_frame(&codec, &iter);
					if (img) {
						firstCG = CreateCGImageFromVpxImages(img, alphaImg);
						break;
					}
				}
			}
		}
		nestegg_free_packet(pkt);
		pkt = NULL;
		if (firstCG) {
			// Early exit immediately after the 1st keyframe is decoded!
			break;
		}
	}

	if (hasAlphaCodec) {
		vpx_codec_destroy(&alphaCodec);
	}
	vpx_codec_destroy(&codec);
	nestegg_destroy(demux);
	fclose(fp);

	if (firstCG) {
		UIImage *uiImg = [UIImage imageWithCGImage:firstCG];
		CGImageRelease(firstCG);
		return uiImg;
	}
	return nil;
}

@end

#pragma mark - TGWebMStreamPlayer Implementation

@implementation TGWebMStreamPlayer {
	FILE *_fp;
	nestegg *_demux;
	int _videoTrack;
	vpx_codec_ctx_t _codec;
	vpx_codec_ctx_t _alphaCodec;
	BOOL _codecInited;
	BOOL _alphaCodecInited;
	CADisplayLink *_displayLink;
	uint8_t _ringBuffer[3][512 * 512 * 4];
	int _ringSlot;
	CGImageRef _currentImage;
}

- (instancetype)initWithPath:(NSString *)path {
	if (!path.length) return nil;
	if ((self = [super init])) {
		_path = [path copy];
		_ringSlot = 0;
		if (![self initDemuxerAndCodec]) {
			[self cleanup];
			return nil;
		}
	}
	return self;
}

- (BOOL)initDemuxerAndCodec {
	_fp = fopen(_path.UTF8String, "rb");
	if (!_fp) return NO;

	nestegg_io io = { webm_io_read, webm_io_seek, webm_io_tell, _fp };
	if (nestegg_init(&_demux, io, NULL, -1) != 0) {
		return NO;
	}

	unsigned int trackCount = 0;
	nestegg_track_count(_demux, &trackCount);
	_videoTrack = -1;
	for (unsigned int i = 0; i < trackCount; i++) {
		if (nestegg_track_type(_demux, i) == NESTEGG_TRACK_VIDEO) {
			_videoTrack = (int)i;
			break;
		}
	}
	if (_videoTrack < 0) return NO;

	uint64_t durNs = 0;
	nestegg_duration(_demux, &durNs);
	_duration = (durNs > 0) ? ((double)durNs / 1000000000.0) : 2.0;

	vpx_codec_dec_cfg_t cfg = {0};
	cfg.threads = 1;
	vpx_codec_iface_t *iface = vpx_codec_vp9_dx();
	if (vpx_codec_dec_init(&_codec, iface, &cfg, 0) != VPX_CODEC_OK) {
		return NO;
	}
	_codecInited = YES;

	_fps = 30.0;
	_pixelSize = CGSizeMake(kTGWebMDefaultSide, kTGWebMDefaultSide);

	// Decode the first frame to populate pixelSize and initial contents
	CGImageRef f0 = [self decodeNextFrame];
	if (f0) {
		_pixelSize = CGSizeMake(CGImageGetWidth(f0), CGImageGetHeight(f0));
	}

	return YES;
}

- (void)cleanup {
	[self stop];
	if (_currentImage) {
		CGImageRelease(_currentImage);
		_currentImage = NULL;
	}
	if (_alphaCodecInited) {
		vpx_codec_destroy(&_alphaCodec);
		_alphaCodecInited = NO;
	}
	if (_codecInited) {
		vpx_codec_destroy(&_codec);
		_codecInited = NO;
	}
	if (_demux) {
		nestegg_destroy(_demux);
		_demux = NULL;
	}
	if (_fp) {
		fclose(_fp);
		_fp = NULL;
	}
}

- (void)dealloc {
	[self cleanup];
}

- (void)play {
	if (_isPlaying) return;
	_isPlaying = YES;
	if (!_displayLink) {
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
		int interval = (int)round(60.0 / (_fps > 0 ? _fps : 30.0));
		if (interval < 1) interval = 1;
		_displayLink.frameInterval = interval;
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	}
}

- (void)stop {
	_isPlaying = NO;
	if (_displayLink) {
		[_displayLink invalidate];
		_displayLink = nil;
	}
}

- (void)pause {
	[self stop];
}

- (CGImageRef)currentFrameImage {
	return _currentImage;
}

- (CGImageRef)decodeNextFrame {
	if (!_demux || _videoTrack < 0 || !_codecInited) return _currentImage;

	nestegg_packet *pkt = NULL;
	int loopCount = 0;

	while (loopCount < 2) {
		int r = nestegg_read_packet(_demux, &pkt);
		if (r <= 0) {
			// Loop around when EOF is reached
			loopCount++;
			if (_fp) {
				fseek(_fp, 0, SEEK_SET);
				if (_demux) nestegg_destroy(_demux);
				_demux = NULL;
				nestegg_io io = { webm_io_read, webm_io_seek, webm_io_tell, _fp };
				if (nestegg_init(&_demux, io, NULL, -1) != 0) {
					return _currentImage;
				}
			}
			continue;
		}

		unsigned int track = 0;
		nestegg_packet_track(pkt, &track);
		if ((int)track == _videoTrack) {
			unsigned int count = 0;
			nestegg_packet_count(pkt, &count);

			unsigned char *alphaData = NULL;
			size_t alphaLen = 0;
			nestegg_packet_additional_data(pkt, 1, &alphaData, &alphaLen);

			for (unsigned int c = 0; c < count; c++) {
				unsigned char *data = NULL;
				size_t len = 0;
				if (nestegg_packet_data(pkt, c, &data, &len) == 0 && data && len > 0) {
					vpx_codec_decode(&_codec, data, (unsigned int)len, NULL, 0);

					vpx_image_t *alphaImg = NULL;
					if (alphaData && alphaLen > 0) {
						if (!_alphaCodecInited) {
							vpx_codec_dec_cfg_t cfg = {0};
							cfg.threads = 1;
							if (vpx_codec_dec_init(&_alphaCodec, vpx_codec_vp9_dx(), &cfg, 0) == VPX_CODEC_OK) {
								_alphaCodecInited = YES;
							}
						}
						if (_alphaCodecInited) {
							vpx_codec_decode(&_alphaCodec, alphaData, (unsigned int)alphaLen, NULL, 0);
							vpx_codec_iter_t aIter = NULL;
							alphaImg = vpx_codec_get_frame(&_alphaCodec, &aIter);
						}
					}

					vpx_codec_iter_t iter = NULL;
					vpx_image_t *img = vpx_codec_get_frame(&_codec, &iter);
					if (img) {
						unsigned int w = (unsigned int)MIN(512, (int)img->d_w);
						unsigned int h = (unsigned int)MIN(512, (int)img->d_h);
						if (w > 0 && h > 0) {
							_ringSlot = (_ringSlot + 1) % 3;
							uint8_t *slotBuf = _ringBuffer[_ringSlot];
							size_t rgbaStride = w * 4;

							ConvertYUV420ToRGBA(img, alphaImg, slotBuf, w, h, rgbaStride);

							CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
							CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, slotBuf, rgbaStride * h, NULL);
							CGImageRef newCg = CGImageCreate(
								w, h, 8, 32, rgbaStride,
								colorSpace,
								kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
								provider, NULL, NO, kCGRenderingIntentDefault);
							CGDataProviderRelease(provider);
							CGColorSpaceRelease(colorSpace);

							if (newCg) {
								if (_currentImage) CGImageRelease(_currentImage);
								_currentImage = newCg;
							}
						}
						nestegg_free_packet(pkt);
						return _currentImage;
					}
				}
			}
		}
		nestegg_free_packet(pkt);
		pkt = NULL;
	}

	return _currentImage;
}

- (void)tick:(CADisplayLink *)link {
	if (!_isPlaying) return;
	CGImageRef img = [self decodeNextFrame];
	if (img) {
		if (self.targetLayer) {
			self.targetLayer.contents = (__bridge id)img;
		}
		if (self.onFrame) {
			self.onFrame(img);
		}
	}
}

@end
