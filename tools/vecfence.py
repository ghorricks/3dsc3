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

# ---- version 2: free-standing thin walls (the original draws them as a band) become ONE centre line instead of a double outline
from skimage.morphology import skeletonize, disk
def _longest_path(sk):
    ys,xs=np.nonzero(sk); pts=set(zip(xs.tolist(),ys.tolist()))
    if len(pts)<2: return []
    def bfs(s):
        prev={s:None}; q=[s]; last=s
        for p in q:
            last=p
            for dx in(-1,0,1):
                for dy in(-1,0,1):
                    n=(p[0]+dx,p[1]+dy)
                    if n in pts and n not in prev: prev[n]=p; q.append(n)
        return last,prev
    a,_=bfs(next(iter(pts))); b,prev=bfs(a)
    path=[]; p=b
    while p is not None: path.append(p); p=prev[p]
    return path
def _level(P):                                  # snap near-horizontal / near-vertical segments exactly
    P=[list(map(float,p)) for p in P]
    for i in range(len(P)-1):
        a,b=P[i],P[i+1]; dx,dy=b[0]-a[0],b[1]-a[1]
        if abs(dy)<=2 and abs(dx)>=6: y=round((a[1]+b[1])/2); a[1]=b[1]=y
        elif abs(dx)<=2 and abs(dy)>=6: x=round((a[0]+b[0])/2); a[0]=b[0]=x
    return P
def vec_base2(m,seed,r=5,eps=1.8):
    L,it=lane(m,seed)
    Nn=~L
    pp=r+2; fat=ndi.binary_opening(np.pad(Nn,pp,constant_values=True),structure=disk(r))[pp:-pp,pp:-pp]
    thin=Nn&~fat
    lane2=~fat
    if m[:,W-4:].any(axis=1).sum()>=10: lane2[:,W-1]=False          # the original draws a wall right on the screen edge
    if m[:,:4].any(axis=1).sum()>=10: lane2[:,0]=False
    if m[H-4:,:].any(axis=0).sum()>=10: lane2[H-1,:]=False
    base,_,polys,_=vec_base_from(lane2)
    lab,k=ndi.label(thin,structure=np.ones((3,3)))
    for i in range(1,k+1):
        comp=lab==i
        if comp.sum()<25: continue
        if comp[0,:].any() or comp[-1,:].any() or comp[:,0].any() or comp[:,-1].any(): continue
        sk=skeletonize(comp); first=True
        for _ in range(12):                                   # branch after branch: longest path, remove it, repeat
            if sk.sum()<6: break
            path=_longest_path(sk)
            if len(path)<(8 if first else 6): break
            first=False
            P=np.array(path,np.int32)
            ap=cv2.approxPolyDP(P.reshape(-1,1,2),eps,False)[:,0,:].tolist()
            ap=_level(ap)
            for end in (0,-1):                                # attach a branch end to what is already drawn (gap <= 5 px)
                ex,ey=int(round(ap[end][0])),int(round(ap[end][1])); yy,xx=np.nonzero(base[max(ey-5,0):ey+6,max(ex-5,0):ex+6])
                if len(yy):
                    q=np.argmin((xx-(ex-max(ex-5,0)))**2+(yy-(ey-max(ey-5,0)))**2); ap[end]=[xx[q]+max(ex-5,0),yy[q]+max(ey-5,0)]
            img=np.zeros((H,W),np.uint8); cv2.polylines(img,[np.round(np.array(ap)).astype(np.int32)],False,1,1); base|=img>0
            rm=np.zeros((H,W),np.uint8); rm[P[:,1],P[:,0]]=1
            sk=sk&~ndi.binary_dilation(rm>0,iterations=2)
            sk=sk&ndi.binary_dilation(sk,structure=np.ones((3,3)))
    return base,lane2,polys,it
def vec_base_from(Lm,eps=1.8):
    base=np.zeros((H,W),bool); polys=[]
    cs,_=cv2.findContours(Lm.astype(np.uint8),cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
    for c in cs:
        if len(c)<20: continue
        ap=cv2.approxPolyDP(c,eps,True)[:,0,:].astype(float).tolist()
        if len(ap)<3: continue
        P=snap(ap); polys.append(P)
        img=np.zeros((H,W),np.uint8); cv2.polylines(img,[np.round(np.array(P)).astype(np.int32)],True,1,1); base|=img>0
    return base,Lm,polys,0
