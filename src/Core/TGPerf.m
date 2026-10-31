//
// TGPerf.m - see TGPerf.h.
//
#import <Foundation/Foundation.h>
#import "TGPerf.h"
#include <mach/mach.h>
#include <mach/mach_time.h>

double TGPerfNow(void) {
	// mach_absolute_time is the only clock iOS 6 exports: clock_gettime is
	// weakly matched there, and calling it jumped into a null stub. Ticks
	// replay the boot epoch, so the count can outgrow a double's precision
	// on a device that never powers off - anchoring to our first call keeps
	// every absolute small and every subtraction of two of them exact.
	static mach_timebase_info_data_t tb;
	if (tb.denom == 0)
		mach_timebase_info(&tb);
	static double epochMs = -1.0;
	if (epochMs < 0.0)
		epochMs = (double)mach_absolute_time() * (double)tb.numer
				/ (double)tb.denom / 1.0e6;
	double nowMs = (double)mach_absolute_time() * (double)tb.numer
			/ (double)tb.denom / 1.0e6;
	return nowMs - epochMs;
}

void TGPerfReport(const char *what, const char *detail, double startMs, double budgetMs) {
	double took = TGPerfNow() - startMs;
	if (took < budgetMs)
		return;
	NSLog(@"[perf] %s %s took %.1f ms (budget %.0f)", what ?: "?",
			detail ?: "", took, budgetMs);
}

size_t TGPerfResidentBytes(void) {
	struct mach_task_basic_info info;
	mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
	if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
			(task_info_t)&info, &count) != KERN_SUCCESS)
		return 0;
	return (size_t)info.resident_size;
}

void TGPerfReportMemory(const char *what) {
	size_t bytes = TGPerfResidentBytes();
	if (!bytes)
		return;
	NSLog(@"[perf] %s resident %.1f MB", what ?: "?", (double)bytes / (1024.0 * 1024.0));
}
