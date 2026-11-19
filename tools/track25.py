# Track 25 - an original circuit (not in the 1988 game), designed on the isometric grid so every fence is an exact 2:1 line.
# World (a,b) -> screen x=a-b+X0, y=(a+b)/2+Y0.  Lane = union of rectangles round a centre line (width W); the fence is the outline of the union.
import numpy as np, json
from PIL import Image, ImageDraw
B="/home/claude/stockcar/build/"
W=30; X0=121; Y0=22
# centre line, a closed loop: long start straight with a kink (chicane), a fast right-hander, a hairpin and a back straight
CL=[(24,24),(120,24),(120,110),(24,110)]
CL=CL+[CL[0]]
def rect(p,q):
    (a0,b0),(a1,b1)=p,q
    return (min(a0,a1)-W//2,min(b0,b1)-W//2,max(a0,a1)+W//2,max(b0,b1)+W//2)
R=[rect(CL[i],CL[i+1]) for i in range(len(CL)-1)]
S=2                                                # grid cell = 2 world units
amax=max(r[2] for r in R)//S+3; bmax=max(r[3] for r in R)//S+3
cell=np.zeros((amax,bmax),bool)
for a0,b0,a1,b1 in R: cell[a0//S:a1//S,b0//S:b1//S]=True
TEETH=[(50,29,64,39),(82,9,96,19),(44,115,58,125),(78,95,92,105),(9,60,19,74)]    # chicane teeth cut out of the lane: (a0,b0,a1,b1)
for a0,b0,a1,b1 in TEETH: cell[a0//S:a1//S,b0//S:b1//S]=False
def proj(a,b): return (a-b+X0,(a+b)//2+Y0)
img=Image.new("L",(256,192),0); d=ImageDraw.Draw(img)
for i in range(amax):
    for j in range(bmax):
        if not cell[i,j]: continue
        a,b=i*S,j*S
        for di,dj,(p,q) in ((-1,0,((a,b),(a,b+S))),(1,0,((a+S,b),(a+S,b+S))),(0,-1,((a,b),(a+S,b))),(0,1,((a,b+S),(a+S,b+S)))):
            ni,nj=i+di,j+dj
            if not(0<=ni<amax and 0<=nj<bmax) or not cell[ni,nj]:
                d.line([proj(*p),proj(*q)],fill=255)
m=np.array(img)>0
ys,xs=np.nonzero(m); print("fence px",m.sum(),"x",xs.min(),xs.max(),"y",ys.min(),ys.max())
open(B+"track25x.bin","wb").write(np.packbits(m,axis=1).tobytes())
np.save(B+"fence25.npy",m)
sx,sy=proj(120,56)
t=json.load(open(B+"tracks.json")); t["25"]={"wall_colour":3,"blue_bar":None,"wall_px":int(m.sum()),"start":[sx,sy]}
json.dump(t,open(B+"tracks.json","w"))
print("start",sx,sy)
Image.fromarray((m*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save("/tmp/t25.png")
