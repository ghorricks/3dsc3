# original capture with a coordinate grid (every 10 px, labelled every 20), 5x, optional crop x0 y0 x1 y1
import sys
from PIL import Image,ImageDraw
sc='/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/'
n=int(sys.argv[1]); S=5
x0,y0,x1,y1=(int(v) for v in sys.argv[2:6]) if len(sys.argv)>=6 else (0,0,256,192)
im=Image.open(f'orig/track{n}_median.png').convert('RGB').crop((x0,y0,x1,y1)).resize(((x1-x0)*S,(y1-y0)*S),Image.NEAREST)
d=ImageDraw.Draw(im)
for x in range((x0//10)*10,x1,10):
    if x<x0: continue
    d.line([((x-x0)*S,0),((x-x0)*S,(y1-y0)*S)],fill=(255,0,0) if x%20==0 else (90,0,0))
    if x%20==0: d.text(((x-x0)*S+2,2),str(x),fill=(255,255,0))
for y in range((y0//10)*10,y1,10):
    if y<y0: continue
    d.line([(0,(y-y0)*S),((x1-x0)*S,(y-y0)*S)],fill=(255,0,0) if y%20==0 else (90,0,0))
    if y%20==0: d.text((2,(y-y0)*S+2),str(y),fill=(255,255,0))
im.save(sc+f'grid{n}.png')
