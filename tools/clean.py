# Clean fence extraction: base lines (bottom edge of each traced fence), gap repair, ground plane, preview renderer.
import numpy as np, math
from scipy import ndimage as ndi
from PIL import Image, ImageDraw
W,H=254,174
FH=5   # fence height in px

def bottom_edge(m):
    below=np.zeros_like(m); below[:-1]=m[1:]
    return m & ~below

def remove_poles(m):
    """drop flag poles / signposts: tall thin vertical runs with nothing beside them"""
    m=m.copy()
    for x in range(1,W-1):
        y=0
        while y<H:
            if m[y,x]:
                y0=y
                while y<H and m[y,x]: y+=1
                if y-y0>=8:
                    mid=slice(y0+2,y-2)
                    side=m[mid,max(x-2,0):x].any() or m[mid,x+1:x+3].any()
                    if not side: m[y0:y,x]=False
            else: y+=1
    return m

def vclose(m):
    """fill the open panel between a fence's rails so each fence is one solid band"""
    return ndi.binary_closing(np.pad(m,8),structure=np.ones((FH+3,1)))[8:-8,8:-8] | m

def panel_of(base):
    p=base.copy()
    for k in range(1,FH+1):
        sh=np.zeros_like(base); sh[:-k]=base[k:]; p|=sh
    return p

def ground_k(base,seed=None):
    """inside-the-outer-fence region. Returns (ground bool plane, k, how)."""
    from scipy.spatial import ConvexHull
    pan=panel_of(base)
    pts=np.argwhere(pan)[:,::-1]; hull=ConvexHull(pts); hp=[tuple(int(v) for v in pts[i]) for i in hull.vertices]
    hi=Image.new("L",(W,H),0); ImageDraw.Draw(hi).polygon(hp,fill=1); hullm=np.array(hi,bool)
    for k in range(1,13):
        bar=ndi.binary_dilation(pan,iterations=k)
        lab,_=ndi.label(~bar)
        border=(set(np.unique(lab[0]))|set(np.unique(lab[-1]))|set(np.unique(lab[:,0]))|set(np.unique(lab[:,-1])))-{0}
        outside=np.isin(lab,list(border)); interior=~outside
        seed_ok=seed is not None and not outside[min(seed[1],H-1),min(seed[0],W-1)] and interior.sum()>=0.55*hullm.sum()
        if interior.sum()>=0.93*hullm.sum() or seed_ok: 
            og=ndi.binary_dilation(outside,iterations=min(k,2)) & ~pan
            return ~og,k,"closed"
    return hullm|pan,0,"hull"

def base_lines(mv):
    """base (ground) line of every fence: bottom edge, full length of steep runs, outline+hatch of solid platforms"""
    b=bottom_edge(mv)
    # steep fences: long vertical runs -> base is everything below the top FH rows of the run
    for x in range(W):
        y=0
        while y<H:
            if mv[y,x]:
                y0=y
                while y<H and mv[y,x]: y+=1
                if y-y0>FH+3: b[y0+FH:y,x]=True
            else: y+=1
    # solid platforms (dense hatched infield): outline ring + horizontal hatch lines
    blob=ndi.binary_opening(mv,structure=np.ones((9,9)))
    lb,nb_=ndi.label(blob)
    for i in range(1,nb_+1):
        if (lb==i).sum()<170: blob[lb==i]=False
    if blob.any():
        blob=ndi.binary_dilation(blob,iterations=1) & mv
        ring=blob & ~ndi.binary_erosion(blob)
        b|=ring
        # the blob's own raw bottom edge is replaced by its ring
    return b

def repair(m):
    """close small gaps in the traced wall mask, then bridge gaps along the convex-hull outline"""
    from scipy.spatial import ConvexHull
    mc=ndi.binary_closing(np.pad(m,6),structure=np.ones((3,3)),iterations=2)[6:-6,6:-6] | m
    pts=np.argwhere(mc)[:,::-1]; hull=ConvexHull(pts); hp=[tuple(int(v) for v in pts[i]) for i in hull.vertices]
    ol=Image.new("L",(W,H),0); d=ImageDraw.Draw(ol); d.polygon(hp,outline=1); outline=np.array(ol,bool)
    near=ndi.binary_dilation(mc,iterations=3)
    # ordered outline walk: bridge runs of 'no wall nearby' shorter than 46 px between wall-adjacent ends
    seq=[]
    for i in range(len(hp)):
        (x0,y0),(x1,y1)=hp[i],hp[(i+1)%len(hp)]
        n=max(abs(x1-x0),abs(y1-y0),1)
        for t in range(n): seq.append((int(round(x0+(x1-x0)*t/n)),int(round(y0+(y1-y0)*t/n))))
    flag=[bool(near[min(y,H-1),min(x,W-1)]) for x,y in seq]
    out=mc.copy(); n=len(seq); i=0
    while i<n:
        if not flag[i]:
            j=i
            while j<n and not flag[j]: j+=1
            run=j-i
            if 0<i and j<n and run<=46:
                for x,y in seq[i:j]:
                    if 0<=x<W and 0<=y<H:
                        out[y,x]=True; out[min(y+1,H-1),x]=True
            i=j
        else: i+=1
    return out

def ground_from(base):
    """inside-the-outer-fence region (True = inside); thin fences: dilate, fill, trim back"""
    barrier=ndi.binary_dilation(base|ndi.binary_dilation(base,structure=np.array([[0,1,0]]).T,iterations=FH),iterations=1)
    lab,_=ndi.label(~np.pad(barrier,1),structure=np.ones((3,3)))
    outside=(lab==lab[0,0])[1:-1,1:-1]
    return ~outside

