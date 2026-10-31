//
// TGPerf.h - the two numbers this hardware argues about: milliseconds and
// resident bytes.
//
// An iPod touch 4 has one in-order 800 MHz core and ~40 MB before jetsam, so
// "feels slow" has to become a number before anything is optimised. These
// report only when a budget is blown, which keeps them in the shipping build:
// a quiet log is the normal case and the cost is one mach_absolute_time.
//
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Milliseconds from an arbitrary origin, monotonic.
double TGPerfNow(void);

/// Logs `what` if it took longer than `budgetMs`. `detail` may be NULL.
void TGPerfReport(const char *what, const char *detail, double startMs, double budgetMs);

/// This process's resident size, or 0 if the kernel would not say.
size_t TGPerfResidentBytes(void);

/// Logs the resident size with a label, every time - called at the handful of
/// points worth a line (chat opened, history loaded).
void TGPerfReportMemory(const char *what);

#ifdef __cplusplus
}
#endif
