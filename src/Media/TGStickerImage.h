//
// TGStickerImage.h - the one place a picked picture becomes a sticker file.
//
// Telegram checks the bytes, not the declared format: a sticker uploaded as
// WebP must start with RIFF....WEBP. A static sticker is also required to
// fit a 512x512 square, with the picture aspect-fitted and the rest left
// transparent. Both rules live here so the camera roll and the thumbnail
// path cannot drift apart.
//
#ifndef TG_STICKER_IMAGE_H
#define TG_STICKER_IMAGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The side Telegram requires for a static sticker and for a set thumbnail.
extern const size_t TGStickerImageSide;

/// The source drawn aspect-fit and centred on a transparent square. Returns
/// a +1 CGImage; the caller releases it. NULL for no image or a zero side.
CGImageRef TGStickerImageCreatePadded(CGImageRef source, size_t side);

/// The padded image encoded as lossy WebP. nil when encoding fails. The
/// bytes always start with "RIFF" and carry "WEBP" at offset 8.
NSData *TGStickerImageWebPData(CGImageRef source, size_t side, float quality);

#ifdef __cplusplus
}
#endif

#endif
