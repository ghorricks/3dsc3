import numpy as np
from PIL import Image
from scipy import ndimage as ndi
med=np.array(Image.open("/home/claude/stockcar/orig/track3_median.png").convert("RGB"))
w=(med==(0,205,205)).all(2)
w[:9]=False
w[33:45,199:208]=False       # flag
w[168:192,0:24]=False        # track number sign
w[78:115,90:166]=False       # raised platform in the middle (hatched): replaced by its footprint outline below
def line(x0,y0,x1,y1):
    n=max(abs(x1-x0),abs(y1-y0))
    for i in range(n+1):
        x=round(x0+(x1-x0)*i/n); y=round(y0+(y1-y0)*i/n); w[y,x]=True
L,T,R,B=(93,103),(127,86),(161,103),(127,120)
line(*L,*T); line(*T,*R); line(*R,*B); line(*B,*L)
lab,k=ndi.label(w,structure=np.ones((3,3)))
keep=np.zeros_like(w)
for i,sl in enumerate(ndi.find_objects(lab),1):
    if max(sl[0].stop-sl[0].start,sl[1].stop-sl[1].start)>=24: keep|=(lab==i)
open("/home/claude/stockcar/build/track03x.bin","wb").write(np.packbits(keep,axis=1).tobytes())
Image.fromarray((keep*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save("/home/claude/stockcar/build/track03x.png")
print(keep.sum())
