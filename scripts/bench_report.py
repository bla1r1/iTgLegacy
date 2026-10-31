#!/usr/bin/env python3
# bench_report.py DUMP BINARY [ARCH] - rank functions in a TGSampler dump.
#
# "self" is where the main thread was when sampled, "total" counts a function
# once per sample anywhere on the stack. App frames go through atos against
# the unstripped binary; system frames keep the name dladdr found on device.
import collections, subprocess, sys

dump, binary = sys.argv[1], sys.argv[2]
arch = sys.argv[3] if len(sys.argv) > 3 else "armv7"
app = binary.rsplit("/", 1)[-1]

samples, addrs = [], {}
for line in open(dump):
    parts = line.split()
    if not parts:
        continue
    if parts[0] == "S":
        samples.append([int(a, 16) for a in parts[1:]])
    elif parts[0] == "A":
        addrs[int(parts[1], 16)] = (int(parts[2], 16), parts[3], " ".join(parts[4:]))

names = {a: f"{img}`{sym}" for a, (base, img, sym) in addrs.items()}
by_base = collections.defaultdict(list)
for a, (base, img, sym) in addrs.items():
    if img == app:
        by_base[base].append(a)
for base, lst in by_base.items():
    # return addresses point after the call; -1 lands on the call's line
    out = subprocess.run(["atos", "-arch", arch, "-o", binary, "-l", hex(base)]
                         + [hex(max(a - 1, base)) for a in lst],
                         capture_output=True, text=True).stdout.splitlines()
    for a, sym in zip(lst, out):
        names[a] = sym.split(" (in ")[0] if " (in " in sym else sym

def name(a):
    n = names.get(a, hex(a))
    return n.split(") (")[0] + ")" if ") (" in n else n

self_c, total_c = collections.Counter(), collections.Counter()
for s in samples:
    self_c[name(s[0])] += 1
    for n in {name(a) for a in s}:
        total_c[n] += 1

n = len(samples) or 1
print(f"{len(samples)} samples ({len(samples) * 2} ms of main thread at 2 ms)")
print("\n-- self (top 25)")
for k, v in self_c.most_common(25):
    print(f"{100 * v / n:5.1f}%  {k}")
print("\n-- total, app code only (top 40)")
shown = 0
for k, v in total_c.most_common():
    if "LegacyTG`" in k or ("`" not in k and not k.startswith("0x")):
        print(f"{100 * v / n:5.1f}%  {k}")
        shown += 1
        if shown == 40:
            break
