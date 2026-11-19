import sys; sys.path.insert(0,'/home/claude/stockcar/tools')
import numpy as np
from PIL import Image
from fenceg import straighten
n=int(sys.argv[1]); sc=int(sys.argv[2]) if len(sys.argv)>2 else 4
src=sys.argv[3] if len(sys.argv)>3 else None
b=np.load(f"/home/claude/stockcar/build/base{n}.npy"); o=straighten(b) if src is None else np.load(src)
med=np.array(Image.open(f"/home/claude/stockcar/orig/track{n}_median.png")).astype(int)//3
im=med.copy(); im[o]=(255,0,0)
Image.fromarray(im.astype(np.uint8)).resize((256*sc,192*sc),Image.NEAREST).save(f"/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/ov{n}.png")
