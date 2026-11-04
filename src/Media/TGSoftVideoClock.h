//
// TGSoftVideoClock.h - when the software video player has to spend less.
//
// Pure C with no UIKit and no FFmpeg types, so the host test suite can drive
// it. The player reads the returned step and applies it to the decoder.
//
#ifndef TGSoftVideoClock_h
#define TGSoftVideoClock_h

#include <stdbool.h>

typedef enum {
	TGSoftVideoQualityFull = 0,
	TGSoftVideoQualitySkipLoopFilter,
	TGSoftVideoQualitySkipBidir,
	TGSoftVideoQualityDropFrames
} TGSoftVideoQuality;

typedef struct {
	TGSoftVideoQuality quality;
	/// False only while recovering from a long lag: the decoded frame is
	/// thrown away instead of drawn.
	bool display;
} TGSoftVideoDecision;

/// `audioSeconds` is the master clock, `videoSeconds` the timestamp of the
/// frame about to be drawn, `frameSeconds` one frame at the stream's rate.
/// `current` is the previous result, so a small lag does not flap the decoder
/// between settings.
TGSoftVideoDecision TGSoftVideoDecide(double audioSeconds, double videoSeconds,
									  double frameSeconds, TGSoftVideoQuality current);

#endif
