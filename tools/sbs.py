# side by side: original capture (left) and the current fence base lines + ground (right), 3x
import sys,numpy as np
from PIL import Image
sc='/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/'
n=int(sys.argv[1]); S=3
med=Image.open(f'orig/track{n}_median.png').convert('RGB').resize((256*S,192*S),Image.NEAREST)
b=np.load(f'build/basef{n}.npy'); g=np.load(f'build/ground{n}.npy')
im=np.zeros((192,256,3),np.uint8); im[:g.shape[0],:g.shape[1]][g]=(60,60,60); im[:b.shape[0],:b.shape[1]][b]=(255,255,255)
R=Image.fromarray(im).resize((256*S,192*S),Image.NEAREST)
W=Image.new('RGB',(256*S*2,192*S)); W.paste(med,(0,0)); W.paste(R,(256*S,0)); W.save(sc+f'sbs{n}.png')
