# Track 25 - an original circuit (not in the 1988 game): a four-leg serpentine with a return lane, fences are exact horizontals and verticals.
# Lane = union of rectangles (screen pixels); the fence is the outline of that region.
import numpy as np, json
from PIL import Image
B="/home/claude/stockcar/build/"
H,Wd=192,256
LW=24                                  # lane width
Y=[40,76,112,148]                      # leg centres (pitch 36: lane 24 + wall 12)
XL,XR=24,232                           # left return lane / right connectors (centres)
XC=60                                  # R2 -> R3 connector (centre)
hw=LW//2
reg=np.zeros((H,Wd),bool)
def lane(x0,y0,x1,y1): reg[min(y0,y1)-hw if y0==y1 else min(y0,y1):max(y0,y1)+hw+1 if y0==y1 else max(y0,y1)+1,min(x0,x1)-hw if x0==x1 else min(x0,x1):max(x0,x1)+hw+1 if x0==x1 else max(x0,x1)+1]=True
def hleg(y,xa,xb): reg[y-hw:y+hw+1,min(xa,xb)-hw:max(xa,xb)+hw+1]=True
def vleg(x,ya,yb): reg[min(ya,yb)-hw:max(ya,yb)+hw+1,x-hw:x+hw+1]=True
hleg(Y[0],XL,XR); vleg(XR,Y[0],Y[1])
hleg(Y[1],XR,XC); vleg(XC,Y[1],Y[2])
hleg(Y[2],XC,XR); vleg(XR,Y[2],Y[3])
hleg(Y[3],XR,XL); vleg(XL,Y[3],Y[0])
# chicane teeth cut out of the lanes: (x0,y0,x1,y1) inclusive
D=6                                    # tooth depth (the gap left in a lane is then 18)
TEETH=[(190,Y[0]-hw,202,Y[0]-hw+D),(140,Y[0]+hw-D,152,Y[0]+hw),       # leg 1: outer wall, then the slab
       (190,Y[1]-hw,202,Y[1]-hw+D),(120,Y[1]+hw-D,132,Y[1]+hw),       # leg 2
       (140,Y[2]-hw,152,Y[2]-hw+D),(190,Y[2]+hw-D,202,Y[2]+hw),       # leg 3
       (90,Y[3]-hw,102,Y[3]-hw+D),(170,Y[3]+hw-D,182,Y[3]+hw)]        # leg 4
for x0,y0,x1,y1 in TEETH: reg[y0:y1+1,x0:x1+1]=False
er=np.zeros_like(reg); er[1:-1,1:-1]=reg[1:-1,1:-1]&reg[:-2,1:-1]&reg[2:,1:-1]&reg[1:-1,:-2]&reg[1:-1,2:]
m=reg&~er                                  # 1-px outline
ys,xs=np.nonzero(m); print("fence px",m.sum(),"x",xs.min(),xs.max(),"y",ys.min(),ys.max())
open(B+"track25x.bin","wb").write(np.packbits(m,axis=1).tobytes())
np.save(B+"fence25.npy",m)
sx,sy=90,Y[0]
t=json.load(open(B+"tracks.json")); t["25"]={"wall_colour":3,"blue_bar":None,"wall_px":int(m.sum()),"start":[sx,sy]}
json.dump(t,open(B+"tracks.json","w"))
Image.fromarray((m*255).astype(np.uint8)).resize((768,576),Image.NEAREST).save("/tmp/t25.png")
