import numpy as np, sys
from PIL import Image
D="/mnt/user-data/attachments/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/"
IDS="8a1e72f2 ee29dc00 7851fd0b 782da5c9 8e74febc 856f3ce9 57fd4d1f dcdeaced 2952729a 441a559b 80548b87 079a09c2 450ccd1f 40f4a236 b2048b90 1e81f640 c3b17a61 2089896e c7db280d 433f7bcb d628f1c9 5ff7ab43 f89cb8e4 ed42d13f".split()
def load(n): return np.array(Image.open(D+IDS[n-1]+"-image.png").convert("RGB"))
if __name__=="__main__":
    for n in (1,8,24):
        a=load(n); lum=a.max(axis=2)>60
        ys,xs=np.nonzero(lum)
        print(n,a.shape,"bbox x",xs.min(),xs.max(),"y",ys.min(),ys.max())
        top=lum[:50]; ty,tx=np.nonzero(top); print("  timer band x",tx.min(),tx.max(),"y",ty.min(),ty.max())
        # run lengths along a row of the timer text
        r=lum[ty.min()+10]; runs=[];c=0
        for v in r:
            if v: c+=1
            elif c: runs.append(c);c=0
        print("  runs",sorted(set(runs))[:12])
