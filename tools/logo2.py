# menu banner: tools/logo_new.png -> build/logo2.bin = 4 palette bytes (RGB332) + 172x24 at 2 bits a pixel, 43 bytes a row, leftmost pixel in the top bits
import numpy as np, os
from PIL import Image
W,H=172,24
D=os.path.dirname(os.path.abspath(__file__))
im=Image.open(os.path.join(D,"logo_new.png")).convert("RGB").resize((W,H),Image.LANCZOS)
a=np.array(im).reshape(-1,3).astype(float)
c=np.array([[0,0,0],[225,225,220],[225,150,10],[120,110,100]],float)   # black, light stone, orange, shaded stone
for _ in range(12):
    d=((a[:,None,:]-c[None])**2).sum(2); k=d.argmin(1)
    for j in range(1,4):
        if (k==j).any(): c[j]=a[k==j].mean(0)
k=d.argmin(1)
pal=[(round(p[0]*7/255)<<5)|(round(p[1]*7/255)<<2)|round(p[2]*3/255) for p in c]
pal=[0,0xFF,0xF4,0xB6]   # brighter than the nearest 3-3-2 mix
out=bytearray(pal)
k=k.reshape(H,W)
for y in range(H):
    for x in range(0,W,4):
        out.append((k[y,x]<<6)|(k[y,x+1]<<4)|(k[y,x+2]<<2)|k[y,x+3])
open(os.path.join(D,"..","build","logo2.bin"),"wb").write(out)
print(pal,len(out))
Image.fromarray(np.array([[c[v] for v in r] for r in k],dtype=np.uint8)).resize((W*4,H*4),Image.NEAREST).save("/tmp/logo2_prev.png")
