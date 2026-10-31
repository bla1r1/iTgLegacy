//
// TGStickerBudget.m - see TGStickerBudget.h.
//
#import "TGStickerBudget.h"

TGStickerBudget TGStickerBudgetForMemory(size_t memoryMB) {
	TGStickerBudget b;
	if (memoryMB <= 256) {
		// Vintage (iPod touch 4, 256 MB): the loop also has to leave room
		// for the chat's own images, TDLib's tree and everything else.
		b.frameCap = 32;
		b.pixelSideCap = 192;
		b.cacheTotalBytes = 6u * 1024u * 1024u;
	} else if (memoryMB <= 512) {
		// Legacy / early 64-bit (A5, A6, A7).
		b.frameCap = 36;
		b.pixelSideCap = 256;
		b.cacheTotalBytes = 10u * 1024u * 1024u;
	} else {
		// A8+ and desktop. The old constants: 60 frames at a full 256.
		b.frameCap = 60;
		b.pixelSideCap = 256;
		b.cacheTotalBytes = 16u * 1024u * 1024u;
	}
	return b;
}

size_t TGStickerFrameBytes(size_t widthPx, size_t heightPx, int frameCount) {
	return widthPx * heightPx * 4u * (size_t)(frameCount > 0 ? frameCount : 0);
}
