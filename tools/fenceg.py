# Straighten a 1-px fence skeleton: trace it between junctions/end points and replace every run by straight segments (Douglas-Peucker).
import numpy as np, cv2
from scipy import ndimage as ndi
def straighten(base,eps=1.6,minrun=5):
    b=base.astype(np.uint8); H,W=b.shape
    nb=ndi.convolve(b,np.ones((3,3),np.uint8),mode='constant')-b
    nodes=(b==1)&((nb!=2))                         # end points (1) and junctions (>=3)
    ys,xs=np.nonzero(b); pts=set(zip(ys.tolist(),xs.tolist())); node=set(zip(*np.nonzero(nodes)))
    node={(int(y),int(x)) for y,x in node}
    seen=set(); out=np.zeros((H,W),bool)
    N8=[(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
    def draw(path):
        a=np.array([[x,y] for y,x in path],np.int32).reshape(-1,1,2)
        ap=cv2.approxPolyDP(a,eps,False).reshape(-1,2)
        m=np.zeros((H,W),np.uint8)
        for i in range(len(ap)-1): cv2.line(m,tuple(int(v) for v in ap[i]),tuple(int(v) for v in ap[i+1]),1,1)
        if len(ap)==1: m[ap[0][1],ap[0][0]]=1
        return m.astype(bool)
    def nbrs(p): return [(p[0]+dy,p[1]+dx) for dy,dx in N8 if (p[0]+dy,p[1]+dx) in pts]
    for s in node:
        for q in nbrs(s):
            if (s,q) in seen: continue
            path=[s,q]; seen.add((s,q)); prev,cur=s,q
            while cur not in node:
                nx=[r for r in nbrs(cur) if r!=prev and r not in path[-3:]]
                if not nx: break
                # prefer 4-neighbours to avoid shortcutting corners
                nx.sort(key=lambda r:abs(r[0]-cur[0])+abs(r[1]-cur[1]))
                prev,cur=cur,nx[0]; path.append(cur)
            seen.add((cur,prev))
            if len(path)>=minrun or cur in node and s in node: out|=draw(path)
    # closed loops without nodes
    left=b.astype(bool)&~ndi.binary_dilation(out,iterations=2)
    lab,k=ndi.label(left,structure=np.ones((3,3)))
    for i in range(1,k+1):
        ys,xs=np.nonzero(lab==i)
        if len(ys)>=12:
            c=np.array([[x,y] for y,x in zip(ys,xs)],np.int32)
            hull=cv2.convexHull(c); m=np.zeros((H,W),np.uint8); cv2.polylines(m,[cv2.approxPolyDP(hull,eps,True)],True,1,1); out|=m.astype(bool)
    return out

def dropsmall(b,n=14):
    lab,k=ndi.label(b,structure=np.ones((3,3)))
    sz=np.bincount(lab.ravel()); sz[0]=0
    return b&(sz[lab]>=n)
def _erase(b,x0,x1,y0,y1): b[y0:y1+1,x0:x1+1]=False
def _line(b,pts):
    m=np.zeros(b.shape,np.uint8)
    for (x0,y0),(x1,y1) in zip(pts[:-1],pts[1:]): cv2.line(m,(int(x0),int(y0)),(int(x1),int(y1)),1,1)
    b|=m.astype(bool)
def edit8(b):
    _erase(b,0,255,0,14); _erase(b,253,255,30,62)
    _erase(b,78,206,30,41); _erase(b,33,93,58,69); _erase(b,180,244,57,69)
    _erase(b,62,192,84,97); _erase(b,8,222,163,181); _erase(b,106,124,134,150)
    _erase(b,240,255,12,22); _erase(b,20,44,10,22); _erase(b,44,52,10,15); _erase(b,20,29,23,37)
    _line(b,[(30,38),(34,33),(41,24),(50,18),(62,15),(112,15)])
    _line(b,[(250,32),(254,45),(252,59)]); _line(b,[(8,174),(16,181)]); _line(b,[(214,181),(222,172)])
    _line(b,[(141,44),(130,98)])
    _line(b,[(107,190),(121,121)]); _line(b,[(184,101),(171,161)])
    return dropsmall(b)
def edit9(b):
    _erase(b,58,82,138,155)
    _line(b,[(53,141),(60,149),(82,159),(100,165)])
    return dropsmall(b)
def edit7(b):
    _line(b,[(82,114),(104,163)])
    return dropsmall(b)
def edit14(b,h=9):
    B=np.load('/home/claude/stockcar/build/plat14.npy'); F=B.copy()
    for t in range(1,h+1): F&=np.roll(B,t,axis=0)       # footprint: wall bands rise h px above the base line
    edge=F&~ndi.binary_erosion(F,structure=np.ones((3,3)))
    return dropsmall(straighten(edge,eps=2.0) | b)
def edit13(b):
    _line(b,[(77,15),(214,15),(232,19),(246,26),(254,36)]); _line(b,[(30,42),(32,38),(34,34)])
    return dropsmall(b)
def edit_n(b): return dropsmall(b)
EDITS={8:edit8,9:edit9,7:edit7,10:edit_n,11:edit_n,12:edit_n,13:edit13,14:edit14}
