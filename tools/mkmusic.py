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
