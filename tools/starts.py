# Start positions (mask coords) + heading; flag-only tracks use pole base measured from the screenshots.
import numpy as np, json, sys
sys.path.insert(0,"/home/claude/stockcar/tools")
from probe import load
from PIL import Image, ImageDraw
W,H,S=254,174,2.5
info=json.load(open("/home/claude/stockcar/build/tracks.json"))
POLE={1:(518,145),2:(546,135),3:(523,145),4:(518,125),5:(283,97),6:(283,72),7:(262,90),
      14:(265,218),15:(406,100),16:(259,210),21:(518,112),22:(520,125),23:(262,87)}
sheet=Image.new("RGB",(W*6+28,H*4+20),(40,40,40))
for n in range(1,25):
    a=load(n); lum=a.max(axis=2)>60; ys,xs=np.nonzero(lum); x0,y0=xs.min(),ys.min()
    m=np.unpackbits(np.frombuffer(open(f"/home/claude/stockcar/build/track{n:02d}.bin","rb").read(),np.uint8).reshape(176,32),axis=1)[:H,:W].astype(bool)
    b=info[str(n)]["blue_bar"]
    if b: sx,sy=(b[0]+b[2])//2,(b[1]+b[3])//2
    else: px,py=POLE[n]; sx,sy=int((px-x0)/S),int((py-y0)/S)
    info[str(n)]["start"]=[sx,sy]
    im=Image.fromarray((m*255).astype(np.uint8)).convert("RGB"); d=ImageDraw.Draw(im)
    d.ellipse([sx-4,sy-4,sx+4,sy+4],outline=(255,0,0)); d.text((4,H-12),str(n),fill=(255,255,0))
    sheet.paste(im,(4+((n-1)%6)*(W+4),4+((n-1)//6)*(H+4)))
json.dump(info,open("/home/claude/stockcar/build/tracks.json","w"),indent=1)
sheet.save("/home/claude/stockcar/build/starts.png")
