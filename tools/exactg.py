# Exact fence mask for tracks 7-10 from the original game's own screen (median of frames removes the cars).
import sys,numpy as np
from PIL import Image
from scipy import ndimage as ndi
n=int(sys.argv[1]); col=tuple(int(v) for v in sys.argv[2].split(',')); minlen=int(sys.argv[3]) if len(sys.argv)>3 else 24
med=np.array(Image.open(f"/home/claude/stockcar/orig/track{n}_median.png"))
w=(med==col).all(2)
w[:9]=False
if n==7: w[:27,88:106]=False; w[:16,140:215]=False
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
np.save(f"/home/claude/stockcar/build/keep{n}.npy",keep)
open(f"/home/claude/stockcar/build/track{n:02d}x.bin","wb").write(np.packbits(keep,axis=1).tobytes())
Image.fromarray((keep*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save(f"/home/claude/stockcar/build/track{n:02d}x.png")
print(n,keep.sum(),w.sum())
