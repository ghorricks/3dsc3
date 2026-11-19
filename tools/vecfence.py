# Vector fence builder: the drivable lane is the black region the car can reach inside the (closed) wall mask; its outline
# (outer wall + islands) is simplified to straight segments snapped to the iso directions (horizontal, vertical, 2:1) and redrawn 1 px wide.
import numpy as np, cv2, math
from scipy import ndimage as ndi
H,W=192,256
ROUND=False
CLEAN=True        # tracks 12+: free ends / level lines tidied; tracks 9 and 10 (already released) keep their original outlines
ANG_OLD=[0.0,math.pi/2,math.atan(0.5),math.pi-math.atan(0.5)]   # allowed edge directions (mod pi)
ANG_ISO=[0.0,math.pi/2,math.atan(0.5),math.pi-math.atan(0.5),math.pi-math.atan(4.0)]   # tracks 12+: the 3D 'vertical' fence runs 1 across for 4 down (the original's far-right fence); a fence that is truly plumb in the original stays plumb
SHEAR=math.pi-math.atan(4.0)
def _A(): return [0.0,math.atan(0.5),math.pi-math.atan(0.5),SHEAR,math.pi/2] if CLEAN else ANG_OLD
def _tol(a,default):                     # horizontals / 2:1 diagonals snap within 11 deg; the leaning and plumb 'vertical' fences only within 6 deg (any other shear stays as drawn)
    return math.radians(6) if (abs(a-math.pi/2)<1e-6 or abs(a-SHEAR)<1e-6) else default
def est_shear(Lm):
    """the track's own shear: length-weighted median angle of its long near-vertical (not plumb) lane edges"""
    global SHEAR
    cs,_=cv2.findContours(Lm.astype(np.uint8),cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE); sm=[]
    for c in cs:
        if len(c)<40: continue
        ap=cv2.approxPolyDP(c,1.8,True)[:,0,:].astype(float)
        for i in range(len(ap)):
            d=ap[(i+1)%len(ap)]-ap[i]; ln=math.hypot(*d)
            if ln<20: continue
            a=math.degrees(math.atan2(d[1],d[0]))%180
            if 70<=a<=115 and abs(a-90)>2.5: sm.append((a,ln))
    if sm:
        sm.sort(); tot=sum(l for _,l in sm); acc=0
        for a,l in sm:
            acc+=l
            if acc>=tot/2: SHEAR=math.radians(a); break
    return SHEAR
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
        best=min(_A(),key=lambda t:min(abs(ang-t),math.pi-abs(ang-t)))
        d=min(abs(ang-best),math.pi-abs(ang-best))
        if d<=_tol(best,tol): t=best
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
def flatten(P,maxjog=8,tol=6.0,closed=True):
    """hand-drawn / traced shapes: two near-horizontal edges joined by a tiny jog become ONE level line (same Y)"""
    P=[list(map(float,p)) for p in P]
    ch=True
    while ch and len(P)>(4 if closed else 3):
        ch=False; n=len(P)
        for i in range(n if closed else n-3):
            ia,ib,ic,id_=i,(i+1)%n,(i+2)%n,(i+3)%n
            a,b,c,d=P[ia],P[ib],P[ic],P[id_]
            e1=abs(b[1]-a[1])<=tol*0.5 and abs(b[0]-a[0])>=6
            e3=abs(d[1]-c[1])<=tol*0.5 and abs(d[0]-c[0])>=6
            jog=math.hypot(c[0]-b[0],c[1]-b[1])<maxjog and abs(c[1]-b[1])<=tol and (b[0]-a[0])*(d[0]-c[0])>0
            if e1 and e3 and jog:
                y=(a[1]*abs(b[0]-a[0])+d[1]*abs(d[0]-c[0]))/(abs(b[0]-a[0])+abs(d[0]-c[0]))
                a[1]=y; d[1]=y
                for k in sorted([ib,ic],reverse=True): P.pop(k)
                ch=True; break
    ch=True                                    # two level-ish edges meeting at a shallow angle: one straight edge
    while ch and len(P)>(4 if closed else 3):
        ch=False; n=len(P)
        for i in range(n if closed else n-2):
            a,b,c=P[i],P[(i+1)%n],P[(i+2)%n]
            if abs(b[0]-a[0])>=8 and abs(c[0]-b[0])>=8 and (b[0]-a[0])*(c[0]-b[0])>0 and abs(b[1]-a[1])<=3.5 and abs(c[1]-b[1])<=3.5 and abs(c[1]-a[1])<=4:
                y=(a[1]*abs(b[0]-a[0])+c[1]*abs(c[0]-b[0]))/(abs(b[0]-a[0])+abs(c[0]-b[0]))
                a[1]=y; c[1]=y; P.pop((i+1)%n); ch=True; break
    n=len(P)
    for i in range(n if closed else n-1):
        a,b=P[i],P[(i+1)%n]
        if abs(b[0]-a[0])>=8 and abs(b[1]-a[1])<=2.6:
            y=(a[1]+b[1])/2; a[1]=y; b[1]=y
    return [tuple(p) for p in P]
