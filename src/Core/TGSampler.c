//
// TGSampler.c - see TGSampler.h.
//
#include "TGSampler.h"
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { kDepth = 32 };

static thread_act_t sMain;
static pthread_t sThread;
static volatile int sRunning;
static unsigned sInterval, sMax, sCount;
static uintptr_t *sFrames;          // sMax * kDepth
static uint8_t *sDepths;
static uintptr_t sStackLo, sStackHi;

static int takeSample(uintptr_t *out) {
	uintptr_t pc, fp;
#if defined(__arm64__)
	arm_thread_state64_t st;
	mach_msg_type_number_t n = ARM_THREAD_STATE64_COUNT;
	if (thread_get_state(sMain, ARM_THREAD_STATE64, (thread_state_t)&st, &n) != KERN_SUCCESS)
		return 0;
	pc = (uintptr_t)st.__pc;
	fp = (uintptr_t)st.__fp;
#elif defined(__arm__)
	arm_thread_state_t st;
	mach_msg_type_number_t n = ARM_THREAD_STATE_COUNT;
	if (thread_get_state(sMain, ARM_THREAD_STATE, (thread_state_t)&st, &n) != KERN_SUCCESS)
		return 0;
	pc = st.__pc;
	fp = st.__r[7];                 // Apple's armv7 ABI keeps r7 as the frame pointer
#else
	(void)out;
	return 0;
#endif
	int d = 0;
	out[d++] = pc;
	// Each frame is {saved fp, return address}. The bounds check is what keeps
	// a half-built frame in a prologue from sending us into unmapped memory.
	while (d < kDepth && fp >= sStackLo && fp + 2 * sizeof(uintptr_t) <= sStackHi
			&& (fp & (sizeof(uintptr_t) - 1)) == 0) {
		uintptr_t next = ((uintptr_t *)fp)[0];
		uintptr_t ret = ((uintptr_t *)fp)[1];
		if (!ret)
			break;
		out[d++] = ret;
		if (next <= fp)
			break;
		fp = next;
	}
	return d;
}

static void *samplerLoop(void *unused) {
	(void)unused;
	while (sRunning && sCount < sMax) {
		if (thread_suspend(sMain) == KERN_SUCCESS) {
			int d = takeSample(sFrames + (size_t)sCount * kDepth);
			thread_resume(sMain);
			if (d > 0)
				sDepths[sCount++] = (uint8_t)d;
		}
		usleep(sInterval);
	}
	return NULL;
}

int TGSamplerStart(unsigned intervalUs, unsigned maxSamples) {
	if (sRunning)
		return 0;
	sMain = mach_thread_self();
	pthread_t self = pthread_self();
	sStackHi = (uintptr_t)pthread_get_stackaddr_np(self);
	sStackLo = sStackHi - pthread_get_stacksize_np(self);
	sInterval = intervalUs ? intervalUs : 2000;
	sMax = maxSamples ? maxSamples : 8000;
	sCount = 0;
	free(sFrames);
	free(sDepths);
	sFrames = calloc((size_t)sMax * kDepth, sizeof(uintptr_t));
	sDepths = calloc(sMax, 1);
	if (!sFrames || !sDepths)
		return 0;
	sRunning = 1;
	if (pthread_create(&sThread, NULL, samplerLoop, NULL) != 0) {
		sRunning = 0;
		return 0;
	}
	return 1;
}

static int cmpAddr(const void *a, const void *b) {
	uintptr_t x = *(const uintptr_t *)a, y = *(const uintptr_t *)b;
	return x < y ? -1 : x > y;
}

