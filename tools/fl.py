import sys,numpy as np,json
from PIL import Image
from scipy import ndimage as ndi
from collections import deque
sc='/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/'
n=int(sys.argv[1]); er=int(sys.argv[2]) if len(sys.argv)>2 else 0
k=np.load(f'build/keep{n}.npy'); j=json.load(open('build/tracks.json')); sx,sy=j[str(n)]['start']
try: h=np.load(f'build/hatch{n}.npy')
except Exception: h=np.zeros_like(k)
wall=ndi.binary_closing(k,np.ones((3,3)))|h
wall=ndi.binary_dilation(wall,iterations=er) if er else wall
lab,m=ndi.label(~wall,structure=np.array([[0,1,0],[1,1,1],[0,1,0]]))
l=lab[sy,sx]; print('label',l,'size',(lab==l).sum())
med=np.array(Image.open(f'orig/track{n}_median.png'))//3
im=med.copy(); im[lab==l]=(0,0,200); im[wall&~(med.sum(2)>0)]=(255,0,0)
Image.fromarray(im.astype(np.uint8)).resize((768,576),Image.NEAREST).save(sc+'fl.png')
