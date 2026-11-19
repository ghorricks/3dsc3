import sys,re,subprocess,json,numpy as np
from PIL import Image,ImageDraw
sc='/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/'
ns=[int(a) for a in sys.argv[1:]]
out=subprocess.run("cd /home/claude/stockcar && DUMPP=%s python3 tools/build_data.py"%",".join(map(str,ns)),shell=True,capture_output=True,text=True).stdout
S=3
W=Image.new('RGB',(256*S*len(ns),192*S))
for i,n in enumerate(ns):
    med=np.array(Image.open(f'orig/track{n}_median.png')).astype(int)//3
    solid=np.load(f'build/solid{n}.npy').astype(bool); g=np.load(f'build/ground{n}.npy').astype(bool)
    im=med.copy(); im[g&~solid]=(im[g&~solid]+np.array([0,0,60])).clip(0,255); im[solid]=(255,0,0)
    I=Image.fromarray(im.astype(np.uint8)).resize((256*S,192*S),Image.NEAREST); d=ImageDraw.Draw(I)
    m=re.search(r'P %d (\d+) (\[.*\])'%n,out)
    if m:
        pts=eval(m.group(2))
        for j,(x,y) in enumerate(pts): d.ellipse([x*S-2,y*S-2,x*S+2,y*S+2],fill=(255,255,0) if j else (0,255,0))
        d.text((6,6),'%d  %s pts'%(n,m.group(1)),fill=(255,255,255))
    W.paste(I,(i*256*S,0))
W.save(sc+'pv.png')
