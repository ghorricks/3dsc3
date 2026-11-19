# Vector fence builder: the drivable lane is the black region the car can reach inside the (closed) wall mask; its outline
# (outer wall + islands) is simplified to straight segments snapped to the iso directions (horizontal, vertical, 2:1) and redrawn 1 px wide.
import numpy as np, cv2, math
from scipy import ndimage as ndi
H,W=192,256
ANG=[0.0,math.pi/2,math.atan(0.5),math.pi-math.atan(0.5)]   # allowed edge directions (mod pi)
def lane(m,seed,top=9):
    mp=np.pad(m,6,constant_values=False)
    for it in (2,3,4,5):
        c=ndi.binary_closing(mp,structure=np.ones((3,3)),iterations=it)[6:-6,6:-6]
        free=~c; free[:top,:]=False
        lab,_=ndi.label(free)
        sx,sy=seed
        if lab[sy,sx]==0:                                   # nearest free pixel
            ys,xs=np.nonzero(lab>0); k=np.argmin((xs-sx)**2+(ys-sy)**2); sx,sy=xs[k],ys[k]
        L=lab==lab[sy,sx]
        border=L[top,:].any() or L[-1,:].any() or L[:,0].any() or L[:,-1].any()
        if not border: return L,it
    return L,-1
def snap(P,tol=math.radians(11),minlen=3):
    n=len(P); lines=[]
    for i in range(n):
        a=np.array(P[i],float); b=np.array(P[(i+1)%n],float); v=b-a; ln=np.hypot(*v)
        ang=math.atan2(v[1],v[0])%math.pi
        best=min(ANG,key=lambda t:min(abs(ang-t),math.pi-abs(ang-t)))
        d=min(abs(ang-best),math.pi-abs(ang-best))
        if d<=tol: t=best
        else: t=ang
        lines.append(((a+b)/2,np.array([math.cos(t),math.sin(t)]),ln,d<=tol))
    out=[]
    for j in range(n):
        p0,d0,_,_=lines[j-1]; p1,d1,_,_=lines[j]
        den=d0[0]*d1[1]-d0[1]*d1[0]
        if abs(den)<1e-3: out.append(tuple(P[j]))
        else:
            t=((p1[0]-p0[0])*d1[1]-(p1[1]-p0[1])*d1[0])/den
            q=p0+t*d0
            if np.hypot(*(q-np.array(P[j])))>9: q=np.array(P[j],float)     # far-off intersection: keep the traced corner
            out.append((float(q[0]),float(q[1])))
    return out
def vec_base(m,seed,eps=1.8):
    L,it=lane(m,seed)
    base=np.zeros((H,W),bool); polys=[]
    cs,_=cv2.findContours(L.astype(np.uint8),cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
    for c in cs:
        if len(c)<20: continue
        ap=cv2.approxPolyDP(c,eps,True)[:,0,:].astype(float).tolist()
        if len(ap)<3: continue
        P=snap(ap); polys.append(P)
        img=np.zeros((H,W),np.uint8)
        pts=np.round(np.array(P)).astype(np.int32)
        cv2.polylines(img,[pts],True,1,1)
        base|=img>0
    return base,L,polys,it
if __name__=="__main__":
    import sys,json
    from PIL import Image
    n=int(sys.argv[1]); info=json.load(open('build/tracks.json'))
    b=np.frombuffer(open(f'build/track{n:02d}x.bin','rb').read(),np.uint8).reshape(192,32); m=np.unpackbits(b,axis=1).astype(bool)
    seed=tuple(info[str(n)]['start'])
    base,L,polys,it=vec_base(m,seed); print('closing',it,'lane px',L.sum(),'polys',len(polys),[len(p) for p in polys])
    np.save(f'build/vec{n}.npy',base)
    S=3; med=Image.open(f'orig/track{n}_median.png').convert('RGB').resize((256*S,192*S),Image.NEAREST)
    im=np.zeros((192,256,3),np.uint8); im[L]=(50,50,50); im[base]=(255,255,255)
    R=Image.fromarray(im).resize((256*S,192*S),Image.NEAREST)
    Wd=Image.new('RGB',(256*S*2,192*S)); Wd.paste(med,(0,0)); Wd.paste(R,(256*S,0))
    Wd.save('/tmp/claude-0/-home-claude/75bc9376-5fde-5ee5-97ba-f2e8c55057d5/scratchpad/vec%d.png'%n)
