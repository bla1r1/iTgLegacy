// bbprof NAME SECONDS - sample every thread of another process (root + task_for_pid-allow)
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <mach/thread_policy.h>
#include <mach/mach_time.h>
#include <mach/task_info.h>
#include <mach-o/dyld_images.h>
int proc_listpids(uint32_t, uint32_t, void *, int);
int proc_name(int, void *, uint32_t);
#define MAXS 60000
#define D 24
static uint32_t buf[MAXS][D]; static uint8_t dep[MAXS]; static int ns;
static int cmp(const void *a, const void *b){ uint32_t x=*(uint32_t*)a,y=*(uint32_t*)b; return x<y?-1:x>y; }
int main(int argc, char **argv) {
	if (argc < 3) return 2;
	int pids[2048], n = proc_listpids(1, 0, pids, sizeof(pids)) / 4, pid = 0;
	for (int i = 0; i < n; i++) { char nm[64] = ""; proc_name(pids[i], nm, 64); if (pids[i] && !strcmp(nm, argv[1])) pid = pids[i]; }
	task_t t; if (!pid || task_for_pid(mach_task_self(), pid, &t)) { fprintf(stderr, "no task for %s (%d)\n", argv[1], pid); return 1; }
	const char *libs[] = {"/System/Library/Frameworks/QuartzCore.framework/QuartzCore","/System/Library/Frameworks/UIKit.framework/UIKit",
		"/System/Library/Frameworks/OpenGLES.framework/OpenGLES","/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
		"/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer","/System/Library/Frameworks/IOKit.framework/IOKit",
		"/System/Library/Frameworks/OpenGLES.framework/libGPUSupport.dylib","/System/Library/Frameworks/OpenGLES.framework/libGLImage.dylib",
		"/System/Library/Frameworks/ImageIO.framework/ImageIO","/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface",
		"/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",0};
	for (int i = 0; libs[i]; i++) dlopen(libs[i], RTLD_LAZY);
	// Realtime, or the render server (higher priority) is never caught running.
	mach_timebase_info_data_t tb; mach_timebase_info(&tb);
	uint64_t perMs = 1000000ull * tb.denom / tb.numer;
	thread_time_constraint_policy_data_t pol = { (uint32_t)(2 * perMs), (uint32_t)(perMs / 10), (uint32_t)(perMs / 5), 1 };
	if (thread_policy_set(mach_thread_self(), THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&pol, THREAD_TIME_CONSTRAINT_POLICY_COUNT))
		fprintf(stderr, "no realtime\n");
	double end = atof(argv[2]) * 1000; int busy = 0, total = 0;
	for (double ms = 0; ms < end && ns < MAXS - 64; ms += 2) {
		thread_act_array_t th; mach_msg_type_number_t tc;
		if (task_threads(t, &th, &tc)) break;
		task_suspend(t); total++;
		for (unsigned i = 0; i < tc && ns < MAXS; i++) {
			thread_basic_info_data_t bi; mach_msg_type_number_t bn = THREAD_BASIC_INFO_COUNT;
			thread_info(th[i], THREAD_BASIC_INFO, (thread_info_t)&bi, &bn);
			if (argc < 4 && bi.run_state != TH_STATE_RUNNING) continue;   // only what was on (or wanting) the CPU
			arm_thread_state_t st; mach_msg_type_number_t sn = ARM_THREAD_STATE_COUNT;
			if (thread_get_state(th[i], ARM_THREAD_STATE, (thread_state_t)&st, &sn)) continue;
			int d = 0; buf[ns][d++] = st.__pc; buf[ns][d++] = st.__lr; uint32_t fp = st.__r[7];
			while (d < D && fp && !(fp & 3)) { uint32_t fr[2]; vm_size_t got = 8;
				if (vm_read_overwrite(t, fp, 8, (vm_address_t)fr, &got) || got != 8 || !fr[1]) break;
				buf[ns][d++] = fr[1]; if (fr[0] <= fp) break; fp = fr[0]; }
			dep[ns++] = d; busy++;
		}
		task_resume(t);
		for (unsigned i = 0; i < tc; i++) mach_port_deallocate(mach_task_self(), th[i]);
		vm_deallocate(mach_task_self(), (vm_address_t)th, tc * 4);
		usleep(2000);
	}
	printf("ticks %d running-samples %d\n", total, busy);
	// Load addresses of the target's own images, for atos on the Mac: the
	// shared cache resolves here through dladdr, an app's dylibs do not.
	struct task_dyld_info di; mach_msg_type_number_t dn = TASK_DYLD_INFO_COUNT;
	if (!task_info(t, TASK_DYLD_INFO, (task_info_t)&di, &dn)) {
		struct dyld_all_image_infos all; vm_size_t got = sizeof all;
		if (!vm_read_overwrite(t, (vm_address_t)di.all_image_info_addr, sizeof all, (vm_address_t)&all, &got)) {
			for (uint32_t i = 0; i < all.infoArrayCount && i < 512; i++) {
				struct dyld_image_info ii; got = sizeof ii;
				if (vm_read_overwrite(t, (vm_address_t)(all.infoArray + i), sizeof ii, (vm_address_t)&ii, &got)) break;
				char path[256] = ""; got = sizeof path - 1;
				vm_read_overwrite(t, (vm_address_t)ii.imageFilePath, sizeof path - 1, (vm_address_t)path, &got);
				if (strstr(path, "/Applications/") || strstr(path, "/var/"))
					printf("I %lx %s\n", (unsigned long)ii.imageLoadAddress, path);
			}
		}
	}
	for (int i = 0; i < ns; i++) { printf("S"); for (int j = 0; j < dep[i]; j++) printf(" %x", buf[i][j]); printf("\n"); }
	static uint32_t u[MAXS * 4]; int k = 0;
	for (int i = 0; i < ns && k < MAXS * 4 - D; i++) for (int j = 0; j < dep[i]; j++) u[k++] = buf[i][j];
	qsort(u, k, 4, cmp);
	for (int i = 0; i < k; i++) { if (i && u[i] == u[i-1]) continue; Dl_info in; memset(&in, 0, sizeof in); dladdr((void *)(uintptr_t)u[i], &in);
		const char *img = in.dli_fname ? strrchr(in.dli_fname, '/') : 0;
		printf("A %x %lx %s %s\n", u[i], (unsigned long)in.dli_fbase, img ? img + 1 : "?", in.dli_sname ? in.dli_sname : "?"); }
	return 0;
}
