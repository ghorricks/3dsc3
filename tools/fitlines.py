import numpy as np
from PIL import Image
b=np.array(Image.open('build/base04.png'))>0
ys,xs=np.nonzero(b)
P=np.stack([xs,ys],1)
res=[]
def runs(sel,key,along):
    # group points by line offset, return segments
    out=[]
    pts=P[sel]
    return pts
for name,f,g in (('/',lambda p:p[:,1]+0.5*p[:,0],lambda p:p[:,0]),('\\',lambda p:p[:,1]-0.5*p[:,0],lambda p:p[:,0]),('|',lambda p:p[:,0].astype(float),lambda p:p[:,1])):
    c=f(P); 
    for c0 in np.arange(c.min(),c.max()+1,0.5):
        m=np.abs(c-c0)<=0.75
        if m.sum()<18: continue
        a=np.sort(g(P[m]))
        # split into runs with gaps >3
        st=0
        for i in range(1,len(a)+1):
            if i==len(a) or a[i]-a[i-1]>4:
                if a[i-1]-a[st]>=18: res.append((name,c0,a[st],a[i-1],i-st))
                st=i
for r in res: print(r)
