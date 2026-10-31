//
// TGSampler.h - a main-thread stack sampler for devices Instruments cannot
// reach (no Developer Disk Image exists for iOS 6/7 in current Xcode).
//
// A background thread suspends the main thread every `intervalUs`, walks its
// frame-pointer chain and stores raw return addresses into a buffer allocated
// up front: the suspended thread may hold the malloc lock, so nothing between
// suspend and resume may allocate. scripts/bench.sh turns the dump into a
// ranked list of functions.
//
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Must be called on the main thread. Returns 0 if a run is already going.
int TGSamplerStart(unsigned intervalUs, unsigned maxSamples);

/// Stops sampling and writes the dump to `path`. Returns the sample count.
int TGSamplerStopAndWrite(const char *path);

/// Where the single core went between two calls: this process per thread
/// (by name), the rest of the system, and idle. The main thread sampling
/// idle while frames drop means the time went to one of the other two.
/// The first call only takes the baseline and returns 0; each later call
/// writes one line into `out` and starts the next interval.
int TGCpuSplit(char *out, size_t cap);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// One line on where resident memory sits, vmmap-style: by VM tag (malloc,
/// CoreAnimation, CGImage...), mapped files apart, plus malloc's own count of
/// live bytes. Resident is what jetsam weighs; virtual size is not.
void TGMemoryBreakdown(char *out, size_t cap);

/// Sizes of live malloc blocks of 64 KB and up, largest first.
void TGMallocBigBlocks(char *out, size_t cap);

#ifdef __cplusplus
}
#endif
