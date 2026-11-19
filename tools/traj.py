import sys,numpy as np,glob
from PIL import Image
from scipy import ndimage as ndi
sc='/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/'
n=int(sys.argv[1]); S=3
fs=sorted(glob.glob(f'/tmp/cap/t{n}/*.ppm'))
med=np.array(Image.open(f'orig/track{n}_median.png')).astype(int)
im=np.array(Image.fromarray((med//3).astype(np.uint8)).resize((256*S,192*S),Image.NEAREST))
cols={}
for k in range(14,len(fs),3):
    f=np.array(Image.open(fs[k]).convert('RGB')).astype(int)
    d=(np.abs(f-med).sum(2)>0); d[:10]=False; d[184:]=False
    lab,m=ndi.label(ndi.binary_dilation(d,iterations=3))
    for i in range(1,m+1):
        ys,xs=np.nonzero(d&(lab==i))
        if len(ys)<12: continue
        x,y=int(xs.mean()),int(ys.mean())
        c=(255*(k%2==0),255*((k//2)%2),255*(k<60)) if False else (255,int(255*k/len(fs)),int(255*(1-k/len(fs))))
        im[y*S-2:y*S+3,x*S-2:x*S+3]=c
Image.fromarray(im).save(sc+'traj.png')