int TGSamplerStopAndWrite(const char *path) {
	if (!sRunning)
		return 0;
	sRunning = 0;
	pthread_join(sThread, NULL);

	FILE *f = fopen(path, "w");
	if (!f)
		return 0;
	// Samples first, one line each, leaf first.
	size_t total = 0;
	for (unsigned i = 0; i < sCount; i++) {
		fprintf(f, "S");
		for (unsigned j = 0; j < sDepths[i]; j++)
			fprintf(f, " %lx", (unsigned long)sFrames[(size_t)i * kDepth + j]);
		fprintf(f, "\n");
		total += sDepths[i];
	}
	// Then one line per distinct address: its image, image base and the
	// nearest exported symbol. System frameworks only symbolicate here, on the
	// device; the app's own frames get atos on the Mac from the unstripped
	// binary, which knows the static functions dladdr cannot see.
	uintptr_t *uniq = malloc(total * sizeof(uintptr_t));
	size_t u = 0;
	if (uniq) {
		for (unsigned i = 0; i < sCount; i++)
			for (unsigned j = 0; j < sDepths[i]; j++)
				uniq[u++] = sFrames[(size_t)i * kDepth + j];
		qsort(uniq, u, sizeof(uintptr_t), cmpAddr);
		for (size_t i = 0; i < u; i++) {
			if (i && uniq[i] == uniq[i - 1])
				continue;
			Dl_info info;
			memset(&info, 0, sizeof(info));
			dladdr((void *)uniq[i], &info);
			const char *img = info.dli_fname ? strrchr(info.dli_fname, '/') : NULL;
			fprintf(f, "A %lx %lx %s %s\n", (unsigned long)uniq[i],
					(unsigned long)info.dli_fbase,
					img ? img + 1 : "?", info.dli_sname ? info.dli_sname : "?");
		}
		free(uniq);
	}
	fclose(f);
	free(sFrames);
	free(sDepths);
	sFrames = NULL;
	sDepths = NULL;
	return (int)sCount;
}

// ---------------------------------------------------------------- CPU split

#include <mach/mach_host.h>
#include <mach/processor_info.h>

enum { kMaxThreads = 64 };
static struct { uint64_t port; double cpu; } sThreadBase[kMaxThreads];
static int sThreadBaseCount;
static unsigned long long sHostBase[CPU_STATE_MAX];
static int sHaveBase;

static double threadSeconds(thread_act_t t) {
	thread_basic_info_data_t info;
	mach_msg_type_number_t n = THREAD_BASIC_INFO_COUNT;
	if (thread_info(t, THREAD_BASIC_INFO, (thread_info_t)&info, &n) != KERN_SUCCESS)
		return 0;
	return info.user_time.seconds + info.user_time.microseconds / 1e6
			+ info.system_time.seconds + info.system_time.microseconds / 1e6;
}

static void hostTicks(unsigned long long out[CPU_STATE_MAX]) {
	natural_t cpus = 0;
	processor_info_array_t info = NULL;
	mach_msg_type_number_t n = 0;
	memset(out, 0, sizeof(unsigned long long) * CPU_STATE_MAX);
	if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpus, &info, &n) != KERN_SUCCESS)
		return;
	for (natural_t c = 0; c < cpus; c++)
		for (int s = 0; s < CPU_STATE_MAX; s++)
			out[s] += (unsigned)info[c * CPU_STATE_MAX + s];
	vm_deallocate(mach_task_self(), (vm_address_t)info, n * sizeof(integer_t));
}

typedef struct { char name[24]; double sec; } ThreadUse;

static int byUse(const void *a, const void *b) {
	double x = ((const ThreadUse *)a)->sec, y = ((const ThreadUse *)b)->sec;
	return x < y ? 1 : x > y ? -1 : 0;
}

