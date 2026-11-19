import sys,numpy as np
from PIL import Image
sc='/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/'
n=int(sys.argv[1]); x0,y0,x1,y1=map(int,sys.argv[2:6]); S=int(sys.argv[6]) if len(sys.argv)>6 else 8
s=np.load(f'/home/claude/stockcar/build/solid{n}.npy').astype(bool); med=np.array(Image.open(f'/home/claude/stockcar/orig/track{n}_median.png'))
a=med[y0:y1,x0:x1].copy(); b=(med//3).copy(); b[s]=(255,0,0); b=b[y0:y1,x0:x1]
W=Image.new('RGB',((x1-x0)*S*2+10,(y1-y0)*S))
W.paste(Image.fromarray(a.astype(np.uint8)).resize(((x1-x0)*S,(y1-y0)*S),Image.NEAREST),(0,0))
W.paste(Image.fromarray(b.astype(np.uint8)).resize(((x1-x0)*S,(y1-y0)*S),Image.NEAREST),((x1-x0)*S+10,0))
W.save(sc+'cr.png')
