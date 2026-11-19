# Pack the three TurboSound PSG files (tools/music9/chip1..3.psg, 50 Hz AY register streams) into 8K music pages.
# frame = three records, one per AY chip: 16-bit mask (bit n = register n changes, 0..13) + one byte per set bit.
# chip 1's mask hi bit7 = continue on next page, bit6 = loop to start (a frame is never split across pages).
import os
R=os.path.dirname(os.path.abspath(__file__))+"/"; B=R+"../build/"
def load(fn):
    d=open(fn,"rb").read()[16:]
    frames=[];i=0
    while i<len(d):
        b=d[i]
        if b==0xFD: break
        if b==0xFE:
            frames+= [{} for _ in range(4*d[i+1])]; i+=2; continue
        assert b==0xFF; i+=1; f={}
        while i<len(d) and d[i]<0xFD: f[d[i]]=d[i+1]; i+=2
        frames.append(f)
    frames[0].update({r:frames[0].get(r,0) for r in range(13)})   # first frame writes everything (the tune loops to it)
    return frames
ch=[load(R+f"music9/chip{n}.psg") for n in (1,2,3)]
assert len(ch[0])==len(ch[1])==len(ch[2]), [len(c) for c in ch]
FADE=200; GAP=150                           # the last 4 s fade out on all nine channels, then 3 s of silence, then the tune restarts with no fade in
for c in ch:
    n=len(c); vol=[0,0,0]; last=[None]*3
    for k in range(n):
        for j in range(3):
            if 8+j in c[k]: vol[j]=c[k][8+j]
            assert vol[j]<16, "envelope volume in the fade"
        if k>=n-FADE:
            for j in range(3):
                v=vol[j]*(n-k-1)//FADE if False else vol[j]*(n-k)//(FADE+1)
                if v!=last[j]: c[k][8+j]=v
                else: c[k].pop(8+j,None)               # an unchanged (scaled) level needs no write
                last[j]=v
    for _ in range(GAP): c.append({})
    c[n-1].update({8:0,9:0,10:0}) if False else None
def rec(f):
    m=0
    for r in sorted(f): m|=1<<r
    return bytes([m&255,m>>8])+bytes(f[r] for r in sorted(f))
pages=[bytearray()]
for k in range(len(ch[0])):
    fr=b"".join(rec(c[k]) for c in ch)
    if len(pages[-1])+len(fr)>8192-2: pages[-1]+=bytes([0,0x80]); pages.append(bytearray())
    pages[-1]+=fr
pages[-1]+=bytes([0,0x40])
inc=[]
for n,p in enumerate(pages):
    open(B+f"music{n}.bin","wb").write(bytes(p))
    inc.append(f"            MMU 6, MUS_PG+{n}\n            ORG $C000\n            INCBIN \"build/music{n}.bin\"")
open(B+"music.inc","w").write("\n".join(inc)+"\n")
print(len(ch[0]),"frames",[len(p) for p in pages])

# ---- victory jingle: 3 channels from victory.psg, played on AY chip 2 (the other chips' records are empty); one page, ends with the "loop" flag
vf=load(R+"music9/victory.psg")
jb=bytearray()
for f in vf:
    jb+=bytes([0,0])+rec(f)+bytes([0,0])
jb+=bytes([0,0x40])
assert len(jb)<8190
open(B+"jingle.bin","wb").write(bytes(jb))
open(B+"music.inc","a").write('            MMU 6, 92\n            ORG $C000\n            INCBIN "build/jingle.bin"\n')
print("jingle",len(vf),"frames",len(jb),"bytes")