int TGCpuSplit(char *out, size_t cap) {
	thread_act_array_t threads = NULL;
	mach_msg_type_number_t count = 0;
	if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS)
		return 0;
	unsigned long long host[CPU_STATE_MAX];
	hostTicks(host);
	thread_act_t mainPort = mach_thread_self();     // only ever called on main

	ThreadUse use[kMaxThreads];
	int used = 0;
	double appTotal = 0;
	int n = count < kMaxThreads ? (int)count : kMaxThreads;
	for (int i = 0; i < n; i++) {
		double now = threadSeconds(threads[i]);
		double before = 0;
		for (int j = 0; j < sThreadBaseCount; j++)
			if (sThreadBase[j].port == threads[i]) { before = sThreadBase[j].cpu; break; }
		double d = now - before;   // a thread born this interval counts from zero
		sThreadBase[i].port = threads[i];
		sThreadBase[i].cpu = now;
		appTotal += d;
		if (d < 0.005)
			continue;
		ThreadUse *u = &use[used++];
		u->sec = d;
		u->name[0] = 0;
		pthread_t pt = pthread_from_mach_thread_np(threads[i]);
		if (pt)
			pthread_getname_np(pt, u->name, sizeof(u->name));
		if (threads[i] == mainPort)
			snprintf(u->name, sizeof(u->name), "main");
		else if (!u->name[0])
			snprintf(u->name, sizeof(u->name), "t%d", i);
	}
	sThreadBaseCount = n;
	for (mach_msg_type_number_t i = 0; i < count; i++)
		mach_port_deallocate(mach_task_self(), threads[i]);
	vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_act_t));
	mach_port_deallocate(mach_task_self(), mainPort);

	int wrote = 0;
	if (sHaveBase) {
		unsigned long long busy = (host[CPU_STATE_USER] - sHostBase[CPU_STATE_USER])
				+ (host[CPU_STATE_SYSTEM] - sHostBase[CPU_STATE_SYSTEM])
				+ (host[CPU_STATE_NICE] - sHostBase[CPU_STATE_NICE]);
		unsigned long long idle = host[CPU_STATE_IDLE] - sHostBase[CPU_STATE_IDLE];
		const double hz = 100.0;    // host load ticks are 10 ms
		double other = busy / hz - appTotal;
		int len = snprintf(out, cap, "wall=%.2fs app=%.2fs other=%.2fs idle=%.2fs |",
				(busy + idle) / hz, appTotal, other < 0 ? 0 : other, idle / hz);
		qsort(use, used, sizeof(ThreadUse), byUse);
		for (int k = 0; k < used && k < 6 && len > 0 && (size_t)len < cap; k++)
			len += snprintf(out + len, cap - len, " %s=%.2f", use[k].name, use[k].sec);
		wrote = 1;
	}
	memcpy(sHostBase, host, sizeof(host));
	sHaveBase = 1;
	return wrote;
}

// ---------------------------------------------------------------- memory

#include <malloc/malloc.h>
#include <mach/vm_statistics.h>

static const char *tagName(unsigned tag) {
	switch (tag) {
	case VM_MEMORY_MALLOC: return "malloc";
	case VM_MEMORY_MALLOC_SMALL: return "malloc-small";
	case VM_MEMORY_MALLOC_LARGE: return "malloc-large";
	case VM_MEMORY_MALLOC_HUGE: return "malloc-huge";
	case VM_MEMORY_MALLOC_TINY: return "malloc-tiny";
	case VM_MEMORY_IOKIT: return "iokit";
	case VM_MEMORY_STACK: return "stack";
	case VM_MEMORY_GUARD: return "guard";
	case VM_MEMORY_SHARED_PMAP: return "pmap";
	case VM_MEMORY_DYLIB: return "dylib";
	case VM_MEMORY_FOUNDATION: return "foundation";
	case VM_MEMORY_COREGRAPHICS: return "cg";
	case VM_MEMORY_LAYERKIT: return "coreanimation";
	case VM_MEMORY_CGIMAGE: return "cgimage";
	case VM_MEMORY_COREGRAPHICS_DATA: return "cg-data";
	case VM_MEMORY_COREGRAPHICS_BACKINGSTORES: return "cg-backing";
	case VM_MEMORY_UNSHARED_PMAP: return "unshared-pmap";
	case VM_MEMORY_SQLITE: return "sqlite";
	case VM_MEMORY_IMAGEIO: return "imageio";
	case VM_MEMORY_JAVASCRIPT_CORE: return "jsc";
	case VM_MEMORY_DYLD: return "dyld";
	case VM_MEMORY_DYLD_MALLOC: return "dyld-malloc";
	}
	return NULL;
}