def render(base,ground,wall,road=(70,70,70),H_=FH):
    img=np.zeros((H,W,3),np.uint8); dist=np.full(W,255,int)
    lo=tuple(int(c*0.55) for c in wall); hi=tuple(min(255,int(c*1.0+60)) for c in wall)
    for y in range(H-1,-1,-1):
        for x in range(W):
            if base[y,x]: dist[x]=0; img[y,x]=lo; continue
            dist[x]=min(dist[x]+1,255)
            if dist[x]<=H_:
                img[y,x]=hi if dist[x]==H_ else (hi if x%8==0 else wall)
            elif ground[y,x]: img[y,x]=road
    return img


def drop_stray(base,ground):
    """remove fence fragments that sit entirely outside the track"""
    out=base.copy(); lab,n=ndi.label(base,structure=np.ones((3,3)))
    pan_all=panel_of(base); road_in=ground & ~ndi.binary_dilation(pan_all,iterations=1)
    for i in range(1,n+1):
        comp=(lab==i); cp=panel_of(comp)
        nb=ndi.binary_dilation(cp,iterations=6)&~pan_all
        if nb.sum()<8: continue
        if (nb&road_in).sum()/nb.sum()<0.15: out[comp]=False
    return out


def straighten(base, eps=1.6, spur=6):
    """fences are straight lines meeting at corners: skeletonise, trace chains between junctions/ends,
    simplify each chain to a polyline and redraw it with 1-px lines."""
    import cv2
    from skimage.morphology import skeletonize
    sk=skeletonize(base)
    k=np.ones((3,3),int); k[1,1]=0
    deg=ndi.convolve(sk.astype(int),k,mode="constant")*sk
    node=sk&((deg==1)|(deg>=3))
    lab,ng=ndi.label(node,structure=np.ones((3,3)))
    cent={}
    for g in range(1,ng+1):
        ys,xs=np.nonzero(lab==g); cent[g]=(int(round(xs.mean())),int(round(ys.mean())))
    isend={g:bool((deg[lab==g]==1).all()) for g in range(1,ng+1)}
    out=np.zeros((H,W),np.uint8)
    visited=np.zeros((H,W),bool)
    nbr=[(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
    def nbs(y,x):
        for dy,dx in nbr:
            yy,xx=y+dy,x+dx
            if 0<=yy<H and 0<=xx<W and sk[yy,xx]: yield yy,xx
    def draw(pts):
        if len(pts)<2: return
        a=np.array(pts,np.int32).reshape(-1,1,2)
        ap=cv2.approxPolyDP(a,eps,False)
        cv2.polylines(out,[ap],False,1,1)
    for g in range(1,ng+1):
        for (py,px) in zip(*np.nonzero(lab==g)):
            for (qy,qx) in nbs(py,px):
                if node[qy,qx] or visited[qy,qx]: continue
                path=[cent[g]]; cur=(qy,qx); end=None
                while True:
                    visited[cur]=True; path.append((cur[1],cur[0]))
                    nxt=None; hit=None
                    for (yy,xx) in nbs(*cur):
                        if node[yy,xx] and lab[yy,xx]!=g or (node[yy,xx] and len(path)>3 and lab[yy,xx]==g): hit=lab[yy,xx]; break
                    if hit is not None: end=hit; break
                    for (yy,xx) in nbs(*cur):
                        if not visited[yy,xx] and not node[yy,xx]: nxt=(yy,xx); break
                    if nxt is None: break
                    cur=nxt
                if end is not None: path.append(cent[end])
                short=len(path)<spur and (isend[g] or (end is not None and isend[end]) or end is None)
                if not short: draw(path)
    # node-only bits and closed loops
    rest=sk&~visited&~node
    lab2,n2=ndi.label(rest,structure=np.ones((3,3)))
    for i in range(1,n2+1):
        ys,xs=np.nonzero(lab2==i)
        if len(ys)>=spur: 
            pts=np.array(list(zip(xs,ys)),np.int32)
            hull=cv2.convexHull(pts) if len(ys)>20 else pts
            cv2.polylines(out,[hull.reshape(-1,1,2)],True,1,1)
    # tiny junction groups keep their centroid so crossings stay joined
    for g in range(1,ng+1): out[cent[g][1],cent[g][0]]=1
    res=out.astype(bool)
    miss=base&~ndi.binary_dilation(res,iterations=2)        # anything the tracing dropped: keep it so no gaps appear
    return res|miss

def hex_outline(base,eps=3.0):
    """replace the rough outer boundary by the ideal convex polygon (hexagonal tracks)"""
    import cv2
    pts=np.argwhere(base)[:,::-1].astype(np.int32)
    hull=cv2.convexHull(pts); poly=cv2.approxPolyDP(hull,eps,True)
    ol=np.zeros((H,W),np.uint8); cv2.polylines(ol,[poly],True,1,1)
    near=ndi.binary_dilation(ol.astype(bool),iterations=4)
    keep=base&~near
    # drop fragments of the old outline that are now detached stubs
    lab,n=ndi.label(keep,structure=np.ones((3,3)))
    for i in range(1,n+1):
        if (lab==i).sum()<10: keep[lab==i]=False
    return keep|ol.astype(bool)


def skel_prune(base,N=0):
    """thin every fence to a 1-px line (no blocks), then remove short spurs/stubs but keep true line ends"""
    from skimage.morphology import skeletonize
    sk=skeletonize(base)
    k=np.ones((3,3),int); k[1,1]=0
    def ends(m): return m&(ndi.convolve(m.astype(int),k,mode="constant")<=1)
    if N==0: return sk
    R=sk.copy()
    for _ in range(N): R&=~ends(R)
    E=ends(R)
    for _ in range(N):
        g=ndi.binary_dilation(E,structure=np.ones((3,3)))&sk&~R
        R|=g; E=g
    return R
