//
// TGStickerBudget.h - how much of this hardware one animated sticker may spend.
//
// A pre-rasterised .tgs loop is frameCount x side x side x 4 bytes, so a
// three-second loop at a full 256x256 on a 2x display is 15 MB on its own -
// the whole 32-bit cache ceiling in one sticker. The numbers are memory
// policy, not UI metrics: they come from the device tier, and they must obey
// the invariant that a full-length loop fits the NSCache's totalCostLimit.
//
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TGStickerBudget {
	int frameCap;             // frames rasterised ahead of playback
	int pixelSideCap;         // raster side per frame, pixels
	size_t cacheTotalBytes;   // NSCache totalCostLimit for the sticker cache
} TGStickerBudget;

/// Budget for a device with `memoryMB` of physical RAM.
TGStickerBudget TGStickerBudgetForMemory(size_t memoryMB);

/// Bytes a decoded loop occupies: one 32-bit RGBA bitmap per frame.
size_t TGStickerFrameBytes(size_t widthPx, size_t heightPx, int frameCount);

#ifdef __cplusplus
}
#endif
