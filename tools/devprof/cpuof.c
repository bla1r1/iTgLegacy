// cpuof - print "<cpu seconds> <name>" for every process (no ps on the device)
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
struct proc_taskinfo { uint64_t vsz, rss, user, sys, tuser, tsys; int32_t pol, faults, pageins, cow, msgs, msgr, sysm, sysu, csw, threads, running, prio; };
int proc_listpids(uint32_t type, uint32_t info, void *buf, int size);
int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buf, int size);
int proc_name(int pid, void *buf, uint32_t size);
int main(void) {
	int pids[2048]; int n = proc_listpids(1, 0, pids, sizeof(pids)) / sizeof(int);
	for (int i = 0; i < n; i++) {
		if (!pids[i]) continue;
		struct proc_taskinfo ti; char name[64] = "";
		if (proc_pidinfo(pids[i], 4, 0, &ti, sizeof(ti)) != sizeof(ti)) continue;
		proc_name(pids[i], name, sizeof(name));
		// times are mach ticks; on A4 the timebase is 1/24 MHz
		printf("%.3f %s\n", (ti.user + ti.sys) / 24e6, name);
	}
	return 0;
}
