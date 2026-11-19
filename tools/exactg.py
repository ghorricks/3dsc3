# Exact fence mask for tracks 7-10 from the original game's own screen (median of frames removes the cars).
import sys,numpy as np
from PIL import Image
from scipy import ndimage as ndi
n=int(sys.argv[1]); col=tuple(int(v) for v in sys.argv[2].split(',')); minlen=int(sys.argv[3]) if len(sys.argv)>3 else 24
med=np.array(Image.open(f"/home/claude/stockcar/orig/track{n}_median.png"))
w=(med==col).all(2)
w[:9]=False
if n==7: w[:27,88:106]=False; w[:16,140:215]=False
if n==18: w[17:24,95:110]=False       # the idle human car sits on the grid
if n==23: w[17:26,92:104]=False; w[37:49,94:102]=False       # flag pole
lab,k=ndi.label(w,structure=np.ones((3,3)))
keep=np.zeros_like(w)
for i,sl in enumerate(ndi.find_objects(lab),1):
    if max(sl[0].stop-sl[0].start,sl[1].stop-sl[1].start)>=minlen: keep|=(lab==i)
if n==14:   # 3D platform in the middle: handled as a solid footprint (see fenceg.edit14); the road fences stay in the mask
    lab3,k3=ndi.label(keep,structure=np.ones((3,3)))
    szs=[(ndi.find_objects(lab3)[i][0].stop-ndi.find_objects(lab3)[i][0].start)*(ndi.find_objects(lab3)[i][1].stop-ndi.find_objects(lab3)[i][1].start) for i in range(k3)]
    order=np.argsort(szs)[::-1]; ring=lab3==order[0]+1; plat=lab3==order[1]+1
    np.save("/home/claude/stockcar/build/plat14.npy",ndi.binary_fill_holes(plat))
    keep=ring
if n in (15,16,18,19,20):   # hatched slab tops (checkerboard texture): drop the texture, keep the outlines
    sr=np.zeros_like(keep)                       # pixels in horizontal runs of length <=2 (the texture is 2-px dashes, walls are long runs)
    for y in range(keep.shape[0]):
        x=0; row=keep[y]
        while x<keep.shape[1]:
            if row[x]:
                x2=x
                while x2<keep.shape[1] and row[x2]: x2+=1
                if x2-x<=2: sr[y,x:x2]=True
                x=x2
            else: x+=1
    dens=ndi.uniform_filter(sr.astype(float),9)>0.30
    blk=ndi.binary_opening(dens,structure=np.ones((5,5)))
    lb,kb=ndi.label(blk)
    for i in range(1,kb+1):
        if (lb==i).sum()<100: blk[lb==i]=False
    blk=ndi.binary_dilation(blk,iterations=2)
    keep=keep&~blk
    np.save("/home/claude/stockcar/build/hatch%d.npy"%n,blk)
if n in (15,16,18,19,20):   # slab top = solid footprint: closed regions of the fence mask the start lane cannot reach
    import json
    sx_,sy_=json.load(open("/home/claude/stockcar/build/tracks.json"))[str(n)]["start"]
    wl=ndi.binary_closing(keep,structure=np.ones((3,3)))
    try: wl|=np.load("/home/claude/stockcar/build/hatch%d.npy"%n)
    except Exception: pass
    lb2,kb2=ndi.label(~wl,structure=np.array([[0,1,0],[1,1,1],[0,1,0]]))
    dn=np.zeros_like(keep)
    for i in range(1,kb2+1):
        m_=lb2==i
        if i!=lb2[sy_,sx_] and m_.sum()>=300 and not (m_[0].any() or m_[-1].any() or m_[:,0].any() or m_[:,-1].any()): dn|=m_
    try: dn|=ndi.binary_dilation(np.load("/home/claude/stockcar/build/hatch%d.npy"%n),iterations=1)
    except Exception: pass
    np.save("/home/claude/stockcar/build/tex%d.npy"%n,dn)
np.save(f"/home/claude/stockcar/build/keep{n}.npy",keep)
open(f"/home/claude/stockcar/build/track{n:02d}x.bin","wb").write(np.packbits(keep,axis=1).tobytes())
Image.fromarray((keep*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save(f"/home/claude/stockcar/build/track{n:02d}x.png")
print(n,keep.sum(),w.sum())
