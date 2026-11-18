# Trace the 24 track layouts from the reference screenshots into 1-bit wall masks.
import numpy as np, json, sys
from PIL import Image
from scipy import ndimage as ndi
sys.path.insert(0, "/home/claude/stockcar/tools")
from probe import load
W,H,S = 254,174,2.5
OUT="/home/claude/stockcar/build/"; import os; os.makedirs(OUT,exist_ok=True)
ZX=[(0,0,0),(0,0,215),(215,0,0),(215,0,215),(0,215,0),(0,215,215),(215,215,0),(215,215,215)]
info={}; sheet=Image.new("RGB",(W*6+7*4,(H)*4+5*4),(40,40,40))
for n in range(1,25):
    a=load(n); lum=a.max(axis=2)>60; ys,xs=np.nonzero(lum); x0,y0=xs.min(),ys.min()
    gx=np.clip((x0+(np.arange(W)+.5)*S).astype(int),0,a.shape[1]-1)
    gy=np.clip((y0+(np.arange(H)+.5)*S).astype(int),0,a.shape[0]-1)
    px=a[np.ix_(gy,gx)]
    col=((px[...,1]>110).astype(int)<<2)|((px[...,0]>110).astype(int)<<1)|(px[...,2]>110).astype(int)
    body=col.copy(); body[:10]=0                      # drop timer band
    cnt=np.bincount(body[body>0 & (body!=1)].ravel(),minlength=8); cnt[1]=0
    wc=int(cnt.argmax())
    m=(body==wc)
    lab,k=ndi.label(m,structure=np.ones((3,3)))
    keep=np.zeros_like(m); 
    for i,sl in enumerate(ndi.find_objects(lab),1):
        h=sl[0].stop-sl[0].start; w=sl[1].stop-sl[1].start
        if max(h,w)>=24: keep|=(lab==i)
    bar=np.argwhere(body==1)
    b=None
    if len(bar)>12: b=[int(bar[:,1].min()),int(bar[:,0].min()),int(bar[:,1].max()),int(bar[:,0].max())]
    info[n]={"wall_colour":wc,"blue_bar":b,"wall_px":int(keep.sum())}
    rows=np.zeros((176,256),bool); rows[:H,:W]=keep
    open(OUT+f"track{n:02d}.bin","wb").write(np.packbits(rows,axis=1).tobytes())
    t=Image.new("RGB",(W,H)); arr=np.zeros((H,W,3),np.uint8); arr[keep]=ZX[wc]
    if b: arr[b[1]:b[3]+1,b[0]:b[2]+1]=ZX[1]
    sheet.paste(Image.fromarray(arr),(4+((n-1)%6)*(W+4),4+((n-1)//6)*(H+4)))
json.dump(info,open(OUT+"tracks.json","w"),indent=1)
sheet.save(OUT+"contact.png"); print("done")
