import collections,sys
S=[];A={}
for l in open(sys.argv[1]):
    p=l.split()
    if not p: continue
    if p[0]=='S': S.append([int(x,16) for x in p[1:]])
    elif p[0]=='A': A[int(p[1],16)]=(p[3]+'`'+' '.join(p[4:]))
nm=lambda a:A.get(a,hex(a))
leaf=collections.Counter(nm(s[0]) for s in S)
img=collections.Counter(nm(s[0]).split('`')[0] for s in S)
tot=collections.Counter()
for s in S:
    for n in {nm(a) for a in s}: tot[n]+=1
N=len(S)
print("-- leaf image"); [print(f"{100*v/N:5.1f}% {k}") for k,v in img.most_common(10)]
print("-- leaf symbol"); [print(f"{100*v/N:5.1f}% {k}") for k,v in leaf.most_common(20)]
print("-- inclusive (named only)"); [print(f"{100*v/N:5.1f}% {k}") for k,v in [x for x in tot.most_common(300) if 'redacted' not in x[0] and not x[0].startswith('0x') and '?' not in x[0]][:40]]