void TGMemoryBreakdown(char *out, size_t cap) {
	enum { kTags = 256 };
	unsigned long long byTag[kTags + 1];        // the extra slot: mapped files
	memset(byTag, 0, sizeof(byTag));
	vm_address_t addr = 0;
	vm_size_t size = 0;
	natural_t depth = 0;
	unsigned long long total = 0;
	for (;;) {
		struct vm_region_submap_info_64 info;
		mach_msg_type_number_t n = VM_REGION_SUBMAP_INFO_COUNT_64;
		if (vm_region_recurse_64(mach_task_self(), &addr, &size, &depth,
				(vm_region_info_64_t)&info, &n) != KERN_SUCCESS)
			break;
		if (info.is_submap) {
			depth++;
			continue;
		}
		// Shared-cache and other shared pages are counted once system-wide;
		// what is private (or copied on write) is what this process costs.
		unsigned long long bytes = (unsigned long long)info.pages_resident * vm_page_size;
		unsigned slot = info.user_tag < kTags ? info.user_tag : 0;
		// A file's clean pages (code, fonts, a mapped database) are dropped
		// and re-read whenever the kernel likes; only its dirtied pages are
		// this process's to give back.
		if (!info.user_tag && info.external_pager) {
			slot = kTags;
			bytes = (unsigned long long)info.pages_dirtied * vm_page_size;
		}
		if (info.share_mode == SM_SHARED || info.share_mode == SM_TRUESHARED)
			bytes = (unsigned long long)info.pages_dirtied * vm_page_size;
		byTag[slot] += bytes;
		total += bytes;
		addr += size;
	}

	malloc_statistics_t ms;
	memset(&ms, 0, sizeof(ms));
	malloc_zone_statistics(NULL, &ms);

	struct mach_task_basic_info ti;
	mach_msg_type_number_t tn = MACH_TASK_BASIC_INFO_COUNT;
	double taskMB = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&ti, &tn) == KERN_SUCCESS
			? ti.resident_size / 1048576.0 : 0;
	int len = snprintf(out, cap, "task=%.1fMB dirty=%.1fMB malloc-live=%.1fMB |",
			taskMB, total / 1048576.0, ms.size_in_use / 1048576.0);
	for (int round = 0; round < 8 && len > 0 && (size_t)len < cap; round++) {
		unsigned best = 0;
		unsigned long long bestBytes = 0;
		for (unsigned t = 0; t <= kTags; t++)
			if (byTag[t] > bestBytes) { bestBytes = byTag[t]; best = t; }
		if (bestBytes < 256 * 1024)
			break;
		const char *name = best == kTags ? "files-dirty" : tagName(best);
		if (name)
			len += snprintf(out + len, cap - len, " %s=%.1f", name, bestBytes / 1048576.0);
		else
			len += snprintf(out + len, cap - len, " tag%u=%.1f", best, bestBytes / 1048576.0);
		byTag[best] = 0;
	}
}

// Sizes of live malloc blocks of 64 KB and up, largest first: the big ones
// are pixel buffers, and their sizes say whose.
static size_t sBig[256];
static unsigned sBigCount;

static kern_return_t readLocal(task_t t, vm_address_t a, vm_size_t n, void **out) {
	(void)t; (void)n;
	*out = (void *)a;
	return KERN_SUCCESS;
}

static void collectBig(task_t t, void *ctx, unsigned type, vm_range_t *ranges, unsigned count) {
	(void)t; (void)ctx; (void)type;
	for (unsigned i = 0; i < count && sBigCount < 256; i++)
		if (ranges[i].size >= 64 * 1024)
			sBig[sBigCount++] = ranges[i].size;
}

static int bySizeDesc(const void *a, const void *b) {
	size_t x = *(const size_t *)a, y = *(const size_t *)b;
	return x < y ? 1 : x > y ? -1 : 0;
}

void TGMallocBigBlocks(char *out, size_t cap) {
	vm_address_t *zones = NULL;
	unsigned zoneCount = 0;
	sBigCount = 0;
	if (malloc_get_all_zones(mach_task_self(), readLocal, &zones, &zoneCount) == KERN_SUCCESS)
		for (unsigned z = 0; z < zoneCount; z++) {
			malloc_zone_t *zone = (malloc_zone_t *)zones[z];
			if (zone && zone->introspect && zone->introspect->enumerator)
				zone->introspect->enumerator(mach_task_self(), NULL, MALLOC_PTR_IN_USE_RANGE_TYPE,
						(vm_address_t)zone, readLocal, collectBig);
		}
	qsort(sBig, sBigCount, sizeof(size_t), bySizeDesc);
	size_t sum = 0;
	for (unsigned i = 0; i < sBigCount; i++) sum += sBig[i];
	int len = snprintf(out, cap, "%u blocks >=64KB, %.1fMB:", sBigCount, sum / 1048576.0);
	for (unsigned i = 0; i < sBigCount && len > 0 && (size_t)len < cap - 16; i++)
		len += snprintf(out + len, cap - len, " %zuK", sBig[i] / 1024);
}
