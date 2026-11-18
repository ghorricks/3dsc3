# Exact track 5 fence mask from the original game's own screen (median of many frames removes the cars).
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
med=np.array(Image.open("/home/claude/stockcar/orig/track5_median.png"))
w=(med==(0,205,205)).all(2)
w[:9]=False                                  # timer header
w[12:28,100:112]=False                       # flag and pole above the top wall
w[172:,:22]=False                            # track number sign
lab,k=ndi.label(w,structure=np.ones((3,3)))
keep=np.zeros_like(w)
for i,sl in enumerate(ndi.find_objects(lab),1):
    if max(sl[0].stop-sl[0].start,sl[1].stop-sl[1].start)>=24: keep|=(lab==i)
open("/home/claude/stockcar/build/track05x.bin","wb").write(np.packbits(keep,axis=1).tobytes())
Image.fromarray((keep*255).astype(np.uint8)).resize((1024,768),Image.NEAREST).save("/home/claude/stockcar/build/track05x.png")
np.save("/home/claude/stockcar/build/keep5.npy",keep)
print(keep.sum(), w.sum())
