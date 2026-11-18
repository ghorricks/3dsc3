# Pack tools/Storm_Runner.psg (50 Hz AY register stream) into 8K music pages for the menus.
# frame = 16-bit mask (bit n = register n changes, 0..13) + one byte per set bit.  mask hi bit7 = continue on next page, bit6 = loop to start.
import sys
d=open("/home/claude/stockcar/tools/Storm_Runner.psg","rb").read()[16:]
frames=[];i=0
while i<len(d):
    b=d[i]
    if b==0xFD: break
    assert b==0xFF; i+=1; f={}
    while i<len(d) and d[i]<0xFD: f[d[i]]=d[i+1]; i+=2
    frames.append(f)
frames[0].update({r:frames[0].get(r,0) for r in range(13)})      # first frame writes everything (the tune loops to it)
pages=[bytearray()]
for f in frames:
    rec=bytearray(); m=0
    for r in sorted(f): m|=1<<r
    rec+=bytes([m&255,m>>8])+bytes(f[r] for r in sorted(f))
    if len(pages[-1])+len(rec)>8192-2: pages[-1]+=bytes([0,0x80]); pages.append(bytearray())
    pages[-1]+=rec
pages[-1]+=bytes([0,0x40])
inc=[]
for n,p in enumerate(pages):
    open(f"/home/claude/stockcar/build/music{n}.bin","wb").write(bytes(p))
    inc.append(f"            MMU 6, MUS_PG+{n}\n            ORG $C000\n            INCBIN \"build/music{n}.bin\"")
open("/home/claude/stockcar/build/music.inc","w").write("\n".join(inc)+"\n")
print(len(frames),"frames",[len(p) for p in pages])
