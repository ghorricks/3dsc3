# menu banner: tools/logo_new.png -> build/logo2.bin = 16 palette bytes (RGB332; entry 0 = transparent) + 172x24 at 4 bits a pixel, 86 bytes a row, left pixel in the high nibble
import numpy as np, os
from PIL import Image
W,H=164,23
D=os.path.dirname(os.path.abspath(__file__))
im=Image.open(os.path.join(D,"logo_new.png")).convert("RGB").resize((W,H),Image.LANCZOS)
a=np.array(im).reshape(-1,3).astype(float)
# the 3-3-2 colours the Next can show, and the 15 of them (plus black) that fit this banner best: k-means in RGB, then snapped to 3-3-2
rng=np.random.RandomState(1)
c=a[rng.choice(len(a),16,replace=False)].copy(); c[0]=0
def snap(p): 
    r=round(p[0]*7/255);g=round(p[1]*7/255);b=round(p[2]*3/255); return (r<<5)|(g<<2)|b,np.array([r*255/7,g*255/7,b*255/3])
for _ in range(25):
    k=((a[:,None,:]-c[None])**2).sum(2).argmin(1)
    for j in range(1,16):
        if (k==j).any(): c[j]=a[k==j].mean(0)
pal=[];cs=[]
for p in c: v,q=snap(p); pal.append(v); cs.append(q)
cs=np.array(cs); cs[0]=0; pal[0]=0
k=((a[:,None,:]-cs[None])**2).sum(2).argmin(1).reshape(H,W)
out=bytearray(pal)
for y in range(H):
    for x in range(0,W,2): out.append((k[y,x]<<4)|k[y,x+1])
open(os.path.join(D,"..","build","logo2.bin"),"wb").write(out)
print(pal,len(out))
Image.fromarray(np.array([[cs[v] for v in r] for r in k],dtype=np.uint8)).resize((W*4,H*4),Image.NEAREST).save("/tmp/logo2_prev.png")
