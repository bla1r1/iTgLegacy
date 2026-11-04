//
// TGSoftVideoClock.c - the lag ladder for software video.
//
// The A4 can decode 480x480 H.264 at about 106 fps plain and 138 fps with
// the loop filter off. That is enough for a 60 fps file only until drawing
// shares the core, so the decoder gives up quality in a fixed order.
//
#include "TGSoftVideoClock.h"

// The decoder is already late at 60 ms. Losing the loop filter costs some
// block edges, nothing else. B frames are the next cheapest to drop and only
// arrive on a stream that has them at all. Below 300 ms of lag the listener
// notices the picture trailing the voice, so frames start going.
static const double kTGLagSkipLoopFilter = 0.060;
static const double kTGLagSkipBidir      = 0.150;
static const double kTGLagDropFrames     = 0.300;
// Once the picture is this close, go back to full quality. Hysteresis keeps
// it from toggling every frame at the boundary.
static const double kTGLagRecover        = 0.020;

TGSoftVideoDecision TGSoftVideoDecide(double audioSeconds, double videoSeconds,
									  double frameSeconds, TGSoftVideoQuality current) {
	TGSoftVideoDecision decision;
	double lag = audioSeconds - videoSeconds;
	if (lag <= kTGLagRecover)
		decision.quality = TGSoftVideoQualityFull;
	else if (lag >= kTGLagDropFrames)
		decision.quality = TGSoftVideoQualityDropFrames;
	else if (lag >= kTGLagSkipBidir)
		decision.quality = TGSoftVideoQualitySkipBidir;
	else if (lag >= kTGLagSkipLoopFilter)
		decision.quality = TGSoftVideoQualitySkipLoopFilter;
	else
		decision.quality = current;

	// A frame later than the audio by more than one frame interval has no
	// slot left; drawing it only makes the next one later still. Frames are
	// shown again as soon as the decoder has caught up to within one frame.
	decision.display = decision.quality != TGSoftVideoQualityDropFrames ||
					   lag <= frameSeconds;
	return decision;
}
