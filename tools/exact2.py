import numpy as np
from PIL import Image
from scipy import ndimage as ndi
med=np.array(Image.open("/home/claude/stockcar/orig/track2_median.png").convert("RGB"))
w=(med==(0,205,0)).all(2)
w[:9]=False
w[40:51,209:218]=False      # flag pole
w[168:192,0:24]=False       # track number sign
lab,k=ndi.label(w,structure=np.ones((3,3)))
keep=np.zeros_like(w)
for i,sl in enumerate(ndi.find_objects(lab),1):
    if max(sl[0].stop-sl[0].start,sl[1].stop-sl[1].start)>=24: keep|=(lab==i)
open("/home/claude/stockcar/build/track02x.bin","wb").write(np.packbits(keep,axis=1).tobytes())
Image.fromarray((keep*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save("/home/claude/stockcar/build/track02x.png")
print(keep.sum())