def merge_parallel(P,closed=True,maxjog=26,maxoff=8.0,minlen=8):
    """ONE fence: two edges running the same way, joined only by a small jog / kink (whatever their direction), become a single straight edge"""
    P=[list(map(float,p)) for p in P]
    def d_(a,b): return math.atan2(b[1]-a[1],b[0]-a[0])%math.pi
    def dif(x,y): q=abs(x-y)%math.pi; return min(q,math.pi-q)
    ch=True
    while ch:
        ch=False; n=len(P)
        for i in range(n if closed else n-2):
            for k in (1,2):
                if len(P)<(4+k if closed else 3+k): continue
                n=len(P); idx=[(i+t)%n for t in range(k+3)]
                if not closed and i+k+2>=n: continue
                a,b,c,d=P[idx[0]],P[idx[1]],P[idx[k+1]],P[idx[k+2]]
                l1=math.hypot(b[0]-a[0],b[1]-a[1]); l3=math.hypot(d[0]-c[0],d[1]-c[1])
                if l1<minlen or l3<minlen: continue
                path=sum(math.hypot(P[idx[t+1]][0]-P[idx[t]][0],P[idx[t+1]][1]-P[idx[t]][1]) for t in range(1,k+1))
                if path>maxjog: continue
                t1,t3=d_(a,b),d_(c,d)
                if dif(t1,t3)>math.radians(4): continue
                u=np.array([math.cos(t1),math.sin(t1)]); nrm=np.array([-u[1],u[0]])
                if abs(np.dot(np.array(c)-np.array(a),nrm))>maxoff: continue
                if np.dot(np.array(d)-np.array(a),u)*np.dot(np.array(b)-np.array(a),u)<0: continue
                o=(np.dot(a,nrm)*l1+np.dot(d,nrm)*l3)/(l1+l3)
                for q in (a,d):
                    sh=o-np.dot(q,nrm); q[0]+=nrm[0]*sh; q[1]+=nrm[1]*sh
                for j in sorted(idx[1:k+2],reverse=True): P.pop(j)
                ch=True; break
            if ch: break
    return [tuple(p) for p in P]
def sharpen(P,short=12,reach=16,closed=True):
    """a corner is a corner: the one or two tiny edges at a fence corner are its rounded pixels, so the two long edges just meet"""
    P=[list(map(float,p)) for p in P]
    ch=True
    while ch and len(P)>(4 if closed else 3):
        ch=False; n=len(P)
        for i in range(n if closed else n-3):
            for k in (1,2):
                if len(P)<=3+k: continue
                if not closed and i+k+2>=n: continue
                idx=[((i-1+t)%n if closed else i+t) for t in range(k+3)]          # a, b ... c, d
                a,b,c,d=P[idx[0]],P[idx[1]],P[idx[k+1]],P[idx[k+2]]
                path=sum(math.hypot(P[idx[t+1]][0]-P[idx[t]][0],P[idx[t+1]][1]-P[idx[t]][1]) for t in range(1,k+1))
                if path>=short or math.hypot(b[0]-a[0],b[1]-a[1])<12 or math.hypot(d[0]-c[0],d[1]-c[1])<12: continue
                u=np.array(b)-np.array(a); v=np.array(d)-np.array(c); den=u[0]*v[1]-u[1]*v[0]
                if abs(den)<1e-6*np.hypot(*u)*np.hypot(*v)+1e-9: continue
                t=((c[0]-a[0])*v[1]-(c[1]-a[1])*v[0])/den; q=np.array(a)+t*u
                if np.hypot(*(q-np.array(b)))>reach or np.hypot(*(q-np.array(c)))>reach: continue
                P[idx[1]]=[float(q[0]),float(q[1])]
                for j in sorted(idx[2:k+2],reverse=True): P.pop(j)
                ch=True; break
            if ch: break
    return [tuple(p) for p in P]
def clean_open(P,tol=math.radians(14)):
    """a free-standing wall: drop the little hook the skeleton leaves at each end, and make every segment run at an allowed angle"""
    P=[list(map(float,p)) for p in P]
    def ang(a,b): return math.atan2(b[1]-a[1],b[0]-a[0])%math.pi
    def dif(x,y): d=abs(x-y)%math.pi; return min(d,math.pi-d)
    for _ in range(3):
        if len(P)>=3 and math.hypot(P[-1][0]-P[-2][0],P[-1][1]-P[-2][1])<9 and dif(ang(P[-2],P[-1]),ang(P[-3],P[-2]))>math.radians(15): P.pop()
        if len(P)>=3 and math.hypot(P[1][0]-P[0][0],P[1][1]-P[0][1])<9 and dif(ang(P[0],P[1]),ang(P[1],P[2]))>math.radians(15): P.pop(0)
    # snap segments to the allowed directions (lines through segment midpoints, intersected; ends projected)
    n=len(P)
    if n<2: return P
    lines=[]
    for i in range(n-1):
        a=np.array(P[i]); b=np.array(P[i+1]); v=b-a; ln=np.hypot(*v); t=math.atan2(v[1],v[0])%math.pi
        best=min(_A(),key=lambda q:dif(t,q))
        if dif(t,best)<=_tol(best,tol): t=best
        lines.append(((a+b)/2,np.array([math.cos(t),math.sin(t)])))
    out=[]
    for j in range(n):
        if j==0 or j==n-1:
            p0,d0=lines[0 if j==0 else n-2]; q=np.array(P[j]); t=np.dot(q-p0,d0); out.append(tuple(p0+t*d0))
        else:
            (p0,d0),(p1,d1)=lines[j-1],lines[j]; den=d0[0]*d1[1]-d0[1]*d1[0]
            if abs(den)<1e-3: out.append(tuple(P[j]))
            else:
                t=((p1[0]-p0[0])*d1[1]-(p1[1]-p0[1])*d1[0])/den; q=p0+t*d0
                out.append(tuple(q) if np.hypot(*(q-np.array(P[j])))<=9 else tuple(P[j]))
    return flatten(out,closed=False)
def vec_base(m,seed,eps=1.8,widen=None):
    L,it=lane(m,seed)
    if widen: L=widen(L)
    base=np.zeros((H,W),bool); polys=[]
    cs,_=cv2.findContours(L.astype(np.uint8),cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
    for c in cs:
        if len(c)<20: continue
        ap=cv2.approxPolyDP(c,eps,True)[:,0,:].astype(float).tolist()
        if len(ap)<3: continue
        P=snap(ap)
        if widen: P=flatten(merge_parallel(P)) if ROUND else flatten(P)       # ROUND: the original's corners are curves (track 14): straighten the runs, keep the bends
        polys.append(P)
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
        elif abs(dx)<=2 and abs(dy)>=6 and not CLEAN: x=round((a[0]+b[0])/2); a[0]=b[0]=x
    return P
def _join_levels(APS):
    """two free walls that meet end to end along a horizontal line: the same Y, the same line"""
    for i in range(len(APS)):
        for j in range(len(APS)):
            if i==j: continue
            for ei in (0,-1):
                for ej in (0,-1):
                    A,B=APS[i],APS[j]; p,q=A[ei],B[ej]
                    if math.hypot(p[0]-q[0],p[1]-q[1])>8: continue
                    pa=A[1] if ei==0 else A[-2]; qb=B[1] if ej==0 else B[-2]
                    if abs(pa[1]-p[1])<=1.0 and abs(qb[1]-q[1])<=1.0 and abs(p[1]-q[1])<=5:
                        y=(p[1]+q[1])/2
                        for (L_,e_,o_) in ((A,ei,1 if ei==0 else -2),(B,ej,1 if ej==0 else -2)):
                            L_[e_]=[L_[e_][0],y]; L_[o_]=[L_[o_][0],y]
def vec_base2(m,seed,r=5,eps=1.8):
    L,it=lane(m,seed)
    Nn=~L
    if CLEAN: est_shear(L)
    pp=r+2; fat=ndi.binary_opening(np.pad(Nn,pp,constant_values=True),structure=disk(r))[pp:-pp,pp:-pp]
    thin=Nn&~fat
    lane2=~fat
    if m[:,W-4:].any(axis=1).sum()>=10: lane2[:,W-1]=False          # the original draws a wall right on the screen edge
    if m[:,:4].any(axis=1).sum()>=10: lane2[:,0]=False
    if m[H-4:,:].any(axis=0).sum()>=10: lane2[H-1,:]=False
    base,_,polys,_=vec_base_from(lane2); APS=[]
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
            ap=[list(q) for q in flatten(sharpen(merge_parallel(_level(clean_open(ap)),closed=False),closed=False),closed=False)] if CLEAN else _level(ap)
            APS.append(ap)
            rm=np.zeros((H,W),np.uint8); rm[P[:,1],P[:,0]]=1
            sk=sk&~ndi.binary_dilation(rm>0,iterations=2)
            sk=sk&ndi.binary_dilation(sk,structure=np.ones((3,3)))
    if CLEAN: _join_levels(APS)
    for ap in APS:
        for end in (0,-1):                                # attach a branch end to what is already drawn (gap <= 5 px)
            ex,ey=int(round(ap[end][0])),int(round(ap[end][1])); yy,xx=np.nonzero(base[max(ey-5,0):ey+6,max(ex-5,0):ex+6])
            if len(yy):
                q=np.argmin((xx-(ex-max(ex-5,0)))**2+(yy-(ey-max(ey-5,0)))**2); nx_,ny_=xx[q]+max(ex-5,0),yy[q]+max(ey-5,0); ox_,oy_=ap[end]; nb=ap[1] if end==0 else ap[-2]
                if not CLEAN: pass
                elif abs(nb[1]-oy_)<0.01: ny_=oy_                      # a level wall stays level (and a plumb one plumb) when its end is attached
                elif abs(nb[0]-ox_)<0.01: nx_=ox_
                ap[end]=[nx_,ny_]
        img=np.zeros((H,W),np.uint8); cv2.polylines(img,[np.round(np.array(ap)).astype(np.int32)],False,1,1); base|=img>0
    return base,lane2,polys,it
def vec_base_from(Lm,eps=1.8):
    base=np.zeros((H,W),bool); polys=[]
    cs,_=cv2.findContours(Lm.astype(np.uint8),cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
    for c in cs:
        if len(c)<20: continue
        ap=cv2.approxPolyDP(c,eps,True)[:,0,:].astype(float).tolist()
        if len(ap)<3: continue
        P=snap(ap)
        if CLEAN: P=flatten(sharpen(merge_parallel(P)))
        polys.append(P)
        img=np.zeros((H,W),np.uint8); cv2.polylines(img,[np.round(np.array(P)).astype(np.int32)],True,1,1); base|=img>0
    return base,Lm,polys,0

def widen_zone(polys,r,glob=0,protect=()):
    """grow the lane by r px, but only inside the given polygons (diagonal stretches): the extra width is taken from the grass"""
    def f(L):
        Z=np.zeros((H,W),np.uint8)
        for P in polys: cv2.fillPoly(Z,[np.array(P,np.int32)],1)
        g=ndi.binary_dilation(L,structure=disk(r))
        W2=L|(g&(Z>0))
        if glob:
            P=np.zeros((H,W),np.uint8)
            for Q in protect: cv2.fillPoly(P,[np.array(Q,np.int32)],1)
            W2=W2|(ndi.binary_dilation(L,structure=disk(glob))&(P==0))
        W2=ndi.binary_closing(np.pad(W2,8),structure=disk(4))[8:-8,8:-8]
        W2=ndi.binary_opening(np.pad(W2,8),structure=disk(3))[8:-8,8:-8]
        return W2|L
    return f
